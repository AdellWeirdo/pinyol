/* Mixer. Streams WAV (PCM16, AUDIO_HZ) from the game folder:
 *   ambience: three mono slots so zones crossfade (even when the player bounces between zones);
 *   music:    one cue = one WAV whose interleaved channels are its layers (vertical layering), each with
 *             its own gain: one SD read per block and layers locked to the sample. Layer changes and
 *             stops wait for the next bar line (iMUSE-style), so the music never changes mid-phrase;
 *   voice:    mono one-shots (listening clips, the echo's lines) in two slots, so a new line crossfades
 *             over the previous one's reverb tail instead of cutting it;
 * SFX are short mono clips cached in RAM with up to 4 variants each (SFX_X, SFX_X_2..SFX_X_4).
 * The game thread only sets targets; the audio thread ramps every gain per sample, so nothing clicks.
 * The ambience bus has a one-pole lowpass: listening muffles the world instead of only lowering it.
 * A missing file leaves its slot silent; subtitles and pulses carry the information. */
#include <math.h>
#include <stdlib.h>
#include <string.h>

#include "bp.h"

#define CHUNK 256
#define SFX_VOICES 12 /* a drum machine's tails overlap (handles keep 4 bits for it) */
#define SFX_CACHE 48
/* ponytail: one byte budget, least recently played out first; on the card the ambience events alone are 3.3 MB */
#define SFX_CACHE_BYTES (1536 * 1024)
#define SFX_MAX_SAMPLES (AUDIO_HZ * 20) /* three tolls of a far bell ring for ~15 s (PSRAM on the board) */
#define NMISSING 96
#define NAMB 3

typedef struct { float v, target, step; } ramp;

typedef struct {
    FILE *f;
    long start, len, pos, loop_at; /* bytes; loop_at: where a loop restarts (after a music intro) */
    int chans;
    bool loop, dying; /* dying: closed once faded to silence; silent music layers keep streaming in sync */
    char id[32];
    ramp g[MAX_STEMS];
    long bar;                          /* bytes per bar; 0 = changes apply at once */
    float pend[MAX_STEMS];             /* layer targets waiting for the next bar line */
    int pend_ms[MAX_STEMS];
    bool pend_set[MAX_STEMS], armed, pend_die;
} stream;

typedef struct {
    char id[32];
    int16_t *pcm[4];
    int n[4], count, last;
    long bytes;
    unsigned used; /* use_clock at its last play: the oldest goes first when the budget is full */
    bool made;     /* by the game (audio_sfx_set): there is no file to load it again, so it stays */
    int pins;      /* studio tracks playing it (audio_clip_pin): never evicted while pinned */
} clip;

typedef struct {
    const int16_t *pcm;
    int n, pos;
    uint32_t frac;     /* pitch != 1: the fraction of a sample past pos, 16 bits */
    float gain, pitch; /* pitch: 1 as recorded, 2 an octave up */
    bool loop;
    uint16_t gen;      /* counts the sounds this voice has started: a handle names one of them */
    int wait;          /* samples of the next block before it starts: a studio step lands on its sample */
} sfx_voice;

enum { S_AMB0, S_MUS = S_AMB0 + NAMB, S_VOICE0, S_VOICE1, NSTREAMS };

static stream st[NSTREAMS];
static ramp bus_amb = {1, 1, 0}, bus_mus = {1, 1, 0}, amb_lp = {1, 1, 0}, master = {1, 1, 0};
static float lp_state;
static sfx_voice sfx[SFX_VOICES];
static clip cache[SFX_CACHE];
static int ncache;
static long cache_bytes;
static unsigned use_clock;
static volatile bool paused;
static char missing[NMISSING][32];
static int nmissing;
/* music_time(): the song's samples mixed since music() started it, and where the last mix ended, by the clock */
static long mus_clock, mark_clock;
static int mus_src; /* 0: no song; 1: the WAV stream; 2: a module (modplay.c) */
static uint32_t mark_us;
static int mark_n;
static double mus_last; /* the last time given: it never goes back */

static uint32_t rd32(const uint8_t *p) { return p[0] | (p[1] << 8) | (p[2] << 16) | ((uint32_t)p[3] << 24); }

