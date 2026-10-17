/* A game's own look: styled text (outline, shadow, gradient, scale, wave), images turned, scaled and flipped, and
 * frames cut from the game's own picture (nine-slice). Everything clips to the surface, so it draws the same on the
 * console's strips as on a whole frame. */
#include <math.h>
#include <string.h>

#include "bp.h"
#include "gfx_px.h"

/* ------------------------------------------------------------------ styled text */

#define PAD 2          /* the ring around a glyph's cell: outline and shadow */
#define CELL_MAX 64    /* fonts up to 64x64 pixels a glyph */
#define MAP_W (CELL_MAX + 2 * PAD)

enum { INK = 1, RING, SHADE };

static uint16_t lerp565(uint16_t a, uint16_t b, int i, int n) { /* a at i = 0, b at i = n - 1 */
    if (n <= 1) return a;
    int ra = a >> 11, ga = a >> 5 & 63, ba = a & 31, rb = b >> 11, gb = b >> 5 & 63, bb = b & 31;
    int r = ra + (rb - ra) * i / (n - 1), g = ga + (gb - ga) * i / (n - 1), bl = ba + (bb - ba) * i / (n - 1);
    return (uint16_t)(r << 11 | g << 5 | bl);
}

/* One glyph: its ink, outline and shadow worked out on a small map in font pixels, then filled run by run, each font
 * pixel a scale x scale block. Only the map's columns this window shows are worked out (and the few around them an
 * outline or a shadow reaches from): on the console's 32-pixel strips, a big glyph costs a strip's share of it. */
static void glyph(surface *sf, const font *f, int c, int x, int y, const text_style *st) {
    const int k = st->scale, w = f->w, h = f->h, W = w + 2 * PAD, H = h + 2 * PAD;
    if (x + (w + PAD) * k <= sf->x0 || x - PAD * k >= sf->x0 + sf->w || y + (h + PAD) * k <= sf->y0 ||
        y - PAD * k >= sf->y0 + sf->h)
        return; /* not in this window: most glyphs, most strips */
    const uint8_t *g = f->bits + (size_t)c * h * f->stride, *b = f->box + 4 * c;
    if (b[1] <= b[0]) return; /* a space */
    int lo = (sf->x0 - x) / k + PAD - 1, hi = (sf->x0 + sf->w - x) / k + PAD + 2; /* the columns shown, map units */
    if (lo < 0) lo = 0;
    if (hi > W) hi = W;
    const int ilo = lo - 3 < 0 ? 0 : lo - 3, ihi = hi + 3 > W ? W : hi + 3; /* ink: what a ring or a shadow comes from */
    static uint8_t maps[2][MAP_W * MAP_W]; /* one for each part of hal_parallel: both may draw text at once */
    uint8_t *m = maps[sf->part & 1];
    memset(m, 0, (size_t)W * H);
    for (int j = b[2]; j < b[3]; j++)
        for (int i = b[0] > ilo - PAD ? b[0] : ilo - PAD; i < b[1] && i + PAD < ihi; i++)
            if (g[j * f->stride + (i >> 3)] & (0x80 >> (i & 7))) m[(j + PAD) * W + i + PAD] = INK;
    if (st->has_outline) /* each inked cell rings its empty neighbours */
        for (int j = 1; j < H - 1; j++)
            for (int i = ilo > 1 ? ilo : 1; i < ihi && i < W - 1; i++)
                if (m[j * W + i] == INK)
                    for (int d = 0; d < 9; d++) {
                        uint8_t *n = &m[(j + d / 3 - 1) * W + i + d % 3 - 1];
                        if (!*n) *n = RING;
                    }
    if (st->has_shadow) /* under what is there: the ink and its outline, moved */
        for (int j = H - 1; j >= 0; j--)
            for (int i = hi - 1; i >= lo; i--) {
                int sj = j - st->sdy, si = i - st->sdx;
                if (!m[j * W + i] && sj >= 0 && sj < H && si >= 0 && si < W && m[sj * W + si] && m[sj * W + si] != SHADE)
                    m[j * W + i] = SHADE;
            }
    for (int j = 0; j < H; j++) {
        int yy = y + (j - PAD) * k;
        if (yy + k <= sf->y0 || yy >= sf->y0 + sf->h) continue;
        uint16_t ink = st->gradient ? lerp565(st->color, st->bottom, j < PAD ? 0 : j - PAD, h) : st->color;
        const uint8_t *row = m + j * W;
        for (int i = lo; i < hi;) {
            int v = row[i], r = i + 1;
            if (!v) {
                i++;
                continue;
            }
            while (r < hi && row[r] == v) r++;
            gfx_fill(sf, x + (i - PAD) * k, yy, (r - i) * k, k, v == INK ? ink : v == RING ? st->outline : st->shadow);
            i = r;
        }
    }
}

