/* Assets (Asset Factory runtime format), blitting, 1-bit fonts and text wrapping. */
#include <stdlib.h>
#include <string.h>

#include "bp.h"

#define MAX_ASSETS 320
#define SLOTS 512 /* hash of asset ids, open addressing (> MAX_ASSETS): lookups happen many times a frame */

static asset assets[MAX_ASSETS];
static int16_t slot[SLOTS]; /* index into assets + 1; 0 = empty */
static uint16_t oom_pixel = 0xF81F; /* stand-in if even a placeholder cannot be allocated */
static int nassets;
static char forced[16][32];
static int nforced;

void gfx_reset(void) {
    for (int i = 0; i < nassets; i++) {
        if (assets[i].pixels != &oom_pixel) free(assets[i].pixels);
        free(assets[i].mask);
    }
    nassets = 0;
    nforced = 0;
    memset(slot, 0, sizeof slot);
}

void gfx_force_missing(const char *id) {
    if (nforced < 16) snprintf(forced[nforced++], sizeof forced[0], "%s", id);
}

static void placeholder(asset *a, int w, int h, int frames) {
    a->w = w > 0 && w <= 512 ? w : 16;
    a->h = h > 0 && h <= 512 ? h : 16;
    a->frames = frames > 0 && frames <= 64 ? frames : 1;
    a->ax = a->w / 2;
    a->ay = a->h - 1;
    if (a->pixels != &oom_pixel) free(a->pixels);
    free(a->mask);
    a->mask = NULL;
    a->pixels = malloc((size_t)a->w * a->h * a->frames * 2);
    if (!a->pixels) {
        a->w = a->h = a->frames = 1;
        a->ax = a->ay = 0;
        a->pixels = &oom_pixel;
        a->missing = true;
        return;
    }
    for (int f = 0; f < a->frames; f++)
        for (int y = 0; y < a->h; y++)
            for (int x = 0; x < a->w; x++)
                a->pixels[(size_t)f * a->w * a->h + y * a->w + x] = ((x / 4 + y / 4) & 1) ? 0xF81F : C_INK;
    a->missing = true;
}

static bool load_asset(asset *a) {
    for (int i = 0; i < nforced; i++)
        if (!strcmp(forced[i], a->id)) return false;
    char rel[96];
    snprintf(rel, sizeof rel, "assets/%s.meta.json", a->id);
    cJSON *meta = json_file(rel);
    if (!meta) return false;
    a->w = jint(meta, "w", 0);
    a->h = jint(meta, "h", 0);
    a->frames = jint(meta, "frames", 1);
    cJSON *anc = jget(meta, "anchor"), *fms = jget(meta, "frame_ms");
    a->ax = jai(anc, 0, a->w / 2);
    a->ay = jai(anc, 1, a->h - 1);
    a->frame_ms = jai(fms, 0, 0);
    cJSON_Delete(meta);
    if (a->w <= 0 || a->h <= 0 || a->frames <= 0 || a->w > 1024 || a->h > 1024 || a->frames > 64) return false;

    char path[384];
    long len = 0;
    size_t npx = (size_t)a->w * a->h * a->frames;
    snprintf(path, sizeof path, "%s/assets/%s.rgb565", G.game_dir, a->id);
    uint8_t *raw = (uint8_t *)read_file(path, &len);
    if (!raw || (size_t)len != npx * 2) {
        hal_log("asset %s: pixel file size %ld, expected %zu", a->id, len, npx * 2);
        free(raw);
        placeholder(a, a->w, a->h, a->frames);
        return true; /* keep the declared geometry */
    }
    a->pixels = malloc(npx * 2);
    if (!a->pixels) {
        free(raw);
        return false;
    }
    for (size_t i = 0; i < npx; i++) a->pixels[i] = (uint16_t)(raw[2 * i] | (raw[2 * i + 1] << 8)); /* LE */
    free(raw);
    snprintf(path, sizeof path, "%s/assets/%s.mask", G.game_dir, a->id);
    a->mask = (uint8_t *)read_file(path, &len);
    if (a->mask && (size_t)len != (size_t)((a->w + 7) / 8) * a->h * a->frames) {
        hal_log("asset %s: bad mask size, drawing opaque", a->id);
        free(a->mask);
        a->mask = NULL;
    }
    return true;
}

