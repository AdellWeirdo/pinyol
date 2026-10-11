/* P01: compare the photo with the plan (dossier p.18). Native 480x320; papers in the top area,
 * controls below. Validation only on release/confirm, never while dragging. */
#include <math.h>
#include <stdlib.h>
#include <string.h>

#include "bp.h"

#define MOVE_PX 3
#define BTN_Y 282
#define BTN_H 34

static puzzle_state *P = &G.pz;

static int arr(const cJSON *a, int i) { return cJSON_GetArrayItem(a, i) ? cJSON_GetArrayItem(a, i)->valueint : 0; }

int p01_anchor_count(const cJSON *def) { return cJSON_GetArraySize(jget(def, "anchors")); }

/* Pure: which anchors of the rotated, placed photo land within tol of the plan's anchors. */
int p01_check(const cJSON *def, int x, int y, int rot) {
    const cJSON *size = jget(def, "trace_size"), *area = jget(def, "area"), *a;
    int w = arr(size, 0), h = arr(size, 1), tol = jint(def, "tol", 12), mask = 0, i = 0;
    cJSON_ArrayForEach(a, jget(def, "anchors")) {
        int u = arr(jget(a, "trace"), 0), v = arr(jget(a, "trace"), 1), ru, rv;
        switch (rot & 3) {
        case 0: ru = u; rv = v; break;
        case 1: ru = h - 1 - v; rv = u; break;
        case 2: ru = w - 1 - u; rv = h - 1 - v; break;
        default: ru = v; rv = w - 1 - u; break;
        }
        int dx = x + ru - (arr(area, 0) + arr(jget(a, "plan"), 0)), dy = y + rv - (arr(area, 1) + arr(jget(a, "plan"), 1));
        if (dx * dx + dy * dy <= tol * tol) mask |= 1 << i;
        i++;
    }
    return mask;
}

static void dims(int *rw, int *rh) {
    const cJSON *size = jget(P->def, "trace_size");
    *rw = (P->rot & 1) ? arr(size, 1) : arr(size, 0);
    *rh = (P->rot & 1) ? arr(size, 0) : arr(size, 1);
}

static void clamp_photo(void) {
    const cJSON *area = jget(P->def, "area");
    int rw, rh;
    dims(&rw, &rh);
    int cx = P->x + rw / 2, cy = P->y + rh / 2;
    int x0 = arr(area, 0), y0 = arr(area, 1), x1 = x0 + arr(area, 2), y1 = y0 + arr(area, 3);
    if (cx < x0) P->x += x0 - cx;
    if (cx > x1) P->x -= cx - x1;
    if (cy < y0) P->y += y0 - cy;
    if (cy > y1) P->y -= cy - y1;
}

static bool is_type(const cJSON *def, const char *t) { return def && jstr(def, "type") && !strcmp(jstr(def, "type"), t); }
static bool is_pattern(const cJSON *def) { return is_type(def, "pattern"); }

void puzzle_open(const char *id) {
    cJSON *def = jget(G.puzzles, id);
    if (!def) return;
    if (is_pattern(def)) { pattern_open(def); return; }
    if (is_type(def, "drill")) { drill_open(def); return; }
    if (is_type(def, "conduit")) { conduit_open(def); return; }
    if (is_type(def, "order")) { order_open(def); return; }
    if (!flag_get("item:IT_PHOTO") || !flag_get("item:IT_PLAN")) {
        dlg_say(G.pl.speaker, "Necesito la foto y el plano para compararlos.", NULL);
        return;
    }
    P->def = def;
    P->solved = flag_get("photo_plan_linked") != 0;
    const cJSON *sol = jget(def, "solution"), *start = jget(def, "trace_start");
    if (P->solved) {
        P->x = jint(sol, "x", 0);
        P->y = jint(sol, "y", 0);
        P->rot = jint(sol, "rot", 0);
    } else if (!flag_get("p01_opened")) {
        flag_set("p01_opened", 1);
        P->x = arr(start, 0);
        P->y = arr(start, 1);
        P->rot = arr(start, 2) & 3;
    }
    P->drag = P->moved = false;
    P->help = 0;
    P->msg = P->solved ? jstr(def, "solved_text") : jstr(def, "instruction");
    layer_push(L_PUZZLE);
}

