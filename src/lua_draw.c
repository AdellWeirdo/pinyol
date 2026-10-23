/* What a game draws at the screen's full resolution (480x320), over the world: text in its fonts and styles, shapes,
 * lines, circles, polygons, pictures, frames. The screen is drawn strip by strip on the console, so a frame's calls
 * are kept in a list and replayed for each strip (draw_overlay). The same calls can draw on a canvas instead
 * (target): a picture the game makes and changes while it runs, drawn on at once. */
#include <math.h>
#include <stdlib.h>
#include <string.h>

#include "gfx_px.h"
#include "lua_api.h"
#include "mesh.h"

#define OV_MAX 2048                /* overlay commands per frame: particles, stars, a split screen drawn twice */
#define OV_TEXT 12288              /* overlay text bytes per frame */
#define OV_EXT 128                 /* styled texts and turned or scaled pictures per frame (each) */
#define MAX_FONTS 16               /* a game's own fonts, besides the four every game has */
#define OV_PTS 4096                /* polygon corners per frame, x and y each */
#define OV_CLIPS 32                /* clip rectangles per frame */
#define BAND 32                    /* screen columns a band: the console's strips (draw_overlay) */
#define MAX_DIRTY 16               /* canvases drawn on in one call before their masks are brought up to date */
#define CLEAR (-1)                 /* as a colour: see-through on a canvas (nothing on the screen) */

/* ------------------------------------------------------------------ the overlay: text and shapes at 480x320 */

enum { OV_TEXT_OP, OV_FILL, OV_SHADE, OV_PANEL, OV_PLATE, OV_BOX, OV_IMG, OV_NINE, OV_LINE, OV_CIRC, OV_POLY, OV_POINTS, OV_QUAD, OV_GRAD, OV_LIGHT, OV_WARP, OV_LINES, OV_MESH, OV_OPS };
static const char *const OP_NAME[OV_OPS] = {"text", "rect", "shade", "panel", "plate", "box", "img", "frame", "line", "circ", "poly", "points", "quad", "grad", "light", "warp", "linetint", "mesh"};

/* Where a frame goes (the meter, perf("ops")): each kind of command counted when it is recorded and timed as the strips draw it, in the
 * frame's own numbers (prof_last: the frame before the one being recorded). Timing each command costs, so only while asked for. */
static struct { uint32_t us[2][OV_OPS]; uint16_t n[OV_OPS]; int cmds, slots; } prof_cur, prof_last; /* us: a row for each part that draws */
static unsigned prof_want;

typedef struct {
    uint8_t op, font, scale, ext; /* ext: 1 + its entry in ov_style (text) or ov_xf (img); 0: none */
    uint8_t clip;                 /* 1 + its entry in ov_clip; 0: none */
    uint8_t flip;                 /* img at 1x mirrored left to right (gfx_blit_flip) */
    uint8_t band0, band1;         /* the screen's BAND-column bands it may draw on (band()): strips skip the others */
    int16_t x, y, w, h, frame;    /* line: x, y to w, h; circle: centre x, y, radius w, filled h; polygon: filled frame */
    uint16_t color, str, len;     /* text: its bytes in ov_text; polygon: its corners in ov_pts */
    const asset *a;
} ov_cmd;

static ov_cmd ov[OV_MAX];
static char ov_text[OV_TEXT];
static text_style ov_style[OV_EXT];
static struct { float sx, sy, deg; } ov_xf[OV_EXT];
static struct { /* img's pal, tint and how it is seen through: c->font is 1 + its entry */
    const asset *pal;
    int tint;
    uint8_t alpha; /* 255: opaque */
    uint8_t mode;  /* BLEND_*: how it meets what is under it (alpha: mixed; add, sub, quarter: its light moved by) */
} ov_look[OV_EXT];
static int nlook;
static struct { /* quad's corners and how it is drawn (grad's two colours in light[0], light[1], lights: across): c->ext is 1 + its entry */
    int16_t xy[8]; /* eighths of a pixel */
    uint8_t light[4][3];
    bool lights, dither, mesh;
    uint8_t mode, alpha, persp; /* BLEND_*, 255: opaque; quad's perspective cells (0: none, 1: as many as it needs) */
    const struct quad_mip *mip; /* quad: the smaller copy of its picture it is sampled from, or NULL */
} ov_quad[OV_EXT];
static int nquad;
#define MESH_SLOTS 48 /* models a game keeps (mesh_new): a character in a few baked poses takes a handful */
#define MESH_POOL 384 /* faces of every mesh() of a frame together */
static mesh_model *models[MESH_SLOTS];
static int nmodels;
static mesh_face mfaces[MESH_POOL]; /* a mesh's faces for the strips: c->str is the first, c->len how many */
static int nmf;
static int nstyle, nxf;
static struct { char name[32]; font f; } vfont[MAX_FONTS]; /* fonts/<name>.fnt, loaded when first used */
static int nvfont;
static int nov, ntext;
static int16_t ov_pts[OV_PTS];
static screen_rect ov_clip[OV_CLIPS];
static int npts, nclip;
static asset *target;               /* NULL: the screen; else a canvas, drawn on at once */
static uint32_t frame_no;           /* counts _draws: the picture cache keeps this frame's pictures */
static int cam_x, cam_y;            /* camera(): subtracted from what is drawn */
static bool clipping;               /* clip(): only inside clip_r */
static screen_rect clip_r;
static screen_rect view;            /* draw_set_view: the screen of two that is drawn on, kept for target() back on the screen */
static bool view_on;
typedef struct { asset *a; int x0, y0, x1, y1; } dirty_box;
static dirty_box dirty[MAX_DIRTY]; /* canvases drawn on: where, for their masks */
static int ndirty;

static ov_cmd *ov_add(int op) {
    if (nov == OV_MAX) return NULL;
    prof_cur.n[op]++;
    ov_cmd *c = &ov[nov++];
    memset(c, 0, sizeof *c);
    c->op = (uint8_t)op;
    c->band1 = 255; /* every band, until commit works out its own */
    return c;
}

static const font *font_named(int k) {
    switch (k) {
    case 0: return &G.font;
    case 1: return &G.bold;
    case 2: return &G.font_l;
    case 3: return &G.bold_l;
    default: return k - 4 < nvfont ? &vfont[k - 4].f : &G.font;
    }
}

/* A picture seen through (img's alpha) or adding its light (add), as a PlayStation or a Saturn drew them: what is
 * under it is kept, the picture drawn the usual way (any of them: plain, mirrored, scaled, turned, packed), and then
 * each pixel mixed with what was there. Where the picture has no pixel the two are the same, so nothing changes. */
static surface img_area(const surface *s, const ov_cmd *c) {
    int x = c->x, y = c->y, w = c->a->w * c->scale, h = c->a->h * c->scale;
    if (c->ext) {
        int ox, oy;
        gfx_blit_ex_bounds(c->a, ov_xf[c->ext - 1].sx, ov_xf[c->ext - 1].sy, ov_xf[c->ext - 1].deg, &ox, &oy, &w, &h);
        x += ox, y += oy;
    }
    return gfx_clip(s, x, y, w, h);
}

/* one each per thread: the console draws its strips on both cores at once, and a shared one was freed under the
 * other's feet (a heap assertion on the board) */
static _Thread_local uint16_t *kept_px;
static _Thread_local size_t kept_cap;

static const uint16_t *keep(const surface *r) { /* r's pixels, copied; NULL: none, or no memory (drawn opaque) */
    size_t n = (size_t)(r->w > 0 ? r->w : 0) * (size_t)(r->h > 0 ? r->h : 0);
    if (!n) return NULL;
    if (n > kept_cap) {
        uint16_t *p = realloc(kept_px, n * sizeof *p);
        if (!p) return NULL;
        kept_px = p, kept_cap = n;
    }
    for (int y = 0; y < r->h; y++)
        for (int x = 0; x < r->w; x++) kept_px[y * r->w + x] = r->px[x * r->xs + y * r->ys];
    return kept_px;
}

static inline uint16_t bswap(uint16_t v) { return (uint16_t)(v << 8 | v >> 8); }

static void see_through(const surface *r, const uint16_t *was, unsigned alpha, int mode) {
    unsigned a = alpha + (alpha >> 7); /* 0..256 */
    for (int y = 0; y < r->h; y++)
        for (int x = 0; x < r->w; x++) {
            uint16_t *p = &r->px[x * r->xs + y * r->ys];
            uint16_t d = was[y * r->w + x], n = *p;
            if (n == d) continue; /* not drawn on */
            if (r->swap) d = bswap(d), n = bswap(n);
            if (d == CANVAS_KEY) continue; /* nothing under it on a canvas: the picture as it is */
            uint16_t v;
            if (mode != BLEND_ALPHA) {
                v = blend_held(d, n, a, mode);
            } else {
                unsigned dr = d >> 11, dg = d >> 5 & 63, db = d & 31, nr = n >> 11, ng = n >> 5 & 63, nb = n & 31;
                v = (uint16_t)(((dr * (256 - a) + nr * a) >> 8) << 11 | ((dg * (256 - a) + ng * a) >> 8) << 5 |
                               ((db * (256 - a) + nb * a) >> 8));
            }
            if (v == CANVAS_KEY) v ^= 1; /* that colour is a canvas's see-through: one step from it */
            *p = r->swap ? bswap(v) : v;
        }
}