static asset *lookup(const char *id, bool quiet) {
    static asset none;
    char key[32];
    snprintf(key, sizeof key, "%s", id ? id : ""); /* compare truncated, so long ids still hit the cache */
    unsigned h = 5381;
    for (const char *c = key; *c; c++) h = h * 33 ^ (unsigned char)*c;
    for (h &= SLOTS - 1; slot[h]; h = (h + 1) & (SLOTS - 1))
        if (!strcmp(assets[slot[h] - 1].id, key)) return &assets[slot[h] - 1];
    if (nassets == MAX_ASSETS) {
        if (!none.pixels) placeholder(&none, 16, 16, 1);
        return &none;
    }
    slot[h] = (int16_t)(nassets + 1);
    asset *a = &assets[nassets++];
    memset(a, 0, sizeof *a);
    snprintf(a->id, sizeof a->id, "%s", key);
    if (!load_asset(a)) {
        if (!quiet) hal_log("asset %s missing, using placeholder", key);
        placeholder(a, 16, 16, 1);
    }
    return a;
}

asset *gfx_asset(const char *id) { return lookup(id, false); }
asset *gfx_asset_opt(const char *id) { return lookup(id, true); } /* a sprite a game may leave out: no log */

bool gfx_opaque(const asset *a, int frame, int u, int v) {
    if (!a->mask) return true;
    int stride = (a->w + 7) / 8;
    return a->mask[(size_t)frame * stride * a->h + v * stride + u / 8] & (0x80 >> (u % 8));
}

static inline uint16_t blend50(uint16_t a, uint16_t b) { return ((a & 0xF7DE) >> 1) + ((b & 0xF7DE) >> 1); }

/* Visible part of a span [x, x+w) on a line [0, lim): first offset into the span, and how many. */
static inline int clip(int x, int w, int lim, int *first) {
    *first = x < 0 ? -x : 0;
    return (x + w > lim ? lim - x : w) - *first;
}

/* Unrotated blit of the first `rows` rows: clipped once, the mask read a row at a time, rows without a mask
 * copied whole. This is every sprite and background in the world, so it is the hot path on the console. */
static void blit_plain(surface *s, const asset *a, int frame, int x, int y, int rows, bool half) {
    int u0, v0, n = clip(x, a->w, s->w, &u0), m = clip(y, rows < a->h ? rows : a->h, s->h, &v0);
    if (n <= 0 || m <= 0) return;
    const uint16_t *src = a->pixels + (size_t)frame * a->w * a->h;
    int stride = (a->w + 7) / 8;
    const uint8_t *mask = a->mask ? a->mask + (size_t)frame * stride * a->h : NULL;
    for (int v = v0; v < v0 + m; v++) {
        const uint16_t *sp = src + v * a->w;
        uint16_t *d = s->px + (y + v) * s->w + x;
        if (!mask && !half) {
            memcpy(d + u0, sp + u0, (size_t)n * sizeof *d);
            continue;
        }
        const uint8_t *mr = mask ? mask + v * stride : NULL;
        for (int u = u0; u < u0 + n; u++) {
            if (mr && !(mr[u >> 3] & (0x80 >> (u & 7)))) continue;
            d[u] = half ? blend50(d[u], sp[u]) : sp[u];
        }
    }
}

