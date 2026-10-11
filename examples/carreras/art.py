# /// script
# requires-python = ">=3.10"
# dependencies = ["pillow>=10"]
# ///
"""The racing game's art and sound.

    uv run examples/carreras/art.py           # art/*.png -> assets/
    uv run examples/carreras/art.py --draw    # first draw art/*.png and audio/*.wav by code, then convert

The circuit's layout is track.lua: change it there and draw again.
"""
from __future__ import annotations

import math
import struct
import subprocess
import sys
import wave
from pathlib import Path

from PIL import Image, ImageDraw

HERE = Path(__file__).resolve().parent
ROOT = HERE.parents[1]
ART, ASSETS, AUDIO = HERE / "art", HERE / "assets", HERE / "audio"


def rgba(c: tuple) -> tuple:
    return (*c, 255)


def track_rows() -> list[str]:
    return [l.split('"')[1] for l in (HERE / "track.lua").read_text().splitlines() if l.startswith('    "')]


ROAD, ROAD_D, LINE = (96, 96, 104), (80, 80, 88), (200, 200, 200)
GRASS, GRASS_D, SAND, SAND_D = (72, 152, 64), (60, 132, 56), (224, 196, 120), (200, 172, 100)
CURB_R, CURB_W = (220, 50, 50), (240, 240, 240)


