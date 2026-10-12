/* The virtual picture processor: the Game Boy Advance's model, in software. A 240x160 frame is drawn line by line from
 * four background layers and 128 sprites over a backdrop colour, with palettes, alpha blending and fades, two
 * rectangular windows and an object window, mosaic, and per-line tables (what HBlank DMA did on the GBA: Mode 7
 * floors, wavy water, parallax bands, gradients). Nothing here knows about any genre.
 *
 * Pixels come in two kinds. Indexed: one byte per pixel, a palette index, 0 transparent (tiles, affine tiles,
 * indexed sprites); the palette entry used is index + 16 * bank, wrapping at 256, so a bank recolours a 16-colour
 * graphic as on the GBA. Direct: RGB565 with an optional 1-bit mask (bitmap layers, and sprites drawn from the
 * engine's runtime assets). Colours are RGB565 throughout.
 *
 * Draw order, back to front: the backdrop; then for priority 3 down to 0, the backgrounds of that priority (BG3 under
 * BG0) and then the sprites of that priority (sprite 127 under sprite 0). */
#pragma once
#include <stdbool.h>
#include <stdint.h>

#define PPU_W 240
#define PPU_H 160
#define PPU_BGS 4
#define PPU_OBJS 128
#define PPU_AFFINES 32

/* Layer bits, for blend targets and window masks. */
enum { PPU_BG0 = 1, PPU_BG1 = 2, PPU_BG2 = 4, PPU_BG3 = 8, PPU_OBJ = 16, PPU_BACK = 32, PPU_FX = 32 /* in windows */ };

typedef enum { BG_OFF, BG_TILES, BG_AFFINE, BG_BITMAP } ppu_bg_mode;

typedef struct {
    ppu_bg_mode mode;
    uint8_t prio;         /* 0 (front) .. 3 (back) */
    bool wrap;            /* the map or bitmap repeats; else outside it is transparent */
    bool mosaic;          /* blocky, by PPU.mosaic.bg_w x bg_h */
    const uint8_t *tiles; /* TILES, AFFINE: 8x8 tiles of 64 index bytes each, row by row */
    int ntiles;
    const uint16_t *rows; /* TILES, optional: ppu_tile_rows() of the tiles, to skip empty rows and copy opaque ones */
    const uint16_t *map;  /* TILES: tile | 0x400 hflip | 0x800 vflip | bank << 12. AFFINE: tile number (low byte) */
    int map_w, map_h;     /* in tiles */
    int scroll_x, scroll_y; /* TILES, BITMAP: the map pixel shown at the screen's top-left */
    /* AFFINE: screen pixel (x, y) shows map pixel (x0 + pa*x + pb*y, y0 + pc*x + pd*y); matrix 8.8, origin 24.8 */
    int32_t pa, pb, pc, pd, x0, y0;
    const uint16_t *bitmap; /* BITMAP: RGB565, bitmap_w x bitmap_h */
    const uint8_t *bitmap_mask; /* BITMAP: 1 bit per pixel, MSB first, rows of (w + 7) / 8 bytes; NULL: opaque */
    int bitmap_w, bitmap_h;
} ppu_bg;

enum { OBJ_NORMAL, OBJ_BLEND /* always a first blend target */, OBJ_WINDOW /* its shape is the object window */ };

typedef struct {
    bool on, hflip, vflip, mosaic;
    int16_t x, y;      /* top-left of the sprite's box on screen */
    uint8_t w, h;      /* source size in pixels, up to 128 x 128 */
    uint8_t prio;      /* 0..3: over backgrounds of the same priority */
    uint8_t bank;      /* indexed pixels use palette entry index + 16 * bank */
    uint8_t mode;      /* OBJ_NORMAL, OBJ_BLEND, OBJ_WINDOW */
    int8_t affine;     /* -1: none; else PPU.affine[affine] maps screen to source around the sprite's centre
                          (x + w/2, y + h/2); flips are then ignored */
    bool dbl;          /* with affine: draw within 2w x 2h around that centre, so a rotation is not cut */
    const uint8_t *idx;   /* indexed source, w x h bytes, 0 transparent; or */
    const uint16_t *rgb;  /* direct source, w x h RGB565 ... */
    const uint8_t *mask;  /* ... with this 1-bit mask (rows of (w + 7) / 8 bytes), NULL: opaque */
} ppu_obj;

typedef struct { int16_t pa, pb, pc, pd; } ppu_affine; /* 8.8: source step per screen x (pa, pc) and per y (pb, pd) */

typedef struct { int16_t x1, x2, y1, y2; } ppu_rect; /* [x1, x2) x [y1, y2) */

enum { FX_NONE, FX_ALPHA, FX_LIGHTEN, FX_DARKEN };

/* Per-line overrides, a value for each of the 160 lines; NULL keeps the register. */
typedef struct { int16_t x, y; } ppu_line_scroll;
typedef struct { int32_t pa, pc, x, y; } ppu_line_affine; /* the line's start (24.8) and step per pixel (8.8) */
#define PPU_LINE_OFF INT32_MIN /* as ppu_line_affine.x: the layer shows nothing on that line (a Mode 7 sky) */
typedef struct { int16_t x1, x2; } ppu_line_span;

typedef struct {
    uint8_t layers;  /* the layers drawn, PPU_BG0..PPU_OBJ bits (the GBA's display control); ppu_reset: all */
    ppu_bg bg[PPU_BGS];
    ppu_obj obj[PPU_OBJS];
    ppu_affine affine[PPU_AFFINES];
    uint16_t bg_pal[256], obj_pal[256]; /* RGB565; bg_pal[0] is the backdrop */
    struct {
        uint8_t mode, first, second; /* FX_*, and the layer bits of the first and second targets */
        uint8_t eva, evb, evy;       /* 0..16: alpha = (first * eva + second * evb) / 16; fades by evy / 16 */
    } fx;
    struct {
        bool on[2], obj_on;          /* windows 0 and 1, and the object window */
        ppu_rect rect[2];
        uint8_t in[2], obj_in, out;  /* what shows inside each window and outside them all: layer bits + PPU_FX */
    } win;
    struct { uint8_t bg_w, bg_h, obj_w, obj_h; } mosaic; /* 1 = off */
    struct {
        const ppu_line_scroll *scroll[PPU_BGS];
        const ppu_line_affine *affine[PPU_BGS];
        const ppu_line_span *win[2];  /* the windows' x span per line (their y span is then the whole screen) */
        const uint16_t *backdrop;     /* the backdrop colour per line */
        const uint8_t *fx_ev;         /* eva per line (evb = 16 - eva; evy = eva for fades) */
    } line;
} ppu_state;

extern ppu_state PPU;

void ppu_reset(void);           /* everything off, palettes black, mosaic 1, identity matrices, no tables */
void ppu_render(uint16_t *out); /* the frame, PPU_W x PPU_H RGB565, row after row */
/* For each of ntiles tiles: bit y set when its row y is all transparent, bit 8 + y when it has no transparent pixel. */
void ppu_tile_rows(const uint8_t *tiles, int ntiles, uint16_t *rows);
