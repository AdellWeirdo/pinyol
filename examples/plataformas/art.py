# /// script
# requires-python = ">=3.10"
# dependencies = ["pillow>=10.1", "fonttools>=4"]
# ///
"""The platformer's art and sound.

    uv run examples/plataformas/art.py           # art/*.png -> assets/ (indexed tiles and sprites)
    uv run examples/plataformas/art.py --draw    # first draw art/*.png and audio/*.wav by code, then convert

Edit the PNGs in art/ with any paint program and run the first command again: the level layout comes from
level.lua, so a new level needs no art changes.

Its own look, made every time: Jersey 15 and 20 from pinyol's font library, and FR_BLOQUE, a brick block for frame().
"""
from __future__ import annotations

import math
import random
import struct
import subprocess
import sys
import wave
from pathlib import Path

from PIL import Image, ImageDraw

HERE = Path(__file__).resolve().parent
ROOT = HERE.parents[1]
ART, ASSETS, AUDIO = HERE / "art", HERE / "assets", HERE / "audio"
T = 8


def level() -> list[str]:
    return [l.split('"')[1] for l in (HERE / "level.lua").read_text().splitlines() if l.startswith('  "')]


def rgba(c: tuple) -> tuple:
    return (*c, 255)


GRASS, GRASS_D, DIRT, DIRT_D, DIRT_L = (88, 176, 72), (56, 128, 56), (152, 96, 56), (112, 68, 40), (184, 128, 80)
BRICK, BRICK_D, MORTAR = (200, 88, 56), (152, 56, 40), (232, 200, 168)
WOOD, WOOD_D, WOOD_L = (168, 112, 64), (120, 72, 40), (208, 152, 96)
WATER, WATER_L, WATER_D = (56, 120, 200), (136, 200, 248), (40, 80, 160)
HILL, HILL_D, TREE, TRUNK = (104, 168, 96), (72, 136, 80), (48, 112, 72), (96, 64, 48)
MOUNT, MOUNT_D, SNOW, CLOUD, CLOUD_D = (120, 136, 184), (96, 104, 152), (232, 240, 248), (248, 248, 255), (208, 220, 240)


def draw_level(rows: list[str]) -> None:
    w, h = len(rows[0]) * T, len(rows) * T
    img = Image.new("RGBA", (w, h), (0, 0, 0, 0))
    d = ImageDraw.Draw(img)
    rnd = random.Random(3)

    def at(x: int, y: int) -> str:
        return rows[y][x] if 0 <= y < len(rows) and 0 <= x < len(rows[0]) else "."

    for ty, row in enumerate(rows):
        for tx, ch in enumerate(row):
            x, y = tx * T, ty * T
            if ch == "#":
                d.rectangle((x, y, x + 7, y + 7), fill=rgba(DIRT))
                for _ in range(2):
                    px, py = x + rnd.randrange(8), y + rnd.randrange(8)
                    d.point((px, py), fill=rgba(DIRT_D))
                d.point((x + rnd.randrange(8), y + rnd.randrange(8)), fill=rgba(DIRT_L))
                if at(tx, ty - 1) != "#":  # grass on top
                    d.rectangle((x, y, x + 7, y + 2), fill=rgba(GRASS))
                    d.line((x, y + 3, x + 7, y + 3), fill=rgba(GRASS_D))
                    d.point((x + (tx * 3) % 8, y + 3), fill=rgba(GRASS))
            elif ch == "B":
                d.rectangle((x, y, x + 7, y + 7), fill=rgba(BRICK))
                d.line((x, y + 3, x + 7, y + 3), fill=rgba(MORTAR))
                d.line((x, y + 7, x + 7, y + 7), fill=rgba(MORTAR))
                off = 0 if ty % 2 else 4
                d.line((x + off, y, x + off, y + 3), fill=rgba(MORTAR))
                d.line((x + (off + 4) % 8, y + 4, x + (off + 4) % 8, y + 7), fill=rgba(MORTAR))
                d.point((x + 1, y + 1), fill=rgba(BRICK_D))
            elif ch == "=":
                d.rectangle((x, y, x + 7, y + 4), fill=rgba(WOOD))
                d.line((x, y, x + 7, y), fill=rgba(WOOD_L))
                d.line((x, y + 4, x + 7, y + 4), fill=rgba(WOOD_D))
                if at(tx - 1, ty) != "=":
                    d.line((x, y, x, y + 4), fill=rgba(WOOD_D))
                if at(tx + 1, ty) != "=":
                    d.line((x + 7, y, x + 7, y + 4), fill=rgba(WOOD_D))
                d.point((x + 3, y + 2), fill=rgba(WOOD_D))
    img.save(ART / "level.png")

    water = Image.new("RGBA", (w, h), (0, 0, 0, 0))  # BG0: blended over the level
    wd = ImageDraw.Draw(water)
    for ty, row in enumerate(rows):
        for tx, ch in enumerate(row):
            if ch != "~":
                continue
            x, y = tx * T, ty * T
            wd.rectangle((x, y, x + 7, y + 7), fill=rgba(WATER))
            if at(tx, ty - 1) != "~":
                wd.line((x, y, x + 7, y), fill=rgba(WATER_L))
                wd.point((x + (tx * 5) % 8, y + 1), fill=rgba(WATER_L))
            else:
                wd.point((x + (tx * 3) % 8, y + 4), fill=rgba(WATER_D))
    water.save(ART / "water.png")


