# /// script
# requires-python = ">=3.10"
# dependencies = ["pillow>=10.1", "fonttools>=4"]
# ///
"""The look of this example, all made here: fonts from pinyol's font library, three frames and a star drawn in code.

    uv run examples/estilos/art.py

- fonts/: the four every game has (Pixelify Sans, as in the other examples) and twelve more from third_party/fonts,
  each at its own pixel size, made bigger (SCALE) when it is small.
- FR_MADERA, FR_NEON, FR_PERGAMI: frames for frame(), 24x24 pictures cut in thirds (8x8 corners, edges, middle).
- STAR: a picture to turn, scale and flip with img().
"""
from __future__ import annotations

import shutil
import subprocess
import sys
from pathlib import Path

from PIL import Image, ImageDraw

HERE = Path(__file__).resolve().parent
ROOT = HERE.parents[1]
ART, ASSETS, FONTS = HERE / "art", HERE / "assets", HERE / "fonts"
sys.path.insert(0, str(ROOT / "tools"))
import font2fnt  # noqa: E402

# name in the game: (font in the library, its pixel size or None to find it, scale)
LIBRARY = {
    "arcade": ("pressstart2p", None, 2),
    "silk": ("silkscreen", None, 2),
    "silk_bold": ("silkscreen-bold", None, 2),
    "terminal": ("vt323", None, 1),
    "jersey": ("jersey10", None, 1),
    "jersey_big": ("jersey20", None, 1),
    "micro": ("micro5", None, 2),
    "gotica": ("jacquard12", None, 1),
    "bastarda": ("jacquardabastarda9", None, 2),
    "byte": ("bytesized", None, 2),
    "dots": ("dotgothic16", 16, 1),
    "pixelify_big": ("pixelifysans", 30, 1),
}


def fonts() -> None:
    FONTS.mkdir(exist_ok=True)
    for f in ("FONT_MAIN", "FONT_BOLD", "FONT_MAIN_L", "FONT_BOLD_L"):
        shutil.copy(ROOT / "examples" / "hola" / "fonts" / f"{f}.fnt", FONTS)
    for name, (src, px, scale) in LIBRARY.items():
        font2fnt.build(src, str(FONTS / f"{name}.fnt"), px, scale)


def frame_madera() -> Image.Image:
    """Wood: a dark rim, a lit and a shaded side, nail heads in the corners; plain paper in the middle."""
    im = Image.new("RGBA", (24, 24), (0, 0, 0, 0))
    d = ImageDraw.Draw(im)
    d.rectangle((0, 0, 23, 23), fill=(58, 34, 20, 255))
    d.rectangle((1, 1, 22, 22), fill=(150, 96, 52, 255))
    d.line((1, 1, 22, 1), fill=(196, 140, 84, 255))
    d.line((1, 1, 1, 22), fill=(196, 140, 84, 255))
    d.line((2, 22, 22, 22), fill=(102, 62, 32, 255))
    d.line((22, 2, 22, 22), fill=(102, 62, 32, 255))
    for y in (4, 12, 19):  # the grain, across the edges
        d.line((3, y, 20, y), fill=(128, 80, 42, 255))
    d.rectangle((5, 5, 18, 18), fill=(70, 40, 22, 255))
    d.rectangle((6, 6, 17, 17), fill=(240, 226, 196, 255))
    for x, y in ((3, 3), (19, 3), (3, 19), (19, 19)):
        d.rectangle((x, y, x + 1, y + 1), fill=(220, 210, 180, 255))
    return im


def frame_neon() -> Image.Image:
    """Night city: a dark glassy middle, a cyan line with its glow, magenta brackets at the corners."""
    im = Image.new("RGBA", (24, 24), (0, 0, 0, 0))
    d = ImageDraw.Draw(im)
    d.rectangle((2, 2, 21, 21), fill=(10, 14, 38, 235))
    d.rectangle((2, 2, 21, 21), outline=(20, 90, 120, 255))
    d.rectangle((3, 3, 20, 20), outline=(70, 240, 255, 255))
    d.rectangle((4, 4, 19, 19), outline=(20, 90, 120, 255))
    for x0, y0, dx, dy in ((0, 0, 1, 1), (23, 0, -1, 1), (0, 23, 1, -1), (23, 23, -1, -1)):
        d.line((x0, y0, x0 + 5 * dx, y0), fill=(255, 60, 200, 255))
        d.line((x0, y0, x0, y0 + 5 * dy), fill=(255, 60, 200, 255))
    return im


def frame_pergami() -> Image.Image:
    """Parchment: rounded corners (see-through outside them), brown ink, a warm paper."""
    im = Image.new("RGBA", (24, 24), (0, 0, 0, 0))
    d = ImageDraw.Draw(im)
    d.rounded_rectangle((0, 0, 23, 23), radius=6, fill=(92, 58, 30, 255))
    d.rounded_rectangle((1, 1, 22, 22), radius=5, fill=(236, 214, 160, 255))
    d.rounded_rectangle((3, 3, 20, 20), radius=3, outline=(176, 128, 72, 255))
    return im


def star() -> Image.Image:
    import math
    im = Image.new("RGBA", (32, 32), (0, 0, 0, 0))
    pts = [(16 + (15 if i % 2 == 0 else 6.5) * math.sin(i * math.pi / 5),
            17 - (15 if i % 2 == 0 else 6.5) * math.cos(i * math.pi / 5)) for i in range(10)]
    d = ImageDraw.Draw(im)
    d.polygon(pts, fill=(255, 208, 64, 255), outline=(120, 60, 10, 255))
    d.polygon([(16, 6), (19, 14), (16, 13)], fill=(255, 246, 190, 255))
    return im


def main() -> None:
    ART.mkdir(exist_ok=True)
    ASSETS.mkdir(exist_ok=True)
    fonts()
    pictures = {"FR_MADERA": frame_madera(), "FR_NEON": frame_neon(), "FR_PERGAMI": frame_pergami(), "STAR": star()}
    for aid, im in pictures.items():
        png = ART / f"{aid.lower()}.png"
        im.save(png)
        subprocess.run([sys.executable, str(ROOT / "tools" / "png2asset.py"), str(png), str(ASSETS), aid], check=True)


if __name__ == "__main__":
    main()
