/* pinyol engine core: shared types, the single game state G, and module APIs. */
#pragma once
#include <stdbool.h>
#include <stdint.h>
#include <stdio.h>

#include "cJSON.h"
#include "hal.h"

#define TICK_HZ 60 /* 60 Hz logic: walking is exactly 1 px per tick, so motion never stutters */
#define TICK_MS (1000.0f / TICK_HZ)
#define AUDIO_HZ 22050 /* mono PCM16 everywhere: 11 kHz of bandwidth keeps glass, birds and paper crisp */
#define MAX_STEMS 3    /* music layers per cue */
#define WORLD_W 240
#define WORLD_H 160
#define SCREEN_W 480
#define SCREEN_H 320
#define TILE 16
#define SCHEMA_VERSION 1

#define RGB(r, g, b) ((uint16_t)((((r) >> 3) << 11) | (((g) >> 2) << 5) | ((b) >> 3)))
/* Dossier p.24 base palette. The UI colours (ink, ochre, terra, paper, paper_sel, dim, brown) are
 * these defaults unless game.json "theme" overrides them (content.c): read them through G.th. */
#define D_INK RGB(0x19, 0x33, 0x2C)
#define C_INK (G.th.ink)
#define C_STONE RGB(0xC6, 0xBD, 0xA6)
#define C_CREAM RGB(0xE8, 0xDC, 0xC2)
#define C_WOOD RGB(0x8B, 0x65, 0x48)
#define D_OCHRE RGB(0xAF, 0x74, 0x3A)
#define C_OCHRE (G.th.ochre)
#define D_TERRA RGB(0xA9, 0x57, 0x43)
#define C_TERRA (G.th.terra)
#define C_GREEN RGB(0x42, 0x67, 0x51)
#define C_BLUEGRAY RGB(0x65, 0x7E, 0x88)
/* UI theme from the approved references: cream paper panels, dark ink text and borders */
#define D_PAPER RGB(0xF2, 0xE9, 0xD2)
#define C_PAPER (G.th.paper)
#define D_PAPER_SEL RGB(0xDF, 0xCF, 0xA8)
#define C_PAPER_SEL (G.th.paper_sel)
#define D_DIM RGB(0x8C, 0x85, 0x70)
#define C_DIM (G.th.dim)
#define D_BROWN RGB(0x5B, 0x40, 0x2E)
#define C_BROWN (G.th.brown)
#define C_BLACK 0x0000
#define C_WHITE 0xFFFF

/* ------------------------------------------------------------------ public API */
typedef struct {
    const char *game_dir; /* folder copied to the SD card, e.g. sd/games/mygame */
    const char *save_dir; /* NULL = <game_dir>/saves */
} bp_config;

bool game_init(const bp_config *cfg); /* false only if fonts/manifest are unreadable */
void game_shutdown(void);
void game_tick(const hal_input *in);
void game_render(uint16_t *native); /* SCREEN_W x SCREEN_H RGB565 */
bool game_quit_requested(void);
bool save_file_atomic(const char *path, const char *txt); /* a game's saves, never half-written (hal_save's work) */
void audio_mix(int16_t *out, int n); /* AUDIO_HZ mono; caller holds the audio lock */
void audio_mix_stereo(int16_t *out, int n); /* the same as left, right, left, right...: 2 n samples; panned sounds are placed */
int script_run(const char *path, void (*frame)(void)); /* 0 = all expectations passed */
int content_validate(void);                            /* number of errors, each logged */

/* The Lua libraries built into the engine (lib/<name>.lua, made into pinyol_lib.c by cmake/embed_lib.cmake) */
typedef struct { const char *name, *src; size_t len; } pinyol_lib_entry;
extern const pinyol_lib_entry pinyol_lib[]; /* ends with a NULL name */

/* ------------------------------------------------------------------ link.c: consoles playing together */
#define LINK_PAYLOAD 220 /* bytes of JSON a message carries */
#define LINK_PEERS 16    /* consoles heard at once */
#define LINK_QUEUE 64    /* messages waiting for the game; more and the oldest go */
typedef struct { uint32_t from; uint16_t len; char data[LINK_PAYLOAD + 1]; } link_msg;
enum { LINK_SENT, LINK_BUSY, LINK_TOO_BIG, LINK_OFF };
bool link_start(const char *game_id); /* the radio on for this game; false if the platform has none */
void link_stop(void);
bool link_active(void);
void link_tick(uint32_t ticks);       /* each game tick: what came in, hellos, consoles gone quiet */
int link_send(const char *data, int len, uint32_t to); /* LINK_*: to 0 is everyone */
bool link_recv(link_msg *m);          /* the oldest message waiting */
int link_peers(uint32_t *ids, int max);
uint32_t link_id(void);
void link_inject(uint32_t from, const char *json); /* tests: a message as if another console had sent it */
bool link_sent_lately(const char *text);           /* tests: one of the last 8 sent contains the text */

