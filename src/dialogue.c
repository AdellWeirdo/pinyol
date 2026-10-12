/* Dialogue runner: entry layers (first match wins), nodes with conditional lines, gated choices,
 * once/repeat variants, show/use handlers, word pagination and typewriter text. */
#include <string.h>

#include "bp.h"

#define BOX_X 8
#define BOX_W 464
#define TEXT_PAD 16
#define LINES_PER_PAGE 3
#define CHARS_PER_TICK 1 /* 60 characters per second at 60 Hz */

static dlg_state *D = &G.dlg;

static int line_h(void) { return ui_font()->h + 4; }

static void wrap(void) {
    D->nlines = text_wrap(ui_font(), D->text, BOX_W - 2 * TEXT_PAD, D->ls, D->ll, 48);
    D->wrapped_large = G.large_text;
    D->page = 0;
    D->shown = 0;
}

static void set_speaker(const char *spk) {
    snprintf(D->speaker, sizeof D->speaker, "%s", spk ? spk : "");
    D->expr = 0;
    char *colon = strchr(D->speaker, ':');
    if (!colon) return;
    *colon = 0;
    int i = 0;
    const cJSON *e;
    cJSON_ArrayForEach(e, jget(G.game, "expressions")) {
        if (cJSON_IsString(e) && !strcmp(e->valuestring, colon + 1)) D->expr = i;
        i++;
    }
}

static void set_line(const cJSON *l) {
    D->is_sub = false;
    if (cJSON_IsArray(l)) {
        set_speaker(jas(l, 0));
        D->text = jas(l, 1);
    } else if (jstr(l, "sub")) {
        set_speaker("");
        D->is_sub = true;
        D->text = jstr(l, "sub");
    } else {
        set_speaker(jstr(l, "s"));
        D->text = jstr(l, "t");
    }
    if (!D->text) D->text = "";
    effects_run(jget(l, "do"));
    wrap();
}

static void dlg_end(void) {
    D->active = false;
    D->single = false;
    D->choosing = false;
    D->pending_choice = NULL;
    D->ill = NULL;
    G.using_item = NULL;
    layer_remove(L_DLG);
}

static void enter_node(const char *name, int depth);

static void next_line(void) {
    const cJSON *lines = jget(D->node, "lines");
    for (D->line_idx++;; D->line_idx++) {
        const cJSON *l = cJSON_GetArrayItem(lines, D->line_idx);
        if (!l) break;
        if (cJSON_IsObject(l) && !cond_eval(jget(l, "if"))) continue;
        set_line(l);
        return;
    }
    D->nchoices = 0;
    D->choice_rows_font = NULL;
    const cJSON *c;
    cJSON_ArrayForEach(c, jget(D->node, "choices")) {
        if (D->nchoices == 16 || !cond_eval(jget(c, "if"))) continue;
        const char *id = jstr(c, "id");
        if (cJSON_IsTrue(jget(c, "once")) && id && flagf_get("topic:%s.%s", D->file_id, id)) continue;
        D->choices[D->nchoices++] = (cJSON *)c;
    }
    if (D->nchoices) {
        D->choosing = true;
        if (D->sel >= D->nchoices) D->sel = 0;
        return;
    }
    if (jstr(D->node, "next")) enter_node(jstr(D->node, "next"), 0);
    else dlg_end();
}

static void enter_node(const char *name, int depth) {
    static int nest; /* "next" chains without lines recurse; a content cycle must not overflow */
    cJSON *n = jget(jget(D->file, "nodes"), name);
    if (!n || nest > 16) {
        hal_log("dialogue %s: no node %s", D->file_id, name);
        dlg_end();
        return;
    }
    const char *rep = jstr(n, "repeat");
    if (rep && depth < 4 && flagf_get("seen:%s.%s", D->file_id, name)) {
        enter_node(rep, depth + 1);
        return;
    }
    flagf_set(1, "seen:%s.%s", D->file_id, name);
    D->node = n;
    snprintf(D->node_id, sizeof D->node_id, "%s", name);
    D->line_idx = -1;
    D->choosing = false;
    D->sel = 0;
    nest++;
    effects_run(jget(n, "do"));
    if (D->active && D->node == n) next_line();
    nest--;
}

