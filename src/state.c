/* Flags (every persistent fact is a named int), save slots with CRC and A/B files, settings. */
#include <stdlib.h>
#include <string.h>
#include <unistd.h>

#include "bp.h"

#define FLAG_SLOTS 2048 /* ponytail: fixed open-addressing table; grow if a chapter needs >1500 names */

static struct { char *name; int16_t val; } flags[FLAG_SLOTS];

static uint32_t hash(const char *s) {
    uint32_t h = 2166136261u;
    while (*s) h = (h ^ (uint8_t)*s++) * 16777619u;
    return h;
}

static int slot_of(const char *name, bool create) {
    uint32_t i = hash(name) & (FLAG_SLOTS - 1);
    for (int n = 0; n < FLAG_SLOTS; n++, i = (i + 1) & (FLAG_SLOTS - 1)) {
        if (!flags[i].name) {
            if (!create) return -1;
            flags[i].name = strdup(name);
            return (int)i;
        }
        if (!strcmp(flags[i].name, name)) return (int)i;
    }
    hal_log("flag table full");
    return -1;
}

int flag_get(const char *name) {
    int i = slot_of(name, false);
    return i < 0 ? 0 : flags[i].val;
}

void flag_set(const char *name, int v) {
    int i = slot_of(name, v != 0);
    if (i >= 0) flags[i].val = (int16_t)v;
}

void flags_reset(void) {
    for (int i = 0; i < FLAG_SLOTS; i++) flags[i].val = 0;
}

void flagf_set(int v, const char *fmt, const char *a, const char *b) {
    char k[96];
    snprintf(k, sizeof k, fmt, a, b);
    flag_set(k, v);
}

int flagf_get(const char *fmt, const char *a, const char *b) {
    char k[96];
    snprintf(k, sizeof k, fmt, a, b);
    return flag_get(k);
}

uint32_t crc32_buf(const uint8_t *p, size_t n) {
    uint32_t c = 0xFFFFFFFFu;
    while (n--) {
        c ^= *p++;
        for (int k = 0; k < 8; k++) c = (c >> 1) ^ (0xEDB88320u & (0u - (c & 1)));
    }
    return ~c;
}

/* ------------------------------------------------------------------ save files
 * header: "BPSV" u16 schema u16 content_version u32 payload_len u32 crc32(payload), little endian
 * payload: text lines "key=value"; flags as "f name=value". Names, never indices. */
#define HDR 16

static void put16(uint8_t *p, uint32_t v) { p[0] = v & 0xFF; p[1] = (v >> 8) & 0xFF; }
static void put32(uint8_t *p, uint32_t v) { put16(p, v & 0xFFFF); put16(p + 2, v >> 16); }
static uint32_t get16(const uint8_t *p) { return p[0] | (p[1] << 8); }
static uint32_t get32(const uint8_t *p) { return get16(p) | (get16(p + 2) << 16); }

static int content_version(void) { return jint(G.game, "content_version", 1); }

static void path_of(char *out, size_t n, const char *slot, char ab) {
    snprintf(out, n, "%s/%s_%c.sav", G.save_dir, slot, ab);
}

/* Returns malloc'd payload (NUL-terminated) of a valid file, NULL otherwise. */
static char *read_valid(const char *path, uint32_t *seq, bool *same_content) {
    long len = 0;
    uint8_t *d = (uint8_t *)read_file(path, &len);
    if (!d) return NULL;
    bool ok = len >= HDR && !memcmp(d, "BPSV", 4) && get16(d + 4) == SCHEMA_VERSION &&
              (long)get32(d + 8) == len - HDR && crc32_buf(d + HDR, len - HDR) == get32(d + 12);
    if (!ok) {
        hal_log("save %s invalid, ignored", path);
        free(d);
        return NULL;
    }
    if (same_content) *same_content = (int)get16(d + 6) == content_version();
    char *payload = malloc(len - HDR + 1);
    if (!payload) {
        hal_log("save %s: out of memory", path);
        free(d);
        return NULL;
    }
    memcpy(payload, d + HDR, len - HDR);
    payload[len - HDR] = 0;
    free(d);
    const char *s = strstr(payload, "seq=");
    *seq = s ? (uint32_t)strtoul(s + 4, NULL, 10) : 0;
    return payload;
}

/* Picks the newest valid file of a slot; *ab gets 'a' or 'b'. */
static char *read_slot(const char *slot, uint32_t *seq, char *ab, bool *same_content) {
    char pa[320], pb[320];
    path_of(pa, sizeof pa, slot, 'a');
    path_of(pb, sizeof pb, slot, 'b');
    uint32_t sa = 0, sb = 0;
    bool ca = true, cb = true;
    char *a = read_valid(pa, &sa, &ca), *b = read_valid(pb, &sb, &cb);
    if (a && (!b || sa >= sb)) {
        free(b);
        *seq = sa; if (ab) *ab = 'a'; if (same_content) *same_content = ca;
        return a;
    }
    if (b) {
        free(a);
        *seq = sb; if (ab) *ab = 'b'; if (same_content) *same_content = cb;
        return b;
    }
    return NULL;
}

bool save_peek(const char *slot, uint32_t *seq_out) {
    uint32_t seq = 0;
    char *p = read_slot(slot, &seq, NULL, NULL);
    free(p);
    if (seq_out) *seq_out = seq;
    return p != NULL;
}

