/* Game state machine as a layer stack: only the top layer receives input each tick, so a key that
 * opened or closed something can never also pick an option in the layer that appears next. */
#include <stdlib.h>
#include <string.h>

#include "bp.h"
#include "compat.h"

game G;

static bool is_menu(layer_id l) { return l == L_INV || l == L_NOTES || l == L_PAUSE; }

void layer_push(layer_id l) {
    if (G.nstack < 16) G.stack[G.nstack++] = l;
    if (is_menu(l)) sound("open");
}

void layer_remove(layer_id l) {
    for (int i = G.nstack - 1; i >= 0; i--)
        if (G.stack[i] == l) {
            if (is_menu(l)) sound("back");
            memmove(&G.stack[i], &G.stack[i + 1], sizeof(layer_id) * (G.nstack - i - 1));
            G.nstack--;
            return;
        }
}

bool layer_has(layer_id l) {
    for (int i = 0; i < G.nstack; i++)
        if (G.stack[i] == l) return true;
    return false;
}

layer_id layer_top(void) { return G.nstack ? G.stack[G.nstack - 1] : L_TITLE; }

void layers_reset(layer_id base) {
    arena_free(); /* a fight never survives a reset of the screen stack */
    G.nstack = 0;
    G.dlg.active = false;
    G.seq.steps = NULL;
    G.seq.prop[0] = G.seq.fprop[0] = 0;
    G.seq.fade = G.seq.cam_x = G.seq.cam_y = 0;
    G.lis.def = NULL;
    G.klaus.anim = NULL;
    G.menu_sel = 0;
    audio_pause(false);
    audio_master((float)G.volume / VOLUME_MAX, 300);
    music_zone_changed();
    if (base == L_TITLE) G.can_continue = save_newest() != NULL;
    if (base == L_END) {
        const char *slot = chapter_def(0) ? jstr(chapter_def(chapter_current()), "load_slot") : "prefinal";
        G.can_load_prefinal = slot && save_peek(slot, NULL); /* each chapter names its own checkpoint, if any */
    }
    layer_push(base);
}

const font *ui_font(void) { return G.large_text ? &G.font_l : &G.font; }
const font *ui_bold(void) { return G.large_text ? &G.bold_l : &G.bold; }

void text_center(surface *s, const font *f, int cx, int y, const char *t, uint16_t col) {
    font_draw(s, f, cx - font_width(f, t, -1) / 2, y, t, -1, -1, col);
}

bool game_quit_requested(void) { return G.quit; }

bool game_init(const bp_config *cfg) {
    game_shutdown();
    G.cfg = *cfg;
    snprintf(G.game_dir, sizeof G.game_dir, "%s", cfg->game_dir);
    if (cfg->save_dir) snprintf(G.save_dir, sizeof G.save_dir, "%s", cfg->save_dir);
    else snprintf(G.save_dir, sizeof G.save_dir, "%s/saves", cfg->game_dir);
    mkdir(G.save_dir, 0755);
    bool ok = content_load();
    char path[384];
    struct { font *f; const char *file; } fonts[] = {
        {&G.font, "FONT_MAIN"}, {&G.font_l, "FONT_MAIN_L"}, {&G.bold, "FONT_BOLD"}, {&G.bold_l, "FONT_BOLD_L"}};
    for (int i = 0; i < 4; i++) {
        snprintf(path, sizeof path, "%s/fonts/%s.fnt", G.game_dir, fonts[i].file);
        ok = font_load(fonts[i].f, path) && ok;
    }
    settings_load();
    flags_reset();
    const char *newest = save_newest(); /* keep seq growing across reboots so "Continuar" picks the latest */
    if (newest) save_peek(newest, &G.save_seq);
    G.autosave_enabled = true;
    music_reset();
    layers_reset(L_TITLE);
    if (!cfg->no_splash) splash_start(); /* POWERED BY PINYOL first (splash.c): _init runs after it */
    if (G.v2) v2_load(); /* a script error shows on screen (and fails --validate); the folder still opens */
    if (!ok) hal_log("game folder %s is incomplete", G.game_dir);
    return ok && G.font.bits && G.font_l.bits && G.bold.bits && G.bold_l.bits;
}

