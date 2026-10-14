/* The console's own games, for the game that is the console's menu (firmware/cirera, a pinyol game itself):
 *
 *   console_games()             -> list, last, cold: {id, title, subtitle, flash, music} for each game; the index
 *                                  of the one played last (nil: none); true the first time since the console woke
 *   console_cover(id, canvas)   -> the game's cover (cover.rgb565, 240x160) on that canvas and its average colour
 *                                  0xRRGGBB, or nil when it has none
 *   console_launch(id)          the menu ends and that game starts
 *   console_off()               switches the console off
 *   console_version()           -> the firmware's version (its git description)
 *
 * The platform keeps the list (hal_games). On a desktop it is the folders in $PINYOL_GAMES (console_dir_*), so the
 * menu can be made in the simulator and tested headless. Any game may call these; only the menu has a reason to. */
#include <dirent.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>

#include "lua_api.h"

#define MAX_GAMES 64

static int l_console_games(lua_State *L) {
    static hal_game g[MAX_GAMES];
    int last = -1;
    bool cold = false;
    int n = hal_games(g, MAX_GAMES, &last, &cold);
    lua_createtable(L, n, 0);
    for (int i = 0; i < n; i++) {
        lua_createtable(L, 0, 5);
        lua_pushstring(L, g[i].id), lua_setfield(L, -2, "id");
        lua_pushstring(L, g[i].title), lua_setfield(L, -2, "title");
        lua_pushstring(L, g[i].subtitle), lua_setfield(L, -2, "subtitle");
        lua_pushboolean(L, g[i].flash), lua_setfield(L, -2, "flash");
        lua_pushboolean(L, !g[i].no_music), lua_setfield(L, -2, "music");
        lua_rawseti(L, -2, i + 1);
    }
    if (last >= 0 && last < n) lua_pushinteger(L, last + 1);
    else lua_pushnil(L);
    lua_pushboolean(L, cold);
    return 3;
}

static int l_console_cover(lua_State *L) {
    const char *id = luaL_checkstring(L, 1), *cid = luaL_checkstring(L, 2);
    asset *a = NULL;
    const char *why = gfx_canvas(cid, COVER_W, COVER_H, NULL, &a);
    if (why) return luaL_error(L, "console_cover: %s", why);
    if (!hal_game_cover(id, a->pixels, COVER_W, COVER_H)) return lua_pushnil(L), 1;
    unsigned r = 0, g = 0, b = 0;
    for (int i = 0; i < COVER_W * COVER_H; i++) {
        uint16_t v = a->pixels[i];
        if (v == CANVAS_KEY) a->pixels[i] = v ^ 1; /* a cover is opaque all over */
        r += v >> 11, g += (v >> 5) & 63, b += v & 31;
    }
    memset(a->mask, 0xFF, (size_t)((COVER_W + 7) / 8) * COVER_H);
    a->gen++;
    unsigned n = COVER_W * COVER_H;
    lua_pushinteger(L, (lua_Integer)((r / n * 255 / 31) << 16 | (g / n * 255 / 63) << 8 | (b / n * 255 / 31)));
    return 1;
}

static int l_console_launch(lua_State *L) {
    hal_launch(luaL_checkstring(L, 1));
    G.quit = true; /* the menu ends; the platform starts the game it was given */
    return 0;
}

static int l_console_off(lua_State *L) {
    (void)L;
    hal_power_off();
    return 0;
}

static int l_console_version(lua_State *L) {
    lua_pushstring(L, hal_firmware());
    return 1;
}

void console_register(lua_State *L) {
    lua_register(L, "console_games", l_console_games);
    lua_register(L, "console_cover", l_console_cover);
    lua_register(L, "console_launch", l_console_launch);
    lua_register(L, "console_off", l_console_off);
    lua_register(L, "console_version", l_console_version);
}

/* ------------------------------------------------------------------ the desktop's: folders in a directory */

static int by_id(const void *a, const void *b) { return strcmp(((const hal_game *)a)->id, ((const hal_game *)b)->id); }

int console_dir_games(const char *root, hal_game *g, int max) {
    DIR *d = root ? opendir(root) : NULL;
    if (!d) return 0;
    int n = 0;
    for (struct dirent *e; n < max && (e = readdir(d));) {
        if (e->d_name[0] == '.' || !strcmp(e->d_name, CONSOLE_MENU_ID)) continue;
        char path[512];
        snprintf(path, sizeof path, "%s/%s/game.json", root, e->d_name);
        FILE *f = fopen(path, "rb");
        if (!f) continue;
        char text[4096];
        size_t len = fread(text, 1, sizeof text - 1, f);
        fclose(f);
        text[len] = 0;
        cJSON *j = cJSON_Parse(text);
        if (!j) continue;
        hal_game *x = &g[n++];
        memset(x, 0, sizeof *x);
        snprintf(x->id, sizeof x->id, "%s", e->d_name);
        const char *t = jstr(j, "title"), *s = jstr(j, "subtitle");
        snprintf(x->title, sizeof x->title, "%s", t ? t : x->id);
        snprintf(x->subtitle, sizeof x->subtitle, "%s", s ? s : "");
        cJSON_Delete(j);
    }
    closedir(d);
    qsort(g, (size_t)n, sizeof *g, by_id);
    return n;
}

bool console_dir_cover(const char *dir, uint16_t *px, int w, int h) {
    static const char *const names[] = {"cover.rgb565", "assets/BG_TITLE.rgb565"}; /* an adventure's title: the same size */
    for (int k = 0; k < 2; k++) {
        char path[512];
        snprintf(path, sizeof path, "%s/%s", dir, names[k]);
        FILE *f = fopen(path, "rb");
        if (!f) continue;
        fseek(f, 0, SEEK_END);
        long size = ftell(f);
        fseek(f, 0, SEEK_SET);
        bool ok = size == (long)w * h * 2 && fread(px, 2, (size_t)w * h, f) == (size_t)w * h;
        fclose(f);
        if (ok) return true; /* (little endian, as both the console and desktops are) */
    }
    return false;
}
