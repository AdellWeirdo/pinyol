/* Zones: character-grid layers, collision, Klaus movement, targeting, exits, rendering, BFS for scripts.
 * Everything visible is derived from flags each frame, so loading a save is just "set flags, enter zone". */
#include <math.h>
#include <stdlib.h>
#include <string.h>
#include <strings.h>

#include "bp.h"
#include "gfx_px.h"

#define SPEED (60.0f / TICK_HZ) /* 60 px/s = 1 px per tick (dossier p.28 proposed 48, "ajustar con prueba") */
#define REACH 20.0f             /* dossier p.05: interaction distance from the feet anchor */
#define MAX_DRAW 64

static zone_rt *Z = &G.zone;
static float cam_x, cam_y;
/* HD (a zone whose background has a <bg>_HD picture, twice its size): the world is drawn as always, but with the key
 * colour where the background would be; each strip draws the HD background first, shaded and tinted as the world
 * was, and the world doubled over it, its key left out (world_render_hd). Set once a frame by world_render. */
static struct { asset *bg; int shade; bool dusk; } hd;
/* Where the HD world is not the key: per world column, its runs of drawn pixels (start, length), found once a frame
 * (hd_spans) so that each strip copies only them; SPAN_FULL: too many, the strip goes down the whole column. */
#define SPANS 6
#define SPAN_FULL 255
static struct { uint8_t n[WORLD_W], run[WORLD_W][SPANS][2]; } *spans;

static void hd_spans(const surface *w) {
    if (!spans && !(spans = hal_realloc_slow(NULL, sizeof *spans))) return;
    static uint8_t start[WORLD_W];
    memset(spans->n, 0, sizeof spans->n);
    memset(start, SPAN_FULL, sizeof start); /* SPAN_FULL as a start: not in a run */
    for (int v = 0; v <= WORLD_H; v++) { /* row by row, as the world is kept; a last pass closes the open runs */
        const uint16_t *row = w->px + v * WORLD_W;
        for (int u = 0; u < WORLD_W; u++) {
            bool in = v < WORLD_H && row[u] != WORLD_KEY;
            if (in && start[u] == SPAN_FULL) start[u] = (uint8_t)v;
            else if (!in && start[u] != SPAN_FULL) {
                uint8_t *n = &spans->n[u];
                if (*n < SPANS) spans->run[u][*n][0] = start[u], spans->run[u][*n][1] = (uint8_t)(v - start[u]), (*n)++;
                else *n = SPAN_FULL;
                start[u] = SPAN_FULL;
            }
        }
    }
}

/* The world doubled over the strip, only its drawn runs (the rest is the HD background, already there). */
static void world_over(surface *s, const surface *w) {
    if (!spans) {
        gfx_upscale2x_key(w, s, WORLD_KEY);
        return;
    }
    const int ys = step_y(s), y0 = s->y0, y1 = s->y0 + s->h;
    for (int x = s->x0; x < s->x0 + s->w && x < 2 * WORLD_W; x++) {
        int u = x >> 1, n = spans->n[u];
        if (n == SPAN_FULL) {
            surface col = gfx_clip(s, x, y0, 1, s->h);
            gfx_upscale2x_key(w, &col, WORLD_KEY);
            continue;
        }
        for (int k = 0; k < n; k++) {
            int ya = 2 * spans->run[u][k][0], yb = 2 * (spans->run[u][k][0] + spans->run[u][k][1]);
            if (ya < y0) ya = y0;
            if (yb > y1) yb = y1;
            uint16_t *d = ya < yb ? at(s, x, ya) : NULL;
            for (int y = ya; y < yb; y++, d += ys) *d = stored(s, w->px[(y >> 1) * WORLD_W + u]);
        }
    }
}
static const cJSON *last_blocked;

/* ------------------------------------------------------------------ zone loading */
static void free_zone(void) {
    for (int i = 0; i < 3; i++) {
        free(Z->layer[i]);
        Z->layer[i] = NULL;
    }
    free(Z->solid);
    Z->solid = NULL;
}

static uint8_t *build_layer(const cJSON *grid) {
    if (!grid) return NULL;
    uint8_t *l = malloc((size_t)Z->tw * Z->th);
    memset(l, 0xFF, (size_t)Z->tw * Z->th);
    cJSON *legend = jget(G.tiles, "legend");
    int y = 0;
    const cJSON *row;
    cJSON_ArrayForEach(row, grid) {
        for (int x = 0; cJSON_IsString(row) && y < Z->th && x < Z->tw && row->valuestring[x]; x++) {
            char k[2] = {row->valuestring[x], 0};
            const char *name = jstr(legend, k);
            int idx = name ? content_tile_index(name) : -1;
            if (idx >= 0) l[y * Z->tw + x] = (uint8_t)idx;
        }
        y++;
    }
    return l;
}

static void anchor_of(const cJSON *o, float *x, float *y) {
    const cJSON *at = jget(o, "at");
    int tx = jai(at, 0, 0), ty = jai(at, 1, 0);
    const cJSON *pair;
    cJSON_ArrayForEach(pair, jget(o, "at_if")) if (cond_eval(cJSON_GetArrayItem(pair, 0))) {
        const cJSON *p = cJSON_GetArrayItem(pair, 1);
        tx = jai(p, 0, tx);
        ty = jai(p, 1, ty);
        break;
    }
    const cJSON *off = jget(o, "off");
    *x = tx * TILE + 8 + (off ? jai(off, 0, 0) : 0);
    *y = ty * TILE + 12 + (off ? jai(off, 1, 0) : 0);
    const char *id = jstr(o, "id");
    if (id && G.seq.prop[0] && !strcmp(id, G.seq.prop)) {
        *x += G.seq.pdx;
        *y += G.seq.pdy;
    }
}

