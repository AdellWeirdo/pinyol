// pinyol's sounds made from numbers (src/synth.c), in JavaScript: the same recipes from the same seeds, rendered for
// listening while editing. The game makes its own with sound() from the recipe and seed, so what is heard here is
// what it plays (to a rounding).
import { t } from './i18n.js';

export const HZ = 22050;
export const WAVES = ['square', 'triangle', 'saw', 'sine', 'noise'];
export const RECIPES = { coin: t('moneda'), laser: t('láser'), explosion: t('explosión'), powerup: t('mejora'), hit: t('golpe'),
                         jump: t('salto'), blip: t('bip'), random: t('sorpresa') }; // as the buttons say them

export function defaults() {
  return { wave: 'square', freq: 440, freq_min: 0, slide: 0, slide_accel: 0, vibrato: 0, vibrato_speed: 6, arp: 1,
           arp_time: 0, duty: 0.5, duty_sweep: 0, attack: 0, sustain: 0.1, punch: 0, decay: 0.2, lowpass: 1,
           lowpass_sweep: 0, resonance: 0, highpass: 0, highpass_sweep: 0, again: 0, volume: 0.5, seed: 1 };
}

function rng(seed) { // xorshift32, as synth.c
  let s = seed >>> 0 || 1;
  const next = () => { s ^= s << 13; s >>>= 0; s ^= s >>> 17; s ^= s << 5; s >>>= 0; return s; };
  const rnd = () => (next() >>> 8) / 16777216;
  return { next, rnd, range: (a, b) => a + (b - a) * rnd() };
}

export function recipe(kind, seed) {
  const r = rng((Math.imul(seed >>> 0, 2654435761) + 12345) >>> 0);
  r.next();
  const p = defaults();
  p.seed = seed || 1;
  const { rnd, range, next } = r;
  const pick = list => list[next() % list.length];
  switch (kind) {
    case 'coin':
      p.wave = rnd() < 0.5 ? 'square' : 'saw';
      p.freq = range(700, 1300); p.sustain = range(0.02, 0.08); p.decay = range(0.12, 0.3);
      p.punch = range(0.3, 0.6); p.arp = range(1.25, 1.6); p.arp_time = range(0.04, 0.09);
      break;
    case 'laser':
      p.wave = pick(['square', 'saw', 'sine']);
      p.freq = range(600, 2200); p.slide = -range(2000, 9000); p.freq_min = range(80, 300);
      p.duty = range(0.15, 0.5); p.duty_sweep = range(-1, 1);
      p.sustain = range(0.04, 0.14); p.decay = range(0.06, 0.25); p.punch = range(0, 0.4);
      if (rnd() < 0.4) p.highpass = range(0.1, 0.4);
      break;
    case 'explosion':
      p.wave = 'noise';
      p.freq = range(80, 900); p.slide = -range(40, 600); p.sustain = range(0.08, 0.3);
      p.decay = range(0.3, 0.9); p.punch = range(0.3, 0.8);
      if (rnd() < 0.5) { p.lowpass = range(0.4, 0.9); p.lowpass_sweep = -range(0, 1); }
      if (rnd() < 0.3) { p.vibrato = range(0.1, 0.5); p.vibrato_speed = range(4, 20); }
      break;
    case 'powerup':
      p.wave = rnd() < 0.5 ? 'square' : 'saw';
      p.freq = range(220, 600); p.slide = range(500, 2400); p.sustain = range(0.12, 0.3);
      p.decay = range(0.15, 0.4); p.duty = range(0.2, 0.5);
      if (rnd() < 0.5) p.again = range(0.08, 0.2);
      else { p.vibrato = range(0.05, 0.3); p.vibrato_speed = range(6, 18); }
      break;
    case 'hit':
      p.wave = pick(['square', 'saw', 'noise']);
      p.freq = range(150, 700); p.slide = -range(600, 3000); p.sustain = range(0.01, 0.06);
      p.decay = range(0.08, 0.2); p.punch = range(0, 0.5);
      if (rnd() < 0.5) p.highpass = range(0.05, 0.3);
      break;
    case 'jump':
      p.wave = 'square';
      p.freq = range(220, 520); p.slide = range(400, 1600); p.duty = range(0.25, 0.5);
      p.sustain = range(0.04, 0.14); p.decay = range(0.08, 0.2);
      if (rnd() < 0.5) p.highpass = range(0.05, 0.3);
      if (rnd() < 0.5) p.lowpass = range(0.5, 0.95);
      break;
    case 'blip':
      p.wave = rnd() < 0.5 ? 'square' : 'saw';
      p.freq = range(400, 1400); p.duty = range(0.2, 0.5); p.sustain = range(0.02, 0.07);
      p.decay = range(0.02, 0.08); p.highpass = 0.1;
      break;
    default: // random
      p.wave = WAVES[next() % 5];
      p.freq = range(60, 2000); p.slide = range(-3000, 3000); p.slide_accel = range(-3000, 3000);
      if (rnd() < 0.3) { p.vibrato = range(0, 0.5); p.vibrato_speed = range(2, 30); }
      if (rnd() < 0.3) { p.arp = range(0.5, 2); p.arp_time = range(0.02, 0.3); }
      p.duty = range(0.1, 0.9); p.duty_sweep = range(-2, 2);
      p.attack = rnd() < 0.7 ? 0 : range(0, 0.3); p.sustain = range(0.02, 0.4);
      p.decay = range(0.05, 0.6); p.punch = range(0, 0.6);
      if (rnd() < 0.4) { p.lowpass = range(0.2, 1); p.lowpass_sweep = range(-1, 1); p.resonance = rnd(); }
      if (rnd() < 0.3) { p.highpass = range(0, 0.4); p.highpass_sweep = range(-0.5, 0.5); }
      if (rnd() < 0.2) p.again = range(0.05, 0.3);
  }
  return p;
}

