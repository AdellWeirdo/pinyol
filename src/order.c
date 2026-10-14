/* Ordering puzzles: message cards, each with a visible mark (01, 02,
 * 03...), in slots that must end up in the cards' listed order. A takes a card and A on another slot swaps them
 * (A on the same slot puts it back); B lets go of a taken card, or leaves keeping the order. «Confirmar» checks
 * it: a wrong order keeps every card where it is and frames the ones out of place. After "assist_after" wrong
 * checks a button puts them in order by their marks. The order lives in flags ("state_flags", value 1-n), so
 * leaving or a power cut never loses it. Fragments are never destroyed; there is no timer. */
#include <string.h>

#include "bp.h"

#define MAX_CARDS 4
#define CARD_X 24
#define CARD_W (SCREEN_W - 48)
#define CARD_H 40
#define CARD_Y 48
#define CARD_STEP 48
#define TEXT_X 92 /* text starts after the mark; one line, the width the validator checks */
#define BTN_Y 196
#define BTN_H 30

static struct {
    cJSON *def;
    int n, slot[MAX_CARDS], focus, held, tries;
    unsigned wrong;
    bool solved;
} O;

static const cJSON *card(int i) { return cJSON_GetArrayItem(jget(O.def, "cards"), i); }
static bool assisted(void) { return O.tries >= jint(O.def, "assist_after", 2); }
static int n_focus(void) { return O.n + 1 + assisted(); } /* the slots, «Confirmar», [«Ordenar por las marcas»] */

static void save_state(void) {
    for (int i = 0; i < O.n; i++) {
        const char *f = jas(jget(O.def, "state_flags"), i);
        if (f) flag_set(f, O.slot[i] + 1);
    }
}

void order_open(cJSON *def) {
    memset(&O, 0, sizeof O);
    O.def = def;
    O.n = cJSON_GetArraySize(jget(def, "cards"));
    if (O.n > MAX_CARDS) O.n = MAX_CARDS;
    O.held = -1;
    for (int i = 0; i < O.n; i++) {
        const char *f = jas(jget(def, "state_flags"), i);
        O.slot[i] = f && flag_get(f) ? flag_get(f) - 1 : jai(jget(def, "start"), i, i);
    }
    if (jstr(def, "tries_flag")) O.tries = flag_get(jstr(def, "tries_flag"));
    G.pz.def = def;
    G.pz.msg = jstr(def, "instruction");
    layer_push(L_PUZZLE);
}

static void confirm(void) {
    O.wrong = 0;
    for (int i = 0; i < O.n; i++) if (O.slot[i] != i) O.wrong |= 1u << i;
    if (!O.wrong) {
        O.solved = true;
        G.pz.msg = jstr(O.def, "solved_text");
        sound("solved");
        return;
    }
    O.tries++;
    if (jstr(O.def, "tries_flag")) flag_set(jstr(O.def, "tries_flag"), O.tries);
    sound(jget(jget(G.music, "sfx"), "error") ? "error" : "back");
    G.pz.msg = O.tries == jint(O.def, "assist_after", 2) && jstr(O.def, "assist_text") ? jstr(O.def, "assist_text") : jstr(O.def, "wrong");
}

static void close_order(void) {
    cJSON *def = O.def;
    bool solved = O.solved;
    G.pz.def = NULL;
    layer_remove(L_PUZZLE);
    if (solved) effects_run(jget(def, "do"));
}

static void activate(int f) {
    if (f < O.n) { /* take, swap, or put back */
        if (O.held < 0) O.held = f;
        else if (O.held != f) {
            int t = O.slot[f];
            O.slot[f] = O.slot[O.held], O.slot[O.held] = t, O.held = -1;
            O.wrong = 0;
            save_state();
        } else O.held = -1;
        sound("ok");
    } else if (f == O.n) confirm();
    else { /* the help: by their marks */
        for (int i = 0; i < O.n; i++) O.slot[i] = i;
        O.held = -1;
        save_state();
        confirm();
    }
}

void order_tick(void) {
    uint16_t p = G.in.pressed;
    if (O.solved) {
        if (p & (ACT_OK | ACT_BACK)) close_order();
        return;
    }
    if (p & ACT_BACK) {
        if (O.held >= 0) O.held = -1;
        else close_order();
        return;
    }
    int nf = n_focus(); /* the rows top to bottom, then the buttons left to right */
    if (p & (ACT_UP | ACT_LEFT)) O.focus = (O.focus + nf - 1) % nf, sound("move");
    if (p & (ACT_DOWN | ACT_RIGHT)) O.focus = (O.focus + 1) % nf, sound("move");
    if (p & ACT_OK) activate(O.focus);
}