static void check(void) {
    int n = p01_anchor_count(P->def), m = p01_check(P->def, P->x, P->y, P->rot);
    if (n && m == (1 << n) - 1) {
        const cJSON *sol = jget(P->def, "solution");
        P->x = jint(sol, "x", P->x); /* soft snap to the authored transform */
        P->y = jint(sol, "y", P->y);
        P->rot = jint(sol, "rot", P->rot);
        P->solved = true;
        P->msg = jstr(P->def, "solved_text");
        sound("solved");
        effects_run(jget(P->def, "do"));
        return;
    }
    const cJSON *partial = jget(P->def, "partial"), *a;
    P->msg = jstr(P->def, "instruction");
    int i = 0;
    cJSON_ArrayForEach(a, jget(P->def, "anchors")) {
        if ((m >> i++) & 1) {
            P->msg = jstr(partial, jstr(a, "id")) ? jstr(partial, jstr(a, "id")) : jstr(partial, "*");
            break;
        }
    }
}

static void rotate(void) {
    int rw, rh;
    dims(&rw, &rh);
    int cx = P->x + rw / 2, cy = P->y + rh / 2;
    P->rot = (P->rot + 1) & 3;
    dims(&rw, &rh);
    P->x = cx - rw / 2;
    P->y = cy - rh / 2;
    clamp_photo();
    check();
}

static void help(void) {
    int n = cJSON_GetArraySize(jget(P->def, "help"));
    if (P->help < n) P->help++;
    if (n && jas(jget(P->def, "help"), P->help - 1)) P->msg = jas(jget(P->def, "help"), P->help - 1);
}

static void close_puzzle(void) {
    cJSON *def = P->def;
    bool solved = P->solved;
    layer_remove(L_PUZZLE);
    if (solved && jstr(def, "after")) dlg_open(jstr(def, "after"));
}

static int button_at(int x, int y) {
    if (y < BTN_Y || y >= BTN_Y + BTN_H) return -1;
    if (x >= 16 && x < 152) return 0;
    if (x >= 168 && x < 304) return 1;
    if (x >= 328 && x < 464) return 2;
    return -1;
}

void puzzle_tick(void) {
    if (is_pattern(P->def)) { pattern_tick(); return; }
    if (is_type(P->def, "drill")) { drill_tick(); return; }
    if (is_type(P->def, "conduit")) { conduit_tick(); return; }
    if (is_type(P->def, "order")) { order_tick(); return; }
    uint16_t p = G.in.pressed, h = G.in.held;
    if (P->solved) {
        if ((p & (ACT_OK | ACT_BACK)) || G.in.tap) close_puzzle();
        return;
    }
    if (G.in.tap) {
        int b = button_at(G.in.px, G.in.py), rw, rh;
        dims(&rw, &rh);
        if (b == 0) rotate();
        else if (b == 1) help();
        else if (b == 2) { close_puzzle(); return; }
        else if (G.in.px >= P->x && G.in.px < P->x + rw && G.in.py >= P->y && G.in.py < P->y + rh) {
            P->drag = true;
            P->gx = G.in.px - P->x;
            P->gy = G.in.py - P->y;
        }
    }
    if (P->drag && G.in.touch) {
        P->x = G.in.px - P->gx;
        P->y = G.in.py - P->gy;
        clamp_photo();
    }
    if (P->drag && G.in.release) {
        P->drag = false;
        check();
    }
    int dx = !!(h & ACT_RIGHT) - !!(h & ACT_LEFT), dy = !!(h & ACT_DOWN) - !!(h & ACT_UP);
    if (dx || dy) {
        P->x += dx * MOVE_PX;
        P->y += dy * MOVE_PX;
        clamp_photo();
        P->moved = true;
    } else if (P->moved) { /* releasing the D-pad is the button equivalent of lifting the finger */
        P->moved = false;
        check();
    }
    if (p & ACT_OK) rotate();
    if (p & ACT_NEXT) help();
    if (p & ACT_BACK) close_puzzle();
}

static void thick_line(surface *s, int x0, int y0, int x1, int y1, uint16_t c) {
    int n = abs(x1 - x0) > abs(y1 - y0) ? abs(x1 - x0) : abs(y1 - y0);
    for (int i = 0; i <= n; i++) {
        int x = x0 + (n ? (x1 - x0) * i / n : 0), y = y0 + (n ? (y1 - y0) * i / n : 0);
        gfx_fill(s, x - 2, y - 2, 5, 5, c);
    }
}

