# /// script
# requires-python = ">=3.10"
# dependencies = ["pillow>=10.1", "fonttools>=4"]
# ///
"""The football game's pictures and letters.

    uv run examples/futbol/art.py      # art/*.png -> assets/ (packed), and its fonts

art/ holds the pictures at the game's size (art/make_art.py made them): the left half of the pitch (the right half is
it mirrored), the footballer running in five frames, and the same in the other kits, whose palettes the game borrows.
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
    convert("pitch.png", "BG_PITCH", "--type", "background")
    convert("player.png", "SPR_PLAYER", "--frames", "5", "--anchor", "30,70")
    for kit in ("blue", "yellow", "green"):
        convert(f"kit_{kit}.png", f"KIT_{kit.upper()}", "--frames", "5")
    sys.path.insert(0, str(ROOT / "tools"))
    import font2fnt
    font2fnt.build("pressstart2p", str(HERE / "fonts" / "arcade.fnt"), None, 2)
    for f in ("FONT_MAIN.fnt", "FONT_BOLD.fnt", "FONT_MAIN_L.fnt", "FONT_BOLD_L.fnt"):
        shutil.copy(ROOT / "examples" / "naves" / "fonts" / f, HERE / "fonts" / f)


if __name__ == "__main__":
    main()