static void draw_one(surface *s, const ov_cmd *c) {
    switch (c->op) {
    case OV_TEXT_OP:
        if (c->ext) font_draw_styled(s, font_named(c->font), c->x, c->y, ov_text + c->str, c->len, -1, &ov_style[c->ext - 1]);
        else font_draw(s, font_named(c->font), c->x, c->y, ov_text + c->str, c->len, -1, c->color);
        break;
    case OV_FILL: gfx_fill(s, c->x, c->y, c->w, c->h, c->color); break;
    case OV_SHADE: gfx_shade(s, c->x, c->y, c->w, c->h); break;
    case OV_PANEL: gfx_panel(s, c->x, c->y, c->w, c->h); break;
    case OV_PLATE: gfx_plate(s, c->x, c->y, c->w, c->h, c->color); break;
    case OV_BOX: gfx_frame(s, c->x, c->y, c->w, c->h, c->color); break;
    case OV_NINE: gfx_nine(s, c->a, c->frame, c->x, c->y, c->w, c->h, c->scale); break;
    case OV_LINE: gfx_line(s, c->x, c->y, c->w, c->h, c->color); break;
    case OV_CIRC: gfx_circ(s, c->x, c->y, c->w, c->color, c->h != 0); break;
    case OV_POLY: gfx_poly(s, ov_pts + c->str, c->len, c->color, c->frame != 0); break;
    case OV_QUAD: {
        const typeof(ov_quad[0]) *q = &ov_quad[c->ext - 1];
        const unsigned al = q->alpha + (q->alpha >> 7);
        gfx_quad(s, c->a, c->frame, q->xy, q->light, q->lights, q->mode, al, q->dither, q->mesh, q->persp, q->mip,
                 c->len ? ov_pts + c->str : NULL);
        break;
    }
    case OV_GRAD: {
        const typeof(ov_quad[0]) *q = &ov_quad[c->ext - 1];
        gfx_grad(s, c->x, c->y, c->w, c->h, q->light[0], q->light[1], q->lights, q->dither, q->mode, q->alpha + (q->alpha >> 7),
                 c->len ? (const uint16_t *)(ov_pts + c->str) : NULL); /* (the ramp, worked out when recorded) */
        break;
    }
    case OV_LIGHT: {
        const typeof(ov_quad[0]) *q = &ov_quad[c->ext - 1];
        gfx_light(s, c->x, c->y, c->w, q->light[0], q->alpha + (q->alpha >> 7), q->mode == BLEND_SUB, q->lights, q->xy[0], q->xy[1],
                  q->xy[2], q->xy[3]);
        break;
    }
    case OV_WARP: {
        const typeof(ov_quad[0]) *q = &ov_quad[c->ext - 1];
        const int16_t *rows = q->lights ? ov_pts + c->str : NULL; /* (the rows' shifts, then the columns') */
        const int16_t *cols = q->dither ? ov_pts + c->str + (q->lights ? c->len : 0) : NULL;
        gfx_warp(s, c->a, c->frame, c->x + q->xy[0], c->y + q->xy[1], rows, cols, q->mode == 1);
        break;
    }
    case OV_LINES: {
        const typeof(ov_quad[0]) *q = &ov_quad[c->ext - 1];
        gfx_lines(s, c->x, c->y, c->w, c->h, (const uint16_t *)(ov_pts + c->str), q->mode == 3 ? BLEND_ALPHA : q->mode,
                  q->alpha + (q->alpha >> 7), q->mode == 4);
        break;
    }
    case OV_MESH: { /* flip: bit 0 lit, bit 1 dithered; the faces are far to near already */
        const bool lit = c->flip & 1, dither = (c->flip & 2) && lit;
        for (int i = 0; i < c->len; i++) {
            const mesh_face *f = &mfaces[c->str + i];
            int x0 = f->xy[0], x1 = f->xy[0], y0 = f->xy[1], y1 = f->xy[1];
            for (int k = 1; k < 4; k++) {
                x0 = f->xy[2 * k] < x0 ? f->xy[2 * k] : x0, x1 = f->xy[2 * k] > x1 ? f->xy[2 * k] : x1;
                y0 = f->xy[2 * k + 1] < y0 ? f->xy[2 * k + 1] : y0, y1 = f->xy[2 * k + 1] > y1 ? f->xy[2 * k + 1] : y1;
            }
            if (x1 / 8 + 2 < s->x0 || x0 / 8 - 1 >= s->x0 + s->w || y1 / 8 + 2 < s->y0 || y0 / 8 - 1 >= s->y0 + s->h) continue;
            uint8_t light[4][3];
            for (int k = 0; k < 4; k++) memcpy(light[k], f->light, 3);
            gfx_quad(s, c->a, c->frame, f->xy, light, lit, BLEND_ALPHA, 256, dither, false, 0, f->mip, f->uv);
        }
        break;
    }
    case OV_POINTS: /* a swarm: its picture at each point (its top-left corner, already worked out) */
        for (int i = 0; i < c->len; i++) {
            int x = ov_pts[c->str + 2 * i], y = ov_pts[c->str + 2 * i + 1];
            if (x + c->a->w > s->x0 && x < s->x0 + s->w && y + c->a->h > s->y0 && y < s->y0 + s->h)
                gfx_blit_flip(s, c->a, c->frame, x, y, false, NULL, -1);
        }
        break;
    case OV_IMG: {
        const bool see = c->font && (ov_look[c->font - 1].alpha < 255 || ov_look[c->font - 1].mode);
        if (see && c->a->pk && !c->ext && c->scale == 1 && !ov_look[c->font - 1].pal) { /* the quick way: mixed as drawn */
            unsigned al = ov_look[c->font - 1].alpha;
            gfx_blit_mixed(s, c->a, c->frame, c->x, c->y, c->flip, ov_look[c->font - 1].tint, al + (al >> 7),
                           ov_look[c->font - 1].mode);
            break;
        }
        surface under = see ? img_area(s, c) : *s;
        const uint16_t *kept = see ? keep(&under) : NULL;
        if (c->ext)
            gfx_blit_ex(s, c->a, c->frame, c->x, c->y, ov_xf[c->ext - 1].sx, ov_xf[c->ext - 1].sy, ov_xf[c->ext - 1].deg,
                        c->font ? ov_look[c->font - 1].pal : NULL, c->font ? ov_look[c->font - 1].tint : -1);
        else if (c->scale == 2)
            gfx_blit2x_look(s, c->a, c->frame, c->x, c->y, c->font ? ov_look[c->font - 1].pal : NULL,
                            c->font ? ov_look[c->font - 1].tint : -1);
        else if (c->font) gfx_blit_flip(s, c->a, c->frame, c->x, c->y, c->flip, ov_look[c->font - 1].pal, ov_look[c->font - 1].tint);
        else gfx_blit_flip(s, c->a, c->frame, c->x, c->y, c->flip, NULL, -1);
        if (kept) see_through(&under, kept, ov_look[c->font - 1].alpha, ov_look[c->font - 1].mode);
        break;
    }
    }
}

static void draw_timed(surface *s, const ov_cmd *c) {
    if (!prof_want) {
        draw_one(s, c);
        return;
    }
    const uint32_t t = hal_micros();
    draw_one(s, c);
    prof_cur.us[s->part & 1][c->op] += hal_micros() - t;
}

void draw_overlay(surface *s) {
    const int b0 = s->x0 / BAND, b1 = (s->x0 + s->w - 1) / BAND; /* the bands of this strip (all, for the whole frame) */
    for (int i = 0; i < nov; i++) {
        const ov_cmd *c = &ov[i];
        if (c->band1 < b0 || c->band0 > b1) continue; /* nowhere near: a byte compared, not a call and its clipping */
        if (!c->clip) {
            draw_timed(s, c);
            continue;
        }
        const screen_rect *r = &ov_clip[c->clip - 1];
        surface in = gfx_clip(s, r->x, r->y, r->w, r->h);
        if (in.w > 0 && in.h > 0) draw_timed(&in, c);
    }
}

void draw_profile(unsigned who, bool on) { prof_want = on ? prof_want | who : prof_want & ~who; }

int draw_profile_rows(draw_prof_row *rows, int max) { /* the last frame's kinds of command, dearest first */
    draw_prof_row all[OV_OPS];
    int n = 0;
    for (int op = 0; op < OV_OPS; op++) {
        if (!prof_last.n[op]) continue;
        const draw_prof_row r = {OP_NAME[op], prof_last.n[op], (prof_last.us[0][op] + prof_last.us[1][op]) / 1000.0f};
        int k = n++;
        while (k > 0 && all[k - 1].ms < r.ms) all[k] = all[k - 1], k--;
        all[k] = r;
    }
    n = n < max ? n : max;
    memcpy(rows, all, (size_t)n * sizeof *rows);
    return n;
}

void draw_profile_slots(int *cmds, int *cmds_max, int *slots, int *slots_max) {
    *cmds = prof_last.cmds, *cmds_max = OV_MAX, *slots = prof_last.slots, *slots_max = OV_EXT;
}

/* ------------------------------------------------------------------ canvases, camera, clip */

void draw_flush(void) { /* the masks of the canvases drawn on, where they were */
    for (int i = 0; i < ndirty; i++)
        gfx_canvas_mask(dirty[i].a, dirty[i].x0, dirty[i].y0, dirty[i].x1 - dirty[i].x0, dirty[i].y1 - dirty[i].y0);
    ndirty = 0;
}

static void touched(asset *a, int x0, int y0, int x1, int y1) { /* a box on canvas a was drawn on (ends excluded) */
    a->gen++;
    int i = 0;
    while (i < ndirty && dirty[i].a != a) i++;
    if (i == MAX_DIRTY) draw_flush(), i = 0;
    if (i == ndirty) dirty[ndirty++] = (dirty_box){a, x0, y0, x1, y1};
    else {
        dirty[i].x0 = x0 < dirty[i].x0 ? x0 : dirty[i].x0, dirty[i].y0 = y0 < dirty[i].y0 ? y0 : dirty[i].y0;
        dirty[i].x1 = x1 > dirty[i].x1 ? x1 : dirty[i].x1, dirty[i].y1 = y1 > dirty[i].y1 ? y1 : dirty[i].y1;
    }
}

static void bounds(const ov_cmd *c, int *x0, int *y0, int *x1, int *y1) { /* what a command may draw on, roughly */
    *x0 = c->x, *y0 = c->y, *x1 = c->x + c->w, *y1 = c->y + c->h;
    switch (c->op) {
    case OV_LINE:
        *x0 = c->x < c->w ? c->x : c->w, *x1 = (c->x > c->w ? c->x : c->w) + 1;
        *y0 = c->y < c->h ? c->y : c->h, *y1 = (c->y > c->h ? c->y : c->h) + 1;
        break;
    case OV_CIRC: *x0 = c->x - c->w, *y0 = c->y - c->w, *x1 = c->x + c->w + 1, *y1 = c->y + c->w + 1; break;
    case OV_BOX: /* its 2-pixel edges are drawn even past a box of no size or a negative one */
        *x0 = (c->w < 0 ? c->x + c->w : c->x) - 2, *x1 = (c->w < 0 ? c->x : c->x + c->w) + 2;
        *y0 = (c->h < 0 ? c->y + c->h : c->y) - 2, *y1 = (c->h < 0 ? c->y : c->y + c->h) + 2;
        break;
    case OV_PANEL:
    case OV_PLATE: /* a card's shadow falls right and below it, and a theme's marks can reach past a small one */
        *x0 = (c->w < 0 ? c->x + c->w : c->x) - 56, *x1 = (c->w < 0 ? c->x : c->x + c->w) + 8;
        *y0 = (c->h < 0 ? c->y + c->h : c->y) - 12, *y1 = (c->h < 0 ? c->y : c->y + c->h) + 8;
        break;
    case OV_POLY:
    case OV_POINTS: {
        int pw = c->op == OV_POINTS ? c->a->w : 1, ph = c->op == OV_POINTS ? c->a->h : 1; /* a point: its picture */
        *x0 = *y0 = 32767, *x1 = *y1 = -32768;
        for (int i = 0; i < c->len; i++) {
            int x = ov_pts[c->str + 2 * i], y = ov_pts[c->str + 2 * i + 1];
            *x0 = x < *x0 ? x : *x0, *y0 = y < *y0 ? y : *y0, *x1 = x + pw > *x1 ? x + pw : *x1, *y1 = y + ph > *y1 ? y + ph : *y1;
        }
        break;
    }
    case OV_LIGHT: *x0 = c->x - c->w, *y0 = c->y - c->w, *x1 = c->x + c->w + 1, *y1 = c->y + c->w + 1; break;
    case OV_QUAD: { /* its corners, a pixel wider each way for the rounding */
        const int16_t *xy = ov_quad[c->ext - 1].xy;
        *x0 = *y0 = 32767, *x1 = *y1 = -32768;
        for (int i = 0; i < 4; i++) {
            *x0 = xy[2 * i] / 8 - 1 < *x0 ? xy[2 * i] / 8 - 1 : *x0, *x1 = xy[2 * i] / 8 + 2 > *x1 ? xy[2 * i] / 8 + 2 : *x1;
            *y0 = xy[2 * i + 1] / 8 - 1 < *y0 ? xy[2 * i + 1] / 8 - 1 : *y0, *y1 = xy[2 * i + 1] / 8 + 2 > *y1 ? xy[2 * i + 1] / 8 + 2 : *y1;
        }
        break;
    }
    case OV_TEXT_OP: *x0 -= 64, *y0 -= 64, *x1 += 64, *y1 += 64; break; /* outlines, shadows, waves */
    case OV_IMG:
        if (c->ext) *x0 = *y0 = -32768, *x1 = *y1 = 32767; /* turned: anywhere */
        else *x1 = c->x + c->a->w * c->scale, *y1 = c->y + c->a->h * c->scale;
        break;
    }
}

