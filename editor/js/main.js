// The editor: the project kept in the browser as it changes, the tabs, and the game built from it for the player
// (Jugar), the console's card (a .zip) or the console itself over its cable.
/* global Blockly */
import { check, pack, safeName, saveLocal, loadLocal, LOOKS, LANGS, MAP_MAX, lookColour, hex565, hexOf } from './project.js';
import { TEMPLATES, templateEmpty } from './templates.js';
import { buildFiles } from './build.js';
import { audioFiles } from './audio.js';
import { zip } from './zip.js';
import { cableWorks, send } from './cable.js';
import { defineBlocks, setProject, workspaceLua, TOOLBOX, templateBlocks } from './blocks.js';
import { initDrawings, renderPalette } from './sprites.js';
import { initMap, coverBytes } from './map.js';
import { initSounds } from './sounds.js';
import { initVideos } from './videos.js';
import { initGuide } from './guide.js';
import { LANG, t, translatePage, chooseLang } from './i18n.js';

const $ = id => document.getElementById(id);
// what every game carries besides its own: the fonts, and kit with what it uses (a copy, so the game plays the same on a
// console with older firmware; tools/make_editor.py puts them in lib/)
const GAME_FILES = ['fonts/FONT_MAIN.fnt', 'fonts/FONT_BOLD.fnt', 'fonts/FONT_MAIN_L.fnt', 'fonts/FONT_BOLD_L.fnt',
  'lib/kit.lua', 'lib/juice.lua', 'lib/particles.lua'];
const TOUCH = matchMedia('(pointer: coarse)').matches;
let project, ws, tabs = {}, saveTimer = 0, loading = false, blocksBroken = false;

// A message at the bottom: read aloud, long enough to read; an error stays until closed; an action can undo something.
function toast(text, { error = false, action = null } = {}) {
  const box = $('toast'), act = $('toast-action');
  clearTimeout(toast.timer);
  $('toast-text').textContent = ''; // emptied first: a screen reader announces the change
  requestAnimationFrame(() => { $('toast-text').textContent = text; });
  box.classList.add('shown');
  box.classList.toggle('error', error);
  act.hidden = !action;
  if (action) act.textContent = action.label, act.onclick = () => { hide(); action.run(); };
  $('toast-close').hidden = !error && !action;
  const hide = () => box.classList.remove('shown');
  if (!error) toast.timer = setTimeout(hide, Math.max(action ? 9000 : 4000, text.length * 70));
}
const oops = text => toast(text, { error: true });

// ------------------------------------------------------------------ the project as it changes

function changed() {
  clearTimeout(saveTimer);
  $('saved').textContent = t('Guardando…');
  saveTimer = setTimeout(save, 400);
}
async function save() { // -> kept; now: also before the page goes (another language)
  clearTimeout(saveTimer);
  if (ws && !blocksBroken) project.blocks = Blockly.serialization.workspaces.save(ws); // broken: the stored ones stay
  if (await saveLocal(project)) { $('saved').textContent = t('Guardado en este navegador'); return true; }
  $('saved').textContent = '';
  oops(t('No se ha podido guardar en este navegador. Pulsa «Guardar archivo» para no perder el juego.'));
  return false;
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
  oops,
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
  placed(name) { // how many times a drawing is on the levels' maps, as a tile or an object
    let n = 0;
    for (const l of project.levels) {
      const t = l.map.tiles.indexOf(name) + 1;
      if (t) n += l.map.cells.filter(c => c === t).length;
      n += l.objects.filter(o => o.kind === name).length;
    }
    return n;
  },
  uses() { // a drawing became a tile, an object or a backdrop: it leaves the other roles' places
    for (const d of project.drawings)
      for (const l of project.levels) {
        if (d.use !== 'tile') dropTile(l, d.name);
        if (d.use !== 'object') l.objects = l.objects.filter(o => o.kind !== d.name);
      }
    tabs.map.render();
  },
  renameVideo(old, name) { // in the blocks that play it
    eachField(f => f.name === 'VIDEO' && f.getValue() === old, f => f.setValue(name));
  },
  renameSound(old, name) { // in the blocks, and as a level's or the cover's music
    const s = project.sounds.find(x => x.name === old);
    if (s) s.name = name;
    for (const x of [...project.levels, project.cover]) if (x.music === old) x.music = name;
    eachField(f => (f.name === 'SOUND' || f.name === 'MUSIC') && f.getValue() === old, f => f.setValue(name));
    tabs.map.render();
  },
  forgetMusic() { // music that is gone, or became an effect, plays nowhere
    const tunes = new Set(project.sounds.filter(s => s.use === 'music').map(s => s.name));
    for (const x of [...project.levels, project.cover]) if (x.music && !tunes.has(x.music)) x.music = '';
    tabs.map.render();
  },
};

