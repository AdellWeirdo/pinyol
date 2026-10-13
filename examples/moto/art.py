# /// script
# requires-python = ">=3.10"
# dependencies = ["pillow>=10.1", "fonttools>=4"]
# ///
"""The motorbike race's pictures and letters.

    uv run examples/carreras/art.py && uv run examples/moto/art.py   # the circuit is carreras': made there first

The circuit (TRACK tiles and map, WORLD palette) and its scoreboard fonts are examples/carreras' own, copied: the
road is the 240x160 world's Mode 7 floor. Over it, at full resolution, art/ (art/make_art.py made it): the coast on the
horizon, the bike leaning in five frames, its rivals' colours, five roadside things. Packed.
"""
from __future__ import annotations

import shutil
import subprocess
import sys
from pathlib import Path

HERE = Path(__file__).resolve().parent
ROOT = HERE.parent.parent
CARRERAS = ROOT / "examples" / "carreras"


def convert(png: str, aid: str, *opts: str) -> None:
    subprocess.run([sys.executable, str(ROOT / "tools" / "png2asset.py"), str(HERE / "art" / png), str(HERE / "assets"),
                    aid, "--packed", *opts], check=True)


def main() -> None:
    for f in ("TRACK.map", "TRACK.meta.json", "TRACK.tiles", "WORLD.pal"):
        shutil.copy(CARRERAS / "assets" / f, HERE / "assets" / f)
    shutil.copy(CARRERAS / "track.lua", HERE / "track.lua")
    convert("sky.png", "BG_COAST", "--type", "background")
    convert("bike.png", "SPR_BIKE", "--frames", "5", "--anchor", "64,127")
    convert("bike_blue.png", "PAL_BLUE", "--frames", "5")
    convert("bike_green.png", "PAL_GREEN", "--frames", "5")
    convert("props.png", "SPR_PROPS", "--frames", "5", "--anchor", "96,199")
    for f in (CARRERAS / "fonts").glob("*.fnt"):
        shutil.copy(f, HERE / "fonts" / f.name)


if __name__ == "__main__":
    main()
