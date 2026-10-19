/* Sounds made from numbers (src/synth.c) and the effect voices' pitch, loop and handles (src/audio.c). */
#include <math.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>

#include "bp.h"

static int failures, checks;
#define CHECK(c)                                                                  \
    do {                                                                          \
        checks++;                                                                 \
        if (!(c)) failures++, fprintf(stderr, "%s:%d: CHECK(%s)\n", __FILE__, __LINE__, #c); \
    } while (0)

#define MAX (4 * AUDIO_HZ + 1) /* SYNTH_MAX_S seconds */
static int16_t a[MAX], b[MAX];
static int16_t out[AUDIO_HZ * 2];

static int peak(const int16_t *p, int n) {
    int m = 0;
    for (int i = 0; i < n; i++) m = abs(p[i]) > m ? abs(p[i]) : m;
    return m;
}

static int16_t *copy(const int16_t *p, int n) {
    int16_t *c = malloc(sizeof(int16_t) * (size_t)n);
    memcpy(c, p, sizeof(int16_t) * (size_t)n);
    return c;
}

int main(void) {
    static const char *kinds[] = {"coin", "laser", "explosion", "powerup", "hit", "jump", "blip", "random"};
    for (int k = 0; k < 8; k++)
        for (uint32_t seed = 1; seed <= 40; seed++) { /* every recipe, many seeds: a sound, in range, the same twice */
            synth_params p, q;
            CHECK(synth_recipe(kinds[k], seed, &p));
            synth_recipe(kinds[k], seed, &q);
            int n = synth_render(&p, a, MAX), m = synth_render(&q, b, MAX);
            CHECK(n > AUDIO_HZ / 50 && n <= MAX && n == m && !memcmp(a, b, sizeof(int16_t) * (size_t)n));
            CHECK(peak(a, n) > 1500 && peak(a, n) <= 30000);
        }
    synth_params p;
    CHECK(!synth_recipe("nothing", 1, &p));

    /* a plain tone: its pitch is right (crossings), its length is attack + sustain + decay */
    synth_defaults(&p);
    p.wave = PSG_SQUARE, p.freq = 441, p.attack = 0, p.sustain = 1, p.decay = 0, p.volume = 0.5f;
    int n = synth_render(&p, a, MAX), cross = 0;
    for (int i = 1; i < n; i++) cross += (a[i - 1] < 0) != (a[i] < 0);
    CHECK(n == AUDIO_HZ && abs(cross - 882) <= 4);

    /* nonsense numbers are made safe: finite, short enough */
    synth_defaults(&p);
    p.freq = NAN, p.slide = INFINITY, p.sustain = 1e9f, p.decay = -5, p.lowpass = NAN, p.volume = 7, p.wave = 99;
    n = synth_render(&p, a, MAX);
    CHECK(n > 0 && n <= MAX && peak(a, n) <= 30000);

    /* a falling sound ends at its floor */
    synth_defaults(&p);
    p.freq = 1000, p.slide = -4000, p.freq_min = 200, p.sustain = 2, p.decay = 0;
    n = synth_render(&p, a, MAX);
    CHECK(abs(n - AUDIO_HZ / 5) <= 50); /* 800 Hz down at 4000 Hz a second: 0.2 s */

    /* the voices: a made clip, looped at pitch 1 keeps sounding past its end; at pitch 2 a one-shot lasts half */
    audio_reset();
    int16_t *clip = malloc(sizeof(int16_t) * 1000);
    for (int i = 0; i < 1000; i++) clip[i] = (int16_t)(i % 100 < 50 ? 10000 : -10000);
    CHECK(audio_sfx_set("BEEP", clip, 1000));
    int h = audio_sfx_play("BEEP", 1, 1, true);
    CHECK(h != 0 && audio_sfx_playing(h));
    audio_mix(out, 3000);
    CHECK(peak(out + 2500, 500) > 5000 && audio_sfx_playing(h));
    audio_sfx_stop(h);
    CHECK(!audio_sfx_playing(h));
    audio_mix(out, 500);
    CHECK(peak(out, 500) == 0);
    h = audio_sfx_play("BEEP", 1, 2, false);
    audio_mix(out, 1000);
    CHECK(peak(out, 480) > 5000 && peak(out + 510, 490) == 0 && !audio_sfx_playing(h));

    /* a handle names one sound: after its voice starts another, the old handle changes nothing */
    int h1 = audio_sfx_play("BEEP", 1, 1, true);
    audio_sfx_stop(h1);
    int h2 = audio_sfx_play("BEEP", 1, 1, true);
    CHECK(h1 != h2 && audio_sfx_playing(h2) && !audio_sfx_playing(h1));
    audio_sfx_adjust(h1, 0, 1);
    audio_mix(out, 200);
    CHECK(peak(out, 200) > 5000);
    audio_sfx_adjust(h2, 0, -1);
    audio_mix(out, 200); /* the gain eases to 0 over this block (a step would click), then it is silent */
    CHECK(peak(out, 50) > 2 * peak(out + 150, 50));
    audio_mix(out, 200);
    CHECK(peak(out, 200) == 0);

    /* making it again replaces it; a voice playing the old one stops first (no dangling sound) */
    int16_t *again = copy(clip, 0 + 1);
    CHECK(audio_sfx_set("BEEP", again, 1));
    CHECK(!audio_sfx_playing(h2));
    CHECK(audio_made_bytes() == 2);
    audio_reset();
    CHECK(audio_made_bytes() == 0);

    printf("synth: %d checks, %d failed\n", checks, failures);
    return failures != 0;
}
