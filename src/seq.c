/* Event sequences (not video) and listening points. Both only tick while they are the top layer,
 * so a "line" step simply pushes a dialogue on top and the sequence resumes once it is read. */
#include <math.h>
#include <string.h>

#include "bp.h"

static seq_state *S = &G.seq;

static const cJSON *arg(const cJSON *st, int i) { return cJSON_GetArrayItem(st, i); }
static const char *sarg(const cJSON *st, int i) { return cJSON_IsString(arg(st, i)) ? arg(st, i)->valuestring : ""; }
static int iarg(const cJSON *st, int i) { return cJSON_IsNumber(arg(st, i)) ? arg(st, i)->valueint : 0; }

/* A sequence is a list of steps, or {"steps": [...], "skip": [effects]} when the player may skip it:
 * skipping runs those effects instead of the rest (so a skipped memory still leaves its notebook entry). */
void seq_start(const char *id) {
    cJSON *def = jget(G.sequences, id), *steps = cJSON_IsObject(def) ? jget(def, "steps") : def;
    if (!steps) {
        hal_log("unknown sequence %s", id);
        return;
    }
    if (S->steps && layer_has(L_SEQ)) { /* never restart under a running step; content should not chain them */
        hal_log("sequence %s ignored: another one is running", id);
        return;
    }
    memset(S, 0, sizeof *S);
    S->steps = steps;
    S->skip = cJSON_IsObject(def) ? jget(def, "skip") : NULL;
    S->idx = 0;
    S->bg_vol = 1;
    layer_push(L_SEQ);
}

static void finish(void) {
    S->steps = NULL;
    S->prop[0] = S->fprop[0] = 0;
    S->pdx = S->pdy = S->cam_x = S->cam_y = 0;
    G.klaus.anim = NULL;
    layer_remove(L_SEQ);
}

bool seq_skippable(void) { return S->steps && S->skip && layer_has(L_SEQ); }

void seq_skip(void) {
    if (!seq_skippable()) return;
    cJSON *skip = S->skip;
    if (layer_has(L_DLG)) { /* a line of the sequence is showing: it goes too */
        G.dlg.active = false;
        layer_remove(L_DLG);
    }
    S->fade = 0;
    finish();
    audio_voice_stop(300);
    effects_run(skip);
}

void seq_render(surface *s) {
    if (!seq_skippable() || layer_top() == L_PAUSE) return;
    gfx_plate(s, SCREEN_W - 132, 8, 124, 30, C_PAPER);
    button_hint(s, SCREEN_W - 120, 8 + (30 - ui_bold()->h) / 2, "C", "Omitir", C_INK);
}

/* Returns the duration of the step in ms; 0 = instant. */
static float start_step(const cJSON *st) {
    const char *op = sarg(st, 0);
    if (!strcmp(op, "wait")) return (float)iarg(st, 1);
    if (!strcmp(op, "anim")) { G.klaus.anim = sarg(st, 1); return (float)iarg(st, 2); }
    if (!strcmp(op, "move_prop")) {
        snprintf(S->prop, sizeof S->prop, "%s", sarg(st, 1));
        return (float)iarg(st, 4);
    }
    if (!strcmp(op, "prop_frame")) {
        snprintf(S->fprop, sizeof S->fprop, "%s", sarg(st, 1));
        S->fframe = iarg(st, 2);
        return (float)iarg(st, 3);
    }
    if (!strcmp(op, "camera")) { S->cdx = S->cam_x; S->cdy = S->cam_y; return (float)iarg(st, 3); }
    if (!strcmp(op, "walk") || !strcmp(op, "walk_to")) { /* walk_to: to a point in the zone, from wherever */
        bool to = !strcmp(op, "walk_to");
        S->wdx = iarg(st, 1) - (to ? G.klaus.x : 0), S->wdy = iarg(st, 2) - (to ? G.klaus.y : 0);
        G.klaus.anim = *sarg(st, 3) ? sarg(st, 3) : G.pl.walk;
        return (float)iarg(st, 4);
    }
    if (!strcmp(op, "audio_fade")) { music_hush(); return (float)iarg(st, 1); }
    if (!strcmp(op, "fade_out") || !strcmp(op, "fade_in")) return (float)iarg(st, 1);
    if (!strcmp(op, "line")) { dlg_say(sarg(st, 1), sarg(st, 2), NULL); return 0; }
    if (!strcmp(op, "do")) { effects_run(arg(st, 1)); return 0; }
    if (!strcmp(op, "sfx")) { audio_sfx(sarg(st, 1), 1); return 0; }
    if (!strcmp(op, "voice")) { audio_voice(sarg(st, 1)); return 0; }
    if (!strcmp(op, "music")) { music_force(sarg(st, 1)); return 0; }
    if (!strcmp(op, "checkpoint")) { save_write("prefinal"); return 0; }
    if (!strcmp(op, "save")) { save_write("auto"); return 0; }
    if (!strcmp(op, "end")) { finish(); layers_reset(L_END); return -1; }
    hal_log("unknown sequence step %s", op);
    return 0;
}

