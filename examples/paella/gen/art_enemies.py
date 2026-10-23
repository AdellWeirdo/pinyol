"""Paella de Combate: builds every enemy / ally / pickup / fx sheet and the bestiary board.

    python3 examples/paella/gen/art_enemies.py

Sheets (art/<name>.png + .json + preview_<name>.png): gull_soldier, gull_bazooka, gull_drone, gull_kamikaze, crab_tank,
grandma, fisherman, items, explosions, shots, props; plus art/bestiary.png (idle frames at 1x next to an 86 px chef box).
Painter: enemies_kit.py (shapes, ramps, outlines, sheets); rigs: gull_parts.py, person_parts.py, fx_parts.py.
"""
from __future__ import annotations

import json
import sys
from pathlib import Path

import numpy as np
from PIL import Image, ImageDraw

sys.path.insert(0, str(Path(__file__).resolve().parent))
import art_enemies_allies  # noqa: E402
import art_enemies_bazooka  # noqa: E402
import art_enemies_crab  # noqa: E402
import art_enemies_drone  # noqa: E402
import art_enemies_fx  # noqa: E402
import art_enemies_items  # noqa: E402
import art_enemies_kamikaze  # noqa: E402
import art_enemies_soldier  # noqa: E402
from enemies_kit import ART  # noqa: E402

GROUND_Y = 150


def frame(name, fr):
    meta = json.loads((ART / f"{name}.json").read_text())
    im = Image.open(ART / f"{name}.png")
    i = meta["frames"].index(fr)
    w, h = meta["w"], meta["h"]
    return im.crop((i * w, 0, i * w + w, h)), meta["anchor"]


def bestiary():
    entries = [("gull_soldier", "idle_0", None), ("gull_bazooka", "idle_0", None), ("gull_drone", "fly_0", 70),
               ("gull_kamikaze", "idle_0", 80), ("crab_tank", "idle_0", None), ("grandma", "tied_0", None),
               ("fisherman", "tied_0", None)]
    board = Image.new("RGB", (1040, 190), (128, 128, 128))
    d = ImageDraw.Draw(board)
    d.rectangle([0, GROUND_Y + 1, board.width, board.height], fill=(96, 84, 76))
    x = 10
    # the chef-sized box (86 px tall) for scale
    d.rectangle([x, GROUND_Y - 86, x + 30, GROUND_Y], outline=(255, 255, 255))
    d.text((x + 2, GROUND_Y - 98), "chef", fill=(255, 255, 255))
    x += 44
    for name, fr, fly_y in entries:
        img, (ax, ay) = frame(name, fr)
        ys, xs = np.nonzero(np.array(img)[..., 3])
        x0, x1 = xs.min(), xs.max()
        top = (fly_y if fly_y is not None else GROUND_Y) - ay
        board.paste(img, (x - x0, top), img)
        d.text((x, 4), name, fill=(240, 240, 240))
        x += (x1 - x0) + 16
    board = board.crop((0, 0, min(board.width, x + 4), board.height))
    board.save(ART / "bestiary.png")
    board.resize((board.width * 2, board.height * 2), Image.NEAREST).save(ART / "preview_bestiary.png")


def main():
    art_enemies_soldier.build()
    art_enemies_bazooka.build()
    art_enemies_drone.build()
    art_enemies_kamikaze.build()
    art_enemies_crab.build()
    art_enemies_allies.build()
    art_enemies_items.build()
    art_enemies_fx.build()
    bestiary()


if __name__ == "__main__":
    main()
