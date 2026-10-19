/* Whole-frame goldens for the virtual picture processor: each scene is drawn from fixed, generated content and the
 * FNV-1a hash of its 240x160 RGB565 frame is compared with tests/ppu_golden.txt. A mismatch means a pixel changed:
 * deliberate (a fidelity fix: review the picture, then `ppu_golden_test --update ppu_golden.txt`) or a regression (an
 * optimisation must keep every hash). The scenes named g* record the CURRENT behaviour, including the known
 * divergences from the GBA listed in docs/gba/audit-01-ppu.md, so each fix shows up as an intentional change.
 *   usage: ppu_golden_test golden.txt [--update] */
#include <stdio.h>
#include <stdlib.h>
#include <string.h>

#include "ppu.h"

#define MAP 64
#define NTILES 1024
#define HASH_FRAMES 8 /* animated scenes: frames 0..7 are hashed together */

static uint32_t rng;
static uint32_t rnd(void) { return rng = rng * 1664525 + 1013904223; }

static uint8_t tiles[NTILES * 64];
static uint16_t tilerows[NTILES];
static uint16_t maps[4][MAP * MAP];
static uint8_t spr[32][16 * 16];
static uint8_t big[64 * 64];
static uint16_t rgbspr[16 * 16];
static uint8_t rgbmask[16 * 2];
static uint8_t atiles[256 * 64];
static uint16_t amap[MAP * MAP];
static uint16_t bmp[100 * 70];
static uint8_t bmpmask[13 * 70];
static ppu_line_affine aline[PPU_H];
static ppu_line_scroll lscroll[PPU_H];
static uint16_t lback[PPU_H];
static ppu_line_span lspan[PPU_H];
static uint8_t lev[PPU_H];
static uint16_t frame[PPU_W * PPU_H];

static void make_content(char kind) {
    rng = 12345;
    for (int t = 0; t < NTILES; t++)
        for (int r = 0; r < 8; r++)
            for (int k = 0; k < 8; k++) {
                int c = t == 0 ? 0 : ((k + r + t) % 5 == 0 ? 0 : 1 + (t + k * 3 + r) % 15);
                if (kind == 'B' && t % 4 == 1) c = 1 + (t + k * 3 + r) % 15; /* fully opaque tiles: the row shortcuts */
                tiles[t * 64 + r * 8 + k] = (uint8_t)c;
            }
    ppu_tile_rows(tiles, NTILES, tilerows);
    for (int l = 0; l < 4; l++)
        for (int i = 0; i < MAP * MAP; i++) {
            uint16_t t = (uint16_t)(rnd() % 1024);
            if (l > 0 && rnd() % 3 == 0) t = 0;
            maps[l][i] = (uint16_t)(t | (rnd() & 0x0C00) | ((l * 4 + rnd() % 4) << 12));
        }
    for (int s = 0; s < 32; s++)
        for (int y = 0; y < 16; y++)
            for (int x = 0; x < 16; x++) {
                int dx = 2 * x - 15, dy = 2 * y - 15;
                spr[s][y * 16 + x] = (uint8_t)(dx * dx + dy * dy < 200 ? 1 + (s + x / 4) % 15 : 0);
            }
    for (int y = 0; y < 64; y++)
        for (int x = 0; x < 64; x++) big[y * 64 + x] = (uint8_t)((x + y) % 7 == 0 ? 0 : 1 + (x / 8 + y / 8) % 15);
    for (int y = 0; y < 16; y++)
        for (int x = 0; x < 16; x++) {
            rgbspr[y * 16 + x] = (uint16_t)((x * 2) << 11 | (y * 4) << 5 | (x ^ y));
            if (!((x + y) % 4 == 0)) rgbmask[y * 2 + x / 8] |= (uint8_t)(0x80 >> (x % 8));
        }
    for (int i = 0; i < MAP * MAP; i++) amap[i] = (uint16_t)(1 + (i * 7 + i / MAP) % 255);
    for (int t = 0; t < 256; t++)
        for (int p = 0; p < 64; p++) atiles[t * 64 + p] = (uint8_t)(t == 0 ? 0 : 128 + ((t + p / 8 + p % 8) % 120));
    memset(bmpmask, 0, sizeof bmpmask);
    for (int y = 0; y < 70; y++)
        for (int x = 0; x < 100; x++) {
            bmp[y * 100 + x] = (uint16_t)((x * 5) << 11 | (y * 9) << 5 | ((x * y) & 31));
            if ((x / 6 + y / 5) % 3) bmpmask[y * 13 + x / 8] |= (uint8_t)(0x80 >> (x % 8));
        }
    for (int y = 0; y < PPU_H; y++) {
        lscroll[y] = (ppu_line_scroll){(int16_t)((y * 37) % 23 - 11), (int16_t)(y % 3)};
        lback[y] = (uint16_t)(y << 8 | (255 - y));
        int w = 70 - (y > 80 ? y - 80 : 80 - y);
        lspan[y] = (ppu_line_span){(int16_t)(120 - (w > 0 ? w : 0)), (int16_t)(120 + (w > 0 ? w : 0))};
        lev[y] = (uint8_t)(y / 10);
    }
}

