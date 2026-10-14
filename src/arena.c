/* Side-view boss arena: one mecha against one boss with a fixed pattern
 * sequence. Move, attack, guard, perfect guard, dodge with invulnerability, resonance, a second phase,
 * exposure, guided breathing and the Canto; defeat offers retry, leave or help. An arena with "goals"
 * (a cockpit simulation) ends when the player has blocked, hit, dodged and breathed instead: the
 * target is exposed once the others are done, and breathing finishes it. Every number lives in
 * arena.json (defaults below); times are 60 Hz ticks and distances are world pixels
 * between body centres. Bodies never overlap, so the player always stays left of the boss and nobody
 * has to turn round. A boss with "repair" is a fixed machine: its
 * protection drops only from blows while its "vulnerable" pattern recovers (one blow a window), then it keeps
 * attacking while the player repairs it over "cycles" passes of its phase 2 sequence, and ends stable, never beaten. */
#include <ctype.h>
#include <math.h>
#include <stdlib.h>
#include <string.h>

#include "bp.h"
#include "gfx_px.h"

/* The boss's patterns: charge, bite and slam; a raised plate that stops frontal blows, a
 * guardable sweep, a containment pulse on the player's floor sector and three marks swept left to right. */
enum { PAT_CHARGE, PAT_BITE, PAT_SLAM, PAT_SHIELD, PAT_SWEEP, PAT_PULSE, PAT_MARKS, NPAT };
enum { G_GUARD, G_HIT, G_DODGE, G_BREATH, NGOALS };
static const char *const GOAL_KEY[NGOALS] = {"guard", "hit", "dodge", "breath"};
static const char *const PAT_KEY[NPAT] = {"charge", "bite", "slam", "shield", "sweep", "pulse", "marks"};

typedef enum { P_FREE, P_ATTACK, P_GUARD, P_DODGE, P_KNEEL, P_CANTO } pstate;
typedef enum { B_IDLE, B_WAIT, B_APPROACH, B_TELL, B_ACTIVE, B_RECOVER, B_SHAKE, B_EXPOSED, B_FREED, B_INTERLUDE, B_STABLE } bstate;
static const char *const PNAME[] = {"free", "attack", "guard", "dodge", "kneel", "canto"};
static const char *const BNAME[] = {"idle", "wait", "approach", "tell", "active", "recover", "shake", "exposed", "freed", "interlude", "stable"};

typedef struct { int tell, active, recover, damage, reach; bool guard; } pattern;

static struct { /* parameters, read once per attempt from arena.json and its "mods" */
    int floor_y, min_x, max_x, player_x, boss_x, speed, half;
    int hp, atk_windup, atk_active, atk_recover, atk_damage, atk_reach;
    int guard_start, perfect_end, guard_pct;
    int dodge_time, dodge_move, dodge_recover, iframe_from, iframe_to, dodge_dist, immunity;
    int res_hit, res_block, res_perfect, res_dodge, res_hurt, breaths, canto_window;
    int boss_hp, phase2_hp, boss_half, boss_speed, pause, shake;
    int assist_damage, assist_tell;
    int vulnerable, cycles; /* repair mode: the pattern whose recovery opens the plate (-1 any), passes to repair */
    bool fixed, repair;
    pattern pat[NPAT];
} K;

static struct {
    cJSON *doc; /* arena.json, alive while the fight is on screen */
    const cJSON *def;
    bool assist;
    float px, bx;
    int hp, res, pt, immune, dodge_dir;
    pstate ps;
    bool landed, fresh_guard, walking;
    int bhp, bt, phase, seq_i, pat;
    bstate bs;
    bool hit_done, dodged, phase2_due, barked[NPAT + 2];
    int sector, mark_k, inter_t, inter_sector; /* the floor sector a pulse or a mark falls on (0 left .. 2 right) */
    int progress;  /* repair mode: cycles survived while Pau works */
    bool vuln_used; /* repair mode: this window already took its blow */
    const char *bark_spk, *bark;
    int bark_t, bark_slot, spit_t, flash, breaths, canto_i, canto_t, wave, fade, menu_sel, hint_t;
    bool menu, practice;
    unsigned goals, done; /* simulation: goals asked for and reached (bits of G_*) */
} A;

/* Hit effects (§22: impact, dust, sparks; 3 frames each), drawn by code over the fighters. */
enum { FX_IMPACT, FX_SPARK, FX_DUST };
#define FX_N 8
#define FX_FRAME 4 /* ticks per frame */
static struct { int kind, t, big; float x, y; } FX[FX_N];

static void fx(int kind, float x, float y, int big) {
    for (int i = 0; i < FX_N; i++)
        if (FX[i].t <= 0) {
            FX[i].kind = kind, FX[i].t = 3 * FX_FRAME, FX[i].big = big, FX[i].x = x, FX[i].y = y;
            return;
        }
}

/* ------------------------------------------------------------------ parameters */
static void load_params(void) {
    const cJSON *d = A.def, *p = jget(d, "player"), *b = jget(d, "boss");
    const cJSON *at = jget(p, "attack"), *gu = jget(p, "guard"), *dg = jget(p, "dodge"), *rs = jget(p, "resonance");
    K.floor_y = jint(d, "floor_y", 126), K.min_x = jint(d, "min_x", 12), K.max_x = jint(d, "max_x", 228);
    K.player_x = jint(p, "x", 45), K.hp = jint(p, "hp", 100), K.half = jint(p, "half_w", 10), K.speed = jint(p, "speed", 60);
    K.atk_windup = jint(at, "windup", 9), K.atk_active = jint(at, "active", 6), K.atk_recover = jint(at, "recover", 15);
    K.atk_damage = jint(at, "damage", 10), K.atk_reach = jint(at, "reach", 30);
    K.guard_start = jint(gu, "start", 3), K.perfect_end = jint(gu, "perfect_end", 12), K.guard_pct = jint(gu, "pct", 30);
    K.dodge_time = jint(dg, "time", 18), K.dodge_recover = jint(dg, "recover", 21), K.dodge_dist = jint(dg, "dist", 24);
    K.dodge_move = jint(dg, "move", 12); /* the run ends inside the invulnerability: out of reach when it ends */
    K.iframe_from = jai(jget(dg, "iframes"), 0, 6), K.iframe_to = jai(jget(dg, "iframes"), 1, 14);
    K.immunity = jint(p, "immunity", 42), K.breaths = jint(p, "breaths", 3), K.canto_window = jint(p, "canto_window", 60);
    K.res_hit = jint(rs, "hit", 10), K.res_block = jint(rs, "block", 5), K.res_perfect = jint(rs, "perfect", 15);
    K.res_dodge = jint(rs, "dodge", 8), K.res_hurt = jint(rs, "hurt", -8);
    K.boss_x = jint(b, "x", 185), K.boss_hp = jint(b, "hp", 160), K.phase2_hp = jint(b, "phase2_hp", 80);
    K.boss_half = jint(b, "half_w", 26), K.boss_speed = jint(b, "speed", 60), K.pause = jint(b, "pause", 40);
    K.shake = jint(b, "shake", 30);
    K.fixed = cJSON_IsTrue(jget(b, "fixed"));
    K.repair = jget(b, "repair") != NULL;
    K.cycles = jint(jget(b, "repair"), "cycles", 3);
    K.vulnerable = -1;
    for (int i = 0; i < NPAT; i++)
        if (jstr(b, "vulnerable") && !strcmp(jstr(b, "vulnerable"), PAT_KEY[i])) K.vulnerable = i;
    K.assist_damage = jint(jget(d, "assist"), "damage_pct", 65), K.assist_tell = jint(jget(d, "assist"), "tell_pct", 130);
    static const pattern dflt[NPAT] = {{45, 30, 54, 18, 60, true}, {54, 12, 60, 22, 22, false}, {60, 12, 69, 20, 40, true},
                                       {90, 0, 0, 0, 0, true}, {48, 15, 60, 18, 36, true}, {54, 12, 30, 15, 0, false}, {54, 12, 30, 15, 0, false}};
    for (int i = 0; i < NPAT; i++) {
        const cJSON *o = jget(b, PAT_KEY[i]);
        K.pat[i] = (pattern){jint(o, "tell", dflt[i].tell), jint(o, "active", dflt[i].active), jint(o, "recover", dflt[i].recover),
                             jint(o, "damage", dflt[i].damage), jint(o, "reach", dflt[i].reach),
                             jget(o, "guard") ? cJSON_IsTrue(jget(o, "guard")) : dflt[i].guard};
    }
    const cJSON *m;
    cJSON_ArrayForEach(m, jget(d, "mods")) if (cond_eval(jget(m, "if"))) { /* S07 setting: Protector / Ágil */
        K.hp = jint(m, "hp", K.hp);
        K.dodge_recover = jint(m, "dodge_recover", K.dodge_recover);
    }
    const char *af = jstr(d, "assist_flag");
    A.assist = af && flag_get(af);
}

