# /// script
# requires-python = ">=3.10"
# dependencies = ["pillow>=10.1"]
# ///
"""Draw and convert four-tone Game Boy art for Ratón de biblioteca."""
from __future__ import annotations

import subprocess
import sys
from pathlib import Path

from PIL import Image, ImageDraw

HERE = Path(__file__).resolve().parent
ROOT = HERE.parents[1]
ART, ASSETS = HERE / "art", HERE / "assets"
T = [(155, 188, 15), (139, 172, 15), (48, 98, 48), (15, 56, 15)]


def sprite_sheet(frames: list[Image.Image]) -> Image.Image:
    out = Image.new("RGBA", (frames[0].width * len(frames), frames[0].height))
    for i, frame in enumerate(frames):
        out.alpha_composite(frame, (i * frame.width, 0))
    return out


def mouse(pose: int) -> Image.Image:
    im = Image.new("RGBA", (16, 16))
    d = ImageDraw.Draw(im)
    # Curled tail, two round ears, pale face, bright eye and dark nose.
    d.line([(4, 12), (1, 12), (0, 10), (1, 8)], fill=T[3], width=1)
    d.ellipse((3, 7, 13, 14), fill=T[2], outline=T[3])
    d.ellipse((3, 2, 8, 8), fill=T[3])
    d.ellipse((4, 3, 7, 6), fill=T[1])
    d.ellipse((8, 3, 13, 8), fill=T[3])
    d.ellipse((9, 4, 12, 7), fill=T[1])
    d.ellipse((5, 6, 14, 12), fill=T[1], outline=T[3])
    d.rectangle((10, 7, 11, 8), fill=T[3])
    d.rectangle((14, 10, 15, 11), fill=T[3])
    if pose == 3:
        d.rectangle((5, 13, 7, 14), fill=T[3])
        d.rectangle((10, 13, 12, 14), fill=T[3])
    else:
        dx = 1 if pose == 1 else -1 if pose == 2 else 0
        d.rectangle((4 + dx, 14, 7 + dx, 15), fill=T[3])
        d.rectangle((10 - dx, 14, 13 - dx, 15), fill=T[3])
    return im


def cat(pose: int) -> Image.Image:
    im = Image.new("RGBA", (16, 16))
    d = ImageDraw.Draw(im)
    if pose == 2:
        d.ellipse((2, 8, 14, 14), fill=T[2], outline=T[3])
        d.line((3, 11, 13, 11), fill=T[3])
        return im
    d.line([(3, 12), (1, 10), (1, 6), (2, 5)], fill=T[3], width=2)
    d.ellipse((3, 6, 14, 14), fill=T[2], outline=T[3])
    d.polygon([(5, 7), (5, 1), (8, 4), (11, 1), (13, 7)], fill=T[3])
    d.ellipse((5, 5, 13, 11), fill=T[2])
    d.point((8, 7), fill=T[0]); d.point((11, 7), fill=T[0])
    d.point((9, 9), fill=T[3])
    if pose == 0:
        d.rectangle((5, 14, 7, 15), fill=T[3]); d.rectangle((11, 14, 13, 15), fill=T[3])
    else:
        d.rectangle((4, 14, 6, 15), fill=T[3]); d.rectangle((10, 14, 12, 15), fill=T[3])
    return im


def cheese(pose: int) -> Image.Image:
    im = Image.new("RGBA", (8, 8))
    d = ImageDraw.Draw(im)
    d.polygon([(0, 5), (6, 1), (7, 6), (0, 7)], fill=T[3])
    d.polygon([(1, 5), (6, 2), (6, 5), (1, 6)], fill=T[0])
    d.point((3, 4), fill=T[2]); d.point((5, 5), fill=T[2])
    if pose: d.point((6, 0), fill=T[3])
    return im


