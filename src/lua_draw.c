/* What a game draws at the screen's full resolution (480x320), over the world: text in its fonts and styles, shapes,
 * pictures, frames. The screen is drawn strip by strip on the console, so a frame's calls are kept in a list and
 * replayed for each strip (draw_overlay). */
#include <math.h>
#include <stdlib.h>
#include <string.h>

#include "lua_api.h"

#define OV_MAX 768                 /* overlay commands per frame */
#define OV_TEXT 12288              /* overlay text bytes per frame */
#define OV_EXT 128                 /* styled texts and turned or scaled pictures per frame (each) */
#define MAX_FONTS 16               /* a game's own fonts, besides the four every game has */

/* ------------------------------------------------------------------ the overlay: text and shapes at 480x320 */

enum { OV_TEXT_OP, OV_FILL, OV_SHADE, OV_PANEL, OV_PLATE, OV_BOX, OV_IMG, OV_NINE };

typedef struct {
    uint8_t op, font, scale, ext; /* ext: 1 + its entry in ov_style (text) or ov_xf (img); 0: none */
    int16_t x, y, w, h, frame;
    uint16_t color, str, len;
    const asset *a;
} ov_cmd;

static ov_cmd ov[OV_MAX];
static char ov_text[OV_TEXT];
static text_style ov_style[OV_EXT];
static struct { float sx, sy, deg; } ov_xf[OV_EXT];
static int nstyle, nxf;
static struct { char name[32]; font f; } vfont[MAX_FONTS]; /* fonts/<name>.fnt, loaded when first used */
static int nvfont;
static int nov, ntext;

static ov_cmd *ov_add(int op) {
    if (nov == OV_MAX) return NULL;
    ov_cmd *c = &ov[nov++];
    memset(c, 0, sizeof *c);
    c->op = (uint8_t)op;
    return c;
}

static const font *font_named(int k) {
    switch (k) {
    case 0: return &G.font;
    case 1: return &G.bold;
    case 2: return &G.font_l;
    case 3: return &G.bold_l;
    default: return k - 4 < nvfont ? &vfont[k - 4].f : &G.font;
    }
}

void draw_overlay(surface *s) {
    for (int i = 0; i < nov; i++) {
        const ov_cmd *c = &ov[i];
        switch (c->op) {
        case OV_TEXT_OP:
            if (c->ext) font_draw_styled(s, font_named(c->font), c->x, c->y, ov_text + c->str, c->len, -1, &ov_style[c->ext - 1]);
            else font_draw(s, font_named(c->font), c->x, c->y, ov_text + c->str, c->len, -1, c->color);
            break;
        case OV_FILL: gfx_fill(s, c->x, c->y, c->w, c->h, c->color); break;
        case OV_SHADE: gfx_shade(s, c->x, c->y, c->w, c->h); break;
        case OV_PANEL: gfx_panel(s, c->x, c->y, c->w, c->h); break;
        case OV_PLATE: gfx_plate(s, c->x, c->y, c->w, c->h, c->color); break;
        case OV_BOX: gfx_frame(s, c->x, c->y, c->w, c->h, c->color); break;
        case OV_NINE: gfx_nine(s, c->a, c->frame, c->x, c->y, c->w, c->h, c->scale); break;
        case OV_IMG:
            if (c->ext) gfx_blit_ex(s, c->a, c->frame, c->x, c->y, ov_xf[c->ext - 1].sx, ov_xf[c->ext - 1].sy, ov_xf[c->ext - 1].deg);
            else if (c->scale == 2) gfx_blit2x(s, c->a, c->frame, c->x, c->y);
            else gfx_blit(s, c->a, c->frame, c->x, c->y, 0, false);
            break;
        }
    }
}