void dlg_open(const char *ref) {
    if (!ref || !*ref) return;
    if (ref[0] == '@') {
        dlg_say(G.pl.speaker, ref + 1, NULL);
        return;
    }
    char file[48];
    const char *dot = strchr(ref, '.');
    snprintf(file, sizeof file, "%.*s", dot ? (int)(dot - ref) : (int)strlen(ref), ref);
    cJSON *d = content_dialogue(file);
    if (!d) {
        hal_log("dialogue %s missing", file);
        return;
    }
    const char *node = dot ? dot + 1 : NULL;
    if (!node) {
        const cJSON *e;
        cJSON_ArrayForEach(e, jget(d, "entry")) if (cond_eval(jget(e, "if"))) {
            node = jstr(e, "node");
            break;
        }
        if (!node) return;
    }
    if (D->active && D->single) hal_log("dialogue %s replaces a one-off line", ref);
    D->active = true;
    D->single = false;
    D->pending_choice = NULL;
    D->ill = NULL;
    D->file = d;
    snprintf(D->file_id, sizeof D->file_id, "%s", file);
    layer_remove(L_DLG); /* always on top, even if a stale entry sits under a sequence */
    layer_push(L_DLG);
    enter_node(node, 0);
}

void dlg_say(const char *speaker, const char *text, const char *ill) {
    if (D->active && !D->single) hal_log("say inside an open dialogue: %.30s", text);
    D->active = true;
    D->single = true;
    D->choosing = false;
    D->pending_choice = NULL;
    D->node = NULL;
    D->ill = ill;
    D->is_sub = speaker && !strcmp(speaker, "SUB"); /* sequences show sound subtitles as speaker "SUB" */
    set_speaker(D->is_sub ? "" : speaker);
    snprintf(D->own, sizeof D->own, "%s", text);
    D->text = D->own;
    wrap();
    layer_remove(L_DLG);
    layer_push(L_DLG);
}

void dlg_show(const char *dlg_id, const char *item) {
    cJSON *d = dlg_id ? content_dialogue(dlg_id) : NULL;
    cJSON *show = jget(d, "show");
    const char *node = jstr(show, item) ? jstr(show, item) : jstr(show, "*");
    if (!node) {
        dlg_say(G.pl.speaker, "No creo que le interese.", NULL);
        return;
    }
    char ref[96];
    snprintf(ref, sizeof ref, "%s.%s", dlg_id, node);
    G.using_item = item;
    dlg_open(ref);
    if (!D->active) G.using_item = NULL;
}

const char *dlg_text(void) { return D->active && D->text ? D->text : ""; }

static void finish_choice(cJSON *c) {
    const char *target = D->pending_target;
    if (cJSON_IsTrue(jget(c, "end")) || !target) {
        dlg_end();
        effects_run(jget(c, "do"));
        return;
    }
    cJSON *file = D->file;
    effects_run(jget(c, "do"));
    if (D->active && D->file == file && !D->single) enter_node(target, 0); /* unless the effects opened another one */
}

static void choose(int i) {
    cJSON *c = D->choices[i];
    const char *id = jstr(c, "id");
    bool repeated = id && flagf_get("topic:%s.%s", D->file_id, id);
    if (id) flagf_set(1, "topic:%s.%s", D->file_id, id);
    D->choosing = false;
    D->pending_target = repeated && jstr(c, "repeat") ? jstr(c, "repeat") : jstr(c, "next");
    const char *text = jstr(c, "text");
    if (text && !cJSON_IsTrue(jget(c, "silent"))) {
        set_speaker(G.pl.speaker);
        D->is_sub = false;
        D->text = text;
        wrap();
        D->pending_choice = c;
        return;
    }
    finish_choice(c);
}

static int page_chars(void) {
    int n = 0;
    for (int i = D->page * LINES_PER_PAGE; i < D->nlines && i < (D->page + 1) * LINES_PER_PAGE; i++)
        n += utf8_count(D->text + D->ls[i], D->ll[i]);
    return n;
}

static int page_lines(void) {
    int n = D->nlines - D->page * LINES_PER_PAGE;
    return n < 1 ? 1 : n > LINES_PER_PAGE ? LINES_PER_PAGE : n;
}

/* Choices may wrap to two lines; rows are laid out from the top of the box. */
/* Each choice's wrapped lines. Wrapping is slow and the layout asks for them many times (choice_y, box_h, touch), in
 * every panel strip of a frame: they are counted when the choices or the font (large text) change. */
