"""Turns the raw sheets the image model made (gen/gpt_jobs.py, gen/gpt_run.py) into the game's art: the background is taken off the sheets that came with a drawn checkerboard
or a flat colour, each sheet is cut into frames, scaled so the character's body is the same size in every sheet and every frame stands on the same baseline
(tools/fit_sprite.py), and the frames are put in one row with a json: art/chef_<id>.png + .json.

    python3 gen/gpt_make.py chef [id ...]
"""
from __future__ import annotations

import json
import os
import subprocess
import sys
import tempfile
from pathlib import Path

import numpy as np
from PIL import Image, ImageChops
from scipy import ndimage

HERE = Path(__file__).resolve().parent
sys.path.insert(0, str(HERE))
import gpt_jobs as J  # noqa: E402

ROOT = HERE.parents[2]
sys.path.insert(0, str(ROOT / "tools"))
from sprite_kit import (ALPHA_MIN, alternate, cut_columns, drop_border_bits, fit_sheet, key_background, quantized, sheet_scale, solid, split_frames)  # noqa: E402,F401
RAW = Path(os.environ.get("PAELLA_RAW", "/private/tmp/claude-501/-Users-pauavila-Desktop-DEV-pinyol/0c2c8ddb-2909-4ab2-9a6a-d16056eabb26/scratchpad/paella/gpt"))
ART = HERE.parent / "art"
FIT = ROOT / "tools" / "fit_sprite.py"
ALPHA_MIN = 16


