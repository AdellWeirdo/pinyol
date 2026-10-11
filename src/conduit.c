/* Conduit puzzles (Geumgye chapter 2, P21 «reconstruir el conductor»): elbow pieces on a small grid, each turned a
 * quarter clockwise with A, must carry the signal from an input side of one cell to an output side of another.
 * Elbows join two neighbouring sides: 0 N-E, 1 E-S, 2 S-W, 3 W-N (a turn adds one). The panel lights every piece
 * the signal reaches from the input, with a white line too so it reads without colour, and labels the joints of
 * the route with letters (A, B, C...), so the solution is explicit. No timer, no damage. Orientations live in
 * flags ("state_flags", value 1-4), so leaving with B or a power cut keeps them. After "hint_after" turns without
 * more continuity a hint appears; after "assist_after", C sets the right orientations. */
#include <stdlib.h>
#include <string.h>

#include "bp.h"

#define MAX_PIECES 4
#define CELL 56
#define BTN_Y 222

static const int DX[4] = {0, 1, 0, -1}, DY[4] = {-1, 0, 1, 0}; /* N E S W */

static struct {
    cJSON *def;
    int n, o[MAX_PIECES], sol[MAX_PIECES], sel, turns, best, since;
    bool solved, hinted;
} C;

static int side_of(const char *s) { return !s ? 0 : *s == 'N' ? 0 : *s == 'E' ? 1 : *s == 'S' ? 2 : 3; }
static const cJSON *piece(const cJSON *def, int i) { return cJSON_GetArrayItem(jget(def, "pieces"), i); }

static int piece_at(const cJSON *def, int x, int y) {
    for (int i = 0; i < cJSON_GetArraySize(jget(def, "pieces")) && i < MAX_PIECES; i++) {
        const cJSON *at = jget(piece(def, i), "at");
        if (jai(at, 0, -1) == x && jai(at, 1, -1) == y) return i;
    }
    return -1;
}

/* Follows the signal from the input: how many pieces it lights, and whether it leaves through the output.
 * path[] (optional) gets the pieces in order and exits[] the side each one sends it out of. */
int conduit_trace(const cJSON *def, const int *orient, bool *complete, int *path, int *exits) {
    const cJSON *in = jget(def, "in"), *out = jget(def, "out");
    int x = jai(jget(in, "at"), 0, 0), y = jai(jget(in, "at"), 1, 0), enter = side_of(jstr(in, "side")), lit = 0;
    *complete = false;
    for (int step = 0; step < MAX_PIECES; step++) {
        int i = piece_at(def, x, y);
        if (i < 0) break;
        int a = orient[i] & 3, b = (a + 1) & 3;
        if (enter != a && enter != b) break;
        int exit = enter == a ? b : a;
        if (path) path[lit] = i, exits[lit] = exit;
        lit++;
        if (x == jai(jget(out, "at"), 0, 0) && y == jai(jget(out, "at"), 1, 0) && exit == side_of(jstr(out, "side"))) {
            *complete = true;
            break;
        }
        x += DX[exit], y += DY[exit], enter = (exit + 2) & 3;
    }
    return lit;
}

static void save_state(void) {
    for (int i = 0; i < C.n; i++) {
        const char *f = jas(jget(C.def, "state_flags"), i);
        if (f) flag_set(f, C.o[i] + 1);
    }
}

void conduit_open(cJSON *def) {
    memset(&C, 0, sizeof C);
    C.def = def;
    C.n = cJSON_GetArraySize(jget(def, "pieces"));
    if (C.n > MAX_PIECES) C.n = MAX_PIECES;
    for (int i = 0; i < C.n; i++) {
        const char *f = jas(jget(def, "state_flags"), i);
        C.o[i] = f && flag_get(f) ? (flag_get(f) - 1) & 3 : jint(piece(def, i), "start", 0) & 3;
    }
    int total = 1, probe[MAX_PIECES];
    for (int i = 0; i < C.n; i++) total *= 4;
    for (int k = 0; k < total; k++) { /* the one set of orientations that completes the route */
        for (int i = 0, v = k; i < C.n; i++, v /= 4) probe[i] = v % 4;
        bool done;
        conduit_trace(def, probe, &done, NULL, NULL);
        if (done) { memcpy(C.sol, probe, sizeof probe); break; }
    }
    bool done;
    C.best = conduit_trace(def, C.o, &done, NULL, NULL);
    C.solved = done;
    G.pz.def = def;
    G.pz.msg = jstr(def, done ? "solved_text" : "instruction");
    layer_push(L_PUZZLE);
}

