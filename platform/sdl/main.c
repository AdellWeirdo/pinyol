/* bp_sim: desktop simulator. Same core, same game folder as the console's microSD.
 *   bp_sim [--game DIR] [--saves DIR] [--scale N] [--mute] [--script FILE]
 * Keys: arrows/WASD move, Enter/E/Z = A, Esc/Backspace/X = B, Tab/C = C, I = MENU (bag), J = notebook, P = START.
 * Mouse = touch. Built with Emscripten it is the web player: the game folder is at /game (packed in, or unzipped
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
#elif defined NP2D_GAME /* the build's GAME_DIR */
#define DEFAULT_GAME NP2D_GAME
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
void hal_audio_unlock(void) { if (audio_dev) SDL_UnlockAudioDevice(audio_dev); }

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

static hal_input poll_input(void) {
    SDL_Event e;
    while (SDL_PollEvent(&e))
        if (e.type == SDL_QUIT) closed = true;
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
    win = SDL_CreateWindow("np2d", SDL_WINDOWPOS_CENTERED, SDL_WINDOWPOS_CENTERED, SCREEN_W * scale,
                           SCREEN_H * scale, 0);
    ren = SDL_CreateRenderer(win, -1, SDL_RENDERER_PRESENTVSYNC);
    SDL_SetHint(SDL_HINT_RENDER_SCALE_QUALITY, "0");
    tex = SDL_CreateTexture(ren, SDL_PIXELFORMAT_RGB565, SDL_TEXTUREACCESS_STREAMING, SCREEN_W, SCREEN_H);
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
        audio_dev = SDL_OpenAudioDevice(NULL, 0, &want, NULL, 0);
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
