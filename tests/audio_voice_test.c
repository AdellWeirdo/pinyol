/* The sample voices with options (audio_voice_play): a start delay to the sample, a loop inside the clip, an envelope with
 * its release, a gain that eases instead of stepping, and sends to the effects. Clips are made from numbers, so every
 * sample can be named. */
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
    /* a start delay lands on its sample */
    audio_reset();
    make("CLICK", 64, click);
    voice_opts o = {.gain = 1, .pitch = 1, .delay = 100};
    CHECK(audio_voice_play("CLICK", &o) != 0);
    memset(out, 0, sizeof out);
    mix(0, 256);
    CHECK(peak(0, 100) == 0 && out[100] == 20000 && peak(101, 256) == 0);

    /* a loop inside the clip: 0..299, then 200..299 again and again */
    audio_reset();
    make("RAMP", 1000, ramp);
    o = (voice_opts){.gain = 1, .pitch = 1, .loop = true, .loop_from = 200, .loop_to = 300};
    int h = audio_voice_play("RAMP", &o);
    mix(0, 256);
    mix(256, 256);
    CHECK(out[0] == 0 && out[299] == 2990 && out[300] == 2000 && out[399] == 2990 && out[400] == 2000);
    CHECK(out[500] == 2000 + 0 && audio_sfx_playing(h));
    /* nonsense bounds play the whole clip */
    audio_reset();
    make("RAMP", 1000, ramp);
    o.loop_from = 500, o.loop_to = 400;
    audio_voice_play("RAMP", &o);
    mix(0, 256);
    CHECK(out[255] == 2550);

    /* an envelope: attack 100, decay 100 to 0.5, sustain, release 100 */
    audio_reset();
    make("LEVEL", 1000, level);
    o = (voice_opts){.gain = 1, .pitch = 1, .loop = true, .adsr = true, .a = 100, .d = 100, .s = 0.5f, .r = 100, .first_variant = true};
    h = audio_voice_play("LEVEL", &o);
    mix(0, 256);
    CHECK(out[0] == 0);
    CHECK(abs(out[50] - 5000) < 120);                 /* half way up the attack */
    CHECK(abs(out[100] - 10000) < 120);               /* the top */
    CHECK(abs(out[150] - 7500) < 120);                /* half way down the decay */
    CHECK(abs(out[200] - 5000) < 120 && abs(out[255] - 5000) < 120); /* sustain */
    audio_voice_release(h);
    mix(256, 256);
    CHECK(abs(out[256] - 5000) < 120);                /* the release starts from the level it was at */
    CHECK(abs(out[306] - 2500) < 150);                /* half way down */
    CHECK(out[356] == 0 && peak(356, 512) == 0);      /* done: silent ... */
    CHECK(!audio_sfx_playing(h));                     /* ... and the voice is free */
    /* releasing a sound with no envelope stops it */
    audio_reset();
    make("LEVEL", 1000, level);
    o = (voice_opts){.gain = 1, .pitch = 1, .loop = true};
    h = audio_voice_play("LEVEL", &o);
    audio_voice_release(h);
    CHECK(!audio_sfx_playing(h));
    /* the envelope is the same however the blocks fall: one block of 256 or 256 of 1 */
    audio_reset();
    make("LEVEL", 1000, level);
    o = (voice_opts){.gain = 1, .pitch = 1, .loop = true, .adsr = true, .a = 30, .d = 40, .s = 0.25f, .r = 50, .first_variant = true};
    audio_voice_play("LEVEL", &o);
    mix(0, 256);
    static int16_t ref[256];
    memcpy(ref, out, sizeof ref);
    audio_reset();
    make("LEVEL", 1000, level);
    audio_voice_play("LEVEL", &o);
    for (int i = 0; i < 256; i++) mix(i, 1);
    CHECK(!memcmp(ref, out, sizeof ref));

    /* a gain change eases over the block: no step in the output */
    audio_reset();
    make("LEVEL", 1000, level);
    o = (voice_opts){.gain = 1, .pitch = 1, .loop = true};
    h = audio_voice_play("LEVEL", &o);
    mix(0, 256);
    CHECK(out[255] == 10000);                         /* steady: exactly pcm * gain, as before */
    audio_sfx_adjust(h, 0.5f, -1);
    mix(256, 256);
    int maxstep = 0;
    for (int i = 257; i < 512; i++) maxstep = abs(out[i] - out[i - 1]) > maxstep ? abs(out[i] - out[i - 1]) : maxstep;
    CHECK(out[256] > 9900 && abs(out[511] - 5000) < 40 && maxstep < 40); /* from 10000 to 5000 in a straight slide */
    mix(512, 256);
    CHECK(out[512] == 5000 && out[767] == 5000);      /* and steady again */

    /* sends reach the effects: a reverb tail after the sound has ended; with no send the silence is exact */
    audio_reset();
    studio_fx_params fx;
    studio_fx_get(&fx);
    fx.reverb = STUDIO_PLATE, fx.size = 0.5f, fx.damp = 0.3f;
    studio_fx_set(&fx);
    make("CLICK", 64, click);
    o = (voice_opts){.gain = 1, .pitch = 1, .send_r = 1};
    audio_voice_play("CLICK", &o);
    for (int off = 0; off < 2048; off += 256) mix(off, 256);
    CHECK(peak(1024, 2048) > 0);                      /* the tail */
    audio_reset();
    studio_fx_reset();
    make("CLICK", 64, click);
    o.send_r = 0;
    audio_voice_play("CLICK", &o);
    for (int off = 0; off < 2048; off += 256) mix(off, 256);
    CHECK(peak(1024, 2048) == 0);                     /* nothing sent: nothing after the end */

    printf("audio_voice: %d checks, %d failed\n", checks, failures);
    return failures != 0;
}