def door(opened: bool) -> Image.Image:
    im = Image.new("RGBA", (16, 16))
    d = ImageDraw.Draw(im)
    d.rectangle((1, 0, 14, 15), fill=T[3])
    d.rectangle((3, 2, 12, 15), fill=T[0] if opened else T[2])
    d.rectangle((5, 4, 10, 13), fill=T[1] if opened else T[3])
    d.rectangle((11, 9, 12, 10), fill=T[3] if opened else T[0])
    d.rectangle((0, 0, 15, 1), fill=T[2])
    return im


def library() -> Image.Image:
    rows = [line.split('"')[1] for line in (HERE / "level.lua").read_text().splitlines()
            if line.startswith('  "')]
    w, h = len(rows[0]) * 8, len(rows) * 8
    im = Image.new("RGBA", (w, h), T[0] + (255,))
    d = ImageDraw.Draw(im)
    # Wallpaper, repeated book-filled bays, trim and wood floor.
    for x in range(0, w, 8):
        for y in range(16, 128, 8):
            if (x // 8 + y // 8) % 5 == 0:
                d.point((x + 3, y + 3), fill=T[1])
                d.point((x + 4, y + 4), fill=T[1])
    for x in range(24, w - 8, 72):
        d.rectangle((x, 28, x + 62, 124), fill=T[1], outline=T[2])
        d.rectangle((x + 3, 30, x + 59, 123), fill=T[0])
        for shelf_y in (42, 66, 90, 114):
            for book_x in range(x + 5, x + 57, 5):
                tone = 2 if (book_x // 5 + shelf_y) % 3 else 3
                height = 10 + (book_x // 5) % 5
                d.rectangle((book_x, shelf_y - height, book_x + 3, shelf_y - 1), fill=T[tone])
                if tone == 2:
                    d.line((book_x + 1, shelf_y - height + 2, book_x + 1, shelf_y - height + 4), fill=T[0])
            d.rectangle((x + 3, shelf_y, x + 59, shelf_y + 2), fill=T[3])
    for y, row in enumerate(rows):
        for x, ch in enumerate(row):
            px, py = x * 8, y * 8
            if ch == "=":
                d.rectangle((px, py, px + 7, py + 2), fill=T[3])
                d.rectangle((px, py + 3, px + 7, py + 5), fill=T[2])
                d.point((px + 2, py + 4), fill=T[1])
                d.rectangle((px + 1, py + 6, px + 2, py + 7), fill=T[3])
            elif ch == "#":
                d.rectangle((px, py, px + 7, py + 7), fill=T[2])
                if y == 16: d.rectangle((px, py, px + 7, py + 2), fill=T[3])
                d.line((px + 1, py + 5, px + 5, py + 5), fill=T[1])
    return im


def convert(png: str, name: str, *options: str) -> None:
    subprocess.run([sys.executable, str(ROOT / "tools/png2asset.py"),
                    str(ART / png), str(ASSETS), name, *options], check=True)


def main() -> None:
    ART.mkdir(exist_ok=True)
    ASSETS.mkdir(exist_ok=True)
    library().save(ART / "library.png")
    sprite_sheet([mouse(i) for i in range(4)]).save(ART / "mouse.png")
    sprite_sheet([cat(i) for i in range(3)]).save(ART / "cat.png")
    sprite_sheet([cheese(i) for i in range(2)]).save(ART / "cheese.png")
    sprite_sheet([door(False), door(True)]).save(ART / "door.png")
    palette = [0] + [(r >> 3) << 11 | (g >> 2) << 5 | b >> 3 for r, g, b in T]
    for name in ("WORLD", "OBJ"):
        (ASSETS / f"{name}.pal").write_bytes(b"".join(c.to_bytes(2, "little") for c in palette))
    convert("library.png", "LIBRARY", "--tiles", "--palette", "WORLD")
    for name, count in (("MOUSE", 4), ("CAT", 3), ("CHEESE", 2), ("DOOR", 2)):
        convert(name.lower() + ".png", name, "--indexed", "--frames", str(count), "--palette", "OBJ")


if __name__ == "__main__":
    main()
