# /// script
# requires-python = ">=3.10"
# dependencies = ["pillow>=10.1"]
# ///
"""The art of Hierba Alta, all drawn by code: a meadow of 30 x 20 tiles, the battle's backdrop, three enemies and the party.

    uv run examples/combate/art.py           # art/*.png and data.lua, then assets/ (tools/png2asset.py)

data.lua is what the game reads of the map: which cell is a tree, water, a rock, or tall grass (where fights start).
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

GRASS, GRASS_D, GRASS_L = (92, 168, 72), (72, 146, 60), (132, 200, 96)
TALL, TALL_D = (52, 124, 64), (34, 96, 52)
PATH, PATH_D = (222, 190, 132), (196, 160, 104)
WATER, WATER_L = (60, 120, 200), (130, 180, 236)
TRUNK, LEAF, LEAF_D, LEAF_L = (112, 76, 44), (44, 112, 56), (28, 84, 44), (84, 160, 76)
ROCK, ROCK_D, ROCK_L = (150, 150, 160), (104, 104, 120), (196, 196, 206)
INK = (28, 24, 40)

# the tiles, by number: what they are
GRASS_T, TALL_T, PATH_T, TREE_T, WATER_T, FLOWER_T, ROCK_T = range(7)
NAMES = ["grass", "tall", "path", "tree", "water", "flowers", "rock"]


def dither(d: ImageDraw.ImageDraw, base: tuple, spots: list[tuple[int, int]], colour: tuple) -> None:
    for x, y in spots:
        d.point((x, y), fill=colour)


def tile(kind: int) -> Image.Image:
    img = Image.new("RGBA", (T, T), GRASS + (255,))
    d = ImageDraw.Draw(img)
    dither(d, GRASS, [(2, 3), (9, 1), (13, 6), (5, 10), (11, 13), (1, 14)], GRASS_D)
    dither(d, GRASS, [(6, 5), (14, 11), (3, 8), (10, 9)], GRASS_L)
    if kind == TALL_T:
        for x in range(1, 16, 4):
            for y in (3, 9):
                d.polygon([(x, y + 6), (x + 1, y), (x + 2, y + 6)], fill=TALL_D)
                d.polygon([(x + 1, y + 6), (x + 2, y + 1), (x + 3, y + 6)], fill=TALL)
    elif kind == PATH_T:
        d.rectangle((0, 0, 15, 15), fill=PATH)
        dither(d, PATH, [(3, 2), (11, 4), (6, 9), (13, 12), (2, 13)], PATH_D)
    elif kind == TREE_T:
        d.ellipse((2, 13, 13, 15), fill=(0, 0, 0, 70))
        d.rectangle((6, 9, 9, 14), fill=TRUNK)
        d.ellipse((0, 0, 15, 11), fill=LEAF_D)
        d.ellipse((1, 0, 14, 9), fill=LEAF)
        d.ellipse((3, 1, 9, 5), fill=LEAF_L)
    elif kind == WATER_T:
        d.rectangle((0, 0, 15, 15), fill=WATER)
        for x, y in ((2, 4), (9, 2), (6, 10), (12, 12)):
            d.line((x, y, x + 3, y), fill=WATER_L)
    elif kind == FLOWER_T:
        for x, y, c in ((3, 4, (240, 220, 90)), (10, 3, (240, 120, 150)), (7, 11, (250, 250, 250)), (13, 12, (240, 220, 90))):
            d.point((x, y - 1), fill=GRASS_L)
            d.rectangle((x, y, x + 1, y + 1), fill=c)
    elif kind == ROCK_T:
        d.ellipse((1, 12, 14, 15), fill=(0, 0, 0, 70))
        d.polygon([(2, 13), (3, 6), (7, 2), (12, 5), (14, 13)], fill=ROCK_D)
        d.polygon([(3, 12), (4, 7), (7, 3), (10, 5), (9, 12)], fill=ROCK)
        d.line((5, 5, 8, 4), fill=ROCK_L)
    return img


def plan() -> list[str]:
    g, t, p, T_, w, f, r = "gtpTwfr"
    rows = ["T" * 30]
    for y in range(1, 19):
        rows.append(["T"] + ["g"] * 28 + ["T"])
    rows.append("T" * 30)
    rows = [list(r_) for r_ in rows]
    for y in range(1, 19):  # the path across, and down to the pond
        rows[y][14] = rows[y][15] = "p"
    for x in range(1, 29):
        rows[9][x] = rows[10][x] = "p"
    for x, y in ((4, 3), (5, 3), (4, 4), (5, 4), (6, 4)):  # a pond in the north-west
        rows[y][x] = "w"
    for y in range(12, 18):  # tall grass west and east: where fights start
        for x in range(3, 12):
            rows[y][x] = "t"
        for x in range(19, 27):
            rows[y][x] = "t"
    for y in range(2, 7):
        for x in range(19, 27):
            if (x + y) % 3 == 0:
                rows[y][x] = "t"
    for x, y in ((22, 7), (8, 7), (25, 15), (12, 3), (17, 15)):
        rows[y][x] = "r"
    for x, y in ((9, 5), (11, 6), (24, 8), (3, 8), (16, 13), (13, 16), (27, 3)):
        rows[y][x] = "f"
    for x, y in ((8, 3), (9, 3), (12, 12), (13, 12), (26, 11), (27, 11), (3, 17), (2, 16)):
        rows[y][x] = "T"
    return ["".join(r_) for r_ in rows]


CODE = {"g": GRASS_T, "t": TALL_T, "p": PATH_T, "T": TREE_T, "w": WATER_T, "f": FLOWER_T, "r": ROCK_T}


def draw_field() -> None:
    tiles = [tile(k) for k in range(len(NAMES))]
    rows = plan()
    img = Image.new("RGBA", (30 * T, 20 * T))
    for y, row in enumerate(rows):
        for x, c in enumerate(row):
            img.paste(tiles[CODE[c]], (x * T, y * T))
    img.save(ART / "field.png")
    lines = ["-- made by art.py: the meadow's cells (0 grass, 1 tall grass, 2 path, 3 tree, 4 water, 5 flowers, 6 rock)",
             "return {w = 30, h = 20, tile = 16, solid = {[3] = true, [4] = true, [6] = true}, tall = 1, grid = {"]
    for row in rows:
        lines.append("  {" + ", ".join(str(CODE[c]) for c in row) + "},")
    lines.append("}}")
    (HERE / "data.lua").write_text("\n".join(lines) + "\n")


def draw_backdrop() -> None:
    img = Image.new("RGBA", (240, 160))
    d = ImageDraw.Draw(img)
    sky = [(108, 170, 236), (128, 186, 240), (150, 200, 244), (176, 214, 246), (200, 226, 248), (224, 238, 250)]
    for i, c in enumerate(sky):
        d.rectangle((0, i * 11, 239, i * 11 + 10), fill=c)
    for cx, cy, w in ((40, 22, 30), (150, 14, 40), (210, 36, 26)):  # clouds
        d.ellipse((cx - w // 2, cy - 5, cx + w // 2, cy + 5), fill=(250, 250, 255))
        d.ellipse((cx - w // 4, cy - 9, cx + w // 4, cy + 3), fill=(250, 250, 255))
    d.polygon([(0, 70), (30, 40), (62, 70)], fill=(116, 150, 196))
    d.polygon([(46, 70), (90, 34), (140, 70)], fill=(100, 136, 184))
    d.polygon([(120, 70), (170, 44), (240, 70)], fill=(116, 150, 196))
    d.rectangle((0, 70, 239, 159), fill=GRASS)
    d.rectangle((0, 70, 239, 74), fill=GRASS_L)
    for y in range(78, 160, 6):  # rows of the meadow getting wider toward you
        for x in range((y // 6 % 2) * 6, 240, 12):
            d.point((x, y), fill=GRASS_D)
            d.point((x + 1, y), fill=GRASS_D)
    for cx, cy, rx, ry in ((176, 84, 40, 9), (56, 106, 46, 11)):  # where they stand (above the menu's panel)
        d.ellipse((cx - rx, cy - ry, cx + rx, cy + ry), fill=(70, 130, 56))
        d.ellipse((cx - rx + 3, cy - ry + 2, cx + rx - 3, cy + ry - 1), fill=(100, 170, 80))
    img.save(ART / "backdrop.png")


def outline(img: Image.Image, colour: tuple = INK) -> Image.Image:
    out = Image.new("RGBA", img.size, (0, 0, 0, 0))
    a = img.split()[3]
    px = a.load()
    o = out.load()
    for y in range(img.height):
        for x in range(img.width):
            if px[x, y] < 128:
                for dx, dy in ((1, 0), (-1, 0), (0, 1), (0, -1)):
                    nx, ny = x + dx, y + dy
                    if 0 <= nx < img.width and 0 <= ny < img.height and px[nx, ny] >= 128:
                        o[x, y] = colour + (255,)
                        break
    out.alpha_composite(img)
    return out


def slime() -> Image.Image:
    img = Image.new("RGBA", (64, 64), (0, 0, 0, 0))
    d = ImageDraw.Draw(img)
    d.ellipse((8, 22, 55, 58), fill=(64, 168, 84))
    d.ellipse((12, 18, 51, 54), fill=(96, 204, 108))
    d.polygon([(20, 22), (32, 8), (44, 22)], fill=(96, 204, 108))
    d.ellipse((17, 24, 29, 32), fill=(176, 240, 180))
    d.ellipse((20, 33, 27, 44), fill=(250, 250, 250))
    d.ellipse((35, 33, 42, 44), fill=(250, 250, 250))
    d.rectangle((23, 38, 26, 43), fill=INK)
    d.rectangle((38, 38, 41, 43), fill=INK)
    d.arc((24, 42, 40, 52), 20, 160, fill=INK)
    return outline(img)


def bat() -> Image.Image:
    img = Image.new("RGBA", (64, 64), (0, 0, 0, 0))
    d = ImageDraw.Draw(img)
    for sx in (-1, 1):  # the wings
        cx = 32
        pts = [(cx + sx * 6, 26), (cx + sx * 28, 12), (cx + sx * 31, 30), (cx + sx * 22, 26), (cx + sx * 20, 38),
               (cx + sx * 12, 32), (cx + sx * 8, 40)]
        d.polygon(pts, fill=(120, 72, 160))
        d.line([(cx + sx * 6, 28), (cx + sx * 26, 16)], fill=(168, 120, 208))
    d.ellipse((22, 20, 42, 46), fill=(86, 52, 120))
    d.polygon([(23, 22), (24, 8), (30, 20)], fill=(86, 52, 120))
    d.polygon([(41, 22), (40, 8), (34, 20)], fill=(86, 52, 120))
    d.ellipse((25, 28, 31, 34), fill=(250, 220, 80))
    d.ellipse((33, 28, 39, 34), fill=(250, 220, 80))
    d.rectangle((27, 30, 29, 33), fill=INK)
    d.rectangle((35, 30, 37, 33), fill=INK)
    d.polygon([(28, 38), (30, 43), (32, 38)], fill=(250, 250, 250))
    d.polygon([(32, 38), (34, 43), (36, 38)], fill=(250, 250, 250))
    return outline(img)


def golem() -> Image.Image:
    img = Image.new("RGBA", (64, 64), (0, 0, 0, 0))
    d = ImageDraw.Draw(img)
    d.rectangle((16, 30, 47, 58), fill=ROCK_D)
    d.rectangle((18, 30, 45, 54), fill=ROCK)
    d.rectangle((20, 6, 43, 28), fill=ROCK_D)
    d.rectangle((22, 6, 42, 24), fill=ROCK)
    d.rectangle((2, 30, 14, 50), fill=ROCK_D)
    d.rectangle((50, 30, 62, 50), fill=ROCK_D)
    d.rectangle((3, 30, 12, 46), fill=ROCK)
    d.rectangle((51, 30, 60, 46), fill=ROCK)
    d.rectangle((24, 14, 30, 18), fill=(250, 120, 60))
    d.rectangle((34, 14, 40, 18), fill=(250, 120, 60))
    d.rectangle((26, 15, 28, 17), fill=(255, 230, 120))
    d.rectangle((36, 15, 38, 17), fill=(255, 230, 120))
    d.line((24, 22, 40, 22), fill=INK)
    d.line((26, 36, 30, 44), fill=ROCK_D)
    d.line((36, 40, 40, 50), fill=ROCK_D)
    d.rectangle((20, 54, 28, 58), fill=ROCK_D)
    d.rectangle((36, 54, 44, 58), fill=ROCK_D)
    d.rectangle((22, 8, 28, 10), fill=ROCK_L)
    return outline(img)


def hero_back(cape: tuple, hair: tuple, mage: bool) -> Image.Image:
    img = Image.new("RGBA", (32, 32), (0, 0, 0, 0))
    d = ImageDraw.Draw(img)
    d.ellipse((6, 27, 25, 31), fill=(0, 0, 0, 70))
    d.rectangle((11, 22, 14, 28), fill=(60, 50, 70))
    d.rectangle((17, 22, 20, 28), fill=(60, 50, 70))
    d.polygon([(8, 12), (23, 12), (26, 26), (5, 26)], fill=cape)
    d.polygon([(10, 12), (21, 12), (22, 24), (9, 24)], fill=tuple(min(255, c + 30) for c in cape))
    d.ellipse((9, 2, 22, 15), fill=hair)
    d.ellipse((11, 9, 20, 15), fill=(236, 196, 156))
    d.chord((9, 2, 22, 15), 170, 370, fill=hair)
    if mage:
        d.polygon([(8, 5), (16, -1), (24, 5), (22, 7), (10, 7)], fill=(120, 60, 170))
        d.line((26, 6, 26, 26), fill=(150, 100, 60), width=2)
        d.ellipse((24, 2, 29, 7), fill=(250, 230, 100))
    else:
        d.line((25, 8, 25, 22), fill=(220, 220, 236), width=2)
        d.rectangle((23, 22, 27, 23), fill=(170, 120, 60))
    return outline(img)


def walker(direction: int, step: int) -> Image.Image:
    body, hair = (60, 110, 210), (90, 54, 30)
    img = Image.new("RGBA", (16, 16), (0, 0, 0, 0))
    d = ImageDraw.Draw(img)
    d.ellipse((3, 13, 12, 15), fill=(0, 0, 0, 80))
    leg = (1, -1)[step]
    side = direction % 2 == 1
    d.rectangle((5, 10, 6, 13 + (0 if side else leg)), fill=(50, 44, 60))
    d.rectangle((9, 10, 10, 13 - (0 if side else leg)), fill=(50, 44, 60))
    d.rectangle((4, 6, 11, 11), fill=body)
    d.ellipse((4, 0, 11, 7), fill=(240, 200, 160))
    if direction == 0:
        d.ellipse((4, 0, 11, 7), fill=hair)
    else:
        d.chord((4, 0, 11, 7), 180, 360, fill=hair)
        for e in {1: [(9, 4)], 2: [(6, 4), (9, 4)], 3: [(6, 4)]}[direction]:
            d.point(e, fill=(30, 30, 40))
    return img


def draw_sprites() -> None:
    strip = Image.new("RGBA", (64 * 3, 64), (0, 0, 0, 0))
    for i, f in enumerate((slime(), bat(), golem())):
        strip.paste(f, (i * 64, 0))
    strip.save(ART / "enemies.png")
    backs = Image.new("RGBA", (64, 32), (0, 0, 0, 0))
    backs.paste(hero_back((60, 110, 210), (90, 54, 30), False), (0, 0))
    backs.paste(hero_back((170, 70, 150), (230, 200, 90), True), (32, 0))
    backs.save(ART / "party.png")
    walk = Image.new("RGBA", (16 * 8, 16), (0, 0, 0, 0))
    for direction in range(4):
        for step in range(2):
            walk.paste(walker(direction, step), ((direction * 2 + step) * 16, 0))
    walk.save(ART / "walker.png")


def convert() -> None:
    py, png = sys.executable, str(ROOT / "tools" / "png2asset.py")
    ASSETS.mkdir(exist_ok=True)
    for f in ASSETS.glob("*"):
        f.unlink()
    for name, aid in (("field.png", "FIELD"), ("backdrop.png", "BACKDROP")):
        subprocess.run([py, png, str(ART / name), str(ASSETS), aid, "--tiles", "--palette", "WORLD"], check=True)
    for name, aid, n in (("enemies.png", "ENEMIES", 3), ("party.png", "PARTY", 2), ("walker.png", "WALKER", 8)):
        subprocess.run([py, png, str(ART / name), str(ASSETS), aid, "--indexed", "--frames", str(n), "--palette", "OBJ"], check=True)


def main() -> None:
    ART.mkdir(exist_ok=True)
    draw_field()
    draw_backdrop()
    draw_sprites()
    convert()


if __name__ == "__main__":
    main()
