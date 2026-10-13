// The Drawings tab: pixel by pixel, in the project's palette, with frames for animation; and what each drawing is
// for (a tile of the map, solid or not, or an object that moves in some way).
import { PALETTE, BEHAVIOURS, SIZES, blankFrame, safeName, uniqueName } from './project.js';

const $ = id => document.getElementById(id);
let app, cur = 0, frame = 0, tool = 'pen', colour = 19;
const undo = new Map(), redo = new Map(); // drawing name -> stacks of frames

export function drawPixels(canvas, d, f, scale = 1) { // a frame onto a canvas (cleared), each pixel scale x scale
  const g = canvas.getContext('2d');
  g.clearRect(0, 0, canvas.width, canvas.height);
  const px = d.frames[f] || d.frames[0];
  for (let y = 0; y < d.h; y++)
    for (let x = 0; x < d.w; x++) {
      const c = px[y * d.w + x];
      if (c >= 0) { g.fillStyle = PALETTE[c]; g.fillRect(x * scale, y * scale, scale, scale); }
    }
}

export function thumbnail(d, size = 32) {
  const c = document.createElement('canvas');
  c.width = d.w, c.height = d.h;
  drawPixels(c, d, 0);
  c.style.width = c.style.height = size + 'px';
  return c;
}

const drawing = () => app.project.drawings[cur];

function snapshot() { // before a change: for undo
  const d = drawing();
  if (!d) return;
  if (!undo.has(d.name)) undo.set(d.name, []);
  const u = undo.get(d.name);
  u.push(JSON.stringify({ w: d.w, h: d.h, frames: d.frames }));
  if (u.length > 60) u.shift();
  redo.set(d.name, []);
}

function restore(from, to) {
  const d = drawing();
  const stack = from.get(d.name);
  if (!stack || !stack.length) return;
  if (!to.has(d.name)) to.set(d.name, []);
  to.get(d.name).push(JSON.stringify({ w: d.w, h: d.h, frames: d.frames }));
  Object.assign(d, JSON.parse(stack.pop()));
  frame = Math.min(frame, d.frames.length - 1);
  changed();
}

function changed() { app.changed(); render(); }

// ------------------------------------------------------------------ drawing on the big canvas

function cellAt(e) {
  const c = $('pixels'), r = c.getBoundingClientRect(), d = drawing();
  const x = Math.floor((e.clientX - r.left) / r.width * d.w), y = Math.floor((e.clientY - r.top) / r.height * d.h);
  return x >= 0 && y >= 0 && x < d.w && y < d.h ? { x, y } : null;
}

function fill(d, f, x, y, to) {
  const px = d.frames[f], from = px[y * d.w + x];
  if (from === to) return;
  const todo = [[x, y]];
  while (todo.length) {
    const [cx, cy] = todo.pop();
    if (cx < 0 || cy < 0 || cx >= d.w || cy >= d.h || px[cy * d.w + cx] !== from) continue;
    px[cy * d.w + cx] = to;
    todo.push([cx + 1, cy], [cx - 1, cy], [cx, cy + 1], [cx, cy - 1]);
  }
}

function paint(e, first) {
  const d = drawing(), at = cellAt(e);
  if (!d || !at) return;
  const px = d.frames[frame], i = at.y * d.w + at.x;
  if (tool === 'pick') { if (px[i] >= 0) setColour(px[i]); setTool('pen'); return; }
  if (first) snapshot();
  if (tool === 'fill') { if (first) fill(d, frame, at.x, at.y, colour); }
  else px[i] = tool === 'erase' || e.buttons === 2 ? -1 : colour;
  app.changed();
  renderCanvas();
}

function renderCanvas() {
  const d = drawing(), c = $('pixels');
  if (!d) return;
  const s = Math.floor(384 / Math.max(d.w, d.h));
  c.width = d.w * s, c.height = d.h * s;
  drawPixels(c, d, frame, s);
  const g = c.getContext('2d');
  g.strokeStyle = 'rgba(255,255,255,0.08)';
  for (let i = 1; i < d.w; i++) { g.beginPath(); g.moveTo(i * s + 0.5, 0); g.lineTo(i * s + 0.5, c.height); g.stroke(); }
  for (let i = 1; i < d.h; i++) { g.beginPath(); g.moveTo(0, i * s + 0.5); g.lineTo(c.width, i * s + 0.5); g.stroke(); }
  renderFrames();
  const li = $('drawings').children[cur];
  if (li) { const t = li.querySelector('canvas'); if (t) drawPixels(t, d, 0); }
}

