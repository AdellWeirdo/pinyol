"""The pictures of examples/torneo, at the game's size, as a CPS2 fighting game has them: each fighter in 15 colours and
see-through (16, four bits a pixel), thirty frames, no zoom; the stage in three layers (the far courtyard, a floor
that is drawn in bands for its perspective, pillars in front of everyone).

    uv run --with pillow examples/torneo/art/make_art.py RAW_DIR     # from the generated images
    uv run --with pillow examples/torneo/art/make_art.py --placeholder  # stand-ins from examples/duelo, a drawn floor

RAW_DIR has stage_far.png, stage_floor.png (a texture seen from above, laid here in perspective), stage_front.png and, for each fighter (alba, gorm), <name>_ref.png and
three sheets of two rows of five frames: <name>_a.png (standing, walking), <name>_b.png (a slash, a kick) and
<name>_c.png (hurt, reeling, guarding, falling, lying; a jump). tools/fit_sprite.py gives every frame the standing
one's scale and feet.
"""
import colorsys
import math
import subprocess
import sys
import tempfile
from pathlib import Path

from PIL import Image, ImageDraw

HERE = Path(__file__).resolve().parent
ROOT = HERE.parents[2]
FIT = ROOT / "tools/fit_sprite.py"
W, H, BODY, FEET, BACK = 208, 176, 136, 172, 76  # a frame; the body's height, its feet's row, its centre's column
COLOURS = 15                                    # and see-through: a CPS2 palette
FAR_W, FAR_H = 640, 262                          # the courtyard, down to just under the floor's top
FLOOR_W, FLOOR_H = 820, 72                       # the floor, from the screen's row 248 to the bottom
FIGHTERS = ("alba", "gorm")
# the sheets' rows, in the strip's order: (sheet, row, anchor); 30 frames
ROWS = (("a", 0, "center"), ("a", 1, "center"), ("b", 0, "left"), ("b", 1, "left"), ("c", 0, "center"),
        ("c", 1, "center"))


def solid(img: Image.Image) -> Image.Image:  # see-through or not, nothing between
    img = img.convert("RGBA")
    img.putalpha(img.getchannel("A").point(lambda v: 255 if v >= 128 else 0))
    return img


def quantized(img: Image.Image, colours: int) -> Image.Image:
    a = img.getchannel("A")
    rgb = img.convert("RGB").quantize(colours, method=Image.Quantize.MEDIANCUT, dither=Image.Dither.NONE).convert("RGB")
    rgb.putalpha(a)
    return rgb


