/* Native-resolution screens: title, pause, inventory, notebook, end, error, HUD and toasts.
 * Every screen works with D-pad + A/B; touch targets are at least 40 px tall (dossier p.38). */
#include <string.h>

#include "bp.h"

#define ROW_H 34

#define TOAST_MS 2500
static char toast_queue[3][96]; /* notes that arrive together are shown one after another */
static int toast_queued;

void ui_toast(const char *msg) { /* at once: the answer to something the player just did */
    snprintf(G.toast, sizeof G.toast, "%s", msg);
    G.toast_ms = TOAST_MS;
}

void ui_toast_queue(const char *msg) {
    if (G.toast_ms > 0 && toast_queued < 3) snprintf(toast_queue[toast_queued++], sizeof toast_queue[0], "%s", msg);
    else ui_toast(msg);
}

void ui_toast_tick(void) {
    if (G.toast_ms <= 0 || (G.toast_ms -= TICK_MS) > 0 || !toast_queued) return;
    snprintf(G.toast, sizeof G.toast, "%s", toast_queue[0]);
    memmove(toast_queue, toast_queue + 1, sizeof toast_queue[0] * (size_t)--toast_queued);
    G.toast_ms = TOAST_MS;
}

void ui_toast_clear(void) {
    toast_queued = 0;
    G.toast_ms = 0;
}

void game_error(const char *fmt, const char *arg) {
    snprintf(G.error, sizeof G.error, fmt, arg);
    hal_log("ERROR: %s", G.error);
    audio_voice_stop(100);
    layers_reset(L_ERROR); /* the director fades music and ambience out */
}

/* A sign that sits on a card's top edge: coloured plate, paper bold text. */
static void title_plate(surface *s, int x, int y, const char *t, uint16_t fill) {
    const font *b = ui_bold();
    int w = font_width(b, t, -1) + 24;
    gfx_plate(s, x, y, w, b->h + 8, fill);
    font_draw(s, b, x + 12, y + 4, t, -1, -1, C_PAPER);
}

/* Button hint: an ink disc with the button letter, then a label. Returns the width used. */
int button_hint(surface *s, int x, int y, const char *btn, const char *label, uint16_t col) {
    const font *f = ui_font(), *b = ui_bold();
    int r = b->h / 2 - 1;
    gfx_disc(s, x + r, y + b->h / 2, r, C_INK);
    font_draw(s, b, x + r - font_width(b, btn, -1) / 2 + 1, y, btn, -1, -1, C_PAPER);
    return 2 * r + 6 + font_draw(s, f, x + 2 * r + 6, y, label, -1, -1, col);
}

/* ------------------------------------------------------------------ menu helper */
typedef struct {
    const char *label[8];
    bool on[8];
    int n, x, y, w;
    int id[8]; /* what each row does; rows a game lacks (bag, notebook) are left out */
} menu;

static void menu_add(menu *m, int id, const char *label, bool on) {
    if (m->n == (int)(sizeof m->id / sizeof m->id[0])) { /* a full list keeps its rows; the extra one is a content bug */
        hal_log("menu full: \"%s\" left out", label);
        return;
    }
    m->id[m->n] = id;
    m->label[m->n] = label;
    m->on[m->n++] = on;
}

enum { M_CONTINUE, M_NEW, M_LARGE, M_PORTRAITS, M_BAG, M_NOTES, M_SAVE, M_TITLE, M_ASSIST, M_VOLUME, M_TONES, M_GAMES };

/* game.json "title_layout": {"logo": [cx, y], "menu": [x, y], "sub": [cx, y]}, with defaults. */
static int title_pos(const char *key, int i, int dflt) { return jai(jget(jget(G.game, "title_layout"), key), i, dflt); }

