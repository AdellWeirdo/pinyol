# /// script
# requires-python = ">=3.10"
# dependencies = ["pillow>=10.1", "fonttools>=4"]
# ///
"""Cirera's game list, made with pinyol: its pictures and letters, as pinyol's brand manual has them.

    uv run firmware/cirera/art.py      # assets/, fonts/

The logo (docs/logo.png) in pieces that put back together are the logo exactly: the seed, its leaves and the word, at
the size the intro draws them. The intro's frames, drawn for it with an image model (art/intro_seed.png: the seed
falling, landing in dust, sprouting; art/intro_word.png: the word arriving as a streak of light, settling, a light
across it, a sparkle; five frames each, on the ink), cut and fitted to those pieces, so the last frame lands on the
logo. Cirera's logo for the list's header (art/cirera_logo.png), a light band the list adds over the chosen cover
(the covers are the games' own, cover.rgb565, given by the console: console_cover), and the manual's two fonts.
"""
from __future__ import annotations

import json
import shutil
import subprocess
import sys
from pathlib import Path

from PIL import Image, ImageDraw

HERE = Path(__file__).resolve().parent
ROOT = HERE.parents[1]
ART, ASSETS = HERE / "art", HERE / "assets"
LOGO_W = 300  # the intro's logo, in screen pixels


def convert(png: Path, aid: str, *opts: str) -> None:
    subprocess.run([sys.executable, str(ROOT / "tools/png2asset.py"), str(png), str(ASSETS), aid, "--packed", *opts],
                   check=True, stdout=subprocess.DEVNULL)


def solid(img: Image.Image) -> Image.Image:
    img = img.convert("RGBA")
    img.putalpha(img.getchannel("A").point(lambda v: 255 if v >= 128 else 0))
    return img


def strip(frames: list[Image.Image]) -> Image.Image:
    s = Image.new("RGBA", (frames[0].width * len(frames), frames[0].height))
    for i, f in enumerate(frames):
        s.alpha_composite(f, (i * f.width, 0))
    return s


def logo_parts() -> dict:
    """The seed, the leaves and the word: every pixel of the logo in exactly one of them."""
    logo = Image.open(ROOT / "docs/logo.png").convert("RGBA")
    px = logo.load()
    W, H = logo.size
    owner = [[None] * W for _ in range(H)]
    for y in range(H):  # the leaves: green, and everything above the word on the left
        for x in range(W):
            p = px[x, y]
            if p[3] and ((y < 128 and x < 235) or (p[1] > p[0] + 20 and p[1] > p[2] + 20 and y < 160 and x < 175)):
                owner[y][x] = "leaves"
    # the rest: each patch of colour (the outline left out) belongs to the seed or the word by where it is; then each
    # outline pixel to the nearest patch, so the seed never takes a sliver of the "p"
    dark = lambda p: p[0] * 3 + p[1] * 6 + p[2] < 500
    queue = []
    for y in range(H):
        for x in range(W):
            if owner[y][x] or not px[x, y][3] or dark(px[x, y]):
                continue
            patch, stack, xs = [], [(x, y)], 0
            owner[y][x] = "?"
            while stack:
                cx, cy = stack.pop()
                patch.append((cx, cy))
                xs += cx
                for nx, ny in ((cx + 1, cy), (cx - 1, cy), (cx, cy + 1), (cx, cy - 1)):
                    if 0 <= nx < W and 0 <= ny < H and owner[ny][nx] is None and px[nx, ny][3] and not dark(px[nx, ny]):
                        owner[ny][nx] = "?"
                        stack.append((nx, ny))
            part = "seed" if xs / len(patch) < 140 else "word"
            for cx, cy in patch:
                owner[cy][cx] = part
            queue += patch
    while queue:  # outlines: the nearest patch's
        nxt = []
        for x, y in queue:
            for nx, ny in ((x + 1, y), (x - 1, y), (x, y + 1), (x, y - 1)):
                if 0 <= nx < W and 0 <= ny < H and owner[ny][nx] is None and px[nx, ny][3]:
                    owner[ny][nx] = owner[y][x]
                    nxt.append((nx, ny))
        queue = nxt
    parts = {k: Image.new("RGBA", logo.size) for k in ("seed", "leaves", "word")}
    for y in range(H):
        for x in range(W):
            if owner[y][x] in parts:
                parts[owner[y][x]].putpixel((x, y), px[x, y])
    box = logo.getchannel("A").getbbox()
    k = LOGO_W / (box[2] - box[0])
    size = (round(logo.width * k), round(logo.height * k))
    out = {}
    for name, img in parts.items():  # each at the intro's size, on the same canvas: they line up when drawn together
        out[name] = solid(img.resize(size, Image.LANCZOS))
    return {"parts": out, "box": [round(v * k) for v in box], "size": size}


def leaves_growing(leaves: Image.Image, frames: int = 6) -> list[Image.Image]:
    """The leaves coming out of the seed: scaled up from where the stem meets it."""
    box = leaves.getchannel("A").getbbox()
    base = (box[0] + (box[2] - box[0]) * 0.45, box[3])  # the stem's foot
    out = []
    for i in range(1, frames + 1):
        k = i / frames
        f = Image.new("RGBA", leaves.size)
        crop = leaves.crop(box)
        w, h = max(1, round(crop.width * k)), max(1, round(crop.height * k))
        small = solid(crop.resize((w, h), Image.LANCZOS))
        f.alpha_composite(small, (round(base[0] - (base[0] - box[0]) * k), round(base[1] - h)))
        out.append(f)
    return out




