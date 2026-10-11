/* ConsolaS3 platform (docs/firmware-plan.md): the engine in src/ runs unchanged; this file is its main loop. The
 * console boots into its game list (launcher.c); a game runs at TICK_HZ with a fixed step, one frame drawn every
 * other tick, until its title's "Otros juegos" sends it back. Autotest builds first play the scripts in the flash
 * image (/flash/autotest/<game>/) and log PASS or FAIL. */
#include <dirent.h>
#include <stdarg.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>

#include "audio_out.h"
#include "bench.h"
#include "bp.h"
#include "display.h"
#include "esp_heap_caps.h"
#include "esp_timer.h"
#include "freertos/FreeRTOS.h"
#include "freertos/semphr.h"
#include "freertos/task.h"
#include "input.h"
#include "launcher.h"
#include "ota.h"
#include "remote.h"
#include "power.h"
#include "sd.h"

#define PANEL_HZ (80 * 1000 * 1000) /* clean on the board, 12.3 ms a frame (F1) */
#define TICK_US (1000000 / TICK_HZ)
#define SLOW_TICK_US 40000 /* worth a log line: zone loads, card stalls */
#ifndef TICKS_PER_FRAME /* -DBP_FRAME_TICKS=2: a frame every other tick, 30 fps */
#define TICKS_PER_FRAME 1  /* 60 fps: a frame every tick; a slow one makes the next ticks catch up (play) */
#endif
#define SLOW_RENDER_US 17000 /* longer than a 60 fps frame: drawn and sent */

static SemaphoreHandle_t audio_mutex;
static uint16_t *frames[2], *frame; /* drawn into one while the other is on its way to the panel */
static struct { int64_t tick, render, present, since; int ticks, frames; } perf;
static volatile bool switch_req; /* "Otros juegos": back to the list once the tick ends */

void hal_log(const char *fmt, ...) {
    va_list ap;
    va_start(ap, fmt);
    vprintf(fmt, ap);
    va_end(ap);
    putchar('\n');
}

void hal_audio_lock(void) { xSemaphoreTake(audio_mutex, portMAX_DELAY); }
void hal_audio_unlock(void) { xSemaphoreGive(audio_mutex); }
bool hal_can_switch_game(void) { return true; }
void hal_switch_game(void) { switch_req = true; }

static struct { int64_t first, rest; } strip_us; /* where the strips' time goes (perf_report) */

static void perf_report(void) {
    int64_t now = esp_timer_get_time();
    if (now - perf.since < 5000000 || !perf.ticks || !perf.frames) return;
    hal_log("perf: tick %.2f ms, render %.2f ms, present %.2f ms, %.1f fps | audio %.0f%% of a core, %d underruns |"
            " battery %.2f V%s | free internal %u KB, PSRAM %u KB",
            perf.tick / 1000.0 / perf.ticks, perf.render / 1000.0 / perf.frames,
            display_present_us / 1000.0 / perf.frames, perf.frames * 1e6 / (now - perf.since),
            audio_out_blocks ? 100.0 * audio_out_mix_us / (now - perf.since) : 0.0, audio_out_underruns,
            power_volts(), power_usb() ? " (USB)" : "",
            (unsigned)(heap_caps_get_free_size(MALLOC_CAP_INTERNAL) / 1024),
            (unsigned)(heap_caps_get_free_size(MALLOC_CAP_SPIRAM) / 1024));
    if (strip_us.first)
        hal_log("strips: first (with the world) %.2f ms, other 14 %.2f ms a frame", strip_us.first / 1000.0 / perf.frames,
                strip_us.rest / 1000.0 / perf.frames);
    strip_us.first = strip_us.rest = 0;
    perf = (typeof(perf)){.since = now};
    display_present_us = 0;
    audio_out_mix_us = 0;
}

/* A panel strip drawn straight from the game: the frame's columns p0..p0+31, turned and byte-swapped for the bus, in
 * internal RAM. The world is drawn into G.world with the first strip; no 480x320 frame exists. */
