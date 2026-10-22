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
#define MIDI_VOICES 16 /* the sequencer's own, after those: a song's notes never take a sound effect's voice */
#define NVOICES (SFX_VOICES + MIDI_VOICES)
#define SFX_CACHE 48
/* ponytail: one byte budget, least recently played out first; on the card the ambience events alone are 3.3 MB */
#define SFX_CACHE_BYTES (1536 * 1024)
#define SFX_MAX_SAMPLES (AUDIO_HZ * 20) /* three tolls of a far bell ring for ~15 s (PSRAM on the board) */
#define NMISSING 96
#define NAMB 3

typedef struct { float v, target, step; } ramp;
#define VAG_SAMPLES 28
#define VAG_BYTES 16

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
    ramp cut_l, cut_r;                 /* pan: how much of each ear's gain is taken away (0..1; both 0: the centre) */
    bool parked;                       /* opened and waiting (S_NEXT): not read until the song playing reaches its bar line */
    /* a stream kept as ADPCM (audio/<id>.spum: every stem's block, then the next block, 28 samples a block), decoded as it plays */
    bool adpcm;
    long samples;                      /* its length in samples (pos and len stay in the bytes of the PCM it stands for) */
    int blk_next, blk_at;              /* the next block to read from the file; how far into the decoded one (28: read the next) */
    int old[MAX_STEMS], older[MAX_STEMS];
    int16_t blk[MAX_STEMS][VAG_SAMPLES];
    uint8_t *rb;                       /* a read buffer of several blocks at a time (the card is read in sizeable pieces) */
    int rb_pos, rb_len;
} stream;

typedef struct {
    char id[32];
    int16_t *pcm[4];
    uint8_t *vag[4];            /* a variant kept as SPU-ADPCM blocks (audio/<id>.vag) instead: pcm[k] is NULL then */
    int loop_a[4], loop_b[4];   /* its file's loop points, in samples (b <= a: none) */
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
    float send_d, send_r; /* a studio track's sends to its echo and reverb (0 for the game's own sounds) */
    float side_l, side_r; /* pan: how far each ear's gain is below 1 (both 0: centred, as a voice without pan) */
    int loop_from, end; /* a loop goes back to loop_from at end (the clip's n unless a loop point says less) */
    bool env;           /* a volume envelope shapes it: attack, decay to sustain, then release when stopped */
    uint8_t stage;      /* ENV_* */
    float level, sustain, rise, fall_d, fall_r; /* rise: a sample's step up; fall_*: a sample's factor down */
    float rev;          /* how much of it goes into the game's reverb */
    const uint8_t *vag; /* an ADPCM clip: its blocks, decoded two at a time into blk as the voice reads along */
    int vbase, vold, volder; /* the clip's sample blk[0] is, and the decoder's last two samples after blk's second half */
    int16_t blk[56];
} sfx_voice;

/* The PlayStation sound chip's ADPCM (psx-spx "SPU ADPCM Samples"): blocks of 16 bytes, 28 samples of 4 bits. Byte 0:
 * the filter (high nibble) and the shift (low); byte 1: flags (the engine takes its loop from the file's header);
 * then the nibbles, low first. Each sample is its nibble scaled by the shift plus a prediction from the last two. */
static const int8_t vag_k0[5] = {0, 60, 115, 98, 122}, vag_k1[5] = {0, 0, -52, -55, -60};

static void vag_block(const uint8_t *b, int *old, int *older, int16_t *out) {
    int shift = b[0] & 15, f = b[0] >> 4;
    if (shift > 12) shift = 12;
    if (f > 4) f = 4;
    for (int i = 0; i < VAG_SAMPLES; i++) {
        int nib = (b[2 + i / 2] >> (i & 1 ? 4 : 0)) & 15;
        int v = ((int16_t)(nib << 12) >> shift) + ((*old * vag_k0[f] + *older * vag_k1[f] + 32) >> 6);
        v = v < -32768 ? -32768 : v > 32767 ? 32767 : v;
        *older = *old, *old = v;
        out[i] = (int16_t)v;
    }
}

/* Block bi of a clip of n samples decoded into out (silence past its end), the decoder's state carried on. */
static void vag_decode(const sfx_voice *x, int bi, int16_t *out, int *old, int *older) {
    if (bi * VAG_SAMPLES < x->n) vag_block(x->vag + (size_t)bi * VAG_BYTES, old, older, out);
    else memset(out, 0, VAG_SAMPLES * sizeof *out);
}

/* The voice's sample i (read along, one or two ahead, or jumped to at a loop's start or the start: the first block of
 * a jump takes the state from nothing, which the encoder allows for by making it a filterless one). */
static inline int vag_get(sfx_voice *x, int i) {
    int rel = i - x->vbase;
    if ((unsigned)rel >= 2 * VAG_SAMPLES) {
        x->vbase = i / VAG_SAMPLES * VAG_SAMPLES, x->vold = x->volder = 0;
        vag_decode(x, x->vbase / VAG_SAMPLES, x->blk, &x->vold, &x->volder);
        vag_decode(x, x->vbase / VAG_SAMPLES + 1, x->blk + VAG_SAMPLES, &x->vold, &x->volder);
        rel = i - x->vbase;
    } else if (rel >= VAG_SAMPLES) { /* into the second block: the window moves on by one */
        memcpy(x->blk, x->blk + VAG_SAMPLES, VAG_SAMPLES * sizeof *x->blk);
        x->vbase += VAG_SAMPLES;
        vag_decode(x, x->vbase / VAG_SAMPLES + 1, x->blk + VAG_SAMPLES, &x->vold, &x->volder);
        rel -= VAG_SAMPLES;
    }
    return x->blk[rel];
}

enum { ENV_ATTACK, ENV_DECAY, ENV_SUSTAIN, ENV_RELEASE };

/* The envelope's next level, one sample on: the attack climbs evenly, the decay and the release fall by a constant
 * factor a sample (as the PlayStation's sound chip's exponential ones do), and a release that is all but silent ends
 * the voice. */
static inline float env_next(sfx_voice *x) {
    switch (x->stage) {
    case ENV_ATTACK:
        x->level += x->rise;
        if (x->level >= 1) x->level = 1, x->stage = x->sustain < 1 ? ENV_DECAY : ENV_SUSTAIN;
        break;
    case ENV_DECAY:
        x->level = x->sustain + (x->level - x->sustain) * x->fall_d;
        if (x->level - x->sustain < 1e-4f) x->level = x->sustain, x->stage = ENV_SUSTAIN;
        break;
    case ENV_RELEASE:
        x->level *= x->fall_r;
        if (x->level < 1e-4f) x->pcm = NULL;
        break;
    default: break;
    }
    return x->level;
}