static int jitter(int n, uint32_t t, int amp) { /* the same for a letter for a few frames, then another */
    uint32_t h = (uint32_t)n * 2654435761u ^ (t / 3) * 40503u;
    h ^= h >> 15;
    h *= 2246822519u;
    h ^= h >> 13;
    return (int)(h % (2u * amp + 1)) - amp;
}

int font_draw_styled(surface *sf, const font *f, int x, int y, const char *s, int nbytes, int maxchars,
                     const text_style *st) {
    if (!s || !f->bits || f->w > CELL_MAX || f->h > CELL_MAX) return 0;
    if (nbytes < 0) nbytes = (int)strlen(s);
    const char *e = s + nbytes;
    const int k = st->scale < 1 ? 1 : st->scale;
    text_style one = *st;
    one.scale = (uint8_t)k;
    int x0 = x;
    for (int n = 0; s < e && (maxchars < 0 || n < maxchars); n++) {
        int c = utf8_cp1252(&s, e);
        if (c < 0) c = '?';
        int dx = 0, dy = 0;
        if (st->wave) dy = (int)lroundf(sinf((float)st->tick * 0.12f + (float)n * 0.7f) * st->wave);
        if (st->shake) dx = jitter(n, st->tick, st->shake), dy += jitter(n + 977, st->tick, st->shake);
        glyph(sf, f, c, x + dx, y + dy, &one);
        x += (f->adv[c] + st->spacing) * k;
    }
    return x - x0;
}

/* ------------------------------------------------------------------ images turned, scaled, flipped */

/* Each pixel of the window the picture may cover is looked up in the picture (nearest), from its centre: a turned
 * picture has no gaps, at the cost of a little arithmetic per pixel. Fixed point, 16 bits of fraction. */
/* n pixels along a picture's row: the pixel at u (16.16) goes to d, then u steps by du and d by step. A pixel outside
 * the row (u not in [0, wf)) or with its mask bit clear is left as it was. swap is a constant at each call, so the
 * byte swap is a choice made once, not once a pixel. */
static inline __attribute__((always_inline)) void line_along(uint16_t *d, int step, const uint16_t *srow, const uint8_t *mrow,
                                                             int32_t u, int32_t du, int n, int32_t wf, bool swap) {
    for (int k = 0; k < n; k++, u += du, d += step) {
        if ((uint32_t)u >= (uint32_t)wf) continue;
        int iu = u >> 16;
        if (mrow && !(mrow[iu >> 3] & (0x80 >> (iu & 7)))) continue;
        uint16_t c = srow[iu];
        *d = swap ? (uint16_t)(c << 8 | c >> 8) : c;
    }
}

/* line_along for two destination lines that read the same row (a picture shown twice as big): each source pixel is read,
 * tested and swapped once and goes to both. */
static inline __attribute__((always_inline)) void line_along2(uint16_t *d, uint16_t *e, int step, const uint16_t *srow,
                                                              const uint8_t *mrow, int32_t u, int32_t du, int n, int32_t wf,
                                                              bool swap) {
    for (int k = 0; k < n; k++, u += du, d += step, e += step) {
        if ((uint32_t)u >= (uint32_t)wf) continue;
        int iu = u >> 16;
        if (mrow && !(mrow[iu >> 3] & (0x80 >> (iu & 7)))) continue;
        uint16_t c = srow[iu];
        if (swap) c = (uint16_t)(c << 8 | c >> 8);
        *d = *e = c;
    }
}

