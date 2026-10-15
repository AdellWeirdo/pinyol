// The Map tab: the game's levels in the order they are played, and its cover. A level is tiles painted on a grid,
// objects put where they start, its size, background colour, the pictures behind it and whom the camera follows;
// shown at twice the world's pixels, as on the console's screen. The cover is the title screen before them.
import { MAP_MAX, LEVELS_MAX, FONTS, LANGS, newLevel, uniqueName, lookOf } from './project.js';
import { drawPixels, thumbnail } from './sprites.js';
import { t } from './i18n.js';

const $ = id => document.getElementById(id);
const S = 2; // screen pixels a world pixel
let app, piece = null, images = new Map(), painting = false; // piece: what a click puts (the first tile at first)
let sel = 0; // the level shown, or -1: the cover
let kb = { x: 0, y: 0 }; // the keyboard's cursor, in tiles
const undo = [], redo = []; // the level's map and objects before each change (any level: the snapshot says which)

const level = () => app.project.levels[sel];
const T = () => app.project.tile || 16; // the map's grid, in the world's pixels (the look's tiles: 16 or 8)
const MIN = () => [240 / T(), 160 / T()]; // a map at least as big as the screen, in tiles
const byName = name => app.project.drawings.find(d => d.name === name);
const isPlayer = kind => { const d = byName(kind); return d && (d.behaviour === 'platformer' || d.behaviour === 'topdown'); };

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

function backdropsOf(l) { // the pictures behind a level, nearest first (at most three: the console's layers 1 to 3)
  return app.project.drawings.filter(d => d.use === 'backdrop' && !l.hide.includes(d.name)).slice(0, 3);
}

// ------------------------------------------------------------------ a level

function renderMap() {
  const p = app.project, l = level(), m = l.map, c = $('map'), g = c.getContext('2d');
  c.width = m.w * T() * S, c.height = m.h * T() * S;
  g.imageSmoothingEnabled = false;
  g.fillStyle = l.background;
  g.fillRect(0, 0, c.width, c.height);
  for (const d of backdropsOf(l).reverse()) { // farthest first, as in the game
    g.save();
    g.scale(S, S);
    g.fillStyle = g.createPattern(imageOf(d), 'repeat');
    g.fillRect(0, 0, m.w * T(), m.h * T());
    g.restore();
  }
  for (let y = 0; y < m.h; y++)
    for (let x = 0; x < m.w; x++) {
      const cell = m.cells[y * m.w + x], d = cell && byName(m.tiles[cell - 1]);
      if (d) g.drawImage(imageOf(d), x * T() * S, y * T() * S, d.w * S, d.h * S);
    }
  for (const o of l.objects) {
    const d = byName(o.kind);
    if (d) g.drawImage(imageOf(d), o.x * S, o.y * S, d.w * S, d.h * S);
    if (o.kind === l.camera) { g.strokeStyle = '#ffc94a'; g.lineWidth = 2; g.strokeRect(o.x * S - 1, o.y * S - 1, (d ? d.w : 16) * S + 2, (d ? d.h : 16) * S + 2); }
  }
  g.strokeStyle = 'rgba(255,255,255,0.07)';
  g.lineWidth = 1;
  for (let x = 1; x < m.w; x++) { g.beginPath(); g.moveTo(x * T() * S + 0.5, 0); g.lineTo(x * T() * S + 0.5, c.height); g.stroke(); }
  for (let y = 1; y < m.h; y++) { g.beginPath(); g.moveTo(0, y * T() * S + 0.5); g.lineTo(c.width, y * T() * S + 0.5); g.stroke(); }
  g.strokeStyle = 'rgba(242,178,51,0.5)'; // what one screen shows
  g.strokeRect(0.5, 0.5, 240 * S - 1, 160 * S - 1);
  if (document.activeElement === c) { // the keyboard's cursor
    kb = { x: Math.min(kb.x, m.w - 1), y: Math.min(kb.y, m.h - 1) };
    g.strokeStyle = '#6cb4e0';
    g.lineWidth = 2;
    g.strokeRect(kb.x * T() * S + 1, kb.y * T() * S + 1, T() * S - 2, T() * S - 2);
  }
}

