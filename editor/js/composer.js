// The composer: a song (song.js) as a grid, steps left to right, the melody's notes above, the bass's under them, the
// drums at the bottom. A click puts a note (dragged right, it lasts longer) or takes it away; the keyboard does the same
// (arrows, Space, Shift+Right to lengthen). While it plays, a line shows where it is, and changes are heard at once.
import { rows, noteName, SCALE_NAMES, WAVES, DRUMS, stepSeconds } from './song.js';
import { play, stop, position } from './audio.js';
import { t } from './i18n.js';

const $ = id => document.getElementById(id);
const CW = 18, RH = 16, LABEL = 52, GAP = 12; // a step's width, a row's height, the names' column, between the parts
const COLOURS = { lead: '#ffc94a', bass: '#6cb4e0', drums: '#e86fa8' };
let app, s, cur = { part: 'lead', row: 0, step: 0 }, drag = null, raf = 0, stretch = false; // stretch: taps lengthen

function layout() { // each part's first row and how many: lead, bass, drums
  const lead = rows(s.song, 'lead').length, bass = rows(s.song, 'bass').length;
  return { lead: { y: 0, n: lead }, bass: { y: lead * RH + GAP, n: bass }, drums: { y: (lead + bass) * RH + 2 * GAP, n: DRUMS.length } };
}

function cellAt(e) {
  const c = $('song-grid'), r = c.getBoundingClientRect();
  const x = (e.clientX - r.left) * c.width / r.width, y = (e.clientY - r.top) * c.height / r.height;
  const step = Math.floor((x - LABEL) / CW);
  if (step < 0 || step >= s.song.steps) return null;
  for (const [part, p] of Object.entries(layout())) {
    const row = Math.floor((y - p.y) / RH);
    if (row >= 0 && row < p.n && y >= p.y) return { part, row, step };
  }
  return null;
}

const noteAt = (track, row, step) => s.song[track].notes.findIndex(([st, r, len]) => r === row && step >= st && step < st + len);

function toggle(at) { // a note put or taken away; returns what a drag does next: 'add' (lengthen) or 'remove'
  if (at.part === 'drums') {
    const list = s.song.drums[DRUMS[at.row][0]], i = list.indexOf(at.step);
    if (i >= 0) { list.splice(i, 1); return 'remove'; }
    list.push(at.step);
    return 'add';
  }
  const notes = s.song[at.part].notes, i = noteAt(at.part, at.row, at.step);
  if (i >= 0) { notes.splice(i, 1); return 'remove'; }
  notes.push([at.step, at.row, 1]);
  return 'add';
}

function stretchTo(at) { // "Alargar notas": the note before `at` in its row reaches it (a tap does what a drag does)
  if (at.part === 'drums') return toggle(at);
  const before = s.song[at.part].notes.filter(([st, r]) => r === at.row && st <= at.step).sort((a, b) => b[0] - a[0])[0];
  if (!before) return toggle(at);
  before[2] = at.step - before[0] + 1;
  return 'add';
}

function lengthen(at, from) { // the note started at `from` reaches `at`
  if (at.part !== from.part || at.row !== from.row) return;
  if (at.part === 'drums') {
    const list = s.song.drums[DRUMS[at.row][0]];
    if (!list.includes(at.step)) list.push(at.step);
    return;
  }
  const n = s.song[at.part].notes.find(([st, r]) => st === from.step && r === from.row);
  if (n && at.step >= n[0]) n[2] = at.step - n[0] + 1;
}

function edited() {
  app.changed();
  draw();
  if (position() >= 0) play(s, position()); // heard at once, from where it was
}

