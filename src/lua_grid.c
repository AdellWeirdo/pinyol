/* Grids for a game's thinking, in C: where to walk, how far a unit can go, what a crowd heads for, a smell or a noise
 * spreading through the rooms (docs/lua.md, "Grids"). Cells are counted from 0, as mget's.
 *
 *   local g = grid(w, h [, cost])       -- every cell costs cost (1) to enter; 0 is a wall; up to 255
 *   g:set(x, y, cost); g:get(x, y); g:size()
 *   g:path(x0, y0, x1, y1 [, {diagonal}]) -> {{x, y}, ...} to the goal (not the start), and its cost; nil: no way
 *   g:reach(x, y, budget [, {diagonal}])  -> {{x, y, cost}, ...}: every cell it can get to for that much
 *   g:distances(x, y | {{x, y}, ...} [, {diagonal}]) -> a layer: the cost from each cell to the nearest target
 *   local l = g:layer([value])          -- a number on each cell: a smell, a noise, heat, danger
 *   l:get(x, y); l:set(x, y, v); l:add(x, y, v); l:fill(v)
 *   l:spread(rate, fade)                -- each cell moves rate (0..1) of the way to its open neighbours' mean, then
 *                                          all of it fades by fade (0..1); walls hold nothing
 *   l:climb(x, y) / l:descend(x, y)     -> dx, dy: the open neighbour with the most / the least (0, 0: none) */
#include <stdlib.h>

#include "lua_api.h"

#define SIDE_MAX 256
#define STRAIGHT 10 /* path costs in tenths: a diagonal step is 14 */
#define DIAGONAL 14
#define FAR 0x7FFFFFFF

typedef struct {
    int w, h;
    uint8_t cost[]; /* 0: a wall */
} grid;

typedef struct {
    int w, h;
    float *v, *tmp; /* (in the same block, after the struct) */
} layer;

static const int DX[8] = {1, -1, 0, 0, 1, 1, -1, -1}, DY[8] = {0, 0, 1, -1, 1, -1, 1, -1};

static grid *check_grid(lua_State *L) { return luaL_checkudata(L, 1, "np2d.grid"); }
static layer *check_layer(lua_State *L) { return luaL_checkudata(L, 1, "np2d.layer"); }

static bool on(int w, int h, int x, int y) { return x >= 0 && y >= 0 && x < w && y < h; }

/* a cell argument: false if outside (or not a number that fits) */
static bool cell(lua_State *L, int arg, int w, int h, int *x, int *y) {
    *x = num(L, arg), *y = num(L, arg + 1);
    return on(w, h, *x, *y);
}

static bool diagonal_opt(lua_State *L, int arg) {
    if (lua_isnoneornil(L, arg)) return false;
    luaL_checktype(L, arg, LUA_TTABLE);
    return opt_bool(L, arg, "diagonal", false);
}

static int l_grid(lua_State *L) { /* grid(w, h [, cost]) */
    int w = num(L, 1), h = num(L, 2);
    lua_Integer c = luaL_optinteger(L, 3, 1);
    luaL_argcheck(L, w >= 1 && h >= 1 && w <= SIDE_MAX && h <= SIDE_MAX, 1, "a grid is 1 to 256 cells a side");
    luaL_argcheck(L, c >= 0 && c <= 255, 3, "a cell costs 0 (a wall) to 255");
    grid *g = lua_newuserdatauv(L, sizeof(grid) + (size_t)w * h, 0);
    g->w = w, g->h = h;
    memset(g->cost, (int)c, (size_t)w * h);
    luaL_setmetatable(L, "np2d.grid");
    return 1;
}

static int g_set(lua_State *L) {
    grid *g = check_grid(L);
    int x, y;
    lua_Integer c = luaL_checkinteger(L, 4);
    luaL_argcheck(L, c >= 0 && c <= 255, 4, "a cell costs 0 (a wall) to 255");
    if (cell(L, 2, g->w, g->h, &x, &y)) g->cost[y * g->w + x] = (uint8_t)c;
    return 0;
}

static int g_get(lua_State *L) {
    grid *g = check_grid(L);
    int x, y;
    if (!cell(L, 2, g->w, g->h, &x, &y)) return lua_pushnil(L), 1;
    lua_pushinteger(L, g->cost[y * g->w + x]);
    return 1;
}

static int g_size(lua_State *L) {
    grid *g = check_grid(L);
    lua_pushinteger(L, g->w), lua_pushinteger(L, g->h);
    return 2;
}

/* ------------------------------------------------------------------ the search: Dijkstra, or A* with a goal */

typedef struct {
    int32_t *dist, *from, *heap, *pos; /* pos: where a cell is in the heap, -1 not in it */
    uint8_t *done;
    int n;
} search;

static void s_free(search *s) { free(s->dist); }

