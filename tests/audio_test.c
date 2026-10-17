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

static int16_t big[AUDIO_HZ];

static void clip_of(const char *id, int n, int a, int b) { /* a clip of n samples, the first half a, the second b */
    int16_t *c = malloc(sizeof(int16_t) * (size_t)n);
    for (int i = 0; i < n; i++) c[i] = (int16_t)(i < n / 2 ? a : b);
    audio_reset();
    audio_sfx_set(id, c, n);
}

static int all_sign(const int16_t *p, int n, int sign) { /* every sample of p of that sign (1 or -1) */
    for (int i = 0; i < n; i++)
        if (p[i] * sign <= 0) return 0;
    return 1;
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

    /* an envelope: a steady clip of 8000 climbs over the attack, falls to the sustain, and lets go on a stop */
    clip_of("DC", AUDIO_HZ, 8000, 8000);
    sfx_opts o = {.gain = 1, .pitch = 1, .loop = true, .env = true, .attack = 0.05f, .decay = 0.02f, .sustain = 0.5f, .release = 0.05f};
    int h2 = audio_sfx_play_opts("DC", &o);
    audio_mix(big, 4000);
    CHECK(big[0] < 200 && abs(big[550] - 4000) < 600 && big[1100] > 7800); /* up over 1102 samples */
    CHECK(abs(big[3500] - 4000) < 150);                                     /* then down to half, and held */
    CHECK(audio_sfx_playing(h2));
    audio_sfx_stop(h2); /* let go: not at once, then to nothing */
    CHECK(audio_sfx_playing(h2));
    audio_mix(big, 100);
    CHECK(big[0] > 2500 && big[0] < 4100 && big[99] < big[0]); /* still sounding, falling */
    audio_mix(big, 2000);
    CHECK(big[1099] < 100);                /* about -60 dB after the release time */
    audio_mix(big, 2000);
    CHECK(!audio_sfx_playing(h2));

    /* no attack and no decay: full from the first sample, and a stop with no release is a stop */
    clip_of("DC", AUDIO_HZ, 8000, 8000);
    o = (sfx_opts){.gain = 1, .pitch = 1, .loop = true, .env = true, .sustain = 1};
    h2 = audio_sfx_play_opts("DC", &o);
    audio_mix(big, 100);
    CHECK(abs(big[0] - 8000) < 5 && abs(big[99] - 8000) < 5);
    audio_sfx_stop(h2);
    CHECK(!audio_sfx_playing(h2));

    /* loop points: the first half is positive, the second negative; a loop of the second half stays there */
    clip_of("HALVES", 1000, 8000, -8000);
    o = (sfx_opts){.gain = 1, .pitch = 1, .loop = true, .loop_start = 500, .loop_end = 1000};
    audio_sfx_play_opts("HALVES", &o);
    audio_mix(big, 3000);
    CHECK(big[100] > 0 && all_sign(big + 500, 2500, -1)); /* the head once, then only the loop */
    clip_of("HALVES", 1000, 8000, -8000);
    o.loop_start = 0, o.loop_end = 500;
    audio_sfx_play_opts("HALVES", &o);
    audio_mix(big, 3000);
    CHECK(all_sign(big, 3000, 1));                        /* the first half for ever: the second is never heard */
    clip_of("HALVES", 1000, 8000, -8000);
    o.loop_start = 500, o.loop_end = 1000, o.pitch = 2;   /* the same at pitch 2, between two samples */
    audio_sfx_play_opts("HALVES", &o);
    audio_mix(big, 3000);
    CHECK(all_sign(big + 400, 2600, -1));
    clip_of("HALVES", 1000, 8000, -8000);
    o.loop_start = 700, o.loop_end = 600;                  /* points out of order: the whole clip, as before */
    audio_sfx_play_opts("HALVES", &o);
    audio_mix(big, 3000);
    CHECK(big[100] > 0 && big[1500] > 0 && big[2400] < 0);

    /* the reverb: a click sent through a room comes back as a tail, left and right apart, dying away; with no send, no
     * wet, or no room, nothing comes back, and the dry sound is what it was */
    static int16_t room_a[2 * AUDIO_HZ], room_b[2 * AUDIO_HZ];
    {
        int16_t *c = calloc(100, sizeof(int16_t));
        c[0] = 16000;
        audio_reset();
        audio_sfx_set("CLICK", c, 100);
    }
    sfx_opts rv = {.gain = 1, .pitch = 1, .reverb = 1};
    audio_sfx_play_opts("CLICK", &rv);
    audio_mix_stereo(room_a, 20000);
    int tail = 0;
    for (int i = 100; i < 20000; i++) tail |= room_a[2 * i] | room_a[2 * i + 1];
    CHECK(tail == 0); /* no room: the click and silence */
    int led = reverb_find("room");
    CHECK(led >= 0 && reverb_find("hall") >= 0 && reverb_find("nothing") == -1);
    audio_reverb(led, 1, 0, 0);
    audio_mix_stereo(room_a, 4000); /* the wet level rises over 100 ms; wait it out */
    audio_sfx_play_opts("CLICK", &rv);
    audio_mix_stereo(room_a, 16000);
    int pk = 0, pk_late = 0, differ = 0;
    for (int i = 100; i < 8000; i++) pk = abs(room_a[2 * i]) > pk ? abs(room_a[2 * i]) : pk;
    for (int i = 12000; i < 16000; i++) pk_late = abs(room_a[2 * i]) > pk_late ? abs(room_a[2 * i]) : pk_late;
    for (int i = 100; i < 8000; i++) differ += room_a[2 * i] != room_a[2 * i + 1];
    CHECK(pk > 200);                 /* a tail */
    CHECK(differ > 1000);            /* the two ears hear different tails */
    CHECK(pk_late < pk);             /* dying away */
    /* the same again from the same start gives the same tail: no state is left over from before */
    audio_reverb(-1, 0, 0, 0);
    audio_mix_stereo(room_b, 12000);
    CHECK(!reverb_on());             /* faded out and freed */
    audio_reverb(led, 1, 0, 0);
    audio_mix_stereo(room_b, 4000);
    audio_sfx_play_opts("CLICK", &rv);
    audio_mix_stereo(room_b, 16000);
    CHECK(!memcmp(room_a, room_b, 2 * 16000 * sizeof(int16_t)));
    /* a sound that sends nothing is not in the room, and at wet 0 nothing comes back: both are the dry sound */
    beep();
    audio_sfx_play("BEEP", 1, 1, true);
    audio_mix_stereo(room_a, 4000);
    beep();
    audio_reverb(led, 1, 0, 0);
    audio_mix_stereo(room_b, 4000);
    audio_sfx_play("BEEP", 1, 1, true); /* (sends nothing) */
    audio_mix_stereo(room_b, 4000);
    beep();
    audio_sfx_play("BEEP", 1, 1, true);
    audio_mix_stereo(room_a, 4000);
    int dry_same = 1;
    for (int i = 0; i < 4000; i++) dry_same &= room_a[2 * i] == room_b[2 * i] && room_a[2 * i + 1] == room_b[2 * i + 1];
    CHECK(dry_same);
    audio_reverb(led, 0, 0, 0);
    audio_mix_stereo(room_b, 3000);
    CHECK(peak_ear(room_b, 0, 3000) > 0);
    /* every room runs: no crash, the signal stays in range (soft-limited), a looped tone through it for a second */
    for (int r = 0; reverb_name(r); r++) {
        beep();
        audio_reverb(r, 0.8f, 0, 0);
        sfx_opts loud = {.gain = 1, .pitch = 1, .loop = true, .reverb = 1};
        audio_sfx_play_opts("BEEP", &loud);
        audio_mix_stereo(room_a, AUDIO_HZ);
        CHECK(peak_ear(room_a, 0, AUDIO_HZ) > 0 && peak_ear(room_a, 1, AUDIO_HZ) <= 32767);
    }

    audio_reset();
    printf("audio: %d checks, %d failed\n", checks, failures);
    return failures != 0;
}