static int menu_tick(menu *m, int *sel) {
    uint16_t p = G.in.pressed;
    if (G.in.tap && G.in.px >= m->x && G.in.px < m->x + m->w && G.in.py >= m->y) {
        int r = (G.in.py - m->y) / ROW_H;
        if (r >= 0 && r < m->n && m->on[r]) {
            *sel = r;
            return r;
        }
    }
    for (int k = 0; k < m->n && (p & (ACT_UP | ACT_DOWN)); k++) {
        *sel = (*sel + (p & ACT_UP ? m->n - 1 : 1)) % m->n;
        if (m->on[*sel]) break;
    }
    if (!m->on[*sel])
        for (int k = 0; k < m->n; k++)
            if (m->on[k]) { *sel = k; break; }
    if (p & ACT_OK) return *sel;
    if (p & ACT_BACK) return -2;
    return -1;
}

static void menu_render(surface *s, const menu *m, int sel) {
    const font *b = ui_bold();
    for (int k = 0; k < m->n && !m->on[sel]; k++) sel = (sel + 1) % m->n;
    for (int i = 0; i < m->n; i++) {
        int y = m->y + i * ROW_H, ty = y + (ROW_H - b->h) / 2;
        if (i == sel) {
            gfx_fill(s, m->x, y + 2, m->w, ROW_H - 4, C_PAPER_SEL);
            gfx_tri(s, m->x + 6 + ((int)G.anim_ms / 300) % 2, ty + b->h / 2 - 6, 6, true, C_TERRA);
        }
        font_draw(s, b, m->x + 22, ty, m->label[i], -1, -1, m->on[i] ? C_INK : C_DIM);
    }
}

/* ------------------------------------------------------------------ title */
static char lbl_large[40], lbl_portraits[40], lbl_bag[40];
static char lbl_assist[32], lbl_volume[32], lbl_tones[32];

static bool has_tones(void) {
    const cJSON *s;
    cJSON_ArrayForEach(s, jget(G.game, "speakers")) if (jstr(s, "blip")) return true;
    return false;
}

static void option_labels(void) {
    snprintf(lbl_large, sizeof lbl_large, "Texto grande: %s", G.large_text ? "sí" : "no");
    snprintf(lbl_portraits, sizeof lbl_portraits, "Retratos: %s", G.portraits ? "sí" : "no");
    snprintf(lbl_bag, sizeof lbl_bag, "Bolso: %s", G.bag ? "bandolera" : "mochila");
    const char *af = jstr(G.game, "assist_flag");
    snprintf(lbl_assist, sizeof lbl_assist, "Ayudas: %s", af && flag_get(af) ? "sí" : "no");
    snprintf(lbl_volume, sizeof lbl_volume, "Volumen: %d/%d", G.volume, VOLUME_MAX);
    snprintf(lbl_tones, sizeof lbl_tones, "Tonos de voz: %s", G.tones ? "sí" : "no");
}

static menu title_menu(void) {
    option_labels();
    menu m = {.x = title_pos("menu", 0, 246) + 8, .y = title_pos("menu", 1, 66) + 10, .w = 214};
    menu_add(&m, M_CONTINUE, "Continuar", G.can_continue);
    menu_add(&m, M_NEW, "Nueva partida", true);
    menu_add(&m, M_LARGE, lbl_large, true);
    menu_add(&m, M_PORTRAITS, lbl_portraits, true);
    if (G.pl.bag_option) menu_add(&m, M_BAG, lbl_bag, true);
    if (hal_can_switch_game()) menu_add(&m, M_GAMES, "Otros juegos", true); /* the console's game list */
    int bottom = jstr(G.game, "tagline") ? SCREEN_H - 38 : SCREEN_H - 8; /* the panel rises to clear the tagline */
    if (m.y + 10 + m.n * ROW_H > bottom) m.y = bottom - 10 - m.n * ROW_H;
    return m;
}

void title_tick(void) {
    menu m = title_menu();
    int r = menu_tick(&m, &G.menu_sel), id = r >= 0 ? m.id[r] : -1;
    if (id == M_CONTINUE) game_continue(save_newest());
    else if (id == M_NEW) game_new();
    else if (id == M_LARGE) { G.large_text = !G.large_text; settings_save(); }
    else if (id == M_PORTRAITS) { G.portraits = !G.portraits; settings_save(); }
    else if (id == M_BAG) { G.bag = !G.bag; settings_save(); }
    else if (id == M_GAMES) hal_switch_game();
}

