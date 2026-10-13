/* Platform contract. The core never includes SDL or ESP-IDF headers.
 * A platform owns its main loop: it polls input into hal_input, calls game_tick() at
 * TICK_HZ, calls game_render() into a 480x320 RGB565 buffer and presents it, and calls
 * audio_mix() from its audio callback/task while holding the audio lock. */
#pragma once
#include <stdbool.h>
#include <stddef.h>
#include <stdint.h>

enum {
    ACT_UP = 1 << 0, ACT_DOWN = 1 << 1, ACT_LEFT = 1 << 2, ACT_RIGHT = 1 << 3,
    ACT_OK = 1 << 4,    /* A / Enter / E */
    ACT_BACK = 1 << 5,  /* B / Esc */
    ACT_NEXT = 1 << 6,  /* C / Tab: cycle target, puzzle help */
    ACT_INV = 1 << 7,   /* MENU / I */
    ACT_NOTES = 1 << 8, /* J (no hardware button: reachable from pause and inventory) */
    ACT_PAUSE = 1 << 9, /* START / P */
    ACT_QUIT = 1 << 10, /* desktop window close */
};

typedef struct {
    uint16_t held;  /* ACT_* bits currently down */
    bool touch;     /* finger / mouse button down */
    int16_t px, py; /* pointer in native 480x320 coordinates */
} hal_input;

void hal_log(const char *fmt, ...);
/* A platform with a game list (the console) gets "Otros juegos" on the title screen; hal_switch_game() asks it to
 * leave this game for the list once the current tick ends. Desktop platforms answer false and do nothing. */
bool hal_can_switch_game(void);
void hal_switch_game(void);
void hal_audio_lock(void);
void hal_audio_unlock(void);
/* fn(0, ctx) here and fn(1, ctx) on the other core, if there is one; returns when both are done. They must not
 * touch the same memory. */
void hal_parallel(void (*fn)(int part, void *ctx), void *ctx);
uint32_t hal_micros(void); /* a microsecond clock, for timing (wraps after ~71 minutes) */
/* realloc for big or script data, in memory that may be slower (PSRAM on the console); free() releases it. */
void *hal_realloc_slow(void *p, size_t n);

/* A radio to other consoles nearby, for link.c: packets of up to HAL_LINK_MAX bytes sent to every console in range,
 * which may be lost (ESP-NOW on the console, UDP on a desktop's network, a BroadcastChannel between browser tabs). */
#define HAL_LINK_MAX 250
bool hal_link_open(void);                    /* the radio on; false: this platform has none */
void hal_link_close(void);
bool hal_link_send(const uint8_t *p, int n); /* to everyone; false if it could not go */
int hal_link_recv(uint8_t *p, int max);      /* one packet that came in (bytes), or 0 */
uint32_t hal_link_id(void);                  /* this console's id: not 0, the same while it runs */

/* The microphone, for mic.c: mono PCM16 at AUDIO_HZ. hal_mic_open starts listening (false: this platform has none,
 * or the player said no); hal_mic_read hands over what came in since the last call, up to max samples (0: nothing). */
bool hal_mic_open(void);
void hal_mic_close(void);
int hal_mic_read(int16_t *p, int max);