static void draw_strip(int p0, uint16_t *out, void *ctx) {
    (void)ctx;
    int64_t a = esp_timer_get_time();
    surface s = gfx_turned(out, p0, 32, SCREEN_W, SCREEN_H, display_flipped(), true); /* the bus sends high bytes first */
    game_draw(&s, p0 == 0);
    *(p0 == 0 ? &strip_us.first : &strip_us.rest) += esp_timer_get_time() - a;
}

static void draw(void) {
    int64_t a = esp_timer_get_time();
#ifdef BP_REMOTE /* remote screenshots read a whole frame: draw one and hand it to the presenting task, as before */
    static int cur;
    frame = frames[cur];
    game_render(frame);
    display_submit(frame);
    cur ^= 1;
#else
    display_wait(); /* the game list's last frame, if it is still going out */
    display_present_strips(draw_strip, NULL);
#endif
    int64_t us = esp_timer_get_time() - a;
    if (us > SLOW_RENDER_US) /* which screen is expensive: the layer stack, bottom first (layer_id in bp.h) */
        hal_log("slow frame: %.0f ms, layers %d %d %d %d (%s)", us / 1000.0, G.nstack > 0 ? G.stack[0] : -1,
                G.nstack > 1 ? G.stack[1] : -1, G.nstack > 2 ? G.stack[2] : -1, G.nstack > 3 ? G.stack[3] : -1, G.zone.id);
    perf.render += us;
    perf.frames++;
}

static void tick(const hal_input *in) {
    int64_t a = esp_timer_get_time();
    game_tick(in);
    int64_t us = esp_timer_get_time() - a;
    if (us > SLOW_TICK_US) hal_log("slow tick: %.0f ms in %s", us / 1000.0, G.zone.id);
    perf.tick += us;
    perf.ticks++;
}

#ifdef BP_BENCH_PLAY
/* -DBP_BENCH=play: each game's end-to-end test, read from the card, plays for 75 s while perf lines are logged; a
 * restart ends each run and RTC memory says which game is next. Saves go to their own folder, never the game's. */
#include <sys/stat.h>
#include "esp_attr.h"
#include "esp_system.h"
extern const char e2e_bajopueblo[] asm("_binary_e2e_full_script_start");
extern const char e2e_geumgye[] asm("_binary_e2e_lectura_script_start");
static RTC_NOINIT_ATTR uint32_t play_next, play_magic;
static int64_t play_deadline;
#endif

/* script_run() ticks the game itself; this is its per-tick hook: show every other tick, let the idle task in. */
static void script_frame(void) {
    static unsigned n;
    static int64_t last_end;
    int64_t start = esp_timer_get_time();
    if (last_end) { /* what ran since the last hook is the game's tick */
        int64_t us = start - last_end;
        if (us > SLOW_TICK_US) hal_log("slow tick: %.0f ms in %s", us / 1000.0, G.zone.id);
        perf.tick += us;
        perf.ticks++;
    }
    if (n++ % TICKS_PER_FRAME == 0) draw();
    if (n % 32 == 0) vTaskDelay(1);
#ifdef BP_BENCH_PLAY
    if (play_deadline && esp_timer_get_time() > play_deadline) esp_restart(); /* this game's measuring time is up */
#endif
    perf_report();
    last_end = esp_timer_get_time();
}

static void play(void) {
    hal_input in = {0}, was = {0};
    int64_t next = esp_timer_get_time();
    int since_draw = TICKS_PER_FRAME;
    while (!game_quit_requested() && !switch_req) {
        if (power_critical()) { /* the battery is nearly flat: keep the game, then sleep */
            hal_log("power: battery critical (%.2f V)", power_volts());
            if (layer_top() == L_PLAY) save_write("auto");
            power_off();
        }
        int64_t now = esp_timer_get_time();
        if (now < next) {
            vTaskDelay(1);
            continue;
        }
        for (int steps = 0; now >= next && steps < 4; steps++, next += TICK_US) {
            in = input_poll();
            if (in.held != was.held || in.touch != was.touch) /* F3: every change, to check the wiring */
                hal_log("input: buttons 0x%03x, touch %s (%d, %d)", in.held, in.touch ? "down" : "up", in.px, in.py);
            was = in;
            tick(&in);
            since_draw++;
        }
        if (now - next > 250000) next = now; /* after a long stall, do not run to catch up */
        if (since_draw >= TICKS_PER_FRAME) { /* counted in ticks: a time threshold misses by a microsecond */
            since_draw = 0;
            draw();
        }
        perf_report();
    }
}

