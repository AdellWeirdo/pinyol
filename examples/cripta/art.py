# /// script
# requires-python = ">=3.10"
# dependencies = ["pillow>=10.1"]
# ///
"""The art of Cripta, drawn by code: a tileset of 16 x 16, eight rooms as Tiled maps, the sprites.

    uv run examples/cripta/art.py --draw    # the plans below -> art/*.tmx, the tileset and the sprites, then the import
    uv run examples/cripta/art.py           # only the import: art/*.tmx (changed in Tiled) -> assets/ and room_*.lua

Each room is a Tiled map of its own (art/<id>.tmx, a layer "suelo" and an object layer), imported with tools/tiled2asset.py into
assets/ROOM_<ID>_SUELO and room_<id>.lua. A room's place in the castle is two map properties, mx and my, in screens of 15 x 10 tiles:
a room is one screen or more, and walking off its edge goes into whichever room holds that place.

Plan legend: # wall, = platform (held from above), x cracked wall (the dash breaks it), . air; things: P start, S statue (saves),
A wings (double jump), R gust (dash), H heart, b bat, s slime, J the boss.
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
SW, SH = 15, 10  # a screen, in tiles

STONE, STONE_D, STONE_L, MORTAR = (92, 84, 120), (64, 58, 90), (128, 120, 158), (44, 40, 64)
WOOD, WOOD_D = (150, 104, 60), (104, 70, 40)
CRACK = (30, 26, 44)
INK = (24, 20, 34)

ROOMS = {
    "entrada": ((0, 1), [
        "###############",
        "#.............#",
        "#.............#",
        "#.............#",
        "#.............#",
        "#..............",
        "#..............",
        "#..............",
        "#..P....S......",
        "###############",
    ]),
    "pasillo": ((1, 1), [
        "##############################",
        "#............................#",
        "#............................#",
        "#.........====.......b.......#",
        "#............................#",
        "..............................",
        "..............................",
        "..............................",
        "......................s.......",
        "######...#####################",
    ]),
    "tesoro": ((1, 2), [
        "######...######",
        "#..........#..#",
        "#...===....#..#",
        "#......====#..#",
        "#..........#..#",
        "#..........#..#",
        "#..====....x..#",
        "#..........x..#",
        "#..........x.H#",
        "###############",
    ]),
    "pozo": ((3, 0), [
        "###############",
        "#.............#",
        "#..............",
        "#..............",
        "#..............",
        "#.....=====####",
        "#.............#",
        "#.............#",
        "#.............#",
        "#.............#",
        "#.......====..#",
        "#.............#",
        "#.............#",
        "#..====.......#",
        "#.............#",
        "...............",
        "........====...",
        "...............",
        "...............",
        "###############",
    ]),
    "cripta": ((4, 1), [
        "###############",
        "#.............#",
        "#.............#",
        "#.............#",
        "#.............#",
        "..............#",
        "..............#",
        "..............#",
        "...s.......A..#",
        "###############",
    ]),
    "mirador": ((4, 0), [
        "##############################",
        "#.........................#..#",
        "..........................#..#",
        "..........................#..#",
        "..........................#..#",
        "#####.................b...x...",
        "#.........................x...",
        "#....====.................x...",
        "#....S.........R..........x...",
        "##############################",
    ]),
    "torre": ((6, 0), [
        "###############",
        "#.............#",
        "#.............#",
        "#.............#",
        "#.............#",
        "..............#",
        "..............#",
        "..............#",
        "..............#",
        "#####.........#",
        "#.............#",
        "#.....====....#",
        "#..b..........#",
        "#.............#",
        "#.........====#",
        "#..............",
        "#.....====.....",
        "#..............",
        "#..............",
        "###############",
    ]),
    "jefe": ((7, 1), [
        "##############################",
        "#............................#",
        "#............................#",
        "#............................#",
        "#............................#",
        ".............................#",
        ".............................#",
        ".............................#",
        "......................J......#",
        "##############################",
    ]),
}

TILES = {"#": 1, "=": 2, "x": 3}  # Tiled's ids (firstgid 1): wall, platform, cracked wall
THINGS = {"P": "start", "S": "statue", "A": "wings", "R": "gust", "H": "heart", "b": "bat", "s": "slime", "J": "boss"}


def tile(kind: str) -> Image.Image:
    img = Image.new("RGBA", (T, T), (0, 0, 0, 0))
    d = ImageDraw.Draw(img)
    if kind in ("#", "x"):
        d.rectangle((0, 0, 15, 15), fill=STONE)
        for y in (0, 8):  # bricks, every other row half a brick along
            d.line((0, y + 7, 15, y + 7), fill=MORTAR)
            off = 0 if y == 0 else 8
            d.line((off, y, off, y + 7), fill=MORTAR)
            d.line((off + 1, y, off + 6, y), fill=STONE_L)
        d.point((4, 3), fill=STONE_D), d.point((11, 12), fill=STONE_D), d.point((13, 4), fill=STONE_D)
        if kind == "x":
            d.line((3, 2, 7, 7, 5, 11, 9, 14), fill=CRACK, width=1)
            d.line((7, 7, 12, 6), fill=CRACK)
            d.line((10, 2, 12, 6, 11, 9), fill=CRACK)
    elif kind == "=":
        d.rectangle((0, 0, 15, 4), fill=WOOD)
        d.line((0, 4, 15, 4), fill=WOOD_D)
        for x in (3, 12):
            d.line((x, 5, x, 9), fill=WOOD_D)
    return img


def draw_tileset() -> None:
    sheet = Image.new("RGBA", (3 * T, T), (0, 0, 0, 0))
    for i, k in enumerate(("#", "=", "x")):
        sheet.paste(tile(k), (i * T, 0))
    sheet.save(ART / "tiles.png")
    (ART / "tiles.tsx").write_text("""<?xml version="1.0" encoding="UTF-8"?>