/* ------------------------------------------------------------------ lua_game.c: pinyol@2 games (docs/lua.md) */
bool v2_load(void);                   /* a fresh Lua state running main.lua and _init(); false on an error */
void v2_free(void);
void v2_tick(void);                   /* _update() */
void v2_meter_toggle(void);           /* the frame meter on the screen, or off (F3 on a desktop) */
void v2_draw_world(void);             /* _draw(), then the PPU into G.world */
const char *v2_error(void);           /* the script's error, or NULL */
bool v2_run(const char *code, bool expr, char *msg, int n); /* test scripts: run code or check an expression */
size_t v2_memory(void);               /* bytes the script's state holds */
typedef struct { uint32_t update, draw, ppu, ppu_max; } v2_times; /* microseconds */
void v2_timing(v2_times *t); /* the averages (and the longest picture) since the last call */

/* ------------------------------------------------------------------ gfx.c */
/* Where drawing goes. {buf, w, h} is a plain w x h buffer, row after row. A surface can also be a window of a bigger
 * frame (fw x fh) stored any way round: pixel (x, y) is px[(x - x0) * xs + (y - y0) * ys], and everything is clipped to
 * [x0, x0 + w) x [y0, y0 + h). Drawing a frame window by window gives the same pixels as drawing it whole: the console
 * draws straight into its panel strips this way (gfx_turned). swap: pixels are stored with their bytes swapped, as a
 * big-endian display bus wants them. part: which part of hal_parallel draws on it (0 or 1), for the scratch memory
 * drawing needs (each part its own). dither 1..16: a dissolve, packed pictures scaled (gfx_blit_ex) leave the pixels
 * under that level of a 4x4 ordered dither (in 2x2 cells) as they were. Fields left at 0 mean the plain buffer. */
typedef struct surface {
    uint16_t *px;
    int w, h;
    int x0, y0, xs, ys, fw, fh;
    bool swap;
    uint8_t part, dither;
} surface;
void v2_draw(surface *s); /* pinyol@2: the world 2x and the script's text and shapes, onto s (lua_game.c) */
void game_draw(surface *s, bool world_pass); /* the frame onto s, a window of it or all (game.c) */
surface gfx_clip(const surface *s, int x, int y, int w, int h); /* the part of s inside a rectangle (maybe empty) */
typedef struct { int x, y, w, h; } screen_rect;
#define PANEL_CORNER 12 /* rows at a panel's top and bottom its corners may leave open (cut corners are 8) */
void game_draw_world(void);                  /* only the zone into G.world: game_draw(s, true) starts with it */

typedef struct {
    char id[32];
    int w, h, frames, ax, ay, frame_ms;
    uint16_t *pixels; /* frames * w * h; NULL for a packed picture until gfx_pixels unpacks it */
    uint8_t *mask;    /* frames * stride * h, MSB first, 1 = opaque; NULL = opaque */
    bool missing;
    bool canvas;      /* made by the game while it runs (gfx_canvas): its pixels change */
    uint32_t gen;     /* a canvas: one more each time it is drawn on, so what was made from it is made again */
    /* packed (tools/png2asset.py --packed): a palette and each frame's columns, only their opaque runs */
    uint8_t *pk;            /* the .pk file, checked whole when loaded */
    const uint16_t *pal;    /* its colours (RGB565), in pk */
    const uint32_t *cols;   /* frames * w: where each column starts in pk */
    uint8_t bpp;            /* 4 or 8; 0: not packed */
    bool pk_opaque;         /* every column of every frame one run, top to bottom (no see-through) */
    /* in memory or not (gfx.c: the least recently drawn go when the pictures pass their budget) */
    bool pinned;            /* never let go: the PPU or a canvas keeps pointers into it */
    bool out;               /* let go: its data comes back from the card the next time it is asked for */
    uint32_t used;          /* the last frame it was asked for (gfx_new_frame) */
    size_t bytes;           /* its data in memory: file, pixels, mask */
} asset;

typedef struct {
    int w, h, stride;
    uint8_t adv[256];
    uint8_t *bits;
    uint8_t *box; /* per glyph, where its ink is: x0, x1, y0, y1 (ends exclusive); font_load fills it, after bits */
} font;

asset *gfx_asset(const char *id); /* cached, never NULL; missing files give a checkerboard */
/* A game's pictures share PIC_BUDGET bytes of memory. Past it, those not asked for in the frame being made go,
 * least recently asked for first, and come back by themselves when asked for again (a moment's load from the card):
 * a game's art can be far bigger than the console's memory, as long as each frame's fits. */
#define PIC_BUDGET (4u << 20)
void gfx_new_frame(void);           /* a frame starts: what it asks for stays in memory until the next one */
void gfx_pin(asset *a);             /* keep it: something holds pointers into its pixels */
void gfx_set_budget(size_t bytes);  /* (tests: a small budget, to let pictures go all the time) */
size_t gfx_picture_bytes(void);     /* the pictures in memory now */
asset *gfx_asset_opt(const char *id); /* the same, silent when the game leaves it out */
void gfx_reset(void);
void gfx_force_missing(const char *id);
bool gfx_opaque(const asset *a, int frame, int u, int v);
uint16_t *gfx_pixels(asset *a); /* its pixels (and mask) as RGB565: a packed picture unpacked, once; NULL: no memory */
/* At 1x, maybe mirrored; pal: another packed picture's colours for this one's (a variant), or NULL; tint >= 0: every
 * pixel that colour (RGB565: a flash, a shadow), else -1. */
