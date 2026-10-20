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

#define HAL_POINTS 5 /* fingers followed at once (the console's ST77922 reports up to 5) */
typedef struct {
    uint16_t held;  /* ACT_* bits currently down */
    bool touch;     /* finger / mouse button down */
    int16_t px, py; /* pointer in native 480x320 coordinates */
    /* every finger down, the first being px, py; a platform that leaves points at 0 has one finger (touch, px, py) */
    uint8_t points;
    int16_t x[HAL_POINTS], y[HAL_POINTS];
} hal_input;

void hal_log(const char *fmt, ...);
/* A platform with a game list (the console) gets "Otros juegos" on the title screen; hal_switch_game() asks it to
 * leave this game for the list once the current tick ends. Desktop platforms answer false and do nothing. */
bool hal_can_switch_game(void);
void hal_switch_game(void);
/* The console's games, for its menu: the game CONSOLE_MENU_ID, a pinyol game (lua_console.c). hal_games fills up
 * to max (never the menu itself), *last the index of the one played last (-1: none), *cold true the first time since
 * power-on; hal_game_cover reads the game's cover (COVER_W x COVER_H, RGB565); hal_launch starts that game once the
 * menu ends; hal_power_off switches off. Desktops list the folders in $PINYOL_GAMES (console_dir_*). */
#define CONSOLE_MENU_ID "cirera"
#define COVER_W 240
#define COVER_H 160
typedef struct {
    char id[32], title[48], subtitle[64];
    bool flash, no_music; /* in the console's flash, so without its music */
} hal_game;
int hal_games(hal_game *g, int max, int *last, bool *cold);
bool hal_game_cover(const char *id, uint16_t *px, int w, int h);
void hal_launch(const char *id);
void hal_power_off(void);
const char *hal_firmware(void); /* the console's firmware version, for its menu (a desktop: "escritorio") */
int console_dir_games(const char *root, hal_game *g, int max);              /* the folders in root that are games */
bool console_dir_cover(const char *dir, uint16_t *px, int w, int h);        /* dir's cover.rgb565 (or BG_TITLE) */
void hal_audio_lock(void);
void hal_audio_unlock(void);
/* Samples between the end of a block audio_mix has just made and the moment its first sample is heard, after what is
 * queued before it; -1 when nothing is heard (tests: the mix itself is the clock). For music_time(). */
int hal_audio_latency(void);
/* fn(0, ctx) here and fn(1, ctx) on the other core, if there is one; returns when both are done. They must not
 * touch the same memory. */
void hal_parallel(void (*fn)(int part, void *ctx), void *ctx);
uint32_t hal_micros(void); /* a microsecond clock, for timing (wraps after ~71 minutes) */
/* A game's saves into their file (save_file_atomic does it, bp.h). The console hands them to a task that writes a
 * moment later, since a FAT write on its flash takes most of a second: several store() in a row become one write and
 * the game does not stop for it. hal_save_flush waits for what is pending (the game ends). Platforms that write at
 * once need not define them: src/lua_game.c has both as weak defaults. */
bool hal_save(const char *path, const char *txt);
void hal_save_flush(void);
/* The wall clock: seconds since 1970 (UTC) in *utc_s and the local time's offset from UTC in minutes in *offset_min; false
 * when this machine does not know the date (the console has no clock of its own: the computer sets it over the cable, and it
 * keeps it while asleep). src/lua_game.c has a weak default from the C library, which computers and browsers use. */
bool hal_clock(int64_t *utc_s, int *offset_min);
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

/* The pilot LED: 0xRRGGBB for a game (a console's has only red and green), -1 back to the console's own. And the
 * battery: level 0..1 and whether it charges; false where it cannot be told. */
void hal_led(int rgb);
bool hal_battery(float *level, bool *charging);