// ------------------------------------------------------------------ the rest of the tab

function renderList() {
  const ul = $('drawings');
  ul.replaceChildren();
  app.project.drawings.forEach((d, i) => {
    const li = document.createElement('li');
    li.append(thumbnail(d));
    li.append(Object.assign(document.createElement('span'), { textContent: d.name }));
    li.append(Object.assign(document.createElement('span'), { className: 'kind', textContent: d.use === 'object' ? 'objeto' : (d.solid ? 'sólida' : 'baldosa') }));
    li.setAttribute('aria-current', String(i === cur));
    li.tabIndex = 0;
    li.addEventListener('click', () => select(i));
    li.addEventListener('keydown', e => { if (e.key === 'Enter') select(i); });
    ul.append(li);
  });
}

function renderFrames() {
  const d = drawing(), box = $('frames');
  box.replaceChildren();
  d.frames.forEach((_, f) => {
    const c = document.createElement('canvas');
    c.width = d.w, c.height = d.h;
    drawPixels(c, d, f);
    c.setAttribute('aria-current', String(f === frame));
    c.title = 'Fotograma ' + (f + 1);
    c.addEventListener('click', () => { frame = f; renderCanvas(); });
    box.append(c);
  });
  $('frame-del').disabled = d.frames.length < 2;
  $('frame-add').disabled = d.frames.length >= 8;
}

function renderProps() {
  const d = drawing();
  $('d-name').value = d.name;
  $('d-size').value = String(d.w);
  for (const r of document.querySelectorAll('input[name=use]')) r.checked = r.value === d.use;
  $('d-solid').checked = d.solid;
  $('d-solid').disabled = d.use !== 'tile';
  $('object-props').hidden = d.use !== 'object';
  $('d-behaviour').value = d.behaviour;
  for (const k of ['speed', 'jump', 'animate']) { $('d-' + k).value = d[k]; $('o-' + k).textContent = d[k]; }
  $('drawing-del').disabled = app.project.drawings.length < 2;
}

function render() {
  if (!app.project.drawings.length) return;
  cur = Math.min(cur, app.project.drawings.length - 1);
  renderList();
  renderCanvas();
  renderProps();
}

function select(i) { cur = i; frame = 0; render(); }

function setTool(t) {
  tool = t;
  for (const b of document.querySelectorAll('[data-tool]')) b.setAttribute('aria-pressed', String(b.dataset.tool === t));
}

function setColour(i) {
  colour = i;
  for (const b of $('palette').children) b.setAttribute('aria-pressed', String(Number(b.dataset.c) === i));
  if (tool === 'erase' || tool === 'pick') setTool('pen');
}

function resize(d, size) {
  const frames = d.frames.map(f => {
    const n = blankFrame(size, size);
    for (let y = 0; y < Math.min(size, d.h); y++) for (let x = 0; x < Math.min(size, d.w); x++) n[y * size + x] = f[y * d.w + x];
    return n;
  });
  Object.assign(d, { w: size, h: size, frames });
}

let anim = 0, last = 0;
function animate(t) { // the preview, at the drawing's animation speed
  const d = drawing();
  if (d && document.getElementById('tab-draw').hidden === false) {
    const ticks = Math.max(1, d.animate || 8);
    if (t - last > ticks * 1000 / 60) { last = t; anim = (anim + 1) % d.frames.length; }
    drawPixels($('preview'), d, anim % d.frames.length, 64 / Math.max(d.w, d.h));
  }
  requestAnimationFrame(animate);
}

