/* The virtual picture processor (ppu.h). Each line is composed back to front into two buffers, the top pixel and the
 * one under it, each with its layer, so a blend sees both (as on the GBA); the windows decide per pixel which layers
 * and effects show. */
#include "ppu.h"

#include <string.h>

ppu_state PPU;

enum { ID_OBJ = 4, ID_BACK = 5, ID_BLEND = 0x80 }; /* layer ids 0..3 are the backgrounds; ID_BLEND marks OBJ_BLEND */

static struct {
    uint16_t top[PPU_W], under[PPU_W];
    uint8_t top_id[PPU_W], under_id[PPU_W];
    uint8_t show[PPU_W];   /* with windows: the layer bits and PPU_FX that show at x */
    uint8_t objwin[PPU_W]; /* the object window's shape on this line */
    bool windowed, track;  /* track: keep the pixel under the top one (an alpha blend needs it) */
    uint8_t order[4][PPU_OBJS], count[4]; /* the frame's visible sprites by priority, back to front */
    bool any_objwin;
} L;

void ppu_reset(void) {
    memset(&PPU, 0, sizeof PPU);
    PPU.mosaic.bg_w = PPU.mosaic.bg_h = PPU.mosaic.obj_w = PPU.mosaic.obj_h = 1;
    for (int i = 0; i < PPU_OBJS; i++) PPU.obj[i].affine = -1;
    for (int i = 0; i < PPU_AFFINES; i++) PPU.affine[i] = (ppu_affine){256, 0, 0, 256};
}

static inline int wrapi(int v, int m) { /* v mod m, never negative */
    v %= m;
    return v < 0 ? v + m : v;
}

static inline void put(int x, uint16_t c, uint8_t id) {
    if (L.windowed && !(L.show[x] & (1 << (id & 7)))) return;
    if (L.track) L.under[x] = L.top[x], L.under_id[x] = L.top_id[x];
    L.top[x] = c, L.top_id[x] = id;
}

/* ------------------------------------------------------------------ backgrounds */

static void bg_tiles(const ppu_bg *b, int n, int y) {
    int sx = b->scroll_x, sy = b->scroll_y, mw = b->mosaic ? PPU.mosaic.bg_w : 1, mh = b->mosaic ? PPU.mosaic.bg_h : 1;
    if (PPU.line.scroll[n]) sx = PPU.line.scroll[n][y].x, sy = PPU.line.scroll[n][y].y;
    int W = b->map_w * 8, H = b->map_h * 8, py = y - y % (mh > 1 ? mh : 1) + sy;
    if (!b->tiles || !b->map || W <= 0 || H <= 0) return;
    if (b->wrap) py = wrapi(py, H);
    else if (py < 0 || py >= H) return;
    const uint16_t *row = b->map + (py >> 3) * b->map_w;
    int fy = py & 7;
    if (mw > 1) { /* mosaic: every pixel samples the left edge of its block */
        for (int x = 0; x < PPU_W; x++) {
            int px = x - x % mw + sx;
            if (b->wrap) px = wrapi(px, W);
            else if (px < 0 || px >= W) continue;
            uint16_t e = row[px >> 3];
            int t = e & 0x3FF, u = px & 7;
            if (t >= b->ntiles) continue;
            uint8_t i = b->tiles[t * 64 + ((e & 0x800) ? 7 - fy : fy) * 8 + ((e & 0x400) ? 7 - u : u)];
            if (i) put(x, PPU.bg_pal[(i + (e >> 12) * 16) & 255], (uint8_t)n);
        }
        return;
    }
    for (int x = 0, px = sx; x < PPU_W;) { /* a tile's run at a time */
        int mx = px;
        if (b->wrap) mx = wrapi(px, W);
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
            const uint8_t *tp = b->tiles + t * 64 + ((e & 0x800) ? 7 - fy : fy) * 8;
            int bank = (e >> 12) * 16;
            if (e & 0x400)
                for (int k = 0; k < run; k++) {
                    uint8_t i = tp[7 - fx - k];
                    if (i) put(x + k, PPU.bg_pal[(i + bank) & 255], (uint8_t)n);
                }
            else
                for (int k = 0; k < run; k++) {
                    uint8_t i = tp[fx + k];
                    if (i) put(x + k, PPU.bg_pal[(i + bank) & 255], (uint8_t)n);
                }
        }
        x += run, px += run;
    }
}