static bool s_init(search *s, int cells) {
    size_t sz = (size_t)cells * (4 * sizeof(int32_t) + 1);
    uint8_t *m = hal_realloc_slow(NULL, sz); /* (PSRAM on the console: up to 1.1 MB for 256x256) */
    if (!m) return false;
    s->dist = (int32_t *)m, s->from = s->dist + cells, s->heap = s->from + cells, s->pos = s->heap + cells;
    s->done = (uint8_t *)(s->pos + cells), s->n = 0;
    for (int i = 0; i < cells; i++) s->dist[i] = FAR, s->from[i] = -1, s->pos[i] = -1;
    memset(s->done, 0, (size_t)cells);
    return true;
}

/* the heap is ordered by key: the distance, plus the estimate to the goal for A* */
static int32_t key_of(const search *s, const grid *g, int i, int gx, int gy, bool diag) {
    if (gx < 0) return s->dist[i];
    int dx = abs(i % g->w - gx), dy = abs(i / g->w - gy);
    int32_t est = diag ? STRAIGHT * (dx > dy ? dx : dy) + (DIAGONAL - STRAIGHT) * (dx < dy ? dx : dy)
                       : STRAIGHT * (dx + dy); /* cells cost at least 1: never more than the true cost */
    return s->dist[i] + est;
}

static void swap(search *s, int a, int b) {
    int32_t t = s->heap[a];
    s->heap[a] = s->heap[b], s->heap[b] = t;
    s->pos[s->heap[a]] = a, s->pos[s->heap[b]] = b;
}

static void up(search *s, const grid *g, int k, int gx, int gy, bool diag) {
    while (k > 0) {
        int p = (k - 1) / 2;
        if (key_of(s, g, s->heap[p], gx, gy, diag) <= key_of(s, g, s->heap[k], gx, gy, diag)) break;
        swap(s, p, k), k = p;
    }
}

static int pop(search *s, const grid *g, int gx, int gy, bool diag) {
    int top = s->heap[0];
    s->pos[top] = -1;
    if (--s->n > 0) {
        s->heap[0] = s->heap[s->n], s->pos[s->heap[0]] = 0;
        for (int k = 0;;) {
            int l = 2 * k + 1, r = l + 1, m = k;
            if (l < s->n && key_of(s, g, s->heap[l], gx, gy, diag) < key_of(s, g, s->heap[m], gx, gy, diag)) m = l;
            if (r < s->n && key_of(s, g, s->heap[r], gx, gy, diag) < key_of(s, g, s->heap[m], gx, gy, diag)) m = r;
            if (m == k) break;
            swap(s, k, m), k = m;
        }
    }
    return top;
}

static void relax(search *s, const grid *g, int i, int32_t d, int from, int gx, int gy, bool diag) {
    if (d >= s->dist[i]) return;
    s->dist[i] = d, s->from[i] = from;
    if (s->pos[i] < 0) s->heap[s->n] = i, s->pos[i] = s->n++;
    up(s, g, s->pos[i], gx, gy, diag);
}

/* From the cells already in the heap, until the goal is done (gx >= 0) or nothing is left, or past budget. */
static void run(search *s, const grid *g, int gx, int gy, bool diag, int32_t budget) {
    int goal = gx >= 0 ? gy * g->w + gx : -1;
    while (s->n > 0) {
        int i = pop(s, g, gx, gy, diag);
        s->done[i] = 1;
        if (i == goal) return;
        int x = i % g->w, y = i / g->w;
        for (int d = 0; d < (diag ? 8 : 4); d++) {
            int nx = x + DX[d], ny = y + DY[d];
            if (!on(g->w, g->h, nx, ny)) continue;
            int j = ny * g->w + nx;
            if (!g->cost[j] || s->done[j]) continue;
            if (d >= 4 && (!g->cost[y * g->w + nx] || !g->cost[ny * g->w + x])) continue; /* no cutting corners */
            int32_t nd = s->dist[i] + (d < 4 ? STRAIGHT : DIAGONAL) * g->cost[j];
            if (nd <= budget) relax(s, g, j, nd, i, gx, gy, diag);
        }
    }
}