function dropTile(level, name) {
  const m = level.map, i = m.tiles.indexOf(name);
  if (i < 0) return;
  m.tiles.splice(i, 1);
  m.cells = m.cells.map(c => (c === i + 1 ? 0 : c > i + 1 ? c - 1 : c));
}

// A look chosen: every drawing and background in its colours, its letters, and its tiles while the maps are empty
function applyLook(key) {
  const look = LOOKS[key] || LOOKS[''], p = project, was = p.look || '';
  if (key === was) return;
  const painted = p.drawings.some(d => d.frames.some(f => f.some(v => v >= 0)));
  if (look.palette && painted &&
      !confirm(t('Aspecto {name}: los dibujos y los colores de fondo pasan a sus colores (al más parecido). ¿Seguir?', { name: look.name }))) {
    $('look').value = was;
    return;
  }
  const colour = hex => hexOf(lookColour(look, hex565(hex)));
  p.look = key || '';
  p.font = look.font;
  for (const d of p.drawings) d.frames = d.frames.map(f => f.map(v => lookColour(look, v)));
  for (const x of [...p.levels, p.cover]) x.background = look.background && !painted ? look.background : colour(x.background);
  const old = p.tile || 16, tiles = p.drawings.some(d => d.use === 'tile' && d.w !== look.tile);
  let said = t('Aspecto {name}.', { name: look.name });
  if (look.tile !== old) {
    if (tiles || p.levels.some(l => l.map.cells.some(Boolean))) {
      said += ' ' + t('Las baldosas siguen de {old} × {old}: ya hay mapas o baldosas de ese tamaño ({name} las usaba de {tile}).',
                      { old, name: look.name, tile: look.tile });
    } else { // empty maps: the same world, in tiles of the new size
      p.tile = look.tile;
      for (const l of p.levels) {
        const w = Math.max(240 / p.tile, Math.min(MAP_MAX, Math.round(l.map.w * old / p.tile)));
        const h = Math.max(160 / p.tile, Math.min(MAP_MAX, Math.round(l.map.h * old / p.tile)));
        Object.assign(l.map, { w, h, cells: new Array(w * h).fill(0) });
      }
      said += ' ' + t('Baldosas de {n} × {n}.', { n: p.tile });
    }
  }
  renderPalette();
  tabs.draw.reset();
  tabs.map.reset();
  changed();
  toast(said);
}

function load(p, blocks) {
  project = p;
  project.videos = project.videos || []; // (templates and projects from before videos)
  setProject(project);
  $('title').value = project.title;
  if (!$('look').options.length) for (const [k, l] of Object.entries(LOOKS)) $('look').append(new Option(l.name, k));
  $('look').value = project.look || '';
  renderPalette();
  blocksBroken = false;
  if (ws) {
    loading = true;
    ws.clear();
    try { if (blocks || project.blocks) Blockly.serialization.workspaces.load(blocks || project.blocks, ws); }
    catch {
      blocksBroken = true; // they stay as they were stored until the blocks are changed by hand
      oops(t('Los bloques de este juego no se han podido abrir. Si tienes su archivo, ábrelo otra vez con «Abrir».'));
    }
    if (blocks) ws.cleanUp(); // a template's blocks: in a column, none on top of another
    loading = false;
  }
  $('player').removeAttribute('src');
  tabs.draw.reset();
  tabs.map.reset();
  tabs.sound.reset();
  tabs.video.reset();
  changed();
}

// Nuevo and Abrir replace the game being made: it is kept as "previous", and the message offers it back.
async function replace(p, blocks, said) {
  await saveLocal(project, 'previous');
  load(p, blocks);
  showTab('draw');
  toast(said, { action: { label: t('Recuperar el anterior'), run: async () => {
    const prev = await loadLocal('previous');
    if (!prev) return oops(t('No queda ningún juego anterior.'));
    await saveLocal(project, 'previous');
    load(prev);
    toast(t('Has vuelto al juego anterior.'));
  } } });
}

// ------------------------------------------------------------------ the game

