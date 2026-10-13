// The project: everything a game made in the editor is, as plain data (saved in the browser, or as a .json file).
// build.js turns it into a game folder np2d plays.

export const FORMAT = 3; // 3: levels and a cover; 2: pixels in the console's colours (RGB565); 1: palette indices
export const TILE = 16; // the map's grid, in the world's pixels
export const MAP_MAX = 64; // tiles a side: the map is drawn once into a canvas of at most 1024 px
export const LEVELS_MAX = 32;
export const MAX_SIDE = 512; // a drawing's width or height (a background two screens wide)
export const MAX_PIXELS = 768 * 1024; // all drawings' frames together: 1.5 MB of the console's memory
const SEE_THROUGH = 0xF81F; // a saved frame's see-through pixel; a real colour that is this one becomes 0xF81E

// 16 of PICO-8's colours and 8 more: colours at hand that go together (any other can be picked)
export const PALETTE = [
  '#000000', '#1D2B53', '#7E2553', '#008751', '#AB5236', '#5F574F', '#C2C3C7', '#FFF1E8',
  '#FF004D', '#FFA300', '#FFEC27', '#00E436', '#29ADFF', '#83769C', '#FF77A8', '#FFCCAA',
  '#6CB4E0', '#3A3466', '#F2B233', '#E8443A', '#6B4A2E', '#3FA34D', '#2F7FD0', '#8E4FC2',
];

// What a drawing is for. An object moves by itself in one of these ways (kit.lua's behaviours).
export const BEHAVIOURS = {
  platformer: 'Jugador de plataformas (flechas y A para saltar)',
  topdown: 'Jugador visto desde arriba (flechas)',
  patrol: 'Patrulla (anda y se da la vuelta)',
  chase: 'Persigue al jugador',
  shot: 'Proyectil (vuela recto)',
  still: 'Quieto',
};

export const SIZES = [8, 16, 24, 32, 48, 64];

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

export function pixelsOf(drawings) { return drawings.reduce((n, d) => n + d.w * d.h * d.frames.length, 0); }

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
function art(rows, colours) {
  const h = rows.length, w = rows[0].length, f = [];
  for (const r of rows) for (const c of r) f.push(c === '.' ? -1 : hex565(PALETTE[colours[c]]));
  return { w, h, frame: f };
}

function drawing(name, rows, colours, extra = {}) {
  const frames = Array.isArray(rows[0]) ? rows : [rows];
  const parts = frames.map(r => art(r, colours));
  return { name, w: parts[0].w, h: parts[0].h, frames: parts.map(p => p.frame), use: 'tile', solid: false,
           behaviour: 'still', speed: 1, jump: 4.5, animate: 8, parallax: 0.5, ...extra };
}

// an explorer of our own: a blue woolly hat, an amber coat, boots; two frames of walking
const HERO = [
  ['................', '.....hhhhhh.....', '....hhhhhhhh....', '...hHHHHHHHHh...', '....ssssssss....', '....sesssses....',
   '....ssssssss....', '.....ssssss.....', '....cccccccc....', '...cccccccccc...', '..sccCccccCccs..', '..s.cccccccc.s..',
   '....pppppppp....', '....ppp..ppp....', '....ppp..ppp....', '...bbbb..bbbb...'],
  ['................', '.....hhhhhh.....', '....hhhhhhhh....', '...hHHHHHHHHh...', '....ssssssss....', '....sesssses....',
   '....ssssssss....', '.....ssssss.....', '....cccccccc....', '...cccccccccc...', '..sccCccccCccs..', '..s.cccccccc.s..',
   '....pppppppp....', '....ppp...pp....', '...bbbb...pp....', '..........bbb...'],
];
const HERO_COLOURS = { h: 12, H: 22, s: 15, e: 0, c: 18, C: 9, p: 17, b: 20 };

const GROUND = ['gggggggggggggggg', 'gGGgggGGgggGGggg', 'GllGGGllGGGllGGG', 'llllllllllllllll', 'llLlllllllLlllll',
  'llllllLllllllllL', 'lLlllllllLllllll', 'lllllllllllllLll', 'llllLlllllllllll', 'lllllllllLllllll', 'lLllllllllllllll',
  'llllllLllllllLll', 'llllllllllllllll', 'llLlllllllLlllll', 'llllllllLlllllll', 'llllllllllllllll'];