static void bg_affine(const ppu_bg *b, int n, int y) {
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
    bool pow2 = !(W & (W - 1)) && !(H & (H - 1));
    for (int x = 0; x < PPU_W; x++) {
        int xx = mw > 1 ? x - x % mw : x;
        int u = (ax + pa * xx) >> 8, v = (ay + pc * xx) >> 8; /* arithmetic shift: floor */
        if (b->wrap) {
            if (pow2) u &= W - 1, v &= H - 1;
            else u = wrapi(u, W), v = wrapi(v, H);
        } else if ((unsigned)u >= (unsigned)W || (unsigned)v >= (unsigned)H) continue;
        int t = b->map[(v >> 3) * b->map_w + (u >> 3)] & 0xFF;
        if (t >= b->ntiles) continue;
        uint8_t i = b->tiles[t * 64 + (v & 7) * 8 + (u & 7)];
        if (i) put(x, PPU.bg_pal[i], (uint8_t)n);
    }
}

static void bg_bitmap(const ppu_bg *b, int n, int y) {
    int sx = b->scroll_x, sy = b->scroll_y, mw = b->mosaic ? PPU.mosaic.bg_w : 1, mh = b->mosaic ? PPU.mosaic.bg_h : 1;
    if (PPU.line.scroll[n]) sx = PPU.line.scroll[n][y].x, sy = PPU.line.scroll[n][y].y;
    int W = b->bitmap_w, H = b->bitmap_h, v = y - y % (mh > 1 ? mh : 1) + sy, stride = (W + 7) / 8;
    if (!b->bitmap || W <= 0 || H <= 0) return;
    if (b->wrap) v = wrapi(v, H);
    else if (v < 0 || v >= H) return;
    const uint16_t *src = b->bitmap + v * W;
    const uint8_t *m = b->bitmap_mask ? b->bitmap_mask + v * stride : NULL;
    for (int x = 0; x < PPU_W; x++) {
        int u = (mw > 1 ? x - x % mw : x) + sx;
        if (b->wrap) u = wrapi(u, W);
        else if (u < 0 || u >= W) continue;
        if (m && !(m[u >> 3] & (0x80 >> (u & 7)))) continue;
        put(x, src[u], (uint8_t)n);
    }
}

/* ------------------------------------------------------------------ sprites */

/* The box a sprite covers on screen: its own, or twice as big around the same centre with dbl. */
static void obj_box(const ppu_obj *o, int *x0, int *y0, int *w, int *h) {
    *w = o->w, *h = o->h, *x0 = o->x, *y0 = o->y;
    if (o->affine >= 0 && o->dbl) *x0 -= o->w / 2, *y0 -= o->h / 2, *w *= 2, *h *= 2;
}

