/* Content loading (JSON files under the game folder) and the reference validator. */
#include <dirent.h>
#include <limits.h>
#include <stdlib.h>
#include <string.h>
#include <strings.h>
#include <sys/stat.h>

#include "bp.h"

/* fread in 8 KB pieces: on the console the card is shared with the sound mixer, which streams from it, and one
 * long read would make it wait past its buffer (crackles while a zone loads). Each piece through a buffer of internal
 * memory (static: the console keeps .bss there): read straight into PSRAM, the card's driver goes a 512-byte sector
 * per command, ~0.5 MB/s (a 48 KB portrait took 100 ms). Same result as one fread. (The game's task only.) */
size_t fread_chunked(void *dst, size_t n, FILE *f) {
    static uint8_t piece[8192] __attribute__((aligned(64)));
    size_t got = 0;
    while (got < n) {
        size_t want = n - got < sizeof piece ? n - got : sizeof piece, r = fread(piece, 1, want, f);
        memcpy((char *)dst + got, piece, r);
        got += r;
        if (r < want) break;
    }
    return got;
}

/* The game's folders listed once each (content_free forgets them): on the console's card, opening a file walks its
 * whole folder a sector per command, and one that is not there costs the most (a picture without a mask, a pose a
 * sprite may leave out, a sound's next variant: tens of milliseconds each). Those are answered from here. */
#define LISTED 4
static struct { char path[320]; char **names; int n; } listed[LISTED]; /* no names: not listed, every file is tried */
static int nlisted;

static int by_name(const void *a, const void *b) { return strcasecmp(*(char *const *)a, *(char *const *)b); }

static void list_folder(int i, const char *path) {
    snprintf(listed[i].path, sizeof listed[i].path, "%s", path);
    DIR *d = opendir(path);
    for (struct dirent *e; d && (e = readdir(d));) {
        char **more = listed[i].n % 256 ? listed[i].names : realloc(listed[i].names, (listed[i].n + 256) * sizeof(char *));
        char *copy = more ? strdup(e->d_name) : NULL;
        if (more) listed[i].names = more;
        if (copy) listed[i].names[listed[i].n++] = copy;
    }
    if (d) closedir(d);
    if (listed[i].n) qsort(listed[i].names, (size_t)listed[i].n, sizeof(char *), by_name);
}

bool game_has(const char *rel) {
    const char *slash = strrchr(rel, '/'), *name = slash ? slash + 1 : rel;
    char path[320];
    if (!slash || snprintf(path, sizeof path, "%s/%.*s", G.game_dir, (int)(slash - rel), rel) >= (int)sizeof path) return true;
    int i = 0;
    while (i < nlisted && strcmp(listed[i].path, path)) i++; /* (by the whole path: tools move G.game_dir) */
    if (i == nlisted) {
        if (nlisted == LISTED) return true;
        list_folder(nlisted++, path);
    }
    return !listed[i].n || bsearch(&name, listed[i].names, (size_t)listed[i].n, sizeof(char *), by_name);
}

char *read_file(const char *path, long *len) {
    struct stat st; /* only a file: Linux opens a folder too, and its "length" is LONG_MAX */
    if (stat(path, &st) || !S_ISREG(st.st_mode)) return NULL;
    FILE *f = fopen(path, "rb");
    if (!f) return NULL;
    long n = fseek(f, 0, SEEK_END) ? -1 : ftell(f);
    fseek(f, 0, SEEK_SET);
    char *d = n >= 0 && n < LONG_MAX ? malloc((size_t)n + 1) : NULL;
    if (d && fread_chunked(d, (size_t)n, f) != (size_t)n) {
        free(d);
        d = NULL;
    }
    fclose(f);
    if (!d) return NULL;
    d[n] = 0;
    if (len) *len = n;
    return d;
}

cJSON *json_file(const char *rel) {
    char path[384];
    snprintf(path, sizeof path, "%s/%s", G.game_dir, rel);
    char *txt = read_file(path, NULL);
    if (!txt) return NULL;
    cJSON *j = cJSON_Parse(txt);
    if (!j) hal_log("%s: JSON error near: %.40s", rel, cJSON_GetErrorPtr() ? cJSON_GetErrorPtr() : "?");
    free(txt);
    return j;
}

cJSON *jget(const cJSON *o, const char *key) { return o ? cJSON_GetObjectItemCaseSensitive(o, key) : NULL; }

const char *jstr(const cJSON *o, const char *key) {
    cJSON *v = jget(o, key);
    return cJSON_IsString(v) ? v->valuestring : NULL;
}

int jint(const cJSON *o, const char *key, int dflt) {
    cJSON *v = jget(o, key);
    return cJSON_IsNumber(v) ? v->valueint : dflt;
}

int jai(const cJSON *arr, int i, int dflt) {
    const cJSON *v = cJSON_GetArrayItem(arr, i);
    return cJSON_IsNumber(v) ? v->valueint : dflt;
}

const char *jas(const cJSON *arr, int i) {
    const cJSON *v = cJSON_GetArrayItem(arr, i);
    return cJSON_IsString(v) ? v->valuestring : NULL;
}

void content_free(void) {
    for (int i = 0; i < nlisted; i++) {
        for (int k = 0; k < listed[i].n; k++) free(listed[i].names[k]);
        free(listed[i].names);
        listed[i] = (typeof(listed[i])){0};
    }
    nlisted = 0;
    cJSON **all[] = {&G.game, &G.tiles, &G.items, &G.events, &G.notebook, &G.sequences, &G.listens, &G.puzzles,
                     &G.music, &G.dialogues, &G.zones};
    for (size_t i = 0; i < sizeof all / sizeof all[0]; i++) {
        cJSON_Delete(*all[i]);
        *all[i] = NULL;
    }
}

