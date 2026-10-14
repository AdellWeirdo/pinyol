/* The console's own screen, part of the firmware in the board's flash: every game on the card, then any only in
 * the flash image (those play without music), and "Apagar". Tap a row; or move with the d-pad or C and press A
 * (BOOT, while the buttons are not wired). Drawn with the engine's gfx, in a font borrowed from the first game. */
#include "launcher.h"

#include "cable.h"

#include <dirent.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>

#include "bp.h"
#include "cJSON.h"
#include "display.h"
#include "freertos/FreeRTOS.h"
#include "freertos/task.h"
#include "input.h"
#include "power.h"

#define TOP 60     /* first game row */
#define ROW 102    /* row pitch with two games, room for a thumbnail; more games share the height, without one */
#define TW LAUNCHER_THUMB_W
#define TH LAUNCHER_THUMB_H
#define LEFT 24
#define OFF_X 336  /* "Apagar", bottom right */
#define OFF_Y 270
#define OFF_W 120
#define OFF_H 38

/* pinyol's colours (its brand manual), the console's own screens only: games keep the engine's defaults (theme()) */
#define L_BG RGB(0x0B, 0x0E, 0x1F)       /* ink */
#define L_PLATE RGB(0x1C, 0x23, 0x50)
#define L_PLATE_SEL RGB(0x2B, 0x33, 0x68)
#define L_TEXT RGB(0xEE, 0xF0, 0xFF)     /* paper */
#define L_DIM RGB(0x8F, 0x97, 0xCC)
#define L_CHERRY RGB(0xE8, 0x34, 0x4E)
#define L_GOLD RGB(0xFF, 0xC9, 0x4A)

/* the logo, already on L_BG (brand.py): copied a row at a time */
extern const uint8_t logo_small_start[] asm("_binary_logo_small_rgb565_start");
extern const uint8_t logo_big_start[] asm("_binary_logo_big_rgb565_start");
#define LOGO_S_W 63
#define LOGO_S_H 40
#define LOGO_B_W 254
#define LOGO_B_H 160

static void logo(uint16_t *px, const uint8_t *src, int w, int h, int x, int y) {
    for (int r = 0; r < h; r++) memcpy(px + (y + r) * SCREEN_W + x, src + r * w * 2, w * 2);
}

static font bold, regular;
static int last; /* the row chosen last time: back from a game, its own row is the one marked */
static char menu_dir[96]; /* the console's menu, a pinyol game (CONSOLE_MENU_ID): not in the list, run before it */

static uint16_t avg4(uint16_t a, uint16_t b, uint16_t c, uint16_t d) { /* RGB565, channel by channel */
    int r = (a >> 11) + (b >> 11) + (c >> 11) + (d >> 11);
    int g = ((a >> 5) & 63) + ((b >> 5) & 63) + ((c >> 5) & 63) + ((d >> 5) & 63);
    int bl = (a & 31) + (b & 31) + (c & 31) + (d & 31);
    return (uint16_t)((r / 4) << 11 | (g / 4) << 5 | bl / 4);
}

static uint16_t *load_thumb(const char *dir) { /* BG_TITLE is 240x160, the world's size: each 2x2 block averaged */
    char path[160];
    snprintf(path, sizeof path, "%s/assets/BG_TITLE.rgb565", dir);
    long len = 0;
    uint16_t *src = (uint16_t *)read_file(path, &len), *t = NULL;
    if (src && len == 4L * TW * TH * 2 && (t = malloc(TW * TH * 2))) /* any other size: no thumbnail */
        for (int y = 0; y < TH; y++)
            for (int x = 0; x < TW; x++) {
                const uint16_t *p = src + 2 * y * 2 * TW + 2 * x;
                t[y * TW + x] = avg4(p[0], p[1], p[2 * TW], p[2 * TW + 1]);
            }
    free(src);
    return t;
}

