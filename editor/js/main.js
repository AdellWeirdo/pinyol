// The editor: the project kept in the browser as it changes, the tabs, and the game built from it for the player
// (Play) or the console's card (a .zip).
/* global Blockly */
import { check, pack, saveLocal, loadLocal } from './project.js';
import { TEMPLATES, templateEmpty } from './templates.js';
import { buildFiles } from './build.js';
import { zip } from './zip.js';
import { defineBlocks, setProject, workspaceLua, TOOLBOX, templateBlocks } from './blocks.js';
import { initDrawings } from './sprites.js';
import { initMap } from './map.js';
import { initSounds } from './sounds.js';

const $ = id => document.getElementById(id);
// what every game carries besides its own: the fonts, and kit with what it uses (a copy, so the game plays the same on a
// console with older firmware; tools/make_editor.py puts them in lib/)
const GAME_FILES = ['fonts/FONT_MAIN.fnt', 'fonts/FONT_BOLD.fnt', 'fonts/FONT_MAIN_L.fnt', 'fonts/FONT_BOLD_L.fnt',
  'lib/kit.lua', 'lib/juice.lua', 'lib/particles.lua'];
let project, ws, tabs = {}, saveTimer = 0, gameFiles = null;

function toast(text, ms = 2500) {
  const t = $('toast');
  t.textContent = text;
  t.hidden = false;
  clearTimeout(toast.timer);
  toast.timer = setTimeout(() => { t.hidden = true; }, ms);
}

// ------------------------------------------------------------------ the project as it changes

function changed() {
  clearTimeout(saveTimer);
  saveTimer = setTimeout(() => {
    project.blocks = ws ? Blockly.serialization.workspaces.save(ws) : project.blocks;
    if (!saveLocal(project)) toast('No se ha podido guardar en el navegador: guarda el proyecto en un archivo');
  }, 400);
}

function eachField(test, set) { // the blocks' fields that name a drawing or a sound
  if (!ws) return;
  for (const b of ws.getAllBlocks(false))
    for (const input of b.inputList)
      for (const f of input.fieldRow) if (f.name && test(f)) set(f);
}

const app = {
  get project() { return project; },
  changed,
  toast,
  rename(old, name) { // a drawing's new name, everywhere it is used: every level, the cover, the blocks
    const d = project.drawings.find(x => x.name === old);
    if (!d) return;
    d.name = name;
    for (const l of project.levels) {
      l.map.tiles = l.map.tiles.map(t => (t === old ? name : t));
      for (const o of l.objects) if (o.kind === old) o.kind = name;
      if (l.camera === old) l.camera = name;
      l.hide = l.hide.map(n => (n === old ? name : n));
    }
    if (project.cover.picture === old) project.cover.picture = name;
    eachField(f => ['KIND', 'A', 'B', 'TILE'].includes(f.name) && f.getValue() === old, f => f.setValue(name));
    tabs.map.render();
    changed();
  },
  remove(name) { // a drawing gone: from every level's map, objects and camera, and the cover
    project.drawings = project.drawings.filter(d => d.name !== name);
    for (const l of project.levels) {
      dropTile(l, name);
      l.objects = l.objects.filter(o => o.kind !== name);
      if (l.camera === name) l.camera = '';
      l.hide = l.hide.filter(n => n !== name);
    }
    if (project.cover.picture === name) project.cover.picture = '';
    tabs.map.render();
    changed();
  },
  uses() { // a drawing became a tile, an object or a backdrop: it leaves the other roles' places
    for (const d of project.drawings)
      for (const l of project.levels) {
        if (d.use !== 'tile') dropTile(l, d.name);
        if (d.use !== 'object') l.objects = l.objects.filter(o => o.kind !== d.name);
      }
    tabs.map.render();
  },
  renameSound(old, name) {
    const s = project.sounds.find(x => x.name === old);
    if (s) s.name = name;
    eachField(f => f.name === 'SOUND' && f.getValue() === old, f => f.setValue(name));
  },
};

