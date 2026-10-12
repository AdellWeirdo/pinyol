/* Sounds made from a few numbers, as sfxr made them famous: a wave, its pitch and how it slides, wobbles or jumps,
 * an envelope (attack, sustain with a punch, decay), and a resonant lowpass and a highpass that can sweep. Rendered
 * once into a clip (audio_sfx_set), then played like any recording: sfx(id) with its pitch and loop. The recipes
 * (synth_recipe) roll a coin, a laser, an explosion... from a seed, so a game can have a thousand sounds and no
 * files. Everything in Hz and seconds; the same numbers give the same sound on every machine. */
#include <math.h>
#include <string.h>

#include "bp.h"

#define OVERSAMPLE 4 /* worked out at 88 kHz and averaged: high pitches without the grit of aliasing */
#define NOISE_N 32   /* noise: new random values each period, so its pitch is heard */

static uint32_t next(uint32_t *s) { /* xorshift32 */
    uint32_t x = *s ? *s : 1;
    x ^= x << 13, x ^= x >> 17, x ^= x << 5;
    return *s = x;
}
static float rnd(uint32_t *s) { return (float)(next(s) >> 8) / 16777216.0f; } /* 0..1 */
static float range(uint32_t *s, float a, float b) { return a + (b - a) * rnd(s); }

void synth_defaults(synth_params *p) {
    *p = (synth_params){.wave = PSG_SQUARE, .freq = 440, .vibrato_speed = 6, .arp = 1, .duty = 0.5f, .sustain = 0.1f,
                        .decay = 0.2f, .lowpass = 1, .volume = 0.5f, .seed = 1};
}

static float clampf(float v, float lo, float hi) { return v != v ? lo : v < lo ? lo : v > hi ? hi : v; }

void synth_clamp(synth_params *p) { /* a game's numbers made safe: finite, in range, at most SYNTH_MAX_S long */
    p->wave = p->wave > PSG_NOISE ? PSG_SQUARE : p->wave;
    p->freq = clampf(p->freq, 1, 20000), p->freq_min = clampf(p->freq_min, 0, 20000);
    p->slide = clampf(p->slide, -100000, 100000), p->slide_accel = clampf(p->slide_accel, -1000000, 1000000);
    p->vibrato = clampf(p->vibrato, 0, 1), p->vibrato_speed = clampf(p->vibrato_speed, 0, 100);
    p->arp = clampf(p->arp, 0.1f, 10), p->arp_time = clampf(p->arp_time, 0, SYNTH_MAX_S);
    p->duty = clampf(p->duty, 0.02f, 0.98f), p->duty_sweep = clampf(p->duty_sweep, -10, 10);
    p->attack = clampf(p->attack, 0, SYNTH_MAX_S), p->sustain = clampf(p->sustain, 0, SYNTH_MAX_S);
    p->decay = clampf(p->decay, 0, SYNTH_MAX_S), p->punch = clampf(p->punch, 0, 1);
    float len = p->attack + p->sustain + p->decay;
    if (len > SYNTH_MAX_S) p->attack *= SYNTH_MAX_S / len, p->sustain *= SYNTH_MAX_S / len, p->decay *= SYNTH_MAX_S / len;
    p->lowpass = clampf(p->lowpass, 0, 1), p->lowpass_sweep = clampf(p->lowpass_sweep, -10, 10);
    p->resonance = clampf(p->resonance, 0, 1);
    p->highpass = clampf(p->highpass, 0, 1), p->highpass_sweep = clampf(p->highpass_sweep, -10, 10);
    p->repeat = clampf(p->repeat, 0, SYNTH_MAX_S), p->volume = clampf(p->volume, 0, 1);
}

