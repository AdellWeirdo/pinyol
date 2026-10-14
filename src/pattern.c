/* Rhythm puzzles (C2 dossier p.21, the bell): repeat a pattern heard before. Three slots, each a short
 * or long pulse, confirmed explicitly; the comparison is symbolic, never timing or volume. With
 * "symbols" (say body, memory, will) each slot cycles through those instead, drawn with
 * "icons" when given; "buttons" relabels the three buttons. Buttons:
 * left/right choose, A changes the slot or presses the focused button, C hears the clue again, B leaves.
 * After "assist_after" tries a button fills in the rhythm heard. No penalty, ever; the rhythm is also
 * drawn as marks so it can be solved with the sound off. */
#include <string.h>

#include "bp.h"

#define SLOTS 3
#define SLOT_W 56 /* big touch plates (dossier: 56x56 native) */
#define SLOT_GAP 20
#define BTN_Y 214
#define BTN_H 34

enum { EMPTY, SHORT, LONG };

static struct {
    cJSON *def;
    int slot[SLOTS], focus, tries, playing, lit; /* playing: next pulse to strike, -1 = idle */
    float wait_ms;
    const char *msg;
    bool solved;
} B;

static int slot_gap(void) { return jint(B.def, "slot_gap", SLOT_GAP); } /* wider for named symbols */
static int slot_x(int i) { return SCREEN_W / 2 - (SLOTS * SLOT_W + (SLOTS - 1) * slot_gap()) / 2 + i * (SLOT_W + slot_gap()); }
static bool assisted(void) { return B.tries >= jint(B.def, "assist_after", 3); }
static int n_focus(void) { return SLOTS + 2 + assisted(); } /* slots, Tocar, Oír, [Repetir lo oído] */

static const char *const BTN[] = {"Tocar", "Oír", "Repetir lo oído"};
static const char *const KEY[] = {"A", "C", "A"};
static const char *btn_label(int i) { return jas(jget(B.def, "buttons"), i) ? jas(jget(B.def, "buttons"), i) : BTN[i]; }

/* Slot values: EMPTY, then 1..n for the symbols (default: SHORT, LONG). */
static const cJSON *symbols(void) { return jget(B.def, "symbols"); }
static int n_symbols(void) { return symbols() ? cJSON_GetArraySize(symbols()) : 2; }
static const char *symbol_label(int v) {
    if (v == EMPTY) return "";
    if (symbols()) return jas(jget(B.def, "labels"), v - 1) ? jas(jget(B.def, "labels"), v - 1) : jas(symbols(), v - 1);
    return v == SHORT ? "corto" : "largo";
}

static int btn_x(int i) {
    int n = 2 + assisted(), w = n == 3 ? 136 : 150, gap = 12, x0 = (SCREEN_W - (n * w + (n - 1) * gap)) / 2;
    return x0 + i * (w + gap);
}
static int btn_w(void) { return assisted() ? 136 : 150; }

/* B leaves keeping what was placed; "tries_flag" keeps the tries in a flag, so the help
 * that comes after "assist_after" survives leaving and saves (§27). */
void pattern_open(cJSON *def) {
    int kept[SLOTS] = {0};
    if (B.def == def && !B.solved) memcpy(kept, B.slot, sizeof kept);
    memset(&B, 0, sizeof B);
    memcpy(B.slot, kept, sizeof kept);
    B.def = def;
    if (jstr(def, "tries_flag")) B.tries = flag_get(jstr(def, "tries_flag"));
    B.playing = B.lit = -1;
    B.msg = G.pz.msg = jstr(def, "instruction");
    G.pz.def = def;
    layer_push(L_PUZZLE);
}

static int wanted(int i) {
    const char *w = jas(jget(B.def, "solution"), i);
    for (int k = 0; w && symbols() && k < n_symbols(); k++)
        if (!strcmp(w, jas(symbols(), k) ? jas(symbols(), k) : "")) return k + 1;
    return w && w[0] == 'l' ? LONG : SHORT;
}

/* "hint_after" tries in, the first slot is marked and stays marked ("hint_flag", kept
 * like the tries); "clear_on_wrong" empties the slots after a wrong order, with "sfx_wrong". */
