"""The kit for Socavón's art: pictures written as text, two colours each, turned into the engine's assets.

A block (8x8) is `X` ink and `.` paper; a sprite is `X` ink and `.` see-through (a ZX Spectrum sprite has an ink and no
paper of its own: it takes the ink of the block it is over, the colour clash). `ART.tile(name, rows)` and
`ART.sprite(sheet, name, rows)` register pictures; build() writes them:

  assets/ROOM.tiles/.map   an atlas of every block, 32 blocks wide (the game reads each tile's number with mget)
  assets/<SHEET>.idx       a strip of 16x16 (or w x h) frames
  data/tilepos.lua         block name -> {column, row} in the atlas
  data/frames.lua          sheet -> frame name -> number
  art/*.png                contact sheets to look at (ink white on black, and in colour)
"""
from __future__ import annotations

import subprocess
import sys
from pathlib import Path

from PIL import Image

HERE = Path(__file__).resolve().parent.parent
ROOT = HERE.parents[1]
ART_DIR, ASSETS, DATA = HERE / "art", HERE / "assets", HERE / "data"
INK, PAPER = (255, 255, 255), (8, 8, 8)  # the key colours: index 1 and 2 of WORLD.pal
ATLAS_W = 32


def rows_of(text: str, w: int, h: int) -> list[str]:
    rows = [r for r in text.strip("\n").split("\n")]
    rows = [r.strip() if len(r.strip()) == w else r for r in rows]
    if len(rows) != h or any(len(r) != w for r in rows):
        bad = [(i, len(r)) for i, r in enumerate(rows) if len(r) != w]
        raise ValueError(f"picture needs {h} rows of {w}: has {len(rows)} rows, bad rows {bad}")
    bad = {c for r in rows for c in r} - set("X.")
    if bad:
        raise ValueError(f"picture has characters other than X and .: {sorted(bad)}")
    return rows


class Registry:
    def __init__(self):
        self.tiles: dict[str, list[str]] = {}
        self.sheets: dict[str, dict] = {}

    def tile(self, name: str, rows) -> None:
        rows = rows_of(rows, 8, 8) if isinstance(rows, str) else rows
        if name in self.tiles:
            raise ValueError(f"block {name} twice")
        self.tiles[name] = rows

    def sheet(self, name: str, w: int = 16, h: int = 16) -> None:
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


def contact(pics: list[list[str]], cols: int, scale: int, ink, paper, transparent=False) -> Image.Image:
    h, w = len(pics[0]), len(pics[0][0])
    rows = (len(pics) + cols - 1) // cols
    img = Image.new("RGB", ((w + 1) * cols * scale, (h + 1) * rows * scale), (40, 40, 40))
    for i, p in enumerate(pics):
        ox, oy = (i % cols) * (w + 1), (i // cols) * (h + 1)
        for y, row in enumerate(p):
            for x, ch in enumerate(row):
                c = ink if ch == "X" else paper
                for dy in range(scale):
                    for dx in range(scale):
                        img.putpixel(((ox + x) * scale + dx, (oy + y) * scale + dy), c)
    return img


def build() -> None:
    for d in (ART_DIR, ASSETS, DATA):
        d.mkdir(exist_ok=True)
    key = lambda c: (c[0] >> 3) << 11 | (c[1] >> 2) << 5 | c[2] >> 3
    (ASSETS / "WORLD.pal").write_bytes(b"".join(v.to_bytes(2, "little") for v in (0, key(INK), key(PAPER))))
    (ASSETS / "OBJ.pal").write_bytes(b"".join(v.to_bytes(2, "little") for v in (0, key(INK))))
    names = list(ART.tiles)
    n_rows = max(18, (len(names) + ATLAS_W - 1) // ATLAS_W)  # the map is also the room's 32x18 grid of cells
    atlas = Image.new("RGB", (ATLAS_W * 8, n_rows * 8), PAPER)
    pos = {}
    for i, n in enumerate(names):
        cx, cy = i % ATLAS_W, i // ATLAS_W
        pos[n] = [cx, cy]
        for y, row in enumerate(ART.tiles[n]):
            for x, ch in enumerate(row):
                atlas.putpixel((cx * 8 + x, cy * 8 + y), INK if ch == "X" else PAPER)
    atlas.save(ART_DIR / "room.png")
    convert(ART_DIR / "room.png", "ROOM", "--tiles", "--palette", "WORLD")
    frames = {}
    for sid, s in ART.sheets.items():
        fr = s["frames"]
        strip = Image.new("RGBA", (s["w"] * len(fr), s["h"]))
        for i, (_, rows) in enumerate(fr):
            for y, row in enumerate(rows):
                for x, ch in enumerate(row):
                    if ch == "X":
                        strip.putpixel((i * s["w"] + x, y), INK + (255,))
        strip.save(ART_DIR / f"{sid.lower()}.png")
        convert(ART_DIR / f"{sid.lower()}.png", sid, "--indexed", "--frames", str(len(fr)), "--palette", "OBJ")
        frames[sid] = {"w": s["w"], "h": s["h"], "n": len(fr), **{name: i for i, (name, _) in enumerate(fr)}}
    (DATA / "tilepos.lua").write_text("-- made by gen/art.py: block name -> {column, row} of the ROOM atlas\nreturn " + lua_table(pos) + "\n")
    (DATA / "frames.lua").write_text("-- made by gen/art.py: sprite sheets and their frame numbers\nreturn " + lua_table(frames) + "\n")
    # contact sheets to look at: the blocks as ink on black and the sprites
    contact([ART.tiles[n] for n in names], 16, 6, INK, PAPER).save(ART_DIR / "tiles_sheet.png")
    for sid, s in ART.sheets.items():
        contact([r for _, r in s["frames"]], 8, 5, INK, PAPER).save(ART_DIR / f"sheet_{sid.lower()}.png")
    print(f"{len(names)} blocks, " + ", ".join(f"{sid} {len(s['frames'])} frames" for sid, s in ART.sheets.items()))
