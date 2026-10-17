# /// script
# requires-python = ">=3.10"
# dependencies = ["pillow>=10.1", "numpy>=1.26"]
# ///
"""A generated "pixel art" picture back onto its real pixel grid, in the four Game Boy tones.

    uv run pixelize.py in.png out.png [--frames N] [--pixel P] [--opaque]

Image models draw pixel art big and slightly off-grid: each art pixel a block of ~P image pixels, not always the
same size. This finds P (the block size that makes the picture most nearly constant inside each block), samples the
middle of every block, maps it to the nearest of the four tones and keeps alpha. --frames N cuts a sheet at its
emptiest columns into N frames written as out_0.png ... (each trimmed to its drawing, all on one canvas and
baseline). --opaque: a background (no alpha).
"""
from __future__ import annotations

import argparse
import sys
from pathlib import Path

import numpy as np
from PIL import Image

LAST_P = 0.0  # the block size the last call used (build_gb.py rescales from it)
TONES = np.array([(224, 248, 208), (136, 192, 112), (52, 104, 86), (8, 24, 32)], dtype=np.float32)


def nearest_tone(rgb: np.ndarray) -> np.ndarray:
    """Index 0-3 of the nearest tone, by luminance first (the generator's greens drift in hue)."""
    lum = rgb @ np.array([0.3, 0.59, 0.11], dtype=np.float32)
    tl = TONES @ np.array([0.3, 0.59, 0.11], dtype=np.float32)
    return np.abs(lum[..., None] - tl).argmin(-1)


def block_score(lum: np.ndarray, p: float, ox: float, oy: float) -> float:
    h, w = lum.shape
    xs = np.arange(ox + p / 2, w, p).astype(int)
    ys = np.arange(oy + p / 2, h, p).astype(int)
    xs, ys = xs[xs < w], ys[ys < h]
    centre = lum[np.ix_(ys, xs)]
    up = np.repeat(np.repeat(centre, int(np.ceil(p)), 0), int(np.ceil(p)), 1)
    # compare each block's centre with the pixels a quarter block away from it, both ways
    q = max(1, int(p / 4))
    a = lum[np.ix_(np.clip(ys - q, 0, h - 1), np.clip(xs - q, 0, w - 1))]
    b = lum[np.ix_(np.clip(ys + q, 0, h - 1), np.clip(xs + q, 0, w - 1))]
    return float(np.mean(np.abs(centre - a)) + np.mean(np.abs(centre - b)))


def find_grid(lum: np.ndarray) -> tuple[float, float, float]:
    best = None
    for p in np.arange(3.0, 24.0, 0.25):
        for ox in np.arange(0, p, max(0.5, p / 6)):
            score = block_score(lum, p, ox, ox) + 0.02 * (24 - p)  # ties go to the bigger block
            if best is None or score < best[0]:
                best = (score, p, ox)
    return best[1], best[2], best[2]


def pixelize(src: Image.Image, p: float | None, opaque: bool) -> Image.Image:
    rgba = np.asarray(src.convert("RGBA"), dtype=np.float32)
    lum = rgba[..., :3] @ np.array([0.3, 0.59, 0.11], dtype=np.float32)
    if not opaque:
        lum = np.where(rgba[..., 3] > 127, lum, 0)
    if p is None:
        p, ox, oy = find_grid(lum[: min(600, lum.shape[0]), : min(900, lum.shape[1])])
    else:
        ox = oy = 0.0
    global LAST_P
    LAST_P = p
    h, w = lum.shape
    xs = np.arange(ox + p / 2, w, p).astype(int)
    ys = np.arange(oy + p / 2, h, p).astype(int)
    xs, ys = xs[xs < w], ys[ys < h]
    cells = rgba[np.ix_(ys, xs)]
    idx = nearest_tone(cells[..., :3])
    out = TONES[idx].astype(np.uint8)
    alpha = np.full(idx.shape, 255, np.uint8) if opaque else np.where(cells[..., 3] > 127, 255, 0).astype(np.uint8)
    print(f"pixel {p:.2f} offset {ox:.1f}: {len(xs)}x{len(ys)}", file=sys.stderr)
    return Image.fromarray(np.dstack([out, alpha]), "RGBA")


def blobs(mask: np.ndarray) -> list[tuple[int, int, int, int, int]]:
    """Connected drawings (8-neighbours): (area, x0, y0, x1, y1) each."""
    h, w = mask.shape
    seen = np.zeros_like(mask, bool)
    out = []
    for y0, x0 in zip(*np.nonzero(mask)):
        if seen[y0, x0]:
            continue
        stack, area = [(y0, x0)], 0
        seen[y0, x0] = True
        bx0, by0, bx1, by1 = x0, y0, x0, y0
        while stack:
            y, x = stack.pop()
            area += 1
            bx0, by0, bx1, by1 = min(bx0, x), min(by0, y), max(bx1, x), max(by1, y)
            for dy in (-1, 0, 1):
                for dx in (-1, 0, 1):
                    ny, nx = y + dy, x + dx
                    if 0 <= ny < h and 0 <= nx < w and mask[ny, nx] and not seen[ny, nx]:
                        seen[ny, nx] = True
                        stack.append((ny, nx))
        out.append((area, bx0, by0, bx1 + 1, by1 + 1))
    return out


def split(img: Image.Image, n: int) -> list[Image.Image]:
    """n frames: the n biggest drawings, each with the loose marks nearest to it (drops, hearts, a Z); each trimmed,
    then all on one canvas, bottoms aligned, in order left to right."""
    mask = np.asarray(img)[..., 3] > 0
    parts = sorted(blobs(mask), reverse=True)
    cores = sorted(parts[:n], key=lambda b: b[1])
    boxes = [list(c[1:]) for c in cores]
    for area, x0, y0, x1, y1 in parts[n:]:
        mid = (x0 + x1) / 2
        k = min(range(len(cores)), key=lambda i: 0 if cores[i][1] <= mid <= cores[i][3]
                else min(abs(mid - cores[i][1]), abs(mid - cores[i][3])))
        b = boxes[k]
        boxes[k] = [min(b[0], x0), min(b[1], y0), max(b[2], x1), max(b[3], y1)]
    frames = []
    for b in boxes:  # each frame: only its own pixels (a neighbour's mark outside its box is not copied)
        f = img.crop(tuple(b))
        frames.append(f)
    w = max(f.width for f in frames) + 4
    h = max(f.height for f in frames) + 2
    bottom_gap = [max(bb[3] for bb in boxes) - bb[3] for bb in boxes]  # keep the sheet's floor
    out = []
    for f, gap in zip(frames, bottom_gap):
        c = Image.new("RGBA", (w, h + max(bottom_gap)))
        c.paste(f, ((w - f.width) // 2, c.height - 1 - gap - f.height))
        out.append(c)
    return out


def main() -> None:
    ap = argparse.ArgumentParser()
    ap.add_argument("src")
    ap.add_argument("out")
    ap.add_argument("--frames", type=int, default=0)
    ap.add_argument("--pixel", type=float)
    ap.add_argument("--opaque", action="store_true")
    a = ap.parse_args()
    img = pixelize(Image.open(a.src), a.pixel, a.opaque)
    out = Path(a.out)
    if a.frames:
        for i, f in enumerate(split(img, a.frames)):
            f.save(out.with_name(f"{out.stem}_{i}.png"))
            print(out.with_name(f"{out.stem}_{i}.png"), f.size)
    else:
        if not a.opaque:
            img = img.crop(img.getbbox())
        img.save(out)
        print(out, img.size)


if __name__ == "__main__":
    main()
