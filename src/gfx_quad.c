/* A picture's frame laid on any four corners: a Saturn VDP1 distorted sprite, a PlayStation textured quad. Two
 * triangles, each with the picture's coordinates (and, if asked, a colour to light it by) changing evenly across it,
 * as the PlayStation drew them, with no correction for depth.
 *
 * Corners are in eighths of a pixel, so a quad can glide. Whether a pixel is inside a triangle is worked out with
 * whole numbers, at the pixel's centre, with the top-left rule: a pixel on the edge two triangles share belongs to
 * one of them, so the diagonal has neither a hole nor a doubly mixed row (which an add or a sub would show). The
 * screen is drawn in turned strips, so it goes column by column: for each column the rows inside the triangle are
 * found from its three edges, and the picture's row and column are stepped down them in 16.16 fixed point. */
#include <math.h>

#include "gfx_px.h"

/* The PlayStation's 4x4 dither, in 8-bit steps added before a colour is cut to 5 bits (psx-spx, "GPU Rendering
 * Attributes"): lit pixels lose their low bits unevenly instead of in bands. */
static const int8_t PSX_DITHER[16] = {-4, 0, -3, 1, 2, -2, 3, -1, -3, 1, -4, 0, 3, -1, 2, -2};

typedef struct {
    int32_t x, y; /* eighths of a pixel */
    float at[6];  /* the picture's column and row, the light's red, green and blue, and 1/w (perspective; 1 when flat) */
} vertex;

typedef struct {
    int32_t a, b, c; /* the edge function: a X + b Y + c > 0 inside (X, Y in eighths) */
    int32_t bias;    /* 0 on a top or left edge (a pixel exactly on it is in), 1 otherwise */
} edge;

static inline int32_t floor_div32(int32_t a, int32_t b) { /* b > 0 */
    int32_t q = a / b;
    return q - (a % b != 0 && a < 0);
}
static inline int32_t ceil_div32(int32_t a, int32_t b) { return -floor_div32(-a, b); }

/* How the picture's pixel is lit: each colour channel times the light (128 = as it is, up to 255 = twice as bright),
 * held to its range; the dither, if any, added before the low bits go. */
static inline uint16_t lit(uint16_t c, int lr, int lg, int lb, int dither) {
    int r = c >> 11, g = c >> 5 & 63, b = c & 31;
    r = (r << 3 | r >> 2) * lr >> 7, g = (g << 2 | g >> 4) * lg >> 7, b = (b << 3 | b >> 2) * lb >> 7;
    r += dither, g += dither >> 1, b += dither;
    r = r < 0 ? 0 : r > 255 ? 255 : r, g = g < 0 ? 0 : g > 255 ? 255 : g, b = b < 0 ? 0 : b > 255 ? 255 : b;
    return (uint16_t)((r >> 3) << 11 | (g >> 2) << 5 | (b >> 3));
}

typedef struct {
    const uint16_t *src;
    const uint8_t *mask;
    int w, h, stride;
    bool lit, dither;
    int mode;
    unsigned alpha; /* 0..256 */
    bool plain;     /* opaque: no look at what is under it */
    bool persp;     /* at[0], at[1] are the picture's column and row over w, at[5] is 1/w: divided again every few pixels */
} quad_ctx;

/* A column of a quad's triangle, in functions of their own and not inlined: inside the triangle's big loop the compiler ran out
 * of registers and read the column's numbers back from memory for each pixel (about 150 ns a pixel on the console). */
typedef struct { int32_t u, v, lr, lg, lb, du, dv, dlr, dlg, dlb; } col_step;

static __attribute__((noinline)) void col_plain(uint16_t *dst, int ys, int n, int32_t u, int32_t v, int32_t du, int32_t dv,
                                                const quad_ctx *q, bool swap) {
    const uint16_t *src = q->src;
    const int W = q->w, wmax = q->w - 1, hmax = q->h - 1;
    if (swap)
        for (int i = 0; i < n; i++, dst += ys, u += du, v += dv) {
            int iu = u >> 16, iv = v >> 16;
            iu = iu < 0 ? 0 : iu > wmax ? wmax : iu, iv = iv < 0 ? 0 : iv > hmax ? hmax : iv;
            *dst = bswap16(src[iv * W + iu]);
        }
    else
        for (int i = 0; i < n; i++, dst += ys, u += du, v += dv) {
            int iu = u >> 16, iv = v >> 16;
            iu = iu < 0 ? 0 : iu > wmax ? wmax : iu, iv = iv < 0 ? 0 : iv > hmax ? hmax : iv;
            *dst = src[iv * W + iu];
        }
}

