/* The console itself, for games that reach out of the screen: its pilot LED and its battery.
 *
 *   led(0xRRGGBB)  the LED in that colour (the console's is red and green: no blue); led() gives it back
 *   battery()      -> level 0..1, charging; nil where it cannot be told (a desktop without one)
 *
 * A battery about to die still blinks the LED red over whatever the game asked. */
#include "lua_api.h"

static int led_now = -1;                                     /* -1: the console's own */
static struct { bool on, have, charging; float level; } fake; /* tests: a battery (script: battery) */

static int l_led(lua_State *L) {
    led_now = lua_isnoneornil(L, 1) ? -1 : (int)(luaL_checkinteger(L, 1) & 0xFFFFFF);
    hal_led(led_now);
    return 0;
}

static int l_battery(lua_State *L) {
    float level = 0;
    bool charging = false;
    if (fake.on ? !fake.have : !hal_battery(&level, &charging)) return lua_pushnil(L), 1;
    if (fake.on) level = fake.level, charging = fake.charging;
    lua_pushnumber(L, level < 0 ? 0 : level > 1 ? 1 : level);
    lua_pushboolean(L, charging);
    return 2;
}

void device_register(lua_State *L) {
    lua_register(L, "led", l_led);
    lua_register(L, "battery", l_battery);
}

void device_reset(void) { /* a game ends: the LED is the console's again */
    if (led_now >= 0) hal_led(-1);
    led_now = -1;
}

int device_led(void) { return led_now; }

void device_fake_battery(bool on, bool have, float level, bool charging) {
    fake.on = on, fake.have = have, fake.level = level, fake.charging = charging;
}