enum { S_AMB0, S_MUS = S_AMB0 + NAMB, S_VOICE0, S_VOICE1, S_NEXT, NSTREAMS }; /* S_NEXT: the song waiting for the bar line, parked */

static stream st[NSTREAMS];
static ramp bus_amb = {1, 1, 0}, bus_mus = {1, 1, 0}, amb_lp = {1, 1, 0}, master = {1, 1, 0};
static ramp user = {1, 1, 0}; /* the console's volume (conf.c), over the game's master */
/* the buses a game sets (bus(), duck()): the sounds' gain; the music's lowpass and its duck (a dip that comes back) */
static ramp bus_sfx = {1, 1, 0}, mus_lp = {1, 1, 0}, duck_mus = {1, 1, 0};
static clip *clip_get(const char *id); /* (below) */
static float mus_lp_state;
static long duck_hold;      /* samples the duck stays down before it comes back */
static int duck_release_ms;
static ramp rv_wet = {0, 0, 0};               /* how much of the game's reverb comes back */
static float rv_music, rv_amb;                 /* what the music and the ambience send into it */
static bool rv_closing;                        /* fading out: the room goes when it is silent */
static float lp_state, lp_l, lp_r; /* the ambience's lowpass, and the same for what a panned bed adds to each ear */
static sfx_voice sfx[NVOICES];
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

bool wav_parse(FILE *f, long *data_start, long *data_len, int *chans) { return wav_parse_marks(f, data_start, data_len, chans, NULL); }

/* The same, and the file's own markers if asked: the loop's start from its smpl chunk (what a DAW or Audacity writes for a
 * loop region) and its first two cue points (cue chunk), in sample frames; they usually sit after the data chunk, so the
 * whole file is walked. */
bool wav_parse_marks(FILE *f, long *data_start, long *data_len, int *chans, wav_marks *m) {
    uint8_t h[12], c[8], fmt[16], b[64]; /* (b: a smpl chunk's header and first loop, 60 bytes) */
    if (m) memset(m, 0, sizeof *m);
    if (fread(h, 1, 12, f) != 12 || memcmp(h, "RIFF", 4) || memcmp(h + 8, "WAVE", 4)) return false;
    bool fmt_ok = false, data_ok = false;
    int ch = 0;
    while (fread(c, 1, 8, f) == 8) {
        long size = (long)rd32(c + 4);
        if (m && !memcmp(c, "smpl", 4) && size >= 36 + 24) { /* the first loop's start */
            if (fread(b, 1, 36 + 24, f) != 36 + 24) break;
            if (rd32(b + 28) >= 1) m->loop = (long)rd32(b + 36 + 8);
            fseek(f, size + (size & 1) - (36 + 24), SEEK_CUR);
        } else if (m && !memcmp(c, "cue ", 4) && size >= 4) { /* the first two points, by sample offset */
            if (fread(b, 1, 4, f) != 4) break;
            const long n = (long)rd32(b);
            long read = 4;
            for (long i = 0; i < n && i < 2 && read + 24 <= size; i++, read += 24) {
                if (fread(b, 1, 24, f) != 24) break;
                m->cue[m->ncue++] = (long)rd32(b + 20);
            }
            if (m->ncue == 2 && m->cue[1] < m->cue[0]) { long t = m->cue[0]; m->cue[0] = m->cue[1], m->cue[1] = t; }
            fseek(f, size + (size & 1) - read, SEEK_CUR);
        } else
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
            data_ok = fmt_ok && *data_len >= frame;
            if (!m || size > avail) break; /* (no markers wanted, or a truncated file: nothing past the data) */
            fseek(f, *data_start + size + (size & 1), SEEK_SET);
        } else {
            fseek(f, size + (size & 1), SEEK_CUR);
        }
    }
    return data_ok;
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
static FILE *open_wav(const char *id, long *start, long *len, int *chans, bool quiet, wav_marks *m) {
    if (!id || !*id || is_missing(id)) return NULL;
    char path[384];
    snprintf(path, sizeof path, "%s/audio/%s.wav", G.game_dir, id);
    FILE *f = game_has(path + strlen(G.game_dir) + 1) ? fopen(path, "rb") : NULL;
    if (f && wav_parse_marks(f, start, len, chans, m)) {
        fseek(f, *start, SEEK_SET);
        return f;
    }
    if (f) fclose(f);
    if (!quiet) hal_log("audio %s missing or not PCM16 %d Hz; continuing silent", id, AUDIO_HZ);
    mark_missing(id);
    return NULL;
}

/* audio/<id>.spum: a stream kept as ADPCM, the music and the beds that were WAVs a third the size. "SPUM", the samples of each
 * stem, the sample a loop goes back to (a block's start), the stems (1 to MAX_STEMS) and 3 spare bytes, 32-bit little endian;
 * then, for each 28 samples, one 16-byte block of each stem in turn (tools/wav2vag.py --stream makes it from a WAV). */
static FILE *open_spum(const char *id, long *start, long *len, int *chans, long *samples, long *loop_sample, bool quiet) {
    if (!id || !*id || is_missing(id)) return NULL;
    char rel[160], path[384];
    snprintf(rel, sizeof rel, "audio/%s.spum", id);
    if (!game_has(rel)) return NULL;
    snprintf(path, sizeof path, "%s/%s", G.game_dir, rel);
    FILE *f = fopen(path, "rb");
    uint8_t h[16];
    if (f && fread(h, 1, 16, f) == 16 && !memcmp(h, "SPUM", 4) && h[12] >= 1 && h[12] <= MAX_STEMS) {
        const long n = (long)rd32(h + 4);
        const long blocks = (n + VAG_SAMPLES - 1) / VAG_SAMPLES;
        fseek(f, 0, SEEK_END);
        if (n > 0 && n < 3600L * AUDIO_HZ && ftell(f) >= 16 + blocks * h[12] * VAG_BYTES) {
            *chans = h[12], *samples = n, *start = 16, *len = n * 2L * h[12];
            long loop = (long)rd32(h + 8);
            *loop_sample = loop < n ? loop / VAG_SAMPLES * VAG_SAMPLES : 0; /* a jump lands on a block's start */
            fseek(f, 16, SEEK_SET);
            return f;
        }
    }
    if (f) fclose(f);
    if (!quiet) hal_log("audio %s is not an ADPCM stream; continuing silent", id);
    mark_missing(id);
    return NULL;
}

