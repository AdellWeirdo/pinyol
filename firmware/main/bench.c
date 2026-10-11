/* Phase 0 of the v2 plan (a GBA-like virtual PPU): what each piece of a software tile/sprite renderer costs on this
 * board. Built with -DBP_BENCH=ON instead of the game list; results go to the USB log as "BENCH ..." lines. The kernels
 * are plain, reasonably tight C: the baseline a real renderer has to match or beat, not the renderer itself.
 * Logical frame: 240x160, 8-bit palette indices, drawn line by line; the output stage scales it 2x, turns it to panel
 * rows and swaps bytes in one pass while the strips go out by DMA. */
#include "bench.h"

#include <dirent.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <sys/stat.h>

#include "display.h"
#include "driver/gpio.h"
#include "esp_cpu.h"
#include "esp_heap_caps.h"
#include "esp_memory_utils.h"
#include "esp_timer.h"
#include "freertos/FreeRTOS.h"
#include "freertos/semphr.h"
#include "freertos/task.h"
#include "sd.h"
#include "sdkconfig.h"

#define LW 240
#define LH 160
#define PANEL_W 320
#define STRIP 32
#define PIN_TE 42
#define NSPR 128
#define MAP 64 /* regular maps: 64x64 tiles of 8x8, wrapping */
#define AMAP 64 /* affine map: 64x64 tiles, 8 bpp */

#define LOG(...) (printf("BENCH " __VA_ARGS__), putchar('\n'))

typedef struct {
    const uint8_t *tiles; /* 4 bpp, 32 bytes a tile, left pixel in the low nibble (as the GBA) */
    const uint16_t *map;  /* GBA text entries: tile 0-9, hflip 10, vflip 11, palette bank 12-15 */
    int sx, sy;
} layer;

typedef struct {
    int16_t x, y;
    uint8_t bank, hflip;
    const uint8_t *tiles; /* 16x16 at 4 bpp: 8 bytes a row */
} sprite;

typedef struct {
    const uint8_t *map, *tiles; /* 8 bpp tiles, 64 bytes each */
    int32_t pa[LH], pc[LH], x0[LH], y0[LH]; /* per line: step per pixel and start, 24.8 fixed point */
} affine;

static uint8_t *idx[2];        /* logical frames, internal RAM */
static uint16_t pal[256];      /* RGB565, already byte-swapped for the bus */
static layer bg[4];
static sprite oam[NSPR];
static affine *aff;
static int nlayers, nsprites;
static bool use_affine;

static void *ialloc(size_t n) { /* internal RAM, or the test cannot say what it claims to measure */
    void *p = heap_caps_malloc(n, MALLOC_CAP_INTERNAL | MALLOC_CAP_8BIT);
    if (!p) LOG("out of internal RAM for %u bytes (largest block %u)", (unsigned)n,
                (unsigned)heap_caps_get_largest_free_block(MALLOC_CAP_INTERNAL));
    return p;
}

/* ------------------------------------------------------------------ kernels: one logical line each */

static inline void put_row4(uint8_t *out, int x, uint32_t row, uint8_t bank, bool hflip) {
    if (x >= 0 && x <= LW - 8) { /* whole tile on screen: no clipping per pixel */
        if (hflip)
            for (int k = 7; k >= 0; k--, row >>= 4) { uint8_t c = row & 15; if (c) out[x + k] = bank | c; }
        else
            for (int k = 0; k < 8; k++, row >>= 4) { uint8_t c = row & 15; if (c) out[x + k] = bank | c; }
        return;
    }
    for (int k = 0; k < 8; k++, row >>= 4) {
        int px = x + (hflip ? 7 - k : k);
        uint8_t c = row & 15;
        if (c && (unsigned)px < LW) out[px] = bank | c;
    }
}

static void layer_line(const layer *L, int y, uint8_t *out) {
    int wy = (y + L->sy) & (MAP * 8 - 1), fy = wy & 7, wx = L->sx & (MAP * 8 - 1);
    const uint16_t *mrow = L->map + (wy >> 3) * MAP;
    int tx = wx >> 3;
    for (int x = -(wx & 7); x < LW; x += 8, tx = (tx + 1) & (MAP - 1)) {
        uint16_t e = mrow[tx];
        uint32_t row = ((const uint32_t *)(L->tiles + (e & 0x3FF) * 32))[(e & 0x800) ? 7 - fy : fy];
        if (row) put_row4(out, x, row, (uint8_t)((e >> 8) & 0xF0), e & 0x400);
    }
}