void gfx_blit_flip(surface *s, const asset *a, int frame, int x, int y, bool flip_x, const asset *pal, int tint);
/* How a picture meets what is under it (img's alpha, add, sub, quarter), the PlayStation's four: BLEND_ALPHA mixes,
 * the others add, take away or add a quarter of the picture's light (scaled by alpha), each channel held to its range. */
enum { BLEND_ALPHA, BLEND_ADD, BLEND_SUB, BLEND_QUARTER };
void gfx_blit_mixed(surface *s, const asset *a, int frame, int x, int y, bool flip, int tint, unsigned alpha, int mode);
/* Frame 0, then halved `shade` times (gfx_shade) and tinted to dusk (gfx_tint_dusk): for a packed picture, in its
 * palette, the same pixels without going over them again */
void gfx_blit_lit(surface *s, const asset *a, int x, int y, int shade, bool dusk);
/* The same for any frame, its top `rows` only (a figure going down a step) */
void gfx_blit_lit_rows(surface *s, const asset *a, int frame, int x, int y, int rows, int shade, bool dusk);
/* From now on every packed picture is drawn pulled towards amber (0: not; 1-3: more): the Canto's light, in the
 * palettes, set before the strips and back to 0 after them */
void gfx_light_warm(int level);
void gfx_blit(surface *s, const asset *a, int frame, int x, int y, int rot, bool half);
void gfx_blit2x(surface *s, const asset *a, int frame, int x, int y);
void gfx_blit2x_look(surface *s, const asset *a, int frame, int x, int y, const asset *pal, int tint); /* (pal, tint: packed) */
void gfx_blit_rows(surface *s, const asset *a, int frame, int x, int y, int rows); /* top rows only */
void gfx_fill(surface *s, int x, int y, int w, int h, uint16_t c);
void gfx_frame(surface *s, int x, int y, int w, int h, uint16_t c);
void gfx_shade(surface *s, int x, int y, int w, int h); /* darken by half */
void gfx_upscale2x(const surface *src, surface *dst);
/* The same, leaving dst as it is wherever src has the key colour: a world drawn over a full-resolution background */
void gfx_upscale2x_key(const surface *src, surface *dst, uint16_t key);
void gfx_shade_except(surface *s, uint16_t key); /* a plain buffer darkened, but its key-coloured pixels */
/* Panel rows row0..row0+rows-1 of a portrait panel showing a fw x fh frame turned a quarter (the console's ST77922,
 * which cannot swap rows and columns): panel row r is frame column r (flip: fw-1-r), panel pixel p is frame row fh-1-p
 * (flip: p). out holds rows x fh pixels, row after row, as the panel takes them, with bytes swapped if swap. */
surface gfx_turned(uint16_t *out, int row0, int rows, int fw, int fh, bool flip, bool swap);
void gfx_tint_dusk(surface *s);
void gfx_tint_dusk_except(surface *s, uint16_t key); /* (a plain buffer: its key-coloured pixels stay) */
void gfx_panel(surface *s, int x, int y, int w, int h);               /* paper card: shadow, rounded ink border */
void gfx_plate(surface *s, int x, int y, int w, int h, uint16_t fill); /* small sign / name tag */
void gfx_disc(surface *s, int cx, int cy, int r, uint16_t c);
void gfx_tri(surface *s, int x, int y, int size, bool right, uint16_t c); /* down or right pointing */
uint16_t hex565(const char *hex, uint16_t dflt);
bool font_load(font *f, const char *path);
int utf8_cp1252(const char **p, const char *end); /* next char as cp1252, -1 if unencodable */
int font_width(const font *f, const char *s, int nbytes);
int font_draw(surface *sf, const font *f, int x, int y, const char *s, int nbytes, int maxchars,
              uint16_t col);
int text_wrap(const font *f, const char *s, int max_w, uint16_t *starts, uint16_t *lens, int max_lines);

/* ------------------------------------------------------------------ gfx_style.c: a game's own look */
typedef struct {
    uint16_t color, bottom, outline, shadow; /* bottom: the colour at the foot of the letters (a vertical gradient) */
    bool gradient, has_outline, has_shadow;
    int8_t sdx, sdy;     /* the shadow's offset in font pixels, -2..2 */
    uint8_t scale;       /* each font pixel k x k screen pixels */
    int8_t spacing;      /* font pixels added after each letter */
    uint8_t wave, shake; /* screen pixels: letters along a moving sine, or jittering */
    uint32_t tick;       /* when it was drawn: wave and jitter move with it */
} text_style;
int font_draw_styled(surface *sf, const font *f, int x, int y, const char *s, int nbytes, int maxchars,
                     const text_style *st);
/* The picture scaled (sx, sy; negative flips), turned by degrees about its centre; (x, y) is where its top-left
 * corner would be unturned. */
void gfx_blit_ex(surface *s, const asset *a, int frame, int x, int y, float sx, float sy, float degrees, const asset *pal,
                 int tint); /* pal, tint (-1: none): packed pictures not turned */
