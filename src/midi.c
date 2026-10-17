/* A song as notes: a Standard MIDI File played by a bank of samples, as the PlayStation did with its SEQ and VAB (and the
 * Saturn with its sequencer and the sound chip's RAM). The notes are the MIDI file's (audio/<id>.mid); the sounds are the
 * bank's (audio/<bank>.bank, tools/mkbank.py makes it from WAVs or a SoundFont): ADPCM samples with the key range they
 * serve, the note they were recorded at, a loop, and an envelope. The notes play in the voices kept for songs (audio.c), the
 * ones a sound effect does not take, so the same envelope, pan and reverb send as any other sound; they are a third of the
 * memory of PCM and decoded as they play.
 *
 * Time is worked out when the file is read: every event gets its place in samples, tempo changes included, so the audio
 * thread only walks a sorted list. A note that falls inside a block of samples starts that many samples into it.
 *
 * What it understands: notes (with velocity), program changes, volume (7), pan (10), expression (11), sustain pedal (64), reverb
 * send (91), all notes off (123), pitch bend (+-2 semitones), tempo, and the channel 10 drum kit. A loop goes back to the
 * marker "loopStart" (or controller 111, as RPG Maker's) and goes round at the marker "loopEnd" or the end of the song. */
#include <math.h>
#include <stdlib.h>
#include <string.h>

#include "bp.h"

#define MAX_EVENTS 60000
#define MAX_ACTIVE 48

typedef struct {
    uint32_t t; /* the sample the event falls on */
    uint8_t status, d1, d2;
} event;

typedef struct {
    uint8_t lo_key, hi_key, lo_vel, hi_vel, root, pan, sustain, volume;
    uint16_t sample, attack_ms, decay_ms, release_ms;
    int16_t fine; /* cents */
} region;

typedef struct {
    uint32_t offset, samples, loop_from, loop_to; /* in the bank's data; a loop of 0, 0: none */
} bank_sample;

typedef struct {
    uint8_t *data;       /* the whole file */
    const uint8_t *blocks;
    bank_sample *sample;
    region *region;
    struct { uint16_t first, count; } program[129]; /* 0..127 melodic, 128 the drum kit */
    int n_samples, n_regions;
} bank;

typedef struct {
    int voice;
    uint16_t gen;
    uint8_t chan, key;
    bool held;  /* its key is up but the pedal is down */
    float base; /* its pitch in semitones from its sample's, before the channel's bend */
} active_note;

static struct {
    bool on, loop;
    event *ev;
    int n_ev, next;
    uint32_t pos, length, loop_from, loop_to; /* in samples */
    bank *bk;
    float level, pan;
    struct { uint8_t prog, vol, expr, pan, rev; int16_t bend; bool pedal; } ch[16];
    active_note act[MAX_ACTIVE];
    int n_act;
} S;

static uint32_t be32(const uint8_t *p) { return (uint32_t)p[0] << 24 | p[1] << 16 | p[2] << 8 | p[3]; }
static uint16_t le16(const uint8_t *p) { return (uint16_t)(p[0] | p[1] << 8); }
static uint32_t le32(const uint8_t *p) { return p[0] | p[1] << 8 | p[2] << 16 | (uint32_t)p[3] << 24; }

/* ------------------------------------------------------------------ the bank */

static void bank_free(bank *b) {
    if (!b) return;
    free(b->data), free(b->sample), free(b->region), free(b);
}

/* "SBNK", u16 version (1), u16 samples, u16 regions, u16 reserved; 129 programs of (u16 first region, u16 count); the samples
 * (u32 offset, samples, loop from, loop to: 16 bytes each); the regions (24 bytes each: lo key, hi key, lo vel, hi vel, root,
 * pan 0..127, sustain 0..255, volume 0..255, u16 sample, attack ms, decay ms, release ms, i16 fine cents, 2 spare); then the
 * ADPCM blocks the samples' offsets point into. */