static int prop_frame(const cJSON *p) {
    const char *id = jstr(p, "id");
    if (id && G.seq.fprop[0] && !strcmp(id, G.seq.fprop)) return G.seq.fframe;
    const cJSON *pair;
    cJSON_ArrayForEach(pair, jget(p, "frame_if")) if (cond_eval(cJSON_GetArrayItem(pair, 0))) return jai(pair, 1, 0);
    if (cJSON_IsTrue(jget(p, "anim"))) { /* looping prop (a lantern, a glowing crack) drawn in its own layer */
        const asset *a = gfx_asset(jstr(p, "sprite"));
        int fms = a->frame_ms > 0 ? a->frame_ms : 250;
        return (int)((G.anim_ms + jint(p, "phase", 0)) / fms) % (a->frames > 0 ? a->frames : 1);
    }
    return jint(p, "frame", 0);
}

static bool visible(const cJSON *o) { return cond_eval(jget(o, "if")); }

void world_safe_position(void) {
    const cJSON *s = jget(jget(Z->def, "spawns"), "safe");
    G.klaus.x = jai(s, 0, 0) * TILE + 8;
    G.klaus.y = jai(s, 1, 0) * TILE + 12;
}

static int dir_of(const char *s) {
    if (!s) return DIR_S;
    return s[0] == 'N' ? DIR_N : s[0] == 'E' ? DIR_E : (s[0] == 'W' || s[0] == 'O') ? DIR_W : DIR_S;
}

bool world_enter(const char *zone, const char *spawn) {
    cJSON *def = content_zone(zone);
    if (!def) {
        game_error("Falta el mapa %s. Tu partida guardada se conserva.", zone);
        return false;
    }
    int tw = jai(jget(def, "size"), 0, 0), th = jai(jget(def, "size"), 1, 0);
    if (tw < 1 || th < 1 || tw > 255 || th > 255) {
        game_error("El mapa %s no tiene un tamaño válido. Tu partida guardada se conserva.", zone);
        return false;
    }
    free_zone();
    Z->def = def;
    snprintf(Z->id, sizeof Z->id, "%s", zone);
    Z->tw = tw;
    Z->th = th;
    Z->exterior = cJSON_IsTrue(jget(def, "exterior"));
    const char *names[3] = {"floor", "wall_back", "front"};
    for (int i = 0; i < 3; i++) Z->layer[i] = build_layer(jget(def, names[i]));
    Z->solid = calloc((size_t)Z->tw * Z->th, 1);
    const char *solid = jstr(def, "solid") ? jstr(def, "solid") : "#";
    int y = 0;
    const cJSON *row;
    cJSON_ArrayForEach(row, jget(def, "floor")) {
        for (int x = 0; cJSON_IsString(row) && x < Z->tw && row->valuestring[x]; x++)
            if (strchr(solid, row->valuestring[x])) Z->solid[y * Z->tw + x] = 1;
        if (++y >= Z->th) break;
    }
    if (spawn) {
        const cJSON *s = jget(jget(def, "spawns"), spawn);
        if (!s) s = jget(jget(def, "spawns"), "safe");
        G.klaus.x = jai(s, 0, 0) * TILE + 8;
        G.klaus.y = jai(s, 1, 0) * TILE + 12;
        G.klaus.facing = dir_of(cJSON_IsString(cJSON_GetArrayItem(s, 2)) ? cJSON_GetArrayItem(s, 2)->valuestring : NULL);
    }
    G.klaus.moving = false;
    G.klaus.sink = 0;
    G.exit_guard = true;
    G.target = NULL;
    G.target_cycle = 0;
    last_blocked = NULL;
    flagf_set(1, "visited:%s%s", zone, "");
    music_zone_changed();
    effects_run(jget(def, "on_enter"));
    if (spawn && G.autosave_enabled && !layer_has(L_SEQ)) save_write("auto");
    if (spawn) G.banner_ms = 1800;
    return true;
}

/* ------------------------------------------------------------------ collision */
static bool hit(float ax, float ay, float aw, float ah, float bx, float by, float bw, float bh) {
    return ax < bx + bw && bx < ax + aw && ay < by + bh && by < ay + ah;
}

static bool foot_hit(const cJSON *o, const cJSON *foot, float bx, float by) {
    if (cJSON_GetArraySize(foot) < 4) return false;
    float x, y;
    anchor_of(o, &x, &y);
    return hit(bx, by, 10, 6, x + jai(foot, 0, 0), y + jai(foot, 1, 0),
               jai(foot, 2, 0), jai(foot, 3, 0));
}