static int choice_lines(int i) {
    if (D->choice_rows_font != ui_bold()) {
        D->choice_rows_font = ui_bold();
        for (int k = 0; k < D->nchoices; k++) {
            const char *t = jstr(D->choices[k], "text") ? jstr(D->choices[k], "text") : jstr(D->choices[k], "label");
            uint16_t ls[2], ll[2];
            D->choice_rows[k] = (uint8_t)(t ? text_wrap(ui_bold(), t, BOX_W - 2 * TEXT_PAD - 14, ls, ll, 2) : 1);
        }
    }
    return D->choice_rows[i];
}

static int choice_y(int i) {
    int y = 12;
    for (int k = 0; k < i; k++) y += choice_lines(k) * line_h() + 4;
    return y;
}

static int box_h(void) {
    int lh = line_h();
    if (D->choosing) return choice_y(D->nchoices) + 10;
    int lines = page_lines() < 2 ? 2 : page_lines(); /* never a sliver: at least two lines tall */
    return 22 + lines * lh + 10;
}

/* A line {"s", "t", "pause": ms} leaves a beat of silence after it, box hidden, before the next one. */
static int pause_after(void) {
    if (D->single || !D->node) return 0;
    const cJSON *ln = cJSON_GetArrayItem(jget(D->node, "lines"), D->line_idx);
    return cJSON_IsObject(ln) ? jint(ln, "pause", 0) : 0;
}

static void advance(void) {
    if ((D->page + 1) * LINES_PER_PAGE < D->nlines) {
        D->page++;
        D->shown = 0;
        return;
    }
    if (D->pending_choice) {
        cJSON *c = D->pending_choice;
        D->pending_choice = NULL;
        finish_choice(c);
    } else if (D->single || !D->node) {
        dlg_end();
    } else if (pause_after() > 0) {
        D->hold = pause_after() / TICK_MS;
    } else {
        next_line();
    }
}

#define BLIP_EVERY 5 /* letters between two tones of a voice */

static void blip(void) { /* game.json speakers[...]."blip": a small tone per voice while its text runs */
    const char *id = jstr(jget(jget(G.game, "speakers"), D->speaker), "blip");
    if (id && G.tones && D->shown % BLIP_EVERY == 1) audio_sfx(id, 1);
}

void dlg_tick(void) {
    if (!D->active) {
        layer_remove(L_DLG);
        return;
    }
    if (D->hold > 0) { /* the silence after a line; A cuts it short */
        if (--D->hold == 0 || (G.in.pressed & ACT_OK)) D->hold = 0, next_line();
        return;
    }
    if (D->wrapped_large != G.large_text) wrap();
    uint16_t p = G.in.pressed;
    if (D->choosing) {
        int by = SCREEN_H - box_h() - 6;
        if (G.in.tap)
            for (int i = 0; i < D->nchoices; i++)
                if (G.in.py >= by + choice_y(i) && G.in.py < by + choice_y(i + 1)) {
                    choose(i);
                    return;
                }
        if (p & ACT_UP) D->sel = (D->sel + D->nchoices - 1) % D->nchoices;
        if (p & ACT_DOWN) D->sel = (D->sel + 1) % D->nchoices;
        if (p & ACT_OK) choose(D->sel);
        else if (p & ACT_BACK) /* B picks the farewell/leave option when there is one */
            for (int i = D->nchoices - 1; i >= 0; i--)
                if (cJSON_IsTrue(jget(D->choices[i], "end")) || cJSON_IsTrue(jget(D->choices[i], "bye"))) {
                    choose(i);
                    break;
                }
        return;
    }
    int total = page_chars();
    if ((p & (ACT_OK | ACT_BACK)) || G.in.tap) {
        if (D->shown < total) D->shown = total;
        else sound("advance"), advance();
    } else if (D->shown < total) {
        D->shown += CHARS_PER_TICK;
        blip();
    }
}

static void closeup_at(const asset *a, int by, int *x, int *y) { /* the 2x illustration's corner, above the box */
    *x = (SCREEN_W - 2 * a->w) / 2, *y = by - 2 * a->h - 14;
    if (*y < 6) *y = 6;
}

