/* Test builds only (-DBP_REMOTE=ON): the console driven over its USB cable while nobody is at it, by
 * tools/remote.py. One command per line on the serial port:
 *   tap X Y    a finger down at (X, Y) for a few polls, then lifted
 *   key NAME   A, B, C, UP, DOWN, LEFT, RIGHT, START or MENU, held for a few polls
 *   shot       the frame last sent to the panel: "SHOT <w> <h>", one base64 line per row (RGB565 LE), "SHOT END" */
#include "remote.h"

#include <stdio.h>
#include <string.h>

#include "bp.h"
#include "display.h"
#include "driver/usb_serial_jtag.h"
#include "driver/usb_serial_jtag_vfs.h"
#include "freertos/FreeRTOS.h"
#include "freertos/task.h"
#include "mbedtls/base64.h"

#define HOLD 4 /* polls an injected input lasts: long enough for the game's edge detection */

static char line[48];
static int len;
static bool overlong; /* a line longer than the buffer is dropped whole, not run cut short */
static hal_input inject;
static int hold;
static bool ready;

void remote_init(void) {
    usb_serial_jtag_driver_config_t cfg = USB_SERIAL_JTAG_DRIVER_CONFIG_DEFAULT();
    if (usb_serial_jtag_driver_install(&cfg) != ESP_OK) return;
    usb_serial_jtag_vfs_use_driver(); /* the log goes through the driver too, so both directions share it */
    ready = true;
    hal_log("remote: listening (tap, key, shot)");
}

static void shot(void) {
    const uint16_t *px = display_last();
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

static void run(const char *cmd) {
    static const struct { const char *name; uint16_t act; } keys[] = {
        {"A", ACT_OK}, {"B", ACT_BACK}, {"C", ACT_NEXT}, {"UP", ACT_UP}, {"DOWN", ACT_DOWN},
        {"LEFT", ACT_LEFT}, {"RIGHT", ACT_RIGHT}, {"START", ACT_PAUSE}, {"MENU", ACT_INV}};
    int x, y;
    char k[8];
    if (sscanf(cmd, "tap %d %d", &x, &y) == 2) inject = (hal_input){0, true, (int16_t)x, (int16_t)y}, hold = HOLD;
    else if (sscanf(cmd, "key %7s", k) == 1) {
        for (size_t i = 0; i < sizeof keys / sizeof keys[0]; i++)
            if (!strcmp(k, keys[i].name)) inject = (hal_input){keys[i].act, false, 0, 0}, hold = HOLD;
    } else if (!strcmp(cmd, "shot")) shot();
    else return;
    hal_log("remote: %s", cmd);
}

void remote_poll(hal_input *in) {
    if (!ready) return;
    char buf[32];
    int n = usb_serial_jtag_read_bytes(buf, sizeof buf, 0);
    for (int i = 0; i < n; i++) {
        if (buf[i] == '\n' || buf[i] == '\r') {
            line[len] = 0;
            if (len && !overlong) run(line);
            len = 0;
            overlong = false;
        } else if (len < (int)sizeof line - 1) line[len++] = buf[i];
        else overlong = true;
    }
    if (hold > 0) {
        hold--;
        in->held |= inject.held;
        if (inject.touch) in->touch = true, in->px = inject.px, in->py = inject.py;
    }
}