bool world_collides_at(float x, float y) {
    float bx = x - 5, by = y - 4; /* 10x6 box at the feet, dossier p.07 */
    int tx0 = (int)floorf(bx / TILE), tx1 = (int)floorf((bx + 9.99f) / TILE);
    int ty0 = (int)floorf(by / TILE), ty1 = (int)floorf((by + 5.99f) / TILE);
    for (int ty = ty0; ty <= ty1; ty++)
        for (int tx = tx0; tx <= tx1; tx++)
            if (tx < 0 || ty < 0 || tx >= Z->tw || ty >= Z->th || Z->solid[ty * Z->tw + tx]) return true;
    const cJSON *o;
    cJSON_ArrayForEach(o, jget(Z->def, "blocks")) { /* furniture painted into the background, in px; */
        const cJSON *r = cJSON_IsObject(o) ? jget(o, "rect") : o; /* {"rect", "if"}: water that drains */
        if (cJSON_IsObject(o) && !cond_eval(jget(o, "if"))) continue;
        if (hit(bx, by, 10, 6, jai(r, 0, 0), jai(r, 1, 0), jai(r, 2, 0), jai(r, 3, 0))) return true;
    }
    cJSON_ArrayForEach(o, jget(Z->def, "props")) if (visible(o) && foot_hit(o, jget(o, "foot"), bx, by)) return true;
    static cJSON *npc_foot; /* wide enough that Klaus never overlaps a neighbour's body */
    if (!npc_foot) npc_foot = cJSON_Parse("[-8,-6,16,9]");
    cJSON_ArrayForEach(o, jget(Z->def, "npcs")) if (visible(o) && foot_hit(o, npc_foot, bx, by)) return true;
    return false;
}

bool world_box_free(float x, float y) { return !world_collides_at(x, y); }

static const cJSON *exit_at(float x, float y) {
    const cJSON *e;
    cJSON_ArrayForEach(e, jget(Z->def, "exits")) {
        const cJSON *r = jget(e, "rect");
        if (hit(x - 5, y - 4, 10, 6, jai(r, 0, 0) * TILE, jai(r, 1, 0) * TILE,
                jai(r, 2, 0) * TILE, jai(r, 3, 0) * TILE))
            return e;
    }
    return NULL;
}

bool world_on_exit(float x, float y) { return exit_at(x, y) != NULL; }

bool world_exit_rect(const char *to, int *x, int *y, int *w, int *h) {
    const cJSON *e;
    cJSON_ArrayForEach(e, jget(Z->def, "exits")) {
        if (!jstr(e, "to") || strcmp(jstr(e, "to"), to)) continue;
        const cJSON *r = jget(e, "rect");
        *x = jai(r, 0, 0);
        *y = jai(r, 1, 0);
        *w = jai(r, 2, 0);
        *h = jai(r, 3, 0);
        return true;
    }
    return false;
}

/* Moves the feet if possible. Returns true when an exit changed the zone. */
static bool step(float nx, float ny) {
    const cJSON *e = exit_at(nx, ny);
    if (e && !G.exit_guard && e != exit_at(G.klaus.x, G.klaus.y)) { /* entering, never trapped inside one */
        if (cond_eval(jget(e, "if")) && jstr(e, "to")) {
            char to[8], sp[32];
            snprintf(to, sizeof to, "%s", jstr(e, "to"));
            snprintf(sp, sizeof sp, "%s", jstr(e, "spawn") ? jstr(e, "spawn") : "safe");
            world_enter(to, sp);
            return true;
        }
        if (e != last_blocked) effects_run(jget(e, "else"));
        last_blocked = e;
        return false;
    }
    if (!world_collides_at(nx, ny)) {
        G.klaus.x = nx;
        G.klaus.y = ny;
    }
    return false;
}

/* ------------------------------------------------------------------ targeting */
typedef struct { const cJSON *o; bool npc; float x, y, score; } cand;

static int candidates(cand *out, int max) {
    int n = 0;
    const char *kinds[2] = {"hotspots", "npcs"};
    static const int fx[4] = {0, 1, 0, -1}, fy[4] = {-1, 0, 1, 0};
    for (int k = 0; k < 2; k++) {
        const cJSON *o;
        cJSON_ArrayForEach(o, jget(Z->def, kinds[k])) {
            if (n == max || !visible(o) || (!jget(o, "dlg") && !jget(o, "do"))) continue;
            float x, y;
            anchor_of(o, &x, &y);
            float dx = x - G.klaus.x, dy = y - G.klaus.y, d = sqrtf(dx * dx + dy * dy);
            if (d > jint(o, "reach", (int)REACH)) continue;
            bool facing = dx * fx[G.klaus.facing] + dy * fy[G.klaus.facing] > 0 || d < 4;
            out[n++] = (cand){o, k == 1, x, y, d + (facing ? 0 : 12)};
        }
    }
    for (int i = 1; i < n; i++) /* insertion sort by score */
        for (int j = i; j > 0 && out[j].score < out[j - 1].score; j--) {
            cand t = out[j];
            out[j] = out[j - 1];
            out[j - 1] = t;
        }
    return n;
}

void world_update_target(void) {
    cand c[16];
    int n = candidates(c, 16);
    G.target = NULL;
    if (!n) return;
    cand *t = &c[G.target_cycle % n];
    G.target = t->o;
    G.target_npc = t->npc;
    G.target_x = t->x;
    G.target_y = t->y;
}

const cJSON *world_find(const char *id, float *x, float *y, bool *is_npc) {
    const char *kinds[2] = {"hotspots", "npcs"};
    for (int k = 0; k < 2; k++) {
        const cJSON *o;
        cJSON_ArrayForEach(o, jget(Z->def, kinds[k])) {
            if (!visible(o) || !jstr(o, "id") || strcmp(jstr(o, "id"), id)) continue;
            anchor_of(o, x, y);
            if (is_npc) *is_npc = k == 1;
            return o;
        }
    }
    return NULL;
}

