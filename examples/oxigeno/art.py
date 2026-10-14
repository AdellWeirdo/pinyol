# /// script
# requires-python = ">=3.10"
# dependencies = ["pillow>=10"]
# ///
"""Draw all ZX Spectrum art and convert it to pinyol assets.

    uv run games/oxigeno/art.py
"""
from __future__ import annotations

import subprocess
import sys
from pathlib import Path

from PIL import Image, ImageDraw, ImageFont

HERE = Path(__file__).resolve().parent
ROOT = HERE.parents[1]
ART, ASSETS = HERE / "art", HERE / "assets"
INK, PAPER = (255, 255, 255), (8, 8, 8)
BLOCKS = {
    ".": ["........", "...X....", "........", "........", "........", "......X.", "........", "........"],
    "#": ["XXXXXXXX", "X..X..X.", "XXXXXXXX", "..X..X..", "XXXXXXXX", "X..X..X.", "XXXXXXXX", "..X..X.."],
    "+": [".XXXXXX.", "X......X", "X.XXXX.X", "X.X..X.X", "X.X..X.X", "X.XXXX.X", "X......X", ".XXXXXX."],
    "o": ["...XX...", "..XXXX..", "..X..X..", "..X..X..", "..X..X..", "..X..X..", "..XXXX..", "...XX..."],
    "X": ["XXXXXXXX", "XX....XX", "X.X..X.X", "X..XX..X", "X..XX..X", "X.X..X.X", "XX....XX", "XXXXXXXX"],
}
ASTRONAUT = """
.....XXXXXX.....|.....XXXXXX.....
....XXXXXXXX....|....XXXXXXXX....
...XX......XX...|...XX......XX...
..XX.XXXXXX.XX..|..XX.XXXXXX.XX..
..X.XX.XX.XX.X..|..X.XX.XX.XX.X..
..X.XXXXXXXX.X..|..X.XXXXXXXX.X..
..XX........XX..|..XX........XX..
...XXXXXXXXXX...|...XXXXXXXXXX...
....XXXXXXXX....|....XXXXXXXX....
...XXXXXXXXXX...|...XXXXXXXXXX...
..XXX.XXXX.XXX..|...XX.XXXX.XX...
..XX..XXXX..XX..|...XX.XXXX.XX...
......XXXX......|......XXXX......
.....XX..XX.....|.....XXX.XX.....
....XXX..XXX....|....XXX...XX....
....XX....XX....|....XX....XX....
"""
ROBOT = """
....XXXXXXXX....|....XXXXXXXX....
...XXXXXXXXXX...|...XXXXXXXXXX...
..XXX.XXXX.XXX..|..XXX.XXXX.XXX..
..XXXXXXXXXXXX..|..XXXXXXXXXXXX..
..XX.XX..XX.XX..|..XX.XX..XX.XX..
..XX.XXXXXX.XX..|..XX.XXXXXX.XX..
...XXXXXXXXXX...|...XXXXXXXXXX...
....XXXXXXXX....|....XXXXXXXX....
...XXXXXXXXXX...|...XXXXXXXXXX...
..XX.XXXXXX.XX..|..XX.XXXXXX.XX..
..XX.XXXXXX.XX..|..XX.XXXXXX.XX..
...X.XXXXXX.X...|...X.XXXXXX.X...
....XX....XX....|....XX....XX....
...XXX....XXX...|....XXX..XXX....
..XX........XX..|.....XX..XX.....
..XX........XX..|.....XX..XX.....
"""


def draw_frames(pattern: str) -> Image.Image:
    rows = pattern.strip().splitlines()
    frames = list(zip(*(row.split("|") for row in rows)))
    image = Image.new("RGBA", (16 * len(frames), 16))
    for index, frame in enumerate(frames):
        for y, row in enumerate(frame):
            for x, char in enumerate(row):
                if char == "X":
                    image.putpixel((index * 16 + x, y), (*INK, 255))
    return image


def draw_room() -> Image.Image:
    rows = [line.split('"')[1] for line in (HERE / "room.lua").read_text().splitlines() if line.startswith('  "')]
    image = Image.new("RGB", (32 * 8, 18 * 8), PAPER)
    for ty, row in enumerate(rows):
        for tx, char in enumerate(row):
            for y, pixels in enumerate(BLOCKS.get(char, BLOCKS["."])):
                for x, pixel in enumerate(pixels):
                    image.putpixel((tx * 8 + x, ty * 8 + y), INK if pixel == "X" else PAPER)
    return image