bool wav_parse(FILE *f, long *data_start, long *data_len, int *chans) {
    uint8_t h[12], c[8], fmt[16];
    if (fread(h, 1, 12, f) != 12 || memcmp(h, "RIFF", 4) || memcmp(h + 8, "WAVE", 4)) return false;
    bool fmt_ok = false;
    int ch = 0;
    while (fread(c, 1, 8, f) == 8) {
        long size = (long)rd32(c + 4);
        if (!memcmp(c, "fmt ", 4)) {
            if (size < 16 || fread(fmt, 1, 16, f) != 16) return false;
            int format = fmt[0] | (fmt[1] << 8), bits = fmt[14] | (fmt[15] << 8);
            ch = fmt[2] | (fmt[3] << 8);
            fmt_ok = (format == 1 || format == 0xFFFE) && ch >= 1 && ch <= MAX_STEMS && bits == 16 && rd32(fmt + 4) == AUDIO_HZ;
            fseek(f, size - 16 + (size & 1), SEEK_CUR);
        } else if (!memcmp(c, "data", 4)) {
            *data_start = ftell(f);
            fseek(f, 0, SEEK_END);
            long avail = ftell(f) - *data_start; /* a truncated copy on the SD must not lie about its length */
            long frame = 2L * (ch > 0 ? ch : 1);
            *data_len = (size < avail ? size : avail) / frame * frame;
            if (chans) *chans = ch;
            return fmt_ok && *data_len >= frame;
        } else {
            fseek(f, size + (size & 1), SEEK_CUR);
        }
    }
    return false;
}

static bool is_missing(const char *id) {
    for (int i = 0; i < nmissing; i++)
        if (!strcmp(missing[i], id) || !strcmp(missing[i], "*")) return true;
    return false;
}

static void mark_missing(const char *id) {
    if (nmissing < NMISSING && !is_missing(id)) snprintf(missing[nmissing++], sizeof missing[0], "%s", id);
}

/* Opens and validates <id>.wav; NULL (logged once) if absent or in the wrong format. */
static FILE *open_wav(const char *id, long *start, long *len, int *chans, bool quiet) {
    if (!id || !*id || is_missing(id)) return NULL;
    char path[384];
    snprintf(path, sizeof path, "%s/audio/%s.wav", G.game_dir, id);
    FILE *f = game_has(path + strlen(G.game_dir) + 1) ? fopen(path, "rb") : NULL;
    if (f && wav_parse(f, start, len, chans)) {
        fseek(f, *start, SEEK_SET);
        return f;
    }
    if (f) fclose(f);
    if (!quiet) hal_log("audio %s missing or not PCM16 %d Hz; continuing silent", id, AUDIO_HZ);
    mark_missing(id);
    return NULL;
}

static void ramp_to(ramp *r, float target, int ms) {
    r->target = target < 0 ? 0 : target > 1 ? 1 : target;
    float d = fabsf(r->target - r->v), n = (float)ms * AUDIO_HZ / 1000;
    r->step = n > 1 ? d / n : 1;
}

static inline float ramp_next(ramp *r) {
    if (r->v < r->target) r->v = r->v + r->step < r->target ? r->v + r->step : r->target;
    else if (r->v > r->target) r->v = r->v - r->step > r->target ? r->v - r->step : r->target;
    return r->v;
}

static void close_stream(stream *s) {
    if (s->f) fclose(s->f);
    *s = (stream){0};
}

static void fade_out(stream *s, int ms) {
    for (int k = 0; k < MAX_STEMS; k++) ramp_to(&s->g[k], 0, ms);
    s->dying = true;
}

/* Opens a mono id into a slot, rising from silence to gain over ms (file I/O outside the lock, swap inside). */
static bool open_into(int slot, const char *id, bool loop, float gain, int ms) {
    long start = 0, len = 0;
    int chans = 1;
    FILE *f = open_wav(id, &start, &len, &chans, false);
    if (f && chans != 1) {
        hal_log("audio %s must be mono", id);
        fclose(f);
        f = NULL;
        mark_missing(id);
    }
    hal_audio_lock();
    close_stream(&st[slot]);
    if (f) {
        st[slot] = (stream){.f = f, .start = start, .len = len, .chans = 1, .loop = loop};
        snprintf(st[slot].id, sizeof st[slot].id, "%s", id);
        ramp_to(&st[slot].g[0], gain, ms);
    }
    hal_audio_unlock();
    return f != NULL;
}

