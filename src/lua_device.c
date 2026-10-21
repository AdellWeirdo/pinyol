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

/* tilt() -> x, y, z: the way gravity pulls on the console (-1..1 each), relative to the neutral position tilt_zero() sets
 * (the player holds it as they like, presses A: Kirby Tilt 'n' Tumble's trick); nil on a console without a sensor
 * (docs/hardware-rev2.md: an IMU on the I2C bus, behind hal_imu). Tests: `tilt X Y Z`. */
/* Where there is no sensor and no motor (a desktop, the browser, a console before its rev2): the platform says nothing
 * and these answer. Weak, and in this file, the only one that calls them: MinGW's linker does not let a weak
 * definition in one object of the archive answer another object's reference. */
__attribute__((weak)) bool hal_imu(float *x, float *y, float *z) { (void)x, (void)y, (void)z; return false; }
__attribute__((weak)) void hal_rumble(int ms, float strength) { (void)ms, (void)strength; }

static struct { bool on, have; float x, y, z; } fake_tilt;
static float zero[3];

static bool read_tilt(float *v) {
    if (fake_tilt.on) {
        if (!fake_tilt.have) return false;
        v[0] = fake_tilt.x, v[1] = fake_tilt.y, v[2] = fake_tilt.z;
        return true;
    }
    return hal_imu(&v[0], &v[1], &v[2]);
}

static int l_tilt(lua_State *L) {
    float v[3];
    if (!read_tilt(v)) return lua_pushnil(L), 1;
    for (int i = 0; i < 3; i++) {
        float r = v[i] - zero[i];
        lua_pushnumber(L, r < -1 ? -1 : r > 1 ? 1 : r);
    }
    return 3;
}

static int l_tilt_zero(lua_State *L) { /* the position held now is the neutral one from now on; tilt_zero(false) forgets it */
    float v[3];
    if (lua_isboolean(L, 1) && !lua_toboolean(L, 1)) zero[0] = zero[1] = zero[2] = 0;
    else if (read_tilt(v)) zero[0] = v[0], zero[1] = v[1], zero[2] = 0; /* (z, up and down, keeps its sense) */
    return 0;
}

/* rumble(ms [, strength]): a vibration of that length (strength 0..1, 1); nothing where there is no motor (hal_rumble).
 * Tests: expect_rumble MS. */
static int rumble_last;

static int l_rumble(lua_State *L) {
    int ms = (int)luaL_checkinteger(L, 1);
    float strength = (float)luaL_optnumber(L, 2, 1);
    ms = ms < 0 ? 0 : ms > 5000 ? 5000 : ms;
    strength = strength < 0 ? 0 : strength > 1 ? 1 : strength;
    rumble_last = ms;
    hal_rumble(ms, strength);
    return 0;
}

int device_rumble_last(void) { int r = rumble_last; rumble_last = 0; return r; }

void device_fake_tilt(bool on, bool have, float x, float y, float z) {
    fake_tilt.on = on, fake_tilt.have = have, fake_tilt.x = x, fake_tilt.y = y, fake_tilt.z = z;
}

void device_register(lua_State *L) {
    lua_register(L, "led", l_led);
    lua_register(L, "battery", l_battery);
    lua_register(L, "tilt", l_tilt);
    lua_register(L, "tilt_zero", l_tilt_zero);
    lua_register(L, "rumble", l_rumble);
}

void device_reset(void) { /* a game ends: the LED is the console's again, the tilt's neutral forgotten */
    if (led_now >= 0) hal_led(-1);
    led_now = -1;
    zero[0] = zero[1] = zero[2] = 0;
    rumble_last = 0;
}

int device_led(void) { return led_now; }

void device_fake_battery(bool on, bool have, float level, bool charging) {
    fake.on = on, fake.have = have, fake.level = level, fake.charging = charging;
}
