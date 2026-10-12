/* The synthesised voices (src/psg.c): pitch, envelopes, lengths, slides, noise and note names. */
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

static float buf[AUDIO_HZ * 2];

static void run(int n) { /* n samples of the voices alone */
    memset(buf, 0, sizeof buf);
    for (int off = 0; off < n; off += 256) psg_mix(buf + off, n - off < 256 ? n - off : 256);
}

static int crossings(int from, int to) {
    int c = 0;
    for (int i = from + 1; i < to; i++) c += (buf[i - 1] < 0) != (buf[i] < 0);
    return c;
}

static float peak(int from, int to) {
    float m = 0;
    for (int i = from; i < to; i++) m = fabsf(buf[i]) > m ? fabsf(buf[i]) : m;
    return m;
}

int main(void) {
    psg_reset();
    psg_play(0, &(psg_note){.wave = PSG_SQUARE, .freq = 441, .vol = 1, .duty = 0.5f, .sustain = 1, .release = 0.01f});
    run(AUDIO_HZ);
    CHECK(abs(crossings(0, AUDIO_HZ) - 882) <= 2); /* 441 periods in a second, two crossings each */
    CHECK(peak(0, AUDIO_HZ) > 7000 && peak(0, AUDIO_HZ) <= 8001);
    psg_release(0);
    run(AUDIO_HZ / 2);
    CHECK(peak(AUDIO_HZ / 4, AUDIO_HZ / 2) == 0); /* let go: faded out and freed */

    psg_play(1, &(psg_note){.wave = PSG_TRIANGLE, .freq = 220, .vol = 1, .decay = 0.05f}); /* a pluck */
    run(AUDIO_HZ);
    CHECK(peak(0, AUDIO_HZ / 20) > 3000 && peak(AUDIO_HZ / 2, AUDIO_HZ) == 0);

    psg_play(2, &(psg_note){.wave = PSG_SINE, .freq = 300, .vol = 1, .sustain = 1, .len = 0.1f, .release = 0.01f});
    run(AUDIO_HZ / 2);
    CHECK(peak(0, AUDIO_HZ / 10) > 7000 && peak(AUDIO_HZ / 4, AUDIO_HZ / 2) == 0); /* its length, then gone */

    psg_play(3, &(psg_note){.wave = PSG_SAW, .freq = 1000, .vol = 1, .sustain = 1, .slide = -2000});
    run(AUDIO_HZ);
    CHECK(crossings(0, AUDIO_HZ / 10) > crossings(AUDIO_HZ * 4 / 10, AUDIO_HZ / 2)); /* lower as it slides */
    CHECK(peak(AUDIO_HZ * 6 / 10, AUDIO_HZ) == 0); /* slid below hearing at 0.5 s: stopped */

    psg_play(0, &(psg_note){.wave = PSG_NOISE, .freq = 4000, .vol = 1, .sustain = 1});
    run(AUDIO_HZ / 10);
    CHECK(crossings(0, AUDIO_HZ / 10) > 50 && peak(0, AUDIO_HZ / 10) > 7000);
    psg_reset();
    run(256);
    CHECK(peak(0, 256) == 0);

    CHECK(fabsf(psg_note_hz("A4") - 440) < 0.01f && fabsf(psg_note_hz("C4") - 261.63f) < 0.01f);
    CHECK(fabsf(psg_note_hz("C#4") - 277.18f) < 0.01f && fabsf(psg_note_hz("Eb5") - 622.25f) < 0.01f);
    CHECK(psg_note_hz("H2") == 0 && psg_note_hz("A10") == 0 && psg_note_hz("") == 0 && psg_note_hz("C") == 0);
    printf("psg: %d checks, %d failed\n", checks, failures);
    return failures != 0;
}
