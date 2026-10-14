/* pinyol_sim: desktop simulator. Same core, same game folder as the console's microSD.
 *   pinyol_sim [--game DIR] [--saves DIR] [--scale N] [--mute] [--script FILE]
 * Keys: arrows/WASD move, Enter/E/Z = A, Esc/Backspace/X = B, Tab/C = C, I = MENU (bag), J = notebook, P = START.
 * Mouse = touch. F5 restarts the game, and so does saving any of its files (hot reload, to make games quickly).
 * Built with Emscripten it is the web player: the game folder is at /game (packed in, or unzipped
 * there by player.html), and the page's on-screen buttons press through web_button(). */
#include <SDL.h>
#include <stdarg.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>

#include "bp.h"

#ifdef __EMSCRIPTEN__
#include <emscripten.h>
#define DEFAULT_GAME "/game"
#elif defined PINYOL_GAME /* the build's GAME_DIR */
#define DEFAULT_GAME PINYOL_GAME
#else
#define DEFAULT_GAME "examples/hola"
#endif

static SDL_AudioDeviceID audio_dev;
static SDL_Window *win;
static SDL_Renderer *ren;
static SDL_Texture *tex;
static uint16_t fb[SCREEN_W * SCREEN_H];
static int scale = 2;
static bool closed;

void hal_log(const char *fmt, ...) {
    va_list ap;
    va_start(ap, fmt);
    vfprintf(stderr, fmt, ap);
    va_end(ap);
    fputc('\n', stderr);
}

void *hal_realloc_slow(void *p, size_t n) { return realloc(p, n); }

void hal_parallel(void (*fn)(int part, void *ctx), void *ctx) { fn(0, ctx), fn(1, ctx); }
uint32_t hal_micros(void) { return (uint32_t)(SDL_GetPerformanceCounter() * 1000000 / SDL_GetPerformanceFrequency()); }

void hal_audio_lock(void) { if (audio_dev) SDL_LockAudioDevice(audio_dev); }

static int audio_block; /* samples of each callback, as the device gave them */
#ifdef __EMSCRIPTEN__
EM_JS(double, web_audio_latency, (void), { /* seconds the browser adds after a buffer is handed over */
    const c = Module.SDL2 && Module.SDL2.audioContext;
    return c ? (c.baseLatency || 0) + (c.outputLatency || 0) : 0;
});
#endif
/* ponytail: a block waits for the one playing; the system adds about half a block more (desktop) or what the
 * browser says. A rhythm game still lets the player tune it (docs/lua.md, music_time). */
int hal_audio_latency(void) {
    if (!audio_dev) return -1;
#ifdef __EMSCRIPTEN__
    return audio_block + (int)(web_audio_latency() * AUDIO_HZ);
#else
    return audio_block + audio_block / 2;
#endif
}
void hal_audio_unlock(void) { if (audio_dev) SDL_UnlockAudioDevice(audio_dev); }

/* The link between consoles (src/link.c). Desktop: UDP multicast on the local network (platform/link_udp.c), so
 * simulators hear each other. Browser: a BroadcastChannel, so tabs of the same browser do. */
#ifdef __EMSCRIPTEN__
EM_JS(int, web_link_open, (void), {
    if (typeof BroadcastChannel === "undefined") return 0;
    if (!Module.pinyolLink) {
        Module.pinyolLink = new BroadcastChannel("pinyol-link");
        Module.pinyolLinkIn = [];
        Module.pinyolLink.onmessage = (e) => { if (Module.pinyolLinkIn.length < 256) Module.pinyolLinkIn.push(e.data); };
    }
    return 1;
});
EM_JS(void, web_link_send, (const uint8_t *p, int n), { Module.pinyolLink.postMessage(HEAPU8.slice(p, p + n)); });
EM_JS(int, web_link_recv, (uint8_t *p, int max), {
    const q = Module.pinyolLinkIn;
    while (q && q.length) {
        const d = q.shift();
        if (!(d instanceof Uint8Array) || d.length > max) continue;
        HEAPU8.set(d, p);
        return d.length;
    }
    return 0;
});
EM_JS(uint32_t, web_link_id, (void), {
    if (!Module.pinyolLinkId) Module.pinyolLinkId = (Math.random() * 0x7FFFFFFF | 0) + 1;
    return Module.pinyolLinkId;
});
bool hal_link_open(void) { return web_link_open(); }
void hal_link_close(void) {}
bool hal_link_send(const uint8_t *p, int n) { return web_link_send(p, n), true; }
int hal_link_recv(uint8_t *p, int max) { return web_link_recv(p, max); }
uint32_t hal_link_id(void) { return web_link_id(); }
#else
#include "../link_udp.h"
bool hal_link_open(void) { return link_udp_open(); }
void hal_link_close(void) { link_udp_close(); }
bool hal_link_send(const uint8_t *p, int n) { return link_udp_send(p, n); }
int hal_link_recv(uint8_t *p, int max) { return link_udp_recv(p, max); }
uint32_t hal_link_id(void) { return link_udp_id(); }
#endif

