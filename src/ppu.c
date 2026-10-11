/* The virtual picture processor (ppu.h). Each line is composed back to front into two buffers, the top pixel and the
 * one under it, each a colour with its layer, so a blend sees both (as on the GBA); the windows decide per pixel which
 * layers and effects show. Two cores share a frame, even lines and odd lines (hal_parallel), each with its own
 * buffers.
 *
 * Speed matters here more than anywhere: on the console every frame is 38,400 pixels through up to four layers. The
 * layer loops come in four copies, with and without windows and the pixel under (always_inline on constant flags),
 * so the inner loops have no branches they do not need; tile rows known empty are skipped and rows known opaque
 * copied without testing (ppu_bg.rows). */
#include "ppu.h"

#include <string.h>

#include "hal.h"

#if defined(__GNUC__) && !defined(__clang__)
/* GCC turns short copies like "the top pixels go under" into memmove calls: on the console that is a call into ROM
 * for every 8 pixels, and it cost more than everything else in a blended frame. */
#pragma GCC optimize("no-tree-loop-distribute-patterns")
#endif

ppu_state PPU;

enum { ID_OBJ = 4, ID_BACK = 5, ID_BLEND = 0x80 }; /* layer ids 0..3 are the backgrounds; ID_BLEND marks OBJ_BLEND */
#define PX(c, id) ((uint32_t)(c) | (uint32_t)(id) << 16) /* a pixel in the line buffers: colour, layer id above */

/* A fade by ey/16 as three tables, a colour's channels looked up in place: (c >> 11, c >> 5 & 63, c & 31). */
typedef struct { int ey, up; uint16_t r[32], g[64], b[32]; } fade_lut;

typedef struct {
    uint32_t top[PPU_W], under[PPU_W]; /* PX(colour, id) */
    uint8_t show[PPU_W];   /* with windows: the layer bits and PPU_FX that show at x */
    uint8_t objwin[PPU_W]; /* the object window's shape on this line */
    bool win;              /* this line has windows */
    fade_lut fade;         /* the last fade's tables */
    uint8_t drew;          /* the layer bits that may have pixels on this line, PPU_BACK always */
    bool drew_blend;       /* an OBJ_BLEND sprite crossed it */
} lines;

static lines LB[2] = {{.fade.ey = -1}, {.fade.ey = -1}}; /* one per core */

static struct {
    uint8_t order[4][PPU_OBJS], count[4]; /* the frame's visible sprites by priority, back to front */
    bool any_objwin;
    bool track; /* keep the pixel under the top one (an alpha blend needs it) */
} F;

#define ALWAYS static inline __attribute__((always_inline))

void ppu_reset(void) {
    memset(&PPU, 0, sizeof PPU);
    PPU.mosaic.bg_w = PPU.mosaic.bg_h = PPU.mosaic.obj_w = PPU.mosaic.obj_h = 1;
    for (int i = 0; i < PPU_OBJS; i++) PPU.obj[i].affine = -1;
    for (int i = 0; i < PPU_AFFINES; i++) PPU.affine[i] = (ppu_affine){256, 0, 0, 256};
}

void ppu_tile_rows(const uint8_t *tiles, int ntiles, uint16_t *rows) {
    for (int t = 0; t < ntiles; t++) {
        uint16_t r = 0;
        for (int y = 0; y < 8; y++) {
            int set = 0;
            for (int x = 0; x < 8; x++) set += tiles[t * 64 + y * 8 + x] != 0;
            if (!set) r |= (uint16_t)(1 << y);
            if (set == 8) r |= (uint16_t)(0x100 << y);
        }
        rows[t] = r;
    }
}

