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

void *hal_realloc_slow(void *p, size_t n) { return realloc(p, n); }

void hal_parallel(void (*fn)(int part, void *ctx), void *ctx) { fn(0, ctx), fn(1, ctx); }

uint32_t hal_micros(void) {
    struct timespec t;
    clock_gettime(CLOCK_MONOTONIC, &t);
    return (uint32_t)(t.tv_sec * 1000000 + t.tv_nsec / 1000);
}

bool hal_can_switch_game(void) { return getenv("BP_SWITCH_GAME") != NULL; } /* to see the console's title menu */
void hal_switch_game(void) {}

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
