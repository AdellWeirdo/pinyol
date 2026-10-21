/* pinyol@2 games: the game is a Lua program (main.lua) that drives the virtual picture processor (ppu.h) and draws text
 * and shapes at the screen's full resolution over it. The engine calls _init() once, _update() every tick (60 Hz)
 * and _draw() before each frame; docs/lua.md lists the API.
 *
 * The script runs in a sandbox: a memory quota, a budget of jumps and calls per call (an endless loop ends in an error,
 * not a frozen console), source chunks only (never bytecode), no io/os/debug/package, and require() reads .lua
 * files from the game's own folder. Lua is built with 32-bit numbers everywhere, so a game behaves the same on the
 * console, the desktop and the web. */
#include <math.h>
#include <stdio.h>
#include <sys/stat.h>
#include <stdlib.h>
#include <string.h>
#include <time.h>

#include "bp.h"
#include "lauxlib.h"
#include "lua.h"
#include "lualib.h"
#include "ppu.h"
#include "lua_api.h"
#include "lua_prof.h"
#include "conf.h"
#include "gfx_px.h"
#include "played.h"
#include "post.h"
#include "sysmenu.h"

#define MEM_QUOTA_KB 4096          /* game.json "lua_memory_kb" can ask for up to MEM_MAX_KB */
#define MEM_MAX_KB 6144
#define CALL_BUDGET 20000000L      /* jumps, loop turns and calls per _init/_update/_draw call before it is stopped */
#define MAX_SHEETS 96
#define MAX_TILEMAPS 24

static lua_State *Ls;
static int splash_ref = LUA_NOREF; /* the game's careta (splash.lua): its table, while it plays */
static uint32_t us_update, us_draw, us_ppu; /* the last tick's _update, the last frame's _draw and picture (perf()) */
static bool blank;          /* the world this frame is the backdrop alone (ppu_blank): drawn as a fill */
static uint16_t backdrop;
static struct { uint64_t update, draw, ppu; uint32_t ppu_max; int ticks, frames; } acc; /* since v2_timing */
static size_t mem_used, mem_quota;
extern long pinyol_budget; /* counted down by the VM on jumps, loop turns and calls (third_party/lua/lvm.c, luai_budget) */
extern void (*pinyol_budget_over)(lua_State *L);
static char error[320];
static bool failed;

/* ------------------------------------------------------------------ assets: sheets, tilemaps, palettes */

typedef struct {
    char id[32];
    int w, h, frames;
    uint8_t *idx;    /* indexed sheet (.idx), or */
    const asset *a;  /* a runtime RGB565 asset */
} sheet;

typedef struct {
    char id[32];
    uint8_t *tiles;
    int ntiles;
    uint16_t *rows;  /* ppu_tile_rows */
    uint16_t *map;   /* the asset's map, read-only: a layer copies it */
    int map_w, map_h;
    char palette[32]; /* the palette its colours index (png2asset --palette), "" if its own */
} tilemap;

static sheet sheets[MAX_SHEETS];
static int nsheets;
static tilemap tilemaps[MAX_TILEMAPS];
static int ntilemaps;
typedef struct { uint16_t *map; int mx7_on; float cx, cy, angle, height, horizon, fov; } layer_t;
static layer_t layer[PPU_BGS];

/* two screens (below): what a screen parks while the other is drawn on, and which one it is */
typedef struct {
    layer_t layer[PPU_BGS];
    ppu_line_scroll scroll[PPU_BGS][PPU_H];
    ppu_line_affine affine[PPU_BGS][PPU_H];
    ppu_line_span win[2][PPU_H];
    uint16_t back[PPU_H];
    ppu_line_pal pal[2][PPU_H];
    uint8_t ev[PPU_H];
} parked_screen;
static int screens = 1, cur_screen; /* 1 or 2; the one drawn on (0 or 1) */
static parked_screen *parked;       /* [2], only for a game with two screens */
static uint16_t *world2;            /* the bottom screen's picture (G.world is the top's) */

static void *load_bytes(const char *id, const char *ext, long *len) {
    char path[384];
    snprintf(path, sizeof path, "%s/assets/%s.%s", G.game_dir, id, ext);
    return read_file(path, len);
}

static cJSON *load_meta(const char *id) {
    char rel[96];
    snprintf(rel, sizeof rel, "assets/%s.meta.json", id);
    return json_file(rel);
}

/* An asset ID a game asks for: a file name inside the game folder, and short enough to be kept whole. */
static bool asset_name(const char *id) { return safe_name(id) && strlen(id) < sizeof(sheets[0].id); }

static int sheet_get(const char *id) { /* handle (1-based), 0 if it cannot be loaded */
    if (!asset_name(id)) return 0;
    for (int i = 0; i < nsheets; i++)
        if (!strcmp(sheets[i].id, id)) return i + 1;
    if (nsheets == MAX_SHEETS) return 0;
    sheet *s = &sheets[nsheets];
    memset(s, 0, sizeof *s);
    snprintf(s->id, sizeof s->id, "%s", id);
    cJSON *meta = load_meta(id);
    const char *fmt = jstr(meta, "format");
    if (fmt && !strcmp(fmt, "idx8")) {
        s->w = jint(meta, "w", 0), s->h = jint(meta, "h", 0), s->frames = jint(meta, "frames", 1);
        long len = 0;
        s->idx = load_bytes(id, "idx", &len);
        /* the sizes come from the game: bounded first, then checked in 64 bits (long is 32 on the console) */
        if (!s->idx || s->w <= 0 || s->h <= 0 || s->w > 255 || s->h > 255 || s->frames <= 0 || s->frames > 1024 ||
            (int64_t)len != (int64_t)s->w * s->h * s->frames) {
            hal_log("sheet %s: bad indexed pixels", id);
            free(s->idx);
            cJSON_Delete(meta);
            return 0;
        }
    } else {
        asset *a = gfx_asset(id);
        if (a->missing || a->w > 255 || a->h > 255 || !gfx_pixels(a)) { /* the PPU reads pixels: a packed one unpacked */
            cJSON_Delete(meta);
            return 0;
        }
        gfx_pin(a); /* its sprites point into its pixels from frame to frame */
        s->a = a, s->w = a->w, s->h = a->h, s->frames = a->frames;
    }
    cJSON_Delete(meta);
    return ++nsheets;
}

static tilemap *tilemap_get(const char *id) {
    if (!asset_name(id)) return NULL;
    for (int i = 0; i < ntilemaps; i++)
        if (!strcmp(tilemaps[i].id, id)) return &tilemaps[i];
    if (ntilemaps == MAX_TILEMAPS) return NULL;
    tilemap *t = &tilemaps[ntilemaps];
    memset(t, 0, sizeof *t);
    snprintf(t->id, sizeof t->id, "%s", id);
    cJSON *meta = load_meta(id);
    t->ntiles = jint(meta, "tiles", 0), t->map_w = jint(meta, "map_w", 0), t->map_h = jint(meta, "map_h", 0);
    snprintf(t->palette, sizeof t->palette, "%s", jstr(meta, "palette") ? jstr(meta, "palette") : id);
    cJSON_Delete(meta);
    long tl = 0, ml = 0;
    t->tiles = load_bytes(id, "tiles", &tl);
    t->map = load_bytes(id, "map", &ml);
    if (!t->tiles || !t->map || t->ntiles <= 0 || t->ntiles > 1024 || (int64_t)tl != t->ntiles * 64LL ||
        t->map_w <= 0 || t->map_h <= 0 || t->map_w > 1024 || t->map_h > 1024 ||
        (int64_t)ml != 2LL * t->map_w * t->map_h) { /* tile numbers are 10 bits; maps up to 1024x1024 tiles */
        hal_log("tilemap %s: missing or the wrong size", id);
        free(t->tiles);
        free(t->map);
        return NULL;
    }
    for (long i = 0; i < ml / 2; i++) { /* little endian on disk */
        const uint8_t *b = (const uint8_t *)&t->map[i];
        t->map[i] = (uint16_t)(b[0] | b[1] << 8);
    }
    t->rows = malloc(t->ntiles * sizeof *t->rows);
    if (t->rows) ppu_tile_rows(t->tiles, t->ntiles, t->rows); /* else drawn without the shortcuts */
    ntilemaps++;
    return t;
}

static int palette_load(const char *id, uint16_t *pal, int offset) { /* entries loaded, 0 on failure */
    if (!asset_name(id)) return 0;
    long len = 0;
    uint8_t *raw = load_bytes(id, "pal", &len);
    if (!raw || len < 2) {
        free(raw);
        return 0;
    }
    int n = (int)(len / 2);
    for (int i = 0; i < n && offset + i < 256; i++) /* an index 0 is transparent: entry 0 keeps the backdrop */
        if (offset + i) pal[offset + i] = (uint16_t)(raw[2 * i] | raw[2 * i + 1] << 8);
    free(raw);
    return n;
}

static void assets_free(void) {
    for (int i = 0; i < nsheets; i++) free(sheets[i].idx);
    for (int i = 0; i < ntilemaps; i++) free(tilemaps[i].tiles), free(tilemaps[i].map), free(tilemaps[i].rows);
    for (int i = 0; i < PPU_BGS; i++) free(layer[i].map);
    if (parked) for (int k = 0; k < 2; k++) if (k != cur_screen) for (int i = 0; i < PPU_BGS; i++) free(parked[k].layer[i].map);
    nsheets = ntilemaps = 0;
    memset(layer, 0, sizeof layer);
}

/* ------------------------------------------------------------------ per-line tables */

static ppu_line_scroll line_scroll_tab[PPU_BGS][PPU_H];
static ppu_line_affine line_affine_tab[PPU_BGS][PPU_H];
static ppu_line_span line_win_tab[2][PPU_H];
static uint16_t line_back_tab[PPU_H];
static ppu_line_pal line_pal_tab[2][PPU_H]; /* [0] the backgrounds' palette, [1] the sprites' */
static uint8_t line_ev_tab[PPU_H];

/* ------------------------------------------------------------------ two screens (game.json "screens": 2)
 * What belongs to a screen but lives beside the PPU (its layers' maps, the per-line tables, whether it is only its
 * backdrop) is parked while the other screen is the one drawn on: screen(n) swaps them. docs/ds-dual-screen-design.md */



bool v2_dual(void) { return screens == 2; }

static void screen_copy(parked_screen *p, bool save) { /* the current screen's into p, or p's into it */
#define SWAP_TAB(field, tab) do { if (save) memcpy(p->field, tab, sizeof p->field); else memcpy(tab, p->field, sizeof tab); } while (0)
    SWAP_TAB(layer, layer);
    SWAP_TAB(scroll, line_scroll_tab);
    SWAP_TAB(affine, line_affine_tab);
    SWAP_TAB(win, line_win_tab);
    SWAP_TAB(back, line_back_tab);
    SWAP_TAB(pal, line_pal_tab);
    SWAP_TAB(ev, line_ev_tab);
#undef SWAP_TAB
}

static void screen_select(int n) { /* 0 or 1 */
    if (screens < 2 || n == cur_screen) return;
    screen_copy(&parked[cur_screen], true);
    screen_copy(&parked[n], false);
    cur_screen = n;
    ppu_select(n);
}

static void screen_view(int n) { draw_set_view(DUAL_X(n), DUAL_Y, WORLD_W, WORLD_H); }

static int l_screen(lua_State *L) { /* screen(1 or 2): the top or the bottom (the touch one); what is drawn from now on is for it */
    lua_Integer n = luaL_checkinteger(L, 1);
    if (n < 1 || n > screens) return luaL_error(L, screens == 2 ? "screen(%d): the screens are 1 and 2" : "screen(%d): this game has one screen (game.json \"screens\": 2)", (int)n);
    if (screens == 2) screen_select((int)n - 1), screen_view((int)n - 1);
    return 0;
}

/* ------------------------------------------------------------------ the sandbox */

static void *alloc(void *ud, void *p, size_t osize, size_t nsize) {
    (void)ud;
    if (!p) osize = 0;
    if (!nsize) {
        free(p);
        mem_used -= osize;
        return NULL;
    }
    if (mem_used - osize + nsize > mem_quota) return NULL; /* Lua raises "not enough memory" */
    void *q = hal_realloc_slow(p, nsize);
    if (q) mem_used = mem_used - osize + nsize;
    return q;
}

static void hook(lua_State *L, lua_Debug *ar) {
    (void)ar;
    /* Over: from now on every instruction fails, so a pcall in a loop cannot catch the error and carry on. */
    lua_sethook(L, hook, LUA_MASKCOUNT, 1);
    luaL_error(L, "the script ran too long without returning (an endless loop?)");
}

/* The VM ran out of the budget (in this thread: a coroutine too). The count hook, set only now, raises the error at the next
 * instruction, where the VM has saved its place. While the budget stays spent every jump in any thread comes here again. */
static void over(lua_State *L) { lua_sethook(L, hook, LUA_MASKCOUNT, 1); }

static void arm_as(const char *entry) { /* a fresh budget for one call from the engine, and no hook (but perf("lua")'s): the VM runs at its full speed */
    pinyol_budget = CALL_BUDGET;
    prof_arm(Ls, entry);
}

static void arm(void) { arm_as(NULL); }

static int msgh(lua_State *L) { /* the error with where it happened */
    const char *m = lua_tostring(L, 1);
    luaL_traceback(L, L, m ? m : "error", 1);
    return 1;
}

