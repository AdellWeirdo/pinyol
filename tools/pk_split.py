#!/usr/bin/env python3
"""Splits packed pictures (.pk, tools/png2asset.py --packed) into pieces of a few frames each:
    python3 tools/pk_split.py games/mygame/assets/SPR_HERO.pk [more.pk ...] [--frames 10] [--remove]
SPR_HERO.pk of 50 frames becomes SPR_HERO_C0.pk .. SPR_HERO_C4.pk (frames 0-9, 10-19, ...), each with its own .meta.json;
the game draws frame f from piece f // 10 as its frame f % 10 (examples: IL·LUSTRES's gfx.fighter).

Why: the console's PSRAM is one heap shared with Lua's memory and every picture, and a picture needs ONE block. After a
fight or two a 600 KB sheet finds none (the pieces of free memory are 300-700 KB) and the fighter is invisible, even with
3 MB free; pieces of 100-200 KB find room, and only the pieces in use stay in memory (docs/measurements.md, 2026-10-22).
The palette is the whole sheet's, so palette variants (a `pal` picture) work on every piece. Needs nothing but Python.
"""
from __future__ import annotations

import argparse
import json
import struct
import sys
from pathlib import Path


def parse(pk: bytes) -> tuple[int, int, int, int, int, bytes, tuple[int, ...]]:
    """-> bpp, colours, w, h, frames, the palette's bytes, where each column starts (frames x w)."""
    if pk[:4] != b"NP2K" or pk[4] != 1 or pk[5] not in (4, 8):
        raise ValueError("not a packed picture (NP2K, version 1, 4 or 8 bits)")
    bpp = pk[5]
    colours, w, h, frames, _ = struct.unpack_from("<HHHHH", pk, 6)
    palette = pk[16:16 + 2 * colours]
    table = (16 + 2 * colours + 3) & ~3
    offsets = struct.unpack_from(f"<{w * frames}I", pk, table)
    return bpp, colours, w, h, frames, palette, offsets


def column_length(pk: bytes, at: int, bpp: int) -> int:
    runs = struct.unpack_from("<H", pk, at)[0]
    p = at + 2
    for _ in range(runs):
        _, n = struct.unpack_from("<HH", pk, p)
        p += 4 + (n if bpp == 8 else (n + 1) // 2)
    return p - at


def split(pk: bytes, step: int) -> list[tuple[int, int, bytes]]:
    """-> [(first frame, end frame, a .pk of those frames)]"""
    bpp, colours, w, h, frames, palette, offsets = parse(pk)
    pieces = []
    for f0 in range(0, frames, step):
        f1 = min(frames, f0 + step)
        head = b"NP2K" + bytes([1, bpp]) + struct.pack("<HHHHH", colours, w, h, f1 - f0, 0) + palette
        head += bytes((-len(head)) % 4)
        first = len(head) + 4 * w * (f1 - f0)
        table, data = [], bytearray()
        for f in range(f0, f1):
            for u in range(w):
                at = offsets[f * w + u]
                n = column_length(pk, at, bpp)
                table.append(first + len(data))
                data += pk[at:at + n]
        pieces.append((f0, f1, head + struct.pack(f"<{len(table)}I", *table) + bytes(data)))
    return pieces


def same_frames(pk: bytes, f0: int, piece: bytes) -> bool:
    """Every column of the piece is the original's (the check the tool runs on what it writes)."""
    bpp, _, w, _, _, _, offsets = parse(pk)
    pb, _, pw, _, pf, _, poffsets = parse(piece)
    if (pb, pw) != (bpp, w):
        return False
    for f in range(pf):
        for u in range(w):
            a, b = offsets[(f0 + f) * w + u], poffsets[f * w + u]
            n = column_length(pk, a, bpp)
            if n != column_length(piece, b, bpp) or pk[a:a + n] != piece[b:b + n]:
                return False
    return True


def split_file(path: Path, step: int, remove: bool) -> list[Path]:
    pk = path.read_bytes()
    meta_path = path.with_suffix(".meta.json")
    meta = json.loads(meta_path.read_text())
    aid = meta["asset"]
    written = []
    for k, (f0, f1, piece) in enumerate(split(pk, step)):
        if not same_frames(pk, f0, piece):
            raise SystemExit(f"{path}: piece {k} is not the original's frames (a bug in pk_split)")
        m = dict(meta)
        m["asset"] = f"{aid}_C{k}"
        m["frames"] = f1 - f0
        if isinstance(meta.get("frame_ms"), list):
            m["frame_ms"] = meta["frame_ms"][f0:f1]
        m["order"] = list(range(f1 - f0))
        m["memory_bytes"] = {"total": len(piece), "as_rgb565": meta["w"] * meta["h"] * (f1 - f0) * 2}
        out = path.with_name(f"{aid}_C{k}.pk")
        out.write_bytes(piece)
        out.with_suffix(".meta.json").write_text(json.dumps(m, indent=2) + "\n")
        written.append(out)
    if remove:
        path.unlink()
        meta_path.unlink()
    return written


def main() -> None:
    ap = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    ap.add_argument("pk", nargs="+", type=Path, help="the .pk files (their .meta.json beside them)")
    ap.add_argument("--frames", type=int, default=10, help="frames to a piece (10)")
    ap.add_argument("--remove", action="store_true", help="delete the whole picture after splitting it")
    a = ap.parse_args()
    for path in a.pk:
        pieces = split_file(path, max(1, a.frames), a.remove)
        sizes = ", ".join(f"{p.stat().st_size // 1024} KB" for p in pieces)
        print(f"{path.name}: {len(pieces)} pieces ({sizes})")


if __name__ == "__main__":
    sys.exit(main())
