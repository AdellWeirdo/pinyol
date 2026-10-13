# /// script
# requires-python = ">=3.10"
# dependencies = ["pillow>=10"]
# ///
"""Convert a PNG into an np2d runtime asset.

Direct colour (np2d@1 games, and sprites or bitmap layers of np2d@2 ones): <ID>.rgb565 (little endian) + <ID>.mask
(1 bit, MSB first) + <ID>.meta.json.

    uv run tools/png2asset.py hero_walk.png games/mygame/assets PJ_WALK --frames 16 --ms 125 --anchor 12,29
    uv run tools/png2asset.py room.png games/mygame/assets BG_Z01 --type background

Indexed, for the PPU of np2d@2 games (docs/lua.md): one byte per pixel into a palette of up to 255 colours plus
transparent index 0. --palette PAL shares (and grows) assets/PAL.pal across several images.

    uv run tools/png2asset.py level.png games/mygame/assets LEVEL --tiles --palette WORLD    # .tiles .map .pal
    uv run tools/png2asset.py ship.png games/mygame/assets SHIP --indexed --frames 4 --palette OBJ  # .idx .pal

--tiles cuts the image into 8x8 tiles, keeps one copy of each (a flipped copy counts as the same tile) and writes
the map that rebuilds the image. --frames N cuts a horizontal strip into N frames. Pixels with alpha < 128 are
transparent.
"""
from __future__ import annotations

import argparse
import json
import struct
import re
from pathlib import Path

from PIL import Image


def pack565(r: int, g: int, b: int) -> int:
    return ((r >> 3) << 11) | ((g >> 2) << 5) | (b >> 3)


