/* The sample voices with options (audio_sfx_play_opts), as an instrument uses them: a start delay to the sample, a loop inside
 * the clip, and an envelope with its release (the attack climbs evenly, the decay and the release fall by a constant factor a
 * sample). Clips are made from numbers, so every sample can be named. */
#include <math.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>

#include "bp.h"
#include "studio_synth.h"

static int failures, checks;
#define CHECK(c)                                                                             \
    do {                                                                                     \
        checks++;                                                                            \
        if (!(c)) failures++, fprintf(stderr, "%s:%d: CHECK(%s)\n", __FILE__, __LINE__, #c); \
    } while (0)

#define N 4096
static int16_t out[N];

static void mix(int off, int n) { /* the audio thread's block (at most 256), the lock held as it is there */
    hal_audio_lock();
    audio_mix(out + off, n);
    hal_audio_unlock();
}

static void make(const char *id, int n, int16_t (*f)(int)) {
    int16_t *pcm = malloc(sizeof(int16_t) * (size_t)n);
    for (int i = 0; i < n; i++) pcm[i] = f(i);
    audio_sfx_set(id, pcm, n);
}

static int16_t level(int i) { (void)i; return 10000; }
static int16_t ramp(int i) { return (int16_t)(i * 10); }
static int16_t click(int i) { return (int16_t)(i == 0 ? 20000 : 0); }

static int peak(int a, int b) {
    int p = 0;
    for (int i = a; i < b; i++) p = abs(out[i]) > p ? abs(out[i]) : p;
    return p;
}

int main(void) {
    sfx_opts o;
    /* a start delay lands on its sample */
    audio_reset();
    make("CLICK", 64, click);
    o = (sfx_opts){.gain = 1, .pitch = 1, .wait = 100};
    CHECK(audio_sfx_play_opts("CLICK", &o) != 0);
    memset(out, 0, sizeof out);
    mix(0, 256);
    CHECK(peak(0, 100) == 0 && out[100] == 20000 && peak(101, 256) == 0);

    /* a loop inside the clip: 0..299, then 200..299 again and again */
    audio_reset();
    make("RAMP", 1000, ramp);
    o = (sfx_opts){.gain = 1, .pitch = 1, .loop = true, .loop_start = 200, .loop_end = 300};
    int h = audio_sfx_play_opts("RAMP", &o);
    mix(0, 256);
    mix(256, 256);
    CHECK(out[0] == 0 && out[299] == 2990 && out[300] == 2000 && out[399] == 2990 && out[400] == 2000);
    CHECK(out[500] == 2000 && audio_sfx_playing(h));
    /* nonsense bounds play the whole clip */
    audio_reset();
    make("RAMP", 1000, ramp);
    o.loop_start = 500, o.loop_end = 400;
    audio_sfx_play_opts("RAMP", &o);
    mix(0, 256);
    CHECK(out[255] == 2550);

    /* an envelope: attack 100 samples, decay 100 to 0.5 (exponential: most of the way there at the end), sustain, release */
    audio_reset();
    make("LEVEL", 1000, level);
    o = (sfx_opts){.gain = 1, .pitch = 1, .loop = true, .env = true, .attack = 100.0f / AUDIO_HZ, .decay = 100.0f / AUDIO_HZ,
                   .sustain = 0.5f, .release = 100.0f / AUDIO_HZ};
    h = audio_sfx_play_opts("LEVEL", &o);
    mix(0, 256);
    CHECK(abs(out[50] - 5000) < 200);                       /* half way up the attack */
    CHECK(out[99] > 9500 && out[99] <= 10000);              /* the top */
    CHECK(out[150] < out[101] && out[150] > 5000);          /* falling towards the sustain */
    CHECK(abs(out[255] - 5000) < 100 && abs(out[240] - 5000) < 100); /* sustain */
    audio_sfx_stop(h);
    CHECK(audio_sfx_playing(h));                            /* a voice with a release goes on until it is quiet */
    mix(256, 512);
    CHECK(out[256] > 4500 && out[256] < 5100);              /* the release starts from the level it was at */
    CHECK(out[300] < out[256] && out[356] < out[300]);      /* and falls */
    CHECK(peak(700, 768) == 0 && !audio_sfx_playing(h));    /* done: silent and the voice is free */
    /* stopping a sound with no envelope stops it at once */
    audio_reset();
    make("LEVEL", 1000, level);
    o = (sfx_opts){.gain = 1, .pitch = 1, .loop = true};
    h = audio_sfx_play_opts("LEVEL", &o);
    audio_sfx_stop(h);
    CHECK(!audio_sfx_playing(h));
    /* the envelope is the same however the blocks fall: one block of 256 or 256 of 1 */
    audio_reset();
    make("LEVEL", 1000, level);
    o = (sfx_opts){.gain = 1, .pitch = 1, .loop = true, .env = true, .attack = 30.0f / AUDIO_HZ, .decay = 40.0f / AUDIO_HZ,
                   .sustain = 0.25f, .release = 50.0f / AUDIO_HZ};
    audio_sfx_play_opts("LEVEL", &o);
    mix(0, 256);
    static int16_t ref[256];
    memcpy(ref, out, sizeof ref);
    audio_reset();
    make("LEVEL", 1000, level);
    audio_sfx_play_opts("LEVEL", &o);
    for (int i = 0; i < 256; i++) mix(i, 1);
    CHECK(!memcmp(ref, out, sizeof ref));

    printf("audio_voice: %d checks, %d failed\n", checks, failures);
    return failures != 0;
}
