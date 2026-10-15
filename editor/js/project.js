// The project: everything a game made in the editor is, as plain data (saved in the browser, or as a .json file).
// build.js turns it into a game folder pinyol plays.
import { checkSong } from './song.js';
import { t } from './i18n.js';

const VIDEO_B64_MAX = 4.5 * (1 << 20); // a 3 MB clip, as base64
export const FORMAT = 3; // 3: levels and a cover; 2: pixels in the console's colours (RGB565); 1: palette indices
export const TILE = 16; // the map's grid, in the world's pixels
export const MAP_MAX = 64; // tiles a side: the map is drawn once into a canvas of at most 1024 px
export const LEVELS_MAX = 32;
const FILE_MAX = 24 << 20; // a sound file kept in the project, as base64: songs of a few minutes
export const MAX_SIDE = 512; // a drawing's width or height (a background two screens wide)
export const MAX_BYTES = 4 << 20; // all drawings together, as built (build.js sizeOf): the console's picture memory (PIC_BUDGET)
const SEE_THROUGH = 0xF81F; // a saved frame's see-through pixel; a real colour that is this one becomes 0xF81E

// 16 of PICO-8's colours and 8 more: colours at hand that go together (any other can be picked)
export const COLOUR_NAMES = [t('negro'), t('azul marino'), t('granate'), t('verde oscuro'), t('marrón'), t('gris oscuro'),
  t('gris claro'), t('blanco'), t('rojo'), t('naranja'), t('amarillo'), t('verde'), t('azul'), t('lavanda'), t('rosa'),
  t('carne'), t('celeste'), t('índigo'), t('ámbar'), t('rojo teja'), t('chocolate'), t('verde hierba'), t('azul medio'),
  t('morado')]; // PALETTE's, said
export const PALETTE = [
  '#000000', '#1D2B53', '#7E2553', '#008751', '#AB5236', '#5F574F', '#C2C3C7', '#FFF1E8',
  '#FF004D', '#FFA300', '#FFEC27', '#00E436', '#29ADFF', '#83769C', '#FF77A8', '#FFCCAA',
  '#6CB4E0', '#3A3466', '#F2B233', '#E8443A', '#6B4A2E', '#3FA34D', '#2F7FD0', '#8E4FC2',
];

// What a drawing is for. An object moves by itself in one of these ways (kit.lua's behaviours).
export const BEHAVIOURS = {
  platformer: t('Es el jugador: anda y salta (flechas y A)'),
  topdown: t('Es el jugador, visto desde arriba (flechas)'),
  grid: t('Es el jugador: se mueve de casilla en casilla (puzles)'),
  patrol: t('Va y viene (se da la vuelta en las paredes)'),
  chase: t('Persigue al jugador'),
  shot: t('Vuela recto (disparos, cosas que caen)'),
  push: t('Se deja empujar (cajas de puzle)'),
  still: t('No se mueve'),
};
export const SHOT_DIRS = { forward: t('hacia donde mira quien lo crea'), up: t('hacia arriba'), down: t('hacia abajo'),
                           left: t('hacia la izquierda'), right: t('hacia la derecha') };
export const DRIFTS = { '': t('no'), down: t('hacia abajo'), up: t('hacia arriba'), left: t('hacia la izquierda'),
                        right: t('hacia la derecha') };

// what a drawing is unless told otherwise (gravity null: what its behaviour says, platformers and patrols fall)
export const DRAWING = { use: 'tile', solid: false, behaviour: 'still', speed: 1, jump: 4.5, animate: 8, gravity: null,
                         dir: 'forward', parallax: 0.5, drift: '', drift_speed: 0.5 };

export const SIZES = [8, 16, 24, 32, 48, 64];
export const MAX_FRAMES = 16; // a drawing's frames: room for named animations (still, walking, hit)
export const ANIMS = { idle: t('Quieto'), walk: t('Andar'), hit: t('Golpe') }; // kit.lua's named animations
export const LANGS = { es: 'Castellano', ca: 'Català', en: 'English' }; // a game's (and the editor's): each in its own words

// The letters a game can have: the engine's own, or one of these (fonts/<id>/: the four FONT_*.fnt the game carries,
// made by tools/font2fnt.py from third_party/fonts, and font.woff2 for the cover's preview)
export const FONTS = { '': t('La del motor'), silkscreen: 'Silkscreen', micro5: 'Micro 5', pressstart2p: 'Arcade 8',
                       jersey15: 'Jersey 15' };

