# /// script
# requires-python = ">=3.10"
# dependencies = ["pillow>=10"]
# ///
"""Cuts a wide picture into columns, so only the ones on the screen need memory (lib/slices.lua draws them).

    uv run tools/slice_pic.py art/far.png games/mygame FAR                       # assets/FAR_0.pk, FAR_1.pk... (packed backgrounds)
    uv run tools/slice_pic.py art/far.png games/mygame FAR --width 160 --lua games/mygame/far_slices.lua

--width: a column's width in pixels (default 160: about 100 KB a column at 320 high, small enough to find a block on the console).
--lua: also writes the table `require("far_slices")` returns: {w, h, slices = {{id, x, w}, ...}}, what slices.draw wants.
Any other argument goes to png2asset.py (e.g. --colours 16).
"""
from __future__ import annotations

import argparse
import subprocess
import sys
import tempfile
from pathlib import Path

from PIL import Image

HERE = Path(__file__).resolve().parent


def slice_picture(png: Path, game: Path, name: str, width: int, extra: list[str]) -> dict:
    im = Image.open(png).convert("RGBA")
    out = []
    with tempfile.TemporaryDirectory() as tmp:
        for i, x in enumerate(range(0, im.width, width)):
            part = im.crop((x, 0, min(im.width, x + width), im.height))
            src = Path(tmp) / f"{name}_{i}.png"
            part.save(src)
            subprocess.run([sys.executable, str(HERE / "png2asset.py"), str(src), str(game / "assets"), f"{name}_{i}", "--packed", "--type", "background",
                            *extra], check=True, stdout=subprocess.DEVNULL)
            out.append({"id": f"{name}_{i}", "x": x, "w": part.width})
    return {"w": im.width, "h": im.height, "slices": out}


def lua_table(d: dict) -> str:
    rows = ", ".join(f'{{id = "{s["id"]}", x = {s["x"]}, w = {s["w"]}}}' for s in d["slices"])
    return f"-- made by tools/slice_pic.py: where each column of the picture goes (lib/slices.lua)\nreturn {{w = {d['w']}, h = {d['h']}, slices = {{{rows}}}}}\n"


def main() -> None:
    p = argparse.ArgumentParser(description=__doc__.split("\n\n")[0])
    p.add_argument("png", type=Path)
    p.add_argument("game", type=Path, help="the game's folder (the columns go to its assets/)")
    p.add_argument("name", help="the assets' name: NAME_0, NAME_1... (capitals, digits and _)")
    p.add_argument("--width", type=int, default=160)
    p.add_argument("--lua", type=Path, help="write the table lib/slices.lua draws from")
    a, extra = p.parse_known_args()
    if a.width < 8:
        sys.exit("--width: at least 8 pixels")
    (a.game / "assets").mkdir(parents=True, exist_ok=True)
    d = slice_picture(a.png, a.game, a.name, a.width, extra)
    if a.lua:
        a.lua.write_text(lua_table(d), encoding="utf-8")
    print(f"{a.name}: {len(d['slices'])} columns of {a.width} px from a {d['w']}x{d['h']} picture")


if __name__ == "__main__":
    main()
