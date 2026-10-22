"""The shots tests/mesh.script took (saves DIR): the cube drawn by mesh() (mesh_a0..3) and by hand with quad() (mesh_b0..3) must
be the same picture: nearly every pixel within a few levels of its twin. Usage: mesh_check.py DIR"""
import sys
from pathlib import Path

from PIL import Image, ImageChops

TOLERANCE, MAX_BAD = 8, 0.002   # a level a channel; the share of pixels beyond it (C's floats and Lua's round a corner apart now and then)
d = Path(sys.argv[1])
for i in range(4):
    a, b = Image.open(d / f"mesh_a{i}.ppm").convert("RGB"), Image.open(d / f"mesh_b{i}.ppm").convert("RGB")
    total = a.width * a.height
    bad = sum(ImageChops.difference(a, b).convert("L").histogram()[TOLERANCE + 1:]) / total
    clear = Image.new("RGB", a.size, a.getpixel((2, 2)))          # the corner is the clear colour
    drawn = sum(ImageChops.difference(a, clear).convert("L").histogram()[16:])
    print(f"pose{i}: {drawn} pixels drawn, {bad * 100:.3f} % beyond {TOLERANCE} levels")
    assert drawn > 1000, f"pose{i}: nothing drawn"
    assert bad <= MAX_BAD, f"pose{i}: {bad * 100:.3f} % of the pixels differ"