static __attribute__((noinline)) void col_general(const surface *s, uint16_t *dst, int ys, int n, int y, int x, const col_step *st,
                                                  const quad_ctx *q) {
    int32_t u = st->u, v = st->v, lr = st->lr, lg = st->lg, lb = st->lb;
    const int32_t du = st->du, dv = st->dv, dlr = st->dlr, dlg = st->dlg, dlb = st->dlb;
    const int W = q->w, H = q->h;
    const uint16_t *src = q->src;
    const uint8_t *mask = q->mask;
    const bool swap = s->swap, plain = q->plain, isLit = q->lit;
    const int8_t *dith = q->dither ? &PSX_DITHER[x & 3] : NULL; /* this column's offsets, 4 apart down the rows */
    for (int i = 0; i < n; i++, y++, dst += ys, u += du, v += dv, lr += dlr, lg += dlg, lb += dlb) {
        int iu = u >> 16, iv = v >> 16;
        if ((unsigned)iu >= (unsigned)W) iu = iu < 0 ? 0 : W - 1;
        if ((unsigned)iv >= (unsigned)H) iv = iv < 0 ? 0 : H - 1;
        if (mask && !(mask[iv * q->stride + (iu >> 3)] & (0x80 >> (iu & 7)))) continue;
        uint16_t c = src[iv * W + iu];
        if (isLit) {
            int r = lr >> 16, g = lg >> 16, b = lb >> 16;
            if ((unsigned)r > 255) r = r < 0 ? 0 : 255;
            if ((unsigned)g > 255) g = g < 0 ? 0 : 255;
            if ((unsigned)b > 255) b = b < 0 ? 0 : 255;
            c = lit(c, r, g, b, dith ? dith[(y & 3) * 4] : 0);
        }
        if (plain) {
            *dst = swap ? bswap16(c) : c;
            continue;
        }
        const uint16_t under = swap ? bswap16(*dst) : *dst;
        *dst = under == CANVAS_KEY ? stored(s, c) : stored(s, mix565(under, c, q->alpha, q->mode));
    }
}

/* A column of a quad in perspective: U/w, V/w and 1/w change evenly down it (they are what is flat on the screen); every 8 pixels the
 * picture's own column and row are worked out from them by a division, and between those they are stepped evenly, as Quake drew its
 * walls (Abrash). The column, a span at a time, goes to col_plain or col_general. */
static __attribute__((noinline)) void col_persp(const surface *s, uint16_t *dst, int ys, int n, int y, int x, const col_step *st,
                                                int32_t iw, int32_t diw, const quad_ctx *q) {
    int32_t uw = st->u, vw = st->v, lr = st->lr, lg = st->lg, lb = st->lb;
    const int32_t duw = st->du, dvw = st->dv;
    const bool fast = q->plain && !q->lit && !q->mask;
    float fi = (float)(iw > 16 ? iw : 16);
    int32_t u0 = (int32_t)((float)uw / fi * 65536.0f), v0 = (int32_t)((float)vw / fi * 65536.0f);
    while (n > 0) {
        const int span = n < 8 ? n : 8;
        uw += duw * span, vw += dvw * span, iw += diw * span;
        fi = (float)(iw > 16 ? iw : 16);
        const int32_t u1 = (int32_t)((float)uw / fi * 65536.0f), v1 = (int32_t)((float)vw / fi * 65536.0f);
        const int32_t du = span == 8 ? (u1 - u0) / 8 : (u1 - u0) / span, dv = span == 8 ? (v1 - v0) / 8 : (v1 - v0) / span;
        if (fast) {
            col_plain(dst, ys, span, u0, v0, du, dv, q, s->swap);
        } else {
            const col_step c = {u0, v0, lr, lg, lb, du, dv, st->dlr, st->dlg, st->dlb};
            col_general(s, dst, ys, span, y, x, &c, q);
            lr += st->dlr * span, lg += st->dlg * span, lb += st->dlb * span;
        }
        dst += ys * span, y += span, n -= span, u0 = u1, v0 = v1;
    }
}

