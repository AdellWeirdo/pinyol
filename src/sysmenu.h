/* The console's own menu over any Lua game (sysmenu.c): a tap of MENU (or MENU held a second, in a game that reads
 * MENU itself) pauses the game and offers to go on, start again, the game's own items (menuitem in Lua), the console's
 * settings (conf.h) and the list; MENU held two seconds still goes to the list. The crash screen is here too: a game
 * stopped on an error shows it whole, A starts the game again, B goes to the list. */
#pragma once
#include <stdbool.h>

#include "bp.h"

bool sysmenu_tick(void);   /* each tick of a Lua game, with G.in read: true when the game gets this tick (not paused, not skipped by the speed) */
bool sysmenu_paused(void); /* the menu or the crash screen is up: the picture stays as it was */
void sysmenu_draw(surface *s); /* over the game's picture */
void sysmenu_reset(void);  /* a game starts: closed, no items */
bool sysmenu_open(void);   /* the menu is up */
void sysmenu_crash(const char *error); /* the game stopped: what the crash screen says (and its QR code) */
int sysmenu_qr_size(void);             /* modules a side of the crash's QR code, 0 when none shows (tests) */
