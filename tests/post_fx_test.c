/* The world's post effects (post.c): a distort zone moves only the pixels inside its rectangle (heat sideways, water both ways); crt() dims every
 * second row, and its persistence keeps a fading glow where the picture went dark, and turns off cleanly. */
#include <stdio.h>
#include <string.h>

#include "post.h"

#define W 32
#define H 24
#define WHITE 0xFFFF
#define RED 0xF800

static int failures;
#define CHECK(c, ...)                                                                                                       \
    do {                                                                                                                    \
        if (!(c)) failures++, fprintf(stderr, "%s:%d: CHECK(%s) ", __FILE__, __LINE__, #c), fprintf(stderr, __VA_ARGS__), fputc('\n', stderr); \
    } while (0)

static uint16_t px[W * H], ref[W * H];

static void stripes(void) { /* a picture whose every row is told apart by its column: pixel = column */
    for (int y = 0; y < H; y++)
        for (int x = 0; x < W; x++) px[y * W + x] = (uint16_t)(x + 1);
}

int main(void) {
    post_free();
    stripes(), memcpy(ref, px, sizeof px);
    post_zone(8, 4, 15, 11, false, 3, 0.25f, 8); /* heat inside columns 8-15, rows 4-11 */
    post_apply(px, W, H);
    int moved = 0;
    for (int y = 0; y < H; y++)
        for (int x = 0; x < W; x++) {
            const bool inside = x >= 8 && x <= 15 && y >= 4 && y <= 11;
            if (!inside) CHECK(px[y * W + x] == ref[y * W + x], "outside the zone (%d,%d) changed", x, y);
            else moved += px[y * W + x] != ref[y * W + x];
        }
    CHECK(moved > 0, "the heat moved nothing");
    CHECK(!post_any(), "a zone is for one frame only");

    stripes();
    post_zone(0, 8, W - 1, 15, true, 4, 0, 6); /* water: columns' values change by rows too, but rows outside stay */
    post_apply(px, W, H);
    for (int y = 0; y < H; y++)
        if (y < 8 || y > 15)
            for (int x = 0; x < W; x++) CHECK(px[y * W + x] == ref[y * W + x], "water changed row %d outside", y);

    for (int i = 0; i < W * H; i++) px[i] = WHITE;
    post_crt(true, 0.5f, 0);
    CHECK(post_any(), "crt stays on");
    post_apply(px, W, H);
    CHECK(px[0] == WHITE && px[W] != WHITE && (px[W] >> 11) <= 16, "scanlines: row 0 clear, row 1 dimmed by half, got %04x", px[W]);
    CHECK(px[2 * W] == WHITE && px[3 * W] == px[W], "scanlines every second row");

    post_crt(true, 0, 0.5f); /* persistence: a white frame, then a black one leaves half the glow, then a quarter */
    for (int i = 0; i < W * H; i++) px[i] = WHITE;
    post_apply(px, W, H);
    CHECK(px[5] == WHITE, "the first frame is itself");
    memset(px, 0, sizeof px), post_apply(px, W, H);
    CHECK((px[5] >> 11) == 15 && ((px[5] >> 5) & 63) == 31 && (px[5] & 31) == 15, "half the glow after one dark frame, got %04x", px[5]);
    memset(px, 0, sizeof px), post_apply(px, W, H);
    CHECK((px[5] >> 11) == 7, "a quarter after two, got %04x", px[5]);
    for (int i = 0; i < W * H; i++) px[i] = RED;
    post_apply(px, W, H);
    CHECK((px[5] >> 11) == 31 && (px[5] & 31) < 5, "a brighter channel wins over the glow, a darker one keeps it, got %04x", px[5]);

    post_crt(false, 0, 0);
    memset(px, 0, sizeof px);
    post_apply(px, W, H);
    CHECK(px[5] == 0 && !post_any(), "crt off leaves the picture alone");
    post_free();
    if (failures) return fprintf(stderr, "post_fx: %d failure(s)\n", failures), 1;
    puts("post_fx: ok");
    return 0;
}
