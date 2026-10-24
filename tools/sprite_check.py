# /// script
# requires-python = ">=3.10"
# dependencies = ["pillow>=10", "numpy", "scipy"]
# ///
"""Audits a game's sprite strips for the mistakes that make a game's art look wrong: a frame cut by its cell, feet off the ground line, a character that changes size or jumps sideways
between animations. A strip is art/<name>.png (frames side by side) with art/<name>.json {w, h, anchor, frames}.

    uv run tools/sprite_check.py examples/taller/art              # every strip of a folder
    uv run tools/sprite_check.py examples/taller/art/vera.json    # one
    uv run tools/sprite_check.py GAME/art --contact out.png       # also a picture of each strip with its ground line and cell borders
    uv run tools/sprite_check.py GAME/art --regen                 # which raw sheets made the frames with errors (to ask the image model again: gen/gpt_run.py --redo ...)
    uv run tools/sprite_check.py GAME/art --fresh                 # art/ newer than the assets built from it (a build forgotten)
Exit 1 if there is an error. What it checks (the numbers are in the code, in pixels):

  clipped   an opaque pixel on the cell's border: the frame was cut (error). Only the body counts, not an effect that grazes the edge by a pixel.
  ground    the soles of the main body are not on the anchor's row (> 5 px): it floats or sinks (error). Frames named fall/jump/die/lie/dead/hurt are exempt from sinking only.
  size      the median height of an animation (idle, walk, atk...) is more than 35% off the character's standing height: it was scaled by a crouch or a pose (warning).
  centre    the middle of the feet is more than 14 px from the anchor's column in a standing or walking frame: the character slides sideways between frames (warning).
"""
from __future__ import annotations

import argparse
import json
import statistics
import sys
from pathlib import Path

import numpy as np
from PIL import Image, ImageDraw
from scipy import ndimage

sys.path.insert(0, str(Path(__file__).resolve().parent))
from sprite_kit import ALPHA_MIN, FEET  # noqa: E402

AIR = ("fall", "jump", "die", "lie", "dead", "hurt", "down", "getup", "fly", "boom", "hit")
STAND = ("idle", "walk", "run", "stand")
PRE = lambda n: n.rsplit("_", 1)[0]


def measure(a: np.ndarray) -> dict | None:
    """Body of one frame's alpha mask: its extent, the soles' row and the middle of its feet."""
    if not a.any():
        return None
    lab, k = ndimage.label(a)
    main = lab == (1 + int(np.argmax(ndimage.sum(a, lab, range(1, k + 1)))))
    ys = np.where(main.any(axis=1))[0]
    lo = int(ys.max()) - max(2, int(FEET * (ys.max() - ys.min())))
    fx = np.where(main[lo:ys.max() + 1].any(axis=0))[0]
    return {"sole": int(ys.max()) + 1, "height": int(ys.max() - ys.min() + 1), "feet": (int(fx.min()) + int(fx.max())) / 2}


def audit(json_path: Path) -> tuple[list[str], list[str], dict]:
    m = json.loads(json_path.read_text())
    png = json_path.with_suffix(".png")
    if not png.exists() or "frames" not in m:
        return [], [], {}
    w, h = m["w"], m["h"]
    ax, ay = m["anchor"]
    if m.get("edge_ok"):  # full-height pieces by design (a pillar): they may touch their cell
        return [], [], {}
    if ay < 0.15 * h:  # anchored at the top (interface frames fill their cell on purpose): nothing to check
        return [], [], {}
    grounded = ay >= 0.6 * h  # a character or a prop that stands on the anchor's row; an effect or a shot is centred on it
    alpha = np.array(Image.open(png).convert("RGBA").getchannel("A")) >= 128
    errs, warns, heights = [], [], {}
    for i, name in enumerate(m["frames"]):
        a = alpha[:, i * w:(i + 1) * w]
        ms = measure(a)
        if ms is None:
            continue
        room_below = h - ay >= 12  # a prop standing on the bottom of its cell touches it on purpose; with room below, touching it means something fell out of the cell
        cut = a[0].sum() > 2 or a[:, 0].sum() > 2 or a[:, -1].sum() > 2 or (room_below and a[-1].sum() > 2)
        if cut:
            errs.append(f"{json_path.stem}.{name}: clipped by its {w}x{h} cell")
        gap = ms["sole"] - ay
        floating = gap < -3 and name.split("_")[0] not in AIR
        if grounded and abs(gap) > 5 and (floating or gap > 5):
            errs.append(f"{json_path.stem}.{name}: soles {gap:+d} px from the ground row")
        heights.setdefault(PRE(name), []).append(ms["height"])
        if grounded and PRE(name) in STAND and abs(ms["feet"] - ax) > 14:
            warns.append(f"{json_path.stem}.{name}: feet {ms['feet'] - ax:+.0f} px off the anchor's column")
    ref = [statistics.median(v) for k, v in heights.items() if k in ("idle", "stand")]
    if ref:
        for k, v in heights.items():
            if k in AIR or k.startswith(("crouch", "crawl", "atk", "fight", "hop", "slam", "swing", "chime", "special", "throw", "grab", "gat", "stomp", "beam", "charge", "open", "pot")):
                continue
            if abs(statistics.median(v) / ref[0] - 1) > 0.35:
                warns.append(f"{json_path.stem}.{k}: {statistics.median(v):.0f} px tall against {ref[0]:.0f} standing")
    return errs, warns, heights