function draw() {
  const c = $('song-grid'), L = layout(), w = LABEL + s.song.steps * CW, h = L.drums.y + L.drums.n * RH;
  if (c.width !== w || c.height !== h) c.width = w, c.height = h;
  const g = c.getContext('2d');
  g.fillStyle = '#0b0e1f';
  g.fillRect(0, 0, w, h);
  g.font = '11px system-ui';
  g.textBaseline = 'middle';
  const part = (name, p, labels) => {
    for (let r = 0; r < p.n; r++) {
      g.fillStyle = r % 2 ? '#1d1928' : '#221d2e';
      g.fillRect(LABEL, p.y + r * RH, s.song.steps * CW, RH);
      g.fillStyle = '#9c90b0';
      g.fillText(labels[r], 4, p.y + r * RH + RH / 2);
    }
    for (let st = 0; st <= s.song.steps; st++) { // beats, and bars stronger
      g.fillStyle = st % 16 === 0 ? '#5a4d72' : st % 4 === 0 ? '#3a3150' : '#2b2539';
      g.fillRect(LABEL + st * CW, p.y, 1, p.n * RH);
    }
    g.fillStyle = COLOURS[name];
    if (name === 'drums')
      DRUMS.forEach(([d], r) => s.song.drums[d].forEach(st => g.fillRect(LABEL + st * CW + 3, p.y + r * RH + 3, CW - 6, RH - 6)));
    else for (const [st, r, len] of s.song[name].notes) g.fillRect(LABEL + st * CW + 1, p.y + r * RH + 2, len * CW - 2, RH - 4);
  };
  part('lead', L.lead, rows(s.song, 'lead').map(noteName));
  part('bass', L.bass, rows(s.song, 'bass').map(noteName));
  part('drums', L.drums, DRUMS.map(([, label]) => label));
  if (document.activeElement === c) { // the keyboard's cursor
    g.strokeStyle = '#ffffff';
    g.lineWidth = 2;
    g.strokeRect(LABEL + cur.step * CW + 1, L[cur.part].y + cur.row * RH + 1, CW - 2, RH - 2);
  }
  const at = position(); // where it plays
  if (at >= 0) {
    g.fillStyle = '#ffffffaa';
    g.fillRect(LABEL + at / stepSeconds(s.song) * CW, 0, 2, h);
  }
}

function tick() { // the line follows the music while it plays
  cancelAnimationFrame(raf);
  if (!s || !$('song-grid') || !$('song-grid').isConnected) return;
  draw();
  if (position() >= 0) raf = requestAnimationFrame(tick);
}

function keys(e) {
  const L = layout(), order = ['lead', 'bass', 'drums'];
  const move = { ArrowLeft: [0, -1], ArrowRight: [0, 1], ArrowUp: [-1, 0], ArrowDown: [1, 0] }[e.key];
  if (move && e.shiftKey && e.key === 'ArrowRight' && cur.part !== 'drums') { // the note under the cursor, longer
    const i = noteAt(cur.part, cur.row, cur.step);
    if (i >= 0) { s.song[cur.part].notes[i][2] = Math.min(s.song.steps - s.song[cur.part].notes[i][0], s.song[cur.part].notes[i][2] + 1); edited(); }
  } else if (move) {
    cur.step = Math.max(0, Math.min(s.song.steps - 1, cur.step + move[1]));
    let row = cur.row + move[0], p = order.indexOf(cur.part);
    if (row < 0 && p > 0) cur.part = order[p - 1], row = L[cur.part].n - 1; // up into the part above
    else if (row >= L[cur.part].n && p < 2) cur.part = order[p + 1], row = 0;
    cur.row = Math.max(0, Math.min(L[cur.part].n - 1, row));
    draw();
  } else if (e.key === ' ') { toggle(cur); edited(); }
  else if (e.key === 'Enter') { if (position() >= 0) stop(); else play(s).then(tick); draw(); }
  else return;
  e.preventDefault();
}

function control(label, el) {
  const l = document.createElement('label');
  l.append(label, el);
  return l;
}
function select(options, value, set) {
  const sel = document.createElement('select');
  for (const [v, t] of Object.entries(options)) sel.append(new Option(t, v));
  sel.value = value;
  sel.addEventListener('change', () => { set(sel.value); edited(); });
  return sel;
}

