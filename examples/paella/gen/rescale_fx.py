"""Puts every kind of effect of art/explosions.png at its own size (a small blast is not as big as a large one), the biggest frame of each kind at the size below, all the
frames of a kind by the same factor so it still grows and fades: python3 gen/rescale_fx.py"""
import json
import sys
from pathlib import Path

from PIL import Image

sys.path.insert(0, str(Path(__file__).resolve().parent))
import gpt_make as M  # noqa: E402

ART = Path(__file__).resolve().parent.parent / "art"
GROUPS = {"boom_s": 72, "boom_m": 112, "boom_l": 176, "boom_grenade": 150, "smoke": 84, "feathers": 96}
m = json.loads((ART / "explosions.json").read_text())
im = Image.open(ART / "explosions.png").convert("RGBA")
w, h = m["w"], m["h"]
ax, ay = m["anchor"]
crops = []
for i, n in enumerate(m["frames"]):
    f = im.crop((i * w, 0, (i + 1) * w, h))
    bb = f.getchannel("A").point(lambda v: 255 if v >= 128 else 0).getbbox()
    crops.append((n, f, bb))
big = {}
for n, f, bb in crops:
    g = n.rsplit("_", 1)[0]
    if bb:
        big[g] = max(big.get(g, 0), max(bb[2] - bb[0], bb[3] - bb[1]))
out = Image.new("RGBA", im.size)
for i, (n, f, bb) in enumerate(crops):
    g = n.rsplit("_", 1)[0]
    if not bb:
        continue
    # the frame's own centre of its ink moves with the scale: scale about the frame's centre so a blast stays centred where the game puts it
    k = GROUPS[g] / big[g] if g in GROUPS else 1.0
    c = f.crop(bb)
    c = c.resize((max(1, round(c.width * k)), max(1, round(c.height * k))), Image.LANCZOS)
    cx, cy = (bb[0] + bb[2]) / 2 - ax, (bb[1] + bb[3]) / 2 - ay
    fr = Image.new("RGBA", (w, h))
    px = round(ax + cx * k - c.width / 2)
    py = round(ay + cy * k - c.height / 2)
    px, py = min(max(px, 0), w - c.width), min(max(py, 0), h - c.height)
    fr.alpha_composite(M.solid(c), (px, py))
    out.alpha_composite(fr, (i * w, 0))
M.quantized(out, 128).save(ART / "explosions.png")
print("effects rescaled:", big)
