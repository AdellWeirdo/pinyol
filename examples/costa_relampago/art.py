# /// script
# requires-python = ">=3.10"
# dependencies = ["pillow>=10.1", "fonttools>=4"]
# ///
"""Fit generated Mega Drive art to 240x160 PPU assets.

Raw images and prompts: ../../raw/costa_relampago/. Run with
``uv run games/costa_relampago/art.py``.
"""
from __future__ import annotations

import shutil
import subprocess
import sys
import math
import random
from pathlib import Path

from PIL import Image, ImageDraw

HERE = Path(__file__).resolve().parent
ROOT = HERE.parents[1]
RAW = ROOT / "raw" / "costa_relampago"
ART, ASSETS = HERE / "art", HERE / "assets"
WIDTH, HEIGHT = 1920, 160
HERO_FRAME, HERO_BODY, HERO_FEET, HERO_CENTRE = 32, 29, 30, 16
GROUND_ROW = 128


def surface(x: int) -> int:
    """Keep art's turf at same pixel as Lua collision surface."""
    for start, finish, first, last in (
        (280, 360, 128, 104), (480, 560, 104, 128),
        (1080, 1160, 128, 112), (1280, 1360, 112, 128),
        (1510, 1570, 128, 112), (1690, 1750, 112, 128),
    ):
        if start <= x < finish:
            return round(first + (last - first) * (x - start) / (finish - start))
    if 360 <= x < 480:
        return 104
    if 1160 <= x < 1280 or 1570 <= x < 1690:
        return 112
    return GROUND_ROW


def opaque(image: Image.Image) -> Image.Image:
    image = image.convert("RGBA")
    image.putalpha(image.getchannel("A").point(lambda alpha: 255 if alpha >= 128 else 0))
    return image


