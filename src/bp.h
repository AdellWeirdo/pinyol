/* Bajo Pueblo engine core: shared types, the single game state G, and module APIs. */
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
    const char *game_dir; /* folder copied to the SD card, e.g. sd/games/bajopueblo */
    const char *save_dir; /* NULL = <game_dir>/saves */
} bp_config;

bool game_init(const bp_config *cfg); /* false only if fonts/manifest are unreadable */
void game_shutdown(void);
void game_tick(const hal_input *in);
void game_render(uint16_t *native); /* SCREEN_W x SCREEN_H RGB565 */
bool game_quit_requested(void);
void audio_mix(int16_t *out, int n); /* AUDIO_HZ mono; caller holds the audio lock */
int script_run(const char *path, void (*frame)(void)); /* 0 = all expectations passed */
int content_validate(void);                            /* number of errors, each logged */

/* ------------------------------------------------------------------ gfx.c */
/* Where drawing goes. {buf, w, h} is a plain w x h buffer, row after row. A surface can also be a window of a bigger
 * frame (fw x fh) stored any way round: pixel (x, y) is px[(x - x0) * xs + (y - y0) * ys], and everything is clipped to
 * [x0, x0 + w) x [y0, y0 + h). Drawing a frame window by window gives the same pixels as drawing it whole: the console
 * draws straight into its panel strips this way (gfx_turned). swap: pixels are stored with their bytes swapped, as a
 * big-endian display bus wants them. Fields left at 0 mean the plain buffer. */
typedef struct {
    uint16_t *px;
    int w, h;
    int x0, y0, xs, ys, fw, fh;
    bool swap;
} surface;
void game_draw(surface *s, bool world_pass); /* the frame onto s, a window of it or all (game.c) */

typedef struct {
    char id[32];
    int w, h, frames, ax, ay, frame_ms;
    uint16_t *pixels; /* frames * w * h */
    uint8_t *mask;    /* frames * stride * h, MSB first, 1 = opaque; NULL = opaque */
    bool missing;
} asset;

typedef struct {
    int w, h, stride;
    uint8_t adv[256];
    uint8_t *bits;
    uint8_t *box; /* per glyph, where its ink is: x0, x1, y0, y1 (ends exclusive); font_load fills it, after bits */
} font;

asset *gfx_asset(const char *id); /* cached, never NULL; missing files give a checkerboard */
asset *gfx_asset_opt(const char *id); /* the same, silent when the game leaves it out */
void gfx_reset(void);
void gfx_force_missing(const char *id);
bool gfx_opaque(const asset *a, int frame, int u, int v);
void gfx_blit(surface *s, const asset *a, int frame, int x, int y, int rot, bool half);
void gfx_blit2x(surface *s, const asset *a, int frame, int x, int y);
void gfx_blit_rows(surface *s, const asset *a, int frame, int x, int y, int rows); /* top rows only */
void gfx_fill(surface *s, int x, int y, int w, int h, uint16_t c);
void gfx_frame(surface *s, int x, int y, int w, int h, uint16_t c);
void gfx_shade(surface *s, int x, int y, int w, int h); /* darken by half */
void gfx_upscale2x(const surface *src, surface *dst);
/* Panel rows row0..row0+rows-1 of a portrait panel showing a fw x fh frame turned a quarter (the console's ST77922,
 * which cannot swap rows and columns): panel row r is frame column r (flip: fw-1-r), panel pixel p is frame row fh-1-p
 * (flip: p). out holds rows x fh pixels, row after row, as the panel takes them, with bytes swapped if swap. */
surface gfx_turned(uint16_t *out, int row0, int rows, int fw, int fh, bool flip, bool swap);
void gfx_tint_dusk(surface *s);
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
void dlg_render(surface *s);
const char *dlg_text(void); /* text of the current line, for scripts */

/* ------------------------------------------------------------------ world.c */
bool world_enter(const char *zone, const char *spawn);
void world_tick(void);
void world_render(surface *world);
void world_render_marker(surface *native);
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
void audio_preload(const char *id);
long audio_cache_bytes(void); /* RAM held by cached SFX: stays under a fixed budget */
void audio_bus(float amb, float mus, float amb_lowpass_hz, int fade_ms); /* ducking; lowpass 0 = open */
void audio_master(float gain, int fade_ms);
#define VOLUME_MAX 4
void audio_pause(bool paused);
void audio_reset(void);
void audio_force_missing(const char *id);

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
void inv_tick(void), inv_render(surface *s);
void notes_tick(void), notes_render(surface *s);
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
    bool tones; /* speakers' "blip" while their text runs (Geumgye §23), pause menu */
    bool bag; /* Klaus carries: false = backpack (dossier), true = crossbody bag (Options) */
    char toast[96];
    float toast_ms;
    char error[192];
    float anim_ms;
    uint32_t save_seq;
    bool exit_guard, quit, autosave_enabled;
    unsigned draws; /* frames drawn: render code that looks things up once a frame keys on it (game_draw) */
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