/* game.json "theme" (UI colours, corners) and "player", with their defaults. */
static void content_theme(void) {
    ui_theme *t = &G.th;
    const cJSON *th = jget(G.game, "theme");
    t->ink = hex565(jstr(th, "ink"), D_INK);
    t->ochre = hex565(jstr(th, "ochre"), D_OCHRE);
    t->terra = hex565(jstr(th, "terra"), D_TERRA);
    t->paper = hex565(jstr(th, "paper"), D_PAPER);
    t->paper_sel = hex565(jstr(th, "paper_sel"), D_PAPER_SEL);
    t->dim = hex565(jstr(th, "dim"), D_DIM);
    t->brown = hex565(jstr(th, "brown"), D_BROWN);
    t->cut = jstr(th, "corners") && !strcmp(jstr(th, "corners"), "cut");
    player_ids *p = &G.pl;
    const cJSON *pl = jget(G.game, "player");
    p->bag_option = !pl || cJSON_IsTrue(jget(pl, "bag_option"));
    char tag[8];
    const char *sprite = jstr(pl, "sprite"), *speaker = jstr(pl, "speaker");
    snprintf(tag, sizeof tag, "%s", sprite ? sprite : "KL");
    snprintf(p->speaker, sizeof p->speaker, "%s", speaker ? speaker : "KLAUS");
    const char *pt = jstr(jget(jget(G.game, "speakers"), p->speaker), "portrait");
    snprintf(p->portrait, sizeof p->portrait, "%s", pt ? pt : "PT_KLAUS");
    snprintf(p->prefix, sizeof p->prefix, "%s_", tag);
    snprintf(p->idle, sizeof p->idle, "%s_IDLE", tag);
    snprintf(p->walk, sizeof p->walk, "%s_WALK", tag);
    snprintf(p->interact, sizeof p->interact, "%s_INTERACT", tag);
    snprintf(p->listen, sizeof p->listen, "%s_LISTEN", tag);
    snprintf(p->descend, sizeof p->descend, "%s_DESCEND", tag);
}

bool content_load(void) {
    content_free();
    G.game = json_file("game.json");
    const char *engine = jstr(G.game, "engine");
    /* "np2d" is the engine's first name: games that still say "np2d@2" run as before */
    G.v2 = engine && (!strncmp(engine, "pinyol@2", 8) || !strncmp(engine, "np2d@2", 6));
    if (G.v2) { /* a Lua game: none of the v1 content files */
        cJSON **rest[] = {&G.tiles, &G.items, &G.events, &G.notebook, &G.sequences, &G.listens, &G.puzzles, &G.music};
        for (size_t i = 0; i < sizeof rest / sizeof rest[0]; i++) *rest[i] = cJSON_CreateObject();
        G.dialogues = cJSON_CreateObject();
        G.zones = cJSON_CreateObject();
        content_theme();
        return true;
    }
    cJSON_Delete(G.game);
    G.game = NULL;
    struct { cJSON **dst; const char *file; } files[] = {
        {&G.game, "game.json"},         {&G.tiles, "tiles.json"},         {&G.items, "items.json"},
        {&G.events, "events.json"},     {&G.notebook, "notebook.json"},   {&G.sequences, "sequences.json"},
        {&G.listens, "listen.json"},    {&G.puzzles, "puzzles.json"},     {&G.music, "music.json"},
    };
    bool ok = true;
    for (size_t i = 0; i < sizeof files / sizeof files[0]; i++) {
        *files[i].dst = json_file(files[i].file);
        if (!*files[i].dst) {
            hal_log("required content missing or invalid: %s", files[i].file);
            *files[i].dst = cJSON_CreateObject();
            ok = false;
        }
    }
    G.dialogues = cJSON_CreateObject();
    G.zones = cJSON_CreateObject();
    content_theme();
    return ok;
}

/* A game without items has no bag (MENU pauses instead); one without notebook content has no notebook. */
bool content_has_bag(void) { /* only once something is in it: a game can start without one */
    const cJSON *it;
    cJSON_ArrayForEach(it, G.items) if (flagf_get("item:%s%s", it->string, "")) return true;
    return false;
}

const char *content_bag_label(void) { return jstr(G.game, "bag_label") ? jstr(G.game, "bag_label") : "Bolsa"; }
bool content_has_notes(void) { return cJSON_GetArraySize(G.notebook) > 0; }

static cJSON *cached(cJSON *cache, const char *dir, const char *id) {
    if (!id || !*id) return NULL;
    cJSON *c = jget(cache, id);
    if (c) return cJSON_IsNull(c) ? NULL : c;
    char rel[96];
    snprintf(rel, sizeof rel, "%s/%s.json", dir, id);
    c = json_file(rel);
    cJSON_AddItemToObject(cache, id, c ? c : cJSON_CreateNull());
    return c;
}

cJSON *content_zone(const char *id) {
    if (!strcmp(id, G.missing_zone)) return NULL;
    return cached(G.zones, "zones", id);
}

cJSON *content_dialogue(const char *id) { return cached(G.dialogues, "dialogues", id); }

/* ------------------------------------------------------------------ validator */
static int errors;
static cJSON *arenas; /* arena.json while validating: optional, only games with fights have it */
static char where[128];

static void err(const char *fmt, const char *a) {
    char msg[256];
    snprintf(msg, sizeof msg, fmt, a ? a : "(null)");
    hal_log("validate: %s: %s", where, msg);
    errors++;
}

static void check_text(const char *s) {
    if (!s) return;
    const char *p = s, *e = s + strlen(s);
    while (p < e)
        if (utf8_cp1252(&p, e) < 0) {
            err("text not encodable in cp1252: %s", s);
            return;
        }
}

/* Puzzle messages sit in a two-line panel with no paging: they must fit in normal and in large text. */
static void check_panel_text(const char *s) {
    check_text(s);
    uint16_t ls[8], ll[8];
    const font *fonts[] = {&G.font, &G.font_l};
    for (int i = 0; i < 2; i++)
        if (s && fonts[i]->bits && text_wrap(fonts[i], s, SCREEN_W - 64, ls, ll, 8) > 2) {
            err("needs more than 2 lines in the puzzle panel: %s", s);
            return;
        }
}

/* Arena texts sit on one line over the fight: they must fit in normal and in large text. */
static void check_arena_line(const char *s, bool bold, int pad) {
    check_text(s);
    const font *fonts[] = {bold ? &G.bold : &G.font, bold ? &G.bold_l : &G.font_l};
    for (int i = 0; i < 2; i++)
        if (s && fonts[i]->bits && font_width(fonts[i], s, -1) + pad > SCREEN_W - 8) {
            err("does not fit on one line over the arena: %s", s);
            return;
        }
}

static bool split_ref(const char *ref, char *file, size_t fn, const char **node) {
    const char *dot = strchr(ref, '.');
    size_t n = dot ? (size_t)(dot - ref) : strlen(ref);
    if (n >= fn) return false;
    memcpy(file, ref, n);
    file[n] = 0;
    *node = dot ? dot + 1 : NULL;
    return true;
}

