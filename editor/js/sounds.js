// The Sounds tab: a recipe and a seed (as sound() makes them), or the numbers moved by hand; heard at once.
import { safeName, uniqueName } from './project.js';
import { RECIPES, WAVES, recipe, render as renderSound, play } from './synth.js';

const $ = id => document.getElementById(id);
let app, cur = 0;

const SLIDERS = [
  ['Tono (Hz)', 'freq', 40, 2400, 1], ['Deslizar el tono', 'slide', -8000, 8000, 10], ['Entrada', 'attack', 0, 1, 0.01],
  ['Duración', 'sustain', 0, 1.5, 0.01], ['Caída', 'decay', 0, 2, 0.01], ['Golpe', 'punch', 0, 1, 0.01],
  ['Vibrato', 'vibrato', 0, 1, 0.01], ['Velocidad del vibrato', 'vibrato_speed', 0, 30, 0.1],
  ['Salto de tono', 'arp', 0.25, 3, 0.01], ['Momento del salto', 'arp_time', 0, 0.5, 0.005],
  ['Quitar agudos', 'lowpass', 0, 1, 0.01], ['Quitar graves', 'highpass', 0, 1, 0.01],
  ['Repetir cada', 'again', 0, 0.5, 0.005], ['Volumen', 'volume', 0, 1, 0.01],
];
const WAVE_NAMES = { square: 'cuadrada', triangle: 'triangular', saw: 'sierra', sine: 'senoidal', noise: 'ruido' };

const sound = () => app.project.sounds[cur];
export function paramsOf(s) { return s.params ? { ...s.params } : recipe(s.recipe, s.seed); }

function drawWave(p) {
  const c = $('wave'), g = c.getContext('2d'), data = renderSound(p);
  c.width = c.clientWidth || 640;
  g.clearRect(0, 0, c.width, c.height);
  g.strokeStyle = '#6cb4e0';
  g.beginPath();
  const step = Math.max(1, data.length / c.width);
  for (let x = 0; x < c.width; x++) {
    let lo = 0, hi = 0;
    for (let i = Math.floor(x * step); i < Math.min(data.length, (x + 1) * step); i++) lo = Math.min(lo, data[i]), hi = Math.max(hi, data[i]);
    g.moveTo(x + 0.5, c.height / 2 - hi * c.height / 2);
    g.lineTo(x + 0.5, c.height / 2 - lo * c.height / 2 + 1);
  }
  g.stroke();
  g.fillStyle = '#9c90b0';
  g.font = '12px system-ui';
  g.fillText((data.length / 22050).toFixed(2) + ' s', 8, 16);
}

function renderList() {
  const ul = $('sounds');
  ul.replaceChildren();
  app.project.sounds.forEach((s, i) => {
    const li = document.createElement('li');
    li.textContent = s.name;
    li.append(Object.assign(document.createElement('span'), { className: 'kind', textContent: s.params ? 'a mano' : RECIPES[s.recipe] || '' }));
    li.setAttribute('aria-current', String(i === cur));
    li.tabIndex = 0;
    li.addEventListener('click', () => { cur = i; render(); play(paramsOf(app.project.sounds[i])); });
    ul.append(li);
  });
}

function render() {
  const has = app.project.sounds.length > 0;
  for (const id of ['s-name', 's-play', 's-again', 'sound-del']) $(id).disabled = !has;
  renderList();
  if (!has) { $('sliders').replaceChildren(); $('wave').getContext('2d').clearRect(0, 0, 9999, 999); return; }
  cur = Math.min(cur, app.project.sounds.length - 1);
  const s = sound(), p = paramsOf(s);
  $('s-name').value = s.name;
  for (const b of $('recipes').children) b.setAttribute('aria-pressed', String(!s.params && b.dataset.r === s.recipe));
  const box = $('sliders');
  box.replaceChildren();
  const wave = document.createElement('label');
  wave.textContent = 'Onda';
  const sel = document.createElement('select');
  for (const w of WAVES) sel.append(new Option(WAVE_NAMES[w], w));
  sel.value = p.wave;
  sel.addEventListener('change', () => tweak('wave', sel.value));
  wave.append(sel);
  box.append(wave);
  for (const [label, key, min, max, step] of SLIDERS) {
    const l = document.createElement('label'), out = document.createElement('output'), r = document.createElement('input');
    Object.assign(r, { type: 'range', min, max, step, value: p[key] });
    out.textContent = Number(p[key]).toFixed(step < 1 ? 2 : 0);
    r.addEventListener('input', () => { out.textContent = Number(r.value).toFixed(step < 1 ? 2 : 0); tweak(key, Number(r.value), true); });
    r.addEventListener('change', () => play(paramsOf(sound())));
    l.append(label, out, r);
    box.append(l);
  }
  drawWave(p);
}

function tweak(key, value, quiet) { // the numbers by hand: the sound keeps them, the recipe is where it came from
  const s = sound();
  s.params = { ...paramsOf(s), [key]: value };
  app.changed();
  drawWave(s.params);
  if (!quiet) { play(s.params); renderList(); }
}

export function initSounds(ctx) {
  app = ctx;
  for (const [r, label] of Object.entries(RECIPES)) {
    const b = document.createElement('button');
    b.textContent = label, b.dataset.r = r;
    b.addEventListener('click', () => {
      if (!app.project.sounds.length) add(r);
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
    app.project.sounds.push({ name: uniqueName(safeName(RECIPES[r] || 'sonido'), names), recipe: r, seed: 1 + Math.floor(Math.random() * 99999), params: null });
    cur = app.project.sounds.length - 1;
    app.changed();
  };
  $('sound-add').addEventListener('click', () => { add(); render(); play(paramsOf(sound())); });
  $('s-play').addEventListener('click', () => play(paramsOf(sound())));
  $('s-again').addEventListener('click', () => {
    const s = sound();
    s.seed = 1 + Math.floor(Math.random() * 99999), s.params = null;
    app.changed();
    render();
    play(paramsOf(s));
  });
  $('sound-del').addEventListener('click', () => {
    if (!confirm(`¿Quitar el sonido «${sound().name}»?`)) return;
    app.project.sounds.splice(cur, 1);
    cur = Math.max(0, cur - 1);
    app.changed();
    render();
  });
  $('s-name').addEventListener('change', e => {
    const s = sound(), names = new Set(app.project.sounds.filter(x => x !== s).map(x => x.name));
    const name = uniqueName(safeName(e.target.value, s.name), names);
    if (name !== s.name) app.renameSound(s.name, name);
    app.changed();
    render();
  });
  return { render, reset: () => { cur = 0; render(); } };
}
