/* The studio's effects, fed by its tracks' sends, and its Lo-fi GBA master.
 *   echo:   a delay in steps of the tempo (3 is a dotted 8th), its repeats darkened by a lowpass as a tape echo's;
 *           a tempo change glides its length there, as a tape's speed would, instead of clicking;
 *   reverb: a plate (Freeverb, Jezar's lengths halved for 22 kHz: eight combs, four allpasses, mono), or GBA: the
 *           two echoes Nintendo's sound driver (m4a) fed back into its mix buffer, ~100 and ~117 ms apart, the
 *           "tunnel" of so many GBA soundtracks;
 *   lofi:   everything held at 13,379 Hz and cut to 8 bits with no dither, as that driver mixed it.
 * Audio thread, the lock held; studio_fx_set from the game. On the console this file's code runs from IRAM and its
 * buffers live in internal RAM (linker.lf): the plate reads and writes twelve of them every sample, and from PSRAM
 * that took a fifth of a core and made the sound stutter. So they hold 16-bit samples, ~18 KB in all; the echo's
 * 1.5 s goes to PSRAM (it reads and writes at two places that move along: the cache serves them). Eight seconds with
 * nothing sent to them and they stop costing anything. */
#include <math.h>
#include <string.h>

#include "bp.h"
#include "studio_synth.h"

#define DELAY_MAX (AUDIO_HZ * 3 / 2) /* 1.5 s: four steps at 40 BPM */
#define GBA_TAP1 2216                /* 6 and 7 frames of 224 samples at 13,379 Hz, in samples at AUDIO_HZ */
#define GBA_TAP2 2585

static studio_fx_params P = {3, 0.35f, 0.5f, STUDIO_PLATE, 0.5f, 0.5f, false};

static float *dbuf; /* DELAY_MAX samples, in PSRAM */
static int dpos;
static float dlen, dlp; /* the echo's length now (gliding to its target) and its tone's state */
static const int CL[8] = {558, 594, 638, 678, 711, 745, 778, 808};
static const int AL[4] = {278, 220, 170, 112};
#define VS 4.0f /* a stored sample is the value / VS: room for a reverb's build-up in 16 bits */
static int16_t cbuf[558 + 594 + 638 + 678 + 711 + 745 + 778 + 808], abuf[278 + 220 + 170 + 112];
static int cpos[8], apos[4];
static float cfilt[8];
static int16_t gbuf[GBA_TAP2 + 1];
static long idle;                      /* samples with nothing sent: past IDLE_MAX the effects rest */
#define IDLE_MAX (AUDIO_HZ * 8)
static int gpos;
static float lph, lheld;

static float clampf(float v, float lo, float hi) { return v > lo ? (v < hi ? v : hi) : lo; }

static int16_t pack(float v) { return (int16_t)clampf(v / VS + (v >= 0 ? 0.5f : -0.5f), -32767, 32767); }

static void clear(void) {
    if (dbuf) memset(dbuf, 0, sizeof(float) * DELAY_MAX);
    memset(cbuf, 0, sizeof cbuf), memset(abuf, 0, sizeof abuf);
    memset(gbuf, 0, sizeof gbuf), memset(cpos, 0, sizeof cpos), memset(apos, 0, sizeof apos);
    memset(cfilt, 0, sizeof cfilt);
    dpos = gpos = 0, dlen = dlp = 0;
}

void studio_fx_reset(void) { /* the game's thread, at a game's start: the echo's buffer is made here, once */
    if (!dbuf) dbuf = hal_realloc_slow(NULL, sizeof(float) * DELAY_MAX);
    clear();
    lph = lheld = 0, idle = IDLE_MAX;
    P = (studio_fx_params){3, 0.35f, 0.5f, STUDIO_PLATE, 0.5f, 0.5f, false};
}

void studio_fx_set(const studio_fx_params *f) {
    hal_audio_lock();
    bool snap = f->delay != P.delay;
    P.delay = clampf(f->delay, 0.25f, 16);
    P.feedback = clampf(f->feedback, 0, 0.95f);
    P.tone = clampf(f->tone, 0, 1);
    P.reverb = f->reverb == STUDIO_GBA ? STUDIO_GBA : STUDIO_PLATE;
    P.size = clampf(f->size, 0, 1), P.damp = clampf(f->damp, 0, 1);
    P.lofi = f->lofi;
    if (snap) dlen = 0; /* a new time is taken at once; only a tempo change glides */
    hal_audio_unlock();
}