static bool has_choice(const cJSON *dlg, const char *id) {
    const cJSON *node;
    cJSON_ArrayForEach(node, jget(dlg, "nodes")) {
        const cJSON *c;
        cJSON_ArrayForEach(c, jget(node, "choices")) {
            const char *cid = jstr(c, "id");
            if (cid && !strcmp(cid, id)) return true;
        }
    }
    return false;
}

static void check_dlg_ref(const char *ref) {
    if (!ref) return err("missing dialogue reference%s", "");
    if (ref[0] == '@') return check_text(ref + 1);
    char file[48];
    const char *node;
    if (!split_ref(ref, file, sizeof file, &node)) return err("bad dialogue ref %s", ref);
    cJSON *d = content_dialogue(file);
    if (!d) return err("unknown dialogue %s", ref);
    if (node && !jget(jget(d, "nodes"), node)) err("unknown dialogue node %s", ref);
    if (!node && !jget(d, "entry")) err("dialogue %s has no entry", ref);
}

static bool list_has(const cJSON *arr, const char *s) {
    const cJSON *v;
    cJSON_ArrayForEach(v, arr) if (cJSON_IsString(v) && !strcmp(v->valuestring, s)) return true;
    return false;
}

static void check_flag(const char *name) {
    if (name[0] == '!') name++;
    const char *colon = strchr(name, ':');
    if (!colon) {
        if (!list_has(jget(G.game, "flags"), name) && !jget(jget(G.game, "enums"), name)) err("undeclared flag %s", name);
        return;
    }
    const char *v = colon + 1;
    if (!strncmp(name, "item:", 5)) { if (!jget(G.items, v)) err("unknown item in %s", name); }
    else if (!strncmp(name, "note:", 5)) { if (!jget(jget(G.notebook, "entries"), v)) err("unknown note in %s", name); }
    else if (!strncmp(name, "visited:", 8)) { if (!list_has(jget(G.game, "zones"), v)) err("unknown zone in %s", name); }
    else if (!strncmp(name, "seen:", 5)) check_dlg_ref(v);
    else if (!strncmp(name, "topic:", 6)) {
        char file[48];
        const char *c;
        cJSON *d = split_ref(v, file, sizeof file, &c) ? content_dialogue(file) : NULL;
        if (!d || !c || !has_choice(d, c)) err("unknown topic %s", name);
    } else err("unknown flag prefix %s", name);
}

static void check_cond(const cJSON *c);

static void check_enum(const char *flag, const cJSON *val) {
    if (cJSON_IsString(val) && enum_index(flag, val) < 0) err("bad enum value for %s", flag);
}

static void check_cond(const cJSON *c) {
    if (!c) return;
    if (cJSON_IsString(c)) return check_flag(c->valuestring);
    if (!cJSON_IsArray(c)) return err("condition must be string or array%s", "");
    const cJSON *op = cJSON_GetArrayItem(c, 0);
    const char *o = cJSON_IsString(op) ? op->valuestring : "";
    const cJSON *a1 = cJSON_GetArrayItem(c, 1), *a2 = cJSON_GetArrayItem(c, 2);
    if (!strcmp(o, "eq") || !strcmp(o, "ge")) {
        if (!cJSON_IsString(a1)) return err("%s needs a flag", o);
        check_flag(a1->valuestring);
        check_enum(a1->valuestring, a2);
    } else if (!strcmp(o, "has") || !strcmp(o, "using")) {
        if (!cJSON_IsString(a1) || !jget(G.items, a1->valuestring)) err("unknown item in %s", o);
    } else if (!strcmp(o, "seen") || !strcmp(o, "topic") || !strcmp(o, "visited")) {
        char k[96];
        snprintf(k, sizeof k, "%s:%s", o, cJSON_IsString(a1) ? a1->valuestring : "?");
        check_flag(k);
    } else if (!strcmp(o, "open")) {
        if (!cJSON_IsString(a1) || !jget(G.puzzles, a1->valuestring)) err("open needs a puzzle id%s", "");
    } else if (!strcmp(o, "and") || !strcmp(o, "or") || !strcmp(o, "not")) {
        for (const cJSON *x = a1; x; x = x->next) check_cond(x);
    } else { /* plain list = AND */
        const cJSON *x;
        cJSON_ArrayForEach(x, c) check_cond(x);
    }
}

static void check_effects(const cJSON *list);

/* Every referenced sound must exist in the runtime format: the audio pipeline is part of the build.
 * Returns the WAV's channel count (music cues: one channel per layer), 0 if unusable. */
static int audio_chans(const char *id) {
    if (!id || !*id) return err("missing audio id%s", ""), 0;
    if (strlen(id) >= 32) return err("audio id %s is longer than 31 characters", id), 0;
    char path[384];
    snprintf(path, sizeof path, "%s/audio/%s.wav", G.game_dir, id);
    FILE *f = fopen(path, "rb");
    long start, len;
    int chans = 0;
    if (!f || !wav_parse(f, &start, &len, &chans)) err("audio %s missing or not PCM16 at AUDIO_HZ", id), chans = 0;
    if (f) fclose(f);
    return chans;
}

static void check_audio(const char *id) {
    if (audio_chans(id) > 1) err("audio %s must be mono", id);
}

static void check_cue(const char *id) {
    const cJSON *def = jget(jget(G.music, "cues"), id ? id : ""), *row;
    if (!def) return err("unknown music cue %s (define it in music.json cues)", id);
    int chans = audio_chans(id);
    if (!chans) return;
    if (cJSON_GetArraySize(jget(def, "layers")) != 4) err("cue %s needs 4 layers rows (tension 0..3)", id);
    cJSON_ArrayForEach(row, jget(def, "layers")) if (cJSON_GetArraySize(row) != chans)
        err("cue %s: every layers row needs one gain per WAV channel", id);
}