static void add_games(const char *root, bool flash, launcher_game *g, int *n, int max) {
    char path[160];
    snprintf(path, sizeof path, "%s/games", root);
    DIR *d = opendir(path);
    if (!d) return;
    for (struct dirent *e; *n < max && (e = readdir(d));) {
        bool dup = e->d_name[0] == '.';
        if (!strcmp(e->d_name, CONSOLE_MENU_ID)) { /* the menu: the card's copy first, as for any game */
            if (!menu_dir[0]) snprintf(menu_dir, sizeof menu_dir, "%s/games/%s", root, e->d_name);
            continue;
        }
        for (int i = 0; i < *n && !dup; i++) dup = !strcmp(g[i].id, e->d_name); /* the card's copy has the music */
        if (dup) continue;
        launcher_game *x = &g[*n];
        *x = (launcher_game){.no_music = flash};
        snprintf(x->id, sizeof x->id, "%s", e->d_name);
        snprintf(x->dir, sizeof x->dir, "%s/games/%s", root, e->d_name);
        snprintf(path, sizeof path, "%s/game.json", x->dir);
        long len;
        char *txt = read_file(path, &len);
        cJSON *j = txt ? cJSON_Parse(txt) : NULL;
        free(txt);
        if (!j) continue; /* not a game folder */
        const cJSON *t = cJSON_GetObjectItem(j, "title"), *s = cJSON_GetObjectItem(j, "subtitle");
        snprintf(x->title, sizeof x->title, "%s", cJSON_IsString(t) ? t->valuestring : x->id);
        snprintf(x->subtitle, sizeof x->subtitle, "%s", cJSON_IsString(s) ? s->valuestring : "");
        cJSON_Delete(j);
        x->thumb = load_thumb(x->dir);
        (*n)++;
    }
    closedir(d);
}

int launcher_scan(launcher_game *g, int max) {
    int n = 0;
    for (int i = 0; i < max; i++) { /* scanned again (a game came over the cable): the old thumbnails go */
        free(g[i].thumb);
        g[i].thumb = NULL;
    }
    menu_dir[0] = 0; /* the menu found again too: one sent over the cable to the card replaces the flash's */
    add_games("/sdcard", false, g, &n, max);
    add_games("/flash", true, g, &n, max);
    char path[160];
    for (int i = 0; i < n && (!bold.bits || !regular.bits); i++) { /* every game ships the engine's fonts */
        snprintf(path, sizeof path, "%s/fonts/FONT_BOLD_L.fnt", g[i].dir);
        if (!bold.bits && !font_load(&bold, path)) bold = (font){0};
        snprintf(path, sizeof path, "%s/fonts/FONT_MAIN.fnt", g[i].dir);
        if (!regular.bits && !font_load(&regular, path)) regular = (font){0};
    }
    for (int i = 0; i < n; i++) hal_log("launcher: %s \"%s\" in %s", g[i].id, g[i].title, g[i].dir);
    return n;
}

static void theme(void) { /* the engine's defaults: G is cleared between games */
    G.th = (ui_theme){D_INK, D_OCHRE, D_TERRA, D_PAPER, D_PAPER_SEL, D_DIM, D_BROWN, false};
}

static int shown(int n) { return n < LAUNCHER_ROWS ? n : LAUNCHER_ROWS; }
static int row_h(int n) { return shown(n) <= 2 ? ROW : (OFF_Y - 12 - TOP) / shown(n); }

static int row_at(int x, int y, int n, int first) { /* game index, n for "Apagar", -1 for nothing */
    if (x >= OFF_X && x < OFF_X + OFF_W && y >= OFF_Y && y < OFF_Y + OFF_H) return n;
    if (x < LEFT || x >= SCREEN_W - LEFT || y < TOP) return -1;
    int i = (y - TOP) / row_h(n);
    return i < shown(n) && (y - TOP) % row_h(n) < row_h(n) - 10 ? first + i : -1;
}

static void render(uint16_t *px, const launcher_game *g, int n, int sel, int first) {
    surface s = {.px = px, .w = SCREEN_W, .h = SCREEN_H};
    theme();
    gfx_fill(&s, 0, 0, SCREEN_W, SCREEN_H, L_BG);
    gfx_fill(&s, LEFT, 48, SCREEN_W - 2 * LEFT, 2, L_CHERRY);
    logo(px, logo_small_start, LOGO_S_W, LOGO_S_H, LEFT - 4, 4);
    const char *brand = "Cirera";
    font_draw(&s, &bold, SCREEN_W - LEFT - font_width(&bold, brand, -1), 14, brand, -1, -1, L_TEXT);
    int h = row_h(n);
    if (first > 0) gfx_tri(&s, SCREEN_W / 2 - 8, 36, 8, false, L_DIM); /* more above (drawn pointing down: a cue) */
    if (first + shown(n) < n) gfx_tri(&s, SCREEN_W / 2 - 8, OFF_Y - 12, 8, false, L_GOLD); /* more below */
    for (int i = first; i < first + shown(n); i++) {
        int y = TOP + (i - first) * h, ph = h - 10, tx = LEFT + 30;
        gfx_plate(&s, LEFT, y, SCREEN_W - 2 * LEFT, ph, i == sel ? L_PLATE_SEL : L_PLATE);
        if (i == sel) gfx_tri(&s, LEFT + 12, y + ph / 2 - 6, 6, true, L_CHERRY);
        if (g[i].thumb && ph >= TH + 8) { /* the game's own title picture, in an ink frame */
            int x0 = LEFT + 26, y0 = y + (ph - TH) / 2;
            gfx_fill(&s, x0 - 2, y0 - 2, TW + 4, TH + 4, L_BG);
            for (int r = 0; r < TH; r++) memcpy(px + (y0 + r) * SCREEN_W + x0, g[i].thumb + r * TW, TW * 2);
            tx = x0 + TW + 16;
        }
        bool sub = g[i].subtitle[0] && ph >= bold.h + regular.h + 8; /* three or four games: the title alone */
        int ty = y + (ph - bold.h - (sub ? regular.h + 2 : 0)) / 2;
        if (ty < y + 2) ty = y + 2;
        font_draw(&s, &bold, tx, ty, g[i].title, -1, -1, L_TEXT);
        if (sub) font_draw(&s, &regular, tx, ty + bold.h + 2, g[i].subtitle, -1, -1, L_DIM);
        if (g[i].no_music) { /* on the title's line, against the plate's right edge */
            const char *m = "sin música";
            font_draw(&s, &regular, SCREEN_W - LEFT - 14 - font_width(&regular, m, -1), ty + 2, m, -1, -1, L_GOLD);
        }
    }
    gfx_plate(&s, OFF_X, OFF_Y, OFF_W, OFF_H, sel == n ? L_PLATE_SEL : L_PLATE);
    if (sel == n) gfx_tri(&s, OFF_X + 12, OFF_Y + OFF_H / 2 - 6, 6, true, L_CHERRY);
    font_draw(&s, &bold, OFF_X + 30, OFF_Y + (OFF_H - bold.h) / 2, "Apagar", -1, -1, L_TEXT);
}