// A game's look, as a console drew it: its colours (only those, or any snapped to the console's own), the size of its
// map's tiles, its letters, and the colours of the game's own texts and hearts (kit.lua's data.style)
const MD = c => Math.min(252, Math.round(c / 36) * 36); // a Mega Drive's 512 colours: 8 steps a channel
const GBA = c => Math.min(248, Math.round(c / 8) * 8); // a Game Boy Advance's 32768: 32 steps a channel
export const LOOKS = {
  '': { name: t('Libre'), palette: null, tile: 16, font: '' },
  gameboy: { name: 'Game Boy', tile: 16, font: 'silkscreen', background: '#9BBC0F',
             palette: ['#0F380F', '#306230', '#8BAC0F', '#9BBC0F'],
             names: [t('verde negro'), t('verde oscuro'), t('verde claro'), t('verde pálido')],
             style: { text: '#9BBC0F', outline: '#0F380F', accent: '#8BAC0F', bad: '#9BBC0F', heart: '#306230' } },
  pico8: { name: 'PICO-8', tile: 8, font: 'micro5', background: '#1D2B53',
           palette: null, // PALETTE's first 16, below
           style: { text: '#FFF1E8', outline: '#000000', accent: '#FFEC27', bad: '#FF004D', heart: '#FF004D' } },
  spectrum: { name: 'ZX Spectrum', tile: 8, font: 'pressstart2p', background: '#000000',
              palette: ['#000000', '#0000D7', '#D70000', '#D700D7', '#00D700', '#00D7D7', '#D7D700', '#D7D7D7',
                        '#0000FF', '#FF0000', '#FF00FF', '#00FF00', '#00FFFF', '#FFFF00', '#FFFFFF'],
              names: [t('negro'), t('azul'), t('rojo'), t('magenta'), t('verde'), t('cian'), t('amarillo'), t('blanco'),
                      t('azul brillante'), t('rojo brillante'), t('magenta brillante'), t('verde brillante'),
                      t('cian brillante'), t('amarillo brillante'), t('blanco brillante')],
              style: { text: '#FFFFFF', outline: '#000000', accent: '#FFFF00', bad: '#FF0000', heart: '#FF0000' } },
  '16bits': { name: t('16 bits'), tile: 16, font: 'jersey15', snap: MD, // any colour, as one of the console's 512
              palette: ['#000000', '#242424', '#6C6C6C', '#B4B4B4', '#FCFCFC', '#480000', '#B42424', '#FC4848',
                        '#FC9048', '#FCD86C', '#FCFC90', '#244800', '#48906C', '#6CD848', '#B4FC6C', '#002448',
                        '#0048B4', '#2490FC', '#6CD8FC', '#B4FCFC', '#480048', '#902490', '#D848B4', '#FC90D8',
                        '#482400', '#906C48', '#D8B490', '#FCD8B4', '#244848', '#486C90', '#9090D8', '#D8D8FC'] },
  gba: { name: 'Game Boy Advance', tile: 16, font: '', snap: GBA, // any colour in 15 bits; 32 bright ones at hand
         palette: ['#101018', '#283048', '#485878', '#8098B8', '#D0D8E8', '#F8F8F8', '#602030', '#C03040', '#F86048',
                   '#F8A060', '#F8D048', '#F8F0A0', '#284020', '#488838', '#80C050', '#C8E878', '#183858', '#2868B0',
                   '#48A0E8', '#98D8F8', '#382058', '#7048A8', '#B080E0', '#F0A8D8', '#483020', '#886040', '#C89868',
                   '#F0D0A8', '#205858', '#38A098', '#78D8C0', '#A8A8B0'],
         names: [t('negro tinta'), t('azul noche'), t('pizarra'), t('pizarra clara'), t('niebla'), t('blanco'), t('granate'),
                 t('rojo'), t('coral'), t('naranja'), t('amarillo'), t('crema'), t('verde bosque'), t('verde'), t('lima'),
                 t('lima pálido'), t('azul profundo'), t('azul'), t('celeste'), t('hielo'), t('morado oscuro'), t('morado'),
                 t('lila'), t('rosa'), t('marrón oscuro'), t('marrón'), t('canela'), t('piel'), t('verde azulado oscuro'),
                 t('verde azulado'), t('menta'), t('gris')],
         style: { text: '#F8F8F8', outline: '#101018', accent: '#F8D048', bad: '#F86048', heart: '#F05068' } },
};
LOOKS.pico8.palette = PALETTE.slice(0, 16);
LOOKS.pico8.names = COLOUR_NAMES.slice(0, 16);
export const lookOf = p => LOOKS[p && p.look] || LOOKS[''];

