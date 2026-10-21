/* Music from trackers, as GBA games had theirs: ProTracker modules (.mod, made with MilkyTracker, OpenMPT,
 * ProTracker...) rendered by pocketmod (third_party), and FastTracker II and Scream Tracker 3 modules (.xm, .s3m:
 * instruments with envelopes, more channels) rendered by IBXM (third_party, Martin Cameron). This file loads one,
 * loops it, and mixes it with the rest of the sound (audio_mix, through the music bus like a WAV: bus("music") and
 * duck() reach it). A module from a downloaded game is untrusted: both players check every offset against the
 * file's size, and the file is capped here. IBXM's memory (the samples as 16-bit, the patterns, the replay) is asked
 * for in slow memory (pinyol_calloc_slow, below).
 * A bar is sixteen lines (four beats of four, as most modules are written): a module asked for with at = "bar"
 * waits, loaded, for the bar line of the one playing (mod_queue), and a stop at the bar plays to the line and fades
 * there (mod_stop_at_bar), as a theme ends on a button. */
#if defined(__GNUC__)
#pragma GCC diagnostic push
#pragma GCC diagnostic ignored "-Wsign-compare"
#pragma GCC diagnostic ignored "-Wunused-parameter"
#endif
#define POCKETMOD_IMPLEMENTATION
#include "pocketmod.h"
#if defined(__GNUC__)
#pragma GCC diagnostic pop
#endif

#include <stdlib.h>
#include <string.h>

#include "bp.h"
#include "ibxm.h"

#define MOD_MAX_BYTES (4 << 20)
#define MOD_LEVEL 20000.0f /* full scale of the render (-1..1) in the mixer's units: under the effects */
#define XM_LEVEL (MOD_LEVEL / 32768.0f) /* IBXM renders in 16-bit units */
#define MOD_BAR_LINES 16   /* ponytail: 4/4 at four lines a beat; a `bar` in lines when a game writes in 3/4 */

void *pinyol_calloc_slow(size_t n, size_t size) { /* IBXM's calloc and malloc (ibxm.c, PINYOL_SLOW_ALLOC) */
    void *p = hal_realloc_slow(NULL, n * size);
    if (p) memset(p, 0, n * size);
    return p;
}
void *pinyol_malloc_slow(size_t size) { return hal_realloc_slow(NULL, size); }

enum { KIND_NONE, KIND_MOD, KIND_XM };

typedef struct { /* an XM or S3M under way: IBXM renders a tick (a line's share) at a time into mix, read out by frames */
    struct module *module;
    struct replay *replay;
    int *mix, cnt, pos; /* frames the last tick gave, and the next to take */
} xm_t;

typedef struct {
    int kind;
    pocketmod_context *pm; /* KIND_MOD: the context (slow memory), playing its samples straight from the file */
    uint8_t *bytes;
    xm_t xm;               /* KIND_XM */
} song_t;

static song_t song, next_song; /* playing, and waiting for the bar line */
static song_t garbage;         /* what the audio thread let go at a swap, freed on the next call from the game */
static bool playing, queued, stop_at_bar;
static float gain, next_gain, fade_step, level; /* level fades to 0 at fade_step per sample after mod_stop */
static int bar_fade_ms;

static void let_go(song_t *s) { /* the game's thread, no lock */
    if (s->kind == KIND_XM) {
        if (s->xm.replay) dispose_replay(s->xm.replay);
        if (s->xm.module) dispose_module(s->xm.module);
        free(s->xm.mix);
    }
    free(s->pm);
    free(s->bytes);
    memset(s, 0, sizeof *s);
}

static void take_out(void) { let_go(&garbage); } /* the audio thread is done with it */

static bool is_xm(const uint8_t *data, long len) {
    return (len > 17 && !memcmp(data, "Extended Module:", 16)) || (len > 48 && !memcmp(data + 44, "SCRM", 4));
}

