/* Test builds only (-DBP_REMOTE=ON): the console driven over its USB cable while nobody is at it, by
 * tools/remote.py. One command per line on the serial port (read by cable.c, which hands over what is not its own):
 *   tap X Y    a finger down at (X, Y) for a few polls, then lifted
 *   key NAME [N]  A, B, C, UP, DOWN, LEFT, RIGHT, START or MENU, held for N polls (a few by default)
 *   lua CODE   pinyol@2: runs CODE in the game (print() answers in the log), as a test script's lua line
 *   shot       the frame last sent to the panel: "SHOT <w> <h>", one base64 line per row (RGB565 LE), "SHOT END" */
#include "remote.h"

#include <stdio.h>
#include <string.h>

#include "bp.h"
#include "display.h"
#include "freertos/FreeRTOS.h"
#include "freertos/task.h"
#include "mbedtls/base64.h"

#define HOLD 4 /* polls an injected input lasts: long enough for the game's edge detection */

static hal_input inject;
static int hold;
static bool ready;

void remote_init(void) { ready = true; hal_log("remote: listening (tap, key, lua, shot)"); }

static void shot(void) {
    const uint16_t *px = remote_picture();
    if (!px) return;
    static unsigned char out[SCREEN_W * 2 * 4 / 3 + 8];
    printf("SHOT %d %d\n", SCREEN_W, SCREEN_H);
    for (int y = 0; y < SCREEN_H; y++) {
        size_t n = 0;
        mbedtls_base64_encode(out, sizeof out, &n, (const unsigned char *)(px + y * SCREEN_W), SCREEN_W * 2);
        out[n] = 0;
        printf("%s\n", out);
        if (y % 8 == 7) vTaskDelay(1); /* a dump takes seconds: let the idle task feed the watchdog */
    }
    printf("SHOT END\n");
    fflush(stdout);
}

void remote_line(const char *cmd) {
    static const struct { const char *name; uint16_t act; } keys[] = {
        {"A", ACT_OK}, {"B", ACT_BACK}, {"C", ACT_NEXT}, {"UP", ACT_UP}, {"DOWN", ACT_DOWN},
        {"LEFT", ACT_LEFT}, {"RIGHT", ACT_RIGHT}, {"START", ACT_PAUSE}, {"MENU", ACT_INV}};
    int x, y, n = HOLD;
    char k[8];
    if (!strncmp(cmd, "lua ", 4)) { /* not echoed: a bot asks many times a second, print() is the answer */
        char msg[120];
        if (!v2_run(cmd + 4, false, msg, sizeof msg)) hal_log("remote: lua failed: %s", msg);
        return;
    }
    if (sscanf(cmd, "tap %d %d", &x, &y) == 2) inject = (hal_input){.touch = true, .px = (int16_t)x, .py = (int16_t)y}, hold = HOLD;
    else if (sscanf(cmd, "key %7s %d", k, &n) >= 1) {
        for (size_t i = 0; i < sizeof keys / sizeof keys[0]; i++)
            if (!strcmp(k, keys[i].name)) inject = (hal_input){.held = keys[i].act}, hold = n < 1 ? 1 : n > 600 ? 600 : n;
    } else if (!strcmp(cmd, "shot")) shot();
    else return;
    hal_log("remote: %s", cmd);
}

void remote_input(hal_input *in) {
    if (!ready || hold <= 0) return;
    hold--;
    in->held |= inject.held;
    if (inject.touch) in->touch = true, in->px = inject.px, in->py = inject.py;
}