/* The sprite's source pixel for screen (sx, sy), as an RGB565 colour; false where it is transparent or outside. */
static bool obj_pixel(const ppu_obj *o, int sx, int sy, uint16_t *c) {
    int u, v;
    if (o->affine >= 0) { /* from the pixel's centre, in half pixels, so an even-sized sprite turns about its middle */
        const ppu_affine *a = &PPU.affine[o->affine & (PPU_AFFINES - 1)];
        int dx = 2 * (sx - o->x) + 1 - o->w, dy = 2 * (sy - o->y) + 1 - o->h;
        u = ((a->pa * dx + a->pb * dy) >> 9) + o->w / 2;
        v = ((a->pc * dx + a->pd * dy) >> 9) + o->h / 2;
        if ((unsigned)u >= o->w || (unsigned)v >= o->h) return false;
    } else {
        u = sx - o->x, v = sy - o->y;
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

static void obj_line(const ppu_obj *o, int y, bool window_pass) {
    int bx, by, bw, bh;
    obj_box(o, &bx, &by, &bw, &bh);
    if (y < by || y >= by + bh) return;
    int mw = o->mosaic ? PPU.mosaic.obj_w : 1, mh = o->mosaic ? PPU.mosaic.obj_h : 1;
    int sy = mh > 1 ? y - y % mh : y;
    int xa = bx < 0 ? 0 : bx, xb = bx + bw > PPU_W ? PPU_W : bx + bw;
    uint8_t id = (uint8_t)(ID_OBJ | (o->mode == OBJ_BLEND ? ID_BLEND : 0));
    for (int x = xa; x < xb; x++) {
        uint16_t c;
        if (!obj_pixel(o, mw > 1 ? x - x % mw : x, sy, &c)) continue;
        if (window_pass) L.objwin[x] = 1;
        else put(x, c, id);
    }
}

/* ------------------------------------------------------------------ the frame */

static inline uint16_t blend(uint16_t a, uint16_t b, int ea, int eb) {
    int r = (((a >> 11) * ea + (b >> 11) * eb) >> 4), g = ((((a >> 5) & 63) * ea + ((b >> 5) & 63) * eb) >> 4),
        bl = (((a & 31) * ea + (b & 31) * eb) >> 4);
    return (uint16_t)((r > 31 ? 31 : r) << 11 | (g > 63 ? 63 : g) << 5 | (bl > 31 ? 31 : bl));
}

static inline uint16_t fade(uint16_t a, int ey, bool up) {
    int r = a >> 11, g = (a >> 5) & 63, b = a & 31;
    if (up) r += (31 - r) * ey >> 4, g += (63 - g) * ey >> 4, b += (31 - b) * ey >> 4;
    else r -= r * ey >> 4, g -= g * ey >> 4, b -= b * ey >> 4;
    return (uint16_t)(r << 11 | g << 5 | b);
}

static void prepare(void) {
    memset(L.count, 0, sizeof L.count);
    L.any_objwin = false;
    bool blend_obj = false;
    for (int i = PPU_OBJS - 1; i >= 0; i--) { /* back to front: sprite 127 under sprite 0 */
        const ppu_obj *o = &PPU.obj[i];
        if (!o->on || !o->w || !o->h || (!o->idx && !o->rgb)) continue;
        if (o->mode == OBJ_WINDOW) {
            L.any_objwin = true;
            continue;
        }
        blend_obj |= o->mode == OBJ_BLEND;
        int p = o->prio & 3;
        L.order[p][L.count[p]++] = (uint8_t)i;
    }
    L.track = PPU.fx.mode == FX_ALPHA || blend_obj;
}

static void line(int y, uint16_t *out) {
    uint16_t back = PPU.line.backdrop ? PPU.line.backdrop[y] : PPU.bg_pal[0];
    for (int x = 0; x < PPU_W; x++) L.top[x] = L.under[x] = back, L.top_id[x] = L.under_id[x] = ID_BACK;

    L.windowed = PPU.win.on[0] || PPU.win.on[1] || (PPU.win.obj_on && L.any_objwin);
    if (L.windowed) { /* outside, then the object window, window 1 and window 0 on top */
        memset(L.show, PPU.win.out, PPU_W);
        if (PPU.win.obj_on && L.any_objwin) {
            memset(L.objwin, 0, PPU_W);
            for (int i = PPU_OBJS - 1; i >= 0; i--)
                if (PPU.obj[i].on && PPU.obj[i].mode == OBJ_WINDOW) obj_line(&PPU.obj[i], y, true);
            for (int x = 0; x < PPU_W; x++)
                if (L.objwin[x]) L.show[x] = PPU.win.obj_in;
        }
        for (int k = 1; k >= 0; k--) {
            if (!PPU.win.on[k]) continue;
            int x1 = PPU.win.rect[k].x1, x2 = PPU.win.rect[k].x2;
            if (PPU.line.win[k]) x1 = PPU.line.win[k][y].x1, x2 = PPU.line.win[k][y].x2;
            else if (y < PPU.win.rect[k].y1 || y >= PPU.win.rect[k].y2) continue;
            if (x1 < 0) x1 = 0;
            if (x2 > PPU_W) x2 = PPU_W;
            if (x1 < x2) memset(L.show + x1, PPU.win.in[k], (size_t)(x2 - x1));
        }
    }

    for (int p = 3; p >= 0; p--) {
        for (int n = PPU_BGS - 1; n >= 0; n--) {
            const ppu_bg *b = &PPU.bg[n];
            if ((b->prio & 3) != p) continue;
            if (b->mode == BG_TILES) bg_tiles(b, n, y);
            else if (b->mode == BG_AFFINE) bg_affine(b, n, y);
            else if (b->mode == BG_BITMAP) bg_bitmap(b, n, y);
        }
        for (int k = 0; k < L.count[p]; k++) obj_line(&PPU.obj[L.order[p][k]], y, false);
    }

    int ea = PPU.fx.eva, eb = PPU.fx.evb, ey = PPU.fx.evy;
    if (PPU.line.fx_ev) ea = ey = PPU.line.fx_ev[y], eb = 16 - ea;
    for (int x = 0; x < PPU_W; x++) {
        uint16_t c = L.top[x];
        if (L.windowed && !(L.show[x] & PPU_FX)) {
            out[x] = c;
            continue;
        }
        uint8_t t = L.top_id[x], tb = (uint8_t)(1 << (t & 7)), ub = (uint8_t)(1 << (L.under_id[x] & 7));
        if ((t & ID_BLEND) && (PPU.fx.second & ub)) c = blend(c, L.under[x], ea, eb);
        else if (PPU.fx.first & tb) {
            if (PPU.fx.mode == FX_ALPHA && (PPU.fx.second & ub)) c = blend(c, L.under[x], ea, eb);
            else if (PPU.fx.mode == FX_LIGHTEN) c = fade(c, ey, true);
            else if (PPU.fx.mode == FX_DARKEN) c = fade(c, ey, false);
        }
        out[x] = c;
    }
}

void ppu_render(uint16_t *out) {
    prepare();
    for (int y = 0; y < PPU_H; y++) line(y, out + y * PPU_W);
}