void title_render(surface *s) {
    asset *bg = gfx_asset_opt("BG_TITLE"), *logo = gfx_asset_opt("LOGO");
    if (bg->missing) gfx_fill(s, 0, 0, SCREEN_W, SCREEN_H, C_BROWN);
    else gfx_blit2x(s, bg, 0, 0, 0);
    if (!logo->missing) {
        gfx_blit(s, logo, 0, title_pos("logo", 0, 132) - logo->w / 2, title_pos("logo", 1, 6), 0, false);
    } else {
        gfx_panel(s, 24, 60, 220, 90);
        const char *t = jstr(G.game, "title") ? jstr(G.game, "title") : jstr(G.game, "id");
        text_center(s, &G.bold_l, 134, 90, t ? t : "", C_INK);
    }
    const char *sub = jstr(G.game, "subtitle") ? jstr(G.game, "subtitle") : "";
    int sw = font_width(ui_bold(), sub, -1) + 24, sx = title_pos("sub", 0, 132) - sw / 2;
    title_plate(s, sx < 8 ? 8 : sx, title_pos("sub", 1, 234), sub, C_TERRA);
    menu m = title_menu();
    gfx_panel(s, m.x - 8, m.y - 10, 228, m.n * ROW_H + 20);
    menu_render(s, &m, G.menu_sel);
    const char *tag = jstr(G.game, "tagline");
    if (tag) { /* the guiding phrase, as a quiet caption */
        text_center(s, &G.font, SCREEN_W / 2 + 1, SCREEN_H - 33, tag, C_INK);
        text_center(s, &G.font, SCREEN_W / 2, SCREEN_H - 34, tag, C_PAPER);
    }
}

/* ------------------------------------------------------------------ pause */
static int pause_top(int rows) { /* the pause panel's top edge: centred, never under the title plate's room */
    int top = (SCREEN_H - (rows * ROW_H + 26)) / 2;
    return top < 16 ? 16 : top;
}

static menu pause_menu(void) {
    option_labels();
    bool can_save = G.nstack >= 2 && G.stack[G.nstack - 2] == L_PLAY; /* not mid dialogue/sequence */
    menu m = {.x = 124, .y = 38, .w = 232};
    menu_add(&m, M_CONTINUE, "Continuar", true);
    if (content_has_notes()) menu_add(&m, M_NOTES, "Cuaderno", true);
    menu_add(&m, M_SAVE, "Guardar partida", can_save);
    if (jstr(G.game, "assist_flag")) menu_add(&m, M_ASSIST, lbl_assist, true); /* wider windows, less damage */
    menu_add(&m, M_LARGE, lbl_large, true);
    menu_add(&m, M_PORTRAITS, lbl_portraits, true);
    if (G.pl.bag_option) menu_add(&m, M_BAG, lbl_bag, true);
    menu_add(&m, M_VOLUME, lbl_volume, true);
    if (has_tones()) menu_add(&m, M_TONES, lbl_tones, true);
    menu_add(&m, M_TITLE, "Volver al título", true);
    m.y = pause_top(m.n) + 14; /* the panel is centred, so a longer list still fits */
    return m;
}

void pause_tick(void) {
    menu m = pause_menu();
    int r = menu_tick(&m, &G.menu_sel), id = r >= 0 ? m.id[r] : -1;
    if (r == -2 || id == M_CONTINUE || (G.in.pressed & ACT_PAUSE)) { layer_remove(L_PAUSE); audio_pause(false); }
    else if (id == M_NOTES) { layer_remove(L_PAUSE); audio_pause(false); if (!layer_has(L_NOTES)) layer_push(L_NOTES); }
    else if (id == M_SAVE) ui_toast(save_write("manual") ? "Partida guardada." : "No se pudo guardar.");
    else if (id == M_LARGE) { G.large_text = !G.large_text; settings_save(); }
    else if (id == M_PORTRAITS) { G.portraits = !G.portraits; settings_save(); }
    else if (id == M_BAG) { G.bag = !G.bag; settings_save(); }
    else if (id == M_ASSIST) flag_set(jstr(G.game, "assist_flag"), !flag_get(jstr(G.game, "assist_flag")));
    else if (id == M_VOLUME) { /* A steps it down and wraps to full; it is heard at once, under the pause */
        G.volume = G.volume > 0 ? G.volume - 1 : VOLUME_MAX;
        audio_master((float)G.volume / VOLUME_MAX, 150);
        settings_save();
    }
    else if (id == M_TONES) { G.tones = !G.tones; settings_save(); }
    else if (id == M_TITLE) game_to_title();
}

