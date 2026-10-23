/* The world's picture bent after it is drawn (post.h): a copy of it is kept and each moved pixel is read from the
 * copy at its displaced place (nearest neighbour: the picture stays pixel art). The copy lives in slow memory and is
 * made the first time something asks for it. A ring of radius 60 moves about six thousand pixels: well under a
 * millisecond on the console; the haze moves whole rows, memmove-cheap. */
#include <math.h>
#include <stdlib.h>
#include <string.h>

#include "hal.h"
#include "post.h"

#define MAX_SHOCKS 4

static struct { float x, y, r, width, amp; } shocks[MAX_SHOCKS];
static int nshocks;
#define MAX_ZONES 4
typedef struct { int x0, y0, x1, y1; float amp, phase, period; bool water; } zone_t;
static zone_t zones[MAX_ZONES];
static int nzones;
static struct { float scan, persist; bool on; } crt;
static uint16_t *phos; /* the last frame as the phosphor still glows it (persistence) */
static int phos_n;
static uint32_t frames; /* rendered frames, for the zones' own animation */
static uint16_t *copy;
static int copy_n;

void post_reset(void) {
    nshocks = 0;
    nzones = 0;
}

void post_free(void) { /* a game ended */
    post_reset();
    free(copy), copy = NULL, copy_n = 0;
    free(phos), phos = NULL, phos_n = 0;
    crt.on = false, frames = 0;
}

bool post_any(void) { return nshocks > 0 || nzones > 0 || crt.on; }

void post_crt(bool on, float scan, float persist) {
    crt.on = on, crt.scan = scan < 0 ? 0 : scan > 1 ? 1 : scan, crt.persist = persist < 0 ? 0 : persist > 0.95f ? 0.95f : persist;
    if (!on || crt.persist <= 0) free(phos), phos = NULL, phos_n = 0;
}

void post_shock(float x, float y, float r, float width, float amp) {
    if (nshocks >= MAX_SHOCKS || !(r > 0) || !(width > 0)) return;
    shocks[nshocks++] = (typeof(shocks[0])){x, y, r, width, amp};
}

void post_zone(int x0, int y0, int x1, int y1, bool water, float amp, float phase, float period) {
    if (nzones >= MAX_ZONES) return;
    if (y1 < y0) { int t = y0; y0 = y1, y1 = t; }
    if (x1 < x0) { int t = x0; x0 = x1, x1 = t; }
    zones[nzones++] = (zone_t){x0, y0, x1, y1, amp, phase, period > 0.01f ? period : 0.01f, water};
}

void post_haze(int y0, int y1, float amp, float phase, float period) { post_zone(0, y0, 1 << 20, y1, false, amp, phase, period); }

/* The rows the effects read: the haze's, and each ring's reach (a ring reads up to its radius and width around its
 * centre; a shifted row reads only itself). Copying the whole picture every frame was a millisecond on the console
 * for a haze of twenty rows. */
static void rows_read(int h, int *y0, int *y1) {
    int a = h, b = -1;
    for (int k = 0; k < nzones; k++) { /* (water also reads a few rows above and below: its swell moves things up and down) */
        const int m = zones[k].water ? (int)ceilf(fabsf(zones[k].amp)) : 0;
        a = zones[k].y0 - m < a ? zones[k].y0 - m : a, b = zones[k].y1 + m > b ? zones[k].y1 + m : b;
    }
    for (int k = 0; k < nshocks; k++) {
        const int lo = (int)floorf(shocks[k].y - shocks[k].r - shocks[k].width - fabsf(shocks[k].amp)) - 1;
        const int hi = (int)ceilf(shocks[k].y + shocks[k].r + shocks[k].width + fabsf(shocks[k].amp)) + 1;
        a = lo < a ? lo : a, b = hi > b ? hi : b;
    }
    *y0 = a < 0 ? 0 : a, *y1 = b >= h ? h - 1 : b;
}

static bool keep_copy(const uint16_t *world, int w, int h) {
    if (copy_n != w * h) {
        copy = hal_realloc_slow(copy, (size_t)w * h * sizeof *copy);
        copy_n = copy ? w * h : 0;
    }
    if (!copy) return false;
    int y0, y1;
    rows_read(h, &y0, &y1);
    if (y1 >= y0) memcpy(copy + (size_t)y0 * w, world + (size_t)y0 * w, (size_t)(y1 - y0 + 1) * w * sizeof *copy);
    return true;
}

/* A zone: heat moves each row sideways by amp * sin(y / period + phase); water also lifts each column by half that, so the picture
 * wobbles both ways as light does through water. Only the pixels inside the rectangle change. */