static void sprites_line(int y, uint8_t *out) {
    for (int i = nsprites - 1; i >= 0; i--) { /* lower index on top, as OAM */
        const sprite *s = &oam[i];
        int r = y - s->y;
        if ((unsigned)r >= 16) continue;
        const uint32_t *row = (const uint32_t *)(s->tiles + r * 8);
        if (s->hflip) {
            put_row4(out, s->x + 8, row[0], s->bank, true);
            put_row4(out, s->x, row[1], s->bank, true);
        } else {
            put_row4(out, s->x, row[0], s->bank, false);
            put_row4(out, s->x + 8, row[1], s->bank, false);
        }
    }
}

static void affine_line(int y, uint8_t *out) {
    int32_t px = aff->x0[y], py = aff->y0[y], pa = aff->pa[y], pc = aff->pc[y];
    for (int x = 0; x < LW; x++, px += pa, py += pc) {
        unsigned u = (unsigned)(px >> 8) & (AMAP * 8 - 1), v = (unsigned)(py >> 8) & (AMAP * 8 - 1);
        uint8_t c = aff->tiles[aff->map[(v >> 3) * AMAP + (u >> 3)] * 64 + (v & 7) * 8 + (u & 7)];
        if (c) out[x] = c;
    }
}

/* One logical frame, back to front: the affine floor, then the regular layers, then the sprites. */
static void render(uint8_t *frame) {
    for (int y = 0; y < LH; y++) {
        uint8_t *out = frame + y * LW;
        memset(out, 0, LW);
        if (use_affine) affine_line(y, out);
        for (int l = nlayers - 1; l >= 0; l--) layer_line(&bg[l], y, out);
        sprites_line(y, out);
    }
}

/* Alpha blend of two RGB565 lines in 1/16 steps, as BLDALPHA: the expensive compositor case. */
static void blend_line(const uint16_t *a, const uint16_t *b, uint16_t *out, int eva, int evb) {
    for (int x = 0; x < LW; x++) {
        uint32_t ca = (a[x] | (uint32_t)a[x] << 16) & 0x07E0F81F, cb = (b[x] | (uint32_t)b[x] << 16) & 0x07E0F81F;
        uint32_t c = ((ca * eva + cb * evb) >> 4) & 0x07E0F81F;
        out[x] = (uint16_t)(c | c >> 16);
    }
}

/* ------------------------------------------------------------------ output stage */

/* Panel rows p0..p0+31 = frame columns, from the logical frame: each logical pixel becomes a 2x2 block, i.e. two
 * aligned 32-bit stores in two consecutive panel rows. Panel pixel px = 319 - frame row. */
static void strip_indexed(int p0, uint16_t *out, void *ctx) {
    const uint8_t *frame = ctx;
    uint32_t *o = (uint32_t *)out;
    int lx0 = p0 >> 1;
    for (int ly = 0; ly < LH; ly++) {
        const uint8_t *row = frame + ly * LW + lx0;
        int w = (PANEL_W - 2 - 2 * ly) >> 1; /* 32-bit word holding panel pixels 318-2ly and 319-2ly */
        for (int c = 0; c < STRIP / 2; c++) {
            uint32_t v = pal[row[c]];
            v |= v << 16;
            o[(2 * c) * (PANEL_W / 2) + w] = v;
            o[(2 * c + 1) * (PANEL_W / 2) + w] = v;
        }
    }
}

static int64_t output_cpu_us; /* time spent building strips, without the DMA */

static void strip_indexed_timed(int p0, uint16_t *out, void *ctx) {
    int64_t t = esp_timer_get_time();
    strip_indexed(p0, out, ctx);
    output_cpu_us += esp_timer_get_time() - t;
}

/* ------------------------------------------------------------------ test content */

static uint32_t rng = 12345;
static uint32_t rnd(void) { return rng = rng * 1664525 + 1013904223; }