static void face_toward(float x, float y) {
    float dx = x - G.klaus.x, dy = y - G.klaus.y;
    if (fabsf(dx) > fabsf(dy)) G.klaus.facing = dx > 0 ? DIR_E : DIR_W;
    else G.klaus.facing = dy > 0 ? DIR_S : DIR_N;
}

static void interact(void) {
    face_toward(G.target_x, G.target_y);
    G.klaus.act_ms = 350;
    const cJSON *t = G.target;
    if (jstr(t, "dlg")) dlg_open(jstr(t, "dlg"));
    effects_run(jget(t, "do"));
}

void world_use_item(const char *item, bool show) {
    world_update_target();
    if (!G.target) {
        dlg_say(G.pl.speaker, show ? "No hay nadie a quien enseñárselo." : "Aquí no hay nada en lo que usarlo.", NULL);
        return;
    }
    face_toward(G.target_x, G.target_y);
    if (G.target_npc) {
        if (jstr(G.target, "dlg")) dlg_show(jstr(G.target, "dlg"), item);
        else dlg_say(G.pl.speaker, "No parece interesarle.", NULL);
        return;
    }
    if (show) {
        dlg_say(G.pl.speaker, "No hay nadie a quien enseñárselo.", NULL);
        return;
    }
    const cJSON *use = jget(G.target, "use");
    const char *r = jstr(use, item) ? jstr(use, item) : jstr(use, "*");
    G.using_item = item;
    if (r) dlg_open(r);
    else dlg_say(G.pl.speaker, "No sirve aquí.", NULL);
    if (!G.dlg.active) G.using_item = NULL;
}

/* ------------------------------------------------------------------ tick */
/* Footsteps on the walk cycle's contact frames (0 and 2), on the zone's surface ("steps"). */
void world_footsteps(bool moved) {
    static int last = -1;
    const asset *a = gfx_asset(G.pl.walk);
    int i = (int)(G.anim_ms / (a->frame_ms > 0 ? a->frame_ms : 125)) % 4;
    if (moved && i != last && !(i & 1)) audio_sfx(jstr(G.zone.def, "steps"), 0.5f);
    last = moved ? i : -1;
}

void world_tick(void) {
    klaus_state *k = &G.klaus;
    if (k->act_ms > 0) k->act_ms -= TICK_MS;
    uint16_t h = G.in.held, p = G.in.pressed;
    if (p & ACT_INV) { G.inv_menu = false; layer_push(L_INV); return; }
    if (p & ACT_NOTES) { layer_push(L_NOTES); return; }
    float dx = (float)(!!(h & ACT_RIGHT) - !!(h & ACT_LEFT)), dy = (float)(!!(h & ACT_DOWN) - !!(h & ACT_UP));
    k->moving = dx != 0 || dy != 0;
    if (k->moving) {
        if (dx && dy) {
            dx *= 0.70710678f;
            dy *= 0.70710678f;
            bool keep = (k->facing == DIR_E && dx > 0) || (k->facing == DIR_W && dx < 0) ||
                        (k->facing == DIR_S && dy > 0) || (k->facing == DIR_N && dy < 0);
            if (!keep) k->facing = dx > 0 ? DIR_E : DIR_W;
        } else {
            k->facing = dx > 0 ? DIR_E : dx < 0 ? DIR_W : dy > 0 ? DIR_S : DIR_N;
        }
        G.target_cycle = 0;
        float ox = k->x, oy = k->y;
        if (dx && step(k->x + dx * SPEED, k->y)) return;
        if (layer_top() != L_PLAY) return;
        if (dy && step(k->x, k->y + dy * SPEED)) return;
        if (layer_top() != L_PLAY) return;
        if (k->x == ox && k->y == oy && (!dx || !dy)) { /* grazing a corner: slide round it, up to 5 px */
            for (int d = 1; d <= 5; d++) {
                float sx = dy ? (float)d : 0, sy = dx ? (float)d : 0, px = dx ? 0 : 1, py = dy ? 0 : 1;
                if (world_box_free(k->x + dx * SPEED - sx, k->y + dy * SPEED - sy) && world_box_free(k->x - px, k->y - py)) {
                    k->x -= px;
                    k->y -= py;
                    break;
                }
                if (world_box_free(k->x + dx * SPEED + sx, k->y + dy * SPEED + sy) && world_box_free(k->x + px, k->y + py)) {
                    k->x += px;
                    k->y += py;
                    break;
                }
            }
        }
        if (!exit_at(k->x, k->y)) last_blocked = NULL;
        world_footsteps(k->x != ox || k->y != oy);
    } else {
        world_footsteps(false);
    }
    if (G.exit_guard && !exit_at(k->x, k->y)) G.exit_guard = false;
    if (p & ACT_NEXT) G.target_cycle++;
    world_update_target();
    if ((p & ACT_OK) && G.target) interact();
}

/* ------------------------------------------------------------------ BFS (scripts) */
static bool tile_ok(int tx, int ty, int gx, int gy) {
    if (tx < 0 || ty < 0 || tx >= Z->tw || ty >= Z->th) return false;
    if (tx == gx && ty == gy) return true;
    float x = tx * TILE + 8, y = ty * TILE + 12;
    /* demand a little clearance so a path never grazes a painted block's edge */
    return world_box_free(x, y) && world_box_free(x - 2, y - 2) && world_box_free(x + 2, y + 2) &&
           world_box_free(x - 2, y + 2) && world_box_free(x + 2, y - 2) && !exit_at(x, y);
}

