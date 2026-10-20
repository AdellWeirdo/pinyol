/* pinyol as a libretro core: the same engine inside RetroArch, and so inside RetroPie, Batocera, Recalbox, Lakka...
 * (docs/libretro.md). Content is a game's folder, its game.json, or its .zip / .pinyol (tools/pack_game.py, the
 * Library), which is unpacked into the frontend's save folder as <saves>/pinyol/<name>/game; the game's own saves
 * go next to it, in <saves>/pinyol/<name>/saves.
 * The pad: d-pad, A = A, B = B, X or Y = C, START = START, SELECT = MENU; a touch screen or a mouse = touch. */
#include <errno.h>
#include <fcntl.h>
#include <stdarg.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <sys/stat.h>
#include <time.h>
#include <unistd.h>

#include "bp.h"
#include "libretro.h"
#include "puff.h"
#include "../link_udp.h"

#ifndef PINYOL_VERSION
#define PINYOL_VERSION "dev"
#endif

static retro_environment_t env_cb;
static retro_video_refresh_t video_cb;
static retro_audio_sample_batch_t audio_cb;
static retro_input_poll_t poll_cb;
static retro_input_state_t input_cb;
static retro_log_printf_t log_cb;

static uint16_t fb[SCREEN_W * SCREEN_H];
static char game_dir[512], save_dir[512];
static bp_config cfg; /* points at game_dir, save_dir: game_init keeps the pointers */
static uint64_t frames;

/* ------------------------------------------------------------------ the platform */
void hal_log(const char *fmt, ...) {
    char line[512];
    va_list ap;
    va_start(ap, fmt);
    vsnprintf(line, sizeof line, fmt, ap);
    va_end(ap);
    if (log_cb) log_cb(RETRO_LOG_INFO, "[pinyol] %s\n", line);
    else fprintf(stderr, "%s\n", line);
}

void hal_audio_lock(void) {} /* retro_run mixes on the frontend's thread: nothing runs beside it */
void hal_audio_unlock(void) {}
/* ponytail: RetroArch's default audio latency (64 ms); a frontend set otherwise is tuned in the game (music_time) */
int hal_audio_latency(void) { return AUDIO_HZ * 64 / 1000; }
void *hal_realloc_slow(void *p, size_t n) { return realloc(p, n); }
void hal_parallel(void (*fn)(int part, void *ctx), void *ctx) { fn(0, ctx), fn(1, ctx); }
uint32_t hal_micros(void) {
    struct timespec t;
    clock_gettime(CLOCK_MONOTONIC, &t);
    return (uint32_t)(t.tv_sec * 1000000 + t.tv_nsec / 1000);
}

bool hal_can_switch_game(void) { return false; } /* the frontend has the game list */
void hal_switch_game(void) {}
int hal_games(hal_game *g, int max, int *last, bool *cold) { return (void)g, (void)max, *last = -1, *cold = false, 0; }
bool hal_game_cover(const char *id, uint16_t *px, int w, int h) { return (void)id, (void)px, (void)w, (void)h, false; }
void hal_launch(const char *id) { (void)id; }
void hal_power_off(void) {}
const char *hal_firmware(void) { return "libretro"; }

/* The link: UDP multicast on the local network, as the desktop simulator (two Raspberry Pis can play together) */
bool hal_link_open(void) { return link_udp_open(); }
void hal_link_close(void) { link_udp_close(); }
bool hal_link_send(const uint8_t *p, int n) { return link_udp_send(p, n); }
int hal_link_recv(uint8_t *p, int max) { return link_udp_recv(p, max); }
uint32_t hal_link_id(void) { return link_udp_id(); }

bool hal_mic_open(void) { return false; } /* ponytail: libretro's microphone interface is new; add when asked */
void hal_mic_close(void) {}
int hal_mic_read(int16_t *p, int max) { return (void)p, (void)max, 0; }
void hal_led(int rgb) { (void)rgb; }
bool hal_battery(float *level, bool *charging) { return (void)level, (void)charging, false; }

/* ------------------------------------------------------------------ the game's zip */
#define ZIP_MAX (128u << 20) /* a game bigger than this (packed or unpacked) is refused: both can be in memory at once */

static uint32_t le16(const uint8_t *p) { return p[0] | p[1] << 8; }
static uint32_t le32(const uint8_t *p) { return p[0] | p[1] << 8 | p[2] << 16 | (uint32_t)p[3] << 24; }

