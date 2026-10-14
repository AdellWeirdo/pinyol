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

/* The search's memory, kept from one search to the next (PSRAM on the console: up to 1 MB for 256x256): a cell's
 * numbers count only when its seen[] is this search's generation, so nothing is cleared between searches. The heap
 * holds each cell's key with it: comparing never reaches back into the cells. */
typedef struct { int32_t key, idx; } hnode;
typedef struct { int32_t dist, from, pos; uint16_t seen; } scell; /* one cell's numbers together: one cache line */
static struct {
    int cap, n;
    uint16_t gen;
    scell *c;                   /* pos: where the cell is in the heap; -1 not in it; -2 done */
    hnode *heap;
    int gx, gy;                 /* the goal (A*), or gx < 0 */
    bool diag;
} S;

void grid_free(void) { free(S.c), memset(&S, 0, sizeof S); }

static bool s_begin(int cells, int gx, int gy, bool diag) {
    if (cells > S.cap) {
        uint8_t *m = hal_realloc_slow(S.c, (size_t)cells * (sizeof(scell) + sizeof(hnode)));
        if (!m) return false;
        S.c = (scell *)m, S.heap = (hnode *)(S.c + cells), S.cap = cells, S.gen = 0;
        for (int i = 0; i < cells; i++) S.c[i].seen = 0;
    }
    if (++S.gen == 0) { /* (after 65535 searches: once) */
        for (int i = 0; i < S.cap; i++) S.c[i].seen = 0;
        S.gen = 1;
    }
    S.n = 0, S.gx = gx, S.gy = gy, S.diag = diag;
    return true;
}

static int32_t dist_of(int i) { return S.c[i].seen == S.gen ? S.c[i].dist : FAR; }

static int32_t estimate(int x, int y) { /* never more than the true cost: cells cost at least 1 */
    if (S.gx < 0) return 0;
    int dx = abs(x - S.gx), dy = abs(y - S.gy);
    return S.diag ? STRAIGHT * (dx > dy ? dx : dy) + (DIAGONAL - STRAIGHT) * (dx < dy ? dx : dy) : STRAIGHT * (dx + dy);
}

static void place(int k, hnode v) { S.heap[k] = v, S.c[v.idx].pos = k; }

static void up(int k) {
    hnode v = S.heap[k];
    while (k > 0) {
        int p = (k - 1) / 2;
        if (S.heap[p].key <= v.key) break;
        place(k, S.heap[p]), k = p;
    }
    place(k, v);
}

static int pop(void) {
    int top = S.heap[0].idx;
    S.c[top].pos = -2;
    if (--S.n > 0) {
        hnode v = S.heap[S.n];
        int k = 0;
        for (;;) {
            int l = 2 * k + 1, r = l + 1, m = k;
            int32_t mk = v.key;
            if (l < S.n && S.heap[l].key < mk) m = l, mk = S.heap[l].key;
            if (r < S.n && S.heap[r].key < mk) m = r;
            if (m == k) break;
            place(k, S.heap[m]), k = m;
        }
        place(k, v);
    }
    return top;
}

static void relax(int i, int x, int y, int32_t d, int from) {
    scell *c = &S.c[i];
    if (c->seen != S.gen) c->seen = S.gen, c->dist = FAR, c->from = -1, c->pos = -1;
    if (d >= c->dist || c->pos == -2) return;
    c->dist = d, c->from = from;
    hnode v = {d + estimate(x, y), i};
    if (c->pos < 0) S.heap[S.n] = v, c->pos = S.n++;
    else S.heap[c->pos].key = v.key;
    up(c->pos);
}