def fit(part: Image.Image, size: int, body: int, feet: int, centre: int,
        scale: float | None = None) -> Image.Image:
    """Crop transparent gutters; resize before alpha threshold; fix feet baseline."""
    scale = scale or min((size - 2) / part.width, body / part.height)
    width, height = round(part.width * scale), round(part.height * scale)
    part = opaque(part.resize((width, height), Image.Resampling.LANCZOS))
    out = Image.new("RGBA", (size, size))
    out.alpha_composite(part, (centre - width // 2, feet - height + 1))
    return out


def strip(frames: list[Image.Image]) -> Image.Image:
    out = Image.new("RGBA", (frames[0].width * len(frames), frames[0].height))
    for index, frame in enumerate(frames):
        out.alpha_composite(frame, (index * frame.width, 0))
    return out


def generated_sprites() -> dict[str, Image.Image]:
    squirrel = Image.open(RAW / "squirrel_sheet.png").convert("RGBA")
    objects = Image.open(RAW / "objects_sheet.png").convert("RGBA")
    squirrel_boxes = (
        (25, 40, 340, 350), (375, 40, 710, 350),
        (735, 40, 1070, 350), (1100, 40, 1435, 350),
        (15, 370, 350, 735), (375, 365, 710, 735),
        (735, 365, 1070, 735), (1090, 365, 1438, 735),
        (40, 785, 350, 1045), (385, 785, 705, 1045),
        (750, 785, 1060, 1045), (1110, 785, 1410, 1045),
    )
    # Model's objects extend across nominal grid columns. Cut at clear gutters.
    object_boxes = (
        (50, 65, 390, 370), (405, 65, 770, 370),
        (785, 65, 1070, 370), (1125, 65, 1415, 370),
        (75, 425, 330, 720), (435, 420, 710, 720),
        (800, 480, 1070, 710), (1140, 390, 1420, 710),
        (70, 740, 350, 1040), (400, 740, 700, 1040),
        (760, 740, 1080, 1040), (1110, 740, 1420, 1040),
    )

    def crop_cell(sheet: Image.Image, box: tuple[int, int, int, int]) -> Image.Image:
        part = sheet.crop(box)
        bounds = part.getchannel("A").point(lambda alpha: 255 if alpha >= 128 else 0).getbbox()
        if bounds is None:
            raise ValueError(f"empty generated sprite crop {box}")
        return part.crop(bounds)

    poses = [crop_cell(squirrel, squirrel_boxes[i]) for i in (0, 1, 2, 3, 4, 5, 6, 8, 9, 10, 11)]
    body_scale = min(30 / max(p.width for p in poses[:7]), HERO_BODY / max(p.height for p in poses[:7]))
    roll_scale = min(30 / max(p.width for p in poses[7:]), HERO_BODY / max(p.height for p in poses[7:]))
    hero = [fit(p, HERO_FRAME, HERO_BODY, HERO_FEET, HERO_CENTRE,
                body_scale if i < 7 else roll_scale) for i, p in enumerate(poses)]
    object_cell = lambda i: crop_cell(objects, object_boxes[i])
    return {
        "hero": strip(hero),
        "beetle": strip([fit(object_cell(i), 32, 28, 30, 16) for i in (0, 1)]),
        "gem": strip([fit(object_cell(i), 16, 14, 14, 8) for i in (2, 3, 4, 5)]),
        "spring": strip([fit(object_cell(i), 16, 15, 15, 8) for i in (6, 7)]),
        "goal": strip([fit(object_cell(i), 32, 30, 31, 16) for i in (8, 9, 10, 11)]),
    }


def terrain() -> Image.Image:
    """Coastal sandstone, slate outcrops and patchy salt grass; no repeating grid."""
    rng = random.Random(271828)
    out = Image.new("RGBA", (WIDTH, HEIGHT))
    pixels = out.load()
    sand = ((221, 183, 113), (232, 198, 129), (207, 166, 100), (194, 151, 91))
    rock = ((105, 122, 119), (124, 139, 129), (81, 105, 105), (151, 150, 125))
    for x in range(WIDTH):
        top = surface(x)
        grass = math.sin(x * 0.021) + 0.42 * math.sin(x * 0.079 + 1.4) > 0.4
        for y in range(top, HEIGHT):
            depth = y - top
            grit = (((x % 32) * 73856093) ^ ((y % 32) * 19349663)) & 255
            seam = 17 + 3 * math.sin(x * 0.047) + 2 * math.sin(x * 0.113)
            if depth < 3 and grass:
                colour = (77, 141, 72) if depth else (150, 195, 97)
            elif depth < 2:
                colour = (247, 220, 154)
            elif depth > seam and math.sin(x * 0.013 + y * 0.041) > -0.2:
                colour = rock[0 if grit < 170 else 1 if grit < 225 else 2]
            else:
                colour = sand[0 if grit < 176 else 1 if grit < 230 else 2]
            pixels[x, y] = (*colour, 255)
    draw = ImageDraw.Draw(out)
    for _ in range(175):
        x = rng.randrange(WIDTH)
        y = rng.randrange(surface(x) + 7, HEIGHT)
        radius = rng.randrange(2, 10)
        colour = rock[rng.randrange(len(rock))] if rng.random() < 0.7 else sand[2]
        draw.polygon(((x - radius, y), (x - radius // 2, y - radius // 2),
                      (x + radius // 2, y - radius // 3), (x + radius, y + 1),
                      (x + radius // 3, y + radius // 2)), fill=(*colour, 255))
    for x in range(5, WIDTH, 17):
        if math.sin(x * 0.021) + 0.42 * math.sin(x * 0.079 + 1.4) > 0.4:
            y = surface(x)
            draw.line((x, y, x - 2, y - 3), fill=(63, 127, 70, 255))
            draw.line((x + 1, y, x + 3, y - 2), fill=(156, 199, 93, 255))
    # Stone arch keeps the physical loop readable without a striped neon ring.
    cx, cy = 960, 96
    draw.ellipse((cx - 34, cy - 34, cx + 34, cy + 34), fill=(112, 129, 119, 255))
    draw.ellipse((cx - 29, cy - 29, cx + 29, cy + 29), outline=(178, 177, 133, 255), width=3)
    draw.ellipse((cx - 24, cy - 24, cx + 24, cy + 24), fill=(0, 0, 0, 0))
    for angle in range(0, 360, 24):
        rad = math.radians(angle)
        x, y = round(cx + 31 * math.cos(rad)), round(cy + 31 * math.sin(rad))
        draw.line((x - 2, y - 1, x + 1, y + 2), fill=(67, 96, 100, 255), width=1)
    return out


def wrap_edges(image: Image.Image, radius: int = 16) -> Image.Image:
    """Blend opposing edges so repeating parallax maps have no hard seam."""
    result = image.copy()
    pixels = result.load()
    for y in range(result.height):
        for offset in range(radius):
            left = pixels[offset, y]
            right = pixels[result.width - 1 - offset, y]
            midpoint = tuple(round((a + b) / 2) for a, b in zip(left, right))
            weight = (radius - offset) / radius
            pixels[offset, y] = tuple(round(a * (1 - weight) + m * weight)
                                      for a, m in zip(left, midpoint))
            pixels[result.width - 1 - offset, y] = tuple(round(b * (1 - weight) + m * weight)
                                                       for b, m in zip(right, midpoint))
    return result


def generated_backgrounds() -> dict[str, Image.Image]:
    panorama = Image.open(RAW / "backdrop.png").convert("RGB")
    # One generated panorama supplies sky, mountain and sea bands together.
    far = panorama.resize((256, HEIGHT), Image.Resampling.LANCZOS).convert("RGBA")
    hills = Image.open(RAW / "hills.png").convert("RGBA")
    hills = hills.resize((384, HEIGHT), Image.Resampling.LANCZOS)
    far = wrap_edges(far)
    hills = wrap_edges(hills)
    backdrop = Image.new("RGBA", hills.size)
    for x in range(0, backdrop.width, far.width):
        backdrop.alpha_composite(far, (x, 0))
    backdrop.alpha_composite(hills)
    level = terrain()
    draw = ImageDraw.Draw(level)
    for left, right in ((176, 254), (586, 686), (1382, 1478), (1770, 1870)):
        draw.rectangle((left, 148, right, 159), fill=(38, 147, 181, 255))
        draw.line((left, 148, right, 148), fill=(198, 248, 241, 255), width=2)
        for x in range(left + 5, right, 13):
            draw.line((x, 153, min(x + 5, right), 153), fill=(105, 208, 218, 255))
    return {"far": opaque(backdrop), "level": level}


def quantize_together(pictures: dict[str, Image.Image], colours: int) -> dict[str, Image.Image]:
    """Shared palette across PPU layers; retain binary transparency."""
    samples = Image.new("RGB", (256, 256 * len(pictures)))
    for index, picture in enumerate(pictures.values()):
        sample = picture.convert("RGB").resize((256, 256), Image.Resampling.NEAREST)
        samples.paste(sample, (0, index * 256))
    palette = samples.quantize(colors=colours, method=Image.Quantize.MEDIANCUT,
                               dither=Image.Dither.NONE)
    result = {}
    for name, picture in pictures.items():
        indexed = picture.convert("RGB").quantize(palette=palette, dither=Image.Dither.NONE)
        image = indexed.convert("RGB").convert("RGBA")
        image.putalpha(picture.getchannel("A"))
        result[name] = opaque(image)
    return result


def convert(png: str, aid: str, *opts: str) -> None:
    subprocess.run([sys.executable, str(ROOT / "tools" / "png2asset.py"), str(ART / png),
                    str(ASSETS), aid, *opts], check=True)


def main() -> None:
    ART.mkdir(parents=True, exist_ok=True)
    ASSETS.mkdir(parents=True, exist_ok=True)
    for palette in ASSETS.glob("*.pal"):
        palette.unlink()
    backgrounds = generated_backgrounds()
    pictures = quantize_together(backgrounds, 176) | quantize_together(generated_sprites(), 64)
    for name, picture in pictures.items():
        picture.save(ART / f"{name}.png")
    for name in ("level", "far"):
        convert(f"{name}.png", name.upper(), "--tiles", "--palette", "WORLD")
    for name, count in (("hero", 11), ("beetle", 2), ("gem", 4), ("spring", 2), ("goal", 4)):
        convert(f"{name}.png", name.upper(), "--indexed", "--frames", str(count), "--palette", "OBJ")
    sys.path.insert(0, str(ROOT / "tools"))
    import font2fnt
    font_dir = HERE / "fonts"
    font2fnt.build("pressstart2p", str(font_dir / "arcade.fnt"), None, 2)
    for name in ("FONT_MAIN.fnt", "FONT_BOLD.fnt", "FONT_MAIN_L.fnt", "FONT_BOLD_L.fnt"):
        shutil.copy(ROOT / "examples" / "naves" / "fonts" / name, font_dir / name)


if __name__ == "__main__":
    main()
