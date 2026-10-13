// The Map tab: tiles painted on a grid, objects put where they start, the map's size, its background colour and whom
// the camera follows. Shown at twice the world's pixels, as on the console's screen.
import { TILE, MAP_MAX } from './project.js';
import { drawPixels, thumbnail } from './sprites.js';

const $ = id => document.getElementById(id);
const S = 2; // screen pixels a world pixel
let app, piece = { type: 'erase' }, images = new Map(), painting = false;

function imageOf(d) { // each drawing as a small canvas, drawn scaled (fast, crisp)
  let c = images.get(d.name);
  if (!c) {
    c = document.createElement('canvas');
    c.width = d.w, c.height = d.h;
    drawPixels(c, d, 0);
    images.set(d.name, c);
  }
  return c;
}

const byName = name => app.project.drawings.find(d => d.name === name);

function render() {
  const p = app.project, m = p.map, c = $('map'), g = c.getContext('2d');
  images = new Map();
  c.width = m.w * TILE * S, c.height = m.h * TILE * S;
  g.imageSmoothingEnabled = false;
  g.fillStyle = p.background;
  g.fillRect(0, 0, c.width, c.height);
  for (let y = 0; y < m.h; y++)
    for (let x = 0; x < m.w; x++) {
      const t = m.cells[y * m.w + x], d = t && byName(m.tiles[t - 1]);
      if (d) g.drawImage(imageOf(d), x * TILE * S, y * TILE * S, d.w * S, d.h * S);
    }
  for (const o of p.objects) {
    const d = byName(o.kind);
    if (d) g.drawImage(imageOf(d), o.x * S, o.y * S, d.w * S, d.h * S);
    if (o.kind === p.camera) { g.strokeStyle = '#f2b233'; g.lineWidth = 2; g.strokeRect(o.x * S - 1, o.y * S - 1, (d ? d.w : 16) * S + 2, (d ? d.h : 16) * S + 2); }
  }
  g.strokeStyle = 'rgba(255,255,255,0.07)';
  g.lineWidth = 1;
  for (let x = 1; x < m.w; x++) { g.beginPath(); g.moveTo(x * TILE * S + 0.5, 0); g.lineTo(x * TILE * S + 0.5, c.height); g.stroke(); }
  for (let y = 1; y < m.h; y++) { g.beginPath(); g.moveTo(0, y * TILE * S + 0.5); g.lineTo(c.width, y * TILE * S + 0.5); g.stroke(); }
  g.strokeStyle = 'rgba(242,178,51,0.5)'; // what one screen shows
  g.strokeRect(0.5, 0.5, 240 * S - 1, 160 * S - 1);
}

function renderPieces() {
  const p = app.project;
  const box = (id, list, type) => {
    const el = $(id);
    el.replaceChildren();
    if (type === 'tile') el.append(pieceButton({ type: 'erase' }, null, 'Goma'));
    for (const d of list) el.append(pieceButton({ type, name: d.name }, d, d.name + (d.solid ? ' (sólida)' : '')));
    if (!list.length) el.append(Object.assign(document.createElement('p'), { className: 'hint', textContent: type === 'tile'
      ? 'Ningún dibujo es baldosa: márcalo en Dibujos.' : 'Ningún dibujo es objeto: márcalo en Dibujos.' }));
  };
  box('map-tiles', p.drawings.filter(d => d.use === 'tile'), 'tile');
  box('map-objects', p.drawings.filter(d => d.use === 'object'), 'object');
  $('map-w').value = p.map.w, $('map-h').value = p.map.h, $('map-bg').value = p.background;
  const cam = $('map-camera');
  cam.replaceChildren(new Option('(nadie: el primer jugador)', ''));
  for (const d of p.drawings.filter(d => d.use === 'object')) cam.append(new Option(d.name, d.name));
  cam.value = p.camera || '';
}

function pieceButton(pc, d, label) {
  const b = document.createElement('button');
  b.title = label;
  b.setAttribute('aria-label', label);
  if (d) b.append(thumbnail(d, 40));
  else b.textContent = '⌫';
  b.setAttribute('aria-pressed', String(pc.type === piece.type && pc.name === piece.name));
  b.addEventListener('click', () => { piece = pc; renderPieces(); });
  return b;
}

function at(e) {
  const r = $('map').getBoundingClientRect();
  return { x: (e.clientX - r.left) / S, y: (e.clientY - r.top) / S };
}

function objectAt(x, y) {
  for (let i = app.project.objects.length - 1; i >= 0; i--) {
    const o = app.project.objects[i], d = byName(o.kind) || { w: 16, h: 16 };
    if (x >= o.x && y >= o.y && x < o.x + d.w && y < o.y + d.h) return i;
  }
  return -1;
}

function setTile(x, y, name) {
  const m = app.project.map, tx = Math.floor(x / TILE), ty = Math.floor(y / TILE);
  if (tx < 0 || ty < 0 || tx >= m.w || ty >= m.h) return false;
  let v = 0;
  if (name) {
    v = m.tiles.indexOf(name) + 1;
    if (!v) { m.tiles.push(name); v = m.tiles.length; }
  }
  if (m.cells[ty * m.w + tx] === v) return false;
  m.cells[ty * m.w + tx] = v;
  return true;
}

function act(e, first) {
  const { x, y } = at(e), erase = e.buttons === 2 || piece.type === 'erase';
  const p = app.project;
  if (piece.type === 'object' && !erase) {
    if (!first) return;
    const hit = objectAt(x, y);
    if (hit >= 0) p.objects.splice(hit, 1);
    else {
      const d = byName(piece.name);
      p.objects.push({ kind: piece.name, x: Math.max(0, Math.round((x - d.w / 2) / 4) * 4), y: Math.max(0, Math.round((y - d.h / 2) / 4) * 4) });
    }
  } else if (erase) {
    const hit = objectAt(x, y);
    if (hit >= 0 && first) p.objects.splice(hit, 1);
    else if (!setTile(x, y, null)) return;
  } else if (!setTile(x, y, piece.name)) return;
  app.changed();
  render();
}

function resize(w, h) {
  const m = app.project.map;
  w = Math.max(15, Math.min(MAP_MAX, w | 0)), h = Math.max(10, Math.min(MAP_MAX, h | 0));
  const cells = new Array(w * h).fill(0);
  for (let y = 0; y < Math.min(h, m.h); y++) for (let x = 0; x < Math.min(w, m.w); x++) cells[y * w + x] = m.cells[y * m.w + x];
  Object.assign(m, { w, h, cells });
  app.changed();
  renderPieces();
  render();
}

export function initMap(ctx) {
  app = ctx;
  const c = $('map');
  c.addEventListener('pointerdown', e => { painting = true; c.setPointerCapture(e.pointerId); act(e, true); });
  c.addEventListener('pointermove', e => { if (painting && e.buttons) act(e, false); });
  c.addEventListener('pointerup', () => { painting = false; });
  c.addEventListener('contextmenu', e => e.preventDefault());
  $('map-w').addEventListener('change', e => resize(Number(e.target.value), app.project.map.h));
  $('map-h').addEventListener('change', e => resize(app.project.map.w, Number(e.target.value)));
  $('map-bg').addEventListener('input', e => { app.project.background = e.target.value; app.changed(); render(); });
  $('map-camera').addEventListener('change', e => { app.project.camera = e.target.value; app.changed(); render(); });
  return { render: () => { renderPieces(); render(); } };
}
