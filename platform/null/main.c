/* bp_headless: validate content or run acceptance scripts without a window.
 *   bp_headless --game examples/hola [--saves DIR] [--fresh] (--validate | --script FILE)
 *               [--audio FILE.pcm] [--video FILE.mp4]   (tools/record.sh joins the two)
 *               [--crc FILE]   a CRC-32 of every other frame, to check that a change draws the same pixels
 *               [--check-strips]   every frame also drawn as the console's panel strips, which must match */
#include <dirent.h>
#include <signal.h>
#include <stdio.h>
#include <string.h>
#include <sys/stat.h>
#include <unistd.h>

#include "bp.h"

#ifndef NP2D_GAME /* the build's GAME_DIR (CMakeLists.txt) */
#define NP2D_GAME "examples/hola"
#endif

static void wipe_saves(const char *dir) {
    mkdir(dir, 0755);
    DIR *d = opendir(dir);
    if (!d) return;
    for (struct dirent *e; (e = readdir(d));) {
        size_t n = strlen(e->d_name);
        if (n > 4 && (!strcmp(e->d_name + n - 4, ".sav") || !strcmp(e->d_name + n - 4, ".ppm"))) {
            char p[512];
            snprintf(p, sizeof p, "%s/%s", dir, e->d_name);
            unlink(p);
        }
    }
    closedir(d);
}

static FILE *dump; /* --audio FILE: the game's mix as raw PCM16 mono at AUDIO_HZ, to listen to a run */

/* Mixes one tick of audio per game tick, so every script also exercises the mixer (under ASan in Debug). */
static void mix_tick(void) {
    static int16_t buf[AUDIO_HZ / TICK_HZ + 1];
    static int frac;
    int n = AUDIO_HZ / TICK_HZ + ((frac += AUDIO_HZ % TICK_HZ) >= TICK_HZ ? 1 : 0); /* 367.5 per tick, exact */
    if (frac >= TICK_HZ) frac -= TICK_HZ;
    hal_audio_lock();
    audio_mix(buf, n);
    hal_audio_unlock();
    if (dump) fwrite(buf, 2, (size_t)n, dump);
}

static FILE *video; /* --video FILE.mp4: every other frame (30 fps) through ffmpeg, to watch a run */
static FILE *crcs;  /* --crc FILE: a CRC-32 of every other frame, one per line, to compare two builds frame by frame */

static uint32_t crc32(const void *data, size_t n) {
    const uint8_t *p = data;
    uint32_t c = 0xFFFFFFFFu;
    while (n--) {
        c ^= *p++;
        for (int k = 0; k < 8; k++) c = c >> 1 ^ (0xEDB88320u & -(c & 1));
    }
    return ~c;
}

static bool check_strips; /* --check-strips: every frame drawn whole and as the console's 32-row panel strips */
static int strip_errors;

/* The frame drawn strip by strip into a turned panel, as the firmware does (the world pass is done: game_render just
 * did it), against the frame drawn whole. */
static void compare_strips(const uint16_t *fb, unsigned n) {
    enum { ROWS = 32 };
    static uint16_t strip[ROWS * SCREEN_H];
    bool flip = n & 2, swap = n & 4; /* both ways round and both byte orders, frame about */
    for (int r0 = 0; r0 < SCREEN_W; r0 += ROWS) {
        surface s = gfx_turned(strip, r0, ROWS, SCREEN_W, SCREEN_H, flip, swap);
        game_draw(&s, false);
        for (int k = 0; k < ROWS; k++)
            for (int p = 0; p < SCREEN_H; p++) {
                int r = r0 + k, x = flip ? SCREEN_W - 1 - r : r, y = flip ? p : SCREEN_H - 1 - p;
                uint16_t v = strip[k * SCREEN_H + p];
                if (swap) v = (uint16_t)(v << 8 | v >> 8);
                strip[k * SCREEN_H + p] = v;
                if (v == fb[y * SCREEN_W + x]) continue;
                if (strip_errors++ < 5)
                    fprintf(stderr, "strips differ at frame %u, pixel (%d, %d)%s%s: %04x whole, %04x strip\n", n, x, y,
                            flip ? " flipped" : "", swap ? " swapped" : "", fb[y * SCREEN_W + x], v);
            }
    }
}

