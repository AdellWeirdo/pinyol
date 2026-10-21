/* perf("lua"): a sampling profiler of the game's Lua, by function (lua_prof.c) */
#pragma once
#include <stdbool.h>
#include <stdio.h>

#include "lua.h"

typedef struct { const char *name; float self_ms, total_ms; } prof_row;

void prof_start(void);         /* from now on every call into the game is sampled */
void prof_stop(void);          /* off, and what was counted forgotten */
bool prof_on(void);
void prof_new_state(void);    /* the game's Lua state is closing: keep the counts, forget its functions' identities */
void prof_arm(lua_State *L, const char *entry); /* before each call into the game (_update...): the sampling hook, or none */
int prof_rows(prof_row *rows, int max, float *total_ms); /* functions, dearest own time first; total_ms: all Lua time sampled */
int prof_folded(FILE *f);      /* every stack seen, "root;...;leaf us" a line; returns the lines */