static void forget(const ov_cmd *c, int text_bytes, int corners) { /* the last command, off the list with its data */
    nov--, ntext -= text_bytes, npts -= 2 * corners;
    if (c->op == OV_MESH) nmf -= c->len;
    else if (c->op == OV_QUAD || c->op == OV_GRAD || c->op == OV_LIGHT || c->op == OV_WARP || c->op == OV_LINES) nquad--;
    else if (c->ext && c->op == OV_TEXT_OP) nstyle--;
    else if (c->ext) nxf--;
    if (c->op == OV_IMG && c->font) nlook--;
}

/* The costly commands (styled text, nine-slice frames, turned pictures) drawn once into a picture of their own,
 * kept from frame to frame while they stay the same (gfx_cache.c); the command becomes "copy that picture", which
 * every strip does the fast way. The same pixels as drawing them directly. */
#define KEY_MAX 512

static void key_add(uint8_t *k, int *n, const void *v, int len) {
    if (*n + len <= KEY_MAX) memcpy(k + *n, v, (size_t)len);
    *n += len;
}

#define SEEN 256
static uint32_t seen[2][SEEN]; /* the keys asked for in this frame and the one before */
static int nseen[2];

static uint32_t key_hash(const uint8_t *k, int n) {
    uint32_t h = 2166136261u;
    for (int i = 0; i < n; i++) h = (h ^ k[i]) * 16777619u;
    return h;
}

/* Kept, or made now (fresh). Only what is asked for again the next frame is made: a picture that turns or a frame
 * that grows every frame would be made and thrown away each time, dearer than drawing it straight. NULL: draw it
 * straight. */
static asset *picture(const uint8_t *key, int n, int w, int h, bool *fresh) {
    *fresh = false;
    if (n > KEY_MAX) return NULL;
    asset *a = pic_find(key, n, frame_no);
    if (a) return a;
    uint32_t hk = key_hash(key, n);
    int now = frame_no & 1;
    if (nseen[now] < SEEN) seen[now][nseen[now]++] = hk;
    bool again = false;
    for (int i = 0; i < nseen[!now] && !again; i++) again = seen[!now][i] == hk;
    if (again && (a = pic_make(key, n, w, h, frame_no))) *fresh = true;
    return a;
}

static uint16_t not_key(uint16_t c) { return c == CANVAS_KEY ? c ^ 1 : c; } /* the key colour is see-through there */

static bool straight(const ov_cmd *c) { /* a packed picture scaled, not turned: drawn from its columns, not kept */
    return c->a->pk && ov_xf[c->ext - 1].deg == 0;
}

static void as_picture(ov_cmd *c) {
    uint8_t key[KEY_MAX];
    int n = 0, w = 0, h = 0, ox = 0, oy = 0;
    bool fresh;
    asset *a = NULL;
    key_add(key, &n, &c->op, 1);
    if (c->op == OV_TEXT_OP && c->ext) {
        text_style st = ov_style[c->ext - 1];
        if (st.wave || st.shake) return; /* letters that move each frame: drawn directly */
        const font *f = font_named(c->font);
        int k = st.scale < 1 ? 1 : st.scale, m = 3 * k; /* room for the outline and the shadow */
        st.color = not_key(st.color), st.bottom = not_key(st.bottom), st.outline = not_key(st.outline);
        st.shadow = not_key(st.shadow), st.tick = 0;
        key_add(key, &n, &f, sizeof f), key_add(key, &n, &st, sizeof st), key_add(key, &n, ov_text + c->str, c->len);
        w = c->w + f->w * k + 2 * m, h = f->h * k + 2 * m, ox = oy = -m;
        if (!(a = picture(key, n, w, h, &fresh))) return;
        if (fresh) {
            surface s = {.px = a->pixels, .w = w, .h = h};
            font_draw_styled(&s, f, m, m, ov_text + c->str, c->len, -1, &st);
        }
    } else if (c->op == OV_NINE) {
        key_add(key, &n, &c->a, sizeof c->a), key_add(key, &n, &c->frame, sizeof c->frame);
        key_add(key, &n, &c->w, sizeof c->w), key_add(key, &n, &c->h, sizeof c->h), key_add(key, &n, &c->scale, 1);
        w = c->w, h = c->h;
        if (!(a = picture(key, n, w, h, &fresh))) return;
        if (fresh) {
            surface s = {.px = a->pixels, .w = w, .h = h};
            gfx_nine(&s, c->a, c->frame, 0, 0, w, h, c->scale);
        }
    } else if (c->op == OV_IMG && c->ext && !straight(c)) {
        float t[3] = {ov_xf[c->ext - 1].sx, ov_xf[c->ext - 1].sy, ov_xf[c->ext - 1].deg};
        key_add(key, &n, &c->a, sizeof c->a), key_add(key, &n, &c->frame, sizeof c->frame), key_add(key, &n, t, sizeof t);
        key_add(key, &n, &c->a->gen, sizeof c->a->gen); /* a canvas drawn on since: another picture */
        gfx_blit_ex_bounds(c->a, t[0], t[1], t[2], &ox, &oy, &w, &h);
        if (!(a = picture(key, n, w, h, &fresh))) return;
        if (fresh) {
            surface s = {.px = a->pixels, .w = w, .h = h};
            gfx_blit_ex(&s, c->a, c->frame, -ox, -oy, t[0], t[1], t[2], NULL, -1);
        }
    } else {
        return;
    }
    if (fresh) pic_done(a);
    uint8_t look = 0; /* (a text's font field is no look: it becomes a plain picture) */
    if (c->op == OV_IMG && c->font) {
        if (ov_look[c->font - 1].alpha < 255 || ov_look[c->font - 1].mode) look = c->font; /* still seen through */
        else nlook--;
    }
    c->op = OV_IMG, c->a = a, c->x = i16(c->x + ox), c->y = i16(c->y + oy), c->scale = 1, c->ext = 0, c->frame = 0;
    c->font = look, c->flip = 0;
}

/* The bands of BAND screen columns a command may draw on (the console draws the screen as strips of 32 columns, and
 * each strip looks only at the commands of its band); none (band0 > band1) when it is off the screen. */
static void band(ov_cmd *c) {
    int x0, y0, x1, y1;
    bounds(c, &x0, &y0, &x1, &y1);
    if (c->clip) {
        const screen_rect *r = &ov_clip[c->clip - 1];
        x0 = x0 > r->x ? x0 : r->x, x1 = x1 < r->x + r->w ? x1 : r->x + r->w;
        y0 = y0 > r->y ? y0 : r->y, y1 = y1 < r->y + r->h ? y1 : r->y + r->h;
    }
    if (x1 <= 0 || x0 >= SCREEN_W || y1 <= 0 || y0 >= SCREEN_H || x0 >= x1 || y0 >= y1) {
        c->band0 = 1, c->band1 = 0;
        return;
    }
    c->band0 = (uint8_t)(x0 < 0 ? 0 : x0 / BAND), c->band1 = (uint8_t)(((x1 > SCREEN_W ? SCREEN_W : x1) - 1) / BAND);
}

/* A drawing call's command, finished: moved by the camera; then kept for the screen's strips with the clip in force,
 * or, when the target is a canvas, drawn on it at once and taken off the list. */
static void commit(ov_cmd *c, int text_bytes, int corners) {
    c->x = i16(c->x - cam_x), c->y = i16(c->y - cam_y);
    if (c->op == OV_LINE) c->w = i16(c->w - cam_x), c->h = i16(c->h - cam_y);
    for (int i = 0; c->op == OV_POLY && i < c->len; i++)
        ov_pts[c->str + 2 * i] = i16(ov_pts[c->str + 2 * i] - cam_x), ov_pts[c->str + 2 * i + 1] = i16(ov_pts[c->str + 2 * i + 1] - cam_y);
    for (int i = 0; c->op == OV_QUAD && i < 4; i++)
        ov_quad[c->ext - 1].xy[2 * i] = i16(ov_quad[c->ext - 1].xy[2 * i] - cam_x * 8),
        ov_quad[c->ext - 1].xy[2 * i + 1] = i16(ov_quad[c->ext - 1].xy[2 * i + 1] - cam_y * 8);
    for (int i = 0; c->op == OV_MESH && i < c->len; i++)
        for (int k = 0; k < 4; k++)
            mfaces[c->str + i].xy[2 * k] = i16(mfaces[c->str + i].xy[2 * k] - cam_x * 8),
            mfaces[c->str + i].xy[2 * k + 1] = i16(mfaces[c->str + i].xy[2 * k + 1] - cam_y * 8);
    if (!target) {
        as_picture(c); /* the costly ones, once, then copied */
        if (clipping) {
            if (!nclip || memcmp(&ov_clip[nclip - 1], &clip_r, sizeof clip_r)) {
                if (nclip == OV_CLIPS) { /* better not drawn than drawn outside it */
                    forget(c, text_bytes, corners);
                    return;
                }
                ov_clip[nclip++] = clip_r;
            }
            c->clip = (uint8_t)nclip;
        }
        band(c);
        return;
    }
    surface whole = {.px = target->pixels, .w = target->w, .h = target->h, .canvas = true};
    surface s = clipping ? gfx_clip(&whole, clip_r.x, clip_r.y, clip_r.w, clip_r.h) : whole;
    if (s.w > 0 && s.h > 0) {
        if (c->op == OV_SHADE) gfx_canvas_shade(&s, c->x, c->y, c->w, c->h); /* see-through stays so */
        else draw_one(&s, c);
        int x0, y0, x1, y1;
        bounds(c, &x0, &y0, &x1, &y1);
        touched(target, x0, y0, x1, y1);
    }
    forget(c, text_bytes, corners);
}

/* A colour argument: 0xRRGGBB, or CLEAR (see-through on a canvas). false: nothing to draw (CLEAR on the screen). */
static bool colour_at(lua_State *L, int arg, lua_Integer d, uint16_t *out) {
    lua_Integer v = luaL_optinteger(L, arg, d);
    if (v == CLEAR) return *out = CANVAS_KEY, target != NULL;
    *out = to565(v);
    if (target && *out == CANVAS_KEY) *out ^= 1; /* the see-through colour itself, drawn: one step off */
    return true;
}

static int font_by_name(lua_State *L, const char *name) { /* the four of every game, or fonts/<name>.fnt */
    static const char *const names[] = {"main", "bold", "large", "large_bold"};
    for (int i = 0; i < 4; i++)
        if (!strcmp(name, names[i])) return i;
    for (int i = 0; i < nvfont; i++)
        if (!strcmp(vfont[i].name, name)) return 4 + i;
    if (!safe_name(name) || strchr(name, '/') || strlen(name) >= sizeof vfont[0].name)
        return luaL_error(L, "font \"%s\": not a font name", name);
    if (nvfont == MAX_FONTS) return luaL_error(L, "font \"%s\": a game can have %d fonts of its own", name, MAX_FONTS);
    char path[384];
    snprintf(path, sizeof path, "%s/fonts/%s.fnt", G.game_dir, name);
    font *f = &vfont[nvfont].f;
    memset(f, 0, sizeof *f);
    if (!font_load(f, path)) return luaL_error(L, "font \"%s\": fonts/%s.fnt is missing or not a font", name, name);
    snprintf(vfont[nvfont].name, sizeof vfont[0].name, "%s", name);
    return 4 + nvfont++;
}

static int font_arg(lua_State *L, int arg) { return font_by_name(L, luaL_optstring(L, arg, "main")); }

static const font *spaced(const font *f, int spacing) { /* the font with its letters further apart: for measuring */
    static font t;
    if (!spacing) return f;
    t = *f;
    for (int c = 0; c < 256; c++) {
        int v = f->adv[c] + spacing;
        t.adv[c] = (uint8_t)(v < 0 ? 0 : v > 255 ? 255 : v);
    }
    return &t;
}