static void set_palettes(void) {
    for (int i = 0; i < 256; i++) {
        uint16_t c = (uint16_t)(((i * 7) & 31) << 11 | ((i * 3) & 63) << 5 | ((255 - i) & 31));
        PPU.bg_pal[i] = c;
        PPU.obj_pal[i] = (uint16_t)(c ^ 0x2108);
    }
}

static void tiled(int n, int prio, int sx, int sy) {
    PPU.bg[n] = (ppu_bg){.mode = BG_TILES, .prio = (uint8_t)prio, .wrap = true, .tiles = tiles, .ntiles = NTILES,
                         .rows = tilerows, .map = maps[n], .map_w = MAP, .map_h = MAP, .scroll_x = sx, .scroll_y = sy};
}

static void sprite(int i, int x, int y, int prio, int mode) {
    PPU.obj[i] = (ppu_obj){.on = true, .x = (int16_t)x, .y = (int16_t)y, .w = 16, .h = 16, .prio = (uint8_t)prio,
                           .bank = (uint8_t)(i % 16), .affine = -1, .mode = (uint8_t)mode, .idx = spr[i % 32]};
}

static void alpha_fx(int first, int second, int eva, int evb) {
    PPU.fx.mode = FX_ALPHA, PPU.fx.first = (uint8_t)first, PPU.fx.second = (uint8_t)second;
    PPU.fx.eva = (uint8_t)eva, PPU.fx.evb = (uint8_t)evb;
}

static void windows(void) {
    PPU.win.on[0] = PPU.win.on[1] = true;
    PPU.win.rect[0] = (ppu_rect){40, 200, 20, 140};
    PPU.win.rect[1] = (ppu_rect){100, 140, 0, 160};
    PPU.win.in[0] = PPU_BG0 | PPU_BG1 | PPU_BG2 | PPU_BG3 | PPU_OBJ | PPU_FX;
    PPU.win.in[1] = PPU_BG0 | PPU_BG2 | PPU_FX;
    PPU.win.out = PPU_BG1 | PPU_BG2 | PPU_BG3 | PPU_OBJ;
}

static void scatter(int n, int count, int mode) { /* count sprites moving over the screen, as bench.c does */
    for (int i = 0; i < count; i++) {
        uint32_t h = (uint32_t)i * 2654435761u;
        sprite(i, (int)((h % 260 + (uint32_t)n * (1 + i % 3)) % 260) - 10,
               (int)((h / 260 % 180 + (uint32_t)n * (i % 2)) % 180) - 10, 0, (mode && (i & 1)) ? OBJ_BLEND : OBJ_NORMAL);
    }
}

static void affine_floor(int n) {
    int32_t ca = 256, sa = (n * 3) % 256 - 128;
    for (int y = 0; y < PPU_H; y++) {
        int32_t lam = (64 * 256) / (y + 16), pa = lam * ca >> 8, pc = lam * sa >> 8;
        aline[y] = (ppu_line_affine){.pa = pa, .pc = pc, .x = (n << 10) - pa * (PPU_W / 2), .y = (lam * 64) - pc * (PPU_W / 2)};
    }
    PPU.bg[3] = (ppu_bg){.mode = BG_AFFINE, .prio = 3, .wrap = true, .tiles = atiles, .ntiles = 256, .map = amap,
                         .map_w = MAP, .map_h = MAP};
    PPU.line.affine[3] = aline;
}