static void make_content(uint8_t *tiles4, uint16_t *maps, uint8_t *spr4, uint8_t *amap, uint8_t *atiles) {
    for (int t = 0; t < 1024; t++) /* tile 0 empty, others: stripes and dots with some transparency */
        for (int r = 0; r < 8; r++) {
            uint32_t row = 0;
            for (int k = 0; k < 8; k++) {
                int c = t == 0 ? 0 : ((k + r + t) % 5 == 0 ? 0 : 1 + (t + k * 3 + r) % 15);
                row |= (uint32_t)c << (4 * k);
            }
            ((uint32_t *)tiles4)[t * 8 + r] = row;
        }
    for (int l = 0; l < 4; l++)
        for (int i = 0; i < MAP * MAP; i++) {
            uint16_t t = (uint16_t)(rnd() % 1024);
            if (l > 0 && rnd() % 3 == 0) t = 0; /* upper layers are partly empty, as in a game */
            maps[l * MAP * MAP + i] = (uint16_t)(t | (rnd() & 0x0C00) | ((l * 4 + rnd() % 4) << 12));
        }
    for (int s = 0; s < 32; s++) /* 32 sprite designs: a disc */
        for (int y = 0; y < 16; y++)
            for (int x = 0; x < 16; x++) {
                int dx = 2 * x - 15, dy = 2 * y - 15, c = dx * dx + dy * dy < 200 ? 1 + (s + x / 4) % 15 : 0;
                uint8_t *b = spr4 + s * 128 + y * 8 + x / 2;
                *b = (uint8_t)(x & 1 ? (*b & 0x0F) | c << 4 : (*b & 0xF0) | c);
            }
    for (int i = 0; i < AMAP * AMAP; i++) amap[i] = (uint8_t)(1 + (i * 7 + i / AMAP) % 255);
    for (int t = 0; t < 256; t++)
        for (int p = 0; p < 64; p++) atiles[t * 64 + p] = (uint8_t)(t == 0 ? 0 : 128 + ((t + p / 8 + p % 8) % 120));
    for (int i = 0; i < 256; i++) { /* a smooth palette, stored byte-swapped as the bus wants */
        uint16_t c = (uint16_t)(((i * 7) & 31) << 11 | ((i * 3) & 63) << 5 | ((255 - i) & 31));
        pal[i] = (uint16_t)(c >> 8 | c << 8);
    }
}

static void place_sprites(uint8_t *spr4, int frame_no) {
    for (int i = 0; i < NSPR; i++) {
        uint32_t h = (uint32_t)i * 2654435761u;
        oam[i] = (sprite){
            .x = (int16_t)((h % 260 + frame_no * (1 + i % 3)) % 260 - 10),
            .y = (int16_t)((h / 260 % 180 + frame_no * (i % 2)) % 180 - 10),
            .bank = (uint8_t)((i % 16) << 4), .hflip = i & 1, .tiles = spr4 + (i % 32) * 128,
        };
    }
}

static void mode7_table(int frame_no) { /* a perspective floor: scale grows toward the bottom, the camera turns */
    int32_t ca = 256, sa = (frame_no * 3) % 256 - 128; /* small-angle stand-in for cos/sin, 8.8 */
    for (int y = 0; y < LH; y++) {
        int32_t lam = (64 * 256) / (y + 16); /* 8.8 scale for this line */
        aff->pa[y] = lam * ca >> 8;
        aff->pc[y] = lam * sa >> 8;
        aff->x0[y] = (frame_no << 10) - aff->pa[y] * (LW / 2);
        aff->y0[y] = (lam * 64) - aff->pc[y] * (LW / 2);
    }
}

/* ------------------------------------------------------------------ measurements */

static uint32_t time_render(int runs) { /* best of runs, in cycles: interrupts only ever add */
    uint32_t best = UINT32_MAX;
    for (int r = 0; r < runs; r++) {
        uint32_t a = esp_cpu_get_cycle_count();
        render(idx[0]);
        uint32_t c = esp_cpu_get_cycle_count() - a;
        if (c < best) best = c;
    }
    return best;
}

static void scene(const char *name, int layers, int sprites, bool affine_on) {
    nlayers = layers;
    nsprites = sprites;
    use_affine = affine_on;
    uint32_t c = time_render(5);
    LOG("scene %-22s %8u cycles = %6.2f ms = %5.1f%% of one core at 60 fps", name, (unsigned)c, c / 240000.0,
        100.0 * c / 4000000.0);
    vTaskDelay(1);
}

