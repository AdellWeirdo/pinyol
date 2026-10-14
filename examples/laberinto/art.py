# /// script
# requires-python = ">=3.10"
# dependencies = ["pillow>=10.1", "fonttools>=4"]
# ///
"""The first-person maze's textures and sprites, all drawn here by code.

    uv run examples/laberinto/art.py      # art/*.png and assets/

Walls are 32x32 textures (raycast() wraps each across a square of wall): stone, brick, wood and the way out. Sprites
stand in the maze facing the player: a ghost (two frames), a gem, a lamp. All plain pictures (not packed): raycast
reads their pixels.
"""
from __future__ import annotations

import math
import random
import shutil
import subprocess
import sys
from pathlib import Path

from PIL import Image, ImageDraw

HERE = Path(__file__).resolve().parent
ROOT = HERE.parents[1]
ART, ASSETS = HERE / "art", HERE / "assets"


def stone() -> Image.Image:
    img = Image.new("RGB", (32, 32), (96, 96, 104))
    d = ImageDraw.Draw(img)
    rnd = random.Random(1)
    for y0, h in ((0, 10), (10, 12), (22, 10)):
        x = -rnd.randrange(12)
        while x < 32:
            w = 10 + rnd.randrange(10)
            g = 100 + rnd.randrange(40)
            d.rectangle((x + 1, y0 + 1, x + w - 1, y0 + h - 1), fill=(g, g, g + 8))
            d.line((x + 1, y0 + 1, x + w - 2, y0 + 1), fill=(g + 30, g + 30, g + 36))
            x += w
    return img


def brick() -> Image.Image:
    img = Image.new("RGB", (32, 32), (72, 40, 32))
    d = ImageDraw.Draw(img)
    for row in range(4):
        off = 8 if row % 2 else 0
        for x in range(-off, 32, 16):
            d.rectangle((x + 1, row * 8 + 1, x + 14, row * 8 + 6), fill=(168, 64, 48))
            d.line((x + 1, row * 8 + 1, x + 14, row * 8 + 1), fill=(200, 96, 72))
    return img


def wood() -> Image.Image:
    img = Image.new("RGB", (32, 32))
    d = ImageDraw.Draw(img)
    for x in range(0, 32, 8):
        d.rectangle((x, 0, x + 7, 31), fill=(128, 84, 44))
        d.line((x, 0, x, 31), fill=(72, 44, 24))
        for y in range(3, 32, 7):
            d.point((x + 3 + (y // 7) % 3, y), fill=(96, 60, 32))
    return img


def door() -> Image.Image:
    img = wood()
    d = ImageDraw.Draw(img)
    d.rectangle((4, 4, 27, 31), fill=(40, 120, 64), outline=(16, 48, 24))
    d.polygon(((10, 14), (22, 14), (16, 8)), fill=(240, 240, 200))  # an arrow: the way out
    d.rectangle((14, 14, 18, 22), fill=(240, 240, 200))
    return img


def ghost(frame: int) -> Image.Image:
    img = Image.new("RGBA", (32, 32))
    d = ImageDraw.Draw(img)
    d.ellipse((6, 2, 26, 22), fill=(220, 230, 255))
    d.rectangle((6, 12, 26, 26), fill=(220, 230, 255))
    for k in range(4):  # the hem, waving
        x = 6 + k * 5
        y = 26 + ((k + frame) % 2) * 3
        d.polygon(((x, 26), (x + 5, 26), (x + 2, y + 2)), fill=(220, 230, 255))
    d.ellipse((11, 9, 15, 14), fill=(24, 24, 64))
    d.ellipse((18, 9, 22, 14), fill=(24, 24, 64))
    d.ellipse((14, 16, 18, 20), fill=(24, 24, 64))
    return img


def gem() -> Image.Image:
    img = Image.new("RGBA", (32, 32))
    d = ImageDraw.Draw(img)
    d.polygon(((16, 14), (24, 20), (16, 30), (8, 20)), fill=(64, 224, 160), outline=(16, 96, 64))
    d.polygon(((16, 14), (20, 20), (16, 24), (12, 20)), fill=(176, 255, 224))
    return img


def lamp() -> Image.Image:
    img = Image.new("RGBA", (32, 32))
    d = ImageDraw.Draw(img)
    d.rectangle((15, 8, 16, 29), fill=(60, 60, 64))
    d.rectangle((10, 29, 21, 31), fill=(60, 60, 64))
    d.ellipse((9, 0, 22, 12), fill=(255, 220, 120), outline=(160, 120, 40))
    return img


def strip(frames: list[Image.Image]) -> Image.Image:
    s = Image.new("RGBA", (frames[0].width * len(frames), frames[0].height))
    for i, f in enumerate(frames):
        s.alpha_composite(f.convert("RGBA"), (i * f.width, 0))
    return s


def convert(png: str, aid: str, *opts: str) -> None:
    subprocess.run([sys.executable, str(ROOT / "tools" / "png2asset.py"), str(ART / png), str(ASSETS), aid, *opts],
                   check=True)


def main() -> None:
    ART.mkdir(exist_ok=True)
    ASSETS.mkdir(exist_ok=True)
    for name, img in (("stone", stone()), ("brick", brick()), ("wood", wood()), ("door", door()),
                      ("gem", gem()), ("lamp", lamp())):
        img.save(ART / f"{name}.png")
    strip([ghost(0), ghost(1)]).save(ART / "ghost.png")
    for name in ("stone", "brick", "wood", "door"):
        convert(f"{name}.png", f"TEX_{name.upper()}", "--type", "background")
    convert("ghost.png", "GHOST", "--frames", "2", "--anchor", "16,31")
    convert("gem.png", "GEM", "--anchor", "16,31")
    convert("lamp.png", "LAMP", "--anchor", "16,31")
    sys.path.insert(0, str(ROOT / "tools"))
    import font2fnt
    font2fnt.build("pressstart2p", str(HERE / "fonts" / "arcade.fnt"), None, 2)
    for f in ("FONT_MAIN.fnt", "FONT_BOLD.fnt", "FONT_MAIN_L.fnt", "FONT_BOLD_L.fnt"):  # the engine's own, as every game
        shutil.copy(ROOT / "examples" / "naves" / "fonts" / f, HERE / "fonts" / f)


if __name__ == "__main__":
    main()
