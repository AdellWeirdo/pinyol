"""The pictures of examples/calle, from the images they were generated as (big, not kept here): the night street and
the thug's frames, at the game's size, in at most 256 colours each. The hero is examples/duelo's Kai (its art/kai.png).

    uv run --with pillow examples/calle/art/make_art.py RAW_DIR

RAW_DIR has street.png, thug_ref.png and thug_moves.png (a row of five: walking three, a punch, reeling back).
"""
import shutil
import subprocess
import sys
import tempfile
from pathlib import Path

from PIL import Image

HERE = Path(__file__).resolve().parent
FIT = Path.home() / ".claude/skills/gpt-image-bridge/bin/fit-sprite.py"
W, H, BODY, FEET, BACK = 192, 184, 168, 181, 122  # as duelo's fighters, facing left: the body's centre on BACK


def solid(img: Image.Image) -> Image.Image:
    img = img.convert("RGBA")
    img.putalpha(img.getchannel("A").point(lambda v: 255 if v >= 128 else 0))
    return img


def quantized(img: Image.Image, colours: int) -> Image.Image:
    a = img.getchannel("A")
    rgb = img.convert("RGB").quantize(colours, method=Image.Quantize.MEDIANCUT, dither=Image.Dither.NONE).convert("RGB")
    rgb.putalpha(a)
    return rgb


def main(raw: Path) -> None:
    street = Image.open(raw / "street.png").convert("RGB").resize((720, 480), Image.LANCZOS).crop((0, 100, 720, 420))
    street.quantize(256, method=Image.Quantize.MEDIANCUT, dither=Image.Dither.NONE).convert("RGB").save(HERE / "street.png")
    with tempfile.TemporaryDirectory() as t:
        t = Path(t)
        ref = solid(Image.open(raw / "thug_ref.png"))
        ref = ref.crop(ref.getchannel("A").getbbox())
        ref = ref.resize((round(ref.width * BODY / ref.height), BODY), Image.LANCZOS)
        still = Image.new("RGBA", (W, H))
        still.alpha_composite(solid(ref), (min(W - ref.width, max(0, BACK - ref.width // 2)), FEET - BODY))
        still.save(t / "still.png")
        subprocess.run([sys.executable, str(FIT), str(raw / "thug_moves.png"), str(t / "moves"), "--like", str(t / "still.png"),
                        "--split", "5", "--anchor", "right"], check=True, stdout=subprocess.DEVNULL)
        frames = [still] + [Image.open(p) for p in sorted((t / "moves").glob("*.png"))][:5]
        strip = Image.new("RGBA", (W * len(frames), H))
        for i, f in enumerate(frames):
            strip.alpha_composite(solid(f if f.size == (W, H) else f.resize((W, H))), (i * W, 0))
        quantized(strip, 64).save(HERE / "thug.png")
    shutil.copy(HERE.parent.parent / "duelo" / "art" / "kai.png", HERE / "kai.png")
    print("street, thug: 6 frames, kai")


if __name__ == "__main__":
    main(Path(sys.argv[1]))