static void triangle(surface *s, const quad_ctx *q, vertex p[3]) {
    int64_t area = (int64_t)(p[1].x - p[0].x) * (p[2].y - p[0].y) - (int64_t)(p[1].y - p[0].y) * (p[2].x - p[0].x);
    if (!area) return;
    if (area < 0) { /* the other way round: the same triangle with two corners swapped */
        vertex t = p[1];
        p[1] = p[2], p[2] = t;
        area = -area;
    }
    edge e[3];
    for (int i = 0; i < 3; i++) {
        const vertex *A = &p[i], *B = &p[(i + 1) % 3];
        e[i].a = -(B->y - A->y), e[i].b = B->x - A->x, e[i].c = (B->y - A->y) * A->x - (B->x - A->x) * A->y;
        e[i].bias = (B->y < A->y || (B->y == A->y && B->x > A->x)) ? 0 : 1; /* left edge: going up; top: going right */
    }
    /* how the picture's coordinates and the light change with a step of one eighth right or down, then per pixel */
    float gx[6], gy[6];
    const float d = (float)area;
    for (int k = 0; k < 6; k++) {
        float a1 = p[1].at[k] - p[0].at[k], a2 = p[2].at[k] - p[0].at[k];
        gx[k] = (a1 * (float)(p[2].y - p[0].y) - a2 * (float)(p[1].y - p[0].y)) / d;
        gy[k] = (a2 * (float)(p[1].x - p[0].x) - a1 * (float)(p[2].x - p[0].x)) / d;
    }
    int x_lo = p[0].x < p[1].x ? p[0].x : p[1].x, x_hi = p[0].x > p[1].x ? p[0].x : p[1].x;
    if (p[2].x < x_lo) x_lo = p[2].x;
    if (p[2].x > x_hi) x_hi = p[2].x;
    int bx0 = floor_div32(x_lo, 8), bx1 = ceil_div32(x_hi, 8) + 1; /* the columns it can touch */
    if (bx0 < s->x0) bx0 = s->x0;
    if (bx1 > s->x0 + s->w) bx1 = s->x0 + s->w;
    const int ys = step_y(s), top = s->y0, bottom = s->y0 + s->h - 1;
    if (bx0 >= bx1) return;
    /* What changes from one column to the next is stepped, not worked out again: a quad cut into bands is many short
     * columns, and a division and some float arithmetic in each cost more than the pixels. For each edge, the rows
     * it lets through come from F = floor(M / B), M = a X + c - bias, B = |b|: M moves by 8a a column, so F moves by
     * a fixed amount and a remainder that carries. The picture's coordinates and the light are kept for row 0 as
     * 32-bit numbers that may wrap (the arithmetic is exact modulo 2^32, and what is wanted fits), moved by a column's
     * step, then taken to the column's first row by its row step. */
    struct { int32_t b, B, F, R, dF, dR, M, dM; } ed[3];
    for (int i = 0; i < 3; i++) {
        ed[i].b = e[i].b, ed[i].B = e[i].b < 0 ? -e[i].b : e[i].b;
        ed[i].dM = 8 * e[i].a;
        ed[i].M = e[i].a * (8 * bx0 + 4) + e[i].c - e[i].bias;
        if (ed[i].B) {
            ed[i].F = floor_div32(ed[i].M, ed[i].B), ed[i].R = ed[i].M - ed[i].F * ed[i].B;
            ed[i].dF = floor_div32(ed[i].dM, ed[i].B), ed[i].dR = ed[i].dM - ed[i].dF * ed[i].B;
        }
    }
    uint32_t col0[6], dcol[6], drow[6];
    for (int k = 0; k < 6; k++) { /* worked out at column 0 and row 0 whatever the strip starts at, so every strip gets
                                   * the very same numbers for a pixel: the value at column x is that plus x steps */
        const double at0 = (double)p[0].at[k] + (double)gx[k] * (double)(4 - p[0].x) + (double)gy[k] * (double)(4 - p[0].y);
        dcol[k] = (uint32_t)(int32_t)(gx[k] * 8.0f * 65536.0f);
        drow[k] = (uint32_t)(int32_t)(gy[k] * 8.0f * 65536.0f);
        col0[k] = (uint32_t)(int64_t)(at0 * 65536.0) + (uint32_t)bx0 * dcol[k];
    }
    for (int x = bx0; x < bx1; x++) {
        int32_t lo = top, hi = bottom; /* the rows (inclusive) inside all three edges */
        bool none = false;
        for (int i = 0; i < 3; i++) {
            if (ed[i].b > 0) {
                const int32_t y = (3 - ed[i].F) >> 3; /* ceil((-F - 4) / 8) */
                if (y > lo) lo = y;
            } else if (ed[i].b < 0) {
                const int32_t y = (ed[i].F - 4) >> 3; /* floor((F - 4) / 8) */
                if (y < hi) hi = y;
            } else if (ed[i].M < 0) { /* a level edge: this column is inside it where -M >= 0 is not (M < 0 means K > 0) */
                none = true;
            }
        }
        /* the next column's state, whether this one draws or not */
        const uint32_t c0[6] = {col0[0], col0[1], col0[2], col0[3], col0[4], col0[5]};
        for (int i = 0; i < 3; i++) {
            ed[i].M += ed[i].dM;
            if (ed[i].B) {
                ed[i].F += ed[i].dF, ed[i].R += ed[i].dR;
                if (ed[i].R >= ed[i].B) ed[i].R -= ed[i].B, ed[i].F++;
            }
        }
        for (int k = 0; k < 6; k++) col0[k] += dcol[k];
        if (none || lo > hi) continue;
        const int32_t at5[5] = {(int32_t)(c0[0] + (uint32_t)lo * drow[0]), (int32_t)(c0[1] + (uint32_t)lo * drow[1]),
                                (int32_t)(c0[2] + (uint32_t)lo * drow[2]), (int32_t)(c0[3] + (uint32_t)lo * drow[3]),
                                (int32_t)(c0[4] + (uint32_t)lo * drow[4])};
        const int32_t dv5[5] = {(int32_t)drow[0], (int32_t)drow[1], (int32_t)drow[2], (int32_t)drow[3], (int32_t)drow[4]};
        int32_t u = at5[0], v = at5[1], lr = at5[2], lg = at5[3], lb = at5[4];
        const int32_t du = dv5[0], dv = dv5[1], dlr = dv5[2], dlg = dv5[3], dlb = dv5[4];
        uint16_t *dst = at(s, x, lo);
        const int n = hi - lo + 1;
        if (q->persp) {
            const col_step st = {u, v, lr, lg, lb, du, dv, dlr, dlg, dlb};
            col_persp(s, dst, ys, n, lo, x, &st, (int32_t)(c0[5] + (uint32_t)lo * drow[5]), (int32_t)drow[5], q);
        } else if (q->plain && !q->lit && !q->mask) col_plain(dst, ys, n, u, v, du, dv, q, s->swap);
        else {
            const col_step st = {u, v, lr, lg, lb, du, dv, dlr, dlg, dlb};
            col_general(s, dst, ys, n, lo, x, &st, q);
        }
    }
}

