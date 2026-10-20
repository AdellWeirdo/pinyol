# /// script
# requires-python = ">=3.10"
# dependencies = ["pillow>=10.1"]
# ///
"""The art of Sima, drawn by code: two tile maps the size of a floor (48 x 32 cells of 16 pixels) that the game writes cell by cell with
mset, and the sprites (the hero, three monsters, a potion, gold, the amulet, a blow).

    uv run examples/sima/art.py           # art/*.png, then assets/, and index.lua (the four map entries of each kind of cell)

DUNGEON (BG1) is all rock but for one row past the floor's last (never shown: the camera stops at the floor's edge), which holds one
cell of each kind: rock, rock with its face lit (a wall over a floor), floor, cracked floor, stairs down. FOG (BG0, over the sprites) is
all dark but for, in that row, one cell seen before (a checker of dark: what is under it shows dimmed) and one clear. The game reads
where each kind's four 8x8 tiles went from index.lua, and loads the two maps again for each floor: they come back all rock and all
dark at once, and only the floor's open cells and what the hero sees are written into them.
"""
from __future__ import annotations

import subprocess
import sys
from pathlib import Path

from PIL import Image, ImageDraw

HERE = Path(__file__).resolve().parent
ROOT = HERE.parents[1]
ART, ASSETS = HERE / "art", HERE / "assets"
CELL, W, H = 16, 48, 32

ROCK, ROCK_HI, ROCK_LO = (58, 50, 62), (84, 74, 88), (38, 32, 42)
FACE, FACE_HI, FACE_LO = (120, 98, 84), (150, 126, 106), (86, 68, 58)
SLAB, SLAB_HI, SEAM = (72, 80, 96), (88, 98, 116), (48, 54, 66)
DARK = (8, 6, 12)
CELLS = ["wall", "face", "floor", "crack", "stairs"]
FOGS = ["dark", "seen", "clear"]


def cell_img(kind: str) -> Image.Image:
    img = Image.new("RGBA", (CELL, CELL), (0, 0, 0, 0))
    d = ImageDraw.Draw(img)
    if kind in ("wall", "face"):
        d.rectangle((0, 0, 15, 15), fill=ROCK)
        for x, y in ((2, 3), (9, 1), (12, 8), (4, 11), (7, 6)):
            d.point((x, y), fill=ROCK_HI), d.point((x + 1, y + 1), fill=ROCK_LO)
        if kind == "face":  # the wall's front, lit by the hero's torch: two courses of stone
            d.rectangle((0, 8, 15, 15), fill=FACE)
            d.line((0, 8, 15, 8), fill=FACE_HI)
            d.line((0, 12, 15, 12), fill=FACE_LO)
            d.line((7, 9, 7, 11), fill=FACE_LO), d.line((3, 13, 3, 15), fill=FACE_LO), d.line((11, 13, 11, 15), fill=FACE_LO)
    elif kind in ("floor", "crack"):
        d.rectangle((0, 0, 15, 15), fill=SLAB)
        d.line((0, 0, 15, 0), fill=SLAB_HI), d.line((0, 0, 0, 15), fill=SLAB_HI)
        d.line((0, 15, 15, 15), fill=SEAM), d.line((15, 0, 15, 15), fill=SEAM)
        d.line((8, 1, 8, 7), fill=SEAM), d.line((1, 8, 14, 8), fill=SEAM)
        if kind == "crack":
            d.line((3, 10, 6, 13), fill=SEAM), d.line((6, 13, 10, 12), fill=SEAM)
    elif kind == "stairs":
        d.rectangle((0, 0, 15, 15), fill=SLAB)
        for i, c in enumerate(((40, 40, 52), (28, 28, 38), (18, 18, 26), (8, 8, 14))):
            d.rectangle((1 + i, 2 + 3 * i, 14 - i, 4 + 3 * i), fill=c)
    return img


