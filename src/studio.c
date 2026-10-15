/* The studio: a step sequencer that runs in the audio thread, so every step lands on its sample at any tempo. A
 * game's ticks come 60 a second: steps played from them move by up to 17 ms, and only tempos of 900/n BPM come out
 * even. Tracks play clips (WAVs or made sounds, pinned in the cache while a track holds them) with a velocity per
 * step; odd steps come late by the swing, as an MPC's; tracks of one choke group cut each other, as an 808's closed
 * hat cuts its open one. A synth track plays notes instead, on its own voice (studio_synth.c): a note per step,
 * an accent, a slide into the next one, as a TB-303's pattern. The game sets everything under the audio lock;
 * studio_pos() says what the player hears now, past the queue to the speaker, as music_time() does. */
#include <string.h>

#include "bp.h"
#include "studio_synth.h"

typedef struct {
    bool pending, accent, legato;
    int at, note, gate; /* at: its sample in the block; note 0: let the held note go */
} event;

typedef struct {
    const int16_t *pcm;
    int n;
    float gain, pitch;
    float vel[STUDIO_STEPS];
    int choke, voice; /* voice: the handle of its last hit, which a hit of its choke group stops */
    bool synth;       /* a synth track: notes on its voice instead of a clip */
    sv_patch patch;
    sv_voice sv;
    uint8_t note[STUDIO_STEPS], flags[STUDIO_STEPS]; /* note 0 is a rest; flags: STUDIO_ACCENT, STUDIO_SLIDE */
    event ev;
} track;

static track T[STUDIO_TRACKS];
static bool on;
static float bpm = 120, swing = 50;
static int len = 16;
static int up;            /* the next step to sound */
static double grid;       /* its sample on the straight grid; the swing is added when it starts */
static long now;          /* samples mixed so far */
#define HEARD 8
typedef struct {
    long at;
    int step;
} stamp;
static stamp heard[HEARD]; /* the last steps started, for studio_pos */
static int nheard;
static long mark_now;
static uint32_t mark_us;
static int mark_n;

static float clampf(float v, float lo, float hi) { return v > lo ? (v < hi ? v : hi) : lo; } /* NaN: lo */

static double step_samples(void) { return AUDIO_HZ * 60.0 / (bpm * 4); }

static void cut(int choke) {
    for (int j = 0; j < STUDIO_TRACKS; j++)
        if (T[j].choke == choke && T[j].voice) audio_voice_stop_locked(T[j].voice), T[j].voice = 0;
}

/* ponytail: a choke cuts the other voice at the start of the block, up to 11 ms before the hit that chokes it;
 * a voice that ends exactly on the hit's sample needs a stop time in sfx_voice */
static void start(track *t, float vel, int wait) {
    if (t->choke) cut(t->choke);
    t->voice = audio_voice_start_locked(t->pcm, t->n, t->gain * vel, t->pitch, false, wait);
}

/* A synth track's step: a note (sliding in if the step before slides into it, held on if it slides into the next),
 * or a rest that lets a held note go. The voice takes it at its sample, in studio_mix. */
static void fire_note(track *t, int s, int wait) {
    int prev = (s - 1 + len) % len, next = (s + 1) % len, n = t->note[s];
    if (n) {
        bool slide = (t->flags[s] & STUDIO_SLIDE) && t->note[next];
        int gate = slide ? -1 : (int)(step_samples() * 0.55); /* a 303's gate: a little over half the step */
        t->ev = (event){true, (t->flags[s] & STUDIO_ACCENT) != 0, (t->flags[prev] & STUDIO_SLIDE) && t->note[prev],
                        wait, n, gate};
    } else if (t->sv.gate < 0) {
        t->ev = (event){true, false, false, wait, 0, 0};
    }
}

static void fire(int s, int wait) {
    for (int i = 0; i < STUDIO_TRACKS; i++) {
        if (T[i].synth) fire_note(&T[i], s, wait);
        else if (T[i].pcm && T[i].vel[s] > 0) start(&T[i], T[i].vel[s], wait);
    }
    heard[nheard % HEARD].at = now + wait, heard[nheard % HEARD].step = s;
    nheard++;
}

void studio_tick(int m) {
    if (on) {
        double sl = step_samples();
        for (;;) {
            double at = grid + (up % 2 ? (swing - 50) / 50.0 * sl : 0);
            if (at >= (double)(now + m)) break;
            fire(up, at > (double)now ? (int)(at - (double)now) : 0);
            grid += sl;
            up = (up + 1) % len;
        }
    }
    now += m;
}

void studio_mark(int n) { mark_now = now, mark_us = hal_micros(), mark_n = n; }

void studio_mix(float *acc, int m) {
    for (int i = 0; i < STUDIO_TRACKS; i++) {
        track *t = &T[i];
        if (!t->synth) continue;
        event *e = &t->ev;
        if (!e->pending) {
            sv_render(&t->sv, &t->patch, acc, 0, m);
            continue;
        }
        int at = e->at < m ? e->at : m - 1;
        sv_render(&t->sv, &t->patch, acc, 0, at);
        if (e->note) sv_note(&t->sv, &t->patch, e->note, e->accent, e->legato, e->gate);
        else sv_release(&t->sv);
        e->pending = false;
        sv_render(&t->sv, &t->patch, acc, at, m);
    }
}

void studio_replace_locked(const int16_t *old, const int16_t *pcm, int n) {
    for (int i = 0; i < STUDIO_TRACKS; i++)
        if (T[i].pcm == old) T[i].pcm = pcm, T[i].n = n;
}