def placed(body: Image.Image) -> Image.Image:  # a cut-out body on a frame: BODY tall, feet on FEET, centre on BACK
    body = solid(body)
    body = body.crop(body.getchannel("A").getbbox())
    k = BODY / body.height
    body = solid(body.resize((max(1, round(body.width * k)), BODY), Image.LANCZOS))
    frame = Image.new("RGBA", (W, H))
    frame.alpha_composite(body, (max(0, BACK - body.width // 2), FEET - BODY))
    return frame


def grounded(frame: Image.Image) -> Image.Image:  # its lowest pixel on FEET (a jump's height is the game's, not the art's)
    box = frame.getchannel("A").getbbox()
    if not box:
        return frame
    out = Image.new("RGBA", frame.size)
    out.alpha_composite(frame.crop(box), (box[0], min(H - (box[3] - box[1]), FEET - (box[3] - box[1]))))
    return out


def rows(sheet: Image.Image) -> list[Image.Image]:  # two rows of frames, cut at the emptiest row near the middle
    a = sheet.getchannel("A")
    counts = [a.crop((0, y, sheet.width, y + 1)).histogram()[255] for y in range(sheet.height)]  # opaque pixels
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


def strip(frames: list[Image.Image]) -> Image.Image:
    s = Image.new("RGBA", (W * len(frames), H))
    for i, f in enumerate(frames):
        s.alpha_composite(solid(f if f.size == (W, H) else f.resize((W, H))), (i * W, 0))
    return quantized(s, COLOURS)


def alternate(img: Image.Image) -> Image.Image:  # the second player's colours: clothes turned half round, not skin
    rgb565 = lambda c: (c[0] >> 3, c[1] >> 2, c[2] >> 3)
    px = img.load()
    colours = sorted({px[x, y][:3] for y in range(img.height) for x in range(img.width) if px[x, y][3]})
    new, used, by565 = {}, set(), {}
    for c in colours:  # the same pixels, each of the console's colours its own: the palette keeps its order, so the
        if rgb565(c) in by565:  # game can borrow it (two colours that are one on the console stay one)
            new[c] = by565[rgb565(c)]
            continue
        h, l, s = colorsys.rgb_to_hls(*(v / 255 for v in c))
        skin = 0.03 < h < 0.14 and l > 0.3  # skin and hair keep theirs, as a CPS2 game's second colours do
        n = tuple(round(v * 255) for v in colorsys.hls_to_rgb((h + 0.5) % 1, l, s)) if s > 0.25 and not skin else c
        while rgb565(n) in used:
            n = (n[0], min(255, n[1] + 4), min(255, n[2] + 8)) if n[2] < 248 else (n[0], max(0, n[1] - 4), n[2] - 16)
        used.add(rgb565(n))
        new[c] = by565[rgb565(c)] = n
    out = img.copy()
    po = out.load()
    for y in range(img.height):
        for x in range(img.width):
            if px[x, y][3]:
                po[x, y] = new[px[x, y][:3]] + (255,)
    return out


def fighter(raw: Path, name: str) -> None:
    with tempfile.TemporaryDirectory() as t:
        t = Path(t)
        placed(Image.open(raw / f"{name}_ref.png")).save(t / "like.png")
        frames = []
        for sheet, r, anchor in ROWS:
            row = rows(solid(Image.open(raw / f"{name}_{sheet}.png")))[r]
            got = fitted(row, t / "like.png", anchor, t, f"{sheet}{r}")
            frames += [grounded(f) for f in got] if (sheet, r) == ("c", 1) else got
        save_fighter(name, frames)


def save_fighter(name: str, frames: list[Image.Image]) -> None:
    s = strip(frames)
    s.save(HERE / f"{name}.png")
    alternate(s).save(HERE / f"{name}_b.png")
    print(f"{name}: {len(frames)} frames of {W}x{H}, {COLOURS} colours and see-through")


def stage(raw: Path) -> None:
    far = Image.open(raw / "stage_far.png").convert("RGB")
    k = FAR_W / far.width
    far = far.resize((FAR_W, round(far.height * k)), Image.LANCZOS)
    far.crop((0, 0, FAR_W, FAR_H)).quantize(256, method=Image.Quantize.MEDIANCUT, dither=Image.Dither.NONE) \
        .convert("RGB").save(HERE / "stage_far.png")
    floor(Image.open(raw / "stage_floor.png").convert("RGB")).save(HERE / "stage_floor.png")
    front = solid(Image.open(raw / "stage_front.png"))
    front = solid(front.resize((480, round(front.height * 480 / front.width)), Image.LANCZOS))
    quantized(front.crop((0, front.height - 320, 480, front.height)), 63).save(HERE / "stage_front.png")


# ------------------------------------------------------------------ stand-ins, before the generated art

def floor(texture: Image.Image | None = None) -> Image.Image:
    """The floor seen from the middle of the stage: a texture seen from above (or drawn flags) laid in perspective."""
    img = Image.new("RGB", (FLOOR_W, FLOOR_H))
    px = img.load()
    tex = texture.resize((256, 256), Image.LANCZOS).load() if texture else None
    for y in range(FLOOR_H):
        z = 18.0 / (y + 6)  # depth: far at the top
        shade = 0.72 + 0.28 * y / FLOOR_H
        for x in range(FLOOR_W):
            u, v = (x - FLOOR_W / 2) * z / 26, z * 3.2
            if tex:
                c = tex[int(u * 64) % 256, int(v * 64) % 256]
            else:
                edge = min(u % 1, 1 - u % 1, v % 1, 1 - v % 1) < 0.05 + 0.02 * z
                c = (70, 58, 50) if edge else ((150, 132, 112) if (math.floor(u) + math.floor(v)) % 2 else (176, 158, 134))
            px[x, y] = tuple(round(v * shade) for v in c)
    return img


def drawn_front() -> Image.Image:  # two stone pillars at the edges, a banner on each
    img = Image.new("RGBA", (480, 320))
    d = ImageDraw.Draw(img)
    for x0 in (0, 436):
        d.rectangle((x0, 0, x0 + 43, 319), fill=(92, 80, 72, 255), outline=(30, 24, 22, 255))
        d.rectangle((x0 + 6, 0, x0 + 12, 319), fill=(128, 114, 100, 255))
        d.rectangle((x0 + 8, 40, x0 + 36, 150), fill=(150, 30, 40, 255), outline=(40, 10, 14, 255))
    return img


def placeholder() -> None:
    duelo = ROOT / "examples/duelo/art"
    for name, src in (("alba", "kai.png"), ("gorm", "ran.png")):
        sheet = Image.open(duelo / src).convert("RGBA")
        old = [sheet.crop((i * 192, 0, i * 192 + 192, 184)) for i in range(sheet.width // 192)]
        pick = [0] * 5 + [1, 2, 3, 4, 5] + [6, 7, 8, 9, 10] * 2 + [0] * 10
        save_fighter(name, [placed(old[i]) for i in pick])
    Image.open(duelo / "stage_far.png").convert("RGB").crop((0, 0, FAR_W, FAR_H)).save(HERE / "stage_far.png")
    floor().save(HERE / "stage_floor.png")
    drawn_front().save(HERE / "stage_front.png")


if __name__ == "__main__":
    if sys.argv[1:] == ["--placeholder"]:
        placeholder()
    else:
        raw = Path(sys.argv[1])
        stage(raw)
        for name in sys.argv[2:] or FIGHTERS:
            fighter(raw, name)