<tileset version="1.10" name="cripta" tilewidth="16" tileheight="16" tilecount="3" columns="3">
 <image source="tiles.png" width="48" height="16"/>
 <tile id="0"><properties><property name="solid" type="bool" value="true"/></properties></tile>
 <tile id="1"><properties><property name="platform" type="bool" value="true"/></properties></tile>
 <tile id="2"><properties><property name="solid" type="bool" value="true"/><property name="cracked" type="bool" value="true"/></properties></tile>
</tileset>
""")


def draw_room(rid: str, pos: tuple[int, int], rows: list[str]) -> None:
    h, w = len(rows), len(rows[0])
    assert w % SW == 0 and h % SH == 0 and all(len(r) == w for r in rows), rid
    grid = ",\n".join(",".join(str(TILES.get(c, 0)) for c in row) for row in rows)
    objs, n = [], 1
    for y, row in enumerate(rows):
        for x, c in enumerate(row):
            if c in THINGS:
                objs.append(f'<object id="{n}" name="{THINGS[c]}" type="{THINGS[c]}" x="{x * T + T // 2}" y="{(y + 1) * T}"/>')
                n += 1
    (ART / f"{rid}.tmx").write_text(f"""<?xml version="1.0" encoding="UTF-8"?>
<map version="1.10" orientation="orthogonal" renderorder="right-down" width="{w}" height="{h}" tilewidth="{T}" tileheight="{T}"
     infinite="0" nextlayerid="3" nextobjectid="{n}">
 <properties>
  <property name="mx" type="int" value="{pos[0]}"/>
  <property name="my" type="int" value="{pos[1]}"/>
 </properties>
 <tileset firstgid="1" source="tiles.tsx"/>
 <layer id="1" name="suelo" width="{w}" height="{h}">
  <data encoding="csv">
{grid}
</data>
 </layer>
 <objectgroup id="2" name="cosas">
  {chr(10).join("  " + o for o in objs).strip()}
 </objectgroup>