static void fail(const char *what, const char *msg) {
    snprintf(error, sizeof error, "%s: %s", what, msg ? msg : "error");
    hal_log("lua %s", error);
    failed = true;
    sysmenu_crash(error); /* the crash screen: the whole error, A to start again */
    char path[400], *txt = malloc(sizeof error + 256);
    if (txt) { /* crash.txt in the saves folder: what to send with a bug report */
        snprintf(path, sizeof path, "%s/crash.txt", G.save_dir);
        snprintf(txt, sizeof error + 256, "pinyol %s\ngame %s\ntick %u\n%s\n", hal_firmware(), jstr(G.game, "id") ? jstr(G.game, "id") : "?",
                 (unsigned)G.ticks, error);
        FILE *f = fopen(path, "w"); /* plainly (not the saves' two files): the game has stopped, nothing waits */
        if (!f || fputs(txt, f) < 0 || fclose(f)) hal_log("cannot write %s", path);
        free(txt);
    }
}

static bool call(const char *fn, int nargs) { /* args are on the stack; true if it ran (or does not exist) */
    if (failed) {
        lua_pop(Ls, nargs);
        return false;
    }
    lua_getglobal(Ls, fn);
    if (!lua_isfunction(Ls, -1)) {
        lua_pop(Ls, 1 + nargs);
        return true;
    }
    screen_select(0); /* every call starts on the top screen */
    lua_insert(Ls, -1 - nargs);
    lua_pushcfunction(Ls, msgh);
    lua_insert(Ls, -2 - nargs);
    arm_as(fn);
    int base = lua_gettop(Ls) - nargs - 1;
    int rc = lua_pcall(Ls, nargs, 0, base);
    lua_remove(Ls, base); /* msgh */
    draw_flush();         /* the canvases it drew on, ready to be shown */
    if (rc != LUA_OK) {
        fail(fn, lua_tostring(Ls, -1));
        lua_pop(Ls, 1);
        return false;
    }
    return true;
}


static int load_chunk(lua_State *L, const char *rel) { /* pushes the compiled chunk, or raises */
    char path[384];
    snprintf(path, sizeof path, "%s/%s", G.game_dir, rel);
    long len = 0;
    char *src = read_file(path, &len);
    if (!src) return luaL_error(L, "cannot read %s", rel);
    char name[96];
    snprintf(name, sizeof name, "@%s", rel);
    int rc = luaL_loadbufferx(L, src, (size_t)len, name, "t");
    free(src);
    if (rc != LUA_OK) return lua_error(L);
    return 1;
}

static int l_require(lua_State *L) {
    const char *mod = luaL_checkstring(L, 1);
    if (!safe_name(mod)) return luaL_error(L, "require: bad module name '%s'", mod);
    lua_getfield(L, LUA_REGISTRYINDEX, "pinyol.loaded");
    lua_getfield(L, -1, mod);
    if (!lua_isnil(L, -1)) return 1;
    lua_pop(L, 1);
    char rel[128];
    snprintf(rel, sizeof rel, "%s.lua", mod);
    for (char *c = rel; *c && strcmp(c, ".lua"); c++) if (*c == '.') *c = '/'; /* "ui.menu" -> ui/menu.lua */
    char path[384];
    snprintf(path, sizeof path, "%s/%s", G.game_dir, rel);
    FILE *own = fopen(path, "rb"); /* the game's own copy first: a library can be copied into a game and changed */
    const pinyol_lib_entry *lib = NULL;
    for (int i = 0; !own && pinyol_lib[i].name; i++)
        if (!strcmp(pinyol_lib[i].name, mod)) lib = &pinyol_lib[i];
    if (own) fclose(own);
    if (lib) {
        char name[48];
        snprintf(name, sizeof name, "=pinyol/%s.lua", mod);
        if (luaL_loadbufferx(L, lib->src, lib->len, name, "t") != LUA_OK) return lua_error(L);
    } else {
        load_chunk(L, rel);
    }
    lua_pushstring(L, mod);
    lua_call(L, 1, 1);
    if (lua_isnil(L, -1)) lua_pop(L, 1), lua_pushboolean(L, 1);
    lua_pushvalue(L, -1);
    lua_setfield(L, -3, mod);
    return 1;
}

/* A module changed while the game runs (the simulator, a file saved; a test's `hotswap FILE MOD`): the file is run again and
 * what it returns is copied over the table the game already holds (the way rxi's lume.hotswap does it), so every reference
 * the game keeps stays good and its state lives on: a number tuned, a function fixed, without starting over. False when it
 * is not a module the game has required, or it fails (the engine then starts the game over as before). */
bool v2_hotswap(const char *rel, const char *mod) {
    if (!Ls || failed || !safe_name(rel) || !mod || !safe_name(mod)) return false;
    lua_getfield(Ls, LUA_REGISTRYINDEX, "pinyol.loaded");
    lua_getfield(Ls, -1, mod);
    if (!lua_istable(Ls, -1)) { lua_pop(Ls, 2); return false; }
    const int old = lua_gettop(Ls);
    lua_pushcfunction(Ls, msgh);
    const int base = lua_gettop(Ls);
    load_chunk(Ls, rel);
    lua_pushstring(Ls, mod);
    arm_as("hotswap");
    if (lua_pcall(Ls, 1, 1, base) != LUA_OK) {
        hal_log("hotswap %s: %s", rel, lua_tostring(Ls, -1));
        lua_settop(Ls, old - 2);
        return false;
    }
    if (!lua_istable(Ls, -1)) { lua_settop(Ls, old - 2); return false; }
    /* the new table's fields over the old's (fields gone from the file are left: the game may still hold them) */
    lua_pushnil(Ls);
    while (lua_next(Ls, -2)) {
        lua_pushvalue(Ls, -2), lua_pushvalue(Ls, -2);
        lua_settable(Ls, old);
        lua_pop(Ls, 1);
    }
    if (lua_getmetatable(Ls, -1)) lua_setmetatable(Ls, old);
    lua_settop(Ls, old - 2);
    draw_flush();
    hal_log("hotswap %s: %s renewed, the game's state kept", rel, mod);
    return true;
}

#define FILE_MAX (1024 * 1024)

/* file(name) -> the text of one of the game's files ("story/es.txt", "maps/metro.csv"), or nil if it has none */
static int l_file(lua_State *L) {
    const char *rel = luaL_checkstring(L, 1);
    if (!safe_name(rel)) return luaL_error(L, "file: bad file name '%s'", rel);
    char path[384];
    snprintf(path, sizeof path, "%s/%s", G.game_dir, rel);
    FILE *f = fopen(path, "rb");
    if (!f) return lua_pushnil(L), 1;
    long n = fseek(f, 0, SEEK_END) ? -1 : ftell(f);
    fclose(f);
    if (n > FILE_MAX) return luaL_error(L, "file: %s is bigger than %d KB", rel, FILE_MAX / 1024);
    long len = 0;
    char *txt = n >= 0 ? read_file(path, &len) : NULL;
    if (!txt) return lua_pushnil(L), 1;
    lua_pushlstring(L, txt, (size_t)len);
    free(txt);
    return 1;
}

static int l_load(lua_State *L) { /* load(chunk [, name [, mode [, env]]]) with source only, never bytecode */
    size_t n = 0;
    const char *s = luaL_checklstring(L, 1, &n);
    const char *name = luaL_optstring(L, 2, s);
    int env = !lua_isnone(L, 4);
    if (luaL_loadbufferx(L, s, n, name, "t") != LUA_OK) {
        lua_pushnil(L);
        lua_insert(L, -2);
        return 2;
    }
    if (env) {
        lua_pushvalue(L, 4);
        if (!lua_setupvalue(L, -2, 1)) lua_pop(L, 1);
    }
    return 1;
}

static int l_log(lua_State *L) {
    int n = lua_gettop(L); /* before the buffer takes a stack slot */
    luaL_Buffer b;
    luaL_buffinit(L, &b);
    for (int i = 1; i <= n; i++) {
        if (i > 1) luaL_addchar(&b, ' ');
        luaL_tolstring(L, i, NULL);
        luaL_addvalue(&b);
    }
    luaL_pushresult(&b);
    hal_log("lua: %s", lua_tostring(L, -1));
    return 0;
}

/* ------------------------------------------------------------------ the API */

static bool menu_read; /* the game has asked about MENU: a tap of it is the game's, not the console's menu (sysmenu.c) */
bool v2_reads_menu(void) { return menu_read; }

static int act_bit(const char *name) {
    static const struct { const char *n; int bit; } A[] = {
        {"up", ACT_UP}, {"down", ACT_DOWN}, {"left", ACT_LEFT}, {"right", ACT_RIGHT}, {"a", ACT_OK}, {"b", ACT_BACK},
        {"c", ACT_NEXT}, {"start", ACT_PAUSE}, {"menu", ACT_INV}};
    for (size_t i = 0; i < sizeof A / sizeof A[0]; i++)
        if (!strcmp(A[i].n, name)) {
            if (A[i].bit == ACT_INV) menu_read = true;
            return A[i].bit;
        }
    return 0;
}

/* Each button's story, kept every tick before _update: how long it has been held, when it was last pressed, whether it
 * was let go this tick, and whether btnb has used that press already. */
#define NBUTTONS 16
static struct { uint16_t prev, released, used; uint32_t held_t[NBUTTONS], pressed_at[NBUTTONS]; } BT;

static int bit_index(int bit) {
    int i = 0;
    while (bit > 1) bit >>= 1, i++;
    return i;
}

static void buttons_tick(void) {
    uint16_t h = G.in.held;
    BT.released = BT.prev & ~h;
    for (int i = 0; i < NBUTTONS; i++) {
        uint16_t bit = (uint16_t)(1u << i);
        BT.held_t[i] = (h & bit) ? BT.held_t[i] + 1 : 0;
        if (G.in.pressed & bit) BT.pressed_at[i] = (uint32_t)G.ticks, BT.used &= (uint16_t)~bit;
    }
    BT.prev = h;
}

static int checked_bit(lua_State *L) {
    int bit = act_bit(luaL_checkstring(L, 1));
    if (!bit) return luaL_error(L, "no button called \"%s\" (up down left right a b c start menu)", lua_tostring(L, 1));
    return bit;
}

static int l_btn(lua_State *L) { lua_pushboolean(L, G.in.held & act_bit(luaL_checkstring(L, 1))); return 1; }

/* btnp(name [, hold, every]): true on the tick it was pressed; with hold, again after it has been held that many ticks
 * and then every `every` ticks (a menu's cursor, a fast scroll) */
static int l_btnp(lua_State *L) {
    int bit = act_bit(luaL_checkstring(L, 1));
    bool on = (G.in.pressed & bit) != 0;
    if (!on && bit && !lua_isnoneornil(L, 2)) {
        lua_Integer hold = luaL_checkinteger(L, 2), every = luaL_optinteger(L, 3, hold);
        uint32_t t = BT.held_t[bit_index(bit)];
        if (hold < 1) hold = 1;
        if (every < 1) every = 1;
        on = t > (uint32_t)hold && (t - 1 - (uint32_t)hold) % (uint32_t)every == 0;
    }
    lua_pushboolean(L, on);
    return 1;
}

static int l_btnr(lua_State *L) { lua_pushboolean(L, BT.released & checked_bit(L)); return 1; } /* let go this tick */

static int l_btnt(lua_State *L) { /* btnt(name) -> ticks it has been held (0: up) */
    lua_pushinteger(L, (lua_Integer)BT.held_t[bit_index(checked_bit(L))]);
    return 1;
}

/* btnb(name [, window]): was it pressed in the last `window` ticks (6) and not used yet? A jump pressed just before
 * landing still jumps. Answering true uses that press. */
static int l_btnb(lua_State *L) {
    int bit = checked_bit(L), i = bit_index(bit);
    lua_Integer window = luaL_optinteger(L, 2, 6);
    bool on = !(BT.used & bit) && BT.pressed_at[i] && (lua_Integer)(G.ticks - BT.pressed_at[i]) < window;
    if (on) BT.used |= (uint16_t)bit;
    lua_pushboolean(L, on);
    return 1;
}

static int l_touch(lua_State *L) { /* in the 240x160 world's pixels */
    lua_pushinteger(L, screens == 2 ? G.in.px : G.in.px / 2); /* two screens: already the bottom one's own pixels (game_tick) */
    lua_pushinteger(L, screens == 2 ? G.in.py : G.in.py / 2);
    lua_pushboolean(L, G.in.touch);
    lua_pushboolean(L, G.in.tap);
    lua_pushboolean(L, G.in.release);
    return 5;
}

static int l_pen(lua_State *L) { /* the same finger in the screen's own 480x320 pixels (text() and shapes' space), with the lift */
    lua_pushinteger(L, G.in.px);
    lua_pushinteger(L, G.in.py);
    lua_pushboolean(L, G.in.touch);
    lua_pushboolean(L, G.in.tap);
    lua_pushboolean(L, G.in.release);
    return 5;
}

static int l_touches(lua_State *L) { /* every finger down, {{x, y}, ...}, in pen()'s pixels; the first is pen()'s */
    lua_createtable(L, G.in.points, 0);
    for (int i = 0; i < G.in.points; i++) {
        lua_createtable(L, 2, 0);
        lua_pushinteger(L, G.in.x[i]), lua_rawseti(L, -2, 1);
        lua_pushinteger(L, G.in.y[i]), lua_rawseti(L, -2, 2);
        lua_rawseti(L, -2, i + 1);
    }
    return 1;
}

static int l_t(lua_State *L) { lua_pushnumber(L, (lua_Number)G.ticks / TICK_HZ); return 1; }
static int l_ticks(lua_State *L) { lua_pushinteger(L, (lua_Integer)G.ticks); return 1; }

static int l_rgb(lua_State *L) {
    lua_Integer r = num(L, 1), g = num(L, 2), b = num(L, 3);
    r = r < 0 ? 0 : r > 255 ? 255 : r, g = g < 0 ? 0 : g > 255 ? 255 : g, b = b < 0 ? 0 : b > 255 ? 255 : b;
    lua_pushinteger(L, (r & 255) << 16 | (g & 255) << 8 | (b & 255));
    return 1;
}