void pause_render(surface *s) {
    gfx_shade(s, 0, 0, SCREEN_W, SCREEN_H);
    menu m = pause_menu();
    int top = pause_top(m.n);
    gfx_panel(s, 112, top, 256, m.n * ROW_H + 26);
    title_plate(s, 124, top - 14, "Pausa", C_TERRA);
    menu_render(s, &m, G.menu_sel);
}

/* ------------------------------------------------------------------ inventory */
/* The bag shows PAGE items at a time (3 x 2); more than that and LEFT / RIGHT past an edge turn the page. */
#define BAG_MAX 24
#define PAGE 6
static int inv_items(const char **out) {
    int n = 0;
    const cJSON *it;
    cJSON_ArrayForEach(it, G.items) if (n < BAG_MAX && flagf_get("item:%s%s", it->string, "")) out[n++] = it->string;
    return n;
}

static const char *inv_sub_labels[4] = {"Inspeccionar", "Usar", "Mostrar", "Volver"};

void inv_tick(void) {
    const char *items[BAG_MAX];
    int n = inv_items(items);
    uint16_t p = G.in.pressed;
    if (G.inv_sel >= n) G.inv_sel = n ? n - 1 : 0;
    if (p & (ACT_NEXT | ACT_NOTES)) {
        layer_remove(L_INV);
        layer_push(L_NOTES);
        return;
    }
    if (G.inv_menu) {
        menu m = {{inv_sub_labels[0], inv_sub_labels[1], inv_sub_labels[2], inv_sub_labels[3]}, {true, true, true, true}, 4, 284, 74, 180, {0}};
        int r = menu_tick(&m, &G.inv_sub);
        const char *item = n ? items[G.inv_sel] : NULL;
        if (r == -2 || r == 3) G.inv_menu = false;
        else if (r == 0 && item) {
            G.inv_menu = false;
            cJSON *def = jget(G.items, item);
            effects_run(jget(def, "inspect"));
            dlg_say(G.pl.speaker, jstr(def, "desc") ? jstr(def, "desc") : "", jstr(def, "ill"));
        } else if ((r == 1 || r == 2) && item) {
            G.inv_menu = false;
            layer_remove(L_INV);
            world_use_item(item, r == 2);
        }
        return;
    }
    if ((p & (ACT_BACK | ACT_INV)) || (G.in.tap && G.in.py >= 262 && G.in.px >= 340)) {
        layer_remove(L_INV);
        return;
    }
    if (G.in.tap) { /* the icons are 66 px plates every 72 px (inv_render) */
        int col = (G.in.px - 24) / 72, row = (G.in.py - 50) / 72, i = G.inv_sel / PAGE * PAGE + row * 3 + col;
        if (G.in.px >= 24 && col < 3 && G.in.py >= 50 && row < 2 && i < n) {
            G.inv_sel = i;
            G.inv_menu = true;
            G.inv_sub = 0;
        }
        return;
    }
    if (!n) return;
    if (p & ACT_RIGHT) G.inv_sel = (G.inv_sel + 1) % n;
    if (p & ACT_LEFT) G.inv_sel = (G.inv_sel + n - 1) % n;
    if ((p & ACT_DOWN) && G.inv_sel % PAGE < 3 && G.inv_sel + 3 < n) G.inv_sel += 3;
    if ((p & ACT_UP) && G.inv_sel % PAGE >= 3) G.inv_sel -= 3;
    if (p & ACT_OK) { G.inv_menu = true; G.inv_sub = 0; }
}

