# /// script
# requires-python = ">=3.10"
# dependencies = ["pillow>=10.1", "fonttools>=4"]
# ///
"""The 32-bit (PlayStation / Saturn) gothic game's pictures and letters.

    uv run examples/gotico/art.py      # art/*.png -> assets/ (packed), and its fonts

art/ holds the pictures at the game's size (art/make_art.py made them): the castle hall (repeated, mirrored every
other time) and its columns in front, Lluna's twenty frames (0-4 standing, 5-9 walking, 10-14 the whip, 15-19 a jump),
a bat (five frames), the ghost, the boss skull, and two lights, a glow and a moonbeam. All in up to 256 colours.
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
    convert("hall_far.png", "BG_HALL", "--type", "background")
    convert("hall_near.png", "BG_COLUMNS", "--type", "background")
    convert("lluna.png", "SPR_LLUNA", "--frames", "20", "--anchor", "50,100")
    convert("bat.png", "SPR_BAT", "--frames", "5")
    convert("ghost.png", "SPR_GHOST")
    convert("boss.png", "SPR_BOSS")
    convert("glow.png", "FX_GLOW")
    convert("beam.png", "FX_BEAM")
    sys.path.insert(0, str(ROOT / "tools"))
    import font2fnt
    font2fnt.build("jacquard12", str(HERE / "fonts" / "gothic.fnt"), None, 2)
    font2fnt.build("pressstart2p", str(HERE / "fonts" / "arcade.fnt"), None, 2)
    for f in ("FONT_MAIN.fnt", "FONT_BOLD.fnt", "FONT_MAIN_L.fnt", "FONT_BOLD_L.fnt"):  # the engine's own, as every game
        shutil.copy(ROOT / "examples" / "naves" / "fonts" / f, HERE / "fonts" / f)


if __name__ == "__main__":
    main()