static void update_step(const cJSON *st, float p, float dt_frac) {
    const char *op = sarg(st, 0);
    if (!strcmp(op, "move_prop")) { /* state already moved: animate from the old spot to the new one */
        S->pdx = -iarg(st, 2) * (1 - p);
        S->pdy = -iarg(st, 3) * (1 - p);
    } else if (!strcmp(op, "camera")) {
        S->cam_x = S->cdx + (iarg(st, 1) - S->cdx) * p;
        S->cam_y = S->cdy + (iarg(st, 2) - S->cdy) * p;
    } else if (!strcmp(op, "walk") || !strcmp(op, "walk_to")) {
        G.klaus.x += S->wdx * dt_frac;
        G.klaus.y += S->wdy * dt_frac;
        G.klaus.sink = iarg(st, 5) * p; /* optional: sink into the stairs while walking */
        G.klaus.moving = true;
        world_footsteps(true);
    } else if (!strcmp(op, "fade_out")) S->fade = p;
    else if (!strcmp(op, "fade_in")) S->fade = 1 - p;
}

static void end_step(const cJSON *st) {
    const char *op = sarg(st, 0);
    if (!strcmp(op, "anim") || !strcmp(op, "walk") || !strcmp(op, "walk_to")) { G.klaus.anim = NULL; G.klaus.moving = false; }
    if (!strcmp(op, "move_prop")) { S->prop[0] = 0; S->pdx = S->pdy = 0; }
    if (!strcmp(op, "prop_frame")) S->fprop[0] = 0;
}

void seq_tick(void) {
    if (!S->steps) {
        layer_remove(L_SEQ);
        return;
    }
    for (;;) { /* run instant steps in one tick, stop at the first timed one */
        const cJSON *st = cJSON_GetArrayItem(S->steps, S->idx);
        if (!st) {
            finish();
            return;
        }
        if (!S->step_started) {
            S->step_started = true;
            S->t = 0;
            S->dur = start_step(st);
            if (S->dur < 0) return; /* "end" */
            if (layer_top() != L_SEQ) { /* a line was pushed on top: resume after it */
                S->idx++;
                S->step_started = false;
                if (!cJSON_GetArrayItem(S->steps, S->idx)) finish(); /* the last step handed over (a fight, a */
                return;                                               /* puzzle): the next scene may start freely */
            }
        }
        if (S->dur <= 0) {
            end_step(st);
            S->idx++;
            S->step_started = false;
            continue;
        }
        float before = S->t;
        S->t += TICK_MS;
        if (S->t > S->dur) S->t = S->dur;
        update_step(st, S->t / S->dur, (S->t - before) / S->dur);
        if (S->t >= S->dur) {
            end_step(st);
            S->idx++;
            S->step_started = false;
        }
        return;
    }
}

/* ------------------------------------------------------------------ listening points */
static listen_state *Li = &G.lis;

void listen_start(const char *id) {
    cJSON *def = jget(G.listens, id);
    if (!def) {
        hal_log("unknown listen point %s", id);
        return;
    }
    memset(Li, 0, sizeof *Li);
    Li->def = def;
    snprintf(Li->id, sizeof Li->id, "%s", id);
    Li->max = (float)jint(def, "max_ms", 6000); /* dossier p.19: up to 6 s */
    if (jstr(def, "audio")) audio_voice(jstr(def, "audio")); /* the director ducks the bed while listening */
    layer_push(L_LISTEN);
}

static void listen_finish(void) {
    cJSON *def = Li->def;
    Li->def = NULL;
    audio_voice_stop(250);
    layer_remove(L_LISTEN);
    effects_run(jget(def, "do")); /* applied on completion or interruption: listening never blocks */
    if (jstr(def, "after")) dlg_open(jstr(def, "after"));
}

