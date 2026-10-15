// The games "Nuevo" starts from: a platformer, an adventure seen from above, a space shooter and a box-pushing puzzle,
// each with its own drawings (original, as characters or as code), levels, sounds and a cover; their blocks are in
// blocks.js (templateBlocks). And an empty game. Their texts and language are the editor's; ids and names stay.
import { FORMAT, TILE, DRAWING, blankFrame, rgb565, drawing, newLevel, check } from './project.js';
import { LANG, t } from './i18n.js';

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
  return { ...DRAWING, name: 'montes', w, h, frames: [f], use: 'backdrop', parallax: 0.4 };
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
    { id: 'nivel1', name: t('Nivel 1: el prado'), map: meadow, background: '#6CB4E0', camera: 'heroe', hide: [],
      objects: [{ kind: 'heroe', x: 24, y: 112 }, { kind: 'moneda', x: 132, y: 64 }, { kind: 'moneda', x: 148, y: 64 },
        { kind: 'moneda', x: 372, y: 64 }, { kind: 'moneda', x: 404, y: 64 }, { kind: 'babosa', x: 290, y: 128 },
        { kind: 'meta', x: 600, y: 128 }] },
    { id: 'nivel2', name: t('Nivel 2: la cueva'), map: cave, background: '#2A2338', camera: 'heroe', hide: ['montes'],
      objects: [{ kind: 'heroe', x: 24, y: 112 }, { kind: 'moneda', x: 84, y: 80 }, { kind: 'moneda', x: 212, y: 80 },
        { kind: 'moneda', x: 228, y: 80 }, { kind: 'moneda', x: 372, y: 48 }, { kind: 'babosa', x: 200, y: 128 },
        { kind: 'babosa', x: 280, y: 128 }, { kind: 'babosa', x: 400, y: 128 }, { kind: 'meta', x: 452, y: 128 }] },
  ];
  return {
    format: FORMAT, id: 'mi_aventura', title: t('Mi aventura'), lang: LANG, drawings, levels,
    cover: { on: true, subtitle: t('Pulsa A para empezar'), picture: 'montes', background: '#6CB4E0' },
    ending: t('¡Has terminado el juego!'),
    sounds: [
      { name: 'moneda', recipe: 'coin', seed: 3 },
      { name: 'salto', recipe: 'jump', seed: 2 },
      { name: 'golpe', recipe: 'hit', seed: 5 },
    ],
    blocks: null, // the starter blocks are made by blocks.js (templateBlocks): they need Blockly's ids
  };
}


export function templateEmpty() {
  const level = newLevel('nivel1', t('Nivel {n}', { n: 1 }));
  level.objects.push({ kind: 'jugador', x: 112, y: 72 });
  return {
    format: FORMAT, id: 'juego_nuevo', title: t('Juego nuevo'), lang: LANG,
    drawings: [{ ...DRAWING, name: 'jugador', w: 16, h: 16, frames: [blankFrame(16, 16)], use: 'object', behaviour: 'topdown',
                 speed: 1.5 }],
    levels: [level], cover: { on: true, subtitle: t('Pulsa A para empezar'), picture: '', background: '#1D2B53' },
    ending: t('¡Has ganado!'), sounds: [], videos: [], blocks: null,
  };
}


// ------------------------------------------------------------------ helpers for the other templates

// a picture from a function of (x, y) -> a key of `colours` or '.': textures (water, stone, stars) read better as code
function rowsOf(w, h, at) { return Array.from({ length: h }, (_, y) => Array.from({ length: w }, (_, x) => at(x, y)).join('')); }

// a level from rows of characters, one a tile: `tiles` says which tile each character is, `things` which object
// starts there (a character can be both: a box on the floor)
function levelOf(id, name, rows, tiles, things, extra = {}) {
  const names = [...new Set(Object.values(tiles))], objects = [];
  if (rows.some(r => r.length !== rows[0].length)) throw new Error(`level ${id}: rows of different lengths`);
  rows.forEach((r, y) => [...r].forEach((c, x) => { if (things[c]) objects.push({ kind: things[c], x: x * TILE, y: y * TILE }); }));
  return { id, name, objects, camera: '', hide: [], background: '#1D2B53', ...extra,
           map: { w: rows[0].length, h: rows.length, tiles: names,
                  cells: rows.join('').split('').map(c => (tiles[c] ? names.indexOf(tiles[c]) + 1 : 0)) } };
}

function game(id, title, drawings, levels, sounds, cover, ending) {
  return { format: FORMAT, id, title, lang: LANG, drawings, levels, sounds,
           cover: { on: true, subtitle: t('Pulsa A para empezar'), ...cover }, ending, blocks: null };
}

