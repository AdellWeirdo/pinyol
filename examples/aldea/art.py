# /// script
# requires-python = ">=3.10"
# dependencies = ["pillow>=10.1", "fonttools>=4"]
# ///
"""The village's art: a 16x16 tileset, the map as a Tiled map, the characters and things, all drawn by code.

    uv run examples/aldea/art.py           # art/aldea.tmx and the PNGs -> assets/ and aldea.lua
    uv run examples/aldea/art.py --draw    # first draw art/ (the tileset, the map, the sprites), then convert

art/aldea.tmx opens in Tiled (mapeditor.org): change the village there and run this without --draw to import it
again (tools/tiled2asset.py). --draw would write the map anew from the plan below.

Its own look, made every time: blackletter (Jacquarda Bastarda 9, Jacquard 12) from pinyol's font library, a
parchment (FR_PERGAMI) and a wooden sign (FR_MADERA) for frame().
"""
from __future__ import annotations

import subprocess
import sys
from pathlib import Path

from PIL import Image, ImageDraw

HERE = Path(__file__).resolve().parent
ROOT = HERE.parents[1]
ART, ASSETS = HERE / "art", HERE / "assets"
T = 16  # tile size

GRASS, GRASS_D, GRASS_L = (104, 184, 64), (84, 160, 52), (140, 208, 88)
PATH, PATH_D = (222, 186, 128), (196, 156, 100)
WATER, WATER_D, WATER_L = (72, 140, 228), (56, 112, 200), (168, 210, 250)
LEAF, LEAF_D, LEAF_L, TRUNK = (48, 128, 64), (32, 96, 52), (88, 168, 80), (116, 78, 44)
ROOF, ROOF_D, WALL, WALL_D = (196, 76, 60), (150, 52, 44), (240, 226, 190), (204, 188, 150)
WOOD, WOOD_D, GLASS, ROCK, ROCK_D = (170, 116, 66), (122, 80, 42), (126, 190, 236), (160, 160, 172), (112, 112, 128)
SAND, FLOWERS = (238, 216, 154), [(250, 240, 120), (250, 140, 170), (255, 255, 255)]

# the tileset: name -> index, in the order drawn; "solid" ones stop the player (a tile property in Tiled)
NAMES = ["grass", "flowers", "path", "water", "trunk", "crown", "roof_l", "roof", "roof_r", "wall", "door", "window",
         "fence", "bridge", "rock", "sand", "tallgrass", "crown_low"]
SOLID = {"water", "trunk", "roof_l", "roof", "roof_r", "wall", "door", "window", "fence", "rock"}
ID = {n: i for i, n in enumerate(NAMES)}