static int l_pal(lua_State *L) { /* pal(i, 0xRRGGBB [, "obj"]) */
    int i = num(L, 1) & 255;
    uint16_t c = to565(luaL_checkinteger(L, 2));
    if (lua_toboolean(L, 3)) PPU.obj_pal[i] = c;
    else PPU.bg_pal[i] = c;
    return 0;
}

static int l_palette(lua_State *L) { /* palette(id [, "obj"] [, offset]) */
    const char *id = luaL_checkstring(L, 1);
    bool obj = lua_toboolean(L, 2);
    int off = (int)luaL_optinteger(L, 3, 0);
    if (off < 0 || off > 255) return luaL_error(L, "palette: offset %d outside 0..255", off);
    int n = palette_load(id, obj ? PPU.obj_pal : PPU.bg_pal, off);
    if (!n) return luaL_error(L, "palette: no assets/%s.pal", id);
    lua_pushinteger(L, n);
    return 1;
}

static int l_backdrop(lua_State *L) { PPU.bg_pal[0] = to565(luaL_checkinteger(L, 1)); return 0; }

/* palcycle(lo, hi, phase [, {obj, blend}]): entries lo..hi of the palette cycle (Mark Ferrari's living worlds: a waterfall,
 * lava, a river from a handful of entries): entry i shows what entry lo + ((i - lo + phase) mod n) held, and with blend (on by
 * default) a fraction of phase mixes two neighbours, so the cycle glides instead of stepping (canvascycle's BlendShift).
 * The entries' own colours are kept from the first call for that range (up to 8 ranges); palcycle() forgets them all (after
 * a new palette is loaded), palcycle(lo, hi) puts that range back and forgets it. */
#define CYCLES 8
static struct { int lo, hi; bool obj, on; uint16_t base[256]; } cycles[CYCLES];

static int l_palcycle(lua_State *L) {
    if (lua_isnoneornil(L, 1)) {
        for (int k = 0; k < CYCLES; k++) cycles[k].on = false;
        return 0;
    }
    const int lo = (int)luaL_checkinteger(L, 1), hi = (int)luaL_checkinteger(L, 2);
    luaL_argcheck(L, lo >= 0 && lo < 256, 1, "entry 0..255");
    luaL_argcheck(L, hi > lo && hi < 256, 2, "an entry above the first, up to 255");
    bool obj = false, blend = true;
    if (lua_type(L, 4) == LUA_TSTRING) obj = !strcmp(lua_tostring(L, 4), "obj");
    else if (lua_istable(L, 4)) obj = opt_bool(L, 4, "obj", false), blend = opt_bool(L, 4, "blend", true);
    uint16_t *pal = obj ? PPU.obj_pal : PPU.bg_pal;
    int k = -1, free_k = -1;
    for (int i = 0; i < CYCLES; i++) {
        if (cycles[i].on && cycles[i].lo == lo && cycles[i].hi == hi && cycles[i].obj == obj) k = i;
        else if (!cycles[i].on && free_k < 0) free_k = i;
    }
    const int n = hi - lo + 1;
    if (lua_isnoneornil(L, 3)) { /* back as it was */
        if (k >= 0) memcpy(pal + lo, cycles[k].base + lo, (size_t)n * sizeof *pal), cycles[k].on = false;
        return 0;
    }
    if (k < 0) {
        if (free_k < 0) return luaL_error(L, "palcycle: %d ranges at most (palcycle() forgets them)", CYCLES);
        k = free_k;
        cycles[k].lo = lo, cycles[k].hi = hi, cycles[k].obj = obj, cycles[k].on = true;
        memcpy(cycles[k].base + lo, pal + lo, (size_t)n * sizeof *pal);
    }
    const float phase = fin(luaL_checknumber(L, 3));
    float ph = fmodf(phase, (float)n);
    if (ph < 0) ph += (float)n;
    const int whole = (int)ph;
    const unsigned frac = (unsigned)((ph - (float)whole) * 256);
    for (int i = 0; i < n; i++) {
        const uint16_t a = cycles[k].base[lo + (i + whole) % n], b = cycles[k].base[lo + (i + whole + 1) % n];
        pal[lo + i] = blend && frac ? mix565(a, b, frac, BLEND_ALPHA) : a;
    }
    return 0;
}

static int bg_index(lua_State *L, int arg) {
    int n = (int)luaL_checkinteger(L, arg);
    luaL_argcheck(L, n >= 0 && n < PPU_BGS, arg, "background 0..3");
    return n;
}




/* bg(n, {mode = "tiles" | "affine" | "bitmap" | "off", map = "ID", image = "ID", prio, wrap, mosaic, x, y, pal}) */
static int l_bg(lua_State *L) {
    int n = bg_index(L, 1);
    ppu_bg *b = &PPU.bg[n];
    if (lua_isnoneornil(L, 2)) {
        b->mode = BG_OFF;
        return 0;
    }
    luaL_checktype(L, 2, LUA_TTABLE);
    const char *mode = opt_str(L, 2, "mode");
    if (!mode) mode = opt_str(L, 2, "image") ? "bitmap" : "tiles";
    free(layer[n].map);
    layer[n].map = NULL;
    layer[n].mx7_on = 0;
    PPU.line.affine[n] = NULL;
    memset(b, 0, sizeof *b);
    b->prio = (uint8_t)(opt_int(L, 2, "prio", n) & 3);
    b->wrap = opt_bool(L, 2, "wrap", true);
    b->mosaic = opt_bool(L, 2, "mosaic", false);
    b->scroll_x = (int)fin((lua_Number)opt_int(L, 2, "x", 0)); /* within +-NUM_MAX, as scroll() keeps them */
    b->scroll_y = (int)fin((lua_Number)opt_int(L, 2, "y", 0));
    b->pa = b->pd = 256;
    if (!strcmp(mode, "off")) return 0;
    if (!strcmp(mode, "bitmap")) {
        const char *id = opt_str(L, 2, "image");
        asset *a = id && asset_name(id) ? gfx_asset(id) : NULL;
        if (!a || a->missing) return luaL_error(L, "bg %d: no image '%s'", n, id ? id : "");
        if (!gfx_pixels(a)) return luaL_error(L, "bg %d: no memory to unpack '%s'", n, id);
        gfx_pin(a); /* the layer points into its pixels */
        b->mode = BG_BITMAP, b->bitmap = a->pixels, b->bitmap_mask = a->mask, b->bitmap_w = a->w, b->bitmap_h = a->h;
        return 0;
    }
    const char *id = opt_str(L, 2, "map");
    tilemap *t = id ? tilemap_get(id) : NULL;
    if (!t) return luaL_error(L, "bg %d: no tilemap '%s' (assets/%s.tiles, .map, .meta.json)", n, id ? id : "", id ? id : "");
    size_t bytes = (size_t)t->map_w * t->map_h * 2;
    layer[n].map = hal_realloc_slow(NULL, bytes);
    if (!layer[n].map) return luaL_error(L, "bg %d: out of memory for its map", n);
    memcpy(layer[n].map, t->map, bytes);
    b->mode = strcmp(mode, "affine") ? BG_TILES : BG_AFFINE;
    b->tiles = t->tiles, b->ntiles = t->ntiles, b->rows = t->rows;
    b->map = layer[n].map, b->map_w = t->map_w, b->map_h = t->map_h;
    if (opt_bool(L, 2, "pal", true) && safe_name(t->palette)) palette_load(t->palette, PPU.bg_pal, 0); /* its colours */
    return 0;
}

static int l_scroll(lua_State *L) {
    int n = bg_index(L, 1);
    PPU.bg[n].scroll_x = num(L, 2), PPU.bg[n].scroll_y = num(L, 3);
    return 0;
}

static int32_t fx8(lua_Number v) { return (int32_t)lroundf(fin(v) * 256.0f); } /* a position, 24.8 */
static int32_t fx8m(lua_Number v) { /* a matrix coefficient, 8.8 as on the GBA: -128 to 127.99 */
    float f = fin(v);
    return (int32_t)lroundf((f > 127.99f ? 127.99f : f < -128 ? -128 : f) * 256.0f);
}

static int l_affine(lua_State *L) { /* affine(n, pa, pb, pc, pd, x0, y0): screen (x, y) shows map (x0 + pa x + pb y, ...) */
    int n = bg_index(L, 1);
    ppu_bg *b = &PPU.bg[n];
    b->pa = fx8m(luaL_checknumber(L, 2)), b->pb = fx8m(luaL_checknumber(L, 3));
    b->pc = fx8m(luaL_checknumber(L, 4)), b->pd = fx8m(luaL_checknumber(L, 5));
    b->x0 = fx8(luaL_checknumber(L, 6)), b->y0 = fx8(luaL_checknumber(L, 7));
    return 0;
}

static int l_rot(lua_State *L) { /* rot(n, degrees, zoom, map_x, map_y, screen_x, screen_y) */
    int n = bg_index(L, 1);
    float a = (float)luaL_checknumber(L, 2) * 3.14159265f / 180.0f, z = (float)luaL_optnumber(L, 3, 1);
    float cx = (float)luaL_optnumber(L, 4, 0), cy = (float)luaL_optnumber(L, 5, 0);
    float sx = (float)luaL_optnumber(L, 6, PPU_W / 2), sy = (float)luaL_optnumber(L, 7, PPU_H / 2);
    if (z == 0) z = 1;
    float pa = cosf(a) / z, pb = sinf(a) / z, pc = -sinf(a) / z, pd = cosf(a) / z;
    ppu_bg *b = &PPU.bg[n];
    b->pa = fx8m(pa), b->pb = fx8m(pb), b->pc = fx8m(pc), b->pd = fx8m(pd);
    b->x0 = fx8(cx - (pa * sx + pb * sy)), b->y0 = fx8(cy - (pc * sx + pd * sy));
    return 0;
}

/* mode7(n, cam_x, cam_y, degrees, height, horizon, fov): a perspective floor from a camera over the map. */
static int l_mode7(lua_State *L) {
    int n = bg_index(L, 1);
    float cx = (float)luaL_checknumber(L, 2), cy = (float)luaL_checknumber(L, 3);
    float a = (float)luaL_checknumber(L, 4) * 3.14159265f / 180.0f, h = (float)luaL_optnumber(L, 5, 32);
    int hor = optnum(L, 6, 40);
    hor = hor < -10000 ? -10000 : hor > 10000 ? 10000 : hor; /* y - hor below must not overflow */
    float fov = (float)luaL_optnumber(L, 7, 120);
    float fx = sinf(a), fy = -cosf(a), rx = cosf(a), ry = sinf(a); /* forward and right on the map */
    for (int y = 0; y < PPU_H; y++) {
        ppu_line_affine *l = &line_affine_tab[n][y];
        if (y <= hor) {
            *l = (ppu_line_affine){.x = PPU_LINE_OFF};
            continue;
        }
        float d = h * fov / (float)(y - hor), step = d / fov; /* distance to the line, map units per pixel */
        float mx = cx + fx * d - rx * step * (PPU_W / 2), my = cy + fy * d - ry * step * (PPU_W / 2);
        *l = (ppu_line_affine){.pa = fx8m(rx * step), .pc = fx8m(ry * step), .x = fx8(mx), .y = fx8(my)};
    }
    PPU.line.affine[n] = line_affine_tab[n];
    layer[n].mx7_on = 1;
    layer[n].cx = cx, layer[n].cy = cy, layer[n].angle = a, layer[n].height = h, layer[n].horizon = (float)hor,
    layer[n].fov = fov;
    return 0;
}

/* project(n, map_x, map_y) -> screen x, y, scale, visible: where a point of a mode7 floor appears (for its sprites) */
static int l_project(lua_State *L) {
    int n = bg_index(L, 1);
    if (!layer[n].mx7_on) return luaL_error(L, "project: background %d has no mode7", n);
    float dx = (float)luaL_checknumber(L, 2) - layer[n].cx, dy = (float)luaL_checknumber(L, 3) - layer[n].cy;
    float a = layer[n].angle, fx = sinf(a), fy = -cosf(a), rx = cosf(a), ry = sinf(a);
    float d = dx * fx + dy * fy, side = dx * rx + dy * ry;
    if (d <= 0.5f) {
        lua_pushnumber(L, 0), lua_pushnumber(L, 0), lua_pushnumber(L, 0), lua_pushboolean(L, 0);
        return 4;
    }
    float scale = layer[n].fov / d;
    lua_pushnumber(L, PPU_W / 2 + side * scale);
    lua_pushnumber(L, layer[n].horizon + layer[n].height * scale);
    lua_pushnumber(L, scale);
    lua_pushboolean(L, 1);
    return 4;
}

static uint16_t *map_at(lua_State *L, int n, int tx, int ty) {
    ppu_bg *b = &PPU.bg[n];
    if (!layer[n].map) luaL_error(L, "background %d has no map", n);
    if (tx < 0 || ty < 0 || tx >= b->map_w || ty >= b->map_h) return NULL;
    return &layer[n].map[ty * b->map_w + tx];
}

static int l_mget(lua_State *L) {
    uint16_t *m = map_at(L, bg_index(L, 1), (int)luaL_checkinteger(L, 2), (int)luaL_checkinteger(L, 3));
    lua_pushinteger(L, m ? *m : 0);
    return 1;
}

static int l_mset(lua_State *L) {
    uint16_t *m = map_at(L, bg_index(L, 1), (int)luaL_checkinteger(L, 2), (int)luaL_checkinteger(L, 3));
    if (m) *m = (uint16_t)luaL_checkinteger(L, 4);
    return 0;
}