#define BAG_TEXT_W (SCREEN_W - 52) /* the item's name and description, under the icons */

void inv_render(surface *s, bool shade) { /* shade: darken what is under it (game_draw may have done it) */
    const font *f = ui_font(), *b = ui_bold();
    const char *items[BAG_MAX];
    int n = inv_items(items), page = G.inv_sel / PAGE;
    if (shade) gfx_shade(s, 0, 0, SCREEN_W, SCREEN_H);
    gfx_panel(s, 8, 24, SCREEN_W - 16, SCREEN_H - 32);
    title_plate(s, 20, 10, content_bag_label(), C_TERRA);
    if (!n) font_draw(s, f, 28, 80, "Todavía no llevo nada.", -1, -1, C_DIM);
    for (int i = page * PAGE; i < n && i < (page + 1) * PAGE; i++) { /* icons only: the selected one's name heads its description below */
        int x = 24 + (i % 3) * 72, y = 50 + (i % PAGE / 3) * 72;
        bool sel = i == G.inv_sel;
        gfx_plate(s, x, y, 66, 66, sel ? C_PAPER_SEL : C_PAPER);
        asset *ic = gfx_asset(jstr(jget(G.items, items[i]), "icon"));
        gfx_blit2x(s, ic, 0, x + 33 - ic->w, y + 33 - ic->h);
    }
    if (n > PAGE) { /* which page, and that there are others */
        char pg[16];
        snprintf(pg, sizeof pg, "%d / %d", page + 1, (n + PAGE - 1) / PAGE);
        font_draw(s, b, 240, 110, pg, -1, -1, C_DIM);
    }
    if (n) {
        const cJSON *def = jget(G.items, items[G.inv_sel]);
        const char *nm = jstr(def, "name") ? jstr(def, "name") : items[G.inv_sel], *d = jstr(def, "desc");
        font_draw(s, b, 26, 196, nm, -1, -1, C_INK);
        uint16_t ls[4], ll[4]; /* the whole width (the hints sit up top); a 4th line only in large text */
        int k = d ? text_wrap(f, d, BAG_TEXT_W, ls, ll, 4) : 0;
        for (int i = 0; i < k; i++) font_draw(s, f, 26, 198 + b->h + i * f->h, d + ls[i], ll[i], -1, C_BROWN);
    }
    if (G.inv_menu) {
        menu m = {{inv_sub_labels[0], inv_sub_labels[1], inv_sub_labels[2], inv_sub_labels[3]}, {true, true, true, true}, 4, 284, 74, 180, {0}};
        gfx_panel(s, 276, 64, 196, 4 * ROW_H + 20);
        menu_render(s, &m, G.inv_sub);
    } else button_hint(s, SCREEN_W - 130, 34, "B", "Volver", C_INK);
    if (content_has_notes()) button_hint(s, SCREEN_W - 280, 34, "C", "Cuaderno", C_DIM);
}

/* ------------------------------------------------------------------ notebook */
/* Notebook actions (notebook.json "actions": label, if, do): "Comparar foto y plano", "Terminar episodio"... */
static int note_actions(const cJSON **out, int max) {
    int n = 0;
    const cJSON *a;
    cJSON_ArrayForEach(a, jget(G.notebook, "actions")) if (n < max && cond_eval(jget(a, "if"))) out[n++] = a;
    return n;
}

#define NOTES_MAX 64 /* the list scrolls with the selection (notes_render) */
static int note_entries(const cJSON **out, int max) {
    int n = 0;
    const cJSON *e;
    cJSON_ArrayForEach(e, jget(G.notebook, "entries")) if (n < max && flagf_get("note:%s%s", e->string, "")) out[n++] = e;
    return n;
}

static int action_y = 92; /* where the first action button was drawn, for touch */
#define ACTION_H 44

