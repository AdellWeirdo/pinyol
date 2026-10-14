# /// script
# requires-python = ">=3.10"
# dependencies = ["pillow>=10"]
# ///
"""pinyol's logo for the console's own screens, as the firmware draws it: RGB565 (the RGB() of src/bp.h, little
endian), already laid on the launcher's ink, so it is copied a row at a time with no transparency to work out.

    uv run firmware/main/brand.py      # docs/logo.png -> firmware/main/logo_small.rgb565, logo_big.rgb565

logo_small is the launcher's header (40 rows), logo_big the boot screen (160 rows); launcher.c knows their sizes.
"""
from pathlib import Path

from PIL import Image

HERE = Path(__file__).resolve().parent
INK = (0x0B, 0x0E, 0x1F)  # pinyol's ink (its brand manual): the launcher's background


def rgb565(img: Image.Image) -> bytes:
    raw, out = img.tobytes(), bytearray()
    for i in range(0, len(raw), 3):
        r, g, b = raw[i], raw[i + 1], raw[i + 2]
        out += ((r >> 3) << 11 | (g >> 2) << 5 | b >> 3).to_bytes(2, "little")
    return bytes(out)


def main() -> None:
    logo = Image.open(HERE.parents[1] / "docs" / "logo.png").convert("RGBA")
    logo = logo.crop(logo.getchannel("A").getbbox())
    for name, h in (("logo_small", 40), ("logo_big", 160)):
        w = round(logo.width * h / logo.height)
        on_ink = Image.new("RGBA", (w, h), INK + (255,))
        on_ink.alpha_composite(logo.resize((w, h), Image.LANCZOS))
        (HERE / f"{name}.rgb565").write_bytes(rgb565(on_ink.convert("RGB")))
        print(f"{name}: {w}x{h}")


if __name__ == "__main__":
    main()
