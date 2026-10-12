/* Acceptance script runner: feeds synthetic input through the real game loop (same as a player)
 * and checks invariants on every tick. One command per line; '#' starts a comment. */
#include <math.h>
#include <stdlib.h>
#include <string.h>

#include "bp.h"

static void (*frame_cb)(void);
static int line_no;
static char fail_msg[256];

#define FAIL(...) do { snprintf(fail_msg, sizeof fail_msg, __VA_ARGS__); return false; } while (0)

static bool tick_input(uint16_t held, bool touch, int px, int py) {
    hal_input in = {held, touch, (int16_t)px, (int16_t)py};
    game_tick(&in);
    if (layer_has(L_PLAY)) {
        const char *bad = invariants_check();
        if (bad) FAIL("%s", bad);
    }
    if (frame_cb) frame_cb();
    return true;
}

static bool tick(uint16_t held) { return tick_input(held, false, 0, 0); }
static int pace; /* "pace N": idle ticks after every press, to record a run at a human (reading) speed */
static int read_cps; /* "read CPS": each line waits as long as reading it takes (a duration run, Geumgye §02) */
static const char *last_read;

static bool idle(int n) {
    for (int i = 0; i < n; i++)
        if (!tick(0)) return false;
    return true;
}

static bool press(uint16_t k) {
    if (!tick(k) || !tick(0)) return false;
    for (int i = 0; i < pace; i++)
        if (!tick(0)) return false;
    return true;
}

static bool press_named(const char *name, uint16_t k) {
    if (!k) FAIL("unknown key %s", name);
    return press(k);
}

static uint16_t key_of(const char *s) {
    static const struct { const char *n; uint16_t k; } keys[] = {
        {"UP", ACT_UP}, {"DOWN", ACT_DOWN}, {"LEFT", ACT_LEFT}, {"RIGHT", ACT_RIGHT}, {"OK", ACT_OK}, {"A", ACT_OK},
        {"BACK", ACT_BACK}, {"B", ACT_BACK}, {"NEXT", ACT_NEXT}, {"C", ACT_NEXT}, {"INV", ACT_INV}, {"MENU", ACT_INV}, {"NOTES", ACT_NOTES},
        {"PAUSE", ACT_PAUSE}, {"START", ACT_PAUSE}};
    uint16_t k = 0;
    char buf[64];
    snprintf(buf, sizeof buf, "%s", s);
    for (char *t = strtok(buf, "+"); t; t = strtok(NULL, "+"))
        for (size_t i = 0; i < sizeof keys / sizeof keys[0]; i++)
            if (!strcmp(keys[i].n, t)) k |= keys[i].k;
    return k;
}

static const char *layer_name(layer_id l) {
    static const char *n[] = {"?", "TITLE", "PLAY", "DLG", "INV", "NOTES", "PUZZLE", "SEQ", "LISTEN", "PAUSE", "END", "ERROR", "ARENA"};
    return l <= L_ARENA ? n[l] : "?";
}

/* Reads dialogues, sequences and listening through until the player is free (or a choice is up). */
static bool advance(void) {
    for (int i = 0; i < 20000; i++) {
        layer_id t = layer_top();
        if (t == L_DLG && !G.dlg.choosing) {
            if (read_cps && dlg_text() != last_read) { /* read it once: a page break or a silence is not re-read */
                last_read = dlg_text();
                if (!idle((int)strlen(last_read) * TICK_HZ / read_cps + TICK_HZ / 2)) return false;
            }
            if (!press(ACT_OK)) return false;
        }
        else if (t == L_SEQ || t == L_LISTEN || (t == L_ARENA && arena_busy())) { if (!tick(0)) return false; }
        else return true;
    }
    FAIL("advance did not settle (top %s)", layer_name(layer_top()));
}

/* Steer the feet to the centre of tile (tx,ty). */
static bool walk_to_tile(int tx, int ty) {
    float gx = tx * TILE + 8, gy = ty * TILE + 12;
    char zone[8];
    snprintf(zone, sizeof zone, "%s", G.zone.id);
    for (int i = 0; i < 90; i++) {
        float dx = gx - G.klaus.x, dy = gy - G.klaus.y, ox = G.klaus.x, oy = G.klaus.y;
        if (fabsf(dx) <= 1.7f && fabsf(dy) <= 1.7f) return true; /* within one step (1.6 px) */
        uint16_t h = dx > 0.4f ? ACT_RIGHT : dx < -0.4f ? ACT_LEFT : 0, v = dy > 0.4f ? ACT_DOWN : dy < -0.4f ? ACT_UP : 0;
        if (!tick(h | v)) return false;
        if (layer_top() != L_PLAY || strcmp(zone, G.zone.id)) return true;
        if (G.klaus.x == ox && G.klaus.y == oy && h && v) { /* grazing a corner: settle one axis, then the other */
            if (!tick(v) || !tick(h)) return false;
        }
    }
    FAIL("stuck walking to tile %d,%d (at %.1f,%.1f)", tx, ty, G.klaus.x, G.klaus.y);
}