def mask_1bpp(img: Image.Image) -> bytes:
    w, h = img.size
    stride = (w + 7) // 8
    alpha = img.getchannel("A").tobytes()
    out = bytearray(stride * h)
    for y in range(h):
        for x in range(w):
            if alpha[y * w + x] >= 128:
                out[y * stride + x // 8] |= 0x80 >> (x % 8)
    return bytes(out)


def export(assets: Path, aid: str, frames: list[Image.Image], frame_ms: int = 0, anchor: tuple | None = None,
           kind: str = "sprite") -> None:
    if not re.fullmatch(r"[A-Za-z0-9_]+", aid):
        raise ValueError(f"asset ID {aid!r}: use letters, digits and _ only (it names files in {assets})")
    frames = [f.convert("RGBA") for f in frames]
    w, h = frames[0].size
    if any(f.size != (w, h) for f in frames):
        raise ValueError(f"{aid}: every frame must be {w}x{h}")
    pixels = bytearray()
    for f in frames:
        raw = f.tobytes()
        for i in range(0, len(raw), 4):
            pixels += pack565(raw[i], raw[i + 1], raw[i + 2]).to_bytes(2, "little")
    has_alpha = any(a < 128 for f in frames for a in f.getchannel("A").tobytes())
    mask = b"".join(mask_1bpp(f) for f in frames) if has_alpha else b""
    assets.mkdir(parents=True, exist_ok=True)
    (assets / f"{aid}.rgb565").write_bytes(pixels)
    mask_path = assets / f"{aid}.mask"
    if has_alpha:
        mask_path.write_bytes(mask)
    elif mask_path.exists():
        mask_path.unlink()
    meta = {"asset": aid, "type": kind, "w": w, "h": h, "frames": len(frames),
            "frame_ms": [frame_ms] * len(frames), "order": list(range(len(frames))),
            "anchor": list(anchor) if anchor else [w // 2, h - 1], "tile": None,
            "rgb565": {"endian": "little", "order": "rgb", "alpha": "mask1" if has_alpha else "none"},
            "memory_bytes": {"pixels": len(pixels), "mask": len(mask), "total": len(pixels) + len(mask)}}
    (assets / f"{aid}.meta.json").write_text(json.dumps(meta, indent=2) + "\n")


def rgb565(r: int, g: int, b: int) -> int:
    return pack565(r, g, b)


# ------------------------------------------------------------------ packed pictures (the format "packed", src/gfx.c)
# For big pictures and many frames at the screen's full resolution (as a Neo Geo game draws them): a palette of up to
# 16 colours (4 bits a pixel) or 256 (8 bits), and each frame kept column by column, as the console's turned screen
# draws it, only the opaque runs of each column stored. Little-endian:
#   "NP2K", u8 version 1, u8 bpp (4 or 8), u16 colours, u16 w, u16 h, u16 frames, u16 0
#   colours x u16 RGB565, padded to 4 bytes
#   frames x w x u32: where each column starts, from the file's start
#   a column: u16 runs, then each run: u16 y, u16 length, its indices (8 bits each; 4 bits: high nibble first, a
#   run's last odd nibble padded)
def pack_frames(frames: list[Image.Image], colours: int | None) -> tuple[bytes, int, int]:
    """-> (the .pk file, bits per pixel, colours used). colours: at most this many (quantized if more are drawn)."""
    w, h = frames[0].size
    rgba = [f.convert("RGBA") for f in frames]
    seen = {}
    for f in rgba:
        raw = f.tobytes()
        for i in range(0, len(raw), 4):
            if raw[i + 3] >= 128:
                seen.setdefault(pack565(raw[i], raw[i + 1], raw[i + 2]), None)
    limit = min(colours or 256, 256)
    if len(seen) > limit:  # more than fit: the frames as one strip, quantized together (one palette for all)
        strip = Image.new("RGBA", (w * len(rgba), h))
        for k, f in enumerate(rgba):
            strip.paste(f, (k * w, 0))
        q = strip.convert("RGB").quantize(colors=limit, method=Image.Quantize.MEDIANCUT, dither=Image.Dither.NONE)
        qrgb = q.convert("RGB")
        alpha = strip.getchannel("A")
        qrgb.putalpha(alpha)
        rgba = [qrgb.crop((k * w, 0, (k + 1) * w, h)) for k in range(len(rgba))]
        seen = {}
        for f in rgba:
            raw = f.tobytes()
            for i in range(0, len(raw), 4):
                if raw[i + 3] >= 128:
                    seen.setdefault(pack565(raw[i], raw[i + 1], raw[i + 2]), None)
    pal = list(seen) or [0]
    index = {c: i for i, c in enumerate(pal)}
    bpp = 4 if len(pal) <= 16 else 8
    head = b"NP2K" + bytes([1, bpp]) + struct.pack("<HHHHH", len(pal), w, h, len(rgba), 0)
    head += b"".join(struct.pack("<H", c) for c in pal)
    head += b"\0" * (-len(head) % 4)
    table_at = len(head)
    data_at = table_at + 4 * w * len(rgba)
    table, data = [], bytearray()
    for f in rgba:
        raw = f.tobytes()
        for x in range(w):
            table.append(data_at + len(data))
            runs, y = [], 0
            while y < h:
                if raw[(y * w + x) * 4 + 3] < 128:
                    y += 1
                    continue
                y0 = y
                while y < h and raw[(y * w + x) * 4 + 3] >= 128:
                    y += 1
                runs.append((y0, y - y0))
            data += struct.pack("<H", len(runs))
            for y0, n in runs:
                data += struct.pack("<HH", y0, n)
                ids = [index[pack565(*raw[((y0 + j) * w + x) * 4:((y0 + j) * w + x) * 4 + 3])] for j in range(n)]
                if bpp == 8:
                    data += bytes(ids)
                else:
                    ids += [0] * (n & 1)
                    data += bytes(ids[j] << 4 | ids[j + 1] for j in range(0, len(ids), 2))
    return head + struct.pack(f"<{len(table)}I", *table) + bytes(data), bpp, len(pal)


def export_packed(assets: Path, aid: str, frames: list[Image.Image], colours: int | None, frame_ms: int = 0,
                  anchor: tuple | None = None, kind: str = "sprite") -> None:
    w, h = frames[0].size
    blob, bpp, used = pack_frames(frames, colours)
    assets.mkdir(parents=True, exist_ok=True)
    for old in (".rgb565", ".mask"):  # the same picture, packed now
        if (assets / f"{aid}{old}").exists():
            (assets / f"{aid}{old}").unlink()
    (assets / f"{aid}.pk").write_bytes(blob)
    meta = {"asset": aid, "type": kind, "format": "packed", "bpp": bpp, "colours": used, "w": w, "h": h,
            "frames": len(frames), "frame_ms": [frame_ms] * len(frames), "order": list(range(len(frames))),
            "anchor": list(anchor) if anchor else [w // 2, h - 1], "tile": None,
            "memory_bytes": {"total": len(blob), "as_rgb565": w * h * len(frames) * 2}}
    (assets / f"{aid}.meta.json").write_text(json.dumps(meta, indent=2) + "\n")


def load_palette(path: Path) -> list[int]:
    if not path.exists():
        return [0]  # index 0: transparent
    raw = path.read_bytes()
    return [raw[i] | raw[i + 1] << 8 for i in range(0, len(raw), 2)]


def indices(img: Image.Image, pal: list[int]) -> bytes:
    """One palette index per pixel, adding colours to pal as they appear (index 0 is transparent)."""
    img = img.convert("RGBA")
    out = bytearray()
    where = {c: i for i, c in enumerate(pal) if i}
    raw = img.tobytes()
    for k in range(0, len(raw), 4):
        r, g, b, a = raw[k], raw[k + 1], raw[k + 2], raw[k + 3]
        if a < 128:
            out.append(0)
            continue
        c = rgb565(r, g, b)
        if c not in where:
            if len(pal) >= 256:
                raise SystemExit("more than 255 colours: reduce the image's colours or split the palette")
            where[c] = len(pal)
            pal.append(c)
        out.append(where[c])
    return bytes(out)


def save_palette(path: Path, pal: list[int]) -> None:
    path.write_bytes(b"".join(c.to_bytes(2, "little") for c in pal))


def tiles_and_map(px: bytes, w: int, h: int, flips: bool = True) -> tuple[list[bytes], list[int]]:
    """8x8 tiles, each kept once (tile 0 is the empty one); map entries tile | 0x400 hflip | 0x800 vflip. Affine
    layers ignore flips, so for them (flips=False) a flipped copy is a tile of its own."""
    def tile(tx: int, ty: int) -> bytes:
        return b"".join(px[(ty * 8 + y) * w + tx * 8:(ty * 8 + y) * w + tx * 8 + 8] for y in range(8))

    def hflip(t: bytes) -> bytes:
        return b"".join(t[y * 8:y * 8 + 8][::-1] for y in range(8))

    def vflip(t: bytes) -> bytes:
        return b"".join(t[y * 8:y * 8 + 8] for y in range(7, -1, -1))

    tiles, seen, entries = [bytes(64)], {bytes(64): 0}, []
    for ty in range(h // 8):
        for tx in range(w // 8):
            t = tile(tx, ty)
            variants = ((0, t), (0x400, hflip(t)), (0x800, vflip(t)), (0xC00, vflip(hflip(t)))) if flips else ((0, t),)
            for flags, v in variants:
                if v in seen:
                    entries.append(seen[v] | flags)
                    break
            else:
                if len(tiles) >= 1024:
                    raise SystemExit("more than 1024 different tiles: a map holds tile numbers up to 1023")
                seen[t] = len(tiles)
                entries.append(len(tiles))
                tiles.append(t)
    return tiles, entries


def main() -> None:
    p = argparse.ArgumentParser(description=__doc__.split("\n\n")[0])
    p.add_argument("png", type=Path)
    p.add_argument("assets", type=Path, help="the game's assets/ folder")
    p.add_argument("id", help="asset ID, e.g. BG_Z01, PJ_WALK, NPC_AMIGA, IC_LLAVE")
    p.add_argument("--frames", type=int, default=1, help="frames in a horizontal strip")
    p.add_argument("--ms", type=int, default=0, help="milliseconds per frame")
    p.add_argument("--anchor", help="x,y inside a frame (characters: their feet); default bottom centre")
    p.add_argument("--type", default="sprite", choices=("sprite", "background", "ui"))
    p.add_argument("--tiles", action="store_true", help="indexed 8x8 tiles + a map of the image (a PPU background)")
    p.add_argument("--indexed", action="store_true", help="indexed sprite frames (a PPU sprite sheet)")
    p.add_argument("--affine", action="store_true", help="with --tiles: for an affine layer (no flips, 256 tiles)")
    p.add_argument("--palette", help="share assets/PALETTE.pal (it grows); default: the asset's own <ID>.pal")
    p.add_argument("--packed", action="store_true",
                   help="packed: a palette and only the opaque runs, column by column; up to 7x smaller and faster to "
                        "draw at the screen's full resolution (big characters, many frames, wide backgrounds)")
    p.add_argument("--colours", type=int, help="with --packed: at most this many colours (16: 4 bits a pixel, as a "
                                              "Neo Geo sprite); more are drawn: quantized")
    a = p.parse_args()
    if not re.fullmatch(r"[A-Za-z0-9_]+", a.id) or (a.palette and not re.fullmatch(r"[A-Za-z0-9_]+", a.palette)):
        p.error("IDs: letters, digits and _ only")
    if a.tiles or a.indexed:
        a.assets.mkdir(parents=True, exist_ok=True)
        pal_path = a.assets / f"{a.palette or a.id}.pal"
        pal = load_palette(pal_path)
        img = Image.open(a.png).convert("RGBA")
        if a.tiles:
            if img.width % 8 or img.height % 8:
                p.error(f"{img.width}x{img.height}: --tiles needs a size in whole 8x8 tiles")
            tiles, entries = tiles_and_map(indices(img, pal), img.width, img.height, flips=not a.affine)
            if a.affine and len(tiles) > 256:
                raise SystemExit(f"{len(tiles)} different tiles: an affine layer holds 256 (simplify the image)")
            (a.assets / f"{a.id}.tiles").write_bytes(b"".join(tiles))
            (a.assets / f"{a.id}.map").write_bytes(b"".join(e.to_bytes(2, "little") for e in entries))
            meta = {"asset": a.id, "type": "tilemap", "tiles": len(tiles), "map_w": img.width // 8,
                    "map_h": img.height // 8, "palette": a.palette or a.id}
            print(f"{a.assets / a.id}: {len(tiles)} tiles, map {img.width // 8}x{img.height // 8}, {len(pal) - 1} colours")
        else:
            if img.width % a.frames:
                p.error(f"{img.width} px wide does not split into {a.frames} equal frames")
            fw = img.width // a.frames
            frames = [img.crop((i * fw, 0, (i + 1) * fw, img.height)) for i in range(a.frames)]
            (a.assets / f"{a.id}.idx").write_bytes(b"".join(indices(f, pal) for f in frames))
            meta = {"asset": a.id, "type": "sprite", "format": "idx8", "w": fw, "h": img.height, "frames": a.frames,
                    "frame_ms": [a.ms] * a.frames, "palette": a.palette or a.id}
            print(f"{a.assets / a.id}: {a.frames} indexed frame(s) of {fw}x{img.height}, {len(pal) - 1} colours")
        save_palette(pal_path, pal)
        (a.assets / f"{a.id}.meta.json").write_text(json.dumps(meta, indent=2) + "\n")
        return
    img = Image.open(a.png).convert("RGBA")
    if img.width % a.frames:
        p.error(f"{img.width} px wide does not split into {a.frames} equal frames")
    fw = img.width // a.frames
    frames = [img.crop((i * fw, 0, (i + 1) * fw, img.height)) for i in range(a.frames)]
    anchor = tuple(int(v) for v in a.anchor.split(",")) if a.anchor else None
    if a.packed:
        export_packed(a.assets, a.id, frames, a.colours, a.ms, anchor, a.type)
        meta = json.loads((a.assets / f"{a.id}.meta.json").read_text())
        print(f"{a.assets / a.id}: {a.frames} packed frame(s) of {fw}x{img.height}, {meta['colours']} colours, "
              f"{meta['bpp']} bits, {meta['memory_bytes']['total'] // 1024} KB (as RGB565: "
              f"{meta['memory_bytes']['as_rgb565'] // 1024} KB)")
        return
    export(a.assets, a.id, frames, a.ms, anchor, a.type)
    print(f"{a.assets / a.id}: {a.frames} frame(s) of {fw}x{img.height}")


if __name__ == "__main__":
    main()
