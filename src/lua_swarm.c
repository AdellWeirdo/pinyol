/* Swarms: many things that move the same simple way (bullets, sparks, rain, stars, a crowd), moved, culled, tested
 * and drawn here in C. In Lua each one costs some microseconds to move and as many to draw, so a few hundred of them
 * take a console's whole frame; a swarm costs one call to step and one to draw them all (docs/lua.md, "Swarms").
 *
 *   local orbs = swarm(600 [, {x0, y0, x1, y1}])   -- room for 600; those that leave the area go (default: the
 *                                                  -- screen and 32 pixels around it)
 *   orbs:add(x, y, vx, vy [, life])                -- false when full; life in ticks (0 or none: until it leaves)
 *   orbs:step()                                    -- each moves by its speed; those out of the area or of life go
 *   orbs:draw(picture [, frame])                   -- each drawn centred on its point
 *   orbs:hit(x, y, w, h [, keep])                  -- how many are in that box; they go, unless keep
 *   orbs:get(i) / orbs:set(i, x, y [, vx, vy])     -- one of them, 1..#orbs; orbs:remove(i); orbs:clear(); #orbs
 */
#include "lua_api.h"

#define SWARM_MAX 4096

typedef struct {
    int n, cap;
    float x0, y0, x1, y1; /* the area: those that leave it go */
    float *x, *y, *vx, *vy;
    uint16_t *life;       /* ticks left; 0: no end */
} swarm;

static swarm *check(lua_State *L) { return luaL_checkudata(L, 1, "np2d.swarm"); }

static void drop(swarm *s, int i) { /* the last one takes its place: order is not kept, nothing moves */
    int k = --s->n;
    s->x[i] = s->x[k], s->y[i] = s->y[k], s->vx[i] = s->vx[k], s->vy[i] = s->vy[k], s->life[i] = s->life[k];
}

static int index_arg(lua_State *L, const swarm *s) {
    lua_Integer i = luaL_checkinteger(L, 2);
    luaL_argcheck(L, i >= 1 && i <= s->n, 2, "no such one in the swarm");
    return (int)i - 1;
}

static int l_swarm(lua_State *L) { /* swarm(cap [, {x0, y0, x1, y1}]) */
    lua_Integer cap = luaL_checkinteger(L, 1);
    luaL_argcheck(L, cap >= 1 && cap <= SWARM_MAX, 1, "a swarm holds 1 to 4096");
    size_t bytes = sizeof(swarm) + (size_t)cap * (4 * sizeof(float) + sizeof(uint16_t));
    swarm *s = lua_newuserdatauv(L, bytes, 0);
    memset(s, 0, bytes);
    float *f = (float *)(s + 1);
    s->cap = (int)cap, s->x = f, s->y = f + cap, s->vx = f + 2 * cap, s->vy = f + 3 * cap;
    s->life = (uint16_t *)(f + 4 * cap);
    s->x0 = -32, s->y0 = -32, s->x1 = SCREEN_W + 32, s->y1 = SCREEN_H + 32;
    if (lua_istable(L, 2)) {
        float a[4];
        for (int i = 0; i < 4; i++) {
            lua_rawgeti(L, 2, i + 1);
            a[i] = fin(luaL_checknumber(L, -1));
            lua_pop(L, 1);
        }
        s->x0 = a[0], s->y0 = a[1], s->x1 = a[2], s->y1 = a[3];
    }
    luaL_setmetatable(L, "np2d.swarm");
    return 1;
}

static int l_add(lua_State *L) {
    swarm *s = check(L);
    if (s->n == s->cap) return lua_pushboolean(L, 0), 1;
    int i = s->n++;
    s->x[i] = fin(luaL_checknumber(L, 2)), s->y[i] = fin(luaL_checknumber(L, 3));
    s->vx[i] = fin(luaL_optnumber(L, 4, 0)), s->vy[i] = fin(luaL_optnumber(L, 5, 0));
    lua_Integer life = luaL_optinteger(L, 6, 0);
    s->life[i] = (uint16_t)(life < 0 ? 0 : life > 65535 ? 65535 : life);
    lua_pushboolean(L, 1);
    return 1;
}

static int l_step(lua_State *L) {
    swarm *s = check(L);
    for (int i = 0; i < s->n;) {
        s->x[i] += s->vx[i], s->y[i] += s->vy[i];
        bool gone = s->x[i] < s->x0 || s->x[i] >= s->x1 || s->y[i] < s->y0 || s->y[i] >= s->y1;
        if (s->life[i] && --s->life[i] == 0) gone = true;
        if (gone) drop(s, i); /* the last one, not yet stepped, comes to i: the loop steps it next */
        else i++;
    }
    return 0;
}

static int l_draw(lua_State *L) {
    swarm *s = check(L);
    const char *id = luaL_checkstring(L, 2);
    asset *a = safe_name(id) ? gfx_asset(id) : NULL;
    if (!a || a->missing) return 0;
    lua_Integer f = luaL_optinteger(L, 3, 0);
    draw_points(a, (int)(f < 0 || f >= a->frames ? 0 : f), s->x, s->y, s->n);
    return 0;
}

static int l_hit(lua_State *L) {
    swarm *s = check(L);
    float x = fin(luaL_checknumber(L, 2)), y = fin(luaL_checknumber(L, 3));
    float w = fin(luaL_checknumber(L, 4)), h = fin(luaL_checknumber(L, 5));
    bool keep = lua_toboolean(L, 6);
    int hits = 0;
    for (int i = 0; i < s->n;) {
        if (s->x[i] >= x && s->x[i] < x + w && s->y[i] >= y && s->y[i] < y + h) {
            hits++;
            if (!keep) {
                drop(s, i);
                continue;
            }
        }
        i++;
    }
    lua_pushinteger(L, hits);
    return 1;
}

static int l_get(lua_State *L) {
    swarm *s = check(L);
    int i = index_arg(L, s);
    lua_pushnumber(L, s->x[i]), lua_pushnumber(L, s->y[i]), lua_pushnumber(L, s->vx[i]), lua_pushnumber(L, s->vy[i]);
    lua_pushinteger(L, s->life[i]);
    return 5;
}

static int l_set(lua_State *L) {
    swarm *s = check(L);
    int i = index_arg(L, s);
    s->x[i] = fin(luaL_checknumber(L, 3)), s->y[i] = fin(luaL_checknumber(L, 4));
    if (!lua_isnoneornil(L, 5)) s->vx[i] = fin(luaL_checknumber(L, 5));
    if (!lua_isnoneornil(L, 6)) s->vy[i] = fin(luaL_checknumber(L, 6));
    return 0;
}

static int l_remove(lua_State *L) {
    swarm *s = check(L);
    drop(s, index_arg(L, s));
    return 0;
}

static int l_clear(lua_State *L) {
    check(L)->n = 0;
    return 0;
}

static int l_len(lua_State *L) {
    lua_pushinteger(L, check(L)->n);
    return 1;
}

void swarm_register(lua_State *L) {
    static const luaL_Reg M[] = {{"add", l_add}, {"step", l_step}, {"draw", l_draw}, {"hit", l_hit}, {"get", l_get},
                                 {"set", l_set}, {"remove", l_remove}, {"clear", l_clear}, {NULL, NULL}};
    luaL_newmetatable(L, "np2d.swarm");
    lua_newtable(L);
    luaL_setfuncs(L, M, 0);
    lua_setfield(L, -2, "__index");
    lua_pushcfunction(L, l_len);
    lua_setfield(L, -2, "__len");
    lua_pop(L, 1);
    lua_register(L, "swarm", l_swarm);
}