int world_path(int gx, int gy, int *dirs, int max) {
    int n = Z->tw * Z->th, sx = (int)(G.klaus.x / TILE), sy = (int)(G.klaus.y / TILE);
    int *prev = malloc(sizeof(int) * n), *q = malloc(sizeof(int) * n), qh = 0, qt = 0;
    for (int i = 0; i < n; i++) prev[i] = -2;
    static const int ddx[4] = {0, 1, 0, -1}, ddy[4] = {-1, 0, 1, 0};
    prev[sy * Z->tw + sx] = -1;
    q[qt++] = sy * Z->tw + sx;
    int found = -1;
    while (qh < qt) {
        int c = q[qh++], cx = c % Z->tw, cy = c / Z->tw;
        if (cx == gx && cy == gy) { found = c; break; }
        for (int d = 0; d < 4; d++) {
            int nx = cx + ddx[d], ny = cy + ddy[d], ni = ny * Z->tw + nx;
            if (!tile_ok(nx, ny, gx, gy) || prev[ni] != -2) continue;
            prev[ni] = c;
            q[qt++] = ni;
        }
    }
    int len = -1;
    if (found >= 0) {
        int m = 0;
        for (int c = found; prev[c] >= 0; c = prev[c]) m++;
        len = m < max ? m : max;
        int i = m - 1; /* walk back from the goal; write only the first `len` steps from the start */
        for (int c = found; prev[c] >= 0; c = prev[c], i--) {
            int p = prev[c], d = c - p == 1 ? DIR_E : c - p == -1 ? DIR_W : c > p ? DIR_S : DIR_N;
            if (i < len) dirs[i] = d;
        }
    }
    free(prev);
    free(q);
    return len;
}

/* ------------------------------------------------------------------ render */
static void draw_tiles(surface *s, const uint8_t *layer) {
    if (!layer) return;
    asset *ts = gfx_asset("TS_ATLAS");
    int cols = ts->w / TILE, rows = ts->h / TILE;
    for (int ty = cam_y > 0 ? (int)cam_y / TILE : 0; ty <= ((int)cam_y + WORLD_H) / TILE && ty < Z->th; ty++)
        for (int tx = cam_x > 0 ? (int)cam_x / TILE : 0; tx <= ((int)cam_x + WORLD_W) / TILE && tx < Z->tw; tx++) {
            uint8_t t = layer[ty * Z->tw + tx];
            if (t == 0xFF) continue;
            int ox = tx * TILE - (int)cam_x, oy = ty * TILE - (int)cam_y;
            if (ts->missing || t >= cols * rows) {
                gfx_fill(s, ox, oy, TILE, TILE, (uint16_t)(t * 2731));
                continue;
            }
            int u0 = (t % cols) * TILE, v0 = (t / cols) * TILE;
            for (int v = 0; v < TILE; v++)
                for (int u = 0; u < TILE; u++) {
                    int dx = ox + u, dy = oy + v;
                    if (dx < 0 || dy < 0 || dx >= s->w || dy >= s->h || !gfx_opaque(ts, 0, u0 + u, v0 + v)) continue;
                    s->px[dy * s->w + dx] = ts->pixels[(v0 + v) * ts->w + u0 + u];
                }
        }
}

typedef struct { float y; const cJSON *o; int kind; } drawable; /* kind: 0 prop, 1 npc, 2 klaus */

static void draw_sprite(surface *s, const char *id, int frame, float x, float y) {
    asset *a = gfx_asset(id);
    gfx_blit(s, a, frame, (int)x - a->ax - (int)cam_x, (int)y - a->ay - (int)cam_y, 0, false);
}

/* "lift" moves only the drawing (a box on a table), never sorting, collision or targeting. */
static void draw_prop(surface *s, const cJSON *o, int frame) {
    float x, y;
    anchor_of(o, &x, &y);
    const cJSON *lift = jget(o, "lift");
    if (lift) {
        x += jai(lift, 0, 0);
        y += jai(lift, 1, 0);
    }
    draw_sprite(s, jstr(o, "sprite"), frame, x, y);
}

static int anim_frame(const asset *a, int dirs, int dir, float t_ms, int frame_ms) {
    int fpd = a->frames / dirs > 0 ? a->frames / dirs : 1;
    if (dirs == 1) dir = 0;
    int i = frame_ms > 0 ? (int)(t_ms / frame_ms) % fpd : 0;
    return dir * fpd + i;
}

/* The bag choice (Options): Klaus's sprites and portrait have a _B twin with the crossbody bag.
 * A missing twin falls back to the backpack art, so a game folder without them still works. */
const char *klaus_variant(const char *id) {
    static char buf[40];
    if (!G.bag || !id || (strncmp(id, G.pl.prefix, strlen(G.pl.prefix)) && strcmp(id, G.pl.portrait))) return id;
    snprintf(buf, sizeof buf, "%s_B", id);
    return gfx_asset(buf)->missing ? id : buf;
}

