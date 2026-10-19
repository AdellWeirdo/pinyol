// A drawing's animations, turning point and sheet: a project from before (animations as {first, last}) comes in with
// nothing lost; a drawing with a pivot and two animations at their own speeds builds with its anchor and frame_ms
// where they belong, and kit.lua gets them; a sheet in a grid is cut into its cells.
//   node editor/test/anims_test.mjs
import assert from 'node:assert/strict';
import { check, DRAWING, blankFrame } from '../js/project.js';
import { buildFiles } from '../js/build.js';
import { cutFrames, gridOf } from '../js/sprites.js';

// a project from before: its animations were ranges, at the drawing's pause, always going round
const old = check({ format: 3, drawings: [{ ...DRAWING, name: 'heroe', use: 'object', w: 8, h: 8, animate: 6,
  frames: [blankFrame(8, 8), blankFrame(8, 8), blankFrame(8, 8), blankFrame(8, 8)],
  anims: { idle: [0, 0], walk: [3, 1], hit: [3, 3], nada: [0, 1] } }] });
assert.deepEqual(old.drawings[0].anims, {
  idle: { frames: [0], fps: null, loop: true }, walk: { frames: [1, 2, 3], fps: null, loop: true },
  hit: { frames: [3], fps: null, loop: true } }); // (and a name kit.lua has no use for is left out)
assert.equal(old.drawings[0].pivot, null);
// out of bounds: frames past the last, a speed past 60 and one that is no number, a pivot outside the picture
const odd = check({ format: 3, drawings: [{ ...DRAWING, name: 'x', use: 'object', w: 8, h: 8, pivot: [20, -3],
  frames: [blankFrame(8, 8), blankFrame(8, 8)], anims: { idle: { frames: [0, 9], fps: 600 }, walk: { frames: [1], fps: 'a' } } }] });
assert.deepEqual(odd.drawings[0].anims, { idle: { frames: [0, 1], fps: 60, loop: true }, walk: { frames: [1], fps: null, loop: true } });
assert.deepEqual(odd.drawings[0].pivot, [7, 0]);

// a drawing whose pixels start at (2, 1), with its pivot at (5, 6): the anchor is the pivot in the cut picture
const px = blankFrame(10, 8);
for (let y = 1; y < 8; y++) for (let x = 2; x < 9; x++) px[y * 10 + x] = 0x07E0;
const p = check({ format: 3, drawings: [{ ...DRAWING, name: 'heroe', use: 'object', behaviour: 'still', w: 10, h: 8, animate: 6,
  frames: [px, px.slice(), px.slice(), px.slice()], pivot: [5, 6],
  anims: { idle: { frames: [0, 1], fps: 10 }, walk: { frames: [2, 3], loop: false } } }], levels: [] });
const files = buildFiles(p, '', []);
const meta = JSON.parse(new TextDecoder().decode(files.get('assets/SPR_heroe.meta.json')));
assert.deepEqual([meta.w, meta.h], [7, 7]);
assert.deepEqual(meta.anchor, [3, 5]); // (5 - 2, 6 - 1)
assert.deepEqual(meta.frame_ms, [100, 100, 100, 100]); // idle at 10 a second; walk at the drawing's 6 ticks: 100 ms too
const data = new TextDecoder().decode(files.get('data.lua'));
assert.match(data, /idle = \{\s*frames = \{0, 1\},\s*fps = 10\s*\}/);
assert.match(data, /walk = \{\s*frames = \{2, 3\},\s*loop = false\s*\}/);
assert.match(data, /pivot = \{3, 5\}/);
// without a pivot: the middle of the feet, as always, and no pivot for kit.lua
const plain = check({ ...p, drawings: [{ ...p.drawings[0], pivot: null, anims: { idle: { frames: [0], fps: 20 } } }] });
const files2 = buildFiles(plain, '', []), meta2 = JSON.parse(new TextDecoder().decode(files2.get('assets/SPR_heroe.meta.json')));
assert.deepEqual(meta2.anchor, [3, 6]);
assert.deepEqual(meta2.frame_ms, [50, 100, 100, 100]);
assert.doesNotMatch(new TextDecoder().decode(files2.get('data.lua')), /pivot/);

// a sheet 3 columns by 2 rows of 4 x 5 cells: six frames, each its own cell, row after row
const tw = 12, th = 5, rows = 2, sheet = new Uint8ClampedArray(tw * th * rows * 4);
for (let y = 0; y < th * rows; y++)
  for (let x = 0; x < tw; x++) {
    const i = (y * tw + x) * 4, cell = Math.floor(y / th) * 3 + Math.floor(x / 4);
    sheet[i] = cell * 40, sheet[i + 3] = (x % 4 === 0 && y % th === 0) ? 0 : 255; // each cell's corner see-through
  }
const frames = cutFrames(sheet, tw, 3, rows, 4, th, r => r);
assert.equal(frames.length, 6);
for (let k = 0; k < 6; k++) {
  assert.equal(frames[k].length, 4 * th);
  assert.equal(frames[k][0], -1);
  assert.ok(frames[k].slice(1).every(v => v === k * 40), `frame ${k} is cell ${k}`);
}
// a sheet's grid from its size: a row of squares, rows of squares, and a square picture left whole
assert.deepEqual(gridOf(128, 32), [4, 1]);
assert.deepEqual(gridOf(96, 64), [3, 2]);
assert.deepEqual(gridOf(64, 64), [1, 1]);
assert.deepEqual(gridOf(64, 96), [1, 1]);
assert.deepEqual(gridOf(32 * 70, 32), [1, 1]); // more than 64 frames: not a sheet it can take whole

console.log('anims: old animations, pivot, speeds, loops and sheets in a grid');