void listen_tick(void) {
    if (!Li->def) {
        layer_remove(L_LISTEN);
        return;
    }
    Li->t += TICK_MS;
    if (Li->pulse > 0) Li->pulse -= TICK_MS;
    const cJSON *c;
    while ((c = cJSON_GetArrayItem(jget(Li->def, "cues"), Li->cue)) && jai(c, 0, 0) <= Li->t) {
        const char *kind = jas(c, 1) ? jas(c, 1) : "";
        if (!strcmp(kind, "sub") && jas(c, 2)) Li->sub = jas(c, 2);
        else if (!strcmp(kind, "pulse")) Li->pulse = 250;
        Li->cue++;
    }
    if ((G.in.pressed & ACT_BACK) || Li->t >= Li->max) listen_finish();
}

void listen_render(surface *s) {
    const font *f = ui_font(), *b = ui_bold();
    const char *title = "Escuchando", *hint = "B para parar";
    int tw = font_width(b, title, -1) + font_width(f, hint, -1) + 80, tx = (SCREEN_W - tw) / 2, th = b->h + 16;
    gfx_plate(s, tx, 8, tw, th, C_PAPER);
    asset *ear = gfx_asset("FX_LISTEN");
    gfx_blit(s, ear, ((int)G.anim_ms / 200) % ear->frames, tx + 10, 8 + (th - ear->h) / 2, 0, false);
    int hx = tx + 34 + font_draw(s, b, tx + 34, 14, title, -1, -1, C_INK) + 14;
    font_draw(s, f, hx, 14, hint, -1, -1, C_DIM);
    float p = Li->max > 0 ? Li->t / Li->max : 1;
    gfx_fill(s, tx + 6, 8 + th - 5, (int)((tw - 12) * (p > 1 ? 1 : p)), 2, C_TERRA);
    if (Li->pulse > 0) { /* ripples in sync with the cues (also covers playing without sound) */
        int r = 8 + (int)((250 - Li->pulse) / 10), cx = (int)(G.klaus.x * 2) % SCREEN_W, cy = 120;
        (void)cx;
        for (int k = 0; k < 2; k++) {
            int rr = r + k * 10;
            for (int a = 0; a < 64; a++) {
                float t = a * 6.2831853f / 64;
                gfx_fill(s, SCREEN_W / 2 + (int)(rr * cosf(t)) - 1, cy + (int)(rr * sinf(t)) - 1, 2, 2, C_PAPER);
            }
        }
    }
    if (Li->sub) {
        uint16_t ls[8], ll[8];
        int n = text_wrap(f, Li->sub, SCREEN_W - 64, ls, ll, 3), lh = f->h + 2, h = n * lh + 34;
        int y = SCREEN_H - h - 8;
        gfx_panel(s, 8, y, SCREEN_W - 16, h);
        /* what kind of sound it is (C2): real and located, an echo, or something familiar; label, never colour alone */
        const char *kind = jstr(Li->def, "kind") ? jstr(Li->def, "kind") : "";
        const char *lbl = jstr(Li->def, "label") ? jstr(Li->def, "label") /* a game's own reading (Geumgye: the receiver) */
                        : !strcmp(kind, "eco") ? "Eco" : !strcmp(kind, "familiar") ? "Familiar ?" : !strcmp(kind, "fisico") ? "Sonido real" : "Sonido";
        uint16_t pc = !strcmp(kind, "eco") ? C_TERRA : !strcmp(kind, "familiar") ? C_BROWN : C_BLUEGRAY;
        int level = jint(Li->def, "level", 0), bars = level ? 3 * 10 + 6 : 0; /* signal strength 1-3, by size too */
        int w = font_width(b, lbl, -1) + 24 + bars, ph = b->h + 8;
        gfx_plate(s, 22, y - ph / 2, w, ph, pc);
        font_draw(s, b, 34, y - ph / 2 + 4, lbl, -1, -1, C_PAPER);
        for (int k = 0; k < 3 && level; k++) {
            int bh = 4 + 4 * k, bx = 22 + w - 12 - bars + 6 + k * 10;
            gfx_fill(s, bx, y + ph / 2 - 5 - bh, 7, bh, k < level ? C_OCHRE : C_INK);
        }
        for (int i = 0; i < n; i++) font_draw(s, f, 24, y + 20 + i * lh, Li->sub + ls[i], ll[i], -1, C_BROWN);
    }
}