/* The x in [*x0, *x1] where lo <= a + p * x <= hi, narrowed from what it was (an affine line inside its map). */
static void clip_span(int64_t a, int64_t p, int64_t lo, int64_t hi, int *x0, int *x1) {
    int64_t from, to;
    if (p == 0) {
        if (a < lo || a > hi) *x1 = *x0 - 1;
        return;
    }
    if (p < 0) a = -a, p = -p, from = lo, lo = -hi, hi = -from; /* the same with p > 0: -hi <= -a + (-p) x <= -lo */
    from = lo - a, to = hi - a; /* p x in [from, to] */
    from = from >= 0 ? (from + p - 1) / p : -(-from / p);   /* ceil */
    to = to >= 0 ? to / p : -((-to + p - 1) / p);           /* floor */
    if (from > *x0) *x0 = from > PPU_W ? PPU_W : (int)from;
    if (to < *x1) *x1 = to < -1 ? -1 : (int)to;
}

static inline int wrapi(int v, int m) { /* v mod m, never negative */
    v %= m;
    return v < 0 ? v + m : v;
}

/* A pixel of a layer onto the line: hidden by the windows, or over the top one (which goes under when tracking). */
ALWAYS void put(lines *L, int x, uint32_t px, int bit, bool win, bool track) {
    if (win && !(L->show[x] & bit)) return;
    if (track) L->under[x] = L->top[x];
    L->top[x] = px;
}

/* ------------------------------------------------------------------ backgrounds */

/* One tile's pixels fx..fx+run-1 of row tp (8 indices) onto x.. ; rev reads the row right to left (hflip). */
ALWAYS void tile_run(lines *L, int x, const uint8_t *tp, int fx, int run, bool rev, bool opaque, int bank, uint32_t id,
                     int bit, bool win, bool track) {
    const uint16_t *pal = PPU.bg_pal;
    if (opaque && !win) { /* every pixel shows: no tests */
        uint32_t *top = L->top + x, *under = L->under + x;
        for (int k = 0; k < run; k++) {
            uint32_t px = pal[(tp[rev ? 7 - fx - k : fx + k] + bank) & 255] | id;
            if (track) under[k] = top[k];
            top[k] = px;
        }
        return;
    }
    for (int k = 0; k < run; k++) {
        uint8_t i = tp[rev ? 7 - fx - k : fx + k];
        if (i) put(L, x + k, pal[(i + bank) & 255] | id, bit, win, track);
    }
}