/* ------------------------------------------------------------------ helpers */
/* arena.json "sfx": event -> sound id (hit, block, perfect, dodge, hurt, canto, free, shield, interlude,
 * "tell_" + pattern when it winds up, the pattern's own name when it strikes). Missing ids are silent. */
static void sfx(const char *event) {
    const char *id = jstr(jget(A.def, "sfx"), event);
    if (id) audio_sfx(id, 1);
}

static float gap(void) { return A.bx - A.px; }
static int contact(void) { return K.half + K.boss_half; }
static void add_res(int v) { A.res = A.res + v < 0 ? 0 : A.res + v > 100 ? 100 : A.res + v; }
static void player_set(pstate s) { A.ps = s, A.pt = 0; }
static void boss_set(bstate s, int t) { A.bs = s, A.bt = t; }

/* Centre distance from which a pattern reaches the player (charge: its run plus contact). */
/* (charge: "reach" is its run, so it can start from its run plus contact) */
static bool area(int pat) { return pat == PAT_SHIELD || pat == PAT_PULSE || pat == PAT_MARKS; } /* from where it stands */
static int reach(int pat) {
    return area(pat) ? 1 << 20 : pat == PAT_CHARGE ? K.pat[pat].reach + contact() : K.boss_half + K.pat[pat].reach + K.half;
}
static int sector_of(float x) { /* the floor in three equal sectors between the arena's edges */
    int w = (K.max_x - K.min_x) / 3, k = ((int)x - K.min_x) / (w > 0 ? w : 1);
    return k < 0 ? 0 : k > 2 ? 2 : k;
}
static bool shielded(void) { return (A.bs == B_TELL && A.pat == PAT_SHIELD) || A.bs == B_INTERLUDE; }
static bool plate_open(void) { /* repair mode: only the vulnerable pattern's recovery lets a blow through */
    return A.phase == 1 && A.bs == B_RECOVER && (K.vulnerable < 0 || A.pat == K.vulnerable);
}
static int tell_ticks(int pat) { return A.assist ? (K.pat[pat].tell * K.assist_tell + 50) / 100 : K.pat[pat].tell; }
static bool invulnerable(void) { return A.ps == P_DODGE && A.pt >= K.iframe_from && A.pt <= K.iframe_to; }
static bool guarding(void) { return A.ps == P_GUARD && A.pt >= K.guard_start; }
static bool perfect_guard(void) { return guarding() && A.fresh_guard && A.pt <= K.perfect_end; }

/* §12: one rounding at the end, half up, at least 1. */
static int damage(int base, bool guard) {
    if (base <= 0) return 0; /* simulation targets */
    long pg = guard ? K.guard_pct : 100, pa = A.assist ? K.assist_damage : 100;
    int d = (int)((base * pg * pa + 5000) / 10000);
    return d < 1 ? 1 : d;
}

#define BARK_T 120 /* a hint stays 2 s (§11) */
#define SPIT_T 70  /* the presentation: the boss retches up an old weapon before the fight */

static void say_bark(const cJSON *b) { /* [speaker, text] in the hint strip */
    A.bark_spk = jstr(jget(jget(G.game, "speakers"), jas(b, 0)), "name");
    A.bark = jas(b, 1);
    A.bark_t = BARK_T;
}

static void bark(int slot, const char *key) {
    const cJSON *b = jget(jget(A.def, "barks"), key);
    if (!b || A.barked[slot]) return;
    A.barked[slot] = true;
    A.bark_slot = slot;
    say_bark(b);
}

/* ------------------------------------------------------------------ fight */
static void reset_fight(void) {
    load_params();
    cJSON *doc = A.doc;
    const cJSON *def = A.def;
    bool assist = A.assist, practice = A.practice;
    memset(&A, 0, sizeof A);
    A.doc = doc, A.def = def, A.assist = assist, A.practice = practice;
    memset(FX, 0, sizeof FX);
    A.px = (float)K.player_x, A.bx = (float)K.boss_x, A.hp = K.hp, A.bhp = K.boss_hp, A.phase = 1;
    const cJSON *g;
    cJSON_ArrayForEach(g, jget(A.def, "goals")) for (int i = 0; i < NGOALS; i++)
        if (cJSON_IsString(g) && !strcmp(g->valuestring, GOAL_KEY[i])) A.goals |= 1u << i;
    boss_set(B_IDLE, 0);
}

static void expose(void);

/* Simulation: tick off a goal; with all but breathing done the target kneels, and breathing ends it. */
static void reach_goal(int g) {
    if (!(A.goals & (1u << g)) || (A.done & (1u << g))) return;
    A.done |= 1u << g;
    sound("ok");
    unsigned rest = A.goals & ~A.done;
    if (rest == (1u << G_BREATH) && A.bs != B_EXPOSED) expose();
    if (!rest) A.fade = 1;
}

static void expose(void) {
    boss_set(B_EXPOSED, 0);
    A.bark_t = 0; /* the fight's hints are over */
    A.breaths = A.res < 100 ? K.breaths : 0;
    if (jstr(A.def, "exposed")) dlg_open(jstr(A.def, "exposed"));
}

static void enemy_hit(int pat) {
    if (A.hit_done || A.ps == P_KNEEL) return;
    if (invulnerable()) { /* a real dodge pays once per enemy action */
        if (!A.dodged) A.dodged = true, add_res(K.res_dodge), reach_goal(G_DODGE), sfx("perfect");
        return;
    }
    if (A.immune > 0) return;
    bool guard = guarding() && K.pat[pat].guard;
    A.hit_done = true;
    if (guarding() && !guard && jstr(A.def, "unguardable_hint")) A.hint_t = 120; /* "B · Esquiva" */
    if (guard) reach_goal(G_GUARD);
    if (guard && perfect_guard()) {
        add_res(K.res_perfect);
        sfx("perfect");
        fx(FX_SPARK, A.px + K.half, K.floor_y - 22, 1);
        return;
    }
    sfx(guard ? "block" : "hurt");
    fx(guard ? FX_SPARK : FX_IMPACT, A.px + K.half, K.floor_y - 22, 0);
    A.hp -= damage(K.pat[pat].damage, guard);
    add_res(guard ? K.res_block : K.res_hurt);
    A.immune = K.immunity;
    if (A.hp <= 0) A.hp = 0, A.bark_t = 0, player_set(P_KNEEL);
}

static void player_hits(void) {
    if (A.landed || A.bs == B_EXPOSED || A.bs == B_FREED || A.bs == B_STABLE || gap() > K.atk_reach + K.boss_half) return;
    if (shielded() || (K.repair && (!plate_open() || A.vuln_used))) { /* the plate takes it: no stability lost */
        A.landed = true;
        sfx("shield");
        fx(FX_SPARK, A.bx - K.boss_half + 2, K.floor_y - 24, 0);
        return;
    }
    A.landed = true, A.flash = 12;
    sfx("hit");
    fx(FX_IMPACT, A.bx - K.boss_half + 2, K.floor_y - 22, 0);
    add_res(K.res_hit);
    reach_goal(G_HIT);
    A.bhp -= K.atk_damage;
    if (K.repair) { /* protection: a blow a window; empty, Pau can reach the panel */
        A.vuln_used = true;
        if (A.bhp <= 0) A.bhp = 0, A.phase2_due = true;
        return;
    }
    if (A.phase == 1 && A.bhp <= K.phase2_hp) A.phase2_due = true;
    if (A.bhp <= 1) A.bhp = 1, expose(); /* never kill: the boss is freed, not executed */
}

static void exposed_input(uint16_t p) {
    if (A.res < 100 && (p & ACT_OK)) { /* guided breathing: fills what is missing in the pulses left */
        int left = A.breaths > 0 ? A.breaths : 1;
        add_res((100 - A.res + left - 1) / left);
        if (A.breaths > 0) A.breaths--;
        sfx("canto");
        reach_goal(G_BREATH);
    } else if (A.goals && (p & ACT_OK)) {
        reach_goal(G_BREATH);
    } else if (A.res >= 100 && !A.goals && (p & ACT_UP)) {
        player_set(P_CANTO);
        A.canto_i = A.canto_t = 0;
        say_bark(cJSON_GetArrayItem(jget(A.def, "canto_barks"), 0)); /* §12: the others help, one line a pulse */
    }
}

#define BARK_W (SCREEN_W - 40)

#define CANTO_LEAD 20 /* dark ticks before each pulse lights up */

static bool canto_open(void) { return A.canto_t > CANTO_LEAD && A.canto_t <= CANTO_LEAD + K.canto_window; }

#define WAVE_T 20  /* a confirmed pulse's wave: 4 frames of 5 ticks */
#define FREE_T 210 /* the release: light, falling iron, the boss withdraws, then black */