def shine_band() -> Image.Image:
    """A slanted band of light, added over the chosen cover as it lands."""
    w, h = 72, 176  # the chosen cover's height (160 x 1.1): drawn as it is, not scaled
    band = Image.new("RGBA", (w, h))
    d = band.load()
    for y in range(h):
        for x in range(w):
            u = abs(x - 36 - (y - h / 2) * 0.35) / 22
            if u < 1:
                v = round(110 * (1 - u) ** 1.5)
                d[x, y] = (v, v, round(v * 1.1), 255)
    return band




def key_ink(img: Image.Image, tolerance: int = 30) -> Image.Image:
    """The sheet's flat ink background made see-through: flooded from the borders, every pixel near its colour."""
    img = img.convert("RGBA")
    w, h = img.size
    px = img.load()
    border = sorted(px[x, y][:3] for x in range(0, w, 7) for y in (0, h - 1))
    bg = border[len(border) // 2]
    near = lambda c: sum(abs(c[i] - bg[i]) for i in range(3)) <= tolerance
    seen = bytearray(w * h)
    stack = [(x, y) for x in range(w) for y in (0, h - 1)] + [(x, y) for y in range(h) for x in (0, w - 1)]
    while stack:
        x, y = stack.pop()
        if not (0 <= x < w and 0 <= y < h) or seen[y * w + x] or not near(px[x, y]):
            continue
        seen[y * w + x] = 1
        px[x, y] = (0, 0, 0, 0)
        stack += ((x + 1, y), (x - 1, y), (x, y + 1), (x, y - 1))
    return img


def intro_frames(sheet: str, like: Image.Image, anchor: str, t: Path) -> Image.Image:
    """A sheet of five frames on the ink, cut and fitted to a piece of the logo (tools/fit_sprite.py: one scale, set by
    the last frame, which is the piece itself), as a strip on the logo's canvas."""
    like.save(t / "like.png")
    key_ink(Image.open(ART / f"{sheet}.png")).save(t / "keyed.png")
    out = t / sheet
    subprocess.run([sys.executable, str(ROOT / "tools/fit_sprite.py"), str(t / "keyed.png"), str(out), "--like",
                    str(t / "like.png"), "--split", "5", "--scale-frame", "4", "--anchor", anchor],
                   check=True, stdout=subprocess.DEVNULL)
    return strip([solid(Image.open(f)) for f in sorted(out.glob("*.png"))][:5])


def sky() -> Image.Image:
    """The night behind the menu, as the manual's cover has it: a fixed scatter of faint stars and a few bright ones
    that twinkle (two frames). Packed, a picture keeps only its stars: one call draws them all."""
    frames = []
    for f in range(2):
        img = Image.new("RGBA", (480, 320))
        seed = 7
        for i in range(46):
            seed = (seed * 1103515245 + 12345) % 2147483648
            x, y = seed % 479, (seed // 480) % 319
            bright = i % 5 == 0
            if bright and (i // 5 + f) % 2 == 0:
                img.paste((238, 240, 255, 255), (x, y, x + 2, y + 2))
            else:
                img.putpixel((x, y), (80, 86, 122, 255))
        frames.append(img)
    return strip(frames)


def cirera_logo(height: int) -> Image.Image:
    """The console's logo for the list's header: at least 96 pixels wide, as the manual asks."""
    img = Image.open(ART / "cirera_logo.png").convert("RGBA")
    img = img.crop(img.getchannel("A").point(lambda v: 255 if v >= 128 else 0).getbbox())
    return solid(img.resize((round(img.width * height / img.height), height), Image.LANCZOS))


def main() -> None:
    import tempfile
    ART.mkdir(exist_ok=True)
    ASSETS.mkdir(exist_ok=True)
    logo = logo_parts()
    p = logo["parts"]
    p["seed"].save(ART / "seed.png")
    strip(leaves_growing(p["leaves"])).save(ART / "leaves.png")
    p["word"].save(ART / "word.png")
    convert(ART / "seed.png", "SEED")
    convert(ART / "leaves.png", "LEAVES", "--frames", "6")
    convert(ART / "word.png", "WORD")
    with tempfile.TemporaryDirectory() as t:
        seed_leaves = p["seed"].copy()
        seed_leaves.alpha_composite(p["leaves"])
        intro_frames("intro_seed", seed_leaves, "center", Path(t)).save(ART / "intro_seed_fit.png")
        intro_frames("intro_word", p["word"], "right", Path(t)).save(ART / "intro_word_fit.png")
    convert(ART / "intro_seed_fit.png", "INTRO_SEED", "--frames", "5")
    convert(ART / "intro_word_fit.png", "INTRO_WORD", "--frames", "5")
    head = cirera_logo(38)
    assert head.width >= 96, head.size
    head.save(ART / "cirera_head.png")
    convert(ART / "cirera_head.png", "CIRERA_LOGO")
    sky().save(ART / "sky.png")
    convert(ART / "sky.png", "SKY", "--frames", "2")
    shine_band().save(ART / "shine.png")
    convert(ART / "shine.png", "SHINE")
    sys.path.insert(0, str(ROOT / "tools"))
    import font2fnt
    font2fnt.build("jersey15", str(HERE / "fonts" / "title.fnt"), None, 1)
    font2fnt.build("silkscreen", str(HERE / "fonts" / "label.fnt"), None, 2)
    for f in ("FONT_MAIN.fnt", "FONT_BOLD.fnt", "FONT_MAIN_L.fnt", "FONT_BOLD_L.fnt"):  # the engine's own, as every game
        shutil.copy(ROOT / "examples" / "naves" / "fonts" / f, HERE / "fonts" / f)
    print(f"logo {logo['size']} box {logo['box']}, header {head.size}")


if __name__ == "__main__":
    main()
