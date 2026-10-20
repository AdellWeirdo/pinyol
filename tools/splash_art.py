# /// script
# requires-python = ">=3.10"
# dependencies = ["pillow>=10.1"]
# ///
"""The pictures of the careta, the "POWERED BY PINYOL" every game opens with (src/splash.c), as pinyol's brand
manual has them: Silkscreen for labels, paper on ink, a cherry seed.

    uv run tools/splash_art.py      # splash/*.pk + .meta.json, built into the engine (cmake/embed_lib.cmake)

SEAL: "POWERED BY PINYOL" on a rounded ink plate, the seal the engine draws over every game's own careta, where the
game says (powered_by) or under it in the middle. LABEL: "POWERED BY" alone, over the logo of the engine's own
careta. The logo itself is the console menu's (firmware/cirera/assets: the seed, its leaves, the word, the sky).
"""
from __future__ import annotations

import subprocess
import sys
from pathlib import Path

from PIL import Image, ImageDraw, ImageFont

ROOT = Path(__file__).resolve().parent.parent
OUT = ROOT / "splash"
FONT = ROOT / "third_party/fonts/silkscreen/Silkscreen-Regular.ttf"
BOLD = ROOT / "third_party/fonts/silkscreen/Silkscreen-Bold.ttf"
INK, INK3, PAPER, DIM, CHERRY = (11, 14, 31), (28, 35, 80), (238, 240, 255), (143, 151, 204), (232, 52, 78)
PX = 8  # Silkscreen's pixel size: one square of its grid, one pixel


def words(text: str, font: Path, colour: tuple, k: int) -> Image.Image:
    """The text at k screen pixels a font pixel, crisp (drawn at 1x, then scaled by k with no smoothing)."""
    f = ImageFont.truetype(str(font), PX)
    box = f.getbbox(text)
    img = Image.new("RGBA", (box[2] - box[0], box[3] - box[1]))
    ImageDraw.Draw(img).text((-box[0], -box[1]), text, font=f, fill=colour + (255,))
    img.putalpha(img.getchannel("A").point(lambda v: 255 if v >= 128 else 0))
    return img.resize((img.width * k, img.height * k), Image.NEAREST)


def seal() -> Image.Image:
    """POWERED BY, dim, then PINYOL, paper, a cherry seed between them, on an ink plate with a lighter rim."""
    small, big = words("POWERED BY", FONT, DIM, 2), words("PINYOL", BOLD, PAPER, 2)
    seed, gap, pad = 6, 8, 8
    w = small.width + gap + seed + gap + big.width + 2 * pad
    h = max(small.height, big.height) + 2 * pad
    img = Image.new("RGBA", (w, h))
    d = ImageDraw.Draw(img)
    d.rounded_rectangle((0, 0, w - 1, h - 1), radius=6, fill=INK3 + (255,))
    d.rounded_rectangle((2, 2, w - 3, h - 3), radius=4, fill=INK + (255,))
    x = pad
    img.alpha_composite(small, (x, (h - small.height) // 2))
    x += small.width + gap
    d.ellipse((x, h // 2 - seed // 2, x + seed - 1, h // 2 + seed // 2 - 1), fill=CHERRY + (255,))
    x += seed + gap
    img.alpha_composite(big, (x, (h - big.height) // 2))
    return img


def convert(img: Image.Image, aid: str) -> None:
    png = OUT / f"{aid.lower()}.png"
    img.save(png)
    subprocess.run([sys.executable, str(ROOT / "tools/png2asset.py"), str(png), str(OUT), aid, "--packed"],
                   check=True, stdout=subprocess.DEVNULL)


def main() -> None:
    OUT.mkdir(exist_ok=True)
    convert(seal(), "SEAL")
    convert(words("POWERED BY", FONT, DIM, 2), "LABEL")


if __name__ == "__main__":
    main()