ALWAYS void bg_tiles_x(lines *L, const ppu_bg *b, int n, int y, bool win, bool track) {
    int sx = b->scroll_x, sy = b->scroll_y, mw = b->mosaic ? PPU.mosaic.bg_w : 1, mh = b->mosaic ? PPU.mosaic.bg_h : 1;
    if (PPU.line.scroll[n]) sx = PPU.line.scroll[n][y].x, sy = PPU.line.scroll[n][y].y;
    int W = b->map_w * 8, H = b->map_h * 8, py = y - y % (mh > 1 ? mh : 1) + sy;
    if (!b->tiles || !b->map || W <= 0 || H <= 0) return;
    if (b->wrap) py = wrapi(py, H);
    else if (py < 0 || py >= H) return;
    const uint16_t *row = b->map + (py >> 3) * b->map_w;
    int fy = py & 7, bit = 1 << n;
    uint32_t id = (uint32_t)n << 16;
    if (mw > 1) { /* mosaic: a block of mw pixels shows its left edge */
        for (int x0 = 0; x0 < PPU_W; x0 += mw) {
            int px = x0 + sx;
            if (b->wrap) px = wrapi(px, W);
            else if (px < 0 || px >= W) continue;
            uint16_t e = row[px >> 3];
            int t = e & 0x3FF, u = px & 7;
            if (t >= b->ntiles) continue;
            uint8_t i = b->tiles[t * 64 + ((e & 0x800) ? 7 - fy : fy) * 8 + ((e & 0x400) ? 7 - u : u)];
            if (!i) continue;
            uint32_t c = PPU.bg_pal[(i + (e >> 12) * 16) & 255] | id;
            for (int x = x0, x1 = x0 + mw < PPU_W ? x0 + mw : PPU_W; x < x1; x++) put(L, x, c, bit, win, track);
        }
        L->drew |= (uint8_t)bit;
        return;
    }
    bool pow2 = !(W & (W - 1)), drew = false;
    for (int x = 0, px = sx; x < PPU_W;) { /* a tile's run at a time */
        int mx = px;
        if (b->wrap) mx = pow2 ? mx & (W - 1) : wrapi(px, W);
        else if (mx < 0) { /* left of the map: skip to it */
            int skip = -mx < PPU_W - x ? -mx : PPU_W - x;
            x += skip, px += skip;
            continue;
        } else if (mx >= W) break;
        int fx = mx & 7, run = 8 - fx;
        if (run > PPU_W - x) run = PPU_W - x;
        uint16_t e = row[mx >> 3];
        int t = e & 0x3FF;
        if (t < b->ntiles) {
            int ty = (e & 0x800) ? 7 - fy : fy;
            unsigned info = b->rows ? b->rows[t] >> ty : 0; /* bit 0: the row is empty; bit 8: opaque */
            if (!(info & 1)) {
                drew = true;
                const uint8_t *tp = b->tiles + t * 64 + ty * 8;
                int bank = (e >> 12) * 16;
                bool rev = e & 0x400;
                if (info & 0x100) {
                    if (rev) tile_run(L, x, tp, fx, run, true, true, bank, id, bit, win, track);
                    else tile_run(L, x, tp, fx, run, false, true, bank, id, bit, win, track);
                } else if (rev) tile_run(L, x, tp, fx, run, true, false, bank, id, bit, win, track);
                else tile_run(L, x, tp, fx, run, false, false, bank, id, bit, win, track);
            }
        }
        x += run, px += run;
    }
    if (drew) L->drew |= (uint8_t)bit;
}

ALWAYS void bg_affine_x(lines *L, const ppu_bg *b, int n, int y, bool win, bool track) {
    int W = b->map_w * 8, H = b->map_h * 8, mw = b->mosaic ? PPU.mosaic.bg_w : 1, mh = b->mosaic ? PPU.mosaic.bg_h : 1;
    if (!b->tiles || !b->map || W <= 0 || H <= 0) return;
    int32_t ax, ay, pa, pc;
    if (PPU.line.affine[n]) {
        const ppu_line_affine *l = &PPU.line.affine[n][y];
        if (l->x == PPU_LINE_OFF) return;
        ax = l->x, ay = l->y, pa = l->pa, pc = l->pc;
    } else {
        int yy = y - y % (mh > 1 ? mh : 1);
        ax = b->x0 + b->pb * yy, ay = b->y0 + b->pd * yy, pa = b->pa, pc = b->pc;
    }
    int bit = 1 << n, nt = b->ntiles;
    uint32_t id = (uint32_t)n << 16;
    const uint8_t *tiles = b->tiles;
    const uint16_t *map = b->map, *pal = PPU.bg_pal;
    bool pow2 = !(W & (W - 1)) && !(H & (H - 1));
    if (mw == 1 && pow2) { /* the common case (a Mode 7 floor, a turned map): stepping, shifts, no multiplies */
        int shift = __builtin_ctz((unsigned)b->map_w), x0 = 0, x1 = PPU_W - 1;
        if (!b->wrap) { /* only the span inside the map: (ax + pa x) >> 8 in [0, W), the same for y */
            clip_span(ax, pa, 0, (int64_t)W * 256 - 1, &x0, &x1);
            clip_span(ay, pc, 0, (int64_t)H * 256 - 1, &x0, &x1);
            if (x0 > x1) return;
        }
        L->drew |= (uint8_t)bit;
        int32_t px = ax + pa * x0, py = ay + pc * x0;
        for (int x = x0; x <= x1; x++, px += pa, py += pc) {
            int u = (px >> 8) & (W - 1), v = (py >> 8) & (H - 1); /* arithmetic shift: floor; the mask wraps */
            int t = map[((v >> 3) << shift) + (u >> 3)] & 0xFF;
            if (t >= nt) continue;
            uint8_t i = tiles[t * 64 + (v & 7) * 8 + (u & 7)];
            if (i) put(L, x, pal[i] | id, bit, win, track);
        }
        return;
    }
    L->drew |= (uint8_t)bit;
    for (int x0 = 0; x0 < PPU_W; x0 += mw) { /* a block of mw pixels (mosaic) shows its left edge */
        int u = (ax + pa * x0) >> 8, v = (ay + pc * x0) >> 8;
        if (b->wrap) {
            if (pow2) u &= W - 1, v &= H - 1;
            else u = wrapi(u, W), v = wrapi(v, H);
        } else if ((unsigned)u >= (unsigned)W || (unsigned)v >= (unsigned)H) continue;
        int t = map[(v >> 3) * b->map_w + (u >> 3)] & 0xFF;
        if (t >= nt) continue;
        uint8_t i = tiles[t * 64 + (v & 7) * 8 + (u & 7)];
        if (!i) continue;
        for (int x = x0, x1 = x0 + mw < PPU_W ? x0 + mw : PPU_W; x < x1; x++) put(L, x, pal[i] | id, bit, win, track);
    }
}

