"""Puts the sprite strips of art/ in 16 colours (a Neo Geo sprite's palette had 15, and 16 colours are packed in 4 bits: a third less memory than any more): python3 gen/requantize.py [name ...]
The pictures' memory on the console (about 3 MB) is what holds Paella's frame rate down: the more of it a mission needs, the more pieces are let go and read again. The boss stays at 160 colours."""
import json
import sys
from pathlib import Path

from PIL import Image

sys.path.insert(0, str(Path(__file__).resolve().parents[3] / "tools"))
from sprite_kit import quantized  # noqa: E402

ART = Path(__file__).resolve().parent.parent / "art"
SKIP = {"boss", "ui", "logo", "boss_fx"}
names = sys.argv[1:] or [p.stem for p in sorted(ART.glob("*.json")) if p.stem not in SKIP and "faces" in json.loads(p.read_text()) or p.stem in ("items", "explosions", "props", "shots")]
for n in names:
    im = Image.open(ART / f"{n}.png").convert("RGBA")
    quantized(im, 16).save(ART / f"{n}.png")
    print(n, "16 colours")
