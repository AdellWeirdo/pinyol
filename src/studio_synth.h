/* The studio's synth voice (studio_synth.c): one monophonic subtractive voice, for synth tracks. */
#ifndef STUDIO_SYNTH_H
#define STUDIO_SYNTH_H

#include <stdbool.h>

typedef struct {
    int wave;          /* 0 saw, 1 square */
    float cutoff, res; /* 0..1: 30 Hz to 9 kHz, and how much it rings at the cutoff */
    float env, decay;  /* how far the filter envelope opens it (0..1, six octaves), its fall in seconds */
    float accent;      /* 0..1: an accented note opens the filter further and plays louder */
    float glide;       /* seconds a slide takes to reach the next note */
    float drive;       /* 0..1: soft saturation before the filter */
    float volume;      /* 0..1 */
    float tune;        /* semitones added to every note */
} sv_patch;

typedef struct {
    float phase, freq, target; /* Hz now and where a slide goes */
    float ic1, ic2;            /* the filter's two states */
    float fenv, amp, cut;      /* filter envelope, amplitude, the base cutoff smoothed (no zipper) */
    float a1, a2, a3;          /* filter coefficients, worked out every few samples */
    float k_cut, k_env, k_res; /* what they were worked out for: a filter standing still keeps them (a held pad) */
    int coef;                  /* samples until they are worked out again */
    int gate;                  /* samples until the note is let go; -1 held (sliding into the next) */
    bool on, acc, legato;
} sv_voice;

void sv_defaults(sv_patch *p);
void sv_note(sv_voice *v, const sv_patch *p, int note, bool accent, bool legato, int gate);
void sv_release(sv_voice *v);
void sv_render(sv_voice *v, const sv_patch *p, float *out, int from, int to); /* adds to out[from..to) */

/* Between the studio's files: a step's length in samples now (studio.c); the effects back to silence (studio_fx.c) */
double studio_step_samples(void);
void studio_fx_reset(void);
void studio_fx_free(void);

/* studio.c: a track becomes a synth track with that patch; its patch now (false: it is not a synth track) */
void studio_synth(int track, const sv_patch *p);
bool studio_synth_get(int track, sv_patch *p);

#endif
