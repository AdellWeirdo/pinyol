# /// script
# requires-python = ">=3.10"
# dependencies = ["pillow>=10"]
# ///
"""A game's cover for the Cirera's menu: cover.rgb565 in its folder, 240x160 (half the screen: games draw their
world twice as big, so its pixels stay whole), RGB565 little endian as the console reads it.

    python3 tools/cover.py games/mygame                     # its title screen, a second and a half in
    python3 tools/cover.py games/mygame --from shot.png     # any picture, cut to 3:2 and halved
    python3 tools/cover.py games/mygame --at 300 --keys "RIGHT 60"   # later, after some play

A game with no cover gets a card with its title in the menu. pack_game.py packs the cover with the game.
"""
from __future__ import annotations

import argparse
import subprocess
import sys
import tempfile
from pathlib import Path

from PIL import Image

ROOT = Path(__file__).resolve().parent.parent
W, H = 240, 160


def shot(game: Path, headless: Path, at: int, keys: str) -> Image.Image:
    with tempfile.TemporaryDirectory() as t:
        script = Path(t) / "cover.script"
        lines = ["new", "tick 2"] + [f"hold {k}" for k in keys.split(",") if k.strip()] + [f"tick {at}", "shot cover"]
        script.write_text("\n".join(lines) + "\n")
        subprocess.run([str(headless), "--game", str(game), "--saves", t, "--fresh", "--script", str(script)],
                       check=True, capture_output=True)
        return Image.open(Path(t) / "cover.ppm").convert("RGB")


def cover(img: Image.Image) -> Image.Image:
    img = img.convert("RGB")
    if img.width * 2 != img.height * 3:  # cut to 3:2 around the middle
        w, h = (img.width, img.width * 2 // 3) if img.width * 2 < img.height * 3 else (img.height * 3 // 2, img.height)
        img = img.crop(((img.width - w) // 2, (img.height - h) // 2, (img.width + w) // 2, (img.height + h) // 2))
    return img.resize((W, H), Image.BOX)


def rgb565(img: Image.Image) -> bytes:
    raw, out = img.tobytes(), bytearray()
    for i in range(0, len(raw), 3):
        out += ((raw[i] >> 3) << 11 | (raw[i + 1] >> 2) << 5 | raw[i + 2] >> 3).to_bytes(2, "little")
    return bytes(out)


def main() -> None:
    ap = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    ap.add_argument("game", type=Path)
    ap.add_argument("--from", dest="src", type=Path, help="a picture instead of the game's own screen")
    ap.add_argument("--at", type=int, default=90, help="ticks of play before the shot (90: a second and a half)")
    ap.add_argument("--keys", default="", help='buttons held first, e.g. "A 2,RIGHT 60"')
    ap.add_argument("--headless", type=Path, default=ROOT / "build" / "pinyol_headless")
    a = ap.parse_args()
    if not (a.game / "game.json").exists():
        sys.exit(f"{a.game}: no game.json, not a game folder")
    img = Image.open(a.src) if a.src else shot(a.game, a.headless, a.at, a.keys)
    (a.game / "cover.rgb565").write_bytes(rgb565(cover(img)))
    print(f"{a.game}/cover.rgb565")


if __name__ == "__main__":
    main()