static bool assisted(void) { return C.since >= jint(C.def, "assist_after", 12); }

static void check(void) {
    bool done;
    int lit = conduit_trace(C.def, C.o, &done, NULL, NULL);
    if (lit > C.best) C.best = lit, C.since = 0;
    else C.since++;
    if (done) {
        C.solved = true;
        G.pz.msg = jstr(C.def, "solved_text");
        sound("solved");
        if (jstr(C.def, "sfx")) audio_sfx(jstr(C.def, "sfx"), 1);
    } else if (C.since == jint(C.def, "hint_after", 6)) {
        G.pz.msg = jstr(C.def, "hint_text");
    } else if (C.since == jint(C.def, "assist_after", 12)) {
        G.pz.msg = jstr(C.def, "assist_text");
    }
}

static void close_conduit(void) {
    cJSON *def = C.def;
    bool solved = C.solved;
    G.pz.def = NULL;
    layer_remove(L_PUZZLE);
    if (solved) effects_run(jget(def, "do"));
}

void conduit_tick(void) {
    uint16_t p = G.in.pressed;
    if (C.solved) {
        if (p & (ACT_OK | ACT_BACK)) close_conduit();
        return;
    }
    if (p & ACT_BACK) { close_conduit(); return; }
    if (p & (ACT_LEFT | ACT_UP)) C.sel = (C.sel + C.n - 1) % C.n, sound("move");
    if (p & (ACT_RIGHT | ACT_DOWN)) C.sel = (C.sel + 1) % C.n, sound("move");
    if (p & ACT_OK) {
        C.o[C.sel] = (C.o[C.sel] + 1) & 3;
        C.turns++;
        if (jstr(C.def, "sfx_turn")) audio_sfx(jstr(C.def, "sfx_turn"), 1);
        save_state();
        check();
    } else if ((p & ACT_NEXT) && assisted()) { /* the help: every piece to its place */
        memcpy(C.o, C.sol, sizeof C.o);
        save_state();
        check();
    }
}

/* ------------------------------------------------------------------ render */
static int grid_w(void) {
    int w = 1;
    for (int i = 0; i < C.n; i++) if (jai(jget(piece(C.def, i), "at"), 0, 0) + 1 > w) w = jai(jget(piece(C.def, i), "at"), 0, 0) + 1;
    return w;
}

static void cell_xy(int gx, int gy, int *x, int *y) {
    *x = SCREEN_W / 2 - grid_w() * (CELL + 8) / 2 + gx * (CELL + 8);
    *y = 64 + gy * (CELL + 8);
}

static void arm(surface *s, int cx, int cy, int side, bool lit) { /* a pipe from the centre to one side */
    int len = CELL / 2, w = 8;
    int x0 = side == 3 ? cx - len : cx - w / 2, y0 = side == 0 ? cy - len : cy - w / 2;
    int ww = side == 1 || side == 3 ? len + w / 2 : w, hh = side == 0 || side == 2 ? len + w / 2 : w;
    gfx_fill(s, x0, y0, ww, hh, lit ? C_OCHRE : C_BLUEGRAY);
    if (lit) gfx_fill(s, side == 1 || side == 3 ? x0 : cx - 1, side == 0 || side == 2 ? y0 : cy - 1,
                      side == 1 || side == 3 ? ww : 2, side == 0 || side == 2 ? hh : 2, C_WHITE); /* reads without colour */
}

static void joint(surface *s, int x, int y, char letter) { /* a lettered notch where two ends must meet */
    char t[2] = {letter, 0};
    const font *b = ui_bold();
    gfx_plate(s, x - 9, y - b->h / 2 - 3, 18, b->h + 6, C_INK);
    font_draw(s, b, x - font_width(b, t, -1) / 2, y - b->h / 2, t, -1, -1, C_PAPER);
}

static void edge_mid(int gx, int gy, int side, int *x, int *y) {
    int cx, cy;
    cell_xy(gx, gy, &cx, &cy);
    *x = cx + CELL / 2 + DX[side] * (CELL / 2 + 4);
    *y = cy + CELL / 2 + DY[side] * (CELL / 2 + 4);
}