static int font_by_name(lua_State *L, const char *name) { /* the four of every game, or fonts/<name>.fnt */
    static const char *const names[] = {"main", "bold", "large", "large_bold"};
    for (int i = 0; i < 4; i++)
        if (!strcmp(name, names[i])) return i;
    for (int i = 0; i < nvfont; i++)
        if (!strcmp(vfont[i].name, name)) return 4 + i;
    if (!safe_name(name) || strchr(name, '/') || strlen(name) >= sizeof vfont[0].name)
        return luaL_error(L, "font \"%s\": not a font name", name);
    if (nvfont == MAX_FONTS) return luaL_error(L, "font \"%s\": a game can have %d fonts of its own", name, MAX_FONTS);
    char path[384];
    snprintf(path, sizeof path, "%s/fonts/%s.fnt", G.game_dir, name);
    font *f = &vfont[nvfont].f;
    memset(f, 0, sizeof *f);
    if (!font_load(f, path)) return luaL_error(L, "font \"%s\": fonts/%s.fnt is missing or not a font", name, name);
    snprintf(vfont[nvfont].name, sizeof vfont[0].name, "%s", name);
    return 4 + nvfont++;
}

static int font_arg(lua_State *L, int arg) { return font_by_name(L, luaL_optstring(L, arg, "main")); }

static const font *spaced(const font *f, int spacing) { /* the font with its letters further apart: for measuring */
    static font t;
    if (!spacing) return f;
    t = *f;
    for (int c = 0; c < 256; c++) {
        int v = f->adv[c] + spacing;
        t.adv[c] = (uint8_t)(v < 0 ? 0 : v > 255 ? 255 : v);
    }
    return &t;
}

static int utf8_prefix(const char *s, int n, int *chars) { /* bytes of up to *chars characters; *chars counts down */
    int b = 0;
    while (b < n && *chars > 0) {
        b++;
        while (b < n && (s[b] & 0xC0) == 0x80) b++;
        (*chars)--;
    }
    return b;
}

typedef struct {
    int f, al, wrap, chars;
    uint16_t colour;
    bool styled;
    text_style st;
} text_args;

/* text's options, as a table: {color, font, align, width, chars, outline, shadow, shadow_x, shadow_y, gradient,
 * scale, spacing, wave, shake} */
static void text_opts(lua_State *L, int t, text_args *a) {
    static const char *const aligns[] = {"left", "center", "right", NULL};
    lua_getfield(L, t, "font");
    a->f = lua_isnil(L, -1) ? 0 : font_by_name(L, luaL_checkstring(L, -1));
    lua_pop(L, 1);
    lua_getfield(L, t, "align");
    a->al = luaL_checkoption(L, -1, "left", aligns);
    lua_pop(L, 1);
    a->wrap = (int)opt_float(L, t, "width", 0, 0, 2 * SCREEN_W);
    a->chars = (int)opt_float(L, t, "chars", 1 << 30, 0, 1 << 30);
    a->colour = to565(opt_int(L, t, "color", 0xFFFFFF));
    text_style *st = &a->st;
    memset(st, 0, sizeof *st);
    st->color = a->colour;
    lua_getfield(L, t, "outline");
    if ((st->has_outline = !lua_isnil(L, -1))) st->outline = to565(luaL_checkinteger(L, -1));
    lua_pop(L, 1);
    lua_getfield(L, t, "shadow");
    if ((st->has_shadow = !lua_isnil(L, -1))) st->shadow = to565(luaL_checkinteger(L, -1));
    lua_pop(L, 1);
    st->sdx = (int8_t)opt_float(L, t, "shadow_x", 1, -2, 2), st->sdy = (int8_t)opt_float(L, t, "shadow_y", 1, -2, 2);
    lua_getfield(L, t, "gradient");
    if ((st->gradient = !lua_isnil(L, -1))) st->bottom = to565(luaL_checkinteger(L, -1));
    lua_pop(L, 1);
    st->scale = (uint8_t)opt_float(L, t, "scale", 1, 1, 8);
    st->spacing = (int8_t)opt_float(L, t, "spacing", 0, -8, 32);
    st->wave = (uint8_t)opt_float(L, t, "wave", 0, 0, 32), st->shake = (uint8_t)opt_float(L, t, "shake", 0, 0, 16);
    st->tick = (uint32_t)G.ticks;
    a->styled = st->has_outline || st->has_shadow || st->gradient || st->scale > 1 || st->spacing || st->wave || st->shake;
}

static int line_w(const font *f, const char *s, int n, const text_args *a) {
    return a->styled ? font_width(spaced(f, a->st.spacing), s, n) * a->st.scale : font_width(f, s, n);
}