static void memory(void) {
    const size_t n = 64 * 1024, big = 1024 * 1024; /* PSRAM side 1 MB: far past the 64 KB data cache */
    uint8_t *i1 = ialloc(n), *i2 = ialloc(n);
    uint8_t *p1 = heap_caps_malloc(big, MALLOC_CAP_SPIRAM), *p2 = heap_caps_malloc(big, MALLOC_CAP_SPIRAM);
    if (i1 && i2 && p1 && p2) {
        memset(i1, 1, n);
        memset(p1, 2, big);
        int64_t t = esp_timer_get_time();
        for (int r = 0; r < 16; r++) memcpy(i2, i1, n);
        LOG("memcpy SRAM->SRAM    %6.1f MB/s", 16.0 * n / (esp_timer_get_time() - t));
        t = esp_timer_get_time();
        for (size_t o = 0; o < big; o += n) memcpy(p2 + o, i1, n);
        LOG("memcpy SRAM->PSRAM   %6.1f MB/s (1 MB, uncached)", (double)big / (esp_timer_get_time() - t));
        t = esp_timer_get_time();
        for (size_t o = 0; o < big; o += n) memcpy(i2, p1 + o, n);
        LOG("memcpy PSRAM->SRAM   %6.1f MB/s (1 MB, uncached)", (double)big / (esp_timer_get_time() - t));
        t = esp_timer_get_time();
        memcpy(p2, p1, big);
        LOG("memcpy PSRAM->PSRAM  %6.1f MB/s (1 MB)", (double)big / (esp_timer_get_time() - t));
    }
    heap_caps_free(i1); heap_caps_free(i2); heap_caps_free(p1); heap_caps_free(p2);
}

static volatile int te_count;
static void IRAM_ATTR te_isr(void *arg) { (void)arg; te_count++; }

static void tearing_signal(void) {
    gpio_config_t io = {.pin_bit_mask = 1ULL << PIN_TE, .mode = GPIO_MODE_INPUT, .intr_type = GPIO_INTR_POSEDGE};
    gpio_config(&io);
    esp_err_t e = gpio_install_isr_service(0);
    if (e != ESP_OK && e != ESP_ERR_INVALID_STATE) { LOG("TE: no ISR service (%d)", e); return; }
    gpio_isr_handler_add(PIN_TE, te_isr, NULL);
    te_count = 0;
    vTaskDelay(pdMS_TO_TICKS(2000));
    LOG("panel TE, line and frame pulses: %.1f Hz", te_count / 2.0);
    display_te_vblank_only(true);
    vTaskDelay(pdMS_TO_TICKS(50));
    te_count = 0;
    vTaskDelay(pdMS_TO_TICKS(2000));
    LOG("panel TE, frame pulses only: %.1f Hz = the panel's refresh rate", te_count / 2.0);
    display_te_vblank_only(false);
    gpio_isr_handler_remove(PIN_TE);
}

static void sd_speed(void) {
    if (!storage_mount()) { LOG("SD: not mounted"); return; }
    char best[300] = "";
    long best_size = 0;
    const char *dirs[] = {"/sdcard/games/bajopueblo/audio", "/sdcard/games/geumgye/audio"};
    for (size_t d = 0; d < 2; d++) {
        DIR *dir = opendir(dirs[d]);
        for (struct dirent *e; dir && (e = readdir(dir));) {
            char path[300];
            struct stat st;
            snprintf(path, sizeof path, "%s/%s", dirs[d], e->d_name);
            if (!stat(path, &st) && st.st_size > best_size) best_size = st.st_size, snprintf(best, sizeof best, "%s", path);
        }
        if (dir) closedir(dir);
    }
    if (!best_size) { LOG("SD: no large file to read"); return; }
    uint8_t *buf = ialloc(64 * 1024);
    if (!buf) return;
    int sizes[] = {64 * 1024, 8 * 1024, 512};
    for (size_t k = 0; k < 3; k++) {
        FILE *f = fopen(best, "rb");
        if (!f) { LOG("SD: cannot open %s", best); break; }
        long want = sizes[k] >= 8192 ? 4L << 20 : 1L << 20, got = 0;
        int64_t t = esp_timer_get_time();
        for (size_t r; got < want && (r = fread(buf, 1, (size_t)sizes[k], f)) > 0;) got += (long)r;
        int64_t us = esp_timer_get_time() - t;
        fclose(f);
        LOG("SD read %5d-byte chunks: %5.2f MB/s (%ld KB of %s)", sizes[k], (double)got / us, got / 1024, best);
    }
    heap_caps_free(buf);
}

/* ------------------------------------------------------------------ the whole pipeline on two cores */

static SemaphoreHandle_t drawn[2], shown[2];
static volatile int demo_frame;
static uint8_t *spr_tiles;