def draw_cover() -> Image.Image:
    image = Image.new("RGB", (224, 144), (0, 0, 80))
    d = ImageDraw.Draw(image)
    for x, y in [(9, 12), (30, 24), (69, 10), (109, 18), (170, 11), (199, 27),
                 (18, 60), (48, 49), (121, 58), (206, 70), (31, 110), (186, 118)]:
        d.point((x, y), fill=(255, 255, 255))
    d.ellipse((155, 48, 245, 137), fill=(0, 0, 215), outline=(0, 215, 215), width=3)
    d.ellipse((181, 65, 203, 87), outline=(255, 255, 255), width=2)
    d.rectangle((42, 83, 156, 116), fill=(0, 0, 0), outline=(215, 215, 215), width=3)
    for x in (52, 84, 116):
        d.rectangle((x, 88, x + 20, 104), outline=(0, 215, 215), width=2)
    d.polygon([(26, 94), (42, 88), (42, 112), (26, 106)], fill=(215, 0, 0), outline=(255, 255, 0))
    d.rectangle((156, 89, 179, 103), fill=(215, 215, 215), outline=(255, 255, 0))
    # Astronaut outside airlock; oxygen canister in outstretched hand.
    d.ellipse((96, 60, 116, 80), fill=(255, 255, 255), outline=(0, 0, 0), width=2)
    d.rectangle((101, 66, 111, 73), fill=(0, 215, 215))
    d.rectangle((99, 81, 114, 101), fill=(255, 255, 255))
    d.line((99, 86, 89, 78), fill=(255, 255, 255), width=4)
    d.line((114, 86, 125, 77), fill=(255, 255, 255), width=4)
    d.line((103, 100, 98, 113), fill=(255, 255, 255), width=4)
    d.line((111, 100, 118, 113), fill=(255, 255, 255), width=4)
    d.rectangle((125, 69, 133, 82), fill=(255, 255, 0), outline=(0, 0, 0))
    d.rectangle((127, 66, 131, 69), fill=(255, 255, 255))
    d.rectangle((0, 0, 224, 39), fill=(0, 0, 0))
    # Letters from a pixel font, one colour each and on whole 8x8 blocks: two colours a block, as the Spectrum had.
    pixel = ROOT / "third_party/fonts/pressstart2p/PressStart2P-Regular.ttf"
    d.text((24, 8), "OXIGENO 48K", font=ImageFont.truetype(str(pixel), 16), fill=(255, 255, 0))
    d.text((56, 28), "MISION ORBITAL", font=ImageFont.truetype(str(pixel), 8), fill=(0, 215, 215))
    return image


def convert(png: str, asset: str, *opts: str) -> None:
    subprocess.run([sys.executable, str(ROOT / "tools" / "png2asset.py"), str(ART / png), str(ASSETS), asset, *opts], check=True)


def main() -> None:
    ART.mkdir(exist_ok=True)
    ASSETS.mkdir(exist_ok=True)
    draw_room().save(ART / "room.png")
    draw_frames(ASTRONAUT).save(ART / "astronaut.png")
    draw_frames(ROBOT).save(ART / "robot.png")
    sys.path.insert(0, str(ART))
    from make_art import spectrum
    mono, colour = spectrum(draw_cover())
    mono.resize((448, 288), Image.Resampling.NEAREST).save(ART / "loading_mono.png")
    colour.resize((448, 288), Image.Resampling.NEAREST).save(ART / "loading.png")
    rgb565 = lambda c: (c[0] >> 3) << 11 | (c[1] >> 2) << 5 | c[2] >> 3
    (ASSETS / "WORLD.pal").write_bytes(b"".join(rgb565(c).to_bytes(2, "little") for c in ((0, 0, 0), INK, PAPER)))
    (ASSETS / "OBJ.pal").write_bytes(b"".join(rgb565(c).to_bytes(2, "little") for c in ((0, 0, 0), INK)))
    convert("room.png", "ROOM", "--tiles", "--palette", "WORLD")
    convert("astronaut.png", "ASTRONAUT", "--indexed", "--frames", "2", "--palette", "OBJ")
    convert("robot.png", "ROBOT", "--indexed", "--frames", "2", "--palette", "OBJ")
    convert("loading_mono.png", "LOAD_MONO", "--type", "background")
    convert("loading.png", "LOAD", "--type", "background")


if __name__ == "__main__":
    main()
