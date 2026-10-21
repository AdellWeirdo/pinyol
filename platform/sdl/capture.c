/* Screenshots, covers and GIFs from the simulator (capture.h). The PNG is written here (stored deflate blocks, no
 * compression: a screenshot is small and nothing else is needed); the GIF by msf_gif (third_party/msf_gif, MIT). */
#include <stdio.h>
#include <stdlib.h>
#include <string.h>

#define MSF_GIF_IMPL
#include "msf_gif.h"

#include "bp.h"
#include "capture.h"

#define GIF_SECONDS 8
#define GIF_FPS 30 /* every other frame: the GIF's clock is in hundredths of a second */
#define GIF_FRAMES (GIF_SECONDS * GIF_FPS)

static uint16_t *ring;    /* GIF_FRAMES frames of 480x320, the oldest overwritten */
static int ring_n, ring_at, frames_seen;
static char last_path[512];

const char *capture_last(void) { return last_path; }

void capture_frame(const uint16_t *fb) {
    if (frames_seen++ & 1) return;
    if (!ring) ring = malloc((size_t)GIF_FRAMES * SCREEN_W * SCREEN_H * sizeof *ring);
    if (!ring) return;
    memcpy(ring + (size_t)ring_at * SCREEN_W * SCREEN_H, fb, (size_t)SCREEN_W * SCREEN_H * sizeof *fb);
    ring_at = (ring_at + 1) % GIF_FRAMES;
    if (ring_n < GIF_FRAMES) ring_n++;
}

static FILE *numbered(const char *dir, const char *stem, const char *ext) { /* dir/stem-N.ext, the first N not taken */
    for (int n = 1; n < 10000; n++) {
        snprintf(last_path, sizeof last_path, "%s/%s-%d.%s", dir, stem, n, ext);
        FILE *f = fopen(last_path, "rb");
        if (f) { fclose(f); continue; }
        return fopen(last_path, "wb");
    }
    return NULL;
}

/* ---- PNG: RGB8, one IDAT of stored deflate blocks (each 65535 bytes at most) */
static void put32(FILE *f, uint32_t v) { fputc(v >> 24, f), fputc(v >> 16, f), fputc(v >> 8, f), fputc(v, f); }

static void chunk(FILE *f, const char *type, const uint8_t *data, size_t n) {
    uint8_t *buf = malloc(n + 4);
    if (!buf) return;
    memcpy(buf, type, 4);
    if (n) memcpy(buf + 4, data, n);
    put32(f, (uint32_t)n);
    fwrite(buf, 1, n + 4, f);
    put32(f, crc32_buf(buf, n + 4));
    free(buf);
}

bool capture_png(const uint16_t *fb, const char *dir) {
    const size_t row = (size_t)SCREEN_W * 3 + 1, raw_n = row * SCREEN_H;
    uint8_t *raw = malloc(raw_n);
    if (!raw) return false;
    for (int y = 0; y < SCREEN_H; y++) {
        uint8_t *p = raw + y * row;
        *p++ = 0; /* no filter */
        for (int x = 0; x < SCREEN_W; x++) {
            const uint16_t v = fb[y * SCREEN_W + x];
            const unsigned r = v >> 11, g = v >> 5 & 63, b = v & 31;
            *p++ = (uint8_t)(r << 3 | r >> 2), *p++ = (uint8_t)(g << 2 | g >> 4), *p++ = (uint8_t)(b << 3 | b >> 2);
        }
    }
    /* zlib: a header, stored blocks, adler32 */
    const size_t blocks = (raw_n + 65534) / 65535, z_n = 2 + raw_n + blocks * 5 + 4;
    uint8_t *z = malloc(z_n);
    if (!z) return free(raw), false;
    size_t at = 0;
    z[at++] = 0x78, z[at++] = 0x01;
    uint32_t a = 1, b = 0;
    for (size_t i = 0; i < raw_n; i++) a = (a + raw[i]) % 65521, b = (b + a) % 65521;
    for (size_t off = 0; off < raw_n; off += 65535) {
        const size_t n = raw_n - off < 65535 ? raw_n - off : 65535;
        z[at++] = off + n == raw_n ? 1 : 0;
        z[at++] = (uint8_t)n, z[at++] = (uint8_t)(n >> 8), z[at++] = (uint8_t)~n, z[at++] = (uint8_t)(~n >> 8);
        memcpy(z + at, raw + off, n), at += n;
    }
    z[at++] = (uint8_t)(b >> 8), z[at++] = (uint8_t)b, z[at++] = (uint8_t)(a >> 8), z[at++] = (uint8_t)a;
    free(raw);
    FILE *f = numbered(dir, "pantalla", "png");
    if (!f) return free(z), false;
    static const uint8_t SIG[8] = {137, 80, 78, 71, 13, 10, 26, 10};
    fwrite(SIG, 1, 8, f);
    uint8_t ihdr[13] = {0, 0, (uint8_t)(SCREEN_W >> 8), (uint8_t)SCREEN_W, 0, 0, (uint8_t)(SCREEN_H >> 8), (uint8_t)SCREEN_H, 8, 2, 0, 0, 0};
    chunk(f, "IHDR", ihdr, 13);
    chunk(f, "IDAT", z, at);
    chunk(f, "IEND", NULL, 0);
    free(z);
    return fclose(f) == 0;
}

bool capture_gif(const char *dir) {
    if (!ring_n) return false;
    MsfGifState g = {0};
    if (!msf_gif_begin(&g, SCREEN_W, SCREEN_H)) return false;
    uint8_t *rgba = malloc((size_t)SCREEN_W * SCREEN_H * 4);
    if (!rgba) return false;
    for (int k = 0; k < ring_n; k++) {
        const uint16_t *fr = ring + (size_t)((ring_at - ring_n + k + GIF_FRAMES) % GIF_FRAMES) * SCREEN_W * SCREEN_H;
        for (int i = 0; i < SCREEN_W * SCREEN_H; i++) {
            const uint16_t v = fr[i];
            const unsigned r = v >> 11, gg = v >> 5 & 63, b = v & 31;
            rgba[i * 4] = (uint8_t)(r << 3 | r >> 2), rgba[i * 4 + 1] = (uint8_t)(gg << 2 | gg >> 4);
            rgba[i * 4 + 2] = (uint8_t)(b << 3 | b >> 2), rgba[i * 4 + 3] = 255;
        }
        msf_gif_frame(&g, rgba, 100 / GIF_FPS, 16, SCREEN_W * 4);
    }
    free(rgba);
    MsfGifResult r = msf_gif_end(&g);
    bool ok = false;
    if (r.data) {
        FILE *f = numbered(dir, "clip", "gif");
        if (f) ok = fwrite(r.data, 1, r.dataSize, f) == r.dataSize && fclose(f) == 0;
    }
    msf_gif_free(r);
    return ok;
}

bool capture_cover(const uint16_t *fb, const char *game_dir) { /* every other pixel: a game's world pixels are whole */
    snprintf(last_path, sizeof last_path, "%s/cover.rgb565", game_dir);
    FILE *f = fopen(last_path, "wb");
    if (!f) return false;
    for (int y = 0; y < COVER_H; y++)
        for (int x = 0; x < COVER_W; x++) {
            const uint16_t v = fb[(y * 2) * SCREEN_W + x * 2];
            fputc(v & 255, f), fputc(v >> 8, f);
        }
    return fclose(f) == 0;
}
