# /// script
# requires-python = ">=3.10"
# dependencies = ["pillow>=10.1"]
# ///
"""Pixel art reproducible for Museo de Medianoche: uv run games/museo_nocturno/art.py."""
from __future__ import annotations

import random
import subprocess
import sys
from pathlib import Path

from PIL import Image, ImageDraw

HERE = Path(__file__).resolve().parent
ROOT = HERE.parents[1]
ART = HERE / "art"
ASSETS = HERE / "assets"


def stone() -> Image.Image:
    image = Image.new("RGB", (32, 32), (36, 47, 59))
    draw = ImageDraw.Draw(image)
    rng = random.Random(7)
    for y in range(0, 32, 8):
        for x in range(0, 32, 8):
            v = rng.randrange(-7, 8)
            draw.rectangle((x + 1, y + 1, x + 7, y + 7), fill=(58 + v, 70 + v, 79 + v))
            draw.line((x + 1, y + 1, x + 7, y + 1), fill=(91 + v, 97 + v, 101 + v))
    return image


def marble() -> Image.Image:
    image = Image.new("RGB", (32, 32), (76, 81, 87))
    draw = ImageDraw.Draw(image)
    for x in range(0, 32, 8):
        draw.rectangle((x + 1, 0, x + 6, 31), fill=(101, 106, 107))
        draw.line((x + 1, 0, x + 1, 31), fill=(155, 151, 137))
    draw.rectangle((0, 2, 31, 5), fill=(173, 148, 94))
    draw.rectangle((0, 26, 31, 29), fill=(54, 61, 68))
    return image


def gallery() -> Image.Image:
    image = Image.new("RGB", (32, 32), (24, 67, 68))
    draw = ImageDraw.Draw(image)
    draw.rectangle((0, 1, 31, 3), fill=(181, 145, 82))
    draw.rectangle((0, 27, 31, 31), fill=(14, 42, 47))
    for x in (5, 25):
        draw.rectangle((x, 5, x + 1, 25), fill=(46, 96, 92))
    draw.rectangle((7, 8, 24, 23), fill=(165, 119, 57))
    draw.rectangle((9, 10, 22, 21), fill=(10, 37, 57))
    draw.ellipse((15, 11, 19, 15), fill=(231, 215, 156))
    draw.polygon(((9, 21), (14, 14), (18, 19), (22, 15), (22, 21)), fill=(42, 82, 72))
    return image


def exit_door() -> Image.Image:
    image = Image.new("RGB", (32, 32), (33, 45, 53))
    draw = ImageDraw.Draw(image)
    draw.rectangle((3, 1, 28, 31), fill=(156, 121, 69), outline=(228, 184, 101), width=2)
    draw.rectangle((7, 5, 24, 31), fill=(19, 64, 60), outline=(10, 40, 40))
    draw.polygon(((16, 9), (10, 16), (13, 16), (13, 23), (19, 23), (19, 16), (22, 16)), fill=(221, 213, 145))
    return image


def painting(kind: int) -> Image.Image:
    image = Image.new("RGBA", (32, 32))
    draw = ImageDraw.Draw(image)
    draw.rectangle((1, 4, 30, 29), fill=(94, 56, 27), outline=(29, 24, 19))
    draw.rectangle((3, 6, 28, 27), outline=(229, 188, 90), width=2)
    draw.rectangle((6, 9, 25, 24), fill=(17, 29, 50))
    if kind == 0:  # moonlit sea
        draw.ellipse((17, 10, 22, 15), fill=(247, 225, 160))
        for y in (19, 22, 24):
            draw.line((7, y, 24, y), fill=(45, 122, 152))
    elif kind == 1:  # red flower
        draw.rectangle((6, 9, 25, 24), fill=(85, 102, 63))
        draw.line((16, 22, 16, 15), fill=(31, 61, 42), width=2)
        for x, y in ((14, 14), (18, 14), (16, 12), (16, 16)):
            draw.ellipse((x - 2, y - 2, x + 2, y + 2), fill=(201, 69, 70))
        draw.point((16, 14), fill=(244, 195, 92))
    elif kind == 2:  # mountain
        draw.rectangle((6, 9, 25, 24), fill=(76, 97, 130))
        draw.polygon(((6, 24), (15, 12), (25, 24)), fill=(116, 128, 137))
        draw.polygon(((11, 18), (15, 12), (20, 18)), fill=(224, 220, 205))
    elif kind == 3:  # city
        draw.rectangle((6, 9, 25, 24), fill=(43, 46, 81))
        for x, h in ((8, 10), (13, 14), (19, 12), (23, 8)):
            draw.rectangle((x, 24 - h, x + 3, 24), fill=(32, 36, 53))
            draw.point((x + 1, 23 - h + 3), fill=(236, 195, 92))
    else:  # golden sun
        draw.rectangle((6, 9, 25, 24), fill=(133, 77, 61))
        draw.ellipse((12, 10, 21, 19), fill=(250, 199, 96))
        draw.polygon(((6, 24), (11, 18), (16, 24)), fill=(66, 66, 67))
        draw.polygon(((14, 24), (23, 17), (25, 24)), fill=(47, 52, 58))
    return image


def guard(step: int) -> Image.Image:
    image = Image.new("RGBA", (32, 32))
    draw = ImageDraw.Draw(image)
    draw.ellipse((5, 28, 27, 31), fill=(6, 9, 16, 190))
    draw.rectangle((10, 23, 14, 29 - step), fill=(22, 26, 38))
    draw.rectangle((18, 23, 22, 29 - (1 - step)), fill=(22, 26, 38))
    draw.rectangle((8, 13, 24, 24), fill=(25, 35, 49), outline=(10, 17, 25))
    draw.rectangle((7, 14, 9, 23), fill=(30, 42, 57))
    draw.rectangle((23, 14, 25, 23), fill=(30, 42, 57))
    draw.ellipse((11, 5, 21, 15), fill=(158, 125, 104))
    draw.rectangle((9, 3, 23, 7), fill=(25, 35, 49))
    draw.rectangle((13, 4, 19, 5), fill=(201, 164, 86))
    draw.rectangle((12, 10, 14, 11), fill=(16, 24, 35))
    draw.rectangle((18, 10, 20, 11), fill=(16, 24, 35))
    draw.rectangle((15, 15, 17, 18), fill=(213, 174, 90))
    draw.rectangle((25, 19, 29, 21), fill=(236, 222, 154))
    return image


def strip(frames: list[Image.Image]) -> Image.Image:
    image = Image.new("RGBA", (32 * len(frames), 32))
    for index, frame in enumerate(frames):
        image.alpha_composite(frame.convert("RGBA"), (32 * index, 0))
    return image


def convert(filename: str, asset_id: str, *options: str) -> None:
    subprocess.run([sys.executable, str(ROOT / "tools" / "png2asset.py"),
                    str(ART / filename), str(ASSETS), asset_id, *options], check=True)


def main() -> None:
    ART.mkdir(exist_ok=True)
    ASSETS.mkdir(exist_ok=True)
    for name, image in (("stone", stone()), ("marble", marble()), ("gallery", gallery()), ("exit", exit_door())):
        image.save(ART / f"{name}.png")
        convert(f"{name}.png", f"TEX_{name.upper()}", "--type", "background")
    strip([painting(index) for index in range(5)]).save(ART / "paintings.png")
    strip([guard(0), guard(1)]).save(ART / "guard.png")
    convert("paintings.png", "PAINTINGS", "--frames", "5", "--anchor", "16,31")
    convert("guard.png", "GUARD", "--frames", "2", "--anchor", "16,31")


if __name__ == "__main__":
    main()