// ------------------------------------------------------------------ an adventure seen from above

const EXPLORER = [
  ['................', '.....rrrrrr.....', '....rrrrrrrr....', '...rrssssssrr...', '...rsessssesr...', '...rssssssssr...',
   '....ssssssss....', '.....ssssss.....', '....tttttttt....', '...tttttttttt...', '..sttTttttTtts..', '..s.bbbbbbbb.s..',
   '....tttttttt....', '....lll..lll....', '....lll..lll....', '...fff....fff...'],
  ['................', '.....rrrrrr.....', '....rrrrrrrr....', '...rrssssssrr...', '...rsessssesr...', '...rssssssssr...',
   '....ssssssss....', '.....ssssss.....', '....tttttttt....', '...tttttttttt...', '..sttTttttTtts..', '..s.bbbbbbbb.s..',
   '....tttttttt....', '....lll...ll....', '...fff....ll....', '..........fff...'],
];
const TREE = ['.....gggggg.....', '...gggGgggggg...', '..gggGGggggGgg..', '.ggGGggggGGgggg.', '.gggggggGGggGgg.',
  'ggGgggggggggGggg', 'gggGGgggGgggggGg', 'gggggggGGgggGggg', '.ggGgggggggggGg.', '.gggggGggGgggg..', '..ggggggggggg...',
  '....gggtggg.....', '......tttt......', '......tttt......', '.....tttttt.....', '................'];
const WATER = rowsOf(16, 16, (x, y) => ((x + 3 * y) % 11 === 0 || (x + 3 * y + 1) % 11 === 0) && y % 4 === 1 ? 'W'
  : (x * 7 + y * 5) % 23 === 0 ? 'L' : 'w');
const DOOR = rowsOf(16, 16, (x, y) => (x === 0 || x === 15 || y === 0 ? 'D' : x >= 7 && x <= 8 && y >= 7 && y <= 9 ? (y === 8 ? 'k' : 'L')
  : x === 5 || x === 10 ? 'D' : y % 5 === 2 ? 'd' : 'o'));
const KEY = ['................', '................', '................', '....yyy.........', '...yY..y........',
  '...y...yyyyyyy..', '...y...y...y.y..', '....yyy....y.y..', '................', '................', '................',
  '................', '................', '................', '................', '................'];
const GEM = [
  ['................', '................', '.......p........', '......pPp.......', '.....pPWPp......', '....pPPPPPp.....',
   '.....pPPPp......', '......pPp.......', '.......p........', '................', '................', '................',
   '................', '................', '................', '................'],
  ['................', '................', '.......p........', '......pPp.......', '.....pPPPp......', '....pPPPWPp.....',
   '.....pPPPp......', '......pPp.......', '.......p........', '................', '................', '................',
   '................', '................', '................', '................'],
];
const GHOST = [
  ['................', '.....wwwwww.....', '....wwwwwwww....', '...wwwwwwwwww...', '...wwkwwwwkww...', '...wwkwwwwkww...',
   '...wwwwwwwwww...', '...wwwwwwwwww...', '...wwwwmmwwww...', '...wwwwwwwwww...', '...wwwwwwwwww...', '...lwwwwwwwwl...',
   '...w.ww..ww.w...', '................', '................', '................'],
  ['................', '.....wwwwww.....', '....wwwwwwww....', '...wwwwwwwwww...', '...wwkwwwwkww...', '...wwkwwwwkww...',
   '...wwwwwwwwww...', '...wwwwwwwwww...', '...wwwwmmwwww...', '...wwwwwwwwww...', '...wwwwwwwwww...', '...lwwwwwwwwl...',
   '...ww.ww..ww.w..', '................', '................', '................'],
];
const CRAB = [
  ['................', '................', '................', '..cc........cc..', '.c..c......c..c.', '.cc.c......c.cc.',
   '...cc......cc...', '....cccccccc....', '...cckcccckcc...', '..cccccccccccc..', '..cccccccccccc..', '...cccccccccc...',
   '..c.c.c..c.c.c..', '.c..c.c..c.c..c.', '................', '................'],
  ['................', '................', '..cc........cc..', '.c..c......c..c.', '.cc.c......c.cc.', '...cc......cc...',
   '...cc......cc...', '....cccccccc....', '...cckcccckcc...', '..cccccccccccc..', '..cccccccccccc..', '...cccccccccc...',
   '.c..c.c..c.c..c.', '..c.c.c..c.c.c..', '................', '................'],
];
const STAIRS = rowsOf(16, 16, (x, y) => {
  if (x === 0 || x === 15 || y === 0 || y === 15) return 'd';
  const k = Math.floor((y - 1) / 3.5); // four steps going down, each further in
  if (x <= k * 2) return 'd';
  return (y - 1) % 3.5 < 1 ? 'L' : 'M';
});
const STONE = rowsOf(16, 16, (x, y) => (y % 8 === 0 || (x + (Math.floor(y / 8) % 2) * 8) % 16 === 0 ? 'k'
  : (y % 8 === 1 || x % 8 === 1) ? 'L' : 'm'));