static int g_path(lua_State *L) { /* g:path(x0, y0, x1, y1 [, {diagonal}]) */
    grid *g = check_grid(L);
    int x0, y0, x1, y1;
    bool diag = diagonal_opt(L, 6);
    if (!cell(L, 2, g->w, g->h, &x0, &y0) || !cell(L, 4, g->w, g->h, &x1, &y1)) return lua_pushnil(L), 1;
    int a = y0 * g->w + x0, b = y1 * g->w + x1;
    if (!g->cost[b]) return lua_pushnil(L), 1;
    search s;
    if (!s_init(&s, g->w * g->h)) return luaL_error(L, "grid path: out of memory");
    s.dist[a] = 0, s.heap[0] = a, s.pos[a] = 0, s.n = 1;
    run(&s, g, x1, y1, diag, FAR - 255 * DIAGONAL);
    if (s.dist[b] == FAR) {
        s_free(&s);
        return lua_pushnil(L), 1;
    }
    int len = 0;
    for (int i = b; i != a; i = s.from[i]) len++;
    lua_createtable(L, len, 0);
    int k = len;
    for (int i = b; i != a; i = s.from[i], k--) {
        lua_createtable(L, 2, 0);
        lua_pushinteger(L, i % g->w), lua_rawseti(L, -2, 1);
        lua_pushinteger(L, i / g->w), lua_rawseti(L, -2, 2);
        lua_rawseti(L, -2, k);
    }
    lua_pushnumber(L, s.dist[b] / (lua_Number)STRAIGHT);
    s_free(&s);
    return 2;
}

static int g_reach(lua_State *L) { /* g:reach(x, y, budget [, {diagonal}]) */
    grid *g = check_grid(L);
    int x, y;
    float budget = fin(luaL_checknumber(L, 4));
    bool diag = diagonal_opt(L, 5);
    lua_newtable(L);
    if (!cell(L, 2, g->w, g->h, &x, &y) || budget < 0) return 1;
    search s;
    if (!s_init(&s, g->w * g->h)) return luaL_error(L, "grid reach: out of memory");
    int a = y * g->w + x;
    s.dist[a] = 0, s.heap[0] = a, s.pos[a] = 0, s.n = 1;
    run(&s, g, -1, -1, diag, (int32_t)(budget * STRAIGHT + 0.5f));
    int k = 0;
    for (int i = 0; i < g->w * g->h; i++) {
        if (s.dist[i] == FAR) continue;
        lua_createtable(L, 3, 0);
        lua_pushinteger(L, i % g->w), lua_rawseti(L, -2, 1);
        lua_pushinteger(L, i / g->w), lua_rawseti(L, -2, 2);
        lua_pushnumber(L, s.dist[i] / (lua_Number)STRAIGHT), lua_rawseti(L, -2, 3);
        lua_rawseti(L, -2, ++k);
    }
    s_free(&s);
    return 1;
}

/* ------------------------------------------------------------------ layers */

static layer *new_layer(lua_State *L, int gi, float v) { /* a layer over the grid at stack index gi */
    grid *g = lua_touserdata(L, gi);
    size_t cells = (size_t)g->w * g->h;
    layer *l = lua_newuserdatauv(L, sizeof(layer) + 2 * cells * sizeof(float), 1);
    l->w = g->w, l->h = g->h, l->v = (float *)(l + 1), l->tmp = l->v + cells;
    for (size_t i = 0; i < cells; i++) l->v[i] = v;
    luaL_setmetatable(L, "np2d.layer");
    lua_pushvalue(L, gi), lua_setiuservalue(L, -2, 1); /* it keeps its grid (its walls) */
    return l;
}

static const grid *grid_of(lua_State *L) { /* the layer at 1's grid */
    lua_getiuservalue(L, 1, 1);
    const grid *g = lua_touserdata(L, -1);
    lua_pop(L, 1); /* (the layer keeps it alive) */
    return g;
}

static int g_layer(lua_State *L) { /* g:layer([value]) */
    check_grid(L);
    new_layer(L, 1, fin(luaL_optnumber(L, 2, 0)));
    return 1;
}

static int g_distances(lua_State *L) { /* g:distances(x, y | {{x, y}, ...} [, {diagonal}]) -> a layer */
    grid *g = check_grid(L);
    int cells = g->w * g->h, opt = lua_istable(L, 2) ? 3 : 4;
    bool diag = diagonal_opt(L, opt);
    search s;
    if (!s_init(&s, cells)) return luaL_error(L, "grid distances: out of memory");
    int x, y;
    if (lua_istable(L, 2)) {
        int n = (int)lua_rawlen(L, 2);
        for (int k = 1; k <= n; k++) {
            lua_rawgeti(L, 2, k);
            if (lua_istable(L, -1)) {
                lua_rawgeti(L, -1, 1), lua_rawgeti(L, -2, 2);
                x = lua_isnumber(L, -2) ? (int)floorf(fin(lua_tonumber(L, -2))) : -1;
                y = lua_isnumber(L, -1) ? (int)floorf(fin(lua_tonumber(L, -1))) : -1;
                lua_pop(L, 2);
                if (on(g->w, g->h, x, y) && g->cost[y * g->w + x]) relax(&s, g, y * g->w + x, 0, -1, -1, -1, diag);
            }
            lua_pop(L, 1);
        }
    } else if (cell(L, 2, g->w, g->h, &x, &y) && g->cost[y * g->w + x]) {
        relax(&s, g, y * g->w + x, 0, -1, -1, -1, diag);
    }
    run(&s, g, -1, -1, diag, FAR - 255 * DIAGONAL);
    layer *l = new_layer(L, 1, 0);
    for (int i = 0; i < cells; i++) l->v[i] = s.dist[i] == FAR ? HUGE_VALF : s.dist[i] / (float)STRAIGHT;
    s_free(&s);
    return 1;
}