static int utf8_prefix(const char *s, int n, int *chars) { /* bytes of up to *chars characters; *chars counts down */
    int b = 0;
    while (b < n && *chars > 0) {
        b++;
        while (b < n && (s[b] & 0xC0) == 0x80) b++;
        (*chars)--;
    }
    return b;
}

typedef struct {
    int f, al, wrap, chars;
    uint16_t colour;
    bool styled;
    text_style st;
} text_args;

/* text's options, as a table: {color, font, align, width, chars, outline, shadow, shadow_x, shadow_y, gradient,
 * scale, spacing, wave, shake} */
static void text_opts(lua_State *L, int t, text_args *a) {
    static const char *const aligns[] = {"left", "center", "right", NULL};
    lua_getfield(L, t, "font");
    a->f = lua_isnil(L, -1) ? 0 : font_by_name(L, luaL_checkstring(L, -1));
    lua_pop(L, 1);
    lua_getfield(L, t, "align");
    a->al = luaL_checkoption(L, -1, "left", aligns);
    lua_pop(L, 1);
    a->wrap = (int)opt_float(L, t, "width", 0, 0, 2 * SCREEN_W);
    a->chars = (int)opt_float(L, t, "chars", 1 << 30, 0, 1 << 30);
    a->colour = to565(opt_int(L, t, "color", 0xFFFFFF));
    text_style *st = &a->st;
    memset(st, 0, sizeof *st);
    st->color = a->colour;
    lua_getfield(L, t, "outline");
    if ((st->has_outline = !lua_isnil(L, -1))) st->outline = to565(luaL_checkinteger(L, -1));
    lua_pop(L, 1);
    lua_getfield(L, t, "shadow");
    if ((st->has_shadow = !lua_isnil(L, -1))) st->shadow = to565(luaL_checkinteger(L, -1));
    lua_pop(L, 1);
    st->sdx = (int8_t)opt_float(L, t, "shadow_x", 1, -2, 2), st->sdy = (int8_t)opt_float(L, t, "shadow_y", 1, -2, 2);
    lua_getfield(L, t, "gradient");
    if ((st->gradient = !lua_isnil(L, -1))) st->bottom = to565(luaL_checkinteger(L, -1));
    lua_pop(L, 1);
    st->scale = (uint8_t)opt_float(L, t, "scale", 1, 1, 8);
    st->spacing = (int8_t)opt_float(L, t, "spacing", 0, -8, 32);
    st->wave = (uint8_t)opt_float(L, t, "wave", 0, 0, 32), st->shake = (uint8_t)opt_float(L, t, "shake", 0, 0, 16);
    st->tick = (uint32_t)G.ticks;
    a->styled = st->has_outline || st->has_shadow || st->gradient || st->scale > 1 || st->spacing || st->wave || st->shake;
}

static int line_w(const font *f, const char *s, int n, const text_args *a) {
    return a->styled ? font_width(spaced(f, a->st.spacing), s, n) * a->st.scale : font_width(f, s, n);
}

static void text_line(const char *s, int n, int x, int y, const text_args *a) {
    ov_cmd *c = ntext + n <= OV_TEXT ? ov_add(OV_TEXT_OP) : NULL;
    if (!c) return;
    int w = line_w(font_named(a->f), s, n, a);
    memcpy(ov_text + ntext, s, (size_t)n);
    c->str = (uint16_t)ntext, c->len = (uint16_t)n, ntext += n;
    c->x = i16(x - (a->al == 1 ? w / 2 : a->al == 2 ? w : 0)), c->y = i16(y);
    c->font = (uint8_t)a->f, c->color = a->colour;
    c->w = i16(w), c->h = i16(font_named(a->f)->h * (a->styled ? a->st.scale : 1));
    if (a->styled && nstyle < OV_EXT) ov_style[nstyle] = a->st, c->ext = (uint8_t)(++nstyle); /* past it: plain */
    commit(c, n, 0);
}

/* text(str, x, y [, colour [, font [, align [, width [, chars]]]]]) or text(str, x, y, {options}) -> width, height;
 * screen pixels (480x320). width wraps the text into lines that fit it; chars shows only that many characters. */
static int l_text(lua_State *L) {
    size_t n = 0;
    const char *s = luaL_checklstring(L, 1, &n);
    int x = num(L, 2), y = num(L, 3);
    text_args a = {0};
    if (lua_istable(L, 4)) text_opts(L, 4, &a);
    else {
        static const char *const aligns[] = {"left", "center", "right", NULL};
        a.f = font_arg(L, 5), a.wrap = optnum(L, 7, 0), a.chars = optnum(L, 8, 1 << 30);
        a.al = luaL_checkoption(L, 6, "left", aligns);
        a.colour = to565(luaL_optinteger(L, 4, 0xFFFFFF));
    }
    if (a.wrap > 2 * SCREEN_W) a.wrap = 2 * SCREEN_W; /* wider is no use, and wrapping costs grow with the line's length */
    const font *f = font_named(a.f);
    int k = a.styled ? a.st.scale : 1, lh = f->h * k, chars = a.chars;
    if (a.wrap <= 0) { /* one line */
        int w = line_w(f, s, (int)n, &a);
        text_line(s, utf8_prefix(s, (int)n, &chars), x, y, &a);
        lua_pushinteger(L, w), lua_pushinteger(L, lh);
        return 2;
    }
    uint16_t starts[32], lens[32];
    int lines = text_wrap(a.styled ? spaced(f, a.st.spacing) : f, s, a.wrap / k, starts, lens, 32), widest = 0;
    for (int i = 0; i < lines; i++) {
        int w = line_w(f, s + starts[i], lens[i], &a);
        widest = w > widest ? w : widest;
        if (chars > 0) text_line(s + starts[i], utf8_prefix(s + starts[i], lens[i], &chars), x, y + i * lh, &a);
    }
    lua_pushinteger(L, widest), lua_pushinteger(L, lines * lh);
    return 2;
}

/* textw(str [, font | {font, scale, spacing}]) -> width, height */
static int l_textw(lua_State *L) {
    size_t n = 0;
    const char *s = luaL_checklstring(L, 1, &n);
    text_args a = {0};
    if (lua_istable(L, 2)) text_opts(L, 2, &a);
    else a.f = font_arg(L, 2); /* before pushing: a pushed result would become argument 2 */
    const font *f = font_named(a.f);
    lua_pushinteger(L, line_w(f, s, (int)n, &a));
    lua_pushinteger(L, f->h * (a.styled ? a.st.scale : 1));
    return 2;
}

static int shape(lua_State *L, int op, bool colour) {
    ov_cmd *c = ov_add(op);
    if (!c) return 0;
    c->x = i16(num(L, 1)), c->y = i16(num(L, 2)), c->w = i16(num(L, 3)), c->h = i16(num(L, 4));
    if (colour && !colour_at(L, 5, 0xFFFFFF, &c->color)) return nov--, 0;
    commit(c, 0, 0);
    return 0;
}

static int l_rect(lua_State *L) { return shape(L, OV_FILL, true); }
static int l_box(lua_State *L) { return shape(L, OV_BOX, true); }
static int l_shade(lua_State *L) { return shape(L, OV_SHADE, false); }
static int l_panel(lua_State *L) { return shape(L, OV_PANEL, false); }
static int l_plate(lua_State *L) { return shape(L, OV_PLATE, true); }

typedef struct {
    lua_Integer frame, tint;
    float scale, sx, sy, deg;
    bool has_sx, has_sy, flip_x, flip_y, tinted, dimmed;
    float dim;  /* dim: a picture's colours times this (a night); mul: times each channel of 0xRRGGBB (0xFF as it is) */
    int mul;
    uint8_t mode; /* BLEND_*: add, sub or quarter, the last one asked for */
    float alpha;
    const char *pal; /* (a string the table keeps alive) */
    bool outlined;
    lua_Integer outline; /* outline: a ring of this 0xRRGGBB round the picture's shape, outline_width pixels thick (1 to 4) */
    int outline_width;
} img_opts;

static float clampf(float v, float lo, float hi) { return v < lo ? lo : v > hi ? hi : v; }

/* img's options, read in one walk over the table: only the keys it has (most calls give two or three of the nine),
 * where looking each one up was most of an img's cost on the console */
static void img_options(lua_State *L, int t, img_opts *o) {
    *o = (img_opts){.scale = 1, .alpha = 1, .dim = 1, .mul = 0xFFFFFF};
    lua_pushnil(L);
    while (lua_next(L, t)) {
        const char *k = lua_type(L, -2) == LUA_TSTRING ? lua_tostring(L, -2) : "";
        if (!strcmp(k, "frame")) o->frame = luaL_checkinteger(L, -1);
        else if (!strcmp(k, "flip_x")) o->flip_x = lua_toboolean(L, -1);
        else if (!strcmp(k, "tint")) o->tint = luaL_checkinteger(L, -1), o->tinted = true;
        else if (!strcmp(k, "dim")) o->dim = clampf(fin(luaL_checknumber(L, -1)), 0, 1), o->dimmed = true;
        else if (!strcmp(k, "mul")) o->mul = (int)(luaL_checkinteger(L, -1) & 0xFFFFFF), o->dimmed = true, o->dim = 1;
        else if (!strcmp(k, "scale")) o->scale = fin(luaL_checknumber(L, -1));
        else if (!strcmp(k, "angle")) o->deg = fin(luaL_checknumber(L, -1));
        else if (!strcmp(k, "scale_x")) o->sx = fin(luaL_checknumber(L, -1)), o->has_sx = true;
        else if (!strcmp(k, "scale_y")) o->sy = fin(luaL_checknumber(L, -1)), o->has_sy = true;
        else if (!strcmp(k, "flip_y")) o->flip_y = lua_toboolean(L, -1);
        else if (!strcmp(k, "pal")) o->pal = lua_type(L, -1) == LUA_TSTRING ? lua_tostring(L, -1) : NULL;
        else if (!strcmp(k, "alpha")) o->alpha = clampf(fin(luaL_checknumber(L, -1)), 0, 1);
        else if (!strcmp(k, "add")) o->mode = lua_toboolean(L, -1) ? BLEND_ADD : o->mode;
        else if (!strcmp(k, "sub")) o->mode = lua_toboolean(L, -1) ? BLEND_SUB : o->mode;
        else if (!strcmp(k, "quarter")) o->mode = lua_toboolean(L, -1) ? BLEND_QUARTER : o->mode;
        else if (!strcmp(k, "outline")) o->outline = luaL_checkinteger(L, -1), o->outlined = true;
        else if (!strcmp(k, "outline_width")) o->outline_width = (int)clampf(fin(luaL_checknumber(L, -1)), 1, 4);
        lua_pop(L, 1);
    }
}

/* img(id, x, y [, frame [, scale 1|2]]) or img(id, x, y, {frame, scale, scale_x, scale_y, flip_x, flip_y, angle}):
 * a runtime asset at screen resolution; angle in degrees, about the picture's centre */
