/* -DBP_BENCH=ppu: the REAL ppu_render (src/ppu.c) on the board, serial on core 0 (hal_parallel runs both halves in turn
 * while part1 is not started), one 240x160 frame at a time. The scenes, content and per-frame animation are those of
 * the host harness, so the FNV-1a hash of frames 0..119 must equal the host's: the same pixels from the same code.
 * Lines start with "BENCH ppu". Cycles at 240 MHz; 4.0 M cycles = one core for a 60 fps frame. */
#include "bench.h"

#include <stdio.h>
#include <stdlib.h>
#include <string.h>

#include "esp_cpu.h"
#include "esp_heap_caps.h"
#include "freertos/FreeRTOS.h"
#include "freertos/task.h"
#include "ppu.h"
#include "sdkconfig.h"

#define LOG(...) (printf("BENCH ppu " __VA_ARGS__), putchar('\n'))

#define MAP 64
#define NTILES 1024
#define NSPR 128
#define WARMUP 50
#define HASH_FRAMES 120
#define TIMED 300

static uint32_t rng = 12345;
static uint32_t rnd(void) { return rng = rng * 1664525 + 1013904223; }

static uint8_t *tiles;     /* NTILES * 64, 8 bpp index tiles */
static uint16_t *tilerows; /* NTILES */
static uint16_t *maps;     /* 4 * MAP * MAP */
static uint8_t *spr;       /* 32 * 256 */
static uint8_t *atiles;    /* 256 * 64 */
static uint16_t *amap;     /* MAP * MAP */
static ppu_line_affine *aline;
static uint16_t *frame;
static uint32_t caps;      /* where the content lives: internal RAM or PSRAM; the frame is always internal */

static bool alloc_all(uint32_t c) {
    caps = c;
    tiles = heap_caps_malloc(NTILES * 64, c | MALLOC_CAP_8BIT);
    tilerows = heap_caps_malloc(NTILES * 2, c | MALLOC_CAP_8BIT);
    maps = heap_caps_malloc(4 * MAP * MAP * 2, c | MALLOC_CAP_8BIT);
    spr = heap_caps_malloc(32 * 256, c | MALLOC_CAP_8BIT);
    atiles = heap_caps_malloc(256 * 64, c | MALLOC_CAP_8BIT);
    amap = heap_caps_malloc(MAP * MAP * 2, c | MALLOC_CAP_8BIT);
    aline = heap_caps_malloc(PPU_H * sizeof *aline, MALLOC_CAP_INTERNAL | MALLOC_CAP_8BIT);
    frame = heap_caps_malloc(PPU_W * PPU_H * 2, MALLOC_CAP_INTERNAL | MALLOC_CAP_8BIT);
    return tiles && tilerows && maps && spr && atiles && amap && aline && frame;
}

static void free_all(void) {
    heap_caps_free(tiles), heap_caps_free(tilerows), heap_caps_free(maps), heap_caps_free(spr);
    heap_caps_free(atiles), heap_caps_free(amap), heap_caps_free(aline), heap_caps_free(frame);
    tiles = NULL, tilerows = NULL, maps = NULL, spr = NULL, atiles = NULL, amap = NULL, aline = NULL, frame = NULL;
}

static void make_content(void) {
    rng = 12345;
    for (int t = 0; t < NTILES; t++)
        for (int r = 0; r < 8; r++)
            for (int k = 0; k < 8; k++) {
                int c = t == 0 ? 0 : ((k + r + t) % 5 == 0 ? 0 : 1 + (t + k * 3 + r) % 15);
                tiles[t * 64 + r * 8 + k] = (uint8_t)c;
            }
    ppu_tile_rows(tiles, NTILES, tilerows);
    for (int l = 0; l < 4; l++)
        for (int i = 0; i < MAP * MAP; i++) {
            uint16_t t = (uint16_t)(rnd() % 1024);
            if (l > 0 && rnd() % 3 == 0) t = 0;
            maps[l * MAP * MAP + i] = (uint16_t)(t | (rnd() & 0x0C00) | ((l * 4 + rnd() % 4) << 12));
        }
    for (int s = 0; s < 32; s++)
        for (int y = 0; y < 16; y++)
            for (int x = 0; x < 16; x++) {
                int dx = 2 * x - 15, dy = 2 * y - 15;
                spr[s * 256 + y * 16 + x] = (uint8_t)(dx * dx + dy * dy < 200 ? 1 + (s + x / 4) % 15 : 0);
            }
    for (int i = 0; i < MAP * MAP; i++) amap[i] = (uint16_t)(1 + (i * 7 + i / MAP) % 255);
    for (int t = 0; t < 256; t++)
        for (int p = 0; p < 64; p++) atiles[t * 64 + p] = (uint8_t)(t == 0 ? 0 : 128 + ((t + p / 8 + p % 8) % 120));
}

static void set_palettes(void) {
    for (int i = 0; i < 256; i++) {
        uint16_t c = (uint16_t)(((i * 7) & 31) << 11 | ((i * 3) & 63) << 5 | ((255 - i) & 31));
        PPU.bg_pal[i] = c;
        PPU.obj_pal[i] = (uint16_t)(c ^ 0x2108);
    }
}

