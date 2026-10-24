# /// script
# requires-python = ">=3.10"
# dependencies = ["pillow>=10", "numpy", "scipy"]
# ///
"""What the engine knows about turning an image model's sheets into a game's sprites (the lessons of Paella and Taller, in one place). A library: import it from a game's gen/ script
(`sys.path.insert(0, ROOT / "tools"); import sprite_kit as K`) or read tools/sprite_check.py for the audit that checks what it makes.

The rules it keeps, each one a mistake that was made once:

  * **Every sheet has its own scale.** The model fits a character to the sheet: a sheet of four poses draws it 30% bigger than one of six. So no single scale works: each sheet is
    scaled by an UPRIGHT frame of it (`kf`: never a crouch, a tuck or arms in the air, or the whole sheet is scaled wrong). A sheet with no such frame (a jump, a fall) takes the
    size the model gives a body in a sheet of that height.
  * **The soles of the main body stand on the anchor's row in every frame**, jumps and falls too: the game lifts a jump with its own height (`z`), so a frame never carries it.
    The main body is the largest blob: sparks, smoke, gears and motion lines are not what stands.
  * **The feet, not the arm, are centred.** The anchor's column is the middle of the lowest 18% of the body: a punch that reaches out does not drag the character sideways.
  * **A frame is never cut.** It is moved inside its cell if it fits; a cell is made big enough, with room below the ground line for what falls (`auto_cell`).
  * **Things have their own size** next to the characters (`SIZES`: a barrel is not a street lamp), **and an effect has its kind's size** (`GROUPS`: a spark is a fist, not a hero),
    every frame of a kind scaled by the same factor so it still grows and fades.
  * **15 colours means `MAXCOVERAGE`**, not median cut (which turns a rare teal jacket brown), and a second set of colours is another palette in the same order (`alternate`).
"""
from __future__ import annotations

import colorsys
import json
from pathlib import Path

import numpy as np
from PIL import Image, ImageChops
from scipy import ndimage

ALPHA_MIN = 16
FEET = 0.18  # the lowest part of the body whose middle is where the feet are


# ------------------------------------------------------------------------------------------------------------------------------------------------ the background

