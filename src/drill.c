/* Timed exercises (a training, a repair, an echo at a door). A puzzle of
 * "type": "drill" is a list of steps played one at a time over the zone, with no damage and no overall
 * time limit:
 *   "press":  A inside a window that opens after a lead-in.
 *   "hold":   DOWN held through every tick of a window.
 *   "rhythm": a demonstration of pulses (ticks from the first), then the player repeats them with A; the
 *             first press fixes the origin and the others are compared with the pulses' offsets.
 * A failed step repeats alone. After "assist_after" failures its window or tolerance grows by "assist_pct";
 * after "guided_after" a rhythm only asks for a press with each shown pulse and a press waits for A with its
 * window open, never expiring. C replays a rhythm's demonstration, or restarts a press with the "help" text;
 * B leaves (not with "stay": a scene with nowhere to go back to). "step_flag" keeps the steps already done (value = steps done), so leaving or a power cut resumes
 * there. "indicators" (say, current and edge) are two labelled lamps stacked over the zone that each
 * step turns on at its "ready" ticks; the window opens with the last. Timing is ticks of simulation, never the
 * sound, so it plays muted too. */
#include <stdlib.h>
#include <string.h>

#include "bp.h"

typedef enum { D_LEAD, D_DEMO, D_INPUT, D_RESULT } dphase;

#define LEAD_IN 60   /* ticks before a rhythm's input opens, after its demonstration */
#define RESULT_T 70  /* ticks a step's verdict stays on screen */
#define MAX_PULSES 6

static struct {
    cJSON *def;
    const cJSON *st; /* current step */
    int step, n, t, fails, presses, origin, at[MAX_PULSES];
    dphase ph;
    bool ok, done;
    const char *msg;
} R;

static const char *kind(void) { return jstr(R.st, "kind") ? jstr(R.st, "kind") : "press"; }
static bool is(const char *k) { return !strcmp(kind(), k); }
static int pulses(void) { int n = cJSON_GetArraySize(jget(R.st, "pulses")); return n > MAX_PULSES ? MAX_PULSES : n; }
static int pulse(int i) { return jai(jget(R.st, "pulses"), i, 0); }
static bool assisted(void) { return R.fails >= jint(R.def, "assist_after", 3); }
static bool guided(void) { return !is("hold") && R.fails >= jint(R.def, "guided_after", 4); }
static int grow(int v) { return assisted() ? v * jint(R.def, "assist_pct", 200) / 100 : v; }
static int lead(void) { return jint(R.st, "lead", 60); }
static bool ready(int k) { return R.ph != D_RESULT ? R.t >= jai(jget(R.st, "ready"), k, lead()) : R.ok; }
static int window(void) { return grow(jint(R.st, "window", 24)); }
static int tol(void) { return guided() ? jint(R.st, "guided_tol", 40) : grow(jint(R.st, "tol", 18)); }
static const char *text_or(const char *key, const char *dflt) { return jstr(R.def, key) ? jstr(R.def, key) : dflt; }

static void start_step(void) {
    R.st = cJSON_GetArrayItem(jget(R.def, "steps"), R.step);
    R.t = R.presses = 0;
    R.origin = -1;
    R.ph = is("rhythm") ? D_DEMO : D_LEAD;
    R.msg = G.pz.msg = jstr(R.st, "text");
}

void drill_open(cJSON *def) {
    memset(&R, 0, sizeof R);
    R.def = def;
    R.n = cJSON_GetArraySize(jget(def, "steps"));
    if (jstr(def, "tries_flag")) R.fails = flag_get(jstr(def, "tries_flag")); /* the help survives leaving (§09) */
    if (jstr(def, "step_flag") && flag_get(jstr(def, "step_flag")) < R.n) R.step = flag_get(jstr(def, "step_flag"));
    G.pz.def = def;
    if (jstr(def, "player_anim")) G.klaus.anim = jstr(def, "player_anim"); /* e.g. on guard through the training */
    start_step();
    layer_push(L_PUZZLE);
}

static void verdict(bool ok, const char *msg) {
    R.ok = ok;
    R.ph = D_RESULT;
    R.t = 0;
    R.msg = G.pz.msg = msg;
    sound(ok ? "solved" : jget(jget(G.music, "sfx"), "error") ? "error" : "back");
    if (!ok) R.fails++;
    if (ok && jstr(R.def, "step_flag")) { /* kept the moment it is right, even if B follows (a milestone, C3 §23) */
        flag_set(jstr(R.def, "step_flag"), R.step + 1);
        if (G.autosave_enabled) save_write("auto");
    }
    if (!ok && jstr(R.def, "tries_flag")) flag_set(jstr(R.def, "tries_flag"), R.fails);
}

