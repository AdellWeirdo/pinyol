#include <stdlib.h>
/* Headless HAL: logs to stderr, no audio device (so no lock is needed). */
#include <stdarg.h>
#include <stdio.h>
#include <time.h>

#include "hal.h"

void hal_log(const char *fmt, ...) {
    va_list ap;
    va_start(ap, fmt);
    vfprintf(stderr, fmt, ap);
    va_end(ap);
    fputc('\n', stderr);
}

void hal_audio_lock(void) {}
void hal_audio_unlock(void) {}
int hal_audio_latency(void) { return -1; } /* no speaker: what is mixed is the clock (main.c mixes each tick) */

void *hal_realloc_slow(void *p, size_t n) { return realloc(p, n); }

void hal_parallel(void (*fn)(int part, void *ctx), void *ctx) { fn(0, ctx), fn(1, ctx); }

uint32_t hal_micros(void) {
    struct timespec t;
    clock_gettime(CLOCK_MONOTONIC, &t);
    return (uint32_t)(t.tv_sec * 1000000 + t.tv_nsec / 1000);
}

bool hal_can_switch_game(void) { return getenv("BP_SWITCH_GAME") != NULL; } /* to see the console's title menu */
void hal_switch_game(void) {}

/* The console's games, for its menu (src/lua_console.c): here the folders in $PINYOL_GAMES; a launch ends the run. */
static int last_game = -1;
int hal_games(hal_game *g, int max, int *last, bool *cold) {
    static bool woke = true;
    *last = last_game, *cold = woke;
    woke = false;
    return console_dir_games(getenv("PINYOL_GAMES"), g, max);
}
bool hal_game_cover(const char *id, uint16_t *px, int w, int h) {
    const char *root = getenv("PINYOL_GAMES");
    char dir[512];
    if (!root) return false;
    snprintf(dir, sizeof dir, "%s/%s", root, id);
    return console_dir_cover(dir, px, w, h);
}
void hal_launch(const char *id) { hal_log("console: launch %s", id); }
void hal_power_off(void) { hal_log("console: off"); }
const char *hal_firmware(void) { return "escritorio"; }

/* The link (src/link.c): by default a quiet air, where tests make other consoles speak (script: link_from);
 * BP_LINK=udp joins the desktop's real one (platform/link_udp.c), so headless runs can play each other. */
#include <string.h>

#include "../link_udp.h"

static bool udp;

bool hal_link_open(void) {
    const char *e = getenv("BP_LINK");
    udp = e && !strcmp(e, "udp");
    return udp ? link_udp_open() : true;
}
void hal_link_close(void) {
    if (udp) link_udp_close();
}
bool hal_link_send(const uint8_t *p, int n) { return udp ? link_udp_send(p, n) : true; }
int hal_link_recv(uint8_t *p, int max) { return udp ? link_udp_recv(p, max) : 0; }
uint32_t hal_link_id(void) {
    const char *e = getenv("BP_LINK_ID");
    return udp ? link_udp_id() : e ? (uint32_t)strtoul(e, NULL, 16) : 0x0A0B0C0D;
}

/* No microphone: tests make one up (script: mic, src/mic.c) */
bool hal_mic_open(void) { return false; }
void hal_mic_close(void) {}
int hal_mic_read(int16_t *p, int max) { return (void)p, (void)max, 0; }

void hal_led(int rgb) { (void)rgb; }                                            /* (tests read it: expect_led) */
bool hal_battery(float *level, bool *charging) { return (void)level, (void)charging, false; } /* (script: battery) */