void notes_tick(void) {
    uint16_t p = G.in.pressed;
    const cJSON *e[NOTES_MAX], *act[4];
    int na = note_actions(act, 4), n = note_entries(e, NOTES_MAX), rows = n + na;
    if (p & (ACT_BACK | ACT_NOTES) || (G.in.tap && G.in.py >= 262 && G.in.px >= 340)) { layer_remove(L_NOTES); return; }
    if (p & (ACT_NEXT | ACT_INV)) { layer_remove(L_NOTES); G.inv_menu = false; layer_push(L_INV); return; }
    if (rows == 0) return;
    if (p & ACT_DOWN) G.notes_sel = (G.notes_sel + 1) % rows;
    if (p & ACT_UP) G.notes_sel = (G.notes_sel + rows - 1) % rows;
    int tapped = G.in.tap && G.in.py >= action_y && G.in.py < action_y + na * ACTION_H ? (G.in.py - action_y) / ACTION_H : -1;
    int chosen = tapped >= 0 ? tapped : (p & ACT_OK) && G.notes_sel < na ? G.notes_sel : -1;
    if (chosen >= 0) {
        layer_remove(L_NOTES);
        effects_run(jget(act[chosen], "do"));
    }
}

static const char *kind_label(const char *k) {
    return !strcmp(k, "obs") ? "Observación" : !strcmp(k, "test") ? "Testimonio" : !strcmp(k, "heard") ? "Oí" : "Pregunta";
}

void notes_render(surface *s, bool shade) {
    const font *f = ui_font(), *b = ui_bold();
    int lh = f->h + 2;
    if (shade) gfx_shade(s, 0, 0, SCREEN_W, SCREEN_H);
    gfx_panel(s, 8, 24, SCREEN_W - 16, SCREEN_H - 32);
    title_plate(s, 20, 10, "Cuaderno", C_GREEN);
    const cJSON *q;
    int y = 40;
    cJSON_ArrayForEach(q, jget(G.notebook, "questions")) if (cond_eval(jget(q, "if"))) {
        font_draw(s, b, 24, y, jstr(q, "t"), -1, -1, C_INK);
        y += lh;
        break;
    }
    cJSON_ArrayForEach(q, jget(G.notebook, "tasks")) if (cond_eval(jget(q, "if"))) {
        font_draw(s, f, 24, y, jstr(q, "t"), -1, -1, C_GREEN);
        y += lh;
    }
    y += 4;
    const cJSON *act[4];
    int row = note_actions(act, 4);
    action_y = y;
    for (int i = 0; i < row; i++, y += ACTION_H) {
        gfx_plate(s, 20, y, SCREEN_W - 40, 36, G.notes_sel == i ? C_PAPER_SEL : C_PAPER);
        if (G.notes_sel == i) gfx_tri(s, 30, y + 12, 6, true, C_TERRA);
        font_draw(s, b, 44, y + (36 - b->h) / 2, jstr(act[i], "label"), -1, -1, C_INK);
    }
    const cJSON *e[NOTES_MAX];
    int n = note_entries(e, NOTES_MAX), first = G.notes_sel - row - 1;
    if (first < 0) first = 0;
    if (!n) font_draw(s, f, 24, y, "Sin anotaciones todavía.", -1, -1, C_DIM);
    for (int i = first; i < n; i++) {
        const char *t = jstr(e[i], "text");
        uint16_t ls[6], ll[6];
        int k = t ? text_wrap(f, t, SCREEN_W - 64, ls, ll, 3) : 0;
        if (y + (k + 1) * lh > 258) break; /* keep clear of the Volver button */
        bool sel = G.notes_sel == i + row;
        const char *kind = jstr(e[i], "kind") ? jstr(e[i], "kind") : "obs";
        uint16_t kc = !strcmp(kind, "test") ? C_TERRA : !strcmp(kind, "q") ? C_BLUEGRAY : !strcmp(kind, "heard") ? C_BROWN : C_GREEN;
        gfx_fill(s, 18, y + 2, 4, lh * (k + 1) - 4, sel ? C_TERRA : kc); /* margin mark: colour + label, never colour alone */
        int x = 28 + font_draw(s, b, 28, y, kind_label(kind), -1, -1, kc);
        font_draw(s, b, x + 10, y, jstr(e[i], "title"), -1, -1, C_INK);
        y += lh;
        for (int j = 0; j < k; j++, y += lh) font_draw(s, f, 28, y, t + ls[j], ll[j], -1, C_INK);
        y += 4;
    }
    gfx_plate(s, 340, 262, 124, 42, C_PAPER);
    button_hint(s, 352, 262 + (42 - b->h) / 2, "B", "Volver", C_INK);
    button_hint(s, 24, 272, "C", content_bag_label(), C_DIM);
}