static void check_music(void) {
    snprintf(where, sizeof where, "music.json");
    const cJSON *x, *r;
    check_cue(jstr(jget(G.music, "title"), "cue"));
    check_cue(jstr(jget(G.music, "end"), "cue"));
    cJSON_ArrayForEach(x, jget(G.music, "cues")) check_cue(x->string);
    cJSON_ArrayForEach(x, jget(G.music, "zones")) {
        if (!list_has(jget(G.game, "zones"), x->string)) err("unknown zone %s", x->string);
        if (cJSON_IsString(x)) check_cue(x->valuestring);
        cJSON_ArrayForEach(r, x) if (cJSON_IsObject(r)) { check_cond(jget(r, "if")); check_cue(jstr(r, "cue")); }
    }
    cJSON_ArrayForEach(r, jget(G.music, "tension")) check_cond(jget(r, "if"));
    const cJSON *rest = jget(G.music, "rest");
    if (rest && (jint(rest, "after_s", 0) < 10 || jint(rest, "for_s", 0) < 1)) err("rest needs after_s >= 10 and for_s >= 1%s", "");
    cJSON_ArrayForEach(x, jget(G.music, "sfx")) check_audio(cJSON_IsString(x) ? x->valuestring : jas(x, 0));
    cJSON_ArrayForEach(x, jget(G.music, "events")) {
        if (!list_has(jget(G.game, "zones"), x->string)) err("unknown zone %s", x->string);
        cJSON_ArrayForEach(r, x) {
            check_audio(jstr(r, "id"));
            check_cond(jget(r, "if"));
            if (cJSON_GetArraySize(jget(r, "every")) != 2 || jai(jget(r, "every"), 0, 0) < 1 ||
                jai(jget(r, "every"), 1, 0) < jai(jget(r, "every"), 0, 0))
                err("event %s needs every: [min_s >= 1, max_s >= min_s]", jstr(r, "id"));
        }
    }
}

static void check_effect(const cJSON *e) {
    const cJSON *op = cJSON_GetArrayItem(e, 0), *a1 = cJSON_GetArrayItem(e, 1), *a2 = cJSON_GetArrayItem(e, 2);
    if (!cJSON_IsString(op)) return err("effect must start with a string%s", "");
    const char *o = op->valuestring, *s1 = cJSON_IsString(a1) ? a1->valuestring : NULL;
    if (!strcmp(o, "set") || !strcmp(o, "clear")) {
        if (!s1) return err("%s needs a flag", o);
        check_flag(s1);
        check_enum(s1, a2);
    } else if (!strcmp(o, "give") || !strcmp(o, "take")) {
        if (!s1 || !jget(G.items, s1)) err("unknown item in %s", o);
    } else if (!strcmp(o, "note")) { if (!s1 || !jget(jget(G.notebook, "entries"), s1)) err("unknown note %s", s1); }
    else if (!strcmp(o, "event")) { if (!s1 || !jget(G.events, s1)) err("unknown event %s", s1); }
    else if (!strcmp(o, "seq")) { if (!s1 || !jget(G.sequences, s1)) err("unknown sequence %s", s1); }
    else if (!strcmp(o, "listen")) { if (!s1 || !jget(G.listens, s1)) err("unknown listen point %s", s1); }
    else if (!strcmp(o, "puzzle")) { if (!s1 || !jget(G.puzzles, s1)) err("unknown puzzle %s", s1); }
    else if (!strcmp(o, "arena")) { if (!s1 || !jget(arenas, s1)) err("unknown arena %s", s1); }
    else if (!strcmp(o, "dlg")) check_dlg_ref(s1);
    else if (!strcmp(o, "say")) check_text(s1);
    else if (!strcmp(o, "zone")) { if (!s1 || !list_has(jget(G.game, "zones"), s1)) err("unknown zone %s", s1); }
    else if (!strcmp(o, "when")) { check_cond(a1); check_effects(a2); }
    else if (!strcmp(o, "sfx") || !strcmp(o, "voice")) check_audio(s1);
    else if (!strcmp(o, "music")) check_cue(s1);
    else if (!strcmp(o, "save") || !strcmp(o, "checkpoint") || !strcmp(o, "end") || !strcmp(o, "audio_fade")) {}
    else err("unknown effect %s", o);
}

static void check_effects(const cJSON *list) {
    const cJSON *e;
    cJSON_ArrayForEach(e, list) check_effect(e);
}

static void check_speaker(const char *spk) {
    char s[32];
    snprintf(s, sizeof s, "%s", spk);
    char *colon = strchr(s, ':');
    if (colon) *colon = 0;
    if (strcmp(s, "SUB") && !jget(jget(G.game, "speakers"), s)) err("unknown speaker %s", s); /* SUB: a sound subtitle */
}

static void check_line(const cJSON *l) {
    if (cJSON_IsArray(l)) {
        const cJSON *s = cJSON_GetArrayItem(l, 0), *t = cJSON_GetArrayItem(l, 1);
        if (!cJSON_IsString(s) || !cJSON_IsString(t)) return err("line must be [speaker, text]%s", "");
        check_speaker(s->valuestring);
        check_text(t->valuestring);
        return;
    }
    check_cond(jget(l, "if"));
    if (jstr(l, "sub")) return check_text(jstr(l, "sub"));
    if (!jstr(l, "s") || !jstr(l, "t")) return err("line object needs s and t (or sub)%s", "");
    check_speaker(jstr(l, "s"));
    check_text(jstr(l, "t"));
}

static void check_dialogue(const char *id) {
    snprintf(where, sizeof where, "dialogues/%s", id);
    cJSON *d = content_dialogue(id);
    if (!d) return err("cannot load %s", id);
    char ref[96];
    const cJSON *x;
    cJSON_ArrayForEach(x, jget(d, "entry")) {
        check_cond(jget(x, "if"));
        snprintf(ref, sizeof ref, "%s.%s", id, jstr(x, "node") ? jstr(x, "node") : "?");
        check_dlg_ref(ref);
    }
    cJSON_ArrayForEach(x, jget(d, "show")) {
        snprintf(ref, sizeof ref, "%s.%s", id, cJSON_IsString(x) ? x->valuestring : "?");
        check_dlg_ref(ref);
        if (strcmp(x->string, "*") && !jget(G.items, x->string)) err("show for unknown item %s", x->string);
    }
    const cJSON *node;
    cJSON_ArrayForEach(node, jget(d, "nodes")) {
        snprintf(where, sizeof where, "dialogues/%s.%s", id, node->string);
        const char *refs[] = {jstr(node, "next"), jstr(node, "repeat")};
        for (int i = 0; i < 2; i++)
            if (refs[i]) {
                snprintf(ref, sizeof ref, "%s.%s", id, refs[i]);
                check_dlg_ref(ref);
            }
        check_effects(jget(node, "do"));
        const cJSON *l;
        cJSON_ArrayForEach(l, jget(node, "lines")) check_line(l);
        const cJSON *c;
        cJSON_ArrayForEach(c, jget(node, "choices")) {
            check_text(jstr(c, "text"));
            check_cond(jget(c, "if"));
            check_effects(jget(c, "do"));
            if ((jget(c, "once") || jget(c, "repeat")) && !jstr(c, "id")) err("choice with once/repeat needs an id%s", "");
            const char *cr[] = {jstr(c, "next"), jstr(c, "repeat")};
            for (int i = 0; i < 2; i++)
                if (cr[i]) {
                    snprintf(ref, sizeof ref, "%s.%s", id, cr[i]);
                    check_dlg_ref(ref);
                }
        }
        if (!jget(node, "lines") && !jget(node, "choices") && !jget(node, "next") && !jget(node, "do"))
            err("empty node%s", "");
    }
}

