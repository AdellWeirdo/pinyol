/* Cirera platform (docs/firmware-plan.md): the engine in src/ runs unchanged; this file is its main loop. The
 * console boots into its game list (launcher.c); a game runs at TICK_HZ with a fixed step, one frame drawn every
 * other tick, until its title's "Otros juegos" sends it back. Autotest builds first play the scripts in the flash
 * image (/flash/autotest/<game>/) and log PASS or FAIL. */
#include <dirent.h>
#include <stdarg.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <sys/stat.h>

#include "audio_out.h"
#include "bench.h"
#include "bp.h"
#include "display.h"
#include "esp_app_desc.h"
#include "esp_heap_caps.h"
#include "esp_timer.h"
#include "freertos/FreeRTOS.h"
#include "freertos/semphr.h"
#include "freertos/task.h"
#include "input.h"
#include "cable.h"
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
#ifndef PERF_WINDOW_US
#define PERF_WINDOW_US 5000000 /* a perf line every 5 s (test builds: every second, to see a short test's phases) */
#endif

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

uint32_t hal_micros(void) { return (uint32_t)esp_timer_get_time(); }

/* A game's saves, written by a task a moment after the last store(): on the flash's FAT a save takes most of a
 * second, which the game would spend frozen. The newest text wins; the game's end waits for it (hal.h). */
static SemaphoreHandle_t save_mx, save_write_mx;
static TaskHandle_t saver;
static char *save_txt, save_path[400];
#define SAVE_QUIET_MS 1000

static void save_now(void) {
    xSemaphoreTake(save_write_mx, portMAX_DELAY);
    xSemaphoreTake(save_mx, portMAX_DELAY);
    char *t = save_txt, p[400];
    snprintf(p, sizeof p, "%s", save_path);
    save_txt = NULL;
    xSemaphoreGive(save_mx);
    if (t) {
        int64_t a = esp_timer_get_time();
        if (!save_file_atomic(p, t)) hal_log("saves: %s could not be written", p);
        else hal_log("saves: %u bytes in %.0f ms", (unsigned)strlen(t), (esp_timer_get_time() - a) / 1000.0);
        free(t);
    }
    xSemaphoreGive(save_write_mx);
}

static void saver_task(void *arg) {
    (void)arg;
    for (;;) {
        ulTaskNotifyTake(pdTRUE, portMAX_DELAY);
        while (ulTaskNotifyTake(pdTRUE, pdMS_TO_TICKS(SAVE_QUIET_MS))) { /* until the stores stop for a moment */ }
        save_now();
    }
}

bool hal_save(const char *path, const char *txt) {
    if (!saver) {
        save_mx = xSemaphoreCreateMutex();
        save_write_mx = xSemaphoreCreateMutex();
        if (!save_mx || !save_write_mx || xTaskCreate(saver_task, "saves", 6144, NULL, 2, &saver) != pdPASS) {
            saver = NULL;
            return save_file_atomic(path, txt);
        }
    }
    char *t = strdup(txt);
    if (!t) return save_file_atomic(path, txt);
    xSemaphoreTake(save_mx, portMAX_DELAY);
    free(save_txt);
    save_txt = t;
    snprintf(save_path, sizeof save_path, "%s", path);
    xSemaphoreGive(save_mx);
    xTaskNotifyGive(saver);
    return true;
}

void hal_save_flush(void) {
    if (saver) save_now();
}

/* hal_parallel: the second part runs on core 1, where the audio mixer (higher priority) and the idle game-list
 * presenter live; the caller is the game loop on core 0. */
static TaskHandle_t part1_task, part1_waiter;
static void (*part1_fn)(int, void *);
static void *part1_ctx;

static void part1_loop(void *arg) {
    (void)arg;
    for (;;) {
        ulTaskNotifyTake(pdTRUE, portMAX_DELAY);
        part1_fn(1, part1_ctx);
        xTaskNotifyGive(part1_waiter);
    }
}

void hal_parallel(void (*fn)(int part, void *ctx), void *ctx) {
    if (!part1_task) {
        fn(0, ctx), fn(1, ctx);
        return;
    }
    part1_fn = fn, part1_ctx = ctx, part1_waiter = xTaskGetCurrentTaskHandle();
    xTaskNotifyGive(part1_task);
    fn(0, ctx);
    ulTaskNotifyTake(pdTRUE, portMAX_DELAY);
}