/* A free slot, else the quietest one (caller holds the lock). */
static int pick_slot(int first, int n) {
    int best = first;
    for (int i = first; i < first + n; i++) {
        if (!st[i].f) return i;
        if (st[i].g[0].v < st[best].g[0].v) best = i;
    }
    return best;
}

/* ------------------------------------------------------------------ game-thread API */
void audio_ambient(const char *id, int fade_ms) {
    hal_audio_lock();
    int keep = -1;
    for (int i = S_AMB0; i < S_AMB0 + NAMB; i++)
        if (id && st[i].f && !strcmp(st[i].id, id)) keep = i;
    for (int i = S_AMB0; i < S_AMB0 + NAMB; i++)
        if (i != keep) fade_out(&st[i], fade_ms);
    if (keep >= 0) { /* already here (maybe fading out after a quick back-and-forth): bring it back */
        ramp_to(&st[keep].g[0], 1, fade_ms);
        st[keep].dying = false;
    }
    int slot = pick_slot(S_AMB0, NAMB);
    hal_audio_unlock();
    if (keep < 0 && id) open_into(slot, id, true, 1, fade_ms);
}

bool audio_music_playing(void) {
    hal_audio_lock();
    bool on = st[S_MUS].f != NULL;
    hal_audio_unlock();
    return on;
}

static void pend(stream *s, int k, float gain, int ms) {
    s->pend[k] = gain;
    s->pend_ms[k] = ms;
    s->pend_set[k] = s->armed = true;
}

static void apply_pending(stream *s) {
    for (int k = 0; k < MAX_STEMS; k++)
        if (s->pend_set[k]) ramp_to(&s->g[k], s->pend[k], s->pend_ms[k]);
    if (s->pend_die) s->dying = true;
    memset(s->pend_set, 0, sizeof s->pend_set);
    s->armed = s->pend_die = false;
}

static bool now(const stream *s) { return !s->bar || s->pos == 0; }

void audio_music_stop(int fade_ms) {
    hal_audio_lock();
    stream *s = &st[S_MUS];
    if (now(s)) fade_out(s, fade_ms);
    else {
        for (int k = 0; k < MAX_STEMS; k++) pend(s, k, 0, fade_ms);
        s->pend_die = true;
    }
    hal_audio_unlock();
}

/* Starts a cue from sample 0, each layer rising from silence to gains[k] over fade_ms, in one locked
 * swap (the audio thread never sees it half set up). bar_s > 0 quantises later changes to bar lines.
 * Returns the cue's layer count (its WAV channels). */
int audio_music_start(const char *cue, float loop_at_s, float bar_s, const float *gains, int fade_ms) {
    long start = 0, len = 0;
    int chans = 1;
    FILE *f = open_wav(cue, &start, &len, &chans, false);
    if (!(loop_at_s >= 0 && loop_at_s < 3600)) loop_at_s = 0; /* also NaN */
    if (!(bar_s > 0 && bar_s < 60)) bar_s = 0;
    hal_audio_lock();
    stream *s = &st[S_MUS];
    close_stream(s);
    audio_music_clock_locked(f ? 1 : 0); /* in the same swap: not one block of the old song counted */
    if (f) {
        long frame = 2L * chans, at = (long)(loop_at_s * AUDIO_HZ) * frame;
        *s = (stream){.f = f, .start = start, .len = len, .chans = chans, .loop = true,
                      .loop_at = at < len ? at : 0, .bar = (long)(bar_s * AUDIO_HZ) * frame};
        snprintf(s->id, sizeof s->id, "%s", cue);
        for (int k = 0; k < chans; k++) ramp_to(&s->g[k], gains ? gains[k] : k == 0, fade_ms);
    }
    hal_audio_unlock();
    return f ? chans : 0;
}

void audio_music_layer(int i, float gain, int fade_ms) {
    if (i < 0 || i >= MAX_STEMS) return;
    hal_audio_lock();
    stream *s = &st[S_MUS];
    if (!s->dying && !s->pend_die) {
        if (now(s)) ramp_to(&s->g[i], gain, fade_ms);
        else pend(s, i, gain, fade_ms);
    }
    hal_audio_unlock();
}

void audio_voice(const char *id) {
    hal_audio_lock();
    fade_out(&st[S_VOICE0], 120);
    fade_out(&st[S_VOICE1], 120);
    int slot = pick_slot(S_VOICE0, 2);
    hal_audio_unlock();
    open_into(slot, id, false, 1, 5);
}