static bool releasing(void) { return A.bs == B_FREED && !A.goals; }
static int end_ticks(void) { return releasing() ? FREE_T : A.bs == B_STABLE ? 120 : 60; } /* stable: a beat, then black */

static void canto_tick(uint16_t p) {
    if (A.wave && ++A.wave > WAVE_T) A.wave = 0;
    if (++A.canto_t > CANTO_LEAD + K.canto_window) A.canto_t = 0; /* missed: the same pulse again, no harm */
    if ((p & ACT_OK) && canto_open()) {
        A.canto_i++, A.canto_t = 0, A.wave = 1, sfx("canto");
        if (A.canto_i < 3) say_bark(cJSON_GetArrayItem(jget(A.def, "canto_barks"), A.canto_i));
    }
    if (A.canto_i >= 3) boss_set(B_FREED, 0), A.fade = 1, sfx("free");
}

static void player_tick(void) {
    uint16_t h = G.in.held, p = G.in.pressed;
    A.pt++;
    if (A.immune > 0) A.immune--;
    A.walking = false;
    switch (A.ps) {
    case P_GUARD:
        if (h & ACT_DOWN) break;
        player_set(P_FREE);
        /* fall through - releasing the guard and pressing A or B on the same tick still acts */
    case P_FREE:
        if (A.bs == B_EXPOSED) { exposed_input(p); break; }
        if (p & ACT_OK) { player_set(P_ATTACK); A.landed = false; break; }
        if (p & ACT_BACK) { A.dodge_dir = (h & ACT_RIGHT) ? 1 : -1; player_set(P_DODGE); sfx("dodge"); fx(FX_DUST, A.px, K.floor_y - 1, 0); break; } /* no direction: back */
        if (h & ACT_DOWN) { A.fresh_guard = (p & ACT_DOWN) != 0; player_set(P_GUARD); break; }  /* held over: no perfect */
        int dx = !!(h & ACT_RIGHT) - !!(h & ACT_LEFT);
        A.px += (float)(dx * K.speed) / TICK_HZ;
        A.walking = dx != 0;
        break;
    case P_ATTACK:
        if (A.pt > K.atk_windup && A.pt <= K.atk_windup + K.atk_active) player_hits();
        if (A.pt >= K.atk_windup + K.atk_active + K.atk_recover) player_set(P_FREE);
        break;
    case P_DODGE:
        if (A.pt <= K.dodge_move) A.px += (float)(A.dodge_dir * K.dodge_dist) / K.dodge_move;
        if (A.pt >= K.dodge_time + K.dodge_recover) player_set(P_FREE);
        break;
    case P_KNEEL:
        if (A.pt >= 60) A.menu = true, A.menu_sel = 0;
        break;
    case P_CANTO: canto_tick(p); break;
    }
}

static int pattern_of(const char *step) {
    for (int i = 0; step && i < NPAT; i++)
        if (!strcmp(step, PAT_KEY[i])) return i;
    return -1;
}

static void start_tell(void) {
    static const char *const tell[NPAT] = {"tell_charge", "tell_bite", "tell_slam", "tell_shield", "tell_sweep", "tell_pulse", "tell_marks"};
    boss_set(B_TELL, tell_ticks(A.pat));
    A.vuln_used = false;
    bark(A.pat, PAT_KEY[A.pat]);
    sfx(tell[A.pat]);
    if (A.pat == PAT_PULSE) A.sector = sector_of(A.px); /* under the player: step out of it */
    if (A.pat == PAT_MARKS) A.sector = A.mark_k = 0;    /* left, centre, right, one at a time */
}

static void active_tick(void) {
    const pattern *pt = &K.pat[A.pat];
    if (A.pat == PAT_SHIELD) { /* the plate comes down: nothing to hit */
    } else if (A.pat == PAT_PULSE || A.pat == PAT_MARKS) {
        if (sector_of(A.px) == A.sector) enemy_hit(A.pat);
        if (!A.bt && A.pat == PAT_MARKS && A.mark_k < 2) { /* the next sector */
            A.sector = ++A.mark_k, A.hit_done = false;
            boss_set(B_TELL, tell_ticks(PAT_MARKS));
            sfx("tell_marks");
            return;
        }
    } else if (A.pat == PAT_CHARGE) { /* runs its reach over its active time and stops at the first contact */
        A.bx -= (float)pt->reach / pt->active;
        if (gap() <= contact()) {
            A.bx = A.px + (float)contact();
            fx(FX_DUST, A.bx - K.boss_half, K.floor_y - 1, 0);
            enemy_hit(PAT_CHARGE);
            A.bt = 0;
        }
    } else if (gap() <= reach(A.pat)) {
        enemy_hit(A.pat);
    }
    if (!A.bt) boss_set(B_RECOVER, pt->recover);
}

/* The interlude's pulses: each marks the player's sector "tell" ticks before its second and strikes for "active". */
static int pulse_phase(void) { /* -1 none, 0 marking, 1 striking */
    const cJSON *in = jget(jget(A.def, "boss"), "interlude"), *t;
    const pattern *pt = &K.pat[PAT_PULSE];
    cJSON_ArrayForEach(t, jget(in, "pulses")) {
        int at = t->valueint;
        if (A.inter_t >= at - pt->tell && A.inter_t < at) return 0;
        if (A.inter_t >= at && A.inter_t < at + pt->active) return 1;
    }
    return -1;
}

static void interlude_tick(void) {
    const cJSON *t;
    A.inter_t++;
    cJSON_ArrayForEach(t, jget(jget(jget(A.def, "boss"), "interlude"), "pulses"))
        if (A.inter_t == t->valueint - K.pat[PAT_PULSE].tell) { /* a pulse starts marking where the player is */
            A.inter_sector = sector_of(A.px), A.hit_done = false;
            sfx("tell_pulse");
        }
    cJSON_ArrayForEach(t, jget(jget(jget(A.def, "boss"), "interlude"), "pulses"))
        if (A.inter_t == t->valueint) sfx("pulse");
    if (pulse_phase() == 1 && sector_of(A.px) == A.inter_sector) enemy_hit(PAT_PULSE);
    if (!A.bt) boss_set(B_IDLE, 0); /* power cut: phase 2 */
}

static void boss_tick(void) {
    if (A.bt > 0) A.bt--;
    switch (A.bs) {
    case B_IDLE: {
        if (A.phase2_due) { /* once: a short shake without damage, then the phase 2 sequence */
            A.phase2_due = false, A.phase = 2, A.seq_i = 0;
            const cJSON *in = jget(jget(A.def, "boss"), "interlude");
            if (in) { /* the boss kneels, out of reach, while the player cuts its power; pulses leave a safe zone */
                bark(NPAT + 1, "interlude");
                sfx("interlude");
                A.inter_t = 0;
                boss_set(B_INTERLUDE, jint(in, "ticks", 360));
                break;
            }
            bark(NPAT, "phase2");
            boss_set(B_SHAKE, K.shake);
            break;
        }
        const cJSON *seq = jget(jget(A.def, "boss"), A.phase == 1 ? "phase1" : "phase2");
        int n = cJSON_GetArraySize(seq);
        if (K.repair && A.phase == 2 && n && A.seq_i == n) { /* a whole pass survived: Pau closes a segment */
            A.seq_i = 0;
            const cJSON *b = cJSON_GetArrayItem(jget(jget(jget(A.def, "boss"), "repair"), "barks"), A.progress);
            if (++A.progress >= K.cycles) {
                boss_set(B_STABLE, 0), A.fade = 1, A.bark_t = 0;
                sfx("stable");
                break;
            }
            if (b) say_bark(b);
            sfx("segment");
        }
        A.pat = pattern_of(n ? jas(seq, A.seq_i++ % n) : NULL);
        if (A.pat < 0) boss_set(B_WAIT, K.pause);
        else if (!K.fixed && gap() > reach(A.pat)) boss_set(B_APPROACH, 0);
        else start_tell();
        break;
    }
    case B_WAIT:
    case B_SHAKE:
    case B_RECOVER:
        if (!A.bt) boss_set(B_IDLE, 0);
        break;
    case B_APPROACH: /* walks into range without a hitbox */
        A.bx -= (float)K.boss_speed / TICK_HZ;
        if (gap() <= reach(A.pat)) start_tell();
        break;
    case B_TELL:
        if (!A.bt) {
            boss_set(B_ACTIVE, K.pat[A.pat].active), A.hit_done = A.dodged = false;
            sfx(PAT_KEY[A.pat]);
            if (A.pat == PAT_SLAM) { /* the fists land: dust both ways along the ring */
                fx(FX_DUST, A.bx - K.boss_half - 12, K.floor_y - 1, 1);
                fx(FX_DUST, A.bx - K.boss_half - 34, K.floor_y - 1, 1);
            }
        }
        break;
    case B_ACTIVE: active_tick(); break;
    case B_INTERLUDE: interlude_tick(); break;
    case B_EXPOSED:
    case B_FREED:
    case B_STABLE: break;
    }
}

