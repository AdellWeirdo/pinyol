# /// script
# requires-python = ">=3.10"
# dependencies = ["pillow>=10.1", "fonttools>=4"]
# ///
"""The ZX Spectrum-style game's art, drawn here by code: the room's 8x8 blocks, the miner and the guardian.

    uv run examples/cinta/art.py      # art/*.png and assets/ (art/make_art.py makes the loading screen)

Every block is drawn in two key colours, its ink and its paper, which WORLD.pal keeps at indices 1 and 2: the game
gives each block its colours with a palette bank (16 entries each, map entry | bank << 12), as the Spectrum's
attributes did, two colours an 8x8 block. Sprites are ink only (OBJ.pal index 1); the game colours each with a bank
too: the ink of the block it is in, so it changes colour as it passes, the famous clash. The room comes from
room.lua; columns 28 and up of its map hold the blocks the game swaps in (a conveyor's turns, a floor crumbling).
"""
from __future__ import annotations

import shutil
import subprocess
import sys
from pathlib import Path

from PIL import Image

HERE = Path(__file__).resolve().parent
ROOT = HERE.parents[1]
ART, ASSETS = HERE / "art", HERE / "assets"
INK, PAPER = (255, 255, 255), (8, 8, 8)  # the key colours: index 1 and 2 of WORLD.pal

BLOCKS = {  # 8x8: X ink, . paper
    ".": ["........"] * 8,
    "#": ["XXXXXXXX", "X...X...", "X...X...", "XXXXXXXX", "..X...X.", "..X...X.", "XXXXXXXX", "X...X..."],
    "=": ["XXXXXXXX", "XXXXXXXX", "X.XX.XX.", ".X..X..X", "........", "........", "........", "........"],
    "-": ["XXXXXXXX", "X.X.X.X.", ".X.X.X.X", "X...X...", "........", "........", "........", "........"],
    "-1": ["........", "XXXXXXXX", "X.X.X.X.", ".X...X..", "........", "........", "........", "........"],
    "-2": ["........", "........", "X.X.X.X.", "X...X...", "........", "........", "........", "........"],
    ">": ["XXXXXXXX", "X..X..X.", "XXXXXXXX", ".X..X..X", "........", "........", "........", "........"],
    ">1": ["XXXXXXXX", ".X..X..X", "XXXXXXXX", "..X..X..", "........", "........", "........", "........"],
    ">2": ["XXXXXXXX", "..X..X..", "XXXXXXXX", "X..X..X.", "........", "........", "........", "........"],
    "*": ["...X....", "X..X..X.", ".X.X.X..", "..XXX...", "X.XXX.X.", ".XXXXX..", "..XXX...", "XXXXXXXX"],
    "k": ["..XXX...", ".X...X..", ".X...X..", "..XXX...", "...X....", "...XX...", "...X....", "...XXX.."],
    "X": ["XXXXXXXX", "X......X", "X.XXXX.X", "X.X..X.X", "X.X..X.X", "X.XXXX.X", "X......X", "XXXXXXXX"],
}
SPARE = [">1", ">2", "-1", "-2"]  # in column 28, rows 0-3: the game reads their tile numbers with mget

MINER = """
......XXX.......|......XXX.......|......XXX.......|......XXX.......
.....XXXXXX.....|.....XXXXXX.....|.....XXXXXX.....|.....XXXXXX.....
....XXXXXXXXX...|....XXXXXXXXX...|....XXXXXXXXX...|....XXXXXXXXX...
.....X.XX.......|.....X.XX.......|.....X.XX.......|.....X.XX.......
.....XXXXX......|.....XXXXX......|.....XXXXX......|.....XXXXX......
......XXX.......|......XXX.......|......XXX.......|......XXX.......
.....XXXXX......|.....XXXXX......|.....XXXXX......|.....XXXXX......
....XXXXXXX.....|....XXXXXXX.....|....XXXXXXX.....|....XXXXXXX.....
...XX.XXX.XX....|....XXXXXX......|...XX.XXX.XX....|....XXXXXX......
...X..XXX..X....|.....XXXX.......|...X..XXX..X....|.....XXXX.......
......XXX.......|......XXX.......|......XXX.......|......XXX.......
.....XX.XX......|......XX........|.....XX.XX......|......XXX.......
....XX...XX.....|......XX........|....XX...XX.....|.....XX.X.......
...XX.....XX....|......XXX.......|...XX.....XX....|.....X..XX......
..XXX.....XXX...|......XX........|..XXX.....XXX...|....XX...X......
................|................|................|................
"""

