// js/build.js's packed pictures read back as the engine reads them (docs/game-format.md, "Packed pictures"): random
// drawings of few and many colours, with see-through holes, give back their pixels; a photo of more than 256
// colours and a backdrop stay RGB565.
//   node editor/test/packed_test.mjs
import assert from 'node:assert/strict';
import { packed, cropOf } from '../js/build.js';

let seed = 7;
const rnd = n => (seed = (seed * 1103515245 + 12345) & 0x7fffffff) % n;

function unpack(bytes) { // -> frames of RGB565 or -1, w, h
  const v = new DataView(bytes.buffer), u16 = i => v.getUint16(i, true);
  assert.equal(String.fromCharCode(...bytes.subarray(0, 4)), 'NP2K');
  const bpp = bytes[5], ncol = u16(6), w = u16(8), h = u16(10), nf = u16(12);
  const pal = Array.from({ length: ncol }, (_, i) => u16(16 + 2 * i)), table = (16 + 2 * ncol + 3) & ~3;
  const frames = [];
  for (let f = 0; f < nf; f++) {
    const px = new Array(w * h).fill(-1);
    for (let x = 0; x < w; x++) {
      let p = v.getUint32(table + 4 * (f * w + x), true);
      const runs = u16(p);
      p += 2;
      for (let r = 0; r < runs; r++) {
        const y = u16(p), n = u16(p + 2);
        for (let j = 0; j < n; j++) {
          const id = bpp === 8 ? bytes[p + 4 + j] : j & 1 ? bytes[p + 4 + (j >> 1)] & 15 : bytes[p + 4 + (j >> 1)] >> 4;
          assert.ok(id < ncol);
          px[(y + j) * w + x] = pal[id];
        }
        p += 4 + (bpp === 8 ? n : (n + 1) >> 1);
      }
    }
    frames.push(px);
  }
  return { frames, w, h, bpp };
}

for (const [colours, bpp] of [[1, 4], [16, 4], [17, 8], [256, 8]])
  for (const use of ['object', 'tile']) {
    const w = 1 + rnd(40), h = 1 + rnd(40), cols = Array.from({ length: colours }, (_, i) => i * 251 & 0xffff);
    const d = { use, w, h, frames: Array.from({ length: 1 + rnd(4) }, () =>
      Array.from({ length: w * h }, () => rnd(4) ? cols[rnd(colours)] : -1)) };
    d.frames[0][0] = cols[colours - 1]; // every colour drawn somewhere: the palette is full
    for (let i = 0; i < colours; i++) d.frames[0][i % (w * h)] = cols[i];
    const pk = packed(d), c = cropOf(d), got = unpack(pk.bytes);
    assert.equal(got.bpp, bpp);
    assert.deepEqual([got.w, got.h], [c.w, c.h]);
    d.frames.forEach((f, k) => {
      for (let y = 0; y < c.h; y++)
        for (let x = 0; x < c.w; x++) assert.equal(got.frames[k][y * c.w + x], f[(y + c.y) * w + x + c.x], `${colours} colours, ${use}`);
    });
  }
const photo = { use: 'object', w: 20, h: 20, frames: [Array.from({ length: 400 }, (_, i) => i)] };
assert.equal(packed(photo), null);
assert.equal(packed({ use: 'backdrop', w: 2, h: 2, frames: [[1, 2, 3, 4]] }), null);
console.log('packed: drawings read back as drawn');
