# /// script
# requires-python = ">=3.10"
# dependencies = ["pillow>=10"]
# ///
"""Makes assets/LCD: the case, the printed picture and every figure's ghost, drawn by glass.lua (polygons) in the headless player and kept as one
picture, because a full-screen canvas costs ~100 ms a frame on the console and a picture ~1 ms.

    uv run examples/malabar/gen/make_glass.py
"""
import shutil
import subprocess
import sys
import tempfile
from pathlib import Path

from PIL import Image

HERE = Path(__file__).resolve().parent.parent
ROOT = HERE.parents[1]


def main() -> None:
    with tempfile.TemporaryDirectory() as t:
        t = Path(t)
        g = t / "glass"
        (g / "fonts").mkdir(parents=True)
        for f in ("shapes.lua", "glass.lua", "game.json"):
            shutil.copy(HERE / f, g / f)
        for f in (HERE / "fonts").glob("*.fnt"):
            shutil.copy(f, g / "fonts" / f.name)
        (g / "main.lua").write_text('local G = require("glass")\nfunction _init() show(0) end\nfunction _draw() G.paint() end\nfunction _update() end\n')
        (t / "s.script").write_text("tick 3\nshot glass\nexpect_ok\n")
        subprocess.run([str(ROOT / "build" / "pinyol_headless"), "--game", str(g), "--saves", str(t / "saves"), "--fresh", "--script",
                        str(t / "s.script")], check=True, stdout=subprocess.DEVNULL)
        Image.open(t / "saves" / "glass.ppm").convert("RGB").save(t / "glass.png")
        (HERE / "assets").mkdir(exist_ok=True)
        subprocess.run([sys.executable, str(ROOT / "tools" / "png2asset.py"), str(t / "glass.png"), str(HERE / "assets"), "LCD",
                        "--type", "background"], check=True)


if __name__ == "__main__":
    main()
