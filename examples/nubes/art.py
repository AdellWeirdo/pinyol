# /// script
# requires-python = ">=3.10"
# dependencies = ["pillow>=10.1", "fonttools>=4"]
# ///
"""The shoot-em-up's pictures and letters.

    uv run examples/nubes/art.py      # art/*.png -> assets/ (packed), and its fonts

art/ holds the pictures at the game's size (art/make_art.py made them): the sky (mirrored every other time as it
repeats), the clouds in front, the ship, the drone spinning in five frames, the battleship, the explosion in five, the
orb the enemies fire and the ship's bolt.
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
    convert("sky.png", "BG_SKY", "--type", "background")
    convert("clouds.png", "BG_CLOUDS", "--type", "background")
    convert("ship.png", "SPR_SHIP")
    convert("drone.png", "SPR_DRONE", "--frames", "5")
    convert("boss.png", "SPR_BOSS")
    convert("boom.png", "SPR_BOOM", "--frames", "5")
    convert("orb.png", "SPR_ORB")
    convert("bolt.png", "SPR_BOLT")
    sys.path.insert(0, str(ROOT / "tools"))
    import font2fnt
    font2fnt.build("pressstart2p", str(HERE / "fonts" / "arcade.fnt"), None, 2)
    for f in ("FONT_MAIN.fnt", "FONT_BOLD.fnt", "FONT_MAIN_L.fnt", "FONT_BOLD_L.fnt"):  # the engine's own, as every game
        shutil.copy(ROOT / "examples" / "naves" / "fonts" / f, HERE / "fonts" / f)


if __name__ == "__main__":
    main()
