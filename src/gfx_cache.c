/* Pictures worked out once and kept: a styled line of text, a nine-slice frame of a size, a turned picture. Drawing
 * them is costly, and the console draws the screen in fifteen strips, sixty times a second; drawn once into a picture
 * of their own, every strip copies them by the fast way pictures go. Most of them are the same from one frame to the
 * next (a title, a frame, a score in its style), so they are kept, the least recently used going when the room runs
 * out; those used in the frame being drawn always stay. */
#include <stdlib.h>
#include <string.h>

#include "bp.h"

#define PIC_MAX 128
#define PIC_BYTES (1536 * 1024) /* PSRAM for all of them */

typedef struct { /* in a slot of its own while it lives: the frame's commands point at it */
    bool used;
    uint32_t hash, frame; /* frame: when it was last used */
    uint8_t *key;
    int klen;
    size_t bytes;
    asset a;
} pic;

static pic pics[PIC_MAX];
static size_t bytes;

static uint32_t hash_of(const void *key, int len) {
    uint32_t h = 2166136261u;
    for (int i = 0; i < len; i++) h = (h ^ ((const uint8_t *)key)[i]) * 16777619u;
    return h;
}

static void drop(int i) {
    free(pics[i].key), free(pics[i].a.pixels), free(pics[i].a.mask);
    bytes -= pics[i].bytes;
    memset(&pics[i], 0, sizeof pics[i]);
}

void pic_reset(void) {
    for (int i = 0; i < PIC_MAX; i++)
        if (pics[i].used) drop(i);
}

asset *pic_find(const void *key, int len, uint32_t frame) {
    uint32_t h = hash_of(key, len);
    for (int i = 0; i < PIC_MAX; i++)
        if (pics[i].used && pics[i].hash == h && pics[i].klen == len && !memcmp(pics[i].key, key, (size_t)len)) {
            pics[i].frame = frame;
            return &pics[i].a;
        }
    return NULL;
}

/* A new picture w x h for key, see-through, to draw into (then pic_done); NULL if there is no room even after the
 * ones not used this frame went. */
asset *pic_make(const void *key, int len, int w, int h, uint32_t frame) {
    if (w < 1 || h < 1 || w > 1024 || h > 1024) return NULL;
    size_t need = (size_t)w * h * 2 + (size_t)((w + 7) / 8) * h + (size_t)len;
    if (need > PIC_BYTES) return NULL;
    int slot = -1;
    for (;;) {
        for (int i = 0; i < PIC_MAX && slot < 0; i++)
            if (!pics[i].used) slot = i;
        if (slot >= 0 && bytes + need <= PIC_BYTES) break;
        int old = -1; /* no slot or no room: the least recently used goes, never one of this frame's */
        for (int i = 0; i < PIC_MAX; i++)
            if (pics[i].used && pics[i].frame != frame && (old < 0 || pics[i].frame < pics[old].frame)) old = i;
        if (old < 0) return NULL;
        drop(old);
    }
    pic *p = &pics[slot];
    memset(p, 0, sizeof *p);
    p->key = malloc((size_t)len);
    p->a.pixels = hal_realloc_slow(NULL, (size_t)w * h * 2);
    p->a.mask = hal_realloc_slow(NULL, (size_t)((w + 7) / 8) * h);
    if (!p->key || !p->a.pixels || !p->a.mask) {
        free(p->key), free(p->a.pixels), free(p->a.mask);
        return NULL;
    }
    memcpy(p->key, key, (size_t)len);
    p->used = true, p->hash = hash_of(key, len), p->klen = len, p->frame = frame, p->bytes = need;
    p->a.w = w, p->a.h = h, p->a.frames = 1, p->a.canvas = true;
    for (int i = 0; i < w * h; i++) p->a.pixels[i] = CANVAS_KEY;
    bytes += need;
    return &p->a;
}

void pic_done(asset *a) { /* drawn into: its mask from its see-through key; none if it is opaque all over */
    for (int i = 0; i < a->w * a->h; i++)
        if (a->pixels[i] == CANVAS_KEY) {
            gfx_canvas_mask(a, 0, 0, a->w, a->h);
            return;
        }
    for (int i = 0; i < PIC_MAX; i++)
        if (&pics[i].a == a) pics[i].bytes -= (size_t)((a->w + 7) / 8) * a->h;
    bytes -= (size_t)((a->w + 7) / 8) * a->h;
    free(a->mask);
    a->mask = NULL; /* opaque: copied the fastest way */
}
