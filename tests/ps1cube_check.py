"""The shots tests/ps1cube.script took (saves DIR) against what a real PlayStation drew (tests/ps1cube_ref): the same cube
(PSn00bSDK's examples/graphics/gte), four fixed poses. quad() must give the same silhouette, box and mean colour. Usage:
ps1cube_check.py DIR"""
import sys
from pathlib import Path

from PIL import Image

HERE = Path(__file__).parent
BG = (63, 0, 127)          # the PlayStation's clear colour, ours too
MIN_IOU, MAX_BOX, MAX_MEAN = 0.97, 2, 8


def cube_pixels(img):
    """{(x, y): (r, g, b)} of what is not the clear colour."""
    px = img.load()
    w, h = img.size
    return {(x, y): px[x, y] for y in range(h) for x in range(w)
            if sum(abs(c - b) for c, b in zip(px[x, y], BG)) > 30}


def box(pts):
    xs, ys = [p[0] for p in pts], [p[1] for p in pts]
    return min(xs), min(ys), max(xs), max(ys)


for i in range(4):
    ps1 = Image.open(HERE / "ps1cube_ref" / f"ps1_pose{i}.png").convert("RGB")                    # 320x240
    ours = Image.open(Path(sys.argv[1]) / f"ps1cube_pose{i}.ppm").convert("RGB")                 # 480x320, the cube at 4/3
    ours = ours.crop((240 - 160 * 4 // 3, 0, 240 + 160 * 4 // 3, 320)).resize((320, 240), Image.BOX)
    a, b = cube_pixels(ps1), cube_pixels(ours)
    both = a.keys() & b.keys()
    iou = len(both) / len(a.keys() | b.keys())
    off = max(abs(p - q) for p, q in zip(box(a), box(b)))
    mean = max(abs(sum(a[k][c] for k in both) - sum(b[k][c] for k in both)) / len(both) for c in range(3))
    print(f"pose{i}: IoU {iou:.3f}, box off by {off} px, mean colour off by {mean:.1f}")
    assert iou >= MIN_IOU, f"pose{i}: silhouette {iou:.3f} < {MIN_IOU}"
    assert off <= MAX_BOX, f"pose{i}: box off by {off} px"
    assert mean <= MAX_MEAN, f"pose{i}: mean colour off by {mean:.1f}"
