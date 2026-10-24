"""Puts every pickup of art/items.png at its own real size (a ham is not as big as a sardine), from the picture itself: python3 gen/rescale_items.py
The biggest side of each, in pixels next to a cook 90 px tall."""
import json
import sys
from pathlib import Path

from PIL import Image

sys.path.insert(0, str(Path(__file__).resolve().parent))
import gpt_make as M  # noqa: E402

ART = Path(__file__).resolve().parent.parent / "art"
SIZES = {"crate_a": 48, "crate_b": 48, "crate_c": 48, "ammo": 30, "heart": 26, "shield": 40, "food_jamon": 44, "food_cheese": 30, "food_paella": 40, "food_tortilla": 32,
         "food_melon": 30, "food_sardine": 28, "food_orange": 22, "food_bread": 32, "food_olive_can": 24, "food_wine_skin": 34, "food_churro": 30, "food_ensaimada": 28}
m = json.loads((ART / "items.json").read_text())
im = Image.open(ART / "items.png").convert("RGBA")
w, h = m["w"], m["h"]
ax, ay = m["anchor"]
out = Image.new("RGBA", im.size)
for i, n in enumerate(m["frames"]):
    f = im.crop((i * w, 0, (i + 1) * w, h))
    bb = f.getchannel("A").point(lambda v: 255 if v >= 128 else 0).getbbox()
    if not bb:
        continue
    c = f.crop(bb)
    if n in SIZES:
        k = SIZES[n] / max(c.size)
        c = c.resize((max(1, round(c.width * k)), max(1, round(c.height * k))), Image.LANCZOS)
    fr = Image.new("RGBA", (w, h))
    fr.alpha_composite(M.solid(c), (ax - c.width // 2, ay - c.height + 4))
    out.alpha_composite(fr, (i * w, 0))
M.quantized(out, 128).save(ART / "items.png")
print("items rescaled")
