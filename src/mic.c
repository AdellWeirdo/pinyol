/* The microphone, for games (np2d@2): how loud it is, the pitch of a voice or a whistle, a sudden sound (a clap),
 * and recordings that become sounds a game plays. The platform hands over samples (hal_mic_read); all of it is
 * worked out here once a tick, so a game only reads numbers and every platform agrees. Tests feed a tone or noise
 * instead of a real microphone (mic_inject). */
#include <math.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>

#include "bp.h"

#define WIN 1024         /* the last 46 ms: pitch needs two periods of a low voice */
#define DEC 2            /* pitch is looked for at half the rate: a quarter of the work, still up to 1 kHz */
#define LAG_MIN 11       /* 11025 / 11 = 1000 Hz */
#define LAG_MAX 160      /* 11025 / 160 = 69 Hz */
#define CLARITY 0.6f     /* how periodic it must be to have a pitch (1 = a pure tone) */
#define DB_FLOOR -60.0f  /* level 0 */
#define DB_SPAN 54.0f    /* level 1 at -6 dBFS: a shout close to the console */
#define PITCH_LEVEL 0.15f
#define HIT_RISE 12.0f   /* dB above the recent average in one tick: a clap, a knock, a shout */
#define HIT_LEVEL 0.3f
#define HIT_REST 6       /* ticks after a hit before the next can come */
#define REC_MAX_S 10

static struct {
    bool on, real, tried;       /* on: listening; real: through the platform's microphone; tried: asked for one */
    int16_t win[WIN];
    float level, pitch, avg_db;
    bool hit;
    int rest;
    char rec_id[32];
    int16_t *rec;
    int rec_n, rec_max;
} M;

static struct { /* tests: a made-up microphone, which stays from one game to the next */
    bool on;
    float amp, hz, phase;
    uint32_t seed;
} I;

static float level_of(float db) {
    float l = (db - DB_FLOOR) / DB_SPAN;
    return l < 0 ? 0 : l > 1 ? 1 : l;
}

/* McLeod's normalised square difference on the window at half rate: the first strong peak is the period. */
static float find_pitch(void) {
    enum { N = WIN / DEC };
    static float x[N], nsdf[LAG_MAX + 2];
    float e = 0;
    for (int i = 0; i < N; i++) {
        x[i] = (M.win[i * DEC] + M.win[i * DEC + 1]) * (1.0f / 65536);
        e += x[i] * x[i];
    }
    if (e < 1e-6f) return 0;
    float m = 2 * e; /* the sum of x[i]^2 + x[i+lag]^2 over the overlap, shrinking as the lag grows */
    float best = 0;
    for (int lag = 1; lag <= LAG_MAX + 1; lag++) {
        m -= x[N - lag] * x[N - lag] + x[lag - 1] * x[lag - 1];
        if (lag < LAG_MIN - 1) continue;
        float r = 0;
        for (int i = 0; i < N - lag; i++) r += x[i] * x[i + lag];
        nsdf[lag] = m > 1e-9f ? 2 * r / m : 0;
        if (lag >= LAG_MIN && lag <= LAG_MAX && nsdf[lag] > best) best = nsdf[lag];
    }
    if (best < CLARITY) return 0;
    /* peaks count once the curve has dipped below zero (or rises from the start: a high note), else the slope of a
     * dull sound at short lags would pass for a period */
    bool past_dip = nsdf[LAG_MIN] > nsdf[LAG_MIN - 1];
    for (int lag = LAG_MIN; lag <= LAG_MAX; lag++) {
        if (nsdf[lag] < 0) past_dip = true;
        if (past_dip && nsdf[lag] >= 0.9f * best && nsdf[lag] >= nsdf[lag - 1] && nsdf[lag] >= nsdf[lag + 1]) {
            float a = nsdf[lag - 1], b = nsdf[lag], c = nsdf[lag + 1], d = a - 2 * b + c;
            float at = lag + (d != 0 ? 0.5f * (a - c) / d : 0); /* between the samples, on the parabola */
            return (float)AUDIO_HZ / DEC / at;
        }
    }
    return 0;
}

