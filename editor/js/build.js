// From a project to a game folder np2d plays: game.json, data.lua (the drawings' sizes, kinds, the map, the objects,
// the sounds), main.lua (kit and the blocks' code), assets/SPR_<name> (each drawing in the engine's own format) and
// the four fonts. The same files go in the browser's player and in the .zip for the console's card.
import { TILE, MAX_PIXELS, pixelsOf } from './project.js';

// ------------------------------------------------------------------ pictures in the engine's format

// An object's frames cut to what is drawn in any of them: its hitbox is what you see. A tile keeps its whole square.
export function cropOf(d) {
  if (d.use !== 'object') return { x: 0, y: 0, w: d.w, h: d.h };
  let x0 = d.w, y0 = d.h, x1 = -1, y1 = -1;
  for (const f of d.frames)
    for (let y = 0; y < d.h; y++)
      for (let x = 0; x < d.w; x++)
        if (f[y * d.w + x] >= 0) x0 = Math.min(x0, x), y0 = Math.min(y0, y), x1 = Math.max(x1, x), y1 = Math.max(y1, y);
  if (x1 < 0) return { x: 0, y: 0, w: 1, h: 1 };
  return { x: x0, y: y0, w: x1 - x0 + 1, h: y1 - y0 + 1 };
}

function picture(d) { // -> {rgb565, mask|null, meta}
  const c = cropOf(d), n = d.frames.length, stride = (c.w + 7) >> 3;
  const px = new Uint8Array(c.w * c.h * n * 2), mask = new Uint8Array(stride * c.h * n);
  let seeThrough = false, i = 0;
  d.frames.forEach((f, k) => {
    for (let y = 0; y < c.h; y++)
      for (let x = 0; x < c.w; x++) {
        const p = f[(y + c.y) * d.w + x + c.x], v = p >= 0 ? p : 0;
        px[i++] = v & 255, px[i++] = v >> 8;
        if (p >= 0) mask[(k * c.h + y) * stride + (x >> 3)] |= 0x80 >> (x & 7);
        else seeThrough = true;
      }
  });
  const meta = { asset: 'SPR_' + d.name, type: 'sprite', w: c.w, h: c.h, frames: n, frame_ms: new Array(n).fill(0),
                 order: [...Array(n).keys()], anchor: [c.w >> 1, c.h - 1], tile: null,
                 rgb565: { endian: 'little', order: 'rgb', alpha: seeThrough ? 'mask1' : 'none' } };
  return { rgb565: px, mask: seeThrough ? mask : null, meta, crop: c };
}

// ------------------------------------------------------------------ Lua

