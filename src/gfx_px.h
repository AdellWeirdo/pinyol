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

/* Visible part of a span [x, x+len) on a line [lo, hi): first offset into the span, and how many. */
static inline int clip(int x, int len, int lo, int hi, int *first) {
    *first = x < lo ? lo - x : 0;
    return (x + len > hi ? hi - x : len) - *first;
}
#define CLIP_X(s, x, len, first) clip(x, len, (s)->x0, (s)->x0 + (s)->w, first)
#define CLIP_Y(s, y, len, first) clip(y, len, (s)->y0, (s)->y0 + (s)->h, first)
