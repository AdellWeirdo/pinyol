# /// script
# requires-python = ">=3.10"
# dependencies = ["pillow>=10.1", "fonttools>=4"]
# ///
"""The Game Boy-style platformer's art, all drawn here by code in four tones, as that console had them.

    uv run examples/bolsillo/art.py      # art/*.png and assets/

Every picture is drawn with tone 0 (the lightest) to tone 3 (the darkest). WORLD.pal and OBJ.pal are written first
with the four tones in that order, so png2asset keeps each tone at the same index (1 to 4): the game changes the
four colours (pal) and the whole picture changes palette, as a Game Boy Color did with an old game. The level comes
from level.lua; the console around the screen (BORDER) is a picture at the screen's full resolution.
"""
from __future__ import annotations

import shutil
import subprocess
import sys
from pathlib import Path

from PIL import Image, ImageDraw

HERE = Path(__file__).resolve().parent
ROOT = HERE.parents[1]
ART, ASSETS = HERE / "art", HERE / "assets"
TONES = [(155, 188, 15), (139, 172, 15), (48, 98, 48), (15, 56, 15)]  # the first palette: lightest to darkest

TILES = {  # 8x8, by the level's characters; "." is see-through: the backdrop (tone 0) shows
    "top": ["33333333", "21212121", "12121212", "22222222", "21222122", "22222222", "22122212", "22222222"],
    "#": ["22222222", "21222122", "22222222", "22122212", "22222222", "21222122", "22222222", "22122212"],
    "B": ["33333333", "11131111", "11131111", "33333333", "13111113", "13111113", "33333333", "11131111"],
    "=": ["33333333", "21111112", "33333333", "..3..3..", "..3..3..", "........", "........", "........"],
    "^": ["........", "...33...", "..3223..", "..3223..", ".322223.", ".322223.", "32222223", "33333333"],
    "?": ["33333333", "31111113", "31333113", "31113113", "31133113", "31111113", "31131113", "33333333"],
    "T": ["...11...", "..1221..", ".122221.", "12222221", "12222221", ".122221.", "...33...", "...33..."],
    "c": ["........", "...111..", "..1...1.", ".1.....1", "1.......", "1......1", ".111111.", "........"],
    "|": ["...33...", "...33...", "...33...", "...33...", "...33...", "...33...", "...33...", "...33..."],
}

HERO = """
................|................|................|................|................
.....333333.....|.....333333.....|.....333333.....|.....333333.....|.....333333.....
...3322222233...|...3322222233...|...3322222233...|...3322222233...|...3322222233...
..322002200223..|..322002200223..|..322002200223..|..322002200223..|..322002200223..
.32220022002223.|.32220022002223.|.32220022002223.|.32220022002223.|.32220022002223.
.32222222222223.|.32222222222223.|.32222222222223.|.32222222222223.|.32222222222223.
.33333333333333.|.33333333333333.|.33333333333333.|.33333333333333.|.33333333333333.
....30000003....|....30000003....|....30000003....|...3300000033...|....30000003....
....30300303....|....30300303....|....30300303....|..3.30300303.3..|....33033033....
....30000003....|....30000003....|....30000003....|....30000003....|....30300303....
....30011003....|....30011003....|....30011003....|....30033003....|....30000003....
.....300003.....|.....300003.....|.....300003.....|.....300003.....|.....300003.....
.....311113.....|.....311113.....|.....311113.....|.....311113.....|.....311113.....
.....311113.....|....3311113.....|.....3111133....|.....311113.....|.....311113.....
....33....33....|...33.....33....|....33....33....|.....33..33.....|....33....33....
...333....333...|..333......33...|...33.....333...|.....33..33.....|...333....333...
"""

HEDGEHOG = """
................|................|................
................|................|................
................|................|................
................|................|................
.....3.3.3......|......3.3.3.....|................
....33333333....|....33333333....|................
...3232323233...|...3323232323...|................
..323232323233..|..332323232323..|................
.33232323232333.|.33323232323233.|................
3000332323233333|3000323232323333|................
3030332323232323|3030332323232323|................
3000333333333333|3000333333333333|...3.3.3.3.3....
.3003222222222..|.3003222222222..|..333333333333..
..33322222222...|..33322222222...|.30033323232333.
...33.33..33....|..33..33.33.....|3003333333333333
...33.33..33....|..33...33.33....|3333333333333333
"""

COIN = """
..3333..|...33...|...33...|...33...
.300003.|..3003..|...33...|..3003..
30001003|..3013..|...33...|..3013..
30010003|..3013..|...33...|..3013..
30010003|..3013..|...33...|..3013..
30001003|..3013..|...33...|..3013..
.300003.|..3003..|...33...|..3003..
..3333..|...33...|...33...|...33...
"""

FLAG = """
33..............|33..............
3333333.........|33.3333.........
33000003333.....|3330000033333...
330000000003....|33000000000033..
33000220000.....|3300022000003...
3300222200......|330022220003....
330002200.......|33000220003.....
333333..........|33333333........
33..............|33..............
"""