/* A scene sets the PPU up for frame n (called after ppu_reset and set_palettes for n = 0, then again for each frame). */
typedef void (*scene_fn)(int n);

static void s_clear(int n) { (void)n; }
static void s_layer1(int n) { tiled(0, 0, n, n / 2); }
static void s_layer4(int n) { for (int l = 0; l < 4; l++) tiled(l, l, n * (l + 1) + 13 * l, n * l / 2 + 7 * l); }
static void s_spr128(int n) { scatter(n, 128, 0); }
static void s_affine(int n) { affine_floor(n); }
static void s_light(int n) { tiled(0, 0, n, 0), tiled(1, 1, 2 * n, 3); scatter(n, 32, 0); }
static void s_mode0(int n) { s_layer4(n); scatter(n, 128, 0); }
static void s_mode7(int n) { tiled(0, 0, n, 0); affine_floor(n); scatter(n, 64, 0); }
static void s_max(int n) { for (int l = 0; l < 3; l++) tiled(l, l, n + 13 * l, 7 * l); affine_floor(n); scatter(n, 128, 0); }
static void s_alpha_win(int n) { s_layer4(n); alpha_fx(PPU_BG0, PPU_BG1 | PPU_BG2 | PPU_BG3 | PPU_BACK, 10, 6); windows(); }
static void s_half_blend(int n) {
    scatter(n, 128, 1);
    alpha_fx(0, PPU_BG0 | PPU_BG1 | PPU_BG2 | PPU_BG3 | PPU_BACK, 8, 8);
}