static int l_mapsize(lua_State *L) {
    int n = bg_index(L, 1);
    lua_pushinteger(L, PPU.bg[n].map_w), lua_pushinteger(L, PPU.bg[n].map_h);
    return 2;
}

static int line_index(lua_State *L, int arg) {
    int y = (int)luaL_checkinteger(L, arg);
    luaL_argcheck(L, y >= 0 && y < PPU_H, arg, "line 0..159");
    return y;
}

static int l_line_scroll(lua_State *L) { /* line_scroll(n, y, x, y_offset) */
    int n = bg_index(L, 1), y = line_index(L, 2);
    if (PPU.line.scroll[n] != line_scroll_tab[n]) { /* first use this frame: start from the layer's own scroll */
        for (int i = 0; i < PPU_H; i++)
            line_scroll_tab[n][i] = (ppu_line_scroll){i16(PPU.bg[n].scroll_x), i16(PPU.bg[n].scroll_y)};
        PPU.line.scroll[n] = line_scroll_tab[n];
    }
    line_scroll_tab[n][y] = (ppu_line_scroll){i16(num(L, 3)), i16(optnum(L, 4, PPU.bg[n].scroll_y))};
    return 0;
}

/* line_affine(n, y, x, y_map, pa, pc): on line y, layer n (in affine mode) starts at map point (x, y_map) and steps by (pa,
 * pc) a screen pixel: what mode7() works out for a floor, line by line, for anything else (a floor with hills, a wall seen at
 * an angle, a tower turning, a flag waving). The first use in a frame starts every line from the layer's own matrix. */
static int l_line_affine(lua_State *L) {
    int n = bg_index(L, 1), y = line_index(L, 2);
    if (PPU.line.affine[n] != line_affine_tab[n]) {
        const ppu_bg *b = &PPU.bg[n];
        for (int i = 0; i < PPU_H; i++)
            line_affine_tab[n][i] = (ppu_line_affine){.pa = b->pa, .pc = b->pc, .x = b->x0 + b->pb * i, .y = b->y0 + b->pd * i};
        PPU.line.affine[n] = line_affine_tab[n];
    }
    line_affine_tab[n][y] = (ppu_line_affine){.pa = fx8m(luaL_checknumber(L, 5)), .pc = fx8m(luaL_optnumber(L, 6, 0)),
                                              .x = fx8(luaL_checknumber(L, 3)), .y = fx8(luaL_checknumber(L, 4))};
    return 0;
}

/* line_scroll_ramp(n, y0, y1, x0, x1 [, curve]): layer n's scroll goes from x0 on line y0 to x1 on line y1, straight or along
 * k ^ curve: a floor sliding faster the nearer it is, a tower's side, a wave, in one call instead of a line_scroll a line. */
static int l_line_scroll_ramp(lua_State *L) {
    int n = bg_index(L, 1), y0 = line_index(L, 2), y1 = line_index(L, 3);
    const float x0 = fin(luaL_checknumber(L, 4)), x1 = fin(luaL_checknumber(L, 5)), curve = (float)luaL_optnumber(L, 6, 1);
    luaL_argcheck(L, curve > 0 && curve < 16, 6, "a curve above 0");
    if (PPU.line.scroll[n] != line_scroll_tab[n]) {
        for (int i = 0; i < PPU_H; i++)
            line_scroll_tab[n][i] = (ppu_line_scroll){i16(PPU.bg[n].scroll_x), i16(PPU.bg[n].scroll_y)};
        PPU.line.scroll[n] = line_scroll_tab[n];
    }
    const int step = y1 >= y0 ? 1 : -1, len = y1 >= y0 ? y1 - y0 : y0 - y1;
    for (int i = 0, y = y0; i <= len; i++, y += step) {
        float k = len ? (float)i / (float)len : 0;
        if (curve != 1) k = powf(k, curve);
        line_scroll_tab[n][y].x = i16((int)lroundf(x0 + (x1 - x0) * k));
    }
    return 0;
}

/* shock(x, y, r [, width [, amp]]) and haze(y0, y1 [, amp [, phase [, period]]]): the world's picture bent after it is drawn
 * (post.c), for this frame: a ring that pushes what it passes outwards (an explosion, a drum hit), rows swaying sideways (heat
 * over sand, a fire, a portal's edge). In the picture's own pixels (240 x 160). */
static int l_shock(lua_State *L) {
    const float x = fin(luaL_checknumber(L, 1)), y = fin(luaL_checknumber(L, 2)), r = fin(luaL_checknumber(L, 3));
    float width = (float)luaL_optnumber(L, 4, 8), amp = (float)luaL_optnumber(L, 5, 6);
    if (!(r > 0 && r < 1000)) return luaL_error(L, "shock: a radius from 0 to 1000");
    width = width < 1 ? 1 : width > 200 ? 200 : width, amp = amp < -64 ? -64 : amp > 64 ? 64 : amp;
    post_shock(x, y, r, width, amp);
    return 0;
}

static int l_haze(lua_State *L) {
    const int y0 = num(L, 1), y1 = num(L, 2);
    float amp = (float)luaL_optnumber(L, 3, 2), phase = (float)luaL_optnumber(L, 4, 0), period = (float)luaL_optnumber(L, 5, 12);
    amp = amp < -64 ? -64 : amp > 64 ? 64 : amp;
    post_haze(y0, y1, amp, phase, period);
    return 0;
}

static int l_line_backdrop(lua_State *L) {
    int y = line_index(L, 1);
    if (PPU.line.backdrop != line_back_tab) {
        for (int i = 0; i < PPU_H; i++) line_back_tab[i] = PPU.bg_pal[0];
        PPU.line.backdrop = line_back_tab;
    }
    line_back_tab[y] = to565(luaL_checkinteger(L, 2));
    return 0;
}

/* line_pal(y, index, colour [, colour ...]) and line_pal_obj(...): on line y, palette entry index (and the ones after it, one for each
 * further colour) has that colour, as a game's HBlank palette writes do (a sky that deepens, water that shimmers). Up to 16 entries a line in
 * each palette; they last until line_off(). */
/* entry `idx` of line y's table takes colour c (the same entry again is replaced, not added); false when the line is full */
static bool line_pal_put(ppu_line_pal *tab, int y, int idx, uint16_t c) {
    ppu_line_pal *e = &tab[y];
    int at = -1;
    for (int i = 0; i < e->n; i++) if (e->idx[i] == idx) at = i;
    if (at < 0) {
        if (e->n >= PPU_LINE_PALS) return false;
        at = e->n++;
    }
    e->idx[at] = (uint8_t)idx, e->col[at] = c;
    return true;
}

static ppu_line_pal *line_pal_table(bool obj) { /* the table of the frame, made ready the first time it is written */
    ppu_line_pal *tab = line_pal_tab[obj ? 1 : 0];
    const ppu_line_pal **slot = obj ? &PPU.line.pal_obj : &PPU.line.pal_bg;
    if (*slot != tab) {
        memset(tab, 0, sizeof line_pal_tab[0]);
        *slot = tab;
    }
    return tab;
}

static int line_pal_set(lua_State *L, bool obj) {
    int y = line_index(L, 1);
    int first = (int)luaL_checkinteger(L, 2);
    int n = lua_gettop(L) - 2;
    luaL_argcheck(L, first >= 0 && first < 256, 2, "entry 0..255");
    if (n < 1) return luaL_error(L, "line_pal: a colour at least");
    luaL_argcheck(L, first + n <= 256, 2, "entries run past 255");
    ppu_line_pal *tab = line_pal_table(obj);
    for (int k = 0; k < n; k++)
        if (!line_pal_put(tab, y, first + k, to565(luaL_checkinteger(L, 3 + k)))) return luaL_error(L, "line_pal: %d entries a line at most", PPU_LINE_PALS);
    return 0;
}
static int l_line_pal(lua_State *L) { return line_pal_set(L, false); }

/* line_ramp(y0, y1, index, from, to [, curve] [, "obj"]): entry `index` of the palette goes from colour `from` on line y0 to `to` on
 * line y1, in a straight line, or along k ^ curve (a sky that pales quickly near the horizon: 1.5). One call for what would be a
 * line_pal on every line: a sky, a sea, a glow, without a hundred calls into C a frame. */
static int l_line_ramp(lua_State *L) {
    int y0 = line_index(L, 1), y1 = line_index(L, 2);
    int idx = (int)luaL_checkinteger(L, 3);
    luaL_argcheck(L, idx >= 0 && idx < 256, 3, "entry 0..255");
    lua_Integer a = luaL_checkinteger(L, 4), b = luaL_checkinteger(L, 5);
    int top = lua_gettop(L);
    bool obj = top >= 6 && lua_type(L, top) == LUA_TSTRING && !strcmp(lua_tostring(L, top), "obj");
    float curve = top >= 6 && lua_type(L, 6) == LUA_TNUMBER ? (float)lua_tonumber(L, 6) : 1.0f;
    luaL_argcheck(L, curve > 0 && curve < 16, 6, "a curve above 0");
    ppu_line_pal *tab = line_pal_table(obj);
    const int ar = (int)(a >> 16 & 255), ag = (int)(a >> 8 & 255), ab = (int)(a & 255);
    const int br = (int)(b >> 16 & 255), bg_ = (int)(b >> 8 & 255), bb = (int)(b & 255);
    int step = y1 >= y0 ? 1 : -1, n = y1 >= y0 ? y1 - y0 : y0 - y1;
    for (int i = 0, y = y0; i <= n; i++, y += step) {
        float k = n ? (float)i / (float)n : 0.0f;
        if (curve != 1.0f) k = powf(k, curve);
        int r = ar + (int)lroundf((float)(br - ar) * k), g = ag + (int)lroundf((float)(bg_ - ag) * k), bl = ab + (int)lroundf((float)(bb - ab) * k);
        if (!line_pal_put(tab, y, idx, to565(r << 16 | g << 8 | bl))) return luaL_error(L, "line_ramp: %d entries a line at most", PPU_LINE_PALS);
    }
    return 0;
}
static int l_line_pal_obj(lua_State *L) { return line_pal_set(L, true); }

static int l_line_window(lua_State *L) { /* line_window(k, y, x1, x2) */
    int k = (int)luaL_checkinteger(L, 1) & 1, y = line_index(L, 2);
    if (PPU.line.win[k] != line_win_tab[k]) {
        memset(line_win_tab[k], 0, sizeof line_win_tab[k]);
        PPU.line.win[k] = line_win_tab[k];
    }
    line_win_tab[k][y] = (ppu_line_span){i16(num(L, 3)), i16(num(L, 4))};
    return 0;
}

static int l_line_off(lua_State *L) {
    (void)L;
    for (int n = 0; n < PPU_BGS; n++) {
        PPU.line.scroll[n] = NULL;
        if (!layer[n].mx7_on) PPU.line.affine[n] = NULL;
    }
    PPU.line.win[0] = PPU.line.win[1] = NULL;
    PPU.line.backdrop = NULL;
    PPU.line.fx_ev = NULL;
    PPU.line.pal_bg = PPU.line.pal_obj = NULL;
    return 0;
}

static int l_sheet(lua_State *L) { /* sheet(id) -> handle, w, h, frames */
    const char *id = luaL_checkstring(L, 1);
    int h = safe_name(id) ? sheet_get(id) : 0;
    if (!h) return luaL_error(L, "sheet: no sprite sheet '%s'", id);
    lua_pushinteger(L, h);
    lua_pushinteger(L, sheets[h - 1].w), lua_pushinteger(L, sheets[h - 1].h), lua_pushinteger(L, sheets[h - 1].frames);
    return 4;
}

enum { F_FLIPX = 1, F_FLIPY = 2, F_BLEND = 4, F_WINDOW = 8, F_DOUBLE = 16, F_MOSAIC = 32 };

static int obj_index(lua_State *L, int arg) {
    int i = (int)luaL_checkinteger(L, arg);
    luaL_argcheck(L, i >= 0 && i < PPU_OBJS, arg, "sprite 0..127");
    return i;
}

/* spr(i, sheet, frame, x, y [, flags]): flags FLIP_X | FLIP_Y | BLEND | WINDOW | DOUBLE | MOSAIC | prio(p) | bank(b) |
 * spr_mat(m) */
static int l_spr(lua_State *L) {
    int i = obj_index(L, 1), h = (int)luaL_checkinteger(L, 2);
    if (h < 1 || h > nsheets) return luaL_error(L, "spr: %d is not a sheet (use sheet(id))", h);
    const sheet *s = &sheets[h - 1];
    int f = (int)luaL_optinteger(L, 3, 0), fl = (int)luaL_optinteger(L, 6, 0);
    if (f < 0 || f >= s->frames) f = 0;
    ppu_obj *o = &PPU.obj[i];
    *o = (ppu_obj){.on = true, .x = i16(num(L, 4)), .y = i16(num(L, 5)), .w = (uint8_t)s->w, .h = (uint8_t)s->h,
                   .hflip = fl & F_FLIPX, .vflip = (fl & F_FLIPY) != 0, .mosaic = (fl & F_MOSAIC) != 0,
                   .mode = (uint8_t)(fl & F_WINDOW ? OBJ_WINDOW : fl & F_BLEND ? OBJ_BLEND : OBJ_NORMAL),
                   .dbl = (fl & F_DOUBLE) != 0, .prio = (uint8_t)((fl >> 8) & 3), .bank = (uint8_t)((fl >> 12) & 15),
                   .affine = (int8_t)(((fl >> 16) & 63) - 1)};
    if (s->idx) o->idx = s->idx + (size_t)f * s->w * s->h;
    else {
        o->rgb = s->a->pixels + (size_t)f * s->w * s->h;
        o->mask = s->a->mask ? s->a->mask + (size_t)f * ((s->w + 7) / 8) * s->h : NULL;
    }
    return 0;
}