void audio_voice_stop(int fade_ms) {
    hal_audio_lock();
    fade_out(&st[S_VOICE0], fade_ms);
    fade_out(&st[S_VOICE1], fade_ms);
    hal_audio_unlock();
}

void audio_bus(float amb, float mus, float amb_lowpass_hz, int fade_ms) {
    float a = amb_lowpass_hz > 0 ? 1 - expf(-6.2831853f * amb_lowpass_hz / AUDIO_HZ) : 1;
    hal_audio_lock();
    ramp_to(&bus_amb, amb, fade_ms);
    ramp_to(&bus_mus, mus, fade_ms);
    ramp_to(&amb_lp, a, fade_ms);
    hal_audio_unlock();
}

void audio_master(float gain, int fade_ms) {
    hal_audio_lock();
    ramp_to(&master, gain, fade_ms);
    hal_audio_unlock();
}

static int16_t *load_clip(const char *id, int *n, bool quiet) {
    long start = 0, len = 0;
    int chans = 1;
    FILE *f = open_wav(id, &start, &len, &chans, quiet);
    if (!f) return NULL;
    long count = len / 2 < SFX_MAX_SAMPLES ? len / 2 : SFX_MAX_SAMPLES;
    int16_t *pcm = chans == 1 ? malloc(sizeof(int16_t) * (size_t)count) : NULL;
    *n = pcm ? (int)(fread_chunked(pcm, sizeof(int16_t) * (size_t)count, f) / sizeof(int16_t)) : 0;
    fclose(f);
    if (chans != 1 || *n <= 0) mark_missing(id); /* never retried from the SD on every play */
    if (pcm && *n > 0 && count < len / 2) { /* too long for RAM: keep the head, fade it instead of clicking */
        int k = *n < AUDIO_HZ / 10 ? *n : AUDIO_HZ / 10;
        for (int i = 0; i < k; i++) pcm[*n - k + i] = (int16_t)(pcm[*n - k + i] * (k - i) / k);
        hal_log("audio %s longer than %d s, truncated", id, SFX_MAX_SAMPLES / AUDIO_HZ);
    }
    if (pcm && *n > 0) return pcm;
    free(pcm);
    return NULL;
}

static bool playing(const clip *c) { /* under the lock: a voice still reading one of its variants */
    for (int v = 0; v < SFX_VOICES; v++)
        for (int k = 0; k < c->count; k++)
            if (sfx[v].pcm == c->pcm[k]) return true;
    return false;
}

/* Frees the least recently played clip that no voice is reading, except the newest entry; false if none. */
static bool evict_one(int keep) {
    hal_audio_lock();
    int old = -1;
    for (int i = 0; i < ncache; i++)
        if (i != keep && !cache[i].made && !cache[i].pins && !playing(&cache[i]) &&
            (old < 0 || cache[i].used < cache[old].used))
            old = i;
    if (old >= 0) {
        for (int k = 0; k < cache[old].count; k++) free(cache[old].pcm[k]);
        cache_bytes -= cache[old].bytes;
        memmove(&cache[old], &cache[old + 1], sizeof cache[0] * (size_t)(ncache - old - 1)); /* keeps the order */
        ncache--;
    }
    hal_audio_unlock();
    return old >= 0;
}

static clip *clip_get(const char *id) {
    for (int i = 0; i < ncache; i++)
        if (!strcmp(cache[i].id, id)) {
            cache[i].used = ++use_clock;
            return &cache[i];
        }
    if (is_missing(id) || (ncache == SFX_CACHE && !evict_one(-1))) return NULL;
    clip *c = &cache[ncache];
    memset(c, 0, sizeof *c);
    snprintf(c->id, sizeof c->id, "%s", id);
    c->last = -1;
    if (!(c->pcm[0] = load_clip(id, &c->n[0], false))) return NULL;
    c->count = 1;
    char v[40];
    for (int k = 2; k <= 4; k++) { /* optional variants: SFX_X_2..SFX_X_4 */
        snprintf(v, sizeof v, "%s_%d", id, k);
        if (!(c->pcm[c->count] = load_clip(v, &c->n[c->count], true))) break;
        c->count++;
    }
    for (int k = 0; k < c->count; k++) c->bytes += (long)c->n[k] * (long)sizeof(int16_t);
    c->used = ++use_clock;
    cache_bytes += c->bytes;
    ncache++;
    while (cache_bytes > SFX_CACHE_BYTES && evict_one(ncache - 1)) {} /* the new one is always last */
    return &cache[ncache - 1];
}