/* The projective map of the picture's square (u, v in 0..1) onto the four screen points (Heckbert's "Fundamentals of Texture
 * Mapping"): x = (a u + b v + c) / (g u + h v + 1), y = (d u + e v + f) / (g u + h v + 1). False when the points make a
 * parallelogram (or nothing can be done): an affine quad is then already right. */
typedef struct { double a, b, c, d, e, f, g, h; } homography;

static bool make_homography(const int16_t xy8[8], homography *H) {
    double x[4], y[4];
    for (int i = 0; i < 4; i++) x[i] = xy8[2 * i] / 8.0, y[i] = xy8[2 * i + 1] / 8.0;
    const double sx = x[0] - x[1] + x[2] - x[3], sy = y[0] - y[1] + y[2] - y[3];
    if (fabs(sx) < 1e-6 && fabs(sy) < 1e-6) return false;
    const double dx1 = x[1] - x[2], dx2 = x[3] - x[2], dy1 = y[1] - y[2], dy2 = y[3] - y[2];
    const double den = dx1 * dy2 - dx2 * dy1;
    if (fabs(den) < 1e-9) return false;
    H->g = (sx * dy2 - dx2 * sy) / den, H->h = (dx1 * sy - sx * dy1) / den;
    H->a = x[1] - x[0] + H->g * x[1], H->b = x[3] - x[0] + H->h * x[3], H->c = x[0];
    H->d = y[1] - y[0] + H->g * y[1], H->e = y[3] - y[0] + H->h * y[3], H->f = y[0];
    return true;
}

void gfx_quad(surface *s, const asset *a, int frame, const int16_t xy8[8], const uint8_t light[4][3], bool lights,
              int mode, unsigned alpha, bool dither, int persp) {
    if (!a->pixels || frame < 0 || frame >= a->frames) return;
    quad_ctx q = {.src = a->pixels + (size_t)frame * a->w * a->h, .w = a->w, .h = a->h, .stride = (a->w + 7) / 8,
                  .lit = lights, .dither = dither && lights, .mode = mode, .alpha = alpha};
    q.mask = a->mask ? a->mask + (size_t)frame * q.stride * a->h : NULL;
    if (q.mask) { /* a frame with no see-through pixel needs no look at its mask for each pixel */
        const size_t n = (size_t)q.stride * a->h;
        const int tail = a->w & 7; /* the last byte of a row has bits past the picture's width */
        bool all = true;
        for (size_t i = 0; i < n && all; i++) {
            const uint8_t want = (tail && (i + 1) % q.stride == 0) ? (uint8_t)(0xFF << (8 - tail)) : 0xFF;
            all = (q.mask[i] & want) == want;
        }
        if (all) q.mask = NULL;
    }
    q.plain = mode == BLEND_ALPHA && alpha >= 256;
    homography H;
    /* perspective: the four corners as the picture's square seen in perspective (Heckbert's homography). Each corner carries the
     * picture's column and row over its w, and 1/w, the w scaled so the nearest corner's is 1 (so none of them overflows) */
    float iw[4] = {1, 1, 1, 1};
    if (persp && make_homography(xy8, &H)) {
        const double w[4] = {1, H.g + 1, H.g + H.h + 1, H.h + 1};
        const double wmin = fmin(fmin(w[0], w[1]), fmin(w[2], w[3]));
        if (wmin > 1e-6) { /* (a quad that folds over itself has no such map: drawn flat) */
            for (int i = 0; i < 4; i++) iw[i] = (float)(wmin / w[i]);
            q.persp = true;
        }
    }
    /* the corners and what each carries: the picture's own corners, so the frame fills the quad */
    const float tu[4] = {0, (float)a->w, (float)a->w, 0}, tv[4] = {0, 0, (float)a->h, (float)a->h};
    vertex v[4];
    for (int i = 0; i < 4; i++) {
        v[i].x = xy8[2 * i], v[i].y = xy8[2 * i + 1];
        v[i].at[0] = tu[i] * iw[i], v[i].at[1] = tv[i] * iw[i], v[i].at[5] = iw[i];
        for (int k = 0; k < 3; k++) v[i].at[2 + k] = lights ? (float)light[i][k] : 128.0f;
    }
    vertex t1[3] = {v[0], v[1], v[2]}, t2[3] = {v[0], v[2], v[3]};
    triangle(s, &q, t1);
    triangle(s, &q, t2);
}

