/* What the files of the Lua API share (lua_game.c, lua_draw.c): reading a game's arguments safely. */
#pragma once
#include <math.h>
#include <string.h>

#include "bp.h"
#include "cJSON.h"
#include "lauxlib.h"
#include "lua.h"

static inline bool safe_name(const char *s) { /* a module or asset name: letters, digits, _ . / and no ".." */
    if (!s || !*s || strstr(s, "..") || *s == '/') return false;
    for (; *s; s++)
        if (!(*s == '_' || *s == '.' || *s == '/' || (*s >= 'a' && *s <= 'z') || (*s >= 'A' && *s <= 'Z') ||
              (*s >= '0' && *s <= '9')))
            return false;
    return true;
}

/* Numbers from a game are made finite and kept within +-NUM_MAX: far beyond any screen or map, and safe in the
 * engine's int arithmetic (NaN, infinities and 1e30 from a buggy or hostile game must not reach it). */
#define NUM_MAX 1000000.0f
static inline float fin(lua_Number v) {
    float f = (float)v;
    return f != f ? 0 : f > NUM_MAX ? NUM_MAX : f < -NUM_MAX ? -NUM_MAX : f;
}
static inline int16_t i16(int v) { return (int16_t)(v < -32768 ? -32768 : v > 32767 ? 32767 : v); }

/* A number argument as an int, rounded down: game code computes positions and colours with fractions. */
static inline int num(lua_State *L, int arg) { return (int)floorf(fin(luaL_checknumber(L, arg))); }
static inline int optnum(lua_State *L, int arg, int d) { return lua_isnoneornil(L, arg) ? d : num(L, arg); }

static inline uint16_t to565(lua_Integer rgb) {
    unsigned r = (rgb >> 16) & 255, g = (rgb >> 8) & 255, b = rgb & 255;
    return (uint16_t)((r >> 3) << 11 | (g >> 2) << 5 | b >> 3);
}


static inline bool opt_bool(lua_State *L, int t, const char *k, bool d) {
    lua_getfield(L, t, k);
    bool v = lua_isnil(L, -1) ? d : lua_toboolean(L, -1);
    lua_pop(L, 1);
    return v;
}

static inline lua_Integer opt_int(lua_State *L, int t, const char *k, lua_Integer d) {
    lua_getfield(L, t, k);
    lua_Integer v = lua_isnil(L, -1) ? d : luaL_checkinteger(L, -1);
    lua_pop(L, 1);
    return v;
}

static inline const char *opt_str(lua_State *L, int t, const char *k) {
    lua_getfield(L, t, k);
    const char *v = lua_tostring(L, -1); /* the table keeps the string alive */
    lua_pop(L, 1);
    return v;
}

static inline float opt_float(lua_State *L, int t, const char *k, float d, float lo, float hi) {
    lua_getfield(L, t, k);
    float v = lua_isnil(L, -1) ? d : fin(luaL_checknumber(L, -1));
    lua_pop(L, 1);
    return v < lo ? lo : v > hi ? hi : v;
}

/* lua_draw.c: what is drawn at the screen's full resolution, text, shapes, pictures and canvases */
void draw_register(lua_State *L); /* the API's drawing functions, as globals */
void draw_frame_begin(void);      /* before _draw: a new list */
void draw_overlay(surface *s);    /* the list, onto s (a window of the screen or all of it) */
bool draw_covers_screen(void);    /* the list starts with a full-screen opaque picture: the world need not be drawn */
void draw_free(void);             /* the game's fonts, when its Lua state goes */
void draw_flush(void);            /* after each call into the game: the masks of the canvases it drew on */

/* lua_game.c: a game's values as JSON and back (store, link) */
cJSON *json_from_lua(lua_State *L, int i, int depth, const char *who, int *count);
void json_to_lua(lua_State *L, const cJSON *v, int depth);

/* lua_link.c: link.send, link.recv, link.peers, link.id */
void link_register(lua_State *L);

/* lua_sound.c: sound, sfx, sfx_set, sfx_stop, sfx_on, music, music_layer, tone, note */
void sound_register(lua_State *L);

/* lua_draw.c: a swarm's points drawn, each as the picture centred on it (lua_swarm.c) */
void draw_points(const asset *a, int frame, const float *x, const float *y, int n);
void swarm_register(lua_State *L); /* swarm(): lua_swarm.c */
void physics_register(lua_State *L); /* physics_turning(), for lib/physics.lua: lua_physics.c */
void physics_free(void);
void clip_register(lua_State *L); /* video(): clips on a canvas, lua_clip.c */
void clip_tick(void);             /* each tick: the clips playing move on */
void clip_free_all(void);
void device_register(lua_State *L); /* led(), battery(): lua_device.c */
void grid_register(lua_State *L);   /* grid(): paths, reach, distances, layers: lua_grid.c */
void device_reset(void);