def fog_img(kind: str) -> Image.Image:
    img = Image.new("RGBA", (CELL, CELL), (0, 0, 0, 0))
    for y in range(CELL):
        for x in range(CELL):
            if kind == "dark" or (kind == "seen" and (x + y) % 2 == 0):
                img.putpixel((x, y), DARK + (255,))
    return img


def sheet_map(kinds: list[str], make, fill: str, name: str) -> None:
    img = Image.new("RGBA", (W * CELL, (H + 1) * CELL), (0, 0, 0, 0))
    filler = make(fill)
    for cy in range(H + 1):
        for cx in range(W):
            img.paste(make(kinds[cx]) if cy == H and cx < len(kinds) else filler, (cx * CELL, cy * CELL))
    img.save(ART / f"{name}.png")


def entries(aid: str, kinds: list[str]) -> dict:
    raw = (ASSETS / f"{aid}.map").read_bytes()
    tw = W * 2
    at = lambda tx, ty: int.from_bytes(raw[(ty * tw + tx) * 2:(ty * tw + tx) * 2 + 2], "little")
    y = 2 * H
    return {k: [at(2 * i, y), at(2 * i + 1, y), at(2 * i, y + 1), at(2 * i + 1, y + 1)] for i, k in enumerate(kinds)}


# ------------------------------------------------------------------ the sprites, 16 x 16
def figure(draw) -> list[Image.Image]:
    out = []
    for f in (0, 1):
        img = Image.new("RGBA", (16, 16), (0, 0, 0, 0))
        draw(ImageDraw.Draw(img), f)
        out.append(img)
    return out


def hero(d: ImageDraw.ImageDraw, f: int) -> None:
    b = f  # a breath: the body one pixel lower on the second frame
    d.ellipse((5, 1 + b, 10, 6 + b), fill=(240, 196, 150))  # head
    d.rectangle((4, 0 + b, 11, 2 + b), fill=(70, 120, 210))  # hood
    d.point((9, 4 + b), fill=(20, 20, 30))
    d.rectangle((4, 7 + b, 11, 12), fill=(70, 120, 210))  # cloak
    d.line((12, 3, 12, 12), fill=(220, 220, 230))  # sword
    d.line((11, 9, 13, 9), fill=(150, 110, 60))
    d.rectangle((5, 13, 6, 15), fill=(60, 44, 40)), d.rectangle((9, 13, 10, 15), fill=(60, 44, 40))


def rat(d: ImageDraw.ImageDraw, f: int) -> None:
    d.ellipse((3, 8, 12, 14), fill=(150, 130, 120))
    d.ellipse((10, 7, 14, 11), fill=(150, 130, 120))
    d.point((13, 8), fill=(220, 40, 40)), d.point((11, 6), fill=(200, 160, 160))
    d.line((3, 12, 0, 10 + f * 3), fill=(210, 160, 160))  # the tail swings
    d.point((5, 15 - f), fill=(110, 90, 80)), d.point((10, 14 + f), fill=(110, 90, 80))


def bat(d: ImageDraw.ImageDraw, f: int) -> None:
    c = (110, 70, 140)
    d.ellipse((6, 6, 10, 11), fill=c)
    if f == 0:
        d.polygon([(6, 8), (0, 4), (2, 10)], fill=c), d.polygon([(10, 8), (15, 4), (13, 10)], fill=c)
    else:
        d.polygon([(6, 8), (0, 12), (3, 13)], fill=c), d.polygon([(10, 8), (15, 12), (12, 13)], fill=c)
    d.point((7, 8), fill=(255, 220, 80)), d.point((9, 8), fill=(255, 220, 80))


def skeleton(d: ImageDraw.ImageDraw, f: int) -> None:
    bone, dark = (232, 228, 210), (60, 56, 50)
    d.ellipse((5, 0, 10, 5), fill=bone)
    d.point((6, 2), fill=dark), d.point((9, 2), fill=dark)
    d.line((7, 6, 7, 11), fill=bone), d.line((8, 6, 8, 11), fill=bone)
    for y in (7, 9):
        d.line((5, y, 10, y), fill=bone)
    d.line((5, 7, 3, 10 - f), fill=bone), d.line((10, 7, 12, 10 - f), fill=bone)
    d.line((7, 11, 5, 15), fill=bone), d.line((8, 11, 10, 15), fill=bone)
    d.line((12, 4 - f, 12, 11 - f), fill=(160, 160, 170))  # a rusty blade


