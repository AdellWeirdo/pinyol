/* The console's record of its games (played.h): one small JSON file, read when first needed, written when something
 * changes (to a temporary file, then renamed: a cut write leaves the old one). Without a console folder (the
 * headless player, unless PINYOL_HOME is set) it is kept in memory for the run. */
#include <stdio.h>
#include <stdlib.h>
#include <string.h>

#include "bp.h"
#include "played.h"

static bool safe_id(const char *s) { /* a game's id as the Library allows it: letters, digits, _ and -, 1 to 40 */
    size_t n = strlen(s);
    if (!n || n > 40) return false;
    for (; *s; s++)
        if (!((*s >= 'a' && *s <= 'z') || (*s >= 'A' && *s <= 'Z') || (*s >= '0' && *s <= '9') || *s == '_' || *s == '-')) return false;
    return true;
}

static cJSON *doc;
static char current[32];
static char *json_text;

static bool path_of(char *p, size_t n) {
    char dir[384];
    if (!hal_console_dir(dir, sizeof dir)) return false;
    snprintf(p, n, "%s/played.json", dir);
    return true;
}

static cJSON *load(void) {
    if (doc) return doc;
    char p[400];
    char *txt = path_of(p, sizeof p) ? read_file(p, NULL) : NULL;
    doc = txt ? cJSON_Parse(txt) : NULL;
    free(txt);
    if (!cJSON_IsObject(doc)) cJSON_Delete(doc), doc = cJSON_CreateObject();
    return doc;
}

static void save(void) {
    char p[400], tmp[408];
    if (!path_of(p, sizeof p)) return;
    char *txt = cJSON_PrintUnformatted(load());
    if (!txt) return;
    snprintf(tmp, sizeof tmp, "%s.tmp", p);
    FILE *f = fopen(tmp, "w");
    bool ok = f && fputs(txt, f) >= 0 && fputc('\n', f) != EOF;
    if (f) ok = (fclose(f) == 0) && ok;
    if (ok) ok = rename(tmp, p) == 0;
    if (!ok) hal_log("played: cannot write %s", p);
    free(txt);
}

static cJSON *entry(const char *id) { /* the game's record, made if needed */
    cJSON *d = load(), *e = cJSON_GetObjectItemCaseSensitive(d, id);
    if (!cJSON_IsObject(e)) {
        if (e) cJSON_DeleteItemFromObjectCaseSensitive(d, id);
        e = cJSON_AddObjectToObject(d, id);
    }
    return e;
}

static void set_num(cJSON *e, const char *k, double v) {
    cJSON *n = cJSON_GetObjectItemCaseSensitive(e, k);
    if (cJSON_IsNumber(n)) cJSON_SetNumberValue(n, v);
    else cJSON_DeleteItemFromObjectCaseSensitive(e, k), cJSON_AddNumberToObject(e, k, v);
}

static double get_num(const cJSON *e, const char *k) {
    const cJSON *n = cJSON_GetObjectItemCaseSensitive(e, k);
    return cJSON_IsNumber(n) ? n->valuedouble : 0;
}

void played_begin(const char *id) { /* a play more, now (the time comes at the end) */
    const bool game = id && safe_id(id) && strcmp(id, CONSOLE_MENU_ID); /* (the menu itself is not a game played) */
    snprintf(current, sizeof current, "%s", game ? id : "");
    if (!current[0]) return;
    cJSON *e = entry(current);
    set_num(e, "plays", get_num(e, "plays") + 1);
    int64_t utc = 0;
    int off = 0;
    if (hal_clock(&utc, &off)) set_num(e, "last", (double)utc);
    set_num(load(), "_seq", get_num(load(), "_seq") + 1);
    set_num(e, "seq", get_num(load(), "_seq")); /* the order games were played in, clock or not */
    free(json_text), json_text = NULL;
    save();
}

void played_end(uint32_t ticks) {
    if (!current[0]) return;
    if (ticks) {
        cJSON *e = entry(current);
        set_num(e, "seconds", get_num(e, "seconds") + (double)ticks / TICK_HZ);
        free(json_text), json_text = NULL;
        save();
    }
    current[0] = 0;
}

bool played_favourite(const char *id, int set) {
    if (!id || !safe_id(id)) return false;
    cJSON *e = entry(id), *f = cJSON_GetObjectItemCaseSensitive(e, "fav");
    if (set >= 0) {
        cJSON_DeleteItemFromObjectCaseSensitive(e, "fav");
        cJSON_AddBoolToObject(e, "fav", set);
        free(json_text), json_text = NULL;
        save();
        return set;
    }
    return cJSON_IsTrue(f);
}

static cJSON *done_list(cJSON *e) {
    cJSON *d = cJSON_GetObjectItemCaseSensitive(e, "done");
    if (!cJSON_IsArray(d)) {
        if (d) cJSON_DeleteItemFromObjectCaseSensitive(e, "done");
        d = cJSON_AddArrayToObject(e, "done");
    }
    return d;
}

bool played_achieved(const char *game, const char *id) {
    if (!game || !id || !safe_id(game)) return false;
    const cJSON *d = done_list(entry(game)), *it;
    cJSON_ArrayForEach(it, d) if (cJSON_IsString(it) && !strcmp(it->valuestring, id)) return true;
    return false;
}

bool played_achieve(const char *game, const char *id) {
    if (played_achieved(game, id)) return false;
    if (!game || !id || !safe_id(game) || strlen(id) > 32) return false;
    cJSON_AddItemToArray(done_list(entry(game)), cJSON_CreateString(id));
    free(json_text), json_text = NULL;
    save();
    return true;
}

const char *played_json(void) {
    if (!json_text) json_text = cJSON_PrintUnformatted(load());
    return json_text ? json_text : "{}";
}