ALWAYS void bg_bitmap_x(lines *L, const ppu_bg *b, int n, int y, bool win, bool track) {
    int sx = b->scroll_x, sy = b->scroll_y, mw = b->mosaic ? PPU.mosaic.bg_w : 1, mh = b->mosaic ? PPU.mosaic.bg_h : 1;
    if (PPU.line.scroll[n]) sx = PPU.line.scroll[n][y].x, sy = PPU.line.scroll[n][y].y;
    int W = b->bitmap_w, H = b->bitmap_h, v = y - y % (mh > 1 ? mh : 1) + sy, stride = (W + 7) / 8, bit = 1 << n;
    uint32_t id = (uint32_t)n << 16;
    if (!b->bitmap || W <= 0 || H <= 0) return;
    if (b->wrap) v = wrapi(v, H);
    else if (v < 0 || v >= H) return;
    const uint16_t *src = b->bitmap + v * W;
    const uint8_t *m = b->bitmap_mask ? b->bitmap_mask + v * stride : NULL;
    L->drew |= (uint8_t)bit;
    for (int x0 = 0; x0 < PPU_W; x0 += mw) { /* a block of mw pixels (mosaic) shows its left edge */
        int u = x0 + sx;
        if (b->wrap) u = wrapi(u, W);
        else if (u < 0 || u >= W) continue;
        if (m && !(m[u >> 3] & (0x80 >> (u & 7)))) continue;
        for (int x = x0, x1 = x0 + mw < PPU_W ? x0 + mw : PPU_W; x < x1; x++) put(L, x, src[u] | id, bit, win, track);
    }
}

/* ------------------------------------------------------------------ sprites */

/* The box a sprite covers on screen: its own, or twice as big around the same centre with dbl. */
static void obj_box(const ppu_obj *o, int *x0, int *y0, int *w, int *h) {
    *w = o->w, *h = o->h, *x0 = o->x, *y0 = o->y;
    if (o->affine >= 0 && o->dbl) *x0 -= o->w / 2, *y0 -= o->h / 2, *w *= 2, *h *= 2;
}

