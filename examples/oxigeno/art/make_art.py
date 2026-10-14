"""Convert a cover to ZX Spectrum ink and paper, two colours per 8x8 block.

Used by ../art.py for monochrome and colour tape-loading frames.
"""
import sys
from pathlib import Path

from PIL import Image

HERE = Path(__file__).resolve().parent
W, H = 224, 144  # 28x18 blocks
BASE = [(0, 0, 0), (0, 0, 215), (215, 0, 0), (215, 0, 215), (0, 215, 0), (0, 215, 215), (215, 215, 0), (215, 215, 215)]
BRIGHT = [(0, 0, 0), (0, 0, 255), (255, 0, 0), (255, 0, 255), (0, 255, 0), (0, 255, 255), (255, 255, 0), (255, 255, 255)]
BAYER = [[0, 8, 2, 10], [12, 4, 14, 6], [3, 11, 1, 9], [15, 7, 13, 5]]  # a 4x4 pattern of thresholds, as artists dithered


def d2(a, b):
    return (a[0] - b[0]) ** 2 + (a[1] - b[1]) ** 2 + (a[2] - b[2]) ** 2


def block(px: list, x0: int, y0: int) -> tuple:
    """The best ink and paper for one 8x8 block: every pixel takes the nearer of the two, the least error wins."""
    cells = [px[(y0 + y) * W + x0 + x] for y in range(8) for x in range(8)]
    best = None
    for pal in (BASE, BRIGHT):
        for i in range(8):
            for j in range(i, 8):
                a, b = pal[i], pal[j]
                err = sum(min(d2(c, a), d2(c, b)) for c in cells)
                if best is None or err < best[0]:
                    best = (err, a, b)
    return best[1], best[2]


def spectrum(img: Image.Image) -> tuple[Image.Image, Image.Image]:
    img = img.convert("RGB").resize((W, H), Image.LANCZOS)
    raw = img.tobytes()
    px = [tuple(raw[i:i + 3]) for i in range(0, len(raw), 3)]
    colour, mono = Image.new("RGB", (W, H)), Image.new("RGB", (W, H))
    for by in range(0, H, 8):
        for bx in range(0, W, 8):
            ink, paper = block(px, bx, by)
            if sum(ink) > sum(paper):  # ink is the darker of the two, as on most loading screens
                ink, paper = paper, ink
            span = max(1, d2(ink, paper))
            for y in range(by, by + 8):
                for x in range(bx, bx + 8):
                    c = px[y * W + x]  # how far from the paper towards the ink, against the pattern's threshold
                    t = sum((c[k] - paper[k]) * (ink[k] - paper[k]) for k in range(3)) / span
                    on = t * 16 > BAYER[y % 4][x % 4] + 0.5
                    colour.putpixel((x, y), ink if on else paper)
                    mono.putpixel((x, y), (0, 0, 0) if on else (255, 255, 255))
    return mono, colour


def main(src: Path) -> None:
    mono, colour = spectrum(Image.open(src))
    mono.resize((W * 2, H * 2), Image.NEAREST).save(HERE / "loading_mono.png")
    colour.resize((W * 2, H * 2), Image.NEAREST).save(HERE / "loading.png")
    print(f"loading screen: {W}x{H}, two colours a block")


if __name__ == "__main__":
    if len(sys.argv) != 2:
        raise SystemExit("Usage: python make_art.py IMAGE.png")
    main(Path(sys.argv[1]))
