/* bp_headless: validate content or run acceptance scripts without a window.
 *   bp_headless --game examples/hola [--saves DIR] [--fresh] (--validate | --script FILE)
 *               [--audio FILE.pcm] [--video FILE.mp4]   (tools/record.sh joins the two) */
#include <dirent.h>
#include <signal.h>
#include <stdio.h>
#include <string.h>
#include <sys/stat.h>
#include <unistd.h>

#include "bp.h"

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

static void frame_tick(void) {
    static uint16_t fb[SCREEN_W * SCREEN_H];
    static unsigned n;
    mix_tick();
    if (!video || n++ % 2) return;
    game_render(fb);
    fwrite(fb, 2, SCREEN_W * SCREEN_H, video);
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
    bp_config cfg = {"examples/hola", NULL};
    const char *script = NULL;
    bool validate = false, fresh = false;
    for (int i = 1; i < argc; i++) {
        if (!strcmp(argv[i], "--game") && i + 1 < argc) cfg.game_dir = argv[++i];
        else if (!strcmp(argv[i], "--saves") && i + 1 < argc) cfg.save_dir = argv[++i];
        else if (!strcmp(argv[i], "--script") && i + 1 < argc) script = argv[++i];
        else if (!strcmp(argv[i], "--validate")) validate = true;
        else if (!strcmp(argv[i], "--fresh")) fresh = true;
        else if (!strcmp(argv[i], "--audio") && i + 1 < argc) dump = fopen(argv[++i], "wb");
        else if (!strcmp(argv[i], "--video") && i + 1 < argc) {
            if (!(video = open_video(argv[++i]))) return 2;
        }
        else {
            fprintf(stderr, "usage: %s --game DIR [--saves DIR] [--fresh] (--validate | --script FILE) "
                            "[--audio FILE.pcm] [--video FILE.mp4]\n", argv[0]);
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
    if (video && pclose(video)) rc = rc ? rc : 1;
    return rc;
}