/* one picture's command, by its options: the body of img() for a table of them */
static void img_emit(asset *a, int x, int y, const img_opts *o) {
    ov_cmd *c = ov_add(OV_IMG);
    if (!c) return;
    c->a = a, c->x = i16(x), c->y = i16(y), c->scale = 1, c->flip = 0, c->font = 0;
    lua_Integer f = o->frame;
    c->frame = (int16_t)(f < 0 || f >= a->frames ? 0 : f);
    float k = clampf(o->scale, -16, 16);
    float sx = clampf(o->has_sx ? o->sx : k, -16, 16), sy = clampf(o->has_sy ? o->sy : k, -16, 16);
    float deg = clampf(o->deg, -1e6f, 1e6f);
    if (o->flip_x) sx = -sx;
    if (o->flip_y) sy = -sy;
    if (deg == 0 && sx == sy && (sx == 1 || sx == 2)) c->scale = (uint8_t)sx; /* the plain ways, faster */
    else if (deg == 0 && sx == -1 && sy == 1) c->flip = 1;      /* mirrored at 1x: as fast as plain */
    else if (nxf < OV_EXT) ov_xf[nxf].sx = sx, ov_xf[nxf].sy = sy, ov_xf[nxf].deg = deg, c->ext = (uint8_t)(++nxf);
    const char *pal = o->pal;
    bool tinted = o->tinted;
    lua_Integer tint = o->tint;
    bool colours = (pal || tinted || o->dimmed) && (c->ext ? straight(c) : c->scale == 1 || a->pk); /* a variant's, one, or dimmed */
    if ((colours || o->alpha < 1 || o->mode) && nlook < OV_EXT) {
        asset *pa = colours && pal && safe_name(pal) ? gfx_asset_opt(pal) : NULL;
        ov_look[nlook].pal = pa && !pa->missing ? pa : NULL;
        ov_look[nlook].tint = colours && tinted ? to565(tint) : -1;
        if (colours && !tinted && o->dimmed) { /* a multiplier, as the palette is to be multiplied (gfx.c, mul565) */
            const int r = (int)((o->mul >> 16 & 255) * o->dim), g = (int)((o->mul >> 8 & 255) * o->dim), b = (int)((o->mul & 255) * o->dim);
            ov_look[nlook].tint = -2 - (r << 16 | g << 8 | b);
        }
        ov_look[nlook].alpha = (uint8_t)(o->alpha * 255 + 0.5f), ov_look[nlook].mode = o->mode;
        c->font = (uint8_t)(++nlook);
    }
    if ((c->ext ? !straight(c) : c->scale == 2 && !a->pk) && !gfx_pixels(a)) { /* turned: unpacked here, once */
        forget(c, 0, 0);
        return;
    }
    commit(c, 0, 0);
}

/* img(id, x, y [, frame [, scale 1|2]]) or img(id, x, y, {frame, scale, scale_x, scale_y, flip_x, flip_y, angle, pal, tint, dim, mul, alpha,
 * add, sub, quarter, outline, outline_width}): a runtime asset at screen resolution; angle in degrees, about the picture's centre */
static int l_img(lua_State *L) {
    const char *id = luaL_checkstring(L, 1);
    asset *a = safe_name(id) ? gfx_asset(id) : NULL;
    if (!a || a->missing) return 0;
    if (lua_istable(L, 4)) {
        img_opts o;
        img_options(L, 4, &o);
        const int x = num(L, 2), y = num(L, 3);
        if (o.outlined) { /* a ring: the picture's shape in the outline's colour, one step out each way, under the picture itself */
            const int w = o.outline_width ? o.outline_width : 1;
            img_opts ring = o;
            ring.outlined = false, ring.tinted = true, ring.tint = o.outline, ring.dimmed = false, ring.pal = NULL, ring.mode = 0;
            static const int8_t step[4][2] = {{-1, 0}, {1, 0}, {0, -1}, {0, 1}};
            for (int k = 0; k < 4; k++) img_emit(a, x + step[k][0] * w, y + step[k][1] * w, &ring);
        }
        img_emit(a, x, y, &o);
        return 0;
    }
    ov_cmd *c = ov_add(OV_IMG);
    if (!c) return 0;
    c->a = a, c->x = i16(num(L, 2)), c->y = i16(num(L, 3)), c->scale = 1, c->flip = 0, c->font = 0;
    lua_Integer f = luaL_optinteger(L, 4, 0);
    c->frame = (int16_t)(f < 0 || f >= a->frames ? 0 : f);
    c->scale = (uint8_t)(luaL_optinteger(L, 5, 1) == 2 ? 2 : 1);
    if (c->scale == 2 && !a->pk && !gfx_pixels(a)) forget(c, 0, 0);
    else commit(c, 0, 0);
    return 0;
}

/* light(x, y, r, colour [, {intensity, sub, cone}]): a soft round glow of that colour reaching r pixels, added to what is under
 * it (a candle, a lamp, a flame, a window's light); sub = true takes it away instead (a pool of shadow). intensity 0..2 (1:
 * as the colour). cone = {angle = degrees (0: to the right, 90: down), width = degrees across} makes it a beam (a flashlight,
 * a guard's sight): full inside two thirds of it, half at the rim. It reads no picture: only the pixels it reaches cost (~200 ns each on the console). */
static int l_light(lua_State *L) {
    int x = num(L, 1), y = num(L, 2), r = num(L, 3);
    lua_Integer col = luaL_checkinteger(L, 4);
    if (r < 1 || nquad == OV_EXT) return 0;
    if (r > 400) r = 400;
    float intensity = 1;
    bool sub = false, cone = false;
    float angle = 0, width = 360;
    if (lua_istable(L, 5)) {
        lua_getfield(L, 5, "intensity"), intensity = clampf(fin(luaL_optnumber(L, -1, 1)), 0, 2), lua_pop(L, 1);
        lua_getfield(L, 5, "sub"), sub = lua_toboolean(L, -1), lua_pop(L, 1);
        lua_getfield(L, 5, "cone");
        if (lua_istable(L, -1)) {
            cone = true;
            lua_getfield(L, -1, "angle"), angle = fin(luaL_optnumber(L, -1, 0)), lua_pop(L, 1);
            lua_getfield(L, -1, "width"), width = clampf(fin(luaL_optnumber(L, -1, 60)), 2, 340), lua_pop(L, 1);
        }
        lua_pop(L, 1);
    }
    ov_cmd *c = ov_add(OV_LIGHT);
    if (!c) return 0;
    c->x = i16(x), c->y = i16(y), c->w = i16(r);
    ov_quad[nquad].light[0][0] = (uint8_t)(col >> 16), ov_quad[nquad].light[0][1] = (uint8_t)(col >> 8), ov_quad[nquad].light[0][2] = (uint8_t)col;
    ov_quad[nquad].mode = sub ? BLEND_SUB : BLEND_ADD;
    ov_quad[nquad].alpha = (uint8_t)(clampf(intensity, 0, 1) * 255 + 0.5f); /* (above 1: the colour itself brighter, see below) */
    ov_quad[nquad].lights = cone;
    if (intensity > 1) { /* brighter than the colour: its channels scaled up, held to full */
        for (int i = 0; i < 3; i++) ov_quad[nquad].light[0][i] = (uint8_t)clampf(ov_quad[nquad].light[0][i] * intensity, 0, 255);
        ov_quad[nquad].alpha = 255;
    }
    const float rad = angle * 3.14159265f / 180.0f, half = width * 3.14159265f / 360.0f;
    ov_quad[nquad].xy[0] = (int16_t)(cosf(rad) * 16384), ov_quad[nquad].xy[1] = (int16_t)(sinf(rad) * 16384);
    ov_quad[nquad].xy[2] = (int16_t)(cosf(half) * 16384), ov_quad[nquad].xy[3] = (int16_t)(cosf(half * 0.66f) * 16384);
    c->ext = (uint8_t)(++nquad);
    commit(c, 0, 0);
    return 0;
}

/* grad(x, y, w, h, c1, c2 [, {across, dither, alpha, add, sub, quarter}]): a box shaded from c1 at its top to c2 at its
 * bottom (across: left to right): a sky, a vignette, a shaft of light (with add), a shadow (with sub) */
static int l_grad(lua_State *L) {
    int x = num(L, 1), y = num(L, 2), w = num(L, 3), h = num(L, 4);
    lua_Integer c1 = luaL_checkinteger(L, 5), c2 = luaL_checkinteger(L, 6);
    if (w <= 0 || h <= 0 || nquad == OV_EXT) return 0;
    img_opts o = {.scale = 1, .alpha = 1};
    bool across = false, dither = false;
    if (lua_istable(L, 7)) {
        img_options(L, 7, &o);
        lua_getfield(L, 7, "across"), across = lua_toboolean(L, -1), lua_pop(L, 1);
        lua_getfield(L, 7, "dither"), dither = lua_toboolean(L, -1), lua_pop(L, 1);
    }
    ov_cmd *c = ov_add(OV_GRAD);
    if (!c) return 0;
    c->x = i16(x), c->y = i16(y), c->w = i16(w), c->h = i16(h);
    ov_quad[nquad].light[0][0] = (uint8_t)(c1 >> 16), ov_quad[nquad].light[0][1] = (uint8_t)(c1 >> 8), ov_quad[nquad].light[0][2] = (uint8_t)c1;
    ov_quad[nquad].light[1][0] = (uint8_t)(c2 >> 16), ov_quad[nquad].light[1][1] = (uint8_t)(c2 >> 8), ov_quad[nquad].light[1][2] = (uint8_t)c2;
    ov_quad[nquad].lights = across, ov_quad[nquad].dither = dither;
    ov_quad[nquad].mode = o.mode, ov_quad[nquad].alpha = (uint8_t)(o.alpha * 255 + 0.5f);
    /* a dithered box that is not mixed with what is under it: its ramp worked out here, once, not in each of the strips (the dither
     * is in screen rows and columns, so with the camera's shift); a box too big for what is left of the list's room is worked out as it is drawn */
    const int len = across ? w : h, n = len * 4;
    if (dither && ov_quad[nquad].mode == BLEND_ALPHA && ov_quad[nquad].alpha == 255 && len <= 1024 && npts + n <= OV_PTS) {
        uint8_t a1[3] = {ov_quad[nquad].light[0][0], ov_quad[nquad].light[0][1], ov_quad[nquad].light[0][2]};
        uint8_t a2[3] = {ov_quad[nquad].light[1][0], ov_quad[nquad].light[1][1], ov_quad[nquad].light[1][2]};
        gfx_grad_table((uint16_t *)&ov_pts[npts], i16(x - cam_x), i16(y - cam_y), w, h, a1, a2, across);
        c->str = (uint16_t)npts, c->len = (uint16_t)n;
        npts += n;
        c->ext = (uint8_t)(++nquad);
        commit(c, 0, n / 2);
        return 0;
    }
    c->ext = (uint8_t)(++nquad);
    commit(c, 0, 0);
    return 0;
}

/* A list a game gives as a table, or as a function asked for each place: n numbers into out (held to 16 bits). */
static bool numbers_arg(lua_State *L, int idx, int n, int16_t *out, float lo, float hi) {
    if (lua_isfunction(L, idx)) {
        for (int i = 0; i < n; i++) {
            lua_pushvalue(L, idx), lua_pushinteger(L, i);
            lua_call(L, 1, 1);
            out[i] = (int16_t)clampf(fin(luaL_optnumber(L, -1, 0)), lo, hi);
            lua_pop(L, 1);
        }
        return true;
    }
    if (lua_istable(L, idx)) {
        for (int i = 0; i < n; i++) {
            lua_rawgeti(L, idx, i + 1);
            out[i] = (int16_t)clampf(fin(luaL_optnumber(L, -1, 0)), lo, hi);
            lua_pop(L, 1);
        }
        return true;
    }
    return false;
}

/* warp(id, x, y, {frame, rows, cols, wrap}): the picture with each row j moved right by rows[j] pixels and then each column i moved
 * down by cols[i] (a table, or a function asked for j or i from 0): water that ripples, heat, a flag, a panorama going round
 * (wrap = true). The Saturn's line and column scroll, at the full screen's resolution. */