// the composer, in `box`, for the sound `sound` (with its song)
export function renderComposer(box, sound, ctx) {
  app = ctx, s = sound;
  const tempo = Object.assign(document.createElement('input'), { type: 'range', min: 50, max: 220, step: 1, value: s.song.bpm });
  const perMinute = () => t('{n} por minuto', { n: s.song.bpm });
  const out = Object.assign(document.createElement('output'), { textContent: perMinute() });
  tempo.addEventListener('input', () => { s.song.bpm = Number(tempo.value); out.textContent = perMinute(); edited(); });
  const tempoLabel = control(t('Velocidad'), tempo);
  tempoLabel.insertBefore(out, tempo);
  const lengths = { 16: t('1 compás (16 pasos)'), 32: t('{n} compases', { n: 2 }), 48: t('{n} compases', { n: 3 }),
                    64: t('{n} compases', { n: 4 }) };
  const controls = document.createElement('div');
  controls.className = 'sliders';
  controls.append(tempoLabel,
    control(t('Largo'), select(lengths, String(s.song.steps), v => {
      s.song.steps = Number(v);
      for (const t of ['lead', 'bass']) s.song[t].notes = s.song[t].notes.filter(([st]) => st < s.song.steps);
      for (const [d] of DRUMS) s.song.drums[d] = s.song.drums[d].filter(st => st < s.song.steps);
    })),
    control(t('Escala'), select(SCALE_NAMES, s.song.scale, v => {
      s.song.scale = v;
      for (const t of ['lead', 'bass']) { const max = rows(s.song, t).length - 1; for (const n of s.song[t].notes) n[1] = Math.min(n[1], max); }
    })),
    control(t('Melodía'), select(WAVES, s.song.lead.wave, v => { s.song.lead.wave = v; })),
    control(t('Bajo'), select(WAVES, s.song.bass.wave, v => { s.song.bass.wave = v; })));
  const scroll = document.createElement('div');
  scroll.className = 'song-scroll';
  const grid = Object.assign(document.createElement('canvas'), { id: 'song-grid', tabIndex: 0 });
  grid.setAttribute('role', 'application');
  grid.setAttribute('aria-roledescription', t('partitura'));
  grid.setAttribute('aria-label', t('La música: melodía arriba, bajo en medio, batería abajo'));
  grid.setAttribute('aria-describedby', 'song-help');
  scroll.append(grid);
  const help = Object.assign(document.createElement('p'), { id: 'song-help', className: 'hint',
    textContent: t('Clic para poner o quitar una nota; arrástrala a la derecha para que dure más.') + ' ' +
                 t('Con el teclado: flechas, Espacio pone o quita, Mayús+→ alarga, Intro escucha o para.') + ' ' +
                 t('Amarillo: melodía. Azul: bajo. Rosa: batería.') });
  const longer = Object.assign(document.createElement('button'), { type: 'button', textContent: '↔ ' + t('Alargar notas') });
  longer.setAttribute('aria-pressed', String(stretch));
  longer.title = t('Mientras está pulsado, tocar una casilla alarga hasta ella la nota de su izquierda');
  longer.addEventListener('click', () => { stretch = !stretch; longer.setAttribute('aria-pressed', String(stretch)); });
  controls.append(longer);
  box.append(controls, scroll, help);
  grid.addEventListener('pointerdown', e => {
    if (!e.isPrimary) return;
    const at = cellAt(e);
    if (!at) return;
    if (stretch) { stretchTo(at); edited(); return; }
    if (e.pointerType === 'mouse' || e.pointerType === 'pen') grid.setPointerCapture(e.pointerId); // a finger may scroll
    drag = { from: at, mode: toggle(at) };
    edited();
  });
  grid.addEventListener('pointermove', e => {
    if (!drag || !e.buttons) return;
    const at = cellAt(e);
    if (at && drag.mode === 'add') { lengthen(at, drag.from); draw(); }
  });
  grid.addEventListener('pointerup', () => { if (drag) { drag = null; edited(); } });
  grid.addEventListener('pointercancel', () => { drag = null; }); // the finger scrolled instead
  grid.addEventListener('keydown', keys);
  grid.addEventListener('focus', draw);
  grid.addEventListener('blur', draw);
  draw();
  if (position() >= 0) tick();
}

export function composerPlays() { tick(); } // after Escuchar: the line starts moving