void game_shutdown(void) {
    v2_free();
    arena_free();
    audio_reset();
    studio_fx_free();
    gfx_reset();
    content_free();
    free(G.font.bits);
    free(G.font_l.bits);
    free(G.bold.bits);
    free(G.bold_l.bits);
    free(G.zone.layer[0]);
    free(G.zone.layer[1]);
    free(G.zone.layer[2]);
    free(G.zone.solid);
    memset(&G, 0, sizeof G);
}

static void reset_run(void) {
    flags_reset();
    memset(&G.klaus, 0, sizeof G.klaus);
    memset(&G.pz, 0, sizeof G.pz);
    G.target = NULL;
    G.using_item = NULL;
    G.inv_sel = G.inv_sub = G.notes_sel = 0; /* a new run starts with fresh cursors, not the last run's */
    ui_toast_clear();
    G.anim_ms = 0;
}

void game_new(void) {
    if (G.v2) {
        v2_load();
        return;
    }
    reset_run();
    layers_reset(L_PLAY);
    const cJSON *st = jget(G.game, "start");
    if (!world_enter(jstr(st, "zone") ? jstr(st, "zone") : "Z01", jstr(st, "spawn") ? jstr(st, "spawn") : "safe")) return;
    if (jstr(st, "seq")) seq_start(jstr(st, "seq"));
    else if (jstr(st, "dlg")) dlg_open(jstr(st, "dlg"));
}

bool game_continue(const char *slot) {
    if (!slot) return false;
    reset_run();
    layers_reset(L_PLAY);
    if (!save_load(slot)) {
        game_error("La partida guardada (%s) está dañada.", slot);
        return false;
    }
    if (layer_top() == L_ERROR) return false;
    if (chapter_done(chapter_current())) layers_reset(L_END); /* finished chapter: next one, title or reload */
    return true;
}

/* ------------------------------------------------------------------ chapters (game.json "chapters")
 * Each chapter: title, "started" (condition; chapter 0 always is), "done" (condition), "end_text" and,
 * from the second one, "start": {do, zone, spawn, seq}. The same save carries on across chapters. */
const cJSON *chapter_def(int i) { return i < 0 ? NULL : cJSON_GetArrayItem(jget(G.game, "chapters"), i); }

int chapter_current(void) {
    int cur = 0;
    for (int i = 1; chapter_def(i); i++)
        if (jget(chapter_def(i), "started") && cond_eval(jget(chapter_def(i), "started"))) cur = i;
    return cur;
}

bool chapter_done(int i) {
    const cJSON *d = jget(chapter_def(i), "done");
    return d ? cond_eval(d) : flag_get("first_descent_complete") != 0; /* no chapters: C1 alone */
}

void chapter_begin(int i) {
    const cJSON *st = jget(chapter_def(i), "start");
    if (!st) return;
    layers_reset(L_PLAY);
    effects_run(jget(st, "do"));
    if (!world_enter(jstr(st, "zone") ? jstr(st, "zone") : "Z01", jstr(st, "spawn") ? jstr(st, "spawn") : "safe")) return;
    save_write("auto"); /* checkpoint A: the new chapter at its first step */
    if (jstr(st, "seq")) seq_start(jstr(st, "seq"));
}

void game_to_title(void) {
    reset_run();
    layers_reset(L_TITLE);
    audio_voice_stop(200);
}

/* Cursor and confirm clicks in menus and dialogue choices (open/back come from layer_push/remove). */
static void menu_sounds(layer_id top) {
    bool menu = top == L_TITLE || top == L_END || is_menu(top) || (top == L_DLG && G.dlg.choosing);
    if (!menu) return;
    if (G.in.pressed & ACT_OK) sound("ok");
    else if (G.in.pressed & (ACT_UP | ACT_DOWN | ACT_LEFT | ACT_RIGHT)) sound("move");
}

