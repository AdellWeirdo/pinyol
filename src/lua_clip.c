/* Video: clips played on a canvas, a frame at a time from the card (tools/clip2npv.py makes them, docs/lua.md
 * "Clips"). The canvas is drawn as any other: on a monitor of a TV studio, as a backdrop, turned, scaled.
 *
 *   local tv = video("noticias" [, {canvas = "TV", loop = true, speed = 1, play = true}])
 *   tv:play(); tv:pause(); tv:seek(frame); tv:frame(); tv:frames(); tv:fps(); tv:playing(); tv:close()
 *   tv.speed = 2 (or -1: backwards, a tape rewinding)
 *
 * A clip from a downloaded game is untrusted: every offset, run and colour index is checked against the file. */
#include <stdlib.h>

#include "lua_api.h"

#define MAX_CLIPS 8
#define CATCH_UP 4 /* frames decoded in one tick at most: a clip falls behind rather than freezing the game */

typedef struct {
    FILE *f;
    asset *canvas;
    int w, h, frames, key, ncol, shown; /* shown: the frame on the canvas (-1: none yet) */
    float fps, speed, at;               /* at: the frame it is at, with the fraction */
    bool playing, loop;
    uint16_t pal[256];
    uint32_t *index; /* frames + 1 offsets */
    uint8_t *buf;
    uint32_t buf_cap;
    char canvas_id[32];
} clip;

static clip *open_clips[MAX_CLIPS];

static uint32_t rd32(const uint8_t *p) { return p[0] | p[1] << 8 | p[2] << 16 | (uint32_t)p[3] << 24; }
static unsigned rd16(const uint8_t *p) { return p[0] | p[1] << 8; }

static void clip_close(clip *c) {
    if (c->f) fclose(c->f);
    free(c->index), free(c->buf);
    c->f = NULL, c->index = NULL, c->buf = NULL;
    for (int i = 0; i < MAX_CLIPS; i++)
        if (open_clips[i] == c) open_clips[i] = NULL;
}

/* Frame k's ops onto the canvas; false if the file cannot be read (a bad run only stops that frame). */
static bool decode(clip *c, int k) {
    uint32_t a = c->index[k], n = c->index[k + 1] - a;
    if (n && (fseek(c->f, (long)a, SEEK_SET) || fread_chunked(c->buf, n, c->f) != n)) return false; /* (PSRAM) */
    uint16_t *px = c->canvas->pixels;
    const uint8_t *p = c->buf, *end = c->buf + n;
    uint32_t i = 0, total = (uint32_t)c->w * c->h;
    while (p < end && i < total) {
        unsigned op = *p++;
        if (op < 0x80) {
            i += op + 1;
        } else if (op < 0xC0) {
            unsigned m = op - 0x7F;
            if ((uint32_t)(end - p) < m) break;
            for (unsigned j = 0; j < m && i < total; j++, i++) px[i] = c->pal[p[j] < c->ncol ? p[j] : 0];
            p += m;
        } else {
            if (p == end) break;
            unsigned m = op - 0xBF;
            uint16_t col = c->pal[*p < c->ncol ? *p : 0];
            p++;
            for (unsigned j = 0; j < m && i < total; j++) px[i++] = col;
        }
    }
    memset(c->canvas->mask, 0xFF, (size_t)((c->w + 7) / 8) * c->h); /* a clip covers its canvas */
    c->canvas->gen++;
    return true;
}

/* Brings the canvas to frame k: from the keyframe before it unless k follows the one shown. */
static void show_frame(clip *c, int k) {
    if (k == c->shown) return;
    int from = k == c->shown + 1 ? k : k - k % c->key;
    for (int j = from; j <= k; j++)
        if (!decode(c, j)) {
            hal_log("video %s: cannot read frame %d", c->canvas_id, j);
            c->playing = false;
            return;
        }
    c->shown = k;
}