/* Up to max samples at AUDIO_HZ into out; how many. p is clamped first. */
int synth_render(const synth_params *in, int16_t *out, int max) {
    synth_params p = *in;
    synth_clamp(&p);
    int total = (int)((p.attack + p.sustain + p.decay) * AUDIO_HZ);
    if (total > max) total = max;
    const float dt = 1.0f / (AUDIO_HZ * OVERSAMPLE);
    uint32_t seed = p.seed ? p.seed : 1;
    float noise[NOISE_N];
    for (int i = 0; i < NOISE_N; i++) noise[i] = rnd(&seed) * 2 - 1;
    float freq = p.freq, slide = p.slide, duty = p.duty, phase = 0, t = 0, rep = 0, lp = p.lowpass, hp = p.highpass;
    float fltp = 0, fltdp = 0, fltphp = 0;
    bool arped = false;
    int n = 0;
    for (; n < total; n++) {
        float acc = 0;
        for (int o = 0; o < OVERSAMPLE; o++) {
            if (p.repeat > 0 && rep >= p.repeat) /* again from the start: an alarm, a power-up's climb */
                freq = p.freq, slide = p.slide, duty = p.duty, arped = false, rep = 0;
            if (!arped && p.arp_time > 0 && rep >= p.arp_time) freq *= p.arp, arped = true; /* a jump: a coin's ding */
            slide += p.slide_accel * dt;
            freq += slide * dt;
            if (p.freq_min > 0 && freq < p.freq_min) goto done; /* slid below its floor: over */
            if (freq < 1) freq = 1;
            if (freq > 20000) freq = 20000;
            float f = p.vibrato > 0 ? freq * (1 + p.vibrato * 0.5f * sinf(6.2831853f * p.vibrato_speed * t)) : freq;
            duty = clampf(duty + p.duty_sweep * dt, 0.02f, 0.98f);
            phase += f * dt;
            if (phase >= 1) {
                phase -= floorf(phase);
                if (p.wave == PSG_NOISE)
                    for (int i = 0; i < NOISE_N; i++) noise[i] = rnd(&seed) * 2 - 1;
            }
            float x;
            switch (p.wave) {
            case PSG_SQUARE: x = phase < duty ? 0.5f : -0.5f; break;
            case PSG_TRIANGLE: x = phase < 0.5f ? 2 * phase - 0.5f : 1.5f - 2 * phase; break;
            case PSG_SAW: x = 0.5f - phase; break;
            case PSG_SINE: x = 0.5f * sinf(6.2831853f * phase); break;
            default: x = 0.5f * noise[(int)(phase * NOISE_N) % NOISE_N]; break;
            }
            /* a resonant lowpass (open at 1) and a highpass after it, sweeping as they go */
            lp = clampf(lp + p.lowpass_sweep * dt, 0, 1), hp = clampf(hp + p.highpass_sweep * dt, 0, 1);
            float old = fltp;
            if (lp < 1) {
                float w = lp * lp * lp * 0.1f, damp = 5 / (1 + p.resonance * p.resonance * 20) * (0.01f + w);
                fltdp += (x - fltp) * w;
                fltdp -= fltdp * (damp > 0.8f ? 0.8f : damp);
                fltp += fltdp;
            } else {
                fltp = x, fltdp = 0;
            }
            fltphp += fltp - old;
            fltphp -= fltphp * hp * hp * 0.1f;
            acc += fltphp;
            t += dt, rep += dt;
        }
        float s = (float)n / AUDIO_HZ, env;
        if (s < p.attack) env = s / p.attack;
        else if (s < p.attack + p.sustain) env = 1 + (1 - (s - p.attack) / p.sustain) * 2 * p.punch;
        else env = p.decay > 0 ? 1 - (s - p.attack - p.sustain) / p.decay : 0;
        float v = clampf(acc / OVERSAMPLE * env * p.volume * 2, -1, 1);
        out[n] = (int16_t)lroundf(v * 30000);
    }
done:
    if (p.decay > 0 || n < total) /* no click at the end; but a sound that stops dead (decay 0) is made to loop */
        for (int i = n - (n < 64 ? n : 64); i < n; i++) out[i] = (int16_t)(out[i] * (n - i) / 64);
    return n;
}