static int inject(int16_t *p, int n) {
    for (int i = 0; i < n; i++) {
        float v;
        if (I.hz > 0) {
            v = sinf(I.phase);
            I.phase += 6.2831853f * I.hz / AUDIO_HZ;
            if (I.phase > 6.2831853f) I.phase -= 6.2831853f;
        } else { /* noise, as loud as a sine of that peak */
            I.seed = I.seed * 1664525u + 1013904223u;
            v = ((int32_t)I.seed >> 8) / 8388608.0f * 1.2247449f;
        }
        float s = v * I.amp;
        p[i] = (int16_t)(s > 32767 ? 32767 : s < -32768 ? -32768 : s);
    }
    return n;
}

static void rec_finish(void) {
    if (!M.rec) return;
    if (M.rec_n == 0) M.rec[M.rec_n++] = 0; /* silence, but a sound: sfx(id) plays it */
    int16_t *fit = hal_realloc_slow(M.rec, sizeof(int16_t) * (size_t)M.rec_n);
    if (!audio_sfx_set(M.rec_id, fit ? fit : M.rec, M.rec_n)) hal_log("mic: no room for the sound \"%s\"", M.rec_id);
    M.rec = NULL;
}

bool mic_open(void) {
    if (!M.on && !M.tried) { /* asked once: a platform without a microphone is not asked again every tick */
        M.tried = true;
        M.real = !I.on && hal_mic_open();
        M.on = I.on || M.real;
        M.avg_db = DB_FLOOR;
    }
    return M.on;
}

void mic_close(void) { /* a game stops listening, or ends: what it was recording is kept */
    rec_finish();
    if (M.real) hal_mic_close();
    memset(&M, 0, sizeof M);
}

void mic_tick(void) {
    M.hit = false;
    if (M.rest) M.rest--;
    if (!M.on) return;
    static int16_t buf[1024];
    double sum = 0;
    int got = 0;
    for (int k = 0; k < 8; k++) { /* what came in since the last tick (a late tick finds more) */
        int n = M.real ? hal_mic_read(buf, 1024) : k ? 0 : inject(buf, AUDIO_HZ / TICK_HZ);
        if (n <= 0) break;
        if (n > 1024) n = 1024;
        for (int i = 0; i < n; i++) sum += (double)buf[i] * buf[i];
        got += n;
        int keep = WIN - n; /* the window slides */
        memmove(M.win, M.win + n, sizeof(int16_t) * (size_t)keep);
        memcpy(M.win + keep, buf, sizeof(int16_t) * (size_t)n);
        if (M.rec) {
            int c = M.rec_max - M.rec_n < n ? M.rec_max - M.rec_n : n;
            memcpy(M.rec + M.rec_n, buf, sizeof(int16_t) * (size_t)c);
            M.rec_n += c;
            if (M.rec_n == M.rec_max) rec_finish();
        }
    }
    if (!got) return; /* nothing new (a platform may hand over blocks bigger than a tick): the last numbers stand */
    float rms = (float)sqrt(sum / got) / 32768.0f;
    float db = rms > 1e-6f ? 20 * log10f(rms) : -120;
    M.level = level_of(db);
    M.pitch = M.level > PITCH_LEVEL ? find_pitch() : 0;
    if (db < DB_FLOOR) db = DB_FLOOR;
    if (!M.rest && M.level >= HIT_LEVEL && db - M.avg_db >= HIT_RISE) M.hit = true, M.rest = HIT_REST, M.avg_db = db;
    else M.avg_db += (db - M.avg_db) * 0.1f; /* ~10 ticks to settle; a hit is the new loudness at once */
}

bool mic_read(float *level, float *pitch, bool *hit, bool *recording) {
    if (!M.on) return false;
    *level = M.level, *pitch = M.pitch, *hit = M.hit, *recording = M.rec != NULL;
    return true;
}

bool mic_record(const char *id, float seconds) {
    if (!M.on) return false;
    rec_finish();
    int n = (int)((seconds > REC_MAX_S ? REC_MAX_S : seconds) * AUDIO_HZ);
    if (n < 1 || !(M.rec = hal_realloc_slow(NULL, sizeof(int16_t) * (size_t)n))) return false;
    snprintf(M.rec_id, sizeof M.rec_id, "%s", id);
    M.rec_n = 0, M.rec_max = n;
    return true;
}

void mic_record_stop(void) { rec_finish(); }

void mic_inject(bool present, float level, float hz) {
    if (!present || !I.on) mic_close(); /* the microphone changes under the game: it opens it again */
    I.on = present, I.hz = hz;
    float db = DB_FLOOR + level * DB_SPAN;
    I.amp = level > 0 ? 32768.0f * powf(10, db / 20) * 1.4142136f : 0; /* a sine's peak from its RMS */
}
