# /// script
# requires-python = ">=3.10"
# dependencies = ["pillow>=10.1"]
# ///
"""The art of Isla, drawn by code: the island's ground as one tiled background (the water, the beaches, the cliffs over the sea, the
grass in a checker so the grid reads), and for sprites everything that stands up and must be drawn in depth order: stone columns one
to four blocks high, a crate, a sunk crate, a palm, a gem, the hero, its shadow and a splash.

    uv run examples/isla/art.py           # art/*.png, then assets/, and index.lua (the ground's geometry, the water's palette entries)

The cells are 2:1 diamonds 32 x 16, a block 16 high. The ground's cell (x, y) has its top corner at (OX + (x - y) * 16, OY + (x + y) * 8).
The water is four background palette entries in stripes; the game turns one of three into the glint, in turn, and the stripes move.
"""
from __future__ import annotations

import math
import re
import subprocess
import sys
from pathlib import Path

from PIL import Image

HERE = Path(__file__).resolve().parent
ROOT = HERE.parents[1]
ART, ASSETS = HERE / "art", HERE / "assets"

TW, TH, BLOCK = 32, 16, 16
OX, OY, IMG_W, IMG_H = 200, 32, 400, 240

WATER = {"water": (40, 96, 176), "wa": (48, 108, 184), "wb": (56, 116, 192), "wc": (64, 124, 200)}  # (the game colours a, b and c)
GLINT = (120, 180, 236)
GROUND = {"grass1": (96, 176, 72), "grass2": (84, 160, 64), "sand": (228, 208, 140), "cliff_l": (150, 110, 70), "cliff_r": (110, 78, 50)}
STONE = {"top": (168, 176, 150), "top_rim": (200, 206, 184), "left": (140, 136, 128), "right": (100, 96, 92), "seam": (72, 68, 66)}
WOOD = {"top": (206, 150, 84), "left": (172, 116, 60), "right": (132, 86, 44), "frame": (96, 60, 30)}
HERO = {"hat": (220, 60, 50), "skin": (248, 200, 160), "shirt": (60, 110, 200), "legs": (60, 50, 70), "eye": (30, 20, 30),
        "pack": (150, 100, 50)}


def rgb565(c: tuple) -> int:
    r, g, b = c
    return ((r >> 3) << 11) | ((g >> 2) << 5) | (b >> 3)


def seed_palette(path: Path, colours: dict) -> dict:
    """The palette file with these entries at 1.. in this order, so the game knows where each is (png2asset adds the rest after)."""
    raw, index = [0], {}
    for name, c in colours.items():
        raw.append(rgb565(c))
        index[name] = len(raw) - 1
    path.write_bytes(b"".join(v.to_bytes(2, "little") for v in raw))
    return index


def level_rows() -> list[str]:
    return re.findall(r'"([~.\dt]+)"', (HERE / "level.lua").read_text())


# ------------------------------------------------------------------ iso pieces
def put(img: Image.Image, x: int, y: int, c: tuple) -> None:
    if 0 <= x < img.width and 0 <= y < img.height:
        img.putpixel((x, y), c + (255,))


def half_width(r: int) -> int:
    return 2 * r + 2 if r < 8 else 2 * (15 - r) + 2


def diamond(img: Image.Image, sx: int, sy: int, colour, rim=None) -> None:
    """The top of a cell, its top corner at (sx, sy): 32 wide, 16 tall. colour may be a function of (x, y)."""
    for r in range(16):
        hw = half_width(r)
        for x in range(sx - hw, sx + hw):
            c = colour(x, sy + r) if callable(colour) else colour
            if rim and r < 8 and (x < sx - hw + 2 or x >= sx + hw - 2):
                c = rim
            put(img, x, sy + r, c)


def bottom_row(k: int) -> int:
    """The last row of the diamond in the column k pixels from its middle (1..16)."""
    return max(r for r in range(16) if half_width(r) >= k)


def faces(img: Image.Image, sx: int, sy: int, height: int, left, right, seam=None, every: int = BLOCK) -> None:
    """The two faces seen under a diamond, `height` pixels down; a seam line at each block's foot but the last."""
    for side, colour in ((-1, left), (1, right)):
        for k in range(1, 17):
            x = sx - k if side < 0 else sx + k - 1
            top = sy + bottom_row(k) + 1
            for dy in range(height):
                c = colour
                if seam and (dy + 1) % every == 0 and dy + 1 < height:
                    c = seam
                put(img, x, top + dy, c)