static bank *bank_load(const char *path) {
    FILE *f = fopen(path, "rb");
    if (!f) return NULL;
    fseek(f, 0, SEEK_END);
    long size = ftell(f);
    fseek(f, 0, SEEK_SET);
    bank *b = calloc(1, sizeof *b);
    if (!b || size < 12 || size > 8L * 1024 * 1024 || !(b->data = malloc((size_t)size)) || fread(b->data, 1, (size_t)size, f) != (size_t)size) {
        fclose(f);
        bank_free(b);
        return NULL;
    }
    fclose(f);
    const uint8_t *d = b->data;
    b->n_samples = le16(d + 6), b->n_regions = le16(d + 8);
    const long tables = 12 + 129 * 4, ends = tables + (long)b->n_samples * 16 + (long)b->n_regions * 24;
    if (memcmp(d, "SBNK", 4) || le16(d + 4) != 1 || ends > size) {
        bank_free(b);
        return NULL;
    }
    for (int i = 0; i < 129; i++) b->program[i].first = le16(d + 12 + i * 4), b->program[i].count = le16(d + 14 + i * 4);
    b->sample = calloc((size_t)b->n_samples + 1, sizeof *b->sample);
    b->region = calloc((size_t)b->n_regions + 1, sizeof *b->region);
    if (!b->sample || !b->region) {
        bank_free(b);
        return NULL;
    }
    b->blocks = d + ends;
    const long data_len = size - ends;
    for (int i = 0; i < b->n_samples; i++) {
        const uint8_t *e = d + tables + i * 16;
        b->sample[i] = (bank_sample){le32(e), le32(e + 4), le32(e + 8), le32(e + 12)};
        bank_sample *sm = &b->sample[i];
        const uint64_t blocks = ((uint64_t)sm->samples + 27) / 28; /* (64 bits: long is 32 on the console) */
        if (sm->samples == 0 || sm->samples > (uint32_t)INT32_MAX || (uint64_t)sm->offset + blocks * 16 > (uint64_t)data_len) {
            bank_free(b); /* a sample that runs past the file: no bank */
            return NULL;
        }
        if (sm->loop_to > sm->samples) sm->loop_to = sm->samples;
        if (sm->loop_from >= sm->loop_to) sm->loop_from = sm->loop_to = 0; /* no loop */
    }
    for (int i = 0; i < b->n_regions; i++) {
        const uint8_t *e = d + tables + (long)b->n_samples * 16 + i * 24;
        b->region[i] = (region){.lo_key = e[0], .hi_key = e[1], .lo_vel = e[2], .hi_vel = e[3], .root = e[4], .pan = e[5],
                                .sustain = e[6], .volume = e[7], .sample = le16(e + 8), .attack_ms = le16(e + 10),
                                .decay_ms = le16(e + 12), .release_ms = le16(e + 14), .fine = (int16_t)le16(e + 16)};
        if (b->region[i].sample >= b->n_samples) {
            bank_free(b);
            return NULL;
        }
    }
    for (int i = 0; i < 129; i++)
        if ((int)b->program[i].first + b->program[i].count > b->n_regions) b->program[i].count = 0;
    return b;
}

/* ------------------------------------------------------------------ the file */

typedef struct { uint32_t tick, seq; uint8_t status, d1, d2; int marker; } raw_event; /* marker: 1 loopStart, 2 loopEnd */

/* by tick; at one tick a note's end before any start (a key struck again on the beat it ended), then as the file has them */
static int by_tick(const void *a, const void *b) {
    const raw_event *x = a, *y = b;
    if (x->tick != y->tick) return x->tick < y->tick ? -1 : 1;
    const int xo = (x->status & 0xF0) == 0x80, yo = (y->status & 0xF0) == 0x80;
    if (xo != yo) return xo ? -1 : 1;
    return x->seq < y->seq ? -1 : x->seq > y->seq;
}