typedef struct {
    const char *name;
    int layers, sprites;
    bool affine, alpha, window, half_blend, offscreen;
    int line_pals; /* entries replaced on every line, in each palette (line_pal), 0: none */
} scene;

static EXT_RAM_BSS_ATTR ppu_line_pal lpal_bg[PPU_H], lpal_obj[PPU_H]; /* in PSRAM, as the engine's own line tables */

static void setup(const scene *s) {
    ppu_reset();
    set_palettes();
    if (s->line_pals) { /* the cost of a palette changed on every line, as a sky gradient does */
        for (int y = 0; y < PPU_H; y++) {
            lpal_bg[y].n = lpal_obj[y].n = (uint8_t)s->line_pals;
            for (int i = 0; i < s->line_pals; i++) {
                lpal_bg[y].idx[i] = lpal_obj[y].idx[i] = (uint8_t)(1 + i);
                lpal_bg[y].col[i] = (uint16_t)(y * 257 + i * 31), lpal_obj[y].col[i] = (uint16_t)(y * 131 + i * 17);
            }
        }
        PPU.line.pal_bg = lpal_bg, PPU.line.pal_obj = lpal_obj;
    }
    for (int l = 0; l < s->layers; l++)
        PPU.bg[l] = (ppu_bg){.mode = BG_TILES, .prio = (uint8_t)l, .wrap = true, .tiles = tiles, .ntiles = NTILES,
                             .rows = tilerows, .map = maps + l * MAP * MAP, .map_w = MAP, .map_h = MAP,
                             .scroll_x = 13 * l, .scroll_y = 7 * l};
    if (s->affine) {
        PPU.bg[3] = (ppu_bg){.mode = BG_AFFINE, .prio = 3, .wrap = true, .tiles = atiles, .ntiles = 256, .map = amap,
                             .map_w = MAP, .map_h = MAP};
        PPU.line.affine[3] = aline;
    }
    for (int i = 0; i < s->sprites; i++)
        PPU.obj[i] = (ppu_obj){.on = true, .w = 16, .h = 16, .prio = 0, .bank = (uint8_t)(i % 16), .affine = -1,
                               .hflip = i & 1, .mode = (s->half_blend && (i & 1)) ? OBJ_BLEND : OBJ_NORMAL,
                               .idx = spr + (i % 32) * 256};
    if (s->alpha) {
        PPU.fx.mode = FX_ALPHA;
        PPU.fx.first = PPU_BG0;
        PPU.fx.second = PPU_BG1 | PPU_BG2 | PPU_BG3 | PPU_BACK;
        PPU.fx.eva = 10, PPU.fx.evb = 6;
    }
    if (s->half_blend) {
        PPU.fx.second = PPU_BG0 | PPU_BG1 | PPU_BG2 | PPU_BG3 | PPU_BACK;
        PPU.fx.eva = 8, PPU.fx.evb = 8;
    }
    if (s->window) {
        PPU.win.on[0] = PPU.win.on[1] = true;
        PPU.win.rect[0] = (ppu_rect){40, 200, 20, 140};
        PPU.win.rect[1] = (ppu_rect){100, 140, 0, 160};
        PPU.win.in[0] = PPU_BG0 | PPU_BG1 | PPU_BG2 | PPU_BG3 | PPU_OBJ | PPU_FX;
        PPU.win.in[1] = PPU_BG0 | PPU_BG2 | PPU_FX;
        PPU.win.out = PPU_BG1 | PPU_BG2 | PPU_BG3 | PPU_OBJ;
    }
}

static void animate(const scene *s, int n) {
    for (int l = 0; l < s->layers; l++) PPU.bg[l].scroll_x = n * (l + 1) + 13 * l, PPU.bg[l].scroll_y = n * l / 2 + 7 * l;
    for (int i = 0; i < s->sprites; i++) {
        uint32_t h = (uint32_t)i * 2654435761u;
        PPU.obj[i].x = (int16_t)((h % 260 + n * (1 + i % 3)) % 260 - 10);
        PPU.obj[i].y = (int16_t)((h / 260 % 180 + n * (i % 2)) % 180 - 10);
        if (s->offscreen) PPU.obj[i].y = -100;
    }
    if (s->affine) {
        int32_t ca = 256, sa = (n * 3) % 256 - 128;
        for (int y = 0; y < PPU_H; y++) {
            int32_t lam = (64 * 256) / (y + 16);
            int32_t pa = lam * ca >> 8, pc = lam * sa >> 8;
            aline[y] = (ppu_line_affine){.pa = pa, .pc = pc, .x = (n << 10) - pa * (PPU_W / 2), .y = (lam * 64) - pc * (PPU_W / 2)};
        }
    }
}

static uint64_t fnv(uint64_t h, const void *p, size_t n) {
    const uint8_t *b = p;
    for (size_t i = 0; i < n; i++) h = (h ^ b[i]) * 1099511628211ULL;
    return h;
}