function dropTile(level, name) {
  const m = level.map, i = m.tiles.indexOf(name);
  if (i < 0) return;
  m.tiles.splice(i, 1);
  m.cells = m.cells.map(c => (c === i + 1 ? 0 : c > i + 1 ? c - 1 : c));
}

function load(p, blocks) {
  project = p;
  setProject(project);
  $('title').value = project.title;
  if (ws) {
    ws.clear();
    try { if (blocks || project.blocks) Blockly.serialization.workspaces.load(blocks || project.blocks, ws); }
    catch (e) { toast('Los bloques no se han podido abrir: ' + e.message); }
    if (blocks) ws.cleanUp(); // a template's blocks: in a column, none on top of another
  }
  tabs.draw.reset();
  tabs.map.reset();
  tabs.sound.reset();
  changed();
}

// ------------------------------------------------------------------ the game

async function getGameFiles() { // -> [[path in the game, bytes]]
  if (gameFiles) return gameFiles;
  const out = [];
  for (const f of GAME_FILES) {
    const r = await fetch(f);
    if (!r.ok) throw new Error('falta ' + f + ' (¿se ha montado el editor con tools/make_editor.py?)');
    out.push([f.replace(/^lib\//, ''), new Uint8Array(await r.arrayBuffer())]);
  }
  return (gameFiles = out);
}

export function luaCode() { return ws ? workspaceLua(ws) : ''; }

async function buildZip(opts) { // opts.start: a level to play first, skipping the cover (to try it)
  project.blocks = Blockly.serialization.workspaces.save(ws);
  return zip(buildFiles(project, luaCode(), await getGameFiles(), opts), project.id);
}

function renderStart() { // Play from the cover or any level
  const sel = $('play-start'), was = sel.value;
  sel.replaceChildren(new Option(project.cover.on ? 'la portada' : 'el primer nivel', ''));
  project.levels.forEach((l, i) => sel.append(new Option(`${i + 1}. ${l.name}`, l.id)));
  sel.value = [...sel.options].some(o => o.value === was) ? was : '';
}

let playerReady = null;
async function play() {
  showTab('game');
  $('game-status').textContent = 'Preparando el juego…';
  $('game-status').classList.remove('error');
  try {
    const bytes = await buildZip({ start: $('play-start').value || null });
    const frame = $('player');
    playerReady = new Promise(resolve => { frame.onload = resolve; });
    frame.src = 'player/player.html?embed=1&t=' + Date.now(); /* a fresh engine: it starts once per page */
    await playerReady;
    frame.contentWindow.postMessage({ np2d: 'play', zip: bytes.buffer }, location.origin, [bytes.buffer]);
    $('game-status').textContent = 'Flechas o WASD, Z = A, X = B. Haz clic en el juego para jugar.';
    frame.focus();
  } catch (e) {
    $('game-status').textContent = 'No se ha podido construir el juego: ' + e.message;
    $('game-status').classList.add('error');
  }
}

function download(bytes, name, type) {
  const a = document.createElement('a');
  a.href = URL.createObjectURL(new Blob([bytes], { type }));
  a.download = name;
  a.click();
  setTimeout(() => URL.revokeObjectURL(a.href), 5000);
}

// ------------------------------------------------------------------ tabs and buttons

function showTab(name) {
  for (const b of document.querySelectorAll('[role=tab]')) b.setAttribute('aria-selected', String(b.dataset.tab === name));
  for (const s of document.querySelectorAll('.tab')) s.hidden = s.id !== 'tab-' + name;
  if (name === 'logic' && ws) Blockly.svgResize(ws);
  if (name === 'map') tabs.map.render();
  if (name === 'draw') tabs.draw.render();
  if (name === 'game') renderStart();
}

function initBlockly() {
  defineBlocks();
  const theme = Blockly.Theme.defineTheme('np2d', {
    base: Blockly.Themes.Classic,
    componentStyles: { workspaceBackgroundColour: '#1b1724', toolboxBackgroundColour: '#221d2e',
                       toolboxForegroundColour: '#f1e9da', flyoutBackgroundColour: '#2b2539',
                       flyoutForegroundColour: '#f1e9da', flyoutOpacity: 0.96, scrollbarColour: '#3a3150',
                       insertionMarkerColour: '#ffffff', insertionMarkerOpacity: 0.3, cursorColour: '#d0d0d0' },
    fontStyle: { family: 'system-ui, sans-serif', size: 12 },
  });
  ws = Blockly.inject('blockly', { toolbox: TOOLBOX, theme, trashcan: true, renderer: 'zelos',
                                   zoom: { controls: true, wheel: true, startScale: 0.8 }, grid: { spacing: 24, length: 2, colour: '#2b2539' } });
  let codeTimer = 0;
  ws.addChangeListener(e => {
    if (e.isUiEvent) return;
    changed();
    clearTimeout(codeTimer);
    codeTimer = setTimeout(() => { $('lua-code').textContent = luaCode(); }, 300);
  });
}

function init() {
  const ctx = app;
  tabs.draw = initDrawings(ctx);
  tabs.map = initMap(ctx);
  tabs.sound = initSounds(ctx);
  initBlockly();
  const saved = loadLocal();
  if (saved) load(saved);
  else load(TEMPLATES[0].make(), templateBlocks(TEMPLATES[0].key));

  for (const b of document.querySelectorAll('[role=tab]')) b.addEventListener('click', () => showTab(b.dataset.tab));
  $('title').addEventListener('change', e => { project.title = e.target.value.trim().slice(0, 40) || 'Juego'; changed(); tabs.map.render(); });
  $('new').addEventListener('click', () => {
    const list = $('new-list');
    list.hidden = !list.hidden;
    $('new').setAttribute('aria-expanded', String(!list.hidden));
  });
  const fresh = (label, start) => { // a game to start from, in the Nuevo menu
    const b = Object.assign(document.createElement('button'), { textContent: label });
    b.addEventListener('click', () => {
      $('new-list').hidden = true;
      if (!confirm('¿Empezar un juego nuevo? Guarda antes el actual si lo quieres conservar.')) return;
      start();
      showTab('draw');
    });
    $('new-list').append(b);
  };
  for (const t of TEMPLATES) fresh(t.label, () => load(t.make(), templateBlocks(t.key)));
  fresh('Vacío', () => load(templateEmpty(), { blocks: { languageVersion: 0, blocks: [] } }));
  $('open').addEventListener('change', async e => {
    const f = e.target.files[0];
    e.target.value = '';
    if (!f) return;
    try { load(check(JSON.parse(await f.text()))); toast('Proyecto abierto'); }
    catch (err) { toast('No se ha podido abrir: ' + err.message); }
  });
  $('save').addEventListener('click', () => {
    project.blocks = Blockly.serialization.workspaces.save(ws);
    download(new TextEncoder().encode(JSON.stringify(pack(project))), project.id + '.np2d.json', 'application/json');
  });
  $('export').addEventListener('click', async () => {
    try {
      download(await buildZip(), project.id + '.zip', 'application/zip');
      toast('Descomprime el .zip en la carpeta games/ de la tarjeta de la consola');
    } catch (e) { toast('No se ha podido construir: ' + e.message); }
  });
  $('play').addEventListener('click', play);
  $('restart').addEventListener('click', play);
  addEventListener('message', e => { /* the player tells what went wrong */
    if (e.origin === location.origin && e.data && e.data.np2d === 'error') {
      $('game-status').textContent = e.data.message;
      $('game-status').classList.add('error');
    }
  });
  renderStart();
  window.np2dEditor = { get project() { return project; }, buildZip, luaCode, load: p => load(check(p)) }; // for tests
}

init();