void game_tick(const hal_input *in) {
    G.in.pressed = in->held & ~G.in.held;
    /* an adventure with nothing in its bag pauses on MENU; a Lua game reads MENU itself (btnp("menu")) */
    if (!G.v2 && (G.in.pressed & ACT_INV) && !content_has_bag()) G.in.pressed = (G.in.pressed & ~ACT_INV) | ACT_PAUSE;
    G.in.held = in->held;
    int px = in->px, py = in->py;
    bool touch = in->touch;
    if (G.v2 && v2_dual()) { /* two screens: the bottom's own pixels; a touch off it is none */
        px -= DUAL_X(1), py -= DUAL_Y;
        if (px < 0 || py < 0 || px >= WORLD_W || py >= WORLD_H) touch = false;
    }
    G.in.tap = touch && !G.in.touch;
    G.in.release = !touch && G.in.touch;
    G.in.touch = touch;
    G.in.px = px;
    G.in.py = py;
    if (in->held & ACT_QUIT) G.quit = true;
    if (splash_on()) { /* the careta's ticks: the game's begin after it (it cannot be skipped: no button reaches it) */
        splash_tick();
        return;
    }
    G.ticks++;
    if (G.v2) {
        v2_tick();
        return;
    }

    layer_id top = layer_top();
    if (top != L_PAUSE) {
        G.anim_ms += TICK_MS;
        ui_toast_tick();
        if (G.banner_ms > 0 && top == L_PLAY) G.banner_ms -= TICK_MS;
    }
    bool in_game = top != L_TITLE && top != L_END && top != L_ERROR;
    if (in_game && top != L_PAUSE && (G.in.pressed & ACT_PAUSE)) {
        layer_push(L_PAUSE);
        G.menu_sel = 0;
        music_tick(); /* the open click plays before the mixer pauses */
        audio_pause(true);
        return;
    }
    menu_sounds(top);
    if (top != L_PAUSE && (G.in.pressed & ACT_NEXT) && seq_skippable()) { /* C skips a skippable scene */
        seq_skip();
        music_tick();
        return;
    }
    switch (top) {
    case L_TITLE: title_tick(); break;
    case L_PLAY:
        hud_tick();
        if (layer_top() == L_PLAY) world_tick();
        break;
    case L_DLG: dlg_tick(); break;
    case L_INV: inv_tick(); break;
    case L_NOTES: notes_tick(); break;
    case L_PUZZLE: puzzle_tick(); break;
    case L_SEQ: seq_tick(); break;
    case L_LISTEN: listen_tick(); break;
    case L_PAUSE: pause_tick(); break;
    case L_END: end_tick(); break;
    case L_ERROR: error_tick(); break;
    case L_ARENA: arena_tick(); break;
    }
    music_tick();
}

void game_render(uint16_t *native) {
    surface scr = {.px = native, .w = SCREEN_W, .h = SCREEN_H};
    game_draw(&scr, true);
}

/* The zone (or the fight) into G.world, once a frame, before its windows are drawn. */
void game_draw_world(void) {
    G.draws++;
    if (splash_on() && !splash_own()) return; /* the engine's careta draws no world */
    if (G.v2) {
        v2_draw_world();
        return;
    }
    layer_id base = G.nstack ? G.stack[0] : L_TITLE;
    if (base == L_TITLE || base == L_END || base == L_ERROR) return;
    surface world = {.px = G.world, .w = WORLD_W, .h = WORLD_H};
    if (layer_has(L_ARENA)) arena_render_world(&world);
    else world_render(&world);
}

/* Occlusion: a layer is drawn only where the layers above it do not cover it with an opaque panel. A region is a list
 * of disjoint rectangles; cutting a rectangle out of one leaves up to four. */
#define MAX_RECTS 24
typedef struct { int n; screen_rect r[MAX_RECTS]; } region;

