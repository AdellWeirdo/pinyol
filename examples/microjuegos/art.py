# /// script
# requires-python = ">=3.10"
# dependencies = ["pillow>=10.1"]
# ///
"""The art of Microjuegos, drawn by code: three backdrops (240 x 160, cut into tiles) and one sheet of 16 x 16 things.

    uv run examples/microjuegos/art.py           # art/*.png, then assets/ (tools/png2asset.py)
"""
from __future__ import annotations

import subprocess
import sys
from pathlib import Path

from PIL import Image, ImageDraw

HERE = Path(__file__).resolve().parent
ROOT = HERE.parents[1]
ART, ASSETS = HERE / "art", HERE / "assets"
INK = (30, 26, 42)


def backdrop(name: str, a: tuple, b: tuple, kind: str) -> None:
    img = Image.new("RGBA", (240, 160), a + (255,))
    d = ImageDraw.Draw(img)
    if kind == "checker":
        for y in range(0, 160, 16):
            for x in range(0, 240, 16):
                if (x // 16 + y // 16) % 2:
                    d.rectangle((x, y, x + 15, y + 15), fill=b)
    elif kind == "stripes":
        for x in range(0, 240, 24):
            d.rectangle((x, 0, x + 11, 159), fill=b)
    else:
        for y in range(8, 160, 24):
            for x in range(8 + (y // 24 % 2) * 12, 240, 24):
                d.ellipse((x - 4, y - 4, x + 4, y + 4), fill=b)
    img.save(ART / f"{name}.png")


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


def thing(i: int) -> Image.Image:
    img = Image.new("RGBA", (16, 16), (0, 0, 0, 0))
    d = ImageDraw.Draw(img)
    if i == 0:    # the hero
        d.ellipse((4, 0, 11, 7), fill=(240, 200, 160)); d.chord((4, 0, 11, 7), 180, 360, fill=(90, 54, 30))
        d.rectangle((4, 7, 11, 12), fill=(60, 110, 220)); d.rectangle((5, 12, 6, 15), fill=(50, 44, 60)); d.rectangle((9, 12, 10, 15), fill=(50, 44, 60))
        d.point((6, 4), fill=INK); d.point((9, 4), fill=INK)
    elif i == 1:  # a rock
        d.polygon([(2, 13), (1, 7), (5, 2), (11, 2), (15, 8), (13, 14)], fill=(130, 126, 140))
        d.polygon([(4, 11), (3, 7), (6, 4), (10, 4)], fill=(176, 172, 186))
    elif i == 2:  # a coin
        d.ellipse((2, 2, 13, 13), fill=(250, 210, 60)); d.ellipse((4, 4, 11, 11), fill=(230, 170, 30)); d.line((8, 5, 8, 10), fill=(255, 240, 150))
    elif i == 3:  # an arrow, up
        d.polygon([(8, 0), (14, 8), (10, 8), (10, 15), (6, 15), (6, 8), (2, 8)], fill=(240, 90, 90))
        d.polygon([(8, 2), (11, 7), (5, 7)], fill=(255, 170, 170))
    elif i in (4, 5):  # a star, and the same with a dot: the odd one out
        d.polygon([(8, 0), (10, 6), (15, 6), (11, 9), (13, 15), (8, 11), (3, 15), (5, 9), (1, 6), (6, 6)], fill=(250, 220, 90))
        if i == 5:
            d.ellipse((6, 6, 9, 9), fill=(220, 80, 80))
    elif i == 6:  # a cloud for the boss's bar
        d.ellipse((1, 6, 9, 14), fill=(250, 250, 255)); d.ellipse((6, 3, 14, 13), fill=(250, 250, 255))
    return outline(img)


def main() -> None:
    ART.mkdir(exist_ok=True)
    backdrop("bg1", (70, 110, 200), (84, 128, 218), "checker")
    backdrop("bg2", (60, 150, 110), (74, 168, 124), "stripes")
    backdrop("bg3", (130, 80, 170), (148, 98, 190), "dots")
    sheet = Image.new("RGBA", (16 * 7, 16), (0, 0, 0, 0))
    for i in range(7):
        sheet.paste(thing(i), (i * 16, 0))
    sheet.save(ART / "things.png")
    py, png = sys.executable, str(ROOT / "tools" / "png2asset.py")
    ASSETS.mkdir(exist_ok=True)
    for f in ASSETS.glob("*"):
        f.unlink()
    for n in (1, 2, 3):
        subprocess.run([py, png, str(ART / f"bg{n}.png"), str(ASSETS), f"BG{n}", "--tiles", "--palette", "WORLD"], check=True)
    subprocess.run([py, png, str(ART / "things.png"), str(ASSETS), "THINGS", "--indexed", "--frames", "7", "--palette", "OBJ"], check=True)


if __name__ == "__main__":
    main()
