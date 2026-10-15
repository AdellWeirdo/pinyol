/* The studio (src/studio.c): each step lands on its sample at any tempo, the swing makes the odd steps late, a tempo
 * change carries on from the step it is at, a choke group cuts the other sound, a made sound that takes a track's
 * place is played instead, and studio_pos follows the mix. A one-sample click marks where each step starts. */
#include <math.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>

#include "bp.h"
#include "studio_synth.h"

static int failures, checks;
#define CHECK(c)                                                                                \
    do {                                                                                        \
        checks++;                                                                               \
        if (!(c)) failures++, fprintf(stderr, "%s:%d: CHECK(%s)\n", __FILE__, __LINE__, #c);    \
    } while (0)

#define N (AUDIO_HZ * 3)
static int16_t out[N];

static void mix(int n) {
    for (int off = 0; off < n; off += 256) {
        hal_audio_lock();
        audio_mix(out + off, n - off < 256 ? n - off : 256);
        hal_audio_unlock();
    }
}

static void make(const char *id, int16_t level, int n) { /* a made sound: level, then silence */
    int16_t *pcm = calloc((size_t)n, sizeof *pcm);
    pcm[0] = level;
    audio_sfx_set(id, pcm, n);
}

static double rms(int a, int b) {
    double e = 0;
    for (int i = a; i < b; i++) e += (double)out[i] * out[i];
    return sqrt(e / (b - a));
}

static double hf(int a, int b) { /* the energy of the first difference: how much treble there is */
    double e = 0;
    for (int i = a + 1; i < b; i++) e += (double)(out[i] - out[i - 1]) * (out[i] - out[i - 1]);
    return sqrt(e / (b - a));
}

static double pitch(int a, int b) { /* Hz, from the first rising zero crossing to the last */
    int c = 0, first = -1, last = -1;
    for (int i = a + 1; i < b; i++)
        if (out[i - 1] < 0 && out[i] >= 0) c++, last = i, first = first < 0 ? i : first;
    return c > 1 ? (c - 1) * (double)AUDIO_HZ / (last - first) : 0;
}

static void synth_run(sv_patch p, const uint8_t *notes, const uint8_t *flags, int n) {
    audio_reset();
    studio_synth(0, &p);
    studio_notes(0, notes, flags, n);
    studio_length(n);
    studio_tempo(120, 50);
    memset(out, 0, sizeof out);
    studio_play(0);
    mix(N);
}

static int clicks(int *at, int max) { /* where the output jumps from silence */
    int k = 0;
    for (int i = 0; i < N && k < max; i++)
        if (out[i] > 1000 && (i == 0 || out[i - 1] < 1000)) at[k++] = i;
    return k;
}

int main(void) {
    audio_reset();
    make("CLICK", 20000, 8);
    float all[16];
    for (int s = 0; s < 16; s++) all[s] = 1;

    /* 120 BPM: a 16th is 2756.25 samples; step k starts at floor(k * 2756.25) */
    CHECK(studio_track(0, "CLICK", 1, 1, 0));
    CHECK(!studio_track(1, "NO_SUCH_SOUND", 1, 1, 0));
    studio_steps(0, all, 16);
    studio_tempo(120, 50);
    studio_play(0);
    mix(N);
    int at[64], n = clicks(at, 64);
    CHECK(n == 24);
    for (int k = 0; k < n; k++) CHECK(at[k] == (int)(k * 2756.25));

    /* swing 66 %: the odd steps 0.32 of a step late */
    audio_reset();
    make("CLICK", 20000, 8);
    studio_track(0, "CLICK", 1, 1, 0);
    studio_steps(0, all, 16);
    studio_tempo(120, 66);
    studio_play(0);
    mix(N);
    n = clicks(at, 64);
    CHECK(n == 24);
    for (int k = 0; k < n; k++) CHECK(at[k] == (int)(k * 2756.25 + (k % 2 ? 0.32 * 2756.25 : 0)));

    /* 100 BPM (3307.5 samples, not a whole number of ticks), then 150 from the step it has reached */
    audio_reset();
    make("CLICK", 20000, 8);
    studio_track(0, "CLICK", 1, 1, 0);
    studio_steps(0, all, 16);
    studio_tempo(100, 50);
    studio_play(0);
    mix(5 * 3307 + 100);
    studio_tempo(150, 50);
    memset(out, 0, sizeof out);
    hal_audio_lock();
    for (int off = 0; off < N; off += 256) audio_mix(out + off, 256 < N - off ? 256 : N - off);
    hal_audio_unlock();
    n = clicks(at, 64);
    CHECK(n > 10);
    for (int k = 1; k + 1 < n; k++) CHECK(abs(at[k + 1] - at[k] - 2205) <= 1); /* 150 BPM: 2205 samples a step */

    /* velocities and the track's gain scale the hit; a silent step plays nothing */
    audio_reset();
    make("CLICK", 20000, 8);
    studio_track(0, "CLICK", 0.5f, 1, 0);
    float half[4] = {1, 0, 0.5f, 0};
    studio_steps(0, half, 4);
    studio_length(4);
    studio_tempo(120, 50);
    studio_play(0);
    mix(4 * 2757);
    CHECK(abs(out[0] - 10000) <= 2);
    CHECK(abs(out[(int)(2 * 2756.25)] - 5000) <= 2);
    CHECK(out[2756] == 0);

    /* a choke group: the closed hat on step 1 cuts the open one still ringing from step 0 */
    audio_reset();
    int16_t *ring = malloc(sizeof(int16_t) * AUDIO_HZ);
    for (int i = 0; i < AUDIO_HZ; i++) ring[i] = 3000;
    audio_sfx_set("OPEN", ring, AUDIO_HZ);
    make("CLOSED", 20000, 8);
    studio_track(0, "OPEN", 1, 1, 1);
    studio_track(1, "CLOSED", 1, 1, 1);
    float first[2] = {1, 0}, second[2] = {0, 1};
    studio_steps(0, first, 2);
    studio_steps(1, second, 2);
    studio_length(2);
    studio_tempo(120, 50);
    studio_play(0);
    mix(2756 + 512);
    CHECK(out[1000] == 3000);                 /* ringing */
    CHECK(out[2756 + 300] == 0);              /* cut by the closed hat (and it, one sample, is over) */

    /* a made sound taking the clip's place is what the track plays from then on */
    audio_reset();
    make("CLICK", 20000, 8);
    studio_track(0, "CLICK", 1, 1, 0);
    studio_steps(0, all, 16);
    studio_tempo(120, 50);
    studio_play(0);
    mix(1000);
    make("CLICK", 7000, 8);
    memset(out, 0, sizeof out);
    mix(N);
    int loud = 0, old = 0;
    for (int i = 0; i < N; i++) loud += out[i] == 7000, old += out[i] == 20000;
    CHECK(loud > 20);
    CHECK(old == 0);

    /* where the player is: the step heard, and how far into it (headless: the mix itself is the clock) */
    audio_reset();
    make("CLICK", 20000, 8);
    studio_track(0, "CLICK", 1, 1, 0);
    studio_steps(0, all, 16);
    studio_tempo(120, 50);
    int step;
    float frac;
    CHECK(!studio_pos(&step, &frac));         /* stopped */
    studio_play(3);
    mix(2756 * 2 + 512);
    CHECK(studio_pos(&step, &frac));
    CHECK(step == 5);
    CHECK(frac >= 0 && frac < 1);
    studio_stop();
    CHECK(!studio_pos(&step, &frac));

    /* the synth voice: A2 held (sliding into itself) sounds at 110 Hz */
    sv_patch p;
    sv_defaults(&p);
    p.cutoff = 0.5f, p.res = 0.2f, p.env = 0, p.drive = 0;
    uint8_t a2[16], none[16] = {0}, slides[16];
    for (int k = 0; k < 16; k++) a2[k] = 45, slides[k] = STUDIO_SLIDE;
    synth_run(p, a2, slides, 16);
    CHECK(fabs(pitch(AUDIO_HZ / 4, AUDIO_HZ) - 110) < 2);

    /* a note on step 2 starts on its sample, and is let go a little over half a step later */
    uint8_t one[4] = {0, 45, 0, 0};
    synth_run(p, one, none, 4);
    int onset = 0;
    while (onset < N && abs(out[onset]) < 30) onset++;
    CHECK(abs(onset - 2756) <= 2);
    CHECK(rms(2756 + 400, 2756 + 1400) > 500);
    CHECK(rms(2756 * 2 - 200, 2756 * 2) < rms(2756 + 400, 2756 + 1400) / 20);

    /* the filter: closed, much less treble than open */
    sv_patch dark = p, bright = p;
    dark.cutoff = 0.1f, bright.cutoff = 0.9f;
    synth_run(dark, a2, slides, 16);
    double hf_dark = hf(AUDIO_HZ / 4, AUDIO_HZ) / rms(AUDIO_HZ / 4, AUDIO_HZ);
    synth_run(bright, a2, slides, 16);
    double hf_bright = hf(AUDIO_HZ / 4, AUDIO_HZ) / rms(AUDIO_HZ / 4, AUDIO_HZ);
    CHECK(hf_dark * 3 < hf_bright);

    /* an accent plays louder */
    uint8_t acc[4] = {STUDIO_ACCENT, 0, 0, 0}, plain[4] = {0}, note0[4] = {45, 0, 0, 0};
    sv_patch ap = p;
    ap.accent = 1;
    synth_run(ap, note0, plain, 4);
    double quiet = rms(200, 1400);
    synth_run(ap, note0, acc, 4);
    CHECK(rms(200, 1400) > quiet * 1.2);

    /* a slide: A2 into A3 with no gap, and it gets there */
    uint8_t up[4] = {45, 57, 0, 0}, sl[4] = {STUDIO_SLIDE, 0, 0, 0};
    synth_run(p, up, sl, 4);
    CHECK(rms(2756 - 100, 2756 + 100) > rms(400, 2400) * 0.5); /* no release between them */
    CHECK(fabs(pitch(2756 + 900, 2756 + 1480) - 220) < 8);

    /* the echo: a click sent to it comes back two steps later (5512.5 samples: shared by two), then at half */
    float hit0[16] = {1};
    audio_reset();
    make("CLICK", 20000, 8);
    studio_track(0, "CLICK", 1, 1, 0);
    studio_sends(0, 1, 0);
    studio_steps(0, hit0, 16);
    studio_tempo(120, 50);
    studio_fx_params f;
    studio_fx_get(&f);
    f.delay = 2, f.feedback = 0.5f, f.tone = 1;
    studio_fx_set(&f);
    memset(out, 0, sizeof out);
    studio_play(0);
    mix(6 * 2757);
    int before = 0;
    for (int i = 100; i < 5400; i++) before = abs(out[i]) > before ? abs(out[i]) : before;
    CHECK(before < 10);
    CHECK(abs(out[5512] - 10000) <= 2 && abs(out[5513] - 10000) <= 2);
    int again = 0;
    for (int i = 11020; i < 11030; i++) again += abs(out[i]);
    CHECK(again > 8000 && again < 12000);

    /* the plate: a tail after the click, dying away; at its largest it still does not run away */
    audio_reset();
    make("CLICK", 20000, 8);
    studio_track(0, "CLICK", 1, 1, 0);
    studio_sends(0, 0, 1);
    studio_steps(0, hit0, 16);
    studio_fx_get(&f);
    f.reverb = STUDIO_PLATE, f.size = 0.6f, f.damp = 0.3f;
    studio_fx_set(&f);
    memset(out, 0, sizeof out);
    studio_play(0);
    mix(N);
    double early = rms(2000, 6000), late = rms(30000, 34000);
    CHECK(early > 50);
    CHECK(late < early / 3);
    audio_reset();
    make("CLICK", 20000, 8);
    studio_track(0, "CLICK", 1, 1, 0);
    studio_sends(0, 1, 1);
    studio_steps(0, all, 16);
    studio_fx_get(&f);
    f.size = 1, f.damp = 0, f.feedback = 0.95f;
    studio_fx_set(&f);
    studio_play(0);
    for (int k = 0; k < 5; k++) mix(N);
    CHECK(rms(N - AUDIO_HZ, N) < 30000);

    /* GBA: Nintendo's two echoes, 2216 and 2585 samples (100 and 117 ms) after the click */
    audio_reset();
    make("CLICK", 20000, 8);
    studio_track(0, "CLICK", 1, 1, 0);
    studio_sends(0, 0, 1);
    studio_steps(0, hit0, 16);
    studio_fx_get(&f);
    f.reverb = STUDIO_GBA, f.size = 0.5f;
    studio_fx_set(&f);
    memset(out, 0, sizeof out);
    studio_play(0);
    mix(4000);
    CHECK(abs(out[2216] - 6800) <= 2 && abs(out[2585] - 6800) <= 2);
    CHECK(out[2215] == 0 && out[2400] == 0);

    /* Lo-fi GBA: 256 levels, each held about 1.65 samples (13,379 Hz) */
    audio_reset();
    make("CLICK", 20000, 400);
    int16_t *ramp = malloc(sizeof(int16_t) * 4000);
    for (int i = 0; i < 4000; i++) ramp[i] = (int16_t)((i * 7919) % 31 * 600 - 9000); /* new every sample */
    audio_sfx_set("RAMP", ramp, 4000);
    studio_track(0, "RAMP", 1, 1, 0);
    studio_steps(0, hit0, 16);
    studio_fx_get(&f);
    f.lofi = true;
    studio_fx_set(&f);
    memset(out, 0, sizeof out);
    studio_play(0);
    mix(4000);
    int odd = 0, changes = 0;
    for (int i = 1; i < 4000; i++) odd += out[i] % 256 != 0, changes += out[i] != out[i - 1];
    CHECK(odd == 0);
    CHECK(changes > 2200 && changes <= 2430); /* 4000 * 13379 / 22050 = 2427 holds, a few land on the same level */

    printf("studio: %d checks, %d failed\n", checks, failures);
    return failures != 0;
}