static int l_spr_off(lua_State *L) { PPU.obj[obj_index(L, 1)].on = false; return 0; }

static int l_spr_clear(lua_State *L) {
    (void)L;
    for (int i = 0; i < PPU_OBJS; i++) PPU.obj[i].on = false;
    return 0;
}

static int l_prio(lua_State *L) { lua_pushinteger(L, (luaL_checkinteger(L, 1) & 3) << 8); return 1; }
static int l_bank(lua_State *L) { lua_pushinteger(L, (luaL_checkinteger(L, 1) & 15) << 12); return 1; }
static int l_spr_mat(lua_State *L) { lua_pushinteger(L, ((luaL_checkinteger(L, 1) & 31) + 1) << 16); return 1; }

static int l_mat(lua_State *L) { /* mat(m, degrees, scale_x [, scale_y]): sprite matrix m turns and scales */
    int m = (int)luaL_checkinteger(L, 1) & (PPU_AFFINES - 1);
    float a = (float)luaL_checknumber(L, 2) * 3.14159265f / 180.0f, sx = (float)luaL_optnumber(L, 3, 1);
    float sy = (float)luaL_optnumber(L, 4, sx);
    if (sx == 0) sx = 1;
    if (sy == 0) sy = 1;
    PPU.affine[m] = (ppu_affine){(int16_t)fx8m(cosf(a) / sx), (int16_t)fx8m(sinf(a) / sx),
                                 (int16_t)fx8m(-sinf(a) / sy), (int16_t)fx8m(cosf(a) / sy)};
    return 0;
}

static int ev(lua_State *L, int arg) {
    int v = num(L, arg);
    return v < 0 ? 0 : v > 16 ? 16 : v;
}

static int l_blend(lua_State *L) { /* blend(first, second, eva, evb) */
    PPU.fx.mode = FX_ALPHA, PPU.fx.first = (uint8_t)luaL_checkinteger(L, 1), PPU.fx.second = (uint8_t)luaL_checkinteger(L, 2);
    PPU.fx.eva = (uint8_t)ev(L, 3), PPU.fx.evb = (uint8_t)ev(L, 4);
    return 0;
}

static int l_fade(lua_State *L) { /* fade("light" | "dark", layers, amount 0..16) */
    const char *k = luaL_checkstring(L, 1);
    PPU.fx.mode = strcmp(k, "light") ? FX_DARKEN : FX_LIGHTEN;
    PPU.fx.first = (uint8_t)luaL_checkinteger(L, 2), PPU.fx.evy = (uint8_t)ev(L, 3);
    return 0;
}

static int l_line_fx(lua_State *L) { /* line_fx(y, amount 0..16): the fade's amount, or the blend's weight of the first target
                                        (the second gets 16 - amount), on line y: fog that thickens with distance */
    int y = line_index(L, 1);
    if (PPU.line.fx_ev != line_ev_tab) { /* first use this frame: every line starts at the effect's own amount */
        memset(line_ev_tab, PPU.fx.mode == FX_ALPHA ? PPU.fx.eva : PPU.fx.evy, sizeof line_ev_tab);
        PPU.line.fx_ev = line_ev_tab;
    }
    line_ev_tab[y] = (uint8_t)ev(L, 2);
    return 0;
}

static int l_show(lua_State *L) { /* show(layers): which of BG0..BG3 and OBJ are drawn */
    PPU.layers = (uint8_t)(luaL_checkinteger(L, 1) & (PPU_BG0 | PPU_BG1 | PPU_BG2 | PPU_BG3 | PPU_OBJ));
    return 0;
}

static int l_fx_off(lua_State *L) {
    (void)L;
    PPU.fx.mode = FX_NONE;
    return 0;
}

static int l_window(lua_State *L) { /* window(k, x1, y1, x2, y2, inside) */
    int k = (int)luaL_checkinteger(L, 1) & 1;
    PPU.win.on[k] = true;
    PPU.win.rect[k] = (ppu_rect){i16(num(L, 2)), i16(num(L, 4)), i16(num(L, 3)), i16(num(L, 5))};
    PPU.win.in[k] = (uint8_t)luaL_checkinteger(L, 6);
    return 0;
}

static int l_window_off(lua_State *L) { PPU.win.on[(int)luaL_checkinteger(L, 1) & 1] = false; return 0; }
static int l_window_out(lua_State *L) { PPU.win.out = (uint8_t)luaL_checkinteger(L, 1); return 0; }

static int l_objwindow(lua_State *L) { /* objwindow(inside) or objwindow(nil) to turn it off */
    PPU.win.obj_on = !lua_isnoneornil(L, 1);
    PPU.win.obj_in = (uint8_t)luaL_optinteger(L, 1, 0);
    return 0;
}

static int l_mosaic(lua_State *L) {
    int v[4];
    for (int i = 0; i < 4; i++) {
        v[i] = (int)luaL_optinteger(L, i + 1, i < 2 ? 1 : (int)luaL_optinteger(L, i - 1, 1));
        if (v[i] < 1) v[i] = 1;
        if (v[i] > 16) v[i] = 16;
    }
    PPU.mosaic.bg_w = (uint8_t)v[0], PPU.mosaic.bg_h = (uint8_t)v[1], PPU.mosaic.obj_w = (uint8_t)v[2], PPU.mosaic.obj_h = (uint8_t)v[3];
    return 0;
}

/* noise(x [, y [, z]]) -> about -1..1: Ken Perlin's improved gradient noise, smooth from one place to the next and
 * the same on every machine (its shuffle is made from a fixed seed). For landscapes, clouds, wobbles. */
static uint8_t perm[512];
static bool perm_made;

static float fade(float t) { return t * t * t * (t * (t * 6 - 15) + 10); }
static float lerp(float t, float a, float b) { return a + t * (b - a); }
static float grad(int h, float x, float y, float z) {
    h &= 15;
    float u = h < 8 ? x : y, v = h < 4 ? y : (h == 12 || h == 14) ? x : z;
    return ((h & 1) ? -u : u) + ((h & 2) ? -v : v);
}

static int l_noise(lua_State *L) {
    if (!perm_made) { /* once: 0..255 shuffled by a fixed LCG, twice over */
        for (int i = 0; i < 256; i++) perm[i] = (uint8_t)i;
        uint32_t r = 2463534242u;
        for (int i = 255; i > 0; i--) {
            r = r * 1664525u + 1013904223u;
            int j = (int)((r >> 8) % (uint32_t)(i + 1));
            uint8_t t = perm[i];
            perm[i] = perm[j], perm[j] = t;
        }
        for (int i = 0; i < 256; i++) perm[256 + i] = perm[i];
        perm_made = true;
    }
    float x = fin(luaL_checknumber(L, 1)), y = fin(luaL_optnumber(L, 2, 0)), z = fin(luaL_optnumber(L, 3, 0));
    float fx = floorf(x), fy = floorf(y), fz = floorf(z);
    int X = (int)fx & 255, Y = (int)fy & 255, Z = (int)fz & 255;
    x -= fx, y -= fy, z -= fz;
    float u = fade(x), v = fade(y), w = fade(z);
    int A = perm[X] + Y, AA = perm[A] + Z, AB = perm[A + 1] + Z, B = perm[X + 1] + Y, BA = perm[B] + Z, BB = perm[B + 1] + Z;
    float n = lerp(w, lerp(v, lerp(u, grad(perm[AA], x, y, z), grad(perm[BA], x - 1, y, z)),
                           lerp(u, grad(perm[AB], x, y - 1, z), grad(perm[BB], x - 1, y - 1, z))),
                   lerp(v, lerp(u, grad(perm[AA + 1], x, y, z - 1), grad(perm[BA + 1], x - 1, y, z - 1)),
                        lerp(u, grad(perm[AB + 1], x, y - 1, z - 1), grad(perm[BB + 1], x - 1, y - 1, z - 1))));
    lua_pushnumber(L, n);
    return 1;
}

/* The meter (perf(true); MENU and C together on the console, F3 on a desktop): the frames a second, the last 60
 * frames' times as bars, where a frame goes and what the game holds, drawn over everything. */
static struct {
    bool on;
    uint32_t last_us;
    uint16_t ms10[60]; /* each frame's time, in tenths of a millisecond */
    int k;
} meter;

void v2_meter_toggle(void) { meter.on = !meter.on; }

static void meter_frame(void) { /* once a frame */
    uint32_t now = hal_micros(), d = now - meter.last_us;
    meter.last_us = now;
    meter.ms10[meter.k] = (uint16_t)(d / 100 > 9999 ? 9999 : d / 100);
    meter.k = (meter.k + 1) % 60;
}

static void meter_draw(surface *s) {
    uint32_t sum = 0;
    for (int i = 0; i < 60; i++) sum += meter.ms10[i];
    float ms = sum / 600.0f;
    char line[6][96];
    snprintf(line[0], sizeof line[0], "%.0f fps   %.1f ms a frame", ms > 0 ? 1000 / ms : 0, ms);
    snprintf(line[1], sizeof line[1], "update %.1f  draw %.1f  layers %.1f", us_update / 1000.0f, us_draw / 1000.0f,
             us_ppu / 1000.0f);
    snprintf(line[2], sizeof line[2], "Lua %u KB   pictures %u KB", (unsigned)(mem_used / 1024),
             (unsigned)(gfx_picture_bytes() / 1024));
    int cmds, cmds_max, slots, slots_max;
    draw_profile_slots(&cmds, &cmds_max, &slots, &slots_max);
    snprintf(line[3], sizeof line[3], "commands %d/%d   slots %d/%d", cmds, cmds_max, slots, slots_max);
    draw_prof_row rows[3];
    const int nr = draw_profile_rows(rows, 3);
    int at = snprintf(line[4], sizeof line[4], "strips (CPU ms):");
    for (int i = 0; i < nr && at < (int)sizeof line[4]; i++)
        at += snprintf(line[4] + at, sizeof line[4] - (size_t)at, " %s %.1f", rows[i].name, rows[i].ms);
    if (!nr) snprintf(line[4], sizeof line[4], "strips: one frame to measure");
    int nl = 5;
    if (prof_on()) { /* perf("lua"): the dearest functions by their own time, as shares of the Lua time sampled */
        prof_row top[2];
        float total = 0;
        const int np = prof_rows(top, 2, &total);
        at = snprintf(line[5], sizeof line[5], "Lua:");
        for (int i = 0; i < np && at < (int)sizeof line[5]; i++)
            at += snprintf(line[5] + at, sizeof line[5] - (size_t)at, " %.24s %.0f%%", top[i].name,
                           total > 0 ? 100 * top[i].self_ms / total : 0);
        nl = 6;
    }
    int lh = G.font.h - 6, h = nl * lh + 8, tw = 0, tw_all = 0;
    for (int i = 0; i < nl; i++) {
        int w = font_width(&G.font, line[i], (int)strlen(line[i]));
        tw_all = w > tw_all ? w : tw_all;
        if (i < 3) tw = w > tw ? w : tw;
    }
    /* the bars sit right of the first three lines (up to 33 ms, the 16.7 ms of 60 fps marked); the two lines of the strips are wider */
    int bx = 10 + tw + 10, by = 4 + 3 * lh + 2;
    int shade_w = bx + 66 > 10 + tw_all + 6 ? bx + 66 : 10 + tw_all + 6;
    if (shade_w > SCREEN_W - 4) shade_w = SCREEN_W - 4;
    gfx_shade(s, 4, 4, shade_w, h), gfx_shade(s, 4, 4, shade_w, h);
    for (int i = 0; i < nl; i++) font_draw(s, &G.font, 10, 6 + i * lh, line[i], (int)strlen(line[i]), -1, C_PAPER);
    for (int i = 0; i < 60; i++) {
        int v = meter.ms10[(meter.k + i) % 60], bh = v / 10 > 33 ? 33 : v / 10;
        gfx_fill(s, bx + i, by - bh, 1, bh, v <= 175 ? RGB(96, 224, 128) : RGB(255, 96, 80));
    }
    gfx_fill(s, bx, by - 17, 60, 1, RGB(255, 224, 112));
}

static int l_perf(lua_State *L) { /* perf() -> ms of the last _update, _draw, picture, and KB of script memory;
                                   * perf(true) / perf(false): the meter on the screen;
                                   * perf("ops") -> {kind = {n, ms}}, commands, slots: where the last frame's drawing went;
                                   * perf("lua") -> {{name, self, total}, ...} (ms, dearest own time first), ms sampled:
                                   * where the Lua time went since the first call; perf("lua", false) stops it */
    if (lua_isboolean(L, 1)) {
        meter.on = lua_toboolean(L, 1);
        return 0;
    }
    if (lua_type(L, 1) == LUA_TSTRING && !strcmp(lua_tostring(L, 1), "lua")) {
        if (lua_isboolean(L, 2) && !lua_toboolean(L, 2)) {
            prof_stop();
            return 0;
        }
        prof_start(); /* from the next call into the game on (this one is not sampled) */
        prof_row rows[128];
        float total = 0;
        const int n = prof_rows(rows, 128, &total);
        lua_createtable(L, n, 0);
        for (int i = 0; i < n; i++) {
            lua_createtable(L, 0, 3);
            lua_pushstring(L, rows[i].name), lua_setfield(L, -2, "name");
            lua_pushnumber(L, rows[i].self_ms), lua_setfield(L, -2, "self");
            lua_pushnumber(L, rows[i].total_ms), lua_setfield(L, -2, "total");
            lua_rawseti(L, -2, i + 1);
        }
        lua_pushnumber(L, total);
        return 2;
    }
    if (lua_type(L, 1) == LUA_TSTRING && !strcmp(lua_tostring(L, 1), "ops")) {
        draw_profile(2u, true); /* from now on every frame is measured (the first answer is empty: a frame has to go by) */
        draw_prof_row rows[32];
        const int n = draw_profile_rows(rows, 32);
        lua_createtable(L, 0, n);
        for (int i = 0; i < n; i++) {
            lua_createtable(L, 0, 2);
            lua_pushinteger(L, rows[i].n), lua_setfield(L, -2, "n");
            lua_pushnumber(L, rows[i].ms), lua_setfield(L, -2, "ms");
            lua_setfield(L, -2, rows[i].name);
        }
        int cmds, cmds_max, slots, slots_max;
        draw_profile_slots(&cmds, &cmds_max, &slots, &slots_max);
        lua_pushinteger(L, cmds), lua_pushinteger(L, slots);
        return 3;
    }
    lua_pushnumber(L, us_update / 1000.0f), lua_pushnumber(L, us_draw / 1000.0f), lua_pushnumber(L, us_ppu / 1000.0f);
    lua_pushnumber(L, mem_used / 1024.0f);
    return 4;
}

