/* The console's settings (conf.c): conf_set's parsing and ranges, and the colour filter: greys stay grey, a pure red
 * and a pure green come out apart for a protanope (red gains on the channels he sees), and off it changes nothing. */
#include <stdio.h>
#include <stdlib.h>

#include <string.h>

#include "conf.h"
#include "hal.h"

static int fails;
#define CHECK(c) do { if (!(c)) { printf("conf_test: %s (line %d)\n", #c, __LINE__); fails++; } } while (0)

static int r5(uint16_t v) { return v >> 11; }
static int g6(uint16_t v) { return v >> 5 & 63; }
static int b5(uint16_t v) { return v & 31; }

int main(void) {
    conf_load(); /* the headless player has no folder: the defaults */
    CHECK(CONF.volume == 100 && CONF.speed == 100 && !CONF.reduce_flash && CONF.colour == CONF_COLOUR_NORMAL && !CONF.swap_ab);
    CHECK(conf_set("volume", "80") && CONF.volume == 80);
    CHECK(!conf_set("volume", "101") && CONF.volume == 80);
    CHECK(!conf_set("volume", "abc"));
    CHECK(conf_set("volume", "0") && CONF.volume == 0);
    CHECK(conf_set("speed", "75") && CONF.speed == 75 && !conf_set("speed", "60"));
    CHECK(conf_set("flash", "less") && CONF.reduce_flash && conf_set("flash", "normal") && !CONF.reduce_flash);
    CHECK(conf_set("lang", "ca") && CONF.lang == CONF_CA && !conf_set("lang", "fr"));
    CHECK(conf_set("swap_ab", "true") && CONF.swap_ab && !conf_set("swap_ab", "yes"));
    CHECK(conf_set("swap_ab", "false") && conf_set("buttons", "CAB") && !strcmp(CONF.buttons, "CAB"));
    CHECK(!conf_set("buttons", "AAB") && !conf_set("buttons", "ABCD") && !conf_set("buttons", "abc") && !strcmp(CONF.buttons, "CAB"));
    CHECK(conf_input(ACT_OK, false) == ACT_NEXT && conf_input(ACT_BACK, false) == ACT_OK && conf_input(ACT_NEXT | ACT_UP, false) == (ACT_BACK | ACT_UP));
    CHECK(conf_set("buttons", "ABC") && conf_set("hold", "toggle") && CONF.sticky && !conf_set("hold", "maybe"));
    /* sticky: a press latches A, the next press lets it go; nothing latches while the console's menu is up */
    CHECK(conf_input(0, false) == 0 && conf_input(ACT_OK, false) == ACT_OK && conf_input(0, false) == ACT_OK && conf_input(0, false) == ACT_OK);
    CHECK(conf_input(ACT_OK, false) == 0 && conf_input(0, false) == 0 && conf_input(ACT_OK, true) == ACT_OK && conf_input(0, true) == 0);
    CHECK(conf_set("hold", "press") && !CONF.sticky);
    CHECK(!conf_set("nothing", "1"));

    uint16_t grey = 0x8410, red = 0xF800, green = 0x07E0, blue = 0x001F; /* 50% grey, and the three pure colours */
    uint16_t px[4] = {grey, red, green, blue};
    conf_filter(px, 4); /* off: as they were */
    CHECK(px[0] == grey && px[1] == red && px[2] == green && px[3] == blue);
    CHECK(conf_set("colour", "protan") && conf_filter_on());
    conf_filter(px, 4);
    CHECK(abs(r5(px[0]) - 16) <= 1 && abs(g6(px[0]) - 32) <= 2 && abs(b5(px[0]) - 16) <= 1); /* grey stays grey */
    CHECK(g6(px[1]) > 8 && b5(px[1]) > 4);           /* red: what a protanope misses, added where he sees */
    CHECK(px[1] != px[2]);                            /* red and green still apart */
    CHECK(r5(px[3]) <= 2 && b5(px[3]) >= 28);         /* blue, which he sees, nearly as it was */
    CHECK(conf_set("colour", "deutan") && conf_set("colour", "tritan") && conf_set("colour", "normal") && !conf_filter_on());
    printf(fails ? "conf_test: %d failed\n" : "conf_test: ok\n", fails);
    return fails != 0;
}