void studio_fx_get(studio_fx_params *f) {
    hal_audio_lock();
    *f = P;
    hal_audio_unlock();
}

static inline float echo(float in, float target) { /* target: its length, worked out once a block */
    if (!dbuf) return 0;
    dlen = dlen <= 0 ? target : dlen + (target - dlen) * 0.0005f;
    float rp = (float)dpos - dlen;
    if (rp < 0) rp += DELAY_MAX;
    int i0 = (int)rp, i1 = i0 + 1 < DELAY_MAX ? i0 + 1 : 0;
    float y = dbuf[i0] + (dbuf[i1] - dbuf[i0]) * (rp - (float)i0);
    dlp += (y - dlp) * (0.08f + 0.92f * P.tone); /* the tone: 1 lets everything through */
    dbuf[dpos] = in + dlp * P.feedback;
    if (++dpos == DELAY_MAX) dpos = 0;
    return dlp;
}

static inline float plate(float in) {
    float room = 0.7f + P.size * 0.28f, damp = P.damp * 0.4f, out = 0, x = in * 0.015f;
    int16_t *c = cbuf;
    for (int k = 0; k < 8; k++) {
        float y = c[cpos[k]] * VS;
        cfilt[k] = y * (1 - damp) + cfilt[k] * damp;
        c[cpos[k]] = pack(x + cfilt[k] * room);
        if (++cpos[k] == CL[k]) cpos[k] = 0;
        out += y;
        c += CL[k];
    }
    int16_t *a = abuf;
    for (int k = 0; k < 4; k++) {
        float b = a[apos[k]] * VS;
        a[apos[k]] = pack(out + b * 0.5f);
        out = b - out;
        if (++apos[k] == AL[k]) apos[k] = 0;
        a += AL[k];
    }
    return out * 3;
}

static inline float gba(float in) { /* two taps fed back: their gains add up to under 1, so it always dies away */
    float fb = 0.2f + P.size * 0.28f;
    int p1 = gpos - GBA_TAP1, p2 = gpos - GBA_TAP2;
    if (p1 < 0) p1 += GBA_TAP2 + 1;
    if (p2 < 0) p2 += GBA_TAP2 + 1;
    float w = (gbuf[p1] + gbuf[p2]) * VS * fb;
    gbuf[gpos] = pack(in + w);
    if (++gpos == GBA_TAP2 + 1) gpos = 0;
    return w;
}

void studio_fx(float *acc, const float *sd, const float *sr, int m) {
    bool sent = false;
    for (int i = 0; i < m && !sent; i++) sent = sd[i] != 0 || sr[i] != 0;
    if (sent) {
        if (idle >= IDLE_MAX) clear(); /* waking: no stale tail from before */
        idle = 0;
    } else if (idle < IDLE_MAX) {
        idle += m;
    }
    if (idle < IDLE_MAX) { /* one effect over the block, then the next: each walks its own buffers in order */
        /* once a block, in float: the console has no double-precision hardware, and a double divide a sample
         * cost more than all the effects together */
        float target = clampf((float)(P.delay * studio_step_samples()), 1, DELAY_MAX - 2);
        for (int i = 0; i < m; i++) acc[i] += echo(sd[i], target);
        if (P.reverb == STUDIO_GBA)
            for (int i = 0; i < m; i++) acc[i] += gba(sr[i]);
        else
            for (int i = 0; i < m; i++) acc[i] += plate(sr[i]);
    }
    if (P.lofi) /* sample and hold at the GBA's rate, 256 levels, no dither: its hiss and its sizzle */
        for (int i = 0; i < m; i++) {
            lph += 13379.0f / AUDIO_HZ;
            if (lph >= 1) lph -= 1, lheld = floorf(clampf(acc[i], -32768, 32767) / 256 + 0.5f) * 256;
            acc[i] = lheld;
        }
}