static int l_get(lua_State *L) {
    layer *l = check_layer(L);
    int x, y;
    if (!cell(L, 2, l->w, l->h, &x, &y) || isinf(l->v[y * l->w + x])) return lua_pushnil(L), 1;
    lua_pushnumber(L, l->v[y * l->w + x]);
    return 1;
}

static int l_set(lua_State *L) {
    layer *l = check_layer(L);
    int x, y;
    float v = fin(luaL_checknumber(L, 4));
    if (cell(L, 2, l->w, l->h, &x, &y)) l->v[y * l->w + x] = v;
    return 0;
}

static int l_add(lua_State *L) {
    layer *l = check_layer(L);
    int x, y;
    float v = fin(luaL_checknumber(L, 4));
    if (cell(L, 2, l->w, l->h, &x, &y) && !isinf(l->v[y * l->w + x])) l->v[y * l->w + x] = fin(l->v[y * l->w + x] + v);
    return 0;
}

static int l_fill(lua_State *L) {
    layer *l = check_layer(L);
    float v = fin(luaL_checknumber(L, 2));
    for (int i = 0; i < l->w * l->h; i++) l->v[i] = v;
    return 0;
}

static int l_spread(lua_State *L) { /* l:spread(rate, fade) */
    layer *l = check_layer(L);
    const grid *g = grid_of(L);
    float rate = fin(luaL_checknumber(L, 2)), fade = fin(luaL_optnumber(L, 3, 0));
    rate = rate < 0 ? 0 : rate > 1 ? 1 : rate, fade = fade < 0 ? 0 : fade > 1 ? 1 : fade;
    for (int y = 0; y < l->h; y++)
        for (int x = 0; x < l->w; x++) {
            int i = y * l->w + x;
            if (!g->cost[i] || isinf(l->v[i])) {
                l->tmp[i] = g->cost[i] ? l->v[i] : 0;
                continue;
            }
            float sum = 0;
            int n = 0;
            for (int d = 0; d < 4; d++) {
                int nx = x + DX[d], ny = y + DY[d], j = ny * l->w + nx;
                if (on(l->w, l->h, nx, ny) && g->cost[j] && !isinf(l->v[j])) sum += l->v[j], n++;
            }
            float v = n ? l->v[i] + rate * (sum / n - l->v[i]) : l->v[i];
            l->tmp[i] = v * (1 - fade);
        }
    float *t = l->v;
    l->v = l->tmp, l->tmp = t;
    return 0;
}

static int towards(lua_State *L, int sign) { /* the open neighbour with the most (sign 1) or the least (-1) */
    layer *l = check_layer(L);
    const grid *g = grid_of(L);
    int x, y, bx = 0, by = 0;
    if (cell(L, 2, l->w, l->h, &x, &y)) {
        float best = l->v[y * l->w + x];
        for (int d = 0; d < 8; d++) {
            int nx = x + DX[d], ny = y + DY[d];
            if (!on(l->w, l->h, nx, ny) || !g->cost[ny * l->w + nx]) continue;
            if (d >= 4 && (!g->cost[y * l->w + nx] || !g->cost[ny * l->w + x])) continue;
            float v = l->v[ny * l->w + nx];
            if (sign > 0 ? v > best : v < best) best = v, bx = DX[d], by = DY[d];
        }
    }
    lua_pushinteger(L, bx), lua_pushinteger(L, by);
    return 2;
}

static int l_climb(lua_State *L) { return towards(L, 1); }
static int l_descend(lua_State *L) { return towards(L, -1); }

static void meta(lua_State *L, const char *name, const luaL_Reg *m) {
    luaL_newmetatable(L, name);
    lua_newtable(L);
    luaL_setfuncs(L, m, 0);
    lua_setfield(L, -2, "__index");
    lua_pop(L, 1);
}

void grid_register(lua_State *L) {
    static const luaL_Reg G[] = {{"set", g_set}, {"get", g_get}, {"size", g_size}, {"path", g_path},
                                 {"reach", g_reach}, {"distances", g_distances}, {"layer", g_layer}, {NULL, NULL}};
    static const luaL_Reg Y[] = {{"get", l_get}, {"set", l_set}, {"add", l_add}, {"fill", l_fill},
                                 {"spread", l_spread}, {"climb", l_climb}, {"descend", l_descend}, {NULL, NULL}};
    meta(L, "np2d.grid", G);
    meta(L, "np2d.layer", Y);
    lua_register(L, "grid", l_grid);
}