/* ------------------------------------------------------------------ render */
static void mark_icon(surface *s, int x, int y, int k) { /* 01 a closed rectangle, 02 two hands, 03 three waves */
    if (k == 0) {
        gfx_fill(s, x, y, 18, 2, C_INK), gfx_fill(s, x, y + 12, 18, 2, C_INK);
        gfx_fill(s, x, y, 2, 14, C_INK), gfx_fill(s, x + 16, y, 2, 14, C_INK);
    } else if (k == 1) {
        for (int h = 0; h < 2; h++) {
            gfx_fill(s, x + h * 10, y + 4, 8, 10, C_INK);
            for (int f = 0; f < 3; f++) gfx_fill(s, x + h * 10 + f * 3, y, 2, 4, C_INK);
        }
    } else {
        for (int w = 0; w < 3; w++)
            for (int t = 0; t < 4; t++) gfx_fill(s, x + w * 6 + (t == 0 || t == 3 ? 0 : 2), y + 2 + t * 3, 2, 3, C_INK);
    }
}

void order_render(surface *s) {
    const font *f = ui_font(), *b = ui_bold();
    gfx_fill(s, 0, 0, SCREEN_W, SCREEN_H, C_INK);
    const char *title = jstr(O.def, "title");
    if (title) {
        int tw = font_width(b, title, -1) + 32;
        gfx_plate(s, (SCREEN_W - tw) / 2, 4, tw, b->h + 8, C_TERRA);
        font_draw(s, b, (SCREEN_W - tw) / 2 + 16, 8, title, -1, -1, C_PAPER);
    }
    for (int i = 0; i < O.n; i++) { /* one row per slot: mark, its icon, the fragment */
        const cJSON *c = card(O.slot[i]);
        int x = CARD_X + (O.held == i ? 10 : 0), y = CARD_Y + i * CARD_STEP;
        bool sel = O.focus == i && !O.solved, bad = O.wrong & (1u << i);
        if (bad) gfx_fill(s, x - 3, y - 3, CARD_W + 6, CARD_H + 6, C_TERRA); /* out of order: framed, by shape too */
        gfx_plate(s, x, y, CARD_W, CARD_H, O.solved ? C_OCHRE : sel ? C_PAPER_SEL : C_PAPER);
        if (sel) gfx_tri(s, x - 14, y + CARD_H / 2 - 6, 6, true, C_PAPER);
        font_draw(s, b, x + 12, y + (CARD_H - b->h) / 2, jstr(c, "mark") ? jstr(c, "mark") : "", -1, -1, C_INK);
        mark_icon(s, x + 46, y + (CARD_H - 14) / 2, O.slot[i]);
        font_draw(s, f, x + TEXT_X, y + (CARD_H - f->h) / 2, jstr(c, "text") ? jstr(c, "text") : "", -1, -1, C_INK);
        if (bad) font_draw(s, b, x + CARD_W - 20, y + (CARD_H - b->h) / 2, "!", -1, -1, C_TERRA);
    }
    const char *labels[2] = {jas(jget(O.def, "buttons"), 0) ? jas(jget(O.def, "buttons"), 0) : "Confirmar",
                             jas(jget(O.def, "buttons"), 1) ? jas(jget(O.def, "buttons"), 1) : "Ordenar por las marcas"};
    int nb = 1 + assisted(), bw = nb == 2 ? 200 : 180, x0 = (SCREEN_W - (nb * bw + (nb - 1) * 12)) / 2;
    for (int i = 0; i < nb; i++) {
        bool sel = O.focus == O.n + i && !O.solved;
        int x = x0 + i * (bw + 12);
        gfx_plate(s, x, BTN_Y, bw, BTN_H, sel ? C_PAPER_SEL : C_PAPER);
        if (sel) gfx_tri(s, x + 10, BTN_Y + BTN_H / 2 - 6, 6, true, C_INK);
        text_center(s, b, x + bw / 2, BTN_Y + (BTN_H - b->h) / 2, labels[i], C_INK);
    }
    button_hint(s, 40, 228, "B", O.held >= 0 ? "Soltar" : "Volver", C_PAPER);
    gfx_panel(s, 16, 256, SCREEN_W - 32, 58);
    if (G.pz.msg) {
        uint16_t ls[3], ll[3];
        int n = text_wrap(f, G.pz.msg, SCREEN_W - 64, ls, ll, 2);
        for (int i = 0; i < n; i++) font_draw(s, f, 32, 264 + i * (f->h + 2), G.pz.msg + ls[i], ll[i], -1, O.solved ? C_TERRA : C_INK);
    }
}
