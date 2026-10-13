"""The pictures of examples/duelo, from the images they were generated as (big, not kept here): the stage's two layers
and each fighter's frames, at the game's size, in at most 256 colours (so their packed pictures are exact). Run when
the generated images change; ../art.py then makes the game's assets from what this leaves here.

    uv run --with pillow examples/duelo/art/make_art.py RAW_DIR

RAW_DIR has stage_far.png, stage_near.png, <fighter>_ref.png, <fighter>_walk.png and <fighter>_punch.png (rows of
five frames) for each fighter. fit-sprite.py (the image skill's) matches each frame's scale and feet to the idle one.
"""
import subprocess
import sys
import tempfile
from pathlib import Path

from PIL import Image

HERE = Path(__file__).resolve().parent
FIT = Path.home() / ".claude/skills/gpt-image-bridge/bin/fit-sprite.py"
W, H, BODY, FEET, BACK = 192, 184, 168, 181, 70  # a frame; the body's height, its feet's row, its centre's column
COLOURS = 64  # a fighter's palette, shared by all its frames


def solid(img: Image.Image) -> Image.Image:  # see-through or not, nothing between
    img = img.convert("RGBA")
    img.putalpha(img.getchannel("A").point(lambda v: 255 if v >= 128 else 0))
    return img


def stage(raw: Path) -> None:
    far = Image.open(raw / "stage_far.png").convert("RGB").crop((0, 0, 1536, 780)).resize((640, 325), Image.LANCZOS)
    far = far.crop((0, 5, 640, 325)).quantize(256, method=Image.Quantize.MEDIANCUT, dither=Image.Dither.NONE)
    far.convert("RGB").save(HERE / "stage_far.png")
    near = solid(Image.open(raw / "stage_near.png").crop((0, 430, 1536, 900)).resize((572, 175), Image.LANCZOS))
    rgb = near.convert("RGB").quantize(255, method=Image.Quantize.MEDIANCUT, dither=Image.Dither.NONE).convert("RGB")
    rgb.putalpha(near.getchannel("A"))
    rgb.save(HERE / "stage_near.png")


def idle(raw: Path, name: str, out: Path) -> None:  # the reference, its body BODY px tall, feet on FEET, centre on BACK
    ref = solid(Image.open(raw / f"{name}_ref.png"))
    ref = ref.crop(ref.getchannel("A").getbbox())
    k = BODY / ref.height
    ref = ref.resize((round(ref.width * k), BODY), Image.LANCZOS)
    frame = Image.new("RGBA", (W, H))
    frame.alpha_composite(solid(ref), (max(0, BACK - ref.width // 2), FEET - BODY))
    frame.save(out)


def fighter(raw: Path, name: str) -> None:
    with tempfile.TemporaryDirectory() as t:
        t = Path(t)
        idle(raw, name, t / "idle.png")
        frames = [Image.open(t / "idle.png")]
        for move, anchor in (("walk", "center"), ("punch", "left")):  # a punch grows forward, the body stays
            subprocess.run([sys.executable, str(FIT), str(raw / f"{name}_{move}.png"), str(t / move), "--like",
                            str(t / "idle.png"), "--split", "5", "--anchor", anchor, "--keep-main"], check=True,
                           stdout=subprocess.DEVNULL)
            frames += [Image.open(p) for p in sorted((t / move).glob("*.png"))][:5]
        strip = Image.new("RGBA", (W * len(frames), H))
        for i, f in enumerate(frames):
            strip.alpha_composite(solid(f.resize((W, H)) if f.size != (W, H) else solid(f)), (i * W, 0))
        a = strip.getchannel("A")
        rgb = strip.convert("RGB").quantize(COLOURS, method=Image.Quantize.MEDIANCUT, dither=Image.Dither.NONE).convert("RGB")
        rgb.putalpha(a)
        rgb.save(HERE / f"{name}.png")
        print(f"{name}: {len(frames)} frames of {W}x{H}")


if __name__ == "__main__":
    raw = Path(sys.argv[1])
    stage(raw)
    for name in sys.argv[2:] or ("kai", "ran"):
        fighter(raw, name)