static bool mkdirs(char *path) { /* every folder of path, as mkdir -p */
    for (char *s = path + 1; *s; s++) {
        if (*s != '/') continue;
        *s = 0;
        bool ok = mkdir(path, 0755) == 0 || errno == EEXIST;
        *s = '/';
        if (!ok) return false;
    }
    return mkdir(path, 0755) == 0 || errno == EEXIST;
}

/* A name from the zip that stays inside the folder it is unpacked into: relative, no "..", no backslash or colon */
static bool safe_name(const char *n, size_t len) {
    if (!len || n[0] == '/') return false;
    for (size_t i = 0; i < len; i++) {
        if (n[i] == '\\' || n[i] == ':' || !n[i]) return false;
        bool start = i == 0 || n[i - 1] == '/';
        if (start && n[i] == '.' && (i + 1 == len || n[i + 1] == '/' ||
                                     (n[i + 1] == '.' && (i + 2 == len || n[i + 2] == '/'))))
            return false;
    }
    return true;
}

static uint8_t *read_all(const char *path, size_t *n) {
    FILE *f = fopen(path, "rb");
    if (!f) return NULL;
    uint8_t *d = NULL;
    long len = fseek(f, 0, SEEK_END) ? -1 : ftell(f);
    if (len > 0 && (unsigned long)len <= ZIP_MAX && !fseek(f, 0, SEEK_SET) && (d = malloc((size_t)len)) &&
        fread(d, 1, (size_t)len, f) != (size_t)len)
        free(d), d = NULL;
    fclose(f);
    *n = d ? (size_t)len : 0;
    return d;
}

typedef struct { /* one file of the zip, from its central directory */
    const char *name;
    uint32_t len, method, crc, csize, usize, local;
} zip_entry;

static bool zip_entry_at(const uint8_t *z, size_t n, size_t *at, zip_entry *e) {
    size_t p = *at;
    if (p > n || n - p < 46 || le32(z + p) != 0x02014b50) return false; /* (n - p: no wrap with a 32-bit size_t) */
    e->method = le16(z + p + 10), e->crc = le32(z + p + 16), e->csize = le32(z + p + 20), e->usize = le32(z + p + 24);
    e->len = le16(z + p + 28), e->local = le32(z + p + 42), e->name = (const char *)z + p + 46;
    *at = p + 46 + e->len + le16(z + p + 30) + le16(z + p + 32);
    return *at <= n && !(le16(z + p + 8) & 1); /* (bit 0: encrypted) */
}

static bool unpack(const uint8_t *z, size_t n, const zip_entry *e, const char *dest) {
    size_t p = e->local;
    if (p > n || n - p < 30 || le32(z + p) != 0x04034b50) return false;
    p += 30 + le16(z + p + 26) + le16(z + p + 28);
    if (p > n || e->csize > n - p || e->usize > ZIP_MAX) return false;
    uint8_t *out = malloc(e->usize ? e->usize : 1);
    if (!out) return hal_log("%s: out of memory", dest), false;
    unsigned long ulen = e->usize, clen = e->csize;
    bool ok = e->method == 0 ? (e->csize == e->usize && (memcpy(out, z + p, e->usize), true))
            : e->method == 8 && puff(out, &ulen, z + p, &clen) == 0 && ulen == e->usize;
    ok = ok && crc32_buf(out, e->usize) == e->crc;
    int fd = ok ? open(dest, O_WRONLY | O_CREAT | O_TRUNC | O_NOFOLLOW, 0644) : -1; /* never through a link */
    FILE *f = fd >= 0 ? fdopen(fd, "wb") : NULL;
    if (fd >= 0 && !f) close(fd);
    ok = f && fwrite(out, 1, e->usize, f) == e->usize;
    if (f && fclose(f)) ok = false;
    free(out);
    return ok;
}

static bool game_name(const char *name, const char *root) { /* a name for <root>/pinyol/<name>/game: game_dir */
    return safe_name(name, strlen(name)) && !strchr(name, '/') &&
           snprintf(game_dir, sizeof game_dir, "%s/pinyol/%s/game", root, name) < 256;
}

/* The zip holds a game: game.json at its top or in one folder (pack_game.py: <id>/game.json). Its name is that
 * folder's, or the zip's; everything beside game.json goes into <root>/pinyol/<name>/game, and game_dir says where.
 * <root>/pinyol/<zip's file name>.unpacked keeps the zip's size and time then, and the name: while they are the
 * same and the game is there, the zip is not even read (a big game takes seconds to unpack on a Raspberry Pi).
 * ponytail: a new version is unpacked over the old one, so files it no longer has stay; harmless, as a game only
 * reads what it names */
