/* The console's menu over a Lua game, and its crash screen (sysmenu.h). Drawn in C with the game's fonts, so every
 * game has it the same way, in the console's language (conf.h). */
#include <stdio.h>
#include <string.h>

#include "conf.h"
#include "sysmenu.h"

#define TAP_TICKS 30     /* MENU let go within this: a tap */
#define HOLD_OPEN 60     /* MENU held this long opens the menu whatever the game does with MENU */
#define HOLD_QUIT 120    /* and this long goes to the list, as before there was a menu */
#define MAX_ITEMS 3      /* the game's own */

enum { PAGE_MAIN, PAGE_SETTINGS };
enum { ROW_VOLUME, ROW_FLASH, ROW_COLOUR, ROW_SPEED, ROW_LANG, ROW_BUTTONS, ROWS_SETTINGS };

static struct {
    bool open, crashed, by_hold;
    int page, cursor, menu_t;
    bool other;      /* another button was pressed while MENU was held: not a tap */
    int scroll;      /* the crash screen's first line */
    char error[600];
    uint16_t carry;  /* presses on the ticks the speed skipped, given to the next */
    uint32_t frame;  /* ticks seen (G.ticks stops on the skipped ones) */
} S;

/* What the menu says, in the console's language (es, ca, en) */
static const char *const T_RESUME[] = {"Seguir", "Seguir", "Resume"};
static const char *const T_RESTART[] = {"Reiniciar", "Reiniciar", "Restart"};
static const char *const T_SETTINGS[] = {"Ajustes", "Ajustos", "Settings"};
static const char *const T_QUIT[] = {"Salir a la lista", "Sortir a la llista", "Back to the list"};
static const char *const T_HINT[] = {"A elegir  ·  B volver", "A triar  ·  B tornar", "A choose  ·  B back"};
static const char *const T_HINT_SET[] = {"A cambiar  ·  B volver", "A canviar  ·  B tornar", "A change  ·  B back"}; /* (LEFT and RIGHT too: no arrows in every font) */
static const char *const T_VOLUME[] = {"Volumen", "Volum", "Volume"};
static const char *const T_FLASH[] = {"Destellos", "Llampecs", "Flashing"};
static const char *const T_FLASH_V[2][3] = {{"normales", "normals", "normal"}, {"menos", "menys", "less"}};
static const char *const T_COLOUR[] = {"Colores", "Colors", "Colours"};
static const char *const T_COLOUR_V[4][3] = {{"normales", "normals", "normal"},
                                             {"rojo-verde (protan)", "vermell-verd (protan)", "red-green (protan)"},
                                             {"rojo-verde (deutan)", "vermell-verd (deutan)", "red-green (deutan)"},
                                             {"azul-amarillo", "blau-groc", "blue-yellow"}};
static const char *const T_SPEED[] = {"Velocidad", "Velocitat", "Speed"};
static const char *const T_LANG[] = {"Idioma", "Idioma", "Language"};
static const char *const T_LANG_V[] = {"Español", "Català", "English"};
static const char *const T_BUTTONS[] = {"Botones", "Botons", "Buttons"};
static const char *const T_BUTTONS_V[2][3] = {{"A y B", "A i B", "A and B"}, {"B y A (cambiados)", "B i A (canviats)", "B and A (swapped)"}};
static const char *const T_CRASH[] = {"El juego se ha parado", "El joc s'ha aturat", "The game stopped"};
static const char *const T_CRASH_HINT[] = {"A otra vez  ·  B a la lista", "A una altra vegada  ·  B a la llista", "A again  ·  B the list"};
static const char *const T_CRASH_HINT_NOLIST[] = {"A otra vez", "A una altra vegada", "A again"};
static const char *const T_SAVED[] = {"(guardado en crash.txt)", "(desat a crash.txt)", "(saved in crash.txt)"};

#define L CONF.lang

void sysmenu_reset(void) {
    memset(&S, 0, sizeof S);
}

bool sysmenu_paused(void) { return S.open || S.crashed; }
bool sysmenu_open(void) { return S.open; }

void sysmenu_crash(const char *error) {
    S.crashed = true, S.open = false, S.scroll = 0;
    snprintf(S.error, sizeof S.error, "%s", error ? error : "error");
}

static int n_items(void) { return v2_menu_items(NULL, 0); }

static int main_rows(void) { return 1 + n_items() + 2 + (hal_can_switch_game() ? 1 : 0); } /* resume, items, restart, settings, quit */

static void open_menu(bool by_hold) {
    S.open = true, S.by_hold = by_hold, S.page = PAGE_MAIN, S.cursor = 0;
    audio_pause(true);
    v2_menu_event("_pause");
}