/* rot: quarter turns clockwise. Forward map (u,v) -> rot1 (h-1-v,u), rot2 (w-1-u,h-1-v), rot3 (v,w-1-u). */
void gfx_blit(surface *s, const asset *a, int frame, int x, int y, int rot, bool half) {
    if (frame < 0 || frame >= a->frames) frame = 0;
    rot &= 3;
    if (rot == 0) {
        blit_plain(s, a, frame, x, y, a->h, half);
        return;
    }
    int rw = (rot & 1) ? a->h : a->w, rh = (rot & 1) ? a->w : a->h;
    const uint16_t *src = a->pixels + (size_t)frame * a->w * a->h;
    for (int ry = 0; ry < rh; ry++) {
        int dy = y + ry;
        if (dy < 0 || dy >= s->h) continue;
        for (int rx = 0; rx < rw; rx++) {
            int dx = x + rx;
            if (dx < 0 || dx >= s->w) continue;
            int u, v;
            switch (rot) {
            case 0: u = rx; v = ry; break;
            case 1: u = ry; v = a->h - 1 - rx; break;
            case 2: u = a->w - 1 - rx; v = a->h - 1 - ry; break;
            default: u = a->w - 1 - ry; v = rx; break;
            }
            if (!gfx_opaque(a, frame, u, v)) continue;
            uint16_t c = src[v * a->w + u];
            uint16_t *d = &s->px[dy * s->w + dx];
            *d = half ? blend50(*d, c) : c;
        }
    }
}

void gfx_blit_rows(surface *s, const asset *a, int frame, int x, int y, int rows) {
    if (frame < 0 || frame >= a->frames) frame = 0;
    blit_plain(s, a, frame, x, y, rows, false);
}

void gfx_blit2x(surface *s, const asset *a, int frame, int x, int y) {
    if (frame < 0 || frame >= a->frames) frame = 0;
    const uint16_t *src = a->pixels + (size_t)frame * a->w * a->h;
    int stride = (a->w + 7) / 8;
    const uint8_t *mask = a->mask ? a->mask + (size_t)frame * stride * a->h : NULL;
    for (int v = 0; v < a->h; v++) {
        int dy = y + 2 * v;
        if (dy < 0 || dy + 1 >= s->h) continue;
        const uint8_t *mr = mask ? mask + v * stride : NULL;
        uint16_t *row = s->px + dy * s->w;
        for (int u = 0; u < a->w; u++) {
            int dx = x + 2 * u;
            if (dx < 0 || dx + 1 >= s->w || (mr && !(mr[u >> 3] & (0x80 >> (u & 7))))) continue;
            uint16_t c = src[v * a->w + u], *d = row + dx;
            d[0] = d[1] = d[s->w] = d[s->w + 1] = c;
        }
    }
}

/* Rows are walked two pixels at a time where aligned (one 32-bit access instead of two). px2 may alias the
 * 16-bit pixels: without it, strict aliasing lets the compiler reorder the wide and narrow accesses. */
typedef uint32_t __attribute__((may_alias)) px2;

void gfx_fill(surface *s, int x, int y, int w, int h, uint16_t c) {
    int i0, j0, n = clip(x, w, s->w, &i0), m = clip(y, h, s->h, &j0);
    uint32_t cc = c * 0x00010001u;
    for (int j = 0; j < m; j++) {
        uint16_t *d = s->px + (y + j0 + j) * s->w + x + i0;
        int i = 0;
        if (n > 0 && ((uintptr_t)d & 2)) d[i++] = c;
        for (; i + 1 < n; i += 2) *(px2 *)(d + i) = cc;
        if (i < n) d[i] = c;
    }
}

void gfx_frame(surface *s, int x, int y, int w, int h, uint16_t c) {
    gfx_fill(s, x, y, w, 2, c);
    gfx_fill(s, x, y + h - 2, w, 2, c);
    gfx_fill(s, x, y, 2, h, c);
    gfx_fill(s, x + w - 2, y, 2, h, c);
}

/* Halving every channel: with bit 0 of each 16-bit lane masked off, two pixels share one 32-bit shift. */
void gfx_shade(surface *s, int x, int y, int w, int h) {
    int i0, j0, n = clip(x, w, s->w, &i0), m = clip(y, h, s->h, &j0);
    for (int j = 0; j < m; j++) {
        uint16_t *d = s->px + (y + j0 + j) * s->w + x + i0;
        int i = 0;
        if (n > 0 && ((uintptr_t)d & 2)) d[i] = (d[i] & 0xF7DE) >> 1, i++;
        for (; i + 1 < n; i += 2) {
            px2 *q = (px2 *)(d + i);
            *q = (*q & 0xF7DEF7DEu) >> 1;
        }
        if (i < n) d[i] = (d[i] & 0xF7DE) >> 1;
    }
}

