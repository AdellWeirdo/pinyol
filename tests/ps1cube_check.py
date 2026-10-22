"""The shots tests/ps1cube.script took (saves DIR) against what a real PlayStation drew (tests/ps1cube_ref): the same cube
(PSn00bSDK's examples/graphics/gte), four fixed poses. quad() must give the same silhouette, box and mean colour. Usage:
ps1cube_check.py DIR"""
import sys
from pathlib import Path

import numpy as np
from PIL import Image

HERE = Path(__file__).parent
BG = np.array((63, 0, 127))          # the PlayStation's clear colour, ours too
MIN_IOU, MAX_BOX, MAX_MEAN = 0.97, 2, 8


def mask(img):
    return np.abs(np.asarray(img).astype(int) - BG).sum(2) > 30


for i in range(4):
    ps1 = Image.open(HERE / "ps1cube_ref" / f"ps1_pose{i}.png").convert("RGB")                     # 320x240
    ours = Image.open(Path(sys.argv[1]) / f"ps1cube_pose{i}.ppm").convert("RGB")                  # 480x320, the cube at 4/3
    ours = ours.crop((240 - 160 * 4 // 3, 0, 240 + 160 * 4 // 3, 320)).resize((320, 240), Image.BOX)
    a, b = mask(ps1), mask(ours)
    iou = (a & b).sum() / (a | b).sum()
    ya, xa = np.where(a)
    yb, xb = np.where(b)
    box = max(abs(ya.min() - yb.min()), abs(ya.max() - yb.max()), abs(xa.min() - xb.min()), abs(xa.max() - xb.max()))
    both = a & b
    mean = np.abs(np.asarray(ps1).astype(int)[both].mean(0) - np.asarray(ours).astype(int)[both].mean(0)).max()
    print(f"pose{i}: IoU {iou:.3f}, box off by {box} px, mean colour off by {mean:.1f}")
    assert iou >= MIN_IOU, f"pose{i}: silhouette {iou:.3f} < {MIN_IOU}"
    assert box <= MAX_BOX, f"pose{i}: box off by {box} px"
    assert mean <= MAX_MEAN, f"pose{i}: mean colour off by {mean:.1f}"
