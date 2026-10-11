/* Music director (music.json). Every tick it derives from the game state:
 *   - the ambience bed (zone "ambient"), crossfaded between zones;
 *   - the music cue (title, end, or the first matching rule of the zone). A new cue waits for the old
 *     one's bar line, fades it out completely, then starts: two keys never overlap;
 *   - the tension level 0..3 (first matching story rule + zone offset). Each cue's "layers" row for that
 *     level sets its layer gains: layers enter over "up_bars" and leave over "down_bars";
 *   - rests: after "rest.after_s" of the same cue the music fades away for "rest.for_s" and the
 *     ambience carries the scene (repetition is what makes players stop hearing a loop);
 *   - ambient events: one-shots per zone ("events") fired at random intervals over the bed, only while
 *     the player walks freely, so a far bell never covers a listening clip or a line;
 *   - bus ducking (and muffling) for dialogue, listening and the puzzle.
 * Sequences can force a cue ("music") or hush the ambience ("audio_fade") until the next zone. */
#include <stdlib.h>
#include <string.h>

#include "bp.h"

#define MAX_EVENTS 12

static struct {
    char amb[32], cue[32], force[32];
    int level, duck;
    bool switching, hush, resting;
    float cue_ms, rest_ms; /* time the cue has played / remaining rest */
    float ev_ms[MAX_EVENTS]; /* countdown per zone event; 0 = not armed yet */
} D;

static float fnum(const cJSON *o, const char *k, float def) {
    const cJSON *v = jget(o, k);
    return cJSON_IsNumber(v) ? (float)v->valuedouble : def;
}

static int fade(const char *key, int def) { return jint(jget(G.music, "fade"), key, def); }

static const cJSON *cue_def(void) { return jget(jget(G.music, "cues"), D.cue); }

static float bar_s(void) {
    const cJSON *c = cue_def();
    float bpm = fnum(c, "bpm", 0);
    return bpm > 0 ? 60 / bpm * fnum(c, "beats", 4) : 0;
}

static int bars_ms(const char *key, float def_bars, int def_ms) {
    float b = bar_s();
    return b > 0 ? (int)(fnum(jget(G.music, "fade"), key, def_bars) * b * 1000) : def_ms;
}

/* ------------------------------------------------------------------ named feedback sounds */
/* music.json "sfx" maps a name to an id or [id, gain]. */
static void play_named(const char *what) {
    const cJSON *x = jget(jget(G.music, "sfx"), what), *g = cJSON_GetArrayItem(x, 1);
    audio_sfx(cJSON_IsString(x) ? x->valuestring : jas(x, 0), cJSON_IsNumber(g) ? (float)g->valuedouble : 1);
}

/* Menu clicks queue per tick and only the most important plays (switching tabs is back + open). */
static const char *const UI_ORDER[] = {"move", "back", "open", "ok"};
static int ui_pending = -1;

void sound(const char *what) {
    for (int i = 0; i < 4; i++)
        if (!strcmp(what, UI_ORDER[i])) {
            if (i > ui_pending) ui_pending = i;
            return;
        }
    play_named(what);
}

/* ------------------------------------------------------------------ cue and layers */
/* A plain id, or [{"if", key}...]: the first rule whose condition holds (the pipe roars until it is shut). */
static const char *first_rule(const cJSON *rules, const char *key) {
    if (cJSON_IsString(rules)) return rules->valuestring;
    const cJSON *r;
    cJSON_ArrayForEach(r, rules) if (cond_eval(jget(r, "if"))) return jstr(r, key);
    return NULL;
}

static int story_tension(void) {
    const cJSON *r;
    int level = 0;
    cJSON_ArrayForEach(r, jget(G.music, "tension")) if (cond_eval(jget(r, "if"))) {
        level = jint(r, "level", 0);
        break;
    }
    level += jint(jget(G.music, "zone_tension"), G.zone.id, 0);
    return level < 0 ? 0 : level > 3 ? 3 : level;
}

static void layer_gains(float *g) {
    const cJSON *row = cJSON_GetArrayItem(jget(cue_def(), "layers"), D.level);
    for (int i = 0; i < MAX_STEMS; i++) {
        const cJSON *v = cJSON_GetArrayItem(row, i);
        g[i] = row ? (cJSON_IsNumber(v) ? (float)v->valuedouble : 0) : (i == 0);
    }
}

static void apply_layers(int ms) {
    float g[MAX_STEMS];
    layer_gains(g);
    for (int i = 0; i < MAX_STEMS; i++) audio_music_layer(i, g[i], ms);
}

static void start_cue(int level) {
    float g[MAX_STEMS];
    D.level = level;
    D.cue_ms = 0;
    layer_gains(g);
    audio_music_start(D.cue, fnum(cue_def(), "loop_at", 0), bar_s(), g, fade("cue_in", 3000));
}