void gfx_upscale2x(const surface *src, surface *dst) {
    for (int y = 0; y < src->h; y++) {
        uint16_t *d0 = dst->px + (2 * y) * dst->w;
        const uint16_t *sp = src->px + y * src->w;
        px2 *pair = (px2 *)d0; /* rows start at even pixels: each source pixel is one aligned word */
        for (int x = 0; x < src->w; x++) pair[x] = sp[x] * 0x00010001u;
        memcpy(d0 + dst->w, d0, (size_t)src->w * 2 * sizeof *d0); /* the second row is the first again */
    }
}

/* ponytail: fixed per-channel scale toward blue-grey; a LUT or palette swap if art needs finer control */
void gfx_tint_dusk(surface *s) {
    for (int i = 0; i < s->w * s->h; i++) {
        uint16_t c = s->px[i];
        int r = (c >> 11) * 5 / 8, g = ((c >> 5) & 63) * 11 / 16, b = (c & 31) * 13 / 16 + 2;
        s->px[i] = (uint16_t)((r << 11) | (g << 5) | (b > 31 ? 31 : b));
    }
}

/* Cards and signs in the style of the approved references: paper, 2 px ink border with cut corners,
 * a thin tan inner line and a soft drop shadow. */
/* Mecha theme ("corners": "cut"): top-left and bottom-right corners chamfered by c pixels. */
static void chamfer(surface *s, int x, int y, int w, int h, uint16_t col, int c, bool shade) {
    for (int r = 0; r < h; r++) {
        int l = r < c ? c - r : 0, rt = r >= h - c ? r - (h - c) + 1 : 0;
        if (shade) gfx_shade(s, x + l, y + r, w - l - rt, 1);
        else gfx_fill(s, x + l, y + r, w - l - rt, 1, col);
    }
}

static void rounded(surface *s, int x, int y, int w, int h, uint16_t fill, int shadow) {
    if (G.th.cut) {
        int c = h >= 24 ? 8 : 5;
        if (shadow) chamfer(s, x + shadow, y + shadow, w, h, 0, c, true);
        chamfer(s, x, y, w, h, C_INK, c, false);
        chamfer(s, x + 2, y + 2, w - 4, h - 4, fill, c - 1, false);
        return;
    }
    if (shadow) { /* the shadow shows only right and below: the fill covers the rest, so it is not shaded */
        gfx_shade(s, x + w - 2, y + shadow, shadow + 2, h);
        gfx_shade(s, x + shadow, y + h - 2, w - shadow - 2, shadow + 2);
    }
    gfx_fill(s, x + 2, y + 2, w - 4, h - 4, fill);
    gfx_fill(s, x + 2, y, w - 4, 2, C_INK);
    gfx_fill(s, x + 2, y + h - 2, w - 4, 2, C_INK);
    gfx_fill(s, x, y + 2, 2, h - 4, C_INK);
    gfx_fill(s, x + w - 2, y + 2, 2, h - 4, C_INK);
    gfx_fill(s, x + 1, y + 1, 1, 1, C_INK);
    gfx_fill(s, x + w - 2, y + 1, 1, 1, C_INK);
    gfx_fill(s, x + 1, y + h - 2, 1, 1, C_INK);
    gfx_fill(s, x + w - 2, y + h - 2, 1, 1, C_INK);
}

void gfx_panel(surface *s, int x, int y, int w, int h) {
    rounded(s, x, y, w, h, C_PAPER, 3);
    if (G.th.cut) { /* cockpit readout: rules top and bottom, a signal bar on the top edge */
        int bar = w / 5 > 40 ? 40 : w / 5;
        gfx_fill(s, x + 12, y + 5, w - 24, 1, C_PAPER_SEL);
        gfx_fill(s, x + 12, y + h - 6, w - 24, 1, C_PAPER_SEL);
        gfx_fill(s, x + w - bar - 12, y, bar, 3, C_TERRA);
        gfx_fill(s, x + 4, y + h - 9, 2, 4, C_OCHRE);
        return;
    }
    gfx_fill(s, x + 4, y + 4, w - 8, 1, C_PAPER_SEL);
    gfx_fill(s, x + 4, y + h - 5, w - 8, 1, C_PAPER_SEL);
    gfx_fill(s, x + 4, y + 4, 1, h - 8, C_PAPER_SEL);
    gfx_fill(s, x + w - 5, y + 4, 1, h - 8, C_PAPER_SEL);
}

