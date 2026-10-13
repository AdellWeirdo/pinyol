"""The pictures of examples/futbol, from the images they were generated as (big, not kept here): the left half of the
pitch with its stand (the right half is the same, mirrored), and the footballer running in five frames; the same in
the other kits (only their palettes are used: img's pal). At the game's size, in at most 256 colours each.

    uv run --with pillow examples/futbol/art/make_art.py RAW_DIR

RAW_DIR has pitch.png and player_run.png (a row of five). ../../moto/art/make_art.py lends its recolouring.
"""
import importlib.util
import sys
import tempfile
from pathlib import Path

from PIL import Image

HERE = Path(__file__).resolve().parent
spec = importlib.util.spec_from_file_location("moto_art", HERE.parent.parent / "moto" / "art" / "make_art.py")
moto = importlib.util.module_from_spec(spec)
spec.loader.exec_module(moto)
HALF = 917  # the halfway line's middle, at this size: the mirrored half starts there


def main(raw: Path) -> None:
    pitch = Image.open(raw / "pitch.png").convert("RGB").resize((952, 635), Image.LANCZOS).crop((0, 0, HALF, 635))
    # its halfway line leans a little: mirrored it would be a V. The grass just left of it goes over it (the game draws
    # the line, straight); the turf's stripes run up and down, so the copy matches
    pitch.paste(pitch.crop((HALF - 34, 228, HALF - 17, 635)), (HALF - 17, 228))
    pitch.quantize(256, method=Image.Quantize.MEDIANCUT, dither=Image.Dither.NONE).convert("RGB").save(HERE / "pitch.png")
    runs = moto.row(Image.open(raw / "player_run.png"), 5)
    k = 60 / max(r.height for r in runs)
    strip = Image.new("RGBA", (72 * 5, 72))
    for i, r in enumerate(runs):  # feet on row 70, the body's centre on column 30
        r = moto.solid(r.resize((round(r.width * k), round(r.height * k)), Image.LANCZOS))
        strip.alpha_composite(r, (i * 72 + 30 - r.width // 2, 70 - r.height))
    red = moto.in565(moto.quantized(moto.solid(strip), 48))
    red.save(HERE / "player.png")
    moto.recoloured(red.copy(), 0.61).save(HERE / "kit_blue.png")
    moto.recoloured(red.copy(), 0.15).save(HERE / "kit_yellow.png")
    moto.recoloured(red.copy(), 0.36).save(HERE / "kit_green.png")
    print("pitch", pitch.size, "player 5 frames of 72x72")


if __name__ == "__main__":
    main(Path(sys.argv[1]))
