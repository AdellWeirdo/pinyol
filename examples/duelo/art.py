# /// script
# requires-python = ">=3.10"
# dependencies = ["pillow>=10.1", "fonttools>=4"]
# ///
"""The fighting game's pictures and letters.

    uv run examples/duelo/art.py      # art/*.png -> assets/ (packed), and its fonts

art/ holds the pictures at the game's size (art/make_art.py made them from generated images): the stage's far layer
(sky, city, water) and near one (the crowd, the pier), and each fighter's frames in a row: 0 still, 1-5 walking, 6-10
striking. Packed (a palette, only the opaque runs, column by column), they are a seventh of their size as RGB565 and
fast enough for the whole screen at 60 frames a second on the console.
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
    convert("stage_far.png", "BG_FAR", "--type", "background")
    convert("stage_near.png", "BG_NEAR", "--type", "background")
    convert("kai.png", "SPR_KAI", "--frames", "11", "--anchor", "70,181")
    convert("ran.png", "SPR_RAN", "--frames", "11", "--anchor", "70,181")
    sys.path.insert(0, str(ROOT / "tools"))
    import font2fnt
    for name, src in (("arcade", "pressstart2p"), ("silk", "silkscreen")):
        font2fnt.build(src, str(HERE / "fonts" / f"{name}.fnt"), None, 2)
    for f in ("FONT_MAIN.fnt", "FONT_BOLD.fnt", "FONT_MAIN_L.fnt", "FONT_BOLD_L.fnt"):  # the engine's own, as every game
        shutil.copy(ROOT / "examples" / "naves" / "fonts" / f, HERE / "fonts" / f)


if __name__ == "__main__":
    main()
