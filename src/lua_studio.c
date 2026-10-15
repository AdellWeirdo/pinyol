/* The studio (docs/lua.md, "The studio"): a step sequencer in the audio thread, every step on its sample.
 *
 *   studio.tempo(bpm [, swing]);  studio.length(steps);  studio.track(i, {sound, gain, pitch, choke}) -> loaded?
 *   studio.steps(i, {v, v, ...});  studio.play([step]);  studio.stop();  studio.playing()
 *   studio.pos() -> step, fraction (what the player hears now; nil when stopped);  studio.hit(i [, velocity]) */
#include <string.h>

#include "lua_api.h"

static int track_arg(lua_State *L, int a) {
    lua_Integer i = luaL_checkinteger(L, a);
    if (i < 1 || i > STUDIO_TRACKS)
        return luaL_error(L, "studio: track %d does not exist (1 to %d)", (int)i, STUDIO_TRACKS);
    return (int)i - 1;
}

static int l_tempo(lua_State *L) { /* studio.tempo(bpm [, swing]): 30..300 BPM; swing 50 (straight) to 75 % */
    studio_tempo(fin(luaL_checknumber(L, 1)), lua_isnoneornil(L, 2) ? -1 : fin(luaL_checknumber(L, 2)));
    return 0;
}

static int l_length(lua_State *L) {
    lua_Integer n = luaL_checkinteger(L, 1);
    if (n < 1 || n > STUDIO_STEPS) return luaL_error(L, "studio.length: %d steps (1 to %d)", (int)n, STUDIO_STEPS);
    studio_length((int)n);
    return 0;
}

/* studio.track(i, {sound, gain, pitch, choke}): what is left out stays as it was. True if its sound is loaded. */
static int l_track(lua_State *L) {
    int i = track_arg(L, 1);
    luaL_checktype(L, 2, LUA_TTABLE);
    lua_getfield(L, 2, "sound");
    const char *sound = lua_isnil(L, -1) ? NULL : luaL_checkstring(L, -1);
    if (sound && (!safe_name(sound) || strlen(sound) >= 32)) return luaL_error(L, "studio.track: \"%s\" is not a sound name", sound);
    float gain = opt_float(L, 2, "gain", -1, -1, 1), pitch = opt_float(L, 2, "pitch", -1, -1, 16);
    lua_getfield(L, 2, "choke");
    int choke = lua_isnil(L, -1) ? -1 : (int)luaL_checkinteger(L, -1);
    if (choke < -1 || choke > 15) return luaL_error(L, "studio.track: choke group %d (0, none, to 15)", choke);
    lua_pushboolean(L, studio_track(i, sound, gain, pitch, choke));
    return 1;
}

/* studio.steps(i, {v, v, ...}): each step's velocity, 0 (silent) to 1; true and false are 1 and 0. */
static int l_steps(lua_State *L) {
    int i = track_arg(L, 1);
    luaL_checktype(L, 2, LUA_TTABLE);
    float vel[STUDIO_STEPS];
    int n = (int)luaL_len(L, 2);
    if (n > STUDIO_STEPS) return luaL_error(L, "studio.steps: %d steps (%d at most)", n, STUDIO_STEPS);
    for (int s = 0; s < n; s++) {
        lua_rawgeti(L, 2, s + 1);
        vel[s] = lua_isboolean(L, -1) ? (float)lua_toboolean(L, -1) : lua_isnil(L, -1) ? 0 : fin(luaL_checknumber(L, -1));
        lua_pop(L, 1);
    }
    studio_steps(i, vel, n);
    return 0;
}

static int l_play(lua_State *L) {
    studio_play((int)luaL_optinteger(L, 1, 1) - 1);
    return 0;
}

static int l_stop(lua_State *L) {
    (void)L;
    studio_stop();
    return 0;
}

static int l_playing(lua_State *L) {
    lua_pushboolean(L, studio_playing());
    return 1;
}

static int l_pos(lua_State *L) { /* studio.pos() -> step (1 = the first), fraction into it; nil before one is heard */
    int step;
    float frac;
    if (!studio_pos(&step, &frac)) return 0;
    lua_pushinteger(L, step + 1);
    lua_pushnumber(L, frac);
    return 2;
}

static int l_hit(lua_State *L) {
    studio_hit(track_arg(L, 1), lua_isnoneornil(L, 2) ? 1 : fin(luaL_checknumber(L, 2)));
    return 0;
}

void studio_register(lua_State *L) {
    static const luaL_Reg F[] = {{"tempo", l_tempo}, {"length", l_length}, {"track", l_track}, {"steps", l_steps},
                                 {"play", l_play}, {"stop", l_stop}, {"playing", l_playing}, {"pos", l_pos},
                                 {"hit", l_hit}, {NULL, NULL}};
    luaL_newlib(L, F);
    lua_setglobal(L, "studio");
}