static int tile_index(const char *name);

static void check_zone(const char *id) {
    snprintf(where, sizeof where, "zones/%s", id);
    cJSON *z = content_zone(id);
    if (!z) return err("cannot load zone %s", id);
    cJSON *size = jget(z, "size");
    int tw = cJSON_GetArrayItem(size, 0) ? cJSON_GetArrayItem(size, 0)->valueint : 0;
    int th = cJSON_GetArrayItem(size, 1) ? cJSON_GetArrayItem(size, 1)->valueint : 0;
    if (tw < 15 || th < 10 || tw > 255 || th > 255) err("zone %s size must be 15x10..255x255", id);
    if (!cJSON_IsArray(jget(jget(z, "spawns"), "safe"))) err("zone %s needs a safe spawn [x,y]", id);
    const cJSON *amb = jget(z, "ambient"), *rules = cJSON_IsArray(amb) ? amb : NULL, *r;
    if (cJSON_IsString(amb)) check_audio(amb->valuestring);
    cJSON_ArrayForEach(r, rules) { check_cond(jget(r, "if")); check_audio(jstr(r, "id")); }
    cJSON_ArrayForEach(r, jget(z, "blocks")) if (cJSON_IsObject(r)) {
        check_cond(jget(r, "if"));
        if (cJSON_GetArraySize(jget(r, "rect")) != 4) err("zone %s: conditional block needs rect [x,y,w,h]", id);
    }
    if (jstr(z, "steps")) check_audio(jstr(z, "steps"));
    const char *layers[] = {"floor", "wall_back", "front"};
    cJSON *legend = jget(G.tiles, "legend");
    for (int li = 0; li < 3; li++) {
        cJSON *grid = jget(z, layers[li]);
        if (!grid) {
            if (li == 0) err("zone %s has no floor", id);
            continue;
        }
        if (cJSON_GetArraySize(grid) != th) err("layer %s row count != height", layers[li]);
        const cJSON *row;
        cJSON_ArrayForEach(row, grid) {
            if (!cJSON_IsString(row)) { err("layer %s rows must be strings", layers[li]); continue; }
            if ((int)strlen(row->valuestring) != tw) err("row width != zone width: %s", row->valuestring);
            for (const char *p = row->valuestring; *p; p++) {
                char k[2] = {*p, 0};
                cJSON *t = jget(legend, k);
                if (!t) { err("char not in legend: %s", k); break; }
                if (cJSON_IsString(t) && tile_index(t->valuestring) < 0) err("unknown tile %s", t->valuestring);
            }
        }
    }
    const cJSON *x;
    cJSON_ArrayForEach(x, jget(z, "exits")) {
        const char *to = jstr(x, "to"), *sp = jstr(x, "spawn");
        check_cond(jget(x, "if"));
        check_effects(jget(x, "else"));
        if (!to || !list_has(jget(G.game, "zones"), to)) { err("exit to unknown zone %s", to); continue; }
        cJSON *tz = content_zone(to);
        if (tz && (!sp || !jget(jget(tz, "spawns"), sp))) err("exit to unknown spawn %s", sp);
        snprintf(where, sizeof where, "zones/%s", id);
    }
    const char *kinds[] = {"props", "npcs", "hotspots"};
    for (int k = 0; k < 3; k++) {
        cJSON_ArrayForEach(x, jget(z, kinds[k])) {
            if (!jstr(x, "id") || !cJSON_IsArray(jget(x, "at"))) err("%s entry needs id and at", kinds[k]);
            check_cond(jget(x, "if"));
            const cJSON *pair;
            cJSON_ArrayForEach(pair, jget(x, "at_if")) check_cond(cJSON_GetArrayItem(pair, 0));
            cJSON_ArrayForEach(pair, jget(x, "frame_if")) check_cond(cJSON_GetArrayItem(pair, 0));
            cJSON_ArrayForEach(pair, jget(x, "pose_if")) check_cond(cJSON_GetArrayItem(pair, 0));
            if (jstr(x, "dlg")) check_dlg_ref(jstr(x, "dlg"));
            check_effects(jget(x, "do"));
            const cJSON *u;
            cJSON_ArrayForEach(u, jget(x, "use")) {
                if (strcmp(u->string, "*") && !jget(G.items, u->string)) err("use of unknown item %s", u->string);
                check_dlg_ref(cJSON_IsString(u) ? u->valuestring : NULL);
            }
        }
    }
    cJSON_ArrayForEach(x, jget(z, "shade")) check_cond(cJSON_GetArrayItem(x, 0));
    check_effects(jget(z, "on_enter"));
}

static int tile_index(const char *name) {
    /* "TS_STONE_03" -> family start + 3 */
    const char *us = strrchr(name, '_');
    if (!us) return -1;
    char fam[32];
    snprintf(fam, sizeof fam, "%.*s", (int)(us - name), name);
    cJSON *r = jget(jget(G.tiles, "families"), fam);
    int idx = atoi(us + 1);
    if (idx < 0 || idx >= jai(r, 1, 0)) return -1;
    return jai(r, 0, 0) + idx;
}

int content_tile_index(const char *name) { return tile_index(name); }

