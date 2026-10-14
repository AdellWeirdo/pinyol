/* First person: a map of walls seen from inside it, a column at a time, as Wolfenstein 3D drew it (docs/lua.md
 * "First person"), onto a canvas the game then shows: twice as big, as a window, turned, anywhere.
 *
 *   local dist, wall = raycast("VIEW", {map = rows, x = 3.5, y = 2.5, angle = 90, fov = 66, fog = 10,
 *                                       walls = {["#"] = "TEX_STONE", D = "TEX_DOOR", W = 0x806040},
 *                                       ceiling = 0x303040, floor = 0x505050,
 *                                       sprites = {{x = 5.5, y = 4.5, picture = "GUARD", frame = 0, scale = 1}}})
 *
 * map: the rows, one character a square (space or "." open). A wall's character is in walls: a picture (its frame 0
 * wraps across each square of wall) or a colour. x, y in squares; angle in degrees, 0 east and 90 south; fov in
 * degrees. Walls and floor darken with distance (fog: squares to black; 0, none) and the walls facing north or south
 * are a little darker, so corners show. Sprites stand on the floor centred on their point, as tall as a wall at the
 * same distance times scale, hidden by the walls in front. Returns the distance to the wall in the middle of the view
 * (in squares, along the view) and that wall's character.
 *
 * A downloaded game's map and numbers are checked: rows and columns are bounded, a ray stops after RAY_STEPS
 * squares, positions are made finite. */
#include "lua_api.h"

#define MAX_ROWS 256
#define MAX_COLS 256
#define MAX_SPRITES 64
#define RAY_STEPS 128
#define MAX_W 480
#define MAX_H 320 /* a view taller is drawn to this height */
#define BAND 16
#define DEG 0.017453292f /* radians a degree */

typedef struct {
    const asset *pic; /* or NULL: a colour */
    uint16_t colour;
} wall_look;

typedef struct {
    int h, y0, k, u;
    const wall_look *look;
} column;

typedef struct {
    float x, y, d, scale;
    asset *pic;
    int frame;
} sprite;

static inline uint16_t shaded(uint16_t c, int k) { /* c times k/256, in 32 steps: the channels spread over 32 bits,
                                                     * one multiply */
    uint32_t x = ((c | (uint32_t)c << 16) & 0x07E0F81Fu) * (uint32_t)((k + 4) >> 3) >> 5 & 0x07E0F81Fu;
    uint16_t v = (uint16_t)(x | x >> 16);
    return v == CANVAS_KEY ? v ^ 1 : v; /* the key colour is see-through on a canvas */
}

static int fog_k(float d, float fog) { /* 256 near, 0 at fog squares */
    if (fog <= 0) return 256;
    float f = 1.0f - d / fog;
    return f <= 0 ? 0 : f >= 1 ? 256 : (int)(f * 256);
}

static int read_map(lua_State *L, int t, const char **rows, int *lens) {
    lua_getfield(L, t, "map");
    if (!lua_istable(L, -1)) luaL_error(L, "raycast: map must be a table of rows (strings)");
    int n = (int)lua_rawlen(L, -1);
    if (n > MAX_ROWS) n = MAX_ROWS;
    for (int i = 0; i < n; i++) {
        lua_rawgeti(L, -1, i + 1);
        size_t len = 0;
        rows[i] = lua_tolstring(L, -1, &len); /* the map table keeps it alive while raycast runs */
        lens[i] = rows[i] ? (int)(len > MAX_COLS ? MAX_COLS : len) : 0;
        lua_pop(L, 1);
    }
    lua_pop(L, 1); /* (the map table stays referenced by the options table) */
    return n;
}

static void read_walls(lua_State *L, int t, wall_look *looks, bool *is_wall) {
    lua_getfield(L, t, "walls");
    if (!lua_istable(L, -1)) luaL_error(L, "raycast: walls must be a table {character = picture or colour}");
    lua_pushnil(L);
    while (lua_next(L, -2)) {
        size_t klen = 0;
        const char *k = lua_type(L, -2) == LUA_TSTRING ? lua_tolstring(L, -2, &klen) : NULL;
        if (k && klen == 1 && (unsigned char)k[0] < 128) {
            unsigned c = (unsigned char)k[0];
            is_wall[c] = true;
            if (lua_type(L, -1) == LUA_TSTRING) {
                const char *id = lua_tostring(L, -1);
                asset *a = safe_name(id) ? gfx_asset(id) : NULL;
                looks[c].pic = a && !a->missing && gfx_pixels(a) ? a : NULL;
                looks[c].colour = 0x8410;
            } else {
                looks[c].pic = NULL;
                looks[c].colour = to565(luaL_checkinteger(L, -1));
            }
        }
        lua_pop(L, 1);
    }
    lua_pop(L, 1);
}

