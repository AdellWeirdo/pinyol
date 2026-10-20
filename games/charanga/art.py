# /// script
# requires-python = ">=3.10"
# dependencies = ["pillow>=10"]
# ///
"""La Charanga de Emergencia's pictures: raw/ (generated, prompts in raw/prompts.txt) -> art/ (fitted) -> assets/.

    uv run art.py

The look is "PlayStation and Saturn 2D" (docs/art.md): pictures at the screen's 480x320, characters about 100 pixels
tall. The sizes below are the ones scene.lua places them by: change them together.
"""
from __future__ import annotations

import os
import subprocess
import sys
from pathlib import Path

from PIL import Image

HERE = Path(__file__).resolve().parent
RAW, ART, ASSETS = HERE / "raw", HERE / "art", HERE / "assets"
PINYOL = Path(os.environ.get("PINYOL", HERE.parents[1]))

PERSON_BODY = 100              # the protagonist standing, head to feet
PERSON_FRAME = (120, 112)      # each pose's frame; feet at the bottom middle (anchor 60,109)
BAND_BODY = 104                # the band marching, tallest raised hand to feet
BAND_FRAME = (150, 116)        # each band pose's frame; feet at the bottom middle (anchor 75,113)
BAND_POSES = 4                 # apiñados, desfilan, fanfarria, celebran
POSES = 5                      # sentada, de pie, avanza, duda, llama


def solid(img: Image.Image) -> Image.Image:
    """Every pixel opaque or clear: the engine's transparency is all or nothing."""
    img = img.convert("RGBA")
    a = img.getchannel("A").point(lambda v: 255 if v >= 128 else 0)
    img.putalpha(a)
    return img


def no_pockets(img: Image.Image, below: float = 0.6) -> Image.Image:
    """The painted checkerboard left between legs (it does not touch the border, so --key-bg keeps it): light grey with
    no colour, only in the frame's lower part, where there are no white shirts; the drum's skin is cream, it stays."""
    px = img.load()
    for y in range(int(img.height * below), img.height):
        for x in range(img.width):
            r, g, b, a = px[x, y]
            if a and min(r, g, b) > 170 and max(r, g, b) - min(r, g, b) < 18:
                px[x, y] = (0, 0, 0, 0)
    return img


def fit(img: Image.Image, body: int) -> Image.Image:
    """Crop to what is visible and scale so it is `body` pixels tall."""
    img = img.convert("RGBA")
    img = img.crop(img.getbbox())
    k = body / img.height
    return solid(img.resize((max(1, round(img.width * k)), body), Image.LANCZOS))


def convert(png: Path, asset: str, *extra: str) -> None:
    subprocess.run([sys.executable, str(PINYOL / "tools" / "png2asset.py"), str(png), str(ASSETS), asset, *extra], check=True)


def background() -> None:
    img = Image.open(RAW / "bg_pasillo.png").convert("RGB").resize((480, 320), Image.LANCZOS)
    img.save(ART / "pasillo.png")
    convert(ART / "pasillo.png", "BG_PASILLO", "--packed")


def band() -> None:
    """The band's poses, fitted to the marching one (the reference): without the sheet, that one four times."""
    body = fit(Image.open(RAW / "charanga.png"), BAND_BODY)
    w, h = BAND_FRAME
    like = Image.new("RGBA", BAND_FRAME, (0, 0, 0, 0))
    like.paste(body, ((w - body.width) // 2, h - 3 - body.height), body)
    like.save(ART / "banda_idle.png")
    frames = [like] * BAND_POSES
    poses = RAW / "charanga_poses.png"
    if poses.exists():
        tmp = ART / "banda_poses"
        tmp.mkdir(exist_ok=True)
        subprocess.run([sys.executable, str(PINYOL / "tools" / "fit_sprite.py"), str(poses), str(tmp), "--like",
                        str(ART / "banda_idle.png"), "--split", str(BAND_POSES), "--scale-frame", "1",
                        "--key-bg", "--keep-main"], check=True)  # (the sheet came with a checkerboard painted in, no alpha)
        frames = [no_pockets(solid(Image.open(p))) for p in sorted(tmp.glob("*.png"))][:BAND_POSES]
    strip = Image.new("RGBA", (w * BAND_POSES, h), (0, 0, 0, 0))
    for i, f in enumerate(frames):
        strip.paste(f, (i * w, 0), f)
    strip.save(ART / "banda.png")
    convert(ART / "banda.png", "SPR_BANDA", "--frames", str(BAND_POSES), "--anchor", f"{w // 2},{h - 3}", "--packed")


def idle() -> Path:
    """The protagonist standing (the reference), in its frame: the size every pose is fitted to."""
    body = fit(Image.open(RAW / "persona_ref.png"), PERSON_BODY)
    frame = Image.new("RGBA", PERSON_FRAME, (0, 0, 0, 0))
    w, h = PERSON_FRAME
    frame.paste(body, ((w - body.width) // 2, h - 3 - body.height), body)
    out = ART / "persona_idle.png"
    frame.save(out)
    return out


def person() -> None:
    like = idle()
    poses = RAW / "persona_poses.png"
    frames = [Image.open(like)]
    if poses.exists():  # the five poses fitted to the standing frame; without them, the standing one five times
        tmp = ART / "poses"
        tmp.mkdir(exist_ok=True)
        subprocess.run([sys.executable, str(PINYOL / "tools" / "fit_sprite.py"), str(poses), str(tmp), "--like", str(like),
                        "--split", str(POSES), "--keep-main", "--scale-frame", "1"], check=True)  # (frame 0 sits: the standing one gives the scale)
        frames = [solid(Image.open(p)) for p in sorted(tmp.glob("*.png"))][:POSES]
    while len(frames) < POSES:
        frames.append(frames[-1])
    w, h = PERSON_FRAME
    strip = Image.new("RGBA", (w * POSES, h), (0, 0, 0, 0))
    for i, f in enumerate(frames):
        f = f.crop((0, 0, w, h)) if f.size != PERSON_FRAME else f
        strip.paste(f, (i * w, 0), f)
    strip.save(ART / "persona.png")
    convert(ART / "persona.png", "SPR_PERSONA", "--frames", str(POSES), "--anchor", f"{w // 2},{h - 3}", "--packed")


if __name__ == "__main__":
    ART.mkdir(exist_ok=True)
    ASSETS.mkdir(exist_ok=True)
    background()
    band()
    person()
