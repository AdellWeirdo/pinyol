// A .zip of files, stored (not compressed: a game made here is small, and every unzip reads it), in one folder.
const CRC = new Uint32Array(256).map((_, n) => {
  let c = n;
  for (let k = 0; k < 8; k++) c = c & 1 ? 0xEDB88320 ^ (c >>> 1) : c >>> 1;
  return c >>> 0;
});

function crc32(b) {
  let c = 0xFFFFFFFF;
  for (let i = 0; i < b.length; i++) c = CRC[(c ^ b[i]) & 255] ^ (c >>> 8);
  return (c ^ 0xFFFFFFFF) >>> 0;
}

// files: Map path -> Uint8Array; folder: the top folder in the zip (the game's id) -> Uint8Array
export function zip(files, folder) {
  const enc = new TextEncoder(), local = [], central = [];
  let offset = 0;
  for (const [path, data] of files) {
    const name = enc.encode(folder + '/' + path), crc = crc32(data);
    const head = new DataView(new ArrayBuffer(30));
    head.setUint32(0, 0x04034b50, true), head.setUint16(4, 20, true), head.setUint32(14, crc, true);
    head.setUint32(18, data.length, true), head.setUint32(22, data.length, true), head.setUint16(26, name.length, true);
    local.push(new Uint8Array(head.buffer), name, data);
    const dir = new DataView(new ArrayBuffer(46));
    dir.setUint32(0, 0x02014b50, true), dir.setUint16(4, 20, true), dir.setUint16(6, 20, true);
    dir.setUint32(16, crc, true), dir.setUint32(20, data.length, true), dir.setUint32(24, data.length, true);
    dir.setUint16(28, name.length, true), dir.setUint32(42, offset, true);
    central.push(new Uint8Array(dir.buffer), name);
    offset += 30 + name.length + data.length;
  }
  const size = central.reduce((n, b) => n + b.length, 0);
  const end = new DataView(new ArrayBuffer(22));
  end.setUint32(0, 0x06054b50, true), end.setUint16(8, files.size, true), end.setUint16(10, files.size, true);
  end.setUint32(12, size, true), end.setUint32(16, offset, true);
  const parts = [...local, ...central, new Uint8Array(end.buffer)];
  const out = new Uint8Array(parts.reduce((n, b) => n + b.length, 0));
  let at = 0;
  for (const b of parts) out.set(b, at), at += b.length;
  return out;
}