static void end_plate(surface *s, const cJSON *end, bool lit, bool is_in) {
    int gx = jai(jget(end, "at"), 0, 0), gy = jai(jget(end, "at"), 1, 0), side = side_of(jstr(end, "side")), x, y;
    edge_mid(gx, gy, side, &x, &y);
    const char *lbl = jstr(end, "label") ? jstr(end, "label") : is_in ? "ENTRADA" : "SALIDA";
    const font *b = ui_bold();
    int w = font_width(b, lbl, -1) + 16, h = b->h + 8;
    int px = side == 3 ? x - 12 - w : side == 1 ? x + 12 : x - w / 2, py = side == 2 ? y + 12 : side == 0 ? y - 12 - h : y - h / 2;
    gfx_plate(s, px, py, w, h, lit ? C_OCHRE : C_PAPER);
    font_draw(s, b, px + 8, py + 4, lbl, -1, -1, C_INK);
}

void conduit_render(surface *s) {
    const font *f = ui_font(), *b = ui_bold();
    gfx_fill(s, 0, 0, SCREEN_W, SCREEN_H, C_INK);
    const char *title = jstr(C.def, "title");
    if (title) {
        int tw = font_width(b, title, -1) + 32;
        gfx_plate(s, (SCREEN_W - tw) / 2, 4, tw, b->h + 8, C_TERRA);
        font_draw(s, b, (SCREEN_W - tw) / 2 + 16, 8, title, -1, -1, C_PAPER);
    }
    bool done;
    int path[MAX_PIECES], exits[MAX_PIECES], lit = conduit_trace(C.def, C.o, &done, path, exits);
    for (int i = 0; i < C.n; i++) {
        const cJSON *at = jget(piece(C.def, i), "at");
        int x, y, on = 0;
        cell_xy(jai(at, 0, 0), jai(at, 1, 0), &x, &y);
        for (int k = 0; k < lit; k++) on |= path[k] == i;
        gfx_plate(s, x, y, CELL, CELL, C.sel == i && !C.solved ? C_PAPER_SEL : C_PAPER);
        if (C.sel == i && !C.solved) gfx_tri(s, x + CELL / 2 - 6, y - 14, 6, false, C_PAPER);
        arm(s, x + CELL / 2, y + CELL / 2, C.o[i], on);
        arm(s, x + CELL / 2, y + CELL / 2, (C.o[i] + 1) & 3, on);
    }
    end_plate(s, jget(C.def, "in"), lit > 0, true);
    end_plate(s, jget(C.def, "out"), done, false);
    bool sd; /* the route's joints, lettered in order: the input side, then each exit of the solution */
    int sp[MAX_PIECES], se[MAX_PIECES], sl = conduit_trace(C.def, C.sol, &sd, sp, se), jx, jy;
    const cJSON *in = jget(C.def, "in");
    edge_mid(jai(jget(in, "at"), 0, 0), jai(jget(in, "at"), 1, 0), side_of(jstr(in, "side")), &jx, &jy);
    joint(s, jx, jy, 'A');
    for (int k = 0; k < sl; k++) {
        const cJSON *at = jget(piece(C.def, sp[k]), "at");
        edge_mid(jai(at, 0, 0), jai(at, 1, 0), se[k], &jx, &jy);
        joint(s, jx, jy, (char)('B' + k));
    }
    int bx = 40;
    bx += button_hint(s, bx, BTN_Y + 6, "A", "Girar", C_PAPER) + 20;
    bx += button_hint(s, bx, BTN_Y + 6, "B", "Volver", C_PAPER) + 20;
    if (assisted() && !C.solved) button_hint(s, bx, BTN_Y + 6, "C", jstr(C.def, "assist_button") ? jstr(C.def, "assist_button") : "Mostrar", C_PAPER);
    gfx_panel(s, 16, 256, SCREEN_W - 32, 58);
    if (G.pz.msg) {
        uint16_t ls[3], ll[3];
        int n = text_wrap(f, G.pz.msg, SCREEN_W - 64, ls, ll, 2);
        for (int i = 0; i < n; i++) font_draw(s, f, 32, 264 + i * (f->h + 2), G.pz.msg + ls[i], ll[i], -1, C.solved ? C_TERRA : C_INK);
    }
}