static void apply_zone(uint16_t *world, int w, int h, const zone_t *z) {
    const int y0 = z->y0 < 0 ? 0 : z->y0, y1 = z->y1 >= h ? h - 1 : z->y1, x0 = z->x0 < 0 ? 0 : z->x0, x1 = z->x1 >= w ? w - 1 : z->x1;
    for (int y = y0; y <= y1; y++) {
        const int dx = (int)lroundf(z->amp * sinf((float)y / z->period * 6.2831853f + z->phase));
        uint16_t *dst = world + (size_t)y * w;
        if (!z->water) {
            if (!dx) continue;
            const uint16_t *src = copy + (size_t)y * w;
            for (int x = x0; x <= x1; x++) {
                int sx = x - dx;
                sx = sx < 0 ? 0 : sx >= w ? w - 1 : sx;
                dst[x] = src[sx];
            }
            continue;
        }
        for (int x = x0; x <= x1; x++) {
            const int dy = (int)lroundf(z->amp * 0.5f * sinf((float)x / (z->period * 1.7f) * 6.2831853f + z->phase * 1.3f));
            int sx = x - dx, sy = y - dy;
            sx = sx < 0 ? 0 : sx >= w ? w - 1 : sx;
            sy = sy < 0 ? 0 : sy >= h ? h - 1 : sy;
            dst[x] = copy[(size_t)sy * w + sx];
        }
    }
}

static void apply_shock(uint16_t *world, int w, int h, int k) {
    const float cx = shocks[k].x, cy = shocks[k].y, r = shocks[k].r, wd = shocks[k].width, amp = shocks[k].amp;
    const int x0 = (int)floorf(cx - r - wd), x1 = (int)ceilf(cx + r + wd), y0 = (int)floorf(cy - r - wd), y1 = (int)ceilf(cy + r + wd);
    for (int y = y0 < 0 ? 0 : y0; y <= y1 && y < h; y++)
        for (int x = x0 < 0 ? 0 : x0; x <= x1 && x < w; x++) {
            const float dx = (float)x - cx, dy = (float)y - cy, d = sqrtf(dx * dx + dy * dy);
            const float off = fabsf(d - r);
            if (off >= wd || d < 0.001f) continue;
            const float m = amp * (1 - off / wd) / d; /* outward, strongest on the ring */
            int sx = (int)lroundf((float)x - dx * m), sy = (int)lroundf((float)y - dy * m);
            sx = sx < 0 ? 0 : sx >= w ? w - 1 : sx;
            sy = sy < 0 ? 0 : sy >= h ? h - 1 : sy;
            world[(size_t)y * w + x] = copy[(size_t)sy * w + sx];
        }
}

/* RGB565 channels scaled by k/256, per channel (a phosphor fading, a scanline dimming) */
static inline uint16_t scale565(uint16_t c, int k) {
    return (uint16_t)(((((c >> 11) * k) >> 8) << 11) | (((((c >> 5) & 63) * k) >> 8) << 5) | (((c & 31) * k) >> 8));
}

/* The glass: the last frame's glow decays (persist) and stays where the new frame is darker, a channel at a time; then every second row of the
 * picture is dimmed (scan) as the gaps between a tube's lines. The glow is kept before the lines are dimmed, so they do not feed back. */
static void apply_crt(uint16_t *world, int w, int h) {
    const int n = w * h;
    if (crt.persist > 0) {
        if (phos_n != n) {
            phos = hal_realloc_slow(phos, (size_t)n * sizeof *phos);
            phos_n = phos ? n : 0;
            if (phos) memcpy(phos, world, (size_t)n * sizeof *phos);
        }
        if (phos) {
            const int k = (int)(crt.persist * 256);
            for (int i = 0; i < n; i++) {
                const uint16_t p = scale565(phos[i], k), c = world[i];
                const uint16_t r = (p >> 11) > (c >> 11) ? p & 0xF800 : c & 0xF800, g = ((p >> 5) & 63) > ((c >> 5) & 63) ? p & 0x07E0 : c & 0x07E0,
                               b = (p & 31) > (c & 31) ? p & 31 : c & 31;
                world[i] = phos[i] = (uint16_t)(r | g | b);
            }
        }
    }
    if (crt.scan > 0) {
        const int k = (int)((1 - crt.scan) * 256);
        for (int y = 1; y < h; y += 2) {
            uint16_t *row = world + (size_t)y * w;
            for (int x = 0; x < w; x++) row[x] = scale565(row[x], k);
        }
    }
}

void post_apply(uint16_t *world, int w, int h) {
    if (!post_any()) return;
    frames++;
    if (nzones || nshocks) {
        if (!keep_copy(world, w, h)) { post_reset(); return; }
        for (int k = 0; k < nzones; k++) apply_zone(world, w, h, &zones[k]);
        if (nshocks && nzones) keep_copy(world, w, h); /* the rings bend the bent picture */
        for (int k = 0; k < nshocks; k++) {
            if (k) keep_copy(world, w, h); /* each ring over the last's */
            apply_shock(world, w, h, k);
        }
    }
    if (crt.on) apply_crt(world, w, h);
    post_reset();
}

float post_time(void) { return (float)frames / 60.0f; } /* seconds of rendered frames, for a zone that animates by itself */