int dlg_opaque(screen_rect *r, bool *closeup) {
    *closeup = false;
    if (!D->active || D->hold > 0) return 0;
    int bh = box_h(), by = SCREEN_H - bh - 6, n = 0;
    if ((*closeup = D->ill && !D->choosing)) { /* the card around the close-up: gfx_panel(x - 8, y - 8, 2w + 16, 2h + 16) */
        asset *a = gfx_asset(D->ill);
        int x, y;
        closeup_at(a, by, &x, &y);
        if (2 * a->h + 16 > 2 * PANEL_CORNER) r[n++] = (screen_rect){x - 8, y - 8 + PANEL_CORNER, 2 * a->w + 16, 2 * a->h + 16 - 2 * PANEL_CORNER};
    }
    if (bh > 2 * PANEL_CORNER) r[n++] = (screen_rect){BOX_X, by + PANEL_CORNER, BOX_W, bh - 2 * PANEL_CORNER};
    return n;
}

void dlg_render(surface *s, bool shade) {
    if (!D->active || D->hold > 0) return;
    const font *f = ui_font(), *b = ui_bold();
    int lh = line_h(), bh = box_h(), by = SCREEN_H - bh - 6;
    bool ill = D->ill && !D->choosing;
    if (ill) { /* close-up: 2x illustration on a framed card above the box */
        asset *a = gfx_asset(D->ill);
        int x, y;
        closeup_at(a, by, &x, &y);
        if (shade) gfx_shade(s, 0, 0, SCREEN_W, SCREEN_H);
        gfx_panel(s, x - 8, y - 8, 2 * a->w + 16, 2 * a->h + 16);
        gfx_blit2x(s, a, 0, x, y);
    }
    gfx_panel(s, BOX_X, by, BOX_W, bh);
    if (D->choosing) {
        for (int i = 0; i < D->nchoices; i++) {
            int y = by + choice_y(i), rows = choice_lines(i);
            const char *t = jstr(D->choices[i], "text") ? jstr(D->choices[i], "text") : jstr(D->choices[i], "label");
            if (!t) t = "...";
            bool sel = i == D->sel;
            if (sel) {
                gfx_fill(s, BOX_X + 6, y - 2, BOX_W - 12, rows * lh + 4, C_PAPER_SEL);
                gfx_tri(s, BOX_X + 12 + ((int)G.anim_ms / 300) % 2, y + lh / 2 - 6, 6, true, C_TERRA);
            }
            uint16_t ls[2], ll[2];
            int n = text_wrap(b, t, BOX_W - 2 * TEXT_PAD - 14, ls, ll, 2); /* wrapped with the bold metrics */
            for (int k = 0; k < n; k++) font_draw(s, sel ? b : f, BOX_X + TEXT_PAD + 14, y + k * lh, t + ls[k], ll[k], -1, sel ? C_INK : C_BROWN);
        }
        return;
    }
    cJSON *spk = jget(jget(G.game, "speakers"), D->speaker);
    const char *name = D->is_sub ? "Sonido" : jstr(spk, "name");
    if (G.portraits && jstr(spk, "portrait") && !D->is_sub && !ill) { /* framed portrait leaning on the box */
        asset *pt = gfx_asset(klaus_variant(jstr(spk, "portrait")));
        int px = BOX_X + BOX_W - pt->w - 16, py = by - pt->h + 6;
        gfx_panel(s, px - 6, py - 6, pt->w + 12, pt->h + 12);
        gfx_blit(s, pt, D->expr, px, py, 0, false);
    }
    if (name) { /* name tag in the speaker's colour, pinned to the top edge */
        uint16_t col = D->is_sub ? C_BLUEGRAY : hex565(jstr(spk, "color"), C_GREEN);
        int w = font_width(b, name, -1) + 24, ph = b->h + 8;
        gfx_plate(s, BOX_X + 14, by - ph / 2, w, ph, col);
        font_draw(s, b, BOX_X + 26, by - ph / 2 + 4, name, -1, -1, C_PAPER);
    }
    int ty = by + 22, left = D->shown;
    for (int i = D->page * LINES_PER_PAGE, row = 0; i < D->nlines && row < LINES_PER_PAGE && left > 0; i++, row++) {
        int n = utf8_count(D->text + D->ls[i], D->ll[i]);
        font_draw(s, f, BOX_X + TEXT_PAD, ty + row * lh, D->text + D->ls[i], D->ll[i], left, D->is_sub ? C_BROWN : C_INK);
        left -= n;
    }
    if (D->shown >= page_chars()) /* bobbing "more" arrow */
        gfx_tri(s, BOX_X + BOX_W - 30, by + bh - 18 + ((int)G.anim_ms / 250) % 2 * 2, 6, false, C_TERRA);
}
