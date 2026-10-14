// The Drawings tab: pixel by pixel in the console's colours (a palette at hand, or any other), with frames for
// animation; pictures brought in from files; and what each drawing is for (a tile of the map, solid or not, an
// object that moves in some way, or a picture behind the map).
import { PALETTE, COLOUR_NAMES, BEHAVIOURS, SHOT_DIRS, DRIFTS, DRAWING, SIZES, MAX_SIDE, MAX_BYTES, blankFrame, safeName, uniqueName, rgb565, hex565, rgbOf, hexOf, } from './project.js';
import { sizeOf, bytesOf } from './build.js';

const $ = id => document.getElementById(id);
let app, cur = 0, frame = 0, tool = 'pen', colour = hex565(PALETTE[19]);
const undo = new Map(), redo = new Map(); // drawing name -> stacks of frames

function imageData(d, f) { // a frame as the screen shows it
  const px = d.frames[f] || d.frames[0], img = new ImageData(d.w, d.h), b = img.data;
  for (let i = 0; i < px.length; i++) {
    if (px[i] < 0) continue;
    const [r, g, bl] = rgbOf(px[i]);
    b[4 * i] = r, b[4 * i + 1] = g, b[4 * i + 2] = bl, b[4 * i + 3] = 255;
  }
  return img;
}

export function drawPixels(canvas, d, f, scale = 1) { // a frame onto a canvas (cleared), each pixel scale x scale
  const g = canvas.getContext('2d');
  g.clearRect(0, 0, canvas.width, canvas.height);
  if (scale === 1) { g.putImageData(imageData(d, f), 0, 0); return; }
  const t = document.createElement('canvas');
  t.width = d.w, t.height = d.h;
  t.getContext('2d').putImageData(imageData(d, f), 0, 0);
  g.imageSmoothingEnabled = false;
  g.drawImage(t, 0, 0, d.w * scale, d.h * scale);
}

export function thumbnail(d, size = 32) {
  const c = document.createElement('canvas');
  c.width = d.w, c.height = d.h;
  drawPixels(c, d, 0);
  c.style.width = c.style.height = size + 'px';
  c.style.objectFit = 'contain';
  return c;
}

const drawing = () => app.project && app.project.drawings[cur]; // (the preview's animation starts before a project)
const fits = (next, prev) => bytesOf(app.project.drawings) - (prev ? sizeOf(prev) : 0) + sizeOf(next) <= MAX_BYTES; // with next in prev's place
const TOO_BIG = 'No cabe: la memoria de la consola está casi llena. Quita fotogramas o dibujos que no uses, o hazlos más pequeños.';
let kb = { x: 0, y: 0 }; // the keyboard's cursor on the canvas

