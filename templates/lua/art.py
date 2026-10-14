# /// script
# requires-python = ">=3.10"
# dependencies = ["pillow>=10"]
# ///
"""This game's art and sound, drawn by code. Replace any PNG in art/ with your own and run this again.

    python3 art.py           # art/*.png -> assets/
    python3 art.py --draw    # first draw art/*.png and audio/*.wav by code (overwrites them), then convert

The room's picture comes from room.lua: change the room there and draw again. The conversion uses pinyol's
tools/png2asset.py: for a game outside the pinyol folder, say where pinyol is: PINYOL=/path/to/pinyol python3 art.py
"""
from __future__ import annotations

import math
import os
import struct
import subprocess
import sys
import wave
from pathlib import Path

from PIL import Image, ImageDraw

HERE = Path(__file__).resolve().parent
ART, ASSETS, AUDIO = HERE / "art", HERE / "assets", HERE / "audio"
PINYOL = Path(os.environ.get("PINYOL", HERE.parents[1]))  # the engine's folder, for tools/png2asset.py

FLOOR, FLOOR_D, GRASS, GRASS_D = (150, 140, 126), (132, 122, 110), (84, 150, 72), (70, 132, 62)
WALL, WALL_D, WALL_L = (120, 72, 56), (90, 52, 42), (150, 96, 74)
LEAF, LEAF_D, TRUNK, WATER, WATER_L = (40, 110, 60), (28, 84, 46), (100, 70, 40), (50, 110, 190), (120, 170, 230)


def room_rows() -> list[str]:
    return [line.split('"')[1] for line in (HERE / "room.lua").read_text().splitlines() if line.startswith('  "')]


def tile(ch: str, tx: int, ty: int) -> Image.Image:
    t = Image.new("RGBA", (8, 8), (*GRASS, 255))
    d = ImageDraw.Draw(t)
    odd = (tx * 7 + ty * 3) % 5 == 0
    if ch == ".":
        d.rectangle((0, 0, 7, 7), fill=FLOOR)
        d.line((0, 7, 7, 7), fill=FLOOR_D)
        d.line((7, 0, 7, 7), fill=FLOOR_D)
    elif ch == "#":
        d.rectangle((0, 0, 7, 7), fill=WALL)
        d.line((0, 3, 7, 3), fill=WALL_D)
        d.line((0, 7, 7, 7), fill=WALL_D)
        d.line((3 if ty % 2 else 7, 0, 3 if ty % 2 else 7, 3), fill=WALL_D)
        d.point((1, 1), fill=WALL_L)
    elif ch == "~":
        d.rectangle((0, 0, 7, 7), fill=WATER)
        d.line((1 + tx % 3, 2, 3 + tx % 3, 2), fill=WATER_L)
    elif ch == "T":
        d.ellipse((0, 0, 7, 6), fill=LEAF)
        d.ellipse((1, 1, 4, 3), fill=LEAF_D)
        d.rectangle((3, 6, 4, 7), fill=TRUNK)
    elif odd:
        d.point((2, 3), fill=GRASS_D)
        d.point((5, 6), fill=GRASS_D)
    return t


def draw_room() -> None:
    rows = room_rows()
    img = Image.new("RGBA", (len(rows[0]) * 8, len(rows) * 8))
    for ty, row in enumerate(rows):
        for tx, ch in enumerate(row):
            if ch in "*@":  # a gem or the start: drawn as the floor around it
                ch = "." if "." in row[max(0, tx - 2):tx + 3] else ","
            img.paste(tile(ch, tx, ty), (tx * 8, ty * 8))
    img.save(ART / "room.png")