/* The microphone (src/mic.c): a capture device whose callback fills a ring the game empties each tick. In a
 * browser SDL asks for it through getUserMedia, so the page asks the player first. */
static SDL_AudioDeviceID mic_dev;
static int16_t mic_ring[8192];
static int mic_w, mic_r; /* under the capture device's lock */

static void mic_cb(void *user, Uint8 *stream, int len) {
    (void)user;
    const int16_t *p = (const int16_t *)stream;
    for (int i = 0; i < len / 2; i++) {
        mic_ring[mic_w] = p[i];
        mic_w = (mic_w + 1) % 8192;
        if (mic_w == mic_r) mic_r = (mic_r + 1) % 8192; /* full: the oldest goes */
    }
}

#ifdef __EMSCRIPTEN__
/* SDL asks for {audio: true}: the browser would level the volume and take out noise, so a breath or a steady level
 * could not be heard. Only the echo of the game's own sound is taken out. */
EM_JS(void, web_mic_raw, (void), {
    const md = navigator.mediaDevices;
    if (!md || Module.pinyolMicRaw) return;
    const ask = md.getUserMedia.bind(md);
    md.getUserMedia = (c) => ask(c && c.audio === true ? Object.assign({}, c, {audio: {echoCancellation: true,
                                    noiseSuppression: false, autoGainControl: false}}) : c);
    Module.pinyolMicRaw = true;
});
#endif

bool hal_mic_open(void) {
#ifdef __EMSCRIPTEN__
    web_mic_raw();
#endif
    if (!SDL_WasInit(SDL_INIT_AUDIO) && SDL_InitSubSystem(SDL_INIT_AUDIO)) return false;
    SDL_AudioSpec want = {.freq = AUDIO_HZ, .format = AUDIO_S16LSB, .channels = 1, .samples = 512, .callback = mic_cb};
    mic_dev = SDL_OpenAudioDevice(NULL, 1, &want, NULL, 0);
    if (!mic_dev) {
        hal_log("microphone unavailable: %s", SDL_GetError());
        return false;
    }
    mic_w = mic_r = 0;
    SDL_PauseAudioDevice(mic_dev, 0);
    return true;
}

void hal_mic_close(void) {
    if (mic_dev) SDL_CloseAudioDevice(mic_dev);
    mic_dev = 0;
}

int hal_mic_read(int16_t *p, int max) {
    if (!mic_dev) return 0;
    SDL_LockAudioDevice(mic_dev);
    int n = 0;
    while (n < max && mic_r != mic_w) p[n++] = mic_ring[mic_r], mic_r = (mic_r + 1) % 8192;
    SDL_UnlockAudioDevice(mic_dev);
    return n;
}

/* The pilot LED and the battery (lua_device.c). The browser: a light on the player's page, and the Battery API
 * where the browser has it (Chrome; asked once, then kept up to date by its events). The desktop: no light, and
 * the laptop's battery as SDL sees it. */