/* A box shaded from colour c1 (RGB888) at its top, or left if `across`, to c2 at its bottom, or right; dither as
 * for gfx_quad; mode and alpha (0..256) as gfx_blit_mixed. */
void gfx_grad(surface *s, int x, int y, int w, int h, const uint8_t c1[3], const uint8_t c2[3], bool across, bool dither,
              int mode, unsigned alpha);
/* A frame of the picture on any four corners, in order: top-left, top-right, bottom-right, bottom-left of the picture
 * (xy8: x, y of each, in eighths of a pixel; at most +-16000). lights: each corner's colour to light it by (0..255 a
 * channel, 128 as it is), blending across the quad; mode and alpha (0..256) as gfx_blit_mixed; dither: the PlayStation's
 * 4x4 on the lit colours. The picture must be unpacked (gfx_pixels). */
void gfx_quad(surface *s, const asset *a, int frame, const int16_t xy8[8], const uint8_t light[4][3], bool lights,
              int mode, unsigned alpha, bool dither);
void gfx_blit_scaled(surface *s, const asset *a, int frame, int bx0, int bx1, int by0, int by1, int32_t u, int32_t du,
                     int32_t v, int32_t dv, const asset *alt, int tint);
void gfx_nine(surface *s, const asset *a, int frame, int x, int y, int w, int h, int k); /* a frame from the picture's thirds */

/* ------------------------------------------------------------------ gfx_cache.c: pictures worked out once */
asset *pic_find(const void *key, int len, uint32_t frame);             /* kept for that key, or NULL */
asset *pic_make(const void *key, int len, int w, int h, uint32_t frame); /* a new see-through one to draw into */
void pic_done(asset *a);                                                 /* drawn: its mask */
void pic_reset(void);
/* gfx_style.c: where a turned picture lands, for one whose unturned top-left corner is at 0, 0 */
void gfx_blit_ex_bounds(const asset *a, float sx, float sy, float degrees, int *x0, int *y0, int *w, int *h);

/* ------------------------------------------------------------------ gfx_draw.c: free drawing and canvases */
#define GFX_POLY_MAX 64              /* corners of a polygon */
#define CANVAS_KEY 0xF81F            /* a canvas's see-through pixels; a game drawing this colour gets 0xF81E */
#define WORLD_KEY CANVAS_KEY         /* where an HD zone's world leaves its background to the HD picture (world.c) */
#define CANVAS_MAX_PX (1536 * 1024) /* pixels of all a game's canvases together: 3 MB */
void gfx_line(surface *s, int x0, int y0, int x1, int y1, uint16_t c);
void gfx_circ(surface *s, int cx, int cy, int r, uint16_t c, bool fill);
void gfx_poly(surface *s, const int16_t *xy, int n, uint16_t c, bool fill); /* xy: x0, y0, x1, y1, ... */
void gfx_canvas_mask(asset *a, int x, int y, int w, int h); /* after drawing on a canvas: its mask, there */
void gfx_canvas_shade(surface *s, int x, int y, int w, int h); /* darker, keeping see-through pixels */
asset *gfx_find(const char *id); /* a picture already in memory, or NULL; nothing is loaded */
/* A canvas w x h (or a copy of from), see-through; one of that name and size is cleared instead. NULL, or why not. */
const char *gfx_canvas(const char *id, int w, int h, const asset *from, asset **out);
int utf8_count(const char *s, int nbytes);

/* ------------------------------------------------------------------ state.c */
int flag_get(const char *name);
void flag_set(const char *name, int v);
void flags_reset(void);
void flagf_set(int v, const char *fmt, const char *a, const char *b);
int flagf_get(const char *fmt, const char *a, const char *b);
uint32_t crc32_buf(const uint8_t *p, size_t n);
bool save_write(const char *slot);
bool save_load(const char *slot);                     /* applies state on success */
bool save_peek(const char *slot, uint32_t *seq_out);  /* valid newest file of slot */
const char *save_newest(void);                       /* slot name or NULL */
void settings_load(void);
void settings_save(void);
const char *klaus_variant(const char *id); /* player sprites and portrait -> their _B (crossbody bag) art when chosen */

/* ------------------------------------------------------------------ content.c */
char *read_file(const char *path, long *len);
size_t fread_chunked(void *dst, size_t n, FILE *f); /* fread in pieces the sound mixer can slip between */
bool game_has(const char *rel); /* "folder/file" in the game: false only when surely not (its folder listed once) */
cJSON *json_file(const char *rel); /* parsed <game_dir>/<rel>, NULL + log on failure */
bool content_load(void);
bool content_has_bag(void);   /* the game has items: bag button and MENU opens it */
const char *content_bag_label(void); /* game.json "bag_label", default "Bolsa" */
bool content_has_notes(void); /* the game has a notebook */
void content_free(void);
cJSON *content_zone(const char *id);
cJSON *content_dialogue(const char *id); /* id without ".node" */
cJSON *jget(const cJSON *o, const char *key);
const char *jstr(const cJSON *o, const char *key);
int jint(const cJSON *o, const char *key, int dflt);
int jai(const cJSON *arr, int i, int dflt);  /* safe array access: content comes from an SD card */
const char *jas(const cJSON *arr, int i);   /* NULL when missing or not a string */
int content_tile_index(const char *name); /* "TS_STONE_03" -> atlas index, -1 if unknown */

