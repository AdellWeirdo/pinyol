/* The virtual picture processor's rules, one small scene each, checked on chosen pixels (src/ppu.h). */
#include <stdio.h>
#include <string.h>

#include "ppu.h"

static int failures, checks;
#define CHECK(c)                                                                  \
    do {                                                                          \
        checks++;                                                                 \
        if (!(c)) failures++, fprintf(stderr, "%s:%d: CHECK(%s)\n", __FILE__, __LINE__, #c); \
    } while (0)

static uint16_t fb[PPU_H][PPU_W];
static uint8_t tiles[4 * 64];
static uint16_t map[32 * 32];

#define RED 0xF800
#define GREEN 0x07E0
#define BLUE 0x001F
#define WHITE 0xFFFF
#define GREY 0x8410

/* tile 0 empty; tile 1 solid colour 1; tile 2 colour 2 on its left half only; tile 3 a single dot of colour 3 at (0,0) */
static void setup(void) {
    ppu_reset();
    memset(tiles, 0, sizeof tiles);
    for (int i = 0; i < 64; i++) tiles[64 + i] = 1, tiles[128 + i] = (i % 8) < 4 ? 2 : 0;
    tiles[192] = 3;
    PPU.bg_pal[0] = GREY, PPU.bg_pal[1] = RED, PPU.bg_pal[2] = GREEN, PPU.bg_pal[3] = BLUE, PPU.bg_pal[17] = WHITE;
    memset(map, 0, sizeof map);
}

static void tiled(int n, int prio) {
    PPU.bg[n] = (ppu_bg){.mode = BG_TILES, .prio = (uint8_t)prio, .wrap = true, .tiles = tiles, .ntiles = 4,
                         .map = map, .map_w = 32, .map_h = 32};
}

static void backdrop_only(void) {
    setup();
    ppu_render(&fb[0][0]);
    CHECK(fb[0][0] == GREY && fb[159][239] == GREY);
}

static void tiles_scroll_flip_bank(void) {
    setup();
    tiled(0, 0);
    map[0] = 1;                          /* tile (0,0) solid red */
    map[1] = 2 | 0x400;                  /* tile (1,0) green, flipped: right half */
    map[2] = 1 | 1 << 12;                /* tile (2,0) bank 1: colour 1 + 16 = 17, white */
    map[32] = 3 | 0x800;                 /* tile (0,1) the dot, flipped vertically: at (0, 15) */
    ppu_render(&fb[0][0]);
    CHECK(fb[0][0] == RED && fb[7][7] == RED);
    CHECK(fb[0][8] == GREY && fb[0][12] == GREEN && fb[0][15] == GREEN);
    CHECK(fb[3][16] == WHITE);
    CHECK(fb[15][0] == BLUE && fb[8][0] == GREY);
    PPU.bg[0].scroll_x = 4, PPU.bg[0].scroll_y = 2;
    ppu_render(&fb[0][0]);
    CHECK(fb[0][0] == RED && fb[0][3] == RED && fb[0][4] == GREY && fb[0][8] == GREEN);
    CHECK(fb[13][0] == GREY && fb[13][4] == GREY); /* the dot moved to (-4, 13): off screen */
    PPU.bg[0].scroll_x = -8, PPU.bg[0].scroll_y = 0; /* wrap: the map's last column on the left */
    map[31] = 1;
    ppu_render(&fb[0][0]);
    CHECK(fb[0][0] == RED && fb[0][8] == RED);
    PPU.bg[0].wrap = false;
    ppu_render(&fb[0][0]);
    CHECK(fb[0][0] == GREY && fb[0][8] == RED);
}

static void priorities(void) {
    setup();
    tiled(0, 1);
    tiled(1, 1);
    static uint16_t map1[32 * 32];
    memset(map1, 0, sizeof map1);
    PPU.bg[1].map = map1;
    map[0] = 2;  /* BG0: green, left half */
    map1[0] = 1; /* BG1: solid red */
    ppu_render(&fb[0][0]);
    CHECK(fb[0][0] == GREEN && fb[0][6] == RED); /* same priority: BG0 over BG1 */
    PPU.bg[1].prio = 0;
    ppu_render(&fb[0][0]);
    CHECK(fb[0][0] == RED);                      /* a lower priority number is in front */
}

static uint8_t spr_idx[8 * 8];
static uint16_t spr_rgb[4 * 4];
static uint8_t spr_mask[4] = {0xA0, 0xF0, 0xF0, 0xF0}; /* row 0: pixels 0 and 2 only */

static void sprites(void) {
    setup();
    tiled(0, 1);
    map[0] = 1;
    memset(spr_idx, 0, sizeof spr_idx);
    for (int i = 0; i < 8; i++) spr_idx[i] = 2; /* the top row, colour 2 */
    spr_idx[8 * 7] = 1;                           /* bottom-left dot, colour 1 */
    PPU.obj_pal[2] = BLUE, PPU.obj_pal[1] = WHITE, PPU.obj_pal[18] = GREEN;
    PPU.obj[5] = (ppu_obj){.on = true, .x = 0, .y = 0, .w = 8, .h = 8, .prio = 1, .affine = -1, .idx = spr_idx};
    ppu_render(&fb[0][0]);
    CHECK(fb[0][0] == BLUE && fb[0][7] == BLUE);  /* over a background of the same priority */
    CHECK(fb[3][3] == RED);                       /* transparent pixels show the background */
    CHECK(fb[7][0] == WHITE);
    PPU.obj[5].prio = 2;
    ppu_render(&fb[0][0]);
    CHECK(fb[0][0] == RED);                       /* behind a background in front of it */
    PPU.obj[5].prio = 0, PPU.obj[5].vflip = true;
    ppu_render(&fb[0][0]);
    CHECK(fb[7][3] == BLUE && fb[0][0] == WHITE);
    PPU.obj[5].vflip = false, PPU.obj[5].hflip = true;
    ppu_render(&fb[0][0]);
    CHECK(fb[7][7] == WHITE && fb[7][0] == RED);
    PPU.obj[5].hflip = false, PPU.obj[5].bank = 1;
    ppu_render(&fb[0][0]);
    CHECK(fb[0][0] == GREEN);                     /* colour 2 + 16 */
    /* sprite 3 over sprite 5 */
    for (int i = 0; i < 16; i++) spr_rgb[i] = GREY + 1;
    PPU.obj[3] = (ppu_obj){.on = true, .x = 0, .y = 0, .w = 4, .h = 4, .affine = -1, .rgb = spr_rgb, .mask = spr_mask};
    ppu_render(&fb[0][0]);
    CHECK(fb[0][0] == GREY + 1 && fb[0][1] == GREEN && fb[0][2] == GREY + 1 && fb[1][1] == GREY + 1);
    PPU.obj[3].on = false;
    /* off the screen's edges */
    PPU.obj[5].x = -4, PPU.obj[5].y = 156, PPU.obj[5].bank = 0;
    ppu_render(&fb[0][0]);
    CHECK(fb[156][0] == BLUE && fb[156][3] == BLUE && fb[156][4] == GREY);
}

static void affine(void) {
    setup();
    map[0] = 1, map[1] = 2, map[32] = 3;
    tiled(0, 0);
    ppu_render(&fb[0][0]);
    static uint16_t ref[PPU_H][PPU_W];
    memcpy(ref, fb, sizeof fb);
    PPU.bg[0] = (ppu_bg){.mode = BG_AFFINE, .wrap = true, .tiles = tiles, .ntiles = 4, .map = map, .map_w = 32,
                         .map_h = 32, .pa = 256, .pd = 256};
    ppu_render(&fb[0][0]);
    CHECK(!memcmp(ref, fb, sizeof fb));           /* the identity matrix is the plain tile layer */
    PPU.bg[0].pa = 128, PPU.bg[0].pd = 128;       /* zoom 2x: tile (0,0) covers 16x16 */
    ppu_render(&fb[0][0]);
    CHECK(fb[15][15] == RED && fb[0][16] == GREEN && fb[0][23] == GREEN && fb[0][24] == GREY);
    static ppu_line_affine rows[PPU_H];            /* per line: every line samples map row 0 */
    for (int y = 0; y < PPU_H; y++) rows[y] = (ppu_line_affine){.pa = 256, .pc = 0, .x = 0, .y = 0};
    PPU.line.affine[0] = rows;
    ppu_render(&fb[0][0]);
    CHECK(fb[100][0] == RED && fb[100][8] == GREEN);
    PPU.line.affine[0] = NULL;
    /* a rotated sprite: 90 degrees maps its top row to its right column */
    memset(spr_idx, 0, sizeof spr_idx);
    for (int i = 0; i < 8; i++) spr_idx[i] = 2;
    PPU.obj_pal[2] = BLUE;
    PPU.bg[0].mode = BG_OFF;
    PPU.affine[1] = (ppu_affine){.pa = 0, .pb = 256, .pc = -256, .pd = 0};
    PPU.obj[0] = (ppu_obj){.on = true, .x = 40, .y = 40, .w = 8, .h = 8, .affine = 1, .idx = spr_idx};
    ppu_render(&fb[0][0]);
    int blue = 0;
    for (int y = 40; y < 48; y++)
        for (int x = 40; x < 48; x++) blue += fb[y][x] == BLUE;
    CHECK(blue == 8);
    CHECK(fb[40][47] == BLUE && fb[47][47] == BLUE && fb[40][40] == GREY);
}

static void effects(void) {
    setup();
    tiled(0, 0);
    tiled(1, 1);
    static uint16_t map1[32 * 32];
    for (int i = 0; i < 32 * 32; i++) map1[i] = 1; /* BG1 all red */
    PPU.bg[1].map = map1;
    map[0] = 2;                                   /* BG0 green on its left half */
    PPU.fx.mode = FX_ALPHA, PPU.fx.first = PPU_BG0, PPU.fx.second = PPU_BG1, PPU.fx.eva = 8, PPU.fx.evb = 8;
    ppu_render(&fb[0][0]);
    CHECK(fb[0][0] == ((31 / 2) << 11 | (63 / 2) << 5)); /* half green, half red */
    CHECK(fb[0][5] == RED);
    PPU.fx.mode = FX_DARKEN, PPU.fx.first = PPU_BG1, PPU.fx.evy = 16;
    ppu_render(&fb[0][0]);
    CHECK(fb[0][5] == 0 && fb[0][0] == GREEN);
    PPU.fx.mode = FX_LIGHTEN, PPU.fx.evy = 16;
    ppu_render(&fb[0][0]);
    CHECK(fb[0][5] == WHITE);
    /* window 0 on x 100..120: inside only BG1 and effects; outside BG0 and BG1, no effects */
    PPU.fx.mode = FX_DARKEN, PPU.fx.first = PPU_BG0 | PPU_BG1, PPU.fx.evy = 16;
    for (int i = 0; i < 32 * 32; i++) map[i] = 1 | 0; /* BG0 all colour 1 ... */
    PPU.bg_pal[1] = RED;
    PPU.win.on[0] = true, PPU.win.rect[0] = (ppu_rect){100, 120, 0, 160};
    PPU.win.in[0] = PPU_BG1 | PPU_FX, PPU.win.out = PPU_BG0 | PPU_BG1;
    ppu_render(&fb[0][0]);
    CHECK(fb[10][110] == 0 && fb[10][99] == RED && fb[10][120] == RED);
}

static void mosaic_and_lines(void) {
    setup();
    tiled(0, 0);
    map[0] = 3; /* one blue dot at (0,0) */
    PPU.bg[0].mosaic = true, PPU.mosaic.bg_w = 4, PPU.mosaic.bg_h = 4;
    ppu_render(&fb[0][0]);
    CHECK(fb[0][0] == BLUE && fb[3][3] == BLUE && fb[0][4] == GREY && fb[4][0] == GREY);
    PPU.bg[0].mosaic = false;
    static ppu_line_scroll sc[PPU_H];
    for (int y = 0; y < PPU_H; y++) sc[y] = (ppu_line_scroll){.x = (int16_t)(y == 0 ? -10 : 0), .y = 0};
    PPU.line.scroll[0] = sc;
    ppu_render(&fb[0][0]);
    CHECK(fb[0][10] == BLUE && fb[0][0] == GREY);
    PPU.line.scroll[0] = NULL;
    /* a mosaic sprite off the block grid: block edges fall outside its box, and stay outside its pixels */
    static uint8_t blk[3 * 3];
    memset(blk, 1, sizeof blk);
    PPU.obj_pal[1] = RED;
    PPU.obj[0] = (ppu_obj){.on = true, .x = 6, .y = 6, .w = 3, .h = 3, .affine = -1, .mosaic = true, .idx = blk};
    PPU.mosaic.obj_w = PPU.mosaic.obj_h = 4;
    ppu_render(&fb[0][0]);
    CHECK(fb[6][6] == GREY && fb[8][8] == RED && fb[9][9] == GREY);
    PPU.obj[0].on = false;
    static uint16_t back[PPU_H];
    for (int y = 0; y < PPU_H; y++) back[y] = (uint16_t)y;
    PPU.line.backdrop = back;
    ppu_render(&fb[0][0]);
    CHECK(fb[50][100] == 50 && fb[159][0] == 159);
}

static void object_window_and_blend_sprite(void) {
    setup();
    tiled(0, 0);
    for (int i = 0; i < 32 * 32; i++) map[i] = 1; /* BG0 all red */
    memset(spr_idx, 1, sizeof spr_idx);
    PPU.obj[0] = (ppu_obj){.on = true, .x = 20, .y = 20, .w = 8, .h = 8, .affine = -1, .mode = OBJ_WINDOW, .idx = spr_idx};
    PPU.win.obj_on = true, PPU.win.obj_in = 0, PPU.win.out = PPU_BG0;
    ppu_render(&fb[0][0]);
    CHECK(fb[24][24] == GREY && fb[10][10] == RED); /* a hole in BG0 the sprite's shape */
    setup();
    memset(spr_idx, 1, sizeof spr_idx);
    PPU.obj_pal[1] = WHITE;
    PPU.obj[0] = (ppu_obj){.on = true, .x = 0, .y = 0, .w = 8, .h = 8, .affine = -1, .mode = OBJ_BLEND, .idx = spr_idx};
    PPU.fx.second = PPU_BACK, PPU.fx.eva = 8, PPU.fx.evb = 8;
    PPU.bg_pal[0] = 0;
    ppu_render(&fb[0][0]);
    CHECK(fb[0][0] == (15 << 11 | 31 << 5 | 15)); /* half white over black, with no blend mode set */
}

static uint16_t bmp[16 * 8];
static uint8_t bmp_mask[2 * 8];

static void bitmaps(void) {
    setup();
    for (int i = 0; i < 16 * 8; i++) bmp[i] = (uint16_t)(1000 + i);
    memset(bmp_mask, 0xFF, sizeof bmp_mask);
    bmp_mask[0] = 0x7F; /* pixel (0,0) transparent */
    PPU.bg[2] = (ppu_bg){.mode = BG_BITMAP, .bitmap = bmp, .bitmap_mask = bmp_mask, .bitmap_w = 16, .bitmap_h = 8};
    ppu_render(&fb[0][0]);
    CHECK(fb[0][0] == GREY && fb[0][1] == 1001 && fb[7][15] == 1000 + 7 * 16 + 15 && fb[0][16] == GREY);
    PPU.bg[2].wrap = true, PPU.bg[2].scroll_x = 1;
    ppu_render(&fb[0][0]);
    CHECK(fb[0][0] == 1001 && fb[0][15] == GREY && fb[8][1] == 1002);
}

int main(void) {
    backdrop_only();
    tiles_scroll_flip_bank();
    priorities();
    sprites();
    affine();
    effects();
    mosaic_and_lines();
    object_window_and_blend_sprite();
    bitmaps();
    printf("ppu: %d checks, %d failed\n", checks, failures);
    return failures != 0;
}