static void paper(surface *s, int x, int y, int w, int h) {
    gfx_fill(s, x - 5, y - 5, w + 10, h + 10, C_PAPER);
    gfx_frame(s, x - 5, y - 5, w + 10, h + 10, C_INK);
}

/* Layout from the approved reference: photo card on the left, plan on the right, a translucent
 * tracing of the photo's landmarks that the player drags and turns over the plan. */
void puzzle_render(surface *s) {
    if (is_pattern(P->def)) { pattern_render(s); return; }
    if (is_type(P->def, "drill")) { drill_render(s); return; }
    if (is_type(P->def, "conduit")) { conduit_render(s); return; }
    if (is_type(P->def, "order")) { order_render(s); return; }
    const cJSON *area = jget(P->def, "area"), *card = jget(P->def, "photo_card");
    int ax = arr(area, 0), ay = arr(area, 1);
    const font *f = ui_font();
    gfx_fill(s, 0, 0, SCREEN_W, SCREEN_H, C_BROWN);
    const font *b = ui_bold();
    const char *title = jstr(P->def, "title");
    if (title) {
        int tw = font_width(b, title, -1) + 32;
        gfx_plate(s, (SCREEN_W - tw) / 2, 4, tw, b->h + 8, C_TERRA);
        font_draw(s, b, (SCREEN_W - tw) / 2 + 16, 8, title, -1, -1, C_PAPER);
    }
    if (card) {
        paper(s, arr(card, 0), arr(card, 1), arr(card, 2), arr(card, 3));
        gfx_blit(s, gfx_asset(jstr(P->def, "photo")), 0, arr(card, 0), arr(card, 1), 0, false);
    }
    paper(s, ax, ay, arr(area, 2), arr(area, 3));
    gfx_blit(s, gfx_asset(jstr(P->def, "plan")), 0, ax, ay, 0, false);
    if (P->help >= 3) { /* last hint points at the plan's fountain */
        const cJSON *a0 = cJSON_GetArrayItem(jget(P->def, "anchors"), 0);
        gfx_frame(s, ax + arr(jget(a0, "plan"), 0) - 9, ay + arr(jget(a0, "plan"), 1) - 9, 18, 18, C_TERRA);
    }
    int rw, rh;
    dims(&rw, &rh);
    gfx_blit(s, gfx_asset(jstr(P->def, "trace")), 0, P->x, P->y, P->rot, true);
    gfx_frame(s, P->x - 1, P->y - 1, rw + 2, rh + 2, P->drag ? C_TERRA : C_INK);
    if (P->solved) {
        const cJSON *st = jget(P->def, "street");
        for (int i = 1; i < cJSON_GetArraySize(st); i++) {
            const cJSON *a = cJSON_GetArrayItem(st, i - 1), *b = cJSON_GetArrayItem(st, i);
            thick_line(s, ax + arr(a, 0), ay + arr(a, 1), ax + arr(b, 0), ay + arr(b, 1), C_TERRA);
        }
    }
    int my = ay + arr(area, 3) + 10;
    gfx_panel(s, 16, my, SCREEN_W - 32, BTN_Y - my - 6);
    if (P->msg) {
        uint16_t ls[4], ll[4];
        int n = text_wrap(f, P->msg, SCREEN_W - 64, ls, ll, 2);
        int ty = my + (BTN_Y - my - 6 - n * (f->h + 2)) / 2;
        for (int i = 0; i < n; i++) font_draw(s, f, 32, ty + i * (f->h + 2), P->msg + ls[i], ll[i], -1, P->solved ? C_TERRA : C_INK);
    }
    const char *labels[3] = {"Girar", "Ayuda", "Volver"}, *keys[3] = {"A", "C", "B"};
    const int bx[3] = {16, 168, 328};
    for (int i = 0; i < 3; i++) {
        if (P->solved && i < 2) continue;
        gfx_plate(s, bx[i], BTN_Y, 136, BTN_H, C_PAPER);
        int r = b->h / 2 - 1, w = 2 * r + 8 + font_width(b, labels[i], -1), x = bx[i] + (136 - w) / 2, cy = BTN_Y + BTN_H / 2;
        gfx_disc(s, x + r, cy, r, C_INK);
        font_draw(s, b, x + r - font_width(b, keys[i], -1) / 2 + 1, cy - b->h / 2, keys[i], -1, -1, C_PAPER);
        font_draw(s, b, x + 2 * r + 8, cy - b->h / 2, labels[i], -1, -1, C_INK);
    }
}