/* ------------------------------------------------------------------ logic.c */
bool cond_eval(const cJSON *c);
void effects_run(const cJSON *list);
bool event_run(const char *id);
const char *invariants_check(void); /* NULL when all hold */
int enum_index(const char *flag, const cJSON *val);

/* ------------------------------------------------------------------ dialogue.c */
void dlg_open(const char *ref); /* "D_X", "D_X.node" or "@text" */
void dlg_say(const char *speaker, const char *text, const char *ill);
void dlg_show(const char *dlg_id, const char *item);
void dlg_tick(void);
void dlg_render(surface *s, bool shade); /* shade: darken what is under a close-up */
int dlg_opaque(screen_rect *r, bool *closeup); /* its opaque panels, corners left out; closeup: it shades the screen */
const char *dlg_text(void); /* text of the current line, for scripts */

/* ------------------------------------------------------------------ world.c */
bool world_enter(const char *zone, const char *spawn);
void world_tick(void);
void world_render(surface *world);
bool world_render_hd(surface *s, const surface *world); /* an HD zone onto a strip: false if the zone is not */
bool world_is_hd(void);                                  /* the zone drawn this frame is HD */
void world_render_marker(surface *native);
int world_card_y(int h);                                 /* top of a card of height h: 54, or low if Klaus is under */
bool world_box_free(float x, float y);
bool world_collides_at(float x, float y);
const cJSON *world_find(const char *id, float *x, float *y, bool *is_npc); /* visible target */
void world_update_target(void);
int world_path(int gx, int gy, int *dirs, int max); /* BFS steps toward tile; -1 none */
bool world_exit_rect(const char *to, int *x, int *y, int *w, int *h);
void world_footsteps(bool moved);
bool seq_skippable(void);
void seq_skip(void);
void seq_render(surface *s);
int button_hint(surface *s, int x, int y, const char *btn, const char *label, uint16_t col);
const cJSON *chapter_def(int i);
int chapter_current(void);
bool chapter_done(int i);
void chapter_begin(int i);
bool world_on_exit(float x, float y);
void world_use_item(const char *item, bool show);
void world_safe_position(void);

/* ------------------------------------------------------------------ seq.c */
void seq_start(const char *id);
void seq_tick(void);
void listen_start(const char *id);
void listen_tick(void);
void listen_render(surface *native);

/* ------------------------------------------------------------------ puzzle.c */
int p01_check(const cJSON *def, int x, int y, int rot); /* bitmask of matched anchors */
int p01_anchor_count(const cJSON *def);
void puzzle_open(const char *id);
void puzzle_tick(void);
void puzzle_render(surface *native);
void pattern_open(cJSON *def);
void pattern_tick(void);
void pattern_render(surface *native);
void drill_open(cJSON *def); /* drill.c: timed exercises ("type": "drill") */
void conduit_open(cJSON *def); /* conduit.c: elbows turned until the signal goes through ("type": "conduit") */
void conduit_tick(void);
void conduit_render(surface *native);
int conduit_trace(const cJSON *def, const int *orient, bool *complete, int *path, int *exits); /* pieces lit */
void order_open(cJSON *def); /* order.c: cards put in order by their marks ("type": "order") */
void order_tick(void);
void order_render(surface *native);
void drill_tick(void);
void drill_render(surface *native);
bool arena_busy(void);
uint16_t arena_bot(void);
bool arena_pattern_known(const char *step); /* a boss phase entry: a pattern or "pause" */ /* scripts: the keys a plain player would hold this tick */    /* a moment without control (the presentation, the fade out) */
bool arena_telling(void); /* the boss is warning: the music ducks */
const char *drill_phase(void); /* lead, demo, input, result: for scripts */

/* ------------------------------------------------------------------ audio.c */
void audio_ambient(const char *id, int fade_ms); /* crossfade the zone bed; NULL fades out */
int audio_music_start(const char *cue, float loop_at_s, float bar_s, const float *gains, int fade_ms);
void audio_music_layer(int stem, float gain, int fade_ms);
void audio_music_stop(int fade_ms);
bool audio_music_playing(void);
void audio_voice(const char *id); /* listening clips and spoken lines */
void audio_voice_stop(int fade_ms);
void audio_sfx(const char *id, float gain);
int audio_sfx_play(const char *id, float gain, float pitch, bool loop); /* a handle, or 0 */
int audio_sfx_play_pan(const char *id, float gain, float pitch, bool loop, float pan); /* pan -1 left .. 1 right */
void audio_sfx_pan(int handle, float pan);
/* Everything a sound can be asked: gain 0..1, pitch, loop (between loop_start and loop_end samples if both are given),
 * pan -1..1, and, if env, a volume envelope in seconds (attack up, decay down to sustain 0..1, release after a stop). */
