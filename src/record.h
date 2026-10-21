/* A play recorded as a test script (record.c): every tick's buttons and fingers, as `in` lines the headless player
 * plays back (docs/lua.md, Testing). One file is a bug report, a regression test and a replay: a game is
 * deterministic given its input, so the same lines give the same frames. The simulator records with --record FILE
 * or F8; the recording starts when the game's own ticks do (after the careta). */
#pragma once
#include <stdbool.h>

#include "hal.h"

bool record_start(const char *path, const char *game_id);
void record_tick(const hal_input *in); /* each tick of the game (game.c) */
void record_stop(void);                /* writes what is pending and closes */
bool record_on(void);