static bool unzip_game(const char *zip, const char *root, char *name, size_t name_max) {
    struct stat st;
    const char *base = strrchr(zip, '/') ? strrchr(zip, '/') + 1 : zip;
    char stamp[640], mark[64] = "", line[64], json[640];
    snprintf(stamp, sizeof stamp, "%s/pinyol/%s.unpacked", root, base);
    if (!stat(zip, &st)) snprintf(mark, sizeof mark, "%lld %lld\n", (long long)st.st_size, (long long)st.st_mtime);
    FILE *f = *mark ? fopen(stamp, "r") : NULL;
    if (f) {
        bool same = fgets(line, sizeof line, f) && !strcmp(line, mark) && fgets(name, (int)name_max, f);
        fclose(f);
        if (same) name[strcspn(name, "\n")] = 0;
        if (same && game_name(name, root) && snprintf(json, sizeof json, "%s/game.json", game_dir) < (int)sizeof json &&
            !stat(json, &st))
            return true;
    }
    remove(stamp);
    size_t n;
    uint8_t *z = read_all(zip, &n);
    if (!z) return hal_log("%s: unreadable, or bigger than %u MB", zip, ZIP_MAX >> 20), false;
    bool ok = false;
    size_t eocd = n >= 22 ? n - 22 : 0, stop = n > 22 + 65535 ? n - 22 - 65535 : 0;
    while (n >= 22 && eocd > stop && le32(z + eocd) != 0x06054b50) eocd--;
    if (n < 22 || le32(z + eocd) != 0x06054b50) {
        hal_log("%s: not a zip", zip);
        goto done;
    }
    size_t cd = le32(z + eocd + 16), count = le16(z + eocd + 10);
    zip_entry e;
    const char *top = NULL;
    size_t top_len = 0, at = cd;
    for (size_t i = 0; i < count; i++) { /* where game.json is */
        if (!zip_entry_at(z, n, &at, &e)) goto bad;
        const char *slash = memchr(e.name, '/', e.len);
        size_t dir = slash ? (size_t)(slash - e.name) + 1 : 0;
        if (e.len - dir == 9 && !memcmp(e.name + dir, "game.json", 9) && (!top || dir < top_len))
            top = e.name, top_len = dir;
    }
    if (!top) {
        hal_log("%s: no game.json in it", zip);
        goto done;
    }
    if (top_len) snprintf(name, name_max, "%.*s", (int)top_len - 1, top);
    else {
        const char *b = strrchr(zip, '/');
        char *dot;
        snprintf(name, name_max, "%s", b ? b + 1 : zip);
        if ((dot = strrchr(name, '.'))) *dot = 0;
    }
    if (!game_name(name, root)) goto bad;
    if (!mkdirs(game_dir)) {
        hal_log("%s: cannot make it", game_dir);
        goto done;
    }
    uint64_t total = 0;
    at = cd;
    for (size_t i = 0; i < count; i++) {
        if (!zip_entry_at(z, n, &at, &e)) goto bad;
        if (e.len < top_len || memcmp(e.name, top, top_len) || e.len == top_len) continue; /* not the game's */
        const char *rel = e.name + top_len;
        size_t len = e.len - top_len;
        if (!safe_name(rel, len)) goto bad;
        if ((total += e.usize) > ZIP_MAX) goto bad;
        char path[768];
        if (snprintf(path, sizeof path, "%s/%.*s", game_dir, (int)len, rel) >= (int)sizeof path) goto bad;
        if (rel[len - 1] == '/') { /* a folder */
            path[strlen(path) - 1] = 0;
            if (!mkdirs(path)) goto bad;
            continue;
        }
        char *slash = strrchr(path, '/');
        *slash = 0;
        bool made = mkdirs(path);
        *slash = '/';
        if (!made || !unpack(z, n, &e, path)) goto bad;
    }
    ok = true;
    if (*mark && (f = fopen(stamp, "w"))) fprintf(f, "%s%s\n", mark, name), fclose(f);
    goto done;
bad:
    hal_log("%s: damaged, holds a file that would land outside its folder, or unpacks to too long a path", zip);
done:
    free(z);
    return ok;
}

/* ------------------------------------------------------------------ the content */
static bool is_dir(const char *p) {
    struct stat st;
    return !stat(p, &st) && S_ISDIR(st.st_mode);
}