const char *save_newest(void) {
    static const char *slots[] = {"auto", "manual", "prefinal"};
    const char *best = NULL;
    uint32_t best_seq = 0;
    for (int i = 0; i < 3; i++) {
        uint32_t s;
        if (save_peek(slots[i], &s) && (!best || s > best_seq)) {
            best = slots[i];
            best_seq = s;
        }
    }
    return best;
}

bool save_write(const char *slot) {
    uint32_t seq_a = 0;
    char ab = 'b';
    char *cur = read_slot(slot, &seq_a, &ab, NULL);
    char target = cur && ab == 'a' ? 'b' : 'a'; /* overwrite the older file, keep the newest valid */
    free(cur);
    if (G.save_seq < seq_a) G.save_seq = seq_a;
    G.save_seq++;

    size_t cap = 4096, n = 0;
    char *buf = malloc(cap);
    n += snprintf(buf + n, cap - n, "seq=%u\nzone=%s\npos=%.2f,%.2f\nfacing=%d\np01=%d,%d,%d\n", (unsigned)G.save_seq, G.zone.id,
                  G.klaus.x, G.klaus.y, G.klaus.facing, G.pz.x, G.pz.y, G.pz.rot);
    for (int i = 0; i < FLAG_SLOTS; i++) {
        if (!flags[i].name || !flags[i].val) continue;
        size_t need = strlen(flags[i].name) + 16;
        if (n + need >= cap) buf = realloc(buf, cap *= 2);
        n += snprintf(buf + n, cap - n, "f %s=%d\n", flags[i].name, flags[i].val);
    }
    uint8_t hdr[HDR];
    memcpy(hdr, "BPSV", 4);
    put16(hdr + 4, SCHEMA_VERSION);
    put16(hdr + 6, (uint32_t)content_version());
    put32(hdr + 8, (uint32_t)n);
    put32(hdr + 12, crc32_buf((uint8_t *)buf, n));

    char path[320];
    path_of(path, sizeof path, slot, target);
    FILE *f = fopen(path, "wb");
    bool ok = f && fwrite(hdr, 1, HDR, f) == HDR && fwrite(buf, 1, n, f) == n && fflush(f) == 0 && fsync(fileno(f)) == 0;
    if (f) ok = (fclose(f) == 0) && ok;
    free(buf);
    if (!ok) hal_log("save %s failed", path);
    return ok;
}

bool save_load(const char *slot) {
    uint32_t seq = 0;
    bool same_content = true;
    char *p = read_slot(slot, &seq, NULL, &same_content);
    if (!p) return false;
    flags_reset();
    char zone[8] = "Z01";
    float x = 0, y = 0;
    int facing = DIR_S, px = 0, py = 0, prot = 0;
    char *save_ptr = NULL;
    for (char *line = strtok_r(p, "\n", &save_ptr); line; line = strtok_r(NULL, "\n", &save_ptr)) {
        if (!strncmp(line, "f ", 2)) {
            char *eq = strrchr(line, '=');
            if (!eq) continue;
            *eq = 0;
            flag_set(line + 2, atoi(eq + 1));
        } else if (!strncmp(line, "zone=", 5)) snprintf(zone, sizeof zone, "%s", line + 5);
        else if (!strncmp(line, "pos=", 4)) sscanf(line + 4, "%f,%f", &x, &y);
        else if (!strncmp(line, "facing=", 7)) facing = atoi(line + 7) & 3;
        else if (!strncmp(line, "p01=", 4)) sscanf(line + 4, "%d,%d,%d", &px, &py, &prot);
    }
    free(p);
    if (G.save_seq < seq) G.save_seq = seq;
    G.pz.x = px;
    G.pz.y = py;
    G.pz.rot = prot & 3;
    if (!world_enter(zone, NULL)) return true; /* error screen is up; the save file is untouched */
    G.klaus.x = x;
    G.klaus.y = y;
    G.klaus.facing = facing;
    if (!same_content || !world_box_free(x, y)) world_safe_position();
    return true;
}

/* ------------------------------------------------------------------ settings */
void settings_load(void) {
    char path[320];
    snprintf(path, sizeof path, "%s/settings.txt", G.save_dir);
    G.large_text = false;
    G.portraits = true;
    G.bag = false;
    G.volume = VOLUME_MAX;
    G.tones = true;
    char *d = read_file(path, NULL);
    if (!d) return;
    const char *l = strstr(d, "large=");
    if (l) G.large_text = l[6] == '1';
    const char *p = strstr(d, "portraits=");
    if (p) G.portraits = p[10] == '1';
    const char *b = strstr(d, "bag=");
    if (b) G.bag = b[4] == '1';
    const char *v = strstr(d, "vol=");
    if (v && v[4] >= '0' && v[4] <= '0' + VOLUME_MAX) G.volume = v[4] - '0';
    const char *t = strstr(d, "tones=");
    if (t) G.tones = t[6] == '1';
    free(d);
}

void settings_save(void) {
    char path[320];
    snprintf(path, sizeof path, "%s/settings.txt", G.save_dir);
    FILE *f = fopen(path, "w");
    if (!f) return;
    fprintf(f, "large=%d\nportraits=%d\nbag=%d\nvol=%d\ntones=%d\n", G.large_text, G.portraits, G.bag, G.volume, G.tones);
    fclose(f);
}