/* A packed RGB565 into the 32-bit form with each channel apart from the next (blue at 0, red at 11, green at 21), room above
 * each for a carry, as mix565 does: one add or subtract then does all three. */
#define SPREAD 0x07E0F81Fu
#define CARRY_RB 0x00010020u /* the bit above blue (5) and above red (16) */
#define CARRY_G 0x08000000u  /* and above green (27) */

static inline uint16_t unspread(uint32_t v) { return (uint16_t)(v | v >> 16); }

static inline uint16_t add565_sat(uint16_t d, uint32_t add_spread) {
    uint32_t sum = ((d | (uint32_t)d << 16) & SPREAD) + add_spread;
    const uint32_t rb = sum & CARRY_RB, g = sum & CARRY_G;
    sum |= (rb - (rb >> 5)) | (g - (g >> 6)); /* a channel that carried is full */
    return unspread(sum & SPREAD);
}

static inline uint16_t not_key(uint16_t v) { return v == CANVAS_KEY ? v ^ 1 : v; } /* (a canvas's see-through colour) */

static inline uint16_t sub565_sat(uint16_t d, uint32_t sub_spread) {
    const uint32_t guards = CARRY_RB | CARRY_G;
    uint32_t diff = (((d | (uint32_t)d << 16) & SPREAD) | guards) - sub_spread; /* a guard bit that is left: no borrow */
    const uint32_t rb = diff & CARRY_RB, g = diff & CARRY_G;
    diff &= (rb - (rb >> 5)) | (g - (g >> 6)); /* a channel that borrowed is empty */
    return unspread(diff & SPREAD);
}

/* A colour made ready to be mixed: for an add, a take or a quarter, its channels apart and scaled (add565_sat, sub565_sat); for an
 * alpha mix, as it is. */
static inline uint32_t ready(uint16_t c, int mode, unsigned alpha) {
    if (mode == BLEND_ALPHA) return c;
    const unsigned sh = mode == BLEND_QUARTER ? 10 : 8;
    return ((c & 31) * alpha >> sh) | ((c >> 11) * alpha >> sh) << 11 | ((c >> 5 & 63) * alpha >> sh) << 21;
}

/* n pixels down a column, each mixed with its ready colour; not inlined, so its loop keeps its numbers in registers */
static __attribute__((noinline)) void mixed_run(const surface *s, uint16_t *dst, int ys, int n, const uint32_t *col, int mode,
                                                unsigned alpha) {
    const bool swap = s->swap;
    if (mode == BLEND_ALPHA) {
        for (int j = 0; j < n; j++, dst += ys) {
            const uint16_t under = swap ? bswap16(*dst) : *dst, c = (uint16_t)col[j];
            *dst = under == CANVAS_KEY ? stored(s, c) : stored(s, mix565(under, c, alpha, BLEND_ALPHA));
        }
    } else if (mode == BLEND_SUB) {
        for (int j = 0; j < n; j++, dst += ys) {
            const uint16_t under = swap ? bswap16(*dst) : *dst;
            const uint16_t v = under == CANVAS_KEY ? unspread(col[j]) : not_key(sub565_sat(under, col[j]));
            *dst = swap ? bswap16(v) : v;
        }
    } else {
        for (int j = 0; j < n; j++, dst += ys) {
            const uint16_t under = swap ? bswap16(*dst) : *dst;
            const uint16_t v = under == CANVAS_KEY ? not_key(unspread(col[j])) : not_key(add565_sat(under, col[j]));
            *dst = swap ? bswap16(v) : v;
        }
    }
}

/* A ramp's colour at step t, as RGB565, the dither's offset d (8-bit steps) added before the low bits go. */
static inline uint16_t ramp565_at(const int32_t ch[3], int d) {
    int r = (ch[0] >> 8) + d * 256, g = (ch[1] >> 8) + d * 128, b = (ch[2] >> 8) + d * 256; /* 8.8 */
    r = r < 0 ? 0 : r > 255 * 256 ? 255 * 256 : r, g = g < 0 ? 0 : g > 255 * 256 ? 255 * 256 : g, b = b < 0 ? 0 : b > 255 * 256 ? 255 * 256 : b;
    return (uint16_t)((r >> 11) << 11 | (g >> 10) << 5 | (b >> 11));
}

static inline uint16_t ramp565(const int32_t first[3], const int32_t step[3], int t, int d) {
    const int32_t ch[3] = {first[0] + step[0] * t, first[1] + step[1] * t, first[2] + step[2] * t};
    return ramp565_at(ch, d);
}

/* A box filled from colour c1 at its top (or left) to c2 at its bottom (right), each channel stepping evenly from the
 * first row's middle to the last's; dither: the PlayStation's 4x4 added before the low bits go, so a slow ramp shows a
 * fine pattern, not bands. Seen through or added to what is under it like a picture (mode, alpha 0..256). */