#ifdef __EMSCRIPTEN__
EM_JS(void, web_led, (int rgb), {
    const e = document.getElementById("led");
    if (!e) return;
    if (rgb < 0) { e.hidden = true; return; }
    const c = "rgb(" + ((rgb >> 16) & 255) + "," + ((rgb >> 8) & 255) + ",0)"; /* red and green: as the console */
    e.hidden = false;
    e.style.background = c;
    e.style.boxShadow = "0 0 10px 3px " + c;
});
EM_JS(int, web_battery, (float *level, int *charging), {
    if (!Module.pinyolBattery && navigator.getBattery) {
        Module.pinyolBattery = {};
        navigator.getBattery().then((b) => { Module.pinyolBattery = b; }).catch(() => {});
    }
    const b = Module.pinyolBattery;
    if (!b || b.level === undefined) return 0;
    HEAPF32[level >> 2] = b.level;
    HEAP32[charging >> 2] = b.charging ? 1 : 0;
    return 1;
});
void hal_led(int rgb) { web_led(rgb); }
bool hal_battery(float *level, bool *charging) {
    int c = 0;
    if (!web_battery(level, &c)) return false;
    *charging = c;
    return true;
}
#else
void hal_led(int rgb) { (void)rgb; }
bool hal_battery(float *level, bool *charging) {
    int pct = -1;
    SDL_PowerState st = SDL_GetPowerInfo(NULL, &pct);
    if (st == SDL_POWERSTATE_UNKNOWN || st == SDL_POWERSTATE_NO_BATTERY || pct < 0) return false;
    *level = pct / 100.0f, *charging = st == SDL_POWERSTATE_CHARGING;
    return true;
}
#endif

static bool muted; /* the web page's mute button: the game plays on, silent (its own fades are left alone) */

static void audio_cb(void *user, Uint8 *stream, int len) {
    (void)user;
    audio_mix((int16_t *)stream, len / 2); /* SDL holds the device lock during the callback */
    if (muted) memset(stream, 0, (size_t)len);
}

#ifdef __EMSCRIPTEN__
static uint16_t web_held; /* the page's on-screen buttons */

/* button: 0 up, 1 down, 2 left, 3 right, 4 A, 5 B, 6 C, 7 START, 8 MENU (the names btn() takes in Lua) */

EMSCRIPTEN_KEEPALIVE void web_mute(int on) { muted = on; }

EMSCRIPTEN_KEEPALIVE void web_button(int button, int down) {
    static const uint16_t bits[] = {ACT_UP, ACT_DOWN, ACT_LEFT, ACT_RIGHT, ACT_OK, ACT_BACK, ACT_NEXT, ACT_PAUSE, ACT_INV};
    if (button < 0 || button >= (int)(sizeof bits / sizeof bits[0])) return;
    web_held = down ? web_held | bits[button] : web_held & ~bits[button];
}
#endif

#ifndef __EMSCRIPTEN__
#include <dirent.h>
#include <sys/stat.h>
#include <time.h>

static bp_config game_cfg;
static bool reload_req;
static struct stat saves_dir; /* --saves, if it lies inside the game folder: the game's own writes are not edits */

/* The newest change among the game's files, one folder deep; saves/ (the game writes there) and art/ (sources, the
 * game reads assets/) left out. */
static time_t newest(const char *dir, int depth) {
    time_t t = 0;
    DIR *d = opendir(dir);
    if (!d) return 0;
    struct dirent *e;
    while ((e = readdir(d))) {
        if (e->d_name[0] == '.' || !strcmp(e->d_name, "saves") || !strcmp(e->d_name, "art")) continue;
        char p[1024];
        struct stat st;
        snprintf(p, sizeof p, "%s/%s", dir, e->d_name);
        if (stat(p, &st)) continue;
        if (S_ISDIR(st.st_mode) && st.st_ino == saves_dir.st_ino && st.st_dev == saves_dir.st_dev) continue;
        time_t u = S_ISDIR(st.st_mode) ? (depth > 0 ? newest(p, depth - 1) : 0) : st.st_mtime;
        if (u > t) t = u;
    }
    closedir(d);
    return t;
}

static void hot_reload(void) { /* twice a second: a file saved since the last look restarts the game */
    static time_t seen;
    static unsigned n;
    if (n++ % (TICK_HZ / 2) == 0) {
        if (n == 1 && game_cfg.save_dir) stat(game_cfg.save_dir, &saves_dir); /* (game_init has made it) */
        time_t t = newest(game_cfg.game_dir, 1);
        if (seen && t > seen) reload_req = true;
        if (t > seen) seen = t;
    }
    if (!reload_req) return;
    reload_req = false;
    game_shutdown();
    if (game_init(&game_cfg)) hal_log("reloaded %s", game_cfg.game_dir);
    else hal_log("reload: %s is incomplete (fix it and save again)", game_cfg.game_dir);
}
#endif