long audio_cache_bytes(void) { return cache_bytes; }

/* Loads a clip into RAM ahead of time (zone entry), so its first play never waits for the SD. */
void audio_preload(const char *id) {
    if (id) clip_get(id);
}

/* From RAM, a variant different from the last one, so repeats never sound identical; at a pitch (1 as recorded),
 * looping or once. Returns a handle for audio_sfx_adjust / audio_sfx_stop, 0 if nothing plays. */
int audio_sfx_play(const char *id, float gain, float pitch, bool loop) {
    if (!id) return 0;
    clip *c = clip_get(id);
    if (!c) return 0;
    int k = c->count > 1 ? rand() % (c->count - 1) : 0;
    if (c->count > 1 && k >= c->last) k++;
    c->last = k;
    hal_audio_lock();
    int h = audio_voice_start_locked(c->pcm[k], c->n[k], gain, pitch, loop, 0);
    hal_audio_unlock();
    return h;
}

/* A voice starts pcm, `wait` samples into the next block mixed (the audio lock held). Returns its handle. */
int audio_voice_start_locked(const int16_t *pcm, int n, float gain, float pitch, bool loop, int wait) {
    pitch = pitch > 0.0625f && pitch < 16 ? pitch : pitch >= 16 ? 16 : 0.0625f; /* NaN too: the lowest */
    int v = -1;
    for (int i = 0; i < SFX_VOICES && v < 0; i++) /* a free voice */
        if (!sfx[i].pcm) v = i;
    if (v < 0) /* else steal one: the one-shot closest to its end, else voice 0 */
        for (int i = 0; i < SFX_VOICES; i++)
            if (!sfx[i].loop && (v < 0 || sfx[i].n - sfx[i].pos < sfx[v].n - sfx[v].pos)) v = i;
    if (v < 0) v = 0;
    uint16_t gen = (uint16_t)(sfx[v].gen + 1);
    sfx[v] = (sfx_voice){pcm, n, 0, 0, gain < 0 ? 0 : gain > 1 ? 1 : gain, pitch, loop, gen, wait < 0 ? 0 : wait};
    return (gen & 0x7FFF) << 4 | (v + 1); /* never 0 */
}

void audio_sfx(const char *id, float gain) { audio_sfx_play(id, gain, 1, false); }

static sfx_voice *by_handle(int h) { /* under the lock: the voice still playing that sound, or NULL */
    int v = (h & 15) - 1;
    if (v < 0 || v >= SFX_VOICES || !sfx[v].pcm || (sfx[v].gen & 0x7FFF) != (h >> 4)) return NULL;
    return &sfx[v];
}

void audio_sfx_adjust(int h, float gain, float pitch) { /* a negative value leaves that one as it is */
    hal_audio_lock();
    sfx_voice *x = by_handle(h);
    if (x && gain >= 0) x->gain = gain > 1 ? 1 : gain;
    if (x && pitch > 0) x->pitch = pitch > 0.0625f ? (pitch < 16 ? pitch : 16) : 0.0625f;
    hal_audio_unlock();
}

void audio_voice_stop_locked(int h) {
    sfx_voice *x = by_handle(h);
    if (x) x->pcm = NULL;
}

void audio_sfx_stop(int h) {
    hal_audio_lock();
    audio_voice_stop_locked(h);
    hal_audio_unlock();
}

/* A clip a studio track plays: loaded now (the game's thread) and never evicted while pinned. Its first variant
 * only, so a pattern sounds the same every time round. */
bool audio_clip_pin(const char *id, const int16_t **pcm, int *n) {
    clip *c = id ? clip_get(id) : NULL;
    if (!c) return false;
    c->pins++;
    *pcm = c->pcm[0], *n = c->n[0];
    return true;
}

void audio_clip_unpin(const int16_t *pcm) {
    for (int i = 0; i < ncache; i++)
        if (cache[i].pcm[0] == pcm && cache[i].pins > 0) cache[i].pins--;
}

bool audio_sfx_playing(int h) {
    hal_audio_lock();
    bool on = by_handle(h) != NULL;
    hal_audio_unlock();
    return on;
}

