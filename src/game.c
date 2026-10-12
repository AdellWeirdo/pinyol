/* Game state machine as a layer stack: only the top layer receives input each tick, so a key that
 * opened or closed something can never also pick an option in the layer that appears next. */
#include <stdlib.h>
#include <string.h>
#include <sys/stat.h>

#include "bp.h"

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
    if (G.v2) v2_load(); /* a script error shows on screen (and fails --validate); the folder still opens */
    if (!ok) hal_log("game folder %s is incomplete", G.game_dir);
    return ok && G.font.bits && G.font_l.bits && G.bold.bits && G.bold_l.bits;
}

void game_shutdown(void) {
    v2_free();
    arena_free();
    audio_reset();
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
    if ((G.in.pressed & ACT_INV) && !content_has_bag()) G.in.pressed = (G.in.pressed & ~ACT_INV) | ACT_PAUSE;
    G.in.held = in->held;
    G.in.tap = in->touch && !G.in.touch;
    G.in.release = !in->touch && G.in.touch;
    G.in.touch = in->touch;
    G.in.px = in->px;
    G.in.py = in->py;
    if (in->held & ACT_QUIT) G.quit = true;
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

/* Layers from..to-1 of the stack onto s (0: the zone, or the fight). The panel layers (bag, notebook) shade what is
 * under them unless they are the first drawn here: then game_draw has shaded only where it shows. */
static void draw_layers(surface *s, surface *world, int from, int to) {
    for (int i = from; i < to; i++) {
        if (i == 0) {
            if (layer_has(L_ARENA)) arena_render_screen(world, s); /* the fight covers the zone it was entered from */
            else {
                gfx_upscale2x(world, s);
                world_render_marker(s);
            }
            continue;
        }
        bool covered = false; /* a dialogue waiting under a sequence/listen/puzzle stays hidden */
        for (int j = i + 1; j < G.nstack; j++) covered |= G.stack[j] == L_SEQ || G.stack[j] == L_LISTEN || G.stack[j] == L_PUZZLE;
        switch (G.stack[i]) {
        case L_DLG: if (!covered) dlg_render(s); break;
        case L_INV: inv_render(s, i > from); break;
        case L_NOTES: notes_render(s, i > from); break;
        case L_PUZZLE: puzzle_render(s); break;
        case L_LISTEN: listen_render(s); break;
        case L_PAUSE: pause_render(s); break;
        default: break;
        }
    }
}

/* The frame onto s, which may be a window of it: everything below draws through gfx.c, clipped to s, so drawing the
 * frame window by window gives the same pixels (the console draws its panel strips this way). world_pass: draw the
 * zone into G.world first (game_draw_world); once a frame is enough, the windows after the first reuse it. */
void game_draw(surface *s, bool world_pass) {
    if (world_pass) game_draw_world();
    if (G.v2) {
        v2_draw(s);
        return;
    }
    surface scr = *s, world = {.px = G.world, .w = WORLD_W, .h = WORLD_H};
    layer_id base = G.nstack ? G.stack[0] : L_TITLE;
    if (base == L_TITLE) { title_render(&scr); return; }
    if (base == L_END) { end_render(&scr); return; }
    if (base == L_ERROR) { error_render(&scr); return; }

    /* The bag and the notebook are opaque panels over almost all the screen: what is under them (the zone, layers
     * below, their shade) is drawn only around the panel's middle, in four bands that miss its corners. */
    int cover = 0;
    for (int i = 1; i < G.nstack; i++)
        if (G.stack[i] == L_INV || G.stack[i] == L_NOTES) cover = i;
    if (!cover) draw_layers(&scr, &world, 0, G.nstack);
    else {
        static const struct { int16_t x, y, w, h; } around[4] = { /* the panel is (8, 24, 464, 288), corners 8 */
            {0, 0, SCREEN_W, 36}, {0, 300, SCREEN_W, SCREEN_H - 300}, {0, 36, 8, 264}, {SCREEN_W - 8, 36, 8, 264}};
        for (int k = 0; k < 4; k++) {
            surface part = gfx_clip(&scr, around[k].x, around[k].y, around[k].w, around[k].h);
            if (part.w <= 0) continue;
            draw_layers(&part, &world, 0, cover);
            gfx_shade(&part, 0, 0, SCREEN_W, SCREEN_H);
        }
        draw_layers(&scr, &world, cover, G.nstack);
    }
    if (G.seq.fade > 0) {
        if (G.seq.fade >= 1) gfx_fill(&scr, 0, 0, SCREEN_W, SCREEN_H, C_BLACK);
        else if (G.seq.fade >= 0.5f) gfx_shade(&scr, 0, 0, SCREEN_W, SCREEN_H), gfx_shade(&scr, 0, 0, SCREEN_W, SCREEN_H);
        else gfx_shade(&scr, 0, 0, SCREEN_W, SCREEN_H);
        if (layer_has(L_DLG)) dlg_render(&scr); /* echo lines stay readable over the fade */
    }
    hud_render(&scr);
    seq_render(&scr);
}