// the colour a look allows nearest to an RGB565 one: its palette's closest, or snapped to the console's own
export function lookColour(look, v) {
  if (v < 0 || !look.palette || look === LOOKS['']) return v;
  const [r, g, b] = rgbOf(v);
  if (look.snap) return rgb565(look.snap(r), look.snap(g), look.snap(b));
  let best = v, d = Infinity;
  for (const hex of look.palette) {
    const [pr, pg, pb] = rgbOf(hex565(hex)), e = (pr - r) ** 2 * 3 + (pg - g) ** 2 * 4 + (pb - b) ** 2 * 2;
    if (e < d) d = e, best = hex565(hex);
  }
  return best;
}

// a name a file and Lua can take: lowercase letters, digits, _ (accents dropped, spaces as _)
export function safeName(s, fallback = 'cosa') {
  const n = String(s || '').normalize('NFD').replace(/[̀-ͯ]/g, '').toLowerCase()
    .replace(/[^a-z0-9_]+/g, '_').replace(/^_+|_+$/g, '').slice(0, 24);
  return n && /^[a-z_]/.test(n) ? n : (n ? 'x' + n : fallback);
}

export function uniqueName(name, taken) {
  let n = name, i = 2;
  while (taken.has(n)) n = name.slice(0, 21) + '_' + i++;
  return n;
}

export function blankFrame(w, h) { return new Array(w * h).fill(-1); }

// named animations: {idle: [first, last], walk: [...], hit: [...]}, frames from 0; null without any
export function checkAnims(a, frames) {
  if (!a || typeof a !== 'object') return null;
  const out = {};
  for (const k of Object.keys(ANIMS))
    if (Array.isArray(a[k]) && a[k].length === 2) {
      const [x, y] = a[k].map(v => clampInt(v, 0, frames - 1, 0));
      out[k] = [Math.min(x, y), Math.max(x, y)];
    }
  return Object.keys(out).length ? out : null;
}

// ------------------------------------------------------------------ colours as the console has them

export function rgb565(r, g, b) {
  const v = ((r >> 3) << 11) | ((g >> 2) << 5) | (b >> 3);
  return v === SEE_THROUGH ? v - 1 : v;
}
export function hex565(hex) { const v = parseInt(hex.slice(1), 16); return rgb565(v >> 16, (v >> 8) & 255, v & 255); }
export function rgbOf(v) { // back to 8 bits a channel, as the screen shows it
  const r = v >> 11, g = (v >> 5) & 63, b = v & 31;
  return [(r << 3) | (r >> 2), (g << 2) | (g >> 4), (b << 3) | (b >> 2)];
}
export function hexOf(v) { return '#' + rgbOf(v).map(c => c.toString(16).padStart(2, '0')).join(''); }


// a frame saved as text: two bytes a pixel, little-endian, SEE_THROUGH for -1 (a quarter of a list of numbers)
export function encodeFrame(f) {
  const b = new Uint8Array(f.length * 2);
  f.forEach((v, i) => { const u = v < 0 ? SEE_THROUGH : v; b[2 * i] = u & 255; b[2 * i + 1] = u >> 8; });
  let s = '';
  for (let i = 0; i < b.length; i += 8192) s += String.fromCharCode.apply(null, b.subarray(i, i + 8192));
  return btoa(s);
}
function decodeFrame(text, n) {
  let s;
  try { s = atob(text); } catch { return null; }
  if (s.length !== n * 2) return null;
  const f = new Array(n);
  for (let i = 0; i < n; i++) { const u = s.charCodeAt(2 * i) | (s.charCodeAt(2 * i + 1) << 8); f[i] = u === SEE_THROUGH ? -1 : u; }
  return f;
}

// what is saved (in the browser or a file): the project with its frames as text
export function pack(p) { return { ...p, drawings: p.drawings.map(d => ({ ...d, frames: d.frames.map(encodeFrame) })) }; }

// a drawing from rows of characters: '.' see-through, else a key into `colours` (indices into PALETTE)
export function art(rows, colours) {
  const h = rows.length, w = rows[0].length, f = [];
  if (rows.some(r => r.length !== w)) throw new Error('a drawing\'s rows are not all ' + w + ' long: ' + rows.join('|'));
  for (const r of rows) for (const c of r) f.push(c === '.' ? -1 : hex565(PALETTE[colours[c]]));
  return { w, h, frame: f };
}

export function drawing(name, rows, colours, extra = {}) {
  const frames = Array.isArray(rows[0]) ? rows : [rows];
  const parts = frames.map(r => art(r, colours));
  return { ...DRAWING, name, w: parts[0].w, h: parts[0].h, frames: parts.map(p => p.frame), ...extra };
}