void *hal_realloc_slow(void *p, size_t n) { /* PSRAM: internal RAM is for DMA, strips and the frame's hot data */
    void *q = heap_caps_realloc(p, n, MALLOC_CAP_SPIRAM);
    return q ? q : realloc(p, n);
}

void hal_audio_lock(void) { xSemaphoreTake(audio_mutex, portMAX_DELAY); }
void hal_audio_unlock(void) { xSemaphoreGive(audio_mutex); }
bool hal_can_switch_game(void) { return true; }
void hal_switch_game(void) { switch_req = true; }

/* The console's menu is a pinyol game (firmware/cirera, CONSOLE_MENU_ID): these give it the list (src/lua_console.c). */
static launcher_game games[LAUNCHER_MAX];
static int ngames, played = -1;     /* the list, and the one played last (-1: none yet) */
static bool woke = true;            /* the menu's first run since power-on: it plays its intro */
static char launch_id[32];          /* what the menu chose */
int hal_games(hal_game *g, int max, int *last, bool *cold) {
    int n = ngames < max ? ngames : max;
    for (int i = 0; i < n; i++) {
        g[i] = (hal_game){.flash = !strncmp(games[i].dir, "/flash/", 7), .no_music = games[i].no_music};
        snprintf(g[i].id, sizeof g[i].id, "%s", games[i].id);
        snprintf(g[i].title, sizeof g[i].title, "%s", games[i].title);
        snprintf(g[i].subtitle, sizeof g[i].subtitle, "%s", games[i].subtitle);
    }
    *last = played, *cold = woke;
    return n;
}
bool hal_game_cover(const char *id, uint16_t *px, int w, int h) {
    for (int i = 0; i < ngames; i++)
        if (!strcmp(games[i].id, id)) return console_dir_cover(games[i].dir, px, w, h);
    return false;
}
void hal_launch(const char *id) { snprintf(launch_id, sizeof launch_id, "%s", id); }
void hal_power_off(void) { power_off(); }
const char *hal_firmware(void) { return esp_app_get_description()->version; }

static struct { int64_t world, wait, first, rest; } strip_us; /* where a frame's time goes (perf_report) */

static void perf_report(void) {
    int64_t now = esp_timer_get_time();
    if (now - perf.since < PERF_WINDOW_US || !perf.ticks || !perf.frames) return;
    hal_log("perf: tick %.2f ms, render %.2f ms, present %.2f ms, %.1f fps | audio %.0f%% of a core, %d underruns |"
            " battery %.2f V%s | free internal %u KB, PSRAM %u KB, core 1 stack %u B unused",
            perf.tick / 1000.0 / perf.ticks, perf.render / 1000.0 / perf.frames,
            display_present_us / 1000.0 / perf.frames, perf.frames * 1e6 / (now - perf.since),
            audio_out_blocks ? 100.0 * audio_out_mix_us / (now - perf.since) : 0.0, audio_out_underruns,
            power_volts(), power_usb() ? " (USB)" : "",
            (unsigned)(heap_caps_get_free_size(MALLOC_CAP_INTERNAL) / 1024),
            (unsigned)(heap_caps_get_free_size(MALLOC_CAP_SPIRAM) / 1024),
            part1_task ? (unsigned)uxTaskGetStackHighWaterMark(part1_task) : 0u);
    if (strip_us.first)
        hal_log("frame: world %.2f ms, waiting for the scan %.2f ms, strips %.2f ms (CPU, the DMA overlaps)",
                strip_us.world / 1000.0 / perf.frames, strip_us.wait / 1000.0 / perf.frames,
                (strip_us.first + strip_us.rest) / 1000.0 / perf.frames);
    if (G.v2) { /* a Lua game: where its frames went */
        v2_times t;
        v2_timing(&t);
        hal_log("lua: _update %.2f ms, _draw %.2f ms, picture %.2f ms (longest %.2f), script memory %u KB",
                t.update / 1000.0, t.draw / 1000.0, t.ppu / 1000.0, t.ppu_max / 1000.0, (unsigned)(v2_memory() / 1024));
    }
    strip_us = (typeof(strip_us)){0};
    perf = (typeof(perf)){.since = now};
    display_present_us = 0;
    audio_out_mix_us = 0;
}

/* A panel strip drawn straight from the game: the frame's columns p0..p0+31, turned and byte-swapped for the bus, in
 * internal RAM. The world is already in G.world (draw); no 480x320 frame exists. */
static surface strip_s;
/* The left or the right half of the strip's columns, the whole height: a game's work is rarely even between the top
 * and the bottom of the screen (a sky above, fighters below), and nearly always even between two neighbouring bands
 * of 16 columns. Each half is its own memory in the strip: a column is contiguous on the panel. */