/* A sound of a kind, rolled from a seed: the same seed, the same sound. false if the kind is not known. */
bool synth_recipe(const char *kind, uint32_t seed, synth_params *p) {
    uint32_t s = seed * 2654435761u + 12345;
    next(&s);
    synth_defaults(p);
    p->seed = seed ? seed : 1;
    if (!strcmp(kind, "coin")) {
        p->wave = rnd(&s) < 0.5f ? PSG_SQUARE : PSG_SAW;
        p->freq = range(&s, 700, 1300), p->sustain = range(&s, 0.02f, 0.08f), p->decay = range(&s, 0.12f, 0.3f);
        p->punch = range(&s, 0.3f, 0.6f), p->arp = range(&s, 1.25f, 1.6f), p->arp_time = range(&s, 0.04f, 0.09f);
    } else if (!strcmp(kind, "laser")) {
        p->wave = (int[]){PSG_SQUARE, PSG_SAW, PSG_SINE}[next(&s) % 3];
        p->freq = range(&s, 600, 2200), p->slide = -range(&s, 2000, 9000), p->freq_min = range(&s, 80, 300);
        p->duty = range(&s, 0.15f, 0.5f), p->duty_sweep = range(&s, -1, 1);
        p->sustain = range(&s, 0.04f, 0.14f), p->decay = range(&s, 0.06f, 0.25f), p->punch = range(&s, 0, 0.4f);
        if (rnd(&s) < 0.4f) p->highpass = range(&s, 0.1f, 0.4f);
    } else if (!strcmp(kind, "explosion")) {
        p->wave = PSG_NOISE;
        p->freq = range(&s, 80, 900), p->slide = -range(&s, 40, 600), p->sustain = range(&s, 0.08f, 0.3f);
        p->decay = range(&s, 0.3f, 0.9f), p->punch = range(&s, 0.3f, 0.8f);
        if (rnd(&s) < 0.5f) p->lowpass = range(&s, 0.4f, 0.9f), p->lowpass_sweep = -range(&s, 0, 1);
        if (rnd(&s) < 0.3f) p->vibrato = range(&s, 0.1f, 0.5f), p->vibrato_speed = range(&s, 4, 20);
    } else if (!strcmp(kind, "powerup")) {
        p->wave = rnd(&s) < 0.5f ? PSG_SQUARE : PSG_SAW;
        p->freq = range(&s, 220, 600), p->slide = range(&s, 500, 2400), p->sustain = range(&s, 0.12f, 0.3f);
        p->decay = range(&s, 0.15f, 0.4f), p->duty = range(&s, 0.2f, 0.5f);
        if (rnd(&s) < 0.5f) p->repeat = range(&s, 0.08f, 0.2f);
        else p->vibrato = range(&s, 0.05f, 0.3f), p->vibrato_speed = range(&s, 6, 18);
    } else if (!strcmp(kind, "hit")) {
        p->wave = (int[]){PSG_SQUARE, PSG_SAW, PSG_NOISE}[next(&s) % 3];
        p->freq = range(&s, 150, 700), p->slide = -range(&s, 600, 3000), p->sustain = range(&s, 0.01f, 0.06f);
        p->decay = range(&s, 0.08f, 0.2f), p->punch = range(&s, 0, 0.5f);
        if (rnd(&s) < 0.5f) p->highpass = range(&s, 0.05f, 0.3f);
    } else if (!strcmp(kind, "jump")) {
        p->wave = PSG_SQUARE;
        p->freq = range(&s, 220, 520), p->slide = range(&s, 400, 1600), p->duty = range(&s, 0.25f, 0.5f);
        p->sustain = range(&s, 0.04f, 0.14f), p->decay = range(&s, 0.08f, 0.2f);
        if (rnd(&s) < 0.5f) p->highpass = range(&s, 0.05f, 0.3f);
        if (rnd(&s) < 0.5f) p->lowpass = range(&s, 0.5f, 0.95f);
    } else if (!strcmp(kind, "blip")) {
        p->wave = rnd(&s) < 0.5f ? PSG_SQUARE : PSG_SAW;
        p->freq = range(&s, 400, 1400), p->duty = range(&s, 0.2f, 0.5f), p->sustain = range(&s, 0.02f, 0.07f);
        p->decay = range(&s, 0.02f, 0.08f), p->highpass = 0.1f;
    } else if (!strcmp(kind, "random")) {
        p->wave = (int)(next(&s) % 5);
        p->freq = range(&s, 60, 2000), p->slide = range(&s, -3000, 3000), p->slide_accel = range(&s, -3000, 3000);
        if (rnd(&s) < 0.3f) p->vibrato = range(&s, 0, 0.5f), p->vibrato_speed = range(&s, 2, 30);
        if (rnd(&s) < 0.3f) p->arp = range(&s, 0.5f, 2), p->arp_time = range(&s, 0.02f, 0.3f);
        p->duty = range(&s, 0.1f, 0.9f), p->duty_sweep = range(&s, -2, 2);
        p->attack = rnd(&s) < 0.7f ? 0 : range(&s, 0, 0.3f), p->sustain = range(&s, 0.02f, 0.4f);
        p->decay = range(&s, 0.05f, 0.6f), p->punch = range(&s, 0, 0.6f);
        if (rnd(&s) < 0.4f) p->lowpass = range(&s, 0.2f, 1), p->lowpass_sweep = range(&s, -1, 1), p->resonance = rnd(&s);
        if (rnd(&s) < 0.3f) p->highpass = range(&s, 0, 0.4f), p->highpass_sweep = range(&s, -0.5f, 0.5f);
        if (rnd(&s) < 0.2f) p->repeat = range(&s, 0.05f, 0.3f);
    } else {
        return false;
    }
    return true;
}
