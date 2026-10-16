/* The microphone, for games (pinyol@2): how loud it is, the pitch of a voice or a whistle, a sudden sound (a clap),
 * what kind of sound it is (a breath, a voice, a whistle, a clap), and recordings that become sounds a game plays.
 * The platform hands over samples (hal_mic_read); all of it is worked out here once a tick, so a game only reads
 * numbers and every platform agrees. Tests feed a tone, noise or a breath instead of a real microphone (mic_inject).
 * On the console it is the game's thread that pays for it: floats only (the chip has no double unit), the pitch
 * looked for every other tick, on every other lag first and then exactly around the peak. */
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
/* What kind of sound: the knobs to tune on a real microphone */
#define LOW_K 0.069f     /* a one-pole low-pass at ~250 Hz: 1 - exp(-2 pi 250 / 22050) */
#define BLOW_LOW 0.45f   /* of the energy below it: wind on the microphone, not a voice (white noise: ~0.04) */
#define BLOW_LEVEL 0.2f
#define BLOW_TICKS 3     /* that long, without a pitch: a breath, not a knock */
#define WHISTLE_HZ 500.0f
#define WHISTLE_CLARITY 0.85f

static struct {
    bool on, real, tried;       /* on: listening; real: through the platform's microphone; tried: asked for one */
    int16_t win[WIN];
    float level, pitch, avg_db, clarity, low_state;
    bool hit;
    int rest, blow_n, ticks;
    const char *kind;
    char rec_id[32];
    int16_t *rec;
    int rec_n, rec_max;
} M;

static struct { /* tests: a made-up microphone, which stays from one game to the next */
    bool on, breath;            /* breath: noise low-passed at ~150 Hz, as wind on a microphone sounds */
    float amp, hz, phase, low;
    uint32_t seed;
} I;

static float level_of(float db) {
    float l = (db - DB_FLOOR) / DB_SPAN;
    return l < 0 ? 0 : l > 1 ? 1 : l;
}

/* McLeod's normalised square difference on the window at half rate: the first strong peak is the period. Looked for
 * on every other lag (a period's curve is far wider than two lags), then exactly around the peak found. */
enum { N = WIN / DEC };
static float x[N], cum[N + 1], nsdf[LAG_MAX + 3];

static float nsdf_at(int lag) {
    float r = 0;
    for (int i = 0; i < N - lag; i++) r += x[i] * x[i + lag];
    float m = cum[N - lag] + (cum[N] - cum[lag]); /* x[i]^2 + x[i+lag]^2 over the overlap */
    return m > 1e-9f ? 2 * r / m : 0;
}

static float find_pitch(float *clarity) {
    *clarity = 0;
    cum[0] = 0;
    for (int i = 0; i < N; i++) {
        x[i] = (M.win[i * DEC] + M.win[i * DEC + 1]) * (1.0f / 65536);
        cum[i + 1] = cum[i] + x[i] * x[i];
    }
    if (cum[N] < 1e-6f) return 0;
    float best = 0;
    for (int lag = LAG_MIN - 1; lag <= LAG_MAX + 2; lag += 2) {
        nsdf[lag] = nsdf_at(lag);
        if (lag >= LAG_MIN && lag <= LAG_MAX && nsdf[lag] > best) best = nsdf[lag];
    }
    for (int lag = LAG_MIN; lag <= LAG_MAX + 1; lag += 2) nsdf[lag] = 0.5f * (nsdf[lag - 1] + nsdf[lag + 1]);
    if (best < 0.9f * CLARITY) return 0; /* (a coarse curve may sit a little under its true peak) */
    /* peaks count once the curve has dipped below zero (or rises from the start: a high note), else the slope of a
     * dull sound at short lags would pass for a period */
    bool past_dip = nsdf[LAG_MIN] > nsdf[LAG_MIN - 1];
    int at = 0;
    for (int lag = LAG_MIN; lag <= LAG_MAX && !at; lag++) {
        if (nsdf[lag] < 0) past_dip = true;
        if (past_dip && nsdf[lag] >= 0.9f * best && nsdf[lag] >= nsdf[lag - 1] && nsdf[lag] >= nsdf[lag + 1]) at = lag;
    }
    if (!at) return 0;
    int lo = at - 2 < LAG_MIN - 1 ? LAG_MIN - 1 : at - 2, hi = at + 2 > LAG_MAX + 1 ? LAG_MAX + 1 : at + 2;
    for (int lag = lo; lag <= hi; lag++) nsdf[lag] = nsdf_at(lag); /* exact, around the peak */
    int top = at;
    for (int lag = lo + 1; lag < hi; lag++) if (nsdf[lag] > nsdf[top]) top = lag;
    if (top <= LAG_MIN - 1 || top >= LAG_MAX + 1 || nsdf[top] < CLARITY) return 0;
    float a = nsdf[top - 1], b = nsdf[top], c = nsdf[top + 1], d = a - 2 * b + c;
    float lag = top + (d != 0 ? 0.5f * (a - c) / d : 0); /* between the samples, on the parabola */
    *clarity = b;
    return (float)AUDIO_HZ / DEC / lag;
}