def draw_hills() -> None:  # BG2, wraps every 256 px
    img = Image.new("RGBA", (256, 160), (0, 0, 0, 0))
    d = ImageDraw.Draw(img)
    for i, (cx, r) in enumerate([(30, 60), (110, 44), (180, 70), (250, 50)]):
        d.ellipse((cx - r, 150 - r // 2, cx + r, 150 + r * 2), fill=rgba(HILL if i % 2 else HILL_D))
    for x in (60, 140, 210):
        d.rectangle((x, 118, x + 2, 134), fill=rgba(TRUNK))
        d.ellipse((x - 8, 100, x + 10, 124), fill=rgba(TREE))
    d.rectangle((0, 150, 255, 159), fill=rgba(HILL_D))
    img.save(ART / "hills.png")


def draw_mountains() -> None:  # BG3, wraps every 256 px
    img = Image.new("RGBA", (256, 160), (0, 0, 0, 0))
    d = ImageDraw.Draw(img)
    for x0, top, wdt in [(-20, 60, 120), (70, 40, 140), (170, 70, 110), (230, 55, 120)]:
        d.polygon([(x0, 150), (x0 + wdt // 2, top), (x0 + wdt, 150)], fill=rgba(MOUNT))
        d.polygon([(x0 + wdt // 2, top), (x0 + wdt // 2 + 18, top + 22), (x0 + wdt // 2 - 14, top + 18)], fill=rgba(SNOW))
        d.line((x0 + wdt // 2, top, x0 + wdt, 150), fill=rgba(MOUNT_D))
    for cx, cy in [(40, 24), (150, 14), (215, 34)]:
        for dx, r in [(-10, 7), (0, 10), (11, 8)]:
            d.ellipse((cx + dx - r, cy - r, cx + dx + r, cy + r), fill=rgba(CLOUD))
        d.line((cx - 16, cy + 8, cx + 18, cy + 8), fill=rgba(CLOUD_D))
    d.rectangle((0, 150, 255, 159), fill=rgba(MOUNT_D))
    img.save(ART / "mountains.png")


SKIN, RED, BLUE, BLUE_D, SHOE, EYE = (248, 200, 160), (216, 56, 56), (64, 96, 200), (40, 64, 144), (88, 56, 40), (24, 24, 40)
SLIME, SLIME_D, SLIME_L = (96, 200, 96), (48, 136, 64), (184, 240, 168)
GOLD, GOLD_D, GOLD_L = (248, 200, 40), (200, 136, 24), (255, 248, 176)
POLE, FLAG = (200, 200, 208), (232, 72, 88)


def hero(pose: str) -> Image.Image:  # 16x16, feet on the bottom row
    img = Image.new("RGBA", (16, 16), (0, 0, 0, 0))
    d = ImageDraw.Draw(img)
    bob = 1 if pose == "run2" else 0
    d.rectangle((5, 1 + bob, 11, 3 + bob), fill=rgba(RED))       # cap
    d.rectangle((10, 3 + bob, 13, 3 + bob), fill=rgba(RED))      # visor
    d.rectangle((5, 4 + bob, 10, 7 + bob), fill=rgba(SKIN))      # face
    d.point((9, 5 + bob), fill=rgba(EYE))
    d.rectangle((4, 8 + bob, 11, 12), fill=rgba(BLUE))           # body
    d.rectangle((4, 8 + bob, 5, 11), fill=rgba(BLUE_D))
    legs = {"idle": [(5, 13, 7, 15), (9, 13, 11, 15)], "run1": [(3, 13, 5, 15), (10, 13, 12, 14)],
            "run2": [(6, 13, 8, 15), (8, 13, 10, 15)], "jump": [(4, 12, 6, 14), (10, 13, 12, 15)],
            "fall": [(5, 13, 7, 15), (10, 12, 12, 14)], "hurt": [(4, 13, 6, 15), (10, 13, 12, 15)]}[pose]
    for l in legs:
        d.rectangle(l, fill=rgba(SHOE))
    if pose == "jump":
        d.rectangle((12, 6, 13, 9), fill=rgba(SKIN))  # arm up
    if pose == "hurt":
        d.point((9, 5), fill=rgba((255, 255, 255)))
    return img


def slime(f: int) -> Image.Image:
    img = Image.new("RGBA", (16, 16), (0, 0, 0, 0))
    d = ImageDraw.Draw(img)
    if f == 2:  # squashed
        d.ellipse((1, 11, 14, 15), fill=rgba(SLIME_D))
        return img
    top = 5 if f == 0 else 6
    d.ellipse((2, top, 13, 15), fill=rgba(SLIME))
    d.rectangle((2, 12, 13, 15), fill=rgba(SLIME))
    d.line((2, 15, 13, 15), fill=rgba(SLIME_D))
    d.point((5, top + 2), fill=rgba(SLIME_L))
    d.rectangle((6, top + 4, 7, top + 5), fill=rgba(EYE))
    d.rectangle((10, top + 4, 11, top + 5), fill=rgba(EYE))
    return img


def coin(f: int) -> Image.Image:
    img = Image.new("RGBA", (8, 8), (0, 0, 0, 0))
    d = ImageDraw.Draw(img)
    w = [3, 2, 0, 2][f]
    d.ellipse((3 - w, 0, 4 + w, 7), fill=rgba(GOLD))
    if w:
        d.ellipse((4 - w // 2, 1, 4 + w // 2, 6), fill=rgba(GOLD_D))
        d.point((3 - w + 1, 2), fill=rgba(GOLD_L))
    return img


def flag(f: int) -> Image.Image:
    img = Image.new("RGBA", (16, 32), (0, 0, 0, 0))
    d = ImageDraw.Draw(img)
    d.rectangle((2, 2, 3, 31), fill=rgba(POLE))
    d.ellipse((1, 0, 4, 3), fill=rgba(GOLD))
    wave_ = [0, 1][f]
    d.polygon([(4, 4), (15, 7 + wave_), (4, 11)], fill=rgba(FLAG))
    return img


def spark() -> Image.Image:
    img = Image.new("RGBA", (8, 8), (0, 0, 0, 0))
    d = ImageDraw.Draw(img)
    d.line((3, 0, 3, 7), fill=rgba(GOLD_L))
    d.line((0, 3, 7, 3), fill=rgba(GOLD_L))
    d.point((3, 3), fill=rgba((255, 255, 255)))
    return img


def strip(frames: list[Image.Image]) -> Image.Image:
    w, h = frames[0].size
    s = Image.new("RGBA", (w * len(frames), h), (0, 0, 0, 0))
    for i, f in enumerate(frames):
        s.paste(f, (i * w, 0))
    return s


def draw_sprites() -> None:
    strip([hero(p) for p in ("idle", "run1", "run2", "jump", "fall", "hurt")]).save(ART / "hero.png")
    strip([slime(i) for i in range(3)]).save(ART / "slime.png")
    strip([coin(i) for i in range(4)]).save(ART / "coin.png")
    strip([flag(i) for i in range(2)]).save(ART / "flag.png")
    spark().save(ART / "spark.png")


def wav(name: str, samples: list[float]) -> None:
    with wave.open(str(AUDIO / f"{name}.wav"), "wb") as w:
        w.setnchannels(1)
        w.setsampwidth(2)
        w.setframerate(22050)
        w.writeframes(b"".join(struct.pack("<h", int(max(-1, min(1, s)) * 32000)) for s in samples))


def tone(freqs: list[float], dur: float, kind: str = "square", vol: float = 0.35) -> list[float]:
    out, n = [], int(22050 * dur)
    for i, f0 in enumerate(freqs):
        ph = 0.0
        for k in range(n):
            f = f0 if not isinstance(f0, tuple) else f0[0] + (f0[1] - f0[0]) * k / n
            ph += f / 22050
            env = math.exp(-3 * k / n)
            s = (1 if (ph % 1) < 0.5 else -1) if kind == "square" else math.sin(2 * math.pi * ph)
            out.append(s * env * vol)
    return out


def draw_sounds() -> None:
    AUDIO.mkdir(exist_ok=True)
    wav("SFX_COIN", tone([988, 1319], 0.07))
    wav("SFX_JUMP", tone([(330, 660)], 0.14))
    noise = random.Random(5)
    wav("SFX_STOMP", [noise.uniform(-1, 1) * 0.4 * math.exp(-6 * k / 3000) for k in range(3000)])
    wav("SFX_HURT", tone([(440, 110)], 0.3))
    wav("SFX_WIN", tone([523, 659, 784, 1047], 0.12))
    melody = [72, 76, 79, 76, 77, 74, 71, 74, 72, 76, 79, 84, 81, 77, 74, 72]
    beat = 22050 * 60 // 140
    out = []
    for i, n in enumerate(melody):
        f, bass = 440 * 2 ** ((n - 69) / 12), 440 * 2 ** ((n - 69 - 24) / 12)
        for k in range(beat):
            env = math.exp(-5 * k / beat)
            out.append(0.16 * env * (1 if (k * f / 22050) % 1 < 0.5 else -1) + 0.12 * math.sin(2 * math.pi * bass * k / 22050))
    wav("MUS_LEVEL", out)


def convert() -> None:
    p2a = [sys.executable, str(ROOT / "tools" / "png2asset.py")]
    for png, aid in [("level", "LEVEL"), ("hills", "HILLS"), ("mountains", "MOUNTAINS"), ("water", "WATER")]:
        subprocess.run(p2a + [str(ART / f"{png}.png"), str(ASSETS), aid, "--tiles", "--palette", "WORLD"], check=True)
    for png, aid, n in [("hero", "HERO", 6), ("slime", "SLIME", 3), ("coin", "COIN", 4), ("flag", "FLAG", 2),
                        ("spark", "SPARK", 1)]:
        subprocess.run(p2a + [str(ART / f"{png}.png"), str(ASSETS), aid, "--indexed", "--frames", str(n),
                              "--palette", "OBJ"], check=True)


def look() -> None:
    sys.path.insert(0, str(ROOT / "tools"))
    import font2fnt
    for name, src, scale in (("marcador", "jersey15", 1), ("titol", "jersey20", 1),):
        font2fnt.build(src, str(HERE / "fonts" / f"{name}.fnt"), None, scale)
    im = Image.new("RGBA", (24, 24), (0, 0, 0, 0))
    d = ImageDraw.Draw(im)
    d.rectangle((0, 0, 23, 23), fill=(74, 44, 26, 255))         # mortar
    for y in range(0, 24, 6):                                      # rows of bricks, every other row shifted
        for x in range(-6 if y % 12 else 0, 24, 12):
            d.rectangle((x + 1, y + 1, x + 10, y + 4), fill=(196, 104, 60, 255))
            d.line((x + 1, y + 1, x + 10, y + 1), fill=(232, 150, 96, 255))
    d.rectangle((6, 6, 17, 17), fill=(255, 244, 214, 255))     # the paper inside
    im.save(ART / "fr_bloque.png")
    subprocess.run([sys.executable, str(ROOT / "tools" / "png2asset.py"), str(ART / "fr_bloque.png"), str(ASSETS),
                    "FR_BLOQUE"], check=True)


def main() -> None:
    if "--draw" in sys.argv:
        ART.mkdir(exist_ok=True)
        draw_level(level())
        draw_hills()
        draw_mountains()
        draw_sprites()
        draw_sounds()
    for f in ASSETS.glob("*.pal"):  # the shared palettes are rebuilt from the PNGs
        f.unlink()
    look()
    convert()


if __name__ == "__main__":
    main()
