/* The world's picture bent after it is drawn (post.h): a copy of it is kept and each moved pixel is read from the
 * copy at its displaced place (nearest neighbour: the picture stays pixel art). The copy lives in slow memory and is
 * made the first time something asks for it. A ring of radius 60 moves about six thousand pixels: well under a
 * millisecond on the console; the haze moves whole rows, memmove-cheap. */
#include <math.h>
#include <string.h>

#include "hal.h"
#include "post.h"

#define MAX_SHOCKS 4

static struct { float x, y, r, width, amp; } shocks[MAX_SHOCKS];
static int nshocks;
static struct { int y0, y1; float amp, phase, period; bool on; } haze;
static uint16_t *copy;
static int copy_n;

void post_reset(void) {
    nshocks = 0;
    haze.on = false;
}

bool post_any(void) { return nshocks > 0 || haze.on; }

void post_shock(float x, float y, float r, float width, float amp) {
    if (nshocks >= MAX_SHOCKS || !(r > 0) || !(width > 0)) return;
    shocks[nshocks++] = (typeof(shocks[0])){x, y, r, width, amp};
}

void post_haze(int y0, int y1, float amp, float phase, float period) {
    if (y1 < y0) { int t = y0; y0 = y1, y1 = t; }
    haze.y0 = y0, haze.y1 = y1, haze.amp = amp, haze.phase = phase, haze.period = period > 0.01f ? period : 0.01f, haze.on = true;
}

static bool keep_copy(const uint16_t *world, int w, int h) {
    if (copy_n != w * h) {
        copy = hal_realloc_slow(copy, (size_t)w * h * sizeof *copy);
        copy_n = copy ? w * h : 0;
    }
    if (!copy) return false;
    memcpy(copy, world, (size_t)w * h * sizeof *copy);
    return true;
}

static void apply_haze(uint16_t *world, int w, int h) {
    const int y0 = haze.y0 < 0 ? 0 : haze.y0, y1 = haze.y1 >= h ? h - 1 : haze.y1;
    for (int y = y0; y <= y1; y++) {
        const int dx = (int)lroundf(haze.amp * sinf((float)y / haze.period * 6.2831853f + haze.phase));
        if (!dx) continue;
        const uint16_t *src = copy + (size_t)y * w;
        uint16_t *dst = world + (size_t)y * w;
        for (int x = 0; x < w; x++) {
            int sx = x - dx;
            sx = sx < 0 ? 0 : sx >= w ? w - 1 : sx;
            dst[x] = src[sx];
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

void post_apply(uint16_t *world, int w, int h) {
    if (!post_any()) return;
    if (!keep_copy(world, w, h)) { post_reset(); return; }
    if (haze.on) apply_haze(world, w, h);
    if (nshocks && haze.on) memcpy(copy, world, (size_t)w * h * sizeof *copy); /* the rings bend the hazed picture */
    for (int k = 0; k < nshocks; k++) {
        if (k) memcpy(copy, world, (size_t)w * h * sizeof *copy); /* each ring over the last's */
        apply_shock(world, w, h, k);
    }
    post_reset();
}