void gfx_grad(surface *s, int x, int y, int w, int h, const uint8_t c1[3], const uint8_t c2[3], bool across, bool dither,
              int mode, unsigned alpha) {
    int u0, v0, n = CLIP_X(s, x, w, &u0), m = CLIP_Y(s, y, h, &v0);
    if (n <= 0 || m <= 0) return;
    const int ys = step_y(s), len = across ? w : h;
    const bool plain = mode == BLEND_ALPHA && alpha >= 256;
    /* each channel in 16.16: c1 + (c2 - c1) (2 t + 1) / 2 len, stepped by (c2 - c1) / len a pixel. No division in the
     * loop: on the console a 64-bit one is dozens of times the rest of the pixel. */
    int32_t step[3], first[3];
    for (int i = 0; i < 3; i++) {
        step[i] = (c2[i] - c1[i]) * 65536 / len;
        first[i] = c1[i] * 65536 + step[i] / 2;
    }
    if (plain) { /* the colours of the ramp worked out once (each row's, in the four the dither has), then only stored */
        const int phases = dither ? 4 : 1; /* the dither's pattern repeats every 4 columns and 4 rows */
        if (!across) {
            uint16_t tbl[4][64];
            for (int j0 = 0; j0 < m; j0 += 64) {
                const int cm = m - j0 < 64 ? m - j0 : 64;
                for (int ph = 0; ph < phases; ph++)
                    for (int j = 0; j < cm; j++) {
                        const int d = dither ? PSX_DITHER[((y + v0 + j0 + j) & 3) * 4 + ph] : 0;
                        tbl[ph][j] = stored(s, ramp565(first, step, v0 + j0 + j, d));
                    }
                for (int k = 0; k < n; k++) {
                    const int px = x + u0 + k;
                    const uint16_t *col = tbl[dither ? (px & 3) : 0];
                    uint16_t *dst = at(s, px, y + v0 + j0);
                    for (int j = 0; j < cm; j++, dst += ys) *dst = col[j];
                }
            }
        } else {
            for (int k = 0; k < n; k++) {
                const int px = x + u0 + k;
                uint16_t col[4];
                for (int ph = 0; ph < phases; ph++) /* ph: the row's 4-row phase */
                    col[ph] = stored(s, ramp565(first, step, u0 + k, dither ? PSX_DITHER[ph * 4 + (px & 3)] : 0));
                uint16_t *dst = at(s, px, y + v0);
                if (!dither)
                    for (int j = 0; j < m; j++, dst += ys) *dst = col[0];
                else
                    for (int j = 0; j < m; j++, dst += ys) *dst = col[(y + v0 + j) & 3];
            }
        }
        return;
    }
    /* mixed with what is there: each row's colour (and its 4 dither phases) made ready once a chunk of rows, as gfx_lines does
     * (a strip of haze over the sky was 300 ns a pixel on the console when each pixel worked out its colour and unpacked it) */
    static uint32_t tabs_of_part[2][4][64];
    uint32_t (*tab)[64] = tabs_of_part[s->part & 1];
    const int phases = dither ? 4 : 1;
    for (int j0 = 0; j0 < m; j0 += 64) {
        const int cm = m - j0 < 64 ? m - j0 : 64, row0 = y + v0 + j0;
        if (!across)
            for (int ph = 0; ph < phases; ph++) /* ph: the column's phase in the dither */
                for (int j = 0; j < cm; j++)
                    tab[ph][j] = ready(ramp565(first, step, v0 + j0 + j, dither ? PSX_DITHER[((row0 + j) & 3) * 4 + ph] : 0), mode, alpha);
        for (int k = 0; k < n; k++) {
            const int px = x + u0 + k;
            const uint32_t *col = tab[dither ? px & 3 : 0];
            if (across) { /* the colour is the column's: the same down it but for the dither's 4 rows */
                uint32_t four[4];
                for (int ph = 0; ph < phases; ph++)
                    four[ph] = ready(ramp565(first, step, u0 + k, dither ? PSX_DITHER[ph * 4 + (px & 3)] : 0), mode, alpha);
                for (int j = 0; j < cm; j++) tab[0][j] = four[dither ? (row0 + j) & 3 : 0];
                col = tab[0];
            }
            mixed_run(s, at(s, px, row0), ys, cm, col, mode, alpha);
        }
    }
}

/* ------------------------------------------------------------------ light: a glow that adds to, or takes from, what is there */

/* A light at (cx, cy) reaching r pixels: each pixel gets the colour times (1 - d^2 / r^2)^2, which is a soft round glow with
 * no edge, times intensity (0..256). With a cone (ux, uy: the direction, unit, 14 bits; cosine of its half angle, 14
 * bits): only inside it; `soft` (a larger cosine inside) is full, between the two half. Nothing is read from a picture: the
 * cost is the pixels in the circle, about 100 ns each on the console. */
