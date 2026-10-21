/* pinyol_sim: desktop simulator. Same core, same game folder as the console's microSD.
 *   pinyol_sim [--game DIR] [--saves DIR] [--scale N] [--mute] [--script FILE] [--no-splash]   (without the careta)
 *   pinyol_sim --console GAMES --menu firmware/cirera    the console: Cirera's menu, the game chosen, the menu again
 * Keys: arrows/WASD move, Enter/E/Z = A, Esc/Backspace/X = B, Tab/C = C, I = MENU (bag), J = notebook, P = START.
 * Mouse = touch. A gamepad: d-pad or stick, A, B, X or Y = C, START, BACK/SELECT = MENU. F11 or Alt+Enter: full
 * screen. F5 restarts the game, and so does saving any of its files (hot reload, to make games quickly).
 * Built with -DPINYOL_APP=ON it is the Cirera desktop app: the console, with its menu and games where desktop.c puts
 * them; a game's .zip dropped on the window is installed.
 * Built with Emscripten it is the web player: the game folder is at /game (packed in, or unzipped
 * there by player.html), and the page's on-screen buttons press through web_button(). */
#include <SDL.h>
#include <stdarg.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>

#include "bp.h"
#include "record.h"
#ifndef __EMSCRIPTEN__
#include "capture.h"
#endif
#ifndef __EMSCRIPTEN__
#include "desktop.h"
#endif

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
#ifndef __EMSCRIPTEN__
/* The console (--console, the app): its menu runs, then the game it launched, until MENU is held 2 s (switch_req) */
static bool console_mode, switch_req, relist;
static char games_root[1024], launch_id[64], last_id[64], dropped[1024];
static SDL_GameController *pad;
#endif

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
    audio_mix_stereo((int16_t *)stream, len / 4); /* two ears: 4 bytes a frame. SDL holds the device lock here */
    if (muted) memset(stream, 0, (size_t)len);
}

#ifdef __EMSCRIPTEN__
static uint16_t web_held; /* the page's on-screen buttons */

/* button: 0 up, 1 down, 2 left, 3 right, 4 A, 5 B, 6 C, 7 START, 8 MENU (the names btn() takes in Lua) */

EMSCRIPTEN_KEEPALIVE void web_mute(int on) { muted = on; }

/* the Lua game's error (where and what, as on its screen), or NULL: the page shows it under the game and tells the editor */
EMSCRIPTEN_KEEPALIVE const char *web_error(void) { return v2_error(); }

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
    game_cfg.no_splash = true; /* the careta was seen when it opened: a saved file goes straight back to the game */
    if (game_init(&game_cfg)) hal_log("reloaded %s", game_cfg.game_dir);
    else hal_log("reload: %s is incomplete (fix it and save again)", game_cfg.game_dir);
}
#endif

#ifndef __EMSCRIPTEN__
static const char *capture_dir(void) { /* where the simulator puts what it captures */
    static char d[1100];
    if (game_cfg.save_dir) return game_cfg.save_dir;
    snprintf(d, sizeof d, "%s/saves", game_cfg.game_dir);
    return d;
}

static void capture_key(SDL_Keycode k) { /* F6 a screenshot, F7 the cover, F8 recording on or off, F9 the last 8 s as a GIF */
    bool ok = true;
    if (k == SDLK_F6) ok = capture_png(fb, capture_dir());
    else if (k == SDLK_F7) ok = capture_cover(fb, game_cfg.game_dir);
    else if (k == SDLK_F9) ok = capture_gif(capture_dir());
    else if (record_on()) {
        record_stop();
        hal_log("recording saved");
        return;
    } else {
        char path[1200];
        for (int n = 1; n < 10000; n++) {
            snprintf(path, sizeof path, "%s/partida-%d.script", capture_dir(), n);
            FILE *f = fopen(path, "rb");
            if (!f) break;
            fclose(f);
        }
        ok = record_start(path, game_cfg.game_dir);
        hal_log(ok ? "recording to %s (F8 again to stop)" : "cannot record to %s", path);
        return;
    }
    hal_log(ok ? "%s" : "cannot write %s", capture_last());
}
#endif