static void check_arenas(void) {
    const cJSON *a, *x;
    cJSON_ArrayForEach(a, arenas) {
        snprintf(where, sizeof where, "arena.json %s", a->string);
        if (jstr(a, "intro")) check_dlg_ref(jstr(a, "intro"));
        if (jstr(a, "exposed")) check_dlg_ref(jstr(a, "exposed"));
        if (jstr(a, "intro_flag")) check_flag(jstr(a, "intro_flag"));
        if (jstr(a, "assist_flag")) check_flag(jstr(a, "assist_flag"));
        check_text(jstr(a, "boss_name"));
        check_effects(jget(a, "win"));
        check_effects(jget(a, "leave"));
        check_effects(jget(a, "practice_win"));
        if (jstr(a, "music")) check_cue(jstr(a, "music"));
        cJSON_ArrayForEach(x, jget(a, "sfx")) check_audio(cJSON_IsString(x) ? x->valuestring : NULL);
        cJSON_ArrayForEach(x, jget(a, "mods")) check_cond(jget(x, "if"));
        const cJSON *repair = jget(jget(a, "boss"), "repair");
        const cJSON *strips[] = {jget(a, "barks"), jget(a, "canto_barks"), jget(repair, "barks")};
        for (int k = 0; k < 3; k++) cJSON_ArrayForEach(x, strips[k]) { /* drawn as "Name: text" in one strip */
            check_speaker(jas(x, 0));
            const char *name = jstr(jget(jget(G.game, "speakers"), jas(x, 0) ? jas(x, 0) : ""), "name");
            char line[256];
            snprintf(line, sizeof line, "%s: %s", name ? name : "", jas(x, 1) ? jas(x, 1) : "");
            check_text(line);
            uint16_t ls[8], ll[8];
            const font *fonts[] = {&G.font, &G.font_l};
            for (int i = 0; i < 2; i++)
                if (fonts[i]->bits && text_wrap(fonts[i], line, SCREEN_W - 40, ls, ll, 8) > 2) {
                    err("hint needs more than 2 lines over the arena: %s", line);
                    break;
                }
        }
        if (jstr(a, "unguardable_hint")) check_arena_line(jstr(a, "unguardable_hint"), true, 28);
        const char *vul = jstr(jget(a, "boss"), "vulnerable");
        if (vul && (!arena_pattern_known(vul) || !strcmp(vul, "pause"))) err("unknown vulnerable pattern %s", vul);
        if (jstr(repair, "label")) check_text(jstr(repair, "label"));
        if (jstr(repair, "shield_label")) check_text(jstr(repair, "shield_label"));
        if (repair && cJSON_GetArraySize(jget(jget(a, "boss"), "phase2")) == 0) err("a repair fight needs its phase2 cycle%s", "");
        const char *phases[] = {"phase1", "phase2"};
        for (int k = 0; k < 2; k++) cJSON_ArrayForEach(x, jget(jget(a, "boss"), phases[k]))
            if (!cJSON_IsString(x) || !arena_pattern_known(x->valuestring)) err("unknown boss pattern %s", cJSON_IsString(x) ? x->valuestring : "?");
        int goals_w = 12; /* the simulation's checklist, one row of plates */
        cJSON_ArrayForEach(x, jget(a, "goal_labels")) if (cJSON_IsString(x)) {
            check_text(x->valuestring);
            goals_w += font_width(&G.bold_l, x->valuestring, -1) + 26;
        }
        if (G.bold_l.bits && goals_w > SCREEN_W - 8) err("goal labels do not fit on one row in large text%s", "");
    }
}