/* The sprite's source pixel for screen (sx, sy), as an RGB565 colour; false where it is transparent or outside. */
static inline bool obj_pixel(const ppu_obj *o, int sx, int sy, uint16_t *c) {
    int u, v;
    if (o->affine >= 0) { /* from the pixel's centre, in half pixels, so an even-sized sprite turns about its middle */
        const ppu_affine *a = &PPU.affine[o->affine & (PPU_AFFINES - 1)];
        int dx = 2 * (sx - o->x) + 1 - o->w, dy = 2 * (sy - o->y) + 1 - o->h;
        u = ((a->pa * dx + a->pb * dy) >> 9) + o->w / 2;
        v = ((a->pc * dx + a->pd * dy) >> 9) + o->h / 2;
        if ((unsigned)u >= o->w || (unsigned)v >= o->h) return false;
    } else { /* mosaic can snap a pixel to a block edge outside the box */
        u = sx - o->x, v = sy - o->y;
        if ((unsigned)u >= o->w || (unsigned)v >= o->h) return false;
        if (o->hflip) u = o->w - 1 - u;
        if (o->vflip) v = o->h - 1 - v;
    }
    if (o->idx) {
        uint8_t i = o->idx[v * o->w + u];
        if (!i) return false;
        *c = PPU.obj_pal[(i + o->bank * 16) & 255];
        return true;
    }
    if (!o->rgb) return false;
    if (o->mask && !(o->mask[v * ((o->w + 7) / 8) + (u >> 3)] & (0x80 >> (u & 7)))) return false;
    *c = o->rgb[v * o->w + u];
    return true;
}

ALWAYS void obj_line_x(lines *L, const ppu_obj *o, int y, bool win, bool track) {
    int bx, by, bw, bh;
    obj_box(o, &bx, &by, &bw, &bh);
    if (y < by || y >= by + bh) return;
    int mw = o->mosaic ? PPU.mosaic.obj_w : 1, mh = o->mosaic ? PPU.mosaic.obj_h : 1;
    int xa = bx < 0 ? 0 : bx, xb = bx + bw > PPU_W ? PPU_W : bx + bw;
    uint32_t id = (uint32_t)(ID_OBJ | (o->mode == OBJ_BLEND ? ID_BLEND : 0)) << 16;
    L->drew |= PPU_OBJ;
    if (o->mode == OBJ_BLEND) L->drew_blend = true;
    if (o->affine < 0 && mw == 1 && mh == 1 && o->idx) { /* a plain indexed sprite: its source row, read straight */
        int v = y - o->y;
        if (o->vflip) v = o->h - 1 - v;
        const uint8_t *src = o->idx + v * o->w;
        const uint16_t *pal = PPU.obj_pal;
        int bank = o->bank * 16;
        if (o->hflip)
            for (int x = xa; x < xb; x++) {
                uint8_t i = src[o->w - 1 - (x - o->x)];
                if (i) put(L, x, pal[(i + bank) & 255] | id, PPU_OBJ, win, track);
            }
        else
            for (int x = xa; x < xb; x++) {
                uint8_t i = src[x - o->x];
                if (i) put(L, x, pal[(i + bank) & 255] | id, PPU_OBJ, win, track);
            }
        return;
    }
    int sy = mh > 1 ? y - y % mh : y;
    for (int x = xa; x < xb;) { /* a block of mw screen pixels (mosaic) shows its left edge */
        int x0 = x - x % mw, x1 = x0 + mw < xb ? x0 + mw : xb;
        uint16_t c;
        if (obj_pixel(o, x0, sy, &c))
            for (; x < x1; x++) put(L, x, c | id, PPU_OBJ, win, track);
        x = x1;
    }
}

static void obj_window_line(lines *L, const ppu_obj *o, int y) { /* an OBJ_WINDOW sprite's shape into objwin */
    int bx, by, bw, bh;
    obj_box(o, &bx, &by, &bw, &bh);
    if (y < by || y >= by + bh) return;
    int mw = o->mosaic ? PPU.mosaic.obj_w : 1, mh = o->mosaic ? PPU.mosaic.obj_h : 1;
    int sy = mh > 1 ? y - y % mh : y;
    int xa = bx < 0 ? 0 : bx, xb = bx + bw > PPU_W ? PPU_W : bx + bw;
    for (int x = xa; x < xb;) {
        int x0 = x - x % mw, x1 = x0 + mw < xb ? x0 + mw : xb;
        uint16_t c;
        if (obj_pixel(o, x0, sy, &c)) memset(L->objwin + x, 1, (size_t)(x1 - x));
        x = x1;
    }
}

