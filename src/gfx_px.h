/* Pixel access on a surface (bp.h), shared by the drawing files: gfx.c, gfx_style.c. */
#pragma once
#include "bp.h"

static inline uint16_t blend50(uint16_t a, uint16_t b) { return ((a & 0xF7DE) >> 1) + ((b & 0xF7DE) >> 1); }

/* A surface's steps between pixels, and the frame it is a window of (surface in bp.h). */
static inline int step_x(const surface *s) { return s->xs ? s->xs : 1; }
static inline int step_y(const surface *s) { return s->xs ? s->ys : s->w; }
static inline int frame_w(const surface *s) { return s->fw ? s->fw : s->w; }
static inline int frame_h(const surface *s) { return s->fh ? s->fh : s->h; }
static inline uint16_t *at(const surface *s, int x, int y) {
    return s->px + (ptrdiff_t)(x - s->x0) * step_x(s) + (ptrdiff_t)(y - s->y0) * step_y(s);
}
static inline uint16_t bswap16(uint16_t v) { return (uint16_t)(v << 8 | v >> 8); }
static inline uint16_t stored(const surface *s, uint16_t c) { return s->swap ? bswap16(c) : c; } /* a colour as kept in s */
static inline bool dithered(const surface *s, int x, int y) { /* a pixel the dissolve leaves as it was (bp.h) */
    static const uint8_t BAYER[16] = {0, 8, 2, 10, 12, 4, 14, 6, 3, 11, 1, 9, 15, 7, 13, 5};
    return BAYER[((y >> 1) & 3) * 4 + ((x >> 1) & 3)] < s->dither;
}

/* The three blends that move a channel by an amount and hold it to its range (BLEND_ADD, BLEND_SUB, BLEND_QUARTER):
 * under d plus, minus, or plus a quarter of what c brings, c scaled by a (0..256). RGB565 in and out; the caller keeps
 * the result off a canvas's see-through colour. */
static inline uint16_t blend_held(uint16_t d, uint16_t c, unsigned a, int mode) {
    const unsigned shift = mode == BLEND_QUARTER ? 10 : 8; /* a / 256, or a quarter of that */
    int dr = d >> 11, dg = d >> 5 & 63, db = d & 31;
    int cr = (int)((c >> 11) * a >> shift), cg = (int)((c >> 5 & 63) * a >> shift), cb = (int)((c & 31) * a >> shift);
    if (mode == BLEND_SUB) cr = -cr, cg = -cg, cb = -cb;
    int r = dr + cr, g = dg + cg, b = db + cb;
    r = r < 0 ? 0 : r > 31 ? 31 : r, g = g < 0 ? 0 : g > 63 ? 63 : g, b = b < 0 ? 0 : b > 31 ? 31 : b;
    return (uint16_t)(r << 11 | g << 5 | b);
}

/* Visible part of a span [x, x+len) on a line [lo, hi): first offset into the span, and how many. */
static inline int clip(int x, int len, int lo, int hi, int *first) {
    *first = x < lo ? lo - x : 0;
    return (x + len > hi ? hi - x : len) - *first;
}
#define CLIP_X(s, x, len, first) clip(x, len, (s)->x0, (s)->x0 + (s)->w, first)
#define CLIP_Y(s, y, len, first) clip(y, len, (s)->y0, (s)->y0 + (s)->h, first)