/* menuitem(label [, fn]): an item of the console's menu (a tap of MENU), the game's own, three at most: fn runs when the
 * player chooses it, with the menu closed; menuitem(label) takes that item away; menuitem() takes all of them. */
#define MENU_ITEMS 3
static int l_menuitem(lua_State *L) {
    lua_getfield(L, LUA_REGISTRYINDEX, "pinyol.menu");
    if (lua_isnoneornil(L, 1)) { /* all gone */
        lua_pushnil(L), lua_setfield(L, LUA_REGISTRYINDEX, "pinyol.menu");
        return 0;
    }
    if (lua_isnil(L, -1)) lua_pop(L, 1), lua_newtable(L), lua_pushvalue(L, -1), lua_setfield(L, LUA_REGISTRYINDEX, "pinyol.menu");
    const char *label = luaL_checkstring(L, 1);
    if (strlen(label) > 32) return luaL_error(L, "menuitem: a label of 32 characters at most");
    const int t = lua_gettop(L), n = (int)lua_rawlen(L, t);
    int at = 0;
    for (int i = 1; i <= n && !at; i++) { /* the same label: that item */
        lua_rawgeti(L, t, i), lua_getfield(L, -1, "label");
        if (!strcmp(lua_tostring(L, -1), label)) at = i;
        lua_pop(L, 2);
    }
    if (lua_isnoneornil(L, 2)) { /* taken away */
        if (at) {
            for (int i = at; i < n; i++) lua_rawgeti(L, t, i + 1), lua_rawseti(L, t, i);
            lua_pushnil(L), lua_rawseti(L, t, n);
        }
        return 0;
    }
    luaL_checktype(L, 2, LUA_TFUNCTION);
    if (!at && n >= MENU_ITEMS) return luaL_error(L, "menuitem: %d items at most", MENU_ITEMS);
    lua_createtable(L, 0, 2);
    lua_pushvalue(L, 1), lua_setfield(L, -2, "label");
    lua_pushvalue(L, 2), lua_setfield(L, -2, "fn");
    lua_rawseti(L, t, at ? at : n + 1);
    return 0;
}

int v2_menu_items(const char **labels, int max) {
    if (!Ls) return 0;
    lua_getfield(Ls, LUA_REGISTRYINDEX, "pinyol.menu");
    const int n = lua_istable(Ls, -1) ? (int)lua_rawlen(Ls, -1) : 0;
    for (int i = 0; labels && i < n && i < max; i++) {
        lua_rawgeti(Ls, -1, i + 1), lua_getfield(Ls, -1, "label");
        labels[i] = lua_tostring(Ls, -1); /* (kept alive by the table) */
        lua_pop(Ls, 2);
    }
    lua_pop(Ls, 1);
    return n;
}

void v2_menu_choose(int i) {
    if (!Ls || failed) return;
    lua_pushcfunction(Ls, msgh);
    lua_getfield(Ls, LUA_REGISTRYINDEX, "pinyol.menu");
    if (!lua_istable(Ls, -1)) { lua_pop(Ls, 2); return; }
    lua_rawgeti(Ls, -1, i + 1);
    if (!lua_istable(Ls, -1)) { lua_pop(Ls, 3); return; }
    lua_getfield(Ls, -1, "fn");
    lua_replace(Ls, -3), lua_pop(Ls, 1); /* the function where the menu table was */
    arm_as("menuitem");
    const int rc = lua_pcall(Ls, 0, 0, -2);
    if (rc != LUA_OK) fail("menuitem", lua_tostring(Ls, -1)), lua_pop(Ls, 1);
    lua_pop(Ls, 1); /* msgh */
    draw_flush();
}

void v2_menu_event(const char *fn) {
    if (Ls && !failed) call(fn, 0);
}

/* achieve(id) -> true the first time: an achievement of the game earned (game.json "achievements": [{"id", "name",
 * "description"}, ...]), kept by the console with the game's record (played.c), for its menu and the Library's shelf.
 * achievements() -> the list, each {id, name, description, done}. */
static int l_achieve(lua_State *L) {
    const char *id = luaL_checkstring(L, 1), *game = jstr(G.game, "id");
    const cJSON *list = jget(G.game, "achievements"), *it;
    bool known = false;
    cJSON_ArrayForEach(it, list) if (cJSON_IsObject(it) && jstr(it, "id") && !strcmp(jstr(it, "id"), id)) known = true;
    if (!known) return luaL_error(L, "achieve: game.json lists no achievement \"%s\"", id);
    lua_pushboolean(L, game && played_achieve(game, id));
    return 1;
}

static int l_achievements(lua_State *L) {
    const char *game = jstr(G.game, "id");
    const cJSON *list = jget(G.game, "achievements"), *it;
    lua_newtable(L);
    int n = 0;
    cJSON_ArrayForEach(it, list) {
        if (!cJSON_IsObject(it) || !jstr(it, "id")) continue;
        lua_createtable(L, 0, 4);
        lua_pushstring(L, jstr(it, "id")), lua_setfield(L, -2, "id");
        lua_pushstring(L, jstr(it, "name") ? jstr(it, "name") : jstr(it, "id")), lua_setfield(L, -2, "name");
        lua_pushstring(L, jstr(it, "description") ? jstr(it, "description") : ""), lua_setfield(L, -2, "description");
        lua_pushboolean(L, game && played_achieved(game, jstr(it, "id"))), lua_setfield(L, -2, "done");
        lua_rawseti(L, -2, ++n);
    }
    return 1;
}

static int l_settings(lua_State *L) { /* settings() -> the console's settings: volume, reduce_flashing, colour, speed, lang, swap_ab */
    static const char *const COL[] = {"normal", "protan", "deutan", "tritan"};
    lua_createtable(L, 0, 6);
    lua_pushinteger(L, CONF.volume), lua_setfield(L, -2, "volume");
    lua_pushboolean(L, CONF.reduce_flash), lua_setfield(L, -2, "reduce_flashing");
    lua_pushstring(L, COL[CONF.colour]), lua_setfield(L, -2, "colour");
    lua_pushinteger(L, CONF.speed), lua_setfield(L, -2, "speed");
    lua_pushstring(L, conf_lang_code()), lua_setfield(L, -2, "lang");
    lua_pushboolean(L, CONF.swap_ab), lua_setfield(L, -2, "swap_ab");
    return 1;
}

static int l_quit(lua_State *L) {
    (void)L;
    if (hal_can_switch_game()) hal_switch_game();
    else G.quit = true;
    return 0;
}

/* store(key, value) / stored(key [, default]): numbers, strings, booleans and tables of them (lists, or string
 * keys), kept in the game's saves folder (v2.json), for high scores, options and progress. */
static cJSON *store;
#define STORE_MAX_BYTES 65536 /* the whole file: a save, not a database */
#define STORE_MAX_DEPTH 16
#define STORE_MAX_VALUES 20000 /* in one store(): shared subtables would otherwise multiply (t = {u, u, u}, ...) */

static void store_path(char *p, size_t n) { snprintf(p, n, "%s/v2.json", G.save_dir); }

/* The saves live in two files, v2.json and v2.json.b, written in turn: each ends its JSON with "#gen N crc XXXXXXXX" (the
 * generation, and the CRC-32 of the JSON before it) and the newest one that reads whole and checks is the saves (a cut or
 * torn write spoils only the one being written: the card may put a file's sectors down in any order). Each is padded to
 * whole 4 KB sectors and rewritten in place, so a save on the console's FAT touches its data and little else. A file
 * with no "crc" (an older engine's) is believed as it is, and an older engine reads these: it stops at the "#gen N". */
static cJSON *store_read(const char *path, long *gen) {
    char *txt = read_file(path, NULL);
    cJSON *j = txt ? cJSON_Parse(txt) : NULL; /* stops at the end of the JSON: the "#gen" after it is not read */
    const char *g = txt ? strstr(txt, "\n#gen ") : NULL;
    unsigned crc = 0;
    int fields = g ? sscanf(g, "\n#gen %ld crc %x", gen, &crc) : 0;
    if (!g) *gen = 0;
    if (fields == 2 && crc32_buf((const uint8_t *)txt, (size_t)(g - txt)) != crc) cJSON_Delete(j), j = NULL; /* torn */
    free(txt);
    if (!cJSON_IsObject(j)) cJSON_Delete(j), j = NULL;
    return j;
}

static long store_gen; /* the newest file's generation: the next save writes the other with this + 1 */

static cJSON *store_get(void) {
    if (store) return store;
    char p[384], b[400], tmp[400];
    long ga = -1, gb = -1;
    store_path(p, sizeof p);
    snprintf(b, sizeof b, "%s.b", p);
    snprintf(tmp, sizeof tmp, "%s.tmp", p);
    cJSON *a = store_read(p, &ga), *bb = store_read(b, &gb);
    if (a && (!bb || ga >= gb)) store = a, store_gen = ga, cJSON_Delete(bb);
    else if (bb) store = bb, store_gen = gb, cJSON_Delete(a);
    else if (!(store = store_read(tmp, &ga))) store = cJSON_CreateObject(); /* tmp: a save cut by an older engine */
    return store;
}

/* The saves into the older of the two files (see store_read), in place when it is already the right size. The generation
 * moves on only once the file is down: a save that fails is tried again on the same file, never on the last good one. */
#define SAVE_SECTOR 4096
bool save_file_atomic(const char *p, const char *txt) {
    char path[400], tail[48];
    long gen = __atomic_load_n(&store_gen, __ATOMIC_SEQ_CST) + 1;
    snprintf(path, sizeof path, gen % 2 ? "%s.b" : "%s", p);
    size_t n = strlen(txt);
    int nt = snprintf(tail, sizeof tail, "\n#gen %ld crc %08x\n", gen, (unsigned)crc32_buf((const uint8_t *)txt, n));
    size_t size = (n + (size_t)nt + SAVE_SECTOR) / SAVE_SECTOR * SAVE_SECTOR;
    struct stat st;
    FILE *f = (!stat(path, &st) && (size_t)st.st_size == size) ? fopen(path, "r+b") : fopen(path, "wb");
    if (!f) return false;
    bool ok = fwrite(txt, 1, n, f) == n && fwrite(tail, 1, (size_t)nt, f) == (size_t)nt;
    for (size_t k = n + (size_t)nt; ok && k < size; k++) ok = fputc(' ', f) != EOF; /* the rest of the sector */
    ok = (fclose(f) == 0) && ok;
    if (ok) __atomic_store_n(&store_gen, gen, __ATOMIC_SEQ_CST);
    return ok;
}

/* The C library's clock: the offset is worked out from the local and the UTC breakdowns of the same moment, with no
 * extension (tm_gmtoff is not everywhere). A year before 2020 is taken as a clock that was never set. */
__attribute__((weak)) bool hal_clock(int64_t *utc_s, int *offset_min) {
    time_t t = time(NULL);
    struct tm lt, gt;
    const struct tm *l = localtime(&t);
    if (!l) return false;
    lt = *l;
    const struct tm *g = gmtime(&t);
    if (!g) return false;
    gt = *g;
    int days = lt.tm_yday - gt.tm_yday;
    if (lt.tm_year != gt.tm_year) days = lt.tm_year > gt.tm_year ? 1 : -1; /* (across new year) */
    *utc_s = (int64_t)t;
    *offset_min = days * 1440 + (lt.tm_hour - gt.tm_hour) * 60 + (lt.tm_min - gt.tm_min);
    return lt.tm_year + 1900 >= 2020;
}

static struct { bool on, known; int64_t utc_s; int offset; } forced;
void clock_force(bool on, bool known, int64_t utc_s, int offset_min) { forced.on = on, forced.known = known, forced.utc_s = utc_s, forced.offset = offset_min; }

/* clock() -> {year, month, day, hour, min, sec, wday (1 Monday .. 7 Sunday), yday (1..366), days, offset}, the local date and time;
 * nil when the machine does not know it. days counts from 1970-01-01 (local): the time between two sessions, in a 32-bit Lua (the console's)
 * that seconds since 1970 would overflow in 2038. The civil date from the days since 1970 (H. Hinnant's days_from_civil, backwards). */