static void render_task(void *arg) { /* core 1: draws frame N+1 while core 0 sends frame N */
    (void)arg;
    for (int n = 0;; n++) {
        int b = n & 1;
        xSemaphoreTake(shown[b], portMAX_DELAY);
        demo_frame = n;
        for (int l = 0; l < 4; l++) bg[l].sx = n * (l + 1), bg[l].sy = n * l / 2;
        place_sprites(spr_tiles, n);
        mode7_table(n);
        render(idx[b]);
        xSemaphoreGive(drawn[b]);
    }
}

static void pipeline(const char *name, int layers, int sprites, bool affine_on, int seconds) {
    nlayers = layers;
    nsprites = sprites;
    use_affine = affine_on;
    for (int b = 0; b < 2; b++) {
        drawn[b] = xSemaphoreCreateBinary();
        shown[b] = xSemaphoreCreateBinary();
        xSemaphoreGive(shown[b]);
    }
    TaskHandle_t task;
    xTaskCreatePinnedToCore(render_task, "bench_render", 4096, NULL, 5, &task, 1);
    int64_t t0 = esp_timer_get_time(), wait = 0;
    output_cpu_us = 0;
    int frames = 0;
    while (esp_timer_get_time() - t0 < seconds * 1000000LL) {
        int b = frames & 1;
        int64_t w = esp_timer_get_time();
        xSemaphoreTake(drawn[b], portMAX_DELAY);
        wait += esp_timer_get_time() - w;
        display_present_strips(strip_indexed_timed, idx[b]);
        xSemaphoreGive(shown[b]);
        frames++;
    }
    int64_t us = esp_timer_get_time() - t0;
    vTaskDelete(task);
    for (int b = 0; b < 2; b++) vSemaphoreDelete(drawn[b]), vSemaphoreDelete(shown[b]);
    LOG("pipeline %-20s %5.1f fps | core 0: output stage %.2f ms/frame of CPU, waited for core 1 %.2f ms/frame",
        name, frames * 1e6 / us, output_cpu_us / 1000.0 / frames, wait / 1000.0 / frames);
}