static bool load(const char *path, song_t *out) { /* into out (a scratch: nothing plays from it until it is swapped in) */
    long len = 0;
    uint8_t *data = (uint8_t *)read_file(path, &len);
    if (!data) return false;
    if (len > MOD_MAX_BYTES) {
        hal_log("music %s: too big a module (%ld KB)", path, len / 1024);
        free(data);
        return false;
    }
    memset(out, 0, sizeof *out);
    if (is_xm(data, len)) {
        char msg[64] = "";
        struct data d = {(char *)data, (int)len};
        out->xm.module = module_load(&d, msg); /* copies what it needs: the file goes */
        free(data);
        if (out->xm.module) out->xm.replay = new_replay(out->xm.module, AUDIO_HZ, 0);
        if (out->xm.replay) out->xm.mix = pinyol_calloc_slow((size_t)calculate_mix_buf_len(AUDIO_HZ), sizeof(int));
        if (!out->xm.mix) {
            hal_log("music %s: not a module that can be played (%s)", path, msg[0] ? msg : "no memory");
            let_go(out);
            return false;
        }
        out->kind = KIND_XM;
        return true;
    }
    /* pocketmod's interpolation reads up to 2 bytes past a sample, so past the file for the last one: zeros there */
    uint8_t *padded = realloc(data, (size_t)len + 8);
    if (!padded) {
        free(data);
        return false;
    }
    data = padded;
    memset(data + len, 0, 8);
    out->pm = hal_realloc_slow(NULL, sizeof *out->pm);
    if (!out->pm || !pocketmod_init(out->pm, data, (int)len, AUDIO_HZ)) {
        hal_log("music %s: not a module that can be played", path);
        free(out->pm), out->pm = NULL;
        free(data);
        return false;
    }
    out->kind = KIND_MOD, out->bytes = data;
    return true;
}

bool mod_play(const char *path, float g) {
    take_out();
    song_t fresh;
    if (!load(path, &fresh)) return false;
    hal_audio_lock();
    song_t old = song, old_next = next_song;
    song = fresh, playing = true, gain = g, level = 1, fade_step = 0;
    queued = false, stop_at_bar = false;
    memset(&next_song, 0, sizeof next_song);
    audio_music_clock_locked(2);
    hal_audio_unlock();
    let_go(&old), let_go(&old_next);
    return true;
}

bool mod_queue(const char *path, float g) {
    if (!playing) return mod_play(path, g);
    take_out();
    song_t fresh;
    if (!load(path, &fresh)) return false;
    hal_audio_lock();
    song_t old_next = next_song;
    next_song = fresh, next_gain = g, queued = true, stop_at_bar = false;
    hal_audio_unlock();
    let_go(&old_next);
    return true;
}

static void drop_queued_locked(song_t *old_next) {
    *old_next = next_song;
    memset(&next_song, 0, sizeof next_song);
    queued = false, stop_at_bar = false;
}

void mod_stop(int fade_ms) {
    song_t old_next;
    take_out();
    hal_audio_lock();
    fade_step = fade_ms > 0 ? 1000.0f / ((float)fade_ms * AUDIO_HZ) : 1;
    drop_queued_locked(&old_next);
    hal_audio_unlock();
    let_go(&old_next);
}

void mod_stop_at_bar(int fade_ms) {
    song_t old_next;
    take_out();
    hal_audio_lock();
    drop_queued_locked(&old_next);
    stop_at_bar = playing, bar_fade_ms = fade_ms;
    hal_audio_unlock();
    let_go(&old_next);
}

bool mod_playing(void) { return playing; }
bool mod_queued(void) { return queued; }

/* Where a song is, in lines from its start: a pattern's lines (64 in a .mod; an XM's or S3M's may differ, counted as
 * if 1024 so a new pattern always begins a bar) */
static int lines_in(const song_t *s) {
    if (s->kind == KIND_MOD) return s->pm->pattern * 64 + (s->pm->line < 0 ? 0 : s->pm->line);
    if (s->kind == KIND_XM) return replay_get_sequence_pos(s->xm.replay) * 1024 + replay_get_row(s->xm.replay);
    return 0;
}

