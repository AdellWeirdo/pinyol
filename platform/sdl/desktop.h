/* The Cirera desktop app's files (desktop.c): its menu and games, and a dropped .zip installed. */
#ifndef PINYOL_DESKTOP_H
#define PINYOL_DESKTOP_H
#include <stdbool.h>
#include <stddef.h>

/* The menu's folder and the games' (made, and given the games the app comes with): false if either is missing. */
bool desktop_paths(char *menu, char *games, size_t n);
/* The game in zip installed into games; name gets its folder's name. */
bool desktop_install(const char *zip, const char *games, char *name, size_t name_max);
#endif