static bool follow_path(int gx, int gy) {
    int dirs[512];
    int n = world_path(gx, gy, dirs, 512);
    if (n < 0) FAIL("no path to tile %d,%d in %s", gx, gy, G.zone.id);
    int tx = (int)(G.klaus.x / TILE), ty = (int)(G.klaus.y / TILE);
    if (!walk_to_tile(tx, ty)) return false;
    static const int ddx[4] = {0, 1, 0, -1}, ddy[4] = {-1, 0, 1, 0};
    for (int i = 0; i < n; i++) {
        tx += ddx[dirs[i]];
        ty += ddy[dirs[i]];
        if (!walk_to_tile(tx, ty)) return false;
        if (layer_top() != L_PLAY) return true;
    }
    return true;
}

static bool go(const char *id) {
    if (layer_top() != L_PLAY) FAIL("go %s: player not free (top %s)", id, layer_name(layer_top()));
    float x, y;
    bool npc;
    const cJSON *o = world_find(id, &x, &y, &npc);
    if (!o) FAIL("go: target %s not visible in %s", id, G.zone.id);
    int reach = jint(o, "reach", 20), best_len = 1 << 30, bx = -1, by = -1, dirs[512];
    for (int ty = (int)(y / TILE) - 3; ty <= (int)(y / TILE) + 3; ty++)
        for (int tx = (int)(x / TILE) - 3; tx <= (int)(x / TILE) + 3; tx++) {
            float cx = tx * TILE + 8, cy = ty * TILE + 12;
            float r = reach - 3.0f; /* margin: the walker stops within a step of the tile centre */
            if ((cx - x) * (cx - x) + (cy - y) * (cy - y) > r * r || !world_box_free(cx, cy) || world_on_exit(cx, cy)) continue;
            int n = world_path(tx, ty, dirs, 512);
            if (n >= 0 && npc && fabsf(cx - x) < fabsf(cy - y)) n += 4; /* talk beside a neighbour, never stacked on them */
            if (n >= 0 && n < best_len) { best_len = n; bx = tx; by = ty; }
        }
    if (bx < 0) FAIL("go: no reachable tile near %s", id);
    if (!follow_path(bx, by)) return false;
    for (int i = 0; i < 8; i++) {
        world_update_target();
        if (G.target == o) return true;
        if (!press(ACT_NEXT)) return false;
    }
    FAIL("go: arrived but %s is not selectable", id);
}

static bool take_exit(const char *zone) {
    if (layer_top() != L_PLAY) FAIL("exit %s: player not free", zone);
    int rx, ry, rw, rh;
    if (!world_exit_rect(zone, &rx, &ry, &rw, &rh)) FAIL("no exit to %s from %s", zone, G.zone.id);
    static const int ddx[4] = {0, 1, 0, -1}, ddy[4] = {-1, 0, 1, 0};
    int dirs[512], best = 1 << 30, gx = -1, gy = -1, push = 0;
    for (int ty = ry; ty < ry + rh; ty++)
        for (int tx = rx; tx < rx + rw; tx++)
            for (int d = 0; d < 4; d++) {
                int nx = tx - ddx[d], ny = ty - ddy[d];
                if (nx >= rx && nx < rx + rw && ny >= ry && ny < ry + rh) continue;
                if (!world_box_free(nx * TILE + 8, ny * TILE + 12)) continue;
                int n = world_path(nx, ny, dirs, 512);
                if (n >= 0 && n < best) { best = n; gx = nx; gy = ny; push = d; }
            }
    if (gx < 0) FAIL("exit %s: no walkable tile next to it", zone);
    if (!follow_path(gx, gy)) return false;
    static const uint16_t key[4] = {ACT_UP, ACT_RIGHT, ACT_DOWN, ACT_LEFT};
    for (int i = 0; i < 60 && strcmp(G.zone.id, zone) && layer_top() == L_PLAY; i++)
        if (!tick(key[push])) return false;
    return tick(0);
}