static void keep_hint(void) {
    const char *hf = jstr(B.def, "hint_flag");
    if (hf && flag_get(hf) && B.slot[0] == EMPTY) B.slot[0] = wanted(0);
}

static void hear(void) {
    if (jstr(B.def, "clue")) audio_voice(jstr(B.def, "clue"));
    B.msg = G.pz.msg = jstr(B.def, "clue_text");
}

static void ring(void) {
    B.playing = 0;
    B.wait_ms = 0;
}

static void judge(void) {
    bool full = true, ok = true;
    for (int i = 0; i < SLOTS; i++) {
        full &= B.slot[i] != EMPTY;
        ok &= B.slot[i] == wanted(i);
    }
    if (full && ok) {
        B.solved = true;
        B.msg = G.pz.msg = jstr(B.def, "solved_text");
        sound("solved");
        return;
    }
    B.tries++;
    if (jstr(B.def, "tries_flag")) flag_set(jstr(B.def, "tries_flag"), B.tries);
    if (full && cJSON_IsTrue(jget(B.def, "clear_on_wrong"))) {
        memset(B.slot, 0, sizeof B.slot);
        if (jstr(B.def, "sfx_wrong")) audio_sfx(jstr(B.def, "sfx_wrong"), 1);
    }
    int hint = jint(B.def, "hint_after", 0);
    if (hint && B.tries >= hint && jstr(B.def, "hint_flag")) flag_set(jstr(B.def, "hint_flag"), 1);
    keep_hint();
    B.msg = G.pz.msg = !full ? jstr(B.def, "incomplete") : B.tries == jint(B.def, "assist_after", 3) ? jstr(B.def, "assist_text")
                     : hint && B.tries == hint && jstr(B.def, "hint_text") ? jstr(B.def, "hint_text") : jstr(B.def, "wrong");
}

static void close_pattern(void) {
    cJSON *def = B.def;
    bool solved = B.solved;
    G.pz.def = NULL;
    layer_remove(L_PUZZLE);
    if (solved) effects_run(jget(def, "do"));
}

static void activate(int f) {
    if (f < SLOTS) B.slot[f] = B.slot[f] % n_symbols() + 1;
    else if (f == SLOTS) ring();
    else if (f == SLOTS + 1) hear();
    else {
        for (int i = 0; i < SLOTS; i++) B.slot[i] = wanted(i);
        ring();
    }
}

void pattern_tick(void) {
    uint16_t p = G.in.pressed;
    keep_hint(); /* a hint read before (or on another visit) is already in its slot */
    if (B.playing >= 0) { /* the bell strikes what is in the slots, one by one; input waits */
        if ((B.wait_ms -= TICK_MS) > 0) return;
        if (B.playing < SLOTS) {
            int v = B.slot[B.playing];
            const char *sfx = symbols() ? jstr(B.def, "sfx") : jstr(B.def, v == LONG ? "sfx_long" : "sfx_short");
            if (v != EMPTY && sfx) audio_sfx(sfx, 1);
            B.lit = B.playing++;
            B.wait_ms = v == LONG && !symbols() ? 900 : 420;
        } else {
            B.playing = B.lit = -1;
            judge();
        }
        return;
    }
    if (B.solved) {
        if ((p & (ACT_OK | ACT_BACK)) || G.in.tap) close_pattern();
        return;
    }
    if (p & ACT_BACK) { close_pattern(); return; }
    if (p & ACT_NEXT) hear();
    int nf = n_focus();
    if (B.focus >= nf) B.focus = nf - 1;
    if (p & ACT_LEFT) B.focus = (B.focus + nf - 1) % nf;
    if (p & ACT_RIGHT) B.focus = (B.focus + 1) % nf;
    if ((p & (ACT_UP | ACT_DOWN)) && B.focus < SLOTS) activate(B.focus);
    if (p & ACT_OK) activate(B.focus);
    if (G.in.tap) {
        int x = G.in.px, y = G.in.py;
        for (int i = 0; i < SLOTS; i++)
            if (x >= slot_x(i) && x < slot_x(i) + SLOT_W && y >= 120 && y < 120 + SLOT_W) { B.focus = i; activate(i); }
        for (int i = 0; i < 2 + assisted(); i++)
            if (x >= btn_x(i) && x < btn_x(i) + btn_w() && y >= BTN_Y && y < BTN_Y + BTN_H) { B.focus = SLOTS + i; activate(SLOTS + i); }
    }
}