void gfx_blit_ex(surface *s, const asset *a, int frame, int x, int y, float sx, float sy, float degrees, const asset *pal,
                 int tint) {
    if (frame < 0 || frame >= a->frames) frame = 0;
    if (!(fabsf(sx) >= 1 / 64.0f && fabsf(sy) >= 1 / 64.0f && isfinite(sx) && isfinite(sy) && isfinite(degrees))) return; /* too small to see; and fixed point stays in range */
    float r = degrees * 3.14159265f / 180.0f, cs = cosf(r), sn = sinf(r), ax = fabsf(sx), ay = fabsf(sy);
    float cx = (float)x + a->w * ax / 2, cy = (float)y + a->h * ay / 2; /* turned about its centre */
    float ex = (fabsf(cs) * a->w * ax + fabsf(sn) * a->h * ay) / 2 + 1, ey = (fabsf(sn) * a->w * ax + fabsf(cs) * a->h * ay) / 2 + 1;
    const int ox = (int)floorf(cx - ex), oy = (int)floorf(cy - ey); /* the whole picture's corner: the same in every strip */
    int bx0 = ox, by0 = oy, bx1 = (int)ceilf(cx + ex), by1 = (int)ceilf(cy + ey);
    if (bx0 < s->x0) bx0 = s->x0;
    if (by0 < s->y0) by0 = s->y0;
    if (bx1 > s->x0 + s->w) bx1 = s->x0 + s->w;
    if (by1 > s->y0 + s->h) by1 = s->y0 + s->h;
    if (bx0 >= bx1 || by0 >= by1) return;
    const float F = 65536.0f;
    /* picture coordinates of a screen point p: u = ((p - c) . (cos, sin)) / sx + w / 2, v = ((p - c) . (-sin, cos)) / sy + h / 2,
     * worked out at the corner, then stepped in whole fixed-point units: a strip lands on exactly the same pixels */
    int32_t du_dx = (int32_t)(cs / sx * F), dv_dx = (int32_t)(-sn / sy * F);
    int32_t du_dy = (int32_t)(sn / sx * F), dv_dy = (int32_t)(cs / sy * F);
    float px = (float)ox + 0.5f - cx, py = (float)oy + 0.5f - cy;
    int32_t u_row = (int32_t)(((px * cs + py * sn) / sx + a->w / 2.0f) * F), v_row = (int32_t)(((-px * sn + py * cs) / sy + a->h / 2.0f) * F);
    u_row += (bx0 - ox) * du_dx + (by0 - oy) * du_dy, v_row += (bx0 - ox) * dv_dx + (by0 - oy) * dv_dy;
    if (a->pk && degrees == 0) { /* packed, not turned: from its columns, never unpacked; in its look */
        gfx_blit_scaled(s, a, frame, bx0, bx1, by0, by1, u_row, du_dx, v_row, dv_dy, pal, tint);
        return;
    }
    const uint16_t *src = a->pixels + (size_t)frame * a->w * a->h;
    const int stride = (a->w + 7) / 8;
    const uint8_t *mask = a->mask ? a->mask + (size_t)frame * stride * a->h : NULL;
    const int32_t wf = a->w << 16, hf = a->h << 16;
    /* lines along the way s keeps its pixels next to each other: rows on a plain frame, columns on the console's
     * turned strips; a pixel's (u, v) is the same sum of whole steps either way */
    const bool by_column = step_y(s) == 1 || step_y(s) == -1;
    const int lines = by_column ? bx1 - bx0 : by1 - by0, len = by_column ? by1 - by0 : bx1 - bx0;
    const int32_t du_line = by_column ? du_dx : du_dy, dv_line = by_column ? dv_dx : dv_dy;
    const int32_t du = by_column ? du_dy : du_dx, dv = by_column ? dv_dy : dv_dx;
    const int step = by_column ? step_y(s) : step_x(s);
    int32_t u_line = u_row, v_line = v_row;
    for (int l = 0; l < lines; l++, u_line += du_line, v_line += dv_line) {
        /* the part of this line inside the picture, where 0 <= u + k du < wf and 0 <= v + k dv < hf, a pixel wider each
         * side (each pixel is still checked): the turned picture's empty corners are not walked */
        int k0 = 0, k1 = len;
        const float uv[2] = {(float)u_line, (float)v_line}, dk[2] = {(float)du, (float)dv}, lim[2] = {(float)wf, (float)hf};
        for (int c = 0; c < 2; c++) {
            if (dk[c] == 0) {
                if (uv[c] < 0 || uv[c] >= lim[c]) k1 = 0;
                continue;
            }
            float lo = (0 - uv[c]) / dk[c], hi = (lim[c] - uv[c]) / dk[c]; /* float: the console has no double hardware */
            if (lo > hi) {
                float t = lo;
                lo = hi, hi = t;
            }
            if (lo - 1 > k0) k0 = lo - 1 < k1 ? (int)(lo - 1) : k1;
            if (hi + 1 < k1) k1 = hi + 1 > 0 ? (int)(hi + 1) : 0;
        }
        if (k0 >= k1) continue;
        int32_t u = u_line + k0 * du, v = v_line + k0 * dv;
        uint16_t *d = by_column ? at(s, bx0 + l, by0 + k0) : at(s, bx0 + k0, by0 + l);
        if (dv == 0 || du == 0) { /* a right-angle turn: along the line one of u, v stays, so its row (or column) and its
                                   * check are worked out once a line, not once a pixel (a turned screen, every frame) */
            if (dv == 0 ? v < 0 || v >= hf : u < 0 || u >= wf) continue;
            if (dv == 0) { /* a row of the picture: its pixels and mask bits are read along it */
                const int iv = v >> 16;
                const uint16_t *srow = src + (size_t)iv * a->w;
                const uint8_t *mrow = mask ? mask + (size_t)iv * stride : NULL;
                /* the next line reads this same row when the picture is bigger than 1x across the lines (u the same,
                 * v still in this row): both are done in one pass, the line after the next picks up from there */
                const bool two = du_line == 0 && l + 1 < lines && ((v + dv_line) >> 16) == iv;
                if (two) {
                    uint16_t *e = by_column ? at(s, bx0 + l + 1, by0 + k0) : at(s, bx0 + k0, by0 + l + 1);
                    if (s->swap) line_along2(d, e, step, srow, mrow, u, du, k1 - k0, wf, true);
                    else line_along2(d, e, step, srow, mrow, u, du, k1 - k0, wf, false);
                    l++, u_line += du_line, v_line += dv_line;
                } else if (s->swap) line_along(d, step, srow, mrow, u, du, k1 - k0, wf, true);
                else line_along(d, step, srow, mrow, u, du, k1 - k0, wf, false);
            } else { /* a column of the picture */
                const int iu = u >> 16;
                const uint16_t *scol = src + iu;
                const uint8_t *mcol = mask ? mask + (iu >> 3) : NULL;
                const uint8_t bit = (uint8_t)(0x80 >> (iu & 7));
                for (int k = k0; k < k1; k++, v += dv, d += step) {
                    if ((uint32_t)v >= (uint32_t)hf) continue;
                    int iv = v >> 16;
                    if (!mcol || mcol[iv * stride] & bit) *d = stored(s, scol[iv * a->w]);
                }
            }
            continue;
        }
        for (int k = k0; k < k1; k++, u += du, v += dv, d += step) {
            if (u < 0 || v < 0 || u >= wf || v >= hf) continue; /* the span is worked out generously: still checked */
            int iu = u >> 16, iv = v >> 16;
            if (!mask || mask[iv * stride + (iu >> 3)] & (0x80 >> (iu & 7))) *d = stored(s, src[iv * a->w + iu]);
        }
    }
}