typedef struct {
    float gain, pitch, pan;
    bool loop;
    int loop_start, loop_end;
    bool env;
    float attack, decay, sustain, release;
} sfx_opts;
int audio_sfx_play_opts(const char *id, const sfx_opts *o);
void audio_sfx_adjust(int handle, float gain, float pitch); /* negative: unchanged */
void audio_sfx_stop(int handle);
bool audio_sfx_playing(int handle);
bool audio_sfx_set(const char *id, int16_t *pcm, int n); /* a clip the game made; takes pcm (malloc'd) */
long audio_made_bytes(void);
void audio_preload(const char *id);
long audio_cache_bytes(void); /* RAM held by cached SFX: stays under a fixed budget */
void audio_bus(float amb, float mus, float amb_lowpass_hz, int fade_ms); /* ducking; lowpass 0 = open */
void audio_master(float gain, int fade_ms);
#define VOLUME_MAX 4
void audio_pause(bool paused);
void audio_music_clock(int src);        /* 0: music() stopped the song; its clock from 0 (1 WAV, 2 module) */
void audio_music_clock_locked(int src); /* (the same, the audio lock held: in a song's swap) */
bool audio_music_time(double *seconds); /* how far into the song the player hears now; false: none plays */
void audio_reset(void);
/* For the studio (studio.c), the audio lock held where it says so */
int audio_voice_start_locked(const int16_t *pcm, int n, float gain, float pitch, bool loop, int wait, float send_d,
                             float send_r); /* a handle */
void audio_voice_stop_locked(int handle);
bool audio_clip_pin(const char *id, const int16_t **pcm, int *n); /* loaded and kept while a track plays it */
void audio_clip_unpin(const int16_t *pcm);

/* The studio: a step sequencer in the audio thread (studio.c). Tracks play clips on steps, each at its sample. */
#define STUDIO_TRACKS 16
#define STUDIO_STEPS 64
void studio_tempo(float bpm, float swing);  /* swing: 50 (straight) to 75 percent, as an MPC's */
void studio_length(int steps);             /* steps in the pattern, 1..STUDIO_STEPS (16: a bar of 16ths) */
bool studio_track(int track, const char *sound, float gain, float pitch, int choke); /* sound NULL: unchanged */
void studio_steps(int track, const float *vel, int n, bool queued); /* 0 (off) to 1; queued: at the next bar */
void studio_play(int step);                /* from that step (0-based), at once */
void studio_stop(void);
bool studio_playing(void);
bool studio_pos(int *step, float *frac);   /* the step the player hears now and how far into it; false: none yet */
void studio_hit(int track, float vel);     /* the track's sound now, as a pad */
void studio_reset(void);
void studio_fx_free(void); /* the engine's end: the effects' memory back */
void studio_tick(int m);                   /* audio thread, lock held: starts the steps inside the next m samples */
void studio_mark(int n);                   /* audio thread, lock held: n samples were mixed (for studio_pos) */
void studio_replace_locked(const int16_t *old, const int16_t *pcm, int n); /* a made sound took old's place */
void studio_mix(float *acc, float *sd, float *sr, int m); /* audio thread: the synth tracks into acc and the sends */
void studio_fx(float *acc, const float *sd, const float *sr, int m); /* audio thread: echo, reverb, Lo-fi GBA */
typedef struct {
    float delay, feedback, tone; /* the echo: its time in steps (3 is a dotted 8th), repeats 0..0.95, tone 0..1 */
    int reverb;                  /* STUDIO_PLATE or STUDIO_GBA (two echoes, as Nintendo's GBA sound driver did) */
    float size, damp;            /* 0..1 */
    bool lofi;                   /* everything held at 13,379 Hz and 8 bits, as a GBA mixed it */
    bool gate;                   /* plate only: close its wet tail shortly after the reverb send falls silent */
} studio_fx_params;
#define STUDIO_PLATE 0
#define STUDIO_GBA 1
void studio_fx_set(const studio_fx_params *f);
void studio_fx_get(studio_fx_params *f);
void studio_sends(int track, float delay, float reverb); /* 0..1; negative keeps it */
#define STUDIO_ACCENT 1
#define STUDIO_SLIDE 2
void studio_notes(int track, const uint8_t *notes, const uint8_t *flags, int n, bool queued); /* MIDI (0 rest) */
void studio_note(int track, int note, bool accent); /* a note by hand on a synth track; 0 lets it go */
void audio_force_missing(const char *id);

/* Synthesised voices (psg.c), mixed with the rest: notes instead of recordings. */
#define PSG_VOICES 4
enum { PSG_SQUARE, PSG_TRIANGLE, PSG_SAW, PSG_SINE, PSG_NOISE };
typedef struct {
    uint8_t wave;        /* PSG_* */
    float freq, vol;     /* Hz; 0..1 */
    float duty;          /* square: the high part of each period, 0..1 */
    float attack, decay; /* seconds: up to full volume, then the time constant towards sustain */
    float sustain;       /* 0..1 of vol held after the decay; 0: the note ends by itself (a pluck) */
    float len, release;  /* seconds: when the note is let go (0: never by itself), and its fade after */
    float slide;         /* Hz per second added to the pitch (a laser, a drop) */
} psg_note;
void psg_play(int voice, const psg_note *n); /* starts at once, replacing what the voice played */
void psg_release(int voice);
void psg_reset(void);
void psg_mix(float *acc, int m); /* audio thread, lock held */
float psg_note_hz(const char *name); /* "A4" = 440, "C#3", "Eb5"; 0 if not a note */