static void text_line(const char *s, int n, int x, int y, const text_args *a) {
    ov_cmd *c = ntext + n <= OV_TEXT ? ov_add(OV_TEXT_OP) : NULL;
    if (!c) return;
    int w = line_w(font_named(a->f), s, n, a);
    memcpy(ov_text + ntext, s, (size_t)n);
    c->str = (uint16_t)ntext, c->len = (uint16_t)n, ntext += n;
    c->x = i16(x - (a->al == 1 ? w / 2 : a->al == 2 ? w : 0)), c->y = i16(y);
    c->font = (uint8_t)a->f, c->color = a->colour;
    if (a->styled && nstyle < OV_EXT) ov_style[nstyle] = a->st, c->ext = (uint8_t)(++nstyle); /* past it: plain */
}

/* text(str, x, y [, colour [, font [, align [, width [, chars]]]]]) or text(str, x, y, {options}) -> width, height;
 * screen pixels (480x320). width wraps the text into lines that fit it; chars shows only that many characters. */
static int l_text(lua_State *L) {
    size_t n = 0;
    const char *s = luaL_checklstring(L, 1, &n);
    int x = num(L, 2), y = num(L, 3);
    text_args a = {0};
    if (lua_istable(L, 4)) text_opts(L, 4, &a);
    else {
        static const char *const aligns[] = {"left", "center", "right", NULL};
        a.f = font_arg(L, 5), a.wrap = optnum(L, 7, 0), a.chars = optnum(L, 8, 1 << 30);
        a.al = luaL_checkoption(L, 6, "left", aligns);
        a.colour = to565(luaL_optinteger(L, 4, 0xFFFFFF));
    }
    if (a.wrap > 2 * SCREEN_W) a.wrap = 2 * SCREEN_W; /* wider is no use, and wrapping costs grow with the line's length */
    const font *f = font_named(a.f);
    int k = a.styled ? a.st.scale : 1, lh = f->h * k, chars = a.chars;
    if (a.wrap <= 0) { /* one line */
        int w = line_w(f, s, (int)n, &a);
        text_line(s, utf8_prefix(s, (int)n, &chars), x, y, &a);
        lua_pushinteger(L, w), lua_pushinteger(L, lh);
        return 2;
    }
    uint16_t starts[32], lens[32];
    int lines = text_wrap(a.styled ? spaced(f, a.st.spacing) : f, s, a.wrap / k, starts, lens, 32), widest = 0;
    for (int i = 0; i < lines; i++) {
        int w = line_w(f, s + starts[i], lens[i], &a);
        widest = w > widest ? w : widest;
        if (chars > 0) text_line(s + starts[i], utf8_prefix(s + starts[i], lens[i], &chars), x, y + i * lh, &a);
    }
    lua_pushinteger(L, widest), lua_pushinteger(L, lines * lh);
    return 2;
}

/* textw(str [, font | {font, scale, spacing}]) -> width, height */
static int l_textw(lua_State *L) {
    size_t n = 0;
    const char *s = luaL_checklstring(L, 1, &n);
    text_args a = {0};
    if (lua_istable(L, 2)) text_opts(L, 2, &a);
    else a.f = font_arg(L, 2); /* before pushing: a pushed result would become argument 2 */
    const font *f = font_named(a.f);
    lua_pushinteger(L, line_w(f, s, (int)n, &a));
    lua_pushinteger(L, f->h * (a.styled ? a.st.scale : 1));
    return 2;
}

static int shape(lua_State *L, int op, bool colour) {
    ov_cmd *c = ov_add(op);
    if (!c) return 0;
    c->x = i16(num(L, 1)), c->y = i16(num(L, 2)), c->w = i16(num(L, 3)), c->h = i16(num(L, 4));
    if (colour) c->color = to565(luaL_optinteger(L, 5, 0xFFFFFF));
    return 0;
}

static int l_rect(lua_State *L) { return shape(L, OV_FILL, true); }
static int l_box(lua_State *L) { return shape(L, OV_BOX, true); }
static int l_shade(lua_State *L) { return shape(L, OV_SHADE, false); }
static int l_panel(lua_State *L) { return shape(L, OV_PANEL, false); }
static int l_plate(lua_State *L) { return shape(L, OV_PLATE, true); }