const clamp = (v, lo, hi) => (Number.isFinite(v) ? Math.min(hi, Math.max(lo, v)) : lo);

export function render(input) { // -> Float32Array at HZ, -1..1
  const p = { ...defaults(), ...input };
  p.freq = clamp(p.freq, 1, 20000); p.freq_min = clamp(p.freq_min, 0, 20000);
  let len = clamp(p.attack, 0, 4) + clamp(p.sustain, 0, 4) + clamp(p.decay, 0, 4);
  const k = len > 4 ? 4 / len : 1;
  const attack = clamp(p.attack, 0, 4) * k, sustain = clamp(p.sustain, 0, 4) * k, decay = clamp(p.decay, 0, 4) * k;
  len = attack + sustain + decay;
  const total = Math.floor(len * HZ), OS = 4, dt = 1 / (HZ * OS), out = new Float32Array(total);
  const r = rng(p.seed || 1), noise = Array.from({ length: 32 }, () => r.rnd() * 2 - 1);
  let freq = p.freq, slide = p.slide, duty = clamp(p.duty, 0.02, 0.98), phase = 0, rep = 0, arped = false;
  let lp = clamp(p.lowpass, 0, 1), hp = clamp(p.highpass, 0, 1), fltp = 0, fltdp = 0, fltphp = 0, vib = 0;
  let n = 0;
  outer: for (; n < total; n++) {
    let acc = 0;
    const v = p.vibrato > 0 ? 1 + p.vibrato * 0.5 * Math.sin(2 * Math.PI * vib) : 1;
    vib = (vib + p.vibrato_speed / HZ) % 1;
    const w = lp * lp * lp * 0.1, damp = Math.min(0.8, 5 / (1 + p.resonance * p.resonance * 20) * (0.01 + w)), hpk = hp * hp * 0.1;
    for (let o = 0; o < OS; o++) {
      if (p.again > 0 && rep >= p.again) { freq = p.freq; slide = p.slide; duty = clamp(p.duty, 0.02, 0.98); arped = false; rep = 0; }
      if (!arped && p.arp_time > 0 && rep >= p.arp_time) { freq *= p.arp; arped = true; }
      slide += p.slide_accel * dt;
      freq += slide * dt;
      if (p.freq_min > 0 && freq < p.freq_min) break outer;
      freq = clamp(freq, 1, 20000);
      duty = clamp(duty + p.duty_sweep * dt, 0.02, 0.98);
      phase += freq * v * dt;
      if (phase >= 1) { phase -= Math.floor(phase); if (p.wave === 'noise') for (let i = 0; i < 32; i++) noise[i] = r.rnd() * 2 - 1; }
      let x;
      switch (p.wave) {
        case 'square': x = phase < duty ? 0.5 : -0.5; break;
        case 'triangle': x = phase < 0.5 ? 2 * phase - 0.5 : 1.5 - 2 * phase; break;
        case 'saw': x = 0.5 - phase; break;
        case 'sine': x = 0.5 * Math.sin(2 * Math.PI * phase); break;
        default: x = 0.5 * noise[Math.floor(phase * 32) % 32];
      }
      const old = fltp;
      if (lp < 1) { fltdp += (x - fltp) * w; fltdp -= fltdp * damp; fltp += fltdp; } else { fltp = x; fltdp = 0; }
      fltphp += fltp - old;
      fltphp -= fltphp * hpk;
      acc += fltphp;
      rep += dt;
    }
    if (p.lowpass_sweep) lp = clamp(lp + p.lowpass_sweep / HZ, 0, 1);
    if (p.highpass_sweep) hp = clamp(hp + p.highpass_sweep / HZ, 0, 1);
    const s = n / HZ;
    const env = s < attack ? s / attack : s < attack + sustain ? 1 + (1 - (s - attack) / sustain) * 2 * clamp(p.punch, 0, 1)
      : decay > 0 ? 1 - (s - attack - sustain) / decay : 0;
    out[n] = clamp(acc / OS * env * clamp(p.volume, 0, 1) * 2, -1, 1) * 0.92;
  }
  return out.subarray(0, n);
}

let ctx = null;
export function play(params) {
  ctx = ctx || new AudioContext();
  const data = render(params);
  if (!data.length) return;
  const buf = ctx.createBuffer(1, data.length, HZ);
  buf.copyToChannel(data, 0);
  const src = ctx.createBufferSource();
  src.buffer = buf;
  src.connect(ctx.destination);
  src.start();
}