static void frame_tick(void) {
    static uint16_t fb[SCREEN_W * SCREEN_H];
    static unsigned n;
    mix_tick();
    if ((!video && !crcs && !check_strips) || n++ % 2) return;
    game_render(fb);
    if (check_strips) compare_strips(fb, n);
    if (video) fwrite(fb, 2, SCREEN_W * SCREEN_H, video);
    if (crcs) fprintf(crcs, "%08x\n", (unsigned)crc32(fb, sizeof fb));
}

static FILE *open_video(const char *path) {
    if (strchr(path, '\'')) {
        fprintf(stderr, "--video: the path cannot contain a quote\n");
        return NULL;
    }
    signal(SIGPIPE, SIG_IGN); /* if ffmpeg dies, writes fail and pclose reports it, instead of killing the run */
    char cmd[1024]; /* pixel art: 2x nearest, so the video keeps hard pixels */
    snprintf(cmd, sizeof cmd,
             "ffmpeg -loglevel error -y -f rawvideo -pixel_format rgb565le -video_size %dx%d -framerate %d -i - "
             "-vf scale=iw*2:ih*2:flags=neighbor -c:v libx264 -pix_fmt yuv420p -crf 18 '%s'",
             SCREEN_W, SCREEN_H, TICK_HZ / 2, path);
    FILE *f = popen(cmd, "w");
    if (!f) fprintf(stderr, "cannot start ffmpeg for %s\n", path);
    return f;
}

int main(int argc, char **argv) {
    bp_config cfg = {NP2D_GAME, NULL};
    const char *script = NULL;
    bool validate = false, fresh = false;
    for (int i = 1; i < argc; i++) {
        if (!strcmp(argv[i], "--game") && i + 1 < argc) cfg.game_dir = argv[++i];
        else if (!strcmp(argv[i], "--saves") && i + 1 < argc) cfg.save_dir = argv[++i];
        else if (!strcmp(argv[i], "--script") && i + 1 < argc) script = argv[++i];
        else if (!strcmp(argv[i], "--validate")) validate = true;
        else if (!strcmp(argv[i], "--fresh")) fresh = true;
        else if (!strcmp(argv[i], "--audio") && i + 1 < argc) dump = fopen(argv[++i], "wb");
        else if (!strcmp(argv[i], "--crc") && i + 1 < argc) crcs = fopen(argv[++i], "w");
        else if (!strcmp(argv[i], "--check-strips")) check_strips = true;
        else if (!strcmp(argv[i], "--video") && i + 1 < argc) {
            if (!(video = open_video(argv[++i]))) return 2;
        }
        else {
            fprintf(stderr, "usage: %s --game DIR [--saves DIR] [--fresh] (--validate | --script FILE) "
                            "[--audio FILE.pcm] [--video FILE.mp4] [--crc FILE] [--check-strips]\n", argv[0]);
            return 2;
        }
    }
    char default_saves[512];
    snprintf(default_saves, sizeof default_saves, "%s/saves", cfg.game_dir);
    if (fresh) wipe_saves(cfg.save_dir ? cfg.save_dir : default_saves);
    if (!game_init(&cfg)) {
        fprintf(stderr, "game folder incomplete: %s\n", cfg.game_dir);
        return 2;
    }
    int rc = 0;
    if (validate) rc = content_validate() ? 1 : 0;
    if (script && !rc) rc = script_run(script, frame_tick);
    game_shutdown();
    if (dump) fclose(dump);
    if (crcs) fclose(crcs);
    if (strip_errors) {
        fprintf(stderr, "check-strips: %d pixels differ\n", strip_errors);
        rc = rc ? rc : 3;
    }
    if (video && pclose(video)) rc = rc ? rc : 1;
    return rc;
}