/* A clip the game made (synth.c): kept under id, taking the place of one of that name; pcm becomes the cache's. */
bool audio_sfx_set(const char *id, int16_t *pcm, int n) {
    clip *c = NULL;
    for (int i = 0; i < ncache && !c; i++)
        if (!strcmp(cache[i].id, id)) c = &cache[i];
    if (!c && ncache == SFX_CACHE && !evict_one(-1)) return free(pcm), false;
    hal_audio_lock();
    int pins = 0;
    if (c) { /* the old sound goes: voices playing it stop first, studio tracks move to the new one */
        for (int v = 0; v < SFX_VOICES; v++)
            for (int k = 0; k < c->count; k++)
                if (sfx[v].pcm == c->pcm[k]) sfx[v].pcm = NULL;
        studio_replace_locked(c->pcm[0], pcm, n);
        pins = c->pins;
        for (int k = 0; k < c->count; k++) free(c->pcm[k]);
        cache_bytes -= c->bytes;
    } else {
        c = &cache[ncache++];
    }
    memset(c, 0, sizeof *c);
    c->pins = pins;
    snprintf(c->id, sizeof c->id, "%s", id);
    c->pcm[0] = pcm, c->n[0] = n, c->count = 1, c->last = -1, c->made = true;
    c->bytes = (long)n * (long)sizeof(int16_t), c->used = ++use_clock;
    cache_bytes += c->bytes;
    hal_audio_unlock();
    return true;
}

long audio_made_bytes(void) { /* the game's own sounds, which are never evicted */
    long b = 0;
    for (int i = 0; i < ncache; i++) b += cache[i].made ? cache[i].bytes : 0;
    return b;
}

void audio_pause(bool p) { paused = p; }

void audio_music_clock_locked(int src) { mus_src = src, mus_clock = mark_clock = 0, mark_n = 0, mus_last = 0; }

void audio_music_clock(int src) {
    hal_audio_lock();
    audio_music_clock_locked(src);
    hal_audio_unlock();
}

static bool music_sounds(void) { return mus_src == 1 ? st[S_MUS].f != NULL : mus_src == 2 && mod_playing(); }

bool audio_music_time(double *seconds) {
    hal_audio_lock();
    bool on = music_sounds();
    long c = mark_clock;
    uint32_t us = mark_us;
    int n = mark_n;
    bool still = paused;
    hal_audio_unlock();
    if (!on) return false;
    int lat = hal_audio_latency();
    double t = (double)c;
    if (lat >= 0 && c > 0) { /* the block mixed last starts after the queue; by the clock since it was mixed */
        double e = still ? 0 : (double)(uint32_t)(hal_micros() - us) * (AUDIO_HZ / 1e6);
        t += (e < n ? e : n) - n - lat;
    }
    if (t < mus_last) t = mus_last;
    mus_last = t;
    *seconds = t > 0 ? t / AUDIO_HZ : 0;
    return true;
}

void audio_reset(void) {
    studio_reset(); /* its tracks point into the cache freed below */
    hal_audio_lock();
    for (int i = 0; i < NSTREAMS; i++) close_stream(&st[i]);
    memset(sfx, 0, sizeof sfx);
    bus_amb = bus_mus = amb_lp = master = (ramp){1, 1, 0};
    lp_state = 0;
    hal_audio_unlock();
    psg_reset();
    mod_reset();
    for (int i = 0; i < ncache; i++)
        for (int k = 0; k < cache[i].count; k++) free(cache[i].pcm[k]);
    ncache = 0;
    cache_bytes = 0;
    paused = false;
    nmissing = 0;
}

void audio_force_missing(const char *id) { mark_missing(id); }

/* ------------------------------------------------------------------ audio thread */
/* Reads up to m frames of a stream into buf (looping), returns how many it produced. */
static int stream_read(stream *s, int16_t *buf, int m) {
    int got = 0;
    long frame = 2L * s->chans;
    while (s->f && got < m) {
        long left = (s->len - s->pos) / frame;
        int want = m - got < left ? m - got : (int)left;
        int r = want > 0 ? (int)fread(buf + got * s->chans, (size_t)frame, (size_t)want, s->f) : 0;
        got += r;
        s->pos += frame * r;
        if (r < want || s->pos >= s->len) {
            if (!s->loop || (r == 0 && s->pos == s->loop_at)) { close_stream(s); break; } /* unreadable: never spin */
            fseek(s->f, s->start + s->loop_at, SEEK_SET);
            s->pos = s->loop_at;
        }
    }
    return got;
}