# ------------------------------------------------------------------ the ground
def draw_floor(rows: list[str]) -> None:
    img = Image.new("RGBA", (IMG_W, IMG_H), (0, 0, 0, 0))
    for y in range(IMG_H):  # the sea: stripes along the grid's slope, three sets the game lights in turn
        for x in range(IMG_W):
            p, dash = (x + 2 * y) % 24, (x // 6 + y // 12) % 4 == 0  # short dashes along the stripes, not lines across the sea
            c = WATER["water"] if not dash else WATER["wa"] if p < 2 else WATER["wb"] if 8 <= p < 10 else WATER["wc"] if 16 <= p < 18 else WATER["water"]
            img.putpixel((x, y), c + (255,))
    h, w = len(rows), len(rows[0])

    def water(x: int, y: int) -> bool:
        return not (0 <= x < w and 0 <= y < h) or rows[y][x] == "~"

    for d in range(w + h - 1):  # back to front, so a cell's cliff is drawn over the one behind it
        for y in range(h):
            x = d - y
            if not (0 <= x < w) or water(x, y):
                continue
            sx, sy = OX + (x - y) * TW // 2, OY + (x + y) * TH // 2
            if water(x, y + 1) or water(x + 1, y):
                faces(img, sx, sy, 8, GROUND["cliff_l"], GROUND["cliff_r"])
            beach = any(water(x + dx, y + dy) for dx, dy in ((1, 0), (-1, 0), (0, 1), (0, -1)))
            diamond(img, sx, sy, GROUND["sand"] if beach else GROUND["grass1" if (x + y) % 2 == 0 else "grass2"])
    img.save(ART / "floor.png")


# ------------------------------------------------------------------ the sprites
def column(k: int) -> Image.Image:
    img = Image.new("RGBA", (TW, TH + BLOCK * k), (0, 0, 0, 0))
    faces(img, 16, 0, BLOCK * k, STONE["left"], STONE["right"], STONE["seam"])
    diamond(img, 16, 0, STONE["top"], STONE["top_rim"])
    return img


def crate(height: int = BLOCK) -> Image.Image:
    img = Image.new("RGBA", (TW, TH + height), (0, 0, 0, 0))
    faces(img, 16, 0, height, WOOD["left"], WOOD["right"])
    for k in (1, 2, 15, 16):  # the frame down each face's edges, and along its foot
        for side in (-1, 1):
            x = 16 - k if side < 0 else 16 + k - 1
            for dy in range(height):
                put(img, x, bottom_row(k) + 1 + dy, WOOD["frame"])
    for k in range(1, 17):
        for side in (-1, 1):
            x = 16 - k if side < 0 else 16 + k - 1
            put(img, x, bottom_row(k) + height, WOOD["frame"])
            if height >= BLOCK:  # a brace across each face
                put(img, x, bottom_row(k) + 1 + (height - 1) * (16 - k) // 15, WOOD["frame"])
    diamond(img, 16, 0, lambda x, y: WOOD["frame"] if abs(x - 15.5) / 2 + abs(y - 7.5) > 6.5 else WOOD["top"])
    return img


def palm() -> Image.Image:
    img = Image.new("RGBA", (TW, 64), (0, 0, 0, 0))
    trunk, dark = (150, 104, 60), (110, 74, 40)
    for y in range(22, 60):  # a trunk that leans a little, ringed
        x = 15 + (60 - y) * (60 - y) // 400
        for dx in range(3):
            put(img, x + dx, y, dark if y % 4 == 0 or dx == 2 else trunk)
    leaf, leaf_dark = (60, 150, 60), (36, 110, 44)
    for ang in range(0, 360, 45):  # fronds: arcs out of the crown, drooping
        a = math.radians(ang)
        for t in range(1, 15):
            x = 17 + math.cos(a) * t
            y = 20 + math.sin(a) * t * 0.55 + t * t / 28
            for dy in (0, 1):
                put(img, int(x), int(y) + dy, leaf if dy == 0 else leaf_dark)
    for x, y in ((15, 21), (18, 22), (16, 23)):
        put(img, x, y, (120, 70, 40))
    return img


def gem_frames() -> list[Image.Image]:
    out = []
    for w in (12, 8, 2, 8):
        img = Image.new("RGBA", (16, 16), (0, 0, 0, 0))
        for y in range(1, 16):
            hw = (w / 2) * (1 - abs(y - 6) / (5 if y <= 6 else 9))
            for x in range(16):
                if abs(x - 7.5) <= hw + 0.01:
                    put(img, x, y, (250, 120, 220) if x < 8 else (190, 60, 170))
        put(img, 6, 4, (255, 240, 255))
        out.append(img)
    return out


def hero_frames() -> list[Image.Image]:
    """Facing the screen (walking down-right) in two steps, then from behind (up-right) in two: the game mirrors them for the others."""
    out = []
    for back in (False, True):
        for step in (0, 1):
            img = Image.new("RGBA", (16, 24), (0, 0, 0, 0))
            for y in range(1, 11):  # head and hat
                for x in range(4, 12):
                    if (x - 7.5) ** 2 + (y - 6) ** 2 <= 14:
                        put(img, x, y, HERO["hat"] if y < 5 or back else HERO["skin"])
            for x in range(2, 14):
                put(img, x, 4, HERO["hat"])
            if not back:
                put(img, 9, 7, HERO["eye"]), put(img, 6, 7, HERO["eye"])
            for y in range(11, 18):  # body, and the pack on the back
                for x in range(4, 12):
                    put(img, x, y, HERO["pack"] if back and 5 <= x <= 10 and y < 17 else HERO["shirt"])
            for y in range(18, 23):  # legs, one forward on the second step
                lx, rx = (5, 9) if step == 0 else (4, 10)
                for x in (lx, lx + 1, rx, rx + 1):
                    put(img, x, y - (1 if step and x >= rx and y == 22 else 0), HERO["legs"])
            out.append(img)
    return out


def shadow() -> Image.Image:
    img = Image.new("RGBA", (16, 8), (0, 0, 0, 0))
    for y in range(8):
        for x in range(16):
            if ((x - 7.5) / 7.5) ** 2 + ((y - 3.5) / 3.5) ** 2 <= 1 and (x + y) % 2 == 0:  # a checker: what is under it shows
                put(img, x, y, (24, 30, 24))
    return img


def splash_frames() -> list[Image.Image]:
    out = []
    for r in (3, 5, 7):
        img = Image.new("RGBA", (16, 16), (0, 0, 0, 0))
        for ang in range(0, 360, 30):
            x, y = 8 + math.cos(math.radians(ang)) * r, 10 + math.sin(math.radians(ang)) * r * 0.5 - (7 - r)
            put(img, int(x), int(y), (230, 244, 255) if ang % 60 == 0 else GLINT)
        out.append(img)
    return out


def strip(frames: list[Image.Image]) -> Image.Image:
    w, h = frames[0].size
    img = Image.new("RGBA", (w * len(frames), h), (0, 0, 0, 0))
    for i, f in enumerate(frames):
        img.paste(f, (i * w, 0))
    return img


def main() -> None:
    ART.mkdir(exist_ok=True)
    ASSETS.mkdir(exist_ok=True)
    for f in ASSETS.glob("*"):
        f.unlink()
    rows = level_rows()
    bg = seed_palette(ASSETS / "WORLD.pal", {**WATER, **GROUND})
    draw_floor(rows)
    sprites = {f"COL{k}": [column(k)] for k in range(1, 5)}
    sprites.update({"CRATE": [crate()], "RAFT": [crate(4)], "PALM": [palm()], "GEM": gem_frames(), "HERO": hero_frames(),
                    "SHADOW": [shadow()], "SPLASH": splash_frames()})
    for name, frames in sprites.items():
        strip(frames).save(ART / f"{name.lower()}.png")
    py, png = sys.executable, str(ROOT / "tools" / "png2asset.py")
    subprocess.run([py, png, str(ART / "floor.png"), str(ASSETS), "FLOOR", "--tiles", "--palette", "WORLD"], check=True)
    for name, frames in sprites.items():
        subprocess.run([py, png, str(ART / f"{name.lower()}.png"), str(ASSETS), name, "--indexed", "--frames", str(len(frames)),
                        "--palette", "OBJ"], check=True)
    lines = ["-- made by art.py: the ground's geometry, and where the water's entries sit in the background palette",
             f"return {{ox = {OX}, oy = {OY}, w = {IMG_W}, h = {IMG_H}, water = {{{bg['water']}, {bg['wa']}, {bg['wb']}, {bg['wc']}}},",
             f"  base = 0x{'%02X%02X%02X' % WATER['water']}, glint = 0x{'%02X%02X%02X' % GLINT}}}"]
    (HERE / "index.lua").write_text("\n".join(lines) + "\n")


if __name__ == "__main__":
    main()