static bool inventory_action(const char *item, int action) {
    if (layer_top() != L_PLAY) FAIL("inventory: player not free");
    if (!press(ACT_INV)) return false;
    int idx = 0, found = -1;
    const cJSON *it;
    cJSON_ArrayForEach(it, G.items) if (flagf_get("item:%s%s", it->string, "")) {
        if (!strcmp(it->string, item)) found = idx;
        idx++;
    }
    if (found < 0) FAIL("inventory: %s not carried", item);
    for (int i = 0; i < 12 && G.inv_sel != found; i++)
        if (!press(ACT_RIGHT)) return false;
    if (!press(ACT_OK)) return false;
    for (int i = 0; i < action; i++)
        if (!press(ACT_DOWN)) return false;
    return press(ACT_OK);
}

static bool choose(const char *what) {
    if (read_cps && !idle(2 * TICK_HZ)) return false; /* thinking it over */
    if (layer_top() != L_DLG || !G.dlg.choosing) FAIL("choose %s: no choices showing (top %s, text \"%.40s\")", what, layer_name(layer_top()), dlg_text());
    int idx = -1;
    for (int i = 0; i < G.dlg.nchoices && idx < 0; i++) {
        const char *id = jstr(G.dlg.choices[i], "id"), *t = jstr(G.dlg.choices[i], "text");
        if ((id && !strcmp(id, what)) || (t && strstr(t, what))) idx = i;
    }
    if (idx < 0) {
        char list[200] = "";
        for (int i = 0; i < G.dlg.nchoices; i++) {
            strncat(list, jstr(G.dlg.choices[i], "id") ? jstr(G.dlg.choices[i], "id") : "?", sizeof list - strlen(list) - 2);
            strncat(list, " ", sizeof list - strlen(list) - 1);
        }
        FAIL("choose %s: not among [%s]", what, list);
    }
    for (int i = 0; i < G.dlg.nchoices && G.dlg.sel != idx; i++)
        if (!press(ACT_DOWN)) return false;
    return press(ACT_OK);
}

/* Button-only placement: A rotates, the D-pad moves; releasing the D-pad validates. */
static bool p01_keys(int x, int y, int rot) {
    if (layer_top() != L_PUZZLE) FAIL("p01: puzzle not open");
    for (int i = 0; i < 4 && G.pz.rot != rot; i++)
        if (!press(ACT_OK)) return false;
    for (int i = 0; i < 400 && layer_top() == L_PUZZLE && !G.pz.solved; i++) {
        int dx = x - G.pz.x, dy = y - G.pz.y;
        uint16_t k = (dx >= 2 ? ACT_RIGHT : dx <= -2 ? ACT_LEFT : 0) | (dy >= 2 ? ACT_DOWN : dy <= -2 ? ACT_UP : 0);
        if (!k) break;
        if (!tick(k)) return false;
    }
    return tick(0);
}

static bool p01_place(int x, int y, int rot) {
    if (layer_top() != L_PUZZLE) FAIL("p01: puzzle not open");
    for (int i = 0; i < 4 && G.pz.rot != rot; i++)
        if (!press(ACT_OK)) return false;
    const cJSON *size = jget(G.pz.def, "trace_size");
    int w = jai(size, 0, 0), h = jai(size, 1, 0);
    int rw = (rot & 1) ? h : w, rh = (rot & 1) ? w : h;
    int sx = G.pz.x + rw / 2, sy = G.pz.y + rh / 2, ex = x + rw / 2, ey = y + rh / 2;
    if (!tick_input(0, true, sx, sy)) return false;
    for (int i = 1; i <= 6; i++)
        if (!tick_input(0, true, sx + (ex - sx) * i / 6, sy + (ey - sy) * i / 6)) return false;
    return tick_input(0, false, ex, ey);
}

static bool write_ppm(const char *name) {
    static uint16_t fb[SCREEN_W * SCREEN_H];
    game_render(fb);
    char path[384];
    snprintf(path, sizeof path, "%s/%s.ppm", G.save_dir, name);
    FILE *f = fopen(path, "wb");
    if (!f) FAIL("cannot write %s", path);
    fprintf(f, "P6\n%d %d\n255\n", SCREEN_W, SCREEN_H);
    for (int i = 0; i < SCREEN_W * SCREEN_H; i++) {
        uint16_t c = fb[i];
        uint8_t rgb[3] = {(uint8_t)((c >> 11) << 3), (uint8_t)(((c >> 5) & 63) << 2), (uint8_t)((c & 31) << 3)};
        fwrite(rgb, 1, 3, f);
    }
    fclose(f);
    hal_log("shot %s", path);
    return true;
}