static void clamp_bodies(void) {
    float lo = (float)(K.min_x + K.half), hi = (float)(K.max_x - K.boss_half);
    if (A.bx > hi) A.bx = hi;
    if (A.px < lo) A.px = lo;
    if (A.px > A.bx - contact()) A.px = A.bx - (float)contact();
    if (A.px < lo) A.px = lo, A.bx = lo + (float)contact();
}

static void leave(const char *key) {
    if (A.practice && !strcmp(key, "win")) key = jget(A.def, "practice_win") ? "practice_win" : "leave";
    const cJSON *fx = jget(A.def, key);
    layer_remove(L_ARENA);
    music_zone_changed(); /* the zone's cue and ambience come back */
    effects_run(fx);
    arena_free();
}

static const char *menu_label(int i) {
    static char help[32];
    snprintf(help, sizeof help, "Ayuda: %s", A.assist ? "sí" : "no");
    const char *labels[] = {"Reintentar", jstr(A.def, "leave_label") ? jstr(A.def, "leave_label") : "Volver", help};
    return labels[i];
}

static void menu_tick(void) {
    uint16_t p = G.in.pressed;
    if (p & ACT_DOWN) A.menu_sel = (A.menu_sel + 1) % 3, sound("move");
    if (p & ACT_UP) A.menu_sel = (A.menu_sel + 2) % 3, sound("move");
    if (!(p & ACT_OK)) return;
    sound("ok");
    if (A.menu_sel == 0) reset_fight();
    else if (A.menu_sel == 1) leave("leave");
    else {
        const char *af = jstr(A.def, "assist_flag");
        if (af) flag_set(af, !flag_get(af));
        A.assist = af && flag_get(af);
    }
}

/* ------------------------------------------------------------------ public */
void arena_free(void) {
    cJSON_Delete(A.doc);
    memset(&A, 0, sizeof A);
}

static void hd_reset(void); /* (render section) */

void arena_start(const char *id) {
    arena_free();
    hd_reset(); /* a new fight: the camera starts where it should, the HD pictures are looked up again */
    A.practice = false; /* the effect turns it on after the start */
    A.doc = json_file("arena.json");
    A.def = jget(A.doc, id ? id : "");
    if (!A.def) {
        arena_free();
        game_error("No se encuentra la arena %s.", id ? id : "?");
        return;
    }
    reset_fight();
    layer_push(L_ARENA);
    if (jstr(A.def, "music")) music_force(jstr(A.def, "music")); /* the fight's cue; the zone's ambience goes quiet */
    music_hush();
    const cJSON *s;
    cJSON_ArrayForEach(s, jget(A.def, "sfx")) if (cJSON_IsString(s)) audio_preload(s->valuestring);
    const char *seen = jstr(A.def, "intro_flag"), *intro = jstr(A.def, "intro");
    if (intro && !(seen && flag_get(seen))) { /* the presentation plays once; retries skip it */
        if (seen) flag_set(seen, 1);
        if (jget(A.def, "intro_spit")) A.spit_t = 1, sfx("spit"); /* the dialogue waits for the weapon to land */
        else dlg_open(intro);
    }
}

/* Before the fight the boss spits out an old weapon; it arcs out and stays on the ground. */
static bool spitting(void) { return A.spit_t > 0 && A.spit_t < SPIT_T; }

static void spit_tick(void) {
    if (++A.spit_t == 50) sfx("spit_land"), fx(FX_DUST, A.bx - K.boss_half - 44, K.floor_y - 1, 0);
    if (A.spit_t == SPIT_T) dlg_open(jstr(A.def, "intro"));
}

/* After the chapter, the fight can be replayed: the state is the finished game's, a win hands
 * nothing again and nothing is saved inside the arena, so a power cut lands on the completed chapter. */
void arena_practice(bool on) { A.practice = on; }

/* For scripts (a duration run, §02): a plain player with no shortcuts. Guards the charge and the slam, dodges the
 * bite just before it, walks in and hits while the boss recovers, retries a defeat, breathes and sings. Returns
 * the keys to hold this tick; a press is a key held after a tick without it. */
uint16_t arena_bot(void) {
    static uint16_t last;
    uint16_t want = 0;
    if (!A.def || A.fade || spitting()) want = 0;
    else if (A.menu) want = ACT_OK; /* Reintentar */
    else if (A.ps == P_CANTO) want = canto_open() ? ACT_OK : 0;
    else if (A.bs == B_EXPOSED) want = A.res < 100 || A.goals ? ACT_OK : ACT_UP;
    else if (A.bs == B_INTERLUDE || ((A.bs == B_TELL || A.bs == B_ACTIVE) && (A.pat == PAT_PULSE || A.pat == PAT_MARKS))) {
        int marked = A.bs == B_INTERLUDE ? (pulse_phase() >= 0 ? A.inter_sector : -1) : A.sector;
        int w = (K.max_x - K.min_x) / 3, mid = K.min_x + marked * w + w / 2; /* out by the nearest edge */
        bool right = marked == 0 || (marked == 1 && A.px >= mid);
        want = sector_of(A.px) == marked ? (right ? ACT_RIGHT : ACT_LEFT) : 0;
    } else if (A.bs == B_TELL && A.pat == PAT_SHIELD) want = 0;
    else if ((A.bs == B_TELL || A.bs == B_ACTIVE) && A.pat == PAT_BITE) want = A.bs == B_TELL && A.bt == 7 ? ACT_BACK : 0;
    else if (A.bs == B_TELL || A.bs == B_ACTIVE) want = ACT_DOWN;
    else if (A.ps == P_FREE) { /* in reach it hits; a repair machine only while its plate is open */
        bool wait = K.repair && !(plate_open() && !A.vuln_used);
        want = gap() > K.atk_reach + K.boss_half - 2 ? ACT_RIGHT : wait ? 0 : ACT_OK;
    }
    const uint16_t presses = ACT_OK | ACT_BACK | ACT_UP;
    uint16_t held = want & last & presses ? want & ~presses : want; /* let go, so the next tick presses again */
    last = held;
    return held;
}

bool arena_pattern_known(const char *step) { return !strcmp(step, "pause") || pattern_of(step) >= 0; }

bool arena_busy(void) { return A.def && (spitting() || A.fade); } /* no control: scripts' advance waits */
bool arena_telling(void) { return A.def && A.bs == B_TELL; }

void arena_tick(void) {
    for (int i = 0; i < FX_N; i++) if (FX[i].t > 0) FX[i].t--;
    if (spitting()) { spit_tick(); return; }
    if (A.fade) {
        if (++A.fade > end_ticks()) leave("win");
        return;
    }
    if (A.menu) { menu_tick(); return; }
    if (A.bark_t > 0) A.bark_t--;
    if (A.hint_t > 0) A.hint_t--;
    if (A.flash > 0) A.flash--;
    player_tick();
    if (layer_top() != L_ARENA) return; /* exposure opened its dialogue */
    if (A.ps != P_KNEEL && A.ps != P_CANTO) boss_tick();
    clamp_bodies();
}

/* ------------------------------------------------------------------ render */
/* HD: when the arena's background has a <bg>_HD picture, the fight is drawn straight onto the screen's strips at full
 * resolution, from <sprite>_HD pictures (made at HD_K pixels per world pixel), through a camera that comes closer when
 * the fighters do (zoom 1 to ZOOM_MAX, as the Neo Geo's fighting games). The world-pixel drawing below goes through
 * this transform: identity when R.hd is off, so a game without HD pictures draws exactly as before. R is worked out
 * once a frame (arena_render_world), before the strips. */
#define HD_K 3.2f
#define ZOOM_MAX 1.6f
static struct { bool hd, covers; float z, cx; asset *bg; int dim; } R; /* covers: the background fills the screen;
                                                                        * dim: halvings of the whole frame (fades) */

static const int RING[4] = {6, 12, 20, 30}; /* the Canto's wave: 4 frames, one dotted ring each, r * 6 dots */
static int8_t ring_xy[(6 + 12 + 20 + 30) * 6][2];
static float ray_cs[8], ray_sn[8]; /* an impact's 8 rays */

static void hd_reset(void) { /* (and the effects' dots, worked out once: their sines were most of a strip's time) */
    R.hd = false, R.z = 0;
    for (int k = 0, i = 0; k < 4; k++)
        for (int a = 0, n = RING[k] * 6; a < n; a++, i++) {
            float th = a * 6.2831853f / n;
            ring_xy[i][0] = (int8_t)lroundf(RING[k] * cosf(th)), ring_xy[i][1] = (int8_t)lroundf(RING[k] * 0.8f * sinf(th));
        }
    for (int d = 0; d < 8; d++) ray_cs[d] = cosf(d * 0.785398f), ray_sn[d] = sinf(d * 0.785398f);
}

