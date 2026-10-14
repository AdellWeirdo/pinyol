"""The pictures of examples/gotico, at the game's size, as a 32-bit console's gothic action game has them: characters
in up to 256 colours (8 bits a pixel packed), many frames; a castle hall that repeats (mirrored every other time),
columns in front of everyone; and the light: a soft glow for candles and moonbeams, drawn here, that the game adds
to or mixes with what is under it (img's add and alpha).

    uv run --with pillow examples/gotico/art/make_art.py RAW_DIR     # from the generated images
    uv run --with pillow examples/gotico/art/make_art.py --placeholder  # stand-ins from examples/mazmorra

RAW_DIR has hall_far.png, hall_near.png, lluna_ref.png, lluna_a.png (standing, walking), lluna_b.png (a whip
attack; a jump), bat.png (a row of five), ghost.png and boss.png.
"""
import math
import subprocess
import sys
import tempfile
from pathlib import Path

from PIL import Image, ImageDraw

HERE = Path(__file__).resolve().parent
ROOT = HERE.parents[2]
FIT = ROOT / "tools/fit_sprite.py"
W, H, BODY, FEET, BACK = 240, 104, 88, 100, 50  # Lluna's frame: the whip reaches far to the right
HALL_W = 720
ROWS = (("a", 0, "center", 0, 1.0), ("a", 1, "center", 0, 1.0), ("b", 0, "left", 0, 1.0), ("b", 1, "center", 0, 0.6))


def solid(img: Image.Image) -> Image.Image:
    img = img.convert("RGBA")
    img.putalpha(img.getchannel("A").point(lambda v: 255 if v >= 128 else 0))
    return img


def quantized(img: Image.Image, colours: int) -> Image.Image:
    a = img.getchannel("A")
    rgb = img.convert("RGB").quantize(colours, method=Image.Quantize.MEDIANCUT, dither=Image.Dither.NONE).convert("RGB")
    rgb.putalpha(a)
    return rgb


