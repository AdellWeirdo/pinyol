# /// script
# requires-python = ">=3.10"
# dependencies = ["pillow>=10"]
# ///
"""Fit a generated image (one frame, or a sheet of frames) into an existing sprite set's format.

Usage:
  fit_sprite.py <generated.png> <out.png> --like <ref_frame.png> [--height N] [--key-bg] [--keep-main]
  fit_sprite.py <sheet.png> <out_set_dir> --like <ref_frame.png> --split N [--scale-frame K] [...]

Scales the character so its main body (the largest connected blob, so motion lines
or sneeze puffs don't shrink it) matches the ref frame's body height (or --height),
and places it on a transparent canvas the same size as the ref, on its baseline and
center. With --split N the sheet is cut into N frames along its empty columns, every
frame gets the same scale (taken from frame K's body) and the same vertical offset,
so motion inside the sheet (a rocket rising) survives; frames are written as
<out_set_dir>/<dir name>_<i>.png.
--feet (recommended for characters; the rules are tools/sprite_kit.py's, docs/art.md "Sprites that fit"): every sheet is scaled by an UPRIGHT frame of
it (--scale-frame, -1: none, for a jump or a fall), the soles of the body stand on the ref's ground row in every frame, the middle of the feet on the ref's middle column (an arm that
reaches out does not drag the character) and nothing is cut. --key-bg removes a white or fake-checkerboard background touching the border, for
outputs without real alpha. --keep-main drops everything not touching the main body
(motion lines). Run with --selftest to check the logic.
"""
from __future__ import annotations

import argparse
import os
import sys

from PIL import Image, ImageChops, ImageDraw

ALPHA_MIN = 16  # ponytail: ignores faint halo noise when trimming; raise if edges keep fringe
KEY_MAX_SPREAD = 16  # max-min channel spread that counts as neutral gray/white (checker cells plus noise)
KEY_MIN_LIGHT = 100  # darker neutrals are outline, not background
LEAD_MARGIN = 4  # px kept ahead of the leading edge with --anchor left/right (antialiasing)

Box = tuple[int, int, int, int]


def solid_mask(im: Image.Image) -> Image.Image:
    return im.getchannel("A").point(lambda a: 255 if a >= ALPHA_MIN else 0)


