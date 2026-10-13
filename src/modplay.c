/* Music from trackers: ProTracker modules (.mod, made with MilkyTracker, OpenMPT, ProTracker...), as GBA games had
 * theirs. pocketmod (third_party) reads and renders the module; this file loads one, loops it, and mixes it with the
 * rest of the sound (audio_mix). A module from a downloaded game is untrusted: pocketmod checks every offset against
 * the file's size, and the file is capped here. */
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

static pocketmod_context song;
static uint8_t *bytes; /* the module's file: the song plays its samples straight from it */
static bool playing;
static float gain, fade_step, level; /* level fades to 0 at fade_step per sample after mod_stop */

bool mod_play(const char *path, float g) {
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
    static pocketmod_context next; /* ~2.5 KB: not on the caller's stack */
    if (len > MOD_MAX_BYTES || !pocketmod_init(&next, data, (int)len, AUDIO_HZ)) {
        hal_log("music %s: not a module that can be played", path);
        free(data);
        return false;
    }
    hal_audio_lock();
    uint8_t *old = bytes;
    song = next, bytes = data, playing = true, gain = g, level = 1, fade_step = 0;
    audio_music_clock_locked(2);
    hal_audio_unlock();
    free(old);
    return true;
}

void mod_stop(int fade_ms) {
    hal_audio_lock();
    fade_step = fade_ms > 0 ? 1000.0f / ((float)fade_ms * AUDIO_HZ) : 1;
    hal_audio_unlock();
}

bool mod_playing(void) { return playing; }

void mod_reset(void) {
    hal_audio_lock();
    uint8_t *old = bytes;
    playing = false, bytes = NULL;
    hal_audio_unlock();
    free(old);
}

/* The audio thread, lock held: m <= 256 samples of the song into acc. */
void mod_mix(float *acc, int m) {
    static float buf[256][2];
    if (!playing || m > 256) return;
    for (int done = 0; done < m && playing;) {
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
    }
}
