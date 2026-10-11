#include <stdlib.h>
/* Headless HAL: logs to stderr, no audio device (so no lock is needed). */
#include <stdarg.h>
#include <stdio.h>

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

bool hal_can_switch_game(void) { return getenv("BP_SWITCH_GAME") != NULL; } /* to see the console's title menu */
void hal_switch_game(void) {}
