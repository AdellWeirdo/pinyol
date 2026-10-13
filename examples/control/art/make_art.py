"""The pictures of examples/control, from the images they were generated as (big, kept in web-retrogo/assets/control):
the control room, each camera's shot at the two sizes its monitors show it, the CCTV view of the player for the
end, and the report the VTR plays (a slow pan across the square, made into a clip with tools/clip2npv.py).

    python3 examples/control/art/make_art.py RAW_DIR
"""
import shutil
import subprocess
import sys
import tempfile
from pathlib import Path

from PIL import Image

HERE = Path(__file__).resolve().parent
GAME = HERE.parent
ROOT = GAME.parent.parent
SMALL, BIG = (96, 72), (128, 96)        # a source monitor's picture, the programme monitor's
ZOOM = (480, 360)                       # CAM 00 at the end: the whole screen, and more, to zoom into


def fit43(img):
    """The middle 4:3 of a picture."""
    w, h = img.size
    if w * 3 > h * 4:
        cw = h * 4 // 3
        return img.crop(((w - cw) // 2, 0, (w - cw) // 2 + cw, h))
    ch = w * 3 // 4
    return img.crop((0, (h - ch) // 2, w, (h - ch) // 2 + ch))


def scanlines(img):
    """Every third row at half brightness, as a monitor's picture looks (baked in: nothing to draw while playing)."""
    img = img.convert("RGB")
    px = img.load()
    for y in range(0, img.height, 3):
        for x in range(img.width):
            r, g, b = px[x, y]
            px[x, y] = (r // 2, g // 2, b // 2)
    return img


def save(img, name, colours=256, lines=True):
    img = scanlines(img) if lines else img.convert("RGB")
    img.quantize(colours, method=Image.Quantize.MEDIANCUT, dither=Image.Dither.NONE).convert("RGB").save(HERE / name)


def main(raw: Path) -> None:
    room = Image.open(raw / "room_raw.png").convert("RGB").resize((576, 384), Image.LANCZOS).crop((48, 0, 528, 320))
    save(room, "room.png", lines=False)
    for cam in ("cam1", "cam2", "cam3"):
        shot = fit43(Image.open(raw / f"{cam}_raw.png").convert("RGB"))
        save(shot.resize(SMALL, Image.LANCZOS), f"{cam}_s.png")
        save(shot.resize(BIG, Image.LANCZOS), f"{cam}_b.png")
    cctv = fit43(Image.open(raw / "cam00_raw.png").convert("RGB"))
    save(cctv.resize(SMALL, Image.LANCZOS), "cam00_s.png", 64)
    save(cctv.resize(BIG, Image.LANCZOS), "cam00_b.png", 64)
    save(cctv.resize(ZOOM, Image.LANCZOS), "cam00_z.png", 64, lines=False)
    # the report: ten seconds at 10 fps, a 4:3 window drifting across the square and closing in a little. Every pixel
    # changes in a pan, so each frame is whole anyway (--key 1): the tape rewinds a frame at a time, cheaply
    wide = Image.open(raw / "vtr_raw.png").convert("RGB")
    W, H = wide.size
    with tempfile.TemporaryDirectory() as t:
        n = 100
        for k in range(n):
            f = k / (n - 1)
            h = int(H * (0.92 - 0.12 * f))
            w = h * 4 // 3
            x = int((W - w) * (0.08 + 0.84 * f))
            y = int((H - h) * 0.4)
            scanlines(wide.crop((x, y, x + w, y + h)).resize(BIG, Image.LANCZOS)).save(f"{t}/f{k:03d}.png")
        subprocess.run([sys.executable, str(ROOT / "tools" / "clip2npv.py"), t, str(GAME), "VTR", "--fps", "10",
                        "--width", str(BIG[0]), "--height", str(BIG[1]), "--key", "1"], check=True)
    print("art in", HERE)


if __name__ == "__main__":
    main(Path(sys.argv[1]))