void gfx_plate(surface *s, int x, int y, int w, int h, uint16_t fill) {
    rounded(s, x, y, w, h, fill, 2);
    int in = G.th.cut ? 6 : 2;
    gfx_fill(s, x + in, y + 2, w - in - 2, 1, (uint16_t)(((fill & 0xF7DE) >> 1) + ((C_PAPER & 0xF7DE) >> 1))); /* top light */
}

void gfx_disc(surface *s, int cx, int cy, int r, uint16_t c) {
    for (int j = -r; j <= r; j++) {
        int half = 0;
        while ((half + 1) * (half + 1) + j * j <= r * r) half++;
        gfx_fill(s, cx - half, cy + j, 2 * half + 1, 1, c);
    }
}

void gfx_tri(surface *s, int x, int y, int size, bool right, uint16_t c) {
    for (int k = 0; k < size; k++) {
        if (right) gfx_fill(s, x + k, y + k, 1, 2 * (size - k) - 1, c);
        else gfx_fill(s, x + k, y + k, 2 * (size - k) - 1, 1, c);
    }
}

uint16_t hex565(const char *h, uint16_t dflt) {
    unsigned r, g, b;
    if (!h || sscanf(h, "#%2x%2x%2x", &r, &g, &b) != 3) return dflt;
    return RGB(r, g, b);
}

/* ------------------------------------------------------------------ fonts */
bool font_load(font *f, const char *path) {
    long len = 0;
    uint8_t *d = (uint8_t *)read_file(path, &len);
    if (!d || len < 264 || memcmp(d, "FNT1", 4)) {
        free(d);
        return false;
    }
    f->w = d[4];
    f->h = d[5];
    f->stride = (f->w + 7) / 8;
    memcpy(f->adv, d + 8, 256);
    long need = 264 + 256L * f->h * f->stride;
    if (len != need) {
        free(d);
        return false;
    }
    f->bits = malloc(need - 264 + 4 * 256); /* the boxes ride in the same block: freeing bits frees them */
    if (!f->bits) {
        free(d);
        return false;
    }
    memcpy(f->bits, d + 264, need - 264);
    free(d);
    f->box = f->bits + (need - 264);
    for (int c = 0; c < 256; c++) { /* a cell is ~28x23 bits for ~10x14 of ink: draw_font walks only the ink */
        const uint8_t *g = f->bits + (size_t)c * f->h * f->stride;
        int x0 = f->w, x1 = 0, y0 = f->h, y1 = 0;
        for (int j = 0; j < f->h; j++)
            for (int i = 0; i < f->w; i++)
                if (g[j * f->stride + (i >> 3)] & (0x80 >> (i & 7))) {
                    if (i < x0) x0 = i;
                    if (i + 1 > x1) x1 = i + 1;
                    if (j < y0) y0 = j;
                    if (j + 1 > y1) y1 = j + 1;
                }
        uint8_t *b = f->box + 4 * c;
        b[0] = (uint8_t)(x1 ? x0 : 0), b[1] = (uint8_t)x1, b[2] = (uint8_t)(y1 ? y0 : 0), b[3] = (uint8_t)y1;
    }
    return true;
}

static int cp1252_from_unicode(uint32_t cp) {
    if (cp < 0x80 || (cp >= 0xA0 && cp <= 0xFF)) return (int)cp;
    static const uint16_t hi[32] = {0x20AC, 0, 0x201A, 0x0192, 0x201E, 0x2026, 0x2020, 0x2021, 0x02C6, 0x2030, 0x0160,
                                    0x2039, 0x0152, 0, 0x017D, 0, 0, 0x2018, 0x2019, 0x201C, 0x201D, 0x2022,
                                    0x2013, 0x2014, 0x02DC, 0x2122, 0x0161, 0x203A, 0x0153, 0, 0x017E, 0x0178};
    for (int i = 0; i < 32; i++)
        if (hi[i] && hi[i] == cp) return 0x80 + i;
    return -1;
}