static void set_cue(const char *cue, int level) {
    if (!cue) cue = "";
    if (strcmp(cue, D.cue)) {
        snprintf(D.cue, sizeof D.cue, "%s", cue);
        audio_music_stop(fade("cue_out", 2000));
        D.switching = true;
        D.resting = false;
    }
    if (D.switching) {
        if (audio_music_playing()) return;
        D.switching = false;
        if (*D.cue) start_cue(level);
        return;
    }
    if (!*D.cue) return;
    const cJSON *rest = jget(G.music, "rest");
    D.cue_ms += TICK_MS;
    if (D.resting) { /* silence is part of the score; a change of tension ends it early */
        D.rest_ms -= TICK_MS;
        if ((D.rest_ms <= 0 || level > D.level) && !audio_music_playing()) { /* the old one has faded out */
            D.resting = false;
            start_cue(level);
        }
        return;
    }
    if (rest && !*D.force && D.cue_ms > fnum(rest, "after_s", 1e6f) * 1000 && level <= jint(rest, "max_tension", 1)) {
        D.resting = true;
        D.rest_ms = fnum(rest, "for_s", 40) * 1000;
        audio_music_stop(bars_ms("rest_out_bars", 4, 6000));
        return;
    }
    if (level != D.level) {
        int ms = level > D.level ? bars_ms("up_bars", 1.5f, 2500) : bars_ms("down_bars", 3, 8000);
        D.level = level;
        apply_layers(ms);
    }
}

static float rand_in(const cJSON *range) {
    float lo = (float)jai(range, 0, 30), hi = (float)jai(range, 1, (int)lo);
    if (lo < 1) lo = 1; /* never every tick, whatever the SD says */
    if (hi < lo) hi = lo;
    return (lo + (hi - lo) * (float)rand() / (float)RAND_MAX) * 1000;
}

/* music.json "events": zone -> [{id, every: [min_s, max_s], gain, if}]. */
static void ambient_events(void) {
    const cJSON *e;
    int i = 0;
    bool free_play = layer_top() == L_PLAY && !D.hush;
    cJSON_ArrayForEach(e, jget(jget(G.music, "events"), G.zone.id)) {
        if (i == MAX_EVENTS) break;
        float *t = &D.ev_ms[i++];
        if (*t <= 0) *t = rand_in(jget(e, "every")); /* first one comes after a full wait, never on entry */
        if (!free_play || (*t -= TICK_MS) > 0) continue;
        *t = rand_in(jget(e, "every"));
        if (cond_eval(jget(e, "if"))) audio_sfx(jstr(e, "id"), fnum(e, "gain", 0.5f));
    }
}

/* Ducking presets in music.json "duck": name -> [ambience gain, music gain, fade ms, ambience lowpass Hz]. */
static void set_duck(int which) {
    static const char *names[] = {"none", "dialogue", "listen", "puzzle", "tell"};
    if (which == D.duck) return;
    D.duck = which;
    const cJSON *d = jget(jget(G.music, "duck"), names[which]);
    float amb = cJSON_GetArrayItem(d, 0) ? (float)cJSON_GetArrayItem(d, 0)->valuedouble : 1;
    float mus = cJSON_GetArrayItem(d, 1) ? (float)cJSON_GetArrayItem(d, 1)->valuedouble : 1;
    float lp = cJSON_GetArrayItem(d, 3) ? (float)cJSON_GetArrayItem(d, 3)->valuedouble : 0;
    audio_bus(amb, mus, lp, jai(d, 2, 800));
}

void music_tick(void) {
    if (ui_pending >= 0) play_named(UI_ORDER[ui_pending]);
    ui_pending = -1;
    if (!G.music) return;
    layer_id base = G.nstack ? G.stack[0] : L_TITLE;
    const char *amb = NULL, *cue = NULL;
    int level = 0;
    if (base == L_TITLE || base == L_END) {
        const cJSON *k = jget(G.music, base == L_TITLE ? "title" : "end");
        cue = jstr(k, "cue");
        level = jint(k, "tension", 0);
        amb = jstr(k, "ambient");
    } else if (base == L_PLAY && G.zone.def) {
        amb = D.hush ? NULL : first_rule(jget(G.zone.def, "ambient"), "id");
        cue = *D.force ? D.force : first_rule(jget(jget(G.music, "zones"), G.zone.id), "cue");
        level = *D.force ? 3 : story_tension();
        ambient_events();
    }
    if (strcmp(amb ? amb : "", D.amb)) {
        snprintf(D.amb, sizeof D.amb, "%s", amb ? amb : "");
        audio_ambient(amb, fade(D.hush ? "hush" : "ambient", 1800));
    }
    set_cue(cue, level);
    set_duck(G.lis.def ? 2 : G.dlg.active ? 1 : layer_has(L_PUZZLE) ? 3 : arena_telling() ? 4 : 0);
}

void music_force(const char *cue) { snprintf(D.force, sizeof D.force, "%s", cue ? cue : ""); }

void music_hush(void) { D.hush = true; }

/* New zone: sequence overrides end. */
void music_zone_changed(void) {
    D.force[0] = 0;
    D.hush = false;
    memset(D.ev_ms, 0, sizeof D.ev_ms);
    const cJSON *e; /* the zone's sounds load now, during the transition, not on first play */
    if (!G.zone.def) return;
    audio_preload(jstr(G.zone.def, "steps"));
    cJSON_ArrayForEach(e, jget(jget(G.music, "events"), G.zone.id)) audio_preload(jstr(e, "id"));
}

void music_reset(void) {
    memset(&D, 0, sizeof D);
    D.level = -1;
    ui_pending = -1;
}