/* Sounds made from numbers (synth.c), in the spirit of sfxr: rendered into a clip, played by sfx(). */
#define SYNTH_MAX_S 4.0f /* seconds a made sound lasts at most */
typedef struct {
    int wave;                             /* PSG_* */
    float freq, freq_min;                 /* Hz: the start, and the floor where a falling sound ends (0: none) */
    float slide, slide_accel;             /* Hz per second the pitch moves, and per second squared */
    float vibrato, vibrato_speed;         /* depth 0..1, Hz */
    float arp, arp_time;                  /* the pitch times arp after arp_time seconds (a coin's jump) */
    float duty, duty_sweep;               /* square: its high part 0..1, and how it moves per second */
    float attack, sustain, punch, decay;  /* seconds, and punch 0..1: louder at the start of the sustain */
    float lowpass, lowpass_sweep, resonance; /* 0..1 (1 open), per second, 0..1 */
    float highpass, highpass_sweep;       /* 0..1 (0 open), per second */
    float repeat, volume;                 /* seconds before it starts again (0: never), 0..1 */
    uint32_t seed;                        /* the noise's */
} synth_params;
void synth_defaults(synth_params *p);
void synth_clamp(synth_params *p);
int synth_render(const synth_params *p, int16_t *out, int max); /* samples at AUDIO_HZ */
bool synth_recipe(const char *kind, uint32_t seed, synth_params *p); /* coin, laser, explosion, powerup, hit, jump, blip, random */

/* Tracker music (modplay.c): a ProTracker .mod, looped. */
/* mic.c: the microphone for Lua games, worked out once a tick */
bool mic_open(void);  /* false: no microphone */
void mic_close(void); /* (a recording under way is kept) */
void mic_tick(void);
bool mic_read(float *level, float *pitch, bool *hit, bool *recording, const char **kind); /* false: not listening.
     * kind: "blow", "voice", "whistle", "clap" or NULL */
bool mic_record(const char *id, float seconds); /* into a sound, sfx(id), when the time is up or on stop */
void mic_record_stop(void);
void mic_inject(bool present, float level, float hz, bool breath); /* tests: a tone (hz 0: noise; breath: blowing) */
int device_led(void); /* lua_device.c: the colour a game set the LED to, -1 none (tests) */
void device_fake_battery(bool on, bool have, float level, bool charging); /* tests: a battery, or none */

bool mod_play(const char *path, float gain); /* false if it cannot be read or played */
void mod_stop(int fade_ms);
bool mod_playing(void);
void mod_reset(void);
void mod_mix(float *acc, int m); /* audio thread, lock held, m <= 256 */

/* ------------------------------------------------------------------ music.c */
void music_tick(void);
void music_force(const char *cue); /* sequence override until the next zone */
void music_hush(void);             /* fade the ambience out until the next zone */
void music_zone_changed(void);
void music_reset(void);
void sound(const char *what);      /* named UI/feedback sound from music.json "sfx" */
bool wav_parse(FILE *f, long *data_start, long *data_len, int *chans);

/* ------------------------------------------------------------------ ui.c */
void ui_toast(const char *msg);
void ui_toast_queue(const char *msg); /* after the one showing (notes that arrive together) */
void ui_toast_tick(void);
void ui_toast_clear(void);
void title_tick(void), title_render(surface *s);
void pause_tick(void), pause_render(surface *s);
void inv_tick(void), inv_render(surface *s, bool shade);
void notes_tick(void), notes_render(surface *s, bool shade);
void end_tick(void), end_render(surface *s);
void error_tick(void), error_render(surface *s);
void hud_tick(void), hud_render(surface *s);
void game_error(const char *fmt, const char *arg);

/* ------------------------------------------------------------------ game.c */
typedef enum { L_TITLE = 1, L_PLAY, L_DLG, L_INV, L_NOTES, L_PUZZLE, L_SEQ, L_LISTEN, L_PAUSE, L_END, L_ERROR, L_ARENA } layer_id;
void layer_push(layer_id l);
void layer_remove(layer_id l);
bool layer_has(layer_id l);
layer_id layer_top(void);
void layers_reset(layer_id base);

/* ------------------------------------------------------------------ arena.c (side-view boss fight) */
void arena_start(const char *id); /* effect ["arena", ID]: arena.json entry, pushed over the zone */
void arena_practice(bool on);     /* ["arena", ID, "practice"]: winning runs "practice_win", never "win" */
void arena_tick(void);
void arena_render_world(surface *world), arena_render_screen(surface *world, surface *scr);
void arena_free(void);
const char *arena_state(const char *who);       /* "boss" / "player": state name, for scripts */
bool arena_value(const char *field, int *out); /* player_hp, boss_hp, resonance, phase, gap */
bool arena_poke(const char *field, int v);     /* debug: boss_hp, resonance, player_hp */
void game_new(void);
bool game_continue(const char *slot);
void game_to_title(void);
const font *ui_font(void); /* regular, normal or large per settings */
const font *ui_bold(void); /* names, signs, buttons */
void text_center(surface *s, const font *f, int cx, int y, const char *t, uint16_t col);

