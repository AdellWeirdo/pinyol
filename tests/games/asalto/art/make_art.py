"""The pictures of examples/asalto, from the images they were generated as (big, not kept here): the canyon far
behind, the street in front, and the frames of the heroine, the scrap robot, the walking tank and the explosion, at
the game's size, in at most 256 colours each (so their packed pictures are exact). Run when the generated images
change; ../art.py then makes the game's assets from what this leaves here.

    uv run --with pillow examples/asalto/art/make_art.py RAW_DIR

RAW_DIR has far.png, nearA.png, explosion.png (a row of five), and <name>_ref.png plus rows of five for hero (run,
shoot), robot (walk) and walker (walk; its ref is walker.png). tools/fit_sprite.py matches each frame's
scale and feet to the still one.
"""
import subprocess
import sys
import tempfile
from pathlib import Path

from PIL import Image

HERE = Path(__file__).resolve().parent
FIT = HERE.parents[2] / "tools/fit_sprite.py"
# name: (frame w, h, body height, feet row, centre column, colours, [(sheet, anchor)...])
SPRITES = {
    "hero": (128, 96, 88, 94, 50, 64, [("run", "center"), ("shoot", "left")]),
    "robot": (96, 80, 72, 78, 52, 48, [("walk", "right")]),
    "walker": (272, 160, 150, 158, 150, 64, [("walk", "right")]),
}
NEAR_K, NEAR_FEET = 0.42, 850  # the street's scale; the row of the generated picture where feet go (screen row 292)
FAR_K, FAR_TOP = 0.4, 90       # the canyon's scale; its first row shown


def solid(img: Image.Image) -> Image.Image:  # see-through or not, nothing between
    img = img.convert("RGBA")
    img.putalpha(img.getchannel("A").point(lambda v: 255 if v >= 128 else 0))
    return img


def quantized(img: Image.Image, colours: int) -> Image.Image:  # one palette, no dithering; alpha kept
    a = img.getchannel("A")
    rgb = img.convert("RGB").quantize(colours, method=Image.Quantize.MEDIANCUT, dither=Image.Dither.NONE).convert("RGB")
    rgb.putalpha(a)
    return rgb


def stage(raw: Path) -> None:
    near = Image.open(raw / "nearA.png").convert("RGBA")
    near = near.resize((round(near.width * NEAR_K), round(near.height * NEAR_K)), Image.LANCZOS)
    top = round(NEAR_FEET * NEAR_K) - 292  # the picture's row at the screen's top
    near = quantized(solid(near.crop((0, top, near.width, top + 320))), 255)
    near.save(HERE / "near.png")
    a = near.getchannel("A")  # below the street's last see-through row the canyon never shows: it is not drawn at all
    rows = 1 + max(y for y in range(near.height) if any(a.getpixel((x, y)) < 128 for x in range(near.width)))
    far = Image.open(raw / "far.png").convert("RGB")
    far = far.resize((round(far.width * FAR_K), round(far.height * FAR_K)), Image.LANCZOS).crop(
        (0, FAR_TOP, round(far.width * FAR_K), FAR_TOP + rows))
    far.quantize(256, method=Image.Quantize.MEDIANCUT, dither=Image.Dither.NONE).convert("RGB").save(HERE / "far.png")
    print(f"far {far.size}, near {near.size}")


def still(raw: Path, name: str, out: Path, w: int, h: int, body: int, feet: int, back: int) -> None:
    ref = solid(Image.open(raw / f"{'walker' if name == 'walker' else name + '_ref'}.png"))
    ref = ref.crop(ref.getchannel("A").getbbox())
    k = body / ref.height
    ref = ref.resize((round(ref.width * k), body), Image.LANCZOS)
    frame = Image.new("RGBA", (w, h))
    frame.alpha_composite(solid(ref), (max(0, back - ref.width // 2), feet - body))
    frame.save(out)


def sprite(raw: Path, name: str) -> None:
    w, h, body, feet, back, colours, sheets = SPRITES[name]
    with tempfile.TemporaryDirectory() as t:
        t = Path(t)
        still(raw, name, t / "still.png", w, h, body, feet, back)
        frames = [Image.open(t / "still.png")]
        for sheet, anchor in sheets:
            subprocess.run([sys.executable, str(FIT), str(raw / f"{name}_{sheet}.png"), str(t / sheet), "--like",
                            str(t / "still.png"), "--split", "5", "--anchor", anchor], check=True, stdout=subprocess.DEVNULL)
            frames += [Image.open(p) for p in sorted((t / sheet).glob("*.png"))][:5]
        strip = Image.new("RGBA", (w * len(frames), h))
        for i, f in enumerate(frames):
            strip.alpha_composite(solid(f if f.size == (w, h) else f.resize((w, h))), (i * w, 0))
        quantized(strip, colours).save(HERE / f"{name}.png")
        print(f"{name}: {len(frames)} frames of {w}x{h}")


def explosion(raw: Path, cell: int = 144, big: int = 140) -> None:  # five frames, centred, the third `big` tall
    sheet = solid(Image.open(raw / "explosion.png"))
    a = sheet.getchannel("A")
    cols = [any(a.getpixel((x, y)) for y in range(0, sheet.height, 2)) for x in range(sheet.width)]
    parts, x = [], 0
    while x < sheet.width:  # runs of columns with something in them, joined across small gaps
        if not cols[x]:
            x += 1
            continue
        x0 = x
        while x < sheet.width and (cols[x] or any(cols[x:x + 12])):
            x += 1
        parts.append((x0, x))
    parts = sorted(sorted(parts, key=lambda p: p[1] - p[0])[-5:])
    boxes = [sheet.crop((x0, 0, x1, sheet.height)) for x0, x1 in parts]
    boxes = [b.crop(b.getchannel("A").getbbox()) for b in boxes]
    k = big / boxes[2].height
    strip = Image.new("RGBA", (cell * 5, cell))
    for i, b in enumerate(boxes):
        b = b.resize((max(1, round(b.width * k)), max(1, round(b.height * k))), Image.LANCZOS)
        b.thumbnail((cell, cell))
        strip.alpha_composite(solid(b), (i * cell + (cell - b.width) // 2, (cell - b.height) // 2))
    quantized(strip, 64).save(HERE / "boom.png")
    print("boom: 5 frames of", cell)


if __name__ == "__main__":
    raw = Path(sys.argv[1])
    stage(raw)
    explosion(raw)
    for name in SPRITES:
        sprite(raw, name)