void bench_run(void) {
    vTaskDelay(pdMS_TO_TICKS(4000)); /* time for the USB log to be reopened after the flash's reset */
    LOG("start | CPU %d MHz | SPI asked 80000 kHz, got %d kHz | free internal %u KB (largest block %u KB), PSRAM %u KB",
        CONFIG_ESP_DEFAULT_CPU_FREQ_MHZ, display_spi_khz(), (unsigned)(heap_caps_get_free_size(MALLOC_CAP_INTERNAL) / 1024),
        (unsigned)(heap_caps_get_largest_free_block(MALLOC_CAP_INTERNAL) / 1024),
        (unsigned)(heap_caps_get_free_size(MALLOC_CAP_SPIRAM) / 1024));
    memory();
    tearing_signal();

    /* the current engine's path: a 480x320 frame in PSRAM, turned into strips */
    uint16_t *big = heap_caps_malloc(480 * 320 * 2, MALLOC_CAP_SPIRAM);
    for (int i = 0; big && i < 480 * 320; i++) big[i] = (uint16_t)(i * 37);
    int64_t t = esp_timer_get_time();
    for (int r = 0; big && r < 10; r++) display_present(big);
    LOG("v1 present: 480x320 RGB565 frame in PSRAM -> panel: %.2f ms", (esp_timer_get_time() - t) / 10000.0);
    heap_caps_free(big);
    sd_speed(); /* before the test content takes internal RAM: it reads into a 64 KB internal buffer */

    uint8_t *tiles4 = ialloc(1024 * 32), *spr4 = ialloc(32 * 128), *amap = ialloc(AMAP * AMAP),
            *atiles = ialloc(256 * 64);
    uint16_t *maps = ialloc(4 * MAP * MAP * 2);
    aff = ialloc(sizeof *aff);
    idx[0] = ialloc(LW * LH);
    idx[1] = ialloc(LW * LH);
    if (!tiles4 || !spr4 || !amap || !atiles || !maps || !aff || !idx[0] || !idx[1]) return;
    spr_tiles = spr4;
    make_content(tiles4, maps, spr4, amap, atiles);
    for (int l = 0; l < 4; l++) bg[l] = (layer){tiles4, maps + l * MAP * MAP, 13 * l, 7 * l};
    aff->map = amap;
    aff->tiles = atiles;
    place_sprites(spr4, 0);
    mode7_table(0);
    LOG("content in internal RAM: free internal now %u KB", (unsigned)(heap_caps_get_free_size(MALLOC_CAP_INTERNAL) / 1024));

    /* the pieces, one frame each (cycles at 240 MHz; 4.0 M cycles = one core for a 60 fps frame) */
    scene("empty (clear only)", 0, 0, false);
    scene("1 regular layer", 1, 0, false);
    scene("4 regular layers", 4, 0, false);
    scene("128 sprites 16x16", 0, 128, false);
    scene("1 affine layer", 0, 0, true);
    scene("light: 2 layers+32 spr", 2, 32, false);
    scene("GBA mode 0: 4L+128 spr", 4, 128, false);
    scene("mode 7: aff+1L+64 spr", 1, 64, true);
    scene("max: aff+4L+128 spr", 4, 128, true);

    { /* alpha blend of two full RGB565 frames, line by line */
        uint16_t *a = ialloc(LW * 2), *b = ialloc(LW * 2), *o = ialloc(LW * 2);
        if (a && b && o) {
            for (int x = 0; x < LW; x++) a[x] = (uint16_t)(x * 91), b[x] = (uint16_t)(x * 17);
            uint32_t c0 = esp_cpu_get_cycle_count();
            for (int y = 0; y < LH; y++) blend_line(a, b, o, 10, 6);
            uint32_t c = esp_cpu_get_cycle_count() - c0;
            LOG("alpha blend 240x160 RGB565: %u cycles = %.2f ms = %.1f%% of one core at 60 fps", (unsigned)c,
                c / 240000.0, 100.0 * c / 4000000.0);
        }
        heap_caps_free(a); heap_caps_free(b); heap_caps_free(o);
    }

    { /* tiles and maps in PSRAM, a different 32 KB tileset per layer: 160 KB, more than the 64 KB data cache */
        uint8_t *pt = heap_caps_malloc(4 * 1024 * 32, MALLOC_CAP_SPIRAM);
        uint16_t *pm = heap_caps_malloc(4 * MAP * MAP * 2, MALLOC_CAP_SPIRAM);
        if (pt && pm) {
            for (int l = 0; l < 4; l++) {
                memcpy(pt + l * 32768, tiles4, 32768);
                bg[l].tiles = pt + l * 32768;
            }
            memcpy(pm, maps, 4 * MAP * MAP * 2);
            for (int l = 0; l < 4; l++) bg[l].map = pm + l * MAP * MAP;
            scene("4 layers, data in PSRAM", 4, 0, false);
            nlayers = 4, nsprites = 0, use_affine = false; /* one run only: no warm cache from a previous run */
            for (int i = 0; i < 4; i++) bg[i].sx += 37, bg[i].sy += 23;
            uint32_t c0 = esp_cpu_get_cycle_count();
            render(idx[0]);
            uint32_t c = esp_cpu_get_cycle_count() - c0;
            LOG("scene 4 layers, PSRAM, cold cache %8u cycles = %6.2f ms", (unsigned)c, c / 240000.0);
            for (int l = 0; l < 4; l++) bg[l].tiles = tiles4, bg[l].map = maps + l * MAP * MAP;
        }
        heap_caps_free(pt); heap_caps_free(pm);
    }

    /* the fused output stage: palette + 2x + transpose + byte swap into strips, with and without the panel */
    nlayers = 4, nsprites = 128, use_affine = false;
    render(idx[0]);
    {
        uint16_t *s = ialloc(STRIP * PANEL_W * 2);
        if (s) {
            uint32_t c0 = esp_cpu_get_cycle_count();
            for (int p0 = 0; p0 < 480; p0 += STRIP) strip_indexed(p0, s, idx[0]);
            uint32_t c = esp_cpu_get_cycle_count() - c0;
            LOG("output stage CPU only (240x160 indexed -> 15 panel strips): %u cycles = %.2f ms", (unsigned)c,
                c / 240000.0);
            heap_caps_free(s);
        }
    }
    t = esp_timer_get_time();
    for (int r = 0; r < 20; r++) display_present_strips(strip_indexed, idx[0]);
    LOG("v2 present: 240x160 indexed in internal RAM -> panel: %.2f ms", (esp_timer_get_time() - t) / 20000.0);

    /* the real thing, on screen: core 1 draws, core 0 sends; 5 s each */
    pipeline("GBA mode 0: 4L+128 spr", 4, 128, false, 5);
    pipeline("mode 7: aff+1L+64 spr", 1, 64, true, 5);
    pipeline("max: aff+4L+128 spr", 4, 128, true, 5);
    LOG("done");
}

