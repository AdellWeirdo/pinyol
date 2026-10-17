/* Assets (Asset Factory runtime format), blitting, 1-bit fonts and text wrapping. */
#include <stdlib.h>
#include <string.h>

#include "bp.h"
#include "gfx_px.h"

#define MAX_ASSETS 320
#define SLOTS 512 /* hash of asset ids, open addressing (> MAX_ASSETS): lookups happen many times a frame */

static asset assets[MAX_ASSETS];
static int16_t slot[SLOTS]; /* index into assets + 1; 0 = empty */
static uint16_t oom_pixel = 0xF81F; /* stand-in if even a placeholder cannot be allocated */
static int nassets;
static size_t canvas_px; /* all the canvases' pixels: CANVAS_MAX_PX at most */
static size_t pic_bytes, pic_budget = PIC_BUDGET, budget_set; /* the pictures' data in memory, how much may be */
static uint32_t pic_frame;                         /* counts gfx_new_frame: 0 for ever in v1 games, nothing goes */
static char forced[16][32];
static int nforced;

void gfx_reset(void) {
    for (int i = 0; i < nassets; i++) {
        if (assets[i].pixels != &oom_pixel) free(assets[i].pixels);
        free(assets[i].mask);
        free(assets[i].pk);
    }
    nassets = 0;
    nforced = 0;
    canvas_px = 0;
    pic_bytes = 0, pic_budget = budget_set ? budget_set : PIC_BUDGET, pic_frame = 0;
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

/* ------------------------------------------------------------------ the pictures' memory */

void gfx_new_frame(void) { pic_frame++; }
void gfx_pin(asset *a) { a->pinned = true; }
void gfx_set_budget(size_t bytes) { pic_budget = budget_set = bytes; } /* for every game from now on */
size_t gfx_picture_bytes(void) { return pic_bytes; }

static void let_go(asset *a) { /* its data freed; the rest (its name, size, anchor) stays for when it comes back */
    free(a->pixels), free(a->mask), free(a->pk);
    a->pixels = NULL, a->mask = NULL, a->pk = NULL, a->pal = NULL, a->cols = NULL;
    pic_bytes -= a->bytes;
    a->bytes = 0, a->out = true;
}

/* Lets pictures go, least recently asked for first, until `need` more bytes fit the budget (all = true: every one it
 * can, as when memory itself ran out). Never one asked for in this frame (its commands draw from it), one pinned, a
 * canvas or `keep`. ponytail: a scan of every picture per one let go; a list in order of use if hundreds go a frame. */
static void make_room(size_t need, const asset *keep, bool all) {
    while (all || pic_bytes + need > pic_budget) {
        asset *lru = NULL;
        for (int i = 0; i < nassets; i++) {
            asset *a = &assets[i];
            if (a == keep || a->pinned || a->canvas || a->out || !a->bytes || a->used == pic_frame) continue;
            if (!lru || a->used < lru->used) lru = a;
        }
        if (!lru) return;
        let_go(lru);
    }
}

/* read_file for a picture's data, with room made for it first (and everything that can go let go, then once more,
 * when memory itself runs out) */
static char *read_picture(const char *path, long *len, const asset *keep) {
    FILE *f = fopen(path, "rb"); /* (once: on the card each opening walks the folder) */
    if (!f) return NULL;
    fseek(f, 0, SEEK_END);
    long n = ftell(f);
    fseek(f, 0, SEEK_SET);
    char *d = NULL;
    if (n >= 0) {
        make_room((size_t)n, keep, false);
        if (!(d = malloc((size_t)n + 1))) make_room(0, keep, true), d = malloc((size_t)n + 1);
    }
    if (d && fread_chunked(d, (size_t)n, f) != (size_t)n) free(d), d = NULL;
    fclose(f);
    if (d) d[n] = 0, *len = n;
    return d;
}

static void *alloc_picture(size_t n, const asset *keep) { /* malloc, with room made the same way */
    make_room(n, keep, false);
    void *p = malloc(n);
    if (!p) make_room(0, keep, true), p = malloc(n);
    return p;
}

static inline unsigned rd16(const uint8_t *p) { return p[0] | p[1] << 8; }
static inline unsigned index_at(const uint8_t *ids, int j, int bpp) {
    return bpp == 8 ? ids[j] : (j & 1 ? ids[j >> 1] & 15 : ids[j >> 1] >> 4);
}

/* A packed picture's file, checked whole: every column's runs inside the picture and the file, so drawing it needs no
 * checks. False (the asset a placeholder) when anything is off. */
static bool load_packed(asset *a) {
    char path[384];
    long len = 0;
    snprintf(path, sizeof path, "%s/assets/%s.pk", G.game_dir, a->id);
    uint8_t *pk = (uint8_t *)read_picture(path, &len, a);
    const char *why = NULL;
    if (!pk || len < 16 || memcmp(pk, "NP2K", 4) || pk[4] != 1 || (pk[5] != 4 && pk[5] != 8)) why = "not a packed picture";
    unsigned ncol = why ? 0 : rd16(pk + 6), w = why ? 0 : rd16(pk + 8), h = why ? 0 : rd16(pk + 10), nf = why ? 0 : rd16(pk + 12);
    size_t table = (16 + 2 * (size_t)ncol + 3) & ~(size_t)3, ncols = (size_t)w * nf;
    if (!why && ((int)w != a->w || (int)h != a->h || (int)nf != a->frames || !ncol || ncol > (pk[5] == 4 ? 16u : 256u)))
        why = "its size is not its meta's";
    if (!why && table + 4 * ncols > (size_t)len) why = "cut short";
    bool opaque = true;
    for (size_t c = 0; !why && c < ncols; c++) { /* every column: its runs, in order, inside the picture and the file */
        uint32_t at;
        memcpy(&at, pk + table + 4 * c, 4);
        if (at < table + 4 * ncols || at > (size_t)len - 2) { why = "a column outside the file"; break; } /* (no at + 2: it wraps) */
        unsigned runs = rd16(pk + at), next = 0;
        size_t p = at + 2;
        if (runs != 1) opaque = false;
        for (unsigned r = 0; r < runs && !why; r++) {
            if (p + 4 > (size_t)len) { why = "a run outside the file"; break; }
            unsigned y = rd16(pk + p), n = rd16(pk + p + 2);
            if (y < next || !n || y + n > h) why = "a run outside its column";
            if (r == 0 && runs == 1 && (y != 0 || n != h)) opaque = false;
            next = y + n;
            p += 4 + (pk[5] == 8 ? n : (n + 1) / 2);
            if (p > (size_t)len) why = "indices outside the file";
        }
        for (size_t q = at + 2, r = 0; !why && r < runs; r++) { /* the indices inside the palette */
            unsigned n = rd16(pk + q + 2);
            for (unsigned j = 0; j < n && !why; j++)
                if (index_at(pk + q + 4, (int)j, pk[5]) >= ncol) why = "a colour outside the palette";
            q += 4 + (pk[5] == 8 ? n : (n + 1) / 2);
        }
    }
    if (why) {
        hal_log("asset %s: %s", a->id, why);
        free(pk);
        return false;
    }
    a->pk = pk, a->bpp = pk[5], a->pal = (const uint16_t *)(pk + 16), a->cols = (const uint32_t *)(pk + table);
    a->pk_opaque = opaque;
    a->bytes = (size_t)len, pic_bytes += a->bytes;
    return true;
}

static bool load_asset(asset *a) {
    for (int i = 0; i < nforced; i++)
        if (!strcmp(forced[i], a->id)) return false;
    char rel[96];
    snprintf(rel, sizeof rel, "assets/%s.meta.json", a->id);
    cJSON *meta = game_has(rel) ? json_file(rel) : NULL;
    if (!meta) return false;
    a->w = jint(meta, "w", 0);
    a->h = jint(meta, "h", 0);
    a->frames = jint(meta, "frames", 1);
    cJSON *anc = jget(meta, "anchor"), *fms = jget(meta, "frame_ms");
    a->ax = jai(anc, 0, a->w / 2);
    a->ay = jai(anc, 1, a->h - 1);
    a->frame_ms = jai(fms, 0, 0);
    const char *format = jstr(meta, "format");
    bool packed = format && !strcmp(format, "packed");
    cJSON_Delete(meta);
    if (a->w <= 0 || a->h <= 0 || a->frames <= 0 || a->w > 1024 || a->h > 1024 || a->frames > 64) return false;
    if (packed) {
        if (load_packed(a)) return true;
        placeholder(a, a->w, a->h, a->frames);
        return true; /* the declared geometry, a checkerboard */
    }

    char path[384];
    long len = 0;
    size_t npx = (size_t)a->w * a->h * a->frames;
    snprintf(path, sizeof path, "%s/assets/%s.rgb565", G.game_dir, a->id);
    uint8_t *raw = (uint8_t *)read_picture(path, &len, a);
    if (!raw || (size_t)len != npx * 2) {
        hal_log("asset %s: pixel file size %ld, expected %zu", a->id, len, npx * 2);
        free(raw);
        placeholder(a, a->w, a->h, a->frames);
        return true; /* keep the declared geometry */
    }
    for (size_t i = 0; i < npx; i++) ((uint16_t *)raw)[i] = (uint16_t)(raw[2 * i] | (raw[2 * i + 1] << 8)); /* LE, in place */
    a->pixels = (uint16_t *)raw; /* (read_file's memory: malloc'd, aligned for any type) */
    snprintf(path, sizeof path, "%s/assets/%s.mask", G.game_dir, a->id);
    a->mask = game_has(path + strlen(G.game_dir) + 1) ? (uint8_t *)read_picture(path, &len, a) : NULL; /* none: opaque */
    if (a->mask && (size_t)len != (size_t)((a->w + 7) / 8) * a->h * a->frames) {
        hal_log("asset %s: bad mask size, drawing opaque", a->id);
        free(a->mask);
        a->mask = NULL;
    }
    a->bytes = npx * 2 + (a->mask ? (size_t)len : 0), pic_bytes += a->bytes;
    return true;
}

static unsigned slot_of(const char *key) { /* its slot, or the empty one where it would go */
    unsigned h = 5381;
    for (const char *c = key; *c; c++) h = h * 33 ^ (unsigned char)*c;
    for (h &= SLOTS - 1; slot[h]; h = (h + 1) & (SLOTS - 1))
        if (!strcmp(assets[slot[h] - 1].id, key)) break;
    return h;
}

static void key_of(char key[32], const char *id) { /* truncated, so long ids still hit the cache (no snprintf: hot) */
    int i = 0;
    for (; id && i < 31 && id[i]; i++) key[i] = id[i];
    key[i] = 0;
}

static asset *lookup(const char *id, bool quiet) {
    static asset none;
    char key[32];
    key_of(key, id);
    unsigned h = slot_of(key);
    if (slot[h]) {
        asset *a = &assets[slot[h] - 1];
        a->used = pic_frame;
        if (a->out) { /* let go earlier: back from the card, as it was */
            a->out = false;
            if (!load_asset(a)) placeholder(a, a->w, a->h, a->frames);
        }
        return a;
    }
    if (nassets == MAX_ASSETS) {
        if (!none.pixels) placeholder(&none, 16, 16, 1);
        return &none;
    }
    slot[h] = (int16_t)(nassets + 1);
    asset *a = &assets[nassets++];
    memset(a, 0, sizeof *a);
    snprintf(a->id, sizeof a->id, "%s", key);
    a->used = pic_frame;
    if (!load_asset(a)) {
        if (!quiet) hal_log("asset %s missing, using placeholder", key);
        placeholder(a, 16, 16, 1);
    }
    return a;
}

asset *gfx_asset(const char *id) { return lookup(id, false); }

asset *gfx_find(const char *id) {
    char key[32];
    key_of(key, id);
    unsigned h = slot_of(key);
    return slot[h] ? &assets[slot[h] - 1] : NULL;
}

const char *gfx_canvas(const char *id, int w, int h, const asset *from, asset **out) {
    if (from) w = from->w, h = from->h;
    if (w < 1 || h < 1 || w > 1024 || h > 1024) return "a canvas is 1 to 1024 pixels a side";
    char key[32];
    snprintf(key, sizeof key, "%s", id);
    unsigned hs = slot_of(key);
    asset *a = slot[hs] ? &assets[slot[hs] - 1] : NULL;
    if (a && !a->canvas) return "that name is one of the game's pictures";
    if (a && (a->w != w || a->h != h)) return "that canvas exists with another size";
    int stride = (w + 7) / 8;
    if (!a) {
        if (canvas_px + (size_t)w * h > CANVAS_MAX_PX) return "no room for it: 3 MB of canvases in all";
        if (nassets == MAX_ASSETS) return "too many pictures";
        uint16_t *px = malloc((size_t)w * h * 2);
        uint8_t *mask = malloc((size_t)stride * h);
        if (!px || !mask) {
            free(px), free(mask);
            return "out of memory";
        }
        slot[hs] = (int16_t)(nassets + 1);
        a = &assets[nassets++];
        memset(a, 0, sizeof *a);
        snprintf(a->id, sizeof a->id, "%s", key);
        a->w = w, a->h = h, a->frames = 1, a->ax = w / 2, a->ay = h - 1, a->pixels = px, a->mask = mask, a->canvas = true;
        canvas_px += (size_t)w * h;
    }
    for (int y = 0; y < h; y++)
        for (int x = 0; x < w; x++) {
            uint16_t v = from ? from->pixels[y * w + x] : CANVAS_KEY;
            if (from && v == CANVAS_KEY) v ^= 1;
            a->pixels[y * w + x] = from && gfx_opaque(from, 0, x, y) ? v : CANVAS_KEY;
        }
    memset(a->mask, 0, (size_t)stride * h);
    if (from) gfx_canvas_mask(a, 0, 0, w, h);
    a->gen++;
    *out = a;
    return NULL;
}
asset *gfx_asset_opt(const char *id) { return lookup(id, true); } /* a sprite a game may leave out: no log */

/* The runs of a packed picture's column (frame f, column u): the code after ids runs for each, with y, n, ids set. */
#define EACH_RUN(a, f, u, y, n, ids, ...)                                                        \
    do {                                                                                        \
        const uint8_t *p_ = (a)->pk + (a)->cols[(size_t)(f) * (a)->w + (u)];                    \
        unsigned runs_ = rd16(p_);                                                              \
        p_ += 2;                                                                                \
        for (unsigned r_ = 0; r_ < runs_; r_++) {                                               \
            int y = (int)rd16(p_), n = (int)rd16(p_ + 2);                                       \
            const uint8_t *ids = p_ + 4;                                                        \
            __VA_ARGS__;                                                                        \
            p_ += 4 + ((a)->bpp == 8 ? n : (n + 1) / 2);                                        \
        }                                                                                       \
    } while (0)

uint16_t *gfx_pixels(asset *a) {
    if (a->pixels || !a->pk) return a->pixels;
    size_t npx = (size_t)a->w * a->h * a->frames;
    int stride = (a->w + 7) / 8;
    size_t nmask = a->pk_opaque ? 0 : (size_t)stride * a->h * a->frames;
    make_room(nmask, a, false);
    uint16_t *px = alloc_picture(npx * 2, a);
    uint8_t *mask = nmask ? calloc(nmask, 1) : NULL;
    if (!px || (nmask && !mask)) {
        free(px), free(mask);
        return NULL;
    }
    memset(px, 0, npx * 2);
    for (int f = 0; f < a->frames; f++)
        for (int u = 0; u < a->w; u++)
            EACH_RUN(a, f, u, y, n, ids, {
                for (int j = 0; j < n; j++) {
                    size_t i = ((size_t)f * a->h + y + j) * a->w + u;
                    px[i] = a->pal[index_at(ids, j, a->bpp)];
                    if (mask) mask[((size_t)f * a->h + y + j) * stride + u / 8] |= 0x80 >> (u % 8);
                }
            });
    a->pixels = px, a->mask = mask;
    a->bytes += npx * 2 + nmask, pic_bytes += npx * 2 + nmask;
    return px;
}

bool gfx_opaque(const asset *a, int frame, int u, int v) {
    if (a->pk && !a->pixels) {
        bool in = false;
        EACH_RUN(a, frame, u, y, n, ids, { (void)ids; if (v >= y && v < y + n) in = true; });
        return in;
    }
    if (!a->mask) return true;
    int stride = (a->w + 7) / 8;
    return a->mask[(size_t)frame * stride * a->h + v * stride + u / 8] & (0x80 >> (u % 8));
}


surface gfx_clip(const surface *s, int x, int y, int w, int h) {
    surface c = *s;
    if (!c.xs) c.xs = 1, c.ys = s->w, c.fw = s->w, c.fh = s->h; /* a plain buffer, as a window of itself */
    int xa = x > c.x0 ? x : c.x0, ya = y > c.y0 ? y : c.y0;
    int xb = x + w < c.x0 + c.w ? x + w : c.x0 + c.w, yb = y + h < c.y0 + c.h ? y + h : c.y0 + c.h;
    if (xb <= xa || yb <= ya) {
        c.w = c.h = 0;
        return c;
    }
    c.px += (ptrdiff_t)(xa - c.x0) * c.xs + (ptrdiff_t)(ya - c.y0) * c.ys;
    c.x0 = xa, c.y0 = ya, c.w = xb - xa, c.h = yb - ya;
    return c;
}

surface gfx_turned(uint16_t *out, int row0, int rows, int fw, int fh, bool flip, bool swap) {
    surface s = {.w = rows, .h = fh, .fw = fw, .fh = fh, .swap = swap};
    if (!flip) { /* frame pixel (x, y) is panel row x, pixel fh-1-y */
        s.x0 = row0, s.xs = fh, s.ys = -1, s.px = out + (fh - 1);
    } else {     /* frame pixel (x, y) is panel row fw-1-x, pixel y */
        s.x0 = fw - row0 - rows, s.xs = -fh, s.ys = 1, s.px = out + (size_t)(rows - 1) * fh;
    }
    return s;
}

/* Unrotated blit of the first `rows` rows: clipped once, the mask read a row at a time, rows without a mask
 * copied whole. This is every sprite and background in the world, so it is the hot path on the console. */
/* A packed picture at 1x, maybe mirrored: column by column (on the console's turned strips both the picture's column
 * and the screen's are contiguous), only the opaque runs, each pixel its palette's colour. rows: the top ones only. */
/* A packed picture's colours as the surface keeps them, here in internal memory (no PSRAM read per pixel): a
 * variant's colours where it has them (alt), or one colour for a flash (tint >= 0) */
static uint16_t dusk(uint16_t c) { /* gfx_tint_dusk's per-channel scale, on one colour */
    int r = (c >> 11) * 5 / 8, g = ((c >> 5) & 63) * 11 / 16, b = (c & 31) * 13 / 16 + 2;
    return (uint16_t)((r << 11) | (g << 5) | (b > 31 ? 31 : b));
}

/* light: LIGHT_DUSK and a number of times halved (gfx_shade), applied to the palette: the same pixels as shading and
 * tinting the picture once drawn, without going over them again */
#define LIGHT_DUSK 0x10
/* A tint of -2 or less is not a colour but a multiplier: -2 - (r << 16 | g << 8 | b), each 0..255 (255 as it is). The
 * picture's palette is multiplied once, so a whole packed picture is made darker, or warmer, at no cost for each pixel. */
static inline uint16_t mul565(uint16_t c, int code) {
    const int m = -2 - code, mr = (m >> 16 & 255) + 1, mg = (m >> 8 & 255) + 1, mb = (m & 255) + 1;
    return (uint16_t)(((c >> 11) * mr >> 8) << 11 | ((c >> 5 & 63) * mg >> 8) << 5 | ((c & 31) * mb >> 8));
}
static int warm_level; /* gfx_light_warm: every packed picture's palette pulled towards amber */
void gfx_light_warm(int level) { warm_level = level; }

static void look_pal(const surface *s, const asset *a, const asset *alt, int tint, int light, uint16_t pal[256]) {
    const int ncol = (int)rd16(a->pk + 6), nalt = alt && alt->pk ? (int)rd16(alt->pk + 6) : 0;
    for (int i = 0; i < ncol; i++) {
        uint16_t c = tint >= 0 ? (uint16_t)tint : i < nalt ? alt->pal[i] : a->pal[i];
        if (tint <= -2) c = mul565(c, tint);
        for (int k = light & 0xF; k > 0; k--) c = (uint16_t)((c & 0xF7DE) >> 1);
        if (light & LIGHT_DUSK) c = dusk(c);
        if (warm_level) { /* (as arena.c's warm, on one colour) */
            int f = warm_level * 3, r = c >> 11, g = (c >> 5) & 63, b = c & 31;
            r += (31 - r) * f / 24, g += (63 - g) * f / 120, b -= b * f / 20;
            c = (uint16_t)(r << 11 | g << 5 | b);
        }
        pal[i] = stored(s, c);
    }
}

static void blit_packed(surface *s, const asset *a, int frame, int x, int y, int rows, bool flip, const asset *alt,
                        int tint, int light) {
    int u0, v0, n = CLIP_X(s, x, a->w, &u0), m = CLIP_Y(s, y, rows < a->h ? rows : a->h, &v0);
    if (n <= 0 || m <= 0) return;
    const int ys = step_y(s), lo = v0, hi = v0 + m, bpp = a->bpp;
    uint16_t pal[256];
    look_pal(s, a, alt, tint, light, pal);
    for (int k = 0; k < n; k++) {
        int u = u0 + k;
        EACH_RUN(a, frame, flip ? a->w - 1 - u : u, ry, rn, ids, {
            int j = ry < lo ? lo - ry : 0, j1 = ry + rn > hi ? hi - ry : rn;
            if (j < j1) {
                uint16_t *d = at(s, x + u, y + ry + j);
                if (bpp == 8) {
                    for (; j < j1; j++, d += ys) *d = pal[ids[j]];
                } else { /* two pixels a byte: the odd one first, then pairs, then the last even one */
                    if (j & 1) *d = pal[ids[j >> 1] & 15], d += ys, j++;
                    for (; j + 1 < j1; j += 2, d += 2 * ys) {
                        unsigned b = ids[j >> 1];
                        d[0] = pal[b >> 4], d[ys] = pal[b & 15];
                    }
                    if (j < j1) *d = pal[ids[j >> 1] >> 4];
                }
            }
        });
    }
}

void gfx_blit_mixed(surface *s, const asset *a, int frame, int x, int y, bool flip, int tint, unsigned alpha, int mode) {
    int u0, v0, n = CLIP_X(s, x, a->w, &u0), m = CLIP_Y(s, y, a->h, &v0);
    if (n <= 0 || m <= 0) return;
    const int ys = step_y(s), lo = v0, hi = v0 + m, bpp = a->bpp, ncol = (int)rd16(a->pk + 6);
    uint16_t pal[256];
    for (int i = 0; i < ncol; i++) pal[i] = tint >= 0 ? (uint16_t)tint : tint <= -2 ? mul565(a->pal[i], tint) : a->pal[i];
    for (int k = 0; k < n; k++) {
        int u = u0 + k;
        EACH_RUN(a, frame, flip ? a->w - 1 - u : u, ry, rn, ids, {
            int j = ry < lo ? lo - ry : 0, j1 = ry + rn > hi ? hi - ry : rn;
            uint16_t *d = j < j1 ? at(s, x + u, y + ry + j) : NULL;
            for (; j < j1; j++, d += ys) {
                unsigned id = bpp == 8 ? ids[j] : (j & 1 ? ids[j >> 1] & 15 : ids[j >> 1] >> 4);
                uint16_t under = s->swap ? bswap16(*d) : *d;
                *d = under == CANVAS_KEY ? stored(s, pal[id]) : stored(s, mix565(under, pal[id], alpha, mode));
            }
        });
    }
}

/* a / b rounded down, b > 0; in 32 bits when it fits (always, but for absurd positions): the console divides those in
 * hardware and 64-bit ones in software, which was most of a scaled picture's cost */
static inline int64_t floor_div(int64_t a, int64_t b) {
    if (a >= INT32_MIN && a <= INT32_MAX && b <= INT32_MAX) {
        int32_t x = (int32_t)a, y = (int32_t)b, q = x / y;
        return q - (x % y != 0 && x < 0);
    }
    return a / b - (a % b != 0 && a < 0);
}

/* A packed picture scaled (and mirrored, by negative steps), straight from its columns: screen column bx0 + i shows
 * picture column (u + i du) >> 16, screen row by0 + k picture row (v + k dv) >> 16, in 16.16 fixed point, as
 * gfx_blit_ex steps them; each run of a column lands on the rows k worked out from its ends, not looked for. */
void gfx_blit_scaled(surface *s, const asset *a, int frame, int bx0, int bx1, int by0, int by1, int32_t u, int32_t du,
                     int32_t v, int32_t dv, const asset *alt, int tint) {
    uint16_t pal[256];
    look_pal(s, a, alt, tint, 0, pal);
    const int ys = step_y(s), len = by1 - by0, bpp = a->bpp;
    const int64_t m = dv < 0 ? -(int64_t)dv : dv;
    for (int x = bx0; x < bx1; x++, u += du) {
        if (u < 0 || u >= a->w << 16) continue;
        uint16_t *col = at(s, x, by0);
        EACH_RUN(a, frame, u >> 16, ry, rn, ids, {
            int64_t lo = ((int64_t)ry << 16) - v, hi = ((int64_t)(ry + rn) << 16) - v; /* lo <= k dv < hi */
            int64_t k0 = dv > 0 ? -floor_div(-lo, m) : floor_div(-hi, m) + 1;
            int64_t k1 = dv > 0 ? -floor_div(-hi, m) : floor_div(-lo, m) + 1;
            if (k0 < 0) k0 = 0;
            if (k1 > len) k1 = len;
            const int n0 = (int)k0, n1 = (int)k1; /* (32-bit from here: the console's loops are its words) */
            int32_t vv = v + n0 * dv;
            uint16_t *d = col + n0 * ys;
            if (s->dither)
                for (int k = n0; k < n1; k++, vv += dv, d += ys) {
                    int j = (vv >> 16) - ry;
                    if (!dithered(s, x, by0 + k)) *d = pal[bpp == 8 ? ids[j] : j & 1 ? ids[j >> 1] & 15 : ids[j >> 1] >> 4];
                }
            else if (bpp == 8)
                for (int k = n0; k < n1; k++, vv += dv, d += ys) *d = pal[ids[(vv >> 16) - ry]];
            else
                for (int k = n0; k < n1; k++, vv += dv, d += ys) {
                    int j = (vv >> 16) - ry;
                    *d = pal[j & 1 ? ids[j >> 1] & 15 : ids[j >> 1] >> 4];
                }
        });
    }
}

static void blit_plain(surface *s, const asset *a, int frame, int x, int y, int rows, bool half) {
    if (a->pk && (!half || !a->pixels)) { /* (half see-through is the v1 games', whose pictures are not packed) */
        blit_packed(s, a, frame, x, y, rows, false, NULL, -1, 0);
        return;
    }
    int u0, v0, n = CLIP_X(s, x, a->w, &u0), m = CLIP_Y(s, y, rows < a->h ? rows : a->h, &v0);
    if (n <= 0 || m <= 0) return;
    const uint16_t *src = a->pixels + (size_t)frame * a->w * a->h;
    int stride = (a->w + 7) / 8, xs = step_x(s);
    const uint8_t *mask = a->mask ? a->mask + (size_t)frame * stride * a->h : NULL;
    const int ys = step_y(s);
    if (!half && (ys == 1 || ys == -1) && xs != 1 && xs != -1) { /* a turned strip: column by column, each contiguous */
        for (int u = u0; u < u0 + n; u++) {
            uint16_t *d = at(s, x + u, y + v0);
            const uint16_t *sp = src + v0 * a->w + u;
            if (!mask) {
                if (s->swap)
                    for (int j = 0; j < m; j++, d += ys, sp += a->w) *d = bswap16(*sp);
                else
                    for (int j = 0; j < m; j++, d += ys, sp += a->w) *d = *sp;
                continue;
            }
            const uint8_t *mp = mask + v0 * stride + (u >> 3), bit = (uint8_t)(0x80 >> (u & 7));
            for (int j = 0; j < m; j++, d += ys, sp += a->w, mp += stride)
                if (*mp & bit) *d = stored(s, *sp);
        }
        return;
    }
    for (int v = v0; v < v0 + m; v++) {
        const uint16_t *sp = src + v * a->w + u0;
        uint16_t *d = at(s, x + u0, y + v);
        if (!mask && !half && xs == 1 && !s->swap) {
            memcpy(d, sp, (size_t)n * sizeof *d);
            continue;
        }
        const uint8_t *mr = mask ? mask + v * stride : NULL;
        if (mr && !half && xs == 1 && !s->swap) { /* a plain row: the mask a byte (8 pixels) at a time */
            int u = u0, end = u0 + n;
            for (; u < end && (u & 7); u++)
                if (mr[u >> 3] & (0x80 >> (u & 7))) d[u - u0] = sp[u - u0];
            for (; u + 8 <= end; u += 8) {
                uint8_t m = mr[u >> 3];
                if (m == 0xFF) memcpy(d + (u - u0), sp + (u - u0), 8 * sizeof *d);
                else if (m)
                    for (int b = 0; b < 8; b++)
                        if (m & (0x80 >> b)) d[u - u0 + b] = sp[u - u0 + b];
            }
            for (; u < end; u++)
                if (mr[u >> 3] & (0x80 >> (u & 7))) d[u - u0] = sp[u - u0];
            continue;
        }
        for (int k = 0; k < n; k++, d += xs) {
            int u = u0 + k;
            if (mr && !(mr[u >> 3] & (0x80 >> (u & 7)))) continue;
            *d = half ? stored(s, blend50(stored(s, *d), sp[k])) : stored(s, sp[k]);
        }
    }
}

/* At 1x, mirrored left to right when flip_x: a fighter facing the other way without the general (scaled, turned) path. */
void gfx_blit_lit(surface *s, const asset *a, int x, int y, int shade, bool dusk_tint) {
    if (!a->pk) { /* (as it was: drawn, then shaded and tinted where it is) */
        gfx_blit(s, a, 0, x, y, 0, false);
        surface in = gfx_clip(s, x, y, a->w, a->h);
        for (int k = 0; k < shade; k++) gfx_shade(&in, 0, 0, SCREEN_W, SCREEN_H);
        if (dusk_tint) gfx_tint_dusk(&in);
        return;
    }
    blit_packed(s, a, 0, x, y, a->h, false, NULL, -1, (shade > 15 ? 15 : shade) | (dusk_tint ? LIGHT_DUSK : 0));
}

void gfx_blit_lit_rows(surface *s, const asset *a, int frame, int x, int y, int rows, int shade, bool dusk_tint) {
    if (frame < 0 || frame >= a->frames) frame = 0;
    if (rows > a->h) rows = a->h;
    if (rows <= 0) return;
    if (!a->pk) { /* (as gfx_blit_lit: drawn, then shaded and tinted where it is) */
        gfx_blit_rows(s, a, frame, x, y, rows);
        surface in = gfx_clip(s, x, y, a->w, rows);
        for (int k = 0; k < shade; k++) gfx_shade(&in, 0, 0, SCREEN_W, SCREEN_H);
        if (dusk_tint) gfx_tint_dusk(&in);
        return;
    }
    blit_packed(s, a, frame, x, y, rows, false, NULL, -1, (shade > 15 ? 15 : shade) | (dusk_tint ? LIGHT_DUSK : 0));
}

void gfx_blit_flip(surface *s, const asset *a, int frame, int x, int y, bool flip_x, const asset *pal, int tint) {
    if (frame < 0 || frame >= a->frames) frame = 0;
    if (a->pk) {
        blit_packed(s, a, frame, x, y, a->h, flip_x, pal, tint, 0);
        return;
    }
    if (!flip_x && tint < 0) {
        blit_plain(s, a, frame, x, y, a->h, false);
        return;
    }
    int u0, v0, n = CLIP_X(s, x, a->w, &u0), m = CLIP_Y(s, y, a->h, &v0), stride = (a->w + 7) / 8;
    if (n <= 0 || m <= 0) return;
    const uint16_t *src = a->pixels + (size_t)frame * a->w * a->h;
    const uint8_t *mask = a->mask ? a->mask + (size_t)frame * stride * a->h : NULL;
    const int ys = step_y(s);
    for (int k = 0; k < n; k++) { /* each screen column from the picture's mirrored one */
        int u = u0 + k, su = flip_x ? a->w - 1 - u : u;
        uint16_t *d = at(s, x + u, y + v0);
        const uint16_t *sp = src + v0 * a->w + su;
        const uint8_t *mp = mask ? mask + v0 * stride + (su >> 3) : NULL, bit = (uint8_t)(0x80 >> (su & 7));
        for (int j = 0; j < m; j++, d += ys, sp += a->w)
            if (!mp || (mp[j * stride] & bit)) *d = stored(s, tint >= 0 ? (uint16_t)tint : *sp);
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
        if (dy < s->y0 || dy >= s->y0 + s->h) continue;
        for (int rx = 0; rx < rw; rx++) {
            int dx = x + rx;
            if (dx < s->x0 || dx >= s->x0 + s->w) continue;
            int u, v;
            switch (rot) {
            case 0: u = rx; v = ry; break;
            case 1: u = ry; v = a->h - 1 - rx; break;
            case 2: u = a->w - 1 - rx; v = a->h - 1 - ry; break;
            default: u = a->w - 1 - ry; v = rx; break;
            }
            if (!gfx_opaque(a, frame, u, v)) continue;
            uint16_t c = src[v * a->w + u];
            uint16_t *d = at(s, dx, dy);
            *d = half ? stored(s, blend50(stored(s, *d), c)) : stored(s, c);
        }
    }
}

void gfx_blit_rows(surface *s, const asset *a, int frame, int x, int y, int rows) {
    if (frame < 0 || frame >= a->frames) frame = 0;
    blit_plain(s, a, frame, x, y, rows, false);
}

/* Each pixel a 2x2 block; a block that would cross the frame's edge is left out whole, whatever window s is. */
/* gfx_blit2x for a packed picture, from its runs, in its look: only the source pixels whose 2x2 block lies whole
 * inside the frame, as gfx_blit2x draws them (the same pixels, packed or not) */
void gfx_blit2x_look(surface *s, const asset *a, int frame, int x, int y, const asset *pal, int tint) {
    if (!a->pk) {
        gfx_blit2x(s, a, frame, x, y);
        return;
    }
    const int fw = frame_w(s), fh = frame_h(s);
    const int x0 = x < 0 ? x + ((1 - x) & ~1) : x, y0 = y < 0 ? y + ((1 - y) & ~1) : y; /* the first whole block */
    const int x1 = fw - x < 0 ? x0 : x + ((fw - x) & ~1), y1 = fh - y < 0 ? y0 : y + ((fh - y) & ~1);
    surface in = gfx_clip(s, x0, y0, x1 - x0, y1 - y0);
    if (in.w > 0 && in.h > 0) gfx_blit_ex(&in, a, frame, x, y, 2, 2, 0, pal, tint);
}

void gfx_blit2x(surface *s, const asset *a, int frame, int x, int y) {
    if (frame < 0 || frame >= a->frames) frame = 0;
    const uint16_t *src = a->pixels + (size_t)frame * a->w * a->h;
    int stride = (a->w + 7) / 8;
    const uint8_t *mask = a->mask ? a->mask + (size_t)frame * stride * a->h : NULL;
    if (!s->xs && !s->swap) { /* a plain buffer: the frame itself */
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
        return;
    }
    int fw = frame_w(s), fh = frame_h(s);
    /* a window: only the source pixels whose block can meet it (a margin of one; the tests below are exact) */
    int ua = (s->x0 - x) / 2 - 1, ub = (s->x0 + s->w - x) / 2 + 1, va = (s->y0 - y) / 2 - 1, vb = (s->y0 + s->h - y) / 2 + 1;
    if (ua < 0) ua = 0;
    if (va < 0) va = 0;
    if (ub > a->w) ub = a->w;
    if (vb > a->h) vb = a->h;
    const int ys = step_y(s), xs = step_x(s), ya = s->y0, yb = s->y0 + s->h;
    /* the source rows whose 2x2 block lies whole inside the window and the frame: [v_in, v_out) */
    const int lo = ya > 0 ? ya : 0, hi = yb < fh ? yb : fh;
    int v_in = (lo - y + 1) >> 1, v_out = ((hi - 2 - y) >> 1) + 1; /* >> on a negative rounds down */
    if (v_in < va) v_in = va;
    if (v_out > vb) v_out = vb;
    for (int u = ua; u < ub; u++) { /* column by column: a turned strip's columns are contiguous */
        int dx = x + 2 * u;
        if (dx < 0 || dx + 1 >= fw) continue;
        int vs = vb, ve = vb; /* rows [vs, ve) done by the fast path: none yet */
        if (dx >= s->x0 && dx + 1 < s->x0 + s->w && v_in < v_out) { /* both columns in: whole blocks, no tests */
            uint16_t *d = at(s, dx, y + 2 * v_in);
            const uint16_t *sp = src + v_in * a->w + u;
            const uint8_t *mp = mask ? mask + v_in * stride + (u >> 3) : NULL;
            const uint8_t bit = (uint8_t)(0x80 >> (u & 7));
            for (int v = v_in; v < v_out; v++, d += 2 * ys, sp += a->w) {
                if (mp) {
                    bool on = *mp & bit;
                    mp += stride;
                    if (!on) continue;
                }
                uint16_t c = stored(s, *sp);
                d[0] = d[ys] = d[xs] = d[xs + ys] = c;
            }
            vs = v_in, ve = v_out; /* done: only the rows outside [v_in, v_out) remain */
        }
        for (int i = 0; i < 2; i++) { /* the rest, carefully: rows [va, vs) and [ve, vb) */
            if (dx + i < s->x0 || dx + i >= s->x0 + s->w) continue;
            uint16_t *col = at(s, dx + i, ya); /* row ya of this column; row r is col + (r - ya) * ys */
            for (int v = va; v < vb; v++) {
                if (v == vs) v = ve;
                if (v >= vb) break;
                int dy = y + 2 * v;
                if (dy < 0 || dy + 1 >= fh || (mask && !(mask[v * stride + (u >> 3)] & (0x80 >> (u & 7))))) continue;
                uint16_t c = stored(s, src[v * a->w + u]);
                if (dy >= ya && dy < yb) col[(dy - ya) * ys] = c;
                if (dy + 1 >= ya && dy + 1 < yb) col[(dy + 1 - ya) * ys] = c;
            }
        }
    }
}

/* Rows are walked two pixels at a time where aligned (one 32-bit access instead of two). px2 may alias the
 * 16-bit pixels: without it, strict aliasing lets the compiler reorder the wide and narrow accesses. */
typedef uint32_t __attribute__((may_alias)) px2;

/* n pixels in a row of memory, two at a time where aligned. */
static void fill_run(uint16_t *d, int n, uint16_t c) {
    uint32_t cc = c * 0x00010001u;
    int i = 0;
    if (n > 0 && ((uintptr_t)d & 2)) d[i++] = c;
    for (; i + 1 < n; i += 2) *(px2 *)(d + i) = cc;
    if (i < n) d[i] = c;
}

void gfx_fill(surface *s, int x, int y, int w, int h, uint16_t c) {
    int i0, j0, n = CLIP_X(s, x, w, &i0), m = CLIP_Y(s, y, h, &j0);
    if (n <= 0 || m <= 0) return;
    c = stored(s, c);
    int xs = step_x(s), ys = step_y(s);
    if (xs == 1) { /* rows are the contiguous runs */
        for (int j = 0; j < m; j++) fill_run(at(s, x + i0, y + j0 + j), n, c);
        return;
    }
    uint16_t *col = at(s, x + i0, y + j0);
    for (int i = 0; i < n; i++, col += xs) { /* a turned window: its columns are */
        if (ys == 1 || ys == -1) fill_run(ys < 0 ? col - (m - 1) : col, m, c);
        else
            for (int j = 0; j < m; j++) col[j * ys] = c;
    }
}

void gfx_frame(surface *s, int x, int y, int w, int h, uint16_t c) {
    gfx_fill(s, x, y, w, 2, c);
    gfx_fill(s, x, y + h - 2, w, 2, c);
    gfx_fill(s, x, y, 2, h, c);
    gfx_fill(s, x + w - 2, y, 2, h, c);
}

/* Halving every channel: with bit 0 of each 16-bit lane masked off, two pixels share one 32-bit shift. With the bytes
 * swapped the same halving is a mask and a one-bit rotation of each lane (checked against every colour). */
static void shade_run(uint16_t *d, int n, bool swap) {
    int i = 0;
    if (swap) {
        if (n > 0 && ((uintptr_t)d & 2)) d[i] = (uint16_t)((d[i] & 0xDEF7) >> 1 | (d[i] & 1) << 15), i++;
        for (; i + 1 < n; i += 2) {
            px2 *q = (px2 *)(d + i);
            uint32_t v = *q & 0xDEF7DEF7u;
            *q = (v >> 1 & 0x7FFF7FFFu) | (v & 0x00010001u) << 15;
        }
        if (i < n) d[i] = (uint16_t)((d[i] & 0xDEF7) >> 1 | (d[i] & 1) << 15);
        return;
    }
    if (n > 0 && ((uintptr_t)d & 2)) d[i] = (d[i] & 0xF7DE) >> 1, i++;
    for (; i + 1 < n; i += 2) {
        px2 *q = (px2 *)(d + i);
        *q = (*q & 0xF7DEF7DEu) >> 1;
    }
    if (i < n) d[i] = (d[i] & 0xF7DE) >> 1;
}

void gfx_shade(surface *s, int x, int y, int w, int h) {
    int i0, j0, n = CLIP_X(s, x, w, &i0), m = CLIP_Y(s, y, h, &j0);
    if (n <= 0 || m <= 0) return;
    int xs = step_x(s), ys = step_y(s);
    if (xs == 1) {
        for (int j = 0; j < m; j++) shade_run(at(s, x + i0, y + j0 + j), n, s->swap);
        return;
    }
    uint16_t *col = at(s, x + i0, y + j0);
    for (int i = 0; i < n; i++, col += xs) {
        if (ys == 1 || ys == -1) shade_run(ys < 0 ? col - (m - 1) : col, m, s->swap);
        else
            for (int j = 0; j < m; j++) col[j * ys] = stored(s, (uint16_t)((stored(s, col[j * ys]) & 0xF7DE) >> 1));
    }
}

void gfx_upscale2x(const surface *src, surface *dst) {
    if (step_x(dst) == 1 && !dst->x0 && !dst->y0) { /* the whole frame, row after row */
        for (int y = 0; y < src->h; y++) {
            uint16_t *d0 = dst->px + (2 * y) * dst->w;
            const uint16_t *sp = src->px + y * src->w;
            px2 *pair = (px2 *)d0; /* rows start at even pixels: each source pixel is one aligned word */
            for (int x = 0; x < src->w; x++) pair[x] = sp[x] * 0x00010001u;
            memcpy(d0 + dst->w, d0, (size_t)src->w * 2 * sizeof *d0); /* the second row is the first again */
        }
        return;
    }
    int xa = dst->x0, xb = dst->x0 + dst->w, ya = dst->y0, yb = dst->y0 + dst->h, ys = step_y(dst), xs = step_x(dst);
    if (xb > 2 * src->w) xb = 2 * src->w;
    if (yb > 2 * src->h) yb = 2 * src->h;
    if ((ys == 1 || ys == -1) && !(xs & 1) && !((xa | ya | xb | yb) & 1)) {
        /* a turned strip: each source pixel's 2x2 block is two aligned 32-bit words, one in each of two columns */
        const int w = src->w, qs = ys, qx = xs / 2, rows = (yb - ya) / 2;
        for (int x = xa; x < xb; x += 2) {
            const uint16_t *sp = src->px + (ya >> 1) * w + (x >> 1);
            uint16_t *d = at(dst, x, ya);
            px2 *q = (px2 *)(ys < 0 ? d - 1 : d);
            if (dst->swap)
                for (int k = 0; k < rows; k++, sp += w, q += qs) {
                    uint32_t v = *sp;
                    v = (v << 8 | v >> 8) & 0xFFFF;
                    q[0] = q[qx] = v | v << 16;
                }
            else
                for (int k = 0; k < rows; k++, sp += w, q += qs) q[0] = q[qx] = *sp * 0x00010001u;
        }
        return;
    }
    for (int x = xa; x < xb; x++) { /* any other window, pixel by pixel */
        uint16_t *d = at(dst, x, ya);
        for (int y = ya; y < yb; y++, d += ys) *d = stored(dst, src->px[(y >> 1) * src->w + x / 2]);
    }
}

void gfx_upscale2x_key(const surface *src, surface *dst, uint16_t key) {
    int xa = dst->x0, xb = dst->x0 + dst->w, ya = dst->y0, yb = dst->y0 + dst->h, ys = step_y(dst);
    if (xb > 2 * src->w) xb = 2 * src->w;
    if (yb > 2 * src->h) yb = 2 * src->h;
    for (int x = xa; x < xb; x++) { /* column by column: on the console's turned strips a column is contiguous */
        uint16_t *d = at(dst, x, ya);
        const uint16_t *sp = src->px + (ya >> 1) * src->w + x / 2;
        int y = ya;
        if (y & 1) { /* an odd first row: the second half of its source pixel */
            if (*sp != key) *d = stored(dst, *sp);
            d += ys, sp += src->w, y++;
        }
        for (; y + 1 < yb; y += 2, d += 2 * ys, sp += src->w)
            if (*sp != key) d[0] = d[ys] = stored(dst, *sp);
        if (y < yb && *sp != key) *d = stored(dst, *sp);
    }
}

/* A plain buffer (aligned, an even count: the world) mostly the key in HD: two pixels a word, skipped together. */
#define EACH_BUT_KEY(s, key, c, ...)                                                    \
    do {                                                                                \
        const uint32_t kk_ = (key) * 0x00010001u;                                       \
        uint16_t *p_ = (s)->px;                                                         \
        for (int i_ = 0; i_ < (s)->w * (s)->h; i_ += 2) {                               \
            if (*(px2 *)(p_ + i_) == kk_) continue;                                     \
            for (int j_ = i_; j_ < i_ + 2; j_++) {                                      \
                uint16_t c = p_[j_];                                                    \
                if (c == (key)) continue;                                               \
                __VA_ARGS__;                                                            \
                p_[j_] = c;                                                             \
            }                                                                           \
        }                                                                               \
    } while (0)

void gfx_shade_except(surface *s, uint16_t key) { EACH_BUT_KEY(s, key, c, c = (uint16_t)((c & 0xF7DE) >> 1)); }

void gfx_tint_dusk_except(surface *s, uint16_t key) {
    EACH_BUT_KEY(s, key, c, {
        int r = (c >> 11) * 5 / 8, g = ((c >> 5) & 63) * 11 / 16, b = (c & 31) * 13 / 16 + 2;
        c = (uint16_t)((r << 11) | (g << 5) | (b > 31 ? 31 : b));
    });
}

/* ponytail: fixed per-channel scale toward blue-grey; a LUT or palette swap if art needs finer control */
void gfx_tint_dusk(surface *s) {
    for (int y = s->y0; y < s->y0 + s->h; y++)
        for (int x = s->x0; x < s->x0 + s->w; x++) {
            uint16_t *d = at(s, x, y), c = stored(s, *d);
            int r = (c >> 11) * 5 / 8, g = ((c >> 5) & 63) * 11 / 16, b = (c & 31) * 13 / 16 + 2;
            *d = stored(s, (uint16_t)((r << 11) | (g << 5) | (b > 31 ? 31 : b)));
        }
}

/* Cards and signs in the style of the approved references: paper, 2 px ink border with cut corners,
 * a thin tan inner line and a soft drop shadow. */
/* Mecha theme ("corners": "cut"): top-left and bottom-right corners chamfered by c pixels. Column k (0..w-1) of such a
 * w x h card covers rows [top, return value): the first c rows start c - row in, the last c rows end row - (h - c) + 1
 * short. */
static int cut_column(int k, int w, int h, int c, int *top) {
    *top = k < c ? c - k : 0;
    int bot = w - k + h - c - 1;
    return bot < h ? bot : h;
}

/* Shade or fill rows [a, b) of column x, minus rows [ca, cb) that something drawn later covers. */
static void column_minus(surface *s, int x, int a, int b, int ca, int cb, bool shade, uint16_t col) {
    if (ca >= cb) ca = cb = b; /* nothing covers it */
    int spans[2][2] = {{a, ca < b ? ca : b}, {cb > a ? cb : a, b}};
    for (int i = 0; i < 2; i++) {
        if (spans[i][0] >= spans[i][1]) continue;
        if (shade) gfx_shade(s, x, spans[i][0], 1, spans[i][1] - spans[i][0]);
        else gfx_fill(s, x, spans[i][0], 1, spans[i][1] - spans[i][0], col);
    }
}

/* A cut-corner card, column by column so each pixel is drawn once: shade where only the shadow is, ink on the 2 px
 * border, paper inside. The same pixels as shading the whole shadow card, then filling the ink card, then the paper
 * card (c - 1 cut, 2 px in) on top; a turned panel strip stores columns contiguously. */
static void cut_card(surface *s, int x, int y, int w, int h, uint16_t fill, int shadow) {
    int c = h >= 24 ? 8 : 5, ka = s->x0 - x, kb = s->x0 + s->w - x; /* only the columns inside the window */
    if (ka < 0) ka = 0;
    if (kb > w + shadow) kb = w + shadow;
    /* the columns between the corners are all alike (shadow below, ink 2 rows each end, paper between): as boxes */
    int m0 = c + (shadow > 1 ? shadow : 1), m1 = w - c - 1;
    m0 = m0 > ka ? m0 : ka, m1 = m1 < kb ? m1 : kb;
    if (m0 < m1) {
        if (shadow) gfx_shade(s, x + m0, y + h, m1 - m0, shadow);
        gfx_fill(s, x + m0, y, m1 - m0, 2, C_INK);
        gfx_fill(s, x + m0, y + h - 2, m1 - m0, 2, C_INK);
        gfx_fill(s, x + m0, y + 2, m1 - m0, h - 4, fill);
    } else m0 = m1 = 0;
    for (int k = ka; k < kb; k++) {
        if (k >= m0 && k < m1) { /* (done) */
            k = m1 - 1;
            continue;
        }
        int it = 0, ib = 0, pt = 0, pb = 0, st = 0, sb = 0; /* ink, paper and shadow rows, relative to y */
        if (k < w) ib = cut_column(k, w, h, c, &it);
        if (k >= 2 && k < w - 2) pb = 2 + cut_column(k - 2, w - 4, h - 4, c - 1, &pt), pt += 2;
        if (shadow && k >= shadow) sb = shadow + cut_column(k - shadow, w, h, c, &st), st += shadow;
        if (st < sb) column_minus(s, x + k, y + st, y + sb, y + it, y + ib, true, 0);
        if (it < ib) column_minus(s, x + k, y + it, y + ib, y + pt, y + pb, false, C_INK);
        if (pt < pb) gfx_fill(s, x + k, y + pt, 1, pb - pt, fill);
    }
}

static void rounded(surface *s, int x, int y, int w, int h, uint16_t fill, int shadow) {
    if (G.th.cut) {
        cut_card(s, x, y, w, h, fill, shadow);
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
    col = stored(sf, col);
    for (int n = 0; s < e && (maxchars < 0 || n < maxchars); n++) {
        int c = utf8_cp1252(&s, e);
        if (c < 0) c = '?';
        const uint8_t *g = f->bits + (size_t)c * f->h * f->stride, *b = f->box ? f->box + 4 * c : NULL;
        int i0, j0, n = CLIP_X(sf, x, f->w, &i0), m = CLIP_Y(sf, y, f->h, &j0);
        int ia = b && b[0] > i0 ? b[0] : i0, ib = b && b[1] < i0 + n ? b[1] : i0 + n; /* the ink, clipped */
        int ja = b && b[2] > j0 ? b[2] : j0, jb = b && b[3] < j0 + m ? b[3] : j0 + m, xs = step_x(sf);
        for (int j = ja; ia < ib && j < jb; j++) {
            const uint8_t *gr = g + j * f->stride;
            uint16_t *d = at(sf, x + ia, y + j);
            for (int i = ia; i < ib; i++, d += xs)
                if (gr[i >> 3] & (0x80 >> (i & 7))) *d = col;
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