/* From the cells in the heap, until the goal is done (gx >= 0) or nothing is left, or past budget. */
static void run(const grid *g, int32_t budget) {
    int goal = S.gx >= 0 ? S.gy * g->w + S.gx : -1, w = g->w, h = g->h;
    while (S.n > 0) {
        int i = pop();
        if (i == goal) return;
        int x = i % w, y = i / w;
        int32_t base = S.c[i].dist;
        for (int d = 0; d < (S.diag ? 8 : 4); d++) {
            int nx = x + DX[d], ny = y + DY[d];
            if (nx < 0 || ny < 0 || nx >= w || ny >= h) continue;
            int j = i + DY[d] * w + DX[d];
            uint8_t c = g->cost[j];
            if (!c) continue;
            if (d >= 4 && (!g->cost[i + DX[d]] || !g->cost[i + DY[d] * w])) continue; /* no cutting corners */
            int32_t nd = base + (d < 4 ? STRAIGHT : DIAGONAL) * c;
            if (nd <= budget) relax(j, nx, ny, nd, i);
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
    if (!s_begin(g->w * g->h, x1, y1, diag)) return luaL_error(L, "grid path: out of memory");
    relax(a, x0, y0, 0, -1);
    run(g, FAR - 255 * DIAGONAL);
    if (dist_of(b) == FAR) return lua_pushnil(L), 1;
    int len = 0;
    for (int i = b; i != a; i = S.c[i].from) len++;
    lua_createtable(L, len, 0);
    int k = len;
    for (int i = b; i != a; i = S.c[i].from, k--) {
        lua_createtable(L, 2, 0);
        lua_pushinteger(L, i % g->w), lua_rawseti(L, -2, 1);
        lua_pushinteger(L, i / g->w), lua_rawseti(L, -2, 2);
        lua_rawseti(L, -2, k);
    }
    lua_pushnumber(L, dist_of(b) / (lua_Number)STRAIGHT);
    return 2;
}

static int g_reach(lua_State *L) { /* g:reach(x, y, budget [, {diagonal}]) */
    grid *g = check_grid(L);
    int x, y;
    float budget = fin(luaL_checknumber(L, 4));
    bool diag = diagonal_opt(L, 5);
    lua_newtable(L);
    if (!cell(L, 2, g->w, g->h, &x, &y) || budget < 0) return 1;
    if (!s_begin(g->w * g->h, -1, -1, diag)) return luaL_error(L, "grid reach: out of memory");
    relax(y * g->w + x, x, y, 0, -1);
    run(g, (int32_t)(budget * STRAIGHT + 0.5f));
    int k = 0;
    for (int i = 0; i < g->w * g->h; i++) {
        if (dist_of(i) == FAR) continue;
        lua_createtable(L, 3, 0);
        lua_pushinteger(L, i % g->w), lua_rawseti(L, -2, 1);
        lua_pushinteger(L, i / g->w), lua_rawseti(L, -2, 2);
        lua_pushnumber(L, S.c[i].dist / (lua_Number)STRAIGHT), lua_rawseti(L, -2, 3);
        lua_rawseti(L, -2, ++k);
    }
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
    if (!s_begin(cells, -1, -1, diag)) return luaL_error(L, "grid distances: out of memory");
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
                if (on(g->w, g->h, x, y) && g->cost[y * g->w + x]) relax(y * g->w + x, x, y, 0, -1);
            }
            lua_pop(L, 1);
        }
    } else if (cell(L, 2, g->w, g->h, &x, &y) && g->cost[y * g->w + x]) {
        relax(y * g->w + x, x, y, 0, -1);
    }
    run(g, FAR - 255 * DIAGONAL);
    layer *l = new_layer(L, 1, 0);
    for (int i = 0; i < cells; i++) {
        int32_t d = dist_of(i);
        l->v[i] = d == FAR ? HUGE_VALF : d / (float)STRAIGHT;
    }
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
    const int w = l->w, h = l->h;
    const float keep = 1 - fade, big = 1e30f; /* (unreachable cells of a distance layer are infinite) */
    const float *v = l->v;
    const uint8_t *c = g->cost;
    for (int y = 0; y < h; y++) {
        const float *row = v + y * w;
        const uint8_t *crow = c + y * w;
        float *out = l->tmp + y * w;
        for (int x = 0; x < w; x++) {
            float here = row[x];
            if (!crow[x] || !(here < big)) {
                out[x] = crow[x] ? here : 0;
                continue;
            }
            float sum = 0;
            int n = 0;
            if (x > 0 && crow[x - 1] && row[x - 1] < big) sum += row[x - 1], n++;
            if (x + 1 < w && crow[x + 1] && row[x + 1] < big) sum += row[x + 1], n++;
            if (y > 0 && crow[x - w] && row[x - w] < big) sum += row[x - w], n++;
            if (y + 1 < h && crow[x + w] && row[x + w] < big) sum += row[x + w], n++;
            out[x] = (n ? here + rate * (sum / n - here) : here) * keep;
        }
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