static void draw_klaus(surface *s) {
    klaus_state *k = &G.klaus;
    const player_ids *p = &G.pl;
    const char *anim = k->anim ? k->anim : layer_has(L_LISTEN) ? p->listen : k->act_ms > 0 ? p->interact
                                         : k->moving ? p->walk : p->idle;
    asset *a = gfx_asset(klaus_variant(anim));
    int frame;
    if (!strcmp(anim, p->listen)) frame = k->facing * 2 + (G.lis.t > 300); /* hold the pose, no flicker */
    else if (!strcmp(anim, p->interact)) frame = k->facing * 2 + (k->act_ms < 175);
    else frame = anim_frame(a, strcmp(anim, p->descend) ? 4 : 1, k->facing, G.anim_ms, a->frame_ms > 0 ? a->frame_ms : 600);
    if (k->sink > 0) { /* going down: the feet disappear below the step edge */
        int rows = a->ay + 1 - (int)k->sink;
        gfx_blit_rows(s, a, frame, (int)k->x - a->ax - (int)cam_x, (int)k->y - a->ay - (int)cam_y + (int)k->sink, rows);
        return;
    }
    draw_sprite(s, anim, frame, k->x, k->y);
}

static void draw_npc(surface *s, const cJSON *o) {
    float x, y;
    anchor_of(o, &x, &y);
    int dir = dir_of(jstr(o, "facing"));
    float dx = G.klaus.x - x, dy = G.klaus.y - y;
    if (dx * dx + dy * dy < 48 * 48) dir = fabsf(dx) > fabsf(dy) ? (dx > 0 ? DIR_E : DIR_W) : (dy > 0 ? DIR_S : DIR_N);
    int frame = dir * 2 + ((int)(G.anim_ms / 600) % 2);
    const char *id = jstr(o, "id");
    if (id && G.seq.prop[0] && !strcmp(id, G.seq.prop) && (G.seq.pdx || G.seq.pdy)) { /* walked by a sequence */
        char walk[40];
        snprintf(walk, sizeof walk, "%s_WALK", jstr(o, "sprite") ? jstr(o, "sprite") : "");
        asset *a = gfx_asset_opt(walk);
        if (!a->missing) { /* the offset shrinks towards 0: they move against its sign */
            float ox = G.seq.pdx, oy = G.seq.pdy;
            int d = fabsf(ox) > fabsf(oy) ? (ox < 0 ? DIR_E : DIR_W) : (oy < 0 ? DIR_S : DIR_N), fpd = a->frames / 4 > 0 ? a->frames / 4 : 1;
            draw_sprite(s, walk, d * fpd + (int)(G.anim_ms / 125) % fpd, x, y);
            return;
        }
    }
    bool talking = id && G.dlg.active && !strcasecmp(id, G.dlg.speaker);
    const cJSON *pose;
    if (!talking) cJSON_ArrayForEach(pose, jget(o, "pose_if")) if (cond_eval(cJSON_GetArrayItem(pose, 0))) {
        const char *pid = jas(pose, 1); /* [cond, sprite]: working, on guard, pointing; looped, one view */
        asset *a = gfx_asset(pid);
        draw_sprite(s, pid, (int)(G.anim_ms / (a->frame_ms > 0 ? a->frame_ms : 400)) % (a->frames > 0 ? a->frames : 1), x, y);
        return;
    }
    if (dir == DIR_S && talking) /* talking: alternate the gesture */
        frame = ((int)(G.anim_ms / 450) % 2) ? 8 : DIR_S * 2;
    draw_sprite(s, jstr(o, "sprite"), frame, x, y);
}

static void draw_props(surface *s, const char *layer) {
    const cJSON *o;
    cJSON_ArrayForEach(o, jget(Z->def, "props")) {
        const char *l = jstr(o, "layer") ? jstr(o, "layer") : "";
        if (strcmp(l, layer) || !visible(o)) continue; /* its condition only in its own pass: once a frame */
        draw_prop(s, o, prop_frame(o));
    }
}