/* ------------------------------------------------------------------ end / error */
/* End of a chapter (game.json "chapters"): continue into the next one, back to the title, or load the
 * chapter's last checkpoint ("load_slot"/"load_label", e.g. before the descent). */
static char lbl_next[64];

static menu end_menu(void) {
    int cur = chapter_current();
    const cJSON *next = chapter_def(cur + 1), *def = chapter_def(cur);
    const cJSON *after = jget(def, "after"); /* no next chapter yet: back into the world, everything kept */
    if (next) snprintf(lbl_next, sizeof lbl_next, "Continuar: %s", jstr(next, "title") ? jstr(next, "title") : "");
    if (next && font_width(ui_bold(), lbl_next, -1) + 44 > SCREEN_W - 40) snprintf(lbl_next, sizeof lbl_next, "Continuar"); /* too long */
    else if (after) snprintf(lbl_next, sizeof lbl_next, "%s", jstr(after, "label") ? jstr(after, "label") : "Seguir jugando");
    else snprintf(lbl_next, sizeof lbl_next, "Continuará…");
    const char *load = jstr(def, "load_label");
    menu m = {{lbl_next, "Volver al título", load ? load : ""}, {next || after, true, load && G.can_load_prefinal}, load ? 3 : 2, 52, 184, 376, {0}};
    int w = 0; /* as wide as its longest label ("Continuar: <chapter title>"), centred */
    for (int i = 0; i < m.n; i++) {
        int lw = font_width(ui_bold(), m.label[i], -1) + 44;
        w = lw > w ? lw : w;
    }
    m.w = w < 376 ? 376 : w > SCREEN_W - 40 ? SCREEN_W - 40 : w;
    m.x = (SCREEN_W - m.w) / 2;
    return m;
}

void end_tick(void) {
    menu m = end_menu();
    int r = menu_tick(&m, &G.menu_sel);
    const cJSON *after = jget(chapter_def(chapter_current()), "after");
    if (r == 0 && !chapter_def(chapter_current() + 1) && after) {
        layers_reset(L_PLAY);
        world_enter(jstr(after, "zone"), jstr(after, "spawn") ? jstr(after, "spawn") : "safe");
    } else if (r == 0) chapter_begin(chapter_current() + 1);
    else if (r == 1) game_to_title();
    else if (r == 2) game_continue(jstr(chapter_def(chapter_current()), "load_slot") ? jstr(chapter_def(chapter_current()), "load_slot") : "prefinal");
}

/* The chapter's end line in large text; too wide, it breaks at " · " (chapter / title) or wraps in two. */
static void end_text_draw(surface *s, const char *t, int y) {
    const font *f = &G.bold_l;
    if (font_width(f, t, -1) <= SCREEN_W - 32) { text_center(s, f, SCREEN_W / 2, y, t, C_PAPER); return; }
    const char *dot = strstr(t, " · ");
    char a[96];
    uint16_t ls[2], ll[2];
    int n = dot ? 2 : text_wrap(f, t, SCREEN_W - 32, ls, ll, 2);
    for (int i = 0; i < n; i++) {
        if (dot) snprintf(a, sizeof a, "%.*s", i ? (int)strlen(dot + 4) : (int)(dot - t), i ? dot + 4 : t);
        else snprintf(a, sizeof a, "%.*s", ll[i], t + ls[i]);
        text_center(s, f, SCREEN_W / 2, y - (f->h + 4) / 2 - 8 + i * (f->h + 4), a, C_PAPER);
    }
}