const TUFTS = ['................', '................', '..g.....g.......', '.g.g...g.g......', '.....g.....g....',
  '....g.g...g.g...', '................', '................', '..........g.....', '.g.......g.g....', 'g.g.............',
  '................', '.....g..........', '....g.g.....g...', '...........g.g..', '................'];

export function templateAdventure() {
  const C = { r: 4, s: 15, e: 0, t: 21, T: 3, b: 20, l: 17, f: 20, g: 21, G: 3, w: 22, W: 7, L: 12, D: 20, d: 20, o: 4,
              k: 0, y: 10, Y: 18, p: 23, P: 14, m: 13, c: 19, M: 5 };
  const drawings = [
    drawing('exploradora', EXPLORER, C, { use: 'object', behaviour: 'topdown', speed: 1.3, animate: 8 }),
    drawing('arbol', TREE, C, { solid: true }),
    drawing('agua', WATER, C, { solid: true }),
    drawing('puerta', DOOR, { ...C, L: 6, o: 4, d: 20 }, { solid: true }),
    drawing('roca', STONE, { k: 0, L: 6, m: 5 }, { solid: true }),
    drawing('hierba', TUFTS, { g: 11 }),
    drawing('llave', KEY, { y: 10, Y: 18 }, { use: 'object', behaviour: 'still', speed: 0 }),
    drawing('gema', GEM, C, { use: 'object', behaviour: 'still', speed: 0, animate: 20 }),
    drawing('cangrejo', CRAB, C, { use: 'object', behaviour: 'patrol', speed: 0.6, animate: 10, gravity: false }),
    drawing('fantasma', GHOST, { w: 7, k: 0, m: 2, l: 13 }, { use: 'object', behaviour: 'chase', speed: 0.35, animate: 16 }),
    drawing('escalera', STAIRS, { d: 0, L: 6, M: 5 }, { use: 'object', behaviour: 'still', speed: 0 }),
  ];
  const things = { P: 'exploradora', k: 'llave', g: 'gema', c: 'cangrejo', f: 'fantasma', E: 'escalera' };
  const forest = levelOf('nivel1', t('El bosque'), [
    '####################',
    '#P.."".....#......E#',
    '#......~~~.#..g....#',
    '#..g...~~~.#....g..#',
    '#......~~~.D.......#',
    '#..""......#..c....#',
    '####.#######.......#',
    '#....k.....#.......#',
    '#.g..""....#...g...#',
    '#......c...#.......#',
    '#..........#.......#',
    '####################',
  ], { '#': 'arbol', '~': 'agua', D: 'puerta', '"': 'hierba' }, things, { background: '#4C8F3C', camera: 'exploradora' });
  const crypt = levelOf('nivel2', t('La cripta'), [
    '####################',
    '#P....#............#',
    '#.....#..g......g..#',
    '#..g..#....####....#',
    '#.....D.........f..#',
    '#.....#....####....#',
    '#.....#............#',
    '####.##..g......g..#',
    '#....k#............#',
    '#..f..#........E...#',
    '#.....#............#',
    '####################',
  ], { '#': 'roca', D: 'puerta' }, things, { background: '#26222F', camera: 'exploradora' });
  return game('la_llave_perdida', t('La llave perdida'), drawings, [forest, crypt],
    [{ name: 'gema', recipe: 'coin', seed: 7 }, { name: 'llave', recipe: 'powerup', seed: 3 },
     { name: 'puerta', recipe: 'blip', seed: 5 }, { name: 'golpe', recipe: 'hit', seed: 4 }],
    { picture: 'exploradora', background: '#4C8F3C' }, t('¡Has encontrado la salida!'));
}

// ------------------------------------------------------------------ a space shooter