int launcher_choose(uint16_t *frames[2], const launcher_game *g, int n) {
    int sel = last < n ? last : 0, rows = n + 1, cur = 0, chosen = -2, first = 0;
    bool dirty = true;
    hal_input was = input_poll(); /* whatever is held on arrival (the tap that left a game) is not a choice */
    while (chosen == -2) {
        hal_input in = input_poll();
        uint16_t pressed = in.held & ~was.held;
        int hit = in.touch && !was.touch ? row_at(in.px, in.py, n, first) : -1;
        was = in;
        if (pressed & (ACT_DOWN | ACT_NEXT)) sel = (sel + 1) % rows, dirty = true;
        if (pressed & ACT_UP) sel = (sel + rows - 1) % rows, dirty = true;
        if (hit >= 0) sel = hit, dirty = true;
        if (hit >= 0 || (pressed & ACT_OK)) chosen = sel;
        if (power_critical()) chosen = n;
        if (cable_wanted()) return LAUNCHER_CABLE; /* the editor sends a game: it is played as soon as it is here */
        if (sel < n && sel < first) first = sel; /* the window follows the selection */
        if (sel < n && sel >= first + shown(n)) first = sel - shown(n) + 1;
        if (dirty) {
            render(frames[cur], g, n, sel, first);
            display_submit(frames[cur]);
            cur ^= 1;
            dirty = false;
        }
        vTaskDelay(pdMS_TO_TICKS(16));
    }
    for (int k = 0; k < 180; k++) { /* at most 3 s: a pin stuck low must not keep the list forever */
        hal_input in = input_poll();
        if (!in.held && !in.touch) break;
        vTaskDelay(pdMS_TO_TICKS(16));
    }
    if (chosen < n) last = chosen;
    return chosen == n ? -1 : chosen; /* released first: the game's title must not read this press as its own */
}

void launcher_message(uint16_t *frame, const char *text, int percent) {
    surface s = {.px = frame, .w = SCREEN_W, .h = SCREEN_H};
    theme();
    gfx_fill(&s, 0, 0, SCREEN_W, SCREEN_H, L_BG);
    font_draw(&s, &bold, (SCREEN_W - font_width(&bold, text, -1)) / 2, 120, text, -1, -1, L_TEXT);
    if (percent >= 0) {
        gfx_fill(&s, 80, 170, SCREEN_W - 160, 14, L_PLATE);
        gfx_fill(&s, 82, 172, (SCREEN_W - 164) * (percent > 100 ? 100 : percent) / 100, 10, L_CHERRY);
    }
    display_submit(frame);
}

void launcher_splash(uint16_t *frame, bool with_logo) {
    for (int i = 0; i < SCREEN_W * SCREEN_H; i++) frame[i] = L_BG;
    if (with_logo)
        logo(frame, logo_big_start, LOGO_B_W, LOGO_B_H, (SCREEN_W - LOGO_B_W) / 2, (SCREEN_H - LOGO_B_H) / 2 - 8);
}

const char *launcher_menu_dir(void) { return menu_dir[0] ? menu_dir : NULL; }
