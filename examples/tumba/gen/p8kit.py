"""The kit for Tumba's art: pictures written as hex digits like a PICO-8 cart's sprite sheet, in PICO-8's sixteen colours.

A picture is rows of characters: `0`..`f` is PICO-8's colour 0..15 (0 black, 7 white, 8 red, 10 yellow, 12 blue...), `.` is see-through (sprites
only: a tile is always opaque). `ART.tile(name, rows)` is an 8x8 block of the map; `ART.sprite(sheet, name, rows)` a sprite of a sheet.
build() writes:
  assets/WORLD.pal, OBJ.pal   the sixteen colours at indices 1..16 (index 0 is see-through)
  assets/ROOM.tiles/.map      an atlas of every tile, 32 wide (the game reads each one's number with mget)
  assets/<SHEET>.idx          a strip of frames
  data/tilepos.lua            tile name -> {column, row} in the atlas
  data/frames.lua             sheet -> frame name -> number
  art/*.png                   contact sheets to look at
"""
from __future__ import annotations

import subprocess
import sys
from pathlib import Path

from PIL import Image

HERE = Path(__file__).resolve().parent.parent
ROOT = HERE.parents[1]
ART_DIR, ASSETS, DATA = HERE / "art", HERE / "assets", HERE / "data"
P8 = [(0, 0, 0), (29, 43, 83), (126, 37, 83), (0, 135, 81), (171, 82, 54), (95, 87, 79), (194, 195, 199), (255, 241, 232),
      (255, 0, 77), (255, 163, 0), (255, 236, 39), (0, 228, 54), (41, 173, 255), (131, 118, 156), (255, 119, 168), (255, 204, 170)]
ATLAS_W = 32
HEX = "0123456789abcdef"


def rows_of(text: str, w: int, h: int) -> list[str]:
    rows = [r.strip() for r in text.strip("\n").split("\n")]
    if len(rows) != h or any(len(r) != w for r in rows):
        bad = [(i, len(r)) for i, r in enumerate(rows) if len(r) != w]
        raise ValueError(f"picture needs {h} rows of {w}: has {len(rows)} rows, bad rows {bad}")
    bad = {c for r in rows for c in r} - set(HEX + ".")
    if bad:
        raise ValueError(f"picture has characters other than 0-9, a-f and .: {sorted(bad)}")
    return rows


class Registry:
    def __init__(self):
        self.tiles: dict[str, list[str]] = {}
        self.sheets: dict[str, dict] = {}

    def tile(self, name: str, rows) -> None:
        rows = rows_of(rows, 8, 8) if isinstance(rows, str) else rows
        if "." in "".join(rows):
            raise ValueError(f"tile {name} has see-through pixels: a tile is opaque")
        if name in self.tiles:
            raise ValueError(f"tile {name} twice")
        self.tiles[name] = rows

    def sheet(self, name: str, w: int = 8, h: int = 8) -> None:
        self.sheets[name] = {"w": w, "h": h, "frames": []}

    def sprite(self, sheet: str, name: str, rows) -> None:
        s = self.sheets[sheet]
        rows = rows_of(rows, s["w"], s["h"]) if isinstance(rows, str) else rows
        if any(n == name for n, _ in s["frames"]):
            raise ValueError(f"frame {sheet}.{name} twice")
        s["frames"].append((name, rows))


ART = Registry()


def lua_table(v, indent=0) -> str:
    pad = "  " * indent
    if isinstance(v, dict):
        items = [f'{pad}  {k if str(k).isidentifier() else "[" + repr(str(k)) + "]"} = {lua_table(x, indent + 1)}' for k, x in v.items()]
        return "{\n" + ",\n".join(items) + f"\n{pad}}}"
    if isinstance(v, (list, tuple)):
        return "{" + ", ".join(lua_table(x) for x in v) + "}"
    if isinstance(v, str):
        return '"' + v.replace('"', '\\"') + '"'
    return str(v)


def convert(png: Path, aid: str, *opts: str) -> None:
    subprocess.run([sys.executable, str(ROOT / "tools" / "png2asset.py"), str(png), str(ASSETS), aid, *opts], check=True)


def color(ch: str):
    return P8[HEX.index(ch)]


def contact(pics: list[list[str]], cols: int, scale: int, bg=(48, 48, 48)) -> Image.Image:
    h, w = len(pics[0]), len(pics[0][0])
    rows = (len(pics) + cols - 1) // cols
    img = Image.new("RGB", ((w + 1) * cols * scale, (h + 1) * rows * scale), bg)
    for i, p in enumerate(pics):
        ox, oy = (i % cols) * (w + 1), (i // cols) * (h + 1)
        for y, row in enumerate(p):
            for x, ch in enumerate(row):
                c = bg if ch == "." else color(ch)
                for dy in range(scale):
                    for dx in range(scale):
                        img.putpixel(((ox + x) * scale + dx, (oy + y) * scale + dy), c)
    return img


def build() -> None:
    for d in (ART_DIR, ASSETS, DATA):
        d.mkdir(exist_ok=True)
    key = lambda c: (c[0] >> 3) << 11 | (c[1] >> 2) << 5 | c[2] >> 3
    pal = b"".join(v.to_bytes(2, "little") for v in [0] + [key(c) for c in P8])
    (ASSETS / "WORLD.pal").write_bytes(pal)
    (ASSETS / "OBJ.pal").write_bytes(pal)
    names = list(ART.tiles)
    n_rows = max(18, (len(names) + ATLAS_W - 1) // ATLAS_W)  # the map is also the room's grid of cells
    atlas = Image.new("RGB", (ATLAS_W * 8, n_rows * 8), P8[0])
    pos = {}
    for i, n in enumerate(names):
        cx, cy = i % ATLAS_W, i // ATLAS_W
        pos[n] = [cx, cy]
        for y, row in enumerate(ART.tiles[n]):
            for x, ch in enumerate(row):
                atlas.putpixel((cx * 8 + x, cy * 8 + y), color(ch))
    atlas.save(ART_DIR / "room.png")
    convert(ART_DIR / "room.png", "ROOM", "--tiles", "--palette", "WORLD")
    frames = {}
    for sid, s in ART.sheets.items():
        fr = s["frames"]
        strip = Image.new("RGBA", (s["w"] * len(fr), s["h"]))
        for i, (_, rows) in enumerate(fr):
            for y, row in enumerate(rows):
                for x, ch in enumerate(row):
                    if ch != ".":
                        strip.putpixel((i * s["w"] + x, y), color(ch) + (255,))
        strip.save(ART_DIR / f"{sid.lower()}.png")
        convert(ART_DIR / f"{sid.lower()}.png", sid, "--indexed", "--frames", str(len(fr)), "--palette", "OBJ")
        frames[sid] = {"w": s["w"], "h": s["h"], "n": len(fr), **{name: i for i, (name, _) in enumerate(fr)}}
    (DATA / "tilepos.lua").write_text("-- made by gen/art.py: tile name -> {column, row} of the ROOM atlas\nreturn " + lua_table(pos) + "\n")
    (DATA / "frames.lua").write_text("-- made by gen/art.py: sprite sheets and their frame numbers\nreturn " + lua_table(frames) + "\n")
    contact([ART.tiles[n] for n in names], 16, 6).save(ART_DIR / "tiles_sheet.png")
    for sid, s in ART.sheets.items():
        contact([r for _, r in s["frames"]], 12, 6).save(ART_DIR / f"sheet_{sid.lower()}.png")
    print(f"{len(names)} tiles, " + ", ".join(f"{sid} {len(s['frames'])} frames" for sid, s in ART.sheets.items()))