def key_background(im: Image.Image, tol: int = 38) -> Image.Image:
    """A picture with no real transparency (a flat colour, or a checkerboard drawn into it) gets one: the pixels like the colours along its border, and joined to it, become see-through."""
    rgba = np.array(im.convert("RGBA"))
    if rgba[..., 3].min() < 255:
        return despeckle(Image.fromarray(rgba))
    rgb = rgba[..., :3].astype(int)
    border = np.concatenate([rgb[0], rgb[-1], rgb[:, 0], rgb[:, -1]])
    q = (border // 8) * 8
    vals, counts = np.unique(q, axis=0, return_counts=True)
    keep = [vals[i] for i in np.argsort(-counts)[:3] if counts[i] > len(border) * 0.08]
    like = np.zeros(rgb.shape[:2], bool)
    for c in keep:
        like |= np.abs(rgb - c).max(axis=2) <= tol
    lab, _ = ndimage.label(like)
    edge = set(np.unique(np.concatenate([lab[0], lab[-1], lab[:, 0], lab[:, -1]]))) - {0}
    rgba[np.isin(lab, list(edge)), 3] = 0
    return despeckle(Image.fromarray(rgba))


def despeckle(im: Image.Image, min_area: int = 500) -> Image.Image:
    """Specks the keying left (bits of the checkerboard) are removed: opaque blobs smaller than `min_area` pixels."""
    a = np.array(im.getchannel("A")) >= ALPHA_MIN
    lab, n = ndimage.label(a)
    if n:
        sizes = ndimage.sum(a, lab, range(1, n + 1))
        small = np.isin(lab, [i + 1 for i, sz in enumerate(sizes) if sz < min_area])
        rgba = np.array(im)
        rgba[small, 3] = 0
        im = Image.fromarray(rgba)
    return im


def solid(im: Image.Image) -> Image.Image:
    """Hard alpha: see-through or not, nothing between (the console draws opaque runs)."""
    im = im.convert("RGBA")
    im.putalpha(im.getchannel("A").point(lambda v: 255 if v >= 128 else 0))
    return im


# ------------------------------------------------------------------------------------------------------------------------------------------------ the colours

def quantized(im: Image.Image, colours: int) -> Image.Image:
    """One palette for the whole strip, no dithering, alpha kept. MAXCOVERAGE keeps a rare colour that median cut would merge into its neighbours."""
    a = im.getchannel("A")
    rgb = im.convert("RGB").quantize(colours, method=Image.Quantize.MAXCOVERAGE, dither=Image.Dither.NONE).convert("RGB")
    rgb.putalpha(a)
    return rgb


def alternate(img: Image.Image) -> Image.Image:
    """The second colours of a character: clothes turned half round the hue wheel, skin, hair and darks kept; the same pixels in the same palette order, so a game can draw the first
    strip with this one's palette (`img(..., {pal = "SPR_X_B"})`) and no pixel is stored twice."""
    rgb565 = lambda c: (c[0] >> 3, c[1] >> 2, c[2] >> 3)
    px = img.load()
    colours = sorted({px[x, y][:3] for y in range(img.height) for x in range(img.width) if px[x, y][3]})
    new, used, by565 = {}, set(), {}
    for c in colours:
        if rgb565(c) in by565:
            new[c] = by565[rgb565(c)]
            continue
        h, l, s = colorsys.rgb_to_hls(*(v / 255 for v in c))
        keep = (0.0 < h < 0.14 and l > 0.25) or l < 0.2
        n = tuple(round(v * 255) for v in colorsys.hls_to_rgb((h + 0.5) % 1, l, s)) if s > 0.25 and not keep else c
        while rgb565(n) in used:
            n = (n[0], min(255, n[1] + 4), min(255, n[2] + 8)) if n[2] < 248 else (n[0], max(0, n[1] - 4), n[2] - 16)
        used.add(rgb565(n))
        new[c] = by565[rgb565(c)] = n
    out = img.copy()
    po = out.load()
    for y in range(img.height):
        for x in range(img.width):
            if px[x, y][3]:
                po[x, y] = new[px[x, y][:3]] + (255,)
    return out


# ------------------------------------------------------------------------------------------------------------------------------------------------ cutting a sheet

def cut_columns(a: np.ndarray, n: int) -> list[tuple[int, int]]:
    """The n cells of a row, cut at the emptiest column near each expected boundary (frames may touch a little)."""
    w = a.shape[1]
    occ = a.sum(axis=0).astype(float)
    cuts = [0]
    for i in range(1, n):
        centre = round(i * w / n)
        half = max(4, w // n // 3)
        lo, hi = max(cuts[-1] + 1, centre - half), min(w - 1, centre + half)
        window = occ[lo:hi + 1]
        cuts.append(lo + int(np.argmin(window + np.abs(np.arange(lo, hi + 1) - centre) * 0.01)))
    cuts.append(w)
    return list(zip(cuts[:-1], cuts[1:]))


def cut_gaps(im: Image.Image, n: int) -> list[Image.Image]:
    """The n objects of a row of DIFFERENT widths (a plate, a bar, an icon), cut at the n - 1 widest empty gaps between them, each trimmed."""
    im = im.convert("RGBA")
    a = np.array(im.getchannel("A")) >= ALPHA_MIN
    occ = a.any(axis=0)
    xs = np.where(occ)[0]
    gaps, start = [], None
    for x in range(xs.min(), xs.max() + 1):
        if not occ[x] and start is None:
            start = x
        if occ[x] and start is not None:
            gaps.append((x - start, start, x))
            start = None
    cuts = sorted(sorted(gaps, reverse=True)[: n - 1], key=lambda g: g[1])
    edges = [xs.min()] + [c for g in cuts for c in (g[1], g[2])] + [xs.max() + 1]
    out = []
    for i in range(n):
        piece = im.crop((edges[2 * i], 0, edges[2 * i + 1], im.height))
        bb = piece.getchannel("A").point(lambda v: 255 if v >= ALPHA_MIN else 0).getbbox()
        out.append(piece.crop(bb) if bb else piece)
    return out


def drop_border_bits(sub: np.ndarray) -> np.ndarray:
    """Pieces of a neighbour cut by the cell's edge: components touching the left or right edge that are small beside the biggest are removed."""
    lab, k = ndimage.label(sub)
    if k < 2:
        return sub
    sizes = ndimage.sum(sub, lab, range(1, k + 1))
    keep = np.ones_like(sub, bool)
    for i in range(1, k + 1):
        comp = lab == i
        if sizes[i - 1] < 0.35 * sizes.max() and (comp[:, 0].any() or comp[:, -1].any()):
            keep &= ~comp
    return sub & keep


def split_frames(im: Image.Image, n: int) -> list[Image.Image]:
    """The n objects of an evenly spaced row, each trimmed."""
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


# ------------------------------------------------------------------------------------------------------------------------------------------------ fitting a character

def blobs(keyed: Image.Image, n: int):
    """Cut a sheet into its n cells and measure each: the whole opaque extent, the main blob (the body: the largest component) and the middle column of its feet."""
    a = np.array(keyed.getchannel("A")) >= ALPHA_MIN
    pieces = []
    for x0, x1 in cut_columns(a, n):
        sub = drop_border_bits(a[:, x0:x1])
        a[:, x0:x1] = sub
        lab, k = ndimage.label(sub)
        main = lab == (1 + int(np.argmax(ndimage.sum(sub, lab, range(1, k + 1))))) if k else sub
        ys = np.where(main.any(axis=1))[0]
        xs = np.where(main.any(axis=0))[0]
        ally = np.where(sub.any(axis=1))[0]
        lo = int(ys.max()) - max(2, int(FEET * (ys.max() - ys.min())))
        fx = np.where(main[lo:ys.max() + 1].any(axis=0))[0]
        pieces.append({"x0": x0, "x1": x1, "top": int(ally.min()), "bottom": int(ally.max()) + 1, "mtop": int(ys.min()), "mbottom": int(ys.max()) + 1,
                       "mcx": x0 + (int(xs.min()) + int(xs.max())) / 2, "fcx": x0 + (int(fx.min()) + int(fx.max())) / 2})
    return a, pieces


def sheet_scale(keyed: Image.Image, n: int, kf: int, height: int) -> float:
    """The scale that makes the body of frame `kf` (an UPRIGHT one) `height` pixels tall."""
    _, pieces = blobs(keyed.convert("RGBA"), n)
    return height / max(1, pieces[kf]["mbottom"] - pieces[kf]["mtop"])


def fit_sheet(keyed: Image.Image, n: int, frame: tuple[int, int], anchor: tuple[int, int], kf: int | None, height: int, const_frac: float = 0.70) -> list[Image.Image]:
    """The n frames of one sheet as frames of the game: scaled by the sheet's own factor (frame `kf`'s body = `height`; else the model's usual `const_frac` of the sheet's height),
    the middle of the feet on the anchor's column and the soles of the body on the anchor's row. A frame that would leave its cell is moved back inside, never cut."""
    keyed = keyed.convert("RGBA")
    a, pieces = blobs(keyed, n)
    scale = height / max(1, pieces[kf]["mbottom"] - pieces[kf]["mtop"]) if kf is not None and 0 <= kf < len(pieces) else height / (const_frac * keyed.height)
    out, (w, h) = [], frame
    for p in pieces:
        crop = keyed.crop((p["x0"], p["top"], p["x1"], p["bottom"]))
        crop.putalpha(ImageChops.multiply(crop.getchannel("A"), Image.fromarray((a[p["top"]:p["bottom"], p["x0"]:p["x1"]] * 255).astype(np.uint8))))
        crop = crop.resize((max(1, round(crop.width * scale)), max(1, round(crop.height * scale))), Image.LANCZOS)
        fr = Image.new("RGBA", (w, h))
        px = round(anchor[0] - (p["fcx"] - p["x0"]) * scale)
        py = round(anchor[1] - (p["mbottom"] - p["top"]) * scale)
        if crop.width <= w and crop.height <= h:
            px, py = min(max(px, 0), w - crop.width), min(max(py, 0), h - crop.height)
            fr.alpha_composite(crop, (px, py))
        else:
            fr.paste(crop.crop((max(0, -px), max(0, -py), min(crop.width, w - px), min(crop.height, h - py))), (max(0, px), max(0, py)))
        out.append(fr)
    return out


def auto_cell(frames: list[Image.Image], anchor: tuple[int, int], margin: int = 6, below: int = 24, step: int = 8) -> tuple[list[Image.Image], tuple[int, int], tuple[int, int]]:
    """Frames fitted on a big canvas (anchor in it) cropped to the smallest common cell that holds every one with `margin` round it and `below` pixels under the ground line (for what
    falls). Returns (frames, (w, h), anchor in the new cell). Use it to find a character's cell size, then write that size in the game's contract."""
    boxes = [f.getchannel("A").point(lambda v: 255 if v >= 128 else 0).getbbox() for f in frames]
    boxes = [b for b in boxes if b]
    half = max(max(anchor[0] - b[0], b[2] - anchor[0]) for b in boxes) + margin
    top = min(b[1] for b in boxes) - margin
    bottom = max(anchor[1] + below, max(b[3] for b in boxes) + margin)
    w = -(-2 * half // step) * step
    h = -(-(bottom - top) // step) * step
    x0, y0 = anchor[0] - w // 2, top
    return [f.crop((x0, y0, x0 + w, y0 + h)) for f in frames], (w, h), (w // 2, anchor[1] - y0)


def build_character(sheets: list[tuple[Image.Image, int, list[str], int | None]], height: int, frame: tuple[int, int] | None = None, anchor: tuple[int, int] | None = None,
                    colours: int = 15, faces: str = "right") -> tuple[Image.Image, dict]:
    """A whole character from its raw sheets [(image, frames in it, their names, upright frame or None)]: every sheet fitted (see fit_sheet), the frames in one row and one
    palette of `colours`. Without `frame`/`anchor` the cell is found (`auto_cell`). Returns (strip, json to write beside it)."""
    big = (int(height * 3.2) // 8 * 8, int(height * 2.6) // 8 * 8)
    big_anchor = (big[0] // 2, int(big[1] * 0.78))
    f0, a0 = (frame, anchor) if frame and anchor else (big, big_anchor)
    names, frames = [], []
    for im, n, fnames, kf in sheets:
        names += fnames
        frames += fit_sheet(key_background(im), n, f0, a0, kf, height)
    if not (frame and anchor):
        frames, f0, a0 = auto_cell(frames, a0)
    strip = Image.new("RGBA", (f0[0] * len(frames), f0[1]))
    for i, f in enumerate(frames):
        strip.alpha_composite(solid(f), (i * f0[0], 0))
    return quantized(strip, colours), {"w": f0[0], "h": f0[1], "anchor": list(a0), "faces": faces, "frames": names}


def write_strip(art: Path, name: str, strip: Image.Image, meta: dict, alt: bool = False) -> None:
    """art/<name>.png + .json (and <name>_b for the second colours)."""
    art.mkdir(parents=True, exist_ok=True)
    strip.save(art / f"{name}.png")
    (art / f"{name}.json").write_text(json.dumps(meta))
    if alt:
        alternate(strip).save(art / f"{name}_b.png")
        (art / f"{name}_b.json").write_text(json.dumps(meta))


# ------------------------------------------------------------------------------------------------------------------------------------------------ objects and effects

def fit_objects(sheets: list[tuple[Image.Image, int, list[str]]], frame: tuple[int, int], anchor: tuple[int, int], default: int, sizes: dict[str, int] | None = None,
                groups: dict[str, int] | None = None, bottom: bool = True, colours: int = 15) -> tuple[Image.Image, dict]:
    """Separate objects in rows [(image, count, names)] at their own sizes: `sizes[name]` is that object's biggest side; `groups[prefix]` the biggest frame of an effect kind (every
    frame of the kind by the same factor); else the sheet's biggest is `default`. Standing on the anchor's row (`bottom`) or centred."""
    sizes, groups = sizes or {}, groups or {}
    w, h = frame
    names, frames = [], []
    for im, n, fnames in sheets:
        pieces = split_frames(key_background(im), n)
        k = default / max(max(p.width, p.height) for p in pieces)
        gk = {}
        for fname, p in zip(fnames, pieces):
            g = fname.rsplit("_", 1)[0]
            if g in groups:
                gk[g] = max(gk.get(g, 0), max(p.width, p.height))
        for fname, p in zip(fnames, pieces):
            g = fname.rsplit("_", 1)[0]
            kk = sizes[fname] / max(p.width, p.height) if fname in sizes else groups[g] / gk[g] if g in groups else k
            p = p.resize((max(1, round(p.width * kk)), max(1, round(p.height * kk))), Image.LANCZOS)
            if p.width > w - 4 or p.height > h - 4:
                p.thumbnail((w - 4, h - 4))
            fr = Image.new("RGBA", (w, h))
            fr.alpha_composite(p, (anchor[0] - p.width // 2, max(0, (anchor[1] - p.height) if bottom else (h // 2 - p.height // 2))))
            names.append(fname)
            frames.append(fr)
    strip = Image.new("RGBA", (w * len(frames), h))
    for i, f in enumerate(frames):
        strip.alpha_composite(solid(f), (i * w, 0))
    return quantized(strip, colours), {"w": w, "h": h, "anchor": list(anchor), "frames": names}