/* img(id, x, y [, frame [, scale 1|2]]) or img(id, x, y, {frame, scale, scale_x, scale_y, flip_x, flip_y, angle}):
 * a runtime asset at screen resolution; angle in degrees, about the picture's centre */
static int l_img(lua_State *L) {
    const char *id = luaL_checkstring(L, 1);
    asset *a = safe_name(id) ? gfx_asset(id) : NULL;
    ov_cmd *c = !a || a->missing ? NULL : ov_add(OV_IMG);
    if (!c) return 0;
    c->a = a, c->x = i16(num(L, 2)), c->y = i16(num(L, 3)), c->scale = 1;
    if (!lua_istable(L, 4)) {
        lua_Integer f = luaL_optinteger(L, 4, 0);
        c->frame = (int16_t)(f < 0 || f >= a->frames ? 0 : f);
        c->scale = (uint8_t)(luaL_optinteger(L, 5, 1) == 2 ? 2 : 1);
        return 0;
    }
    lua_Integer f = opt_int(L, 4, "frame", 0);
    c->frame = (int16_t)(f < 0 || f >= a->frames ? 0 : f);
    float k = opt_float(L, 4, "scale", 1, -16, 16);
    float sx = opt_float(L, 4, "scale_x", k, -16, 16), sy = opt_float(L, 4, "scale_y", k, -16, 16);
    float deg = opt_float(L, 4, "angle", 0, -1e6f, 1e6f);
    if (opt_bool(L, 4, "flip_x", false)) sx = -sx;
    if (opt_bool(L, 4, "flip_y", false)) sy = -sy;
    if (deg == 0 && sx == sy && (sx == 1 || sx == 2)) c->scale = (uint8_t)sx; /* the plain ways, faster */
    else if (nxf < OV_EXT) ov_xf[nxf].sx = sx, ov_xf[nxf].sy = sy, ov_xf[nxf].deg = deg, c->ext = (uint8_t)(++nxf);
    return 0;
}

/* frame(id, x, y, w, h [, scale [, frame]]): a box drawn from the picture's thirds: its corners once, its edges and
 * middle repeated (a nine-slice frame, as GB Studio's frame.png or a windowskin) */
static int l_frame(lua_State *L) {
    const char *id = luaL_checkstring(L, 1);
    asset *a = safe_name(id) ? gfx_asset(id) : NULL;
    ov_cmd *c = !a || a->missing ? NULL : ov_add(OV_NINE);
    if (!c) return 0;
    c->a = a, c->x = i16(num(L, 2)), c->y = i16(num(L, 3)), c->w = i16(num(L, 4)), c->h = i16(num(L, 5));
    lua_Integer k = luaL_optinteger(L, 6, 1), f = luaL_optinteger(L, 7, 0);
    c->scale = (uint8_t)(k < 1 ? 1 : k > 8 ? 8 : k);
    c->frame = (int16_t)(f < 0 || f >= a->frames ? 0 : f);
    return 0;
}

/* ------------------------------------------------------------------ the list's life */

void draw_frame_begin(void) { nov = ntext = nstyle = nxf = 0; }

void draw_free(void) {
    draw_frame_begin();
    for (int i = 0; i < nvfont; i++) free(vfont[i].f.bits);
    nvfont = 0;
}

bool draw_covers_screen(void) {
    const ov_cmd *c = nov ? &ov[0] : NULL;
    int k = c && c->op == OV_IMG ? c->scale : 0;
    return k && !c->ext && !c->a->mask && c->x <= 0 && c->y <= 0 && c->x + k * c->a->w >= SCREEN_W &&
           c->y + k * c->a->h >= SCREEN_H;
}

void draw_register(lua_State *L) {
    static const luaL_Reg F[] = {
        {"text", l_text}, {"textw", l_textw}, {"rect", l_rect}, {"box", l_box}, {"shade", l_shade}, {"panel", l_panel},
        {"plate", l_plate}, {"img", l_img}, {"frame", l_frame}, {NULL, NULL}};
    lua_pushglobaltable(L);
    luaL_setfuncs(L, F, 0);
    lua_pop(L, 1);
}