export function newLevel(id, name) {
  return { id, name, map: { w: 15, h: 10, tiles: [], cells: new Array(150).fill(0) }, objects: [], background: '#1D2B53',
           camera: '', hide: [], music: '' };
}

// made safe after loading: a file from anywhere may be anything
export function check(p) {
  if (!p || typeof p !== 'object') throw new Error('No es un proyecto');
  const out = { format: FORMAT, id: safeName(p.id, 'juego'), title: String(p.title || t('Juego')).slice(0, 40), drawings: [],
                author: String(p.author || '').slice(0, 40), about: String(p.about || '').slice(0, 140), // game.json's
                tagline: String(p.tagline || '').slice(0, 40), // the line under the name in the console's menu
                look: LOOKS[p.look] ? p.look : '', tile: p.tile === 8 ? 8 : 16, font: FONTS[p.font] !== undefined ? p.font : '',
                lang: LANGS[p.lang] ? p.lang : 'es', // (before languages: Spanish; a new game is in the editor's, templates.js)
                levels: [], sounds: [], videos: [], blocks: p.blocks && typeof p.blocks === 'object' ? p.blocks : null };
  const names = new Set();
  const old = !(p.format >= 2), palette = PALETTE.map(hex565); // format 1: indices into the palette
  const pixel = v => (!Number.isInteger(v) || v < 0 ? -1 : old ? (v < palette.length ? palette[v] : -1) : v <= 0xFFFF ? v : -1);
  for (const d of Array.isArray(p.drawings) ? p.drawings.slice(0, 64) : []) {
    const w = clampInt(d.w, 1, MAX_SIDE, 16), h = clampInt(d.h, 1, MAX_SIDE, 16);
    const frames = (Array.isArray(d.frames) ? d.frames.slice(0, MAX_FRAMES) : []).map(f =>
      (typeof f === 'string' ? decodeFrame(f, w * h) : null) ||
      Array.from({ length: w * h }, (_, i) => (Array.isArray(f) ? pixel(f[i]) : -1)));
    const name = uniqueName(safeName(d.name), names);
    names.add(name);
    out.drawings.push({ name, w, h, frames: frames.length ? frames : [blankFrame(w, h)],
                        use: ['object', 'backdrop'].includes(d.use) ? d.use : 'tile', solid: !!d.solid,
                        behaviour: BEHAVIOURS[d.behaviour] ? d.behaviour : 'still',
                        speed: clampNum(d.speed, 0, 6, 1.5), jump: clampNum(d.jump, 0, 10, 4.5),
                        animate: clampNum(d.animate, 0, 60, 8), parallax: clampNum(d.parallax, 0, 1, 0.5),
                        gravity: typeof d.gravity === 'boolean' ? d.gravity : null, dir: SHOT_DIRS[d.dir] ? d.dir : 'forward',
                        drift: DRIFTS[d.drift] !== undefined ? d.drift : '', drift_speed: clampNum(d.drift_speed, 0, 4, 0.5),
                        anims: checkAnims(d.anims, frames.length || 1) });
  }
  const levels = Array.isArray(p.levels) ? p.levels : [{ id: 'nivel1', name: t('Nivel {n}', { n: 1 }), map: p.map, objects: p.objects,
    background: p.background, camera: p.camera, hide: [] }]; // before levels: one map
  const ids = new Set();
  for (const l of levels.slice(0, LEVELS_MAX)) {
    const id = uniqueName(safeName(l.id, 'nivel'), ids);
    ids.add(id);
    const m = l.map || {};
    const mw = clampInt(m.w, 1, MAP_MAX, 15), mh = clampInt(m.h, 1, MAP_MAX, 10);
    const tiles = (Array.isArray(m.tiles) ? m.tiles : []).map(t => safeName(t)).filter(t => names.has(t)).slice(0, 250);
    const level = { id, name: String(l.name || id).slice(0, 40), objects: [], background: colour(l.background, '#1D2B53'),
                    camera: typeof l.camera === 'string' ? safeName(l.camera, '') : '',
                    hide: (Array.isArray(l.hide) ? l.hide : []).map(n => safeName(n)).filter(n => names.has(n)),
                    map: { w: mw, h: mh, tiles, cells: Array.from({ length: mw * mh }, (_, i) => {
                      const c = Array.isArray(m.cells) ? m.cells[i] : 0;
                      return Number.isInteger(c) && c >= 0 && c <= tiles.length ? c : 0;
                    }) } };
    for (const o of Array.isArray(l.objects) ? l.objects.slice(0, 500) : [])
      if (names.has(safeName(o.kind))) level.objects.push({ kind: safeName(o.kind), x: clampNum(o.x, 0, 1024, 0), y: clampNum(o.y, 0, 1024, 0) });
    out.levels.push(level);
  }
  if (!out.levels.length) out.levels.push(newLevel('nivel1', t('Nivel {n}', { n: 1 })));
  const c = p.cover && typeof p.cover === 'object' ? p.cover : {};
  out.cover = { on: c.on !== false, subtitle: String(c.subtitle ?? t('Pulsa A para empezar')).slice(0, 60),
                picture: names.has(safeName(c.picture, '')) ? safeName(c.picture) : '', background: colour(c.background, '#1D2B53') };
  out.ending = String(p.ending || t('¡Has ganado!')).slice(0, 60);
  const snames = new Set();
  for (const s of Array.isArray(p.sounds) ? p.sounds.slice(0, 48) : []) {
    const name = uniqueName(safeName(s.name, 'sonido'), snames);
    snames.add(name);
    if (s.song && typeof s.song === 'object') // composed in the editor (song.js): always music
      out.sounds.push({ name, song: checkSong(s.song), use: 'music' });
    else if (typeof s.file === 'string' && s.file && s.file.length < FILE_MAX && s.mod === true) // a tracker's .mod: music as it is
      out.sounds.push({ name, file: s.file, use: 'music', mod: true });
    else if (typeof s.file === 'string' && s.file && s.file.length < FILE_MAX) // brought in from a file (base64)
      out.sounds.push({ name, file: s.file, use: s.use === 'music' ? 'music' : 'effect', start: clampNum(s.start, 0, 3600, 0),
                        end: clampNum(s.end, 0, 3600, 0), volume: clampNum(s.volume, 0, 2, 1) });
    else
      out.sounds.push({ name, recipe: typeof s.recipe === 'string' ? s.recipe : 'blip', seed: clampInt(s.seed, 1, 999999, 1),
                        params: s.params && typeof s.params === 'object' ? s.params : null });
  }
  const vnames = new Set(); // videos made in the editor (videos.js): a clip's bytes as base64, and its numbers
  for (const v of Array.isArray(p.videos) ? p.videos.slice(0, 8) : []) {
    if (typeof v.npv !== 'string' || !v.npv || v.npv.length > VIDEO_B64_MAX) continue;
    const name = uniqueName(safeName(v.name, 'video'), vnames);
    vnames.add(name);
    out.videos.push({ name, npv: v.npv, w: clampInt(v.w, 1, 1024, 160), h: clampInt(v.h, 1, 1024, 120),
                      frames: clampInt(v.frames, 1, 100000, 1), fps: clampNum(v.fps, 1, 60, 10) });
  }
  const tunes = new Set(out.sounds.filter(x => x.use === 'music').map(x => x.name)); // music only from the sounds there are
  const tune = v => (tunes.has(safeName(v, '')) ? safeName(v) : '');
  out.levels.forEach((l, i) => { l.music = tune((levels[i] || {}).music); });
  out.cover.music = tune(c.music);
  return out;
}