GUARD = """
.....XXXXXX.....|.....XXXXXX.....
....XXXXXXXX....|....XXXXXXXX....
...XX.XXXX.XX...|...XXX.XX.XXX...
...XXXXXXXXXX...|...XXXXXXXXXX...
....XXXXXXXX....|....XXXXXXXX....
......XXXX......|......XXXX......
...XXXXXXXXXX...|...XXXXXXXXXX...
..XX.XXXXXX.XX..|..XXXXXXXXXXXX..
..XX.XXXXXX.XX..|.XX..XXXXXX..XX.
.....XXXXXX.....|.....XXXXXX.....
.....X....X.....|.....X....X.....
....XX....XX....|.....XX..XX.....
...XX......XX...|......X..X......
..XXX......XXX..|.....XX..XX.....
................|................
................|................
"""


def frames(art: str) -> Image.Image:
    rows = art.strip("\n").split("\n")
    fs = list(zip(*(r.split("|") for r in rows)))
    img = Image.new("RGBA", (16 * len(fs), 16))
    for i, f in enumerate(fs):
        for y, row in enumerate(f):
            for x, ch in enumerate(row):
                if ch == "X":
                    img.putpixel((i * 16 + x, y), INK + (255,))
    return img


def room() -> Image.Image:
    rows = [l.split('"')[1] for l in (HERE / "room.lua").read_text().splitlines() if l.startswith('  "')]
    img = Image.new("RGB", (32 * 8, 18 * 8), PAPER)
    def put(name: str, tx: int, ty: int) -> None:
        for y, row in enumerate(BLOCKS[name]):
            for x, ch in enumerate(row):
                img.putpixel((tx * 8 + x, ty * 8 + y), INK if ch == "X" else PAPER)
    for ty, row in enumerate(rows):
        for tx, ch in enumerate(row):
            put(ch if ch in BLOCKS else ".", tx, ty)
    for i, name in enumerate(SPARE):
        put(name, 28, i)
    return img


def convert(png: str, aid: str, *opts: str) -> None:
    subprocess.run([sys.executable, str(ROOT / "tools" / "png2asset.py"), str(ART / png), str(ASSETS), aid, *opts],
                   check=True)


def main() -> None:
    ART.mkdir(exist_ok=True)
    ASSETS.mkdir(exist_ok=True)
    room().save(ART / "room.png")
    frames(MINER).save(ART / "miner.png")
    frames(GUARD).save(ART / "guard.png")
    key = lambda c: (c[0] >> 3) << 11 | (c[1] >> 2) << 5 | c[2] >> 3
    (ASSETS / "WORLD.pal").write_bytes(b"".join(v.to_bytes(2, "little") for v in (0, key(INK), key(PAPER))))
    (ASSETS / "OBJ.pal").write_bytes(b"".join(v.to_bytes(2, "little") for v in (0, key(INK))))
    convert("room.png", "ROOM", "--tiles", "--palette", "WORLD")
    convert("miner.png", "MINER", "--indexed", "--frames", "4", "--palette", "OBJ")
    convert("guard.png", "GUARD", "--indexed", "--frames", "2", "--palette", "OBJ")
    convert("loading_mono.png", "LOAD_MONO", "--type", "background")
    convert("loading.png", "LOAD", "--type", "background")
    sys.path.insert(0, str(ROOT / "tools"))
    import font2fnt
    font2fnt.build("pressstart2p", str(HERE / "fonts" / "arcade.fnt"), None, 2)
    for f in ("FONT_MAIN.fnt", "FONT_BOLD.fnt", "FONT_MAIN_L.fnt", "FONT_BOLD_L.fnt"):  # the engine's own, as every game
        shutil.copy(ROOT / "examples" / "naves" / "fonts" / f, HERE / "fonts" / f)


if __name__ == "__main__":
    main()