const BRICK = ['oooooooooooooooo', 'oOOOOOOooOOOOOOo', 'oOOOOOOooOOOOOOo', 'oOOOOOOooOOOOOOo', 'oooooooooooooooo',
  'OOOooOOOOOOooOOO', 'OOOooOOOOOOooOOO', 'OOOooOOOOOOooOOO', 'oooooooooooooooo', 'oOOOOOOooOOOOOOo', 'oOOOOOOooOOOOOOo',
  'oOOOOOOooOOOOOOo', 'oooooooooooooooo', 'OOOooOOOOOOooOOO', 'OOOooOOOOOOooOOO', 'OOOooOOOOOOooOOO'];

const COIN = [
  ['..yyyy..', '.yYYYYy.', 'yYyyyyYy', 'yYyYYyYy', 'yYyYYyYy', 'yYyyyyYy', '.yYYYYy.', '..yyyy..'],
  ['...yy...', '..yYYy..', '..yyYy..', '..yYYy..', '..yYYy..', '..yyYy..', '..yYYy..', '...yy...'],
];

const SLIME = [
  ['................', '................', '................', '................', '................', '................',
   '.....pppppp.....', '...pppppppppp...', '..ppPPppppPPpp..', '..ppWkppppWkpp..', '.pppWkppppWkppp.', '.pppppppppppppp.',
   '.pppppppppppppp.', 'pppppppppppppppp', 'pppppppppppppppp', '.pp.pp.pp.pp.pp.'],
  ['................', '................', '................', '................', '................', '................',
   '................', '.....pppppp.....', '...pppppppppp...', '..ppPPppppPPpp..', '..ppWkppppWkpp..', '.pppWkppppWkppp.',
   '.pppppppppppppp.', 'pppppppppppppppp', 'pppppppppppppppp', 'pp.pp.pp.pp.pp.p'],
];

const SPIKES = ['................', '................', '................', '................', '................',
  '................', '................', '................', '...w.......w....', '...w.......w....', '..www.....www...',
  '..www.....www...', '.wwwww...wwwww..', '.wwwww...wwwww..', 'wwwwwww.wwwwwwww', 'ssssssssssssssss'];

const FLAG = ['..w.............', '..wRRRRR........', '..wRRRRRRR......', '..wRRRRRRRRR....', '..wRRRRRRR......',
  '..wRRRRR........', '..w.............', '..w.............', '..w.............', '..w.............', '..w.............',
  '..w.............', '..w.............', '..w.............', '.www............', 'wwwww...........'];

// hills behind the map, drawn by code: two rows of them, the far one paler; as wide as they repeat
function hills() {
  const w = 128, h = 160, f = blankFrame(w, h), far = rgb565(150, 196, 170), near = rgb565(104, 160, 120);
  for (let x = 0; x < w; x++) {
    const a = x / w * 2 * Math.PI;
    const top = Math.round(92 + 10 * Math.sin(a) + 5 * Math.sin(3 * a + 1)), front = Math.round(116 + 8 * Math.sin(2 * a + 2) + 4 * Math.sin(5 * a));
    for (let y = top; y < h; y++) f[y * w + x] = y >= front ? near : far;
  }
  return { name: 'montes', w, h, frames: [f], use: 'backdrop', solid: false, behaviour: 'still', speed: 1, jump: 4.5,
           animate: 8, parallax: 0.4 };
}

