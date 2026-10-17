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
    float at[5];  /* the picture's column and row, then the light's red, green and blue */
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
} quad_ctx;

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
    float gx[5], gy[5];
    const float d = (float)area;
    for (int k = 0; k < 5; k++) {
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
    for (int x = bx0; x < bx1; x++) {
        const int32_t X = 8 * x + 4;
        int32_t lo = top, hi = bottom; /* the rows (inclusive) inside all three edges, from where the column crosses them */
        bool none = false;
        for (int i = 0; i < 3 && !none; i++) {
            int32_t K = e[i].bias - (e[i].a * X + e[i].c); /* inside where b Y >= K, Y = 8 y + 4 */
            if (e[i].b > 0) {
                int32_t y = ceil_div32(ceil_div32(K, e[i].b) - 4, 8);
                if (y > lo) lo = y;
            } else if (e[i].b < 0) {
                int32_t y = floor_div32(floor_div32(-K, -e[i].b) - 4, 8);
                if (y < hi) hi = y;
            } else if (K > 0) {
                none = true;
            }
        }
        if (none || lo > hi) continue;
        /* the picture's coordinates and the light at the first row's centre, in 16.16, then a row's step */
        int32_t v0[5], dv[5];
        for (int k = 0; k < 5; k++) {
            float at = p[0].at[k] + gx[k] * (float)(X - p[0].x) + gy[k] * (float)(8 * lo + 4 - p[0].y);
            v0[k] = (int32_t)(at * 65536.0f), dv[k] = (int32_t)(gy[k] * 8.0f * 65536.0f);
        }
        uint16_t *dst = at(s, x, lo);
        for (int y = lo; y <= hi; y++, dst += ys) {
            int iu = v0[0] >> 16, iv = v0[1] >> 16;
            const int lr = v0[2] >> 16, lg = v0[3] >> 16, lb = v0[4] >> 16;
            for (int k = 0; k < 5; k++) v0[k] += dv[k];
            iu = iu < 0 ? 0 : iu >= q->w ? q->w - 1 : iu, iv = iv < 0 ? 0 : iv >= q->h ? q->h - 1 : iv;
            if (q->mask && !(q->mask[iv * q->stride + (iu >> 3)] & (0x80 >> (iu & 7)))) continue;
            uint16_t c = q->src[iv * q->w + iu];
            if (q->lit)
                c = lit(c, lr < 0 ? 0 : lr > 255 ? 255 : lr, lg < 0 ? 0 : lg > 255 ? 255 : lg, lb < 0 ? 0 : lb > 255 ? 255 : lb,
                        q->dither ? PSX_DITHER[(y & 3) * 4 + (x & 3)] : 0);
            if (q->plain) {
                *dst = stored(s, c);
                continue;
            }
            uint16_t under = s->swap ? bswap16(*dst) : *dst;
            *dst = under == CANVAS_KEY ? stored(s, c) : stored(s, mix565(under, c, q->alpha, q->mode));
        }
    }
}

void gfx_quad(surface *s, const asset *a, int frame, const int16_t xy8[8], const uint8_t light[4][3], bool lights,
              int mode, unsigned alpha, bool dither) {
    if (!a->pixels || frame < 0 || frame >= a->frames) return;
    quad_ctx q = {.src = a->pixels + (size_t)frame * a->w * a->h, .w = a->w, .h = a->h, .stride = (a->w + 7) / 8,
                  .lit = lights, .dither = dither && lights, .mode = mode, .alpha = alpha};
    q.mask = a->mask ? a->mask + (size_t)frame * q.stride * a->h : NULL;
    q.plain = mode == BLEND_ALPHA && alpha >= 256;
    /* the corners and what each carries: the picture's own corners, so the frame fills the quad */
    const float tu[4] = {0, (float)a->w, (float)a->w, 0}, tv[4] = {0, 0, (float)a->h, (float)a->h};
    vertex v[4];
    for (int i = 0; i < 4; i++) {
        v[i].x = xy8[2 * i], v[i].y = xy8[2 * i + 1];
        v[i].at[0] = tu[i], v[i].at[1] = tv[i];
        for (int k = 0; k < 3; k++) v[i].at[2 + k] = lights ? (float)light[i][k] : 128.0f;
    }
    vertex t1[3] = {v[0], v[1], v[2]}, t2[3] = {v[0], v[2], v[3]};
    triangle(s, &q, t1);
    triangle(s, &q, t2);
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
    for (int k = 0; k < n; k++) {
        const int px = x + u0 + k;
        uint16_t *dst = at(s, px, y + v0);
        for (int j = 0; j < m; j++, dst += ys) {
            const int py = y + v0 + j, t = across ? u0 + k : v0 + j;
            int ch[3];
            for (int i = 0; i < 3; i++) { /* 8.8: c1 + (c2 - c1) (2 t + 1) / 2 len */
                ch[i] = (c1[i] << 8) + (int)((int64_t)((c2[i] - c1[i]) * 256) * (2 * t + 1) / (2 * len));
                if (dither) ch[i] += PSX_DITHER[(py & 3) * 4 + (px & 3)] * (i == 1 ? 128 : 256);
                ch[i] = ch[i] < 0 ? 0 : ch[i] > 255 * 256 ? 255 * 256 : ch[i];
            }
            uint16_t c = (uint16_t)((ch[0] >> 11) << 11 | (ch[1] >> 10) << 5 | (ch[2] >> 11));
            if (plain) {
                *dst = stored(s, c);
                continue;
            }
            uint16_t under = s->swap ? bswap16(*dst) : *dst;
            *dst = under == CANVAS_KEY ? stored(s, c) : stored(s, mix565(under, c, alpha, mode));
        }
    }
}
