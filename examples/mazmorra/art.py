# /// script
# requires-python = ">=3.10"
# dependencies = ["pillow>=10.1", "fonttools>=4"]
# ///
"""The CPS2-style beat-em-up's pictures and letters.

    uv run examples/mazmorra/art.py      # art/*.png -> assets/ (packed), and its fonts

art/ holds the pictures at the game's size (art/make_art.py made them): the dungeon's wall and floor (repeated,
mirrored every other time), a pillar drawn in front of everyone, Alba from examples/torneo (thirty frames) and two
enemies of ten frames each, facing left (0-4 walking, 5 winding up, 6 striking, 7 recovering, 8 hurt, 9 down). Every
character is 15 colours and see-through, so packed it is four bits a pixel.
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
                    aid, "--packed", *opts], check=True)


def main() -> None:
    convert("dungeon.png", "BG_DUNGEON", "--type", "background")
    convert("pillar.png", "BG_PILLAR", "--type", "background")
    convert("alba.png", "SPR_ALBA", "--colours", "16", "--frames", "30", "--anchor", "76,172")
    for name in ("goblin", "skeleton"):
        convert(f"{name}.png", f"SPR_{name.upper()}", "--colours", "16", "--frames", "10", "--anchor", "110,156")
    sys.path.insert(0, str(ROOT / "tools"))
    import font2fnt
    font2fnt.build("pressstart2p", str(HERE / "fonts" / "arcade.fnt"), None, 2)
    for f in ("FONT_MAIN.fnt", "FONT_BOLD.fnt", "FONT_MAIN_L.fnt", "FONT_BOLD_L.fnt"):  # the engine's own, as every game
        shutil.copy(ROOT / "examples" / "naves" / "fonts" / f, HERE / "fonts" / f)


if __name__ == "__main__":
    main()
