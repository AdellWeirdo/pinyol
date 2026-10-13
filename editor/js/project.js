// The project: everything a game made in the editor is, as plain data (saved in the browser, or as a .json file).
// build.js turns it into a game folder np2d plays.

export const FORMAT = 1;
export const TILE = 16; // the map's grid, in the world's pixels
export const MAP_MAX = 64; // tiles a side: the map is drawn once into a canvas of at most 1024 px

// 16 of PICO-8's colours and 8 more: a palette every drawing shares, so a game's colours go together
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

export const SIZES = [8, 16, 24, 32];

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

// a drawing from rows of characters: '.' see-through, else a key into `colours` (palette indices)
function art(rows, colours) {
  const h = rows.length, w = rows[0].length, f = [];
  for (const r of rows) for (const c of r) f.push(c === '.' ? -1 : colours[c]);
  return { w, h, frame: f };
}

function drawing(name, rows, colours, extra = {}) {
  const frames = Array.isArray(rows[0]) ? rows : [rows];
  const parts = frames.map(r => art(r, colours));
  return { name, w: parts[0].w, h: parts[0].h, frames: parts.map(p => p.frame), use: 'tile', solid: false, ...extra };
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
  ];
  const W = 40, H = 10, cells = new Array(W * H).fill(0);
  const tiles = ['suelo', 'ladrillo', 'pinchos'];
  const put = (x, y, t) => { cells[y * W + x] = tiles.indexOf(t) + 1; };
  for (let x = 0; x < W; x++) if (x < 14 || x > 16) put(x, H - 1, 'suelo');
  for (const x of [8, 9, 10, 22, 23, 24, 25]) put(x, 5, 'ladrillo');
  put(30, H - 2, 'pinchos');
  put(31, H - 2, 'pinchos');
  const objects = [{ kind: 'heroe', x: 24, y: 112 }, { kind: 'moneda', x: 132, y: 64 }, { kind: 'moneda', x: 148, y: 64 },
    { kind: 'moneda', x: 372, y: 64 }, { kind: 'moneda', x: 404, y: 64 }, { kind: 'babosa', x: 290, y: 128 },
    { kind: 'meta', x: 600, y: 128 }];
  return {
    format: FORMAT, id: 'aventura', title: 'Mi aventura', background: '#6CB4E0', camera: 'heroe',
    drawings, map: { w: W, h: H, tiles, cells }, objects,
    sounds: [
      { name: 'moneda', recipe: 'coin', seed: 3 },
      { name: 'salto', recipe: 'jump', seed: 2 },
      { name: 'golpe', recipe: 'hit', seed: 5 },
    ],
    blocks: null, // the starter blocks are made by blocks.js (templateBlocks): they need Blockly's ids
  };
}

export function templateEmpty() {
  return {
    format: FORMAT, id: 'juego', title: 'Juego nuevo', background: '#1D2B53', camera: '',
    drawings: [{ name: 'jugador', w: 16, h: 16, frames: [blankFrame(16, 16)], use: 'object', behaviour: 'topdown',
                 speed: 1.5, jump: 4.5, animate: 8, solid: false }],
    map: { w: 15, h: 10, tiles: [], cells: new Array(150).fill(0) }, objects: [{ kind: 'jugador', x: 112, y: 72 }],
    sounds: [], blocks: null,
  };
}

// made safe after loading: a file from anywhere may be anything
export function check(p) {
  if (!p || typeof p !== 'object') throw new Error('No es un proyecto');
  const out = { format: FORMAT, id: safeName(p.id, 'juego'), title: String(p.title || 'Juego').slice(0, 40),
                background: /^#[0-9a-fA-F]{6}$/.test(p.background) ? p.background : '#1D2B53',
                camera: typeof p.camera === 'string' ? safeName(p.camera, '') : '', drawings: [], objects: [], sounds: [],
                blocks: p.blocks && typeof p.blocks === 'object' ? p.blocks : null };
  const names = new Set();
  for (const d of Array.isArray(p.drawings) ? p.drawings.slice(0, 64) : []) {
    const w = SIZES.includes(d.w) ? d.w : 16, h = SIZES.includes(d.h) ? d.h : 16;
    const frames = (Array.isArray(d.frames) ? d.frames.slice(0, 8) : []).map(f =>
      Array.from({ length: w * h }, (_, i) => (Number.isInteger(f[i]) && f[i] >= 0 && f[i] < PALETTE.length ? f[i] : -1)));
    const name = uniqueName(safeName(d.name), names);
    names.add(name);
    out.drawings.push({ name, w, h, frames: frames.length ? frames : [blankFrame(w, h)],
                        use: d.use === 'object' ? 'object' : 'tile', solid: !!d.solid,
                        behaviour: BEHAVIOURS[d.behaviour] ? d.behaviour : 'still',
                        speed: clampNum(d.speed, 0, 6, 1.5), jump: clampNum(d.jump, 0, 10, 4.5),
                        animate: clampNum(d.animate, 0, 60, 8) });
  }
  const m = p.map || {};
  const mw = clampInt(m.w, 1, MAP_MAX, 15), mh = clampInt(m.h, 1, MAP_MAX, 10);
  const tiles = (Array.isArray(m.tiles) ? m.tiles : []).map(t => safeName(t)).filter(t => names.has(t)).slice(0, 250);
  out.map = { w: mw, h: mh, tiles, cells: Array.from({ length: mw * mh }, (_, i) => {
    const c = Array.isArray(m.cells) ? m.cells[i] : 0;
    return Number.isInteger(c) && c >= 0 && c <= tiles.length ? c : 0;
  }) };
  for (const o of Array.isArray(p.objects) ? p.objects.slice(0, 500) : [])
    if (names.has(safeName(o.kind))) out.objects.push({ kind: safeName(o.kind), x: clampNum(o.x, 0, 1024, 0), y: clampNum(o.y, 0, 1024, 0) });
  const snames = new Set();
  for (const s of Array.isArray(p.sounds) ? p.sounds.slice(0, 48) : []) {
    const name = uniqueName(safeName(s.name, 'sonido'), snames);
    snames.add(name);
    out.sounds.push({ name, recipe: typeof s.recipe === 'string' ? s.recipe : 'blip', seed: clampInt(s.seed, 1, 999999, 1),
                      params: s.params && typeof s.params === 'object' ? s.params : null });
  }
  return out;
}

function clampNum(v, lo, hi, d) { v = Number(v); return Number.isFinite(v) ? Math.min(hi, Math.max(lo, v)) : d; }
function clampInt(v, lo, hi, d) { return Math.round(clampNum(v, lo, hi, d)); }

const KEY = 'np2d-editor-project';
export function saveLocal(p) { try { localStorage.setItem(KEY, JSON.stringify(p)); return true; } catch { return false; } }
export function loadLocal() {
  try { const s = localStorage.getItem(KEY); return s ? check(JSON.parse(s)) : null; } catch { return null; }
}