function renderPieces() {
  const p = app.project, l = level();
  const box = (id, list, type) => {
    const el = $(id);
    el.replaceChildren();
    if (type === 'tile') el.append(pieceButton({ type: 'erase' }, null, t('Goma')));
    for (const d of list) el.append(pieceButton({ type, name: d.name }, d, d.solid ? t('{name} (sólida)', { name: d.name }) : d.name));
    if (!list.length) el.append(Object.assign(document.createElement('p'), { className: 'hint', textContent: type === 'tile'
      ? t('Ningún dibujo es baldosa: marca uno en Dibujos.') : t('Ningún dibujo es objeto: marca uno en Dibujos.') }));
  };
  const tilesNow = p.drawings.filter(d => d.use === 'tile'), objectsNow = p.drawings.filter(d => d.use === 'object');
  if (!piece || (piece.type !== 'erase' && !p.drawings.some(d => d.name === piece.name && d.use === piece.type)))
    piece = tilesNow.length ? { type: 'tile', name: tilesNow[0].name } : objectsNow.length ? { type: 'object', name: objectsNow[0].name } : { type: 'erase' };
  box('map-tiles', tilesNow, 'tile');
  box('map-objects', p.drawings.filter(d => d.use === 'object'), 'object');
  $('level-name').value = l.name;
  $('level-up').disabled = sel === 0;
  $('level-down').disabled = sel === p.levels.length - 1;
  $('level-del').disabled = p.levels.length < 2;
  $('map-w').value = l.map.w, $('map-h').value = l.map.h, $('map-bg').value = l.background;
  [$('map-w').min, $('map-h').min] = MIN();
  const cam = $('map-camera');
  cam.replaceChildren(new Option(t('(el jugador)'), ''));
  for (const d of p.drawings.filter(d => d.use === 'object')) cam.append(new Option(d.name, d.name));
  cam.value = l.camera || '';
  musicSelect($('map-music'), l.music);
  const bds = $('map-backdrops'), all = p.drawings.filter(d => d.use === 'backdrop');
  bds.replaceChildren();
  bds.hidden = !all.length;
  if (all.length) bds.append(t('Detrás:'));
  for (const d of all) {
    const lab = document.createElement('label'), box = document.createElement('input');
    Object.assign(box, { type: 'checkbox', checked: !l.hide.includes(d.name) });
    box.dataset.name = d.name;
    lab.append(box, ' ' + d.name);
    bds.append(lab);
  }
}

function musicSelect(sel, value) { // none, or a sound brought in as music
  sel.replaceChildren(new Option(t('(ninguna)'), ''));
  for (const s of app.project.sounds.filter(x => x.use === 'music')) sel.append(new Option(s.name, s.name));
  sel.value = value || '';
}

const same = (a, b) => a && b && a.type === b.type && a.name === b.name;

function pieceButton(pc, d, label) {
  const b = document.createElement('button');
  b.title = label;
  b.setAttribute('aria-label', label);
  if (d) b.append(thumbnail(d, 40));
  else b.textContent = '⌫';
  b.setAttribute('aria-pressed', String(same(pc, piece)));
  b.addEventListener('click', () => { // chosen: only the pressed states change, the focus stays on it
    piece = pc;
    for (const x of document.querySelectorAll('.pieces button')) x.setAttribute('aria-pressed', String(x === b));
  });
  return b;
}

// undo, redo: what a level's map and objects were
const snap = () => ({ sel, map: JSON.stringify(level().map), objects: JSON.stringify(level().objects) });
function remember() { undo.push(snap()); if (undo.length > 80) undo.shift(); redo.length = 0; }
function back(from, to) {
  const s = from.pop();
  if (!s) return;
  const was = sel;
  sel = s.sel;
  if (!level()) { sel = was; return; } // that level is gone
  to.push(snap());
  Object.assign(level(), { map: JSON.parse(s.map), objects: JSON.parse(s.objects) });
  app.changed();
  render();
}

function at(e) {
  const r = $('map').getBoundingClientRect();
  return { x: (e.clientX - r.left) / S, y: (e.clientY - r.top) / S };
}

function objectAt(x, y) {
  const list = level().objects;
  for (let i = list.length - 1; i >= 0; i--) {
    const o = list[i], d = byName(o.kind) || { w: 16, h: 16 };
    if (x >= o.x && y >= o.y && x < o.x + d.w && y < o.y + d.h) return i;
  }
  return -1;
}