static void fatal_screen(void) { /* no card and no flash games: a plain dark red screen, the reason is in the log */
    for (int i = 0; i < SCREEN_W * SCREEN_H; i++) frame[i] = 0x5000;
    display_submit(frame);
}

static bool start_game(const launcher_game *g) {
    static char save_dir[112];
    snprintf(save_dir, sizeof save_dir, "%s/saves", g->dir);
    bp_config cfg = {g->dir, save_dir}; /* both outlive the game: the list is static */
    int64_t t0 = esp_timer_get_time();
    switch_req = false;
    if (!game_init(&cfg)) {
        hal_log("%s: game_init failed, back to the list", g->id);
        game_shutdown();
        return false;
    }
    hal_log("%s: game_init %.0f ms | free internal %u KB, PSRAM %u KB", g->id, (esp_timer_get_time() - t0) / 1000.0,
            (unsigned)(heap_caps_get_free_size(MALLOC_CAP_INTERNAL) / 1024),
            (unsigned)(heap_caps_get_free_size(MALLOC_CAP_SPIRAM) / 1024));
    perf = (typeof(perf)){.since = esp_timer_get_time()};
    return true;
}

static int by_name(const void *a, const void *b) { return strcmp(a, b); }

/* Autotest builds: every game's scripts in turn, each on a fresh game_init; with /flash/autotest/loop (BP_SOAK)
 * all of it again while everything passes, the heap logged after each script. */
static void run_tests(const launcher_game *g, int n) {
    int last_underruns = audio_out_underruns;
    FILE *loop = fopen("/flash/autotest/loop", "r");
    if (loop) fclose(loop);
    for (int run = 1;; run++) {
        int ran = 0, failed = 0;
        for (int i = 0; i < n; i++) {
            char dir[64], names[8][48];
            snprintf(dir, sizeof dir, "/flash/autotest/%s", g[i].id);
            DIR *d = opendir(dir);
            int k = 0;
            for (struct dirent *e; d && (e = readdir(d));)
                if (strstr(e->d_name, ".script") && (k < 8 || (hal_log("autotest: %s left out (8 per game)", e->d_name), 0)))
                    snprintf(names[k++], sizeof names[0], "%s", e->d_name);
            if (d) closedir(d);
            qsort(names, (size_t)k, sizeof names[0], by_name);
            for (int j = 0; j < k; j++) {
                char path[128];
                snprintf(path, sizeof path, "%s/%s", dir, names[j]);
                if (!start_game(&g[i])) {
                    failed++;
                    continue;
                }
                int64_t s0 = esp_timer_get_time();
                int u0 = audio_out_underruns, rc = script_run(path, script_frame), u1 = audio_out_underruns;
                game_shutdown();
                ran++;
                failed += rc != 0;
                hal_log("AUTOTEST %s %s/%s in %.1f s (run %d) | underruns %d in play, %d loading | free internal %u KB, "
                        "PSRAM %u KB, largest PSRAM block %u KB",
                        rc == 0 ? "PASS" : "FAIL", g[i].id, names[j], (esp_timer_get_time() - s0) / 1e6, run, u1 - u0,
                        u0 - last_underruns, /* the last game's shutdown and this one's game_init */
                        (unsigned)(heap_caps_get_free_size(MALLOC_CAP_INTERNAL) / 1024),
                        (unsigned)(heap_caps_get_free_size(MALLOC_CAP_SPIRAM) / 1024),
                        (unsigned)(heap_caps_get_largest_free_block(MALLOC_CAP_SPIRAM) / 1024));
                last_underruns = u1;
            }
        }
        if (!ran || failed || !loop) return;
    }
}