static void strip_half(int part, void *ctx) {
    (void)ctx;
    int w0 = strip_s.w / 2;
    surface half = gfx_clip(&strip_s, strip_s.x0 + (part ? w0 : 0), 0, part ? strip_s.w - w0 : w0, SCREEN_H);
    half.part = (uint8_t)part;
    game_draw(&half, false);
}

static void draw_strip(int p0, uint16_t *out, void *ctx) {
    (void)ctx;
    int64_t a = esp_timer_get_time();
    surface s = gfx_turned(out, p0, 32, SCREEN_W, SCREEN_H, display_flipped(), true); /* the bus sends high bytes first */
    if (G.v2) { /* a Lua game's strip only reads what the frame recorded: both cores draw it, a half each */
        strip_s = s;
        hal_parallel(strip_half, NULL);
    } else {
        game_draw(&s, false);
    }
    *(p0 == 0 ? &strip_us.first : &strip_us.rest) += esp_timer_get_time() - a;
}

#ifdef BP_REMOTE
static bool playing;
/* A remote shot (remote.c): in a game the strips leave no whole frame behind, so one is drawn for it. */
const uint16_t *remote_picture(void) {
    if (!playing) return display_last();
    game_render(frames[0]);
    return frames[0];
}
#endif

static void draw(void) {
    int64_t a = esp_timer_get_time();
    int64_t w = esp_timer_get_time();
    game_draw_world();
    strip_us.world += esp_timer_get_time() - w;
    display_wait(); /* the game list's last frame, if it is still going out */
    w = esp_timer_get_time();
    display_wait_scan();
    strip_us.wait += esp_timer_get_time() - w;
    display_present_strips(draw_strip, NULL);
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
/* -DBP_BENCH=play: the end-to-end tests on the card, /sdcard/pinyol_bench/<game id>.script, each played on
 * /sdcard/games/<game id> for 75 s while perf lines are logged; a restart ends each run and RTC memory says which test
 * is next. Saves go to their own folder, never the game's. */
#include <sys/stat.h>
#include "esp_attr.h"
#include "esp_system.h"
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
#ifdef BP_REMOTE
    playing = true;
#endif
    while (!game_quit_requested() && !switch_req && !cable_wanted()) {
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
#ifdef BP_REMOTE
    playing = false;
#endif
}

static void fatal_screen(void) { /* no card and no flash games: a plain dark red screen, the reason is in the log */
    for (int i = 0; i < SCREEN_W * SCREEN_H; i++) frame[i] = 0x5000;
    display_submit(frame);
}

static bool start_game(const launcher_game *g) {
    static char save_dir[112];
    snprintf(save_dir, sizeof save_dir, "%s/saves", g->dir);
    if (!strncmp(g->dir, "/flash/", 7) && storage_card()) { /* writing the flash stalls both cores for an erase */
        mkdir("/sdcard/saves", 0755);                       /* (~0.3 s): a flash game saves on the card if there is one */
        snprintf(save_dir, sizeof save_dir, "/sdcard/saves/%s", g->id);
    }
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

/* A game coming over the cable: received, the list read again; its index in it, or -1 (said on screen). */
static int receive(launcher_game *games, int *n) {
    char id[32];
    if (!cable_receive(frames[0], id, sizeof id)) {
        launcher_message(frames[0], "El juego no ha llegado entero", -1);
        vTaskDelay(pdMS_TO_TICKS(2000));
        return -1;
    }
    *n = launcher_scan(games, LAUNCHER_MAX);
    for (int k = 0; k < *n; k++)
        if (!strcmp(games[k].id, id)) return k;
    return -1;
}

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
    if (play_magic != 0x6E703264 || esp_reset_reason() != ESP_RST_SW) play_magic = 0x6E703264, play_next = 0;
    static char name[256], src[300], dir[300];
    uint32_t k = 0;
    *name = 0;
    DIR *d = opendir("/sdcard/pinyol_bench");
    for (struct dirent *e; d && (e = readdir(d));) { /* the play_next-th test, in the folder's order */
        size_t n = strlen(e->d_name);
        if (n > 7 && !strcmp(e->d_name + n - 7, ".script") && k++ == play_next) {
            snprintf(name, sizeof name, "%.*s", (int)(n - 7), e->d_name);
            break;
        }
    }
    if (d) closedir(d);
    if (!*name) {
        hal_log(play_next ? "BENCH play done" : "BENCH play: no /sdcard/pinyol_bench/<game id>.script");
        play_magic = 0; /* a reset starts the series again */
        return;
    }
    play_next++;
    const char *path = "/sdcard/pinyol_bench_saves/run.script";
    snprintf(src, sizeof src, "/sdcard/pinyol_bench/%s.script", name);
    snprintf(dir, sizeof dir, "/sdcard/games/%s", name);
    mkdir("/sdcard/pinyol_bench_saves", 0755);
    FILE *in = fopen(src, "r"), *out = fopen(path, "w");
    for (char line[512]; in && out && fgets(line, sizeof line, in);)
        if (strncmp(line, "shot ", 5)) fputs(line, out); /* without "shot" lines, as the autotest images */
    if (in) fclose(in);
    if (!out) return;
    fclose(out);
    bp_config cfg = {dir, "/sdcard/pinyol_bench_saves"};
    if (!game_init(&cfg)) return;
    hal_log("BENCH play %s at %d ticks a frame", name, TICKS_PER_FRAME);
    perf = (typeof(perf)){.since = esp_timer_get_time()};
    play_deadline = esp_timer_get_time() + 75000000;
    script_run(path, script_frame);
    hal_log("BENCH play %s ended before its time", name);
    esp_restart();
}
#endif

#define MENU_FAILED (-10) /* the menu game would not start, or stopped on an error: the list in C from then on */
#define MENU_AGAIN (-11)  /* it ended without choosing (MENU held two seconds): it runs again */
/* The console's menu, a pinyol game: it runs until it launches a game (console_launch) or switches the console off.
 * The index of the game it chose, LAUNCHER_CABLE, MENU_AGAIN or MENU_FAILED. */
static int menu_choose(void) {
    launcher_game m = {0};
    snprintf(m.id, sizeof m.id, "%s", CONSOLE_MENU_ID);
    snprintf(m.dir, sizeof m.dir, "%s", launcher_menu_dir());
    launch_id[0] = 0;
    if (!start_game(&m)) return MENU_FAILED;
    play();
    bool failed = layer_top() == L_ERROR;
    game_shutdown();
    woke = false;
    if (cable_wanted()) return LAUNCHER_CABLE;
    if (failed) {
        hal_log("menu: stopped on an error; the list drawn in C from now on");
        return MENU_FAILED;
    }
    for (int k = 0; k < ngames; k++)
        if (!strcmp(games[k].id, launch_id)) return k;
    return MENU_AGAIN;
}

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
    cable_init(); /* a game sent from pinyol's editor over the USB cable */
#ifdef BP_REMOTE
    remote_init();
#endif
    hal_log("Cirera | PSRAM free %u KB", (unsigned)(heap_caps_get_free_size(MALLOC_CAP_SPIRAM) / 1024));
    int n = ngames = storage_mount() ? launcher_scan(games, LAUNCHER_MAX) : 0;
    bool menu = launcher_menu_dir() != NULL; /* the menu game; without it (or when it fails), the list drawn in C */
    audio_out_init(input_bus());
    launcher_splash(frame, !menu); /* the ink while the rest starts; pinyol's logo too, unless the menu builds it */
    display_present(frame);
    display_backlight(100);
    display_start_task();
    /* hal_parallel: half a game's frame. Above the audio mixer (6) on this core: a strip has the panel's scan to meet,
     * the mixer 70 ms of sound queued (audio_out.c), and a busy song held the strips back a few ms a frame */
    xTaskCreatePinnedToCore(part1_loop, "part1", 6144, NULL, 7, &part1_task, 1);
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
    for (int next = -1;;) { /* next: a game to start without the list, the one that just came over the cable */
        int i = next;
        if (i < 0 && menu) {
            i = menu_choose();
            if (i == MENU_FAILED) menu = false; /* from now on, the list drawn in C */
            if (i == MENU_FAILED || i == MENU_AGAIN) continue;
        } else if (i < 0) {
            i = launcher_choose(frames, games, n);
        }
        next = -1;
        if (i == LAUNCHER_CABLE) {
            next = receive(games, &n);
            ngames = n;
            continue;
        }
        if (i < 0) power_off();
        played = i;
        if (!start_game(&games[i])) { /* a broken folder: said on screen, then the list again */
            launcher_message(frames[0], "No se puede abrir este juego", -1);
            vTaskDelay(pdMS_TO_TICKS(2000));
            continue;
        }
        play();
        game_shutdown();
        if (cable_wanted()) next = receive(games, &n), ngames = n;
    }
}