int utf8_cp1252(const char **p, const char *end) {
    const unsigned char *s = (const unsigned char *)*p;
    uint32_t cp;
    int n;
    if (s[0] < 0x80) { cp = s[0]; n = 1; }
    else if ((s[0] & 0xE0) == 0xC0) { cp = s[0] & 0x1F; n = 2; }
    else if ((s[0] & 0xF0) == 0xE0) { cp = s[0] & 0x0F; n = 3; }
    else { cp = s[0] & 0x07; n = 4; }
    if ((const char *)s + n > end) n = (int)(end - (const char *)s);
    for (int i = 1; i < n; i++) cp = (cp << 6) | (s[i] & 0x3F);
    *p += n;
    return cp1252_from_unicode(cp);
}

int utf8_count(const char *s, int nbytes) {
    const char *e = s + nbytes;
    int n = 0;
    while (s < e) {
        utf8_cp1252(&s, e);
        n++;
    }
    return n;
}

int font_width(const font *f, const char *s, int nbytes) {
    if (!s) return 0;
    if (nbytes < 0) nbytes = (int)strlen(s);
    const char *e = s + nbytes;
    int w = 0;
    while (s < e) {
        int c = utf8_cp1252(&s, e);
        w += f->adv[c < 0 ? '?' : c];
    }
    return w;
}

int font_draw(surface *sf, const font *f, int x, int y, const char *s, int nbytes, int maxchars, uint16_t col) {
    if (!s || !f->bits) return 0;
    if (nbytes < 0) nbytes = (int)strlen(s);
    const char *e = s + nbytes;
    int x0 = x;
    for (int n = 0; s < e && (maxchars < 0 || n < maxchars); n++) {
        int c = utf8_cp1252(&s, e);
        if (c < 0) c = '?';
        const uint8_t *g = f->bits + (size_t)c * f->h * f->stride, *b = f->box ? f->box + 4 * c : NULL;
        int i0, j0, n = clip(x, f->w, sf->w, &i0), m = clip(y, f->h, sf->h, &j0);
        int ia = b && b[0] > i0 ? b[0] : i0, ib = b && b[1] < i0 + n ? b[1] : i0 + n; /* the ink, clipped */
        int ja = b && b[2] > j0 ? b[2] : j0, jb = b && b[3] < j0 + m ? b[3] : j0 + m;
        for (int j = ja; j < jb; j++) {
            const uint8_t *gr = g + j * f->stride;
            uint16_t *d = sf->px + (y + j) * sf->w + x;
            for (int i = ia; i < ib; i++)
                if (gr[i >> 3] & (0x80 >> (i & 7))) d[i] = col;
        }
        x += f->adv[c];
    }
    return x - x0;
}

/* Greedy word wrap. '\n' forces a break; a word wider than the line is split. */
int text_wrap(const font *f, const char *s, int max_w, uint16_t *starts, uint16_t *lens, int max_lines) {
    if (!s) return 0;
    int n = 0, len = (int)strlen(s), i = 0;
    while (i < len && n < max_lines) {
        while (i < len && s[i] == ' ') i++;
        if (i >= len) break;
        int line_start = i, last_fit = -1, j = i;
        while (j <= len) {
            if (j == len || s[j] == ' ' || s[j] == '\n') {
                if (font_width(f, s + line_start, j - line_start) <= max_w) last_fit = j;
                else break;
                if (j == len || s[j] == '\n') break;
            }
            j++;
        }
        if (last_fit < 0) { /* single word too long: cut at the last fitting char */
            const char *p = s + line_start, *e = s + len;
            int w = 0;
            while (p < e && *p != ' ') {
                const char *q = p;
                int c = utf8_cp1252(&q, e);
                if (w + f->adv[c < 0 ? '?' : c] > max_w && p > s + line_start) break;
                w += f->adv[c < 0 ? '?' : c];
                p = q;
            }
            last_fit = (int)(p - s);
        }
        starts[n] = (uint16_t)line_start;
        lens[n] = (uint16_t)(last_fit - line_start);
        n++;
        i = last_fit;
        if (i < len && s[i] == '\n') i++;
    }
    return n;
}
