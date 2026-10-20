# /// script
# requires-python = ">=3.10"
# dependencies = ["pillow>=10.1"]
# ///
"""The art of Horizonte, drawn by code in a few palette entries that the game recolours line by line (line_pal, line_pal_obj):
the sky and its clouds, the hills and the sea in one layer each, a boat and a sun for sprites.

    uv run examples/horizonte/art.py           # art/*.png, the two palettes with their entries in place, then assets/

The entries (the game reads them from index.lua, made here): background palette 1 sky, 2 cloud, 3 cloud's shade, 4 hills, 5-7 the sea's three tones;
sprite palette 1 hull, 2 sail, 3 mast, 4 sun's core, 5 and 6 its glow.
"""
from __future__ import annotations

import subprocess
import sys
from pathlib import Path

from PIL import Image, ImageDraw

HERE = Path(__file__).resolve().parent
ROOT = HERE.parents[1]
ART, ASSETS = HERE / "art", HERE / "assets"

BG = {"sky": (90, 160, 240), "cloud": (250, 250, 255), "shade": (190, 200, 225), "hills": (60, 70, 110),
      "sea1": (50, 110, 200), "sea2": (60, 124, 212), "sea3": (44, 98, 186)}
OBJ = {"hull": (110, 70, 40), "sail": (245, 240, 230), "mast": (60, 40, 30), "core": (255, 250, 200), "glow1": (255, 220, 120), "glow2": (255, 170, 90)}


def rgb565(c: tuple) -> int:
    r, g, b = c
    return ((r >> 3) << 11) | ((g >> 2) << 5) | (b >> 3)


def seed_palette(path: Path, colours: dict) -> dict:
    """The palette file with the entries at indices 1.. in this order, so the game knows where each is."""
    index = {}
    raw = [0]
    for name, c in colours.items():
        raw.append(rgb565(c))
        index[name] = len(raw) - 1
    path.write_bytes(b"".join(v.to_bytes(2, "little") for v in raw))
    return index


def draw_sky(bg: dict) -> None:
    img = Image.new("RGBA", (240, 160), BG["sky"] + (255,))
    d = ImageDraw.Draw(img)
    for cx, cy, w in ((40, 26, 44), (120, 44, 56), (196, 18, 40), (78, 70, 36)):  # clouds: puffs with a shaded underside
        for dx, dy, r in ((-w // 3, 2, w // 5), (0, -3, w // 4), (w // 3, 3, w // 5), (-w // 8, 4, w // 5)):
            d.ellipse((cx + dx - r, cy + dy - r, cx + dx + r, cy + dy + r), fill=BG["cloud"])
        d.ellipse((cx - w // 2, cy + 3, cx + w // 2, cy + 9), fill=BG["shade"])
        d.ellipse((cx - w // 2 + 2, cy + 2, cx + w // 2 - 2, cy + 6), fill=BG["cloud"])
    img.save(ART / "sky.png")


def draw_front() -> None:
    img = Image.new("RGBA", (240, 160), (0, 0, 0, 0))
    d = ImageDraw.Draw(img)
    d.polygon([(0, 100), (0, 86), (30, 74), (62, 90), (96, 80), (130, 100)], fill=BG["hills"])
    d.polygon([(110, 100), (150, 84), (190, 92), (240, 70), (240, 100)], fill=BG["hills"])
    for y in range(100, 160):  # the sea in stripes of three tones, so each line can be given its own colours
        d.line((0, y, 239, y), fill=BG[("sea1", "sea2", "sea3")[(y // 2) % 3]])
    img.save(ART / "front.png")


def draw_sprites() -> None:
    boat = Image.new("RGBA", (32, 28), (0, 0, 0, 0))
    d = ImageDraw.Draw(boat)
    d.polygon([(2, 20), (30, 20), (25, 27), (7, 27)], fill=OBJ["hull"])
    d.line((16, 2, 16, 20), fill=OBJ["mast"], width=2)
    d.polygon([(18, 3), (18, 18), (29, 18)], fill=OBJ["sail"])
    d.polygon([(14, 6), (14, 18), (4, 18)], fill=OBJ["sail"])
    boat.save(ART / "boat.png")
    sun = Image.new("RGBA", (40, 40), (0, 0, 0, 0))
    d = ImageDraw.Draw(sun)
    d.ellipse((0, 0, 39, 39), fill=OBJ["glow2"])
    d.ellipse((5, 5, 34, 34), fill=OBJ["glow1"])
    d.ellipse((11, 11, 28, 28), fill=OBJ["core"])
    sun.save(ART / "sun.png")


def main() -> None:
    ART.mkdir(exist_ok=True)
    ASSETS.mkdir(exist_ok=True)
    for f in ASSETS.glob("*"):
        f.unlink()
    bg, obj = seed_palette(ASSETS / "WORLD.pal", BG), seed_palette(ASSETS / "OBJ.pal", OBJ)
    draw_sky(bg), draw_front(), draw_sprites()
    py, png = sys.executable, str(ROOT / "tools" / "png2asset.py")
    for name, aid in (("sky.png", "SKY"), ("front.png", "FRONT")):
        subprocess.run([py, png, str(ART / name), str(ASSETS), aid, "--tiles", "--palette", "WORLD"], check=True)
    for name, aid in (("boat.png", "BOAT"), ("sun.png", "SUN")):
        subprocess.run([py, png, str(ART / name), str(ASSETS), aid, "--indexed", "--frames", "1", "--palette", "OBJ"], check=True)
    lines = ["-- made by art.py: where each colour sits in the palettes (the game recolours them line by line)", "return {bg = {"]
    lines += [f"  {k} = {v}," for k, v in bg.items()] + ["}, obj = {"] + [f"  {k} = {v}," for k, v in obj.items()] + ["}}"]
    (HERE / "index.lua").write_text("\n".join(lines) + "\n")


if __name__ == "__main__":
    main()