def tile_img(ch: str, tx: int, ty: int) -> Image.Image:
    t = Image.new("RGBA", (8, 8))
    d = ImageDraw.Draw(t)
    odd = (tx + ty) % 2
    if ch == "#":
        d.rectangle((0, 0, 7, 7), fill=rgba(ROAD))
        for x, y in ((1, 2), (5, 6), (6, 1)) if odd else ((3, 4), (0, 7), (7, 3)):
            d.point((x, y), fill=rgba(ROAD_D))
    elif ch == "c":
        d.rectangle((0, 0, 7, 7), fill=rgba(CURB_R if odd else CURB_W))
    elif ch == "F":
        for y in range(8):
            for x in range(8):
                d.point((x, y), fill=rgba(CURB_W if ((x // 4) + (y // 4) + tx) % 2 else (20, 20, 20)))
    elif ch == "s":
        d.rectangle((0, 0, 7, 7), fill=rgba(SAND))
        d.point((2, 5), fill=rgba(SAND_D))
        d.point((6, 2), fill=rgba(SAND_D))
    else:
        d.rectangle((0, 0, 7, 7), fill=rgba(GRASS if odd else GRASS_D))
    return t


def draw_track() -> None:
    rows = track_rows()
    img = Image.new("RGBA", (len(rows[0]) * 8, len(rows) * 8))
    for ty, row in enumerate(rows):
        for tx, ch in enumerate(row):
            img.paste(tile_img(ch, tx, ty), (tx * 8, ty * 8))
    img.save(ART / "track.png")


def draw_mountains() -> None:  # mountains in the top 40 rows of a 256x160 layer that repeats sideways as the camera turns
    img = Image.new("RGBA", (256, 160), (0, 0, 0, 0))
    d = ImageDraw.Draw(img)
    for x0, top, w, c in [(-10, 6, 90, (110, 120, 170)), (60, 0, 110, (90, 100, 150)), (150, 10, 80, (110, 120, 170)),
                          (200, 4, 100, (90, 100, 150))]:
        d.polygon([(x0, 40), (x0 + w // 2, top), (x0 + w, 40)], fill=rgba(c))
        d.polygon([(x0 + w // 2, top), (x0 + w // 2 + 8, top + 8), (x0 + w // 2 - 7, top + 7)], fill=rgba((235, 240, 250)))
    for x in range(0, 256, 6):
        h = 4 + (x * 7) % 5
        d.rectangle((x, 40 - h, x + 4, 39), fill=rgba((50, 110, 60)))
    img.save(ART / "mountains.png")


def kart(body: tuple, turn: int) -> Image.Image:  # 32x16 seen from behind; turn -1 left, 0, 1 right
    img = Image.new("RGBA", (32, 16), (0, 0, 0, 0))
    d = ImageDraw.Draw(img)
    dark = tuple(max(0, c - 70) for c in body)
    lean = turn * 2
    d.rectangle((3, 9, 9, 15), fill=rgba((30, 30, 30)))   # rear wheels
    d.rectangle((22, 9, 28, 15), fill=rgba((30, 30, 30)))
    d.polygon([(6 + lean, 4), (25 + lean, 4), (28, 12), (3, 12)], fill=rgba(body))
    d.rectangle((8, 10, 23, 12), fill=rgba(dark))
    d.ellipse((12 + lean, 0, 19 + lean, 7), fill=rgba((250, 210, 170)))  # driver's helmet
    d.rectangle((12 + lean, 0, 19 + lean, 2), fill=rgba(body))
    d.point((11, 11), fill=rgba((255, 230, 120)))
    d.point((20, 11), fill=rgba((255, 230, 120)))
    return img


def draw_karts() -> None:
    for name, col in [("kart_red", (220, 50, 40)), ("kart_blue", (50, 100, 220)), ("kart_green", (40, 170, 70)),
                      ("kart_yellow", (230, 190, 30))]:
        s = Image.new("RGBA", (96, 16), (0, 0, 0, 0))
        for i, turn in enumerate((0, -1, 1)):
            s.paste(kart(col, turn), (i * 32, 0))
        s.save(ART / f"{name}.png")


def wav(name: str, samples: list[float]) -> None:
    with wave.open(str(AUDIO / f"{name}.wav"), "wb") as w:
        w.setnchannels(1)
        w.setsampwidth(2)
        w.setframerate(22050)
        w.writeframes(b"".join(struct.pack("<h", int(max(-1, min(1, s)) * 32000)) for s in samples))


def beep(f: float, dur: float, vol: float = 0.3) -> list[float]:
    n = int(22050 * dur)
    return [vol * (1 if (k * f / 22050) % 1 < 0.5 else -1) * (1 - k / n) for k in range(n)]


def draw_sounds() -> None:
    AUDIO.mkdir(exist_ok=True)
    wav("SFX_COUNT", beep(440, 0.25))
    wav("SFX_GO", beep(880, 0.5))
    wav("SFX_LAP", beep(660, 0.1) + beep(990, 0.15))
    wav("SFX_FINISH", beep(523, 0.15) + beep(659, 0.15) + beep(784, 0.15) + beep(1047, 0.4))
    beat, out = 22050 * 60 // 160, []
    line = [57, 60, 64, 67, 69, 67, 64, 60, 55, 59, 62, 67, 65, 64, 62, 59]
    for n in line * 2:
        f = 440 * 2 ** ((n - 69) / 12)
        for k in range(beat // 2):
            out.append(0.14 * math.exp(-4 * k / (beat // 2)) * (1 if (k * f / 22050) % 1 < 0.5 else -1))
    wav("MUS_RACE", out)


def convert() -> None:
    p2a = [sys.executable, str(ROOT / "tools" / "png2asset.py")]
    subprocess.run(p2a + [str(ART / "track.png"), str(ASSETS), "TRACK", "--tiles", "--affine", "--palette", "WORLD"], check=True)
    subprocess.run(p2a + [str(ART / "mountains.png"), str(ASSETS), "SKY", "--tiles", "--palette", "WORLD"], check=True)
    for name in ("kart_red", "kart_blue", "kart_green", "kart_yellow"):
        subprocess.run(p2a + [str(ART / f"{name}.png"), str(ASSETS), name.upper(), "--indexed", "--frames", "3",
                              "--palette", "OBJ"], check=True)


def main() -> None:
    if "--draw" in sys.argv:
        ART.mkdir(exist_ok=True)
        draw_track()
        draw_mountains()
        draw_karts()
        draw_sounds()
    for f in ASSETS.glob("*.pal"):
        f.unlink()
    convert()


if __name__ == "__main__":
    main()