void world_render(surface *s) {
    if (!Z->def) return;
    cam_x = G.klaus.x - WORLD_W / 2 + G.seq.cam_x;
    cam_y = G.klaus.y - 16 - WORLD_H / 2 + G.seq.cam_y;
    float mw = Z->tw * TILE - WORLD_W, mh = Z->th * TILE - WORLD_H;
    cam_x = mw <= 0 ? mw / 2 : cam_x < 0 ? 0 : cam_x > mw ? mw : cam_x;
    cam_y = mh <= 0 ? mh / 2 : cam_y < 0 ? 0 : cam_y > mh ? mh : cam_y;
    cam_x = floorf(cam_x);
    cam_y = floorf(cam_y);
    const char *bg_id = jstr(Z->def, "bg");
    asset *bg = bg_id ? gfx_asset(bg_id) : NULL;
    char hd_id[40];
    snprintf(hd_id, sizeof hd_id, "%s_HD", bg_id ? bg_id : "");
    hd.bg = bg && !bg->missing ? gfx_asset_opt(hd_id) : NULL;
    if (hd.bg && hd.bg->missing) hd.bg = NULL;
    hd.shade = 0, hd.dusk = false;
    gfx_fill(s, 0, 0, s->w, s->h, hd.bg ? WORLD_KEY : C_INK);
    if (hd.bg) {
    } else if (bg && !bg->missing) { /* painted background (approved art); tiles stay as the fallback */
        gfx_blit(s, bg, 0, -(int)cam_x, -(int)cam_y, 0, false);
    } else {
        draw_tiles(s, Z->layer[0]);
        draw_tiles(s, Z->layer[1]);
    }
    draw_props(s, "low");

    drawable list[MAX_DRAW];
    int n = 0;
    const cJSON *o;
    cJSON_ArrayForEach(o, jget(Z->def, "props")) {
        if (n < MAX_DRAW - 1 && visible(o) && !jstr(o, "layer")) {
            float x, y;
            anchor_of(o, &x, &y);
            list[n++] = (drawable){y, o, 0};
        }
    }
    cJSON_ArrayForEach(o, jget(Z->def, "npcs")) {
        if (n < MAX_DRAW - 1 && visible(o)) {
            float x, y;
            anchor_of(o, &x, &y);
            list[n++] = (drawable){y, o, 1};
        }
    }
    list[n++] = (drawable){G.klaus.y, NULL, 2};
    for (int i = 1; i < n; i++) /* Y-sort by feet */
        for (int j = i; j > 0 && list[j].y < list[j - 1].y; j--) {
            drawable t = list[j];
            list[j] = list[j - 1];
            list[j - 1] = t;
        }
    for (int i = 0; i < n; i++) {
        if (list[i].kind == 2) { if (!cJSON_IsTrue(jget(Z->def, "no_player"))) draw_klaus(s); } /* inside the mecha */
        else if (list[i].kind == 1) draw_npc(s, list[i].o);
        else draw_prop(s, list[i].o, prop_frame(list[i].o));
    }
    if (bg && !bg->missing) { /* painted things Klaus can walk behind: redraw them over him */
        cJSON_ArrayForEach(o, jget(Z->def, "occluders")) {
            int ox = jai(o, 0, 0), oy = jai(o, 1, 0), ow = jai(o, 2, 0), oh = jai(o, 3, 0);
            if (G.klaus.y >= oy + oh || G.klaus.x + 12 < ox || G.klaus.x - 12 > ox + ow || G.klaus.y - 32 > oy + oh) continue;
            for (int v = oy < 0 ? 0 : oy; v < oy + oh && v < bg->h; v++)
                for (int u = ox < 0 ? 0 : ox; u < ox + ow && u < bg->w; u++) {
                    int dx = u - (int)cam_x, dy = v - (int)cam_y;
                    if (dx >= 0 && dy >= 0 && dx < s->w && dy < s->h) s->px[dy * s->w + dx] = hd.bg ? WORLD_KEY : bg->pixels[v * bg->w + u];
                }
        }
    }
    draw_props(s, "top"); /* small things lying on painted furniture */
    if (jget(Z->def, "foreground")) { /* roofs, canopies, front walls: always in front of characters */
        char fg_id[16];
        snprintf(fg_id, sizeof fg_id, "FG_%s", Z->id);
        asset *fg = gfx_asset(fg_id);
        if (!fg->missing) gfx_blit(s, fg, 0, -(int)cam_x, -(int)cam_y, 0, false);
    }
    draw_tiles(s, Z->layer[2]);
    draw_props(s, "front");
    cJSON_ArrayForEach(o, jget(Z->def, "shade")) if (cond_eval(cJSON_GetArrayItem(o, 0))) { /* [[cond, n]]: halve the light n times */
        for (int k = jai(o, 1, 1); k > 0; k--) {
            if (hd.bg) gfx_shade_except(s, WORLD_KEY), hd.shade++; /* the HD background is darkened on the strips */
            else gfx_shade(s, 0, 0, s->w, s->h);
        }
        break;
    }
    cJSON_ArrayForEach(o, jget(Z->def, "fx")) { /* ambient loops, phase-shifted per entry */
        if (!visible(o)) continue;
        asset *a = gfx_asset(jstr(o, "sprite"));
        int fms = a->frame_ms > 0 ? a->frame_ms : 250;
        draw_prop(s, o, (int)((G.anim_ms + jint(o, "phase", 0)) / fms) % a->frames);
    }
    draw_props(s, "lit"); /* what a light picks out of the shade, and full-screen memories */
    if (Z->exterior && flag_get("time_segment") == 1) {
        if (hd.bg) gfx_tint_dusk_except(s, WORLD_KEY), hd.dusk = true;
        else gfx_tint_dusk(s);
    }
    if (hd.bg) hd_spans(s);
}

typedef struct { surface *s; const surface *world; } hd_job;

static void hd_half(int part, void *ctx) { /* half of the window's columns, on one core each: they only read */
    const hd_job *j = ctx;
    int w0 = j->s->w / 2, x = -2 * (int)cam_x, y = -2 * (int)cam_y;
    surface s = gfx_clip(j->s, j->s->x0 + (part ? w0 : 0), j->s->y0, part ? j->s->w - w0 : w0, j->s->h);
    if (s.w <= 0 || s.h <= 0) return;
    if (x > 0 || y > 0 || x + hd.bg->w < SCREEN_W || y + hd.bg->h < SCREEN_H) { /* (the ink around: shaded too) */
        gfx_fill(&s, 0, 0, SCREEN_W, SCREEN_H, C_INK);
        for (int k = 0; k < hd.shade; k++) gfx_shade(&s, 0, 0, SCREEN_W, SCREEN_H);
        if (hd.dusk) gfx_tint_dusk(&s);
    }
    gfx_blit_lit(&s, hd.bg, x, y, hd.shade, hd.dusk);
    world_over(&s, j->world);
}

bool world_render_hd(surface *s, const surface *world) {
    if (!hd.bg || layer_top() == L_TITLE) return false;
    hd_job j = {s, world};
    hal_parallel(hd_half, &j);
    return true;
}