static hal_input poll_input(void) {
    SDL_Event e;
    while (SDL_PollEvent(&e)) {
        if (e.type == SDL_QUIT) closed = true;
#ifndef __EMSCRIPTEN__
        if (e.type == SDL_KEYDOWN && e.key.keysym.sym == SDLK_F5) reload_req = true;
        if (e.type == SDL_KEYDOWN && (e.key.keysym.sym == SDLK_F11 ||
                                      (e.key.keysym.sym == SDLK_RETURN && (e.key.keysym.mod & KMOD_ALT))))
            SDL_SetWindowFullscreen(win, SDL_GetWindowFlags(win) & SDL_WINDOW_FULLSCREEN_DESKTOP ? 0 : SDL_WINDOW_FULLSCREEN_DESKTOP);
        if (e.type == SDL_DROPFILE) { /* installed after this frame; the next one waits in the queue for the next */
            if (strlen(e.drop.file) < sizeof dropped) snprintf(dropped, sizeof dropped, "%s", e.drop.file);
            SDL_free(e.drop.file);
            break;
        }
        if (e.type == SDL_CONTROLLERDEVICEADDED && !pad) pad = SDL_GameControllerOpen(e.cdevice.which);
        if (e.type == SDL_CONTROLLERDEVICEREMOVED && pad &&
            e.cdevice.which == SDL_JoystickInstanceID(SDL_GameControllerGetJoystick(pad)))
            SDL_GameControllerClose(pad), pad = NULL;
#endif
        if (e.type == SDL_KEYDOWN && e.key.keysym.sym == SDLK_F3) v2_meter_toggle();
#ifndef __EMSCRIPTEN__
        if (e.type == SDL_KEYDOWN && e.key.keysym.sym >= SDLK_F6 && e.key.keysym.sym <= SDLK_F9) capture_key(e.key.keysym.sym);
#endif
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
#else
    if (pad) {
        static const struct { SDL_GameControllerButton b; uint16_t act; } map[] = {
            {SDL_CONTROLLER_BUTTON_DPAD_UP, ACT_UP}, {SDL_CONTROLLER_BUTTON_DPAD_DOWN, ACT_DOWN},
            {SDL_CONTROLLER_BUTTON_DPAD_LEFT, ACT_LEFT}, {SDL_CONTROLLER_BUTTON_DPAD_RIGHT, ACT_RIGHT},
            {SDL_CONTROLLER_BUTTON_A, ACT_OK}, {SDL_CONTROLLER_BUTTON_B, ACT_BACK}, {SDL_CONTROLLER_BUTTON_X, ACT_NEXT},
            {SDL_CONTROLLER_BUTTON_Y, ACT_NEXT}, {SDL_CONTROLLER_BUTTON_START, ACT_PAUSE}, {SDL_CONTROLLER_BUTTON_BACK, ACT_INV}};
        for (size_t i = 0; i < sizeof map / sizeof map[0]; i++)
            if (SDL_GameControllerGetButton(pad, map[i].b)) in.held |= map[i].act;
        int ax = SDL_GameControllerGetAxis(pad, SDL_CONTROLLER_AXIS_LEFTX), ay = SDL_GameControllerGetAxis(pad, SDL_CONTROLLER_AXIS_LEFTY);
        if (ax < -16000) in.held |= ACT_LEFT;
        if (ax > 16000) in.held |= ACT_RIGHT;
        if (ay < -16000) in.held |= ACT_UP;
        if (ay > 16000) in.held |= ACT_DOWN;
    }
#endif
    int mx, my;
    Uint32 b = SDL_GetMouseState(&mx, &my);
    in.touch = (b & SDL_BUTTON_LMASK) != 0;
#ifdef __EMSCRIPTEN__
    in.px = (int16_t)(mx / scale);
    in.py = (int16_t)(my / scale);
#else /* the window can be any size: its picture is the screen at a whole scale, centred */
    float lx, ly;
    SDL_RenderWindowToLogical(ren, mx, my, &lx, &ly);
    in.px = (int16_t)lx;
    in.py = (int16_t)ly;
#endif
    in.points = in.touch, in.x[0] = in.px, in.y[0] = in.py;
#ifdef __EMSCRIPTEN__
    if (SDL_GetNumTouchDevices() > 0) { /* a phone's fingers, the first being the mouse SDL makes of it */
        SDL_TouchID dev = SDL_GetTouchDevice(0); /* ponytail: one touch device; not yet tried on a phone */
        int n = SDL_GetNumTouchFingers(dev);
        for (int i = 0; i < n && i < HAL_POINTS; i++) {
            SDL_Finger *f = SDL_GetTouchFinger(dev, i);
            if (f) in.x[i] = (int16_t)(f->x * SCREEN_W), in.y[i] = (int16_t)(f->y * SCREEN_H), in.points = (uint8_t)(i + 1);
        }
    }
#else
    if (in.touch && (SDL_GetModState() & KMOD_ALT)) /* Alt and a click: a second finger mirrored round the middle (a pinch) */
        in.points = 2, in.x[1] = (int16_t)(SCREEN_W - 1 - in.px), in.y[1] = (int16_t)(SCREEN_H - 1 - in.py);
#endif
    return in;
}

static void present(void) {
    game_render(fb);
#ifndef __EMSCRIPTEN__
    capture_frame(fb); /* the last 8 s, for F9 */
#endif
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
    if (!console_mode) hot_reload();
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

#ifndef __EMSCRIPTEN__
/* The app's words in the system's language: Spanish, Catalan, or else English */
static const char *say(const char *es, const char *ca, const char *en) {
    static int lang = -1;
    if (lang < 0) {
        SDL_Locale *loc = SDL_GetPreferredLocales();
        const char *l = loc && loc[0].language ? loc[0].language : "";
        lang = !strcmp(l, "es") ? 0 : !strcmp(l, "ca") ? 1 : 2;
        SDL_free(loc);
    }
    return lang == 0 ? es : lang == 1 ? ca : en;
}

static void console_frame(void) { /* a frame of the console, and a game's .zip dropped on the window installed */
    frame();
    if (!dropped[0]) return;
    char name[128], msg[1300];
    bool ok = desktop_install(dropped, games_root, name, sizeof name);
    const char *file = dropped;
    for (const char *c = dropped; *c; c++)
        if (*c == '/' || *c == '\\') file = c + 1;
    if (ok)
        snprintf(msg, sizeof msg, say("Instalado: %s. Ya sale en el menú.", "Instal·lat: %s. Ja surt al menú.",
                                      "Installed: %s. It is in the menu now."), name);
    else
        snprintf(msg, sizeof msg,
                 say("No se ha podido instalar %s: tiene que ser el .zip de un juego de Pinyol.",
                     "No s'ha pogut instal·lar %s: ha de ser el .zip d'un joc de Pinyol.",
                     "Could not install %s: it has to be the .zip of a Pinyol game."), file);
    hal_log("app: %s", msg);
    SDL_ShowSimpleMessageBox(ok ? SDL_MESSAGEBOX_INFORMATION : SDL_MESSAGEBOX_WARNING, "Cirera", msg, win);
    relist = ok; /* the menu starts again, with it in the list */
    dropped[0] = 0;
    last = SDL_GetPerformanceCounter(); /* the box held the clock: no ticks to catch up */
}

/* The console, as the firmware runs it: its menu until it launches a game (console_launch) or switches off, then
 * that game until it ends or MENU is held 2 s, then the menu again. */
static int run_console(const char *menu_dir) {
    for (;;) {
        bp_config menu = {menu_dir, NULL, true}; /* the menu builds pinyol's logo itself */
        launch_id[0] = 0, relist = false;
        if (!game_init(&menu)) {
            fprintf(stderr, "menu incomplete: %s\n", menu_dir);
            return 1;
        }
        while (!game_quit_requested() && !relist && !closed) console_frame();
        game_shutdown();
        if (closed) return 0;
        if (!launch_id[0]) continue; /* it ended without choosing (a game was installed): again */
        char dir[1100];
        snprintf(dir, sizeof dir, "%s/%s", games_root, launch_id);
        bp_config game = {dir, NULL, false};
        switch_req = false;
        if (!game_init(&game)) hal_log("%s: incomplete, back to the menu", launch_id);
        else
            while (!game_quit_requested() && !switch_req && !closed) console_frame();
        game_shutdown();
        if (closed) return 0;
    }
}
#endif

int main(int argc, char **argv) {
    bp_config cfg = {DEFAULT_GAME, NULL, false};
    const char *script = NULL, *record_path = NULL;
    bool mute = false, given = false; /* given: a game named (--game), played as it is */
    (void)record_path;
#ifndef __EMSCRIPTEN__
    const char *menu = NULL;
    char menu_dir[1024];
#ifdef PINYOL_APP
    bool app = true; /* the app opens as the console, unless it is given a game */
#else
    bool app = false;
#endif
#endif
    for (int i = 1; i < argc; i++) {
        if (!strcmp(argv[i], "--game") && i + 1 < argc) cfg.game_dir = argv[++i], given = true;
        else if (!strcmp(argv[i], "--saves") && i + 1 < argc) cfg.save_dir = argv[++i];
        else if (!strcmp(argv[i], "--scale") && i + 1 < argc) scale = atoi(argv[++i]) > 0 ? atoi(argv[i]) : 2;
        else if (!strcmp(argv[i], "--script") && i + 1 < argc) script = argv[++i];
        else if (!strcmp(argv[i], "--mute")) mute = true;
        else if (!strcmp(argv[i], "--no-splash")) cfg.no_splash = true; /* making the game: straight to it */
#ifndef __EMSCRIPTEN__
        else if (!strcmp(argv[i], "--record") && i + 1 < argc) record_path = argv[++i]; /* the play as a test script */
#endif
#ifndef __EMSCRIPTEN__
        else if (!strcmp(argv[i], "--console") && i + 1 < argc) snprintf(games_root, sizeof games_root, "%s", argv[++i]), console_mode = true;
        else if (!strcmp(argv[i], "--menu") && i + 1 < argc) menu = argv[++i];
#endif
    }
    if (script) cfg.no_splash = true; /* a script counts its ticks from _init */
#ifndef __EMSCRIPTEN__
    if (record_path && !record_start(record_path, cfg.game_dir)) fprintf(stderr, "cannot record to %s\n", record_path);
#endif
#ifndef __EMSCRIPTEN__
    if (given) app = false;
#else
    (void)given;
#endif
    if (SDL_Init(SDL_INIT_VIDEO | (mute ? 0 : SDL_INIT_AUDIO)
#ifndef __EMSCRIPTEN__
                 | SDL_INIT_GAMECONTROLLER
#endif
                 ) != 0) {
        fprintf(stderr, "SDL: %s\n", SDL_GetError());
        return 1;
    }
#ifndef __EMSCRIPTEN__
    if (app && !console_mode) {
        if (!desktop_paths(menu_dir, games_root, sizeof menu_dir)) {
            SDL_ShowSimpleMessageBox(SDL_MESSAGEBOX_ERROR, "Cirera",
                                     say("Falta el menú de la consola: tiene que estar junto a la aplicación.",
                                         "Falta el menú de la consola: ha d'estar al costat de l'aplicació.",
                                         "The console's menu is missing: it has to be next to the app."), NULL);
            return 1;
        }
        console_mode = true, menu = menu_dir;
    }
    if (console_mode && !menu) menu = "firmware/cirera";
    win = SDL_CreateWindow(console_mode ? "Cirera" : "pinyol", SDL_WINDOWPOS_CENTERED, SDL_WINDOWPOS_CENTERED,
                           SCREEN_W * scale, SCREEN_H * scale, SDL_WINDOW_RESIZABLE | SDL_WINDOW_ALLOW_HIGHDPI);
#else
    win = SDL_CreateWindow("pinyol", SDL_WINDOWPOS_CENTERED, SDL_WINDOWPOS_CENTERED, SCREEN_W * scale,
                           SCREEN_H * scale, 0);
#endif
    ren = SDL_CreateRenderer(win, -1, SDL_RENDERER_PRESENTVSYNC);
    SDL_SetHint(SDL_HINT_RENDER_SCALE_QUALITY, "0");
    tex = SDL_CreateTexture(ren, SDL_PIXELFORMAT_RGB565, SDL_TEXTUREACCESS_STREAMING, SCREEN_W, SCREEN_H);
#ifndef __EMSCRIPTEN__
    SDL_RenderSetLogicalSize(ren, SCREEN_W, SCREEN_H); /* any window size: the screen at a whole scale, centred */
    SDL_RenderSetIntegerScale(ren, SDL_TRUE);
    if (app) { /* the window's icon, beside the app's menu */
        char icon[1100];
        snprintf(icon, sizeof icon, "%s/../icon.bmp", menu);
        SDL_Surface *ic = SDL_LoadBMP(icon);
        if (ic) SDL_SetWindowIcon(win, ic), SDL_FreeSurface(ic);
    }
    game_cfg = cfg;
    if (!console_mode && !game_init(&cfg)) {
#else
    if (!game_init(&cfg)) {
#endif
        fprintf(stderr, "game folder incomplete: %s\n", cfg.game_dir);
        SDL_Quit();
        return 1;
    }
    if (!mute) {
        SDL_AudioSpec want = {.freq = AUDIO_HZ, .format = AUDIO_S16LSB, .channels = 2, .callback = audio_cb};
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
#ifndef __EMSCRIPTEN__
    } else if (console_mode) {
        freq = SDL_GetPerformanceFrequency();
        last = SDL_GetPerformanceCounter();
        rc = run_console(menu);
        if (audio_dev) SDL_CloseAudioDevice(audio_dev);
        SDL_Quit();
        return rc;
#endif
    } else {
        freq = SDL_GetPerformanceFrequency();
        last = SDL_GetPerformanceCounter();
#ifdef __EMSCRIPTEN__
        emscripten_set_main_loop(frame, 0, 1); /* the browser calls frame() on each display refresh; never returns */
#else
        while (!game_quit_requested()) frame();
#endif
    }
    record_stop(); /* (--record or F8: the recording whole) */
    game_shutdown();
    if (audio_dev) SDL_CloseAudioDevice(audio_dev);
    SDL_Quit();
    return rc;
}

/* The console's games, for its menu (src/lua_console.c): the folders in the console's games (--console, the app),
 * or else in $PINYOL_GAMES (a menu run as a plain game, to work on it: a launch ends the run). */
#ifndef __EMSCRIPTEN__
bool hal_can_switch_game(void) { return console_mode; }
void hal_switch_game(void) { switch_req = true; }
static const char *games_dir(void) { return console_mode ? games_root : getenv("PINYOL_GAMES"); }
void hal_launch(const char *id) {
    snprintf(launch_id, sizeof launch_id, "%s", id);
    snprintf(last_id, sizeof last_id, "%s", id);
}
void hal_power_off(void) {
    if (console_mode) closed = true; /* the menu's "turn off": the app closes */
    else hal_log("console: off");
}
#else
static const char last_id[1] = "";
bool hal_can_switch_game(void) { return false; }
void hal_switch_game(void) {}
static const char *games_dir(void) { return getenv("PINYOL_GAMES"); }
void hal_launch(const char *id) { hal_log("console: launch %s", id); }
void hal_power_off(void) { hal_log("console: off"); }
#endif
int hal_games(hal_game *g, int max, int *last, bool *cold) {
    static bool woke = true;
    int n = console_dir_games(games_dir(), g, max);
    *last = -1, *cold = woke;
    woke = false;
    for (int i = 0; i < n; i++)
        if (!strcmp(g[i].id, last_id)) *last = i;
    return n;
}
bool hal_game_cover(const char *id, uint16_t *px, int w, int h) {
    const char *root = games_dir();
    char dir[1100];
    if (!root) return false;
    snprintf(dir, sizeof dir, "%s/%s", root, id);
    return console_dir_cover(dir, px, w, h);
}
const char *hal_firmware(void) { return "escritorio"; }

bool hal_console_dir(char *path, size_t n) { /* the console's settings on a computer: $PINYOL_HOME, or ~/.pinyol; the browser: its saves' store */
#ifdef __EMSCRIPTEN__
    snprintf(path, n, "/persist/pinyol");
#else
    const char *home = getenv("PINYOL_HOME");
    if (home && *home) snprintf(path, n, "%s", home);
    else if ((home = getenv("HOME")) && *home) snprintf(path, n, "%s/.pinyol", home);
    else return false;
#endif
    mkdir(path, 0755);
    return true;
}
