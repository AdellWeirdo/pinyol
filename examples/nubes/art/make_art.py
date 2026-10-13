"""The pictures of examples/nubes, from the images they were generated as (big, not kept here): the sky far behind,
the band of clouds in front, the player's ship, the spinning drone, the battleship, the explosion; and the shots,
drawn here. At the game's size, in at most 256 colours each (so their packed pictures are exact).

    uv run --with pillow examples/nubes/art/make_art.py RAW_DIR BOOM_PNG

RAW_DIR has sky.png, clouds.png, ship_ref.png, drone.png (a row of five), boss.png; BOOM_PNG is examples/asalto's
art/boom.png (the same explosion).
"""
import shutil
import sys
from pathlib import Path

from PIL import Image, ImageDraw

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


def fit(img: Image.Image, w: int, h: int) -> Image.Image:  # trimmed, as big as fits w x h, centred
    img = solid(img)
    img = img.crop(img.getchannel("A").getbbox())
    k = min(w / img.width, h / img.height)
    img = img.resize((max(1, round(img.width * k)), max(1, round(img.height * k))), Image.LANCZOS)
    cell = Image.new("RGBA", (w, h))
    cell.alpha_composite(solid(img), ((w - img.width) // 2, (h - img.height) // 2))
    return cell


def row(img: Image.Image, n: int) -> list[Image.Image]:  # a row of n things, cut at its emptiest columns
    a = solid(img).getchannel("A")
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
    return [img.crop((x0, 0, x1, img.height)) for x0, x1 in parts]


def strip(frames: list[Image.Image], colours: int, out: str) -> None:
    w, h = frames[0].size
    s = Image.new("RGBA", (w * len(frames), h))
    for i, f in enumerate(frames):
        s.alpha_composite(f, (i * w, 0))
    quantized(s, colours).save(HERE / out)


def shots() -> None:  # the enemies' orb and the ship's bolt, drawn: a glow, a core
    orb = Image.new("RGBA", (14, 14))
    d = ImageDraw.Draw(orb)
    d.ellipse((0, 0, 13, 13), fill=(255, 60, 150, 255))
    d.ellipse((2, 2, 11, 11), fill=(255, 140, 210, 255))
    d.ellipse((4, 4, 9, 9), fill=(255, 255, 255, 255))
    orb.save(HERE / "orb.png")
    bolt = Image.new("RGBA", (26, 8))
    d = ImageDraw.Draw(bolt)
    d.rounded_rectangle((0, 0, 25, 7), 3, fill=(255, 170, 30, 255))
    d.rounded_rectangle((4, 2, 25, 5), 2, fill=(255, 240, 160, 255))
    d.rectangle((14, 3, 24, 4), fill=(255, 255, 255, 255))
    bolt.save(HERE / "bolt.png")


def main(raw: Path, boom: Path) -> None:
    sky = Image.open(raw / "sky.png").convert("RGB").resize((720, 480), Image.LANCZOS).crop((0, 60, 720, 380))
    sky.quantize(256, method=Image.Quantize.MEDIANCUT, dither=Image.Dither.NONE).convert("RGB").save(HERE / "sky.png")
    clouds = solid(Image.open(raw / "clouds.png"))
    clouds = clouds.crop(clouds.getchannel("A").getbbox())
    clouds = clouds.resize((960, round(clouds.height * 960 / clouds.width)), Image.LANCZOS).crop((0, 0, 960, 200))
    quantized(solid(clouds), 255).save(HERE / "clouds.png")
    quantized(fit(Image.open(raw / "ship_ref.png"), 112, 40), 64).save(HERE / "ship.png")
    strip([fit(f, 48, 48) for f in row(Image.open(raw / "drone.png"), 5)], 48, "drone.png")
    quantized(fit(Image.open(raw / "boss.png"), 432, 184), 128).save(HERE / "boss.png")
    shutil.copy(boom, HERE / "boom.png")
    shots()
    print("clouds", clouds.size)


if __name__ == "__main__":
    main(Path(sys.argv[1]), Path(sys.argv[2]))