export function lua(v, indent = '') { // a value as a Lua literal
  if (v === null || v === undefined) return 'nil';
  if (typeof v === 'boolean') return v ? 'true' : 'false';
  if (typeof v === 'number') return Number.isFinite(v) ? String(Math.round(v * 10000) / 10000) : '0';
  if (typeof v === 'string') return '"' + v.replace(/\\/g, '\\\\').replace(/"/g, '\\"').replace(/\n/g, '\\n') + '"';
  if (Array.isArray(v)) {
    const flat = v.every(x => typeof x !== 'object' || x === null);
    if (flat) { // numbers in lines of 32: a map stays readable
      const parts = v.map(x => lua(x));
      const lines = [];
      for (let i = 0; i < parts.length; i += 32) lines.push(parts.slice(i, i + 32).join(', '));
      return lines.length > 1 ? '{\n' + indent + '  ' + lines.join(',\n' + indent + '  ') + '\n' + indent + '}' : '{' + lines.join('') + '}';
    }
    return '{\n' + v.map(x => indent + '  ' + lua(x, indent + '  ')).join(',\n') + '\n' + indent + '}';
  }
  const keys = Object.keys(v).filter(k => v[k] !== undefined);
  if (!keys.length) return '{}';
  return '{\n' + keys.map(k => indent + '  ' + (/^[A-Za-z_][A-Za-z0-9_]*$/.test(k) ? k : '[' + lua(k) + ']') + ' = ' +
    lua(v[k], indent + '  ')).join(',\n') + '\n' + indent + '}';
}

const hex = c => parseInt(c.slice(1), 16);
const DRIFT = { '': () => ({}), down: v => ({ vy: v }), up: v => ({ vy: -v }), left: v => ({ vx: -v }), right: v => ({ vx: v }) };

function levelData(p, l, crops) {
  const backdrops = p.drawings.filter(d => d.use === 'backdrop' && !l.hide.includes(d.name)).slice(0, 3) // layers 1-3
    .map(d => ({ sprite: d.name, parallax: d.parallax, ...DRIFT[d.drift](d.drift_speed) }));
  return { id: l.id, name: l.name, background: hex(l.background), camera: l.camera || null, backdrops,
           objects: l.objects.filter(o => crops[o.kind]).map(o => ({ kind: o.kind, x: o.x + crops[o.kind].x, y: o.y + crops[o.kind].y })),
           map: l.map.tiles.length ? { w: l.map.w, h: l.map.h, tiles: l.map.tiles, cells: l.map.cells } : null };
}

function dataLua(p, crops, start) {
  const sprites = {}, kinds = {}, solid = {}, sounds = {};
  for (const d of p.drawings) {
    const c = crops[d.name];
    sprites[d.name] = { w: c.w, h: c.h, frames: d.frames.length };
    if (d.use === 'object') kinds[d.name] = { behaviour: d.behaviour, speed: d.speed, jump: d.jump, animate: d.animate,
                                              gravity: d.gravity ?? undefined, dir: d.behaviour === 'shot' ? d.dir : undefined };
    else if (d.use === 'tile' && d.solid) solid[d.name] = true;
  }
  for (const s of p.sounds) sounds[s.name] = s.params ? s.params : { recipe: s.recipe, seed: s.seed };
  const c = p.cover, pic = p.drawings.find(d => d.name === c.picture);
  const data = { title: p.title, tile: TILE, sprites, kinds, solid, sounds, ending: p.ending,
                 cover: c.on ? { text: p.title, subtitle: c.subtitle, background: hex(c.background), picture: pic ? pic.name : null,
                                 tiled: pic ? pic.use === 'backdrop' : null } : null,
                 levels: p.levels.map(l => levelData(p, l, crops)),
                 start: start || null }; // Play from a level, skipping the cover (never in the card's zip)
  return '-- Made by np2d\'s editor from the project "' + p.title.replace(/"/g, '') + '": change it there.\nreturn ' + lua(data) + '\n';
}

export function mainLua(p, blocksCode) {
  return `-- ${p.title.replace(/\n/g, ' ')}: made with np2d's editor. The blocks' code is below; kit.lua (a copy of np2d's
-- lib/kit.lua) does the rest: the levels, the map, the objects that move by themselves, the events.
kit = require("kit")
kit.setup(require("data"))

${blocksCode.trim()}

function _init() kit.init() end
function _update() kit.update() end
function _draw() kit.draw() end
`;
}

// ------------------------------------------------------------------ the folder

// -> Map of path -> Uint8Array, the game's files; `carried`: [[path, bytes]] every game has (fonts, kit), already read
export function buildFiles(p, blocksCode, carried, { start } = {}) {
  const used = pixelsOf(p.drawings);
  if (used > MAX_PIXELS)
    throw new Error(`los dibujos ocupan ${used * 2 >> 10} KB y la consola guarda ${MAX_PIXELS * 2 >> 10} KB: ` +
                    'quita fotogramas o haz más pequeños los dibujos grandes');
  const enc = new TextEncoder(), files = new Map(), crops = {};
  for (const d of p.drawings) {
    const pic = picture(d);
    crops[d.name] = pic.crop;
    files.set(`assets/SPR_${d.name}.rgb565`, pic.rgb565);
    if (pic.mask) files.set(`assets/SPR_${d.name}.mask`, pic.mask);
    files.set(`assets/SPR_${d.name}.meta.json`, enc.encode(JSON.stringify(pic.meta, null, 2) + '\n'));
  }
  files.set('game.json', enc.encode(JSON.stringify({ id: p.id, title: p.title, engine: 'np2d@2', main: 'main.lua',
    author: 'np2d editor', description: 'Hecho con el editor de np2d.' }, null, 2) + '\n'));
  files.set('data.lua', enc.encode(dataLua(p, crops, start)));
  files.set('main.lua', enc.encode(mainLua(p, blocksCode)));
  for (const [path, bytes] of carried) files.set(path, bytes);
  return files;
}
