/* A subtractive voice for the studio's synth tracks, made for an acid bass as a TB-303 plays it: one oscillator, saw
 * or square, band-limited with PolyBLEP (at 22 kHz a naive saw folds its upper harmonics back as noise: Valimaki and
 * Huovilainen 2007); a soft drive; a resonant lowpass, Andy Simper's state-variable filter (stable at any cutoff and
 * modulated every few samples without clicks); a filter envelope that falls; an accent that opens the filter further
 * and plays louder; a slide that glides the pitch into the next note without starting its envelopes again. One note
 * at a time. Runs in the audio thread, the lock held. */
#include <math.h>

#include "bp.h"
#include "studio_synth.h"

#define SCALE 9000.0f   /* to the mixer's PCM16 scale, under a drum clip at full gain */
#define COEF_EVERY 8    /* samples between filter coefficients: the envelope moves slower than that */
#define ATTACK 0.25f    /* of the way to full amplitude each sample: ~0.2 ms, no click */
#define RELEASE 0.004f  /* ~11 ms to silence once the gate closes */

static const float PI = 3.14159265f;

void sv_defaults(sv_patch *p) {
    *p = (sv_patch){.wave = 0, .cutoff = 0.35f, .res = 0.6f, .env = 0.5f, .decay = 0.3f, .accent = 0.5f,
                    .glide = 0.06f, .drive = 0.2f, .volume = 0.8f, .tune = 0};
}

static float polyblep(float t, float dt) { /* the step's corner smoothed over one sample each side */
    if (t < dt) {
        t /= dt;
        return t + t - t * t - 1;
    }
    if (t > 1 - dt) {
        t = (t - 1) / dt;
        return t * t + t + t + 1;
    }
    return 0;
}

void sv_note(sv_voice *v, const sv_patch *p, int note, bool accent, bool legato, int gate) {
    float hz = 440.0f * exp2f(((float)note + p->tune - 69) / 12);
    v->target = hz;
    v->legato = legato && v->on && v->gate != 0;
    if (!v->legato) { /* a new note: the envelopes start again and the pitch jumps */
        v->freq = hz;
        v->fenv = 1 + (accent ? p->accent : 0);
        v->acc = accent;
        if (!v->on) v->cut = p->cutoff, v->coef = 0, v->k_cut = -1;
    }
    v->on = true;
    v->gate = gate;
}

void sv_release(sv_voice *v) { v->gate = 0; }

void sv_render(sv_voice *v, const sv_patch *p, float *out, int from, int to) {
    if (!v->on) return;
    float fdec = expf(-1.0f / (fmaxf(p->decay, 0.01f) * AUDIO_HZ));
    float gk = v->legato ? 1 - expf(-3.0f / (fmaxf(p->glide, 0.002f) * AUDIO_HZ)) : 1; /* ~95 % there in `glide` */
    float drive = 1 + p->drive * 4, k = 2 - 2 * fminf(p->res, 1) * 0.97f;
    float level = p->volume * SCALE * (v->acc ? 1 + 0.4f * p->accent : 1) / (1 + p->drive);
    for (int i = from; i < to; i++) {
        v->freq += (v->target - v->freq) * gk;
        float dt = fminf(v->freq / AUDIO_HZ, 0.45f);
        v->phase += dt;
        if (v->phase >= 1) v->phase -= 1;
        float x;
        if (p->wave == 0) {
            x = 2 * v->phase - 1 - polyblep(v->phase, dt);
        } else {
            float t2 = v->phase + 0.5f;
            if (t2 >= 1) t2 -= 1;
            x = (v->phase < 0.5f ? 1 : -1) + polyblep(v->phase, dt) - polyblep(t2, dt);
        }
        x *= drive;
        x /= 1 + fabsf(x); /* soft saturation: louder in, rounder out */
        v->fenv *= fdec;
        v->cut += (p->cutoff - v->cut) * 0.002f; /* a knob turned while it plays glides there */
        if (--v->coef <= 0) {
            float e = p->env * 6 * v->fenv; /* octaves the envelope opens it */
            /* powf, exp2f and tanf cost more than all the rest of a sample: only when the cutoff has moved
             * (by 0.06 % of its frequency or more), not for a filter standing still */
            if (fabsf(v->cut - v->k_cut) > 1e-4f || fabsf(e - v->k_env) > 1e-3f || k != v->k_res) {
                float fc = 30 * powf(300, v->cut) * exp2f(e);
                float g = tanf(PI * fminf(fc, 9000) / AUDIO_HZ);
                v->a1 = 1 / (1 + g * (g + k)), v->a2 = g * v->a1, v->a3 = g * v->a2;
                v->k_cut = v->cut, v->k_env = e, v->k_res = k;
            }
            v->coef = COEF_EVERY;
        }
        float v3 = x - v->ic2, v1 = v->a1 * v->ic1 + v->a2 * v3, v2 = v->ic2 + v->a2 * v->ic1 + v->a3 * v3;
        v->ic1 = 2 * v1 - v->ic1, v->ic2 = 2 * v2 - v->ic2;
        float target = v->gate ? 1 : 0;
        v->amp += (target - v->amp) * (v->gate ? ATTACK : RELEASE);
        out[i] += v2 * v->amp * level;
        if (v->gate > 0) v->gate--;
    }
    if (!v->gate && v->amp < 1e-4f) v->on = false, v->ic1 = v->ic2 = 0, v->amp = 0; /* quiet: it stops costing */
}