static int read_sprites(lua_State *L, int t, sprite *sp, float px, float py) {
    lua_getfield(L, t, "sprites");
    int n = 0;
    if (lua_istable(L, -1)) {
        int len = (int)lua_rawlen(L, -1);
        for (int i = 1; i <= len && n < MAX_SPRITES; i++) {
            lua_rawgeti(L, -1, i);
            if (lua_istable(L, -1)) {
                int s = lua_gettop(L);
                const char *id = opt_str(L, s, "picture");
                asset *a = id && safe_name(id) ? gfx_asset(id) : NULL;
                if (a && !a->missing && gfx_pixels(a)) {
                    sprite *q = &sp[n++];
                    q->x = opt_float(L, s, "x", 0, -NUM_MAX, NUM_MAX), q->y = opt_float(L, s, "y", 0, -NUM_MAX, NUM_MAX);
                    q->scale = opt_float(L, s, "scale", 1, 0.05f, 8);
                    q->frame = (int)opt_int(L, s, "frame", 0);
                    q->frame = q->frame < 0 || q->frame >= a->frames ? 0 : q->frame;
                    q->pic = a;
                    q->d = (q->x - px) * (q->x - px) + (q->y - py) * (q->y - py);
                }
            }
            lua_pop(L, 1);
        }
    }
    lua_pop(L, 1);
    for (int i = 1; i < n; i++) /* the farthest first */
        for (int j = i; j > 0 && sp[j - 1].d < sp[j].d; j--) {
            sprite tmp = sp[j];
            sp[j] = sp[j - 1], sp[j - 1] = tmp;
        }
    return n;
}