static void g_banks(int n) { (void)n; tiled(0, 0, 0, 0); PPU.obj_pal[1] = 0xFFE0; sprite(0, 100, 60, 0, OBJ_NORMAL); }
static void g_nonpow2(int n) {
    (void)n;
    tiled(0, 0, 500, 3), PPU.bg[0].map_w = 40, PPU.bg[0].map_h = 20;
    tiled(1, 1, 60, 30), PPU.bg[1].wrap = false, PPU.bg[1].rows = NULL;
}
static void g_ties(int n) { (void)n; for (int l = 0; l < 4; l++) tiled(l, n == 0 ? 1 : 3 - l, 5 * l, 0); }
static void g_obj_order(int n) {
    (void)n;
    tiled(0, 1, 0, 0), tiled(1, 2, 0, 0);
    sprite(0, 20, 20, 1, 0), sprite(5, 28, 24, 0, 0), sprite(2, 80, 20, 2, 0), sprite(3, 86, 22, 2, 0);
    sprite(9, 120, 40, 1, 0), sprite(10, 126, 44, 2, 0);
}
static void g_obj_flip_clip(int n) {
    (void)n;
    sprite(0, -3, 10, 0, 0), sprite(1, 237, 10, 0, 0), sprite(2, 100, -5, 0, 0), sprite(3, 100, 153, 0, 0);
    PPU.obj[1].hflip = true, PPU.obj[2].vflip = true, PPU.obj[3].hflip = PPU.obj[3].vflip = true;
    PPU.obj[4] = (ppu_obj){.on = true, .x = 60, .y = 60, .w = 16, .h = 16, .affine = -1, .rgb = rgbspr, .mask = rgbmask};
    PPU.obj[5] = (ppu_obj){.on = true, .x = 90, .y = 90, .w = 64, .h = 64, .affine = -1, .bank = 2, .idx = big};
}
static void g_obj_affine(int n) {
    (void)n;
    static const ppu_affine m[4] = {{256, 0, 0, 256}, {128, 0, 0, 128}, {512, 0, 0, 512}, {181, 181, -181, 181}};
    for (int i = 0; i < 4; i++) {
        PPU.affine[i] = m[i];
        sprite(i, 20 + 50 * i, 30, 0, 0), PPU.obj[i].affine = (int8_t)i;
        sprite(4 + i, 20 + 50 * i, 90, 0, 0), PPU.obj[4 + i].affine = (int8_t)i, PPU.obj[4 + i].dbl = true;
    }
}
static void g_affine_bg(int n) {
    (void)n;
    PPU.bg[2] = (ppu_bg){.mode = BG_AFFINE, .prio = 1, .wrap = true, .tiles = atiles, .ntiles = 256, .map = amap,
                         .map_w = 32, .map_h = 32, .pa = 128, .pd = 128, .x0 = 4 << 8, .y0 = 9 << 8};
    PPU.bg[3] = (ppu_bg){.mode = BG_AFFINE, .prio = 2, .wrap = false, .tiles = atiles, .ntiles = 256, .map = amap,
                         .map_w = 16, .map_h = 16, .pa = 222, .pb = -128, .pc = 128, .pd = 222, .x0 = 20 << 8, .y0 = 60 << 8};
}
static void g_bitmap(int n) {
    (void)n;
    PPU.bg[0] = (ppu_bg){.mode = BG_BITMAP, .prio = 1, .wrap = true, .bitmap = bmp, .bitmap_mask = bmpmask,
                         .bitmap_w = 100, .bitmap_h = 70, .scroll_x = 37, .scroll_y = 11};
    PPU.bg[1] = (ppu_bg){.mode = BG_BITMAP, .prio = 0, .bitmap = bmp, .bitmap_mask = bmpmask, .bitmap_w = 100,
                         .bitmap_h = 70, .scroll_x = -30, .scroll_y = -20, .mosaic = true};
    tiled(2, 3, 0, 0);
    PPU.mosaic.bg_w = 4, PPU.mosaic.bg_h = 4;
}
static void g_alpha_kinds(int n) {
    static const int eva[] = {8, 16, 3, 0}, evb[] = {8, 16, 13, 16};
    int k = n % 4;
    tiled(0, 0, 0, 0), tiled(1, 1, 9, 5), sprite(0, 100, 60, 0, 0);
    alpha_fx(PPU_BG0 | PPU_OBJ, PPU_BG1 | PPU_BACK, eva[k], evb[k]);
    if (n >= 4) PPU.fx.mode = n < 6 ? FX_LIGHTEN : FX_DARKEN, PPU.fx.evy = (uint8_t)(n == 4 || n == 6 ? 7 : 16);
}
static void g_blend_sprites(int n) { /* (a) over BG in second, (b) over BG not in second, (c) over a sprite, (d) in a window, (e) fx_off */
    tiled(0, 1, 0, 0), tiled(1, 2, 0, 0);
    alpha_fx(0, PPU_BG0 | PPU_BACK, 8, 8);
    sprite(0, 20, 20, 0, OBJ_BLEND), sprite(1, 80, 20, 0, OBJ_BLEND), PPU.obj[1].prio = 3;
    sprite(2, 140, 20, 1, OBJ_NORMAL), sprite(3, 146, 24, 0, OBJ_BLEND);
    sprite(4, 40, 100, 0, OBJ_BLEND);
    if (n == 1) PPU.fx.second |= PPU_OBJ;
    if (n == 2) PPU.win.on[0] = true, PPU.win.rect[0] = (ppu_rect){0, 120, 0, 160}, PPU.win.in[0] = PPU_BG0 | PPU_BG1 | PPU_OBJ,
                PPU.win.out = PPU_BG0 | PPU_BG1 | PPU_OBJ | PPU_FX;
    if (n == 3) PPU.fx.mode = FX_NONE;
}
static void g_windows(int n) {
    tiled(0, 1, 0, 0), tiled(1, 2, 0, 0), tiled(2, 3, 0, 0);
    scatter(0, 20, 0);
    windows();
    if (n % 2) PPU.win.in[0] &= (uint8_t)~PPU_FX, alpha_fx(PPU_BG0, PPU_BG1, 8, 8);
    if (n >= 2) { /* object window: two shapes, one flipped */
        PPU.win.obj_on = true, PPU.win.obj_in = PPU_BG0 | PPU_OBJ;
        sprite(30, 60, 90, 0, OBJ_WINDOW), sprite(31, 150, 90, 0, OBJ_WINDOW), PPU.obj[31].hflip = true;
    }
}
static void g_window_edges(int n) {
    static const ppu_rect r[] = {{80, 40, 10, 100}, {30, 300, 10, 100}, {-20, 60, 20, 90}, {20, 90, 90, 30}, {20, 90, 20, 200},
                                 {20, 90, 200, 220}, {50, 50, 40, 40}};
    tiled(0, 0, 0, 0), tiled(1, 1, 0, 0);
    PPU.win.on[0] = true, PPU.win.rect[0] = r[n % 7], PPU.win.in[0] = PPU_BG0, PPU.win.out = PPU_BG1;
}
static void g_mosaic(int n) {
    (void)n;
    tiled(0, 1, 13, 7), PPU.bg[0].mosaic = true, PPU.mosaic.bg_w = 5, PPU.mosaic.bg_h = 3;
    affine_floor(3), PPU.bg[3].mosaic = true, PPU.bg[3].prio = 2;
    sprite(0, 13, 7, 0, 0), PPU.obj[0].mosaic = true;
    sprite(1, 100, 80, 0, 0), PPU.obj[1].mosaic = true, PPU.obj[1].affine = 0, PPU.affine[0] = (ppu_affine){200, 60, -60, 200};
    PPU.mosaic.obj_w = 4, PPU.mosaic.obj_h = 4;
}
static void g_lines(int n) {
    tiled(0, 1, 0, 0), tiled(1, 0, n, 0);
    PPU.line.scroll[1] = lscroll, PPU.line.backdrop = lback;
    PPU.win.on[0] = true, PPU.win.rect[0] = (ppu_rect){0, 240, 0, 160}, PPU.win.in[0] = PPU_BG1, PPU.win.out = PPU_BG0;
    PPU.line.win[0] = lspan;
}
static void g_fx_ev(int n) {
    tiled(0, 0, n, 0), tiled(1, 1, 3, 3);
    alpha_fx(PPU_BG0, PPU_BG1 | PPU_BACK, 8, 8);
    if (n % 2) PPU.fx.mode = FX_DARKEN, PPU.fx.evy = 8;
    PPU.line.fx_ev = lev;
}
static void g_stress(int n) {
    s_layer4(n);
    for (int i = 0; i < 128; i++) {
        uint32_t h = (uint32_t)i * 2654435761u;
        PPU.obj[i] = (ppu_obj){.on = true, .x = (int16_t)(h % 200 + (uint32_t)n), .y = (int16_t)(h / 200 % 120), .w = i % 4 ? 16 : 64,
                               .h = i % 4 ? 16 : 64, .prio = (uint8_t)(i % 4), .bank = (uint8_t)i, .affine = -1,
                               .mode = i % 16 == 0 ? OBJ_BLEND : OBJ_NORMAL, .idx = i % 4 ? spr[i % 32] : big};
    }
    PPU.fx.mode = FX_DARKEN, PPU.fx.first = PPU_BG0 | PPU_BG1, PPU.fx.evy = 5, PPU.fx.eva = 8, PPU.fx.evb = 8;
    windows();
}
static void g_reset(int n) { (void)n; tiled(0, 0, 0, 0); sprite(0, 10, 10, 0, 0); ppu_reset(); }