static void close_menu(void) {
    S.open = false;
    audio_pause(false);
    conf_save();
    v2_menu_event("_resume");
}

static void choose_main(void) {
    const int items = n_items();
    if (S.cursor == 0) { close_menu(); return; }
    if (S.cursor <= items) { /* the game's own: closed first, so what it does happens in the game */
        const int i = S.cursor - 1;
        close_menu();
        v2_menu_choose(i);
        return;
    }
    const int k = S.cursor - 1 - items;
    if (k == 0) { close_menu(); game_new(); return; }
    if (k == 1) { S.page = PAGE_SETTINGS, S.cursor = 0; return; }
    close_menu();
    hal_switch_game();
}

static void adjust(int row, int dir) {
    switch (row) {
    case ROW_VOLUME: CONF.volume += 10 * dir; CONF.volume = CONF.volume < 0 ? 0 : CONF.volume > 100 ? 100 : CONF.volume; break;
    case ROW_FLASH: CONF.reduce_flash = !CONF.reduce_flash; break;
    case ROW_COLOUR: CONF.colour = (CONF.colour + 4 + dir) % 4; break;
    case ROW_SPEED: CONF.speed = dir > 0 ? (CONF.speed == 50 ? 75 : 100) : (CONF.speed == 100 ? 75 : 50); break;
    case ROW_LANG: CONF.lang = (CONF.lang + 3 + dir) % 3; break;
    case ROW_BUTTONS: CONF.swap_ab = !CONF.swap_ab; break;
    }
    conf_apply();
}

static void tick_open(void) {
    const uint16_t p = G.in.pressed;
    const int rows = S.page == PAGE_MAIN ? main_rows() : ROWS_SETTINGS;
    if (p & ACT_UP) S.cursor = (S.cursor + rows - 1) % rows;
    if (p & ACT_DOWN) S.cursor = (S.cursor + 1) % rows;
    if (S.page == PAGE_SETTINGS) {
        if (p & ACT_LEFT) adjust(S.cursor, -1);
        if (p & (ACT_RIGHT | ACT_OK)) adjust(S.cursor, 1);
        if (p & ACT_BACK) S.page = PAGE_MAIN, S.cursor = 0;
        return;
    }
    if (p & ACT_OK) choose_main();
    else if (p & ACT_BACK) close_menu();
}

static void tick_crashed(void) {
    const uint16_t p = G.in.pressed;
    if (p & ACT_UP) S.scroll = S.scroll > 0 ? S.scroll - 1 : 0;
    if (p & ACT_DOWN) S.scroll++;
    if (p & ACT_OK) { S.crashed = false; game_new(); }
    else if ((p & ACT_BACK) && hal_can_switch_game()) { S.crashed = false; hal_switch_game(); }
}

bool sysmenu_tick(void) {
    const bool menu_down = (G.in.held & ACT_INV) != 0, menu_was = S.menu_t > 0;
    if (menu_down) {
        S.menu_t++;
        if (G.in.pressed & ~ACT_INV) S.other = true;
        if (S.menu_t == HOLD_OPEN && !S.open && !S.crashed) open_menu(true);
        if (S.menu_t == HOLD_QUIT && hal_can_switch_game()) { /* MENU held 2 s: back to the list, as always */
            if (S.open) close_menu();
            hal_switch_game();
        }
    } else {
        const int t = S.menu_t;
        S.menu_t = 0;
        if (menu_was && t < TAP_TICKS && !S.other) { /* a tap */
            if (S.open && !S.by_hold) close_menu();
            else if (!S.open && !S.crashed && !v2_reads_menu()) open_menu(false);
        }
        if (menu_was) S.by_hold = false, S.other = false;
    }
    if (S.crashed) { tick_crashed(); return false; }
    if (S.open) { /* the game's buttons are the menu's; MENU itself was handled above */
        if (!(G.in.pressed & ACT_INV)) tick_open();
        return false;
    }
    /* the speed: 75 gives the game three ticks in four, 50 one in two; a press on a skipped tick waits for the next */
    S.frame++;
    const bool skip = CONF.speed == 50 ? (S.frame & 1) != 0 : CONF.speed == 75 ? (S.frame & 3) == 3 : false;
    if (skip) { S.carry |= G.in.pressed; return false; }
    G.in.pressed |= S.carry, S.carry = 0;
    return true;
}

/* ------------------------------------------------------------------ drawing */

static void panel(surface *s, int x, int y, int w, int h) {
    gfx_fill(s, x, y, w, h, C_PAPER);
    gfx_frame(s, x, y, w, h, C_INK);
}

