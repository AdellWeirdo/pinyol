/* What the console remembers of its games (played.c), kept in its own folder (hal_console_dir, played.json) and
 * shared with the menu: how many times each was played and for how long, when last, whether it is a favourite,
 * and the achievements earned in it (a game's game.json lists them: "achievements": [{"id", "name", "description"}]). */
#pragma once
#include <stdbool.h>
#include <stdint.h>

void played_begin(const char *id); /* a game starts */
void played_end(uint32_t ticks);   /* it ends, having run that many ticks: the time added, written */
void played_free(void);            /* and the record let go until the next game asks */
bool played_favourite(const char *id, int set); /* -1 asks, 0 or 1 sets; returns it */
bool played_achieve(const char *game, const char *id); /* earned now (written); false if it already was */
bool played_achieved(const char *game, const char *id);
/* all of it as JSON text for Lua: {"<id>": {"plays": n, "seconds": s, "last": unix, "fav": bool, "done": ["ach", ...]}} */
const char *played_json(void);
