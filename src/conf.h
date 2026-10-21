/* The console's own settings, kept outside any game and inherited by every one (sysmenu.c shows them, conf.c keeps
 * them): the volume of everything, less flashing, a colour filter for colour-blind players, the game's speed, the
 * language of what the engine says, and A and B swapped. A platform keeps them in its own folder (hal_console_dir);
 * without one (the headless player) they are the defaults, and a test script sets them. */
#pragma once
#include <stdbool.h>
#include <stdint.h>

enum { CONF_ES, CONF_CA, CONF_EN };
enum { CONF_COLOUR_NORMAL, CONF_COLOUR_PROTAN, CONF_COLOUR_DEUTAN, CONF_COLOUR_TRITAN };

typedef struct {
    int volume;        /* 0..100, of everything the console sounds (a game's own volume() is inside it) */
    bool reduce_flash; /* less flashing: settings().reduce_flashing for games, and the built-in libraries damp theirs */
    int colour;        /* CONF_COLOUR_*: the world's colours shifted so the pairs that player cannot tell apart differ */
    int speed;         /* 100, 75 or 50: the share of ticks the game gets (its music keeps its own pace) */
    int lang;          /* CONF_ES, CONF_CA, CONF_EN: the system menu, the crash screen */
    bool swap_ab;      /* A and B swapped, for every game */
} conf_t;

extern conf_t CONF;

void conf_load(void);  /* from the platform's folder, or the defaults; applies them (volume, colour) */
void conf_save(void);  /* after a change in the system menu */
void conf_apply(void); /* what the settings do outside the menu: the user's volume, the colour filter's table */
void conf_free(void);  /* a game ended: the filter's table let go */
bool conf_set(const char *key, const char *value); /* "volume" "80", "flash" "less"/"normal", "colour" "protan"..., "speed" "50",
                                                    * "lang" "ca", "swap_ab" "true": false if unknown or out of range */
/* The colour filter on a picture's pixels, in place (RGB565): nothing when it is off. */
void conf_filter(uint16_t *px, int n);
bool conf_filter_on(void);
const char *conf_lang_code(void); /* "es", "ca" or "en" */