static int sx_(float x) { return R.hd ? (int)floorf(SCREEN_W / 2 + (x - R.cx) * 2 * R.z) : (int)x; }
static int sy_(float y) { return R.hd ? (int)floorf(2 * K.floor_y + (y - K.floor_y) * 2 * R.z) : (int)y; }

static void wfill(surface *s, int x, int y, int w, int h, uint16_t c) { /* a world box, through the camera */
    if (!R.hd) {
        gfx_fill(s, x, y, w, h, c);
        return;
    }
    int x0 = sx_((float)x), y0 = sy_((float)y), x1 = sx_((float)(x + w)), y1 = sy_((float)(y + h));
    if (x1 < x0 + 1) x1 = x0 + 1;
    if (y1 < y0 + 1) y1 = y0 + 1;
    if (x1 <= s->x0 || x0 >= s->x0 + s->w || y1 <= s->y0 || y0 >= s->y0 + s->h) return; /* not in this strip */
    gfx_fill(s, x0, y0, x1 - x0, y1 - y0, c);
}

static const char *sprite_id(char buf[32], int who, const char *suffix) { /* (into the caller's buffer: the HD
                                                                           * scene is drawn by both cores at once) */
    const char *pre = jstr(jget(A.def, who ? "boss" : "player"), "sprite");
    snprintf(buf, 32, "%s_%s", pre ? pre : who ? "BU" : "GG", suffix);
    return buf;
}

static void sprite(surface *s, const char *id, int frame, float x) {
    asset *a = gfx_asset(id);
    if (!R.hd) {
        gfx_blit(s, a, frame, (int)x - a->ax, K.floor_y - a->ay, 0, false);
        return;
    }
    char hd[40];
    snprintf(hd, sizeof hd, "%s_HD", id);
    asset *h = gfx_asset_opt(hd);
    float k = h->missing ? 2 * R.z : 2 * R.z / HD_K; /* (no HD picture: the world's, enlarged) */
    if (h->missing) h = a;
    if (frame >= h->frames) frame = h->frames - 1;
    gfx_blit_ex(s, h, frame, (int)floorf(sx_(x) - h->ax * k), (int)floorf(sy_((float)K.floor_y) - h->ay * k), k, k, 0, NULL, -1);
}

/* Frames by state. An action's frames are split over its phases by arena.json "frames": how many
 * go to each phase (a punch [2, 2, 1]: wind-up, active, recovery), and inside a phase they follow its progress.
 * Without "frames" each phase shows one frame, as before; a count of 0 shows the idle pose instead. */
static int phased(const cJSON *spec, const int *def, int phase, int t, int len) {
    int base = 0, n;
    for (int i = 0; i < phase; i++) base += spec ? jai(spec, i, 0) : def[i];
    if ((n = spec ? jai(spec, phase, 0) : def[phase]) <= 0) return -1;
    int k = len > 0 ? t * n / len : 0;
    return base + (k < n ? k : n - 1);
}

static int loop(const asset *a, int ms) { return (int)(G.anim_ms / ms) % (a->frames > 0 ? a->frames : 1); }
static int upto(const asset *a, int t, int len) { int k = len > 0 ? t * a->frames / len : 0; return k < a->frames ? k : a->frames - 1; }
static bool has_pose(int who, const char *suffix) { /* its own buffer: sprite_id()'s would be overwritten */
    char id[40];
    const char *pre = jstr(jget(A.def, who ? "boss" : "player"), "sprite");
    snprintf(id, sizeof id, "%s_%s", pre ? pre : who ? "BU" : "GG", suffix);
    return !gfx_asset_opt(id)->missing;
}

static void pose(surface *s, const char *id, int frame, float x) { /* clamps to the frames the sheet has */
    asset *a = gfx_asset(id);
    sprite(s, id, frame < 0 ? 0 : frame < a->frames ? frame : a->frames - 1, x);
}

static void draw_player(surface *s) {
    char sb[32];
    const cJSON *pl = jget(A.def, "player");
    bool impact = A.immune > K.immunity - 14 && A.ps == P_FREE && has_pose(0, "IMPACT");
    if (A.immune && !impact && (A.immune / 3) % 2) return; /* hit flicker */
    static const int ATK[3] = {1, 1, 1}, DODGE[2] = {1, 0}, GUARD[2] = {0, 1};
    const char *id;
    int f;
    switch (A.ps) {
    case P_ATTACK: {
        const cJSON *sp = jget(jget(pl, "attack"), "frames");
        int ph = A.pt <= K.atk_windup ? 0 : A.pt <= K.atk_windup + K.atk_active ? 1 : 2;
        int t = ph == 0 ? A.pt : ph == 1 ? A.pt - K.atk_windup : A.pt - K.atk_windup - K.atk_active;
        pose(s, sprite_id(sb, 0, "ATTACK"), phased(sp, ATK, ph, t, ph == 0 ? K.atk_windup : ph == 1 ? K.atk_active : K.atk_recover), A.px);
        break;
    }
    case P_GUARD:
        f = phased(jget(jget(pl, "guard"), "frames"), GUARD, A.pt < K.guard_start ? 0 : 1, 0, 1);
        pose(s, sprite_id(sb, 0, "GUARD"), f < 0 ? 0 : f, A.px);
        break;
    case P_DODGE: {
        bool rec = A.pt >= K.dodge_time;
        f = phased(jget(jget(pl, "dodge"), "frames"), DODGE, rec, rec ? A.pt - K.dodge_time : A.pt, rec ? K.dodge_recover : K.dodge_time);
        pose(s, sprite_id(sb, 0, "DODGE"), f < 0 ? gfx_asset(sprite_id(sb, 0, "DODGE"))->frames - 1 : f, A.px);
        break;
    }
    case P_KNEEL: id = sprite_id(sb, 0, "KNEEL"); pose(s, id, upto(gfx_asset(id), A.pt, 30), A.px); break;
    case P_CANTO: pose(s, sprite_id(sb, 0, "CANTO"), releasing() ? 99 : A.canto_i, A.px); break; /* opens a step a pulse */
    default:
        if (impact) { id = sprite_id(sb, 0, "IMPACT"); pose(s, id, upto(gfx_asset(id), K.immunity - A.immune, 14), A.px); break; }
        id = sprite_id(sb, 0, A.walking ? "WALK" : "IDLE");
        pose(s, id, loop(gfx_asset(id), A.walking ? 125 : 400), A.px);
    }
}

/* Put the background back over a box in a 4x4 ordered dither: level 0..16 of it. */
static void dissolve(surface *s, const asset *bg, int x0, int y0, int w, int h, int level) {
    static const uint8_t bayer[16] = {0, 8, 2, 10, 12, 4, 14, 6, 3, 11, 1, 9, 15, 7, 13, 5};
    for (int y = y0 < 0 ? 0 : y0; y < y0 + h && y < s->h; y++)
        for (int x = x0 < 0 ? 0 : x0; x < x0 + w && x < s->w; x++)
            if (bayer[(y & 3) * 4 + (x & 3)] < level)
                s->px[y * s->w + x] = bg->missing || x >= bg->w || y >= bg->h ? C_INK : bg->pixels[y * bg->w + x];
}

static void draw_spit(surface *s) {
    const char *id = jstr(jget(A.def, "intro_spit"), "sprite");
    if (!A.spit_t || !id) return;
    asset *a = gfx_asset(id);
    int t = A.spit_t < 20 ? -1 : A.spit_t - 20, x0 = (int)A.bx - K.boss_half, y0 = K.floor_y - 24;
    if (t < 0) return; /* still inside: the boss is retching */
    float p = t >= 30 ? 1 : t / 30.0f; /* 30 ticks of flight, then it lies there */
    int x = x0 - (int)(44 * p), y = y0 + (int)(24 * p) - (int)(28 * p * (1 - p));
    int f = p >= 1 && a->frames > 1 ? 1 : 0;
    if (R.hd) { /* (no HD picture of its own: the world's, enlarged) */
        float k = 2 * R.z;
        gfx_blit_ex(s, a, f, (int)floorf(sx_((float)x) - a->ax * k), (int)floorf(sy_((float)y) - a->ay * k), k, k, 0, NULL, -1);
        return;
    }
    gfx_blit(s, a, f, x - a->ax, y - a->ay, 0, false);
}

