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
RAW = Path(os.environ.get("PAELLA_RAW", "/private/tmp/claude-501/-Users-pauavila-Desktop-DEV-pinyol/0c2c8ddb-2909-4ab2-9a6a-d16056eabb26/scratchpad/paella/gpt"))
ART = HERE.parent / "art"
FIT = ROOT / "tools" / "fit_sprite.py"
ALPHA_MIN = 16


def key_background(im: Image.Image, tol: int = 38) -> Image.Image:
    """A sheet with no real transparency (a flat colour, or a checkerboard drawn into the picture) gets one: the pixels like the background colours seen along its border,
    and connected to the border, become see-through (the character's own dark outline stops the flood)."""
    rgba = np.array(im.convert("RGBA"))
    if rgba[..., 3].min() < 255:
        return despeckle(Image.fromarray(rgba))
    rgb = rgba[..., :3].astype(int)
    border = np.concatenate([rgb[0], rgb[-1], rgb[:, 0], rgb[:, -1]])
    # the background colours: the few most common ones along the border (a checkerboard has two)
    q = (border // 8) * 8
    vals, counts = np.unique(q, axis=0, return_counts=True)
    keep = [vals[i] for i in np.argsort(-counts)[:3] if counts[i] > len(border) * 0.08]
    like = np.zeros(rgb.shape[:2], bool)
    for c in keep:
        like |= (np.abs(rgb - c).max(axis=2) <= tol)
    lab, _ = ndimage.label(like)
    edge_labels = set(np.unique(np.concatenate([lab[0], lab[-1], lab[:, 0], lab[:, -1]]))) - {0}
    bg = np.isin(lab, list(edge_labels))
    rgba[bg, 3] = 0
    return despeckle(Image.fromarray(rgba))


def despeckle(im: Image.Image, min_area: int = 500) -> Image.Image:
    """Specks the keying left (bits of the checkerboard, stray pixels) are removed: opaque blobs smaller than `min_area` pixels."""
    a = np.array(im.getchannel("A")) >= ALPHA_MIN
    lab, n = ndimage.label(a)
    if n:
        sizes = ndimage.sum(a, lab, range(1, n + 1))
        small = np.isin(lab, [i + 1 for i, sz in enumerate(sizes) if sz < min_area])
        rgba = np.array(im)
        rgba[small, 3] = 0
        im = Image.fromarray(rgba)
    return im


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


def solid(im: Image.Image) -> Image.Image:
    im = im.convert("RGBA")
    im.putalpha(im.getchannel("A").point(lambda v: 255 if v >= 128 else 0))
    return im


def quantized(im: Image.Image, colours: int) -> Image.Image:
    a = im.getchannel("A")
    rgb = im.convert("RGB").quantize(colours, method=Image.Quantize.MEDIANCUT, dither=Image.Dither.NONE).convert("RGB")
    rgb.putalpha(a)
    return rgb


def cut_columns(a: np.ndarray, n: int) -> list[tuple[int, int]]:
    """The n cells of a sheet, cut at the emptiest column near each expected boundary (frames can touch or overlap a little: a cut through a thin gap is better than an even one)."""
    w = a.shape[1]
    occ = a.sum(axis=0).astype(float)
    cuts = [0]
    for i in range(1, n):
        centre = round(i * w / n)
        half = max(4, w // n // 3)
        lo, hi = max(cuts[-1] + 1, centre - half), min(w - 1, centre + half)
        window = occ[lo:hi + 1]
        best = lo + int(np.argmin(window + np.abs(np.arange(lo, hi + 1) - centre) * 0.01))
        cuts.append(best)
    cuts.append(w)
    return list(zip(cuts[:-1], cuts[1:]))


def drop_border_bits(sub: np.ndarray) -> np.ndarray:
    """Pieces of a neighbour cut by the cell's edge: components touching the left or right edge that are small beside the biggest one are removed."""
    lab, k = ndimage.label(sub)
    if k < 2:
        return sub
    sizes = ndimage.sum(sub, lab, range(1, k + 1))
    big = sizes.max()
    keep = np.ones_like(sub, bool)
    for i in range(1, k + 1):
        comp = lab == i
        if sizes[i - 1] < 0.35 * big and (comp[:, 0].any() or comp[:, -1].any()):
            keep &= ~comp
    return sub & keep


def fit_sheet(keyed: Image.Image, n: int, frame: tuple[int, int], anchor: tuple[int, int], kf: int | None, height: int, const_frac: float = 0.70) -> list[Image.Image]:
    """The n frames of a sheet as frames of the game: cut left to right, every one scaled by the SAME factor (from the body of frame `kf` if it is upright, else
    from the sheet's height: the model draws a character about `const_frac` of a sheet's height), the body's centre on the anchor's column and the frames' common baseline
    (the median of their bottoms) on the anchor's row, so a jump stays above the floor and a lying frame lies on it."""
    keyed = keyed.convert("RGBA")
    a = np.array(keyed.getchannel("A")) >= ALPHA_MIN
    cols = a.any(axis=0)
    gap = max(6, keyed.width // 120)
    runs = cut_columns(a, n)
    pieces = []
    for x0, x1 in runs:
        sub = drop_border_bits(a[:, x0:x1])
        a[:, x0:x1] = sub
        lab, k = ndimage.label(sub)
        if k:
            sizes = ndimage.sum(sub, lab, range(1, k + 1))
            main = lab == (1 + int(np.argmax(sizes)))
        else:
            main = sub
        ys = np.where(main.any(axis=1))[0]
        xs = np.where(main.any(axis=0))[0]
        ally = np.where(sub.any(axis=1))[0]
        pieces.append({"x0": x0, "x1": x1, "top": int(ally.min()), "bottom": int(ally.max()) + 1, "mtop": int(ys.min()), "mbottom": int(ys.max()) + 1, "mcx": x0 + (int(xs.min()) + int(xs.max())) / 2})
    if kf is not None and 0 <= kf < len(pieces):
        scale = height / max(1, pieces[kf]["mbottom"] - pieces[kf]["mtop"])
    else:
        scale = height / (const_frac * keyed.height)
    base = float(np.median([p["mbottom"] for p in pieces]))
    out = []
    w, h = frame
    for p in pieces:
        crop = keyed.crop((p["x0"], p["top"], p["x1"], p["bottom"]))
        mask = Image.fromarray((a[p["top"]:p["bottom"], p["x0"]:p["x1"]] * 255).astype(np.uint8))
        crop.putalpha(ImageChops.multiply(crop.getchannel("A"), mask))
        crop = crop.resize((max(1, round(crop.width * scale)), max(1, round(crop.height * scale))), Image.LANCZOS)
        fr = Image.new("RGBA", (w, h))
        px = round(anchor[0] - (p["mcx"] - p["x0"]) * scale)
        py = round(anchor[1] + (p["bottom"] - base) * scale - crop.height)
        fr.alpha_composite(crop, (px, py)) if 0 <= px and 0 <= py and px + crop.width <= w and py + crop.height <= h else _paste_clipped(fr, crop, px, py)
        out.append(fr)
    return out


def _paste_clipped(fr: Image.Image, crop: Image.Image, px: int, py: int) -> None:
    """Pastes `crop` at (px, py) on `fr` cutting what falls outside (a long knife or a trail past the frame's edge)."""
    sx0, sy0 = max(0, -px), max(0, -py)
    sx1, sy1 = min(crop.width, fr.width - px), min(crop.height, fr.height - py)
    if sx1 > sx0 and sy1 > sy0:
        fr.alpha_composite(crop.crop((sx0, sy0, sx1, sy1)), (px + sx0, py + sy0))


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


def split_frames(im: Image.Image, n: int) -> list[Image.Image]:
    """The n objects of a sheet, left to right, each trimmed: the sheet is cut at the emptiest columns near the expected boundaries, bits of a neighbour that the cut left
    on an edge are removed."""
    im = im.convert("RGBA")
    a = np.array(im.getchannel("A")) >= ALPHA_MIN
    out = []
    for x0, x1 in cut_columns(a, n):
        sub = drop_border_bits(a[:, x0:x1])
        piece = im.crop((x0, 0, x1, im.height))
        piece.putalpha(ImageChops.multiply(piece.getchannel("A"), Image.fromarray((sub * 255).astype(np.uint8))))
        bb = Image.fromarray((sub * 255).astype(np.uint8)).getbbox()
        out.append(piece.crop(bb) if bb else piece)
    return out


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
