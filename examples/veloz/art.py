# /// script
# requires-python = ">=3.10"
# dependencies = ["pillow>=10.1", "fonttools>=4"]
# ///
"""The 16-bit (Mega Drive / SNES) speed platformer's art, all drawn here by code.

    uv run examples/veloz/art.py      # art/*.png and assets/

The world is 240x160 and its layers are the console's own: BG1 the level in 8x8 tiles (checkered earth, grass), BG2
hills with palms (a bitmap), BG3 mountains and a sea (both in tiles, as those consoles had them) whose every line the game moves at its own speed (as a Mega
Drive game did with its per-line scroll), BG0 a pool of water seen through (as a SNES blended it). The sprites are
32x32 and 15 colours or fewer each: the pangolin running and rolled into a ball, a beetle, a gem, a spring, the
goal; ROLL is the title's floor for Mode 7.
"""
from __future__ import annotations

import math
import shutil
import subprocess
import sys
from pathlib import Path

from PIL import Image, ImageDraw

HERE = Path(__file__).resolve().parent
ROOT = HERE.parents[1]
ART, ASSETS = HERE / "art", HERE / "assets"
T = 8

GRASS, GRASS_D, GRASS_L = (56, 168, 40), (24, 104, 32), (136, 224, 72)
EARTH_A, EARTH_B, EARTH_D = (200, 120, 48), (152, 80, 32), (96, 48, 24)
STONE, STONE_D, STONE_L = (152, 152, 168), (96, 96, 120), (208, 208, 224)
SEA, SEA_D, SEA_L, FOAM = (32, 96, 200), (16, 56, 144), (96, 168, 240), (232, 248, 255)
MOUNT, MOUNT_D, SNOW = (88, 104, 176), (56, 64, 136), (232, 236, 252)
HILL, HILL_D, TRUNK, LEAF = (72, 160, 88), (40, 112, 64), (128, 80, 40), (32, 136, 56)


def level_rows() -> list[str]:
    return [l.split('"')[1] for l in (HERE / "level.lua").read_text().splitlines() if l.startswith('  "')]


