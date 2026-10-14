# /// script
# requires-python = ">=3.10"
# dependencies = ["pillow>=10.1", "fonttools>=4"]
# ///
"""The shoot-'em-up's art and sound.

    uv run examples/naves/art.py           # art/*.png -> assets/
    uv run examples/naves/art.py --draw    # first draw art/*.png and audio/*.wav by code, then convert

Its own look, made every time: arcade letters (Press Start 2P, Silkscreen) from pinyol's font library, and FR_NEON,
a neon frame for frame().
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


def rgba(c: tuple, a: int = 255) -> tuple:
    return (*c, a)


def draw_stars() -> None:  # BG3: 256x160 of stars in three brightnesses; each line scrolls at its own speed
    img = Image.new("RGBA", (256, 160), (0, 0, 0, 0))
    r = random.Random(11)
    for _ in range(140):
        x, y = r.randrange(256), r.randrange(160)
        c = r.choice([(90, 100, 140), (150, 160, 200), (240, 240, 255)])
        img.putpixel((x, y), rgba(c))
        if c[0] > 200 and r.random() < 0.3:
            img.putpixel(((x + 1) % 256, y), rgba((150, 160, 200)))
    img.save(ART / "stars.png")


def draw_planet() -> None:  # BG2 (affine): a ringed planet in a 128x128 map that turns slowly
    img = Image.new("RGBA", (128, 128), (0, 0, 0, 0))
    d = ImageDraw.Draw(img)
    for i, c in enumerate([(70, 40, 110), (110, 60, 150), (150, 90, 180), (190, 130, 200)]):
        rr = 40 - i * 7
        d.ellipse((64 - rr - i * 3, 64 - rr - i * 3, 64 + rr - i * 3, 64 + rr - i * 3), fill=rgba(c))
    bands = Image.new("RGBA", (128, 128), (0, 0, 0, 0))  # stripes, kept inside the planet's disc
    bd = ImageDraw.Draw(bands)
    for y in range(30, 98, 9):
        bd.line((20, y, 108, y + 6), fill=rgba((90, 50, 130)))
    disc = Image.new("L", (128, 128), 0)
    ImageDraw.Draw(disc).ellipse((24, 24, 104, 104), fill=255)
    img.paste(bands, (0, 0), Image.composite(bands, Image.new("RGBA", (128, 128)), disc).getchannel("A"))
    d.ellipse((6, 52, 122, 76), outline=rgba((220, 180, 120)), width=3)
    img.save(ART / "planet.png")


def ship(f: int) -> Image.Image:  # 16x16, nose to the right; f: 0 level, 1 up, 2 down
    img = Image.new("RGBA", (16, 16), (0, 0, 0, 0))
    d = ImageDraw.Draw(img)
    tilt = [0, -1, 1][f]
    d.polygon([(1, 4 + tilt), (13, 8), (1, 12 - tilt)], fill=rgba((200, 210, 230)))
    d.polygon([(3, 6), (11, 8), (3, 10)], fill=rgba((120, 140, 190)))
    d.rectangle((5, 7, 8, 9), fill=rgba((80, 220, 255)))
    d.rectangle((0, 7, 1, 9), fill=rgba((255, 160, 40)))
    d.point((14, 8), fill=rgba((255, 255, 255)))
    return img


def enemy(kind: int, f: int) -> Image.Image:
    img = Image.new("RGBA", (16, 16), (0, 0, 0, 0))
    d = ImageDraw.Draw(img)
    if kind == 0:  # a saucer, nose to the left
        d.ellipse((1, 5, 14, 11), fill=rgba((220, 80, 80)))
        d.ellipse((5, 2 + f, 10, 7), fill=rgba((255, 200, 120)))
        d.point((3 + 3 * f, 8), fill=rgba((255, 255, 160)))
        d.point((12 - 3 * f, 8), fill=rgba((255, 255, 160)))
    else:  # a spiked mine
        d.ellipse((4, 4, 11, 11), fill=rgba((90, 200, 120)))
        for k in range(8):
            a = k * math.pi / 4 + f * math.pi / 8
            d.line((7.5, 7.5, 7.5 + 7 * math.cos(a), 7.5 + 7 * math.sin(a)), fill=rgba((150, 240, 160)))
        d.point((7, 7), fill=rgba((20, 60, 30)))
    return img


def shot(kind: int) -> Image.Image:  # 8x8: 0 player laser, 1 enemy ball
    img = Image.new("RGBA", (8, 8), (0, 0, 0, 0))
    d = ImageDraw.Draw(img)
    if kind == 0:
        d.rectangle((0, 3, 7, 4), fill=rgba((120, 255, 255)))
        d.line((2, 3, 7, 3), fill=rgba((255, 255, 255)))
    else:
        d.ellipse((2, 2, 5, 5), fill=rgba((255, 120, 200)))
        d.point((3, 3), fill=rgba((255, 255, 255)))
    return img


def boom(f: int) -> Image.Image:  # 16x16 explosion, 5 frames
    img = Image.new("RGBA", (16, 16), (0, 0, 0, 0))
    d = ImageDraw.Draw(img)
    r = [3, 5, 7, 7, 6][f]
    cols = [(255, 255, 200), (255, 220, 80), (255, 140, 40), (200, 60, 30), (120, 40, 40)]
    d.ellipse((8 - r, 8 - r, 7 + r, 7 + r), fill=rgba(cols[f]))
    if f < 3:
        d.ellipse((8 - r // 2, 8 - r // 2, 7 + r // 2, 7 + r // 2), fill=rgba((255, 255, 255)))
    return img


def power() -> Image.Image:
    img = Image.new("RGBA", (8, 8), (0, 0, 0, 0))
    d = ImageDraw.Draw(img)
    d.ellipse((0, 0, 7, 7), fill=rgba((255, 210, 60)))
    d.text((2, -1), "P", fill=rgba((120, 60, 0)))
    return img


def strip(frames: list[Image.Image]) -> Image.Image:
    w, h = frames[0].size
    s = Image.new("RGBA", (w * len(frames), h), (0, 0, 0, 0))
    for i, f in enumerate(frames):
        s.paste(f, (i * w, 0))
    return s


def wav(name: str, samples: list[float]) -> None:
    with wave.open(str(AUDIO / f"{name}.wav"), "wb") as w:
        w.setnchannels(1)
        w.setsampwidth(2)
        w.setframerate(22050)
        w.writeframes(b"".join(struct.pack("<h", int(max(-1, min(1, s)) * 32000)) for s in samples))


def sweep(f0: float, f1: float, dur: float, vol: float = 0.3, square: bool = True) -> list[float]:
    n, ph, out = int(22050 * dur), 0.0, []
    for k in range(n):
        ph += (f0 + (f1 - f0) * k / n) / 22050
        s = (1 if ph % 1 < 0.5 else -1) if square else math.sin(2 * math.pi * ph)
        out.append(s * vol * math.exp(-4 * k / n))
    return out


def noise(dur: float, vol: float = 0.45) -> list[float]:
    r, n = random.Random(2), int(22050 * dur)
    return [r.uniform(-1, 1) * vol * math.exp(-5 * k / n) for k in range(n)]


def draw_sounds() -> None:
    AUDIO.mkdir(exist_ok=True)
    wav("SFX_SHOT", sweep(1800, 900, 0.05, 0.18))
    wav("SFX_BOOM", noise(0.35))
    wav("SFX_HIT", sweep(300, 80, 0.25, 0.35))
    wav("SFX_POWER", sweep(600, 1400, 0.2, 0.25, square=False))
    wav("SFX_BOMB", noise(0.8, 0.6))
    beat, out = 22050 * 60 // 150, []
    bass = [45, 45, 48, 43, 45, 45, 50, 48]
    for i in range(32):
        n = bass[i % 8]
        f = 440 * 2 ** ((n - 69) / 12)
        for k in range(beat // 2):
            env = math.exp(-6 * k / (beat // 2))
            out.append(0.2 * env * (1 if (k * f / 22050) % 1 < 0.5 else -1))
    wav("MUS_SPACE", out)


def look() -> None:
    sys.path.insert(0, str(ROOT / "tools"))
    import font2fnt
    for name, src in (("arcade", "pressstart2p"), ("silk", "silkscreen")):
        font2fnt.build(src, str(HERE / "fonts" / f"{name}.fnt"), None, 2)
    im = Image.new("RGBA", (24, 24), (0, 0, 0, 0))  # a dark glassy middle, a cyan line and its glow, magenta corners
    d = ImageDraw.Draw(im)
    d.rectangle((2, 2, 21, 21), fill=(10, 14, 38, 255))
    d.rectangle((2, 2, 21, 21), outline=(20, 90, 120, 255))
    d.rectangle((3, 3, 20, 20), outline=(70, 240, 255, 255))
    d.rectangle((4, 4, 19, 19), outline=(20, 90, 120, 255))
    for x0, y0, dx, dy in ((0, 0, 1, 1), (23, 0, -1, 1), (0, 23, 1, -1), (23, 23, -1, -1)):
        d.line((x0, y0, x0 + 5 * dx, y0), fill=(255, 60, 200, 255))
        d.line((x0, y0, x0, y0 + 5 * dy), fill=(255, 60, 200, 255))
    im.save(ART / "fr_neon.png")


def convert() -> None:
    p2a = [sys.executable, str(ROOT / "tools" / "png2asset.py")]
    subprocess.run(p2a + [str(ART / "stars.png"), str(ASSETS), "STARS", "--tiles", "--palette", "SPACE"], check=True)
    subprocess.run(p2a + [str(ART / "planet.png"), str(ASSETS), "PLANET", "--tiles", "--palette", "SPACE"], check=True)
    for png, aid, n in [("ship", "SHIP", 3), ("saucer", "SAUCER", 2), ("mine", "MINE", 2), ("shots", "SHOTS", 2),
                        ("boom", "BOOM", 5), ("power", "POWER", 1)]:
        subprocess.run(p2a + [str(ART / f"{png}.png"), str(ASSETS), aid, "--indexed", "--frames", str(n),
                              "--palette", "OBJ"], check=True)
    subprocess.run(p2a + [str(ART / "fr_neon.png"), str(ASSETS), "FR_NEON"], check=True)


def main() -> None:
    if "--draw" in sys.argv:
        ART.mkdir(exist_ok=True)
        draw_stars()
        draw_planet()
        strip([ship(f) for f in range(3)]).save(ART / "ship.png")
        strip([enemy(0, f) for f in range(2)]).save(ART / "saucer.png")
        strip([enemy(1, f) for f in range(2)]).save(ART / "mine.png")
        strip([shot(k) for k in range(2)]).save(ART / "shots.png")
        strip([boom(f) for f in range(5)]).save(ART / "boom.png")
        power().save(ART / "power.png")
        draw_sounds()
    for f in ASSETS.glob("*.pal"):
        f.unlink()
    look()
    convert()


if __name__ == "__main__":
    main()