void gfx_blit_ex_bounds(const asset *a, float sx, float sy, float degrees, int *x0, int *y0, int *w, int *h) {
    float r = degrees * 3.14159265f / 180.0f, cs = cosf(r), sn = sinf(r), ax = fabsf(sx), ay = fabsf(sy);
    float cx = a->w * ax / 2, cy = a->h * ay / 2; /* as gfx_blit_ex works it out, for x = y = 0 */
    float ex = (fabsf(cs) * a->w * ax + fabsf(sn) * a->h * ay) / 2 + 1, ey = (fabsf(sn) * a->w * ax + fabsf(cs) * a->h * ay) / 2 + 1;
    *x0 = (int)floorf(cx - ex), *y0 = (int)floorf(cy - ey);
    *w = (int)ceilf(cx + ex) - *x0, *h = (int)ceilf(cy + ey) - *y0;
}

/* ------------------------------------------------------------------ frames from the game's picture */

/* Picture rectangle (u, v, pw, ph) at (x, y), each pixel k x k, inside s: along the way s keeps its pixels next to
 * each other, the source position counted, not divided, pixel by pixel. */
static void part(surface *s, const asset *a, int frame, int u, int v, int pw, int ph, int x, int y, int k) {
    int i0, j0, n = CLIP_X(s, x, pw * k, &i0), m = CLIP_Y(s, y, ph * k, &j0);
    if (n <= 0 || m <= 0) return;
    const uint16_t *src = a->pixels + (size_t)frame * a->w * a->h;
    const int stride = (a->w + 7) / 8;
    const uint8_t *mask = a->mask ? a->mask + (size_t)frame * stride * a->h : NULL;
    const bool by_column = step_y(s) == 1 || step_y(s) == -1;
    const int lines = by_column ? n : m, len = by_column ? m : n, step = by_column ? step_y(s) : step_x(s);
    for (int l = 0; l < lines; l++) {
        int i = by_column ? i0 + l : i0, j = by_column ? j0 : j0 + l; /* where this line starts, in the part */
        uint16_t *d = at(s, x + i, y + j);
        int su = u + i / k, sv = v + j / k, sub = by_column ? j % k : i % k;
        for (int t = 0; t < len; t++, d += step) {
            if (!mask || mask[sv * stride + (su >> 3)] & (0x80 >> (su & 7))) *d = stored(s, src[sv * a->w + su]);
            if (++sub == k) { /* the next source pixel along the line */
                sub = 0;
                if (by_column) sv++;
                else su++;
            }
        }
    }
}