static void region_cut(region *g, screen_rect c) {
    /* inward to even edges: the pieces keep the even bounds the 2x upscale's fast path wants (covering a little less
     * is still right) */
    int cx0 = (c.x + 1) & ~1, cy0 = (c.y + 1) & ~1, cx1 = (c.x + c.w) & ~1, cy1 = (c.y + c.h) & ~1;
    if (cx1 <= cx0 || cy1 <= cy0) return;
    c = (screen_rect){cx0, cy0, cx1 - cx0, cy1 - cy0};
    region out = {0};
    for (int k = 0; k < g->n; k++) {
        screen_rect a = g->r[k];
        int x0 = a.x > c.x ? a.x : c.x, y0 = a.y > c.y ? a.y : c.y;
        int x1 = a.x + a.w < c.x + c.w ? a.x + a.w : c.x + c.w, y1 = a.y + a.h < c.y + c.h ? a.y + a.h : c.y + c.h;
        screen_rect piece[4] = {{a.x, a.y, a.w, y0 - a.y}, {a.x, y1, a.w, a.y + a.h - y1},
                                {a.x, y0, x0 - a.x, y1 - y0}, {x1, y0, a.x + a.w - x1, y1 - y0}};
        int np = 0;
        if (x0 >= x1 || y0 >= y1) piece[0] = a, np = 1; /* they do not meet: a stays whole */
        else
            for (int i = 0; i < 4; i++)
                if (piece[i].w > 0 && piece[i].h > 0) piece[np++] = piece[i];
        if (out.n + np > MAX_RECTS) return; /* too many pieces: keep g as it was (more drawing, same pixels) */
        for (int i = 0; i < np; i++) out.r[out.n++] = piece[i];
    }
    *g = out;
}

static bool covered_dlg(int i) { /* a dialogue waiting under a sequence/listen/puzzle stays hidden */
    for (int j = i + 1; j < G.nstack; j++)
        if (G.stack[j] == L_SEQ || G.stack[j] == L_LISTEN || G.stack[j] == L_PUZZLE) return true;
    return false;
}

/* The opaque panels stack layer i leaves on screen, corners left out; and whether it shades what is under it. */
static int layer_opaque(int i, screen_rect *r, bool *shades) {
    *shades = false;
    switch (G.stack[i]) {
    case L_INV:
    case L_NOTES: /* gfx_panel(8, 24, 464, 288) over a full-screen shade */
        *shades = true;
        r[0] = (screen_rect){8, 24 + PANEL_CORNER, SCREEN_W - 16, SCREEN_H - 32 - 2 * PANEL_CORNER};
        return 1;
    case L_DLG: {
        if (covered_dlg(i)) return 0;
        return dlg_opaque(r, shades); /* a close-up darkens the screen around its card */
    }
    default: return 0;
    }
}

/* Stack layer i onto s (0: the zone, or the fight); shade: as when it is drawn whole. */
static void draw_layer(surface *s, surface *world, int i, bool shade) {
    if (i == 0) {
        if (layer_has(L_ARENA)) arena_render_screen(world, s); /* the fight covers the zone it was entered from */
        else {
            if (!world_render_hd(s, world)) gfx_upscale2x(world, s);
            world_render_marker(s);
        }
        return;
    }
    switch (G.stack[i]) {
    case L_DLG: if (!covered_dlg(i)) dlg_render(s, shade); break;
    case L_INV: inv_render(s, shade); break;
    case L_NOTES: notes_render(s, shade); break;
    case L_PUZZLE: puzzle_render(s); break;
    case L_LISTEN: listen_render(s); break;
    case L_PAUSE: pause_render(s); break;
    default: break;
    }
}

static void draw_in(surface *s, const region *g, surface *world, int i, bool shade) {
    if (g->n == 1 && g->r[0].x <= s->x0 && g->r[0].y <= s->y0 && g->r[0].x + g->r[0].w >= s->x0 + s->w &&
        g->r[0].y + g->r[0].h >= s->y0 + s->h) { /* all of s: straight onto it */
        if (i < 0) gfx_shade(s, 0, 0, SCREEN_W, SCREEN_H);
        else draw_layer(s, world, i, shade);
        return;
    }
    for (int k = 0; k < g->n; k++) {
        surface part = gfx_clip(s, g->r[k].x, g->r[k].y, g->r[k].w, g->r[k].h);
        if (part.w > 0 && part.h > 0) {
            if (i < 0) gfx_shade(&part, 0, 0, SCREEN_W, SCREEN_H);
            else draw_layer(&part, world, i, shade);
        }
    }
}