void studio_reset(void) {
    hal_audio_lock();
    memset(T, 0, sizeof T);
    for (int i = 0; i < STUDIO_TRACKS; i++) T[i].gain = 1, T[i].pitch = 1, sv_defaults(&T[i].patch);
    on = false, bpm = 120, swing = 50, len = 16, up = 0, nheard = 0;
    hal_audio_unlock();
}

void studio_tempo(float b, float s) {
    hal_audio_lock();
    bpm = clampf(b, 30, 300);
    if (s >= 0) swing = clampf(s, 50, 75);
    hal_audio_unlock();
}

void studio_length(int steps) {
    hal_audio_lock();
    len = steps < 1 ? 1 : steps > STUDIO_STEPS ? STUDIO_STEPS : steps;
    up %= len;
    hal_audio_unlock();
}

/* Run on the game's thread: pinning may load the clip from the card. A negative gain, pitch or choke keeps it. */
bool studio_track(int i, const char *sound, float gain, float pitch, int choke) {
    if (i < 0 || i >= STUDIO_TRACKS) return false;
    const int16_t *pcm = NULL;
    int n = 0;
    if (sound && !audio_clip_pin(sound, &pcm, &n)) return false;
    hal_audio_lock();
    track *t = &T[i];
    const int16_t *old = sound ? t->pcm : NULL;
    if (sound) t->pcm = pcm, t->n = n, t->voice = 0, t->synth = false;
    if (gain >= 0) t->gain = clampf(gain, 0, 1);
    if (pitch > 0) t->pitch = clampf(pitch, 0.0625f, 16);
    if (choke >= 0) t->choke = choke;
    hal_audio_unlock();
    if (old) audio_clip_unpin(old);
    return true;
}

/* Track i becomes a synth track, its sound that patch. A clip it held is let go. */
void studio_synth(int i, const sv_patch *p) {
    if (i < 0 || i >= STUDIO_TRACKS) return;
    hal_audio_lock();
    track *t = &T[i];
    const int16_t *old = t->synth ? NULL : t->pcm;
    t->synth = true, t->pcm = NULL, t->patch = *p;
    hal_audio_unlock();
    if (old) audio_clip_unpin(old);
}

bool studio_synth_get(int i, sv_patch *p) {
    if (i < 0 || i >= STUDIO_TRACKS) return false;
    hal_audio_lock();
    bool s = T[i].synth;
    *p = T[i].patch;
    hal_audio_unlock();
    return s;
}

void studio_notes(int i, const uint8_t *notes, const uint8_t *flags, int n) {
    if (i < 0 || i >= STUDIO_TRACKS) return;
    hal_audio_lock();
    for (int s = 0; s < STUDIO_STEPS; s++) {
        T[i].note[s] = s < n && notes[s] < 128 ? notes[s] : 0;
        T[i].flags[s] = s < n ? flags[s] : 0;
    }
    hal_audio_unlock();
}

/* A note played by hand on a synth track (0 lets it go): at once, held a little over half a step. */
void studio_note(int i, int note, bool accent) {
    if (i < 0 || i >= STUDIO_TRACKS) return;
    hal_audio_lock();
    track *t = &T[i];
    if (t->synth && note > 0 && note < 128) sv_note(&t->sv, &t->patch, note, accent, false, (int)(step_samples() * 0.55));
    else if (t->synth) sv_release(&t->sv);
    hal_audio_unlock();
}

void studio_steps(int i, const float *vel, int n) {
    if (i < 0 || i >= STUDIO_TRACKS) return;
    hal_audio_lock();
    for (int s = 0; s < STUDIO_STEPS; s++) T[i].vel[s] = s < n ? clampf(vel[s], 0, 1) : 0;
    hal_audio_unlock();
}

void studio_play(int step) {
    hal_audio_lock();
    on = true, up = (step % len + len) % len, grid = (double)now; /* its first step opens the next block */
    nheard = 0;
    hal_audio_unlock();
}

void studio_stop(void) {
    hal_audio_lock();
    on = false;
    hal_audio_unlock();
}

bool studio_playing(void) {
    hal_audio_lock();
    bool o = on;
    hal_audio_unlock();
    return o;
}

void studio_hit(int i, float vel) {
    if (i < 0 || i >= STUDIO_TRACKS) return;
    hal_audio_lock();
    if (T[i].pcm) start(&T[i], clampf(vel, 0, 1), 0);
    hal_audio_unlock();
}

bool studio_pos(int *step, float *frac) {
    hal_audio_lock();
    bool o = on;
    long c = mark_now;
    uint32_t us = mark_us;
    int n = mark_n, count = nheard;
    stamp h[HEARD];
    memcpy(h, heard, sizeof h);
    double sl = step_samples();
    hal_audio_unlock();
    if (!o || !count) return false;
    int lat = hal_audio_latency();
    double t = (double)c;
    if (lat >= 0 && c > 0) { /* the block mixed last starts after the queue; by the clock since it was mixed */
        double e = (double)(uint32_t)(hal_micros() - us) * (AUDIO_HZ / 1e6);
        t += (e < n ? e : n) - n - lat;
    }
    for (int k = 0; k < HEARD && k < count; k++) { /* the newest step already heard */
        int j = (count - 1 - k) % HEARD;
        if ((double)h[j].at <= t) {
            *step = h[j].step;
            *frac = (float)((t - (double)h[j].at) / sl);
            return true;
        }
    }
    return false;
}
