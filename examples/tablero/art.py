# /// script
# requires-python = ">=3.10"
# dependencies = ["pillow>=10.1"]
# ///
"""The art of Tablero, drawn by code: a battlefield of 15 x 10 tiles, the layer of highlights that goes over it, the units and the cursor.

    uv run examples/tablero/art.py           # art/*.png and data.lua, then assets/ (tools/png2asset.py)

data.lua is what the game reads of the field: the terrain of each cell and where each army starts.
"""
from __future__ import annotations

import subprocess
import sys
from pathlib import Path

from PIL import Image, ImageDraw

HERE = Path(__file__).resolve().parent
ROOT = HERE.parents[1]
ART, ASSETS = HERE / "art", HERE / "assets"
T = 16

GRASS, GRASS_D, GRASS_L = (112, 176, 84), (92, 156, 72), (148, 204, 108)
LEAF, LEAF_D, LEAF_L, TRUNK = (48, 116, 60), (30, 88, 46), (84, 152, 72), (104, 72, 44)
ROCK, ROCK_D, ROCK_L, SNOW = (146, 140, 150), (98, 94, 108), (192, 188, 198), (240, 244, 250)
WATER, WATER_D, WATER_L = (70, 128, 204), (50, 102, 178), (150, 196, 240)
SAND, SAND_D = (226, 196, 140), (200, 166, 110)
WOOD, WOOD_D = (160, 112, 64), (120, 80, 44)
INK = (30, 26, 42)

PLAIN, FOREST, MOUNTAIN, WATER_T, ROAD, BRIDGE = range(6)
NAMES = ["plain", "forest", "mountain", "water", "road", "bridge"]
CODE = {".": PLAIN, "f": FOREST, "m": MOUNTAIN, "w": WATER_T, "r": ROAD, "b": BRIDGE}

PLAN = [
    "..ff...w...ff..",
    ".f.....w.....f.",
    "...mm..w..mm...",
    "rrrrrrrbrrrrrrr",
    "...f...w...f...",
    ".....f.w.f.....",
    "...rrrrbrrrr...",
    "..mm...w...mm..",
    ".f.....w.....f.",
    "..ff...w...ff..",
]
# where the armies stand (x, y) and what they are: 0 sword, 1 bow, 2 rider
BLUE = [(1, 3, 0), (2, 4, 0), (1, 6, 1), (3, 6, 2)]
RED = [(13, 3, 0), (12, 5, 0), (13, 6, 1), (11, 6, 2)]


def base(kind_seed: int = 0) -> Image.Image:
    img = Image.new("RGBA", (T, T), GRASS + (255,))
    d = ImageDraw.Draw(img)
    for x, y in ((2, 3), (9, 1), (13, 6), (5, 10), (11, 13), (1, 14)):
        d.point((x, y), fill=GRASS_D)
    for x, y in ((6, 5), (14, 11), (3, 8), (10, 9)):
        d.point((x, y), fill=GRASS_L)
    return img