function colour(v, d) { return /^#[0-9a-fA-F]{6}$/.test(v) ? v : d; }
function clampNum(v, lo, hi, d) { v = Number(v); return Number.isFinite(v) ? Math.min(hi, Math.max(lo, v)) : d; }
function clampInt(v, lo, hi, d) { return Math.round(clampNum(v, lo, hi, d)); }

// The project kept in the browser as it changes: IndexedDB, which has room for songs (localStorage, before, did not)
const KEY = 'np2d-editor-project';
function store(mode, use) {
  return new Promise((done, fail) => {
    const open = indexedDB.open('np2d-editor', 1);
    open.onupgradeneeded = () => open.result.createObjectStore('projects');
    open.onerror = () => fail(open.error);
    open.onsuccess = () => { // one connection a call, closed after: nothing held open blocks the next
      const db = open.result, t = db.transaction('projects', mode), r = use(t.objectStore('projects'));
      t.oncomplete = () => { db.close(); done(r.result); };
      t.onerror = () => { db.close(); fail(t.error); };
    };
  });
}
// key "current": the game being made; "previous": the one Nuevo or Abrir replaced, to get it back
export async function saveLocal(p, key = 'current') {
  try { await store('readwrite', s => s.put(pack(p), key)); return true; } catch { return false; }
}
export async function loadLocal(key = 'current') {
  try { const p = await store('readonly', s => s.get(key)); if (p) return check(p); } catch { /* none kept */ }
  if (key !== 'current') return null;
  try { const s = localStorage.getItem(KEY); return s ? check(JSON.parse(s)) : null; } catch { return null; } // before
}
