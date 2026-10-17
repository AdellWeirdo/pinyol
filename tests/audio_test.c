/* The mixer's newer voices (src/audio.c): placing a sound between the ears. */
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

#define N 1024
static int16_t mono[N], two[2 * N];

static int peak_ear(const int16_t *s, int ear, int n) { /* the loudest sample of one ear (0 left, 1 right) */
    int m = 0;
    for (int i = 0; i < n; i++) m = abs(s[2 * i + ear]) > m ? abs(s[2 * i + ear]) : m;
    return m;
}

static void beep(void) { /* a steady square wave, "BEEP", looped by every test */
    int16_t *clip = malloc(sizeof(int16_t) * 1000);
    for (int i = 0; i < 1000; i++) clip[i] = (int16_t)(i % 100 < 50 ? 8000 : -8000);
    audio_reset();
    audio_sfx_set("BEEP", clip, 1000);
}

int main(void) {
    /* no pan: both ears the same, and the same as the mono mix, sample for sample */
    beep();
    audio_sfx_play("BEEP", 1, 1, true);
    audio_mix(mono, N);
    beep();
    audio_sfx_play("BEEP", 1, 1, true);
    audio_mix_stereo(two, N);
    int same = 1;
    for (int i = 0; i < N; i++) same &= two[2 * i] == mono[i] && two[2 * i + 1] == mono[i];
    CHECK(same);
    const int centre = peak_ear(two, 0, N);
    CHECK(centre > 7000);

    /* hard left: the right ear hears nothing, the left what the centre had; hard right the other way */
    beep();
    audio_sfx_play_pan("BEEP", 1, 1, true, -1);
    audio_mix_stereo(two, N);
    CHECK(peak_ear(two, 1, N) == 0 && peak_ear(two, 0, N) == centre);
    beep();
    audio_sfx_play_pan("BEEP", 1, 1, true, 1);
    audio_mix_stereo(two, N);
    CHECK(peak_ear(two, 0, N) == 0 && peak_ear(two, 1, N) == centre);

    /* half right: the left ear at half of the right's */
    beep();
    audio_sfx_play_pan("BEEP", 1, 1, true, 0.5f);
    audio_mix_stereo(two, N);
    int l = peak_ear(two, 0, N), r = peak_ear(two, 1, N);
    CHECK(r > 7000 && abs(l * 2 - r) <= 2);

    /* moved while it plays: from the centre to hard left, the right ear goes quiet; out of range is held to it */
    beep();
    int h = audio_sfx_play("BEEP", 1, 1, true);
    audio_mix_stereo(two, N);
    CHECK(peak_ear(two, 1, N) > 7000);
    audio_sfx_pan(h, -5);
    audio_mix_stereo(two, N);
    CHECK(peak_ear(two, 1, N) == 0 && peak_ear(two, 0, N) > 7000);
    audio_sfx_pan(h, NAN);
    audio_mix_stereo(two, N);
    CHECK(peak_ear(two, 1, N) > 7000 && peak_ear(two, 0, N) == peak_ear(two, 1, N));

    /* a mono platform hears a panned sound at the average of its ears */
    beep();
    audio_sfx_play_pan("BEEP", 1, 1, true, 1);
    audio_mix(mono, N);
    beep();
    audio_sfx_play_pan("BEEP", 1, 1, true, 1);
    audio_mix_stereo(two, N);
    int worst = 0;
    for (int i = 0; i < N; i++) worst = abs((two[2 * i] + two[2 * i + 1]) / 2 - mono[i]) > worst ? abs((two[2 * i] + two[2 * i + 1]) / 2 - mono[i]) : worst;
    CHECK(worst <= 1);

    audio_reset();
    printf("audio: %d checks, %d failed\n", checks, failures);
    return failures != 0;
}