static uint32_t varlen(const uint8_t **p, const uint8_t *end) {
    uint32_t v = 0;
    for (int i = 0; i < 4 && *p < end; i++) {
        const uint8_t c = *(*p)++;
        v = v << 7 | (c & 0x7F);
        if (!(c & 0x80)) break;
    }
    return v;
}

/* The file's tracks merged by tick; tempo changes turned into samples; loop markers found. false: not a usable SMF. */
static bool smf_load(const char *path, event **ev_out, int *n_out, uint32_t *length, uint32_t *loop_from, uint32_t *loop_to) {
    FILE *f = fopen(path, "rb");
    if (!f) return false;
    fseek(f, 0, SEEK_END);
    long size = ftell(f);
    fseek(f, 0, SEEK_SET);
    uint8_t *d = size >= 14 && size < 2L * 1024 * 1024 ? malloc((size_t)size) : NULL; /* (the header is 14 bytes) */
    if (!d || fread(d, 1, (size_t)size, f) != (size_t)size || memcmp(d, "MThd", 4)) {
        fclose(f);
        free(d);
        return false;
    }
    fclose(f);
    const uint16_t ntracks = (uint16_t)(d[10] << 8 | d[11]), division = (uint16_t)(d[12] << 8 | d[13]);
    const uint32_t head_len = be32(d + 4);
    if (division & 0x8000 || !division || head_len > (uint32_t)size - 8) { /* SMPTE time: not played; a header past the file */
        free(d);
        return false;
    }
    raw_event *raw = malloc(sizeof *raw * MAX_EVENTS);
    int n = 0;
    uint32_t last_tick = 0;
    struct { uint32_t tick, usec; } tempo[256];
    int ntempo = 0;
    const uint8_t *p = d + 8 + head_len, *end = d + size; /* (lengths from the file are checked against what is left before use) */
    for (int t = 0; t < ntracks && p + 8 <= end && raw; t++) {
        const uint32_t len = be32(p + 4);
        const uint8_t *q = p + 8, *te = len > (size_t)(end - q) ? end : q + len;
        p = te;
        uint32_t tick = 0;
        uint8_t running = 0;
        while (q < te && n < MAX_EVENTS - 2) {
            tick += varlen(&q, te);
            if (q >= te) break;
            uint8_t st = *q;
            if (st < 0x80) st = running; else q++;
            if (st == 0xFF) { /* a meta event */
                if (q >= te) break;
                const uint8_t kind = *q++;
                const uint32_t mlen = varlen(&q, te);
                if (mlen > (size_t)(te - q)) break;
                if (kind == 0x51 && mlen == 3 && ntempo < 256) tempo[ntempo].tick = tick, tempo[ntempo++].usec = (uint32_t)(q[0] << 16 | q[1] << 8 | q[2]);
                else if ((kind == 0x06 || kind == 0x07) && mlen >= 9 && !memcmp(q, "loopStart", 9)) raw[n] = (raw_event){tick, (uint32_t)n, 0, 0, 0, 1}, n++;
                else if ((kind == 0x06 || kind == 0x07) && mlen >= 7 && !memcmp(q, "loopEnd", 7)) raw[n] = (raw_event){tick, (uint32_t)n, 0, 0, 0, 2}, n++;
                else if (kind == 0x2F) last_tick = tick > last_tick ? tick : last_tick;
                q += mlen;
                continue;
            }
            if (st == 0xF0 || st == 0xF7) { /* system exclusive: skipped */
                const uint32_t slen = varlen(&q, te);
                if (slen > (size_t)(te - q)) break;
                q += slen;
                continue;
            }
            if (st < 0x80) break;
            running = st;
            const uint8_t type = st & 0xF0;
            const int need = (type == 0xC0 || type == 0xD0) ? 1 : 2;
            if (need > te - q) break;
            const uint8_t d1 = q[0], d2 = need == 2 ? q[1] : 0;
            q += need;
            if (type == 0x90 && d2 == 0) raw[n] = (raw_event){tick, (uint32_t)n, (uint8_t)(0x80 | (st & 15)), d1, 0, 0}, n++; /* a note on at velocity 0 is an off */
            else if (type == 0x90 || type == 0x80 || type == 0xB0 || type == 0xC0 || type == 0xE0) raw[n] = (raw_event){tick, (uint32_t)n, st, d1, d2, 0}, n++;
            if (tick > last_tick) last_tick = tick;
        }
    }
    free(d);
    if (!raw || n == 0) {
        free(raw);
        return false;
    }
    qsort(raw, (size_t)n, sizeof *raw, by_tick);
    /* ticks to samples: the tempo in force between one change and the next (500000 microseconds a beat until told) */
    event *ev = malloc(sizeof *ev * (size_t)n);
    if (!ev) {
        free(raw);
        return false;
    }
    /* tempo list sorted by tick */
    for (int i = 1; i < ntempo; i++)
        for (int j = i; j > 0 && tempo[j].tick < tempo[j - 1].tick; j--) {
            const uint32_t a = tempo[j].tick, b = tempo[j].usec;
            tempo[j] = tempo[j - 1], tempo[j - 1].tick = a, tempo[j - 1].usec = b;
        }
    int count = 0;
    int ti = 0;
    double usec = 500000, at_s = 0; /* the sample count at the last tempo change, in seconds */
    uint32_t at_tick = 0;
    *loop_from = 0, *loop_to = 0;
    bool have_from = false, have_to = false;
    for (int i = 0; i < n; i++) {
        while (ti < ntempo && tempo[ti].tick <= raw[i].tick) {
            at_s += (double)(tempo[ti].tick - at_tick) * usec / 1e6 / division;
            at_tick = tempo[ti].tick, usec = tempo[ti].usec;
            ti++;
        }
        const double secs = at_s + (double)(raw[i].tick - at_tick) * usec / 1e6 / division;
        const uint32_t t = (uint32_t)(secs * AUDIO_HZ);
        if (raw[i].marker == 1 && !have_from) *loop_from = t, have_from = true;
        else if (raw[i].marker == 2 && !have_to) *loop_to = t, have_to = true;
        else if (raw[i].status) {
            if ((raw[i].status & 0xF0) == 0xB0 && raw[i].d1 == 111 && !have_from) *loop_from = t, have_from = true; /* RPG Maker's loop point */
            ev[count++] = (event){t, raw[i].status, raw[i].d1, raw[i].d2};
        }
    }
    free(raw);
    /* the song's length: where its last event or its end-of-track falls */
    double end_s = at_s + (double)(last_tick - at_tick) * usec / 1e6 / division;
    *length = (uint32_t)(end_s * AUDIO_HZ);
    if (count && ev[count - 1].t > *length) *length = ev[count - 1].t;
    if (!have_to || *loop_to > *length || *loop_to <= *loop_from) *loop_to = *length;
    *ev_out = ev;
    *n_out = count;
    if (count == 0) free(ev);
    return count > 0;
}

