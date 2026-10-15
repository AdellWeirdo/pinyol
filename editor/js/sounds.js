// The Sounds tab: a recipe and a seed (as sound() makes them), or the numbers moved by hand, heard at once; or a sound
// brought in from a file (an effect, or the music of a level), cut and made louder or softer.
import { safeName, uniqueName } from './project.js';
import { RECIPES, WAVES, recipe, render as renderSound, play } from './synth.js';
import { HZ, MAX_S, toBase64, samples, play as playClip, stop as stopClip } from './audio.js';
import { newSong } from './song.js';
import { renderComposer, composerPlays } from './composer.js';
import { t } from './i18n.js';

const $ = id => document.getElementById(id);
let app, cur = 0;

const SLIDERS = [
  [t('Tono (Hz)'), 'freq', 40, 2400, 1], [t('Deslizar el tono'), 'slide', -8000, 8000, 10], [t('Entrada'), 'attack', 0, 1, 0.01],
  [t('Duración'), 'sustain', 0, 1.5, 0.01], [t('Caída'), 'decay', 0, 2, 0.01], [t('Golpe|sonido'), 'punch', 0, 1, 0.01],
  [t('Vibrato'), 'vibrato', 0, 1, 0.01], [t('Velocidad del vibrato'), 'vibrato_speed', 0, 30, 0.1],
  [t('Salto de tono'), 'arp', 0.25, 3, 0.01], [t('Momento del salto'), 'arp_time', 0, 0.5, 0.005],
  [t('Quitar agudos'), 'lowpass', 0, 1, 0.01], [t('Quitar graves'), 'highpass', 0, 1, 0.01],
  [t('Repetir cada'), 'again', 0, 0.5, 0.005], [t('Volumen'), 'volume', 0, 1, 0.01],
];
const WAVE_NAMES = { square: t('cuadrada'), triangle: t('triangular'), saw: t('sierra'), sine: t('senoidal'), noise: t('ruido') };
// the name a new sound of a recipe gets: a name in the blocks and the game, so the same in any language (RECIPES: labels)
const RECIPE_NAMES = { coin: 'moneda', laser: 'laser', explosion: 'explosion', powerup: 'mejora', hit: 'golpe', jump: 'salto',
                       blip: 'bip', random: 'sorpresa' };

const sound = () => app.project.sounds[cur];
export function paramsOf(s) { return s.params ? { ...s.params } : recipe(s.recipe, s.seed); }
const hear = s => (s.mod ? undefined : s.song ? playClip(s).then(composerPlays) // a .mod sounds only in the game
  : s.file ? playClip(s).catch(() => app.oops(t('No se ha podido leer el sonido «{name}».', { name: s.name }))) : play(paramsOf(s)));

function drawWave(data, from = 0, to = data.length, note = '') { // the samples; outside from..to dimmed (cut away)
  const c = $('wave'), g = c.getContext('2d');
  c.width = c.clientWidth || 640;
  g.clearRect(0, 0, c.width, c.height);
  const step = Math.max(1, data.length / c.width);
  for (let x = 0; x < c.width; x++) {
    let lo = 0, hi = 0;
    for (let i = Math.floor(x * step); i < Math.min(data.length, (x + 1) * step); i++) lo = Math.min(lo, data[i]), hi = Math.max(hi, data[i]);
    const kept = x * step >= from && x * step < to;
    g.fillStyle = kept ? '#6cb4e0' : '#3a3150';
    g.fillRect(x, c.height / 2 - hi * c.height / 2, 1, (hi - lo) * c.height / 2 + 1);
  }
  g.fillStyle = '#9c90b0';
  g.font = '12px system-ui';
  const said = note || t('Dura {s} s', { s: (data.length / HZ).toFixed(2) });
  g.fillText(said, 8, 16);
  $('wave-note').textContent = said; // also as text: not only drawn
}

function renderList() {
  const ul = $('sounds'), focused = ul.contains(document.activeElement);
  ul.replaceChildren();
  app.project.sounds.forEach((s, i) => {
    const li = document.createElement('li'), b = document.createElement('button');
    const kind = s.song ? t('compuesta') : s.mod ? t('música .mod') : s.file ? (s.use === 'music' ? t('música') : t('archivo'))
      : s.params ? t('a mano') : RECIPES[s.recipe] || '';
    b.className = 'item';
    b.append(Object.assign(document.createElement('span'), { className: 'name', textContent: s.name }),
      Object.assign(document.createElement('span'), { className: 'kind', textContent: kind }));
    b.setAttribute('aria-current', String(i === cur));
    b.addEventListener('click', () => { cur = i; stopClip(); render(); if (s.use !== 'music') hear(s); });
    li.append(b);
    ul.append(li);
  });
  if (focused) ul.querySelector('[aria-current="true"]')?.focus();
}

function slider(box, label, value, min, max, step, onInput, show = v => Number(v).toFixed(2)) {
  const l = document.createElement('label'), out = document.createElement('output'), r = document.createElement('input');
  Object.assign(r, { type: 'range', min, max, step, value });
  out.textContent = show(value);
  r.addEventListener('input', () => { out.textContent = show(r.value); onInput(Number(r.value)); });
  l.append(label, out, r);
  box.append(l);
  return r;
}

