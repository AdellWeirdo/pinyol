# /// script
# requires-python = ">=3.10"
# dependencies = ["pillow>=10.1", "fonttools>=4"]
# ///
"""The puzzle's art. Its sounds and music are synthesised in main.lua (tone), so there is no audio folder.

    uv run examples/puzle/art.py           # art/*.png -> assets/
    uv run examples/puzle/art.py --draw    # first make art/*.png (the picture from art/picture.png), then convert

art/picture.png is the picture to put together, 144x144 (generated with an image model at 1254x1254 and reduced).
Any square picture works: --draw scales it to 144x144 and reduces it to 96 colours.

Its own look, made every time: DotGothic16 from pinyol's font library, and FR_SUAVE, a soft rounded frame for frame().
"""
from __future__ import annotations

import subprocess
import sys
from pathlib import Path

from PIL import Image, ImageDraw

HERE = Path(__file__).resolve().parent
ROOT = HERE.parents[1]
ART, ASSETS = HERE / "art", HERE / "assets"
N, P, BX, BY = 4, 36, 10, 8  # as in main.lua: 4x4 pieces of 36 px, the board's corner
SIDE = N * P


def picture() -> Image.Image:
    img = Image.open(ART / "picture.png").convert("RGB")
    if img.size != (SIDE, SIDE):
        img = img.resize((SIDE, SIDE), Image.Resampling.LANCZOS)
    return img.quantize(96, method=Image.Quantize.MEDIANCUT, dither=Image.Dither.FLOYDSTEINBERG).convert("RGBA")


def draw_pieces(pic: Image.Image) -> None:  # 16 frames of 36x36, piece k = row k // 4, column k % 4
    strip = Image.new("RGBA", (P * N * N, P))
    for k in range(N * N):
        piece = pic.crop(((k % N) * P, (k // N) * P, (k % N + 1) * P, (k // N + 1) * P))
        d = ImageDraw.Draw(piece)  # a light edge top-left, a dark one bottom-right: each piece reads as a tile
        d.line((0, 0, P - 1, 0), fill=(255, 240, 210, 255))
        d.line((0, 0, 0, P - 1), fill=(255, 240, 210, 255))
        d.line((0, P - 1, P - 1, P - 1), fill=(40, 28, 24, 255))
        d.line((P - 1, 0, P - 1, P - 1), fill=(40, 28, 24, 255))
        strip.paste(piece, (k * P, 0))
    strip.save(ART / "pieces.png")


def draw_frame() -> None:  # 240x160: a wooden frame around the board and a dark well under the pieces
    img = Image.new("RGBA", (240, 160), (0, 0, 0, 0))
    d = ImageDraw.Draw(img)
    d.rectangle((BX - 6, BY - 6, BX + SIDE + 5, BY + SIDE + 5), fill=(120, 76, 44, 255))
    d.rectangle((BX - 6, BY - 6, BX + SIDE + 5, BY - 5), fill=(170, 116, 70, 255))
    d.rectangle((BX - 6, BY - 6, BX - 5, BY + SIDE + 5), fill=(170, 116, 70, 255))
    d.rectangle((BX - 2, BY - 2, BX + SIDE + 1, BY + SIDE + 1), fill=(70, 44, 28, 255))
    d.rectangle((BX, BY, BX + SIDE - 1, BY + SIDE - 1), fill=(28, 22, 34, 255))
    img.save(ART / "frame.png")


def draw_pattern() -> None:  # 32x32 that repeats: soft diagonal stripes and dots
    img = Image.new("RGBA", (32, 32), (52, 40, 70, 255))
    d = ImageDraw.Draw(img)
    for k in range(-32, 32, 8):
        d.line((k, 0, k + 32, 32), fill=(60, 47, 80, 255), width=3)
    for x, y in ((4, 20), (20, 4)):
        d.rectangle((x, y, x + 1, y + 1), fill=(96, 78, 120, 255))
    img.save(ART / "pattern.png")


def convert() -> None:
    p2a = [sys.executable, str(ROOT / "tools" / "png2asset.py")]
    for f in ASSETS.glob("*.pal"):
        f.unlink()
    pic = Image.open(ART / "picture.png")
    if pic.size != (SIDE, SIDE):
        sys.exit("art/picture.png must be 144x144: run with --draw")
    for png, aid in (("picture_q.png", "PICTURE"), ("frame.png", "FRAME"), ("pattern.png", "PATTERN")):
        subprocess.run(p2a + [str(ART / png), str(ASSETS), aid, "--tiles", "--palette", "WORLD"], check=True)
    subprocess.run(p2a + [str(ART / "pieces.png"), str(ASSETS), "PIECES", "--indexed", "--frames", str(N * N),
                          "--palette", "OBJ"], check=True)


def look() -> None:
    sys.path.insert(0, str(ROOT / "tools"))
    import font2fnt
    for name, src, scale in (("dots", "dotgothic16", 1),):
        font2fnt.build(src, str(HERE / "fonts" / f"{name}.fnt"), 16 if src == 'dotgothic16' else None, scale)
    im = Image.new("RGBA", (24, 24), (0, 0, 0, 0))
    d = ImageDraw.Draw(im)
    d.rounded_rectangle((0, 0, 23, 23), radius=7, fill=(90, 110, 160, 255))
    d.rounded_rectangle((1, 1, 22, 22), radius=6, fill=(232, 238, 255, 255))
    d.rounded_rectangle((3, 3, 20, 20), radius=4, outline=(190, 204, 240, 255))
    im.save(ART / "fr_suave.png")
    subprocess.run([sys.executable, str(ROOT / "tools" / "png2asset.py"), str(ART / "fr_suave.png"), str(ASSETS),
                    "FR_SUAVE"], check=True)


def main() -> None:
    ASSETS.mkdir(exist_ok=True)
    if "--draw" in sys.argv:
        pic = picture()
        Image.open(ART / "picture.png").convert("RGB").resize((SIDE, SIDE), Image.Resampling.LANCZOS).save(
            ART / "picture.png")
        pic.save(ART / "picture_q.png")
        draw_pieces(pic)
        draw_frame()
        draw_pattern()
    look()
    convert()


if __name__ == "__main__":
    main()
