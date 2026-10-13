# /// script
# requires-python = ">=3.10"
# dependencies = ["pillow>=10.1", "fonttools>=4"]
# ///
"""CONTROL's pictures and letters.

    uv run examples/control/art.py      # art/*.png -> assets/ (packed), and its fonts

art/ holds the pictures at the game's size (art/make_art.py made them, and the clip video/VTR.npv): the control
room, each camera's shot small (a source monitor) and big (the programme monitor), and CAM 00.
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
                    aid, "--packed", *opts], check=True, stdout=subprocess.DEVNULL)


def main() -> None:
    convert("room.png", "BG_ROOM", "--type", "background")
    for cam in ("cam1", "cam2", "cam3", "cam00"):
        convert(f"{cam}_s.png", f"{cam.upper()}_S", "--type", "background")
        convert(f"{cam}_b.png", f"{cam.upper()}_B", "--type", "background")
    convert("cam00_z.png", "CAM00_Z", "--type", "background")
    sys.path.insert(0, str(ROOT / "tools"))
    import font2fnt
    font2fnt.build("vt323", str(HERE / "fonts" / "vt.fnt"), None, 1)
    font2fnt.build("jersey20", str(HERE / "fonts" / "title.fnt"), None, 1)
    for f in ("FONT_MAIN.fnt", "FONT_BOLD.fnt", "FONT_MAIN_L.fnt", "FONT_BOLD_L.fnt"):
        shutil.copy(ROOT / "examples" / "naves" / "fonts" / f, HERE / "fonts" / f)


if __name__ == "__main__":
    main()