export function initDrawings(ctx) {
  app = ctx;
  const pal = $('palette');
  PALETTE.forEach((hex, i) => {
    const b = document.createElement('button');
    b.style.background = hex, b.dataset.c = i, b.title = hex;
    b.setAttribute('aria-label', 'Color ' + hex);
    b.addEventListener('click', () => setColour(i));
    pal.append(b);
  });
  setColour(colour);
  for (const [k, label] of Object.entries(BEHAVIOURS)) $('d-behaviour').append(new Option(label, k));
  for (const b of document.querySelectorAll('[data-tool]')) b.addEventListener('click', () => setTool(b.dataset.tool));
  const c = $('pixels');
  c.addEventListener('pointerdown', e => { c.setPointerCapture(e.pointerId); paint(e, true); });
  c.addEventListener('pointermove', e => { if (e.buttons && tool !== 'fill' && tool !== 'pick') paint(e, false); });
  c.addEventListener('contextmenu', e => e.preventDefault());
  $('undo').addEventListener('click', () => restore(undo, redo));
  $('redo').addEventListener('click', () => restore(redo, undo));
  addEventListener('keydown', e => {
    if (document.getElementById('tab-draw').hidden || e.target.matches('input, select, textarea')) return;
    if ((e.ctrlKey || e.metaKey) && e.key.toLowerCase() === 'z') { e.preventDefault(); restore(e.shiftKey ? redo : undo, e.shiftKey ? undo : redo); }
    else if ((e.ctrlKey || e.metaKey) && e.key.toLowerCase() === 'y') { e.preventDefault(); restore(redo, undo); }
    else if (!e.ctrlKey && !e.metaKey) {
      const t = { p: 'pen', e: 'erase', f: 'fill', i: 'pick' }[e.key.toLowerCase()];
      if (t) setTool(t);
    }
  });
  $('flip').addEventListener('click', () => {
    const d = drawing();
    snapshot();
    d.frames[frame] = d.frames[frame].map((_, i) => d.frames[frame][Math.floor(i / d.w) * d.w + (d.w - 1 - i % d.w)]);
    changed();
  });
  $('clear').addEventListener('click', () => { const d = drawing(); snapshot(); d.frames[frame] = blankFrame(d.w, d.h); changed(); });
  $('frame-add').addEventListener('click', () => {
    const d = drawing();
    if (d.frames.length >= 8) return;
    snapshot();
    d.frames.splice(frame + 1, 0, d.frames[frame].slice());
    frame++;
    changed();
  });
  $('frame-del').addEventListener('click', () => {
    const d = drawing();
    if (d.frames.length < 2) return;
    snapshot();
    d.frames.splice(frame, 1);
    frame = Math.max(0, frame - 1);
    changed();
  });
  $('drawing-add').addEventListener('click', () => {
    const names = new Set(app.project.drawings.map(d => d.name));
    app.project.drawings.push({ name: uniqueName('dibujo', names), w: 16, h: 16, frames: [blankFrame(16, 16)], use: 'tile',
                                solid: false, behaviour: 'still', speed: 1, jump: 4.5, animate: 8 });
    select(app.project.drawings.length - 1);
    app.changed();
  });
  $('drawing-del').addEventListener('click', () => {
    const d = drawing();
    if (app.project.drawings.length < 2 || !confirm(`¿Quitar «${d.name}»? También sale del mapa.`)) return;
    app.remove(d.name);
    cur = Math.max(0, cur - 1);
    changed();
  });
  $('d-name').addEventListener('change', e => {
    const d = drawing(), names = new Set(app.project.drawings.filter(x => x !== d).map(x => x.name));
    const name = uniqueName(safeName(e.target.value, d.name), names);
    if (name !== d.name) { undo.delete(d.name); app.rename(d.name, name); }
    changed();
  });
  $('d-size').addEventListener('change', e => {
    const size = Number(e.target.value);
    if (!SIZES.includes(size)) return;
    snapshot();
    resize(drawing(), size);
    changed();
  });
  for (const r of document.querySelectorAll('input[name=use]'))
    r.addEventListener('change', () => { drawing().use = r.value; if (r.value === 'object') drawing().solid = false; app.uses(); changed(); });
  $('d-solid').addEventListener('change', e => { drawing().solid = e.target.checked; changed(); });
  $('d-behaviour').addEventListener('change', e => { drawing().behaviour = e.target.value; changed(); });
  for (const k of ['speed', 'jump', 'animate'])
    $('d-' + k).addEventListener('input', e => { drawing()[k] = Number(e.target.value); $('o-' + k).textContent = e.target.value; app.changed(); });
  requestAnimationFrame(animate);
  return { render, reset: () => { cur = 0; frame = 0; undo.clear(); redo.clear(); render(); } };
}
