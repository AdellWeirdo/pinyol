/* The careta: every game made with pinyol opens with "POWERED BY PINYOL", as a film opens with its studio's logo.
 *
 * The engine's own (any game): pinyol's logo builds itself on the night, as the console's menu has it
 * (firmware/cirera/main.lua: the seed falls, lands in dust and sprouts, the word streaks in, a four-note chime),
 * "POWERED BY" over it, then down to black: 3 s. A Lua game may have its own instead (splash.lua: lua_game.c), its
 * pictures, its sound, its way; whatever it draws, the engine draws the seal "POWERED BY PINYOL" over it, where the
 * game puts it (powered_by) or under it in the middle, whole on the screen. Neither can be skipped: a game's own
 * lasts 2 to 6 s. The game's _init runs after it (an adventure's title, after it too).
 *
 * The pictures are built into the engine (pinyol_splash: tools/splash_art.py and the menu's art), not the game's:
 * they are there for every game, and a game's ids never meet them. */
#include <string.h>

#include "bp.h"

#define DEFAULT_TICKS 180      /* the engine's own: 3 s */
#define OWN_MIN (2 * TICK_HZ)  /* a game's own: the seal at least 2 s on the screen */
#define OWN_MAX (6 * TICK_HZ)  /* and no more than 6 */
#define SEAL_MARGIN 12         /* the seal's place when the game gives none: centred, this far from the bottom */
#define LOGO_X 88              /* the logo's canvas (303 x 197) on the screen, as the menu draws it */
#define LOGO_Y 44
#define INK RGB(0x0B, 0x0E, 0x1F)

enum { P_SEAL, P_LABEL, P_SKY, P_INTRO_SEED, P_SEED, P_LEAVES, P_INTRO_WORD, P_WORD, NPICS };
static const char *const NAMES[NPICS] = {"SEAL", "LABEL", "SKY", "INTRO_SEED", "SEED", "LEAVES", "INTRO_WORD", "WORD"};
static asset pics[NPICS];
static bool pics_ready;

static struct {
    bool on, own; /* own: the game's (lua_game.c runs it) */
    int t;        /* ticks since it began */
    bool placed;  /* the game said where the seal goes this frame (powered_by) */
    int sx, sy;
} S;

static void load_pics(void) { /* once: they are the engine's, the same for every game */
    if (pics_ready) return;
    for (int i = 0; i < NPICS; i++) {
        const pinyol_pic_entry *e = pinyol_splash;
        while (e->name && strcmp(e->name, NAMES[i])) e++;
        if (e->name) gfx_asset_builtin(&pics[i], e);
        else hal_log("careta: picture %s not built in", NAMES[i]), memset(&pics[i], 0, sizeof pics[i]);
    }
    pics_ready = true;
}

void splash_start(void) {
    load_pics();
    memset(&S, 0, sizeof S);
    S.on = true;
}

bool splash_on(void) { return S.on; }
bool splash_own(void) { return S.on && S.own; }
int splash_ticks(void) { return S.t; }
void splash_own_begin(void) { S.own = true; }

void splash_own_failed(void) { /* the game's careta stopped on an error: the engine's, from the start */
    S.own = false, S.t = 0;
    psg_reset();
}

void splash_place(int x, int y) { S.placed = true, S.sx = x, S.sy = y; }

void splash_seal_size(int *w, int *h) {
    load_pics();
    *w = pics[P_SEAL].w, *h = pics[P_SEAL].h;
}

/* ------------------------------------------------------------------ the engine's own */

static float ease(float k) { return 1 - (1 - k) * (1 - k) * (1 - k); } /* fast, then gently into place */
static float clamp01(float k) { return k < 0 ? 0 : k > 1 ? 1 : k; }

static void note(int voice, const char *name, int wave, float duty, float decay, float vol) {
    psg_note n = {.wave = (uint8_t)wave, .freq = psg_note_hz(name), .vol = vol, .duty = duty, .attack = 0.005f,
                  .decay = decay, .release = 0.03f};
    psg_play(voice, &n);
}

static void chime(int t) { /* four notes as the logo comes together (the menu's) */
    if (t == 34) note(0, "C5", PSG_SQUARE, 0.25f, 0.25f, 0.2f);
    if (t == 62) note(1, "E5", PSG_SQUARE, 0.25f, 0.25f, 0.2f);
    if (t == 80) note(2, "G5", PSG_SQUARE, 0.25f, 0.4f, 0.2f);
    if (t == 96) note(0, "C6", PSG_TRIANGLE, 0.5f, 0.9f, 0.25f);
}

