// A song composed in the editor: a loop of steps (sixteenth notes) with a melody, a bass and drums, in a scale where
// every note goes with every other (pentatonic, by default). Played back here and made into the WAV the console loops,
// like a song brought in from a file. Plain data and plain maths: Node renders it in the tests.
export const HZ = 22050;
export const SCALES = { penta: [0, 2, 4, 7, 9], major: [0, 2, 4, 5, 7, 9, 11], minor: [0, 2, 3, 5, 7, 8, 10] };
export const SCALE_NAMES = { penta: 'pentatónica (todo suena bien)', major: 'mayor (alegre)', minor: 'menor (misteriosa)' };
export const WAVES = { square: 'cuadrada', triangle: 'suave', saw: 'brillante', sine: 'redonda' };
export const DRUMS = [['kick', 'bombo'], ['snare', 'caja'], ['hat', 'platillo']];
const NOTE = ['Do', 'Do#', 'Re', 'Re#', 'Mi', 'Fa', 'Fa#', 'Sol', 'Sol#', 'La', 'La#', 'Si'];
const BASE = { lead: 60, bass: 36 }; // C4 and C2
const OCTAVES = { lead: 2, bass: 1 };

// the rows of a track, top (high) to bottom (low): MIDI notes of its scale, two octaves (one for the bass) and the top
export function rows(song, track) {
  const sc = SCALES[song.scale] || SCALES.penta, out = [];
  for (let o = 0; o < OCTAVES[track]; o++) for (const s of sc) out.push(BASE[track] + 12 * o + s);
  out.push(BASE[track] + 12 * OCTAVES[track]);
  return out.reverse();
}
export const noteName = midi => NOTE[midi % 12] + (Math.floor(midi / 12) - 1);

// a song to start from, so a new one is heard at once: a little tune, its bass, a beat
export function newSong() {
  return { bpm: 110, steps: 32, scale: 'penta', volume: 0.8,
    lead: { wave: 'square', notes: [[0, 6, 2], [2, 5, 2], [4, 4, 4], [8, 5, 2], [10, 6, 2], [12, 3, 4], [16, 6, 2], [18, 5, 2],
      [20, 4, 2], [22, 2, 2], [24, 3, 6]] },
    bass: { wave: 'triangle', notes: [[0, 5, 4], [8, 3, 4], [16, 5, 4], [24, 2, 4]] },
    drums: { kick: [0, 8, 16, 24], snare: [4, 12, 20, 28], hat: [2, 6, 10, 14, 18, 22, 26, 30] } };
}

// made safe after loading
export function checkSong(x) {
  const n = (v, lo, hi, d) => { v = Number(v); return Number.isFinite(v) ? Math.min(hi, Math.max(lo, Math.round(v))) : d; };
  const s = x && typeof x === 'object' ? x : {}, steps = [16, 32, 48, 64].includes(s.steps) ? s.steps : 32;
  const scale = SCALES[s.scale] ? s.scale : 'penta', song = { bpm: n(s.bpm, 50, 220, 110), steps, scale, drums: {} };
  song.volume = Math.min(1.5, Math.max(0, Number(s.volume) || 0.8));
  for (const track of ['lead', 'bass']) {
    const t = s[track] || {}, max = rows(song, track).length - 1;
    song[track] = { wave: WAVES[t.wave] ? t.wave : track === 'lead' ? 'square' : 'triangle',
      notes: (Array.isArray(t.notes) ? t.notes : []).slice(0, 512).filter(Array.isArray)
        .map(([st, row, len]) => [n(st, 0, steps - 1, 0), n(row, 0, max, 0), n(len, 1, steps, 1)]) };
  }
  for (const [d] of DRUMS)
    song.drums[d] = [...new Set((Array.isArray((s.drums || {})[d]) ? s.drums[d] : []).map(v => n(v, 0, steps - 1, 0)))];
  return song;
}

export const stepSeconds = song => 60 / song.bpm / 4;

// the whole loop, as samples (mono, HZ); the notes end where the loop does, so it loops cleanly
export function renderSong(song) {
  const step = stepSeconds(song), total = Math.round(song.steps * step * HZ), out = new Float32Array(total);
  const tone = (track, gain, sustain) => {
    const r = rows(song, track), wave = song[track].wave;
    for (const [st, row, len] of song[track].notes) {
      const f = 440 * 2 ** ((r[row] - 69) / 12), a = Math.round(st * step * HZ);
      const n = Math.min(total - a, Math.round(len * step * HZ));
      let ph = 0;
      for (let i = 0; i < n; i++) {
        const t = i / HZ, left = (n - i) / HZ;
        const env = Math.min(1, t / 0.005) * (sustain + (1 - sustain) * Math.exp(-t / 0.08)) * Math.min(1, left / 0.02);
        const v = wave === 'square' ? (ph < 0.5 ? 1 : -1) * 0.6 : wave === 'saw' ? (2 * ph - 1) * 0.7
          : wave === 'triangle' ? 1 - 4 * Math.abs(ph - 0.5) : Math.sin(2 * Math.PI * ph);
        out[a + i] += v * env * gain;
        ph = (ph + f / HZ) % 1;
      }
    }
  };
  tone('lead', 0.22, 0.55);
  tone('bass', 0.3, 0.8);
  let seed = 0x9e3779b9; // the drums' noise, the same every time
  const noise = () => { seed ^= seed << 13; seed ^= seed >>> 17; seed ^= seed << 5; return (seed >>> 0) / 2147483648 - 1; };
  const hit = (steps, len, make) => {
    for (const st of steps) {
      const a = Math.round(st * step * HZ), n = Math.min(total - a, Math.round(len * HZ));
      let last = 0, ph = 0;
      for (let i = 0; i < n; i++) {
        const v = make(i / HZ, last, ph);
        last = v.raw ?? 0;
        ph = v.ph ?? 0;
        out[a + i] += v.out;
      }
    }
  };
  hit(song.drums.kick, 0.25, (t, _, ph) => { // a sine falling from 130 to 45 Hz
    const f = 45 + 85 * Math.exp(-t / 0.03);
    return { out: Math.sin(2 * Math.PI * ph) * Math.exp(-t / 0.12) * 0.6, ph: (ph + f / HZ) % 1 };
  });
  hit(song.drums.snare, 0.18, t => ({ out: (noise() * 0.7 + Math.sin(2 * Math.PI * 190 * t) * 0.3) * Math.exp(-t / 0.06) * 0.3 }));
  hit(song.drums.hat, 0.06, (t, last) => { const raw = noise(); return { out: (raw - last) * Math.exp(-t / 0.015) * 0.08, raw }; });
  for (let i = 0; i < total; i++) out[i] = Math.tanh(out[i] * song.volume * 1.2); // loud parts rounded, never clipped
  return out;
}
