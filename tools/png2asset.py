# /// script
# requires-python = ">=3.10"
# dependencies = ["pillow>=10"]
# ///
"""Convert a PNG into an np2d runtime asset: <ID>.rgb565 (little endian) + <ID>.mask (1 bit, MSB first) + <ID>.meta.json.

    uv run tools/png2asset.py hero_walk.png games/mygame/assets PJ_WALK --frames 16 --ms 125 --anchor 12,29
    uv run tools/png2asset.py room.png games/mygame/assets BG_Z01 --type background

--frames N cuts the PNG into N equal frames, left to right (a horizontal strip). Character sheets go in
direction order N, E, S, W. Pixels with alpha < 128 are transparent; an opaque image writes no .mask.
"""
from __future__ import annotations

import argparse
import json
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


def main() -> None:
    p = argparse.ArgumentParser(description=__doc__.split("\n\n")[0])
    p.add_argument("png", type=Path)
    p.add_argument("assets", type=Path, help="the game's assets/ folder")
    p.add_argument("id", help="asset ID, e.g. BG_Z01, PJ_WALK, NPC_AMIGA, IC_LLAVE")
    p.add_argument("--frames", type=int, default=1, help="frames in a horizontal strip")
    p.add_argument("--ms", type=int, default=0, help="milliseconds per frame")
    p.add_argument("--anchor", help="x,y inside a frame (characters: their feet); default bottom centre")
    p.add_argument("--type", default="sprite", choices=("sprite", "background", "ui"))
    a = p.parse_args()
    img = Image.open(a.png).convert("RGBA")
    if img.width % a.frames:
        p.error(f"{img.width} px wide does not split into {a.frames} equal frames")
    fw = img.width // a.frames
    frames = [img.crop((i * fw, 0, (i + 1) * fw, img.height)) for i in range(a.frames)]
    anchor = tuple(int(v) for v in a.anchor.split(",")) if a.anchor else None
    export(a.assets, a.id, frames, a.ms, anchor, a.type)
    print(f"{a.assets / a.id}: {a.frames} frame(s) of {fw}x{img.height}")


if __name__ == "__main__":
    main()
