/* Per-line palette (PPU.line.pal_bg / pal_obj): a line may replace some entries of the backgrounds' or the sprites' palette, as a game's
 * HBlank palette writes do. Each case draws something made of one palette entry, replaces that entry on some lines, and checks every pixel:
 * the replaced lines have the new colour, every other line the registers'. */
#include <stdio.h>
#include <string.h>

#include "ppu.h"

#define RED 0xF800
#define GREEN 0x07E0
#define BLUE 0x001F
#define YELLOW 0xFFE0

static int failures, checks;
#define CHECK(c, ...)                                                                                       \
    do {                                                                                                    \
        checks++;                                                                                           \
        if (!(c)) failures++, fprintf(stderr, "%s:%d: CHECK(%s) ", __FILE__, __LINE__, #c), fprintf(stderr, __VA_ARGS__), fputc('\n', stderr); \
    } while (0)

static uint16_t frame[PPU_W * PPU_H];
static uint8_t tiles[2 * 64];
static uint16_t map[32 * 32];
static uint8_t spr[16 * 16];
static ppu_line_pal tab[PPU_H], tab_obj[PPU_H];

static void setup(void) {
    ppu_reset();
    memset(tab, 0, sizeof tab), memset(tab_obj, 0, sizeof tab_obj);
    for (int i = 0; i < 64; i++) tiles[64 + i] = 5; /* tile 1: all palette entry 5 */
    for (int i = 0; i < 32 * 32; i++) map[i] = 1;
    PPU.bg_pal[0] = YELLOW, PPU.bg_pal[5] = RED, PPU.bg_pal[16 + 5] = GREEN, PPU.bg_pal[6] = GREEN;
    PPU.obj_pal[3] = GREEN;
    memset(spr, 3, sizeof spr);
}

static void tiled(void) {
    PPU.layers = PPU_BG0;
    PPU.bg[0] = (ppu_bg){.mode = BG_TILES, .wrap = true, .tiles = tiles, .ntiles = 2, .map = map, .map_w = 32, .map_h = 32};
}

static uint16_t at(int x, int y) { return frame[y * PPU_W + x]; }

static bool row_is(int y, uint16_t c) {
    for (int x = 0; x < PPU_W; x++) if (at(x, y) != c) return false;
    return true;
}

int main(void) {
    /* a background: entry 5 is red, replaced by a gradient on lines 40..59 */
    setup(), tiled();
    for (int y = 40; y < 60; y++) tab[y].n = 1, tab[y].idx[0] = 5, tab[y].col[0] = (uint16_t)(y << 5);
    PPU.line.pal_bg = tab;
    ppu_render(frame);
    for (int y = 0; y < PPU_H; y++) CHECK(row_is(y, (y >= 40 && y < 60) ? (uint16_t)(y << 5) : RED), "tiles: line %d", y);

    /* a mosaic layer reads the palette on its own path */
    setup(), tiled();
    PPU.bg[0].mosaic = true;
    PPU.mosaic.bg_w = PPU.mosaic.bg_h = 3;
    tab[12].n = 1, tab[12].idx[0] = 5, tab[12].col[0] = BLUE;
    tab[13].n = 1, tab[13].idx[0] = 5, tab[13].col[0] = BLUE;
    tab[14].n = 1, tab[14].idx[0] = 5, tab[14].col[0] = BLUE;
    PPU.line.pal_bg = tab;
    ppu_render(frame);
    CHECK(row_is(12, BLUE) && row_is(13, BLUE) && row_is(14, BLUE) && row_is(11, RED) && row_is(15, RED), "mosaic tiles");

    /* the same, a layer turned and scaled (the other reader of the palette) */
    setup();
    for (int i = 0; i < 256 * 64; i++) (void)i;
    static uint8_t atiles[2 * 64];
    static uint16_t amap[16 * 16];
    for (int i = 0; i < 64; i++) atiles[64 + i] = 5;
    for (int i = 0; i < 16 * 16; i++) amap[i] = 1;
    PPU.layers = PPU_BG0;
    PPU.bg[0] = (ppu_bg){.mode = BG_AFFINE, .wrap = true, .tiles = atiles, .ntiles = 2, .map = amap, .map_w = 16, .map_h = 16,
                         .pa = 256, .pd = 256};
    tab[100].n = 1, tab[100].idx[0] = 5, tab[100].col[0] = BLUE;
    PPU.line.pal_bg = tab;
    ppu_render(frame);
    for (int y = 0; y < PPU_H; y++) CHECK(row_is(y, y == 100 ? BLUE : RED), "affine: line %d", y);

    /* a bank: a map entry's bank 1 reads entry 16 + 5 */
    setup(), tiled();
    for (int i = 0; i < 32 * 32; i++) map[i] = 1 | (1 << 12);
    tab[7].n = 1, tab[7].idx[0] = 16 + 5, tab[7].col[0] = BLUE;
    PPU.line.pal_bg = tab;
    ppu_render(frame);
    CHECK(row_is(7, BLUE) && row_is(6, GREEN) && row_is(8, GREEN), "bank");

    /* the backdrop: entry 0 on a line, nothing else shown; the frame is no longer one colour */
    setup();
    PPU.layers = 0;
    uint16_t one;
    CHECK(ppu_blank(&one) && one == YELLOW, "blank without a line palette");
    tab[20].n = 1, tab[20].idx[0] = 0, tab[20].col[0] = BLUE;
    PPU.line.pal_bg = tab;
    CHECK(!ppu_blank(&one), "a line palette is not blank");
    ppu_render(frame);
    for (int y = 0; y < PPU_H; y++) CHECK(row_is(y, y == 20 ? BLUE : YELLOW), "backdrop: line %d", y);
    /* and line_backdrop wins over it on its lines (it is the more specific write) */
    static uint16_t lback[PPU_H];
    for (int y = 0; y < PPU_H; y++) lback[y] = RED;
    PPU.line.backdrop = lback;
    ppu_render(frame);
    CHECK(row_is(20, RED), "line backdrop over a line palette");

    /* sprites: entry 3 of the sprites' palette, on the lines the sprite covers; the backgrounds' palette is left alone */
    setup();
    PPU.layers = PPU_OBJ;
    PPU.obj[0] = (ppu_obj){.on = true, .x = 100, .y = 40, .w = 16, .h = 16, .affine = -1, .idx = spr};
    for (int y = 44; y < 50; y++) tab_obj[y].n = 1, tab_obj[y].idx[0] = 3, tab_obj[y].col[0] = BLUE;
    PPU.line.pal_obj = tab_obj;
    ppu_render(frame);
    for (int y = 40; y < 56; y++)
        for (int x = 100; x < 116; x++) CHECK(at(x, y) == ((y >= 44 && y < 50) ? BLUE : GREEN), "sprite (%d, %d)", x, y);
    CHECK(at(99, 45) == YELLOW && at(116, 45) == YELLOW, "outside the sprite the backdrop");

    /* a sprite turned and scaled (the other reader of the sprites' palette) */
    setup();
    PPU.layers = PPU_OBJ;
    PPU.affine[0] = (ppu_affine){256, 0, 0, 256};
    PPU.obj[0] = (ppu_obj){.on = true, .x = 100, .y = 40, .w = 16, .h = 16, .affine = 0, .idx = spr};
    for (int y = 44; y < 50; y++) tab_obj[y].n = 1, tab_obj[y].idx[0] = 3, tab_obj[y].col[0] = BLUE;
    PPU.line.pal_obj = tab_obj;
    ppu_render(frame);
    CHECK(at(108, 46) == BLUE && at(108, 52) == GREEN, "affine sprite");

    /* several entries on one line (a table of colours), and sixteen is the most */
    setup(), tiled();
    for (int i = 0; i < 32 * 32; i++) map[i] = (uint16_t)(i % 2 ? 1 : 1);
    tab[30].n = 2, tab[30].idx[0] = 5, tab[30].col[0] = BLUE, tab[30].idx[1] = 6, tab[30].col[1] = YELLOW;
    PPU.line.pal_bg = tab;
    ppu_render(frame);
    CHECK(row_is(30, BLUE), "two entries on a line");

    /* the patch and restore of the renderer: lines after one another that change different entries, then the registers' palette changed
     * between two frames (the copy each core keeps is made again) */
    setup(), tiled();
    for (int y = 10; y < 14; y++) {
        tab[y].n = 1, tab[y].idx[0] = 5, tab[y].col[0] = (uint16_t)(0x0100 + y);
    }
    tab[14].n = 1, tab[14].idx[0] = 6, tab[14].col[0] = BLUE; /* the next line changes another entry: 5 must be back to red */
    tab[15].n = 2, tab[15].idx[0] = 5, tab[15].idx[1] = 6, tab[15].col[0] = BLUE, tab[15].col[1] = BLUE;
    PPU.line.pal_bg = tab;
    ppu_render(frame);
    for (int y = 10; y < 14; y++) CHECK(row_is(y, (uint16_t)(0x0100 + y)), "patch line %d", y);
    CHECK(row_is(14, RED) && row_is(15, BLUE) && row_is(16, RED) && row_is(9, RED), "restore after a patch");
    PPU.bg_pal[5] = YELLOW; /* a frame later the registers' palette is another */
    ppu_render(frame);
    CHECK(row_is(9, YELLOW) && row_is(14, YELLOW) && row_is(16, YELLOW) && row_is(11, (uint16_t)0x010B) && row_is(15, BLUE), "registers changed between frames");

    /* no table: the registers, exactly as before */
    setup(), tiled();
    ppu_render(frame);
    for (int y = 0; y < PPU_H; y++) CHECK(row_is(y, RED), "no table: line %d", y);

    printf("ppu_linepal: %d checks, %d failures\n", checks, failures);
    return failures != 0;
}