const fetched = new Map(); // what every game carries, read once
async function fetchBytes(f) {
  if (!fetched.has(f)) {
    const r = await fetch(f);
    if (!r.ok) throw new Error(t('falta {file} (¿se ha montado el editor con tools/make_editor.py?)', { file: f }));
    fetched.set(f, new Uint8Array(await r.arrayBuffer()));
  }
  return fetched.get(f);
}
async function getGameFiles() { // -> [[path in the game, bytes]]: kit and its libraries, and the game's letters
  const out = [];
  for (const f of GAME_FILES) {
    const font = f.match(/^fonts\/(FONT_\w+\.fnt)$/); // the game's own letters, when it chose some
    const from = font && project.font ? `fonts/${project.font}/${font[1]}` : f;
    out.push([f.replace(/^lib\//, ''), await fetchBytes(from)]);
  }
  return out;
}

export function luaCode() { return ws ? workspaceLua(ws) : ''; }

async function gameFilesOf(opts) { // the game's files (Map path -> bytes); opts.start: a level to begin with
  if (!blocksBroken) project.blocks = Blockly.serialization.workspaces.save(ws);
  const audio = await audioFiles(project);
  return buildFiles(project, luaCode(), await getGameFiles(), { ...opts, audio, cover: await coverBytes() });
}
async function buildZip(opts) { return zip(await gameFilesOf(opts), project.id); }

function renderStart() { // Play from the cover or any level
  const sel = $('play-start'), was = sel.value;
  sel.replaceChildren(new Option(project.cover.on ? t('la portada') : t('el primer nivel'), ''));
  project.levels.forEach((l, i) => sel.append(new Option(`${i + 1}. ${l.name}`, l.id)));
  sel.value = [...sel.options].some(o => o.value === was) ? was : '';
}

let playing = false;
async function play() {
  if (playing) return;
  playing = true;
  showTab('game');
  const status = $('game-status');
  status.textContent = t('Preparando el juego…');
  status.classList.remove('error');
  try {
    const bytes = await buildZip({ start: $('play-start').value || null });
    const frame = $('player');
    const ready = new Promise(resolve => { frame.onload = resolve; });
    const words = LANG === 'es' ? '' : '&lang=' + LANG; // the player's own words, in the editor's language
    frame.src = 'player/player.html?embed=1&t=' + Date.now() + words; /* a fresh engine: it starts once per page */
    await ready;
    frame.contentWindow.postMessage({ pinyol: 'play', zip: bytes.buffer }, location.origin, [bytes.buffer]);
    status.textContent = TOUCH ? t('Juega con los botones de debajo de la pantalla.')
      : t('Flechas o WASD: mover · Z: A · X: B · C: C · P: START · Mayús+Esc: salir del juego. Haz clic en el juego para jugar.');
    frame.focus();
  } catch (e) {
    status.textContent = t('No se ha podido preparar el juego: {why}', { why: e.message });
    status.classList.add('error');
  } finally {
    playing = false;
  }
}

function download(bytes, name, type) {
  const a = document.createElement('a');
  a.href = URL.createObjectURL(new Blob([bytes], { type }));
  a.download = name;
  a.click();
  setTimeout(() => URL.revokeObjectURL(a.href), 5000);
}

// ------------------------------------------------------------------ to the console: the cable or the card

function openConsole() {
  $('zip-name').textContent = project.id + '.zip';
  $('folder-name').textContent = project.id;
  $('cable-send').disabled = !cableWorks;
  $('cable-progress').hidden = true;
  const status = $('cable-status');
  status.classList.remove('error');
  status.textContent = cableWorks ? '' : t('Este navegador no puede usar el cable: usa Chrome o Edge en un ordenador, o la tarjeta.');
  $('console').showModal();
}

async function busy(button, text, work) { // a button that says what it does while it does it, and cannot be pressed twice
  const label = button.innerHTML;
  button.disabled = true;
  button.textContent = text;
  try { return await work(); } finally { button.disabled = false; button.innerHTML = label; }
}

function initConsole() {
  $('export').addEventListener('click', openConsole);
  $('zip-download').addEventListener('click', e => busy(e.currentTarget, t('Preparando…'), async () => {
    try {
      download(await buildZip(), project.id + '.zip', 'application/zip');
      $('cable-status').textContent = '';
      toast(t('Descargado {file}: sigue los pasos para copiarlo a la tarjeta.', { file: project.id + '.zip' }));
    } catch (err) { oops(t('No se ha podido preparar el juego: {why}', { why: err.message })); }
  }));
  $('cable-send').addEventListener('click', e => busy(e.currentTarget, t('Enviando…'), async () => {
    const status = $('cable-status'), bar = $('cable-progress');
    status.classList.remove('error');
    status.textContent = t('Preparando el juego…');
    try {
      const files = await gameFilesOf();
      status.textContent = t('Elige la consola en la ventana del navegador.');
      bar.value = 0;
      bar.hidden = false;
      await send(files, project.id, f => { bar.value = Math.round(f * 100); status.textContent = t('Enviando… {n} %', { n: bar.value }); });
      status.textContent = t('¡Ya está! El juego empieza en la consola.');
    } catch (err) {
      bar.hidden = true;
      status.textContent = t('No se ha podido enviar: {why}.', { why: err.message });
      status.classList.add('error');
    }
  }));
}

// ------------------------------------------------------------------ tabs and buttons

const TABS = () => [...document.querySelectorAll('[role=tab]')];

function showTab(name) {
  for (const b of TABS()) {
    const on = b.dataset.tab === name;
    b.setAttribute('aria-selected', String(on));
    b.tabIndex = on ? 0 : -1; // the tab list is one stop for Tab; the arrows move inside it
  }
  for (const s of document.querySelectorAll('.tab')) s.hidden = s.id !== 'tab-' + name;
  if (name === 'logic' && ws) Blockly.svgResize(ws);
  if (name === 'map') tabs.map.render();
  if (name === 'draw') tabs.draw.render();
  if (name === 'game') {
    renderStart();
    if (!$('player').getAttribute('src')) play(); // the tab plays, as the button does, the first time
  }
}

function initTabs() {
  for (const b of TABS()) {
    b.addEventListener('click', () => showTab(b.dataset.tab));
    b.addEventListener('keydown', e => {
      const list = TABS(), i = list.indexOf(b);
      const to = { ArrowRight: i + 1, ArrowLeft: i - 1, Home: 0, End: list.length - 1 }[e.key];
      if (to === undefined) return;
      e.preventDefault();
      const next = list[(to + list.length) % list.length];
      showTab(next.dataset.tab);
      next.focus();
      next.scrollIntoView({ inline: 'nearest', block: 'nearest' });
    });
  }
}

function initMenu() { // Nuevo: a list that opens under the button, closes with Escape or a click elsewhere
  const button = $('new'), list = $('new-list');
  const open = on => { list.hidden = !on; button.setAttribute('aria-expanded', String(on)); };
  button.addEventListener('click', () => { open(list.hidden); if (!list.hidden) list.querySelector('button').focus(); });
  list.addEventListener('keydown', e => { if (e.key === 'Escape') { open(false); button.focus(); } });
  addEventListener('click', e => { if (!list.hidden && !e.target.closest('.menu')) open(false); });
  const fresh = (label, make) => {
    const b = Object.assign(document.createElement('button'), { textContent: label });
    b.addEventListener('click', () => {
      open(false);
      button.focus();
      make();
    });
    list.append(b);
  };
  for (const tpl of TEMPLATES)
    fresh(tpl.label, async () => replace(await tpl.make(), tpl.blocks ? await tpl.blocks() : templateBlocks(tpl.key),
                                         t('Juego nuevo: {name}.', { name: tpl.label })));
  fresh(t('Vacío'), () => replace(templateEmpty(), { blocks: { languageVersion: 0, blocks: [] } }, t('Juego nuevo, vacío.')));
}

function initBlockly() {
  Object.assign(Blockly.Msg, { // Blockly's own words, said as the editor's blocks say them
    CONTROLS_IF_MSG_ELSE: t('si no'), CONTROLS_IF_MSG_ELSEIF: t('si no, si'), VARIABLES_SET: t('poner %1 a %2'),
    MATH_CHANGE_TITLE: t('sumar %2 a %1'), MATH_RANDOM_INT_TITLE: t('número al azar entre %1 y %2'),
  });
  defineBlocks();
  const theme = Blockly.Theme.defineTheme('pinyol', {
    base: Blockly.Themes.Classic,
    componentStyles: { workspaceBackgroundColour: '#1b1724', toolboxBackgroundColour: '#221d2e',
                       toolboxForegroundColour: '#f1e9da', flyoutBackgroundColour: '#2b2539',
                       flyoutForegroundColour: '#f1e9da', flyoutOpacity: 0.96, scrollbarColour: '#3a3150',
                       insertionMarkerColour: '#ffffff', insertionMarkerOpacity: 0.3, cursorColour: '#d0d0d0' },
    fontStyle: { family: 'system-ui, sans-serif', size: 12 },
  });
  ws = Blockly.inject('blockly', { toolbox: TOOLBOX, theme, trashcan: true, renderer: 'zelos',
                                   zoom: { controls: true, wheel: true, startScale: 0.8 }, grid: { spacing: 24, length: 2, colour: '#2b2539' } });
  ws.addChangeListener(Blockly.Events.disableOrphans); // a block outside an event does nothing: it looks off
  document.querySelector('.blocklyComputeCanvas')?.setAttribute('aria-hidden', 'true'); // Blockly's, to measure text
  new ResizeObserver(() => Blockly.svgResize(ws)).observe($('blockly'));
  let codeTimer = 0;
  ws.addChangeListener(e => {
    if (e.isUiEvent || loading) return;
    blocksBroken = false; // changed by hand: these are the blocks now
    changed();
    clearTimeout(codeTimer);
    codeTimer = setTimeout(() => { $('lua-code').textContent = luaCode(); }, 300);
  });
}

// Blockly's own words (its menus, its built-in blocks) in the editor's language, before any block is made
function blocklyWords() {
  return new Promise((done, fail) => document.head.append(Object.assign(document.createElement('script'), {
    src: `vendor/blockly/msg/${LANG}.js`, onload: done, onerror: () => fail(new Error(`vendor/blockly/msg/${LANG}.js`)) })));
}

async function init() {
  translatePage();
  tabs.draw = initDrawings(app);
  tabs.map = initMap(app);
  tabs.sound = initSounds(app);
  tabs.video = initVideos(app);
  try { await blocklyWords(); } catch (e) { console.error(e); } // without them the blocks still work (their own words do)
  initBlockly();
  const saved = await loadLocal();
  if (saved) load(saved);
  else load(TEMPLATES[0].make(), templateBlocks(TEMPLATES[0].key));

  initTabs();
  initMenu();
  initConsole();
  $('look').addEventListener('change', e => applyLook(e.target.value));
  for (const [k, name] of Object.entries(LANGS)) $('ui-lang').append(new Option(name, k)); // each in its own words
  $('ui-lang').value = LANG;
  $('ui-lang').addEventListener('change', async e => { // the game kept first: the page starts again
    if (await save() || confirm(t('El juego no se ha podido guardar y se perderá al cambiar de idioma. ¿Cambiar igualmente?')))
      chooseLang(e.target.value);
    else e.target.value = LANG;
  });
  $('title').addEventListener('change', e => { // the game's folder on the card follows its name: two games, two folders
    project.title = e.target.value.trim().slice(0, 40) || t('Juego');
    project.id = safeName(project.title, 'juego');
    changed();
    tabs.map.render();
  });
  $('open').addEventListener('change', async e => {
    const f = e.target.files[0];
    e.target.value = '';
    if (!f) return;
    let p;
    try { p = check(JSON.parse(await f.text())); }
    catch { return oops(t('Ese archivo no es un juego del editor. Abre un archivo .pinyol.json hecho con «Guardar archivo».')); }
    replace(p, null, t('Abierto {title}.', { title: p.title }));
  });
  $('save').addEventListener('click', () => {
    if (!blocksBroken) project.blocks = Blockly.serialization.workspaces.save(ws);
    download(new TextEncoder().encode(JSON.stringify(pack(project))), project.id + '.pinyol.json', 'application/json');
    toast(t('Guardado en el archivo {file} (en tus descargas).', { file: project.id + '.pinyol.json' }));
  });
  $('play').addEventListener('click', play);
  $('restart').addEventListener('click', play);
  $('toast-close').addEventListener('click', () => $('toast').classList.remove('shown'));
  addEventListener('message', e => { /* the player: what went wrong, or the way out of the game (Mayús+Esc) */
    if (e.origin !== location.origin || !e.data) return;
    if (e.data.pinyol === 'error') {
      $('game-status').textContent = e.data.message;
      $('game-status').classList.add('error');
    } else if (e.data.pinyol === 'leave') $('restart').focus();
  });
  // a file dropped where nothing takes it must not open in the tab, leaving the editor
  addEventListener('dragover', e => e.preventDefault());
  addEventListener('drop', e => e.preventDefault());
  renderStart();
  initGuide(app, showTab);
  window.pinyolEditor = { get project() { return project; }, buildZip, luaCode, load: p => load(check(p)) }; // for tests
}

init();