static int l_clock(lua_State *L) {
    int64_t utc_s = 0;
    int off = 0;
    bool known = forced.on ? forced.known : hal_clock(&utc_s, &off);
    if (forced.on) utc_s = forced.utc_s, off = forced.offset;
    if (!known) return lua_pushnil(L), 1;
    int64_t local = utc_s + (int64_t)off * 60;
    int64_t days = local >= 0 ? local / 86400 : -((-local + 86399) / 86400), secs = local - days * 86400;
    int64_t z = days + 719468, era = (z >= 0 ? z : z - 146096) / 146097;
    int64_t doe = z - era * 146097, yoe = (doe - doe / 1460 + doe / 36524 - doe / 146096) / 365;
    int64_t doy = doe - (365 * yoe + yoe / 4 - yoe / 100), mp = (5 * doy + 2) / 153;
    int64_t d = doy - (153 * mp + 2) / 5 + 1, m = mp < 10 ? mp + 3 : mp - 9, y = yoe + era * 400 + (m <= 2);
    static const int before[12] = {0, 31, 59, 90, 120, 151, 181, 212, 243, 273, 304, 334};
    bool leap = (y % 4 == 0 && y % 100 != 0) || y % 400 == 0;
    lua_createtable(L, 0, 10);
    lua_pushinteger(L, (lua_Integer)y), lua_setfield(L, -2, "year");
    lua_pushinteger(L, (lua_Integer)m), lua_setfield(L, -2, "month");
    lua_pushinteger(L, (lua_Integer)d), lua_setfield(L, -2, "day");
    lua_pushinteger(L, (lua_Integer)(secs / 3600)), lua_setfield(L, -2, "hour");
    lua_pushinteger(L, (lua_Integer)(secs / 60 % 60)), lua_setfield(L, -2, "min");
    lua_pushinteger(L, (lua_Integer)(secs % 60)), lua_setfield(L, -2, "sec");
    lua_pushinteger(L, (lua_Integer)(((days % 7) + 7 + 3) % 7 + 1)), lua_setfield(L, -2, "wday"); /* 1970-01-01 was a Thursday */
    lua_pushinteger(L, (lua_Integer)(before[m - 1] + d + (leap && m > 2))), lua_setfield(L, -2, "yday");
    lua_pushinteger(L, (lua_Integer)days), lua_setfield(L, -2, "days");
    lua_pushinteger(L, (lua_Integer)off), lua_setfield(L, -2, "offset");
    return 1;
}

__attribute__((weak)) bool hal_save(const char *path, const char *txt) { return save_file_atomic(path, txt); }
__attribute__((weak)) bool hal_console_dir(char *path, size_t n) { (void)path, (void)n; return false; } /* no folder of its own: the defaults */
__attribute__((weak)) bool hal_imu(float *x, float *y, float *z) { (void)x, (void)y, (void)z; return false; } /* no tilt sensor */
__attribute__((weak)) void hal_rumble(int ms, float strength) { (void)ms, (void)strength; }                 /* no motor */
__attribute__((weak)) void hal_save_flush(void) {}

static bool store_write(const char *txt) {
    char p[384];
    store_path(p, sizeof p);
    return hal_save(p, txt);
}

/* A game's value as JSON (store, link.send): numbers, strings, booleans and tables of them, lists or string keys.
 * NULL with a message pushed ("who: ..."). *count counts the values against STORE_MAX_VALUES: tables shared inside
 * one value would otherwise multiply. */
cJSON *json_from_lua(lua_State *L, int i, int depth, const char *who, int *count) {
    if (++*count > STORE_MAX_VALUES) {
        lua_pushfstring(L, "%s: more than %d values in one go", who, STORE_MAX_VALUES);
        return NULL;
    }
    switch (lua_type(L, i)) {
    case LUA_TNUMBER: {
        lua_Number d = lua_tonumber(L, i);
        if (d != d || d - d != 0) { /* NaN or an infinity: JSON has no such numbers */
            lua_pushfstring(L, "%s: a number that is not finite (nan or inf) cannot be kept", who);
            return NULL;
        }
        return cJSON_CreateNumber(d);
    }
    case LUA_TSTRING: return cJSON_CreateString(lua_tostring(L, i));
    case LUA_TBOOLEAN: return cJSON_CreateBool(lua_toboolean(L, i));
    case LUA_TTABLE: break;
    default: lua_pushfstring(L, "%s: a %s cannot be kept", who, luaL_typename(L, i)); return NULL;
    }
    if (depth > STORE_MAX_DEPTH || !lua_checkstack(L, 4)) {
        lua_pushfstring(L, "%s: tables nested too deep (or one inside itself)", who);
        return NULL;
    }
    i = lua_absindex(L, i);
    lua_Integer n = (lua_Integer)lua_rawlen(L, i), keys = 0;
    lua_pushnil(L);
    while (lua_next(L, i)) keys++, lua_pop(L, 1);
    bool list = keys == n; /* keys 1..n and nothing else */
    cJSON *t = list ? cJSON_CreateArray() : cJSON_CreateObject();
    if (list)
        for (lua_Integer k = 1; k <= n; k++) {
            lua_rawgeti(L, i, k);
            cJSON *v = json_from_lua(L, -1, depth + 1, who, count);
            if (!v) return cJSON_Delete(t), lua_remove(L, -2), NULL; /* keep the message, drop the element */
            lua_pop(L, 1);
            cJSON_AddItemToArray(t, v);
        }
    else {
        lua_pushnil(L);
        while (lua_next(L, i)) {
            if (lua_type(L, -2) != LUA_TSTRING) {
                lua_pop(L, 2);
                cJSON_Delete(t);
                lua_pushfstring(L, "%s: a table's keys must be strings, or it must be a list", who);
                return NULL;
            }
            cJSON *v = json_from_lua(L, -1, depth + 1, who, count);
            if (!v) return cJSON_Delete(t), lua_remove(L, -2), lua_remove(L, -2), NULL;
            cJSON_AddItemToObject(t, lua_tostring(L, -2), v);
            lua_pop(L, 1);
        }
    }
    return t;
}

void json_to_lua(lua_State *L, const cJSON *v, int depth) { /* the value pushed; nil past STORE_MAX_DEPTH */
    if (depth > STORE_MAX_DEPTH || !lua_checkstack(L, 3)) lua_pushnil(L);
    else if (cJSON_IsNumber(v)) {
        double d = v->valuedouble;
        if (d == floor(d) && d >= -2147483648.0 && d < 2147483648.0) lua_pushinteger(L, (lua_Integer)d);
        else lua_pushnumber(L, (lua_Number)d);
    } else if (cJSON_IsString(v)) lua_pushstring(L, v->valuestring);
    else if (cJSON_IsBool(v)) lua_pushboolean(L, cJSON_IsTrue(v));
    else if (cJSON_IsArray(v) || cJSON_IsObject(v)) {
        lua_newtable(L);
        int k = 1;
        for (const cJSON *e = v->child; e; e = e->next) {
            json_to_lua(L, e, depth + 1);
            if (cJSON_IsArray(v)) lua_rawseti(L, -2, k++);
            else lua_setfield(L, -2, e->string ? e->string : "");
        }
    } else lua_pushnil(L);
}

static int l_store(lua_State *L) {
    const char *k = luaL_checkstring(L, 1);
    cJSON *s = store_get(), *v = NULL;
    int count = 0;
    if (lua_isnoneornil(L, 2)) cJSON_DeleteItemFromObjectCaseSensitive(s, k);
    else if (!(v = json_from_lua(L, 2, 0, "store", &count))) return lua_error(L);
    char *txt = NULL;
    if (v) {
        cJSON *old = cJSON_DetachItemFromObjectCaseSensitive(s, k);
        cJSON_AddItemToObject(s, k, v);
        txt = cJSON_PrintUnformatted(s);
        if (txt && strlen(txt) > STORE_MAX_BYTES) { /* too big: put back what was there */
            cJSON_DeleteItemFromObjectCaseSensitive(s, k);
            if (old) cJSON_AddItemToObject(s, k, old);
            cJSON_free(txt);
            return luaL_error(L, "store: the saves would pass %d KB", STORE_MAX_BYTES / 1024);
        }
        cJSON_Delete(old);
    } else txt = cJSON_PrintUnformatted(s);
    bool ok = txt && store_write(txt);
    cJSON_free(txt);
    if (!ok) return luaL_error(L, "store: the saves could not be written (card full or read-only?)");
    return 0;
}

static int l_stored(lua_State *L) {
    cJSON *v = jget(store_get(), luaL_checkstring(L, 1));
    if (v) json_to_lua(L, v, 0);
    else lua_pushvalue(L, 2); /* the default */
    return 1;
}

/* ------------------------------------------------------------------ the careta (splash.c, docs/lua.md) */

/* powered_by(x, y) -> w, h: in the game's careta, where the seal "POWERED BY PINYOL" goes this frame (its top-left
 * corner; kept whole on the screen). The engine draws it over everything, wherever it is put. Its size either way. */
static int l_powered_by(lua_State *L) {
    int w = 0, h = 0;
    splash_seal_size(&w, &h);
    if (!lua_isnoneornil(L, 1)) {
        lua_Number x = luaL_checknumber(L, 1), y = luaL_checknumber(L, 2);
        x = x < -SCREEN_W ? -SCREEN_W : x > SCREEN_W ? SCREEN_W : x; /* (whole on the screen anyway: splash.c) */
        y = y < -SCREEN_H ? -SCREEN_H : y > SCREEN_H ? SCREEN_H : y;
        if (splash_own()) splash_place((int)x, (int)y);
    }
    lua_pushinteger(L, w), lua_pushinteger(L, h);
    return 2;
}

static void own_splash_failed(const char *why) { /* the engine's careta instead, and the game's let go */
    hal_log("lua careta: %s (the engine's careta instead)", why ? why : "error");
    if (splash_ref != LUA_NOREF) luaL_unref(Ls, LUA_REGISTRYINDEX, splash_ref);
    splash_ref = LUA_NOREF;
    ppu_reset();
    splash_own_failed();
}

/* The careta's update(t) or draw(t); *done: what update said. False if it failed (the engine's careta from now on). */
static bool splash_call(const char *fn, int t, bool *done) {
    lua_pushcfunction(Ls, msgh);
    lua_rawgeti(Ls, LUA_REGISTRYINDEX, splash_ref);
    lua_getfield(Ls, -1, fn);
    lua_remove(Ls, -2);
    if (!lua_isfunction(Ls, -1)) { /* none: it draws nothing, or it is done as soon as it may be */
        lua_pop(Ls, 2);
        if (done) *done = true;
        return true;
    }
    lua_pushinteger(Ls, t);
    arm();
    int rc = lua_pcall(Ls, 1, 1, -3);
    draw_flush();
    if (rc != LUA_OK) {
        char why[256];
        snprintf(why, sizeof why, "%s: %s", fn, lua_tostring(Ls, -1));
        lua_pop(Ls, 2);
        own_splash_failed(why);
        return false;
    }
    if (done) *done = lua_toboolean(Ls, -1);
    lua_pop(Ls, 2);
    return true;
}

/* game.json "splash", or splash.lua when the game has one: read and compiled always (a mistake in it fails
 * --validate), run only when the careta plays. Its table becomes the careta; an error running it, the engine's. */
static bool splash_load(void) {
    const char *file = jstr(G.game, "splash") ? jstr(G.game, "splash") : "splash.lua";
    if (!safe_name(file)) return fail("start", "game.json \"splash\" is not a file name in the game folder"), false;
    char path[384];
    snprintf(path, sizeof path, "%s/%s", G.game_dir, file);
    FILE *f = jstr(G.game, "splash") ? NULL : fopen(path, "rb"); /* (game_has may say yes when it is not sure) */
    if (!jstr(G.game, "splash") && !f) return true; /* none: the engine's */
    if (f) fclose(f);
    long len = 0;
    char *src = read_file(path, &len);
    if (!src) return fail(file, "cannot read it"), false;
    char name[96];
    snprintf(name, sizeof name, "@%s", file);
    int rc = luaL_loadbufferx(Ls, src, (size_t)len, name, "t");
    free(src);
    if (rc != LUA_OK) {
        fail(file, lua_tostring(Ls, -1));
        lua_settop(Ls, 0);
        return false;
    }
    if (!splash_on()) return lua_settop(Ls, 0), true;
    lua_pushcfunction(Ls, msgh);
    lua_insert(Ls, -2);
    arm();
    rc = lua_pcall(Ls, 0, 1, 1);
    if (rc != LUA_OK) hal_log("lua careta: %s (the engine's careta instead)", lua_tostring(Ls, -1));
    else if (!lua_istable(Ls, -1)) hal_log("lua careta: %s gives no table {update, draw} (the engine's careta instead)", file);
    else {
        lua_pushvalue(Ls, -1);
        splash_ref = luaL_ref(Ls, LUA_REGISTRYINDEX);
        splash_own_begin();
    }
    lua_settop(Ls, 0);
    return true;
}

bool v2_splash_update(int t) {
    if (!Ls || splash_ref == LUA_NOREF) return true;
    clip_tick(); /* (a careta may be a film: clips on canvases) */
    input_state keep = G.in; /* no button reaches it: it cannot be skipped */
    memset(&G.in, 0, sizeof G.in);
    bool done = false;
    splash_call("update", t, &done);
    G.in = keep;
    return done;
}

void v2_splash_end(void) {
    if (!Ls) return;
    if (splash_ref != LUA_NOREF) { /* the game's careta used the PPU: the game starts with it as new */
        luaL_unref(Ls, LUA_REGISTRYINDEX, splash_ref);
        splash_ref = LUA_NOREF;
        ppu_reset();
    }
    call("_init", 0);
}