static void draw_boss(surface *s) {
    char sb[32];
    bool hurt = A.flash && has_pose(1, "HURT");
    if (A.flash && !hurt && (A.flash / 2) % 2) return;
    float x = A.bx + (A.bs == B_SHAKE || (spitting() && A.spit_t < 24) ? ((int)(G.anim_ms / 50) % 2 ? 1.0f : -1.0f) : 0.0f);
    const char *id = sprite_id(sb, 1, "IDLE");
    int frame = loop(gfx_asset(id), 500);
    if (A.bs == B_FREED && has_pose(1, "FREE")) id = sprite_id(sb, 1, "FREE"), frame = upto(gfx_asset(id), A.fade, 120);
    else if (A.bs == B_STABLE && has_pose(1, "STABLE")) id = sprite_id(sb, 1, "STABLE"), frame = loop(gfx_asset(id), 600);
    else if (K.repair && plate_open() && has_pose(1, "OPEN")) id = sprite_id(sb, 1, "OPEN"), frame = loop(gfx_asset(id), 300);
    else if (A.bs == B_EXPOSED || A.bs == B_FREED) id = sprite_id(sb, 1, "EXPOSED"), frame = loop(gfx_asset(id), 700);
    else if (A.bs == B_INTERLUDE) id = sprite_id(sb, 1, has_pose(1, "KNEEL") ? "KNEEL" : "EXPOSED"), frame = loop(gfx_asset(id), 700);
    else if (hurt) id = sprite_id(sb, 1, "HURT"), frame = upto(gfx_asset(id), 12 - A.flash, 12);
    else if (A.bs == B_APPROACH && has_pose(1, "WALK")) id = sprite_id(sb, 1, "WALK"), frame = loop(gfx_asset(id), 150);
    else if (A.bs == B_TELL || A.bs == B_ACTIVE || A.bs == B_RECOVER) {
        static const char *const POSE[NPAT] = {"CHARGE", "BITE", "SLAM", "SHIELD", "SWEEP", "PULSE", "PULSE"};
        static const int DEF[3] = {1, 1, 0}; /* tell, active; recovery shows the idle pose */
        const pattern *pt = &K.pat[A.pat];
        int ph = A.bs == B_TELL ? 0 : A.bs == B_ACTIVE ? 1 : 2, len = ph == 0 ? tell_ticks(A.pat) : ph == 1 ? pt->active : pt->recover;
        int f = phased(jget(jget(jget(A.def, "boss"), PAT_KEY[A.pat]), "frames"), DEF, ph, len - A.bt, len);
        if (f >= 0 && has_pose(1, POSE[A.pat])) id = sprite_id(sb, 1, POSE[A.pat]), frame = f;
    }
    if (releasing() && A.fade > 40) x += (A.fade - 40) * 0.2f;
    int level = releasing() ? (A.fade - 40) * 16 / 120 : 0;
    if (R.hd) { /* the dissolve as it draws: the pixels it leaves show what is under it (no background to read back) */
        surface b = *s;
        b.dither = (uint8_t)(level < 0 ? 0 : level > 16 ? 16 : level);
        pose(&b, id, frame, x);
        return;
    }
    pose(s, id, frame, x);
    if (level > 0) {
        const asset *a = gfx_asset(id);
        dissolve(s, gfx_asset(jstr(A.def, "bg")), (int)x - a->ax, K.floor_y - a->ay, a->w, a->h, level);
    }
}

/* Warnings by shape as well as colour (§05): arrow, teeth, ring on the floor. */
static void sector_mark(surface *s, int k, bool strike) { /* a red frame on the floor, hatched when it strikes */
    int w = (K.max_x - K.min_x) / 3, x = K.min_x + k * w, y = K.floor_y + 1;
    wfill(s, x + 2, y, w - 4, 2, C_TERRA), wfill(s, x + 2, y + 8, w - 4, 2, C_TERRA);
    wfill(s, x + 2, y, 2, 10, C_TERRA), wfill(s, x + w - 4, y, 2, 10, C_TERRA);
    if (strike)
        for (int i = x + 6; i < x + w - 6; i += 4) wfill(s, i, y + 3, 2, 4, C_TERRA);
}

static void draw_tell(surface *s) {
    if (A.bs == B_INTERLUDE) { /* the pulses while Pau works */
        int ph = pulse_phase();
        if (ph == 1 || (ph == 0 && (A.inter_t / 6) % 2 == 0)) sector_mark(s, A.inter_sector, ph == 1);
        return;
    }
    if ((A.pat == PAT_PULSE || A.pat == PAT_MARKS) && (A.bs == B_TELL || A.bs == B_ACTIVE)) {
        if (A.bs == B_ACTIVE || (A.bt / 6) % 2 == 0) sector_mark(s, A.sector, A.bs == B_ACTIVE);
        return;
    }
    if (A.bs != B_TELL || (A.bt / 6) % 2) return;
    int x = (int)A.bx, top = K.floor_y - 52;
    if (A.pat == PAT_SHIELD) { /* a shield: the plate is up */
        wfill(s, x - 7, top - 2, 14, 2, C_PAPER), wfill(s, x - 7, top - 2, 2, 12, C_PAPER);
        wfill(s, x + 5, top - 2, 2, 12, C_PAPER);
        for (int r = 0; r < 5; r++) wfill(s, x - 6 + r, top + 10 + r, 12 - 2 * r, 1, C_PAPER);
        return;
    }
    if (A.pat == PAT_SWEEP) { /* the plate tilts: a slanted bar and the sweep's reach */
        for (int k = 0; k < 14; k++) wfill(s, x - 24 + k, top + 12 - k / 2, 2, 3, C_TERRA);
        int r = K.boss_half + K.pat[PAT_SWEEP].reach;
        wfill(s, x - r, K.floor_y, r - K.boss_half, 2, C_TERRA);
        return;
    }
    if (A.pat == PAT_CHARGE) {
        wfill(s, x - 22, top + 4, 14, 4, C_TERRA);
        for (int k = 0; k < 6; k++) wfill(s, x - 28 + k, top + 6 - k, 1, 2 * k, C_TERRA); /* head of the arrow */
    } else if (A.pat == PAT_BITE) {
        for (int k = 0; k < 4; k++) {
            for (int r = 0; r < 4; r++) wfill(s, x - 10 + k * 5 + r / 2, top + r, 4 - r, 1, C_PAPER);
            for (int r = 0; r < 4; r++) wfill(s, x - 10 + k * 5 + r / 2, top + 10 - r, 4 - r, 1, C_PAPER);
        }
    } else {
        int r = K.boss_half + K.pat[PAT_SLAM].reach;
        wfill(s, x - r, K.floor_y, 2 * r, 2, C_TERRA);
        wfill(s, x - r, K.floor_y - 4, 2, 6, C_TERRA);
        wfill(s, x + r - 2, K.floor_y - 4, 2, 6, C_TERRA);
    }
}

static void bar(surface *s, int x, int y, int w, int v, int max, uint16_t fill) {
    gfx_fill(s, x - 1, y - 1, w + 2, 10, C_PAPER);
    gfx_fill(s, x, y, w, 8, C_INK);
    int f = max > 0 ? w * v / max : 0;
    gfx_fill(s, x, y, f, 8, fill);
    for (int k = 12; k < w; k += 12) gfx_fill(s, x + k, y, 1, 8, C_INK); /* segments */
}

static void label(surface *s, int x, int y, const char *t) {
    const font *f = ui_bold();
    font_draw(s, f, x + 1, y + 1, t, -1, -1, C_INK);
    font_draw(s, f, x, y, t, -1, -1, C_PAPER);
}

static void prompt(surface *s, const char *t, int y) {
    const font *b = ui_bold();
    int w = font_width(b, t, -1) + 28, x = (SCREEN_W - w) / 2;
    gfx_plate(s, x, y, w, b->h + 10, C_INK);
    font_draw(s, b, x + 14, y + 5, t, -1, -1, C_OCHRE);
}

static void draw_canto(surface *s) {
    static const char *const sym[3] = {"CUERPO", "MEMORIA", "VOLUNTAD"};
    const font *b = ui_bold();
    for (int i = 0; i < 3; i++) {
        int w = 120, x = SCREEN_W / 2 - 186 + i * 126, y = SCREEN_H - 70;
        bool done = i < A.canto_i, lit = i == A.canto_i && canto_open();
        gfx_plate(s, x, y, w, 34, done ? C_OCHRE : lit ? C_TERRA : C_INK);
        int tw = font_width(b, sym[i], -1);
        font_draw(s, b, x + (w - tw) / 2, y + 6, sym[i], -1, -1, done ? C_INK : C_PAPER);
    }
    if (canto_open()) prompt(s, "A", SCREEN_H - 112);
}

/* ------------------------------------------------------------------ the Canto's light (§12, §23) */
#define AMBER RGB(0xF3, 0xB6, 0x4D)
#define AMBER_HI RGB(0xFF, 0xE7, 0xA0)
#define STEEL RGB(0x68, 0x74, 0x77)
#define RUST RGB(0x9B, 0x55, 0x47)

static void dot(surface *s, int x, int y, uint16_t c) {
    if (R.hd) wfill(s, x, y, 1, 1, c); /* a world pixel through the camera: a block of the screen's */
    else if (x >= 0 && y >= 0 && x < s->w && y < s->h) s->px[y * s->w + x] = c;
}