static bool expect(const char *arg, bool want) {
    cJSON *c = cJSON_Parse(arg);
    if (!c) c = cJSON_CreateString(arg);
    bool got = cond_eval(c);
    cJSON_Delete(c);
    if (got != want) FAIL("expect%s %s failed", want ? "" : "_not", arg);
    return true;
}

static bool text_visible(const char *s) {
    return strstr(dlg_text(), s) || (G.pz.msg && layer_has(L_PUZZLE) && strstr(G.pz.msg, s)) ||
           (G.lis.sub && strstr(G.lis.sub, s)) || strstr(G.toast, s) || (layer_top() == L_ERROR && strstr(G.error, s));
}

static bool run_line(char *cmd, char *arg) {
    if (!strcmp(cmd, "new")) { game_new(); return tick(0); }
    if (!strcmp(cmd, "lua") || !strcmp(cmd, "expect_lua")) { /* np2d@2: run code / check an expression in the game */
        char msg[200];
        if (!v2_run(arg, cmd[0] == 'e', msg, sizeof msg)) FAIL("%s %s -> %s", cmd, arg, msg);
        return true;
    }
    if (!strcmp(cmd, "expect_lua_error")) { /* np2d@2: this code must fail (a limit of the sandbox) */
        char msg[200];
        if (v2_run(arg, false, msg, sizeof msg)) FAIL("expect_lua_error %s: it ran without an error", arg);
        hal_log("expected error: %s", msg);
        return true;
    }
    if (!strcmp(cmd, "expect_ok")) { /* np2d@2: the script has not stopped on an error */
        if (v2_error()) FAIL("the game's script failed: %s", v2_error());
        return true;
    }
    if (!strcmp(cmd, "continue")) {
        const char *slot = *arg ? arg : save_newest();
        if (!slot) FAIL("continue: no save");
        game_continue(slot);
        return tick(0);
    }
    if (!strcmp(cmd, "tick")) {
        for (int i = atoi(arg); i > 0; i--)
            if (!tick(0)) return false;
        return true;
    }
    if (!strcmp(cmd, "press")) return press_named(arg, key_of(arg));
    if (!strcmp(cmd, "tap")) { /* tap X Y: a finger down and up at screen pixel (X, Y) of the 480x320 screen */
        int x, y;
        if (sscanf(arg, "%d %d", &x, &y) != 2) FAIL("tap X Y");
        return tick_input(0, true, x, y) && tick(0);
    }
    if (!strcmp(cmd, "hold")) {
        char k[32];
        int n = 0;
        sscanf(arg, "%31s %d", k, &n);
        if (!key_of(k)) FAIL("unknown key %s", k);
        for (int i = 0; i < n; i++)
            if (!tick(key_of(k))) return false;
        return tick(0);
    }
    if (!strcmp(cmd, "advance")) return advance();
    if (!strcmp(cmd, "pace")) { pace = atoi(arg); return true; }
    if (!strcmp(cmd, "read")) { read_cps = atoi(arg); return true; }
    if (!strcmp(cmd, "arena_auto")) { /* arena_auto [MAX]: a plain player fights until the arena closes */
        int max = *arg ? atoi(arg) : 60 * TICK_HZ * 15;
        for (int i = 0; i < max; i++) {
            if (!strcmp(arena_state("boss"), "none") && (layer_top() != L_DLG || G.dlg.choosing)) return true; /* or a choice after it */
            if (layer_top() == L_DLG && !G.dlg.choosing) { if (!advance()) return false; continue; }
            if (!tick(arena_bot())) return false;
        }
        int ph = 0, bhp = 0, hp = 0, prog = 0;
        arena_value("phase", &ph), arena_value("boss_hp", &bhp), arena_value("player_hp", &hp), arena_value("progress", &prog);
        FAIL("arena_auto: the fight did not end in %d ticks (boss %s, player %s; phase %d, boss_hp %d, player_hp %d, progress %d)",
             max, arena_state("boss"), arena_state("player"), ph, bhp, hp, prog);
    }
    if (!strcmp(cmd, "choose")) return choose(arg);
    if (!strcmp(cmd, "go")) return go(arg);
    if (!strcmp(cmd, "interact")) return go(arg) && press(ACT_OK);
    if (!strcmp(cmd, "exit")) return take_exit(arg);
    if (!strcmp(cmd, "inspect")) return inventory_action(arg, 0);
    if (!strcmp(cmd, "use")) return inventory_action(arg, 1);
    if (!strcmp(cmd, "show")) return inventory_action(arg, 2);
    if (!strcmp(cmd, "p01")) {
        int x, y, r;
        if (sscanf(arg, "place %d %d %d", &x, &y, &r) == 3) return p01_place(x, y, r);
        if (sscanf(arg, "keys %d %d %d", &x, &y, &r) == 3) return p01_keys(x, y, r);
        if (!strcmp(arg, "solution")) {
            const cJSON *s = jget(G.pz.def, "solution");
            return p01_place(jint(s, "x", 0) + 5, jint(s, "y", 0) - 4, jint(s, "rot", 0)); /* within tolerance */
        }
        FAIL("p01: unknown subcommand %s", arg);
    }
    if (!strcmp(cmd, "expect")) return expect(arg, true);
    if (!strcmp(cmd, "expect_not")) return expect(arg, false);
    if (!strcmp(cmd, "expect_zone")) { if (strcmp(G.zone.id, arg)) FAIL("expected zone %s, in %s", arg, G.zone.id); return true; }
    if (!strcmp(cmd, "expect_layer")) {
        if (strcmp(layer_name(layer_top()), arg)) FAIL("expected layer %s, top is %s", arg, layer_name(layer_top()));
        return true;
    }
    if (!strcmp(cmd, "expect_text")) { if (!text_visible(arg)) FAIL("text \"%s\" not visible (dialogue: \"%.60s\")", arg, dlg_text()); return true; }
    if (!strcmp(cmd, "expect_no_text")) { if (text_visible(arg)) FAIL("text \"%s\" unexpectedly visible", arg); return true; }
    if (!strcmp(cmd, "expect_no_choice")) {
        if (layer_top() != L_DLG || !G.dlg.choosing) FAIL("expect_no_choice: no choices showing");
        for (int i = 0; i < G.dlg.nchoices; i++)
            if (jstr(G.dlg.choices[i], "id") && !strcmp(jstr(G.dlg.choices[i], "id"), arg)) FAIL("choice %s is offered", arg);
        return true;
    }
    if (!strcmp(cmd, "expect_save")) { if (!save_peek(arg, NULL)) FAIL("no valid save in slot %s", arg); return true; }
    if (!strcmp(cmd, "save")) { if (!save_write(*arg ? arg : "manual")) FAIL("save failed"); return true; }
    if (!strcmp(cmd, "powercut")) { /* lose RAM, keep the card */
        bp_config c = G.cfg;
        char game_dir[256], save_dir[256];
        snprintf(game_dir, sizeof game_dir, "%s", G.game_dir);
        snprintf(save_dir, sizeof save_dir, "%s", G.save_dir);
        c.game_dir = game_dir;
        c.save_dir = save_dir;
        game_init(&c);
        return tick(0);
    }
    if (!strcmp(cmd, "missing_audio")) { audio_force_missing(arg); return true; }
    if (!strcmp(cmd, "missing_asset")) { gfx_force_missing(arg); return true; }
    if (!strcmp(cmd, "missing_zone")) {
        snprintf(G.missing_zone, sizeof G.missing_zone, "%s", arg); /* content_zone() checks this first */
        return true;
    }
    if (!strcmp(cmd, "shot")) return write_ppm(arg);
    if (!strcmp(cmd, "zone")) { /* debug: jump straight to a zone's safe spawn */
        layers_reset(L_PLAY);
        return world_enter(arg, "safe") && tick(0);
    }
    if (!strcmp(cmd, "flag")) { /* debug: "flag NAME" sets 1, "flag NAME VALUE" a number or an enum's name */
        char name[64], val[64];
        if (sscanf(arg, "%63s %63s", name, val) == 2) {
            cJSON *v = val[0] >= '0' && val[0] <= '9' ? cJSON_CreateNumber(atoi(val)) : cJSON_CreateString(val);
            flag_set(name, enum_index(name, v));
            cJSON_Delete(v);
        } else flag_set(arg, 1);
        return tick(0);
    }
    if (!strcmp(cmd, "arena")) { arena_start(arg); return tick(0); } /* debug: straight into a fight */
    if (!strcmp(cmd, "drill_wait")) { /* drill_wait PHASE [KEY|-] [MAX]: tick, holding KEY, until the drill is in PHASE */
        char ph[16], k[16] = "-";
        int max = 600, n = sscanf(arg, "%15s %15s %d", ph, k, &max);
        uint16_t key = strcmp(k, "-") ? key_of(k) : 0;
        if (n < 1) FAIL("drill_wait PHASE [KEY|-] [MAX]");
        for (int i = 0; i < max; i++) {
            if (!strcmp(drill_phase(), ph)) return true;
            if (!tick(key)) return false;
        }
        FAIL("drill_wait: never reached %s (now %s)", ph, drill_phase());
    }
    if (!strcmp(cmd, "arena_wait")) { /* arena_wait boss|player STATE [KEY|-] [MAX]: tick, holding KEY, until it */
        char who[16], st[16], k[16] = "-";
        int max = 1200, n = sscanf(arg, "%15s %15s %15s %d", who, st, k, &max);
        uint16_t key = strcmp(k, "-") ? key_of(k) : 0;
        if (n < 2) FAIL("arena_wait boss|player STATE [KEY|-] [MAX]");
        if (strcmp(k, "-") && !key) FAIL("unknown key %s", k);
        for (int i = 0; i < max; i++) {
            if (!strcmp(arena_state(who), st)) return true;
            if (!tick(key)) return false;
        }
        FAIL("arena_wait: %s never reached %s (now %s)", who, st, arena_state(who));
    }
    if (!strcmp(cmd, "expect_arena")) { /* expect_arena FIELD OP N, OP one of == != < > <= >= */
        char f[24], op[3];
        int want, have;
        if (sscanf(arg, "%23s %2s %d", f, op, &want) != 3 || !arena_value(f, &have)) FAIL("expect_arena FIELD OP N: %s", arg);
        bool ok = !strcmp(op, "==") ? have == want : !strcmp(op, "!=") ? have != want : !strcmp(op, "<") ? have < want
                : !strcmp(op, ">") ? have > want : !strcmp(op, "<=") ? have <= want : !strcmp(op, ">=") && have >= want;
        if (!ok) FAIL("expect_arena %s %s %d, got %d", f, op, want, have);
        return true;
    }
    if (!strcmp(cmd, "arena_set")) { /* debug */
        char f[24];
        int v;
        if (sscanf(arg, "%23s %d", f, &v) != 2 || !arena_poke(f, v)) FAIL("arena_set FIELD N: %s", arg);
        return tick(0);
    }
    if (!strcmp(cmd, "place")) { /* debug: put Klaus at x y (logical px), ignoring collision */
        if (sscanf(arg, "%f %f", &G.klaus.x, &G.klaus.y) != 2) FAIL("place x y");
        G.banner_ms = 0;
        return tick(0);
    }
    if (!strcmp(cmd, "log")) { hal_log("script: %s", arg); return true; }
    if (!strcmp(cmd, "mute")) return true;
    FAIL("unknown command %s", cmd);
}

int script_run(const char *path, void (*frame)(void)) {
    frame_cb = frame;
    char *txt = read_file(path, NULL);
    if (!txt) {
        hal_log("cannot read script %s", path);
        return 2;
    }
    line_no = 0;
    pace = read_cps = 0; /* each script sets its own pace: on the console they run one after another */
    last_read = NULL;
    char *save = NULL;
    for (char *line = strtok_r(txt, "\n", &save); line; line = strtok_r(NULL, "\n", &save)) {
        line_no++;
        char *hash = strchr(line, '#');
        if (hash && (hash == line || hash[-1] == ' ')) *hash = 0;
        while (*line == ' ' || *line == '\t') line++;
        size_t len = strlen(line);
        while (len && (line[len - 1] == ' ' || line[len - 1] == '\r')) line[--len] = 0;
        if (!len) continue;
        char *arg = strchr(line, ' ');
        if (arg) *arg++ = 0;
        else arg = line + len;
        fail_msg[0] = 0;
        if (!run_line(line, arg)) {
            hal_log("FAIL %s:%d: %s %s -> %s", path, line_no, line, arg, fail_msg);
            free(txt);
            return 1;
        }
    }
    free(txt);
    hal_log("PASS %s", path);
    return 0;
}