function snapshot() { // before a change: for undo
  const d = drawing();
  if (!d) return;
  if (!undo.has(d.name)) undo.set(d.name, []);
  const u = undo.get(d.name);
  u.push(JSON.stringify({ w: d.w, h: d.h, frames: d.frames }));
  if (u.length > (d.w * d.h > 4096 ? 12 : 60)) u.shift(); // a big picture keeps fewer steps
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

// at: the cell (from the pointer, or the keyboard's cursor); every frame at once when "Pintar en todos" is on
function paint(e, first, at = cellAt(e)) {
  const d = drawing();
  if (!d || !at) return;
  const i = at.y * d.w + at.x, all = $('all-frames').checked && d.frames.length > 1;
  if (tool === 'pick') { if (d.frames[frame][i] >= 0) setColour(d.frames[frame][i]); setTool('pen'); return; }
  if (first) snapshot();
  for (const f of all ? d.frames.keys() : [frame]) {
    if (tool === 'fill') { if (first) fill(d, f, at.x, at.y, colour); }
    else d.frames[f][i] = tool === 'erase' || e.buttons === 2 ? -1 : colour;
  }
  app.changed();
  renderCanvas();
}

function canvasKeys(e) { // arrows move the cursor; Space or Enter paints with the tool; Delete erases
  const d = drawing(), m = { ArrowLeft: [-1, 0], ArrowRight: [1, 0], ArrowUp: [0, -1], ArrowDown: [0, 1] }[e.key];
  if (!d) return;
  if (m) kb = { x: Math.max(0, Math.min(d.w - 1, kb.x + m[0])), y: Math.max(0, Math.min(d.h - 1, kb.y + m[1])) };
  else if (e.key === ' ' || e.key === 'Enter') paint({ buttons: 1 }, true, { ...kb });
  else if (e.key === 'Delete' || e.key === 'Backspace') paint({ buttons: 2 }, true, { ...kb });
  else return;
  e.preventDefault();
  renderCanvas();
}

function renderCanvas() {
  const d = drawing(), c = $('pixels');
  if (!d) return;
  const s = Math.max(1, Math.floor(384 / Math.max(d.w, d.h)));
  c.width = d.w * s, c.height = d.h * s;
  c.style.width = Math.round(d.w * 384 / Math.max(d.w, d.h)) + 'px'; // the longer side 384 px on screen, whatever the size
  drawPixels(c, d, frame, s);
  if (s >= 6) { // the grid, where pixels are big enough to see it
    const g = c.getContext('2d');
    g.strokeStyle = 'rgba(255,255,255,0.08)';
    for (let i = 1; i < d.w; i++) { g.beginPath(); g.moveTo(i * s + 0.5, 0); g.lineTo(i * s + 0.5, c.height); g.stroke(); }
    for (let i = 1; i < d.h; i++) { g.beginPath(); g.moveTo(0, i * s + 0.5); g.lineTo(c.width, i * s + 0.5); g.stroke(); }
  }
  if (document.activeElement === c) { // the keyboard's cursor
    const g = c.getContext('2d');
    kb = { x: Math.min(kb.x, d.w - 1), y: Math.min(kb.y, d.h - 1) };
    g.lineWidth = Math.max(1, s / 8);
    g.strokeStyle = '#6cb4e0';
    g.strokeRect(kb.x * s + g.lineWidth / 2, kb.y * s + g.lineWidth / 2, s - g.lineWidth, s - g.lineWidth);
  }
  $('all-frames-row').hidden = d.frames.length < 2;
  renderFrames();
  drawPreview();
  const li = $('drawings').children[cur];
  if (li) { const t = li.querySelector('canvas'); if (t) drawPixels(t, d, 0); }
}

// ------------------------------------------------------------------ the rest of the tab

const USES = { tile: 'baldosa', object: 'objeto', backdrop: 'fondo' };

function renderList() {
  const ul = $('drawings'), focused = ul.contains(document.activeElement);
  ul.replaceChildren();
  app.project.drawings.forEach((d, i) => {
    const li = document.createElement('li'), b = document.createElement('button');
    b.className = 'item';
    b.append(thumbnail(d), Object.assign(document.createElement('span'), { className: 'name', textContent: d.name }),
      Object.assign(document.createElement('span'), { className: 'kind', textContent: d.use === 'tile' && d.solid ? 'sólida' : USES[d.use] }));
    b.setAttribute('aria-current', String(i === cur));
    b.addEventListener('click', () => select(i));
    li.append(b);
    ul.append(li);
  });
  if (focused) ul.querySelector('[aria-current="true"]')?.focus(); // still where it was
  const used = bytesOf(app.project.drawings), m = $('d-memory');
  m.textContent = `Memoria de la consola: ${used >> 10} de ${MAX_BYTES >> 10} KB`;
  m.classList.toggle('warn', used > MAX_BYTES * 0.9);
}

function renderFrames() {
  const d = drawing(), box = $('frames'), focused = box.contains(document.activeElement);
  box.replaceChildren();
  d.frames.forEach((_, f) => {
    const b = document.createElement('button'), c = document.createElement('canvas');
    c.width = d.w, c.height = d.h;
    drawPixels(c, d, f);
    b.append(c);
    b.setAttribute('aria-pressed', String(f === frame));
    b.setAttribute('aria-label', 'Fotograma ' + (f + 1));
    b.title = 'Fotograma ' + (f + 1);
    b.addEventListener('click', () => { frame = f; renderCanvas(); });
    box.append(b);
  });
  if (focused) box.querySelector('[aria-pressed="true"]')?.focus();
  $('frame-del').disabled = d.frames.length < 2;
  $('frame-add').disabled = d.frames.length >= 8;
}

function renderProps() {
  const d = drawing(), size = $('d-size'), square = d.w === d.h && SIZES.includes(d.w);
  $('d-name').value = d.name;
  size.replaceChildren(...SIZES.map(n => new Option(`${n} × ${n}`, n)));
  if (!square) size.append(new Option(`${d.w} × ${d.h}`, 'own'));
  size.value = square ? String(d.w) : 'own';
  for (const r of document.querySelectorAll('input[name=use]')) r.checked = r.value === d.use;
  $('d-solid').checked = d.solid;
  $('d-solid').disabled = d.use !== 'tile';
  $('object-props').hidden = d.use !== 'object';
  $('backdrop-props').hidden = d.use !== 'backdrop';
  $('d-behaviour').value = d.behaviour;
  $('d-dir').value = d.dir;
  $('dir-row').hidden = d.behaviour !== 'shot';
  $('jump-row').hidden = d.behaviour !== 'platformer';
  $('d-gravity').checked = d.gravity ?? (d.behaviour === 'platformer' || d.behaviour === 'patrol');
  $('d-drift').value = d.drift;
  $('drift-row').hidden = !d.drift;
  for (const k of ['speed', 'jump', 'animate', 'parallax', 'drift_speed']) { $('d-' + k).value = d[k]; $('o-' + k).textContent = d[k]; }
  $('drawing-del').disabled = app.project.drawings.length < 2;
}

function render() {
  if (!app.project.drawings.length) return;
  cur = Math.min(cur, app.project.drawings.length - 1);
  renderList();
  renderCanvas();
  renderProps();
}

function select(i) { cur = i; frame = 0; anim = 0; render(); }

function setTool(t) {
  tool = t;
  for (const b of document.querySelectorAll('[data-tool]')) b.setAttribute('aria-pressed', String(b.dataset.tool === t));
}

function setColour(v) {
  colour = v;
  for (const b of $('palette').children) b.setAttribute('aria-pressed', String(Number(b.dataset.c) === v));
  $('colour-any').value = hexOf(v);
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
function drawPreview() {
  const d = drawing();
  if (d) drawPixels($('preview'), d, anim % d.frames.length, 64 / Math.max(d.w, d.h));
}
function animate(t) { // the preview, at the drawing's animation speed
  const d = drawing();
  if (d && d.frames.length > 1 && !$('tab-draw').hidden && t - last > Math.max(1, d.animate || 8) * 1000 / 60) {
    last = t;
    anim = (anim + 1) % d.frames.length;
    drawPreview();
  }
  requestAnimationFrame(animate);
}

// ------------------------------------------------------------------ pictures from files

let incoming = null; // {bmp, name}: the picture being brought in

function importSize() { // what the picture becomes, as the dialog says: frames in a row, each fw wide in the game
  const { width: w, height: h } = incoming.bmp;
  const n = Math.max(1, Math.min(8, Math.round(Number($('import-frames').value)) || 1));
  const fw = Math.max(1, Math.min(MAX_SIDE, Math.round(Number($('import-w').value)) || 16));
  return { n, tw: fw * n, fw, th: Math.max(1, Math.min(MAX_SIDE, Math.round(h * fw * n / w))) };
}

function importPixels() {
  const { n, tw, fw, th } = importSize(), c = document.createElement('canvas');
  c.width = tw, c.height = th;
  const g = c.getContext('2d', { willReadFrequently: true });
  g.imageSmoothingEnabled = $('import-smooth').checked;
  g.imageSmoothingQuality = 'high';
  g.drawImage(incoming.bmp, 0, 0, tw, th);
  const data = g.getImageData(0, 0, tw, th).data, frames = [];
  for (let k = 0; k < n; k++) {
    const f = blankFrame(fw, th);
    for (let y = 0; y < th; y++)
      for (let x = 0; x < fw; x++) {
        const i = (y * tw + k * fw + x) * 4;
        if (data[i + 3] >= 128) f[y * fw + x] = rgb565(data[i], data[i + 1], data[i + 2]); // half see-through: gone
      }
    frames.push(f);
  }
  return { w: fw, h: th, frames };
}

function importPreview() {
  const pic = importPixels(), c = $('import-preview'), ok = fits({ ...pic, use: useOf(pic) });
  const s = Math.min(240 / pic.w, 160 / pic.h, 8);
  c.width = Math.max(1, Math.round(pic.w * s)), c.height = Math.max(1, Math.round(pic.h * s));
  drawPixels(c, pic, 0, s);
  incoming.total = pic.w * pic.frames.length; // the row's width: kept when the number of frames changes
  $('import-size').textContent = `${pic.w} × ${pic.h} px` + (pic.frames.length > 1 ? ` cada uno, ${pic.frames.length} fotogramas` : '') +
    (ok ? '' : ' · no cabe en la memoria de la consola: hazla más pequeña');
  $('import-size').classList.toggle('warn', !ok);
  $('import-ok').disabled = !ok;
}

function fewColours(bmp) { // pixel art (a few colours) stays sharp when made smaller; a photo is smoothed
  const c = document.createElement('canvas'), n = 128;
  c.width = c.height = n;
  const g = c.getContext('2d', { willReadFrequently: true });
  g.imageSmoothingEnabled = false; // nearest: samples the picture's own colours
  g.drawImage(bmp, 0, 0, n, n);
  const d = g.getImageData(0, 0, n, n).data, seen = new Set();
  for (let i = 0; i < d.length && seen.size <= 256; i += 4) if (d[i + 3] >= 128) seen.add((d[i] << 16) | (d[i + 1] << 8) | d[i + 2]);
  return seen.size <= 256;
}

async function openImport(file) {
  if (!file) return;
  if (!/^image\//.test(file.type)) return app.oops(`«${file.name}» no es una imagen. Usa un archivo PNG, JPG, GIF o WebP.`);
  try { incoming = { bmp: await createImageBitmap(file), name: (file.name || 'imagen').replace(/\.[^.]*$/, '') }; }
  catch { return app.oops('No se ha podido leer esa imagen. Prueba a guardarla como PNG.'); }
  const { width: w, height: h } = incoming.bmp;
  const strip = w > h && w % h === 0 && w / h <= 8 ? w / h : 1; // a row of square frames
  const tw = Math.min(w, strip > 1 ? MAX_SIDE : 240); // the screen is 240 wide
  $('import-frames').value = strip;
  $('import-w').value = Math.round(tw / strip);
  $('import-smooth').checked = w > tw && !fewColours(incoming.bmp);
  importPreview();
  $('import').showModal();
}

const useOf = pic => pic.w === 16 && pic.h === 16 ? 'tile' : pic.w >= 120 || pic.h >= 120 ? 'backdrop' : 'object';

function finishImport() {
  if ($('import').returnValue !== 'ok' || !incoming) { incoming = null; return; }
  const pic = importPixels(), names = new Set(app.project.drawings.map(d => d.name));
  const use = useOf(pic);
  if (!fits({ ...pic, use })) { incoming = null; app.toast(TOO_BIG); return; }
  app.project.drawings.push({ ...DRAWING, name: uniqueName(safeName(incoming.name, 'imagen'), names), ...pic, use,
                              parallax: 0 }); // a picture is rarely made to repeat: still, until asked to move
  incoming.bmp.close();
  incoming = null;
  select(app.project.drawings.length - 1);
  app.uses();
  app.changed();
  app.toast(use === 'backdrop' ? 'Imagen añadida como fondo: se ve detrás del mapa.' : 'Imagen añadida.');
}

function initImport() {
  $('import-file').addEventListener('change', e => { const f = e.target.files[0]; e.target.value = ''; openImport(f); });
  for (const id of ['import-w', 'import-smooth']) $(id).addEventListener('input', importPreview);
  $('import-frames').addEventListener('input', e => {
    const n = Math.max(1, Math.min(8, Math.round(Number(e.target.value)) || 1));
    $('import-w').value = Math.max(1, Math.round(incoming.total / n));
    importPreview();
  });
  $('import').addEventListener('close', finishImport);
  const tab = $('tab-draw');
  tab.addEventListener('dragover', e => { e.preventDefault(); tab.classList.add('dropping'); });
  tab.addEventListener('dragleave', e => { if (e.target === tab) tab.classList.remove('dropping'); });
  tab.addEventListener('drop', e => { e.preventDefault(); tab.classList.remove('dropping'); openImport(e.dataTransfer.files[0]); });
  addEventListener('paste', e => { // an image copied anywhere, pasted here
    if (tab.hidden || e.target.matches('input, textarea')) return;
    const f = [...e.clipboardData.files].find(x => /^image\//.test(x.type));
    if (f) { e.preventDefault(); openImport(f); }
  });
}

// ------------------------------------------------------------------ the tab's controls

export function initDrawings(ctx) {
  app = ctx;
  const pal = $('palette');
  PALETTE.forEach((hex, i) => {
    const b = document.createElement('button'), v = hex565(hex);
    b.style.background = hexOf(v), b.dataset.c = v, b.title = COLOUR_NAMES[i];
    b.setAttribute('aria-label', COLOUR_NAMES[i]);
    b.addEventListener('click', () => setColour(v));
    pal.append(b);
  });
  $('colour-any').addEventListener('input', e => setColour(hex565(e.target.value)));
  setColour(colour);
  for (const [k, label] of Object.entries(BEHAVIOURS)) $('d-behaviour').append(new Option(label, k));
  for (const [k, label] of Object.entries(SHOT_DIRS)) $('d-dir').append(new Option(label, k));
  for (const [k, label] of Object.entries(DRIFTS)) $('d-drift').append(new Option(label, k));
  for (const b of document.querySelectorAll('[data-tool]')) b.addEventListener('click', () => setTool(b.dataset.tool));
  const c = $('pixels');
  c.addEventListener('pointerdown', e => { if (!e.isPrimary) return; c.setPointerCapture(e.pointerId); paint(e, true); });
  c.addEventListener('pointermove', e => { if (e.isPrimary && e.buttons && tool !== 'fill' && tool !== 'pick') paint(e, false); });
  c.addEventListener('keydown', canvasKeys);
  c.addEventListener('focus', renderCanvas);
  c.addEventListener('blur', renderCanvas);
  c.addEventListener('contextmenu', e => e.preventDefault());
  $('undo').addEventListener('click', () => restore(undo, redo));
  $('redo').addEventListener('click', () => restore(redo, undo));
  addEventListener('keydown', e => { // the tab's shortcuts, only over its drawing area (single letters type elsewhere)
    if ($('tab-draw').hidden || $('import').open || !e.target.closest('#tab-draw .work') || e.target.matches('input, select, textarea')) return;
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
    if (!fits({ ...d, frames: [...d.frames, d.frames[frame]] }, d)) { app.toast(TOO_BIG); return; }
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
    if (!fits({ ...DRAWING, w: 16, h: 16, frames: [blankFrame(16, 16)] })) { app.toast(TOO_BIG); return; }
    app.project.drawings.push({ ...DRAWING, name: uniqueName('dibujo', names), w: 16, h: 16, frames: [blankFrame(16, 16)] });
    select(app.project.drawings.length - 1);
    app.changed();
  });
  $('drawing-del').addEventListener('click', () => {
    const d = drawing();
    if (app.project.drawings.length < 2 ||
        !confirm(`¿Quitar «${d.name}»? Sale también de todos los niveles y de la portada, y los bloques que lo usan dejarán de funcionar.`)) return;
    app.remove(d.name);
    cur = Math.max(0, cur - 1);
    changed();
  });
  $('d-name').addEventListener('change', e => {
    const d = drawing(), names = new Set(app.project.drawings.filter(x => x !== d).map(x => x.name));
    const name = uniqueName(safeName(e.target.value, d.name), names);
    if (name !== d.name) { undo.delete(d.name); app.rename(d.name, name); }
    if (name !== e.target.value) app.toast(`Se llama «${name}»: sin acentos ni espacios, así sale en los bloques.`);
    changed();
  });
  $('d-size').addEventListener('change', e => {
    const size = Number(e.target.value), d = drawing();
    if (!SIZES.includes(size)) return;
    const next = { ...d };
    resize(next, size); // (on a copy: d changes after the snapshot)
    if (!fits(next, d)) { app.toast(TOO_BIG); renderProps(); return; }
    snapshot();
    resize(d, size);
    changed();
  });
  for (const r of document.querySelectorAll('input[name=use]'))
    r.addEventListener('change', () => { // what it is placed as goes away from the maps: said first
      const d = drawing(), n = app.placed(d.name);
      if (n && !confirm(`«${d.name}» está puesto ${n} ${n === 1 ? 'vez' : 'veces'} en el mapa. Si cambia, se quita de los niveles. ¿Seguir?`)) {
        renderProps();
        return;
      }
      d.use = r.value;
      if (r.value !== 'tile') d.solid = false;
      app.uses();
      changed();
    });
  $('d-solid').addEventListener('change', e => { drawing().solid = e.target.checked; changed(); });
  $('d-behaviour').addEventListener('change', e => { drawing().behaviour = e.target.value; changed(); });
  $('d-dir').addEventListener('change', e => { drawing().dir = e.target.value; changed(); });
  $('d-gravity').addEventListener('change', e => { drawing().gravity = e.target.checked; changed(); });
  $('d-drift').addEventListener('change', e => { drawing().drift = e.target.value; changed(); });
  for (const k of ['speed', 'jump', 'animate', 'parallax', 'drift_speed'])
    $('d-' + k).addEventListener('input', e => { drawing()[k] = Number(e.target.value); $('o-' + k).textContent = e.target.value; app.changed(); });
  initImport();
  requestAnimationFrame(animate);
  return { render, reset: () => { cur = 0; frame = 0; undo.clear(); redo.clear(); render(); } };
}