/* ------------------------------------------------------------------ v1 profile: where the current engine's frame goes */

#include "bp.h"

#define V1_SAVES "/sdcard/np2d_bench_saves" /* never the game's own saves/ */

static float best_ms(void (*fn)(void *), void *arg) {
    uint32_t best = UINT32_MAX;
    for (int r = 0; r < 3; r++) {
        uint32_t a = esp_cpu_get_cycle_count();
        fn(arg);
        uint32_t c = esp_cpu_get_cycle_count() - a;
        if (c < best) best = c;
    }
    return best / 240000.0f;
}

static surface v1_world, v1_scr;
static uint16_t *v1_strip;
static void do_strips(void *a) { /* the console's way: 15 turned strips of 32 panel rows, world drawn once */
    (void)a;
    for (int r = 0; r < SCREEN_W; r += 32) {
        surface t = gfx_turned(v1_strip, r, 32, SCREEN_W, SCREEN_H, false, true);
        game_draw(&t, false);
    }
}
static void do_strip_upscale(void *a) {
    (void)a;
    for (int r = 0; r < SCREEN_W; r += 32) {
        surface t = gfx_turned(v1_strip, r, 32, SCREEN_W, SCREEN_H, false, true);
        gfx_upscale2x(&v1_world, &t);
    }
}
static void do_swap(void *a) {
    (void)a;
    for (int r = 0; r < SCREEN_W; r += 32) {
        uint32_t *w = (uint32_t *)v1_strip;
        for (int i = 0; i < 32 * SCREEN_H / 2; i++) w[i] = (w[i] & 0x00FF00FFu) << 8 | (w[i] >> 8 & 0x00FF00FFu);
    }
}
static void do_world(void *a) { (void)a; world_render(&v1_world); }
static void do_upscale(void *a) { (void)a; gfx_upscale2x(&v1_world, &v1_scr); }
static void do_frame(void *a) { (void)a; game_render(v1_scr.px); }

static void profile_game(const char *dir) {
    mkdir(V1_SAVES, 0755);
    bp_config cfg = {dir, V1_SAVES};
    if (!game_init(&cfg)) {
        LOG("%s: game_init failed", dir);
        game_shutdown();
        return;
    }
    G.autosave_enabled = false;
    uint16_t *frame = heap_caps_malloc(SCREEN_W * SCREEN_H * 2, MALLOC_CAP_SPIRAM);
    v1_strip = heap_caps_malloc(32 * SCREEN_H * 2, MALLOC_CAP_INTERNAL | MALLOC_CAP_DMA);
    if (!frame || !v1_strip) return;
    v1_world = (surface){.px = G.world, .w = WORLD_W, .h = WORLD_H};
    v1_scr = (surface){.px = frame, .w = SCREEN_W, .h = SCREEN_H};
    const char *id = jstr(G.game, "id") ? jstr(G.game, "id") : dir;
    LOG("v1 %-10s title                 whole frame %6.2f ms", id, best_ms(do_frame, NULL));
    game_new();
    G.autosave_enabled = false;
    const hal_input none = {0};
    float sum_w = 0, sum_u = 0, sum_f = 0, max_f = 0;
    int n = 0;
    const cJSON *z;
    cJSON_ArrayForEach(z, jget(G.game, "zones")) {
        layers_reset(L_PLAY);
        if (!cJSON_IsString(z) || !world_enter(z->valuestring, "safe")) continue;
        for (int i = 0; i < 150; i++) game_tick(&none); /* past the arrival label and any entry scene */
        layers_reset(L_PLAY);
        G.seq.fade = 0;
        float w = best_ms(do_world, NULL), u = best_ms(do_upscale, NULL), f = best_ms(do_frame, NULL);
        float st = best_ms(do_strips, NULL), su = best_ms(do_strip_upscale, NULL), sw = best_ms(do_swap, NULL);
        LOG("v1 %-10s %-5s world %5.2f ms | upscale %5.2f ms | whole frame %6.2f ms || strips: all %5.2f ms, upscale %5.2f ms, swap %5.2f ms",
            id, z->valuestring, w, u, f, st, su, sw);
        sum_w += w, sum_u += u, sum_f += f, n++;
        if (f > max_f) max_f = f;
        vTaskDelay(1);
    }
    if (n) LOG("v1 %-10s average of %d zones: world %.2f ms, upscale %.2f ms, whole frame %.2f ms (worst %.2f ms)", id, n,
               sum_w / n, sum_u / n, sum_f / n, max_f);
    heap_caps_free(frame);
    heap_caps_free(v1_strip);
    game_shutdown();
}