/* "Cambio de paleta": each pulse pulls the scene towards the core's amber; darks stay dark. */
static void warm(surface *s, int level) {
    int f = level * 3; /* of 16 */
    if (R.hd) { /* the strip's own pixels, as it keeps them: column by column, stepping (contiguous on the panel) */
        const int ys = step_y(s);
        for (int x = s->x0; x < s->x0 + s->w; x++) {
            uint16_t *d = at(s, x, s->y0);
            for (int y = 0; y < s->h; y++, d += ys) {
                int c = stored(s, *d), r = c >> 11, g = (c >> 5) & 63, b = c & 31;
                r += (31 - r) * f / 24, g += (63 - g) * f / 120, b -= b * f / 20;
                *d = stored(s, (uint16_t)(r << 11 | g << 5 | b));
            }
        }
        return;
    }
    for (int i = 0; i < s->w * s->h; i++) {
        int c = s->px[i], r = c >> 11, g = (c >> 5) & 63, b = c & 31;
        r += (31 - r) * f / 24, g += (63 - g) * f / 120, b -= b * f / 20;
        s->px[i] = (uint16_t)(r << 11 | g << 5 | b);
    }
}

static void wave(surface *s, int cx, int cy, int t) { /* 4 frames, one dotted ring each */
    if (t < 0 || t >= WAVE_T) return;
    int k = t / 5, r = RING[k], i = 0;
    if (R.hd && (sx_((float)(cx + r + 1)) <= s->x0 || sx_((float)(cx - r)) >= s->x0 + s->w)) return; /* not this strip's */
    for (int j = 0; j < k; j++) i += RING[j] * 6;
    for (int a = 0; a < r * 6; a++, i++) dot(s, cx + ring_xy[i][0], cy + ring_xy[i][1], t < 10 ? AMBER_HI : AMBER);
}

static void bands(surface *s, int x0, int t) { /* two bands of pixel light cross the scene from the core */
    for (int k = 0; k < 2; k++) {
        int x = x0 + (t - k * 10) * 5;
        if (t < k * 10) continue;
        if (R.hd && (sx_((float)(x + 6)) <= s->x0 || sx_((float)x) >= s->x0 + s->w)) continue; /* not this strip's */
        for (int y = 0; y < K.floor_y; y++)
            for (int i = 0; i < 6; i++) if (((x + i + y) & 1) == 0) dot(s, x + i, y, k ? AMBER : AMBER_HI);
    }
}

static void falling_iron(surface *s, int bx, int t) { /* the boss lets go of the metal it swallowed */
    for (int k = 0; k < 6; k++) {
        int t0 = 4 + k * 6, x = bx - 22 + k * 9, y = K.floor_y - 14 - (k * 7) % 12;
        if (t < t0) continue;
        y += (t - t0) * (t - t0) / 24;
        if (y > K.floor_y - 2) y = K.floor_y - 2;
        wfill(s, x, y, 3, 2, STEEL);
        dot(s, x + 2, y + 1, RUST);
    }
}

#define DUST RGB(0xC2, 0xB8, 0xAA)

static void draw_fx(surface *s) {
    for (int i = 0; i < FX_N; i++) {
        if (FX[i].t <= 0) continue;
        int k = 2 - (FX[i].t - 1) / FX_FRAME, x = (int)FX[i].x, y = (int)FX[i].y, big = FX[i].big;
        if (FX[i].kind == FX_IMPACT) { /* a star of rays that opens and thins */
            static const int R[3] = {3, 6, 8};
            int r = R[k] + 2 * big;
            for (int d = 0; d < 8; d++)
                for (int q = r / 2; q <= r; q++) dot(s, x + (int)lroundf(q * ray_cs[d]), y + (int)lroundf(q * ray_sn[d]), k ? AMBER : AMBER_HI);
            if (!k) wfill(s, x - 1, y - 1, 3, 3, C_WHITE);
        } else if (FX[i].kind == FX_SPARK) { /* short streaks thrown up and back off the guard */
            for (int j = 0; j < 4 + 2 * big; j++) {
                int dx = -(2 + j % 3) * (k + 1), dy = -(1 + j) * (k + 1) / 2, len = 3 - k;
                for (int q = 0; q < len; q++) dot(s, x + dx - q, y + dy - q, k == 2 ? AMBER : AMBER_HI);
            }
        } else { /* dust: puffs that spread and rise */
            for (int j = -1; j <= 1; j++) {
                int cx = x + j * (4 + 4 * k + 2 * big), cy = y - 1 - k, r = 2 + k + big;
                for (int v = -r; v <= r; v++)
                    for (int u = -r; u <= r; u++)
                        if (u * u + v * v <= r * r && ((u + v + k) & 1) == 0) dot(s, cx + u, cy + v / 2, DUST);
            }
        }
    }
}

static void draw_release(surface *s) {
    const cJSON *core = jget(jget(A.def, "player"), "core"); /* [dx, dy] from the feet, in the Canto pose */
    int cx = (int)A.px + jai(core, 0, 3), cy = K.floor_y - jai(core, 1, 25);
    bool freed = releasing();
    if (!R.hd) warm(s, freed ? 3 : A.canto_i); /* (HD: in the palettes, arena_render_screen) */
    wave(s, cx, cy, freed ? A.fade - 1 : A.wave - 1);
    if (freed) falling_iron(s, (int)A.bx, A.fade), bands(s, cx, A.fade);
    if (A.canto_i > 0) wfill(s, cx - 1, cy - 1, 3, 3, AMBER); /* the core turns amber */
    if (freed || (canto_open() && (int)(G.anim_ms / 120) % 2)) {
        dot(s, cx, cy, AMBER_HI);
        for (int k = 0; k < 4; k++) dot(s, cx + (k < 2 ? (k ? 2 : -2) : 0), cy + (k >= 2 ? (k == 3 ? 2 : -2) : 0), AMBER);
    }
}

static void draw_menu(surface *s) {
    const font *b = ui_bold();
    int x = 140, y = 96, w = 200, rows = 3;
    gfx_panel(s, x, y, w, rows * 34 + 20);
    for (int i = 0; i < rows; i++) {
        int ry = y + 10 + i * 34;
        if (i == A.menu_sel) gfx_fill(s, x + 8, ry + 2, w - 16, 30, C_PAPER_SEL);
        font_draw(s, b, x + 22, ry + (34 - b->h) / 2, menu_label(i), -1, -1, C_INK);
    }
}

/* Repair mode: the plate's protection, then Pau's segments (one box each, filled as they close). */
static void repair_hud(surface *s) {
    const cJSON *r = jget(jget(A.def, "boss"), "repair");
    char t[48];
    int x = SCREEN_W - 156;
    if (A.phase == 1) {
        snprintf(t, sizeof t, "%s", jstr(r, "shield_label") ? jstr(r, "shield_label") : "Protección");
        bar(s, x, 32, 144, A.bhp, K.boss_hp, C_TERRA);
    } else {
        int n = K.cycles > 0 ? K.cycles : 1, w = (144 - (n - 1) * 4) / n;
        snprintf(t, sizeof t, "%s %d/%d", jstr(r, "label") ? jstr(r, "label") : "Reparación", A.progress, n);
        for (int i = 0; i < n; i++) {
            gfx_fill(s, x + i * (w + 4) - 1, 31, w + 2, 10, C_PAPER);
            gfx_fill(s, x + i * (w + 4), 32, w, 8, i < A.progress || A.bs == B_STABLE ? C_OCHRE : C_INK);
        }
    }
    label(s, x - 8 - font_width(ui_bold(), t, -1), 28, t);
}