static void blit(surface *s, int p, int frame, int x, int y) {
    if (pics[p].w) gfx_blit_flip(s, &pics[p], frame, x, y, false, NULL, -1);
}

static void draw_logo(surface *s, int x, int y, int t) { /* as far as time t has built it (the menu's draw_logo) */
    if (t >= 10) { /* the seed: falls, lands in dust, sprouts; then the logo's own */
        if (t < 34) blit(s, P_INTRO_SEED, 0, x, y - (int)(230 * (1 - clamp01((t - 10) / 24.0f) * clamp01((t - 10) / 24.0f))));
        else if (t < 70) blit(s, P_INTRO_SEED, 1 + (t - 34) / 9 > 4 ? 4 : 1 + (t - 34) / 9, x, y);
        else blit(s, P_SEED, 0, x, y), blit(s, P_LEAVES, 5, x, y);
    }
    if (t >= 60) { /* the word: a streak from the right, arriving, settled, a light across it, a sparkle */
        if (t < 70) blit(s, P_INTRO_WORD, 0, x + (int)(300 * (1 - ease((t - 60) / 10.0f))), y);
        else if (t < 80) blit(s, P_INTRO_WORD, 1, x + (int)(40 * (1 - ease((t - 70) / 10.0f))), y);
        else if (t < 104) blit(s, P_INTRO_WORD, 2 + (t - 80) / 8, x, y);
        else blit(s, P_WORD, 0, x, y);
    }
}

static void draw_default(surface *s, int t) {
    gfx_fill(s, 0, 0, SCREEN_W, SCREEN_H, t < 16 ? C_BLACK : INK);
    if (t >= 16) blit(s, P_SKY, 0, 0, 0); /* (the night comes up from black, then its stars) */
    draw_logo(s, LOGO_X, LOGO_Y + 20, t > 140 ? 140 : t);
    if (t >= 104 && pics[P_LABEL].w) { /* "POWERED BY", a seed's height over the logo */
        unsigned a = (unsigned)(256 * clamp01((t - 104) / 16.0f));
        gfx_blit_mixed(s, &pics[P_LABEL], 0, (SCREEN_W - pics[P_LABEL].w) / 2, LOGO_Y, false, -1, a, BLEND_ALPHA);
    }
    int out = t - (DEFAULT_TICKS - 30); /* then down to black, as a sequence fades (game.c) */
    if (out >= 20) gfx_fill(s, 0, 0, SCREEN_W, SCREEN_H, C_BLACK);
    else if (out >= 10) gfx_shade(s, 0, 0, SCREEN_W, SCREEN_H), gfx_shade(s, 0, 0, SCREEN_W, SCREEN_H);
    else if (out >= 0) gfx_shade(s, 0, 0, SCREEN_W, SCREEN_H);
}

/* ------------------------------------------------------------------ both */

static void finish(void) {
    bool own = S.own;
    S.on = S.own = false;
    psg_reset(); /* its notes end with it; a game's music fades */
    if (own) audio_music_stop(300), midi_stop(300);
    if (G.v2) v2_splash_end(); /* the game's _init, now */
}

void splash_tick(void) {
    if (!S.on) return;
    S.t++;
    bool done;
    if (S.own) done = v2_splash_update(S.t);
    else chime(S.t), done = S.t >= DEFAULT_TICKS; /* (a game's that fails goes on as the engine's, from 0) */
    if ((done && S.t >= (S.own ? OWN_MIN : DEFAULT_TICKS)) || S.t >= OWN_MAX) finish();
}

/* The seal, whole on the screen, over everything a game's careta drew: where it said, or centred at the bottom. */
static void draw_seal(surface *s) {
    const asset *a = &pics[P_SEAL];
    if (!a->w) return;
    int x = S.placed ? S.sx : (SCREEN_W - a->w) / 2, y = S.placed ? S.sy : SCREEN_H - a->h - SEAL_MARGIN;
    x = x < 0 ? 0 : x > SCREEN_W - a->w ? SCREEN_W - a->w : x;
    y = y < 0 ? 0 : y > SCREEN_H - a->h ? SCREEN_H - a->h : y;
    gfx_blit_flip(s, a, 0, x, y, false, NULL, -1);
}

void splash_draw(surface *s) {
    if (!S.own) {
        draw_default(s, S.t);
        return;
    }
    v2_draw(s);
    draw_seal(s);
}

void splash_frame_begin(void) { S.placed = false; } /* each frame says again where the seal goes */