</map>
""")


def outline(img: Image.Image) -> Image.Image:
    out = Image.new("RGBA", img.size, (0, 0, 0, 0))
    px, o = img.load(), out.load()
    for y in range(img.height):
        for x in range(img.width):
            if px[x, y][3] < 128:
                for dx, dy in ((1, 0), (-1, 0), (0, 1), (0, -1)):
                    nx, ny = x + dx, y + dy
                    if 0 <= nx < img.width and 0 <= ny < img.height and px[nx, ny][3] >= 128:
                        o[x, y] = INK + (255,)
                        break
    out.alpha_composite(img)
    return out


def hero(frame: str) -> Image.Image:
    img = Image.new("RGBA", (16, 16), (0, 0, 0, 0))
    d = ImageDraw.Draw(img)
    cloak, skin, hair, boot = (180, 60, 70), (240, 200, 160), (60, 40, 60), (50, 40, 60)
    lean = 1 if frame == "dash" else 0
    if frame in ("run1", "run2"):
        a, b = (1, -1) if frame == "run1" else (-1, 1)
        d.rectangle((5 + a, 12, 6 + a, 15), fill=boot), d.rectangle((9 + b, 12, 10 + b, 15), fill=boot)
    elif frame == "jump":
        d.rectangle((5, 11, 6, 13), fill=boot), d.rectangle((9, 12, 10, 14), fill=boot)
    else:
        d.rectangle((5, 12, 6, 15), fill=boot), d.rectangle((9, 12, 10, 15), fill=boot)
    d.polygon([(4 + lean, 6), (11 + lean, 6), (13 + lean, 13), (2 + lean, 13)], fill=cloak)
    d.ellipse((5 + lean, 0, 11 + lean, 6), fill=skin)
    d.chord((5 + lean, 0, 11 + lean, 6), 180, 360, fill=hair)
    d.point((9 + lean, 3), fill=INK)
    if frame == "attack":
        d.line((11, 8, 15, 8), fill=(230, 230, 240))
    if frame == "dash":
        d.line((0, 9, 3, 9), fill=(250, 220, 120)), d.line((0, 11, 2, 11), fill=(250, 220, 120))
    return outline(img)


def creature(kind: str, frame: int) -> Image.Image:
    img = Image.new("RGBA", (16, 16), (0, 0, 0, 0))
    d = ImageDraw.Draw(img)
    if kind == "bat":
        up = frame == 0
        body = (110, 70, 150)
        for sx in (-1, 1):
            tip = 1 if up else 11
            d.polygon([(8 + sx * 2, 7), (8 + sx * 7, tip), (8 + sx * 7, 9)], fill=body)
        d.ellipse((5, 5, 11, 11), fill=(86, 52, 120))
        d.point((7, 7), fill=(250, 220, 80)), d.point((9, 7), fill=(250, 220, 80))
    elif kind == "slime":
        squash = 1 if frame else 0
        d.ellipse((2, 6 + squash, 13, 15), fill=(80, 180, 100))
        d.ellipse((4, 7 + squash, 8, 10 + squash), fill=(170, 240, 180))
        d.point((6, 11), fill=INK), d.point((10, 11), fill=INK)
    elif kind == "wings":
        for sx, c in ((-1, (230, 240, 255)), (1, (200, 220, 250))):
            d.polygon([(8, 9), (8 + sx * 7, 2 + frame), (8 + sx * 6, 12)], fill=c)
        d.ellipse((6, 7, 10, 11), fill=(250, 220, 120))
    elif kind == "gust":
        for i, y in enumerate((4, 8, 12)):
            d.arc((1 + i, y - 3, 14 - i, y + 3), 200 + frame * 20, 340 + frame * 20, fill=(140, 230, 250))
    elif kind == "heart":
        c = (240, 70, 90) if frame == 0 else (255, 110, 130)
        d.ellipse((2, 3, 8, 9), fill=c), d.ellipse((7, 3, 13, 9), fill=c)
        d.polygon([(2, 7), (13, 7), (8, 14)], fill=c)
    elif kind == "statue":
        lit = (250, 210, 110) if frame else (120, 110, 150)
        d.rectangle((4, 12, 11, 15), fill=(80, 74, 104))
        d.polygon([(5, 12), (10, 12), (9, 4), (6, 4)], fill=(150, 142, 176))
        d.ellipse((5, 0, 10, 5), fill=(150, 142, 176))
        d.ellipse((6, 6, 9, 9), fill=lit)
    elif kind == "slash":
        d.arc((-6, 0, 14, 16), 300 + frame * 10, 60 + frame * 10, fill=(240, 240, 255), width=2)
    return outline(img)


def boss(frame: int) -> Image.Image:
    img = Image.new("RGBA", (48, 48), (0, 0, 0, 0))
    d = ImageDraw.Draw(img)
    stone, dark = (120, 112, 140), (80, 74, 100)
    wing = 6 if frame else 14
    for sx in (-1, 1):
        d.polygon([(24 + sx * 8, 18), (24 + sx * 23, wing), (24 + sx * 22, 30), (24 + sx * 10, 30)], fill=dark)
    d.ellipse((12, 14, 36, 44), fill=stone)
    d.ellipse((14, 2, 34, 22), fill=stone)
    d.polygon([(16, 6), (12, -2), (20, 4)], fill=dark), d.polygon([(32, 6), (36, -2), (28, 4)], fill=dark)
    d.rectangle((18, 10, 21, 13), fill=(250, 90, 60)), d.rectangle((27, 10, 30, 13), fill=(250, 90, 60))
    d.polygon([(20, 17), (28, 17), (24, 21)], fill=dark)
    d.rectangle((14, 42, 20, 47), fill=dark), d.rectangle((28, 42, 34, 47), fill=dark)
    return outline(img)


def far() -> None:
    """The castle's far wall, behind the rooms: a 32 x 32 pattern repeated (BG3)."""
    img = Image.new("RGBA", (32, 32), (28, 24, 44, 255))
    d = ImageDraw.Draw(img)
    for y in (0, 16):
        d.line((0, y + 15, 31, y + 15), fill=(22, 18, 36))
        off = 0 if y == 0 else 16
        d.line((off, y, off, y + 15), fill=(22, 18, 36))
    d.ellipse((20, 4, 26, 12), fill=(36, 32, 58))  # a window's glow, now and then
    img.save(ART / "far.png")