static int l_warp(lua_State *L) {
    const char *id = luaL_checkstring(L, 1);
    asset *a = safe_name(id) ? gfx_asset(id) : NULL;
    const int x = num(L, 2), y = num(L, 3);
    if (!a || a->missing || nquad == OV_EXT || !gfx_pixels(a) || !lua_istable(L, 4)) return 0;
    const int W = a->w, H = a->h;
    int16_t rows[1024], cols[1024];
    bool have_rows = false, have_cols = false, wrap = false;
    lua_Integer frame = 0;
    lua_getfield(L, 4, "frame"), frame = luaL_optinteger(L, -1, 0), lua_pop(L, 1);
    lua_getfield(L, 4, "wrap"), wrap = lua_toboolean(L, -1), lua_pop(L, 1);
    lua_getfield(L, 4, "rows"), have_rows = H <= 1024 && numbers_arg(L, lua_gettop(L), H, rows, -2000, 2000), lua_pop(L, 1);
    lua_getfield(L, 4, "cols"), have_cols = W <= 1024 && numbers_arg(L, lua_gettop(L), W, cols, -2000, 2000), lua_pop(L, 1);
    const int n16 = ((have_rows ? H : 0) + (have_cols ? W : 0) + 1) & ~1;
    if (npts + n16 > OV_PTS) return 0;
    ov_cmd *c = ov_add(OV_WARP);
    if (!c) return 0;
    int rmin = 0, rmax = 0, cmin = 0, cmax = 0;
    for (int j = 0; have_rows && j < H; j++) rmin = rows[j] < rmin ? rows[j] : rmin, rmax = rows[j] > rmax ? rows[j] : rmax;
    for (int i = 0; have_cols && i < W; i++) cmin = cols[i] < cmin ? cols[i] : cmin, cmax = cols[i] > cmax ? cols[i] : cmax;
    const int bx = wrap ? 0 : (rmin < 0 ? rmin : 0), by = cmin < 0 ? cmin : 0;
    c->a = a, c->frame = (int16_t)(frame < 0 || frame >= a->frames ? 0 : frame);
    c->x = i16(x + bx), c->y = i16(y + by);
    c->w = i16(W + (wrap ? 0 : (rmax > 0 ? rmax : 0)) - bx), c->h = i16(H + (cmax > 0 ? cmax : 0) - by);
    c->str = (uint16_t)npts, c->len = (uint16_t)(have_rows ? H : 0);
    memset(&ov_pts[npts], 0, (size_t)n16 * sizeof(int16_t));
    if (have_rows) memcpy(&ov_pts[npts], rows, (size_t)H * sizeof(int16_t));
    if (have_cols) memcpy(&ov_pts[npts + (have_rows ? H : 0)], cols, (size_t)W * sizeof(int16_t));
    npts += n16;
    ov_quad[nquad].xy[0] = (int16_t)-bx, ov_quad[nquad].xy[1] = (int16_t)-by;
    ov_quad[nquad].lights = have_rows, ov_quad[nquad].dither = have_cols, ov_quad[nquad].mode = wrap ? 1 : 0;
    c->ext = (uint8_t)(++nquad);
    commit(c, 0, n16 / 2);
    return 0;
}

/* linetint(x, y, w, h, colours [, {add, sub, alpha, lay}]): each row of the box with a colour of its own (a table of 0xRRGGBB, or
 * a function asked for each row from 0), added to what is there (add), taken from it (sub), mixed at alpha, or laid as it is
 * (lay): a sunset down a wall, a flash up a floor, the Saturn's colour offset for each line. */
static int l_linetint(lua_State *L) {
    const int x = num(L, 1), y = num(L, 2), w = num(L, 3), h = num(L, 4);
    if (w <= 0 || h <= 0 || h > 512 || nquad == OV_EXT || npts + ((h + 1) & ~1) > OV_PTS) return 0;
    uint16_t col[512];
    if (lua_isfunction(L, 5)) {
        for (int j = 0; j < h; j++) {
            lua_pushvalue(L, 5), lua_pushinteger(L, j);
            lua_call(L, 1, 1);
            col[j] = to565(luaL_optinteger(L, -1, 0));
            lua_pop(L, 1);
        }
    } else {
        luaL_checktype(L, 5, LUA_TTABLE);
        for (int j = 0; j < h; j++) {
            lua_rawgeti(L, 5, j + 1);
            col[j] = to565(luaL_optinteger(L, -1, 0));
            lua_pop(L, 1);
        }
    }
    int mode = BLEND_ADD;
    float alpha = 1;
    if (lua_istable(L, 6)) {
        lua_getfield(L, 6, "sub"), mode = lua_toboolean(L, -1) ? BLEND_SUB : mode, lua_pop(L, 1);
        lua_getfield(L, 6, "lay"), mode = lua_toboolean(L, -1) ? 4 : mode, lua_pop(L, 1);
        lua_getfield(L, 6, "alpha");
        if (!lua_isnil(L, -1)) alpha = clampf(fin(luaL_checknumber(L, -1)), 0, 1), mode = mode == BLEND_ADD ? 3 : mode;
        lua_pop(L, 1);
    }
    ov_cmd *c = ov_add(OV_LINES);
    if (!c) return 0;
    const int n16 = (h + 1) & ~1;
    c->x = i16(x), c->y = i16(y), c->w = i16(w), c->h = i16(h), c->str = (uint16_t)npts, c->len = (uint16_t)h;
    memset(&ov_pts[npts], 0, (size_t)n16 * sizeof(int16_t));
    memcpy(&ov_pts[npts], col, (size_t)h * sizeof(uint16_t));
    npts += n16;
    ov_quad[nquad].mode = (uint8_t)mode, ov_quad[nquad].alpha = (uint8_t)(alpha * 255 + 0.5f);
    c->ext = (uint8_t)(++nquad);
    commit(c, 0, n16 / 2);
    return 0;
}

/* quad(id, x1, y1, x2, y2, x3, y3, x4, y4 [, {frame, alpha, add, sub, quarter, light, lights, dither, mesh, uv}]): the picture's
 * frame on four corners, in the picture's own order (top-left, top-right, bottom-right, bottom-left): a Saturn
 * distorted sprite, a PlayStation textured quad. light = 0xRRGGBB lights it by that colour (0x808080 as it is, up to
 * 0xFFFFFF twice as bright); lights = {c1, c2, c3, c4} one per corner, blending across. */
static int l_quad(lua_State *L) {
    const char *id = luaL_checkstring(L, 1);
    asset *a = safe_name(id) ? gfx_asset(id) : NULL;
    int16_t xy[8];
    for (int i = 0; i < 8; i++) {
        float v = clampf(fin(luaL_checknumber(L, 2 + i)), -2000, 2000); /* (the rasterizer's whole numbers stay in range) */
        xy[i] = (int16_t)floorf(v * 8 + 0.5f);
    }
    if (!a || a->missing || nquad == OV_EXT || !gfx_pixels(a)) return 0;
    img_opts o = {.scale = 1, .alpha = 1};
    bool lights = false, dither = false, mesh = false, has_uv = false;
    int persp = 0;
    uint8_t light[4][3] = {{0}};
    int16_t uv8[8];
    if (lua_istable(L, 10)) {
        img_options(L, 10, &o);
        lua_getfield(L, 10, "dither"), dither = lua_toboolean(L, -1), lua_pop(L, 1);
        lua_getfield(L, 10, "mesh"), mesh = lua_toboolean(L, -1), lua_pop(L, 1);
        lua_getfield(L, 10, "uv");
        if (!lua_isnil(L, -1)) {
            luaL_checktype(L, -1, LUA_TTABLE);
            has_uv = true;
            for (int i = 0; i < 8; i++) {
                lua_rawgeti(L, -1, i + 1);
                uv8[i] = (int16_t)floorf(clampf(fin(luaL_checknumber(L, -1)), -2000, 2000) * 8 + 0.5f);
                lua_pop(L, 1);
            }
        }
        lua_pop(L, 1);
        lua_getfield(L, 10, "persp");
        persp = lua_isboolean(L, -1) ? lua_toboolean(L, -1) : (int)clampf(fin(luaL_optnumber(L, -1, 0)), 0, 16);
        lua_pop(L, 1);
        lua_getfield(L, 10, "light");
        if (!lua_isnil(L, -1)) {
            lua_Integer rgb = luaL_checkinteger(L, -1);
            lights = true;
            for (int i = 0; i < 4; i++) light[i][0] = (uint8_t)(rgb >> 16), light[i][1] = (uint8_t)(rgb >> 8), light[i][2] = (uint8_t)rgb;
        }
        lua_pop(L, 1);
        lua_getfield(L, 10, "lights");
        if (lua_istable(L, -1)) {
            lights = true;
            for (int i = 0; i < 4; i++) {
                lua_rawgeti(L, -1, i + 1);
                lua_Integer rgb = luaL_optinteger(L, -1, 0x808080);
                lua_pop(L, 1);
                light[i][0] = (uint8_t)(rgb >> 16), light[i][1] = (uint8_t)(rgb >> 8), light[i][2] = (uint8_t)rgb;
            }
        }
        lua_pop(L, 1);
    }
    if (has_uv && npts + 8 > OV_PTS) return 0;
    ov_cmd *c = ov_add(OV_QUAD);
    if (!c) return 0;
    c->a = a, c->frame = (int16_t)(o.frame < 0 || o.frame >= a->frames ? 0 : o.frame);
    memcpy(ov_quad[nquad].xy, xy, sizeof xy), memcpy(ov_quad[nquad].light, light, sizeof light);
    ov_quad[nquad].lights = lights, ov_quad[nquad].dither = dither && lights, ov_quad[nquad].mesh = mesh;
    ov_quad[nquad].mode = o.mode, ov_quad[nquad].alpha = (uint8_t)(o.alpha * 255 + 0.5f), ov_quad[nquad].persp = (uint8_t)persp;
    /* shortcut: custom UV can cover only part of a picture, so the whole-frame mip ratio would overblur it. */
    ov_quad[nquad].mip = has_uv ? NULL : gfx_quad_mip(a, c->frame, xy);
    if (has_uv) c->str = (uint16_t)npts, c->len = 1, memcpy(ov_pts + npts, uv8, sizeof uv8), npts += 8;
    c->ext = (uint8_t)(++nquad);
    commit(c, 0, has_uv ? 4 : 0);
    return 0;
}

/* mesh_new(verts, faces): a model kept for mesh(), its number. verts = {{x, y, z}, ...}; faces = {{a, b, c, d [, uv = {u1, v1, ... u4, v4}]}, ...}
 * with vertex numbers from 1, in the order quad() takes corners (a triangle gives three, and three uv pairs); uv in texels, on every
 * face or on none (then the whole picture is on each). Up to MESH_MAX_VERTS vertices, MESH_MAX_FACES faces, MESH_SLOTS models. */