// A game to start from: a little platformer, every part of the editor used once
export function templatePlatformer() {
  const P = { r: 19, b: 4, s: 15, d: 22, y: 10, g: 21, G: 11, l: 20, L: 4, o: 20, O: 4, Y: 9, p: 23, P: 14, W: 7, k: 0,
              w: 6, R: 8 };
  const drawings = [
    drawing('heroe', HERO, HERO_COLOURS, { use: 'object', behaviour: 'platformer', speed: 1.6, jump: 4.6, animate: 8 }),
    drawing('suelo', GROUND, P, { solid: true }),
    drawing('ladrillo', BRICK, P, { solid: true }),
    drawing('moneda', COIN, P, { use: 'object', behaviour: 'still', speed: 0, animate: 10 }),
    drawing('babosa', SLIME, P, { use: 'object', behaviour: 'patrol', speed: 0.5, animate: 14 }),
    drawing('pinchos', SPIKES, P),
    drawing('meta', FLAG, P, { use: 'object', behaviour: 'still', speed: 0 }),
    hills(),
  ];
  const tiles = ['suelo', 'ladrillo', 'pinchos'];
  const field = (W, H, paint) => { // a map from a function that puts tiles
    const cells = new Array(W * H).fill(0);
    paint((x, y, t) => { cells[y * W + x] = tiles.indexOf(t) + 1; });
    return { w: W, h: H, tiles: tiles.slice(), cells };
  };
  const meadow = field(40, 10, put => {
    for (let x = 0; x < 40; x++) if (x < 14 || x > 16) put(x, 9, 'suelo');
    for (const x of [8, 9, 10, 22, 23, 24, 25]) put(x, 5, 'ladrillo');
    put(30, 8, 'pinchos');
    put(31, 8, 'pinchos');
  });
  const cave = field(30, 10, put => {
    for (let x = 0; x < 30; x++) if (x !== 9 && x !== 10 && x !== 19 && x !== 20) put(x, 9, 'suelo');
    for (let x = 0; x < 30; x++) put(x, 0, 'ladrillo');
    for (const x of [4, 5, 6, 12, 13, 14, 15]) put(x, 6, 'ladrillo');
    for (const x of [22, 23, 24]) put(x, 4, 'ladrillo');
    put(16, 8, 'pinchos');
    put(17, 8, 'pinchos');
  });
  const levels = [
    { id: 'nivel1', name: 'Nivel 1: el prado', map: meadow, background: '#6CB4E0', camera: 'heroe', hide: [],
      objects: [{ kind: 'heroe', x: 24, y: 112 }, { kind: 'moneda', x: 132, y: 64 }, { kind: 'moneda', x: 148, y: 64 },
        { kind: 'moneda', x: 372, y: 64 }, { kind: 'moneda', x: 404, y: 64 }, { kind: 'babosa', x: 290, y: 128 },
        { kind: 'meta', x: 600, y: 128 }] },
    { id: 'nivel2', name: 'Nivel 2: la cueva', map: cave, background: '#2A2338', camera: 'heroe', hide: ['montes'],
      objects: [{ kind: 'heroe', x: 24, y: 112 }, { kind: 'moneda', x: 84, y: 80 }, { kind: 'moneda', x: 212, y: 80 },
        { kind: 'moneda', x: 228, y: 80 }, { kind: 'moneda', x: 372, y: 48 }, { kind: 'babosa', x: 200, y: 128 },
        { kind: 'babosa', x: 280, y: 128 }, { kind: 'babosa', x: 400, y: 128 }, { kind: 'meta', x: 452, y: 128 }] },
  ];
  return {
    format: FORMAT, id: 'aventura', title: 'Mi aventura', drawings, levels,
    cover: { on: true, subtitle: 'Pulsa A para empezar', picture: 'montes', background: '#6CB4E0' },
    ending: '¡Has terminado el juego!',
    sounds: [
      { name: 'moneda', recipe: 'coin', seed: 3 },
      { name: 'salto', recipe: 'jump', seed: 2 },
      { name: 'golpe', recipe: 'hit', seed: 5 },
    ],
    blocks: null, // the starter blocks are made by blocks.js (templateBlocks): they need Blockly's ids
  };
}

export function newLevel(id, name) {
  return { id, name, map: { w: 15, h: 10, tiles: [], cells: new Array(150).fill(0) }, objects: [], background: '#1D2B53',
           camera: '', hide: [] };
}

