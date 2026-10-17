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
/* The game with that id in the list (n of max rows); one not in it (the list was full) is read and takes the last row, so
 * a game that just came over the cable always starts. Its index, or -1: no such game folder. */
int launcher_find(launcher_game *g, int *n, int max, const char *id);
#define LAUNCHER_CABLE -3 /* launcher_choose: a game is coming over the cable (cable.c) */
/* The console's game list until a row is chosen: its index, -1 for "Apagar" or LAUNCHER_CABLE. Returns once nothing
 * is held. */
int launcher_choose(uint16_t *frames[2], const launcher_game *g, int n);
/* The ink, with pinyol's logo or without (the menu game draws its own), while the console starts. */
void launcher_splash(uint16_t *frame, bool with_logo);
/* The console's menu game (CONSOLE_MENU_ID), found by launcher_scan and kept out of its list; NULL: none. */
const char *launcher_menu_dir(void);
/* One line of text and, when percent >= 0, a progress bar: the screen for a firmware update. */
void launcher_message(uint16_t *frame, const char *text, int percent);