/* ------------------------------------------------------------------ state of one running game */
enum { DIR_N, DIR_E, DIR_S, DIR_W };

typedef struct {
    uint16_t held, pressed;
    bool touch, tap, release;
    int px, py;
} input_state;

typedef struct {
    bool active;
    cJSON *file, *node;
    char file_id[32], node_id[48];
    int line_idx;
    char speaker[24];
    int expr;
    bool is_sub;
    const char *text;
    char own[512];
    const char *ill;
    int nlines;
    uint16_t ls[48], ll[48];
    int page, shown;
    int hold; /* ticks of silence after a line with "pause" */
    bool choosing;
    cJSON *choices[16];
    int nchoices, sel;
    uint8_t choice_rows[16];     /* wrapped lines of each choice (dialogue.c, choice_lines) */
    const void *choice_rows_font; /* the font they were counted with; NULL: count again */
    cJSON *pending_choice; /* choice whose Klaus line is showing */
    const char *pending_target;
    bool wrapped_large;
    bool single;           /* one-off line without a node */
} dlg_state;

typedef struct {
    char id[8];
    cJSON *def;
    int tw, th;
    uint8_t *layer[3]; /* floor, wall_back, front; 0xFF = empty */
    uint8_t *solid;
    bool exterior;
} zone_rt;

typedef struct {
    float x, y; /* feet anchor, logical px */
    int facing;
    bool moving;
    float act_ms;     /* remaining one-shot action anim */
    float sink;       /* px hidden at the feet (going down stairs) */
    const char *anim; /* override by sequences */
} klaus_state;

typedef struct {
    cJSON *steps;
    int idx;
    float t, dur;
    bool step_started;
    char prop[24];
    float pdx, pdy; /* visual offset of the moving prop */
    float wdx, wdy; /* the player's walk, in px over the step */
    char fprop[24];
    int fframe;
    float cdx, cdy, cam_x, cam_y; /* camera tween */
    float fade;                   /* 0..1 black overlay */
    float bg_vol;
    cJSON *skip;                  /* effects run when the player skips it (C), NULL = not skippable */
} seq_state;

typedef struct {
    cJSON *def;
    char id[8];
    float t, max;
    int cue;
    const char *sub;
    float pulse;
} listen_state;

typedef struct {
    cJSON *def;
    int x, y, rot, help;
    bool drag, moved, solved, rotating;
    int gx, gy;
    const char *msg;
} puzzle_state;

/* The player character, from game.json "player" {"speaker", "sprite"}; default Klaus ("KLAUS", "KL"). */
typedef struct {
    char speaker[24], portrait[24], prefix[10];
    char idle[24], walk[24], interact[24], listen[24], descend[24];
    bool bag_option; /* Options offer the _B (crossbody bag) art: default Klaus, or "bag_option": true */
} player_ids;

/* game.json "theme": UI colours as "#RRGGBB" and "corners": "round" (default) or "cut" (mecha). */
typedef struct {
    uint16_t ink, ochre, terra, paper, paper_sel, dim, brown;
    bool cut;
} ui_theme;

typedef struct {
    bp_config cfg;
    char game_dir[256], save_dir[256];
    cJSON *game, *tiles, *items, *events, *notebook, *sequences, *listens, *puzzles, *music;
    cJSON *dialogues, *zones; /* lazy caches: id -> parsed file */
    layer_id stack[16];
    int nstack;
    input_state in;
    zone_rt zone;
    klaus_state klaus;
    player_ids pl;
    ui_theme th;
    const cJSON *target;
    bool target_npc;
    float target_x, target_y;
    int target_cycle;
    dlg_state dlg;
    seq_state seq;
    listen_state lis;
    puzzle_state pz;
    int menu_sel, inv_sel, inv_sub, notes_sel;
    bool inv_menu;
    const char *using_item;
    bool large_text, portraits;
    int volume; /* 0..VOLUME_MAX, pause menu */
    bool tones; /* speakers' "blip" while their text runs, pause menu */
    bool bag; /* Klaus carries: false = backpack (dossier), true = crossbody bag (Options) */
    char toast[96];
    float toast_ms;
    char error[192];
    float anim_ms;
    uint32_t save_seq;
    bool exit_guard, quit, autosave_enabled;
    unsigned draws; /* frames drawn: render code that looks things up once a frame keys on it (game_draw) */
    bool v2;        /* game.json "engine": "pinyol@2": a Lua game on the PPU (lua_game.c), none of the v1 layers */
    unsigned objective_at; /* G.draws when objective was looked up (world.c), reset with G at every game_init */
    const cJSON *objective;
    bool can_continue, can_load_prefinal; /* cached when a menu screen opens: no SD reads per frame */
    char missing_zone[8];
    font font, font_l, bold, bold_l;
    float banner_ms; /* zone name card on arrival */
    uint16_t world[WORLD_W * WORLD_H];
    uint32_t ticks;
} game;

extern game G;