static hal_input poll_input(void) {
    SDL_Event e;
    while (SDL_PollEvent(&e)) {
        if (e.type == SDL_QUIT) closed = true;
#ifndef __EMSCRIPTEN__
        if (e.type == SDL_KEYDOWN && e.key.keysym.sym == SDLK_F5) reload_req = true;
#endif
        if (e.type == SDL_KEYDOWN && e.key.keysym.sym == SDLK_F3) v2_meter_toggle();
    }
    const Uint8 *k = SDL_GetKeyboardState(NULL);
    hal_input in = {0};
    if (k[SDL_SCANCODE_UP] || k[SDL_SCANCODE_W]) in.held |= ACT_UP;
    if (k[SDL_SCANCODE_DOWN] || k[SDL_SCANCODE_S]) in.held |= ACT_DOWN;
    if (k[SDL_SCANCODE_LEFT] || k[SDL_SCANCODE_A]) in.held |= ACT_LEFT;
    if (k[SDL_SCANCODE_RIGHT] || k[SDL_SCANCODE_D]) in.held |= ACT_RIGHT;
    if (k[SDL_SCANCODE_RETURN] || k[SDL_SCANCODE_E] || k[SDL_SCANCODE_SPACE] || k[SDL_SCANCODE_Z]) in.held |= ACT_OK;
    if (k[SDL_SCANCODE_ESCAPE] || k[SDL_SCANCODE_BACKSPACE] || k[SDL_SCANCODE_X]) in.held |= ACT_BACK;
    if (k[SDL_SCANCODE_TAB] || k[SDL_SCANCODE_C]) in.held |= ACT_NEXT;
    if (k[SDL_SCANCODE_I]) in.held |= ACT_INV;
    if (k[SDL_SCANCODE_J]) in.held |= ACT_NOTES;
    if (k[SDL_SCANCODE_P]) in.held |= ACT_PAUSE;
    if (closed) in.held |= ACT_QUIT;
#ifdef __EMSCRIPTEN__
    in.held |= web_held;
#endif
    int mx, my;
    Uint32 b = SDL_GetMouseState(&mx, &my);
    in.touch = (b & SDL_BUTTON_LMASK) != 0;
    in.px = (int16_t)(mx / scale);
    in.py = (int16_t)(my / scale);
    return in;
}

static void present(void) {
    game_render(fb);
    SDL_UpdateTexture(tex, NULL, fb, SCREEN_W * 2);
    SDL_RenderClear(ren);
    SDL_RenderCopy(ren, tex, NULL, NULL);
    SDL_RenderPresent(ren);
}

static void script_frame(void) { /* watch a script run at game speed */
    SDL_Event e;
    while (SDL_PollEvent(&e))
        if (e.type == SDL_QUIT) closed = true;
    present();
    SDL_Delay(1000 / TICK_HZ);
}

static Uint64 freq, last;
static double acc;

static void frame(void) {
#ifndef __EMSCRIPTEN__
    hot_reload();
#endif
    Uint64 now = SDL_GetPerformanceCounter();
    acc += (double)(now - last) * 1000.0 / freq;
    last = now;
    if (acc > 250) acc = 250; /* after a stall, don't spiral */
    if (acc > TICK_MS - 2 && acc < TICK_MS + 2) acc = TICK_MS; /* vsync jitter: exactly one tick per frame */
    while (acc >= TICK_MS) {
        hal_input in = poll_input();
#ifdef __EMSCRIPTEN__ /* in a browser stderr is console.error: no perf log, keep the page's console clean */
        game_tick(&in);
#else
        static Uint64 work;
        static uint32_t frames;
        Uint64 t0 = SDL_GetPerformanceCounter();
        game_tick(&in);
        work += SDL_GetPerformanceCounter() - t0;
        if (++frames % 300 == 0) {
            hal_log("perf: avg tick %.3f ms over 300 ticks", (double)work * 1000.0 / freq / 300);
            work = 0;
        }
#endif
        acc -= TICK_MS;
    }
    present();
}

