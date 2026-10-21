"""The shots tests/looks.script took (saves DIR): palcycle turned the backdrop's entries; shock bent the picture only on
its ring; haze moved rows sideways by what the sine says; line_scroll_ramp slid each row by its share; line_affine gave
every line one map point, so one colour. Usage: looks_check.py DIR"""
import math
import sys
from pathlib import Path

from PIL import Image

d = Path(sys.argv[1])


def shot(name):
    return Image.open(d / f"{name}.ppm").convert("RGB")


def near(a, b, tol=12):
    return all(abs(x - y) <= tol for x, y in zip(a, b))


c0, c1, ch, cb = shot("looks_cycle0"), shot("looks_cycle1"), shot("looks_cycle_half"), shot("looks_cycle_back")
assert near(c0.getpixel((5, 5)), (255, 0, 0)), c0.getpixel((5, 5))
assert near(c1.getpixel((5, 5)), (0, 255, 0)), c1.getpixel((5, 5))
h = ch.getpixel((5, 5))
assert 100 <= h[0] <= 160 and 100 <= h[1] <= 160 and h[2] < 20, h
assert near(cb.getpixel((5, 5)), (255, 0, 0)), cb.getpixel((5, 5))

plain, shock, haze, ramp, affine = shot("looks_plain"), shot("looks_shock"), shot("looks_haze"), shot("looks_ramp"), shot("looks_affine")
pp, sp = plain.load(), shock.load()
diff, far = 0, 0
for y in range(0, 320, 2):
    for x in range(0, 480, 2):
        if pp[x, y] != sp[x, y]:
            diff += 1
            dist = math.hypot(x - 240, y - 160)
            if not 56 <= dist <= 104:
                far += 1
assert diff > 100, diff             # the ring moved something
assert far == 0, far                 # and nothing off the ring
assert pp[240, 160] == sp[240, 160]  # the centre as it was

hp = haze.load()
y = 4  # world row 4: dx = round(4 * sin(4 / 16 * 2 pi)) = 4 world pixels, 8 on the screen
for sx in range(16, 470, 7):
    assert hp[sx, 2 * y] == pp[sx - 8, 2 * y], (sx, hp[sx, 2 * y], pp[sx - 8, 2 * y])
y = 8  # dx = round(4 * sin(pi)) = 0: untouched
for sx in range(0, 480, 7):
    assert hp[sx, 2 * y] == pp[sx, 2 * y]

rp = ramp.load()
y = 159  # the scroll is 32 there: what shows at screen x is the picture 32 world pixels (64 on the screen) further on
for sx in range(0, 400, 7):
    assert rp[sx, 2 * y] == pp[sx + 64, 2 * y], (sx, rp[sx, 2 * y], pp[sx + 64, 2 * y])
y = 0  # and 0 at the top
for sx in range(0, 480, 7):
    assert rp[sx, 0] == pp[sx, 0]

sp = shot("looks_sil").load()  # the ship (an indexed sheet, at 100, 60) behind the picture: red, half, over the picture where it has pixels
changed = 0
for y in range(60, 76):  # the ship's 16 x 16 box
    for x in range(100, 116):
        if sp[2 * x, 2 * y] != pp[2 * x, 2 * y]:
            changed += 1
            r, g, b = sp[2 * x, 2 * y]
            r0, g0, b0 = pp[2 * x, 2 * y]
            assert r >= r0 and g <= g0 and b <= b0 and abs(r - (255 + r0) // 2) <= 24, (x, y, sp[2 * x, 2 * y], pp[2 * x, 2 * y])
assert changed > 20, changed
assert sp[10, 10] == pp[10, 10] and sp[470, 310] == pp[470, 310]  # away from the ship, the picture as it was

ap = affine.load()
for y in range(0, 320, 6):
    row = {ap[x, y] for x in range(0, 480, 5)}
    assert len(row) == 1, (y, row)
print("looks_check: ok")