void end_render(surface *s) {
    gfx_fill(s, 0, 0, SCREEN_W, SCREEN_H, C_BLACK);
    asset *logo = gfx_asset_opt("LOGO_SMALL");
    if (!logo->missing) gfx_blit(s, logo, 0, (SCREEN_W - logo->w) / 2, 6, 0, false);
    const char *end = jstr(chapter_def(chapter_current()), "end_text") ? jstr(chapter_def(chapter_current()), "end_text")
                                                                       : jstr(G.game, "end_text");
    end_text_draw(s, end ? end : "Fin", 140);
    menu m = end_menu();
    gfx_panel(s, m.x - 12, 174, m.w + 24, m.n * ROW_H + 20);
    menu_render(s, &m, G.menu_sel);
}

void error_tick(void) {
    if (G.in.pressed & (ACT_OK | ACT_BACK) || G.in.tap) game_to_title();
}

void error_render(surface *s) {
    const font *f = ui_font();
    gfx_fill(s, 0, 0, SCREEN_W, SCREEN_H, C_INK);
    if (!f->bits) return; /* no font at all: the platform already logged why */
    text_center(s, ui_bold(), SCREEN_W / 2, 60, "No se puede continuar", C_TERRA);
    uint16_t ls[6], ll[6];
    int n = text_wrap(f, G.error, SCREEN_W - 64, ls, ll, 6);
    for (int i = 0; i < n; i++) font_draw(s, f, 32, 110 + i * (f->h + 4), G.error + ls[i], ll[i], -1, C_CREAM);
    text_center(s, f, SCREEN_W / 2, 260, "A: volver al título", C_OCHRE);
}

/* ------------------------------------------------------------------ HUD */
static void icon_button(surface *s, int x, const char *icon) {
    gfx_plate(s, x, 8, 40, 40, C_PAPER);
    asset *a = gfx_asset(icon);
    gfx_blit2x(s, a, 0, x + 20 - a->w, 28 - a->h);
}

void hud_tick(void) {
    if (!G.in.tap || G.in.py >= 48) return;
    bool bag = content_has_bag(), notes = content_has_notes();
    if (bag && G.in.px >= SCREEN_W - 96 && G.in.px < SCREEN_W - 56) { G.inv_menu = false; layer_push(L_INV); }
    else if (notes && G.in.px >= SCREEN_W - 48 && G.in.px < SCREEN_W - 8) layer_push(L_NOTES);
}

void hud_render(surface *s) {
    if (layer_top() == L_PLAY) {
        if (content_has_bag()) icon_button(s, SCREEN_W - 96, "UI_BAG");
        if (content_has_notes()) icon_button(s, SCREEN_W - 48, "UI_BOOK");
    }
    layer_id top = layer_top();
    if (G.toast_ms > 0 && (top == L_PLAY || top == L_DLG || top == L_SEQ || top == L_PAUSE)) {
        /* below the location sign and the HUD buttons; at the bottom over the pause card */
        const font *b = ui_bold();
        asset *ic = gfx_asset("UI_BOOK");
        int w = font_width(b, G.toast, -1) + 28 + ic->w * 2, x = (SCREEN_W - w) / 2, h = b->h + 10;
        int card_h = G.bold_l.h + 24, cy = world_card_y(card_h);
        int y = top == L_PAUSE ? SCREEN_H - h - 6
              : top == L_PLAY && G.banner_ms > 0 ? (cy == 54 ? cy + card_h + 6 : cy - h - 6) /* by the arrival card */
              : top == L_PLAY ? world_card_y(h) : 54;
        gfx_plate(s, x, y, w, h, C_PAPER);
        gfx_blit2x(s, ic, 0, x + 8, y + (h - 2 * ic->h) / 2);
        font_draw(s, b, x + 16 + 2 * ic->w, y + 5, G.toast, -1, -1, C_INK);
    }
}