/* One column of a light, from row y0 to y1: specialised (always inlined with constant flags) so each kind of light is a plain loop
 * with its numbers in registers. */
static inline __attribute__((always_inline)) void light_column(uint16_t *dst, int ys, int n, int d2, int dy, int dot, int uy, int inv,
                                                               int co2, int ci2, const uint32_t *tab, bool sub, bool cone, bool swap) {
    for (int i = 0; i < n; i++, dst += ys, d2 += 2 * dy + 1, dy++, dot += uy) {
        int idx = (d2 * inv) >> 16; /* (below 2^23: the radius squared times 63 << 16 over it) */
        if (idx > 63) idx = 63;
        if (cone) {
            if (dot <= 0) continue;
            const int p = dot >> 6; /* 8 bits of fraction, up to 150 * 256 */
            const int p2 = p * p;   /* 16 bits of fraction, below 2^31: dot^2 against cos^2 * d^2, both in 16 bits */
            if (p2 < co2 * d2) continue;  /* outside the cone */
            if (p2 < ci2 * d2) idx += 64; /* its rim: half */
        }
        const uint16_t d = swap ? bswap16(*dst) : *dst;
        const uint16_t v = sub ? sub565_sat(d, tab[idx]) : add565_sat(d, tab[idx]);
        *dst = swap ? bswap16(v) : v;
    }
}

/* A light at (cx, cy) reaching r pixels: each pixel gets the colour times (1 - d^2 / r^2)^2, which is a soft round glow with
 * no edge, times intensity (0..256). With a cone (ux, uy: the direction, unit, 14 bits; cosine of its half angle, 14
 * bits): only inside it; `soft` (a larger cosine inside) is full, between the two half. Nothing is read from a picture: the
 * cost is the pixels in the circle. */
void gfx_light(surface *s, int cx, int cy, int r, const uint8_t rgb[3], unsigned intensity, bool sub, bool cone, int ux,
               int uy, int cos_outer, int cos_inner) {
    if (r < 1 || intensity == 0) return;
    if (cone && r > 150) r = 150; /* (the cone's squares stay in 32 bits) */
    /* the colour at each of 64 steps from the middle to the edge, packed apart; 64 more at half for a cone's rim. Not on the
     * stack (a big array there pushed the loop's numbers out of the registers); one for each part that draws (both cores draw
     * strips at once: surface.part) */
    static uint32_t tab_of_part[2][128];
    uint32_t *const tab = tab_of_part[s->part & 1];
    for (int i = 0; i < 64; i++) {
        const float u = (float)i / 63.0f, f = (1 - u) * (1 - u) * (float)intensity / 256.0f;
        const int cr = (int)((rgb[0] >> 3) * f + 0.5f), cg = (int)((rgb[1] >> 2) * f + 0.5f), cb = (int)((rgb[2] >> 3) * f + 0.5f);
        tab[i] = (uint32_t)cb | (uint32_t)cr << 11 | (uint32_t)cg << 21;
        tab[64 + i] = (uint32_t)(cb >> 1) | (uint32_t)(cr >> 1) << 11 | (uint32_t)(cg >> 1) << 21;
    }
    const int ys = step_y(s), top = s->y0, bottom = s->y0 + s->h - 1;
    int x0 = cx - r, x1 = cx + r;
    if (x0 < s->x0) x0 = s->x0;
    if (x1 > s->x0 + s->w - 1) x1 = s->x0 + s->w - 1;
    const int inv = (int)((63u << 16) / (unsigned)(r * r)); /* d2 -> a step of 0..63 */
    const int co2 = (int)(((int64_t)cos_outer * cos_outer) >> 12), ci2 = (int)(((int64_t)cos_inner * cos_inner) >> 12); /* 16 bits */
    const bool swap = s->swap;
    for (int x = x0; x <= x1; x++) {
        const int dx = x - cx;
        const int dymax = (int)sqrtf((float)(r * r - dx * dx));
        int y0 = cy - dymax, y1 = cy + dymax;
        if (y0 < top) y0 = top;
        if (y1 > bottom) y1 = bottom;
        if (y0 > y1) continue;
        const int dy = y0 - cy, d2 = dx * dx + dy * dy, dot = dx * ux + dy * uy, n = y1 - y0 + 1;
        uint16_t *dst = at(s, x, y0);
        if (cone) {
            if (sub) light_column(dst, ys, n, d2, dy, dot, uy, inv, co2, ci2, tab, true, true, swap);
            else light_column(dst, ys, n, d2, dy, dot, uy, inv, co2, ci2, tab, false, true, swap);
        } else if (swap) {
            if (sub) light_column(dst, ys, n, d2, dy, 0, 0, inv, 0, 0, tab, true, false, true);
            else light_column(dst, ys, n, d2, dy, 0, 0, inv, 0, 0, tab, false, false, true);
        } else {
            if (sub) light_column(dst, ys, n, d2, dy, 0, 0, inv, 0, 0, tab, true, false, false);
            else light_column(dst, ys, n, d2, dy, 0, 0, inv, 0, 0, tab, false, false, false);
        }
    }
}