static void do_frame_strips(void *a) { /* a whole frame as the console draws it: the world, then 15 strips */
    (void)a;
    for (int r = 0; r < SCREEN_W; r += 32) {
        surface t = gfx_turned(v1_strip, r, 32, SCREEN_W, SCREEN_H, false, true);
        game_draw(&t, r == 0);
    }
}

/* One zone with a screen open on it: "play", "dlg:REF", "inv" (every item in the bag) or "puz:ID". */
static void profile_screens(const char *dir, const char *zone, const char *const *modes, int nmodes) {
    for (int i = 0; i < nmodes; i++) {
        mkdir(V1_SAVES, 0755);
        bp_config cfg = {dir, V1_SAVES};
        if (!game_init(&cfg)) { game_shutdown(); return; }
        uint16_t *frame = heap_caps_malloc(SCREEN_W * SCREEN_H * 2, MALLOC_CAP_SPIRAM);
        v1_strip = heap_caps_malloc(32 * SCREEN_H * 2, MALLOC_CAP_INTERNAL | MALLOC_CAP_DMA);
        if (!frame || !v1_strip) return;
        v1_scr = (surface){.px = frame, .w = SCREEN_W, .h = SCREEN_H};
        game_new();
        G.autosave_enabled = false;
        layers_reset(L_PLAY);
        world_enter(zone, "safe");
        const hal_input none = {0};
        for (int t = 0; t < 150; t++) game_tick(&none);
        layers_reset(L_PLAY);
        G.seq.fade = 0;
        const char *m = modes[i];
        const cJSON *it;
        if (!strncmp(m, "dlg:", 4)) dlg_open(m + 4);
        else if (!strncmp(m, "inv+dlg:", 8)) { /* the bag with a dialogue over it, as when an item is examined */
            cJSON_ArrayForEach(it, G.items) flagf_set(1, "item:%s%s", it->string, "");
            layer_push(L_INV);
            dlg_open(m + 8);
        } else if (!strcmp(m, "inv")) {
            cJSON_ArrayForEach(it, G.items) flagf_set(1, "item:%s%s", it->string, "");
            layer_push(L_INV);
        } else if (!strncmp(m, "puz:", 4)) puzzle_open(m + 4);
        for (int t = 0; t < 240; t++) game_tick(&none); /* the typewriter done */
        LOG("v1 %-10s %-5s %-18s whole frame %6.2f ms || strips with the world %6.2f ms", jstr(G.game, "id"), zone, m,
            best_ms(do_frame, NULL), best_ms(do_frame_strips, NULL));
        heap_caps_free(frame);
        heap_caps_free(v1_strip);
        game_shutdown();
        vTaskDelay(1);
    }
}

void bench_v1_run(void) {
    vTaskDelay(pdMS_TO_TICKS(4000)); /* time for the USB log to be reopened after the flash's reset */
    LOG("v1 G.world at %p: %s", (void *)G.world, esp_ptr_external_ram(G.world) ? "PSRAM" : "internal RAM");
    if (!storage_mount()) { LOG("v1: no card"); return; }
    LOG("v1 start | free internal %u KB, PSRAM %u KB", (unsigned)(heap_caps_get_free_size(MALLOC_CAP_INTERNAL) / 1024),
        (unsigned)(heap_caps_get_free_size(MALLOC_CAP_SPIRAM) / 1024));
    static const char *const bp[] = {"play", "dlg:D_ALCALDESA", "inv", "puz:P01", "puz:P03"};
    static const char *const gg[] = {"play", "dlg:D_M01.noticia", "inv", "puz:P01", "puz:T02"};
    static const char *const bp4[] = {"play", "dlg:D_PANADERA", "inv+dlg:D_PANADERA"};
    profile_game("/sdcard/games/bajopueblo");
    profile_game("/sdcard/games/geumgye");
    profile_screens("/sdcard/games/bajopueblo", "Z04", bp4, 3);
    profile_screens("/sdcard/games/bajopueblo", "Z01", bp, 5);
    profile_screens("/sdcard/games/geumgye", "M01", gg, 5);
    LOG("v1 done");
}