/* The picture in thirds: corners once, edges and middle repeated to fill w x h (the last copy cut short). */
void gfx_nine(surface *s, const asset *a, int frame, int x, int y, int w, int h, int k) {
    if (frame < 0 || frame >= a->frames) frame = 0;
    if (k < 1) k = 1;
    surface in = gfx_clip(s, x, y, w, h);
    if (in.w <= 0 || in.h <= 0) return;
    const int tw = a->w / 3, th = a->h / 3, cw = tw * k, ch = th * k;
    if (tw < 1 || th < 1) return;
    const int xs[3] = {x, x + cw, x + w - cw}, ys[3] = {y, y + ch, y + h - ch};
    const int ws[3] = {cw, w - 2 * cw, cw}, hs[3] = {ch, h - 2 * ch, ch};
    for (int r = 0; r < 3; r++)
        for (int q = 0; q < 3; q++) {
            if (ws[q] <= 0 || hs[r] <= 0) continue;
            surface cell = gfx_clip(&in, xs[q], ys[r], ws[q], hs[r]);
            if (cell.w <= 0 || cell.h <= 0) continue;
            for (int yy = ys[r]; yy < ys[r] + hs[r]; yy += th * k)
                for (int xx = xs[q]; xx < xs[q] + ws[q]; xx += tw * k) part(&cell, a, frame, q * tw, r * th, tw, th, xx, yy, k);
        }
}