def still_frame(ref: Path, out: Path, height: int) -> None:
    """The canonical picture scaled to `height` px of body and put on a frame, feet on the baseline: what every sheet is fitted to."""
    im = Image.open(ref).convert("RGBA")
    im = key_background(im)
    a = im.getchannel("A").point(lambda v: 255 if v >= ALPHA_MIN else 0)
    im = im.crop(a.getbbox())
    k = height / im.height
    im = im.resize((max(1, round(im.width * k)), height), Image.LANCZOS)
    w, h = J.CHEF_FRAME
    fr = Image.new("RGBA", (w, h))
    fr.alpha_composite(im, (J.CHEF_ANCHOR[0] - im.width // 2, J.CHEF_ANCHOR[1] - height))
    fr.save(out)


def make_chef(chef: str, colours: int = 160) -> None:
    ref = RAW / f"{chef}_ref.png"
    names: list[str] = []
    frames: list[Image.Image] = []
    with tempfile.TemporaryDirectory() as t:
        t = Path(t)
        still = t / "still.png"
        still_frame(ref, still, 90)
        for sheet, (n, _, fnames, kf, height) in J.SHEETS.items():
            raw = RAW / f"{chef}_{sheet}.png"
            if not raw.exists():
                print(f"  {chef}: {sheet} missing")
                continue
            for name, fr in zip(fnames, fit_sheet(key_background(Image.open(raw)), n, J.CHEF_FRAME, J.CHEF_ANCHOR, kf, height)):
                names.append(name)
                frames.append(fr)
    w, h = J.CHEF_FRAME
    strip = Image.new("RGBA", (w * len(frames), h))
    for i, f in enumerate(frames):
        strip.alpha_composite(solid(f.resize((w, h)) if f.size != (w, h) else f), (i * w, 0))
    ART.mkdir(exist_ok=True)
    quantized(strip, colours).save(ART / f"chef_{chef}.png")
    (ART / f"chef_{chef}.json").write_text(json.dumps({"w": w, "h": h, "anchor": list(J.CHEF_ANCHOR), "faces": "right", "frames": names}))
    print(f"  {chef}: {len(frames)} frames")


def make_enemy(eid: str, spec: dict, colours: int = 160) -> None:
    """A character of the enemy kind (a canonical picture and sheets fitted like the chefs'): art/<id>.png + json."""
    ref = RAW / f"{eid}_ref.png"
    w, h = spec["frame"]
    ax, ay = spec["anchor"]
    names, frames = [], []
    with tempfile.TemporaryDirectory() as t:
        t = Path(t)
        still = t / "still.png"
        im = key_background(Image.open(ref).convert("RGBA"))
        a = im.getchannel("A").point(lambda v: 255 if v >= ALPHA_MIN else 0)
        im = im.crop(a.getbbox())
        k = spec["height"] / im.height
        im = im.resize((max(1, round(im.width * k)), spec["height"]), Image.LANCZOS)
        fr = Image.new("RGBA", (w, h))
        fr.alpha_composite(im, (ax - im.width // 2, ay - spec["height"]))
        fr.save(still)
        # the raw sheets are NOT drawn at one scale (the model fits the character to each sheet: 30% bigger in a sheet of four poses than of six), so every sheet has its own, set by
        # an upright frame of it (its `kf`); a sheet with none (a jump, a fall) takes the size the model gives a body in a sheet of this height
        for sheet in spec["sheets"]:
            name, n, _, fnames, kf = sheet
            raw = RAW / f"{eid}_{name}.png"
            if not raw.exists():
                print(f"  {eid}: {name} missing")
                continue
            for fname, fr in zip(fnames, fit_sheet(key_background(Image.open(raw)), n, spec["frame"], spec["anchor"], kf, spec["height"])):
                names.append(fname)
                frames.append(fr)
    strip = Image.new("RGBA", (w * len(frames), h))
    for i, f in enumerate(frames):
        strip.alpha_composite(solid(f.resize((w, h)) if f.size != (w, h) else f), (i * w, 0))
    ART.mkdir(exist_ok=True)
    quantized(strip, colours).save(ART / f"{eid}.png")
    (ART / f"{eid}.json").write_text(json.dumps({"w": w, "h": h, "anchor": [ax, ay], "faces": spec["faces"], "frames": names}))
    print(f"  {eid}: {len(frames)} frames")


# per group: the biggest object of a sheet is scaled to this many px, and objects stand on the bottom (True) or are centred (False)
OBJECT_FIT = {"items": (46, True), "explosions": (184, False), "shots": (44, False), "props": (96, True)}


def make_objects(oid: str, spec: dict, colours: int = 128) -> None:
    w, h = spec["frame"]
    ax, ay = spec["anchor"]
    target, bottom = OBJECT_FIT[oid]
    names, frames = [], []
    for name, n, _, fnames in spec["sheets"]:
        raw = RAW / f"{oid}_{name}.png"
        if not raw.exists():
            print(f"  {oid}: {name} missing")
            continue
        pieces = split_frames(key_background(Image.open(raw)), n)
        big = max(max(p.width, p.height) for p in pieces)
        if oid == "props":
            big = pieces[0].height   # the intact one sets the scale; the broken ones are smaller or wider
            k = target / big
        else:
            k = target / big
        for fname, p in zip(fnames, pieces):
            p = p.resize((max(1, round(p.width * k)), max(1, round(p.height * k))), Image.LANCZOS)
            if p.width > w - 4 or p.height > h - 4:
                p.thumbnail((w - 4, h - 4))
            fr = Image.new("RGBA", (w, h))
            x = ax - p.width // 2
            y = (ay - p.height + 4) if bottom else (h // 2 - p.height // 2)
            fr.alpha_composite(p, (x, max(0, y)))
            names.append(fname)
            frames.append(fr)
    strip = Image.new("RGBA", (w * len(frames), h))
    for i, f in enumerate(frames):
        strip.alpha_composite(solid(f), (i * w, 0))
    ART.mkdir(exist_ok=True)
    quantized(strip, colours).save(ART / f"{oid}.png")
    (ART / f"{oid}.json").write_text(json.dumps({"w": w, "h": h, "anchor": [ax, ay], "frames": names}))
    print(f"  {oid}: {len(frames)} frames")


if __name__ == "__main__":
    what = sys.argv[1]
    if what == "chef":
        for c in (sys.argv[2:] or list(J.CHEFS)):
            make_chef(c)
    elif what == "enemy":
        for e in (sys.argv[2:] or list(J.ENEMIES)):
            make_enemy(e, J.ENEMIES[e])
    elif what == "tractor":
        make_enemy("tractor", J.TRACTOR)
    elif what == "obj":
        for o in (sys.argv[2:] or list(J.OBJECTS)):
            make_objects(o, J.OBJECTS[o])
