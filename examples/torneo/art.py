# /// script
# requires-python = ">=3.10"
# dependencies = ["pillow>=10.1", "fonttools>=4"]
# ///
"""The CPS2-style fighting game's pictures and letters.

    uv run examples/torneo/art.py      # art/*.png -> assets/, and its fonts

art/ holds the pictures at the game's size (art/make_art.py made them): the courtyard far behind, the floor (a plain
picture, not packed: the game draws it in bands of rows, each moved by its own amount, for the perspective), the pillars
in front, and each fighter's thirty frames in 15 colours and see-through, which packed is four bits a pixel: 0-4
standing, 5-9 walking, 10-14 a slash, 15-19 a kick, 20 hurt, 21 reeling, 22 guarding, 23 falling, 24 lying, 25-29 a
jump. <name>_b.png is the same fighter in the second player's colours: the game only borrows its palette.
"""
from __future__ import annotations

import shutil
import subprocess
import sys
from pathlib import Path

HERE = Path(__file__).resolve().parent
ROOT = HERE.parent.parent


def convert(png: str, aid: str, *opts: str) -> None:
    subprocess.run([sys.executable, str(ROOT / "tools" / "png2asset.py"), str(HERE / "art" / png), str(HERE / "assets"),
                    aid, *opts], check=True)


def main() -> None:
    convert("stage_far.png", "BG_FAR", "--packed", "--type", "background")
    convert("stage_floor.png", "BG_FLOOR", "--type", "background")
    convert("stage_front.png", "BG_FRONT", "--packed", "--type", "background")
    for name in ("alba", "gorm"):
        for suffix in ("", "_b"):
            convert(f"{name}{suffix}.png", f"SPR_{name.upper()}{suffix.upper()}", "--packed", "--colours", "16",
                    "--frames", "30", "--anchor", "76,172")
    sys.path.insert(0, str(ROOT / "tools"))
    import font2fnt
    font2fnt.build("pressstart2p", str(HERE / "fonts" / "arcade.fnt"), None, 2)
    for f in ("FONT_MAIN.fnt", "FONT_BOLD.fnt", "FONT_MAIN_L.fnt", "FONT_BOLD_L.fnt"):  # the engine's own, as every game
        shutil.copy(ROOT / "examples" / "naves" / "fonts" / f, HERE / "fonts" / f)


if __name__ == "__main__":
    main()