/* ------------------------------------------------------------------ warp: a picture with each row, each column, moved */

/* A frame of the picture drawn at (x, y) with row j moved right by rows[j] pixels (a Saturn VDP2's line scroll: water,
 * heat, a wave) and column i moved down by cols[i] (column scroll: a flag, a ripple). Either may be NULL. wrap: what
 * moves out of one side comes in at the other (a panorama going round); else the gaps are see-through. */
void gfx_warp(surface *s, const asset *a, int frame, int x, int y, const int16_t *rows, const int16_t *cols, bool wrap) {
    if (!a->pixels || frame < 0 || frame >= a->frames) return;
    const int W = a->w, H = a->h, stride = (W + 7) / 8;
    const uint16_t *src = a->pixels + (size_t)frame * W * H;
    const uint8_t *mask = a->mask ? a->mask + (size_t)frame * stride * H : NULL;
    const int ys = step_y(s);
    int cmin = 0, cmax = 0, rmin = 0, rmax = 0;
    for (int j = 0; rows && j < H; j++) rmin = rows[j] < rmin ? rows[j] : rmin, rmax = rows[j] > rmax ? rows[j] : rmax;
    for (int i = 0; cols && i < W; i++) cmin = cols[i] < cmin ? cols[i] : cmin, cmax = cols[i] > cmax ? cols[i] : cmax;
    /* the screen columns the picture can touch, and for each the rows */
    int sx0 = x + rmin, sx1 = x + W + rmax; /* [sx0, sx1) */
    if (wrap) sx0 = x, sx1 = x + W;
    if (sx0 < s->x0) sx0 = s->x0;
    if (sx1 > s->x0 + s->w) sx1 = s->x0 + s->w;
    int j0 = y + cmin, j1 = y + H + cmax; /* screen rows [j0, j1) */
    if (j0 < s->y0) j0 = s->y0;
    if (j1 > s->y0 + s->h) j1 = s->y0 + s->h;
    /* Each row is moved first, then each column of the result: screen pixel (px, py) shows row j = py - y - cols[px - x] of the
     * picture, from its column u = px - x - rows[j]. */
    for (int px = sx0; px < sx1; px++) {
        const int ci = px - x;
        const int cdy = cols ? cols[ci < 0 ? 0 : ci >= W ? W - 1 : ci] : 0;
        uint16_t *dst = at(s, px, j0);
        for (int py = j0; py < j1; py++, dst += ys) {
            const int j = py - y - cdy;
            if ((unsigned)j >= (unsigned)H) continue;
            int u = px - x - (rows ? rows[j] : 0);
            if (wrap) u = ((u % W) + W) % W;
            if ((unsigned)u >= (unsigned)W) continue;
            if (mask && !(mask[j * stride + (u >> 3)] & (0x80 >> (u & 7)))) continue;
            const uint16_t c = src[j * W + u];
            *dst = s->swap ? bswap16(c) : c;
        }
    }
}

/* ------------------------------------------------------------------ lines: a colour for each row, added, taken or laid */

/* The rows of a box each given its own colour (rowcol[j] for row j of h, RGB565): laid as they are, or added to or taken
 * from what is there (the colour offset of a Saturn's VDP2 for each line: a sunset down a wall, a flash up a floor), or mixed
 * at alpha (0..256). */
void gfx_lines(surface *s, int x, int y, int w, int h, const uint16_t *rowcol, int mode, unsigned alpha, bool lay) {
    int u0, v0, n = CLIP_X(s, x, w, &u0), m = CLIP_Y(s, y, h, &v0);
    if (n <= 0 || m <= 0) return;
    const int ys = step_y(s);
    /* each row's colour made ready once a chunk of rows (as stored, or apart and scaled for a saturating add or take), so a pixel is
     * a load, an add and a store: the whole screen was 33 ms on the console when each pixel unpacked its colour. Not on the stack
     * (a big array there pushed the loop's numbers out of the registers) and not _Thread_local (ESP-IDF puts that in every task's
     * stack, and the small ones overflowed at boot): one for each part that draws (surface.part), as both cores draw strips. */
    static uint32_t rows_of_part[2][128];
    uint32_t *const row = rows_of_part[s->part & 1];
    for (int j0 = 0; j0 < m; j0 += 128) {
        const int cm = m - j0 < 128 ? m - j0 : 128;
        for (int j = 0; j < cm; j++) {
            const uint16_t c = rowcol[v0 + j0 + j];
            row[j] = lay ? stored(s, c) : ready(c, mode, alpha);
        }
        for (int k = 0; k < n; k++) {
            uint16_t *dst = at(s, x + u0 + k, y + v0 + j0);
            if (lay)
                for (int j = 0; j < cm; j++, dst += ys) *dst = (uint16_t)row[j];
            else
                mixed_run(s, dst, ys, cm, row, mode, alpha);
        }
    }
}
