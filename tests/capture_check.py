"""The files capture_test wrote: the PNG is 480x320 with the band where it was, the cover 240x160 halves it, the GIF
has frames of the screen. Usage: capture_check.py DIR"""
import struct
import sys
from pathlib import Path

from PIL import Image

d = Path(sys.argv[1])
png = Image.open(d / "pantalla-1.png").convert("RGB")
assert png.size == (480, 320), png.size
assert png.getpixel((10, 10)) == (0, 0, 255), png.getpixel((10, 10))      # blue above the band
assert png.getpixel((10, 200)) == (255, 0, 0), png.getpixel((10, 200))    # the band's last place: rows 190..229
cover = (d / "cover.rgb565").read_bytes()
assert len(cover) == 240 * 160 * 2, len(cover)
assert struct.unpack("<H", cover[(100 * 240 + 5) * 2:(100 * 240 + 5) * 2 + 2])[0] == 0xF800   # row 200 of the screen
assert struct.unpack("<H", cover[(5 * 240 + 5) * 2:(5 * 240 + 5) * 2 + 2])[0] == 0x001F
gif = Image.open(d / "clip-1.gif")
assert gif.size == (480, 320) and getattr(gif, "n_frames", 1) == 10, (gif.size, getattr(gif, "n_frames", 1))  # every other frame of 20
gif.seek(0)
first = gif.convert("RGB")
assert first.getpixel((10, 20))[0] > 200 and first.getpixel((10, 300))[2] > 200, first.getpixel((10, 20))
print("capture_check: ok")