def placed(body: Image.Image, w: int, h: int, height: int, feet: int, centre: int) -> Image.Image:
    body = solid(body)
    body = body.crop(body.getchannel("A").getbbox())
    body = solid(body.resize((max(1, round(body.width * height / body.height)), height), Image.LANCZOS))
    frame = Image.new("RGBA", (w, h))
    frame.alpha_composite(body, (max(0, min(w - body.width, centre - body.width // 2)), feet - height))
    return frame


def box_like(w: int, h: int, height: int, feet: int, centre: int, width: int) -> Image.Image:
    """A stand-in for a reference frame: a box where the body should be (its height, feet and centre)."""
    img = Image.new("RGBA", (w, h))
    ImageDraw.Draw(img).rectangle((centre - width // 2, feet - height, centre + width // 2, feet - 1), fill=(0, 0, 0, 255))
    return img


def rows(sheet: Image.Image) -> list[Image.Image]:
    a = sheet.getchannel("A")
    counts = [a.crop((0, y, sheet.width, y + 1)).histogram()[255] for y in range(sheet.height)]
    mid = sheet.height // 2
    cut = min(range(mid - sheet.height // 6, mid + sheet.height // 6), key=lambda y: (counts[y], abs(y - mid)))
    return [sheet.crop((0, 0, sheet.width, cut)), sheet.crop((0, cut, sheet.width, sheet.height))]


def fitted(img: Image.Image, like: Path, anchor: str, t: Path, name: str, k: int = 0, height: int | None = None,
           n: int = 5) -> list[Image.Image]:
    src, out = t / f"{name}.png", t / name
    img.save(src)
    cmd = [sys.executable, str(FIT), str(src), str(out), "--like", str(like), "--split", str(n), "--anchor", anchor,
           "--keep-main", "--scale-frame", str(k)] + (["--height", str(height)] if height else [])
    if subprocess.run(cmd, stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL).returncode:  # no real alpha
        subprocess.run(cmd + ["--key-bg"], check=True, stdout=subprocess.DEVNULL)
    return [Image.open(p) for p in sorted(out.glob("*.png"))][:n]


def grounded(frame: Image.Image, feet: int) -> Image.Image:
    box = frame.getchannel("A").getbbox()
    if not box:
        return frame
    out = Image.new("RGBA", frame.size)
    out.alpha_composite(frame.crop(box), (box[0], feet - (box[3] - box[1])))
    return out


def save_strip(name: str, frames: list[Image.Image], colours: int) -> None:
    w, h = frames[0].size
    s = Image.new("RGBA", (w * len(frames), h))
    for i, f in enumerate(frames):
        s.alpha_composite(solid(f if f.size == (w, h) else f.resize((w, h))), (i * w, 0))
    quantized(s, colours).save(HERE / f"{name}.png")
    print(f"{name}: {len(frames)} frames of {w}x{h}")


def lights() -> None:
    """A round glow (a candle's) and a beam of moonlight, soft: drawn opaque, the game sees them through or adds them."""
    glow = Image.new("RGBA", (96, 96))
    for y in range(96):
        for x in range(96):
            d = math.hypot(x - 47.5, y - 47.5) / 48
            if d < 1:
                k = (1 - d) ** 2
                glow.putpixel((x, y), (round(255 * k), round(150 * k), round(60 * k), 255))
    glow.save(HERE / "glow.png")
    beam = Image.new("RGBA", (120, 320))
    for y in range(320):
        half = 20 + y * 40 // 320
        for x in range(60 - half, 60 + half):
            k = (1 - abs(x - 60) / half) * (0.5 + 0.5 * (1 - y / 320))
            beam.putpixel((x, y), (round(120 * k), round(150 * k), round(255 * k), 255))
    beam.save(HERE / "beam.png")


def lluna(raw: Path) -> None:
    with tempfile.TemporaryDirectory() as t:
        t = Path(t)
        placed(Image.open(raw / "lluna_ref.png"), W, H, BODY, FEET, BACK).save(t / "like.png")
        frames = []
        for sheet, r, anchor, k, height in ROWS:
            row = rows(solid(Image.open(raw / f"lluna_{sheet}.png")))[r]
            got = fitted(row, t / "like.png", anchor, t, f"{sheet}{r}", k, round(BODY * height))
            frames += [grounded(f, FEET) for f in got] if (sheet, r) == ("b", 1) else got
        save_strip("lluna", frames, 200)


def creatures(raw: Path) -> None:
    with tempfile.TemporaryDirectory() as t:
        t = Path(t)
        box_like(120, 80, 48, 70, 60, 60).save(t / "bat_like.png")
        save_strip("bat", fitted(solid(Image.open(raw / "bat.png")), t / "bat_like.png", "center", t, "bat", 0, 48), 96)
    save_strip("ghost", [placed(Image.open(raw / "ghost.png"), 120, 150, 140, 146, 60)], 96)
    boss = solid(Image.open(raw / "boss.png"))
    boss = boss.crop(boss.getchannel("A").getbbox())
    save_strip("boss", [placed(boss, 200, 200, 190, 196, 100)], 128)


def scenery(raw: Path) -> None:
    far = Image.open(raw / "hall_far.png").convert("RGB")
    far = far.resize((HALL_W, round(far.height * HALL_W / far.width)), Image.LANCZOS)
    far.crop((0, far.height - 320, HALL_W, far.height)).quantize(256, method=Image.Quantize.MEDIANCUT,
                                                                  dither=Image.Dither.NONE).convert("RGB").save(HERE / "hall_far.png")
    near = solid(Image.open(raw / "hall_near.png"))
    near = solid(near.resize((HALL_W, round(near.height * HALL_W / near.width)), Image.LANCZOS))
    quantized(near.crop((0, 0, HALL_W, 320)), 128).save(HERE / "hall_near.png")  # the columns, not the railing below


# ------------------------------------------------------------------ stand-ins, before the generated art

def placeholder() -> None:
    m = ROOT / "examples/mazmorra/art"
    alba = Image.open(m / "alba.png").convert("RGBA")
    old = [alba.crop((i * 208, 0, i * 208 + 208, 176)) for i in range(30)]
    pick = [0, 1, 2, 3, 4] + [5, 6, 7, 8, 9] + [10, 11, 12, 13, 14] + [25, 26, 27, 28, 29]
    save_strip("lluna", [placed(old[i], W, H, BODY if i < 25 else BODY * 6 // 10, FEET, BACK) for i in pick], 200)
    bats = []
    for f in range(5):
        img = Image.new("RGBA", (120, 80))
        d = ImageDraw.Draw(img)
        lift = (2 - abs(f - 2)) * 10
        d.polygon(((60, 50), (10, 30 + lift), (30, 55)), fill=(70, 40, 90, 255))
        d.polygon(((60, 50), (110, 30 + lift), (90, 55)), fill=(70, 40, 90, 255))
        d.ellipse((48, 40, 72, 66), fill=(50, 26, 60, 255))
        bats.append(img)
    save_strip("bat", bats, 32)
    sk = Image.open(m / "skeleton.png").convert("RGBA").crop((0, 0, 176, 160))
    save_strip("ghost", [placed(sk, 120, 150, 140, 146, 60)], 64)
    boss = Image.new("RGBA", (200, 200))
    d = ImageDraw.Draw(boss)
    d.ellipse((10, 10, 190, 170), fill=(140, 136, 128, 255))
    d.rectangle((50, 140, 150, 196), fill=(140, 136, 128, 255))
    for x in (65, 135):
        d.ellipse((x - 25, 60, x + 25, 110), fill=(30, 10, 40, 255))
        d.ellipse((x - 10, 75, x + 10, 95), fill=(180, 80, 255, 255))
    save_strip("boss", [boss], 64)
    far = Image.open(m / "dungeon.png").convert("RGB")
    far.point(lambda v: v * 0.6).save(HERE / "hall_far.png")
    pillar = Image.open(m / "pillar.png").convert("RGBA")
    near = Image.new("RGBA", (HALL_W, 320))
    for x in (60, 330, 600):
        near.alpha_composite(pillar, (x, 0))
    near.save(HERE / "hall_near.png")


if __name__ == "__main__":
    if sys.argv[1:] == ["--placeholder"]:
        placeholder()
    else:
        raw = Path(sys.argv[1])
        scenery(raw)
        lluna(raw)
        creatures(raw)
    lights()