def level() -> Image.Image:
    rows = level_rows()
    img = Image.new("RGBA", (len(rows[0]) * T, len(rows) * T))
    d = ImageDraw.Draw(img)
    at = lambda x, y: rows[y][x] if 0 <= y < len(rows) and 0 <= x < len(rows[0]) else "."
    for ty, row in enumerate(rows):
        for tx, ch in enumerate(row):
            x, y = tx * T, ty * T
            if ch == "#":
                checker = EARTH_A if (tx // 2 + ty // 2) % 2 == 0 else EARTH_B
                d.rectangle((x, y, x + 7, y + 7), fill=checker)
                if (tx + ty) % 2 == 0:
                    d.point((x + 3, y + 4), fill=EARTH_D)
                if at(tx, ty - 1) != "#":  # grass on top
                    d.rectangle((x, y, x + 7, y + 3), fill=GRASS)
                    d.line((x, y + 4, x + 7, y + 4), fill=GRASS_D)
                    for k in range(0, 8, 2):
                        d.point((x + k, y + (k // 2) % 2), fill=GRASS_L)
            elif ch == "=":
                d.rectangle((x, y, x + 7, y + 7), fill=STONE)
                d.line((x, y + 7, x + 7, y + 7), fill=STONE_D)
                d.line((x + 7, y, x + 7, y + 7), fill=STONE_D)
                d.line((x, y, x + 6, y), fill=STONE_L)
                d.rectangle((x, y, x + 7, y + 2), fill=GRASS)
    return img


def hills() -> Image.Image:  # BG2: a band of round hills with palms, 512 wide so it repeats
    img = Image.new("RGBA", (512, 160))
    d = ImageDraw.Draw(img)
    for i, (cx, r) in enumerate(((60, 70), (190, 54), (300, 80), (430, 62), (572, 70))):
        d.ellipse((cx - r * 1.4, 150 - r, cx + r * 1.4, 150 + r), fill=HILL if i % 2 else HILL_D)
    for y in range(80, 160, 8):  # a checker on the hills, as those games painted them
        for x in range(0, 512, 16):
            if img.getpixel((x, y))[3] and (x // 16 + y // 8) % 2:
                d.rectangle((x, y, x + 7, y + 3), fill=tuple(max(0, c - 18) for c in img.getpixel((x, y))[:3]))
    for px in (40, 150, 260, 400, 470):  # palms
        for k in range(0, 46):
            d.point((px + round(4 * math.sin(k / 12)), 150 - k), fill=TRUNK)
            d.point((px + 1 + round(4 * math.sin(k / 12)), 150 - k), fill=TRUNK)
        top = (px + round(4 * math.sin(45 / 12)), 104)
        for ang in range(0, 360, 45):
            a = math.radians(ang)
            d.line((top, (top[0] + 16 * math.cos(a), top[1] + 7 * math.sin(a) + 4)), fill=LEAF, width=3)
    return img


def far() -> Image.Image:  # BG3: mountains over the sea (rows 70-110); the sky above is the backdrop's gradient
    img = Image.new("RGBA", (256, 160))
    d = ImageDraw.Draw(img)
    for cx, h in ((30, 46), (100, 60), (170, 40), (230, 54), (286, 46)):
        d.polygon(((cx - 50, 92), (cx, 92 - h), (cx + 50, 92)), fill=MOUNT)
        d.polygon(((cx, 92 - h), (cx + 50, 92), (cx + 10, 92)), fill=MOUNT_D)
        d.polygon(((cx - 9, 92 - h + 10), (cx, 92 - h), (cx + 9, 92 - h + 10)), fill=SNOW)
    for y in range(92, 160):  # the sea: lines of light and dark, and foam that the per-line scroll makes move
        k = (y - 92) / 68
        base = tuple(round(a + (b - a) * k) for a, b in zip(SEA_D, SEA))
        d.line((0, y, 255, y), fill=base)
        for x in range(0, 256, 16 + (y % 5) * 4):
            if (x * 7 + y * 13) % 5 == 0:
                d.line((x, y, x + 3 + y % 4, y), fill=SEA_L if y % 3 else FOAM)
    return img


def water() -> Image.Image:  # BG0: a pool in the level's pits, drawn see-through by the game
    rows = level_rows()
    img = Image.new("RGBA", (len(rows[0]) * T, len(rows) * T))
    d = ImageDraw.Draw(img)
    for ty, row in enumerate(rows):
        for tx, ch in enumerate(row):
            if ch == "~":
                d.rectangle((tx * T, ty * T, tx * T + 7, ty * T + 7), fill=SEA_L)
                if rows[ty - 1][tx] != "~":
                    d.line((tx * T, ty * T, tx * T + 7, ty * T), fill=FOAM)
    return img


def pangolin(frame: int, ball: bool) -> Image.Image:
    img = Image.new("RGBA", (32, 32))
    d = ImageDraw.Draw(img)
    scale, scale_d, scale_l, skin, out = (176, 104, 56), (112, 64, 32), (224, 160, 96), (240, 208, 160), (48, 24, 16)
    if ball:  # rolled up: a ball of scales, turning
        d.ellipse((5, 5, 27, 27), fill=scale, outline=out)
        for k in range(4):
            a = math.radians(frame * 22 + k * 90)
            d.arc((8, 8, 24, 24), math.degrees(a), math.degrees(a) + 60, fill=scale_d, width=2)
            d.point((16 + round(7 * math.cos(a + 0.5)), 16 + round(7 * math.sin(a + 0.5))), fill=scale_l)
        d.arc((7, 7, 25, 25), 200, 260, fill=scale_l, width=2)
        return img
    bob = (frame % 2)
    d.polygon(((1, 24 - bob), (10, 18 - bob), (10, 26 - bob)), fill=scale_d, outline=out)  # the tail
    d.ellipse((6, 9 - bob, 25, 27 - bob), fill=scale, outline=out)                        # the body
    for row in range(3):
        for k in range(4):
            d.arc((8 + k * 4, 11 + row * 5 - bob, 14 + k * 4, 17 + row * 5 - bob), 180, 360, fill=scale_d)
    d.ellipse((20, 15 - bob, 30, 24 - bob), fill=skin, outline=out)  # the head and its snout
    d.point((26, 18 - bob), fill=out)
    d.point((30, 21 - bob), fill=out)
    legs = ((10, 14, 18, 22), (12, 20, 16, 22), (14, 18, 14, 18), (16, 12, 20, 14))[frame % 4]
    for x in legs:
        d.rectangle((x, 26 - bob, x + 2, 29), fill=out)
    return img


def beetle(frame: int) -> Image.Image:
    img = Image.new("RGBA", (32, 32))
    d = ImageDraw.Draw(img)
    for k in range(3):
        x = 9 + k * 6 + (frame * 2 if k % 2 else -frame * 2)
        d.line((x, 26, x - 2, 30), fill=(24, 24, 32), width=2)
    d.ellipse((6, 14, 26, 28), fill=(208, 32, 40), outline=(48, 8, 16))
    d.line((16, 14, 16, 28), fill=(48, 8, 16))
    for x, y in ((11, 19), (21, 19), (12, 24), (20, 24)):
        d.ellipse((x - 2, y - 2, x + 2, y + 2), fill=(24, 24, 32))
    d.ellipse((2, 18, 10, 26), fill=(24, 24, 32))
    d.point((4, 21), fill=(255, 255, 255))
    return img


def gem(frame: int) -> Image.Image:
    img = Image.new("RGBA", (16, 16))
    d = ImageDraw.Draw(img)
    w = (6, 4, 1, 4)[frame]
    d.polygon(((8 - w, 7), (8, 1), (8 + w, 7), (8, 14)), fill=(64, 208, 240), outline=(16, 72, 128))
    if w > 1:
        d.polygon(((8 - w + 2, 7), (8, 3), (8, 7)), fill=(200, 248, 255))
    return img


def spring(frame: int) -> Image.Image:
    img = Image.new("RGBA", (16, 16))
    d = ImageDraw.Draw(img)
    top = 4 if frame == 0 else 0
    d.rectangle((1, 12, 14, 15), fill=(96, 96, 112), outline=(32, 32, 48))
    for y in range(top + 4, 12, 2):
        d.line((4, y, 11, y + 1), fill=(240, 200, 64))
    d.rectangle((0, top, 15, top + 3), fill=(224, 40, 40), outline=(96, 16, 16))
    return img


def goal(frame: int) -> Image.Image:
    img = Image.new("RGBA", (32, 32))
    d = ImageDraw.Draw(img)
    d.rectangle((15, 12, 17, 31), fill=(96, 96, 112))
    w = (12, 8, 2, 8)[frame]
    d.ellipse((16 - w, 0, 16 + w, 14), fill=(248, 216, 64) if frame < 2 else (64, 160, 240), outline=(80, 48, 16))
    return img


def roll() -> Image.Image:  # the title's Mode 7 floor: a big checker in the level's colours
    img = Image.new("RGBA", (256, 256))
    d = ImageDraw.Draw(img)
    for y in range(0, 256, 32):
        for x in range(0, 256, 32):
            d.rectangle((x, y, x + 31, y + 31), fill=EARTH_A if (x + y) // 32 % 2 else GRASS)
    return img


def strip(frames: list[Image.Image]) -> Image.Image:
    s = Image.new("RGBA", (frames[0].width * len(frames), frames[0].height))
    for i, f in enumerate(frames):
        s.alpha_composite(f, (i * f.width, 0))
    return s


def convert(png: str, aid: str, *opts: str) -> None:
    subprocess.run([sys.executable, str(ROOT / "tools" / "png2asset.py"), str(ART / png), str(ASSETS), aid, *opts],
                   check=True)


def main() -> None:
    ART.mkdir(exist_ok=True)
    ASSETS.mkdir(exist_ok=True)
    for f in ASSETS.glob("*.pal"):
        f.unlink()  # palettes grow as pictures are added: start them again
    level().save(ART / "level.png")
    water().save(ART / "water.png")
    hills().save(ART / "hills.png")
    far().save(ART / "far.png")
    roll().save(ART / "roll.png")
    strip([pangolin(i, False) for i in range(4)] + [pangolin(i, True) for i in range(4)]).save(ART / "hero.png")
    strip([beetle(i) for i in range(2)]).save(ART / "beetle.png")
    strip([gem(i) for i in range(4)]).save(ART / "gem.png")
    strip([spring(i) for i in range(2)]).save(ART / "spring.png")
    strip([goal(i) for i in range(4)]).save(ART / "goal.png")
    convert("level.png", "LEVEL", "--tiles", "--palette", "WORLD")
    convert("water.png", "WATER", "--tiles", "--palette", "WORLD")
    convert("roll.png", "ROLL", "--tiles", "--affine", "--palette", "WORLD")
    convert("hills.png", "HILLS", "--tiles", "--palette", "WORLD")  # tiles: far cheaper for the PPU than bitmaps
    convert("far.png", "FAR", "--tiles", "--palette", "WORLD")
    convert("hero.png", "HERO", "--indexed", "--frames", "8", "--palette", "OBJ")
    convert("beetle.png", "BEETLE", "--indexed", "--frames", "2", "--palette", "OBJ")
    convert("gem.png", "GEM", "--indexed", "--frames", "4", "--palette", "OBJ")
    convert("spring.png", "SPRING", "--indexed", "--frames", "2", "--palette", "OBJ")
    convert("goal.png", "GOAL", "--indexed", "--frames", "4", "--palette", "OBJ")
    sys.path.insert(0, str(ROOT / "tools"))
    import font2fnt
    font2fnt.build("pressstart2p", str(HERE / "fonts" / "arcade.fnt"), None, 2)
    for f in ("FONT_MAIN.fnt", "FONT_BOLD.fnt", "FONT_MAIN_L.fnt", "FONT_BOLD_L.fnt"):  # the engine's own, as every game
        shutil.copy(ROOT / "examples" / "naves" / "fonts" / f, HERE / "fonts" / f)


if __name__ == "__main__":
    main()
