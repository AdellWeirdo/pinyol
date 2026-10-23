# /// script
# requires-python = ">=3.10"
# dependencies = ["pillow>=10.1", "fonttools>=4"]
# ///
"""The run and gun's pictures and letters.

    uv run examples/asalto/art.py      # art/*.png -> assets/ (packed), and its fonts

art/ holds the pictures at the game's size (art/make_art.py made them from generated images): the canyon far behind,
the street in front, the heroine (0 still, 1-5 running, 6-10 firing), the scrap robot (0 still, 1-4 walking, 5
firing), the walking tank (the same) and an explosion in five frames. All packed: a palette each, only the opaque
runs, column by column.
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
    convert("far.png", "BG_FAR", "--type", "background")
    convert("near.png", "BG_NEAR", "--type", "background")
    convert("hero.png", "SPR_HERO", "--frames", "11", "--anchor", "50,94")
    convert("robot.png", "SPR_ROBOT", "--frames", "6", "--anchor", "52,78")
    convert("walker.png", "SPR_WALKER", "--frames", "6", "--anchor", "150,158")
    convert("boom.png", "SPR_BOOM", "--frames", "5", "--anchor", "72,72")
    sys.path.insert(0, str(ROOT / "tools"))
    import font2fnt
    font2fnt.build("pressstart2p", str(HERE / "fonts" / "arcade.fnt"), None, 2)
    for f in ("FONT_MAIN.fnt", "FONT_BOLD.fnt", "FONT_MAIN_L.fnt", "FONT_BOLD_L.fnt"):  # the engine's own, as every game
        shutil.copy(ROOT / "examples" / "naves" / "fonts" / f, HERE / "fonts" / f)


if __name__ == "__main__":
    main()