static bool open_content(const char *path) {
    const char *saves = NULL;
    if (!env_cb(RETRO_ENVIRONMENT_GET_SAVE_DIRECTORY, &saves) || !saves || !*saves) saves = NULL;
    size_t len = strlen(path);
    char root[512], name[128], dir[640];
    bool json = len >= 9 && !strcmp(path + len - 9, "game.json") && (len == 9 || path[len - 10] == '/');
    if (json || is_dir(path)) { /* a game's folder, or its game.json */
        snprintf(game_dir, sizeof game_dir, "%s", path);
        char *s = strrchr(game_dir, '/');
        if (!is_dir(path) && s) *s = 0;
        else if (!is_dir(path)) snprintf(game_dir, sizeof game_dir, ".");
        while ((len = strlen(game_dir)) > 1 && game_dir[len - 1] == '/') game_dir[len - 1] = 0;
        if (len >= 256) return hal_log("%s: too long a path (the engine takes 255 characters)", game_dir), false;
        s = strrchr(game_dir, '/');
        snprintf(name, sizeof name, "%s", s ? s + 1 : game_dir);
        if (!saves) return save_dir[0] = 0, true; /* the engine's default: <game>/saves */
        snprintf(root, sizeof root, "%s", saves);
    } else { /* its zip: unpacked into the save folder, or else beside the zip */
        snprintf(root, sizeof root, "%s", saves ? saves : path);
        char *s = saves ? NULL : strrchr(root, '/');
        if (s) *s = 0;
        else if (!saves) snprintf(root, sizeof root, ".");
        if (!unzip_game(path, root, name, sizeof name)) return false;
    }
    snprintf(dir, sizeof dir, "%s/pinyol/%s", root, name);
    if (snprintf(save_dir, sizeof save_dir, "%s/saves", dir) >= 256)
        return hal_log("%s: too long a path (the engine takes 255 characters)", save_dir), false;
    return mkdirs(dir) || (hal_log("%s: cannot make it", dir), false); /* (game_init makes saves/ itself) */
}

/* ------------------------------------------------------------------ libretro */
RETRO_API unsigned retro_api_version(void) { return RETRO_API_VERSION; }

RETRO_API void retro_get_system_info(struct retro_system_info *info) {
    memset(info, 0, sizeof *info);
    info->library_name = "Pinyol";
    info->library_version = PINYOL_VERSION;
    info->valid_extensions = "zip|pinyol|json";
    info->need_fullpath = true;  /* a game is a folder: the core reads its files itself */
    info->block_extract = true;  /* and opens its zip itself */
}

RETRO_API void retro_get_system_av_info(struct retro_system_av_info *info) {
    memset(info, 0, sizeof *info);
    info->geometry = (struct retro_game_geometry){SCREEN_W, SCREEN_H, SCREEN_W, SCREEN_H, (float)SCREEN_W / SCREEN_H};
    info->timing = (struct retro_system_timing){TICK_HZ, AUDIO_HZ};
}

RETRO_API void retro_set_environment(retro_environment_t cb) {
    env_cb = cb;
    struct retro_log_callback log;
    if (cb(RETRO_ENVIRONMENT_GET_LOG_INTERFACE, &log)) log_cb = log.log;
}
RETRO_API void retro_set_video_refresh(retro_video_refresh_t cb) { video_cb = cb; }
RETRO_API void retro_set_audio_sample(retro_audio_sample_t cb) { (void)cb; }
RETRO_API void retro_set_audio_sample_batch(retro_audio_sample_batch_t cb) { audio_cb = cb; }
RETRO_API void retro_set_input_poll(retro_input_poll_t cb) { poll_cb = cb; }
RETRO_API void retro_set_input_state(retro_input_state_t cb) { input_cb = cb; }
RETRO_API void retro_set_controller_port_device(unsigned port, unsigned device) { (void)port, (void)device; }

RETRO_API void retro_init(void) {}
RETRO_API void retro_deinit(void) {}

static const struct { unsigned id; uint16_t act; const char *name; } pad[] = {
    {RETRO_DEVICE_ID_JOYPAD_UP, ACT_UP, "Up"},          {RETRO_DEVICE_ID_JOYPAD_DOWN, ACT_DOWN, "Down"},
    {RETRO_DEVICE_ID_JOYPAD_LEFT, ACT_LEFT, "Left"},    {RETRO_DEVICE_ID_JOYPAD_RIGHT, ACT_RIGHT, "Right"},
    {RETRO_DEVICE_ID_JOYPAD_A, ACT_OK, "A"},            {RETRO_DEVICE_ID_JOYPAD_B, ACT_BACK, "B"},
    {RETRO_DEVICE_ID_JOYPAD_X, ACT_NEXT, "C"},          {RETRO_DEVICE_ID_JOYPAD_Y, ACT_NEXT, "C"},
    {RETRO_DEVICE_ID_JOYPAD_START, ACT_PAUSE, "START"}, {RETRO_DEVICE_ID_JOYPAD_SELECT, ACT_INV, "MENU"},
};
#define PAD_N (sizeof pad / sizeof pad[0])

