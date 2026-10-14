"""The pictures of examples/mazmorra, at the game's size, as a CPS2 beat-em-up has them: every character in 15 colours
and see-through (16, four bits a pixel), never zoomed; a dungeon wall that repeats (mirrored every other time) and a
stone pillar drawn in front of everyone. The heroine is examples/torneo's Alba (its art/alba.png).

    uv run --with pillow examples/mazmorra/art/make_art.py RAW_DIR     # from the generated images
    uv run --with pillow examples/mazmorra/art/make_art.py --placeholder  # stand-ins: examples/calle's thug, drawn stone

RAW_DIR has dungeon.png, pillar.png and, for each enemy (goblin, skeleton), <name>_ref.png and <name>_moves.png: two
rows of five frames, facing left: walking; then winding up, striking, recovering, hurt, lying down.
"""
import colorsys
import shutil
import subprocess
import sys
import tempfile
from pathlib import Path

from PIL import Image, ImageDraw

HERE = Path(__file__).resolve().parent
ROOT = HERE.parents[2]
FIT = ROOT / "tools/fit_sprite.py"
W, H, FEET, BACK = 176, 160, 156, 110  # an enemy's frame (facing left: its centre on BACK, a strike grows leftwards)
BODY = {"goblin": 92, "skeleton": 132}  # their heights; Alba's body is 136
COLOURS = 15
WALL_W = 720


def solid(img: Image.Image) -> Image.Image:
    img = img.convert("RGBA")
    img.putalpha(img.getchannel("A").point(lambda v: 255 if v >= 128 else 0))
    return img


def quantized(img: Image.Image, colours: int) -> Image.Image:
    a = img.getchannel("A")
    rgb = img.convert("RGB").quantize(colours, method=Image.Quantize.MEDIANCUT, dither=Image.Dither.NONE).convert("RGB")
    rgb.putalpha(a)
    return rgb