static void close_drill(void) {
    cJSON *def = R.def;
    bool done = R.done;
    G.pz.def = NULL;
    if (jstr(def, "player_anim")) G.klaus.anim = NULL;
    layer_remove(L_PUZZLE);
    if (done) effects_run(jget(def, "do"));
}

static void rhythm_tick(uint16_t p) {
    int last = pulse(pulses() - 1);
    if (R.ph == D_DEMO) { /* the door plays its pulses */
        for (int i = 0; i < pulses(); i++)
            if (R.t == pulse(i) && jstr(R.st, "sfx")) audio_sfx(jstr(R.st, "sfx"), 1);
        if (R.t > last + LEAD_IN) R.ph = D_INPUT, R.t = 0, R.msg = G.pz.msg = text_or("your_turn", "Tu turno: A con cada pulso.");
        return;
    }
    if (guided()) { /* help: the pulses show again and each press only has to land near its own */
        if (R.presses < pulses() && R.t == pulse(R.presses) && jstr(R.st, "sfx")) audio_sfx(jstr(R.st, "sfx"), 1);
        if (p & ACT_OK) {
            if (abs(R.t - pulse(R.presses)) > tol()) return;
            if (++R.presses == pulses()) verdict(true, text_or("good", "Bien."));
        }
        return;
    }
    if (p & ACT_OK) {
        if (R.origin < 0) R.origin = R.t; /* the first press fixes the origin: no penalty for a late start */
        R.at[R.presses] = R.t - R.origin;
        int off = R.at[R.presses] - pulse(R.presses);
        if (abs(off) > tol()) {
            verdict(false, off < 0 ? text_or("early", "Demasiado pronto.") : text_or("late", "Demasiado tarde."));
            return;
        }
        if (++R.presses == pulses()) verdict(true, text_or("good", "Bien."));
    } else if (R.origin >= 0 && R.t - R.origin > last + tol() + 30) {
        verdict(false, text_or("late", "Demasiado tarde."));
    }
}

void drill_tick(void) {
    uint16_t p = G.in.pressed, h = G.in.held;
    if ((p & ACT_BACK) && !cJSON_IsTrue(jget(R.def, "stay"))) { close_drill(); return; } /* "stay": no way out but through */
    R.t++;
    if (R.ph == D_RESULT) {
        if (R.t < RESULT_T) return;
        if (!R.ok) { start_step(); return; } /* only the failed step again */
        R.fails = 0;
        if (++R.step >= R.n) { R.done = true; close_drill(); return; }
        start_step();
        return;
    }
    if (is("rhythm")) {
        if ((p & ACT_NEXT) && R.origin < 0) { start_step(); return; } /* C: hear the door again */
        rhythm_tick(p);
        return;
    }
    if (p & ACT_NEXT) { start_step(); if (jstr(R.def, "help")) R.msg = G.pz.msg = jstr(R.def, "help"); return; }
    int open = lead(), shut = guided() && is("press") ? 1 << 30 : lead() + window(); /* guided: it waits */
    if (R.t == open && jstr(R.st, "sfx")) audio_sfx(jstr(R.st, "sfx"), 1); /* the cue by sound as well as sight */
    if (is("hold")) {
        if (R.t >= open && R.t < shut && !(h & ACT_DOWN)) verdict(false, text_or("released", "Has soltado antes de tiempo."));
        else if (R.t >= shut) verdict(true, text_or("good", "Bien."));
        return;
    }
    if ((p & ACT_OK) && guided() && R.t < open) return; /* guided: an early A is not a miss */
    if (p & ACT_OK) verdict(R.t >= open && R.t < shut, R.t < open ? text_or("early", "Demasiado pronto.") : text_or("good", "Bien."));
    else if (R.t >= shut) verdict(false, text_or("late", "Demasiado tarde."));
}