const SHIP = [
  ['.......ww.......', '.......ww.......', '......wbbw......', '......wbbw......', '.....wwbbww.....', '.....wwwwww.....',
   '....wwwwwwww....', '...rwwwwwwwwr...', '..rrwwwwwwwwrr..', '.rrrwwwwwwwwrrr.', 'rrrrwgwwwwgwrrrr', 'rrr.wwwwwwww.rrr',
   'rr...wwwwww...rr', '.....oyyyyo.....', '......oyyo......', '.......oo.......'],
  ['.......ww.......', '.......ww.......', '......wbbw......', '......wbbw......', '.....wwbbww.....', '.....wwwwww.....',
   '....wwwwwwww....', '...rwwwwwwwwr...', '..rrwwwwwwwwrr..', '.rrrwwwwwwwwrrr.', 'rrrrwgwwwwgwrrrr', 'rrr.wwwwwwww.rrr',
   'rr...wwwwww...rr', '......oyyo......', '.......oo.......', '................'],
];
const LASER = ['...bb...', '...bb...', '...ww...', '...ww...', '...ww...', '...bb...', '...bb...', '........'];
const UFO = [
  ['................', '................', '......gggg......', '.....gwwggg.....', '....gggggggg....', '..pppppppppppp..',
   '.ppYppYppYppYpp.', 'pppppppppppppppp', '.pppppppppppppp.', '...pp......pp...', '................', '................',
   '................', '................', '................', '................'],
  ['................', '................', '......gggg......', '.....gwwggg.....', '....gggggggg....', '..pppppppppppp..',
   '.pYppYppYppYppp.', 'pppppppppppppppp', '.pppppppppppppp.', '...pp......pp...', '................', '................',
   '................', '................', '................', '................'],
];
const COMET = [
  ['.....y.....y....', '.....oy...yo....', '......oy.yo.....', '.......ooo......', '......ommmo.....', '.....mmMmmmm....',
   '....mmmmmmMmm...', '....mMmmmmmmm...', '....mmmmMmmmm...', '.....mmmmmmm....', '......mmMmm.....', '.......mmm......',
   '................', '................', '................', '................'],
  ['....y.....y.....', '.....oy..yo.....', '......oyyo......', '.......ooo......', '......ommmo.....', '.....mmMmmmm....',
   '....mmmmmmMmm...', '....mMmmmmmmm...', '....mmmmMmmmm...', '.....mmmmmmm....', '......mmMmm.....', '.......mmm......',
   '................', '................', '................', '................'],
];
function stars(seed, n, bright) { // dots on nothing, 128 x 128, the same every time
  let s = seed;
  const rnd = k => ((s = (s * 1103515245 + 12345) & 0x7fffffff) >> 12) % k, dots = new Map(); // high bits: the low repeat
  for (let i = 0; i < n; i++) dots.set(rnd(128) * 128 + rnd(128), bright && rnd(4) === 0 ? 'W' : bright ? 'w' : 'd');
  return rowsOf(128, 128, (x, y) => dots.get(y * 128 + x) || '.');
}

export function templateShooter() {
  const C = { w: 6, b: 12, r: 19, g: 5, o: 9, y: 10, W: 7, p: 13, Y: 10, m: 5, M: 6 };
  const drawings = [
    drawing('nave', SHIP, C, { use: 'object', behaviour: 'topdown', speed: 2.2, animate: 4 }),
    drawing('laser', LASER, { b: 12, w: 7 }, { use: 'object', behaviour: 'shot', speed: 5, dir: 'up' }),
    drawing('ovni', UFO, { g: 11, w: 7, p: 13, Y: 10 }, { use: 'object', behaviour: 'shot', speed: 0.8, dir: 'down', animate: 12 }),
    drawing('cometa', COMET, { y: 10, o: 9, m: 4, M: 20 }, { use: 'object', behaviour: 'shot', speed: 1.7, dir: 'down', animate: 6 }),
    drawing('estrellas', stars(7, 60, true), { w: 6, W: 7 }, { use: 'backdrop', parallax: 0, drift: 'down', drift_speed: 0.6 }),
    drawing('polvo', stars(99, 110, false), { d: 13 }, { use: 'backdrop', parallax: 0, drift: 'down', drift_speed: 0.25 }),
  ];
  const space = (id, name) => levelOf(id, name, Array(10).fill('...............'), {}, {},
    { background: '#0B0A1A', camera: 'nave', objects: [{ kind: 'nave', x: 112, y: 136 }] });
  return game('defensa_galactica', t('Defensa galáctica'), drawings,
    [space('nivel1', t('Oleada 1')), space('nivel2', t('Oleada 2: cometas'))],
    [{ name: 'laser', recipe: 'laser', seed: 1 }, { name: 'explosion', recipe: 'explosion', seed: 2 },
     { name: 'golpe', recipe: 'hit', seed: 1 }],
    { picture: 'estrellas', background: '#0B0A1A' }, t('¡Has salvado la galaxia!'));
}

