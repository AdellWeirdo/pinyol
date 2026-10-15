// Sounds brought in from files: decoded by the browser (WAV, MP3, OGG, M4A...), cut, made louder or softer, and made
// into what the console plays: a WAV, 16-bit, mono, 22 050 Hz. Effects are kept in the console's memory as they play,
// so they are short; music is read from the card as it plays, so it can be long.
import { renderSong } from './song.js';
import { t } from './i18n.js';

export const HZ = 22050;
export const MAX_S = { effect: 5, music: 240 };

let ctx = null, playing = null;
const audio = () => ctx || (ctx = new AudioContext());
const decoded = new Map(); // a file's text -> its samples at HZ: decoding takes a moment, the same file is decoded once

export function toBase64(bytes) {
  let s = '';
  for (let i = 0; i < bytes.length; i += 8192) s += String.fromCharCode.apply(null, bytes.subarray(i, i + 8192));
  return btoa(s);
}
function fromBase64(text) {
  const s = atob(text), b = new Uint8Array(s.length);
  for (let i = 0; i < s.length; i++) b[i] = s.charCodeAt(i);
  return b;
}

export async function samples(s) { // the whole file, mono at HZ
  if (decoded.has(s.file)) return decoded.get(s.file);
  const buf = await audio().decodeAudioData(fromBase64(s.file).buffer);
  const off = new OfflineAudioContext(1, Math.max(1, Math.ceil(buf.duration * HZ)), HZ); // mixed down, resampled
  const src = off.createBufferSource();
  src.buffer = buf;
  src.connect(off.destination);
  src.start();
  const out = (await off.startRendering()).getChannelData(0);
  decoded.set(s.file, out);
  return out;
}

export function cut(s, data) { // the part kept (start..end seconds, at most MAX_S), at its volume, its ends faded
  const a = Math.min(data.length - 1, Math.floor(s.start * HZ));
  const b = Math.min(data.length, s.end > s.start ? Math.floor(s.end * HZ) : data.length, a + MAX_S[s.use] * HZ);
  const part = data.slice(a, Math.max(a + 1, b)), fade = Math.min(110, part.length >> 1); // 5 ms: no click
  for (let i = 0; i < part.length; i++) {
    const edge = Math.min(1, i / fade, (part.length - 1 - i) / fade);
    part[i] *= s.volume * (s.use === 'music' ? 1 : edge); // music loops: its ends meet, unfaded
  }
  return part;
}

export function wav(part) {
  const n = part.length, b = new Uint8Array(44 + n * 2), v = new DataView(b.buffer);
  const tag = (at, t) => { for (let i = 0; i < 4; i++) b[at + i] = t.charCodeAt(i); };
  tag(0, 'RIFF'), v.setUint32(4, 36 + n * 2, true), tag(8, 'WAVE'), tag(12, 'fmt '), v.setUint32(16, 16, true);
  v.setUint16(20, 1, true), v.setUint16(22, 1, true), v.setUint32(24, HZ, true), v.setUint32(28, HZ * 2, true);
  v.setUint16(32, 2, true), v.setUint16(34, 16, true), tag(36, 'data'), v.setUint32(40, n * 2, true);
  for (let i = 0; i < n; i++) v.setInt16(44 + 2 * i, Math.max(-32768, Math.min(32767, Math.round(part[i] * 32767))), true);
  return b;
}

// the console's names: effects SFX_ (kept when a game is baked into its flash), music MUS_ (left on the card)
export const fileOf = s => (s.use === 'music' ? 'MUS_' : 'SFX_') + s.name;

export async function audioFiles(p) { // [[path, bytes]] of the sounds from files, and of the songs composed
  const out = [];
  for (const s of p.sounds.filter(x => x.song)) out.push([`audio/${fileOf(s)}.wav`, wav(renderSong(s.song))]);
  for (const s of p.sounds.filter(x => x.mod)) out.push([`audio/${fileOf(s)}.mod`, fromBase64(s.file)]); // music() plays it
  for (const s of p.sounds.filter(x => x.file && !x.mod)) {
    try { out.push([`audio/${fileOf(s)}.wav`, wav(cut(s, await samples(s)))]); }
    catch { throw new Error(t('no se ha podido leer el sonido «{name}»', { name: s.name })); }
  }
  return out;
}

export function stop() {
  if (playing) { try { playing.src.stop(); } catch { /* already over */ } }
  playing = null;
}

// as the game will play it: the part kept of a file, or a song (looping, from `offset` seconds)
export async function play(s, offset = 0) {
  stop();
  const part = s.song ? renderSong(s.song) : cut(s, await samples(s)), c = audio(), buf = c.createBuffer(1, part.length, HZ);
  buf.copyToChannel(part, 0);
  const src = c.createBufferSource();
  src.buffer = buf;
  src.loop = !!s.song;
  src.connect(c.destination);
  src.start(0, offset % buf.duration);
  playing = { src, start: c.currentTime - offset, duration: buf.duration };
  src.onended = () => { if (playing && playing.src === src) playing = null; };
}

export function position() { // seconds into what plays (a song: within its loop), or -1
  return playing ? (audio().currentTime - playing.start) % playing.duration : -1;
}