static int l_raycast(lua_State *L) {
    const char *id = luaL_checkstring(L, 1);
    asset *cv = safe_name(id) ? gfx_asset_opt(id) : NULL;
    if (!cv || !cv->canvas) return luaL_error(L, "raycast \"%s\": not a canvas (make one with canvas())", id);
    luaL_checktype(L, 2, LUA_TTABLE);
    const int W = cv->w > MAX_W ? MAX_W : cv->w, H = cv->h > MAX_H ? MAX_H : cv->h;
    static const char *rows[MAX_ROWS];
    static int lens[MAX_ROWS];
    static wall_look looks[128];
    static bool is_wall[128];
    static sprite sp[MAX_SPRITES];
    static float zbuf[MAX_W];
    memset(is_wall, 0, sizeof is_wall);
    int nrows = read_map(L, 2, rows, lens);
    read_walls(L, 2, looks, is_wall);
    float px = opt_float(L, 2, "x", 1.5f, -MAX_COLS, 2 * MAX_COLS), py = opt_float(L, 2, "y", 1.5f, -MAX_ROWS, 2 * MAX_ROWS);
    float ang = opt_float(L, 2, "angle", 0, -NUM_MAX, NUM_MAX) * DEG;
    float fov = opt_float(L, 2, "fov", 66, 20, 150) * DEG;
    float fog = opt_float(L, 2, "fog", 0, 0, 1000);
    lua_Integer ceil_rgb = opt_int(L, 2, "ceiling", 0x303040), floor_rgb = opt_int(L, 2, "floor", 0x505050);
    uint16_t ceil_c = to565(ceil_rgb), floor_c0 = to565(floor_rgb);
    int nsp = read_sprites(L, 2, sp, px, py);

    uint16_t *out = cv->pixels;
    float dx = cosf(ang), dy = sinf(ang), k = tanf(fov / 2);
    float plx = -dy * k, ply = dx * k; /* the camera plane, across the view */
    static column cols[MAX_W];
    static uint16_t floor_c[MAX_H];
    float centre_d = 0;
    char centre_c = 0;
    for (int x = 0; x < W; x++) { /* each column's wall: how far, which face, which square of which texture */
        float cam = 2.0f * (float)x / (float)W - 1.0f;
        float rx = dx + plx * cam, ry = dy + ply * cam;
        int mx = (int)floorf(px), my = (int)floorf(py);
        float ddx = rx == 0 ? 1e30f : fabsf(1.0f / rx), ddy = ry == 0 ? 1e30f : fabsf(1.0f / ry);
        int sx = rx < 0 ? -1 : 1, sy = ry < 0 ? -1 : 1;
        float tx = rx < 0 ? (px - (float)mx) * ddx : ((float)mx + 1.0f - px) * ddx;
        float ty = ry < 0 ? (py - (float)my) * ddy : ((float)my + 1.0f - py) * ddy;
        int side = 0;
        unsigned c = 0;
        for (int step = 0; step < RAY_STEPS; step++) { /* square to square until a wall */
            if (tx < ty) tx += ddx, mx += sx, side = 0;
            else ty += ddy, my += sy, side = 1;
            if (my < 0 || my >= nrows || mx < 0 || mx >= lens[my]) { c = '#'; break; } /* off the map: a wall */
            unsigned ch = (unsigned char)rows[my][mx];
            if (ch < 128 && is_wall[ch]) { c = ch; break; }
        }
        float d = side == 0 ? tx - ddx : ty - ddy;
        if (d < 0.01f) d = 0.01f;
        zbuf[x] = d;
        if (x == W / 2) centre_d = d, centre_c = (char)c;
        column *q = &cols[x];
        q->h = (int)((float)H / d), q->y0 = H / 2 - q->h / 2;
        q->k = fog_k(d, fog) * (side ? 3 : 4) / 4;
        q->look = c < 128 && is_wall[c] ? &looks[c] : NULL;
        q->u = 0;
        if (q->look && q->look->pic) {
            const asset *t = q->look->pic;
            float wx = side == 0 ? py + d * ry : px + d * rx;
            wx -= floorf(wx);
            int u = (int)(wx * (float)t->w);
            if ((side == 0 && rx > 0) || (side == 1 && ry < 0)) u = t->w - 1 - u; /* not mirrored, from either side */
            q->u = u < 0 ? 0 : u >= t->w ? t->w - 1 : u;
        }
    }
    uint16_t ceil_s = shaded(ceil_c, 256);
    for (int y = H / 2; y < H; y++) floor_c[y] = shaded(floor_c0, fog_k((float)H / (2.0f * (float)y - (float)H + 1.0f), fog));
    float inv = 1.0f / (plx * dy - dx * ply);
    static struct { int xl, w, ytop, h, k; const asset *t; const uint16_t *px; int frame; float depth; } sv[MAX_SPRITES];
    int nsv = 0;
    for (int i = 0; i < nsp; i++) { /* the sprites on the view: where and how big (farthest first, as sorted) */
        const sprite *q = &sp[i];
        const asset *t = q->pic;
        float rx = q->x - px, ry = q->y - py;
        float ax = inv * (dy * rx - dx * ry), depth = inv * (-ply * rx + plx * ry);
        if (depth <= 0.05f) continue;
        int h = (int)((float)H / depth * q->scale), w = h * t->w / (t->h ? t->h : 1);
        if (h <= 0 || w <= 0 || h > 8 * H) continue;
        int cx = (int)((float)W / 2 * (1.0f + ax / depth));
        sv[nsv].xl = cx - w / 2, sv[nsv].w = w, sv[nsv].h = h, sv[nsv].ytop = H / 2 + (int)((float)H / depth / 2) - h;
        sv[nsv].k = fog_k(depth, fog), sv[nsv].t = t, sv[nsv].frame = q->frame, sv[nsv].depth = depth;
        sv[nsv].px = t->pixels + (size_t)q->frame * t->w * t->h;
        nsv++;
    }
    /* Drawn a band of BAND columns at a time into internal memory, then copied a row at a time: the canvas (in PSRAM
     * on the console) written in runs instead of a pixel per row, which made a whole view cost twice as much. */
    static uint16_t band[MAX_H * BAND];
    for (int bx = 0; bx < W; bx += BAND) {
        int bw = W - bx < BAND ? W - bx : BAND;
        for (int i = 0; i < bw; i++) {
            const column *q = &cols[bx + i];
            int a = q->y0 < 0 ? 0 : q->y0, b = q->y0 + q->h > H ? H : q->y0 + q->h;
            for (int y = 0; y < a; y++) band[y * BAND + i] = y < H / 2 ? ceil_s : floor_c[y];
            for (int y = b; y < H; y++) band[y * BAND + i] = y < H / 2 ? ceil_s : floor_c[y];
            if (q->look && q->look->pic) {
                const asset *t = q->look->pic;
                const uint16_t *col = t->pixels + q->u;
                int32_t step = (int32_t)((int64_t)t->h * 65536 / (q->h ? q->h : 1)), v = (a - q->y0) * step;
                for (int y = a; y < b; y++, v += step) {
                    int vv = v >> 16;
                    band[y * BAND + i] = shaded(col[(vv < t->h ? vv : t->h - 1) * t->w], q->k);
                }
            } else {
                uint16_t c = shaded(q->look ? q->look->colour : 0x8410, q->k);
                for (int y = a; y < b; y++) band[y * BAND + i] = c;
            }
        }
        for (int i = 0; i < nsv; i++) { /* the sprites' columns in this band, hidden where a wall is nearer */
            const asset *t = sv[i].t;
            int x0 = sv[i].xl > bx ? sv[i].xl : bx, x1 = sv[i].xl + sv[i].w < bx + bw ? sv[i].xl + sv[i].w : bx + bw;
            for (int x = x0; x < x1; x++) {
                if (sv[i].depth >= zbuf[x]) continue;
                int u = (x - sv[i].xl) * t->w / sv[i].w;
                for (int y = sv[i].ytop < 0 ? 0 : sv[i].ytop; y < sv[i].ytop + sv[i].h && y < H; y++) {
                    int v = (y - sv[i].ytop) * t->h / sv[i].h;
                    if (gfx_opaque(t, sv[i].frame, u, v)) band[y * BAND + x - bx] = shaded(sv[i].px[v * t->w + u], sv[i].k);
                }
            }
        }
        for (int y = 0; y < H; y++) memcpy(out + y * cv->w + bx, band + y * BAND, (size_t)bw * sizeof *band);
    }
    memset(cv->mask, 0xFF, (size_t)((cv->w + 7) / 8) * cv->h); /* the view covers its canvas */
    cv->gen++;
    lua_pushnumber(L, centre_d);
    char s[2] = {centre_c, 0};
    lua_pushstring(L, s);
    return 2;
}

void ray_register(lua_State *L) { lua_register(L, "raycast", l_raycast); }