static int cmp(const void *a, const void *b) {
    uint32_t x = *(const uint32_t *)a, y = *(const uint32_t *)b;
    return (x > y) - (x < y);
}

static void run_scene(const scene *s, const char *where) {
    static uint32_t t[TIMED];
    setup(s);
    uint64_t hh = 14695981039346656037ULL;
    for (int n = -WARMUP; n < HASH_FRAMES; n++) {
        animate(s, n < 0 ? 0 : n);
        uint32_t a = esp_cpu_get_cycle_count();
        ppu_render(frame);
        uint32_t c = esp_cpu_get_cycle_count() - a;
        if (n >= 0) hh = fnv(hh, frame, PPU_W * PPU_H * 2);
        (void)c;
        if (!(n & 15)) vTaskDelay(1); /* let the idle task and watchdog run */
    }
    for (int n = 0; n < TIMED; n++) {
        animate(s, n);
        uint32_t a = esp_cpu_get_cycle_count();
        ppu_render(frame);
        t[n] = esp_cpu_get_cycle_count() - a;
        if (!(n & 31)) vTaskDelay(1); /* outside the timed region: a tick can only land in a few frames, the median ignores it */
    }
    uint32_t mn = UINT32_MAX;
    for (int n = 0; n < TIMED; n++) if (t[n] < mn) mn = t[n];
    qsort(t, TIMED, sizeof *t, cmp);
    LOG("SCENE|%s|%s|median_cyc=%u|min_cyc=%u|p95_cyc=%u|median_us=%.1f|core%%=%.1f|hash=%016llx", where, s->name,
        (unsigned)t[TIMED / 2], (unsigned)mn, (unsigned)t[TIMED * 95 / 100], t[TIMED / 2] / 240.0,
        100.0 * t[TIMED / 2] / 4000000.0, (unsigned long long)hh);
}

static const scene SCENES[] = {
    {"clear only", 0, 0, false, false, false, false, false, 0},
    {"1 layer", 1, 0, false, false, false, false, false, 0},
    {"4 layers", 4, 0, false, false, false, false, false, 0},
    {"128 sprites 16x16", 0, 128, false, false, false, false, false, 0},
    {"1 affine layer", 0, 0, true, false, false, false, false, 0},
    {"light: 2L+32 spr", 2, 32, false, false, false, false, false, 0},
    {"GBA mode 0: 4L+128 spr", 4, 128, false, false, false, false, false, 0},
    {"Mode 7: aff+1L+64 spr", 1, 64, true, false, false, false, false, 0},
    {"Max: aff+3L+128 spr", 3, 128, true, false, false, false, false, 0},
    {"FX: 4L+alpha+window", 4, 0, false, true, true, false, false, 0},
    {"FX: 128 spr half OBJ_BLEND", 0, 128, false, false, false, true, false, 0},
    {"x: 4L+alpha only", 4, 0, false, true, false, false, false, 0},
    {"x: 4L+window only", 4, 0, false, false, true, false, false, 0},
    {"x: 4L+128 spr half OBJ_BLEND", 4, 128, false, false, false, true, false, 0},
    {"x: 128 sprites off-screen", 0, 128, false, false, false, false, true, 0},
    {"x: 1 layer, 1 palette entry on every line", 1, 0, false, false, false, false, false, 1},
    {"x: 4L+128 spr, 8+8 palette entries on every line", 4, 128, false, false, false, false, false, 8},
};

void bench_ppu_run(void) {
    vTaskDelay(pdMS_TO_TICKS(4000)); /* time for the USB log to be reopened after the flash's reset */
    LOG("start | CPU %d MHz | free internal %u KB (largest block %u KB), PSRAM %u KB", CONFIG_ESP_DEFAULT_CPU_FREQ_MHZ,
        (unsigned)(heap_caps_get_free_size(MALLOC_CAP_INTERNAL) / 1024),
        (unsigned)(heap_caps_get_largest_free_block(MALLOC_CAP_INTERNAL) / 1024),
        (unsigned)(heap_caps_get_free_size(MALLOC_CAP_SPIRAM) / 1024));
    for (int pass = 0; pass < 2; pass++) {
        const char *where = pass == 0 ? "content-internal" : "content-psram";
        if (!alloc_all(pass == 0 ? MALLOC_CAP_INTERNAL : MALLOC_CAP_SPIRAM)) {
            LOG("%s: allocation failed (free internal %u KB, largest %u KB), skipped", where,
                (unsigned)(heap_caps_get_free_size(MALLOC_CAP_INTERNAL) / 1024),
                (unsigned)(heap_caps_get_largest_free_block(MALLOC_CAP_INTERNAL) / 1024));
            free_all();
            continue;
        }
        make_content();
        LOG("%s: content placed, free internal now %u KB", where, (unsigned)(heap_caps_get_free_size(MALLOC_CAP_INTERNAL) / 1024));
        for (size_t i = 0; i < sizeof SCENES / sizeof *SCENES; i++) run_scene(&SCENES[i], where);
        free_all();
    }
    LOG("done");
}