def tile(name: str) -> Image.Image:
    t = Image.new("RGBA", (T, T), (0, 0, 0, 0))
    d = ImageDraw.Draw(t)

    def grass_base() -> None:
        d.rectangle((0, 0, 15, 15), fill=GRASS)
        for x, y in ((2, 3), (11, 2), (6, 9), (13, 12), (3, 13)):
            d.line((x, y, x, y + 1), fill=GRASS_D)
        d.point((8, 5), fill=GRASS_L)

    if name in ("grass", "flowers", "tallgrass", "trunk", "fence", "rock"):
        grass_base()
    if name == "flowers":
        for (x, y), c in zip(((3, 4), (10, 7), (5, 11), (12, 13)), FLOWERS * 2):
            d.rectangle((x, y, x + 1, y + 1), fill=c)
            d.point((x, y + 2), fill=GRASS_D)
    elif name == "tallgrass":
        for x in range(1, 15, 3):
            d.line((x, 15, x + 1, 8), fill=GRASS_D)
            d.line((x + 1, 15, x + 2, 10), fill=GRASS_L)
    elif name == "path":
        d.rectangle((0, 0, 15, 15), fill=PATH)
        for x, y in ((3, 2), (12, 6), (6, 12), (9, 9)):
            d.point((x, y), fill=PATH_D)
    elif name == "sand":
        d.rectangle((0, 0, 15, 15), fill=SAND)
        d.point((4, 5), fill=PATH_D)
        d.point((11, 11), fill=PATH_D)
    elif name == "water":
        d.rectangle((0, 0, 15, 15), fill=WATER)
        d.line((2, 4, 6, 4), fill=WATER_L)
        d.line((9, 10, 13, 10), fill=WATER_L)
        d.line((0, 15, 15, 15), fill=WATER_D)
    elif name == "bridge":
        d.rectangle((0, 0, 15, 15), fill=WOOD)
        for y in (3, 7, 11, 15):
            d.line((0, y, 15, y), fill=WOOD_D)
        d.line((0, 0, 0, 15), fill=WOOD_D)
        d.line((15, 0, 15, 15), fill=WOOD_D)
    elif name == "trunk":  # the lower half of a tree: crown edge and trunk (the top half is "crown", over the player)
        d.ellipse((0, -10, 15, 9), fill=LEAF)
        d.ellipse((3, -8, 10, 3), fill=LEAF_L)
        d.arc((0, -10, 15, 9), 20, 160, fill=LEAF_D)
        d.rectangle((6, 8, 9, 14), fill=TRUNK)
        d.line((5, 15, 10, 15), fill=(60, 110, 40))
    elif name in ("crown", "crown_low"):
        d.ellipse((0, 4 if name == "crown" else 0, 15, 25), fill=LEAF)
        d.ellipse((3, 6 if name == "crown" else 2, 9, 12), fill=LEAF_L)
        d.point((11, 10), fill=LEAF_D)
        d.point((5, 13), fill=LEAF_D)
    elif name.startswith("roof"):
        d.rectangle((0, 0, 15, 15), fill=ROOF)
        for y in range(1, 16, 4):
            d.line((0, y, 15, y), fill=ROOF_D)
            for x in range(2 if y % 8 == 1 else 0, 16, 5):
                d.point((x, y + 2), fill=ROOF_D)
        if name == "roof_l":
            d.line((0, 0, 0, 15), fill=ROOF_D)
        if name == "roof_r":
            d.line((15, 0, 15, 15), fill=ROOF_D)
    elif name in ("wall", "door", "window"):
        d.rectangle((0, 0, 15, 15), fill=WALL)
        d.line((0, 0, 15, 0), fill=ROOF_D)
        d.line((0, 15, 15, 15), fill=WALL_D)
        if name == "door":
            d.rectangle((4, 4, 11, 15), fill=WOOD_D)
            d.rectangle((5, 5, 10, 15), fill=WOOD)
            d.point((9, 10), fill=(250, 220, 120))
        elif name == "window":
            d.rectangle((3, 4, 12, 11), fill=WOOD_D)
            d.rectangle((4, 5, 11, 10), fill=GLASS)
            d.line((7, 5, 7, 10), fill=WOOD_D)
    elif name == "fence":
        d.rectangle((0, 6, 15, 7), fill=WOOD)
        d.rectangle((0, 11, 15, 12), fill=WOOD)
        for x in (2, 13):
            d.rectangle((x, 3, x + 1, 14), fill=WOOD_D)
    elif name == "rock":
        d.ellipse((2, 5, 14, 15), fill=ROCK_D)
        d.ellipse((2, 4, 13, 13), fill=ROCK)
        d.point((5, 7), fill=(220, 220, 230))
    return t