def main_blob(im: Image.Image) -> Image.Image | None:
    """Mask (255) of the largest connected blob (a trail's sparkles near the center don't win)."""
    mask = solid_mask(im)
    box = mask.getbbox()
    if not box:
        return None
    step = max(1, min(box[2] - box[0], box[3] - box[1]) // 48)
    label = 0
    # ponytail: seeds on a grid, so blobs thinner than `step` can be missed; up to 254 blobs
    for y in range(box[1], box[3], step):
        for x in range(box[0], box[2], step):
            if mask.getpixel((x, y)) == 255 and label < 254:
                label += 1
                ImageDraw.floodfill(mask, (x, y), label)
    if not label:
        return None
    hist = mask.histogram()
    biggest = max(range(1, label + 1), key=lambda v: hist[v])
    return mask.point(lambda v: 255 if v == biggest else 0)


def body_bbox(im: Image.Image) -> Box | None:
    blob = main_blob(im)
    return blob.getbbox() if blob else None


def keep_main(im: Image.Image) -> Image.Image:
    blob = main_blob(im)
    if not blob:
        return im
    out = im.copy()
    out.putalpha(ImageChops.multiply(im.getchannel("A"), blob))
    return out


def key_bg(im: Image.Image) -> Image.Image:
    """Make light neutral pixels (white or fake checkerboard) connected to the border transparent."""
    r, g, b = im.convert("RGB").split()
    hi = ImageChops.lighter(ImageChops.lighter(r, g), b)
    lo = ImageChops.darker(ImageChops.darker(r, g), b)
    neutral = ImageChops.difference(hi, lo).point(lambda v: 255 if v <= KEY_MAX_SPREAD else 0)
    cand = ImageChops.multiply(neutral, lo.point(lambda v: 255 if v >= KEY_MIN_LIGHT else 0))
    w, h = cand.size
    border = [(x, y) for x in range(w) for y in (0, h - 1)] + [(x, y) for y in range(h) for x in (0, w - 1)]
    for pt in border:
        if cand.getpixel(pt) == 255:
            ImageDraw.floodfill(cand, pt, 128)
    # ponytail: enclosed background pockets (not touching the border) stay opaque; fine for loaf/sitting poses
    out = im.convert("RGBA")
    out.putalpha(cand.point(lambda v: 0 if v == 128 else 255))
    return out


def split_sheet(im: Image.Image, n: int) -> list[Image.Image]:
    """Cut a sheet into n full-height columns along empty columns; equal slices if that fails."""
    mask = solid_mask(im)
    w, h = mask.size
    filled = [mask.crop((x, 0, x + 1, h)).getbbox() is not None for x in range(w)]
    segs, start = [], None
    for x, f in enumerate(filled + [False]):
        if f and start is None:
            start = x
        elif not f and start is not None:
            segs.append([start, x])
            start = None
    while len(segs) > n:  # stray sparkles or split marks: merge across the narrowest gap
        i = min(range(len(segs) - 1), key=lambda j: segs[j + 1][0] - segs[j][1])
        segs[i:i + 2] = [[segs[i][0], segs[i + 1][1]]]
    if len(segs) < n:  # frames touch (a glow bridges them): cut at the emptiest column near each expected split
        counts = [mask.crop((x, 0, x + 1, h)).histogram()[255] for x in range(w)]
        reach = w // (4 * n)
        cuts = [min(range(round(i * w / n) - reach, round(i * w / n) + reach),
                    key=lambda x, c=round(i * w / n): (counts[x], abs(x - c))) for i in range(1, n)]
        edges = [0] + cuts + [w]
        segs = [[edges[i], edges[i + 1]] for i in range(n)]
    out = []
    for x0, x1 in segs:
        frame = Image.new("RGBA", im.size, (0, 0, 0, 0))
        frame.paste(im.crop((x0, 0, x1, h)), (x0, 0))
        out.append(frame)
    return out


def place(frames: list[Image.Image], ref: Image.Image, height: int | None = None, scale_frame: int = 0,
          anchor: str = "center") -> list[Image.Image]:
    rbody = body_bbox(ref)
    bodies = [body_bbox(f) for f in frames]
    if not rbody or not all(bodies):
        raise ValueError("empty image (nothing visible to fit)")
    k = bodies[scale_frame]
    scale = (height or (rbody[3] - rbody[1])) / (k[3] - k[1])
    dy = rbody[3] - k[3] * scale  # one vertical offset for all frames keeps their motion
    rcx = (rbody[0] + rbody[2]) / 2
    k_half = (k[2] - k[0]) * scale / 2  # anchor left/right: frame K's body edge lands where its center would
    out = []
    for f, b in zip(frames, bodies):
        if anchor in ("left", "right"):  # nothing lies ahead of the leading edge: pieces there are a neighbor's trail
            f = f.copy()
            ahead = (0, 0, max(0, b[0] - LEAD_MARGIN), f.height) if anchor == "left" else (b[2] + LEAD_MARGIN, 0, f.width, f.height)
            f.paste((0, 0, 0, 0), ahead)
        box = solid_mask(f).getbbox()
        sprite = f.crop(box)
        sprite = sprite.resize((max(1, round(sprite.width * scale)), max(1, round(sprite.height * scale))), Image.LANCZOS)
        if anchor == "left":  # a trail growing behind (to the right) must not shift the nose
            x = round(rcx - k_half - (b[0] - box[0]) * scale)
        elif anchor == "right":
            x = round(rcx + k_half - (b[2] - box[0]) * scale)
        else:
            x = round(rcx - ((b[0] + b[2]) / 2 - box[0]) * scale)
        y = round(dy + box[1] * scale)
        canvas = Image.new("RGBA", ref.size, (0, 0, 0, 0))
        canvas.paste(sprite, (x, y), sprite)  # paste clips at canvas edges
        out.append(canvas)
    return out


def fit(gen: Image.Image, ref: Image.Image, height: int | None = None, key: bool = False,
        split: int = 1, scale_frame: int = 0, main: bool = False, anchor: str = "center") -> list[Image.Image]:
    gen, ref = (key_bg(gen) if key else gen.convert("RGBA")), ref.convert("RGBA")
    if gen.getchannel("A").getextrema()[0] == 255:
        raise ValueError("generated image has no transparency; regenerate asking for one, or pass --key-bg")
    frames = split_sheet(gen, split) if split > 1 else [gen]
    if main:
        frames = [keep_main(f) for f in frames]
    return place(frames, ref, height, scale_frame, anchor)


def selftest() -> None:
    ref = Image.new("RGBA", (200, 152), (0, 0, 0, 0))
    ref.paste((255, 0, 0, 255), (50, 57, 150, 143))  # 100x86 body, baseline 143
    gen = Image.new("RGBA", (1024, 1024), (0, 0, 0, 0))
    gen.paste((0, 255, 0, 255), (300, 200, 700, 544))  # 400x344 body
    gen.paste((0, 255, 0, 255), (320, 60, 340, 120))  # detached motion line above
    out = fit(gen, ref)[0]
    assert out.size == (200, 152), out.size
    assert body_bbox(out)[3] == 143 and abs(body_bbox(out)[1] - 57) <= 1, body_bbox(out)
    assert abs(sum(body_bbox(out)[::2]) // 2 - 100) <= 1, body_bbox(out)
    assert solid_mask(fit(gen, ref, main=True)[0]).getbbox() == body_bbox(out), "keep-main drops the line"

    star = Image.new("RGBA", (400, 400), (0, 0, 0, 0))
    star.paste((0, 255, 0, 255), (250, 250, 390, 390))   # the star, low right
    star.paste((0, 255, 0, 255), (190, 190, 210, 210))   # a trail sparkle at the drawing's center
    assert body_bbox(star) == (250, 250, 390, 390), body_bbox(star)

    sheet = Image.new("RGBA", (1500, 500), (0, 0, 0, 0))
    for i in range(5):
        lift = 60 if i == 2 else 0  # frame 2 hops up
        sheet.paste((0, 0, 255, 255), (i * 300 + 50, 200 - lift, i * 300 + 250, 372 - lift))
    sheet.paste((0, 0, 255, 255), (1290, 50, 1296, 56))  # stray sparkle past the last frame
    frames = fit(sheet, ref, split=5)
    assert len(frames) == 5
    boxes = [body_bbox(f) for f in frames]
    assert all(b[3] == 143 for i, b in enumerate(boxes) if i != 2), boxes
    assert abs(boxes[2][3] - (143 - 30)) <= 1, boxes  # 60 px hop at scale 0.5 kept as 30 px

    trail = Image.new("RGBA", (1500, 500), (0, 0, 0, 0))
    for i in range(5):  # same nose x in every column, a trail growing to the right
        trail.paste((0, 0, 255, 255), (i * 300 + 40, 200, i * 300 + 140 + i * 30, 372))
    trail.paste((0, 0, 255, 255), (1210, 380, 1230, 400))  # frame 3's trail spilling in front of frame 4's nose
    tframes = fit(trail, ref, split=5, anchor="left")
    noses = [body_bbox(f)[0] for f in tframes]
    assert solid_mask(tframes[4]).getbbox()[0] == noses[4], "spilled trail ahead of the nose is dropped"
    assert max(noses) - min(noses) <= 1, noses

    glued = Image.new("RGBA", (1000, 300), (0, 0, 0, 0))
    for i in range(5):
        glued.paste((0, 0, 255, 255), (i * 200 + 20, 50, i * 200 + 190, 250))
    glued.paste((0, 0, 255, 255), (0, 150, 1000, 152))  # a thin glow line bridges every frame
    for i, f in enumerate(split_sheet(glued, 5)):
        fx0, _, fx1, _ = solid_mask(f).crop((0, 0, 1000, 149)).getbbox()  # body only, above the line
        assert (fx0, fx1) == (i * 200 + 20, i * 200 + 190), (i, fx0, fx1)

    checker = Image.new("RGB", (400, 400))
    for i in range(0, 400, 20):
        for j in range(0, 400, 20):
            checker.paste((200, 200, 204) if (i + j) // 20 % 2 else (132, 132, 137), (i, j, i + 20, j + 20))
    checker.paste((60, 30, 20), (100, 100, 300, 300))  # dark outline
    checker.paste((250, 235, 210), (110, 110, 290, 290))  # cream fill inside must survive
    keyed = key_bg(checker)
    assert solid_mask(keyed).getbbox() == (100, 100, 300, 300), solid_mask(keyed).getbbox()
    assert keyed.getpixel((200, 200))[3] == 255
    white = Image.new("RGB", (100, 100), (255, 255, 255))
    white.paste((60, 30, 20), (30, 30, 70, 70))
    assert solid_mask(key_bg(white)).getbbox() == (30, 30, 70, 70)
    try:
        fit(Image.new("RGB", (10, 10), "white"), ref)
        raise AssertionError("opaque input without --key-bg should be rejected")
    except ValueError:
        pass
    print("selftest ok")


if __name__ == "__main__":
    if "--selftest" in sys.argv:
        selftest()
        sys.exit(0)
    ap = argparse.ArgumentParser()
    ap.add_argument("generated")
    ap.add_argument("out", help="output png, or with --split the set's folder")
    ap.add_argument("--like", required=True, help="existing frame whose size, scale and baseline to match")
    ap.add_argument("--height", type=int, help="body height in px (default: ref body height)")
    ap.add_argument("--key-bg", action="store_true", help="remove a flat/checkerboard background touching the border")
    ap.add_argument("--split", type=int, default=1, help="cut a sheet into N frames")
    ap.add_argument("--scale-frame", type=int, default=0, help="frame whose body sets the sheet's scale")
    ap.add_argument("--keep-main", action="store_true", help="drop marks not touching the main body")
    ap.add_argument("--feet", action="store_true", help="fit with tools/sprite_kit.py: soles on the ref's ground row, feet centred, never cut (see above)")
    ap.add_argument("--anchor", choices=("center", "left", "right"), default="center",
                    help="align frames by body center, or by its left/right edge (a trail growing on the other side)")
    a = ap.parse_args()
    try:
        if a.feet:
            sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
            import sprite_kit
            ref = Image.open(a.like).convert("RGBA")
            rb = body_bbox(ref)
            src = Image.open(a.generated)
            keyed = sprite_kit.key_background(src) if a.key_bg else src.convert("RGBA")
            frames = sprite_kit.fit_sheet(keyed, a.split, ref.size, ((rb[0] + rb[2]) // 2, rb[3]), None if a.scale_frame < 0 else a.scale_frame, a.height or rb[3] - rb[1])
        else:
            frames = fit(Image.open(a.generated), Image.open(a.like), a.height, a.key_bg, a.split, a.scale_frame, a.keep_main, a.anchor)
    except ValueError as e:
        sys.exit(f"fit_sprite: {e}")
    if a.split == 1:
        frames[0].save(a.out)
        print(a.out)
    else:
        os.makedirs(a.out, exist_ok=True)
        name = os.path.basename(os.path.normpath(a.out))
        for i, f in enumerate(frames):
            path = os.path.join(a.out, f"{name}_{i}.png")
            f.save(path)
            print(path)
