# /// script
# requires-python = ">=3.10"
# dependencies = ["pillow>=10"]
# ///
"""Cuts a pre-rendered background into the pieces that must pass in front of the characters (a bar's counter, a stool,
a pillar, a hanging lamp), each with the depth it sits at, as the PlayStation's Resident Evil and Final Fantasy VII did:
the character walks in a flat picture and the foreground is laid over him, piece by piece, where it hides him.

    uv run tools/depthcut.py BG.png MAP.png GAME ID --z FF0000=280,00FF00=300,0000FF=262
    uv run tools/depthcut.py BG.png MAP.png GAME ID --z-from-bottom        # each piece's depth: its lowest row

BG.png is the whole background. MAP.png is the same size, painted in flat colours: each colour is one piece, drawn where
that piece is (transparent or black: no piece). --z gives each colour's depth, the y of the line on the floor where
the piece stands: a character whose feet are above that line (a smaller y) is behind it, below it is in front.
--z-from-bottom takes it from the piece itself (the lowest row it covers), which suits a counter or a stool standing on the
floor. Written into the game:
  assets/<ID>.pk                  the whole background (packed, as png2asset --packed)
  assets/<ID>_<n>.pk              the pieces, each cut to its box and see-through outside its colour
  <id>_depth.lua                  `return {{pic = "BG_BAR_1", x, y, z}, ...}`: rooms' `occluders`, drawn among the things by z
"""
from __future__ import annotations

import argparse
import re
import sys
from pathlib import Path

from PIL import Image

sys.path.insert(0, str(Path(__file__).resolve().parent))
from png2asset import export_packed  # noqa: E402


def parse_z(spec: str) -> dict[tuple[int, int, int], int]:
    out = {}
    for item in spec.split(","):
        c, _, z = item.partition("=")
        c = c.strip().lstrip("#")
        if len(c) != 6 or not z:
            sys.exit(f"--z {item!r}: use RRGGBB=y")
        out[(int(c[0:2], 16), int(c[2:4], 16), int(c[4:6], 16))] = int(z)
    return out


def cut(bg: Image.Image, mp: Image.Image, zs: dict | None, colours: int | None):
    """-> [(box, piece image, z)] for each colour of the map, in the order of their depth."""
    bg, mp = bg.convert("RGBA"), mp.convert("RGBA")
    if bg.size != mp.size:
        sys.exit(f"the map is {mp.size} and the background {bg.size}: they must be the same size")
    w, h = bg.size
    by_colour: dict[tuple[int, int, int], list[int]] = {}
    mdata = mp.tobytes()
    for i in range(0, len(mdata), 4):
        r, g, b, a = mdata[i:i + 4]
        if a >= 128 and (r, g, b) != (0, 0, 0):
            by_colour.setdefault((r, g, b), []).append(i // 4)
    pieces = []
    for colour, pixels in by_colour.items():
        xs = [p % w for p in pixels]
        ys = [p // w for p in pixels]
        box = (min(xs), min(ys), max(xs) + 1, max(ys) + 1)
        piece = Image.new("RGBA", (box[2] - box[0], box[3] - box[1]), (0, 0, 0, 0))
        src = bg.load()
        dst = piece.load()
        for p in pixels:
            x, y = p % w, p // w
            dst[x - box[0], y - box[1]] = src[x, y]
        if zs is not None:
            if colour not in zs:
                sys.exit(f"the map has colour #{colour[0]:02X}{colour[1]:02X}{colour[2]:02X} but --z gives it no depth")
            z = zs[colour]
        else:
            z = box[3]  # the lowest row it covers
        pieces.append((box, piece, z))
    pieces.sort(key=lambda p: (p[2], p[0][0]))
    return pieces


def main() -> None:
    ap = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    ap.add_argument("bg", type=Path)
    ap.add_argument("map", type=Path)
    ap.add_argument("game", type=Path)
    ap.add_argument("id", help="the background's asset id, e.g. BG_BAR (letters, digits and _)")
    ap.add_argument("--z", help="RRGGBB=y,RRGGBB=y: each piece's depth")
    ap.add_argument("--z-from-bottom", action="store_true", help="each piece's depth is its lowest row")
    ap.add_argument("--colours", type=int, help="at most this many colours in each picture (16: 4 bits a pixel)")
    a = ap.parse_args()
    if not re.fullmatch(r"[A-Za-z0-9_]+", a.id):
        sys.exit("id: letters, digits and _ only")
    if bool(a.z) == a.z_from_bottom:
        sys.exit("give --z or --z-from-bottom")
    pieces = cut(Image.open(a.bg), Image.open(a.map), parse_z(a.z) if a.z else None, a.colours)
    assets = a.game / "assets"
    export_packed(assets, a.id, [Image.open(a.bg).convert("RGBA")], a.colours, 0, (0, 0), "background")
    lines = ["-- made by tools/depthcut.py: the pieces of %s that pass in front of the characters (rooms' occluders)" % a.id,
             "return {"]
    for n, (box, piece, z) in enumerate(pieces, 1):
        pid = f"{a.id}_{n}"
        export_packed(assets, pid, [piece], a.colours, 0, (0, 0), "sprite")
        lines.append(f'  {{pic = "{pid}", x = {box[0]}, y = {box[1]}, z = {z}}},')
    lines.append("}")
    out = a.game / f"{a.id.lower()}_depth.lua"
    out.write_text("\n".join(lines) + "\n")
    print(f"{out}: {len(pieces)} piece(s) from {a.map.name}, into {assets}")


if __name__ == "__main__":
    main()
