/* The simulator's captures (platform/sdl/capture.c) on a made-up screen: a PNG, the cover, and a GIF of the ring; the
 * files are checked by tests/capture_check.py (PIL opens them and reads the pixels back). Takes the folder to write in. */
#include <stdio.h>
#include <string.h>

#include "bp.h"
#include "capture.h"

int main(int argc, char **argv) {
    if (argc < 2) return 2;
    static uint16_t fb[SCREEN_W * SCREEN_H];
    for (int k = 0; k < 20; k++) { /* twenty frames: a red band moving down a blue screen */
        for (int y = 0; y < SCREEN_H; y++)
            for (int x = 0; x < SCREEN_W; x++) fb[y * SCREEN_W + x] = y >= k * 10 && y < k * 10 + 40 ? 0xF800 : 0x001F;
        capture_frame(fb);
    }
    if (!capture_png(fb, argv[1])) return printf("capture_test: no png\n"), 1;
    printf("%s\n", capture_last());
    if (!capture_cover(fb, argv[1])) return printf("capture_test: no cover\n"), 1;
    printf("%s\n", capture_last());
    if (!capture_gif(argv[1])) return printf("capture_test: no gif\n"), 1;
    printf("%s\n", capture_last());
    return 0;
}
