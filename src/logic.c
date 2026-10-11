/* Conditions, effects and events. Everything persistent is a flag, so effects have set semantics:
 * running an event twice can never duplicate items or notebook entries. */
#include <string.h>

#include "bp.h"

int enum_index(const char *flag, const cJSON *val) {
    if (cJSON_IsNumber(val)) return val->valueint;
    if (!cJSON_IsString(val)) return -1;
    int i = 0;
    const cJSON *v;
    cJSON_ArrayForEach(v, jget(jget(G.game, "enums"), flag)) {
        if (cJSON_IsString(v) && !strcmp(v->valuestring, val->valuestring)) return i;
        i++;
    }
    return -1;
}

static bool op_is(const cJSON *op, const char *name) { return cJSON_IsString(op) && !strcmp(op->valuestring, name); }

bool cond_eval(const cJSON *c) {
    if (!c || cJSON_IsNull(c)) return true;
    if (cJSON_IsString(c)) {
        const char *s = c->valuestring;
        return s[0] == '!' ? flag_get(s + 1) == 0 : flag_get(s) != 0;
    }
    if (!cJSON_IsArray(c)) return false;
    const cJSON *op = cJSON_GetArrayItem(c, 0), *a1 = cJSON_GetArrayItem(c, 1), *a2 = cJSON_GetArrayItem(c, 2);
    const char *s1 = cJSON_IsString(a1) ? a1->valuestring : "";
    if (op_is(op, "eq")) return flag_get(s1) == enum_index(s1, a2);
    if (op_is(op, "ge")) return flag_get(s1) >= enum_index(s1, a2);
    if (op_is(op, "has")) return flagf_get("item:%s%s", s1, "") != 0;
    if (op_is(op, "seen")) return flagf_get("seen:%s%s", s1, "") != 0;
    if (op_is(op, "topic")) return flagf_get("topic:%s%s", s1, "") != 0;
    if (op_is(op, "visited")) return flagf_get("visited:%s%s", s1, "") != 0;
    if (op_is(op, "open")) return G.pz.def && G.pz.def->string && !strcmp(G.pz.def->string, s1); /* a puzzle on screen */
    if (op_is(op, "using")) return G.using_item && !strcmp(G.using_item, s1);
    if (op_is(op, "not")) return !cond_eval(a1);
    if (op_is(op, "or")) {
        for (const cJSON *x = a1; x; x = x->next)
            if (cond_eval(x)) return true;
        return false;
    }
    const cJSON *x = op_is(op, "and") ? a1 : cJSON_GetArrayItem(c, 0);
    for (; x; x = x->next)
        if (!cond_eval(x)) return false;
    return true;
}

static void note_add(const char *id) {
    if (flagf_get("note:%s%s", id, "")) return;
    flagf_set(1, "note:%s%s", id, "");
    sound("note");
    const char *title = jstr(jget(jget(G.notebook, "entries"), id), "title");
    char msg[96];
    snprintf(msg, sizeof msg, "Nueva nota: %s", title ? title : id);
    ui_toast_queue(msg);
}

static void effect_run(const cJSON *e) {
    const cJSON *op = cJSON_GetArrayItem(e, 0), *a1 = cJSON_GetArrayItem(e, 1), *a2 = cJSON_GetArrayItem(e, 2);
    const char *s1 = cJSON_IsString(a1) ? a1->valuestring : "", *s2 = cJSON_IsString(a2) ? a2->valuestring : NULL;
    if (op_is(op, "set")) flag_set(s1, a2 ? enum_index(s1, a2) : 1);
    else if (op_is(op, "clear")) flag_set(s1, 0);
    else if (op_is(op, "give")) flagf_set(1, "item:%s%s", s1, "");
    else if (op_is(op, "take")) flagf_set(0, "item:%s%s", s1, "");
    else if (op_is(op, "note")) note_add(s1);
    else if (op_is(op, "event")) event_run(s1);
    else if (op_is(op, "seq")) seq_start(s1);
    else if (op_is(op, "listen")) listen_start(s1);
    else if (op_is(op, "puzzle")) puzzle_open(s1);
    else if (op_is(op, "arena")) arena_start(s1), arena_practice(s2 && !strcmp(s2, "practice"));
    else if (op_is(op, "dlg")) dlg_open(s1);
    else if (op_is(op, "say")) dlg_say(G.pl.speaker, s1, NULL);
    else if (op_is(op, "zone")) world_enter(s1, s2 ? s2 : "safe");
    else if (op_is(op, "sfx")) audio_sfx(s1, 1);
    else if (op_is(op, "voice")) audio_voice(s1);
    else if (op_is(op, "music")) music_force(s1);
    else if (op_is(op, "audio_fade")) music_hush(); /* the ambience goes quiet until the next zone */
    else if (op_is(op, "when")) { if (cond_eval(a1)) effects_run(a2); }
    else if (op_is(op, "save")) { if (G.autosave_enabled) save_write("auto"); }
    else if (op_is(op, "checkpoint")) save_write("prefinal");
    else if (op_is(op, "end")) layers_reset(L_END);
    else hal_log("unknown effect %s", cJSON_IsString(op) ? op->valuestring : "?");
}

void effects_run(const cJSON *list) {
    static int depth; /* content cycles (event -> event, zone -> on_enter -> zone) must not overflow the stack */
    if (depth > 16) {
        hal_log("effects nested too deep; check content for cycles");
        return;
    }
    depth++;
    const cJSON *e;
    cJSON_ArrayForEach(e, list) effect_run(e);
    depth--;
}

bool event_run(const char *id) {
    cJSON *ev = jget(G.events, id);
    if (!ev) {
        hal_log("unknown event %s", id);
        return false;
    }
    if (!cond_eval(jget(ev, "if"))) return false;
    effects_run(jget(ev, "do"));
    const char *bad = invariants_check();
    if (bad) hal_log("INVARIANT BROKEN after %s: %s", id, bad);
    if (cJSON_IsTrue(jget(ev, "save")) && G.autosave_enabled) save_write("auto");
    if (jstr(ev, "seq")) seq_start(jstr(ev, "seq"));
    return true;
}

const char *invariants_check(void) {
    static char msg[160];
    int i = 0;
    const cJSON *c;
    cJSON_ArrayForEach(c, jget(G.events, "invariants")) {
        if (!cond_eval(c)) {
            char *txt = cJSON_PrintUnformatted(c);
            snprintf(msg, sizeof msg, "invariant #%d %s", i, txt ? txt : "?");
            cJSON_free(txt);
            return msg;
        }
        i++;
    }
    return NULL;
}