/* An ADPCM stream's state, ready to read from its first block */
static void adpcm_setup(stream *s, long samples, int chans) {
    s->adpcm = true, s->samples = samples;
    s->blk_next = 0, s->blk_at = VAG_SAMPLES; /* (nothing decoded yet) */
    memset(s->old, 0, sizeof s->old), memset(s->older, 0, sizeof s->older);
    s->rb = malloc((size_t)chans * VAG_BYTES * 16);
    s->rb_pos = s->rb_len = 0;
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
    free(s->rb);
    *s = (stream){0};
}

static void fade_out(stream *s, int ms) {
    for (int k = 0; k < MAX_STEMS; k++) ramp_to(&s->g[k], 0, ms);
    s->dying = true;
}

/* Opens a mono id into a slot, rising from silence to gain over ms (file I/O outside the lock, swap inside). */
static bool open_into(int slot, const char *id, bool loop, float gain, int ms, float pan) {
    long start = 0, len = 0, samples = 0, loop_sample = 0;
    int chans = 1;
    FILE *f = open_spum(id, &start, &len, &chans, &samples, &loop_sample, false);
    const bool adpcm = f != NULL;
    if (!f) f = open_wav(id, &start, &len, &chans, false, NULL);
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
        if (adpcm) adpcm_setup(&st[slot], samples, 1), st[slot].loop_at = loop_sample * 2;
        ramp_to(&st[slot].g[0], gain, ms);
        ramp_to(&st[slot].cut_l, pan > 0 ? pan : 0, 1), ramp_to(&st[slot].cut_r, pan < 0 ? -pan : 0, 1);
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
void audio_ambient(const char *id, int fade_ms) { audio_ambient_pan(id, fade_ms, 0); }

/* The same placed between the ears (pan -1 left .. 1 right); an ambience already playing is moved there too. */
void audio_ambient_pan(const char *id, int fade_ms, float pan) {
    pan = pan > 1 ? 1 : pan < -1 ? -1 : pan == pan ? pan : 0;
    hal_audio_lock();
    int keep = -1;
    for (int i = S_AMB0; i < S_AMB0 + NAMB; i++)
        if (id && st[i].f && !strcmp(st[i].id, id)) keep = i;
    for (int i = S_AMB0; i < S_AMB0 + NAMB; i++)
        if (i != keep) fade_out(&st[i], fade_ms);
    if (keep >= 0) { /* already here (maybe fading out after a quick back-and-forth): bring it back */
        ramp_to(&st[keep].g[0], 1, fade_ms);
        ramp_to(&st[keep].cut_l, pan > 0 ? pan : 0, fade_ms), ramp_to(&st[keep].cut_r, pan < 0 ? -pan : 0, fade_ms);
        st[keep].dying = false;
    }
    int slot = pick_slot(S_AMB0, NAMB);
    hal_audio_unlock();
    if (keep < 0 && id) open_into(slot, id, true, 1, fade_ms, pan);
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
    close_stream(&st[S_NEXT]);
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
/* A cue opened into `s` (which must be closed), its layers at silence, ready to rise to gains[k] over fade_ms
 * (set_gains): the stream's part of audio_music_start, outside the lock (file I/O). Returns its layer count, 0 if none. */
static int open_cue(stream *s, const char *cue, float loop_at_s, float bar_s) {
    long start = 0, len = 0, samples = 0, loop_sample = 0;
    int chans = 1;
    FILE *f = open_spum(cue, &start, &len, &chans, &samples, &loop_sample, false);
    const bool adpcm = f != NULL;
    wav_marks marks = {0};
    if (!f) f = open_wav(cue, &start, &len, &chans, false, &marks);
    if (!f) return 0;
    if (!(loop_at_s >= 0 && loop_at_s < 3600)) loop_at_s = 0; /* also NaN */
    if (!(bar_s > 0 && bar_s < 60)) bar_s = 0;
    long frame = 2L * chans, at = (long)(loop_at_s * AUDIO_HZ) * frame;
    /* the file's own markers serve when the game gave none: the loop from its smpl chunk, the bar between its first two cues */
    if (loop_at_s == 0 && marks.loop > 0) at = marks.loop * frame;
    if (bar_s == 0 && marks.ncue == 2 && marks.cue[1] > marks.cue[0] && marks.cue[1] - marks.cue[0] < 60L * AUDIO_HZ) bar_s = (float)(marks.cue[1] - marks.cue[0]) / AUDIO_HZ;
    *s = (stream){.f = f, .start = start, .len = len, .chans = chans, .loop = true,
                  .loop_at = at < len ? at : 0, .bar = (long)(bar_s * AUDIO_HZ) * frame};
    snprintf(s->id, sizeof s->id, "%s", cue);
    if (adpcm) { /* a loop goes back to a block's start: the file's own if the game gave none */
        adpcm_setup(s, samples, chans);
        long at2 = loop_at_s > 0 ? (long)(loop_at_s * AUDIO_HZ) / VAG_SAMPLES * VAG_SAMPLES : loop_sample;
        s->loop_at = at2 < samples ? at2 * 2L * chans : 0;
    }
    return chans;
}

static float next_gains[MAX_STEMS];
static int next_fade_ms;

int audio_music_start(const char *cue, float loop_at_s, float bar_s, const float *gains, int fade_ms) {
    stream fresh = {0};
    const int chans = open_cue(&fresh, cue, loop_at_s, bar_s);
    hal_audio_lock();
    stream *s = &st[S_MUS];
    close_stream(s);
    close_stream(&st[S_NEXT]); /* a song waiting for the bar line is no longer wanted */
    audio_music_clock_locked(chans ? 1 : 0); /* in the same swap: not one block of the old song counted */
    if (chans) {
        *s = fresh;
        for (int k = 0; k < chans; k++) ramp_to(&s->g[k], gains ? gains[k] : k == 0, fade_ms);
    }
    hal_audio_unlock();
    return chans;
}

/* The same, but the song starts on the next bar line of the one playing (its `bar`), as iMUSE's transitions did: the
 * new one is opened now and parked; the mixer swaps it in at the line, to the block. With no song playing, or one
 * with no bar, it starts now. */
int audio_music_queue(const char *cue, float loop_at_s, float bar_s, const float *gains, int fade_ms) {
    hal_audio_lock();
    const bool wait = st[S_MUS].f && st[S_MUS].bar && !st[S_MUS].dying;
    hal_audio_unlock();
    if (!wait) return audio_music_start(cue, loop_at_s, bar_s, gains, fade_ms);
    stream fresh = {0};
    const int chans = open_cue(&fresh, cue, loop_at_s, bar_s);
    if (!chans) return 0;
    fresh.parked = true;
    hal_audio_lock();
    close_stream(&st[S_NEXT]);
    st[S_NEXT] = fresh;
    for (int k = 0; k < MAX_STEMS; k++) next_gains[k] = gains ? gains[k] : k == 0;
    next_fade_ms = fade_ms;
    hal_audio_unlock();
    return chans;
}

bool audio_music_queued(void) {
    hal_audio_lock();
    const bool q = st[S_NEXT].f != NULL;
    hal_audio_unlock();
    return q;
}

/* Under the lock, in the mixer: the song playing crossed a bar line (or ended) and one waits: the swap. */
static void swap_in_next(void) {
    stream *s = &st[S_MUS], *n = &st[S_NEXT];
    close_stream(s);
    *s = *n;
    *n = (stream){0};
    s->parked = false;
    audio_music_clock_locked(1);
    for (int k = 0; k < s->chans; k++) ramp_to(&s->g[k], next_gains[k], next_fade_ms);
}

void audio_music_pan(float pan, int fade_ms) {
    pan = pan > 1 ? 1 : pan < -1 ? -1 : pan == pan ? pan : 0;
    hal_audio_lock();
    ramp_to(&st[S_MUS].cut_l, pan > 0 ? pan : 0, fade_ms), ramp_to(&st[S_MUS].cut_r, pan < 0 ? -pan : 0, fade_ms);
    hal_audio_unlock();
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
    open_into(slot, id, false, 1, 5, 0);
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

void audio_reverb(int room, float wet, float send_music, float send_ambient) {
    hal_audio_lock();
    if (room < 0) { /* let it ring out: the return fades, then the room goes */
        ramp_to(&rv_wet, 0, 200);
        rv_closing = reverb_on();
    } else {
        if (!reverb_on() || rv_closing || room != reverb_current()) { /* a new room starts silent */
            reverb_set(room);
            rv_wet = (ramp){0, 0, 0};
        }
        rv_closing = false;
        ramp_to(&rv_wet, wet, 100);
        rv_music = send_music < 0 ? 0 : send_music > 1 ? 1 : send_music;
        rv_amb = send_ambient < 0 ? 0 : send_ambient > 1 ? 1 : send_ambient;
    }
    hal_audio_unlock();
}

void audio_master(float gain, int fade_ms) {
    hal_audio_lock();
    ramp_to(&master, gain, fade_ms);
    hal_audio_unlock();
}

void audio_bus_set(int bus, float gain, float lowpass_hz, int fade_ms) { /* 0 music, 1 ambient, 2 sounds */
    const float a = lowpass_hz > 0 ? 1 - expf(-6.2831853f * lowpass_hz / AUDIO_HZ) : 1;
    hal_audio_lock();
    if (bus == 0) ramp_to(&bus_mus, gain, fade_ms), ramp_to(&mus_lp, a, fade_ms);
    else if (bus == 1) ramp_to(&bus_amb, gain, fade_ms), ramp_to(&amb_lp, a, fade_ms);
    else ramp_to(&bus_sfx, gain, fade_ms);
    hal_audio_unlock();
}

void audio_duck(float to, int attack_ms, int hold_ms, int release_ms) { /* the music dips to `to`, stays, comes back */
    hal_audio_lock();
    ramp_to(&duck_mus, to, attack_ms);
    duck_hold = (long)attack_ms * AUDIO_HZ / 1000 + (long)hold_ms * AUDIO_HZ / 1000;
    duck_release_ms = release_ms;
    hal_audio_unlock();
}

int audio_sfx_count(const char *id) { /* voices playing that sound now */
    clip *c = id ? clip_get(id) : NULL;
    if (!c) return 0;
    int n = 0;
    hal_audio_lock();
    for (int v = 0; v < SFX_VOICES; v++)
        if (sfx[v].pcm)
            for (int k = 0; k < c->count; k++)
                if (sfx[v].pcm == c->pcm[k] || (c->vag[k] && sfx[v].vag == c->vag[k])) n++;
    hal_audio_unlock();
    return n;
}

void audio_user(float gain) { /* the console's volume: a game's volume() is inside it; a game's start leaves it alone */
    hal_audio_lock();
    ramp_to(&user, gain < 0 ? 0 : gain > 1 ? 1 : gain, 60);
    hal_audio_unlock();
}

static int16_t *load_clip(const char *id, int *n, bool quiet) {
    long start = 0, len = 0;
    int chans = 1;
    FILE *f = open_wav(id, &start, &len, &chans, quiet, NULL);
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

/* audio/<id>.vag: "SPUV", then the clip's sample count and its loop's first and last sample (both 0: none), 32-bit
 * little endian, then its ADPCM blocks (tools/wav2vag.py makes it from a WAV). The blocks, malloc'd; NULL if it is not one. */
static uint8_t *load_vag(const char *id, int *n, int *loop_a, int *loop_b) {
    char path[384], rel[160];
    snprintf(rel, sizeof rel, "audio/%s.vag", id);
    if (!game_has(rel)) return NULL;
    snprintf(path, sizeof path, "%s/%s", G.game_dir, rel);
    FILE *f = fopen(path, "rb");
    uint8_t h[16], *blocks = NULL;
    if (f && fread(h, 1, 16, f) == 16 && !memcmp(h, "SPUV", 4)) {
        long count = rd32(h + 4);
        size_t bytes = (size_t)((count + VAG_SAMPLES - 1) / VAG_SAMPLES) * VAG_BYTES;
        if (count > 0 && count <= SFX_MAX_SAMPLES && (blocks = malloc(bytes)) && fread(blocks, 1, bytes, f) == bytes) {
            *n = (int)count, *loop_a = (int)rd32(h + 8), *loop_b = (int)rd32(h + 12);
            if (*loop_b > *n) *loop_b = *n;
        } else {
            free(blocks);
            blocks = NULL;
        }
    }
    if (f) fclose(f);
    if (!blocks) mark_missing(id);
    return blocks;
}

/* Variant k of a clip: audio/<id>.vag if there is one, else the WAV */
static bool load_variant(const char *id, clip *c, int k, bool quiet) {
    if (!is_missing(id) && (c->vag[k] = load_vag(id, &c->n[k], &c->loop_a[k], &c->loop_b[k]))) return true;
    return (c->pcm[k] = load_clip(id, &c->n[k], quiet)) != NULL;
}

static long variant_bytes(const clip *c, int k) {
    return c->vag[k] ? (long)((c->n[k] + VAG_SAMPLES - 1) / VAG_SAMPLES) * VAG_BYTES : (long)c->n[k] * (long)sizeof(int16_t);
}

static bool voice_on(const sfx_voice *x, const clip *c, int k) { /* a voice reading variant k of c */
    return x->pcm && (c->vag[k] ? x->vag == c->vag[k] : x->pcm == c->pcm[k]);
}

static bool playing(const clip *c) { /* under the lock: a voice still reading one of its variants */
    for (int v = 0; v < SFX_VOICES; v++)
        for (int k = 0; k < c->count; k++)
            if (voice_on(&sfx[v], c, k)) return true;
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
        for (int k = 0; k < cache[old].count; k++) free(cache[old].pcm[k]), free(cache[old].vag[k]);
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
    if (!load_variant(id, c, 0, false)) return NULL;
    c->count = 1;
    char v[40];
    for (int k = 2; k <= 4; k++) { /* optional variants: SFX_X_2..SFX_X_4 */
        snprintf(v, sizeof v, "%s_%d", id, k);
        if (!load_variant(v, c, c->count, true)) break;
        c->count++;
    }
    for (int k = 0; k < c->count; k++) c->bytes += variant_bytes(c, k);
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

static sfx_voice *by_handle(int h) { /* under the lock: the voice still playing that sound, or NULL */
    int v = (h & 15) - 1;
    if (v < 0 || v >= SFX_VOICES || !sfx[v].pcm || (sfx[v].gen & 0x7FFF) != (h >> 4)) return NULL;
    return &sfx[v];
}

/* From RAM, a variant different from the last one, so repeats never sound identical; at a pitch (1 as recorded),
 * looping or once. Returns a handle for audio_sfx_adjust / audio_sfx_stop, 0 if nothing plays. */
int audio_sfx_play(const char *id, float gain, float pitch, bool loop) {
    return audio_sfx_play_pan(id, gain, pitch, loop, 0);
}

/* The same placed between the ears: pan -1 (all left) to 1 (all right). Each ear's gain is 1 at the centre and falls to
 * 0 on the far side, so a centred sound is what a mono one always was. */
static void set_pan(sfx_voice *x, float pan) {
    pan = pan > 1 ? 1 : pan < -1 ? -1 : pan == pan ? pan : 0; /* (NaN: the centre) */
    x->side_l = pan > 0 ? -pan : 0, x->side_r = pan < 0 ? pan : 0;
}

int audio_sfx_play_pan(const char *id, float gain, float pitch, bool loop, float pan) {
    return audio_sfx_play_opts(id, &(sfx_opts){.gain = gain, .pitch = pitch, .loop = loop, .pan = pan});
}

/* A time in seconds, as the samples a sample-by-sample step of the envelope takes (at least one) */
static float per_sample(float seconds) { return seconds * AUDIO_HZ < 1 ? 1 : seconds * AUDIO_HZ; }

/* An envelope on a voice: seconds of attack, decay to the sustain level (0..1), and release after a stop */
static void set_envelope(sfx_voice *x, float attack, float decay, float sustain_level, float release) {
    const float sustain = sustain_level < 0 ? 0 : sustain_level > 1 ? 1 : sustain_level == sustain_level ? sustain_level : 1;
    x->env = true, x->stage = attack > 0 ? ENV_ATTACK : ENV_DECAY, x->level = attack > 0 ? 0 : 1;
    x->sustain = sustain, x->rise = 1 / per_sample(attack);
    x->fall_d = powf(0.001f, 1 / per_sample(decay)), x->fall_r = powf(0.001f, 1 / per_sample(release));
    if (decay <= 0) x->fall_d = 0; /* no decay: straight to the sustain level */
    if (release <= 0) x->fall_r = 0; /* no release: a stop is a stop */
}

int audio_sfx_play_opts(const char *id, const sfx_opts *o) {
    if (!id) return 0;
    clip *c = clip_get(id);
    if (!c) return 0;
    int k = c->count > 1 ? rand() % (c->count - 1) : 0;
    if (c->count > 1 && k >= c->last) k++;
    c->last = k;
    hal_audio_lock();
    /* (an ADPCM clip's blocks stand in for pcm: the voice is on while it has some, and reads blk) */
    int h = audio_voice_start_locked(c->vag[k] ? (const int16_t *)c->vag[k] : c->pcm[k], c->n[k], o->gain, o->pitch, o->loop, o->wait, 0, 0);
    sfx_voice *x = by_handle(h);
    if (x) {
        set_pan(x, o->pan);
        x->rev = o->reverb > 1 ? 1 : o->reverb > 0 ? o->reverb : 0;
        if (c->vag[k]) x->vag = c->vag[k], x->pcm = x->blk, x->vbase = -VAG_SAMPLES * 4;
        /* a loop between two points of the clip: both given, inside it, in order (else its file's, if it has them) */
        int from = o->loop_start, to = o->loop_end;
        if (!(to > from && from >= 0 && to <= c->n[k])) from = c->loop_a[k], to = c->loop_b[k];
        if (c->vag[k]) from = from / VAG_SAMPLES * VAG_SAMPLES; /* a jump lands on a block's start */
        if (o->loop && to > from && from >= 0 && to <= c->n[k]) x->loop_from = from, x->end = to;
        if (o->env) set_envelope(x, o->attack, o->decay, o->sustain, o->release);
    }
    hal_audio_unlock();
    return h;
}

/* A voice starts pcm, `wait` samples into the next block mixed (the audio lock held). Returns its handle. */
int audio_voice_start_locked(const int16_t *pcm, int n, float gain, float pitch, bool loop, int wait, float send_d,
                             float send_r) {
    pitch = pitch > 0.0625f && pitch < 16 ? pitch : pitch >= 16 ? 16 : 0.0625f; /* NaN too: the lowest */
    int v = -1;
    for (int i = 0; i < SFX_VOICES && v < 0; i++) /* a free voice */
        if (!sfx[i].pcm) v = i;
    if (v < 0) /* else steal one: the one-shot closest to its end, else voice 0 */
        for (int i = 0; i < SFX_VOICES; i++)
            if (!sfx[i].loop && (v < 0 || sfx[i].n - sfx[i].pos < sfx[v].n - sfx[v].pos)) v = i;
    if (v < 0) v = 0;
    uint16_t gen = (uint16_t)(sfx[v].gen + 1);
    sfx[v] = (sfx_voice){.pcm = pcm, .n = n, .end = n, .gain = gain < 0 ? 0 : gain > 1 ? 1 : gain, .pitch = pitch,
                         .loop = loop, .gen = gen, .wait = wait < 0 ? 0 : wait, .send_d = send_d, .send_r = send_r};
    return (gen & 0x7FFF) << 4 | (v + 1); /* never 0 */
}

void audio_sfx(const char *id, float gain) { audio_sfx_play(id, gain, 1, false); }

void audio_sfx_pan(int h, float pan) {
    hal_audio_lock();
    sfx_voice *x = by_handle(h);
    if (x) set_pan(x, pan);
    hal_audio_unlock();
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

void audio_sfx_stop(int h) { /* a voice with an envelope lets go: its release, then it ends; any other stops at once */
    hal_audio_lock();
    sfx_voice *x = by_handle(h);
    if (x && x->env && x->fall_r > 0) x->stage = ENV_RELEASE;
    else audio_voice_stop_locked(h);
    hal_audio_unlock();
}

/* ------------------------------------------------------------------ the sequencer's voices (midi.c) */
/* A note of a song: a sample's ADPCM blocks played at a pitch (1: as recorded) with its own envelope and place, in one of the
 * voices kept for songs. Called by the sequencer from inside audio_mix (the audio lock is held). Returns the voice, or -1. */
int audio_midi_start(const midi_note *n, uint16_t *gen_out) {
    int v = -1, oldest = -1;
    for (int i = SFX_VOICES; i < NVOICES && v < 0; i++)
        if (!sfx[i].pcm) v = i;
    if (v < 0) { /* the one that has been going longest, a released one first */
        for (int i = SFX_VOICES; i < NVOICES; i++) {
            if (oldest < 0 || (sfx[i].stage == ENV_RELEASE) > (sfx[oldest].stage == ENV_RELEASE) ||
                ((sfx[i].stage == ENV_RELEASE) == (sfx[oldest].stage == ENV_RELEASE) && sfx[i].level < sfx[oldest].level))
                oldest = i;
        }
        v = oldest;
    }
    const uint16_t gen = (uint16_t)(sfx[v].gen + 1);
    sfx[v] = (sfx_voice){.pcm = (const int16_t *)n->vag, .n = n->samples, .end = n->samples, .gain = n->gain > 1 ? 1 : n->gain,
                         .pitch = n->pitch > 16 ? 16 : n->pitch < 0.0625f ? 0.0625f : n->pitch, .loop = n->loop_to > n->loop_from,
                         .gen = gen, .wait = n->wait < 0 ? 0 : n->wait};
    sfx_voice *x = &sfx[v];
    x->vag = n->vag, x->pcm = x->blk, x->vbase = -VAG_SAMPLES * 4;
    if (x->loop) x->loop_from = n->loop_from / VAG_SAMPLES * VAG_SAMPLES, x->end = n->loop_to;
    set_pan(x, n->pan);
    x->rev = n->reverb;
    set_envelope(x, n->attack, n->decay, n->sustain, n->release > 0.004f ? n->release : 0.004f);
    if (gen_out) *gen_out = gen;
    return v;
}

static sfx_voice *midi_voice(int v, uint16_t gen) { return v >= SFX_VOICES && v < NVOICES && sfx[v].pcm && sfx[v].gen == gen ? &sfx[v] : NULL; }
bool audio_midi_alive(int v, uint16_t gen) { return midi_voice(v, gen) != NULL; }
void audio_midi_release(int v, uint16_t gen) {
    sfx_voice *x = midi_voice(v, gen);
    if (x && x->stage != ENV_RELEASE) x->stage = ENV_RELEASE;
}
void audio_midi_stop(int v, uint16_t gen) {
    sfx_voice *x = midi_voice(v, gen);
    if (x) x->pcm = NULL;
}
void audio_midi_stop_all(void) { for (int i = SFX_VOICES; i < NVOICES; i++) sfx[i].pcm = NULL; }
void audio_midi_set(int v, uint16_t gen, float pitch, float gain) {
    sfx_voice *x = midi_voice(v, gen);
    if (!x) return;
    if (pitch > 0) x->pitch = pitch > 16 ? 16 : pitch < 0.0625f ? 0.0625f : pitch;
    if (gain >= 0) x->gain = gain > 1 ? 1 : gain;
}

/* A clip a studio track plays: loaded now (the game's thread) and never evicted while pinned. Its first variant
 * only, so a pattern sounds the same every time round. */
bool audio_clip_pin(const char *id, const int16_t **pcm, int *n) {
    clip *c = id ? clip_get(id) : NULL;
    if (!c || c->vag[0]) return false; /* (a studio track plays raw samples) */
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
                if (voice_on(&sfx[v], c, k)) sfx[v].pcm = NULL;
        if (c->pcm[0]) studio_replace_locked(c->pcm[0], pcm, n);
        pins = c->pins;
        for (int k = 0; k < c->count; k++) free(c->pcm[k]), free(c->vag[k]);
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

static bool music_sounds(void) { return mus_src == 1 ? st[S_MUS].f != NULL : mus_src == 2 ? mod_playing() : mus_src == 3 && midi_playing(); }

double audio_music_bar(void) { /* the playing song's bar in seconds (as music() was told, or the WAV's own cues); 0: none */
    hal_audio_lock();
    const stream *s = &st[S_MUS];
    const double bar = s->f && s->bar > 0 && s->chans > 0 ? (double)s->bar / (2.0 * s->chans * AUDIO_HZ) : 0;
    hal_audio_unlock();
    return bar;
}

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

static float *modb; /* a module's chunk before the music bus (slow memory: the console's internal RAM is counted) */

void audio_reset(void) {
    if (!modb) modb = hal_realloc_slow(NULL, CHUNK * sizeof *modb);
    studio_reset(); /* its tracks point into the cache freed below */
    hal_audio_lock();
    for (int i = 0; i < NSTREAMS; i++) close_stream(&st[i]);
    memset(sfx, 0, sizeof sfx);
    bus_amb = bus_mus = amb_lp = master = bus_sfx = mus_lp = duck_mus = (ramp){1, 1, 0};
    mus_lp_state = 0, duck_hold = 0;
    rv_wet = (ramp){0, 0, 0}, rv_music = rv_amb = 0, rv_closing = false;
    reverb_set(-1);
    lp_state = lp_l = lp_r = 0;
    hal_audio_unlock();
    psg_reset();
    mod_reset();
    midi_reset();
    for (int i = 0; i < ncache; i++)
        for (int k = 0; k < cache[i].count; k++) free(cache[i].pcm[k]), free(cache[i].vag[k]);
    ncache = 0;
    cache_bytes = 0;
    paused = false;
    nmissing = 0;
}

void audio_force_missing(const char *id) { mark_missing(id); }

/* ------------------------------------------------------------------ audio thread */
/* The next block of every stem of an ADPCM stream decoded (the file is read a handful of blocks at a time); false at the file's end. */
static bool adpcm_next(stream *s) {
    const int bytes = s->chans * VAG_BYTES;
    if (s->rb_pos + bytes > s->rb_len) {
        size_t n = fread(s->rb, 1, (size_t)bytes * 16, s->f);
        s->rb_len = (int)(n / (size_t)bytes * (size_t)bytes), s->rb_pos = 0;
        if (s->rb_len < bytes) return false;
    }
    for (int c = 0; c < s->chans; c++) vag_block(s->rb + s->rb_pos + c * VAG_BYTES, &s->old[c], &s->older[c], s->blk[c]);
    s->rb_pos += bytes;
    s->blk_next++, s->blk_at = 0;
    return true;
}

/* Reads up to m frames of a stream into buf (looping), returns how many it produced. */
static int stream_read(stream *s, int16_t *buf, int m) {
    int got = 0;
    long frame = 2L * s->chans;
    if (s->adpcm) {
        while (s->f && got < m) {
            const long left = s->samples - s->pos / frame;
            if (left <= 0) { /* the end: round again from the loop's block, or finish */
                if (!s->loop) { close_stream(s); break; }
                const long at = s->loop_at / frame;
                if (fseek(s->f, s->start + at / VAG_SAMPLES * s->chans * VAG_BYTES, SEEK_SET)) { close_stream(s); break; }
                s->pos = s->loop_at, s->blk_next = (int)(at / VAG_SAMPLES), s->blk_at = VAG_SAMPLES, s->rb_pos = s->rb_len = 0;
                memset(s->old, 0, sizeof s->old), memset(s->older, 0, sizeof s->older); /* (the encoder made that block without prediction) */
                continue;
            }
            if (s->blk_at >= VAG_SAMPLES && !adpcm_next(s)) { /* unreadable: never spin */
                if (!s->loop) { close_stream(s); break; }
                s->pos = s->samples * frame;
                if (s->loop_at >= s->pos) { close_stream(s); break; }
                continue;
            }
            int n = VAG_SAMPLES - s->blk_at;
            if (n > m - got) n = m - got;
            if (n > left) n = (int)left;
            for (int i = 0; i < n; i++)
                for (int c = 0; c < s->chans; c++) buf[(got + i) * s->chans + c] = s->blk[c][s->blk_at + i];
            s->blk_at += n, got += n, s->pos += frame * n;
        }
        return got;
    }
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

/* The mix, mono (every platform's audio_mix) or stereo, left and right alternating (audio_mix_stereo). Everything is
 * mixed once into acc; a panned voice adds to dl and dr how far below that each ear is, which is nothing for all else. */
static void mix_core(int16_t *out, int n, bool stereo) {
    static float acc[CHUNK], amb[CHUNK]; /* single caller (audio callback/task): keep them off its small stack */
    static float sd[CHUNK], sr[CHUNK];   /* what the studio's tracks send to its echo and its reverb */
    static float dl[CHUNK], dr[CHUNK];   /* the panned voices' difference from acc, left and right (both <= 0) */
    static float aml[CHUNK], amr[CHUNK]; /* the same for the ambience beds, before their lowpass */
    static float gv[CHUNK];              /* what is sent into the game's reverb */
    static float mus[CHUNK];             /* the music, before its bus (lowpass, duck) */
    static int16_t buf[CHUNK * MAX_STEMS];
    for (int off = 0; off < n; off += CHUNK) {
        int m = n - off < CHUNK ? n - off : CHUNK;
        memset(acc, 0, sizeof acc);
        memset(amb, 0, sizeof amb);
        memset(sd, 0, sizeof sd);
        memset(sr, 0, sizeof sr);
        memset(dl, 0, sizeof dl);
        memset(aml, 0, sizeof aml), memset(amr, 0, sizeof amr);
        memset(dr, 0, sizeof dr);
        memset(gv, 0, sizeof gv);
        memset(mus, 0, sizeof mus);
        bool mus_open = false;
        const bool rv = reverb_on();
        bool amb_open = false; /* an ambience bed is playing: the bus has something to carry */
        for (int c = 0; c < NSTREAMS && !paused; c++) { /* pause freezes the world; menu clicks still play */
            stream *s = &st[c];
            if (!s->f || s->parked) continue;
            if (s->dying && silent(s)) { close_stream(s); continue; }
            if (c < S_AMB0 + NAMB) amb_open = true;
            if (c == S_MUS) mus_open = true;
            float *dst = c < S_AMB0 + NAMB ? amb : c == S_MUS ? mus : acc;
            ramp b = c == S_MUS ? bus_mus : (ramp){1, 1, 0};
            long p0 = s->pos, bar = s->bar;
            int ch = s->chans; /* read first: stream_read closes (and zeroes) a one-shot that ends */
            int got = stream_read(s, buf, m);
            if (s->armed && bar && (s->pos / bar != p0 / bar || s->pos < p0)) apply_pending(s); /* <= 1 chunk late */
            if (c == S_MUS && st[S_NEXT].f && ((bar && (s->pos / bar != p0 / bar || s->pos < p0)) || !s->f)) swap_in_next(); /* the song waiting, at the line */
            const float send = !rv ? 0 : c == S_MUS ? rv_music : c < S_AMB0 + NAMB ? rv_amb : 0;
            float *pl = c < S_AMB0 + NAMB ? aml : dl, *pr = c < S_AMB0 + NAMB ? amr : dr;
            const bool panned = s->cut_l.v != 0 || s->cut_l.target != 0 || s->cut_r.v != 0 || s->cut_r.target != 0;
            for (int i = 0; i < got; i++) {
                float x = 0;
                for (int k = 0; k < ch; k++) x += buf[i * ch + k] * ramp_next(&s->g[k]);
                x *= ramp_next(&b);
                dst[i] += x;
                if (send > 0) gv[i] += x * send;
                if (panned) pl[i] -= x * ramp_next(&s->cut_l), pr[i] -= x * ramp_next(&s->cut_r);
            }
        }
        /* with no bed playing, its lowpass empty and the three ramps at rest, the loop below adds nothing and moves nothing */
        const bool amb_rest = !amb_open && lp_state == 0 && lp_l == 0 && lp_r == 0 && amb_lp.v == amb_lp.target &&
                              bus_amb.v == bus_amb.target && bus_mus.v == bus_mus.target;
        for (int i = 0; i < m && !paused && !amb_rest; i++) { /* ambience bus: gain then a ramped one-pole lowpass (1 = open) */
            const float a = ramp_next(&amb_lp), g = ramp_next(&bus_amb);
            lp_state += a * (amb[i] * g - lp_state);
            acc[i] += lp_state;
            if (aml[i] != 0 || amr[i] != 0 || lp_l != 0 || lp_r != 0) { /* a panned bed: its difference through the same filter */
                lp_l += a * (aml[i] * g - lp_l), lp_r += a * (amr[i] * g - lp_r);
                dl[i] += lp_l, dr[i] += lp_r;
            }
            ramp_next(&bus_mus);
        }
        if (!paused && music_sounds()) mus_clock += m; /* (before a module may end) */
        if (!paused && mod_playing() && modb) { /* a module goes through the music bus like a WAV: the bus's gain, the duck, the lowpass */
            memset(modb, 0, (size_t)m * sizeof *modb);
            mod_mix(modb, m);
            const float g = bus_mus.v;
            for (int i = 0; i < m; i++) mus[i] += modb[i] * g;
            mus_open = true;
        }
        /* the music bus: its duck (down, held, back) and lowpass; nothing to do while both rest and no music plays */
        if (duck_hold > 0 && !paused) {
            duck_hold -= m;
            if (duck_hold <= 0) ramp_to(&duck_mus, 1, duck_release_ms);
        }
        const bool mus_rest = !mus_open && mus_lp_state == 0 && mus_lp.v == mus_lp.target && duck_mus.v == duck_mus.target;
        for (int i = 0; i < m && !paused && !mus_rest; i++) {
            const float a = ramp_next(&mus_lp), d = ramp_next(&duck_mus);
            mus_lp_state += a * (mus[i] * d - mus_lp_state);
            acc[i] += mus_lp_state;
        }
        const float sg = bus_sfx.v; /* the sounds' bus this chunk (stepped below, a chunk at a time: 3 ms) */
        for (int i = 0; i < m; i++) ramp_next(&bus_sfx);
        if (!paused) studio_tick(m); /* the steps falling in this block start their voices, to the sample */
        if (!paused) midi_tick(m);   /* the song's notes falling in it, the same */
        for (int v = 0; v < NVOICES; v++) {
            sfx_voice *x = &sfx[v];
            int i0 = x->wait < m ? x->wait : m;
            x->wait -= i0;
            const float vgain = v < SFX_VOICES ? x->gain * sg : x->gain; /* the game's sounds through their bus */
            if (x->pitch == 1 && !x->env && !x->vag) /* as recorded: sample after sample, round again if it loops */
                for (int i = i0; i < m && x->pcm;) {
                    int k = x->end - x->pos < m - i ? x->end - x->pos : m - i;
                    for (int j = 0; j < k; j++) acc[i + j] += x->pcm[x->pos + j] * vgain;
                    if (x->send_d > 0 || x->send_r > 0)
                        for (int j = 0; j < k; j++) {
                            float y = x->pcm[x->pos + j] * vgain;
                            sd[i + j] += y * x->send_d, sr[i + j] += y * x->send_r;
                        }
                    if (x->side_l != 0 || x->side_r != 0)
                        for (int j = 0; j < k; j++) {
                            float y = x->pcm[x->pos + j] * vgain;
                            dl[i + j] += y * x->side_l, dr[i + j] += y * x->side_r;
                        }
                    if (rv && x->rev > 0)
                        for (int j = 0; j < k; j++) gv[i + j] += x->pcm[x->pos + j] * vgain * x->rev;
                    x->pos += k, i += k;
                    if (x->pos >= x->end) x->pos = x->loop ? x->loop_from : 0, x->pcm = x->loop ? x->pcm : NULL;
                }
            else { /* faster or slower: between two samples, by the fraction */
                uint32_t step = (uint32_t)(x->pitch * 65536.0f);
                /* what the loop does not change, and the buses nothing goes into: acc is a float pointer like these, so
                 * through the voice every one of them would be loaded again each sample, and a bus at 0 added to anyway */
                const float gain = vgain, send_d = x->send_d, send_r = x->send_r, side_l = x->side_l, side_r = x->side_r, rev = x->rev;
                const bool sends = send_d != 0 || send_r != 0, pan = side_l != 0 || side_r != 0, wet = rv && rev != 0;
                for (int i = i0; i < m && x->pcm; i++) {
                    int a = x->pos, b = a + 1 < x->end ? a + 1 : (x->loop && !x->vag ? x->loop_from : a);
                    int sa = x->vag ? vag_get(x, a) : x->pcm[a], sb = x->vag ? (b == a ? sa : vag_get(x, b)) : x->pcm[b];
                    float y = (sa + (float)(sb - sa) * (float)x->frac / 65536.0f) * gain;
                    if (x->env) y *= env_next(x); /* (a release that ends the voice leaves this sample its last) */
                    acc[i] += y;
                    if (sends) sd[i] += y * send_d, sr[i] += y * send_r;
                    if (pan) dl[i] += y * side_l, dr[i] += y * side_r;
                    if (wet) gv[i] += y * rev;
                    x->frac += step;
                    x->pos += (int)(x->frac >> 16), x->frac &= 0xFFFF;
                    if (x->pos >= x->end) {
                        if (x->loop) x->pos = x->loop_from + (x->pos - x->end) % (x->end - x->loop_from);
                        else x->pcm = NULL;
                    }
                }
            }
        }
        if (!paused) studio_mix(acc, sd, sr, m); /* the synth tracks' voices */
        psg_mix(acc, m);
        if (!paused) studio_fx(acc, sd, sr, m); /* its echo and reverb, then Lo-fi GBA over everything */
        if (rv && !paused) { /* the room's return, left and right apart, with the panned voices' difference */
            static float rl[CHUNK], rr[CHUNK];
            memset(rl, 0, sizeof rl), memset(rr, 0, sizeof rr);
            reverb_mix(gv, rl, rr, m, 1);
            for (int i = 0; i < m; i++) {
                const float w = ramp_next(&rv_wet);
                dl[i] += rl[i] * w, dr[i] += rr[i] * w;
            }
            if (rv_closing && rv_wet.v == 0) reverb_set(-1), rv_closing = false;
        }
        for (int i = 0; i < m; i++) {
            const float g = ramp_next(&master) * ramp_next(&user);
            if (stereo) out[2 * (off + i)] = limit((acc[i] + dl[i]) * g), out[2 * (off + i) + 1] = limit((acc[i] + dr[i]) * g);
            else out[off + i] = limit((acc[i] + 0.5f * (dl[i] + dr[i])) * g); /* (mono: panned sounds at half the gap) */
        }
    }
    mark_clock = mus_clock, mark_us = hal_micros(), mark_n = n;
    studio_mark(n);
}

/* Called by the platform's audio callback/task with the audio lock held. */
void audio_mix(int16_t *out, int n) { mix_core(out, n, false); }
void audio_mix_stereo(int16_t *out, int n) { mix_core(out, n, true); }