def draw_sprites() -> None:
    frames = ("idle", "run1", "run2", "jump", "attack", "dash")
    sheet = Image.new("RGBA", (16 * len(frames), 16), (0, 0, 0, 0))
    for i, f in enumerate(frames):
        sheet.paste(hero(f), (i * 16, 0))
    sheet.save(ART / "hero.png")
    kinds = ("bat", "slime", "wings", "gust", "heart", "statue", "slash")
    sheet = Image.new("RGBA", (16 * 2 * len(kinds), 16), (0, 0, 0, 0))
    for i, k in enumerate(kinds):
        for f in range(2):
            sheet.paste(creature(k, f), ((i * 2 + f) * 16, 0))
    sheet.save(ART / "things.png")
    sheet = Image.new("RGBA", (96, 48), (0, 0, 0, 0))
    for f in range(2):
        sheet.paste(boss(f), (f * 48, 0))
    sheet.save(ART / "boss.png")


def convert() -> None:
    py = sys.executable
    for f in ASSETS.glob("*"):
        f.unlink()
    for rid in ROOMS:
        subprocess.run([py, str(ROOT / "tools" / "tiled2asset.py"), str(ART / f"{rid}.tmx"), str(HERE), f"ROOM_{rid.upper()}"],
                       check=True, capture_output=True)
    png = str(ROOT / "tools" / "png2asset.py")
    subprocess.run([py, png, str(ART / "far.png"), str(ASSETS), "FAR", "--tiles", "--palette", "WORLD"], check=True)
    for name, aid, n in (("hero.png", "HERO", 6), ("things.png", "THINGS", 14), ("boss.png", "BOSS", 2)):
        subprocess.run([py, png, str(ART / name), str(ASSETS), aid, "--indexed", "--frames", str(n), "--palette", "OBJ"], check=True)
    lines = ["-- made by art.py: the rooms of the castle (each room_<id>.lua is tiled2asset's import of art/<id>.tmx)", "return {"]
    lines += [f'  "{rid}",' for rid in ROOMS] + ["}"]
    (HERE / "rooms_list.lua").write_text("\n".join(lines) + "\n")


def main() -> None:
    ART.mkdir(exist_ok=True)
    ASSETS.mkdir(exist_ok=True)
    if "--draw" in sys.argv:
        draw_tileset()
        for rid, (pos, rows) in ROOMS.items():
            draw_room(rid, pos, rows)
        far()
        draw_sprites()
    convert()


if __name__ == "__main__":
    main()
