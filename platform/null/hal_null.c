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
