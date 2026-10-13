"""The pictures of examples/moto, from the images they were generated as (big, not kept here): the coast on the
horizon, the player's motorbike leaning in five frames, the same bike in the rivals' colours (only its palette is
used: img's pal), and five roadside things. At the game's size, in at most 256 colours each.

    uv run --with pillow examples/moto/art/make_art.py RAW_DIR

RAW_DIR has sky.png, bike.png (a row of five) and props.png (a row of five).
"""
import colorsys
import statistics
import sys
from pathlib import Path

from PIL import Image

HERE = Path(__file__).resolve().parent


def solid(img: Image.Image) -> Image.Image:  # see-through or not, nothing between
    img = img.convert("RGBA")
    img.putalpha(img.getchannel("A").point(lambda v: 255 if v >= 128 else 0))
    return img


def quantized(img: Image.Image, colours: int) -> Image.Image:  # one palette, no dithering; alpha kept
    a = img.getchannel("A")
    rgb = img.convert("RGB").quantize(colours, method=Image.Quantize.MEDIANCUT, dither=Image.Dither.NONE).convert("RGB")
    rgb.putalpha(a)
    return rgb


def row(img: Image.Image, n: int) -> list[Image.Image]:  # a row of n things, cut at its emptiest columns, trimmed
    img = solid(img)
    a = img.getchannel("A")
    filled = [a.crop((x, 0, x + 1, a.height)).getbbox() is not None for x in range(a.width)]
    parts, x = [], 0
    while x < a.width:
        if not filled[x]:
            x += 1
            continue
        x0 = x
        while x < a.width and any(filled[x:x + 12]):
            x += 1
        parts.append((x0, x))
    parts = sorted(sorted(parts, key=lambda p: p[1] - p[0])[-n:])
    out = []
    for x0, x1 in parts:
        p = img.crop((x0, 0, x1, img.height))
        out.append(p.crop(p.getchannel("A").getbbox()))
    return out


def strip(things: list[Image.Image], w: int, h: int, k: float) -> Image.Image:  # each scaled by k, feet at the bottom
    s = Image.new("RGBA", (w * len(things), h))
    for i, t in enumerate(things):
        t = t.resize((max(1, round(t.width * k)), max(1, round(t.height * k))), Image.LANCZOS)
        t.thumbnail((w, h))
        s.alpha_composite(solid(t), (i * w + (w - t.width) // 2, h - t.height))
    return s


def recoloured(img: Image.Image, hue: float) -> Image.Image:  # the reds turned to another hue, every colour still its own
    rgb565 = lambda c: (c[0] >> 3, c[1] >> 2, c[2] >> 3)  # (two colours the same here would be one in the palette)
    px = img.load()
    colours = sorted({px[x, y][:3] for y in range(img.height) for x in range(img.width) if px[x, y][3]})
    reds = {c for c in colours if (lambda h, l, s: s > 0.35 and (h < 0.06 or h > 0.92))(*colorsys.rgb_to_hls(*(v / 255 for v in c)))}
    used = {rgb565(c) for c in colours if c not in reds}
    new = {}
    for c in colours:
        if c not in reds:
            new[c] = c
            continue
        h, l, s = colorsys.rgb_to_hls(*(v / 255 for v in c))
        n = tuple(round(v * 255) for v in colorsys.hls_to_rgb(hue, l, s))
        while rgb565(n) in used:  # nudged until it is a colour of its own
            n = (n[0], min(255, n[1] + 4), min(255, n[2] + 8)) if n[2] < 248 else (n[0], max(0, n[1] - 4), n[2] - 16)
        used.add(rgb565(n))
        new[c] = n
    for y in range(img.height):
        for x in range(img.width):
            r, g, b, a = px[x, y]
            if a:
                px[x, y] = new[(r, g, b)] + (a,)
    return img


def in565(img: Image.Image) -> Image.Image:  # each colour as the console keeps it: distinct here, distinct there
    px = img.load()
    for y in range(img.height):
        for x in range(img.width):
            r, g, b, a = px[x, y]
            px[x, y] = (r & 0xF8 | r >> 5, g & 0xFC | g >> 6, b & 0xF8 | b >> 5, a)
    return img


def main(raw: Path) -> None:
    sky = Image.open(raw / "sky.png").convert("RGB").resize((1024, 683), Image.LANCZOS)
    plain = lambda y: statistics.pstdev([sky.getpixel((x, y))[1] for x in range(0, 1024, 16)]) < 4
    horizon = next(y for y in range(200, sky.height) if plain(y))
    sky.crop((0, horizon - 112, 1024, horizon)).quantize(256, method=Image.Quantize.MEDIANCUT,
                                                         dither=Image.Dither.NONE).convert("RGB").save(HERE / "sky.png")
    bikes = row(Image.open(raw / "bike.png"), 5)
    bike = in565(quantized(strip(bikes, 128, 128, 120 / max(b.height for b in bikes)), 96))
    bike.save(HERE / "bike.png")
    recoloured(bike.copy(), 0.61).save(HERE / "bike_blue.png")
    recoloured(bike.copy(), 0.33).save(HERE / "bike_green.png")
    props = row(Image.open(raw / "props.png"), 5)
    quantized(strip(props, 192, 200, 196 / max(p.height for p in props)), 128).save(HERE / "props.png")
    print("bike, props, sky")


if __name__ == "__main__":
    main(Path(sys.argv[1]))