// ------------------------------------------------------------------ a puzzle: boxes pushed onto their marks

const ROBOT = [
  ['.......r........', '.......w........', '....wwwwwwww....', '....wbbwwbbw....', '....wbbwwbbw....', '....wwwwwwww....',
   '....wwkkkkww....', '....wwwwwwww....', '.....gggggg.....', '..wwwwwwwwwwww..', '..wwssssssssww..', '..wwssyyyyssww..',
   '..wwwwwwwwwwww..', '....ww....ww....', '....ww....ww....', '...www....www...'],
  ['.......d........', '.......w........', '....wwwwwwww....', '....wbbwwbbw....', '....wbbwwbbw....', '....wwwwwwww....',
   '....wwkkkkww....', '....wwwwwwww....', '.....gggggg.....', '..wwwwwwwwwwww..', '..wwssssssssww..', '..wwssyyyyssww..',
   '..wwwwwwwwwwww..', '....ww....ww....', '...www....ww....', '..........www...'],
];
const CRATE = rowsOf(16, 16, (x, y) => (x === 0 || y === 0 || x === 15 || y === 15 ? 'D'
  : x === 1 || y === 1 || x === 14 || y === 14 ? 'o' : x === y || x === 15 - y || x === y + 1 || x === 16 - y ? 'D' : 'O'));
const BRICKWALL = rowsOf(16, 16, (x, y) => (y % 4 === 3 || (x + (Math.floor(y / 4) % 2) * 4) % 8 === 7 ? 'k'
  : y % 4 === 0 ? 'L' : 'm'));
const FLOOR = rowsOf(16, 16, (x, y) => (x === 0 || y === 0 ? 'd' : 'f'));
const MARK = rowsOf(16, 16, (x, y) => { const d = Math.hypot(x - 7.5, y - 7.5); return d > 4 && d < 6 ? 'a' : d < 1.6 ? 'a' : '.'; });

export function templatePuzzle() {
  const drawings = [
    drawing('robot', ROBOT, { r: 8, d: 2, w: 6, b: 12, k: 5, g: 13, s: 22, y: 10 },
            { use: 'object', behaviour: 'grid', speed: 2, animate: 6 }),
    drawing('caja', CRATE, { D: 20, o: 9, O: 4 }, { use: 'object', behaviour: 'push', speed: 2 }),
    drawing('muro', BRICKWALL, { k: 0, L: 13, m: 5 }, { solid: true }),
    drawing('suelo', FLOOR, { d: 1, f: 17 }),
    drawing('diana', MARK, { a: 18 }),
  ];
  const tiles = { '#': 'muro', _: 'suelo', P: 'suelo', B: 'suelo', x: 'diana' };
  const things = { P: 'robot', B: 'caja' };
  const room = (id, name, rows) => levelOf(id, name, rows, tiles, things, { background: '#14121C' });
  const empty = '...............';
  return game('cajas_y_robot', t('Cajas y robot'), drawings, [
    room('nivel1', t('Puzle 1: un empujón'), [empty, empty, '..#########....', '..#_______#....', '..#_P_B__x#....',
      '..#_______#....', '..#########....', empty, empty, empty]),
    room('nivel2', t('Puzle 2: dos cajas'), [empty, '...#########...', '...#_______#...', '...#_B___B_#...',
      '...#___P___#...', '...#_______#...', '...#x_____x#...', '...#########...', empty, empty]),
    room('nivel3', t('Puzle 3: tres cajas'), [empty, '..##########...', '..#____#___#...', '..#_B__#_B_#...',
      '..#__B_____#...', '..#_P__##__#...', '..#x__x___x#...', '..##########...', empty, empty]),
  ], [{ name: 'bien', recipe: 'powerup', seed: 6 }, { name: 'otra', recipe: 'blip', seed: 2 }],
  { picture: 'robot', background: '#14121C' }, t('¡Todos los puzles resueltos!'));
}

// what "Nuevo" offers, in its order
export const TEMPLATES = [
  { key: 'plataformas', label: t('Plataformas'), make: templatePlatformer },
  { key: 'aventura', label: t('Aventura desde arriba'), make: templateAdventure },
  { key: 'naves', label: t('Naves'), make: templateShooter },
  { key: 'puzle', label: t('Puzle de cajas'), make: templatePuzzle },
  { key: 'abella', label: 'Abella (Game Boy)', // a whole game, in Catalan, its data loaded only when chosen (abella.js)
    make: async () => check(structuredClone((await import('./abella.js')).ABELLA)),
    blocks: async () => (await import('./abella.js')).ABELLA_BLOCKS },
];