static void draw_hud(surface *s) {
    char title[48]; /* the game's, in capitals */
    snprintf(title, sizeof title, "%s", jstr(G.game, "title") ? jstr(G.game, "title") : "");
    for (char *c = title; *c; c++) *c = (char)toupper((unsigned char)*c);
    label(s, 12, 6, title);
    bar(s, 12, 32, 144, A.hp, K.hp, C_OCHRE);
    if (!K.repair) bar(s, 12, 46, 144, A.res, 100, C_BLUEGRAY);
    const char *boss = jstr(A.def, "boss_name") ? jstr(A.def, "boss_name") : "";
    label(s, SCREEN_W - 12 - font_width(ui_bold(), boss, -1), 6, boss);
    if (K.repair) repair_hud(s);
    else bar(s, SCREEN_W - 156, 32, 144, A.bhp, K.boss_hp, C_TERRA);
    if (A.bark_t > 0 && A.bark) { /* pistas: top strip of up to two lines, above the boss and its warnings */
        const font *f = ui_font();
        char line[160];
        snprintf(line, sizeof line, "%s: %s", A.bark_spk ? A.bark_spk : "", A.bark);
        uint16_t ls[2], ll[2];
        int n = text_wrap(f, line, BARK_W, ls, ll, 2), w = 0; /* the width the validator checks */
        for (int i = 0; i < n; i++) {
            int lw = font_width(f, line + ls[i], ll[i]);
            w = lw > w ? lw : w;
        }
        int x = (SCREEN_W - w - 24) / 2;
        gfx_plate(s, x, 62, w + 24, n * (f->h + 2) + 8, C_INK);
        for (int i = 0; i < n; i++) font_draw(s, f, x + 12, 67 + i * (f->h + 2), line + ls[i], ll[i], -1, C_PAPER);
    }
    if (A.goals) { /* simulation checklist, under the bars */
        const font *b = ui_bold();
        int x = 12;
        for (int i = 0; i < NGOALS; i++) {
            if (!(A.goals & (1u << i))) continue;
            const char *t = jas(jget(A.def, "goal_labels"), i) ? jas(jget(A.def, "goal_labels"), i) : GOAL_KEY[i];
            int w = font_width(b, t, -1) + 20;
            bool ok = A.done & (1u << i);
            gfx_plate(s, x, SCREEN_H - 44, w, b->h + 8, ok ? C_OCHRE : C_INK);
            font_draw(s, b, x + 10, SCREEN_H - 40, t, -1, -1, ok ? C_INK : C_PAPER);
            x += w + 6;
        }
    }
    if (A.hint_t > 0) prompt(s, jstr(A.def, "unguardable_hint"), SCREEN_H - 112);
    if (A.bs == B_INTERLUDE) { /* Pau cutting the power: how much is left */
        const char *t = jstr(jget(jget(A.def, "boss"), "interlude"), "label") ? jstr(jget(jget(A.def, "boss"), "interlude"), "label") : "Alimentación";
        int total = jint(jget(jget(A.def, "boss"), "interlude"), "ticks", 360);
        bar(s, SCREEN_W - 156, 46, 144, A.bt, total, C_BLUEGRAY); /* under the boss's bar, clear of the hints */
        label(s, SCREEN_W - 164 - font_width(ui_bold(), t, -1), 42, t);
    }
    if (A.ps == P_CANTO && !releasing()) draw_canto(s);
    else if (A.bs == B_EXPOSED && A.ps == P_FREE)
        prompt(s, A.goals || A.res < 100 ? "A · Respirar" : "Arriba · Canto", SCREEN_H - (A.goals ? 112 : 60));
    if (A.menu) draw_menu(s);
}

static void scene(surface *s) { /* the fight without its HUD: into the world, or (HD) onto a strip */
    draw_tell(s);
    draw_spit(s);
    draw_boss(s);
    draw_player(s);
    draw_fx(s);
    if (A.ps == P_CANTO) draw_release(s);
}

/* The camera, once a frame: between the fighters, closer the closer they are, eased; never past the arena's edges. */
static void camera_update(void) {
    float gap = fabsf(A.bx - A.px), want = WORLD_W / (gap + K.boss_half + K.half + 48);
    want = want < 1 ? 1 : want > ZOOM_MAX ? ZOOM_MAX : want;
    R.z = R.z < 1 ? want : R.z + (want - R.z) * 0.08f;
    float half = SCREEN_W / (4 * R.z), mid = (A.px + A.bx) / 2; /* half the view, in world pixels */
    R.cx = mid < half ? half : mid > WORLD_W - half ? WORLD_W - half : mid;
    R.covers = sx_(0) <= 0 && sx_(WORLD_W) >= SCREEN_W && sy_(0) <= 0 && sy_(WORLD_H) >= SCREEN_H;
}

void arena_render_world(surface *world) {
    char hd[40];
    snprintf(hd, sizeof hd, "%s_HD", jstr(A.def, "bg") ? jstr(A.def, "bg") : "");
    R.bg = gfx_asset_opt(hd);
    bool was = R.hd;
    R.hd = !R.bg->missing;
    if (R.hd && !was) { /* every picture of both fighters, now: loaded on first use they would stall a strip */
        char sb[32];
        static const char *const POSES[] = {"IDLE", "WALK", "GUARD", "IMPACT", "ATTACK", "DODGE", "KNEEL", "CANTO",
                                            "HURT", "EXPOSED", "CHARGE", "BITE", "SLAM", "FREE", "SHIELD", "SWEEP",
                                            "PULSE", "STABLE", "OPEN"};
        if (jstr(jget(A.def, "intro_spit"), "sprite")) gfx_asset(jstr(jget(A.def, "intro_spit"), "sprite"));
        for (int who = 0; who < 2; who++)
            for (size_t i = 0; i < sizeof POSES / sizeof *POSES; i++) { /* the world's too: they say which poses
                                                                         * there are and how many frames each has */
                gfx_asset_opt(sprite_id(sb, who, POSES[i]));
                snprintf(hd, sizeof hd, "%s_HD", sb);
                gfx_asset_opt(hd);
            }
    }
    if (R.hd) { /* drawn on the strips (arena_render_screen); here only what must be worked out once */
        camera_update();
        return;
    }
    R.z = 0;
    asset *bg = gfx_asset(jstr(A.def, "bg"));
    if (bg->missing) gfx_fill(world, 0, 0, WORLD_W, WORLD_H, C_INK);
    else gfx_blit(world, bg, 0, 0, 0, 0, false);
    scene(world);
}

/* Half of the window's columns (part 0 the left, 1 the right): the HD background and the fight, on one core each.
 * Both only read the fight's state and the pictures (all loaded before the strips), and write their own pixels. */
static surface half_of(const surface *scr, int part) {
    int w0 = scr->w / 2;
    surface half = gfx_clip(scr, scr->x0 + (part ? w0 : 0), scr->y0, part ? scr->w - w0 : w0, scr->h);
    half.part = (uint8_t)part;
    return half;
}

static void hd_half(int part, void *ctx) {
    surface half = half_of(ctx, part);
    if (half.w <= 0 || half.h <= 0) return;
    float k = 2 * R.z / HD_K;
    if (!R.covers) gfx_fill(&half, 0, 0, SCREEN_W, SCREEN_H, C_INK);
    gfx_blit_ex(&half, R.bg, 0, sx_(0), sy_(0), k, k, 0, NULL, -1);
    scene(&half);
}

static void dim_half(int part, void *ctx) {
    surface half = half_of(ctx, part);
    for (int k = 0; k < R.dim; k++) gfx_shade(&half, 0, 0, SCREEN_W, SCREEN_H);
}

void arena_render_screen(surface *world, surface *scr) {
    if (R.hd) {
        gfx_light_warm(A.ps == P_CANTO ? (releasing() ? 3 : A.canto_i) : 0);
        hal_parallel(hd_half, scr); /* (the HUD after, on one core: the UI's code is not made for two) */
        gfx_light_warm(0);
    }
    else gfx_upscale2x(world, scr);
    draw_hud(scr);
    int f = A.fade ? A.fade - (end_ticks() - 60) : A.ps == P_KNEEL ? A.pt * 2 / 3 : 0; /* to black; defeat: dim */
    R.dim = f > 40 ? 3 : f > 20 ? 2 : f > 0 ? 1 : 0;
    if (R.dim) hal_parallel(dim_half, scr);
}

/* ------------------------------------------------------------------ scripts and debugging */
const char *arena_state(const char *who) {
    if (!A.def) return "none";
    return !strcmp(who, "boss") ? BNAME[A.bs] : PNAME[A.ps];
}

bool arena_value(const char *field, int *out) {
    if (!A.def) return false;
    if (!strcmp(field, "player_hp")) *out = A.hp;
    else if (!strcmp(field, "boss_hp")) *out = A.bhp;
    else if (!strcmp(field, "resonance")) *out = A.res;
    else if (!strcmp(field, "phase")) *out = A.phase;
    else if (!strcmp(field, "gap")) *out = (int)(gap() + 0.5f);
    else if (!strcmp(field, "goals_left")) *out = __builtin_popcount(A.goals & ~A.done);
    else if (!strcmp(field, "max_hp")) *out = K.hp; /* after the Protector / Ágil mods */
    else if (!strcmp(field, "dodge_recover")) *out = K.dodge_recover;
    else if (!strcmp(field, "hint")) *out = A.hint_t > 0; /* the unguardable hint is on screen */
    else if (!strcmp(field, "pattern")) *out = A.pat; /* 0 charge 1 bite 2 slam 3 shield 4 sweep 5 pulse 6 marks */
    else if (!strcmp(field, "sector")) *out = sector_of(A.px);
    else if (!strcmp(field, "progress")) *out = A.progress; /* repair mode: segments closed */
    else if (!strcmp(field, "bark")) *out = A.bark_t > 0 ? A.bark_slot + 1 : 0; /* 1 charge, 2 bite, 3 slam, 4 phase 2 */
    else return false;
    return true;
}

bool arena_poke(const char *field, int v) {
    if (!A.def) return false;
    if (!strcmp(field, "boss_hp")) A.bhp = v;
    else if (!strcmp(field, "resonance")) A.res = v;
    else if (!strcmp(field, "player_hp")) A.hp = v;
    else return false;
    return true;
}