typedef struct { const char *name; scene_fn fn; int frames; char content; } scene;
static const scene S[] = {
    {"clear", s_clear, 1, 'A'},         {"layer1", s_layer1, HASH_FRAMES, 'A'},   {"layer1.opaque", s_layer1, HASH_FRAMES, 'B'},
    {"layers4", s_layer4, HASH_FRAMES, 'A'}, {"layers4.opaque", s_layer4, HASH_FRAMES, 'B'},
    {"sprites128", s_spr128, HASH_FRAMES, 'A'}, {"affine", s_affine, HASH_FRAMES, 'A'}, {"light", s_light, HASH_FRAMES, 'A'},
    {"mode0", s_mode0, HASH_FRAMES, 'A'}, {"mode7", s_mode7, HASH_FRAMES, 'A'}, {"max", s_max, HASH_FRAMES, 'A'},
    {"fx.alpha-window", s_alpha_win, HASH_FRAMES, 'A'}, {"fx.half-blend", s_half_blend, HASH_FRAMES, 'A'},
    {"g.banks", g_banks, 1, 'A'}, {"g.nonpow2-nowrap", g_nonpow2, 1, 'A'}, {"g.ties", g_ties, 2, 'A'},
    {"g.obj-order", g_obj_order, 1, 'A'}, {"g.obj-flip-clip", g_obj_flip_clip, 1, 'A'}, {"g.obj-affine", g_obj_affine, 1, 'A'},
    {"g.affine-bg", g_affine_bg, 1, 'A'}, {"g.bitmap", g_bitmap, 1, 'A'}, {"g.alpha-kinds", g_alpha_kinds, 8, 'A'},
    {"g.blend-sprites", g_blend_sprites, 4, 'A'}, {"g.windows", g_windows, 4, 'A'}, {"g.window-edges", g_window_edges, 7, 'A'},
    {"g.mosaic", g_mosaic, 1, 'A'}, {"g.lines", g_lines, HASH_FRAMES, 'A'}, {"g.fx-ev", g_fx_ev, 4, 'A'},
    {"g.stress", g_stress, HASH_FRAMES, 'A'}, {"g.reset", g_reset, 1, 'A'},
};
#define NSCENES ((int)(sizeof S / sizeof *S))