#ifdef BP_BENCH_PLAY
static void bench_play(void) {
    static const struct { const char *dir, *script, *name; } runs[] = {
        {"/sdcard/games/bajopueblo", e2e_bajopueblo, "e2e_full"}, {"/sdcard/games/geumgye", e2e_geumgye, "e2e_lectura"}};
    if (play_magic != 0x6E703264 || esp_reset_reason() != ESP_RST_SW) play_magic = 0x6E703264, play_next = 0;
    if (play_next >= sizeof runs / sizeof runs[0]) {
        hal_log("BENCH play done");
        play_magic = 0; /* a reset starts the series again */
        return;
    }
    int i = (int)play_next++;
    mkdir("/sdcard/np2d_bench", 0755);
    mkdir("/sdcard/np2d_bench_saves", 0755);
    char path[96];
    snprintf(path, sizeof path, "/sdcard/np2d_bench/%s.script", runs[i].name);
    FILE *f = fopen(path, "w");
    if (!f) return;
    for (const char *l = runs[i].script; *l;) { /* without "shot" lines, as the autotest images */
        const char *e = strchr(l, '\n');
        size_t n = e ? (size_t)(e - l + 1) : strlen(l);
        if (strncmp(l, "shot ", 5)) fwrite(l, 1, n, f);
        l += n;
    }
    fclose(f);
    bp_config cfg = {runs[i].dir, "/sdcard/np2d_bench_saves"};
    if (!game_init(&cfg)) return;
    hal_log("BENCH play %s at %d ticks a frame", runs[i].name, TICKS_PER_FRAME);
    perf = (typeof(perf)){.since = esp_timer_get_time()};
    play_deadline = esp_timer_get_time() + 75000000;
    script_run(path, script_frame);
    hal_log("BENCH play %s ended before its time", runs[i].name);
    esp_restart();
}
#endif

void app_main(void) {
    audio_mutex = xSemaphoreCreateMutex();
    for (int i = 0; i < 2; i++) frames[i] = heap_caps_malloc(SCREEN_W * SCREEN_H * 2, MALLOC_CAP_SPIRAM);
    frame = frames[0];
    display_init(PANEL_HZ, false);
    power_init();
    input_init();
#if defined(BP_BENCH) && !defined(BP_BENCH_PLAY) /* the play bench runs the console as usual (bench_play) */
    display_backlight(100);
#ifdef BP_BENCH_V1
    bench_v1_run();
#else
    bench_run();
#endif
    for (;;) vTaskDelay(portMAX_DELAY); /* the last frame stays on screen */
#endif
#ifdef BP_REMOTE
    remote_init();
#endif
    hal_log("ConsolaS3 | PSRAM free %u KB", (unsigned)(heap_caps_get_free_size(MALLOC_CAP_SPIRAM) / 1024));
    static launcher_game games[LAUNCHER_MAX];
    int n = storage_mount() ? launcher_scan(games, LAUNCHER_MAX) : 0;
    audio_out_init(input_bus());
    for (int i = 0; i < SCREEN_W * SCREEN_H; i++) frame[i] = D_INK; /* the list's background, before the light */
    display_present(frame);
    display_backlight(100);
    display_start_task();
    ota_from_card(frames[1]); /* a card with only firmware.bin on it still updates the console */
    if (!n) {
        fatal_screen();
        return; /* not marked good: a new firmware that finds no games goes back to the previous one */
    }
    ota_mark_good(); /* storage, screen, sound and the game list are up: this firmware works */
#ifdef BP_BENCH_PLAY
    bench_play();
    for (;;) vTaskDelay(portMAX_DELAY);
#endif
    run_tests(games, n);
    for (;;) {
        int i = launcher_choose(frames, games, n);
        if (i < 0) power_off();
        if (!start_game(&games[i])) { /* a broken folder: said on screen, then the list again */
            launcher_message(frames[0], "No se puede abrir este juego", -1);
            vTaskDelay(pdMS_TO_TICKS(2000));
            continue;
        }
        play();
        game_shutdown();
    }
}
