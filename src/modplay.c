/* Music from trackers: ProTracker modules (.mod, made with MilkyTracker, OpenMPT, ProTracker...), as GBA games had
 * theirs. pocketmod (third_party) reads and renders the module; this file loads one, loops it, and mixes it with the
 * rest of the sound (audio_mix, through the music bus like a WAV: bus("music") and duck() reach it). A module from a
 * downloaded game is untrusted: pocketmod checks every offset against the file's size, and the file is capped here.
 * A bar is sixteen lines (four beats of four, as most modules are written): a module asked for with at = "bar" waits,
 * loaded, for the bar line of the one playing (mod_queue), and a stop at the bar plays to the line and fades there
 * (mod_stop_at_bar), as a theme ends on a button. */
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

#define MOD_MAX_BYTES (4 << 20)
#define MOD_LEVEL 20000.0f /* full scale of the render (-1..1) in the mixer's units: under the effects */
#define MOD_BAR_LINES 16   /* ponytail: 4/4 at four lines a beat; a `bar` in lines when a game writes in 3/4 */

static pocketmod_context song; /* playing: the audio thread reads it every sample */
static pocketmod_context *next_song, *loaded; /* waiting for the bar line, and the game's thread's scratch: 2.5 KB each, asked for in slow memory */
static uint8_t *bytes, *next_bytes, *garbage; /* their files (the song plays its samples straight from it); garbage is
                                               * what the audio thread let go at a swap, freed on the next call from the game */
static bool playing, queued, stop_at_bar;
static float gain, next_gain, fade_step, level; /* level fades to 0 at fade_step per sample after mod_stop */
static int bar_fade_ms;

static bool load(const char *path, uint8_t **out) { /* into `loaded` */
    long len = 0;
    uint8_t *data = (uint8_t *)read_file(path, &len), *padded;
    if (!data) return false;
    /* pocketmod's interpolation reads up to 2 bytes past a sample, so past the file for the last one: zeros there */
    if (!(padded = realloc(data, (size_t)len + 8))) {
        free(data);
        return false;
    }
    data = padded;
    memset(data + len, 0, 8);
    if (!loaded) loaded = hal_realloc_slow(NULL, sizeof *loaded);
    if (!loaded || len > MOD_MAX_BYTES || !pocketmod_init(loaded, data, (int)len, AUDIO_HZ)) {
        hal_log("music %s: not a module that can be played", path);
        free(data);
        return false;
    }
    *out = data;
    return true;
}

static void take_out(void) { free(garbage), garbage = NULL; } /* the game's thread, no lock: the audio thread is done with it */

bool mod_play(const char *path, float g) {
    uint8_t *data;
    take_out();
    if (!load(path, &data)) return false;
    hal_audio_lock();
    uint8_t *old = bytes, *old_next = next_bytes;
    song = *loaded, bytes = data, playing = true, gain = g, level = 1, fade_step = 0;
    queued = false, stop_at_bar = false, next_bytes = NULL;
    audio_music_clock_locked(2);
    hal_audio_unlock();
    free(old), free(old_next);
    return true;
}

bool mod_queue(const char *path, float g) {
    if (!playing) return mod_play(path, g);
    uint8_t *data;
    take_out();
    if (!load(path, &data)) return false;
    if (!next_song && !(next_song = hal_realloc_slow(NULL, sizeof *next_song))) {
        free(data);
        return false;
    }
    hal_audio_lock();
    uint8_t *old_next = next_bytes;
    *next_song = *loaded, next_bytes = data, next_gain = g, queued = true, stop_at_bar = false;
    hal_audio_unlock();
    free(old_next);
    return true;
}

static void drop_queued_locked(uint8_t **old_next) {
    *old_next = next_bytes;
    queued = false, stop_at_bar = false, next_bytes = NULL;
}

void mod_stop(int fade_ms) {
    uint8_t *old_next;
    take_out();
    hal_audio_lock();
    fade_step = fade_ms > 0 ? 1000.0f / ((float)fade_ms * AUDIO_HZ) : 1;
    drop_queued_locked(&old_next);
    hal_audio_unlock();
    free(old_next);
}

void mod_stop_at_bar(int fade_ms) {
    uint8_t *old_next;
    take_out();
    hal_audio_lock();
    drop_queued_locked(&old_next);
    stop_at_bar = playing, bar_fade_ms = fade_ms;
    hal_audio_unlock();
    free(old_next);
}

bool mod_playing(void) { return playing; }
bool mod_queued(void) { return queued; }

static int lines_in(const pocketmod_context *c) { return c->pattern * 64 + (c->line < 0 ? 0 : c->line); }

bool mod_position(int *bar, int *beat, float *frac) {
    if (!playing || fade_step > 0) return false; /* (a module fading out after music() is gone, as a WAV is) */
    hal_audio_lock();
    const int line = lines_in(&song);
    const float in_line = ((float)song.tick + song.sample / song.samples_per_tick) / (float)(song.ticks_per_line > 0 ? song.ticks_per_line : 1);
    hal_audio_unlock();
    *bar = line / MOD_BAR_LINES + 1;
    *beat = line % MOD_BAR_LINES / 4 + 1;
    *frac = ((float)(line % 4) + (in_line < 0 ? 0 : in_line > 1 ? 1 : in_line)) / 4;
    return true;
}

void mod_reset(void) {
    hal_audio_lock();
    uint8_t *old = bytes, *old_next = next_bytes;
    playing = false, queued = false, stop_at_bar = false, bytes = NULL, next_bytes = NULL;
    hal_audio_unlock();
    free(old), free(old_next);
    take_out();
}

/* The audio thread, lock held: m <= 256 samples of the song into acc. A swap or a stop asked for at the bar lands
 * at most one render (a chunk, 12 ms) after the line. */
void mod_mix(float *acc, int m) {
    static float buf[256][2];
    if (!playing || m > 256) return;
    for (int done = 0; done < m && playing;) {
        const int before = lines_in(&song);
        int got = pocketmod_render(&song, buf[0], (int)((m - done) * sizeof buf[0])) / (int)sizeof buf[0];
        if (got <= 0) break; /* it stops at each new pattern: go on from there */
        for (int i = 0; i < got; i++) {
            acc[done + i] += (buf[i][0] + buf[i][1]) * 0.5f * gain * level * MOD_LEVEL;
            if (fade_step > 0 && (level -= fade_step) <= 0) {
                level = 0, playing = false;
                break;
            }
        }
        done += got;
        const int after = lines_in(&song);
        if (playing && (queued || stop_at_bar) && (after / MOD_BAR_LINES != before / MOD_BAR_LINES || after < before)) {
            if (queued) { /* the song waiting takes over; its file is kept until the game's thread frees the old one */
                if (!garbage) garbage = bytes;
                song = *next_song, bytes = next_bytes, gain = next_gain, level = 1, fade_step = 0;
                next_bytes = NULL, queued = false;
                audio_music_clock_locked(2);
            } else {
                fade_step = bar_fade_ms > 0 ? 1000.0f / ((float)bar_fade_ms * AUDIO_HZ) : 1;
                stop_at_bar = false;
            }
        }
    }
}
