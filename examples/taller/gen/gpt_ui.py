"""The logo and the interface kit of the game, made with the image model (raw pictures in RAW_UI: logo.png, ui.png) and fitted: art/logo.png (one frame, anchor the top centre) and
art/ui.png (frames score, bar, life, gauge, boss, panel, anchor the top left). Paella has the same file.

    python3 gen/gpt_ui.py RAW_UI_DIR [colours]
"""
from __future__ import annotations

import json
import sys
from pathlib import Path

from PIL import Image

HERE = Path(__file__).resolve().parent
sys.path.insert(0, str(HERE))
import gpt_make as M  # noqa: E402

ART = HERE.parent / "art"
# name: widest and tallest the item may be in the game (px)
ITEMS = [("score", (170, 52)), ("bar", (190, 30)), ("life", (28, 28)), ("gauge", (28, 28)), ("boss", (330, 56)), ("panel", (300, 120))]
UI_FRAME = (330, 120)
LOGO_BOX = (420, 170)


def fit(p: Image.Image, box: tuple[int, int]) -> Image.Image:
    k = min(box[0] / p.width, box[1] / p.height)
    return p.resize((max(1, round(p.width * k)), max(1, round(p.height * k))), Image.LANCZOS)


def by_gaps(im: Image.Image, n: int) -> list[Image.Image]:
    """The n objects of a row, cut at the n - 1 widest empty gaps between them (objects of different widths: not an even split); each trimmed."""
    import numpy as np
    im = im.convert("RGBA")
    a = np.array(im.getchannel("A")) >= M.ALPHA_MIN
    occ = a.any(axis=0)
    xs = np.where(occ)[0]
    gaps = []  # (width, start, end) of every empty run between two occupied columns
    start = None
    for x in range(xs.min(), xs.max() + 1):
        if not occ[x] and start is None: start = x
        if occ[x] and start is not None: gaps.append((x - start, start, x)); start = None
    cuts = sorted(sorted(gaps, reverse=True)[: n - 1], key=lambda g: g[1])
    edges = [xs.min()] + [c for g in cuts for c in (g[1], g[2])] + [xs.max() + 1]
    out = []
    for i in range(n):
        x0, x1 = edges[2 * i], edges[2 * i + 1]
        piece = im.crop((x0, 0, x1, im.height))
        bb = piece.getchannel("A").point(lambda v: 255 if v >= M.ALPHA_MIN else 0).getbbox()
        out.append(piece.crop(bb) if bb else piece)
    return out


def main() -> None:
    raw = Path(sys.argv[1])
    colours = int(sys.argv[2]) if len(sys.argv) > 2 else 160
    w, h = UI_FRAME
    pieces = by_gaps(M.key_background(Image.open(raw / "ui.png")), len(ITEMS))
    strip = Image.new("RGBA", (w * len(ITEMS), h))
    sizes = {}
    for i, (p, (name, box)) in enumerate(zip(pieces, ITEMS)):
        f = fit(p, box)
        sizes[name] = [f.width, f.height]
        strip.alpha_composite(M.solid(f), (i * w, 0))
    ART.mkdir(exist_ok=True)
    M.quantized(strip, colours).save(ART / "ui.png")
    (ART / "ui.json").write_text(json.dumps({"w": w, "h": h, "anchor": [0, 0], "frames": [n for n, _ in ITEMS], "sizes": sizes}))
    lw, lh = LOGO_BOX
    logo = fit(M.split_frames(M.key_background(Image.open(raw / "logo.png")), 1)[0], LOGO_BOX)
    fr = Image.new("RGBA", (lw, lh))
    fr.alpha_composite(M.solid(logo), ((lw - logo.width) // 2, 0))
    M.quantized(fr, colours).save(ART / "logo.png")
    (ART / "logo.json").write_text(json.dumps({"w": lw, "h": lh, "anchor": [lw // 2, 0], "frames": ["logo"]}))
    print("ui:", [p.size for p in pieces], "logo:", logo.size)


if __name__ == "__main__":
    main()