static void api(lua_State *L) {
    static const luaL_Reg F[] = {
        {"clock", l_clock}, {"btn", l_btn}, {"btnp", l_btnp}, {"btnr", l_btnr}, {"btnt", l_btnt}, {"btnb", l_btnb}, {"touch", l_touch}, {"pen", l_pen}, {"touches", l_touches}, {"screen", l_screen}, {"t", l_t}, {"ticks", l_ticks}, {"rgb", l_rgb},
        {"pal", l_pal}, {"palette", l_palette}, {"backdrop", l_backdrop}, {"bg", l_bg}, {"scroll", l_scroll},
        {"affine", l_affine}, {"rot", l_rot}, {"mode7", l_mode7}, {"project", l_project}, {"mget", l_mget},
        {"mset", l_mset}, {"mapsize", l_mapsize}, {"line_scroll", l_line_scroll}, {"line_affine", l_line_affine}, {"line_scroll_ramp", l_line_scroll_ramp}, {"palcycle", l_palcycle}, {"shock", l_shock}, {"haze", l_haze}, {"line_backdrop", l_line_backdrop}, {"line_pal", l_line_pal}, {"line_pal_obj", l_line_pal_obj}, {"line_ramp", l_line_ramp},
        {"line_window", l_line_window}, {"line_fx", l_line_fx}, {"line_off", l_line_off}, {"sheet", l_sheet}, {"spr", l_spr},
        {"spr_off", l_spr_off}, {"spr_clear", l_spr_clear}, {"prio", l_prio}, {"bank", l_bank}, {"spr_mat", l_spr_mat},
        {"mat", l_mat}, {"show", l_show}, {"blend", l_blend}, {"fade", l_fade}, {"fx_off", l_fx_off},
        {"window", l_window}, {"window_off", l_window_off}, {"window_out", l_window_out}, {"objwindow", l_objwindow},
        {"mosaic", l_mosaic}, {"noise", l_noise},
        {"quit", l_quit}, {"menuitem", l_menuitem}, {"settings", l_settings}, {"achieve", l_achieve}, {"achievements", l_achievements}, {"perf", l_perf}, {"store", l_store}, {"stored", l_stored}, {"load", l_load}, {"log", l_log},
        {"print", l_log}, {"require", l_require}, {"file", l_file}, {"powered_by", l_powered_by}, {NULL, NULL}};
    lua_pushglobaltable(L);
    luaL_setfuncs(L, F, 0);
    draw_register(L); /* text, shapes, pictures, canvases: lua_draw.c */
    swarm_register(L); /* many things moving the same way: lua_swarm.c */
    link_register(L); /* consoles playing together: lua_link.c */
    studio_register(L); /* the step sequencer in the audio thread: lua_studio.c */
    sound_register(L); /* sounds, music, notes: lua_sound.c */
    physics_register(L); /* bodies that turn, for lib/physics.lua: lua_physics.c */
    clip_register(L); /* video on canvases: lua_clip.c */
    device_register(L); /* the LED and the battery: lua_device.c */
    console_register(L); /* the console's games, for its menu: lua_console.c */
    grid_register(L);   /* a game's thinking on a grid: lua_grid.c */
    ray_register(L);    /* first person: lua_ray.c */
    const struct { const char *n; int v; } K[] = { /* (not static: SCREEN_W and SCREEN_H are the game's) */
        {"BG0", PPU_BG0}, {"BG1", PPU_BG1}, {"BG2", PPU_BG2}, {"BG3", PPU_BG3}, {"OBJ", PPU_OBJ}, {"BACK", PPU_BACK},
        {"FX", PPU_FX}, {"ALL", 0x3F}, {"FLIP_X", F_FLIPX}, {"FLIP_Y", F_FLIPY}, {"BLEND", F_BLEND},
        {"WINDOW", F_WINDOW}, {"DOUBLE", F_DOUBLE}, {"MOSAIC", F_MOSAIC}, {"SCREEN_W", screens == 2 ? WORLD_W : SCREEN_W}, {"SCREEN_H", screens == 2 ? WORLD_H : SCREEN_H},
        {"W", PPU_W}, {"H", PPU_H}};
    for (size_t i = 0; i < sizeof K / sizeof K[0]; i++) lua_pushinteger(L, K[i].v), lua_setfield(L, -2, K[i].n);
    lua_pop(L, 1);
}

/* ------------------------------------------------------------------ lifecycle */

void v2_free(void) {
    memset(&BT, 0, sizeof BT);
    clip_free_all();
    link_stop();
    mic_close();
    physics_free();
    grid_free();
    device_reset();
    if (Ls) lua_close(Ls);
    Ls = NULL;
    prof_new_state();
    prof_stop();
    post_free();
    splash_ref = LUA_NOREF;
    assets_free();
    free(parked), free(world2);
    parked = NULL, world2 = NULL, screens = 1, cur_screen = 0;
    hal_save_flush(); /* a save still on its way is written before the game goes */
    cJSON_Delete(store);
    store = NULL;
    draw_free();
    failed = false;
    error[0] = 0;
    mem_used = 0;
}

bool v2_load(void) {
    v2_free();
    ppu_reset();
    if (jint(G.game, "screens", 1) == 2) { /* two screens: the top is G.world, the bottom's picture and parked state are here */
        parked = calloc(2, sizeof *parked);
        world2 = calloc((size_t)WORLD_W * WORLD_H, sizeof *world2);
        if (!parked || !world2 || !ppu_select(1)) {
            fail("start", "no memory for two screens");
            return false;
        }
        ppu_select(0);
        screens = 2;
    }
    int kb = jint(G.game, "lua_memory_kb", MEM_QUOTA_KB);
    mem_quota = (size_t)(kb < 256 ? 256 : kb > MEM_MAX_KB ? MEM_MAX_KB : kb) * 1024;
    Ls = lua_newstate(alloc, NULL);
    if (!Ls) {
        fail("start", "no memory for Lua");
        return false;
    }
    /* Generational: a game that makes tables every frame (a list of sprites to sort) leaves young garbage, cheap to collect at once;
     * the incremental default let it pile up into cycles whose steps cost a whole scan on the console (examples/isla: 96 frames of
     * 32 ms a minute, 58 fps; generational, 7 in 40 s, 59.8 fps, the same memory). Out of memory, Lua still collects in full first. */
    lua_gc(Ls, LUA_GCGEN, 0, 0);
    pinyol_budget_over = over;
    static const luaL_Reg libs[] = {{LUA_GNAME, luaopen_base}, {LUA_COLIBNAME, luaopen_coroutine},
                                    {LUA_TABLIBNAME, luaopen_table}, {LUA_STRLIBNAME, luaopen_string},
                                    {LUA_MATHLIBNAME, luaopen_math}, {LUA_UTF8LIBNAME, luaopen_utf8}};
    for (size_t i = 0; i < sizeof libs / sizeof libs[0]; i++) {
        luaL_requiref(Ls, libs[i].name, libs[i].func, 1);
        lua_pop(Ls, 1);
    }
    static const char *const unsafe[] = {"dofile", "loadfile", NULL}; /* load is replaced by a source-only one (api) */
    for (int i = 0; unsafe[i]; i++) lua_pushnil(Ls), lua_setglobal(Ls, unsafe[i]);
    lua_getglobal(Ls, "string");
    lua_pushnil(Ls), lua_setfield(Ls, -2, "dump");
    lua_pop(Ls, 1);
    lua_newtable(Ls);
    lua_setfield(Ls, LUA_REGISTRYINDEX, "pinyol.loaded");
    api(Ls);
    lua_getglobal(Ls, "math"); /* the same random numbers on every run: tests and replays depend on it */
    lua_getfield(Ls, -1, "randomseed");
    lua_pushinteger(Ls, 1);
    lua_call(Ls, 1, 0);
    lua_pop(Ls, 1);

    menu_read = false;
    sysmenu_reset();
    post_reset();
    for (int k = 0; k < CYCLES; k++) cycles[k].on = false;
    const char *entry = jstr(G.game, "main") ? jstr(G.game, "main") : "main.lua";
    if (!safe_name(entry)) {
        fail("start", "game.json \"main\" is not a file name in the game folder");
        return false;
    }
    lua_pushcfunction(Ls, msgh);
    arm();
    int rc;
    {
        char path[384];
        snprintf(path, sizeof path, "%s/%s", G.game_dir, entry);
        long len = 0;
        char *src = read_file(path, &len);
        if (!src) {
            fail(entry, "cannot read it");
            return false;
        }
        char name[96];
        snprintf(name, sizeof name, "@%s", entry);
        rc = luaL_loadbufferx(Ls, src, (size_t)len, name, "t");
        free(src);
    }
    if (rc == LUA_OK) rc = lua_pcall(Ls, 0, 0, -2);
    if (rc != LUA_OK) {
        fail(entry, lua_tostring(Ls, -1));
        lua_settop(Ls, 0);
        return false;
    }
    lua_settop(Ls, 0);
    if (!splash_load()) return false;
    if (splash_on()) return true; /* _init after the careta (v2_splash_end) */
    return call("_init", 0);
}

void v2_tick(void) {
    if (G.in.held & ACT_QUIT) G.quit = true;
    if ((G.in.held & ACT_INV) && (G.in.pressed & ACT_NEXT)) meter.on = !meter.on; /* MENU and C: the meter */
    /* (MENU held 2 s, back to the list, and a tap of it, the console's menu: sysmenu_tick, before this) */
    link_tick((uint32_t)G.ticks); /* what other consoles sent, before the game looks */
    mic_tick();                   /* and what the microphone heard */
    buttons_tick();               /* each button's story */
    clip_tick();                  /* the clips playing move on a frame */
    uint32_t t = hal_micros();
    call("_update", 0);
    us_update = hal_micros() - t;
    acc.update += us_update, acc.ticks++;
}

void v2_draw_world(void) {
    meter_frame();
    draw_frame_begin();
    uint32_t t = hal_micros();
    if (splash_own()) splash_frame_begin(), splash_call("draw", splash_ticks(), NULL); /* the game's careta */
    else {
        if (screens == 2) screen_view(0); /* _draw starts on the top screen */
        call("_draw", 0);
    }
    uint32_t u = hal_micros();
    if (screens == 2) { /* each screen's processor draws its own picture (parked state brought back first) */
        for (int k = 0; k < 2; k++) {
            screen_select(k);
            ppu_render(k ? world2 : G.world);
        }
        screen_select(0);
    } else if (!(blank = ppu_blank(&backdrop))) ppu_render(G.world); /* nothing of the world shown: one colour, not worked out */
    if (post_any()) { /* shock(), haze(): the picture bent after it is drawn */
        if (blank) ppu_render(G.world), blank = false; /* (one colour everywhere: nothing to bend, but the frame must exist) */
        post_apply(G.world, WORLD_W, WORLD_H);
    }
    if (conf_filter_on()) { /* the console's colour filter, on the world's pixels (the text and shapes over it stay) */
        if (blank) conf_filter(&backdrop, 1);
        else conf_filter(G.world, WORLD_W * WORLD_H);
        if (screens == 2) conf_filter(world2, WORLD_W * WORLD_H);
    }
    us_draw = u - t, us_ppu = hal_micros() - u;
    acc.draw += us_draw, acc.ppu += us_ppu, acc.frames++;
    if (us_ppu > acc.ppu_max) acc.ppu_max = us_ppu;
}

void v2_timing(v2_times *t) {
    *t = (v2_times){.update = acc.ticks ? (uint32_t)(acc.update / acc.ticks) : 0,
                    .draw = acc.frames ? (uint32_t)(acc.draw / acc.frames) : 0,
                    .ppu = acc.frames ? (uint32_t)(acc.ppu / acc.frames) : 0, .ppu_max = acc.ppu_max};
    memset(&acc, 0, sizeof acc);
}

void v2_draw(surface *s) {
    surface world = {.px = G.world, .w = WORLD_W, .h = WORLD_H};
    if (screens == 2) { /* the two pictures side by side, 1:1, in the middle rows; the text and shapes are cut to each */
        surface bottom = {.px = world2, .w = WORLD_W, .h = WORLD_H};
        gfx_fill(s, 0, 0, SCREEN_W, SCREEN_H, 0);
        gfx_copy1x(&world, s, DUAL_X(0), DUAL_Y);
        gfx_copy1x(&bottom, s, DUAL_X(1), DUAL_Y);
    } else if (draw_covers_screen()) {} /* a full-screen opaque picture comes first: no world */
    else if (blank) gfx_fill(s, 0, 0, SCREEN_W, SCREEN_H, backdrop); /* (the same pixels as the world doubled) */
    else gfx_upscale2x(&world, s);
    draw_profile(1u, meter.on); /* (the commands are timed only while the meter is up) */
    draw_overlay(s);
    if (meter.on) meter_draw(s);
    sysmenu_draw(s); /* the console's menu, or the crash screen with the whole error, over everything */
}

const char *v2_error(void) { return failed ? error : NULL; }

/* For test scripts: run code (or evaluate an expression when expr) in the game's state; true if it ran and, for an
 * expression, came out truthy. */
bool v2_run(const char *code, bool expr, char *msg, int n) {
    if (!Ls) return snprintf(msg, (size_t)n, "no Lua state"), false;
    char buf[512];
    snprintf(buf, sizeof buf, expr ? "return (%s)" : "%s", code);
    arm();
    bool ran = luaL_loadbufferx(Ls, buf, strlen(buf), "=script", "t") == LUA_OK && lua_pcall(Ls, 0, 1, 0) == LUA_OK;
    draw_flush();
    if (!ran) {
        snprintf(msg, (size_t)n, "%s", lua_tostring(Ls, -1));
        lua_settop(Ls, 0);
        return false;
    }
    bool ok = !expr || lua_toboolean(Ls, -1);
    if (!ok) snprintf(msg, (size_t)n, "%s is %s", code, luaL_tolstring(Ls, -1, NULL)), lua_pop(Ls, 1);
    lua_settop(Ls, 0);
    return ok;
}

size_t v2_memory(void) { return mem_used; }