def bad_sheets(json_path: Path, errs: list[str]) -> list[str]:
    """The raw sheets (art/<id>.json's "raw": frame -> file) of the frames that have an error, without repeats."""
    raw = json.loads(json_path.read_text()).get("raw", {})
    frames = {e.split(": ")[0].split(".", 1)[1] for e in errs}
    return sorted({raw[f] for f in frames if f in raw})


def stale(art: Path) -> list[str]:
    """Strips whose picture is newer than the packed assets of the game (assets/SPR_<NAME>*.pk or .rgb565): art that was changed and not built again."""
    assets = art.parent / "assets"
    out = []
    for js in sorted(art.glob("*.json")):
        png = js.with_suffix(".png")
        built = [f for f in assets.glob(f"SPR_{js.stem.upper()}*") if f.suffix in (".pk", ".rgb565", ".idx")] if assets.is_dir() else []
        if png.exists() and (not built or max(f.stat().st_mtime for f in built) < png.stat().st_mtime - 1):
            out.append(js.stem)
    return out


def contact(json_path: Path, out: Path, cols: int = 10) -> None:
    m = json.loads(json_path.read_text())
    im = Image.open(json_path.with_suffix(".png")).convert("RGBA")
    w, h = m["w"], m["h"]
    n = len(m["frames"])
    s = Image.new("RGBA", (cols * w, ((n + cols - 1) // cols) * h), (90, 110, 140, 255))
    d = ImageDraw.Draw(s)
    for i in range(n):
        x, y = (i % cols) * w, (i // cols) * h
        s.alpha_composite(im.crop((i * w, 0, (i + 1) * w, h)), (x, y))
        d.line((x, y + m["anchor"][1], x + w, y + m["anchor"][1]), fill=(0, 255, 0, 255))
        d.line((x + m["anchor"][0], y, x + m["anchor"][0], y + h), fill=(255, 0, 0, 90))
        d.rectangle((x, y, x + w - 1, y + h - 1), outline=(255, 255, 0, 255))
        d.text((x + 3, y + 3), m["frames"][i], fill=(255, 255, 255, 255))
    s.convert("RGB").save(out)


def main() -> None:
    p = argparse.ArgumentParser(description=__doc__.split("\n\n")[0])
    p.add_argument("path", type=Path, help="a strip's .json or a folder of them")
    p.add_argument("--contact", type=Path, help="write a picture of each strip (out.png: out_<name>.png)")
    p.add_argument("--quiet", action="store_true", help="only errors")
    p.add_argument("--regen", action="store_true", help="say which raw sheets to ask the image model for again")
    p.add_argument("--fresh", action="store_true", help="say which art was not built into assets/ again")
    a = p.parse_args()
    files = sorted(a.path.glob("*.json")) if a.path.is_dir() else [a.path]
    bad = 0
    redo: set[str] = set()
    if a.fresh:
        old = stale(a.path if a.path.is_dir() else a.path.parent)
        for n in old:
            print("STALE", f"art/{n}.png is newer than its assets: build again (gen/build.py or tools/build_art.py)")
        bad += len(old)
    for f in files:
        errs, warns, _ = audit(f)
        redo.update(bad_sheets(f, errs))
        if not (errs or warns):
            continue
        for e in errs:
            print("ERROR", e)
        for w in warns:
            if not a.quiet:
                print("WARN ", w)
        bad += len(errs)
        if a.contact:
            contact(f, a.contact.with_name(f"{a.contact.stem}_{f.stem}.png"))
    if a.regen:
        print("REDO " + " ".join(sorted(redo)) if redo else "nothing to ask again (or the strips do not say their raw sheets: build them with sprite_kit)")
        if redo:
            print("  -> python3 gen/gpt_run.py --redo " + " ".join(sorted(redo)) + "   then gen/gpt_make.py and gen/build.py")
    print(f"{len(files)} strips: {bad} errors")
    sys.exit(1 if bad else 0)


if __name__ == "__main__":
    main()