def still(draw) -> list[Image.Image]:
    img = Image.new("RGBA", (16, 16), (0, 0, 0, 0))
    draw(ImageDraw.Draw(img))
    return [img]


def potion(d: ImageDraw.ImageDraw) -> None:
    d.rectangle((7, 2, 8, 5), fill=(200, 200, 210))
    d.ellipse((4, 5, 11, 13), fill=(220, 40, 80))
    d.point((6, 7), fill=(255, 180, 200))


def gold(d: ImageDraw.ImageDraw) -> None:
    for x, y in ((4, 9), (8, 10), (6, 6), (10, 7)):
        d.ellipse((x, y, x + 4, y + 3), fill=(240, 200, 60), outline=(170, 120, 30))


def amulet(d: ImageDraw.ImageDraw) -> None:
    d.arc((3, 0, 12, 9), 180, 360, fill=(240, 200, 60))
    d.ellipse((4, 6, 11, 13), fill=(60, 200, 160), outline=(240, 200, 60))
    d.point((6, 8), fill=(200, 255, 240))


def blow() -> list[Image.Image]:
    out = []
    for r in (3, 6):
        img = Image.new("RGBA", (16, 16), (0, 0, 0, 0))
        d = ImageDraw.Draw(img)
        for a, b in (((8 - r, 8), (8 + r, 8)), ((8, 8 - r), (8, 8 + r)), ((8 - r + 1, 8 - r + 1), (8 + r - 1, 8 + r - 1))):
            d.line((*a, *b), fill=(255, 250, 200))
        out.append(img)
    return out


def strip(frames: list[Image.Image]) -> Image.Image:
    img = Image.new("RGBA", (16 * len(frames), 16), (0, 0, 0, 0))
    for i, f in enumerate(frames):
        img.paste(f, (16 * i, 0))
    return img


def main() -> None:
    ART.mkdir(exist_ok=True)
    ASSETS.mkdir(exist_ok=True)
    for f in ASSETS.glob("*"):
        f.unlink()
    sheet_map(CELLS, cell_img, "wall", "dungeon")
    sheet_map(FOGS, fog_img, "dark", "fog")
    py, png = sys.executable, str(ROOT / "tools" / "png2asset.py")
    for name, aid in (("dungeon", "DUNGEON"), ("fog", "FOG")):
        subprocess.run([py, png, str(ART / f"{name}.png"), str(ASSETS), aid, "--tiles", "--palette", "WORLD"], check=True)
    sprites = {"HERO": figure(hero), "RATA": figure(rat), "MURCIELAGO": figure(bat), "ESQUELETO": figure(skeleton),
               "POCION": still(potion), "ORO": still(gold), "AMULETO": still(amulet), "GOLPE": blow()}
    for aid, frames in sprites.items():
        strip(frames).save(ART / f"{aid.lower()}.png")
        subprocess.run([py, png, str(ART / f"{aid.lower()}.png"), str(ASSETS), aid, "--indexed", "--frames", str(len(frames)),
                        "--palette", "OBJ"], check=True)
    cells, fogs = entries("DUNGEON", CELLS), entries("FOG", FOGS)
    fmt = lambda d: ", ".join(f"{k} = {{{', '.join(str(v) for v in e)}}}" for k, e in d.items())
    (HERE / "index.lua").write_text("-- made by art.py: the map entries of each kind of cell (top-left, top-right, bottom-left, bottom-right)\n"
                                    f"return {{cells = {{{fmt(cells)}}},\n  fog = {{{fmt(fogs)}}}}}\n")


if __name__ == "__main__":
    main()