static int l_mesh_new(lua_State *L) {
    luaL_checktype(L, 1, LUA_TTABLE), luaL_checktype(L, 2, LUA_TTABLE);
    const int nv = (int)lua_rawlen(L, 1), nf = (int)lua_rawlen(L, 2);
    if (nv < 1 || nv > MESH_MAX_VERTS) return luaL_error(L, "mesh_new: 1 to %d vertices, not %d", MESH_MAX_VERTS, nv);
    if (nf < 1 || nf > MESH_MAX_FACES) return luaL_error(L, "mesh_new: 1 to %d faces, not %d", MESH_MAX_FACES, nf);
    if (nmodels == MESH_SLOTS) return luaL_error(L, "mesh_new: a game can keep %d meshes", MESH_SLOTS);
    float *v = lua_newuserdatauv(L, sizeof(float) * 3 * (size_t)nv, 0); /* (the Lua state frees them if an error is raised) */
    uint16_t *idx = lua_newuserdatauv(L, sizeof(uint16_t) * 4 * (size_t)nf, 0);
    float *uv = lua_newuserdatauv(L, sizeof(float) * 8 * (size_t)nf, 0);
    for (int i = 0; i < nv; i++) {
        lua_rawgeti(L, 1, i + 1);
        luaL_checktype(L, -1, LUA_TTABLE);
        for (int k = 0; k < 3; k++) lua_rawgeti(L, -1, k + 1), v[3 * i + k] = fin(luaL_checknumber(L, -1)), lua_pop(L, 1);
        lua_pop(L, 1);
    }
    int with_uv = 0;
    for (int i = 0; i < nf; i++) {
        lua_rawgeti(L, 2, i + 1);
        luaL_checktype(L, -1, LUA_TTABLE);
        for (int k = 0; k < 4; k++) {
            lua_rawgeti(L, -1, k + 1);
            lua_Integer n = k == 3 && lua_isnil(L, -1) ? idx[4 * i + 2] + 1 : luaL_checkinteger(L, -1); /* (a triangle repeats its last) */
            if (n < 1 || n > nv) return luaL_error(L, "mesh_new: face %d names vertex %d, of %d", i + 1, (int)n, nv);
            idx[4 * i + k] = (uint16_t)(n - 1);
            lua_pop(L, 1);
        }
        lua_getfield(L, -1, "uv");
        if (lua_istable(L, -1)) {
            const int n = (int)lua_rawlen(L, -1);
            if (n != 6 && n != 8) return luaL_error(L, "mesh_new: face %d: uv takes 6 numbers (a triangle) or 8", i + 1);
            for (int k = 0; k < 8; k++) {
                lua_rawgeti(L, -1, k < n ? k + 1 : n - 1 + (k & 1)); /* a triangle's fourth corner is its third */
                uv[8 * i + k] = fin(luaL_checknumber(L, -1));
                lua_pop(L, 1);
            }
            with_uv++;
        }
        lua_pop(L, 2);
    }
    if (with_uv && with_uv != nf) return luaL_error(L, "mesh_new: give uv to every face or to none (%d of %d have it)", with_uv, nf);
    mesh_model *m = mesh_model_new(v, nv, idx, with_uv ? uv : NULL, nf);
    if (!m) return luaL_error(L, "mesh_new: out of memory");
    models[nmodels++] = m;
    lua_pushinteger(L, nmodels);
    return 1;
}

static float opt_num(lua_State *L, int t, const char *k, float d) {
    lua_getfield(L, t, k);
    const float v = lua_isnil(L, -1) ? d : (float)fin(luaL_checknumber(L, -1));
    lua_pop(L, 1);
    return v;
}

static void opt_vec3(lua_State *L, int t, const char *k, float out[3]) {
    lua_getfield(L, t, k);
    if (lua_istable(L, -1))
        for (int i = 0; i < 3; i++) {
            lua_rawgeti(L, -1, i + 1);
            if (!lua_isnil(L, -1)) out[i] = (float)fin(luaL_checknumber(L, -1));
            lua_pop(L, 1);
        }
    lua_pop(L, 1);
}

/* mesh(mesh, id, {pos = {x, y, z}, rot = {rx, ry, rz}, scale, focal, cx, cy, near, light, fade, snap, cull, dither, frame}): the model
 * turned, projected, culled, lit and sorted in C and drawn far to near with the picture on every face; returns how many faces show.
 * light = true or {dir = {x, y, z}, ambient, gain}: ambient + gain * (dir . normal), dir toward the lamp in camera space (as
 * the PlayStation's GTE did). fade = {near, far}: full light at near, black at far. */
static int l_mesh(lua_State *L) {
    const lua_Integer h = luaL_checkinteger(L, 1);
    if (h < 1 || h > nmodels) return luaL_error(L, "mesh: no mesh %d (mesh_new gives the numbers)", (int)h);
    const char *id = luaL_checkstring(L, 2);
    asset *a = safe_name(id) ? gfx_asset(id) : NULL;
    if (!a || a->missing || !gfx_pixels(a) || nov == OV_MAX || nmf == MESH_POOL) return lua_pushinteger(L, 0), 1;
    mesh_params p = {.pos = {0, 0, 400}, .scale = 1, .focal = 160, .cx = 240, .cy = 160, .near = 1, .cull = true,
                     .light_dir = {-0.5f, -0.5f, -0.5f}, .ambient = 0.25f, .gain = 0.75f};
    bool dither = true;
    int frame = 0;
    if (lua_istable(L, 3)) {
        opt_vec3(L, 3, "pos", p.pos), opt_vec3(L, 3, "rot", p.rot);
        p.scale = opt_num(L, 3, "scale", 1), p.focal = opt_num(L, 3, "focal", 160), p.near = opt_num(L, 3, "near", 1);
        p.cx = opt_num(L, 3, "cx", 240), p.cy = opt_num(L, 3, "cy", 160);
        frame = (int)opt_num(L, 3, "frame", 0);
        lua_getfield(L, 3, "snap"), p.snap = lua_toboolean(L, -1), lua_pop(L, 1);
        lua_getfield(L, 3, "cull"), p.cull = lua_isnil(L, -1) ? true : lua_toboolean(L, -1), lua_pop(L, 1);
        lua_getfield(L, 3, "dither"), dither = lua_isnil(L, -1) ? true : lua_toboolean(L, -1), lua_pop(L, 1);
        lua_getfield(L, 3, "light");
        if (!lua_isnil(L, -1) && lua_toboolean(L, -1)) {
            p.lit = true;
            if (lua_istable(L, -1)) {
                opt_vec3(L, lua_gettop(L), "dir", p.light_dir);
                p.ambient = opt_num(L, lua_gettop(L), "ambient", p.ambient), p.gain = opt_num(L, lua_gettop(L), "gain", p.gain);
            }
        }
        lua_pop(L, 1);
        lua_getfield(L, 3, "fade");
        if (lua_istable(L, -1)) {
            p.fade = true;
            lua_rawgeti(L, -1, 1), p.fade0 = (float)fin(luaL_checknumber(L, -1)), lua_pop(L, 1);
            lua_rawgeti(L, -1, 2), p.fade1 = (float)fin(luaL_checknumber(L, -1)), lua_pop(L, 1);
        }
        lua_pop(L, 1);
    }
    int bbox[4];
    const int n = mesh_build(models[h - 1], &p, mfaces + nmf, MESH_POOL - nmf, bbox);
    ov_cmd *c = n ? ov_add(OV_MESH) : NULL;
    if (!c) return lua_pushinteger(L, 0), 1;
    c->a = a, c->frame = (int16_t)(frame < 0 || frame >= a->frames ? 0 : frame);
    c->str = (uint16_t)nmf, c->len = (uint16_t)n, c->flip = (uint8_t)((p.lit || p.fade ? 1 : 0) | (dither ? 2 : 0));
    for (int i = 0; i < n; i++) /* (a face with its own uv is sampled from the whole picture, as quad does) */
        if (!mfaces[nmf + i].uv) mfaces[nmf + i].mip = gfx_quad_mip(a, c->frame, mfaces[nmf + i].xy);
    c->x = i16(bbox[0]), c->y = i16(bbox[1]), c->w = i16(bbox[2] - bbox[0]), c->h = i16(bbox[3] - bbox[1]);
    nmf += n;
    commit(c, 0, 0);
    lua_pushinteger(L, n);
    return 1;
}

/* frame(id, x, y, w, h [, scale [, frame]]): a box drawn from the picture's thirds: its corners once, its edges and
 * middle repeated (a nine-slice frame, as GB Studio's frame.png or a windowskin) */
static int l_frame(lua_State *L) {
    const char *id = luaL_checkstring(L, 1);
    asset *a = safe_name(id) ? gfx_asset(id) : NULL;
    ov_cmd *c = !a || a->missing || !gfx_pixels(a) ? NULL : ov_add(OV_NINE); /* (a packed one: unpacked, once) */
    if (!c) return 0;
    c->a = a, c->x = i16(num(L, 2)), c->y = i16(num(L, 3)), c->w = i16(num(L, 4)), c->h = i16(num(L, 5));
    lua_Integer k = luaL_optinteger(L, 6, 1), f = luaL_optinteger(L, 7, 0);
    c->scale = (uint8_t)(k < 1 ? 1 : k > 8 ? 8 : k);
    c->frame = (int16_t)(f < 0 || f >= a->frames ? 0 : f);
    commit(c, 0, 0);
    return 0;
}

/* ------------------------------------------------------------------ free drawing */

static int l_pset(lua_State *L) { /* pset(x, y [, colour]) */
    ov_cmd *c = ov_add(OV_FILL);
    if (!c) return 0;
    c->x = i16(num(L, 1)), c->y = i16(num(L, 2)), c->w = c->h = 1;
    if (!colour_at(L, 3, 0xFFFFFF, &c->color)) return nov--, 0;
    commit(c, 0, 0);
    return 0;
}

static int l_line(lua_State *L) { /* line(x0, y0, x1, y1 [, colour]) */
    ov_cmd *c = ov_add(OV_LINE);
    if (!c) return 0;
    c->x = i16(num(L, 1)), c->y = i16(num(L, 2)), c->w = i16(num(L, 3)), c->h = i16(num(L, 4));
    if (!colour_at(L, 5, 0xFFFFFF, &c->color)) return nov--, 0;
    commit(c, 0, 0);
    return 0;
}

static int l_circ(lua_State *L) { /* circ(x, y, r [, colour [, filled = true]]) */
    ov_cmd *c = ov_add(OV_CIRC);
    if (!c) return 0;
    int r = num(L, 3);
    c->x = i16(num(L, 1)), c->y = i16(num(L, 2)), c->w = (int16_t)(r < 0 ? 0 : r > 2048 ? 2048 : r);
    c->h = lua_isnoneornil(L, 5) || lua_toboolean(L, 5);
    if (!colour_at(L, 4, 0xFFFFFF, &c->color)) return nov--, 0;
    commit(c, 0, 0);
    return 0;
}

static int polygon(lua_State *L, const int *xy, int n, int colour_arg) { /* n corners; the colour, then filled */
    if (npts + 2 * n > OV_PTS) return 0;
    ov_cmd *c = ov_add(OV_POLY);
    if (!c) return 0;
    for (int i = 0; i < 2 * n; i++) ov_pts[npts + i] = i16(xy[i]);
    c->str = (uint16_t)npts, c->len = (uint16_t)n, npts += 2 * n;
    c->frame = lua_isnoneornil(L, colour_arg + 1) || lua_toboolean(L, colour_arg + 1);
    if (!colour_at(L, colour_arg, 0xFFFFFF, &c->color)) return nov--, npts -= 2 * n, 0;
    commit(c, 0, n);
    return 0;
}

static int l_tri(lua_State *L) { /* tri(x0, y0, x1, y1, x2, y2 [, colour [, filled = true]]) */
    int xy[6];
    for (int i = 0; i < 6; i++) xy[i] = num(L, i + 1);
    return polygon(L, xy, 3, 7);
}

static int l_poly(lua_State *L) { /* poly({x0, y0, x1, y1, ...} [, colour [, filled = true]]) */
    luaL_checktype(L, 1, LUA_TTABLE);
    int n = (int)(lua_rawlen(L, 1) / 2), xy[2 * GFX_POLY_MAX];
    if (n > GFX_POLY_MAX) return luaL_error(L, "poly: %d corners at most", GFX_POLY_MAX);
    for (int i = 0; i < 2 * n; i++) {
        lua_rawgeti(L, 1, i + 1);
        xy[i] = (int)floorf(fin(luaL_checknumber(L, -1)));
        lua_pop(L, 1);
    }
    return n ? polygon(L, xy, n, 2) : 0;
}

/* A swarm's points (lua_swarm.c), each drawn as the picture centred on it: one command for all of them. Only those
 * on the screen (or the canvas) are kept, in the frame's corners (ov_pts); past their room, the rest are not drawn. */