def tile(kind: int) -> Image.Image:
    img = base()
    d = ImageDraw.Draw(img)
    if kind == FOREST:
        for cx, cy in ((4, 6), (11, 5), (7, 11)):
            d.rectangle((cx - 1, cy + 3, cx, cy + 6), fill=TRUNK)
            d.polygon([(cx - 4, cy + 3), (cx - 1, cy - 5), (cx + 2, cy + 3)], fill=LEAF_D)
            d.polygon([(cx - 3, cy + 2), (cx - 1, cy - 3), (cx + 1, cy + 2)], fill=LEAF)
    elif kind == MOUNTAIN:
        d.polygon([(0, 15), (5, 3), (10, 15)], fill=ROCK_D)
        d.polygon([(6, 15), (11, 1), (16, 15)], fill=ROCK)
        d.polygon([(9, 6), (11, 1), (13, 6)], fill=SNOW)
        d.polygon([(11, 15), (11, 1), (16, 15)], fill=ROCK_D)
        d.polygon([(4, 7), (5, 3), (7, 7)], fill=ROCK_L)
    elif kind == WATER_T:
        d.rectangle((0, 0, 15, 15), fill=WATER)
        for x, y in ((1, 3), (8, 1), (4, 9), (11, 12), (13, 6)):
            d.line((x, y, x + 3, y), fill=WATER_L)
            d.line((x + 1, y + 1, x + 4, y + 1), fill=WATER_D)
    elif kind == ROAD:
        d.rectangle((0, 0, 15, 15), fill=SAND)
        for x, y in ((3, 2), (11, 4), (6, 9), (13, 12), (2, 13)):
            d.point((x, y), fill=SAND_D)
    elif kind == BRIDGE:
        d.rectangle((0, 0, 15, 15), fill=WATER)
        for x, y in ((1, 3), (9, 12)):
            d.line((x, y, x + 3, y), fill=WATER_L)
        d.rectangle((0, 3, 15, 12), fill=WOOD)
        for x in range(1, 16, 4):
            d.line((x, 3, x, 12), fill=WOOD_D)
        d.line((0, 3, 15, 3), fill=WOOD_D)
        d.line((0, 12, 15, 12), fill=WOOD_D)
    return img


def draw_field() -> None:
    tiles = [tile(k) for k in range(len(NAMES))]
    img = Image.new("RGBA", (15 * T, 10 * T))
    for y, row in enumerate(PLAN):
        for x, c in enumerate(row):
            img.paste(tiles[CODE[c]], (x * T, y * T))
    img.save(ART / "field.png")
    lines = ["-- made by art.py: the cells (0 plain, 1 forest, 2 mountain, 3 water, 4 road, 5 bridge) and where the armies start",
             "return {w = 15, h = 10, grid = {"]
    for row in PLAN:
        lines.append("  {" + ", ".join(str(CODE[c]) for c in row) + "},")
    lines.append("},")
    for name, army in (("blue", BLUE), ("red", RED)):
        lines.append(f"{name} = {{" + ", ".join(f"{{{x}, {y}, {k}}}" for x, y, k in army) + "},")
    lines.append("}")
    (HERE / "data.lua").write_text("\n".join(lines) + "\n")


def draw_overlay() -> None:
    """A layer of the same size, empty but for four 16 x 16 swatches in its top left: the game turns its cells into them
    (mset) to show where a unit can go (blue), what it can hit (red), the danger (orange) and the cursor's row (yellow)."""
    img = Image.new("RGBA", (15 * T, 10 * T), (0, 0, 0, 0))
    d = ImageDraw.Draw(img)
    for i, c in enumerate(((60, 120, 255), (255, 70, 70), (255, 150, 40), (255, 240, 90))):
        d.rectangle(((i + 1) * T, 0, (i + 2) * T - 1, T - 1), fill=c + (255,))
    img.save(ART / "overlay.png")