static bool silent(const stream *s) {
    for (int k = 0; k < s->chans; k++)
        if (s->g[k].v > 0) return false;
    return true;
}

/* Soft knee above -3 dBFS instead of hard clipping when everything plays at once. */
static inline int16_t limit(float x) {
    const float k = 23000, room = 32767 - k;
    float a = fabsf(x);
    if (a > k) a = k + (a - k) / (1 + (a - k) / room);
    return (int16_t)(x < 0 ? -a : a);
}

/* Called by the platform's audio callback/task with the audio lock held. */
void audio_mix(int16_t *out, int n) {
    static float acc[CHUNK], amb[CHUNK]; /* single caller (audio callback/task): keep them off its small stack */
    static int16_t buf[CHUNK * MAX_STEMS];
    for (int off = 0; off < n; off += CHUNK) {
        int m = n - off < CHUNK ? n - off : CHUNK;
        memset(acc, 0, sizeof acc);
        memset(amb, 0, sizeof amb);
        for (int c = 0; c < NSTREAMS && !paused; c++) { /* pause freezes the world; menu clicks still play */
            stream *s = &st[c];
            if (!s->f) continue;
            if (s->dying && silent(s)) { close_stream(s); continue; }
            float *dst = c < S_AMB0 + NAMB ? amb : acc;
            ramp b = c == S_MUS ? bus_mus : (ramp){1, 1, 0};
            long p0 = s->pos, bar = s->bar;
            int ch = s->chans; /* read first: stream_read closes (and zeroes) a one-shot that ends */
            int got = stream_read(s, buf, m);
            if (s->armed && bar && (s->pos / bar != p0 / bar || s->pos < p0)) apply_pending(s); /* <= 1 chunk late */
            for (int i = 0; i < got; i++) {
                float x = 0;
                for (int k = 0; k < ch; k++) x += buf[i * ch + k] * ramp_next(&s->g[k]);
                dst[i] += x * ramp_next(&b);
            }
        }
        for (int i = 0; i < m && !paused; i++) { /* ambience bus: gain then a ramped one-pole lowpass (1 = open) */
            float a = ramp_next(&amb_lp);
            lp_state += a * (amb[i] * ramp_next(&bus_amb) - lp_state);
            acc[i] += lp_state;
            ramp_next(&bus_mus);
        }
        if (!paused) studio_tick(m); /* the steps falling in this block start their voices, to the sample */
        for (int v = 0; v < SFX_VOICES; v++) {
            sfx_voice *x = &sfx[v];
            int i0 = x->wait < m ? x->wait : m;
            x->wait -= i0;
            if (x->pitch == 1) /* as recorded: sample after sample, round again if it loops */
                for (int i = i0; i < m && x->pcm;) {
                    int k = x->n - x->pos < m - i ? x->n - x->pos : m - i;
                    for (int j = 0; j < k; j++) acc[i + j] += x->pcm[x->pos + j] * x->gain;
                    x->pos += k, i += k;
                    if (x->pos >= x->n) x->pos = 0, x->pcm = x->loop ? x->pcm : NULL;
                }
            else { /* faster or slower: between two samples, by the fraction */
                uint32_t step = (uint32_t)(x->pitch * 65536.0f);
                for (int i = i0; i < m && x->pcm; i++) {
                    int a = x->pos, b = a + 1 < x->n ? a + 1 : (x->loop ? 0 : a);
                    acc[i] += (x->pcm[a] + (float)(x->pcm[b] - x->pcm[a]) * (float)x->frac / 65536.0f) * x->gain;
                    x->frac += step;
                    x->pos += (int)(x->frac >> 16), x->frac &= 0xFFFF;
                    if (x->pos >= x->n) {
                        if (x->loop) x->pos %= x->n;
                        else x->pcm = NULL;
                    }
                }
            }
        }
        if (!paused) studio_mix(acc, m); /* the synth tracks' voices */
        psg_mix(acc, m);
        if (!paused && music_sounds()) mus_clock += m; /* (before a module may end) */
        if (!paused) mod_mix(acc, m);
        for (int i = 0; i < m; i++) out[off + i] = limit(acc[i] * ramp_next(&master));
    }
    mark_clock = mus_clock, mark_us = hal_micros(), mark_n = n;
    studio_mark(n);
}
