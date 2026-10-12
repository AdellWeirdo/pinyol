/* Free drawing: lines, circles, polygons and triangles, and canvases (pictures a game draws into while it runs).
 * Each shape is worked out the same way whatever window it is drawn into and only its pixels are clipped, so the
 * console's strips and a whole frame get the same pixels. */
#include <math.h>
#include <stdlib.h>
#include <string.h>

#include "bp.h"
#include "gfx_px.h"

static inline void put(surface *s, int x, int y, uint16_t c) { /* c as kept in s */
    if (x >= s->x0 && x < s->x0 + s->w && y >= s->y0 && y < s->y0 + s->h) *at(s, x, y) = c;
}

static bool outside(const surface *s, int x0, int y0, int x1, int y1) { /* a box, ends included, misses s */
    return x1 < s->x0 || x0 >= s->x0 + s->w || y1 < s->y0 || y0 >= s->y0 + s->h;
}

void gfx_line(surface *s, int x0, int y0, int x1, int y1, uint16_t c) {
    if (outside(s, x0 < x1 ? x0 : x1, y0 < y1 ? y0 : y1, x0 > x1 ? x0 : x1, y0 > y1 ? y0 : y1)) return;
    c = stored(s, c);
    int dx = abs(x1 - x0), dy = -abs(y1 - y0), sx = x0 < x1 ? 1 : -1, sy = y0 < y1 ? 1 : -1, err = dx + dy;
    for (;;) { /* Bresenham, from the first end always: the same pixels in every window */
        put(s, x0, y0, c);
        if (x0 == x1 && y0 == y1) return;
        int e2 = 2 * err;
        if (e2 >= dy) err += dy, x0 += sx;
        if (e2 <= dx) err += dx, y0 += sy;
    }
}

void gfx_circ(surface *s, int cx, int cy, int r, uint16_t c, bool fill) {
    if (r < 0 || outside(s, cx - r, cy - r, cx + r, cy + r)) return;
    uint16_t sc = stored(s, c);
    for (int x = r, y = 0, err = 1 - r; x >= y;) { /* the midpoint circle, an eighth at a time */
        if (fill) {
            gfx_fill(s, cx - x, cy + y, 2 * x + 1, 1, c), gfx_fill(s, cx - x, cy - y, 2 * x + 1, 1, c);
            gfx_fill(s, cx - y, cy + x, 2 * y + 1, 1, c), gfx_fill(s, cx - y, cy - x, 2 * y + 1, 1, c);
        } else {
            put(s, cx + x, cy + y, sc), put(s, cx - x, cy + y, sc), put(s, cx + x, cy - y, sc), put(s, cx - x, cy - y, sc);
            put(s, cx + y, cy + x, sc), put(s, cx - y, cy + x, sc), put(s, cx + y, cy - x, sc), put(s, cx - y, cy - x, sc);
        }
        y++;
        if (err < 0) err += 2 * y + 1;
        else x--, err += 2 * (y - x) + 1;
    }
}

/* Filled: each row's crossings with the edges at the pixels' centres, paired inside-outside (so a shape that
 * crosses itself has holes, as in most drawing programs). Outline: its edges as lines. */
void gfx_poly(surface *s, const int16_t *xy, int n, uint16_t c, bool fill) {
    if (n < 1 || n > GFX_POLY_MAX) return;
    int xmin = xy[0], xmax = xy[0], ymin = xy[1], ymax = xy[1];
    for (int i = 1; i < n; i++) {
        int x = xy[2 * i], y = xy[2 * i + 1];
        xmin = x < xmin ? x : xmin, xmax = x > xmax ? x : xmax, ymin = y < ymin ? y : ymin, ymax = y > ymax ? y : ymax;
    }
    if (outside(s, xmin, ymin, xmax, ymax)) return;
    if (!fill || n < 3) {
        for (int i = 0; i < n; i++) {
            int j = (i + 1) % n;
            gfx_line(s, xy[2 * i], xy[2 * i + 1], xy[2 * j], xy[2 * j + 1], c);
        }
        return;
    }
    int ya = ymin > s->y0 ? ymin : s->y0, yb = ymax < s->y0 + s->h - 1 ? ymax : s->y0 + s->h - 1;
    float cross[GFX_POLY_MAX];
    for (int y = ya; y <= yb; y++) {
        float yc = (float)y + 0.5f;
        int k = 0;
        for (int i = 0; i < n; i++) {
            int j = (i + 1) % n;
            float y0 = xy[2 * i + 1], y1 = xy[2 * j + 1], x0 = xy[2 * i], x1 = xy[2 * j];
            if ((y0 <= yc && yc < y1) || (y1 <= yc && yc < y0)) cross[k++] = x0 + (yc - y0) * (x1 - x0) / (y1 - y0);
        }
        for (int i = 1; i < k; i++) /* few crossings: insertion sort */
            for (int j = i; j > 0 && cross[j - 1] > cross[j]; j--) {
                float t = cross[j];
                cross[j] = cross[j - 1], cross[j - 1] = t;
            }
        for (int i = 0; i + 1 < k; i += 2) { /* pixels whose centres are inside */
            int xa = (int)ceilf(cross[i] - 0.5f), xb = (int)ceilf(cross[i + 1] - 0.5f);
            if (xb > xa) gfx_fill(s, xa, y, xb - xa, 1, c);
        }
    }
}

/* ------------------------------------------------------------------ canvases */

/* A canvas keeps its see-through pixels as CANVAS_KEY in its pixels, so everything that draws on a surface draws on
 * it; its mask, which the screen's drawing reads, is worked out again for the part that was drawn on. */
void gfx_canvas_mask(asset *a, int x, int y, int w, int h) {
    if (!a->mask) return;
    int i0, j0, n = clip(x, w, 0, a->w, &i0), m = clip(y, h, 0, a->h, &j0), stride = (a->w + 7) / 8;
    if (n <= 0 || m <= 0) return;
    for (int j = y + j0; j < y + j0 + m; j++) {
        const uint16_t *p = a->pixels + (size_t)j * a->w;
        uint8_t *row = a->mask + (size_t)j * stride;
        for (int i = x + i0; i < x + i0 + n; i++) {
            if (p[i] == CANVAS_KEY) row[i >> 3] &= (uint8_t)~(0x80 >> (i & 7));
            else row[i >> 3] |= (uint8_t)(0x80 >> (i & 7));
        }
    }
}