/* ------------------------------------------------------------------ playing */

static void channels_reset(void) {
    for (int c = 0; c < 16; c++) S.ch[c] = (typeof(S.ch[0])){.prog = 0, .vol = 100, .expr = 127, .pan = 64, .rev = 0, .bend = 0, .pedal = false};
    S.n_act = 0;
}

static void reset_locked(void) {
    audio_midi_stop_all(); /* the voices play the bank's memory: none may be left sounding when it is freed */
    free(S.ev);
    bank_free(S.bk);
    memset(&S, 0, sizeof S);
}

/* (the mixer walks the song and plays the bank's memory: both go only with the audio lock held) */
void midi_reset(void) {
    hal_audio_lock();
    reset_locked();
    hal_audio_unlock();
}

bool midi_playing(void) { return S.on; }
void midi_pan(float pan) { S.pan = pan > 1 ? 1 : pan < -1 ? -1 : pan == pan ? pan : 0; }

/* The song and its bank are read here, off the audio thread; swapped in under the lock. */
bool midi_play(const char *mid, const char *bank_id, bool loop, float gain, int fade_ms) {
    (void)fade_ms;
    char path[384];
    snprintf(path, sizeof path, "%s/audio/%s.mid", G.game_dir, mid);
    event *ev = NULL;
    int n = 0;
    uint32_t length = 0, lf = 0, lt = 0;
    if (!smf_load(path, &ev, &n, &length, &lf, &lt)) {
        hal_log("audio %s.mid is missing or not a Standard MIDI File", mid);
        return false;
    }
    snprintf(path, sizeof path, "%s/audio/%s.bank", G.game_dir, bank_id);
    bank *bk = bank_load(path);
    if (!bk) {
        hal_log("audio %s.bank is missing or not a bank of samples (tools/mkbank.py)", bank_id);
        free(ev);
        return false;
    }
    hal_audio_lock();
    reset_locked();
    channels_reset();
    S.ev = ev, S.n_ev = n, S.bk = bk, S.length = length, S.loop_from = lf, S.loop_to = lt, S.loop = loop;
    S.level = gain < 0 ? 0 : gain > 1 ? 1 : gain;
    S.on = true;
    audio_music_clock_locked(3);
    hal_audio_unlock();
    return true;
}