/* The layers of one priority, in each of the four ways a line can be drawn. */
ALWAYS void layers_x(lines *L, int p, int y, bool win, bool track) {
    for (int n = PPU_BGS - 1; n >= 0; n--) {
        const ppu_bg *b = &PPU.bg[n];
        if ((b->prio & 3) != p) continue;
        if (b->mode == BG_TILES) bg_tiles_x(L, b, n, y, win, track);
        else if (b->mode == BG_AFFINE) bg_affine_x(L, b, n, y, win, track);
        else if (b->mode == BG_BITMAP) bg_bitmap_x(L, b, n, y, win, track);
    }
    for (int k = 0; k < F.count[p]; k++) obj_line_x(L, &PPU.obj[F.order[p][k]], y, win, track);
}

static void layers_plain(lines *L, int p, int y) { layers_x(L, p, y, false, false); }
static void layers_track(lines *L, int p, int y) { layers_x(L, p, y, false, true); }
static void layers_win(lines *L, int p, int y) { layers_x(L, p, y, true, false); }
static void layers_win_track(lines *L, int p, int y) { layers_x(L, p, y, true, true); }

/* ------------------------------------------------------------------ the frame */

static inline uint16_t blend(uint16_t a, uint16_t b, int ea, int eb) {
    int r = (((a >> 11) * ea + (b >> 11) * eb) >> 4), g = ((((a >> 5) & 63) * ea + ((b >> 5) & 63) * eb) >> 4),
        bl = (((a & 31) * ea + (b & 31) * eb) >> 4);
    return (uint16_t)((r > 31 ? 31 : r) << 11 | (g > 63 ? 63 : g) << 5 | (bl > 31 ? 31 : bl));
}

static void fade_tables(fade_lut *f, int ey, bool up) {
    if (f->ey == ey && f->up == up) return;
    f->ey = ey, f->up = up;
    for (int v = 0; v < 64; v++) {
        int v5 = v & 31, a5 = up ? v5 + ((31 - v5) * ey >> 4) : v5 - (v5 * ey >> 4);
        int a6 = up ? v + ((63 - v) * ey >> 4) : v - (v * ey >> 4);
        if (v < 32) f->r[v] = (uint16_t)(a5 << 11), f->b[v] = (uint16_t)a5;
        f->g[v] = (uint16_t)(a6 << 5);
    }
}

static inline uint16_t fade(const fade_lut *f, uint16_t c) { return f->r[c >> 11] | f->g[(c >> 5) & 63] | f->b[c & 31]; }

static void prepare(void) {
    memset(F.count, 0, sizeof F.count);
    F.any_objwin = false;
    bool blend_obj = false;
    for (int i = PPU_OBJS - 1; i >= 0; i--) { /* back to front: sprite 127 under sprite 0 */
        const ppu_obj *o = &PPU.obj[i];
        if (!o->on || !o->w || !o->h || (!o->idx && !o->rgb)) continue;
        if (o->mode == OBJ_WINDOW) {
            F.any_objwin = true;
            continue;
        }
        blend_obj |= o->mode == OBJ_BLEND;
        int p = o->prio & 3;
        F.order[p][F.count[p]++] = (uint8_t)i;
    }
    F.track = PPU.fx.mode == FX_ALPHA || blend_obj;
}

