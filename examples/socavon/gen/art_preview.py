"""art/zx_preview.png and art/zx_rooms.png: the real rooms (rooms.lua) drawn with the art in their Spectrum colours,
the miner at the start and the guardians where they begin, each sprite in the ink of the block under its centre (the
game's colour clash). Scratch pictures to judge the art in context; the game does not read them."""
from __future__ import annotations

import re
from pathlib import Path

from PIL import Image

HERE = Path(__file__).resolve().parent.parent
NAMES = {"black": (0, 0, 0), "blue": (0, 0, 1), "red": (1, 0, 0), "magenta": (1, 0, 1), "green": (0, 1, 0),
         "cyan": (0, 1, 1), "yellow": (1, 1, 0), "white": (1, 1, 1)}
KIND = {"#": "wall", "=": "floor", "-": "crumble", ">": "conveyor", "<": "conveyor", "*": "hazard", "^": "hazard",
        "v": "hazard", "k": "key", "X": "portal"}
DECO = {"1": "deco_beam_h", "2": "deco_beam_v", "3": "deco_pipe_h", "4": "deco_pipe_v", "l": "deco_lamp", "w": "deco_web",
        "r": "deco_rail", "s": "deco_skull", "c": "deco_crystal"}
FIXED = {"-": "crumble_0", ">": "conv_r_0", "<": "conv_l_0", "*": "plant_a", "^": "spike", "v": "stalac", "k": "key"}


def colour(spec: str) -> tuple[tuple, tuple]:
    bright = spec.startswith("+")
    ink, paper = spec.lstrip("+").split("/")
    v = 255 if bright else 215
    return tuple(c * v for c in NAMES[ink]), tuple(c * v for c in NAMES[paper])


def rooms() -> list[dict]:
    src = HERE / "rooms.lua"
    if not src.exists():
        return []
    out = []
    for block in re.split(r"\n  \{\n", src.read_text())[1:]:
        tiles = re.findall(r'^\s+"([^"]{28})",?$', block, re.M)
        scheme = dict(re.findall(r'(\w+) = "(\+?\w+/\w+)"', block.split("tiles")[0]))
        theme = int(re.search(r"theme = (\d)", block).group(1))
        guards = [(k, float(x), float(y)) for k, x, y in re.findall(r'kind = "(\w+)", x = ([\d.]+), y = ([\d.]+)', block)]
        name = re.search(r'id = "(\w+)"', block).group(1)
        out.append({"id": name, "tiles": tiles, "scheme": scheme, "theme": "abcd"[theme - 1], "guards": guards})
    return out


def tile_name(rm: dict, x: int, y: int, open_portal: bool) -> str:
    c = rm["tiles"][y][x]
    if c == "#":
        return "wall_" + rm["theme"]
    if c == "=":
        return "floor_" + rm["theme"]
    if c == "X":
        top = y == 0 or rm["tiles"][y - 1][x] != "X"
        left = x == 0 or rm["tiles"][y][x - 1] != "X"
        return ("portal_open_" if open_portal else "portal_") + ("t" if top else "b") + ("l" if left else "r")
    return FIXED.get(c) or DECO.get(c) or "air"


def kind(c: str) -> str:
    return KIND.get(c) or ("deco" if c in DECO else "air")


def render(ART, rm: dict, open_portal: bool = False) -> Image.Image:
    img = Image.new("RGB", (28 * 8, 16 * 8))
    px = img.load()
    for y in range(16):
        for x in range(28):
            ink, paper = colour(rm["scheme"].get(kind(rm["tiles"][y][x]), "white/black"))
            for j, row in enumerate(ART.tiles[tile_name(rm, x, y, open_portal)]):
                for i, ch in enumerate(row):
                    px[x * 8 + i, y * 8 + j] = ink if ch == "X" else paper
    sprites = []
    for y, row in enumerate(rm["tiles"]):
        if "P" in row:
            sprites.append(("MINER", "stand", row.index("P") * 8, y * 8))
    for k, gx, gy in rm["guards"]:
        sprites.append(("ENEMY", f"{k}_0", int(gx * 8), int(gy * 8)))
    for sheet, name, sx, sy in sprites:
        frames = dict(ART.sheets[sheet]["frames"])
        cx, cy = min(27, (sx + 8) // 8), min(15, (sy + 8) // 8)
        ink, _ = colour(rm["scheme"].get(kind(rm["tiles"][cy][cx]), "white/black"))
        for j, row in enumerate(frames[name]):
            for i, ch in enumerate(row):
                if ch == "X" and 0 <= sx + i < 224 and 0 <= sy + j < 128:
                    px[sx + i, sy + j] = ink
    return img


def make(ART) -> None:
    rms = rooms()
    if not rms:
        print("no rooms.lua yet: no preview")
        return
    shots = [render(ART, rm, open_portal=(i % 2 == 1)) for i, rm in enumerate(rms)]
    # zx_preview: the first room at 3x over the eight rooms at 1x
    big = shots[0].resize((224 * 3, 128 * 3), Image.NEAREST)
    cols = 3
    rows = (len(shots) + cols - 1) // cols
    sheet = Image.new("RGB", (max(672, cols * 232), 384 + 8 + rows * 136), (48, 48, 48))
    sheet.paste(big, (0, 0))
    for i, s in enumerate(shots):
        sheet.paste(s, ((i % cols) * 232, 392 + (i // cols) * 136))
    sheet.save(HERE / "art" / "zx_preview.png")
    # zx_rooms: every room at 2x, to look at the details
    two = Image.new("RGB", (2 * 456, ((len(shots) + 1) // 2) * 264), (48, 48, 48))
    for i, s in enumerate(shots):
        two.paste(s.resize((448, 256), Image.NEAREST), ((i % 2) * 456, (i // 2) * 264))
    two.save(HERE / "art" / "zx_rooms.png")
    print(f"preview: {len(shots)} rooms")