static void row_text(surface *s, int x, int y, int w, const char *left, const char *right, bool sel) {
    const font *f = &G.font;
    if (sel) gfx_fill(s, x, y - 1, w, f->h - 4, C_PAPER_SEL);
    font_draw(s, f, x + 8, y, left, -1, -1, C_INK);
    if (right) font_draw(s, f, x + w - 8 - font_width(f, right, -1), y, right, -1, -1, sel ? C_INK : C_DIM);
}

static void draw_menu(surface *s) {
    const font *f = &G.font;
    const int lh = f->h - 4, pw = 300;
    gfx_shade(s, 0, 0, SCREEN_W, SCREEN_H);
    char value[64];
    if (S.page == PAGE_MAIN) {
        const int items = n_items(), rows = main_rows(), ph = (rows + 2) * lh + 16;
        const int px = (SCREEN_W - pw) / 2, py = (SCREEN_H - ph) / 2;
        panel(s, px, py, pw, ph);
        int y = py + 8;
        const char *labels[MAX_ITEMS];
        v2_menu_items(labels, MAX_ITEMS);
        for (int r = 0; r < rows; r++, y += lh) {
            const char *t = r == 0 ? T_RESUME[L] : r <= items ? labels[r - 1] : r == items + 1 ? T_RESTART[L] : r == items + 2 ? T_SETTINGS[L] : T_QUIT[L];
            row_text(s, px + 4, y, pw - 8, t, NULL, r == S.cursor);
        }
        text_center(s, f, SCREEN_W / 2, y + lh, T_HINT[L], C_DIM);
        return;
    }
    const int ph = (ROWS_SETTINGS + 2) * lh + 16, px = (SCREEN_W - pw) / 2, py = (SCREEN_H - ph) / 2;
    panel(s, px, py, pw, ph);
    int y = py + 8;
    for (int r = 0; r < ROWS_SETTINGS; r++, y += lh) {
        const char *left = NULL;
        switch (r) {
        case ROW_VOLUME: left = T_VOLUME[L]; snprintf(value, sizeof value, "%d%%", CONF.volume); break;
        case ROW_FLASH: left = T_FLASH[L]; snprintf(value, sizeof value, "%s", T_FLASH_V[CONF.reduce_flash][L]); break;
        case ROW_COLOUR: left = T_COLOUR[L]; snprintf(value, sizeof value, "%s", T_COLOUR_V[CONF.colour][L]); break;
        case ROW_SPEED: left = T_SPEED[L]; snprintf(value, sizeof value, "%d%%", CONF.speed); break;
        case ROW_LANG: left = T_LANG[L]; snprintf(value, sizeof value, "%s", T_LANG_V[CONF.lang]); break;
        default: left = T_BUTTONS[L]; snprintf(value, sizeof value, "%s", T_BUTTONS_V[CONF.swap_ab][L]); break;
        }
        row_text(s, px + 4, y, pw - 8, left, value, r == S.cursor);
    }
    text_center(s, f, SCREEN_W / 2, y + lh, T_HINT_SET[L], C_DIM);
}

static void draw_crash(surface *s) {
    const font *f = &G.font;
    const int lh = f->h - 4;
    gfx_fill(s, 0, 0, SCREEN_W, SCREEN_H, C_BLACK);
    gfx_fill(s, 0, 0, SCREEN_W, lh + 8, RGB(160, 32, 32));
    font_draw(s, &G.bold, 8, 4, T_CRASH[L], -1, -1, C_WHITE);
    uint16_t ls[40], ll[40];
    const int n = text_wrap(f, S.error, SCREEN_W - 16, ls, ll, 40), room = (SCREEN_H - lh - 8 - 2 * lh) / lh;
    if (S.scroll > n - room) S.scroll = n - room > 0 ? n - room : 0;
    int y = lh + 12;
    for (int i = S.scroll; i < n && i < S.scroll + room; i++, y += lh) font_draw(s, f, 8, y, S.error + ls[i], ll[i], -1, C_WHITE);
    text_center(s, f, SCREEN_W / 2, SCREEN_H - 2 * lh - 8, T_SAVED[L], C_STONE);
    text_center(s, f, SCREEN_W / 2, SCREEN_H - lh - 8, hal_can_switch_game() ? T_CRASH_HINT[L] : T_CRASH_HINT_NOLIST[L], C_WHITE);
}

void sysmenu_draw(surface *s) {
    if (S.crashed) draw_crash(s);
    else if (S.open) draw_menu(s);
}