bool mod_position(int *bar, int *beat, float *frac) {
    if (!playing || fade_step > 0) return false; /* (a module fading out after music() is gone, as a WAV is) */
    hal_audio_lock();
    const int line = lines_in(&song);
    float in_line = 0;
    if (song.kind == KIND_MOD) {
        const pocketmod_context *c = song.pm;
        in_line = ((float)c->tick + c->sample / c->samples_per_tick) / (float)(c->ticks_per_line > 0 ? c->ticks_per_line : 1);
    } else if (song.xm.cnt > 0) {
        in_line = (float)song.xm.pos / (float)song.xm.cnt; /* ponytail: a tick taken as a line (true at speed 1) */
    }
    hal_audio_unlock();
    const int l = song.kind == KIND_XM ? line % 1024 : line;
    *bar = (song.kind == KIND_XM ? line / 1024 * 4 : 0) + l / MOD_BAR_LINES + 1;
    *beat = l % MOD_BAR_LINES / 4 + 1;
    *frac = ((float)(l % 4) + (in_line < 0 ? 0 : in_line > 1 ? 1 : in_line)) / 4;
    return true;
}

void mod_reset(void) {
    hal_audio_lock();
    song_t old = song, old_next = next_song;
    playing = false, queued = false, stop_at_bar = false;
    memset(&song, 0, sizeof song), memset(&next_song, 0, sizeof next_song);
    hal_audio_unlock();
    let_go(&old), let_go(&old_next);
    take_out();
}

/* IBXM: n frames into acc (mono: the two sides averaged), a tick rendered whenever the last one is used up */
static void render_xm(xm_t *x, float *acc, int n, float k) {
    for (int i = 0; i < n; i++) {
        if (x->pos >= x->cnt) {
            x->cnt = replay_get_audio(x->replay, x->mix, 0);
            x->pos = 0;
            if (x->cnt <= 0) return;
        }
        acc[i] += (float)(x->mix[x->pos * 2] + x->mix[x->pos * 2 + 1]) * 0.5f * k;
        x->pos++;
    }
}

/* The audio thread, lock held: m <= 256 samples of the song into acc. A swap or a stop asked for at the bar lands
 * at most one render (a chunk, 12 ms) after the line. */
void mod_mix(float *acc, int m) {
    static float buf[256][2];
    if (!playing || m > 256) return;
    for (int done = 0; done < m && playing;) {
        const int before = lines_in(&song);
        int got;
        if (song.kind == KIND_XM) {
            got = m - done;
            float tmp[256];
            memset(tmp, 0, (size_t)got * sizeof *tmp);
            render_xm(&song.xm, tmp, got, gain * XM_LEVEL);
            for (int i = 0; i < got; i++) {
                acc[done + i] += tmp[i] * level;
                if (fade_step > 0 && (level -= fade_step) <= 0) {
                    level = 0, playing = false;
                    break;
                }
            }
        } else {
            got = pocketmod_render(song.pm, buf[0], (int)((m - done) * sizeof buf[0])) / (int)sizeof buf[0];
            if (got <= 0) break; /* it stops at each new pattern: go on from there */
            for (int i = 0; i < got; i++) {
                acc[done + i] += (buf[i][0] + buf[i][1]) * 0.5f * gain * level * MOD_LEVEL;
                if (fade_step > 0 && (level -= fade_step) <= 0) {
                    level = 0, playing = false;
                    break;
                }
            }
        }
        done += got;
        const int after = lines_in(&song);
        if (playing && (queued || stop_at_bar) && (after / MOD_BAR_LINES != before / MOD_BAR_LINES || after < before)) {
            if (queued) { /* the song waiting takes over; what played is kept until the game's thread frees it */
                if (garbage.kind == KIND_NONE) garbage = song;
                song = next_song, gain = next_gain, level = 1, fade_step = 0;
                memset(&next_song, 0, sizeof next_song), queued = false;
                audio_music_clock_locked(2);
            } else {
                fade_step = bar_fade_ms > 0 ? 1000.0f / ((float)bar_fade_ms * AUDIO_HZ) : 1;
                stop_at_bar = false;
            }
        }
    }
}