/* HUD over the world: location sign, arrival card, pointer over the target and the "A" action prompt. */
/* The first objective whose condition holds, looked up once a frame: a frame drawn as panel strips calls the marker
 * once per strip, and a game can have dozens of objectives. */
static const cJSON *current_objective(void) {
    if (G.objective_at != G.draws) {
        G.objective_at = G.draws;
        G.objective = NULL;
        const cJSON *ob;
        cJSON_ArrayForEach(ob, jget(G.game, "objectives")) if (cond_eval(jget(ob, "if"))) {
            G.objective = ob;
            break;
        }
    }
    return G.objective;
}

void world_render_marker(surface *s) {
    if (layer_top() != L_PLAY || !Z->def) return;
    const font *f = ui_font(), *b = ui_bold();
    const char *zname = jstr(Z->def, "name");
    if (zname && G.banner_ms <= 0) { /* small location sign, top-left; not under the arrival card (same name) */
        int w = font_width(b, zname, -1) + 24;
        gfx_plate(s, 8, 8, w, b->h + 10, C_PAPER);
        font_draw(s, b, 20, 13, zname, -1, -1, C_INK);
    }
    const cJSON *ob = G.banner_ms <= 0 && G.toast_ms <= 0 ? current_objective() : NULL, *ck;
    const char *t = jstr(ob, "text");
    if (t && *t) { /* game.json "objectives": the current one, under the sign; it steps aside for the arrival card and notes */
        int nck = cJSON_GetArraySize(jget(ob, "checks")), tw = font_width(f, t, -1), y = 8 + b->h + 16, row = f->h + 12;
        bool one_row = tw + 40 + nck * 40 <= SCREEN_W - 16; /* else the checklist goes under the text */
        int w = one_row ? tw + 40 + nck * 40 : (tw + 40 > nck * 40 + 36 ? tw + 40 : nck * 40 + 36);
        gfx_plate(s, 8, y, w, one_row || !nck ? row : row + 22, C_PAPER);
        gfx_fill(s, 18, y + 5, 10, f->h + 2, C_TERRA); /* the objective's "!" mark */
        gfx_fill(s, 22, y + 8, 2, f->h - 6, C_PAPER);
        gfx_fill(s, 22, y + f->h + 1, 2, 2, C_PAPER);
        font_draw(s, f, 36, y + 6, t, -1, -1, C_INK);
        int x = one_row ? 36 + tw + 10 : 36, cy = one_row ? y : y + row - 6;
        cJSON_ArrayForEach(ck, jget(ob, "checks")) { /* small checklist: icon + box, ticked by its flag */
            asset *ic = gfx_asset(jstr(ck, "icon"));
            if (!ic->missing) gfx_blit(s, ic, 0, x, cy + (row - ic->h) / 2, 0, false);
            gfx_frame(s, x + 18, cy + (row - 12) / 2, 12, 12, C_INK);
            if (cond_eval(jget(ck, "if"))) {
                gfx_fill(s, x + 20, cy + (row - 12) / 2 + 6, 3, 4, C_GREEN);
                gfx_fill(s, x + 23, cy + (row - 12) / 2 + 2, 3, 8, C_GREEN);
            }
            x += 40;
        }
    }
    if (zname && G.banner_ms > 0) { /* arrival card: the place name, centred, with ink rules */
        const font *bl = &G.bold_l;
        int tw = font_width(bl, zname, -1), w = tw + 96, h = bl->h + 24, x = (SCREEN_W - w) / 2, y = 54;
        gfx_panel(s, x, y, w, h);
        font_draw(s, bl, x + 48, y + 12, zname, -1, -1, C_INK);
        gfx_fill(s, x + 14, y + h / 2, 26, 2, C_TERRA);
        gfx_fill(s, x + w - 40, y + h / 2, 26, 2, C_TERRA);
    }
    if (!G.target) return;
    /* above a person's head (feet anchor + ~30 px of sprite), never over their face; objects keep it low */
    int x = (int)((G.target_x - cam_x) * 2), y = (int)((G.target_y - cam_y) * 2) - (G.target_npc ? 70 : 40);
    int bob = ((int)G.anim_ms / 250) % 2 * 2;
    gfx_tri(s, x - 7, y + bob - 1, 8, false, C_INK); /* outlined pointer */
    gfx_tri(s, x - 5, y + bob, 6, false, C_PAPER);
    const char *verb = jstr(G.target, "verb") ? jstr(G.target, "verb") : G.target_npc ? "Hablar" : "Examinar";
    const char *name = jstr(G.target, "name");
    int r = b->h / 2 - 1, vw = font_width(b, verb, -1), nw = name ? font_width(f, name, -1) + 12 : 0;
    int w = 14 + 2 * r + 8 + vw + nw + 16, h = b->h + 12, px = (SCREEN_W - w) / 2, py = SCREEN_H - h - 10;
    gfx_plate(s, px, py, w, h, C_PAPER);
    gfx_disc(s, px + 14 + r, py + h / 2, r, C_INK);
    font_draw(s, b, px + 14 + r - font_width(b, "A", -1) / 2 + 1, py + 6, "A", -1, -1, C_PAPER);
    font_draw(s, b, px + 14 + 2 * r + 8, py + 6, verb, -1, -1, C_INK);
    if (name) font_draw(s, f, px + 14 + 2 * r + 8 + vw + 12, py + 6, name, -1, -1, C_BROWN);
}