function renderMade(s) { // a sound made from numbers
  const p = paramsOf(s), box = $('sliders');
  for (const b of $('recipes').children) b.setAttribute('aria-pressed', String(!s.params && b.dataset.r === s.recipe));
  const wave = document.createElement('label'), sel = document.createElement('select');
  wave.textContent = t('Onda');
  for (const w of WAVES) sel.append(new Option(WAVE_NAMES[w], w));
  sel.value = p.wave;
  sel.addEventListener('change', () => tweak('wave', sel.value));
  wave.append(sel);
  box.append(wave);
  for (const [label, key, min, max, step] of SLIDERS)
    slider(box, label, p[key], min, max, step, v => tweak(key, v, true), v => Number(v).toFixed(step < 1 ? 2 : 0))
      .addEventListener('change', () => play(paramsOf(sound())));
  drawWave(renderSound(p));
}

async function renderClip(s) { // a sound from a file: what it is for, the part kept, how loud
  const box = $('sliders');
  const use = document.createElement('label'), sel = document.createElement('select');
  use.textContent = t('Es');
  sel.append(new Option(t('un efecto: suena una vez (hasta 5 s)'), 'effect'), new Option(t('música: se repite (hasta 4 min)'), 'music'));
  sel.value = s.use;
  sel.addEventListener('change', () => { s.use = sel.value; app.forgetMusic(); app.changed(); render(); $('sliders').querySelector('select')?.focus(); });
  use.append(sel);
  box.append(use);
  let data;
  try { data = await samples(s); } catch { drawWave(new Float32Array(1), 0, 1, t('No se ha podido leer este sonido')); return; }
  if (sound() !== s) return; // another was chosen meanwhile
  const dur = data.length / HZ, secs = v => Number(v).toFixed(2) + ' s';
  const redraw = () => {
    const from = s.start * HZ, to = Math.min(s.end > s.start ? s.end * HZ : data.length, from + MAX_S[s.use] * HZ);
    const long = (s.end > s.start ? s.end : dur) - s.start > MAX_S[s.use];
    drawWave(data, from, to, t('{part} s de {all} s', { part: ((to - from) / HZ).toFixed(2), all: dur.toFixed(2) }) +
      (long ? ' · ' + t('se corta a los {n} s', { n: MAX_S[s.use] }) : ''));
  };
  slider(box, t('Empieza en'), s.start, 0, dur, 0.01, v => { s.start = Math.min(v, dur - 0.01); app.changed(); redraw(); }, secs);
  slider(box, t('Acaba en'), s.end > s.start ? s.end : dur, 0, dur, 0.01, v => { s.end = v >= dur - 0.005 ? 0 : v; app.changed(); redraw(); }, secs);
  slider(box, t('Volumen'), s.volume, 0, 2, 0.05, v => { s.volume = v; app.changed(); });
  redraw();
}

function render() {
  const has = app.project.sounds.length > 0;
  for (const id of ['s-name', 's-play', 's-again', 'sound-del']) $(id).disabled = !has;
  renderList();
  $('sliders').replaceChildren();
  $('composer').replaceChildren();
  if (!has) { $('wave').getContext('2d').clearRect(0, 0, 9999, 999); $('wave-note').textContent = ''; return; }
  cur = Math.min(cur, app.project.sounds.length - 1);
  const s = sound();
  $('s-name').value = s.name;
  $('recipes').hidden = $('recipes-title').hidden = $('s-again').hidden = !!(s.file || s.song);
  $('s-stop').hidden = !(s.file || s.song);
  $('wave').hidden = $('wave-note').hidden = !!(s.song || s.mod); // a song shows its notes instead
  $('s-play').disabled = !!s.mod;
  $('s-stop').hidden = !(s.file || s.song) || !!s.mod;
  if (s.song) renderComposer($('composer'), s, app);
  else if (s.mod) renderMod();
  else if (s.file) renderClip(s);
  else renderMade(s);
}

function tweak(key, value, quiet) { // the numbers by hand: the sound keeps them, the recipe is where it came from
  const s = sound();
  s.params = { ...paramsOf(s), [key]: value };
  app.changed();
  drawWave(renderSound(s.params));
  if (!quiet) { play(s.params); renderList(); }
}

function renderMod() { // the editor cannot play a tracker's module; the engine does
  $('sliders').append(Object.assign(document.createElement('p'), { className: 'hint',
    textContent: t('Música de tracker (.mod): se repite y ocupa muy poco. Aquí no suena: pulsa Jugar para oírla en el juego.') }));
}

// A tracker's module (a ProTracker .mod, from MilkyTracker, OpenMPT...): music kept as it is, for the engine to play
async function bringInMod(file) {
  if (file.size > 4 << 20) return app.oops(t('Ese .mod es demasiado grande: hasta 4 MB.'));
  const bytes = new Uint8Array(await file.arrayBuffer());
  if (bytes.length < 1084) return app.oops(t('«{file}» no parece un .mod de ProTracker.', { file: file.name })); // its header alone: 1084 bytes
  const names = new Set(app.project.sounds.map(x => x.name));
  app.project.sounds.push({ name: uniqueName(safeName(file.name.replace(/\.[^.]*$/, ''), 'musica'), names),
                            file: toBase64(bytes), use: 'music', mod: true });
  cur = app.project.sounds.length - 1;
  app.changed();
  render();
  app.toast(t('Añadida como música: elígela para un nivel en la pestaña Mapa.'));
}