static int inject(int16_t *p, int n) {
    for (int i = 0; i < n; i++) {
        float v;
        if (I.breath) { /* white noise through a ~150 Hz low-pass, brought back to the same loudness */
            I.seed = I.seed * 1664525u + 1013904223u;
            I.low += 0.0418f * (((int32_t)I.seed >> 8) / 8388608.0f * 1.7320508f - I.low);
            v = I.low * 6.84f;
        } else if (I.hz > 0) {
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
    float sum = 0, low_sum = 0, low = M.low_state;
    int got = 0;
    for (int k = 0; k < 8; k++) { /* what came in since the last tick (a late tick finds more) */
        int n = M.real ? hal_mic_read(buf, 1024) : k ? 0 : inject(buf, AUDIO_HZ / TICK_HZ);
        if (n <= 0) break;
        if (n > 1024) n = 1024;
        for (int i = 0; i < n; i++) {
            float v = buf[i] * (1.0f / 32768);
            sum += v * v;
            low += LOW_K * (v - low);
            low_sum += low * low;
        }
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
    M.low_state = low;
    if (!got) return; /* nothing new (a platform may hand over blocks bigger than a tick): the last numbers stand */
    float rms = sqrtf(sum / got);
    float db = rms > 1e-6f ? 20 * log10f(rms) : -120;
    float was = M.level;
    M.level = level_of(db);
    M.ticks++;
    /* the pitch 30 times a second, but at once when a sound starts: a note is heard without delay */
    if (M.level <= PITCH_LEVEL) M.pitch = 0, M.clarity = 0;
    else if (was <= PITCH_LEVEL || (M.ticks & 1)) M.pitch = find_pitch(&M.clarity);
    if (db < DB_FLOOR) db = DB_FLOOR;
    if (!M.rest && M.level >= HIT_LEVEL && db - M.avg_db >= HIT_RISE) M.hit = true, M.rest = HIT_REST, M.avg_db = db;
    else M.avg_db += (db - M.avg_db) * 0.1f; /* ~10 ticks to settle; a hit is the new loudness at once */
    /* what kind of sound */
    float low_part = sum > 0 ? low_sum / sum : 0;
    M.blow_n = (M.pitch == 0 && M.level >= BLOW_LEVEL && low_part >= BLOW_LOW) ? M.blow_n + 1 : 0;
    if (M.pitch > 0) M.kind = M.pitch >= WHISTLE_HZ && M.clarity >= WHISTLE_CLARITY ? "whistle" : "voice";
    else if (M.blow_n >= BLOW_TICKS) M.kind = "blow";
    else if (M.hit) M.kind = "clap";
    else M.kind = NULL;
}

bool mic_read(float *level, float *pitch, bool *hit, bool *recording, const char **kind) {
    if (!M.on) return false;
    *level = M.level, *pitch = M.pitch, *hit = M.hit, *recording = M.rec != NULL, *kind = M.kind;
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

void mic_inject(bool present, float level, float hz, bool breath) {
    if (!present || !I.on) mic_close(); /* the microphone changes under the game: it opens it again */
    I.on = present, I.hz = hz, I.breath = breath;
    float db = DB_FLOOR + level * DB_SPAN;
    I.amp = level > 0 ? 32768.0f * powf(10, db / 20) * 1.4142136f : 0; /* a sine's peak from its RMS */
}
