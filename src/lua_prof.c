/* perf("lua"): where a game's Lua time goes, by function. While it is on, a count hook stops the VM every
 * PROF_EVERY instructions and charges the microseconds since the last stop to the stack it finds there: the time
 * of a C call (mset, a path, a drawing call) lands on the Lua function that made it. Each function gets its own
 * time (it was on top) and its total (it was anywhere on the stack); each distinct stack is kept too, for a flame
 * graph (prof_folded, "a;b;c us" lines as FlameGraph and speedscope.app read). The tables are fixed: no allocation
 * inside the hook, and what does not fit is counted as "(other)". Off, it costs nothing (arm() sets no hook). */
#include <stdio.h>
#include <stdlib.h>
#include <string.h>

#include "hal.h"
#include "lua_prof.h"

#define PROF_EVERY 1000 /* instructions between samples: ~10 us of Lua on the console */
#define PROF_FNS 128
#define PROF_STACKS 512
#define PROF_DEPTH 24

typedef struct {
    const void *src; /* a Lua function: its source string (interned, stable while the game runs) and first line */
    int line;
    char name[56];
    uint64_t self_us, total_us;
    uint32_t mark; /* the sample that last counted it in total_us, so recursion counts once */
} fn_t;

typedef struct {
    uint32_t hash;
    uint8_t depth;
    uint8_t ids[PROF_DEPTH]; /* root first */
    uint64_t us;
} stack_t_;

static struct {
    bool on;
    const char *entry; /* the engine's call this sample is under (_update, _draw): the name its function lacks */
    uint32_t last, samples;
    uint64_t us;
    int nfns;
    fn_t fns[PROF_FNS];
    stack_t_ *stacks; /* PROF_STACKS of them, allocated while on */
} P;

static int fn_id(lua_State *L, lua_Debug *ar, bool root) {
    lua_getinfo(L, "Sn", ar);
    const bool is_c = ar->what[0] == 'C';
    const void *src = is_c ? NULL : (const void *)ar->source; /* C functions go by name */
    const int line = ar->linedefined;
    char name[56];
    if (!ar->name && root && P.entry) ar->name = P.entry;
    if (is_c) snprintf(name, sizeof name, "%s [C]", ar->name ? ar->name : "?");
    else if (ar->what[0] == 'm') snprintf(name, sizeof name, "main chunk (%s)", ar->short_src);
    else snprintf(name, sizeof name, "%s (%s:%d)", ar->name ? ar->name : "function", ar->short_src, line);
    for (int i = 0; i < P.nfns; i++) {
        fn_t *f = &P.fns[i];
        if (f->src == src && f->line == line && (!is_c || !strcmp(f->name, name))) return i;
    }
    if (P.nfns == PROF_FNS) return PROF_FNS - 1; /* the last one is (other) */
    fn_t *f = &P.fns[P.nfns];
    memset(f, 0, sizeof *f);
    f->src = src, f->line = line;
    snprintf(f->name, sizeof f->name, "%s", P.nfns == PROF_FNS - 1 ? "(other)" : name);
    return P.nfns++;
}

static void add_stack(const uint8_t *ids, int depth, uint32_t us) {
    if (!P.stacks) return;
    uint32_t h = 2166136261u;
    for (int i = 0; i < depth; i++) h = (h ^ ids[i]) * 16777619u;
    h ^= (uint32_t)depth;
    for (int k = 0; k < PROF_STACKS; k++) {
        stack_t_ *s = &P.stacks[(h + (uint32_t)k) % PROF_STACKS];
        if (s->depth == 0) {
            s->hash = h, s->depth = (uint8_t)depth;
            memcpy(s->ids, ids, (size_t)depth);
        } else if (s->hash != h || s->depth != depth || memcmp(s->ids, ids, (size_t)depth)) {
            continue;
        }
        s->us += us;
        return;
    }
}

static void sample(lua_State *L, lua_Debug *unused) {
    (void)unused;
    const uint32_t now = hal_micros(), us = now - P.last;
    P.last = now;
    P.samples++, P.us += us;
    uint8_t leaf_first[PROF_DEPTH];
    int depth = 0;
    lua_Debug ar;
    for (int lv = 0; depth < PROF_DEPTH && lua_getstack(L, lv, &ar); lv++)
        leaf_first[depth++] = (uint8_t)fn_id(L, &ar, !lua_getstack(L, lv + 1, &(lua_Debug){0}));
    if (!depth) return;
    P.fns[leaf_first[0]].self_us += us;
    uint8_t root_first[PROF_DEPTH];
    for (int i = 0; i < depth; i++) {
        fn_t *f = &P.fns[leaf_first[i]];
        if (f->mark != P.samples) f->mark = P.samples, f->total_us += us;
        root_first[depth - 1 - i] = leaf_first[i];
    }
    add_stack(root_first, depth, us);
}

void prof_start(void) {
    if (P.on) return;
    memset(&P, 0, sizeof P);
    P.stacks = calloc(PROF_STACKS, sizeof *P.stacks); /* ~20 KB; without it, functions only */
    P.on = true;
}

void prof_stop(void) {
    free(P.stacks);
    memset(&P, 0, sizeof P);
}

bool prof_on(void) { return P.on; }

void prof_new_state(void) { /* the game's Lua state closed: its source strings may come back at the same addresses */
    for (int i = 0; i < P.nfns; i++)
        if (P.fns[i].src) P.fns[i].src = &P; /* never a source: its counts stay, new functions get new entries */
}

void prof_arm(lua_State *L, const char *entry) {
    P.entry = entry;
    P.last = hal_micros(); /* time outside Lua (the engine between calls) is nobody's */
    /* the hook is set once: its count of instructions runs on across the calls, so a tick shorter than PROF_EVERY
     * instructions is sampled too, now and then (setting it again each call would start the count over, and a light
     * game would never be seen) */
    if (!P.on) lua_sethook(L, NULL, 0, 0); /* (and the sandbox's "over" hook, if the last call spent its budget, goes) */
    else if (lua_gethook(L) != sample) lua_sethook(L, sample, LUA_MASKCOUNT, PROF_EVERY);
}

static int by_self(const void *a, const void *b) {
    const prof_row *x = a, *y = b;
    return x->self_ms < y->self_ms ? 1 : x->self_ms > y->self_ms ? -1 : 0;
}

int prof_rows(prof_row *rows, int max, float *total_ms) {
    prof_row all[PROF_FNS];
    for (int i = 0; i < P.nfns; i++) all[i] = (prof_row){P.fns[i].name, P.fns[i].self_us / 1000.0f, P.fns[i].total_us / 1000.0f};
    qsort(all, (size_t)P.nfns, sizeof *all, by_self);
    const int n = P.nfns < max ? P.nfns : max;
    memcpy(rows, all, (size_t)n * sizeof *rows);
    if (total_ms) *total_ms = P.us / 1000.0f;
    return n;
}

int prof_folded(FILE *f) {
    if (!P.stacks) return 0;
    int lines = 0;
    for (int k = 0; k < PROF_STACKS; k++) {
        const stack_t_ *s = &P.stacks[k];
        if (!s->depth) continue;
        for (int i = 0; i < s->depth; i++) {
            for (const char *c = P.fns[s->ids[i]].name; *c; c++) fputc(*c == ';' ? ',' : *c, f);
            fputc(i + 1 < s->depth ? ';' : ' ', f);
        }
        fprintf(f, "%llu\n", (unsigned long long)s->us);
        lines++;
    }
    return lines;
}