static void release_all(bool at_once) {
    for (int i = 0; i < S.n_act; i++) (at_once ? audio_midi_stop : audio_midi_release)(S.act[i].voice, S.act[i].gen);
    S.n_act = 0;
}

void midi_stop(int fade_ms) {
    (void)fade_ms;
    hal_audio_lock();
    if (S.on) {
        release_all(false); /* the notes let go over their release, not cut */
        S.on = false;
    }
    audio_music_clock_locked(0);
    hal_audio_unlock();
}

static float semitone(float n) { return exp2f(n / 12.0f); }

static void note_on(int chan, int key, int vel, int wait) {
    const bank *b = S.bk;
    const bool drums = chan == 9;
    const int prog = drums ? 128 : S.ch[chan].prog;
    for (int r = 0; r < b->program[prog].count; r++) {
        const region *g = &b->region[b->program[prog].first + r];
        if (key < g->lo_key || key > g->hi_key || vel < g->lo_vel || vel > g->hi_vel) continue;
        const bank_sample *sm = &b->sample[g->sample];
        const float v = (float)vel / 127.0f;
        const float pan = ((float)g->pan - 64.0f) / 64.0f * 0.6f + ((float)S.ch[chan].pan - 64.0f) / 64.0f + S.pan;
        const midi_note n = {
            .vag = b->blocks + sm->offset, .samples = (int)sm->samples, .loop_from = (int)sm->loop_from, .loop_to = (int)sm->loop_to,
            .wait = wait, .gain = 0.45f * v * v * ((float)S.ch[chan].vol / 127.0f) * ((float)S.ch[chan].expr / 127.0f) * ((float)g->volume / 255.0f) * S.level,
            .pitch = semitone((float)(key - g->root) + (float)g->fine / 100.0f + (float)S.ch[chan].bend / 8192.0f * 2.0f),
            .pan = pan > 1 ? 1 : pan < -1 ? -1 : pan, .reverb = (float)S.ch[chan].rev / 127.0f,
            .attack = (float)g->attack_ms / 1000.0f, .decay = (float)g->decay_ms / 1000.0f, .sustain = (float)g->sustain / 255.0f,
            .release = (float)g->release_ms / 1000.0f};
        uint16_t gen = 0;
        const int voice = audio_midi_start(&n, &gen);
        if (voice < 0) continue;
        /* the voice the note took might have been one of ours playing: forget it */
        for (int i = 0; i < S.n_act; i++)
            if (S.act[i].voice == voice) S.act[i] = S.act[--S.n_act];
        if (S.n_act < MAX_ACTIVE) S.act[S.n_act++] = (active_note){voice, gen, (uint8_t)chan, (uint8_t)key, false, (float)(key - g->root) + (float)g->fine / 100.0f};
    }
}

