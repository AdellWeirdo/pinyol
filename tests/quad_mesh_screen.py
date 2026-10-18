"""Check VDP1 mesh parity on the final screen across a 32-column strip edge."""
import sys
from pathlib import Path


data = Path(sys.argv[1]).read_bytes()
header, pixels = data.split(b"\n255\n", 1)
assert header == b"P6\n480 320", header


def pixel(x, y):
    offset = (y * 480 + x) * 3
    return tuple(pixels[offset:offset + 3])


background = (32, 48, 64)
white = (248, 252, 248)  # RGB565 white in the headless PPM
for y in range(81, 113):
    for x in range(31, 63):
        expected = white if (x + y) % 2 == 0 else background
        assert pixel(x, y) == expected, (x, y, pixel(x, y), expected)
assert pixel(30, 81) == background
assert pixel(63, 81) == background
assert pixel(30, 120) == background
assert pixel(31, 120) == pixel(32, 120) == pixel(34, 120)
assert pixel(35, 120) != pixel(34, 120)  # custom UV advances by one texel every four screen pixels