RETRO_API bool retro_load_game(const struct retro_game_info *game) {
    enum retro_pixel_format rgb565 = RETRO_PIXEL_FORMAT_RGB565;
    if (!game || !game->path) return false;
    if (!env_cb(RETRO_ENVIRONMENT_SET_PIXEL_FORMAT, &rgb565))
        return hal_log("the frontend cannot show RGB565"), false;
    struct retro_input_descriptor desc[PAD_N + 1];
    for (size_t i = 0; i < PAD_N; i++)
        desc[i] = (struct retro_input_descriptor){0, RETRO_DEVICE_JOYPAD, 0, pad[i].id, pad[i].name};
    desc[PAD_N] = (struct retro_input_descriptor){0};
    env_cb(RETRO_ENVIRONMENT_SET_INPUT_DESCRIPTORS, desc);
    if (!open_content(game->path)) return false;
    cfg = (bp_config){game_dir, save_dir[0] ? save_dir : NULL, false};
    frames = 0;
    if (!game_init(&cfg)) return hal_log("%s: game folder incomplete", game_dir), game_shutdown(), false;
    return true;
}

RETRO_API void retro_unload_game(void) { game_shutdown(); }
RETRO_API void retro_reset(void) {
    if (!game_init(&cfg)) hal_log("%s: game folder incomplete", game_dir);
}

static hal_input read_input(void) {
    hal_input in = {0};
    poll_cb();
    for (size_t i = 0; i < PAD_N; i++)
        if (input_cb(0, RETRO_DEVICE_JOYPAD, 0, pad[i].id)) in.held |= pad[i].act;
    in.touch = input_cb(0, RETRO_DEVICE_POINTER, 0, RETRO_DEVICE_ID_POINTER_PRESSED) != 0;
    long x = input_cb(0, RETRO_DEVICE_POINTER, 0, RETRO_DEVICE_ID_POINTER_X) + 0x7fff; /* -0x7fff..0x7fff */
    long y = input_cb(0, RETRO_DEVICE_POINTER, 0, RETRO_DEVICE_ID_POINTER_Y) + 0x7fff;
    in.px = (int16_t)(x * (SCREEN_W - 1) / 0xfffe), in.py = (int16_t)(y * (SCREEN_H - 1) / 0xfffe);
    return in;
}

RETRO_API void retro_run(void) {
    hal_input in = read_input();
    game_tick(&in);
    game_render(fb);
    video_cb(fb, SCREEN_W, SCREEN_H, SCREEN_W * sizeof fb[0]);
    /* 22050 / 60 = 367.5 samples a frame: 367 and 368 in turn */
    int n = (int)((frames + 1) * AUDIO_HZ / TICK_HZ - frames * AUDIO_HZ / TICK_HZ);
    int16_t stereo[2 * (AUDIO_HZ / TICK_HZ + 1)];
    audio_mix_stereo(stereo, n);
    audio_cb(stereo, (size_t)n);
    frames++;
    if (game_quit_requested()) env_cb(RETRO_ENVIRONMENT_SHUTDOWN, NULL);
}

/* ponytail: no save states, so no rewind, run-ahead or netplay; the games keep their own saves. Add serialize from
 * state.c when a frontend feature asks for it */
RETRO_API size_t retro_serialize_size(void) { return 0; }
RETRO_API bool retro_serialize(void *data, size_t size) { return (void)data, (void)size, false; }
RETRO_API bool retro_unserialize(const void *data, size_t size) { return (void)data, (void)size, false; }
RETRO_API void retro_cheat_reset(void) {}
RETRO_API void retro_cheat_set(unsigned index, bool enabled, const char *code) { (void)index, (void)enabled, (void)code; }
RETRO_API bool retro_load_game_special(unsigned type, const struct retro_game_info *info, size_t num) {
    return (void)type, (void)info, (void)num, false;
}
RETRO_API unsigned retro_get_region(void) { return RETRO_REGION_NTSC; }
RETRO_API void *retro_get_memory_data(unsigned id) { return (void)id, NULL; }
RETRO_API size_t retro_get_memory_size(unsigned id) { return (void)id, 0; }
