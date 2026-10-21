/* What a player (or a maker) takes from the simulator's screen (capture.c): a screenshot as PNG (F6), the game's
 * cover from the screen (F7, cover.rgb565 in the game's folder), the last eight seconds as a GIF (F9, kept in a ring
 * while the simulator runs). Files go in the game's saves folder, numbered. Desktop only. */
#pragma once
#include <stdbool.h>
#include <stdint.h>

void capture_frame(const uint16_t *fb);                 /* every frame shown: the ring for the GIF */
bool capture_png(const uint16_t *fb, const char *dir);  /* a screenshot; false if it could not be written */
bool capture_gif(const char *dir);                      /* the ring as a GIF */
bool capture_cover(const uint16_t *fb, const char *game_dir); /* the screen halved, as cover.rgb565 */
const char *capture_last(void);                         /* the path of the last file written */