/* The stack bottom to top: the zone only where the layers above leave it visible, a panel layer's shade only where
 * its own panels and those above do not cover it. Same pixels as drawing every layer whole, in order. */
static void draw_stack(surface *s, surface *world) {
    int n = G.nstack > 8 ? 8 : G.nstack;
    screen_rect opq[8][3];
    int nopq[8] = {0};
    bool shades[8] = {false};
    for (int i = 1; i < n; i++) nopq[i] = layer_opaque(i, opq[i], &shades[i]);
    static region reg[8];
    surface whole = gfx_clip(s, 0, 0, SCREEN_W, SCREEN_H); /* s's window, in frame coordinates */
    reg[n - 1] = (region){1, {{whole.x0, whole.y0, whole.w, whole.h}}};
    for (int i = n - 2; i >= 0; i--) {
        reg[i] = reg[i + 1];
        for (int k = 0; k < nopq[i + 1]; k++) region_cut(&reg[i], opq[i + 1][k]);
    }
    for (int i = 0; i < n; i++) {
        if (shades[i]) { /* its shade, only where its panels leave the layers below visible */
            static region dim;
            dim = reg[i];
            for (int k = 0; k < nopq[i]; k++) region_cut(&dim, opq[i][k]);
            draw_in(s, &dim, world, -1, false);
        }
        /* the zone is cheap to draw in pieces; a panel layer is not (each piece would lay out its text again): it is
         * drawn whole, over whatever is under it, and only the zone and the shades are cut. Nor is an HD zone or a
         * fight (each piece would set both cores to work again, every picture and the HUD): whole, under the panels */
        if (i == 0 && (world_is_hd() || layer_has(L_ARENA))) draw_layer(s, world, 0, false);
        else if (i == 0) draw_in(s, &reg[0], world, 0, false);
        else draw_layer(s, world, i, false);
    }
    for (int i = n; i < G.nstack; i++) draw_layer(s, world, i, true); /* past 8 layers (rare): whole, as before */
}

/* The frame onto s, which may be a window of it: everything below draws through gfx.c, clipped to s, so drawing the
 * frame window by window gives the same pixels (the console draws its panel strips this way). world_pass: draw the
 * zone into G.world first (game_draw_world); once a frame is enough, the windows after the first reuse it. */
void game_draw(surface *s, bool world_pass) {
    if (world_pass) game_draw_world();
    if (splash_on()) {
        splash_draw(s);
        return;
    }
    if (G.v2) {
        v2_draw(s);
        return;
    }
    surface scr = *s, world = {.px = G.world, .w = WORLD_W, .h = WORLD_H};
    layer_id base = G.nstack ? G.stack[0] : L_TITLE;
    if (base == L_TITLE) { title_render(&scr); return; }
    if (base == L_END) { end_render(&scr); return; }
    if (base == L_ERROR) { error_render(&scr); return; }

    draw_stack(&scr, &world);
    if (G.seq.fade > 0) {
        if (G.seq.fade >= 1) gfx_fill(&scr, 0, 0, SCREEN_W, SCREEN_H, C_BLACK);
        else if (G.seq.fade >= 0.5f) gfx_shade(&scr, 0, 0, SCREEN_W, SCREEN_H), gfx_shade(&scr, 0, 0, SCREEN_W, SCREEN_H);
        else gfx_shade(&scr, 0, 0, SCREEN_W, SCREEN_H);
        if (layer_has(L_DLG)) dlg_render(&scr, true); /* echo lines stay readable over the fade */
    }
    hud_render(&scr);
    seq_render(&scr);
}
