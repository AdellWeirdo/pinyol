/* Synthesised voices: the GBA's programmable sound generator idea (square, wave and noise channels), so a game can
 * make its music and effects from notes instead of recordings. Four voices, each any waveform, with an envelope
 * (attack, then a decay towards a sustain level, then a release), a pitch slide and an optional length. Mixed by
 * audio_mix() next to the WAV voices. */
#include <math.h>
#include <string.h>

#include "bp.h"

#define AMP 8000.0f /* one voice at full volume: four of them reach the limiter's knee */
#define SINE_N 256

typedef struct {
    psg_note n;
    bool on, releasing;
    float phase, freq, t, env, attack_step, decay_k, release_k;
    uint16_t lfsr; float noise; /* noise: a 15-bit (or 7-bit) shift register clocked at the voice's frequency */
    float vib_phase, bend, mult; /* mult: the pitch's factor from vibrato and bend, worked out every 16 samples */
    unsigned tick;
} voice;

static voice V[PSG_VOICES];
static float sine[SINE_N];

void psg_reset(void) {
    hal_audio_lock();
    memset(V, 0, sizeof V);
    hal_audio_unlock();
}

void psg_play(int ch, const psg_note *n) {
    if (ch < 0 || ch >= PSG_VOICES || !(n->freq > 0)) return;
    if (!sine[SINE_N / 4])
        for (int i = 0; i < SINE_N; i++) sine[i] = sinf(6.2831853f * i / SINE_N);
    const float dt = 1.0f / AUDIO_HZ;
    voice v = {.n = *n, .on = true, .freq = n->freq, .lfsr = n->lfsr7 ? 0x7F : 0x7FFF, .noise = 1, .bend = n->bend, .mult = 1};
    v.attack_step = n->attack > dt ? dt / n->attack : 1;
    v.env = n->attack > dt ? 0 : 1;
    v.decay_k = n->decay > 0 ? expf(-dt / n->decay) : 0;
    v.release_k = expf(-dt / (n->release > 0.001f ? n->release : 0.001f));
    hal_audio_lock();
    V[ch] = v;
    hal_audio_unlock();
}

void psg_set(int ch, const psg_mod *m) {
    if (ch < 0 || ch >= PSG_VOICES) return;
    hal_audio_lock();
    if (m->vol >= 0) V[ch].n.vol = m->vol > 1 ? 1 : m->vol;
    if (m->set_bend) V[ch].bend = m->bend;
    hal_audio_unlock();
}

void psg_release(int ch) {
    if (ch < 0 || ch >= PSG_VOICES) return;
    hal_audio_lock();
    V[ch].releasing = true;
    hal_audio_unlock();
}

static inline float wave(voice *v) {
    float p = v->phase;
    switch (v->n.wave) {
    case PSG_SQUARE: return p < v->n.duty ? 1 : -1;
    case PSG_TRIANGLE: return 4 * fabsf(p - 0.5f) - 1;
    case PSG_SAW: return 2 * p - 1;
    case PSG_SINE: return sine[(int)(p * SINE_N) & (SINE_N - 1)];
    case PSG_WAVE: return ((float)v->n.table[(int)(p * 32) & 31] - 7.5f) / 7.5f;
    default: return v->noise;
    }
}

/* Called by audio_mix with the audio lock held: adds m samples of every voice into acc. */
void psg_mix(float *acc, int m) {
    const float dt = 1.0f / AUDIO_HZ;
    for (int c = 0; c < PSG_VOICES; c++) {
        voice *v = &V[c];
        for (int i = 0; i < m && v->on; i++) {
            if (v->releasing || (v->n.len > 0 && v->t >= v->n.len)) { /* note off: fade, then free */
                v->releasing = true;
                v->env *= v->release_k;
                if (v->env < 0.0005f) v->on = false;
            } else if (v->t < v->n.attack) { /* attack: up to full */
                v->env += v->attack_step;
                if (v->env > 1) v->env = 1;
            } else { /* decay towards the sustain level; a plucked note (sustain 0) ends by itself */
                v->env = v->n.sustain + (v->env - v->n.sustain) * v->decay_k;
                if (v->n.sustain <= 0 && v->env < 0.0005f) v->on = false;
            }
            acc[i] += wave(v) * v->env * v->n.vol * AMP;
            if (!(v->tick++ & 15) && (v->n.vib_depth > 0 || v->bend != 0)) { /* vibrato and bend move the pitch */
                float vib = v->t >= v->n.vib_delay ? v->n.vib_depth * sine[(int)(v->vib_phase * SINE_N) & (SINE_N - 1)] : 0;
                v->mult = exp2f(v->bend / 12.0f + vib / 1200.0f);
            }
            v->vib_phase += v->n.vib_speed * dt;
            v->vib_phase -= (float)(int)v->vib_phase;
            v->phase += v->freq * v->mult * dt;
            if (v->phase >= 1) {
                v->phase -= (float)(int)v->phase;
                if (v->n.wave == PSG_NOISE) { /* a new noise value each period */
                    unsigned bit = (v->lfsr ^ (v->lfsr >> 1)) & 1, top = v->n.lfsr7 ? 6 : 14;
                    v->lfsr = (uint16_t)((v->lfsr >> 1) | (bit << top));
                    v->noise = v->lfsr & 1 ? 1 : -1;
                }
            }
            v->freq += v->n.slide * dt;
            if (v->freq < 1 || v->freq > AUDIO_HZ / 2) v->on = false; /* slid out of hearing */
            v->t += dt;
        }
    }
}

float psg_note_hz(const char *name) { /* "A4" 440 Hz, "C#3", "Eb5"; 0 if it is not a note */
    static const int semis[7] = {9, 11, 0, 2, 4, 5, 7}; /* A B C D E F G from C */
    if (!name || name[0] < 'A' || name[0] > 'G') return 0;
    int s = semis[name[0] - 'A'], i = 1;
    if (name[i] == '#') s++, i++;
    else if (name[i] == 'b') s--, i++;
    if (name[i] < '0' || name[i] > '9' || name[i + 1]) return 0;
    int midi = (name[i] - '0' + 1) * 12 + s;
    return 440.0f * powf(2.0f, (midi - 69) / 12.0f);
}
