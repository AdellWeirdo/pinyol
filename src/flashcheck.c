/* Flashing that can hurt (flashcheck.h). The screen in 16 x 10 cells of 30 x 32 pixels; each cell's relative luminance
 * (WCAG's, from the linear channels) is the mean of a quarter of its pixels. A cell's luminance going up by 0.1 or
 * more from its last turning point, then down by 0.1 or more (or the other way), with the darker side under 0.8, is
 * a transition each way; two transitions are a flash; more than six transitions in 60 frames is over the limit for
 * that cell. The verdict is the share of cells over it. Red flashes (WCAG's second rule) are not looked at. */
#include <math.h>
#include <string.h>

#include "bp.h"
#include "flashcheck.h"

#define CW 16
#define CH 10
#define CELL_W (SCREEN_W / CW)
#define CELL_H (SCREEN_H / CH)
#define WINDOW 60
#define MAX_T 16 /* transitions remembered per cell */

static float lin5[32], lin6[64];
static bool tables;

static struct {
    float extreme;          /* the luminance at the last turning point */
    int dir;                /* 1 going up since it, -1 going down, 0 at the start */
    uint32_t at[MAX_T];     /* frames of the last transitions, a ring */
    int n;
} C[CW * CH];
static uint32_t frame;

static void make_tables(void) {
    for (int i = 0; i < 32; i++) {
        float s = i / 31.0f;
        lin5[i] = s <= 0.04045f ? s / 12.92f : powf((s + 0.055f) / 1.055f, 2.4f);
    }
    for (int i = 0; i < 64; i++) {
        float s = i / 63.0f;
        lin6[i] = s <= 0.04045f ? s / 12.92f : powf((s + 0.055f) / 1.055f, 2.4f);
    }
    tables = true;
}

void flash_reset(void) {
    memset(C, 0, sizeof C);
    frame = 0;
}

static float cell_lum(const uint16_t *fb, int cx, int cy) {
    float sum = 0;
    int n = 0;
    for (int y = cy * CELL_H; y < (cy + 1) * CELL_H; y += 2)
        for (int x = cx * CELL_W; x < (cx + 1) * CELL_W; x += 2, n++) {
            const uint16_t v = fb[y * SCREEN_W + x];
            sum += 0.2126f * lin5[v >> 11] + 0.7152f * lin6[v >> 5 & 63] + 0.0722f * lin5[v & 31];
        }
    return sum / (float)n;
}

int flash_frame(const uint16_t *fb) {
    if (!tables) make_tables();
    frame++;
    int over = 0;
    for (int cy = 0; cy < CH; cy++)
        for (int cx = 0; cx < CW; cx++) {
            typeof(C[0]) *c = &C[cy * CW + cx];
            const float l = cell_lum(fb, cx, cy);
            if (frame == 1) { c->extreme = l, c->dir = 0; continue; }
            const float d = l - c->extreme;
            if (c->dir >= 0 && d <= -0.1f && l < 0.8f) { /* it was going up (or nothing yet): a fall of 0.1 or more */
                if (c->dir == 1) c->at[c->n++ % MAX_T] = frame;
                c->dir = -1, c->extreme = l;
            } else if (c->dir <= 0 && d >= 0.1f && c->extreme < 0.8f) {
                if (c->dir == -1) c->at[c->n++ % MAX_T] = frame;
                c->dir = 1, c->extreme = l;
            } else if ((c->dir == 1 && l > c->extreme) || (c->dir == -1 && l < c->extreme)) {
                c->extreme = l; /* further the same way: the turning point moves */
            }
            int recent = 0;
            for (int i = 0; i < c->n && i < MAX_T; i++)
                if (c->at[i] + WINDOW > frame) recent++;
            if (recent > 6) over++;
        }
    return over * 100 / (CW * CH);
}