static void pulse_mark(surface *s, int cx, int cy, int v, uint16_t c, bool lit) {
    if (symbols()) { /* a symbol: its icon at 2x (frame 1, if any, when lit), or nothing (the label names it) */
        asset *ic = v == EMPTY ? NULL : gfx_asset(jas(jget(B.def, "icons"), v - 1));
        if (ic && !ic->missing) gfx_blit2x(s, ic, lit && ic->frames > 1 ? 1 : 0, cx - ic->w, cy - ic->h);
        else if (v == EMPTY) gfx_fill(s, cx - 3, cy - 1, 6, 2, C_DIM);
        return;
    }
    if (v == SHORT) gfx_disc(s, cx, cy, 8, c);
    else if (v == LONG) gfx_fill(s, cx - 18, cy - 6, 36, 12, c);
    else gfx_fill(s, cx - 3, cy - 1, 6, 2, C_DIM);
}

void pattern_render(surface *s) {
    const font *f = ui_font(), *b = ui_bold();
    gfx_fill(s, 0, 0, SCREEN_W, SCREEN_H, C_BROWN);
    const char *title = jstr(B.def, "title");
    if (title) {
        int tw = font_width(b, title, -1) + 32;
        gfx_plate(s, (SCREEN_W - tw) / 2, 4, tw, b->h + 8, C_TERRA);
        font_draw(s, b, (SCREEN_W - tw) / 2 + 16, 8, title, -1, -1, C_PAPER);
    }
    asset *art = jstr(B.def, "art") ? gfx_asset(jstr(B.def, "art")) : NULL; /* optional illustration */
    if (art && !art->missing) gfx_blit2x(s, art, B.lit >= 0 ? 1 : 0, SCREEN_W / 2 - art->w, 112 - art->h * 2);
    for (int i = 0; i < SLOTS; i++) {
        int x = slot_x(i), sel = B.focus == i && B.playing < 0 && !B.solved;
        gfx_plate(s, x, 120, SLOT_W, SLOT_W, B.lit == i ? C_TERRA : sel ? C_PAPER_SEL : C_PAPER);
        if (sel) gfx_tri(s, x + SLOT_W / 2 - 6, 106, 6, false, C_PAPER);
        pulse_mark(s, x + SLOT_W / 2, 120 + SLOT_W / 2, B.slot[i], B.lit == i ? C_PAPER : C_INK, B.lit == i || B.solved);
        text_center(s, f, x + SLOT_W / 2, 120 + SLOT_W + 4, symbol_label(B.slot[i]), C_PAPER); /* never colour alone */
    }
    for (int i = 0; i < 2 + assisted(); i++) {
        int x = btn_x(i), sel = B.focus == SLOTS + i && B.playing < 0 && !B.solved;
        gfx_plate(s, x, BTN_Y, btn_w(), BTN_H, sel ? C_PAPER_SEL : C_PAPER);
        int r = b->h / 2 - 1, w = 2 * r + 8 + font_width(b, btn_label(i), -1), bx = x + (btn_w() - w) / 2, cy = BTN_Y + BTN_H / 2;
        gfx_disc(s, bx + r, cy, r, C_INK);
        font_draw(s, b, bx + r - font_width(b, KEY[i], -1) / 2 + 1, cy - b->h / 2, KEY[i], -1, -1, C_PAPER);
        font_draw(s, b, bx + 2 * r + 8, cy - b->h / 2, btn_label(i), -1, -1, C_INK);
    }
    gfx_panel(s, 16, 256, SCREEN_W - 32, 58);
    if (B.msg) {
        uint16_t ls[3], ll[3];
        int n = text_wrap(f, B.msg, SCREEN_W - 64, ls, ll, 2);
        for (int i = 0; i < n; i++) font_draw(s, f, 32, 264 + i * (f->h + 2), B.msg + ls[i], ll[i], -1, B.solved ? C_TERRA : C_INK);
    }
}