export function templateEmpty() {
  const level = newLevel('nivel1', 'Nivel 1');
  level.objects.push({ kind: 'jugador', x: 112, y: 72 });
  return {
    format: FORMAT, id: 'juego', title: 'Juego nuevo',
    drawings: [{ name: 'jugador', w: 16, h: 16, frames: [blankFrame(16, 16)], use: 'object', behaviour: 'topdown',
                 speed: 1.5, jump: 4.5, animate: 8, solid: false, parallax: 0.5 }],
    levels: [level], cover: { on: true, subtitle: 'Pulsa A para empezar', picture: '', background: '#1D2B53' },
    ending: '¡Has ganado!', sounds: [], blocks: null,
  };
}

// made safe after loading: a file from anywhere may be anything
export function check(p) {
  if (!p || typeof p !== 'object') throw new Error('No es un proyecto');
  const out = { format: FORMAT, id: safeName(p.id, 'juego'), title: String(p.title || 'Juego').slice(0, 40), drawings: [],
                levels: [], sounds: [], blocks: p.blocks && typeof p.blocks === 'object' ? p.blocks : null };
  const names = new Set();
  const old = !(p.format >= 2), palette = PALETTE.map(hex565); // format 1: indices into the palette
  const pixel = v => (!Number.isInteger(v) || v < 0 ? -1 : old ? (v < palette.length ? palette[v] : -1) : v <= 0xFFFF ? v : -1);
  for (const d of Array.isArray(p.drawings) ? p.drawings.slice(0, 64) : []) {
    const w = clampInt(d.w, 1, MAX_SIDE, 16), h = clampInt(d.h, 1, MAX_SIDE, 16);
    const frames = (Array.isArray(d.frames) ? d.frames.slice(0, 8) : []).map(f =>
      (typeof f === 'string' ? decodeFrame(f, w * h) : null) ||
      Array.from({ length: w * h }, (_, i) => (Array.isArray(f) ? pixel(f[i]) : -1)));
    const name = uniqueName(safeName(d.name), names);
    names.add(name);
    out.drawings.push({ name, w, h, frames: frames.length ? frames : [blankFrame(w, h)],
                        use: ['object', 'backdrop'].includes(d.use) ? d.use : 'tile', solid: !!d.solid,
                        behaviour: BEHAVIOURS[d.behaviour] ? d.behaviour : 'still',
                        speed: clampNum(d.speed, 0, 6, 1.5), jump: clampNum(d.jump, 0, 10, 4.5),
                        animate: clampNum(d.animate, 0, 60, 8), parallax: clampNum(d.parallax, 0, 1, 0.5) });
  }
  const levels = Array.isArray(p.levels) ? p.levels : [{ id: 'nivel1', name: 'Nivel 1', map: p.map, objects: p.objects,
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
  if (!out.levels.length) out.levels.push(newLevel('nivel1', 'Nivel 1'));
  const c = p.cover && typeof p.cover === 'object' ? p.cover : {};
  out.cover = { on: c.on !== false, subtitle: String(c.subtitle ?? 'Pulsa A para empezar').slice(0, 60),
                picture: names.has(safeName(c.picture, '')) ? safeName(c.picture) : '', background: colour(c.background, '#1D2B53') };
  out.ending = String(p.ending || '¡Has ganado!').slice(0, 60);
  const snames = new Set();
  for (const s of Array.isArray(p.sounds) ? p.sounds.slice(0, 48) : []) {
    const name = uniqueName(safeName(s.name, 'sonido'), snames);
    snames.add(name);
    out.sounds.push({ name, recipe: typeof s.recipe === 'string' ? s.recipe : 'blip', seed: clampInt(s.seed, 1, 999999, 1),
                      params: s.params && typeof s.params === 'object' ? s.params : null });
  }
  return out;
}

function colour(v, d) { return /^#[0-9a-fA-F]{6}$/.test(v) ? v : d; }
function clampNum(v, lo, hi, d) { v = Number(v); return Number.isFinite(v) ? Math.min(hi, Math.max(lo, v)) : d; }
function clampInt(v, lo, hi, d) { return Math.round(clampNum(v, lo, hi, d)); }

const KEY = 'np2d-editor-project';
export function saveLocal(p) { try { localStorage.setItem(KEY, JSON.stringify(pack(p))); return true; } catch { return false; } }
export function loadLocal() {
  try { const s = localStorage.getItem(KEY); return s ? check(JSON.parse(s)) : null; } catch { return null; }
}