def placed(body: Image.Image, height: int) -> Image.Image:
    body = solid(body)
    body = body.crop(body.getchannel("A").getbbox())
    body = solid(body.resize((max(1, round(body.width * height / body.height)), height), Image.LANCZOS))
    frame = Image.new("RGBA", (W, H))
    frame.alpha_composite(body, (min(W - body.width, max(0, BACK - body.width // 2)), FEET - height))
    return frame


def rows(sheet: Image.Image) -> list[Image.Image]:  # two rows, cut at the emptiest row near the middle
    a = sheet.getchannel("A")
    counts = [a.crop((0, y, sheet.width, y + 1)).histogram()[255] for y in range(sheet.height)]
    mid = sheet.height // 2
    cut = min(range(mid - sheet.height // 6, mid + sheet.height // 6), key=lambda y: (counts[y], abs(y - mid)))
    return [sheet.crop((0, 0, sheet.width, cut)), sheet.crop((0, cut, sheet.width, sheet.height))]


def fitted(row: Image.Image, like: Path, anchor: str, t: Path, name: str) -> list[Image.Image]:
    src, out = t / f"{name}.png", t / name
    row.save(src)
    cmd = [sys.executable, str(FIT), str(src), str(out), "--like", str(like), "--split", "5", "--anchor", anchor,
           "--keep-main"]
    if subprocess.run(cmd, stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL).returncode:  # no real alpha
        subprocess.run(cmd + ["--key-bg"], check=True, stdout=subprocess.DEVNULL)
    return [Image.open(p) for p in sorted(out.glob("*.png"))][:5]


def save_strip(name: str, frames: list[Image.Image]) -> None:
    s = Image.new("RGBA", (W * len(frames), H))
    for i, f in enumerate(frames):
        s.alpha_composite(solid(f if f.size == (W, H) else f.resize((W, H))), (i * W, 0))
    quantized(s, COLOURS).save(HERE / f"{name}.png")
    print(f"{name}: {len(frames)} frames of {W}x{H}")


def enemy(raw: Path, name: str) -> None:
    with tempfile.TemporaryDirectory() as t:
        t = Path(t)
        placed(Image.open(raw / f"{name}_ref.png"), BODY[name]).save(t / "like.png")
        walk, rest = rows(solid(Image.open(raw / f"{name}_moves.png")))
        save_strip(name, fitted(walk, t / "like.png", "center", t, "walk") +
                   fitted(rest, t / "like.png", "right", t, "rest"))


def scenery(raw: Path) -> None:
    wall = Image.open(raw / "dungeon.png").convert("RGB")
    wall = wall.resize((WALL_W, round(wall.height * WALL_W / wall.width)), Image.LANCZOS)
    wall.crop((0, wall.height - 320, WALL_W, wall.height)).quantize(256, method=Image.Quantize.MEDIANCUT,
                                                                    dither=Image.Dither.NONE).convert("RGB").save(HERE / "dungeon.png")
    pillar = solid(Image.open(raw / "pillar.png"))
    pillar = pillar.crop(pillar.getchannel("A").getbbox())
    pillar = solid(pillar.resize((round(pillar.width * 320 / pillar.height), 320), Image.LANCZOS))
    quantized(pillar, 31).save(HERE / "pillar.png")


def alba() -> None:
    shutil.copy(ROOT / "examples/torneo/art/alba.png", HERE / "alba.png")


# ------------------------------------------------------------------ stand-ins, before the generated art

def tinted(img: Image.Image, hue: float | None, light: float) -> Image.Image:
    out = img.copy()
    px = out.load()
    for y in range(out.height):
        for x in range(out.width):
            r, g, b, a = px[x, y]
            if a:
                h, l, s = colorsys.rgb_to_hls(r / 255, g / 255, b / 255)
                h, s = (hue, s) if hue is not None else (h, s * 0.15)
                px[x, y] = tuple(round(v * 255) for v in colorsys.hls_to_rgb(h, min(1, l * light), s)) + (255,)
    return out


def drawn_wall() -> Image.Image:
    img = Image.new("RGB", (WALL_W, 320), (34, 32, 44))
    d = ImageDraw.Draw(img)
    for row, y in enumerate(range(0, 200, 20)):
        for x in range(-40 * (row % 2), WALL_W, 80):
            d.rectangle((x + 1, y + 1, x + 78, y + 18), fill=(58 + row * 2, 54 + row * 2, 70), outline=(22, 20, 30))
    d.rectangle((280, 40, 440, 200), fill=(14, 12, 20))
    d.pieslice((280, -40, 440, 120), 180, 360, fill=(14, 12, 20))
    for y in range(200, 320, 16):
        for x in range(-(y // 16 % 2) * 30, WALL_W, 60):
            d.rectangle((x, y, x + 58, y + 14), fill=(72 - (320 - y) // 6, 64 - (320 - y) // 6, 60), outline=(30, 26, 28))
    return img


def drawn_pillar() -> Image.Image:
    img = Image.new("RGBA", (96, 320))
    d = ImageDraw.Draw(img)
    d.rectangle((12, 24, 84, 319), fill=(84, 78, 92, 255), outline=(20, 18, 26, 255))
    d.rectangle((20, 24, 30, 319), fill=(118, 110, 124, 255))
    d.rectangle((0, 0, 95, 24), fill=(98, 90, 104, 255), outline=(20, 18, 26, 255))
    return img


def placeholder() -> None:
    thug = Image.open(ROOT / "examples/calle/art/thug.png").convert("RGBA")
    old = [thug.crop((i * 192, 0, i * 192 + 192, 184)) for i in range(6)]
    pick = [1, 2, 3, 2, 1, 0, 4, 4, 5, 5]  # walking five; winding up, striking, recovering; hurt; down
    for name, hue, light in (("goblin", 0.3, 0.9), ("skeleton", None, 1.5)):
        save_strip(name, [tinted(placed(old[i], BODY[name]), hue, light) for i in pick])
    drawn_wall().save(HERE / "dungeon.png")
    drawn_pillar().save(HERE / "pillar.png")


if __name__ == "__main__":
    if sys.argv[1:] == ["--placeholder"]:
        placeholder()
    else:
        raw = Path(sys.argv[1])
        scenery(raw)
        for name in BODY:
            enemy(raw, name)
    alba()
