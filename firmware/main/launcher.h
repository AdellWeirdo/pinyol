#pragma once
#include <stdbool.h>
#include <stdint.h>

#define LAUNCHER_MAX 32 /* the list shows LAUNCHER_ROWS at a time and scrolls */
#define LAUNCHER_ROWS 4

typedef struct {
    char id[32], dir[96], title[48], subtitle[64];
    bool no_music;   /* only in the flash image: it plays without its music and ambience */
    uint16_t *thumb; /* its title background at half size (LAUNCHER_THUMB_W x _H), or NULL */
} launcher_game;

#define LAUNCHER_THUMB_W 120
#define LAUNCHER_THUMB_H 80

/* The games on the card (/sdcard/games/<id>/game.json), then those only in the flash image; loads the list's font. */
int launcher_scan(launcher_game *g, int max);
#define LAUNCHER_CABLE -3 /* launcher_choose: a game is coming over the cable (cable.c) */
/* The console's game list until a row is chosen: its index, -1 for "Apagar" or LAUNCHER_CABLE. Returns once nothing
 * is held. */
int launcher_choose(uint16_t *frames[2], const launcher_game *g, int n);
/* pinyol's logo on the ink, the screen while the console starts (no font needed: before launcher_scan works). */
void launcher_splash(uint16_t *frame);
/* One line of text and, when percent >= 0, a progress bar: the screen for a firmware update. */
void launcher_message(uint16_t *frame, const char *text, int percent);