static uint64_t fnv(uint64_t h, const void *p, size_t n) {
    const uint8_t *b = p;
    for (size_t i = 0; i < n; i++) h = (h ^ b[i]) * 1099511628211ULL;
    return h;
}

static uint64_t run(const scene *s, bool again) {
    make_content(s->content);
    ppu_reset();
    set_palettes();
    uint64_t h = 14695981039346656037ULL;
    for (int n = 0; n < s->frames; n++) {
        if (n || again) ppu_reset(), set_palettes(); /* every frame is set up from scratch: no state may leak between frames */
        s->fn(n);
        ppu_render(frame);
        h = fnv(h, frame, sizeof frame);
    }
    return h;
}

int main(int argc, char **argv) {
    if (argc < 2) return fprintf(stderr, "usage: %s golden.txt [--update]\n", argv[0]), 2;
    bool update = argc > 2 && !strcmp(argv[2], "--update");
    uint64_t got[sizeof S / sizeof *S];
    int failures = 0;
    for (int i = 0; i < NSCENES; i++) {
        got[i] = run(&S[i], false);
        if (run(&S[i], true) != got[i]) failures++, fprintf(stderr, "%s: not repeatable (state leaks between renders)\n", S[i].name);
    }
    if (update) {
        FILE *f = fopen(argv[1], "w");
        if (!f) return perror(argv[1]), 2;
        for (int i = 0; i < NSCENES; i++) fprintf(f, "%s %016llx\n", S[i].name, (unsigned long long)got[i]);
        fclose(f);
        printf("wrote %d goldens to %s\n", NSCENES, argv[1]);
        return failures != 0;
    }
    FILE *f = fopen(argv[1], "r");
    if (!f) return perror(argv[1]), 2;
    char name[64];
    unsigned long long want;
    bool seen[sizeof S / sizeof *S] = {false};
    while (fscanf(f, "%63s %llx", name, &want) == 2) {
        int i = 0;
        while (i < NSCENES && strcmp(S[i].name, name)) i++;
        if (i == NSCENES) { failures++, fprintf(stderr, "golden for unknown scene %s\n", name); continue; }
        seen[i] = true;
        if (got[i] != want) failures++, fprintf(stderr, "%s: frame changed (golden %016llx, now %016llx)\n", name, want, (unsigned long long)got[i]);
    }
    fclose(f);
    for (int i = 0; i < NSCENES; i++) if (!seen[i]) failures++, fprintf(stderr, "no golden for %s\n", S[i].name);
    printf("%d scenes, %d failures\n", NSCENES, failures);
    return failures != 0;
}