function setTile(x, y, name) {
  const m = level().map, tx = Math.floor(x / T()), ty = Math.floor(y / T());
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

// a click (or Space) with the chosen piece: a tile painted, an object put (or taken back, clicked again on one of its
// kind); the eraser (or the right button, or Delete) takes away the object there, else the tile. p: from the pointer,
// or the keyboard's cursor
function act(e, first, p = at(e)) {
  const { x, y } = p, erase = e.buttons === 2 || !piece || piece.type === 'erase';
  const objects = level().objects, before = snap();
  if (!erase && piece.type === 'object') {
    if (!first) return;
    const hit = objectAt(x, y);
    if (hit >= 0 && objects[hit].kind === piece.name) objects.splice(hit, 1);
    else {
      const d = byName(piece.name);
      objects.push({ kind: piece.name, x: Math.max(0, Math.round((x - d.w / 2) / 4) * 4), y: Math.max(0, Math.round((y - d.h / 2) / 4) * 4) });
    }
  } else if (erase) {
    const hit = objectAt(x, y);
    if (hit >= 0 && first) objects.splice(hit, 1);
    else if (!setTile(x, y, null)) return;
  } else if (!setTile(x, y, piece.name)) return;
  if (first) { undo.push(before); if (undo.length > 80) undo.shift(); redo.length = 0; } // a stroke is one step
  app.changed();
  renderMap();
}

function mapKeys(e) { // arrows move the cursor a tile; Space or Enter puts the piece; Delete takes away
  const m = level().map, d = { ArrowLeft: [-1, 0], ArrowRight: [1, 0], ArrowUp: [0, -1], ArrowDown: [0, 1] }[e.key];
  const centre = () => ({ x: kb.x * T() + T() / 2, y: kb.y * T() + T() / 2 });
  if (d) kb = { x: Math.max(0, Math.min(m.w - 1, kb.x + d[0])), y: Math.max(0, Math.min(m.h - 1, kb.y + d[1])) };
  else if (e.key === ' ' || e.key === 'Enter') act({ buttons: 1 }, true, centre());
  else if (e.key === 'Delete' || e.key === 'Backspace') act({ buttons: 2 }, true, centre());
  else return;
  e.preventDefault();
  renderMap();
  const c = $('map'), box = c.parentElement; // the cursor stays in view
  const cx = kb.x * T() * S, cy = kb.y * T() * S;
  if (cx < box.scrollLeft || cx + T() * S > box.scrollLeft + box.clientWidth) box.scrollLeft = cx - box.clientWidth / 2;
  if (cy < box.scrollTop || cy + T() * S > box.scrollTop + box.clientHeight) box.scrollTop = cy - box.clientHeight / 2;
}

function resize(w, h) {
  const m = level().map, asked = [w, h];
  const [mw, mh] = MIN();
  w = Math.max(mw, Math.min(MAP_MAX, w | 0)), h = Math.max(mh, Math.min(MAP_MAX, h | 0));
  if (asked[0] !== w || asked[1] !== h)
    app.toast(t('Un mapa mide de {mw} × {mh} a {max} × {max} baldosas: queda en {w} × {h}.', { mw, mh, max: MAP_MAX, w, h }));
  remember();
  const cells = new Array(w * h).fill(0);
  for (let y = 0; y < Math.min(h, m.h); y++) for (let x = 0; x < Math.min(w, m.w); x++) cells[y * w + x] = m.cells[y * m.w + x];
  Object.assign(m, { w, h, cells });
  app.changed();
  render();
}

// ------------------------------------------------------------------ the cover

// the game's letters for the preview: the engine's own (Pixelify Sans), or fonts/<id>/font.woff2, loaded once
const faces = new Map();
function fontFamily(id) {
  if (!id || !FONTS[id]) return Promise.resolve('"Pixelify Sans"');
  if (!faces.has(id)) {
    const f = new FontFace('pinyol-' + id, `url(fonts/${id}/font.woff2)`);
    document.fonts.add(f);
    faces.set(id, f.load().then(() => `"pinyol-${id}"`, () => '"Pixelify Sans"'));
  }
  return faces.get(id);
}

function paintCover(g, family = '"Pixelify Sans"') { // as kit.lua draws it, at the screen's 480×320
  const p = app.project, c = p.cover, st = lookOf(p).style || { text: '#ffffff', outline: '#202020', accent: '#ffe070' };
  g.imageSmoothingEnabled = false;
  g.fillStyle = c.background;
  g.fillRect(0, 0, 480, 320);
  const d = byName(c.picture);
  if (d && d.use === 'backdrop') { // repeated, as behind a level
    g.save();
    g.scale(2, 2);
    g.fillStyle = g.createPattern(imageOf(d), 'repeat');
    g.fillRect(0, 0, 240, 160);
    g.restore();
  } else if (d && d.h <= 50) { // a character: between the title and the line under it (as kit.lua draws it)
    const k = Math.max(1, Math.min(6, Math.floor(100 / d.h), Math.floor(480 / d.w)));
    g.drawImage(imageOf(d), Math.floor((480 - d.w * k) / 2), 128 + Math.floor((100 - d.h * k) / 2), d.w * k, d.h * k);
  } else if (d) { // a picture: as big as fits, in whole steps
    const k = Math.max(1, Math.min(Math.floor(480 / d.w), Math.floor(320 / d.h)));
    g.drawImage(imageOf(d), Math.floor((480 - d.w * k) / 2), Math.floor((320 - d.h * k) / 2), d.w * k, d.h * k);
  }
  g.textAlign = 'center';
  g.lineJoin = 'round';
  const say = (text, y, size, colour) => {
    g.font = `700 ${size}px ${family}, monospace`;
    g.lineWidth = 5, g.strokeStyle = st.outline, g.fillStyle = colour;
    g.strokeText(text, 240, y);
    g.fillText(text, 240, y);
  };
  say(p.title, 118, 44, st.text);
  say(c.subtitle, 254, 17, st.accent);
}

// The cover as the console's menu shows a game: 240×160 RGB565, little endian (the game's cover.rgb565)
export async function coverBytes() {
  const family = await fontFamily(app.project.font);
  await document.fonts.load(`700 44px ${family}`); // not drawn in a fallback font when the tab was never opened
  const big = Object.assign(document.createElement('canvas'), { width: 480, height: 320 });
  paintCover(big.getContext('2d'), family);
  const small = Object.assign(document.createElement('canvas'), { width: 240, height: 160 }), g = small.getContext('2d');
  g.drawImage(big, 0, 0, 240, 160); // halved, smoothly: the title's letters stay readable
  const px = g.getImageData(0, 0, 240, 160).data, out = new Uint8Array(240 * 160 * 2);
  for (let i = 0, j = 0; i < px.length; i += 4, j += 2) {
    const v = (px[i] >> 3) << 11 | (px[i + 1] >> 2) << 5 | px[i + 2] >> 3;
    out[j] = v & 255, out[j + 1] = v >> 8;
  }
  return out;
}

function renderCover() {
  const p = app.project, c = p.cover, cv = $('cover-preview');
  paintCover(cv.getContext('2d'));
  fontFamily(p.font).then(family => { if (app.project === p) paintCover(cv.getContext('2d'), family); }); // once loaded
  $('game-font').value = p.font || '';
  $('game-lang').value = p.lang || 'es';
  cv.classList.toggle('off', !c.on);
  $('cover-on').checked = c.on;
  $('cover-subtitle').value = c.subtitle;
  $('cover-bg').value = c.background;
  $('ending').value = p.ending;
  $('game-tagline').value = p.tagline || ''; // (templates and projects from before have none)
  $('game-author').value = p.author || '';
  $('game-about').value = p.about || '';
  const pic = $('cover-picture');
  pic.replaceChildren(new Option(t('(ninguna)'), ''));
  for (const x of p.drawings) pic.append(new Option(x.name, x.name));
  pic.value = c.picture;
  musicSelect($('cover-music'), c.music);
}

// ------------------------------------------------------------------ the list of levels

function renderLevels() {
  const ul = $('levels'), p = app.project, focused = ul.contains(document.activeElement);
  ul.replaceChildren();
  const item = (i, text) => {
    const li = document.createElement('li'), b = document.createElement('button');
    b.className = 'item';
    b.append(Object.assign(document.createElement('span'), { className: 'name', textContent: text }));
    b.setAttribute('aria-current', String(i === sel));
    b.addEventListener('click', () => { sel = i; render(); });
    li.append(b);
    ul.append(li);
  };
  item(-1, p.cover.on ? '★ ' + t('Portada') : '☆ ' + t('Portada (no se muestra)'));
  p.levels.forEach((l, i) => item(i, `${i + 1}. ${l.name}`));
  $('level-add').disabled = p.levels.length >= LEVELS_MAX;
  if (focused) ul.querySelector('[aria-current="true"]')?.focus();
}

function render() {
  sel = Math.min(sel, app.project.levels.length - 1);
  images = new Map();
  renderLevels();
  const cover = sel < 0;
  $('level-work').hidden = cover;
  $('cover-work').hidden = !cover;
  $('map-palette').hidden = cover;
  if (cover) renderCover();
  else { renderPieces(); renderMap(); }
}

function addLevel() {
  const p = app.project, from = level() || p.levels[0];
  if (p.levels.length >= LEVELS_MAX) return;
  const n = p.levels.length + 1, l = newLevel(uniqueName('nivel' + n, new Set(p.levels.map(x => x.id))), t('Nivel {n}', { n }));
  const [mw, mh] = MIN(); // small tiles: a screen is more of them
  if (l.map.w < mw || l.map.h < mh) Object.assign(l.map, { w: mw, h: mh, cells: new Array(mw * mh).fill(0) });
  l.background = from.background, l.camera = from.camera, l.hide = from.hide.slice(), l.music = from.music;
  l.objects = from.objects.filter(o => isPlayer(o.kind)).map(o => ({ ...o })); // the player is there to start with
  p.levels.push(l);
  sel = p.levels.length - 1;
  app.changed();
  render();
}

function moveLevel(by) {
  const list = app.project.levels, to = sel + by;
  if (to < 0 || to >= list.length) return;
  [list[sel], list[to]] = [list[to], list[sel]];
  sel = to;
  app.changed();
  render();
}

export function initMap(ctx) {
  app = ctx;
  const c = $('map');
  c.addEventListener('pointerdown', e => {
    if (!e.isPrimary || c.classList.contains('pan')) return; // a second finger, or moving the map: no painting
    painting = true;
    c.setPointerCapture(e.pointerId);
    act(e, true);
  });
  c.addEventListener('pointermove', e => { if (painting && e.isPrimary && e.buttons) act(e, false); });
  c.addEventListener('keydown', mapKeys);
  c.addEventListener('focus', renderMap);
  c.addEventListener('blur', renderMap);
  $('map-undo').addEventListener('click', () => back(undo, redo));
  $('map-redo').addEventListener('click', () => back(redo, undo));
  addEventListener('keydown', e => {
    if ($('tab-map').hidden || !e.target.closest('#level-work') || e.target.matches('input, select') || !(e.ctrlKey || e.metaKey)) return;
    const k = e.key.toLowerCase();
    if (k === 'z' || k === 'y') { e.preventDefault(); if (k === 'y' || e.shiftKey) back(redo, undo); else back(undo, redo); }
  });
  $('map-pan').addEventListener('click', e => {
    const on = c.classList.toggle('pan');
    e.currentTarget.setAttribute('aria-pressed', String(on));
  });
  c.addEventListener('pointerup', () => { painting = false; });
  c.addEventListener('contextmenu', e => e.preventDefault());
  $('map-w').addEventListener('change', e => resize(Number(e.target.value), level().map.h));
  $('map-h').addEventListener('change', e => resize(level().map.w, Number(e.target.value)));
  $('map-bg').addEventListener('input', e => { level().background = e.target.value; app.changed(); renderMap(); });
  $('map-camera').addEventListener('change', e => { level().camera = e.target.value; app.changed(); renderMap(); });
  $('map-music').addEventListener('change', e => { level().music = e.target.value; app.changed(); });
  $('map-backdrops').addEventListener('change', e => {
    const l = level(), name = e.target.dataset.name;
    l.hide = e.target.checked ? l.hide.filter(n => n !== name) : [...l.hide, name];
    app.changed();
    renderMap();
  });
  $('level-add').addEventListener('click', addLevel);
  $('level-up').addEventListener('click', () => moveLevel(-1));
  $('level-down').addEventListener('click', () => moveLevel(1));
  $('level-del').addEventListener('click', () => {
    const p = app.project;
    if (p.levels.length < 2 || !confirm(t('¿Quitar «{name}» con todo lo que tiene?', { name: level().name }))) return;
    p.levels.splice(sel, 1);
    sel = Math.max(0, sel - 1);
    app.changed();
    render();
  });
  $('level-name').addEventListener('change', e => { level().name = e.target.value.trim().slice(0, 40) || level().id; app.changed(); renderLevels(); });
  const cover = (id, key, event = 'input', get = e => e.target.value) => $(id).addEventListener(event, e => {
    app.project.cover[key] = get(e);
    app.changed();
    render();
  });
  cover('cover-on', 'on', 'change', e => e.target.checked);
  cover('cover-subtitle', 'subtitle');
  cover('cover-bg', 'background');
  cover('cover-picture', 'picture', 'change');
  cover('cover-music', 'music', 'change');
  $('ending').addEventListener('input', e => { app.project.ending = e.target.value.slice(0, 60); app.changed(); });
  for (const [k, name] of Object.entries(FONTS)) $('game-font').append(new Option(name, k));
  $('game-font').addEventListener('change', e => { app.project.font = e.target.value; app.changed(); render(); });
  for (const [k, name] of Object.entries(LANGS)) $('game-lang').append(new Option(name, k));
  $('game-lang').addEventListener('change', e => { app.project.lang = e.target.value; app.changed(); }); // kit's sentences
  for (const [id, key, max] of [['game-tagline', 'tagline', 40], ['game-author', 'author', 40], ['game-about', 'about', 140]])
    $(id).addEventListener('input', e => { app.project[key] = e.target.value.slice(0, max); app.changed(); });
  return { render, reset: () => { sel = 0; piece = null; undo.length = redo.length = 0; render(); } };
}