void draw_points(const asset *a, int frame, const float *x, const float *y, int n) {
    ov_cmd *c = ov_add(OV_POINTS);
    if (!c) return;
    const int w = target ? target->w : SCREEN_W, h = target ? target->h : SCREEN_H;
    const int ox = cam_x + a->w / 2, oy = cam_y + a->h / 2;
    c->a = a, c->frame = (int16_t)frame, c->str = (uint16_t)npts;
    for (int i = 0; i < n && npts + 2 <= OV_PTS; i++) {
        int px = (int)floorf(x[i]) - ox, py = (int)floorf(y[i]) - oy;
        if (px + a->w <= 0 || px >= w || py + a->h <= 0 || py >= h) continue;
        ov_pts[npts++] = i16(px), ov_pts[npts++] = i16(py);
    }
    c->len = (uint16_t)((npts - c->str) / 2);
    if (!c->len) {
        nov--;
        return;
    }
    c->x = i16(cam_x), c->y = i16(cam_y); /* (commit takes the camera off x, y: the points have it off already) */
    commit(c, 0, c->len);
}

static int l_cls(lua_State *L) { /* cls([colour]): the canvas see-through (or that colour); the screen black */
    if (!target) {
        ov_cmd *c = ov_add(OV_FILL);
        if (!c) return 0;
        c->x = i16(cam_x), c->y = i16(cam_y), c->w = SCREEN_W, c->h = SCREEN_H; /* the camera moves it back to 0, 0 */
        if (!colour_at(L, 1, 0x000000, &c->color)) return nov--, 0;
        commit(c, 0, 0);
        return 0;
    }
    uint16_t col = CANVAS_KEY;
    if (!lua_isnoneornil(L, 1)) colour_at(L, 1, 0, &col);
    size_t npx = (size_t)target->w * target->h;
    uint32_t two = (uint32_t)col << 16 | col, *p = (uint32_t *)target->pixels; /* two pixels a write: on the console */
    for (size_t i = 0; i < npx / 2; i++) p[i] = two;                       /* the canvas is in PSRAM, writes are dear */
    if (npx & 1) target->pixels[npx - 1] = col;
    target->gen++;
    memset(target->mask, col == CANVAS_KEY ? 0 : 0xFF, (size_t)((target->w + 7) / 8) * target->h);
    return 0;
}

static int l_pget(lua_State *L) { /* pget(x, y [, picture]) -> 0xRRGGBB, or nil where it is see-through or outside */
    asset *a = target;
    if (!lua_isnoneornil(L, 3)) {
        const char *id = luaL_checkstring(L, 3);
        a = safe_name(id) ? gfx_asset_opt(id) : NULL;
    }
    int x = num(L, 1), y = num(L, 2);
    if (!a || a->missing || x < 0 || y < 0 || x >= a->w || y >= a->h || !gfx_pixels(a)) return lua_pushnil(L), 1;
    uint16_t v = a->pixels[y * a->w + x];
    if (a->canvas ? v == CANVAS_KEY : !gfx_opaque(a, 0, x, y)) return lua_pushnil(L), 1;
    unsigned r = v >> 11, g = v >> 5 & 63, b = v & 31;
    lua_pushinteger(L, (lua_Integer)((r << 3 | r >> 2) << 16 | (g << 2 | g >> 4) << 8 | (b << 3 | b >> 2)));
    return 1;
}

static int l_canvas(lua_State *L) { /* canvas(id, w, h) or canvas(id, picture): made (or cleared) see-through, or a copy */
    const char *id = luaL_checkstring(L, 1);
    if (!safe_name(id) || strchr(id, '/') || strlen(id) >= sizeof(((asset *)0)->id))
        return luaL_error(L, "canvas \"%s\": not a picture name", id);
    asset *from = NULL, *a;
    int w = 0, h = 0;
    if (lua_type(L, 2) == LUA_TSTRING) {
        const char *src = lua_tostring(L, 2);
        from = safe_name(src) ? gfx_asset_opt(src) : NULL;
        if (from && !from->missing && !gfx_pixels(from)) return luaL_error(L, "canvas \"%s\": no memory to copy \"%s\"", id, src);
        if (!from || from->missing) return luaL_error(L, "canvas \"%s\": no picture \"%s\" to copy", id, src);
    } else {
        w = num(L, 2), h = num(L, 3);
    }
    const char *why = gfx_canvas(id, w, h, from, &a);
    if (why) return luaL_error(L, "canvas \"%s\": %s", id, why);
    return 0;
}

static int l_target(lua_State *L) { /* target(canvas) draws on it from now on; target() on the screen again */
    asset *a = NULL;
    if (!lua_isnoneornil(L, 1)) {
        const char *id = luaL_checkstring(L, 1);
        a = gfx_find(id);
        if (!a || !a->canvas) return luaL_error(L, "target \"%s\": not a canvas (make one with canvas())", id);
    }
    draw_flush(); /* what was drawn on a canvas is there for the next picture that copies it, in this same call */
    target = a, cam_x = cam_y = 0, clipping = false; /* each target starts with no camera and no clip */
    if (!a && view_on) draw_set_view(view.x, view.y, view.w, view.h); /* the screen again: the screen it was on */
    return 0;
}

static int l_camera(lua_State *L) { /* camera([x, y]): what is drawn moves by -x, -y */
    cam_x = optnum(L, 1, 0), cam_y = optnum(L, 2, 0);
    if (view_on && !target) cam_x -= view.x, cam_y -= view.y; /* on one of two screens: from its corner */
    return 0;
}

static int l_clip(lua_State *L) { /* clip([x, y, w, h]): only inside it is drawn on; clip() everywhere again */
    if ((clipping = !lua_isnoneornil(L, 1))) {
        int w = num(L, 3), h = num(L, 4);
        clip_r = (screen_rect){i16(num(L, 1)), i16(num(L, 2)), w < 0 ? 0 : w > 4096 ? 4096 : w, h < 0 ? 0 : h > 4096 ? 4096 : h};
    }
    if (view_on && !target) { /* on one of two screens: from its corner, and never past its edge */
        if (clipping) {
            int x0 = clip_r.x + view.x, y0 = clip_r.y + view.y, x1 = x0 + clip_r.w, y1 = y0 + clip_r.h;
            x0 = x0 > view.x ? x0 : view.x, y0 = y0 > view.y ? y0 : view.y;
            x1 = x1 < view.x + view.w ? x1 : view.x + view.w, y1 = y1 < view.y + view.h ? y1 : view.y + view.h;
            clip_r = (screen_rect){i16(x0), i16(y0), x1 > x0 ? x1 - x0 : 0, y1 > y0 ? y1 - y0 : 0};
        } else clip_r = view;
        clipping = true;
    }
    return 0;
}

static int l_imgsize(lua_State *L) { /* imgsize(picture) -> w, h, frames, or nil */
    const char *id = luaL_checkstring(L, 1);
    asset *a = safe_name(id) ? gfx_asset_opt(id) : NULL;
    if (!a || a->missing) return lua_pushnil(L), 1;
    if (a->oom) { /* no memory for it just now, and on its way: the size it will have, not its stand-in's */
        lua_pushinteger(L, a->oom_w), lua_pushinteger(L, a->oom_h), lua_pushinteger(L, a->oom_frames);
        return 3;
    }
    lua_pushinteger(L, a->w), lua_pushinteger(L, a->h), lua_pushinteger(L, a->frames);
    return 3;
}

/* preload({images = {"BG_BAR", ...}, sounds = {"SFX_GLASS", ...}}) -> how many of the pictures there are. Reads them now,
 * so the first time they are drawn or played nothing waits for the card: a room's, behind the curtain that closes. */
static int l_preload(lua_State *L) {
    luaL_checktype(L, 1, LUA_TTABLE);
    int found = 0;
    lua_getfield(L, 1, "images");
    if (lua_istable(L, -1))
        for (int i = 1; i <= (int)lua_rawlen(L, -1) && i <= 256; i++) {
            lua_rawgeti(L, -1, i);
            const char *id = lua_isstring(L, -1) ? lua_tostring(L, -1) : NULL;
            asset *a = id && safe_name(id) ? gfx_asset_opt(id) : NULL;
            found += a && !a->missing;
            lua_pop(L, 1);
        }
    lua_pop(L, 1);
    lua_getfield(L, 1, "sounds");
    if (lua_istable(L, -1))
        for (int i = 1; i <= (int)lua_rawlen(L, -1) && i <= 256; i++) {
            lua_rawgeti(L, -1, i);
            const char *id = lua_isstring(L, -1) ? lua_tostring(L, -1) : NULL;
            if (id && safe_name(id)) audio_preload(id);
            lua_pop(L, 1);
        }
    lua_pop(L, 1);
    lua_pushinteger(L, found);
    return 1;
}

/* ------------------------------------------------------------------ the list's life */

void draw_frame_begin(void) { /* each _draw starts on the screen, with no camera and no clip */
    frame_no++;
    gfx_new_frame(); /* the pictures this frame asks for stay in memory while it is drawn */
    nseen[frame_no & 1] = 0;
    prof_cur.cmds = nov, prof_cur.slots = nquad; /* the frame before: all its strips are drawn */
    prof_last = prof_cur;
    memset(&prof_cur, 0, sizeof prof_cur);
    nov = ntext = nstyle = nxf = npts = nclip = nlook = nquad = nmf = 0;
    gfx_quad_begin();
    target = NULL, cam_x = cam_y = 0, clipping = false, view_on = false;
}

void draw_set_view(int x, int y, int w, int h) {
    view = (screen_rect){x, y, w, h}, view_on = true;
    cam_x = -x, cam_y = -y;
    clipping = true;
    clip_r = (screen_rect){i16(x), i16(y), w, h};
}

void draw_free(void) {
    draw_frame_begin();
    ndirty = 0;
    pic_reset();
    for (int i = 0; i < nvfont; i++) free(vfont[i].f.bits);
    nvfont = 0;
    for (int i = 0; i < nmodels; i++) mesh_model_free(models[i]), models[i] = NULL;
    nmodels = 0;
}

bool draw_covers_screen(void) {
    const ov_cmd *c = nov ? &ov[0] : NULL;
    int k = c && c->op == OV_IMG ? c->scale : 0;
    bool opaque = c && c->a && (c->a->pk && !c->a->pixels ? c->a->pk_opaque : !c->a->mask);
    return k && !c->ext && !c->flip && opaque && c->x <= 0 && c->y <= 0 && c->x + k * c->a->w >= SCREEN_W &&
           c->y + k * c->a->h >= SCREEN_H;
}

void draw_register(lua_State *L) {
    static const luaL_Reg F[] = {
        {"text", l_text}, {"textw", l_textw}, {"rect", l_rect}, {"box", l_box}, {"shade", l_shade}, {"panel", l_panel},
        {"plate", l_plate}, {"img", l_img}, {"quad", l_quad}, {"mesh_new", l_mesh_new}, {"mesh", l_mesh}, {"grad", l_grad}, {"light", l_light}, {"warp", l_warp}, {"linetint", l_linetint}, {"frame", l_frame}, {"pset", l_pset}, {"pget", l_pget}, {"line", l_line},
        {"circ", l_circ}, {"tri", l_tri}, {"poly", l_poly}, {"cls", l_cls}, {"canvas", l_canvas}, {"target", l_target},
        {"camera", l_camera}, {"clip", l_clip}, {"imgsize", l_imgsize}, {"preload", l_preload}, {NULL, NULL}};
    lua_pushglobaltable(L);
    luaL_setfuncs(L, F, 0);
    lua_pushinteger(L, CLEAR);
    lua_setfield(L, -2, "CLEAR");
    lua_pop(L, 1);
}