int content_validate(void) {
    errors = 0;
    if (G.v2) { /* a Lua game: main.lua must start (compile, run, _init) */
        if (v2_error()) hal_log("validate: %s", v2_error()), errors++;
        hal_log("validate: %d error(s)", errors);
        return errors;
    }
    char path[384];
    snprintf(path, sizeof path, "%s/arena.json", G.game_dir);
    FILE *af = fopen(path, "rb");
    if (af) fclose(af), arenas = json_file("arena.json");
    const cJSON *x;
    snprintf(where, sizeof where, "game.json");
    cJSON_ArrayForEach(x, jget(G.game, "flags")) if (!cJSON_IsString(x) || strchr(x->valuestring, ':')) err("flag names must be strings without ':'%s", "");
    cJSON_ArrayForEach(x, jget(G.game, "zones")) if (cJSON_IsString(x)) check_zone(x->valuestring);
    cJSON_ArrayForEach(x, jget(G.game, "dialogues")) if (cJSON_IsString(x)) check_dialogue(x->valuestring);
    if (jstr(G.game, "assist_flag")) check_flag(jstr(G.game, "assist_flag"));
    cJSON_ArrayForEach(x, jget(G.game, "speakers")) if (jstr(x, "blip")) check_audio(jstr(x, "blip")); /* voice tones */
    snprintf(where, sizeof where, "game.json start");
    check_dlg_ref(jstr(jget(G.game, "start"), "dlg") ? jstr(jget(G.game, "start"), "dlg") : "@");
    cJSON_ArrayForEach(x, G.items) {
        snprintf(where, sizeof where, "items/%s", x->string);
        check_text(jstr(x, "name"));
        check_text(jstr(x, "desc"));
        check_effects(jget(x, "inspect"));
        const font *fl = G.font_l.bits ? &G.font_l : &G.font, *bl = G.bold_l.bits ? &G.bold_l : &G.bold;
        uint16_t ls[8], ll[8]; /* the bag: the name heads the description, SCREEN_W - 52 px wide, 3 lines */
        if (jstr(x, "name") && font_width(bl, jstr(x, "name"), -1) > SCREEN_W - 52) err("item name wider than the bag%s", "");
        if (jstr(x, "desc") && (text_wrap(&G.font, jstr(x, "desc"), SCREEN_W - 52, ls, ll, 8) > 3 || text_wrap(fl, jstr(x, "desc"), SCREEN_W - 52, ls, ll, 8) > 4))
            err("item description too long for the bag (3 lines, 4 in large text)%s", "");
    }
    cJSON_ArrayForEach(x, G.events) {
        snprintf(where, sizeof where, "events/%s", x->string);
        if (!strcmp(x->string, "invariants")) {
            const cJSON *c;
            cJSON_ArrayForEach(c, x) check_cond(c);
            continue;
        }
        check_cond(jget(x, "if"));
        check_effects(jget(x, "do"));
        if (jstr(x, "seq") && !jget(G.sequences, jstr(x, "seq"))) err("unknown sequence %s", jstr(x, "seq"));
    }
    cJSON_ArrayForEach(x, jget(G.notebook, "entries")) {
        snprintf(where, sizeof where, "notebook/%s", x->string);
        const char *k = jstr(x, "kind");
        if (!k || (strcmp(k, "obs") && strcmp(k, "test") && strcmp(k, "q") && strcmp(k, "heard")))
            err("kind must be obs|test|heard|q%s", "");
        if (!jstr(x, "title") || !jstr(x, "text")) err("entry needs title and text%s", "");
        check_text(jstr(x, "text"));
    }
    cJSON_ArrayForEach(x, jget(G.notebook, "questions")) { check_cond(jget(x, "if")); check_text(jstr(x, "t")); }
    cJSON_ArrayForEach(x, jget(G.notebook, "tasks")) { check_cond(jget(x, "if")); check_text(jstr(x, "t")); }
    cJSON_ArrayForEach(x, G.sequences) {
        snprintf(where, sizeof where, "sequences/%s", x->string);
        const cJSON *st;
        if (cJSON_IsObject(x)) check_effects(jget(x, "skip")); /* {"steps", "skip"}: skippable */
        const cJSON *steps = cJSON_IsObject(x) ? jget(x, "steps") : x;
        cJSON_ArrayForEach(st, steps) {
            const char *o = jas(st, 0) ? jas(st, 0) : "";
            if (!strcmp(o, "line")) {
                const cJSON *spk = cJSON_GetArrayItem(st, 1), *t = cJSON_GetArrayItem(st, 2);
                if (!cJSON_IsString(spk) || !cJSON_IsString(t)) err("line step needs speaker and text%s", "");
                else { check_speaker(spk->valuestring); check_text(t->valuestring); }
            }
            else if (!strcmp(o, "do")) check_effects(cJSON_GetArrayItem(st, 1));
            else if (strcmp(o, "wait") && strcmp(o, "anim") && strcmp(o, "move_prop") && strcmp(o, "prop_frame") &&
                     strcmp(o, "camera") && strcmp(o, "walk") && strcmp(o, "walk_to") && strcmp(o, "fade_out") && strcmp(o, "fade_in") &&
                     strcmp(o, "audio_fade") && strcmp(o, "checkpoint") && strcmp(o, "save") && strcmp(o, "end")) {
                if (!strcmp(o, "sfx") || !strcmp(o, "voice")) check_audio(jas(st, 1));
                else if (!strcmp(o, "music")) check_cue(jas(st, 1));
                else err("unknown sequence step %s", o);
            }
        }
    }
    cJSON_ArrayForEach(x, G.listens) {
        snprintf(where, sizeof where, "listen/%s", x->string);
        check_effects(jget(x, "do"));
        if (jstr(x, "audio")) check_audio(jstr(x, "audio"));
        const char *lk = jstr(x, "kind");
        if (lk && strcmp(lk, "fisico") && strcmp(lk, "eco") && strcmp(lk, "familiar")) err("listen kind must be fisico|eco|familiar%s", "");
        if (jstr(x, "after")) check_dlg_ref(jstr(x, "after"));
        const cJSON *c;
        cJSON_ArrayForEach(c, jget(x, "cues")) if (cJSON_IsString(cJSON_GetArrayItem(c, 2))) check_text(cJSON_GetArrayItem(c, 2)->valuestring);
    }
    cJSON_ArrayForEach(x, G.puzzles) {
        snprintf(where, sizeof where, "puzzles/%s", x->string);
        check_panel_text(jstr(x, "instruction"));
        check_panel_text(jstr(x, "solved_text"));
        cJSON *sol = jget(x, "solution");
        if (jstr(x, "type") && !strcmp(jstr(x, "type"), "conduit")) { /* elbows: the route must exist */
            const cJSON *f;
            cJSON_ArrayForEach(f, jget(x, "state_flags")) check_flag(cJSON_IsString(f) ? f->valuestring : "");
            int n = cJSON_GetArraySize(jget(x, "pieces")), total = 1, o[4] = {0}, found = 0;
            if (n < 1 || n > 4) err("conduit needs 1-4 pieces%s", "");
            for (int i = 0; i < n && n <= 4; i++) total *= 4;
            for (int k = 0; k < total && n <= 4; k++) {
                for (int i = 0, v = k; i < n; i++, v /= 4) o[i] = v % 4;
                bool done;
                conduit_trace(x, o, &done, NULL, NULL);
                found += done;
            }
            char nfound[12];
            snprintf(nfound, sizeof nfound, "%d", found);
            if (found != 1) err("conduit needs exactly one solution (has %s)", nfound);
            const char *texts[] = {"instruction", "solved_text", "hint_text", "assist_text"};
            for (int i = 0; i < 4; i++) if (jstr(x, texts[i])) check_panel_text(jstr(x, texts[i]));
            check_effects(jget(x, "do"));
            continue;
        }
        if (jstr(x, "type") && !strcmp(jstr(x, "type"), "order")) { /* cards: marks, texts that fit a card */
            const cJSON *f;
            cJSON_ArrayForEach(f, jget(x, "state_flags")) check_flag(cJSON_IsString(f) ? f->valuestring : "");
            if (jstr(x, "tries_flag")) check_flag(jstr(x, "tries_flag"));
            cJSON_ArrayForEach(f, jget(x, "cards")) {
                check_text(jstr(f, "text"));
                const font *fonts[] = {&G.font, &G.font_l};
                for (int i = 0; i < 2; i++)
                    if (fonts[i]->bits && jstr(f, "text") && font_width(fonts[i], jstr(f, "text"), -1) > SCREEN_W - 48 - 92 - 28)
                        err("card text does not fit on its row: %s", jstr(f, "text"));
            }
            const char *texts[] = {"instruction", "solved_text", "wrong", "assist_text"};
            for (int i = 0; i < 4; i++) if (jstr(x, texts[i])) check_panel_text(jstr(x, texts[i]));
            check_effects(jget(x, "do"));
            continue;
        }
        if (jstr(x, "type") && !strcmp(jstr(x, "type"), "drill")) { /* timed exercises: press, hold, rhythm */
            const cJSON *st;
            if (!cJSON_GetArraySize(jget(x, "steps"))) err("drill needs steps%s", "");
            if (jstr(x, "tries_flag")) check_flag(jstr(x, "tries_flag"));
            cJSON_ArrayForEach(st, jget(x, "steps")) {
                const char *k = jstr(st, "kind") ? jstr(st, "kind") : "press";
                if (strcmp(k, "press") && strcmp(k, "hold") && strcmp(k, "rhythm")) err("drill step kind must be press|hold|rhythm%s", "");
                if (!strcmp(k, "rhythm") && (cJSON_GetArraySize(jget(st, "pulses")) < 2 || cJSON_GetArraySize(jget(st, "pulses")) > 6))
                    err("rhythm needs 2..6 pulses%s", "");
                check_panel_text(jstr(st, "text"));
                if (jstr(st, "sfx")) check_audio(jstr(st, "sfx"));
            }
            const char *texts[] = {"title", "good", "early", "late", "released", "your_turn", "cue_press", "cue_hold"};
            for (int i = 0; i < 8; i++) if (jstr(x, texts[i])) check_text(jstr(x, texts[i]));
            if (jstr(x, "help")) check_panel_text(jstr(x, "help"));
            if (jstr(x, "step_flag")) check_flag(jstr(x, "step_flag"));
            int ind_w[2] = {0, 0}; /* the two lamps: the wider word of each, in large text */
            for (int i = 0; i < 2; i++) for (int j = 0; j < 2; j++) {
                const char *t = jas(cJSON_GetArrayItem(jget(x, "indicators"), i), j);
                if (!t) continue;
                check_text(t);
                int w = font_width(G.bold_l.bits ? &G.bold_l : &G.bold, t, -1) + 52;
                if (w > ind_w[i]) ind_w[i] = w;
            }
            if (ind_w[0] > SCREEN_W - 24 || ind_w[1] > SCREEN_W - 24) err("drill indicator wider than the screen%s", "");
            check_effects(jget(x, "do"));
            continue;
        } else if (jstr(x, "type") && !strcmp(jstr(x, "type"), "pattern")) { /* rhythm puzzle: 3 pulses, its sounds */
            if (cJSON_GetArraySize(sol) != 3) err("pattern solution needs 3 pulses%s", "");
            if (jstr(x, "tries_flag")) check_flag(jstr(x, "tries_flag"));
            if (jstr(x, "hint_flag")) check_flag(jstr(x, "hint_flag"));
            if (jstr(x, "sfx_wrong")) check_audio(jstr(x, "sfx_wrong"));
            if (jstr(x, "hint_text")) check_panel_text(jstr(x, "hint_text"));
            const cJSON *p, *syms = jget(x, "symbols");
            cJSON_ArrayForEach(p, sol) {
                if (syms ? !list_has(syms, cJSON_IsString(p) ? p->valuestring : "")
                         : !cJSON_IsString(p) || (p->valuestring[0] != 's' && p->valuestring[0] != 'l'))
                    err(syms ? "solution entries must be listed in symbols%s" : "pulses are \"short\" or \"long\"%s", "");
            }
            if (syms) {
                if (jstr(x, "sfx")) check_audio(jstr(x, "sfx"));
                cJSON_ArrayForEach(p, jget(x, "labels")) check_text(cJSON_IsString(p) ? p->valuestring : NULL);
                cJSON_ArrayForEach(p, jget(x, "buttons")) check_text(cJSON_IsString(p) ? p->valuestring : NULL);
            } else {
                check_audio(jstr(x, "sfx_short"));
                check_audio(jstr(x, "sfx_long"));
            }
            if (jstr(x, "clue") || !syms) check_audio(jstr(x, "clue"));
            const char *texts[] = {"clue_text", "wrong", "incomplete", "assist_text"};
            for (int i = 0; i < 4; i++) check_panel_text(jstr(x, texts[i]));
            check_effects(jget(x, "do"));
            continue;
        }
        int n = p01_anchor_count(x);
        int m = p01_check(x, jint(sol, "x", 0), jint(sol, "y", 0), jint(sol, "rot", 0));
        if (n == 0 || m != (1 << n) - 1) err("solution does not satisfy all anchors%s", "");
        check_effects(jget(x, "do"));
        if (jstr(x, "after")) check_dlg_ref(jstr(x, "after"));
        const cJSON *h;
        cJSON_ArrayForEach(h, jget(x, "help")) check_panel_text(cJSON_IsString(h) ? h->valuestring : NULL);
        cJSON_ArrayForEach(h, jget(x, "partial")) check_panel_text(cJSON_IsString(h) ? h->valuestring : NULL);
    }
    snprintf(where, sizeof where, "notebook actions");
    cJSON_ArrayForEach(x, jget(G.notebook, "actions")) {
        check_cond(jget(x, "if"));
        check_effects(jget(x, "do"));
        check_text(jstr(x, "label"));
    }
    snprintf(where, sizeof where, "game.json objectives");
    cJSON_ArrayForEach(x, jget(G.game, "objectives")) {
        check_cond(jget(x, "if"));
        if (jstr(x, "text")) check_text(jstr(x, "text"));
        const font *fonts[] = {&G.font, &G.font_l}; /* one line under the location sign, in any text size */
        for (int i = 0; i < 2; i++)
            if (jstr(x, "text") && fonts[i]->bits && font_width(fonts[i], jstr(x, "text"), -1) + 40 > SCREEN_W - 16) {
                err("objective wider than the screen: %s", jstr(x, "text"));
                break;
            }
        const cJSON *c;
        cJSON_ArrayForEach(c, jget(x, "checks")) check_cond(jget(c, "if"));
    }
    cJSON_ArrayForEach(x, jget(G.game, "chapters")) {
        snprintf(where, sizeof where, "game.json chapter %s", jstr(x, "id") ? jstr(x, "id") : "?");
        if (jget(x, "started")) check_cond(jget(x, "started"));
        if (jget(x, "done")) check_cond(jget(x, "done"));
        check_text(jstr(x, "title"));
        const font *bl = G.bold_l.bits ? &G.bold_l : &G.bold;
        const char *end = jstr(x, "end_text"), *dot = end ? strstr(end, " · ") : NULL;
        if (end) { /* the end card: one line, or chapter / title around " · ", in large text */
            check_text(end);
            int w = dot ? font_width(bl, end, (int)(dot - end)) : font_width(bl, end, -1);
            if (dot && font_width(bl, dot + 4, -1) > w) w = font_width(bl, dot + 4, -1);
            if (w > SCREEN_W - 32) err("end text does not fit the end card: %s", end);
        }
        const cJSON *st = jget(x, "start");
        if (st) {
            check_effects(jget(st, "do"));
            if (!list_has(jget(G.game, "zones"), jstr(st, "zone") ? jstr(st, "zone") : "")) err("chapter start zone %s unknown", jstr(st, "zone"));
            if (jstr(st, "seq") && !jget(G.sequences, jstr(st, "seq"))) err("unknown sequence %s", jstr(st, "seq"));
        }
    }
    check_music();
    check_arenas();
    cJSON_Delete(arenas);
    arenas = NULL;
    hal_log("validate: %d error(s)", errors);
    return errors;
}