int main(int argc, char **argv) {
    bp_config cfg = {DEFAULT_GAME, NULL};
    const char *script = NULL;
    bool mute = false;
    for (int i = 1; i < argc; i++) {
        if (!strcmp(argv[i], "--game") && i + 1 < argc) cfg.game_dir = argv[++i];
        else if (!strcmp(argv[i], "--saves") && i + 1 < argc) cfg.save_dir = argv[++i];
        else if (!strcmp(argv[i], "--scale") && i + 1 < argc) scale = atoi(argv[++i]) > 0 ? atoi(argv[i]) : 2;
        else if (!strcmp(argv[i], "--script") && i + 1 < argc) script = argv[++i];
        else if (!strcmp(argv[i], "--mute")) mute = true;
    }
    if (SDL_Init(SDL_INIT_VIDEO | (mute ? 0 : SDL_INIT_AUDIO)) != 0) {
        fprintf(stderr, "SDL: %s\n", SDL_GetError());
        return 1;
    }
    win = SDL_CreateWindow("pinyol", SDL_WINDOWPOS_CENTERED, SDL_WINDOWPOS_CENTERED, SCREEN_W * scale,
                           SCREEN_H * scale, 0);
    ren = SDL_CreateRenderer(win, -1, SDL_RENDERER_PRESENTVSYNC);
    SDL_SetHint(SDL_HINT_RENDER_SCALE_QUALITY, "0");
    tex = SDL_CreateTexture(ren, SDL_PIXELFORMAT_RGB565, SDL_TEXTUREACCESS_STREAMING, SCREEN_W, SCREEN_H);
#ifndef __EMSCRIPTEN__
    game_cfg = cfg;
#endif
    if (!game_init(&cfg)) {
        fprintf(stderr, "game folder incomplete: %s\n", cfg.game_dir);
        SDL_Quit();
        return 1;
    }
    if (!mute) {
        SDL_AudioSpec want = {.freq = AUDIO_HZ, .format = AUDIO_S16LSB, .channels = 1, .callback = audio_cb};
#ifdef __EMSCRIPTEN__
        want.samples = 2048; /* the browser mixes on its main thread, next to the game: a longer buffer, no gaps */
#else
        want.samples = 512;
#endif
        SDL_AudioSpec have;
        audio_dev = SDL_OpenAudioDevice(NULL, 0, &want, &have, 0);
        audio_block = have.samples;
        if (audio_dev) SDL_PauseAudioDevice(audio_dev, 0);
        else fprintf(stderr, "audio unavailable: %s\n", SDL_GetError());
    }
    int rc = 0;
    if (script) {
        rc = script_run(script, script_frame);
    } else {
        freq = SDL_GetPerformanceFrequency();
        last = SDL_GetPerformanceCounter();
#ifdef __EMSCRIPTEN__
        emscripten_set_main_loop(frame, 0, 1); /* the browser calls frame() on each display refresh; never returns */
#else
        while (!game_quit_requested()) frame();
#endif
    }
    game_shutdown();
    if (audio_dev) SDL_CloseAudioDevice(audio_dev);
    SDL_Quit();
    return rc;
}

bool hal_can_switch_game(void) { return false; }
void hal_switch_game(void) {}

/* The console's games, for its menu (src/lua_console.c): here the folders in $PINYOL_GAMES; a launch ends the run. */
static int last_game = -1;
int hal_games(hal_game *g, int max, int *last, bool *cold) {
    static bool woke = true;
    *last = last_game, *cold = woke;
    woke = false;
    return console_dir_games(getenv("PINYOL_GAMES"), g, max);
}
bool hal_game_cover(const char *id, uint16_t *px, int w, int h) {
    const char *root = getenv("PINYOL_GAMES");
    char dir[512];
    if (!root) return false;
    snprintf(dir, sizeof dir, "%s/%s", root, id);
    return console_dir_cover(dir, px, w, h);
}
void hal_launch(const char *id) { hal_log("console: launch %s", id); }
void hal_power_off(void) { hal_log("console: off"); }
const char *hal_firmware(void) { return "escritorio"; }