/* ------------------------------------------------------------------ render: a panel at the bottom, the zone above */
static void timing_bar(surface *s, int x, int y, int w) {
    gfx_fill(s, x, y, w, 10, C_INK);
    if (is("rhythm")) {
        int span = pulse(pulses() - 1) + 30;
        for (int i = 0; i < pulses(); i++) {
            int px = x + 8 + (w - 16) * pulse(i) / span;
            bool lit = R.ph == D_DEMO ? R.t >= pulse(i) && R.t < pulse(i) + 12 : i < R.presses;
        if (R.ph == D_INPUT && assisted() && R.origin >= 0 && abs(R.t - R.origin - pulse(i)) <= 6) lit = true; /* metronome */
            gfx_fill(s, px - 5, y - 4, 10, 18, lit ? C_OCHRE : C_PAPER_SEL);
        }
        if (R.ph == D_DEMO || (R.origin >= 0 && R.ph == D_INPUT)) {
            int t = R.ph == D_DEMO ? R.t : R.t - R.origin;
            gfx_fill(s, x + 8 + (w - 16) * (t < span ? t : span) / span, y - 6, 2, 22, C_TERRA);
        }
        return;
    }
    int span = lead() + window() + 20, wx = x + w * lead() / span, ww = w * window() / span;
    gfx_fill(s, wx, y, ww, 10, C_OCHRE);
    int t = R.ph == D_RESULT ? 0 : R.t;
    gfx_fill(s, x + w * (t < span ? t : span) / span, y - 6, 2, 22, C_TERRA);
}

static void indicators(surface *s) { /* two lamps stacked at the top left: on, by a filled lamp and the word */
    const cJSON *ind = jget(R.def, "indicators");
    const font *b = ui_bold();
    for (int k = 0; k < 2 && cJSON_GetArrayItem(ind, k); k++) {
        bool on = ready(k);
        const char *t = jas(cJSON_GetArrayItem(ind, k), on ? 0 : 1);
        int w = font_width(b, t ? t : "", -1) + 52, x = 12, y = 12 + k * (b->h + 20);
        gfx_plate(s, x, y, w, b->h + 14, C_INK);
        gfx_frame(s, x + 12, y + (b->h + 14 - 16) / 2, 16, 16, C_PAPER);
        if (on) gfx_fill(s, x + 15, y + (b->h + 14 - 16) / 2 + 3, 10, 10, C_OCHRE);
        font_draw(s, b, x + 38, y + 7, t ? t : "", -1, -1, on ? C_OCHRE : C_PAPER);
    }
}

void drill_render(surface *s) {
    const font *f = ui_font(), *b = ui_bold();
    indicators(s);
    int x = 16, y = SCREEN_H - 112, w = SCREEN_W - 32;
    gfx_panel(s, x, y, w, 100);
    char head[64];
    snprintf(head, sizeof head, "%s %d/%d", jstr(R.def, "title") ? jstr(R.def, "title") : "", R.step + 1, R.n ? R.n : 1);
    int hw = font_width(b, head, -1) + 24;
    gfx_plate(s, x + 12, y - 14, hw, b->h + 8, C_TERRA);
    font_draw(s, b, x + 24, y - 10, head, -1, -1, C_PAPER);
    if (R.msg) {
        uint16_t ls[2], ll[2];
        int n = text_wrap(f, R.msg, SCREEN_W - 64, ls, ll, 2); /* the width the validator checks */
        for (int i = 0; i < n; i++) font_draw(s, f, x + 16, y + 18 + i * (f->h + 2), R.msg + ls[i], ll[i], -1, R.ph == D_RESULT && !R.ok ? C_TERRA : C_INK);
    }
    timing_bar(s, x + 20, y + 78, w - 40);
    bool cue = R.ph != D_RESULT && !is("rhythm") && R.t >= lead() && R.t < lead() + window();
    if (cue) { /* the moment, by shape and word as well as colour */
        const char *c = is("hold") ? text_or("cue_hold", "¡Aguanta!") : text_or("cue_press", "¡Ahora!");
        int cw = font_width(b, c, -1) + 28;
        gfx_plate(s, (SCREEN_W - cw) / 2, y - 52, cw, b->h + 10, C_OCHRE);
        font_draw(s, b, (SCREEN_W - cw) / 2 + 14, y - 47, c, -1, -1, C_INK);
    }
}

/* ------------------------------------------------------------------ scripts */
const char *drill_phase(void) {
    static const char *const n[] = {"lead", "demo", "input", "result"};
    return R.def ? n[R.ph] : "none";
}
