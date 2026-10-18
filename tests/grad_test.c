/* A dithered gradient from a table worked out ahead (gfx_grad_table, as the overlay does when it records one) draws exactly the pixels the
 * gradient works out for itself: down and across, on a plain buffer and on the console's turned strips both ways round and both byte
 * orders, whole and cut into strips, with the box partly off the surface. */
#include <stdio.h>
#include <stdlib.h>
#include <string.h>

#include "bp.h"

static int failures, checks;
#define CHECK(c)                                                                  \
    do {                                                                          \
        checks++;                                                                 \
        if (!(c)) failures++, fprintf(stderr, "%s:%d: CHECK(%s)\n", __FILE__, __LINE__, #c); \
    } while (0)

enum { FW = 96, FH = 64 };

static void draw(uint16_t *out, int row0, int rows, bool turned, bool flip, bool swap, int x, int y, int w, int h, bool across,
                 bool use_table) {
    surface s = turned ? gfx_turned(out, row0, rows, FW, FH, flip, swap) : (surface){.px = out, .w = FW, .h = FH};
    const uint8_t c1[3] = {10, 200, 90}, c2[3] = {250, 30, 140};
    uint16_t *table = NULL;
    if (use_table) {
        table = malloc((size_t)(across ? w : h) * 4 * sizeof *table);
        gfx_grad_table(table, x, y, w, h, c1, c2, across);
    }
    gfx_grad(&s, x, y, w, h, c1, c2, across, true, BLEND_ALPHA, 256, table);
    free(table);
}

static void compare(bool turned, bool flip, bool swap, int x, int y, int w, int h, bool across) {
    static uint16_t a[FW * FH], b[FW * FH];
    memset(a, 0x5A, sizeof a), memset(b, 0x5A, sizeof b);
    if (!turned) {
        draw(a, 0, FW, false, false, false, x, y, w, h, across, false);
        draw(b, 0, FW, false, false, false, x, y, w, h, across, true);
    } else {
        for (int r0 = 0; r0 < FW; r0 += 32) { /* the strips, as the console draws them */
            draw(a + (size_t)r0 * FH, r0, 32, true, flip, swap, x, y, w, h, across, false);
            draw(b + (size_t)r0 * FH, r0, 32, true, flip, swap, x, y, w, h, across, true);
        }
    }
    int diff = 0;
    for (size_t i = 0; i < sizeof a / sizeof *a; i++) diff += a[i] != b[i];
    CHECK(diff == 0);
    int touched = 0;
    for (size_t i = 0; i < sizeof a / sizeof *a; i++) touched += a[i] != 0x5A5A;
    CHECK(touched > 0 || x >= FW || y >= FH || x + w <= 0 || y + h <= 0); /* (it did draw something, where it should) */
}

int main(void) {
    const int boxes[][4] = {{0, 0, FW, FH}, {5, 3, 40, 50}, {-10, -7, 60, 40}, {50, 30, 100, 80}, {33, 0, 1, FH}, {0, 61, FW, 3}, {7, 9, 31, 33}};
    for (unsigned k = 0; k < sizeof boxes / sizeof boxes[0]; k++)
        for (int across = 0; across < 2; across++) {
            const int *b = boxes[k];
            compare(false, false, false, b[0], b[1], b[2], b[3], across);
            for (int flip = 0; flip < 2; flip++)
                for (int swap = 0; swap < 2; swap++) compare(true, flip, swap, b[0], b[1], b[2], b[3], across);
        }
    printf("grad_test: %d checks, %d failures\n", checks, failures);
    return failures != 0;
}