async function bringIn(file) {
  if (!file) return;
  if (/\.mod$/i.test(file.name)) return bringInMod(file);
  if (!(/^audio\//.test(file.type) || /\.(wav|mp3|ogg|oga|m4a|aac|flac|opus|webm)$/i.test(file.name)))
    return app.oops(t('«{file}» no es un sonido. Usa un archivo WAV, MP3, OGG o M4A.', { file: file.name }));
  if (file.size > 16 << 20) return app.oops(t('Ese sonido es demasiado grande: hasta 16 MB.'));
  app.toast(t('Leyendo el sonido…'));
  const names = new Set(app.project.sounds.map(x => x.name));
  const s = { name: uniqueName(safeName((file.name || 'sonido').replace(/\.[^.]*$/, ''), 'sonido'), names),
              file: toBase64(new Uint8Array(await file.arrayBuffer())), use: 'effect', start: 0, end: 0, volume: 1 };
  let data;
  try { data = await samples(s); }
  catch { return app.oops(t('No se ha podido leer «{file}». Prueba con otro archivo o guárdalo como WAV o MP3.', { file: file.name })); }
  s.use = data.length / HZ > MAX_S.effect ? 'music' : 'effect'; // a long one is music
  app.project.sounds.push(s);
  cur = app.project.sounds.length - 1;
  app.changed();
  render();
  app.toast(s.use === 'music' ? t('Añadido como música: elígela para un nivel en la pestaña Mapa.') : t('Sonido añadido.'));
}

export function initSounds(ctx) {
  app = ctx;
  for (const [r, label] of Object.entries(RECIPES)) {
    const b = document.createElement('button');
    b.textContent = label, b.dataset.r = r;
    b.addEventListener('click', () => {
      if (!app.project.sounds.length || sound().file) add(r);
      const s = sound();
      s.recipe = r, s.seed = 1 + Math.floor(Math.random() * 99999), s.params = null;
      app.changed();
      render();
      play(paramsOf(s));
    });
    $('recipes').append(b);
  }
  const add = (r = 'blip') => {
    const names = new Set(app.project.sounds.map(s => s.name));
    app.project.sounds.push({ name: uniqueName(RECIPE_NAMES[r] || 'sonido', names), recipe: r, seed: 1 + Math.floor(Math.random() * 99999), params: null });
    cur = app.project.sounds.length - 1;
    app.changed();
  };
  $('sound-add').addEventListener('click', () => { add(); render(); play(paramsOf(sound())); });
  $('sound-file').addEventListener('change', e => { const f = e.target.files[0]; e.target.value = ''; bringIn(f); });
  const tab = $('tab-sound');
  tab.addEventListener('dragover', e => { e.preventDefault(); tab.classList.add('dropping'); });
  tab.addEventListener('dragleave', e => { if (e.target === tab) tab.classList.remove('dropping'); });
  tab.addEventListener('drop', e => { e.preventDefault(); tab.classList.remove('dropping'); bringIn(e.dataTransfer.files[0]); });
  $('s-play').addEventListener('click', () => hear(sound()));
  $('s-stop').addEventListener('click', () => { stopClip(); composerPlays(); });
  $('song-add').addEventListener('click', () => {
    const names = new Set(app.project.sounds.map(x => x.name));
    stopClip();
    app.project.sounds.push({ name: uniqueName('musica', names), song: newSong(), use: 'music' });
    cur = app.project.sounds.length - 1;
    app.changed();
    render();
    app.toast(t('Música nueva, con un ejemplo para empezar: cámbiala como quieras y elígela para un nivel en Mapa.'));
  });
  $('s-again').addEventListener('click', () => {
    const s = sound();
    s.seed = 1 + Math.floor(Math.random() * 99999), s.params = null;
    app.changed();
    render();
    play(paramsOf(s));
  });
  $('sound-del').addEventListener('click', () => {
    if (!confirm(t('¿Quitar el sonido «{name}»?', { name: sound().name }))) return;
    stopClip();
    app.project.sounds.splice(cur, 1);
    cur = Math.max(0, cur - 1);
    app.forgetMusic();
    app.changed();
    render();
  });
  $('s-name').addEventListener('change', e => {
    const s = sound(), names = new Set(app.project.sounds.filter(x => x !== s).map(x => x.name));
    const name = uniqueName(safeName(e.target.value, s.name), names);
    if (name !== s.name) app.renameSound(s.name, name);
    if (name !== e.target.value) app.toast(t('Se llama «{name}»: sin acentos ni espacios, así sale en los bloques.', { name }));
    app.changed();
    render();
  });
  return { render, reset: () => { cur = 0; stopClip(); render(); } };
}