def hero(direction: int, step: int) -> Image.Image:  # 16x16; direction 0 up, 1 right, 2 down, 3 left
    img = Image.new("RGBA", (16, 16), (0, 0, 0, 0))
    d = ImageDraw.Draw(img)
    d.ellipse((3, 13, 12, 15), fill=(0, 0, 0, 90))
    leg = (1, -1)[step]
    d.rectangle((5, 10, 6, 13 + (leg if direction % 2 == 0 else 0)), fill=(40, 40, 60))
    d.rectangle((9, 10, 10, 13 - (leg if direction % 2 == 0 else 0)), fill=(40, 40, 60))
    d.rectangle((4, 6, 11, 11), fill=(60, 120, 200))
    d.ellipse((4, 0, 11, 7), fill=(240, 200, 160))
    d.chord((4, 0, 11, 7), 180, 360, fill=(90, 50, 30))
    if direction == 0:
        d.ellipse((4, 0, 11, 7), fill=(90, 50, 30))
    elif direction == 2:
        d.point((6, 4), fill=(30, 30, 30))
        d.point((9, 4), fill=(30, 30, 30))
    else:
        d.point((9 if direction == 1 else 6, 4), fill=(30, 30, 30))
    return img


def gem(f: int) -> Image.Image:  # 8x8, 4 frames of sparkle
    img = Image.new("RGBA", (8, 8), (0, 0, 0, 0))
    d = ImageDraw.Draw(img)
    d.polygon([(4, 0), (7, 3), (4, 7), (1, 3)], fill=(220, 60, 120))
    d.polygon([(4, 1), (6, 3), (4, 5), (2, 3)], fill=(250, 120, 170))
    d.point([(3, 2), (2 + f % 2, 3)][f // 2], fill=(255, 255, 255))
    return img


def strip(frames: list[Image.Image]) -> Image.Image:
    w, h = frames[0].size
    s = Image.new("RGBA", (w * len(frames), h), (0, 0, 0, 0))
    for i, f in enumerate(frames):
        s.paste(f, (i * w, 0))
    return s


def wav(name: str, samples: list[float]) -> None:  # the engine plays mono PCM16 at 22050 Hz
    with wave.open(str(AUDIO / f"{name}.wav"), "wb") as w:
        w.setnchannels(1)
        w.setsampwidth(2)
        w.setframerate(22050)
        w.writeframes(b"".join(struct.pack("<h", int(max(-1, min(1, s)) * 32000)) for s in samples))


def blip(f0: float, f1: float, dur: float, vol: float = 0.25) -> list[float]:
    n, ph, out = int(22050 * dur), 0.0, []
    for k in range(n):
        ph += (f0 + (f1 - f0) * k / n) / 22050
        out.append(vol * (1 if ph % 1 < 0.5 else -1) * math.exp(-3 * k / n))
    return out


def convert() -> None:
    p2a = [sys.executable, str(PINYOL / "tools" / "png2asset.py")]
    for f in ASSETS.glob("*.pal"):  # palettes grow as images are added: start them again
        f.unlink()
    subprocess.run(p2a + [str(ART / "room.png"), str(ASSETS), "ROOM", "--tiles", "--palette", "WORLD"], check=True)
    subprocess.run(p2a + [str(ART / "hero.png"), str(ASSETS), "HERO", "--indexed", "--frames", "8", "--palette", "OBJ"],
                   check=True)
    subprocess.run(p2a + [str(ART / "gem.png"), str(ASSETS), "GEM", "--indexed", "--frames", "4", "--palette", "OBJ"],
                   check=True)


def main() -> None:
    if "--draw" in sys.argv:
        ART.mkdir(exist_ok=True)
        AUDIO.mkdir(exist_ok=True)
        draw_room()
        strip([hero(d, s) for d in range(4) for s in range(2)]).save(ART / "hero.png")
        strip([gem(f) for f in range(4)]).save(ART / "gem.png")
        wav("SFX_GEM", blip(900, 1800, 0.12))
        wav("SFX_DONE", blip(523, 523, 0.12) + blip(659, 659, 0.12) + blip(784, 784, 0.12) + blip(1047, 1047, 0.3))
    ASSETS.mkdir(exist_ok=True)
    convert()


if __name__ == "__main__":
    main()