def sprites(art: str) -> list[Image.Image]:
    rows = [r for r in art.strip("\n").split("\n")]
    frames = list(zip(*(r.split("|") for r in rows)))
    out = []
    for f in frames:
        img = Image.new("RGBA", (len(f[0]), len(f)))
        for y, row in enumerate(f):
            for x, ch in enumerate(row):
                if ch != ".":
                    img.putpixel((x, y), TONES[int(ch)] + (255,))
        out.append(img)
    return out


def tile(name: str) -> Image.Image:
    img = Image.new("RGBA", (8, 8))
    for y, row in enumerate(TILES[name]):
        for x, ch in enumerate(row):
            if ch != ".":
                img.putpixel((x, y), TONES[int(ch)] + (255,))
    return img


def level() -> Image.Image:
    rows = [l.split('"')[1] for l in (HERE / "level.lua").read_text().splitlines() if l.startswith('  "')]
    img = Image.new("RGBA", (len(rows[0]) * 8, len(rows) * 8))
    for ty, row in enumerate(rows):
        for tx, ch in enumerate(row):
            if ch == "#":
                above = rows[ty - 1][tx] if ty else "."
                img.alpha_composite(tile("#" if above == "#" else "top"), (tx * 8, ty * 8))
            elif ch in TILES:
                img.alpha_composite(tile(ch), (tx * 8, ty * 8))
    return img


def strip(frames: list[Image.Image]) -> Image.Image:
    s = Image.new("RGBA", (frames[0].width * len(frames), frames[0].height))
    for i, f in enumerate(frames):
        s.alpha_composite(f, (i * f.width, 0))
    return s


def border() -> Image.Image:
    """The console around the 160x144 screen (320x288 here, at 80,16): its case, the D-pad and the buttons."""
    img = Image.new("RGBA", (480, 320), (196, 192, 186, 255))
    d = ImageDraw.Draw(img)
    for y in range(0, 320, 4):  # a faint ribbing on the plastic
        d.line((0, y, 479, y), fill=(188, 184, 178, 255))
    d.rounded_rectangle((60, 6, 420, 314), 18, fill=(84, 82, 96, 255))  # the dark glass around the screen
    d.rectangle((80, 16, 399, 303), fill=(0, 0, 0, 0))                  # the screen: see-through
    d.ellipse((66, 150, 74, 158), fill=(200, 40, 40, 255))             # the power light
    cx, cy = 30, 160                                                    # the D-pad
    d.rectangle((cx - 7, cy - 22, cx + 7, cy + 22), fill=(40, 40, 46, 255))
    d.rectangle((cx - 22, cy - 7, cx + 22, cy + 7), fill=(40, 40, 46, 255))
    for x, y in ((448, 146), (434, 174)):                               # B and A
        d.ellipse((x - 12, y - 12, x + 12, y + 12), fill=(150, 30, 80, 255), outline=(90, 16, 50, 255))
    for i in range(6):                                                  # the speaker
        d.line((432 + i * 7, 296, 448 + i * 7, 280), fill=(150, 146, 140, 255), width=3)
    return img


def convert(png: str, aid: str, *opts: str) -> None:
    subprocess.run([sys.executable, str(ROOT / "tools" / "png2asset.py"), str(ART / png), str(ASSETS), aid, *opts],
                   check=True)


def main() -> None:
    ART.mkdir(exist_ok=True)
    ASSETS.mkdir(exist_ok=True)
    level().save(ART / "level.png")
    strip(sprites(HERO)).save(ART / "hero.png")
    strip(sprites(HEDGEHOG)).save(ART / "hedgehog.png")
    strip(sprites(COIN)).save(ART / "coin.png")
    strip(sprites(FLAG)).save(ART / "flag.png")
    border().save(ART / "border.png")
    tones = [0] + [(r >> 3) << 11 | (g >> 2) << 5 | b >> 3 for r, g, b in TONES]  # index 0 see-through, then 1-4
    for pal in ("WORLD", "OBJ"):
        (ASSETS / f"{pal}.pal").write_bytes(b"".join(c.to_bytes(2, "little") for c in tones))
    convert("level.png", "LEVEL", "--tiles", "--palette", "WORLD")
    convert("hero.png", "HERO", "--indexed", "--frames", "5", "--palette", "OBJ")
    convert("hedgehog.png", "HEDGEHOG", "--indexed", "--frames", "3", "--palette", "OBJ")
    convert("coin.png", "COIN", "--indexed", "--frames", "4", "--palette", "OBJ")
    convert("flag.png", "FLAG", "--indexed", "--frames", "2", "--palette", "OBJ")
    convert("border.png", "BORDER", "--packed", "--type", "background")
    sys.path.insert(0, str(ROOT / "tools"))
    import font2fnt
    font2fnt.build("pressstart2p", str(HERE / "fonts" / "arcade.fnt"), None, 2)
    for f in ("FONT_MAIN.fnt", "FONT_BOLD.fnt", "FONT_MAIN_L.fnt", "FONT_BOLD_L.fnt"):  # the engine's own, as every game
        shutil.copy(ROOT / "examples" / "naves" / "fonts" / f, HERE / "fonts" / f)


if __name__ == "__main__":
    main()