void clip_tick(void) { /* each tick: the clips playing move on by their speed */
    for (int i = 0; i < MAX_CLIPS; i++) {
        clip *c = open_clips[i];
        if (!c || !c->playing) continue;
        float step = c->speed * c->fps / TICK_HZ, at = c->at + step;
        if (at >= c->frames || at < 0) {
            if (!c->loop) {
                at = at < 0 ? 0 : (float)c->frames - 1;
                c->playing = false;
            } else {
                at = fmodf(at, (float)c->frames);
                if (at < 0) at += (float)c->frames;
            }
        }
        c->at = at;
        int k = (int)at;
        if (k > c->shown && k - c->shown > CATCH_UP && k - k % c->key <= c->shown) /* far behind: fewer frames */
            c->at = (float)(k = c->shown + CATCH_UP);
        show_frame(c, k);
    }
}

void clip_free_all(void) {
    for (int i = 0; i < MAX_CLIPS; i++)
        if (open_clips[i]) clip_close(open_clips[i]);
}

static clip *check(lua_State *L) {
    clip *c = luaL_checkudata(L, 1, "pinyol.clip");
    if (!c->f) luaL_error(L, "the clip is closed");
    return c;
}

static const char *read_header(clip *c, long size) {
    uint8_t h[20];
    if (fread(h, 1, 20, c->f) != 20 || memcmp(h, "NPV1", 4)) return "not a clip (tools/clip2npv.py makes them)";
    c->w = (int)rd16(h + 4), c->h = (int)rd16(h + 6), c->fps = (float)rd16(h + 8) / 100;
    c->ncol = (int)rd16(h + 10);
    uint32_t frames = rd32(h + 12), key = rd32(h + 16);
    if (c->w < 1 || c->h < 1 || c->w > 1024 || c->h > 1024) return "its size is not 1 to 1024 pixels a side";
    if (c->ncol < 1 || c->ncol > 256 || frames < 1 || frames > 1000000 || key < 1 || !(c->fps >= 1 && c->fps <= 120))
        return "its numbers make no sense";
    c->frames = (int)frames, c->key = (int)key;
    uint8_t pal[512];
    if (fread(pal, 2, (size_t)c->ncol, c->f) != (size_t)c->ncol) return "it is cut short";
    for (int i = 0; i < c->ncol; i++) {
        uint16_t v = (uint16_t)rd16(pal + 2 * i);
        c->pal[i] = v == CANVAS_KEY ? v ^ 1 : v;
    }
    size_t bytes = ((size_t)frames + 1) * 4;
    uint8_t *raw = hal_realloc_slow(NULL, bytes);
    if (!raw) return "no memory for it";
    if (fread_chunked(raw, bytes, c->f) != bytes) return free(raw), "it is cut short";
    c->index = (uint32_t *)raw; /* in place: each offset read once, little-endian */
    uint32_t most = 0, limit = (uint32_t)c->w * c->h * 2 + 1024, first = 20 + 2 * (uint32_t)c->ncol + (uint32_t)bytes;
    for (uint32_t i = 0; i <= frames; i++) {
        uint32_t v = rd32(raw + 4 * i);
        c->index[i] = v;
        if (v < first || v > (uint32_t)size || (i && v < c->index[i - 1])) return "its frames are not where it says";
        if (i && v - c->index[i - 1] > most) most = v - c->index[i - 1];
    }
    if (most > limit) return "a frame is bigger than any frame of its size";
    c->buf_cap = most ? most : 1;
    if (!(c->buf = hal_realloc_slow(NULL, c->buf_cap))) return "no memory for it";
    return NULL;
}