def unit(team: int, kind: int, frame: int) -> Image.Image:
    tunic = ((60, 110, 220), (220, 70, 70))[team]
    light = tuple(min(255, c + 40) for c in tunic)
    img = Image.new("RGBA", (16, 16), (0, 0, 0, 0))
    d = ImageDraw.Draw(img)
    bob = frame
    d.ellipse((3, 13, 12, 15), fill=(0, 0, 0, 80))
    if kind == 2:  # a rider: a horse under it
        d.rectangle((2, 9 + bob, 13, 12), fill=(130, 86, 52))
        d.rectangle((11, 6 + bob, 14, 10), fill=(130, 86, 52))
        d.rectangle((3, 12, 4, 14), fill=(100, 64, 40))
        d.rectangle((10, 12, 11, 14), fill=(100, 64, 40))
        d.rectangle((5, 5 + bob, 9, 10), fill=tunic)
        d.rectangle((5, 5 + bob, 9, 6 + bob), fill=light)
        d.ellipse((5, 0 + bob, 10, 5 + bob), fill=(240, 200, 160))
        d.line((2, 3 + bob, 2, 10), fill=(220, 220, 236))
    else:
        d.rectangle((5, 12, 6, 14), fill=(50, 44, 60))
        d.rectangle((9, 12, 10, 14), fill=(50, 44, 60))
        d.rectangle((4, 6 + bob, 11, 12), fill=tunic)
        d.rectangle((4, 6 + bob, 11, 7 + bob), fill=light)
        d.ellipse((4, 0 + bob, 11, 7 + bob), fill=(240, 200, 160))
        d.chord((4, 0 + bob, 11, 7 + bob), 180, 360, fill=(80, 56, 36))
        d.point((6, 4 + bob), fill=INK)
        d.point((9, 4 + bob), fill=INK)
        if kind == 0:
            d.line((13, 3 + bob, 13, 11), fill=(220, 220, 236))
            d.point((13, 12), fill=(170, 120, 60))
            d.line((12, 11, 14, 11), fill=(170, 120, 60))
        else:
            d.arc((10, 3 + bob, 15, 13), 270, 90, fill=(170, 120, 60))
            d.line((12, 3 + bob, 12, 13), fill=(230, 230, 230))
    out = Image.new("RGBA", (16, 16), (0, 0, 0, 0))
    ink = ImageDraw.Draw(out)
    px = img.load()
    for y in range(16):
        for x in range(16):
            if px[x, y][3] < 128:
                for dx, dy in ((1, 0), (-1, 0), (0, 1), (0, -1)):
                    nx, ny = x + dx, y + dy
                    if 0 <= nx < 16 and 0 <= ny < 16 and px[nx, ny][3] >= 128 and px[nx, ny] != (0, 0, 0, 80):
                        ink.point((x, y), fill=INK + (255,))
                        break
    out.alpha_composite(img)
    return out


def cursor(frame: int) -> Image.Image:
    img = Image.new("RGBA", (16, 16), (0, 0, 0, 0))
    d = ImageDraw.Draw(img)
    pad = frame
    c = (255, 250, 200, 255)
    for x0, y0, dx, dy in ((0, 0, 1, 1), (15, 0, -1, 1), (0, 15, 1, -1), (15, 15, -1, -1)):
        x, y = x0 + dx * pad, y0 + dy * pad
        d.line((x, y, x + dx * 4, y), fill=c)
        d.line((x, y, x, y + dy * 4), fill=c)
    return img


def draw_sprites() -> None:
    units = Image.new("RGBA", (16 * 12, 16), (0, 0, 0, 0))
    for team in range(2):
        for kind in range(3):
            for frame in range(2):
                units.paste(unit(team, kind, frame), (((team * 3 + kind) * 2 + frame) * 16, 0))
    units.save(ART / "units.png")
    cur = Image.new("RGBA", (32, 16), (0, 0, 0, 0))
    for f in range(2):
        cur.paste(cursor(f), (f * 16, 0))
    cur.save(ART / "cursor.png")


def convert() -> None:
    py, png = sys.executable, str(ROOT / "tools" / "png2asset.py")
    ASSETS.mkdir(exist_ok=True)
    for f in ASSETS.glob("*"):
        f.unlink()
    for name, aid in (("field.png", "FIELD"), ("overlay.png", "OVERLAY")):
        subprocess.run([py, png, str(ART / name), str(ASSETS), aid, "--tiles", "--palette", "WORLD"], check=True)
    for name, aid, n in (("units.png", "UNITS", 12), ("cursor.png", "CURSOR", 2)):
        subprocess.run([py, png, str(ART / name), str(ASSETS), aid, "--indexed", "--frames", str(n), "--palette", "OBJ"], check=True)


def main() -> None:
    ART.mkdir(exist_ok=True)
    draw_field()
    draw_overlay()
    draw_sprites()
    convert()


if __name__ == "__main__":
    main()