static void note_off(int chan, int key) {
    for (int i = 0; i < S.n_act; i++) {
        if (S.act[i].chan != chan || S.act[i].key != key || S.act[i].held) continue;
        if (S.ch[chan].pedal) S.act[i].held = true;
        else audio_midi_release(S.act[i].voice, S.act[i].gen), S.act[i] = S.act[--S.n_act], i--;
    }
}

static void pedal_up(int chan) {
    for (int i = 0; i < S.n_act; i++)
        if (S.act[i].chan == chan && S.act[i].held) audio_midi_release(S.act[i].voice, S.act[i].gen), S.act[i] = S.act[--S.n_act], i--;
}

static void event_do(const event *e, int wait) {
    const int chan = e->status & 15;
    switch (e->status & 0xF0) {
    case 0x90: note_on(chan, e->d1, e->d2, wait); break;
    case 0x80: note_off(chan, e->d1); break;
    case 0xC0: S.ch[chan].prog = e->d1 & 127; break;
    case 0xE0: { /* pitch bend: 14 bits, centre 8192; the notes sounding follow it */
        S.ch[chan].bend = (int16_t)(((e->d2 << 7) | e->d1) - 8192);
        for (int i = 0; i < S.n_act; i++)
            if (S.act[i].chan == chan) audio_midi_set(S.act[i].voice, S.act[i].gen, semitone(S.act[i].base + (float)S.ch[chan].bend / 8192.0f * 2.0f), -1);
        break;
    }
    case 0xB0:
        switch (e->d1) {
        case 7: S.ch[chan].vol = e->d2; break;
        case 10: S.ch[chan].pan = e->d2; break;
        case 11: S.ch[chan].expr = e->d2; break;
        case 91: S.ch[chan].rev = e->d2; break;
        case 64:
            if (e->d2 >= 64) S.ch[chan].pedal = true;
            else if (S.ch[chan].pedal) S.ch[chan].pedal = false, pedal_up(chan);
            break;
        case 120: case 123: /* all sound off, all notes off */
            for (int i = 0; i < S.n_act; i++)
                if (S.act[i].chan == chan) (e->d1 == 120 ? audio_midi_stop : audio_midi_release)(S.act[i].voice, S.act[i].gen), S.act[i] = S.act[--S.n_act], i--;
            break;
        default: break;
        }
        break;
    default: break;
    }
}

/* Called inside audio_mix: the events of the next m samples start, each at its own sample. */
void midi_tick(int m) {
    if (!S.on) return;
    /* the notes that ended by themselves are forgotten */
    for (int i = 0; i < S.n_act; i++)
        if (!audio_midi_alive(S.act[i].voice, S.act[i].gen)) S.act[i] = S.act[--S.n_act], i--;
    while (S.next < S.n_ev && S.ev[S.next].t < S.pos + (uint32_t)m) {
        const event *e = &S.ev[S.next++];
        event_do(e, e->t > S.pos ? (int)(e->t - S.pos) : 0);
    }
    S.pos += (uint32_t)m;
    if (S.pos >= S.loop_to) {
        if (!S.loop) {
            if (S.pos >= S.length + (uint32_t)AUDIO_HZ) S.on = false; /* a second for the last notes to ring */
            return;
        }
        /* round again from the loop's start: the events from there on come back */
        const uint32_t over = S.pos - S.loop_to;
        release_all(false);
        S.next = 0;
        while (S.next < S.n_ev && S.ev[S.next].t < S.loop_from) S.next++;
        S.pos = S.loop_from + over;
    }
}