/* video(id [, {canvas, loop, speed, play}]) -> a clip playing video/<id>.npv on the canvas (id, or canvas) */
static int l_clip(lua_State *L) {
    const char *id = luaL_checkstring(L, 1);
    if (!safe_name(id) || strchr(id, '/') || strlen(id) >= 32) return luaL_error(L, "video \"%s\": not a clip name", id);
    const char *cid = id;
    bool loop = false, play = true;
    float speed = 1;
    if (!lua_isnoneornil(L, 2)) {
        luaL_checktype(L, 2, LUA_TTABLE);
        const char *k = opt_str(L, 2, "canvas");
        if (k) cid = k;
        loop = opt_bool(L, 2, "loop", false), play = opt_bool(L, 2, "play", true);
        speed = opt_float(L, 2, "speed", 1, -16, 16);
    }
    if (!safe_name(cid) || strchr(cid, '/') || strlen(cid) >= 32) return luaL_error(L, "video \"%s\": not a canvas name", cid);
    int slot = 0;
    while (slot < MAX_CLIPS && open_clips[slot]) slot++;
    if (slot == MAX_CLIPS) return luaL_error(L, "video \"%s\": %d clips open at most (close one)", id, MAX_CLIPS);
    clip *c = lua_newuserdatauv(L, sizeof(clip), 0);
    memset(c, 0, sizeof *c);
    luaL_setmetatable(L, "pinyol.clip");
    char path[384];
    snprintf(path, sizeof path, "%s/video/%s.npv", G.game_dir, id);
    if (!(c->f = fopen(path, "rb"))) return luaL_error(L, "video \"%s\": no video/%s.npv", id, id);
    fseek(c->f, 0, SEEK_END);
    long size = ftell(c->f);
    fseek(c->f, 0, SEEK_SET);
    const char *why = read_header(c, size);
    if (!why) why = gfx_canvas(cid, c->w, c->h, NULL, &c->canvas);
    if (why) {
        clip_close(c);
        return luaL_error(L, "video \"%s\": %s", id, why);
    }
    snprintf(c->canvas_id, sizeof c->canvas_id, "%s", cid);
    c->shown = -1, c->loop = loop, c->playing = play, c->speed = speed;
    open_clips[slot] = c;
    show_frame(c, 0);
    return 1;
}

static int m_play(lua_State *L) { check(L)->playing = true; return 0; }
static int m_pause(lua_State *L) { check(L)->playing = false; return 0; }
static int m_seek(lua_State *L) {
    clip *c = check(L);
    int k = num(L, 2);
    k = k < 0 ? 0 : k >= c->frames ? c->frames - 1 : k;
    c->at = (float)k;
    show_frame(c, k);
    return 0;
}
static int m_frame(lua_State *L) { lua_pushinteger(L, check(L)->shown); return 1; }
static int m_frames(lua_State *L) { lua_pushinteger(L, check(L)->frames); return 1; }
static int m_fps(lua_State *L) { lua_pushnumber(L, check(L)->fps); return 1; }
static int m_playing(lua_State *L) { lua_pushboolean(L, check(L)->playing); return 1; }
static int m_close(lua_State *L) {
    clip *c = luaL_checkudata(L, 1, "pinyol.clip");
    if (c->f) clip_close(c);
    return 0;
}

static int m_index(lua_State *L) { /* methods, and the speed */
    const char *k = luaL_checkstring(L, 2);
    if (!strcmp(k, "speed")) return lua_pushnumber(L, check(L)->speed), 1;
    luaL_getmetafield(L, 1, "methods");
    lua_getfield(L, -1, k);
    return 1;
}

static int m_newindex(lua_State *L) {
    clip *c = check(L);
    if (strcmp(luaL_checkstring(L, 2), "speed")) return luaL_error(L, "a clip has no field '%s' to set", lua_tostring(L, 2));
    float s = fin(luaL_checknumber(L, 3));
    c->speed = s < -16 ? -16 : s > 16 ? 16 : s;
    return 0;
}

void clip_register(lua_State *L) {
    static const luaL_Reg M[] = {{"play", m_play}, {"pause", m_pause}, {"seek", m_seek}, {"frame", m_frame},
                                 {"frames", m_frames}, {"fps", m_fps}, {"playing", m_playing}, {"close", m_close},
                                 {NULL, NULL}};
    luaL_newmetatable(L, "pinyol.clip");
    luaL_newlib(L, M);
    lua_setfield(L, -2, "methods");
    lua_pushcfunction(L, m_index), lua_setfield(L, -2, "__index");
    lua_pushcfunction(L, m_newindex), lua_setfield(L, -2, "__newindex");
    lua_pushcfunction(L, m_close), lua_setfield(L, -2, "__gc");
    lua_pop(L, 1);
    lua_register(L, "video", l_clip);
}
