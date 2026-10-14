// Clips for pinyol's video() (video/<id>.npv), made in the browser from a video's frames, as tools/clip2npv.py makes
// them (the format: its top): one palette of up to 256 colours for the whole clip, from a median cut of its colours;
// each frame as runs of what changed since the one before, a whole frame every `key` frames. And read back, to show.

const KEY = 0xF81F; // a canvas's see-through colour: never one of a clip's

const to565 = (r, g, b) => (r >> 3) << 11 | (g >> 2) << 5 | b >> 3;
const of565 = c => [(c >> 11) << 3 | c >> 13, (c >> 5 & 63) << 2 | (c >> 9 & 3), (c & 31) << 3 | (c >> 2 & 7)];

// Up to n colours for these frames (RGBA bytes each): the boxes of a median cut over their colours (as RGB565, a
// pixel in every few counted), each box's mean. -> [[r, g, b], ...]
export function palette(frames, n = 256) {
  const count = new Uint32Array(65536);
  for (const f of frames) for (let i = 0; i < f.length; i += 4 * 3) count[to565(f[i], f[i + 1], f[i + 2])]++;
  const colours = [];
  for (let c = 0; c < 65536; c++) if (count[c]) colours.push(c);
  if (!colours.length) colours.push(0);
  let boxes = [colours];
  const chan = (c, k) => of565(c)[k];
  while (boxes.length < n) {
    let bi = -1, best = 0, axis = 0; // the box with the widest channel that can still be cut
    boxes.forEach((b, i) => {
      if (b.length < 2) return;
      for (let k = 0; k < 3; k++) {
        let lo = 255, hi = 0;
        for (const c of b) { const v = chan(c, k); lo = Math.min(lo, v); hi = Math.max(hi, v); }
        if (hi - lo > best) best = hi - lo, bi = i, axis = k;
      }
    });
    if (bi < 0) break;
    const b = boxes[bi].sort((x, y) => chan(x, axis) - chan(y, axis));
    let total = 0, half = 0, cut = 1;
    for (const c of b) total += count[c];
    for (let i = 0; i < b.length - 1; i++) { half += count[b[i]]; if (half * 2 >= total) { cut = i + 1; break; } }
    boxes.splice(bi, 1, b.slice(0, cut), b.slice(cut));
  }
  return boxes.map(b => {
    let r = 0, g = 0, bl = 0, w = 0;
    for (const c of b) { const [x, y, z] = of565(c); r += x * count[c]; g += y * count[c]; bl += z * count[c]; w += count[c]; }
    return w ? [Math.round(r / w), Math.round(g / w), Math.round(bl / w)] : of565(b[0]);
  });
}

function nearest(pal) { // RGB565 -> its palette index, worked out once each
  const memo = new Int16Array(65536).fill(-1);
  return (r, g, b) => {
    const c = to565(r, g, b);
    if (memo[c] >= 0) return memo[c];
    let best = 0, bd = Infinity;
    pal.forEach(([pr, pg, pb], i) => { const d = (pr - r) ** 2 + (pg - g) ** 2 + (pb - b) ** 2; if (d < bd) bd = d, best = i; });
    return (memo[c] = best);
  };
}

function ops(cur, prev, n) { // a frame's ops: what differs from prev (null: all of it), as clip2npv.py writes them
  const out = [];
  let i = 0;
  while (i < n) {
    if (prev && cur[i] === prev[i]) {
      let j = i;
      while (j < n && j - i < 128 && cur[j] === prev[j]) j++;
      if (j === n) break; // the rest stays
      out.push(j - i - 1);
      i = j;
      continue;
    }
    let j = i;
    while (j < n && j - i < 64 && cur[j] === cur[i]) j++;
    if (j - i >= 3) { out.push(0xBF + j - i, cur[i]); i = j; continue; }
    j = i;
    while (j < n && j - i < 64) {
      if (j + 2 < n && cur[j] === cur[j + 1] && cur[j] === cur[j + 2]) break;
      if (prev && j + 1 < n && cur[j] === prev[j] && cur[j + 1] === prev[j + 1]) break;
      j++;
    }
    j = Math.max(j, i + 1);
    out.push(0x7F + j - i);
    for (let k = i; k < j; k++) out.push(cur[k]);
    i = j;
  }
  return out;
}

// frames: RGBA bytes of w x h each; fps: frames a second. -> the .npv file's bytes
export function encode(frames, w, h, fps, { colours = 256, key = Math.max(1, Math.round(fps * 2)) } = {}) {
  const pal = palette(frames, colours), near = nearest(pal), n = w * h, data = [], offsets = [];
  let prev = null;
  frames.forEach((f, k) => {
    const cur = new Uint8Array(n);
    for (let i = 0; i < n; i++) cur[i] = near(f[4 * i], f[4 * i + 1], f[4 * i + 2]);
    offsets.push(data.length);
    for (const b of ops(cur, k % key === 0 ? null : prev, n)) data.push(b);
    prev = cur;
  });
  offsets.push(data.length);
  const head = 20 + 2 * pal.length, start = head + 4 * offsets.length, out = new Uint8Array(start + data.length);
  const v = new DataView(out.buffer);
  out.set([78, 80, 86, 49]); // "NPV1"
  v.setUint16(4, w, true), v.setUint16(6, h, true), v.setUint16(8, Math.round(fps * 100), true);
  v.setUint16(10, pal.length, true), v.setUint32(12, frames.length, true), v.setUint32(16, key, true);
  pal.forEach(([r, g, b], i) => { const c = to565(r, g, b); v.setUint16(20 + 2 * i, c === KEY ? c ^ 1 : c, true); });
  offsets.forEach((o, i) => v.setUint32(head + 4 * i, start + o, true));
  out.set(data, start);
  return out;
}

// The clip's numbers and its frames as RGBA, one after another (to show it in the editor). null if it is not a clip.
export function decode(bytes) {
  if (bytes.length < 20 || String.fromCharCode(...bytes.slice(0, 4)) !== 'NPV1') return null;
  const v = new DataView(bytes.buffer, bytes.byteOffset, bytes.byteLength);
  const w = v.getUint16(4, true), h = v.getUint16(6, true), fps = v.getUint16(8, true) / 100, ncol = v.getUint16(10, true);
  const count = v.getUint32(12, true), head = 20 + 2 * ncol;
  if (!w || !h || !ncol || !count || bytes.length < head + 4 * (count + 1)) return null;
  const pal = Array.from({ length: ncol }, (_, i) => of565(v.getUint16(20 + 2 * i, true)));
  const px = new Uint8ClampedArray(w * h * 4).fill(255), frames = [];
  for (let k = 0; k < count; k++) {
    let p = v.getUint32(head + 4 * k, true), i = 0;
    const end = Math.min(bytes.length, v.getUint32(head + 4 * (k + 1), true));
    const put = c => { const [r, g, b] = pal[c < ncol ? c : 0]; px[4 * i] = r, px[4 * i + 1] = g, px[4 * i + 2] = b; i++; };
    while (p < end && i < w * h) {
      const op = bytes[p++];
      if (op < 0x80) i += op + 1;
      else if (op < 0xC0) for (let j = 0; j < op - 0x7F && p < end && i < w * h; j++) put(bytes[p++]);
      else if (p < end) { const c = bytes[p++]; for (let j = 0; j < op - 0xBF && i < w * h; j++) put(c); }
    }
    frames.push(px.slice());
  }
  return { w, h, fps, frames };
}