def draw_tileset() -> None:
    sheet = Image.new("RGBA", (8 * T, ((len(NAMES) + 7) // 8) * T), (0, 0, 0, 0))
    for i, n in enumerate(NAMES):
        sheet.paste(tile(n), ((i % 8) * T, (i // 8) * T))
    sheet.save(ART / "tiles.png")
    props = "".join(f' <tile id="{ID[n]}"><properties><property name="solid" type="bool" value="true"/></properties>'
                    f'</tile>\n' for n in NAMES if n in SOLID)
    (ART / "tiles.tsx").write_text(f"""<?xml version="1.0" encoding="UTF-8"?>
<tileset version="1.10" name="aldea" tilewidth="{T}" tileheight="{T}" tilecount="{len(NAMES)}" columns="8">
 <image source="tiles.png" width="{sheet.width}" height="{sheet.height}"/>
{props}</tileset>
""")


W, H = 40, 30


def plan() -> tuple[list[list[str]], list[list[str]], list[list[str]], list[str]]:
    """The village: ground, things that stand on it, what is drawn over the player; and the map's objects."""
    ground = [["grass"] * W for _ in range(H)]
    things = [[""] * W for _ in range(H)]
    over = [[""] * W for _ in range(H)]

    def tree(x: int, y: int) -> None:
        things[y][x] = "trunk"
        if y > 0:
            over[y - 1][x] = "crown"

    for x in range(W):  # a forest all around
        for y in (0, 1, H - 1):
            tree(x, y)
    for y in range(H):
        for x in (0, W - 1):
            tree(x, y)
    for x in range(1, W - 1):  # a path from west to east, and one going north to the houses
        ground[18][x] = ground[19][x] = "path"
    for y in range(6, 18):
        ground[y][9] = ground[y][10] = "path"
    for y in range(2, H - 1):  # the river, with a bridge where the path crosses it
        for x in (26, 27):
            ground[y][x] = "water"
        ground[y][25] = ground[y][28] = "sand"
    for x in (25, 26, 27, 28):
        ground[18][x] = ground[19][x] = "bridge"

    def house(x: int, y: int, w: int = 5) -> None:
        for i in range(w):
            things[y][x + i] = things[y + 1][x + i] = "roof_l" if i == 0 else "roof_r" if i == w - 1 else "roof"
            things[y + 2][x + i] = "door" if i == w // 2 else "window" if i in (1, w - 2) else "wall"
        for i in range(w):
            ground[y + 3][x + i] = "path" if i == w // 2 else ground[y + 3][x + i]

    house(4, 3)
    house(12, 3)
    house(4, 11)
    for x in range(6, 15):  # paths from the doors to the one going north
        ground[6][x] = "path"
    for y in range(14, 18):
        ground[y][6] = "path"
    for x in range(6, 10):
        ground[14][x] = "path"
    for x, y in ((14, 11), (17, 13), (19, 9), (21, 15), (16, 23), (8, 25), (21, 25), (12, 22), (31, 23), (35, 25)):
        tree(x, y)
    for x in range(30, 38):  # the meadow with the chest, fenced on its south side, open by the path
        if x not in (33, 34):
            things[12][x] = "fence"
    for x, y in ((31, 5), (36, 7), (33, 9), (30, 9), (35, 4), (5, 22), (14, 26), (19, 21), (3, 16), (22, 4)):
        ground[y][x] = "flowers"
    for x, y in ((24, 23), (29, 26), (22, 9), (36, 21)):
        things[y][x] = "rock"
    for x, y in ((18, 24), (19, 24), (20, 24), (32, 21), (33, 21), (11, 27), (12, 27)):
        ground[y][x] = "tallgrass"
    for y in range(12, 18):
        ground[y][33] = ground[y][34] = "path"
    objects = [
        '<object id="1" name="start" type="spawn" x="128" y="304"/>',
        '<object id="2" name="Abuela Rosa" type="npc" x="120" y="96"><properties>'
        '<property name="who" value="abuela"/><property name="look" type="int" value="1"/></properties></object>',
        '<object id="3" name="Lucio" type="npc" x="392" y="208"><properties>'
        '<property name="who" value="pescador"/><property name="look" type="int" value="2"/></properties></object>',
        '<object id="4" name="Nora" type="npc" x="256" y="256"><properties>'
        '<property name="who" value="nina"/><property name="look" type="int" value="3"/>'
        '<property name="wander" type="bool" value="true"/></properties></object>',
        '<object id="5" name="cofre" type="chest" x="536" y="96"/>',
    ]
    return ground, things, over, objects


def draw_map() -> None:
    ground, things, over, objects = plan()

    def csv(grid: list[list[str]]) -> str:
        return ",\n".join(",".join(str(ID[c] + 1) if c else "0" for c in row) for row in grid)

    layers = "".join(f""" <layer id="{i + 1}" name="{name}" width="{W}" height="{H}">
  <data encoding="csv">
{csv(grid)}
</data>
 </layer>
""" for i, (name, grid) in enumerate((("suelo", ground), ("objetos", things), ("alto", over))))
    (ART / "aldea.tmx").write_text(f"""<?xml version="1.0" encoding="UTF-8"?>
<map version="1.10" orientation="orthogonal" renderorder="right-down" width="{W}" height="{H}" tilewidth="{T}"
     tileheight="{T}" infinite="0" nextlayerid="5" nextobjectid="6">
 <tileset firstgid="1" source="tiles.tsx"/>
{layers} <objectgroup id="4" name="cosas">
  {chr(10).join("  " + o for o in objects).strip()}
 </objectgroup>
</map>
""")


def person(body: tuple, hair: tuple, direction: int, step: int, skirt: bool = False, hat: tuple | None = None):
    img = Image.new("RGBA", (16, 16), (0, 0, 0, 0))
    d = ImageDraw.Draw(img)
    d.ellipse((3, 13, 12, 15), fill=(0, 0, 0, 80))
    leg = (1, -1)[step]
    side = direction % 2 == 1
    d.rectangle((5, 10, 6, 13 + (0 if side else leg)), fill=(50, 44, 60))
    d.rectangle((9, 10, 10, 13 - (0 if side else leg)), fill=(50, 44, 60))
    if skirt:
        d.polygon([(4, 7), (11, 7), (13, 13), (2, 13)], fill=body)
    else:
        d.rectangle((4, 6, 11, 11), fill=body)
    d.ellipse((4, 0, 11, 7), fill=(240, 200, 160))
    if direction == 0:
        d.ellipse((4, 0, 11, 7), fill=hair)
    else:
        d.chord((4, 0, 11, 7), 180, 360, fill=hair)
        eyes = {1: [(9, 4)], 2: [(6, 4), (9, 4)], 3: [(6, 4)]}[direction]
        for e in eyes:
            d.point(e, fill=(30, 30, 40))
    if hat:
        d.rectangle((3, 0, 12, 2), fill=hat)
        d.rectangle((5, -1, 10, 0), fill=hat)
    return img


def draw_people() -> None:
    people = [((60, 110, 210), (90, 54, 30), False, None),         # you
              ((150, 90, 180), (200, 200, 210), True, None),       # abuela Rosa
              ((70, 150, 90), (60, 40, 30), False, (210, 190, 120)),  # Lucio, the fisherman, with his hat
              ((220, 70, 80), (250, 210, 90), True, None)]         # Nora
    sheet = Image.new("RGBA", (16 * 8 * len(people), 16), (0, 0, 0, 0))
    for p, (body, hair, skirt, hat) in enumerate(people):
        for direction in range(4):
            for step in range(2):
                sheet.paste(person(body, hair, direction, step, skirt, hat), ((p * 8 + direction * 2 + step) * 16, 0))
    sheet.save(ART / "people.png")


def draw_things() -> None:  # 16x16: the chest closed, open, and the key
    sheet = Image.new("RGBA", (48, 16), (0, 0, 0, 0))
    for f in range(2):
        d = ImageDraw.Draw(sheet)
        x = f * 16
        d.ellipse((x + 1, 12, x + 14, 15), fill=(0, 0, 0, 80))
        d.rectangle((x + 2, 7, x + 13, 14), fill=WOOD)
        d.rectangle((x + 2, 7, x + 13, 8), fill=WOOD_D)
        if f == 0:
            d.rectangle((x + 2, 3, x + 13, 7), fill=WOOD)
            d.rectangle((x + 7, 6, x + 8, 9), fill=(250, 210, 80))
        else:
            d.rectangle((x + 2, 1, x + 13, 4), fill=WOOD_D)
            d.rectangle((x + 4, 7, x + 11, 9), fill=(250, 230, 120))
    d = ImageDraw.Draw(sheet)
    d.ellipse((34, 4, 40, 10), outline=(250, 210, 80), width=2)
    d.rectangle((40, 6, 46, 8), fill=(250, 210, 80))
    d.rectangle((44, 8, 45, 10), fill=(250, 210, 80))
    sheet.save(ART / "things.png")


def look() -> None:
    sys.path.insert(0, str(ROOT / "tools"))
    import font2fnt
    for name, src, scale in (("bastarda", "jacquardabastarda9", 2), ("gotica", "jacquard12", 1)):
        font2fnt.build(src, str(HERE / "fonts" / f"{name}.fnt"), None, scale)
    im = Image.new("RGBA", (24, 24), (0, 0, 0, 0))  # parchment: rounded corners, brown ink, warm paper
    d = ImageDraw.Draw(im)
    d.rounded_rectangle((0, 0, 23, 23), radius=6, fill=(92, 58, 30, 255))
    d.rounded_rectangle((1, 1, 22, 22), radius=5, fill=(236, 214, 160, 255))
    d.rounded_rectangle((3, 3, 20, 20), radius=3, outline=(176, 128, 72, 255))
    im.save(ART / "fr_pergami.png")
    im = Image.new("RGBA", (24, 24), (0, 0, 0, 0))  # a wooden sign: dark rim, lit and shaded sides, nails, paper
    d = ImageDraw.Draw(im)
    d.rectangle((0, 0, 23, 23), fill=(58, 34, 20, 255))
    d.rectangle((1, 1, 22, 22), fill=(150, 96, 52, 255))
    d.line((1, 1, 22, 1), fill=(196, 140, 84, 255))
    d.line((1, 1, 1, 22), fill=(196, 140, 84, 255))
    d.line((2, 22, 22, 22), fill=(102, 62, 32, 255))
    d.line((22, 2, 22, 22), fill=(102, 62, 32, 255))
    d.rectangle((5, 5, 18, 18), fill=(70, 40, 22, 255))
    d.rectangle((6, 6, 17, 17), fill=(240, 226, 196, 255))
    for x, y in ((3, 3), (19, 3), (3, 19), (19, 19)):
        d.rectangle((x, y, x + 1, y + 1), fill=(220, 210, 180, 255))
    im.save(ART / "fr_madera.png")


def convert() -> None:
    py = sys.executable
    for f in ASSETS.glob("*.pal"):
        f.unlink()
    subprocess.run([py, str(ROOT / "tools" / "tiled2asset.py"), str(ART / "aldea.tmx"), str(HERE), "ALDEA"], check=True)
    for png, aid, n in (("people.png", "PEOPLE", 32), ("things.png", "THINGS", 3)):
        subprocess.run([py, str(ROOT / "tools" / "png2asset.py"), str(ART / png), str(ASSETS), aid, "--indexed",
                        "--frames", str(n), "--palette", "OBJ"], check=True)
    for png, aid in (("fr_pergami.png", "FR_PERGAMI"), ("fr_madera.png", "FR_MADERA")):
        subprocess.run([py, str(ROOT / "tools" / "png2asset.py"), str(ART / png), str(ASSETS), aid], check=True)


def main() -> None:
    ASSETS.mkdir(exist_ok=True)
    if "--draw" in sys.argv:
        ART.mkdir(exist_ok=True)
        draw_tileset()
        draw_map()
        draw_people()
        draw_things()
    look()
    convert()


if __name__ == "__main__":
    main()