static void windows(lines *L, int y) { /* what shows where: outside, then the object window, window 1, window 0 */
    memset(L->show, PPU.win.out, PPU_W);
    if (PPU.win.obj_on && F.any_objwin) {
        memset(L->objwin, 0, PPU_W);
        for (int i = PPU_OBJS - 1; i >= 0; i--)
            if (PPU.obj[i].on && PPU.obj[i].mode == OBJ_WINDOW) obj_window_line(L, &PPU.obj[i], y);
        for (int x = 0; x < PPU_W; x++)
            if (L->objwin[x]) L->show[x] = PPU.win.obj_in;
    }
    for (int k = 1; k >= 0; k--) {
        if (!PPU.win.on[k]) continue;
        int x1 = PPU.win.rect[k].x1, x2 = PPU.win.rect[k].x2;
        if (PPU.line.win[k]) x1 = PPU.line.win[k][y].x1, x2 = PPU.line.win[k][y].x2;
        else if (y < PPU.win.rect[k].y1 || y >= PPU.win.rect[k].y2) continue;
        if (x1 < 0) x1 = 0;
        if (x2 > PPU_W) x2 = PPU_W;
        if (x1 < x2) memset(L->show + x1, PPU.win.in[k], (size_t)(x2 - x1));
    }
}

static void line(lines *L, int y, uint16_t *out) {
    uint32_t back = PX(PPU.line.backdrop ? PPU.line.backdrop[y] : PPU.bg_pal[0], ID_BACK);
    for (int x = 0; x < PPU_W; x++) L->top[x] = back;
    if (F.track)
        for (int x = 0; x < PPU_W; x++) L->under[x] = back;

    L->drew = PPU_BACK, L->drew_blend = false;
    L->win = PPU.win.on[0] || PPU.win.on[1] || (PPU.win.obj_on && F.any_objwin);
    if (L->win) windows(L, y);
    void (*layers)(lines *, int, int) =
        L->win ? (F.track ? layers_win_track : layers_win) : (F.track ? layers_track : layers_plain);
    for (int p = 3; p >= 0; p--) layers(L, p, y);

    /* No effect can touch this line (nothing of the first target on it, no blending sprite): the top pixels are it */
    if (!L->drew_blend && (PPU.fx.mode == FX_NONE || !(L->drew & PPU.fx.first))) {
        for (int x = 0; x < PPU_W; x++) out[x] = (uint16_t)L->top[x];
        return;
    }
    int ea = PPU.fx.eva, eb = PPU.fx.evb, ey = PPU.fx.evy;
    if (PPU.line.fx_ev) ea = ey = PPU.line.fx_ev[y], eb = 16 - ea;
    const int mode = PPU.fx.mode, first = PPU.fx.first, second = PPU.fx.second; /* out may alias PPU: read once */
    const bool win = L->win;
    if (mode == FX_LIGHTEN || mode == FX_DARKEN) fade_tables(&L->fade, ey, mode == FX_LIGHTEN);
    for (int x = 0; x < PPU_W; x++) {
        uint32_t top = L->top[x];
        uint16_t c = (uint16_t)top;
        if (win && !(L->show[x] & PPU_FX)) {
            out[x] = c;
            continue;
        }
        int t = (int)(top >> 16), tb = 1 << (t & 7), ub = 1 << ((L->under[x] >> 16) & 7);
        if ((t & ID_BLEND) && (second & ub)) c = blend(c, (uint16_t)L->under[x], ea, eb);
        else if (first & tb) {
            if (mode == FX_ALPHA) {
                if (second & ub) c = blend(c, (uint16_t)L->under[x], ea, eb);
            } else if (mode == FX_LIGHTEN || mode == FX_DARKEN) c = fade(&L->fade, c);
        }
        out[x] = c;
    }
}

static void render_part(int part, void *frame) { /* every other line, from line `part` */
    uint16_t *out = frame;
    for (int y = part; y < PPU_H; y += 2) line(&LB[part], y, out + y * PPU_W);
}

void ppu_render(uint16_t *out) {
    prepare();
    hal_parallel(render_part, out);
}
