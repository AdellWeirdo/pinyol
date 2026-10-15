# /// script
# requires-python = ">=3.10"
# dependencies = ["pillow>=10.1"]
# ///
"""The README's moving pictures, made from what the site moves (site/src): the header logo's intro, the console
booting in the hero, LÍNEA 0 being made in the editor, the Library's tutorial, and how a frame reaches the panel in
strips.

    uv run docs/media/make.py      # needs ffmpeg
"""
from __future__ import annotations

import math
import subprocess
import sys
from pathlib import Path

from PIL import Image, ImageDraw

HERE = Path(__file__).resolve().parent
ROOT = HERE.parents[1]
VIDEO = ROOT / "site/src/video"


def webp(src: Path, out: str, vf: str) -> None:
    """A video as an animated WebP: half a GIF's weight for the same picture."""
    subprocess.run(["ffmpeg", "-v", "error", "-y", "-i", str(src), "-vf", vf, "-c:v", "libwebp_anim", "-q:v", "75",
                    "-compression_level", "6", "-loop", "0", "-an", str(HERE / out)], check=True)


def ease(a: float, b: float, t: float) -> float:
    """CSS's default `ease` between two keyframes, close enough: a smoothstep."""
    t = min(max(t, 0), 1)
    return a + (b - a) * t * t * (3 - 2 * t)


def track(keys: list[tuple[float, tuple]], pct: float) -> tuple:
    """The value of a keyframe track at pct (0..100)."""
    if pct <= keys[0][0]:
        return keys[0][1]
    for (p0, v0), (p1, v1) in zip(keys, keys[1:]):
        if pct <= p1:
            return tuple(ease(a, b, (pct - p0) / (p1 - p0)) for a, b in zip(v0, v1))
    return keys[-1][1]


def logo() -> None:
    """The header logo (site/src/styles.css, logo-seed/word/leaves): the seed drops and squashes, the word slides in,
    the leaves sprout; at full size, with the logo cut in its three pieces as the console's intro cuts it."""
    sys.path.insert(0, str(ROOT / "firmware/cirera"))
    import art  # noqa: E402  the console's intro: logo_parts() cuts docs/logo.png into seed, leaves and word
    box = Image.open(ROOT / "docs/logo.png").getchannel("A").getbbox()
    art.LOGO_W = box[2] - box[0]  # the pieces at the logo's own size
    parts = art.logo_parts()["parts"]
    W, H = parts["seed"].size
    # the CSS's percentages are of the site's 165x104 pieces, whose seed spans x 0..42, y 27..84: map them here
    sb = parts["seed"].getbbox()
    k = (sb[2] - sb[0]) / 42
    at = lambda x, y: (sb[0] + x * k, sb[1] + (y - 27) * k)
    # keyframes: (percent of the 15 s cycle, (dx, dy, rotation, scale x, scale y)), dx/dy in site pixels; and opacity
    seed = [(0, (0, -114.4, -14, 1, 1)), (4.5, (0, 0, 0, 1, 1)), (5.5, (0, 0, 0, 1.1, .86)), (7, (0, 0, 0, 1, 1))]
    word = [(0, (74.25, 0, 0, 1, 1)), (4, (74.25, 0, 0, 1, 1)), (6.5, (-8.25, 0, 0, 1, 1)), (8, (0, 0, 0, 1, 1))]
    leaves = [(0, (0, 0, 0, 0, 0)), (6, (0, 0, 0, 0, 0)), (8.5, (0, 0, 0, 1.18, 1.18)), (10, (0, 0, 0, 1, 1))]
    fade = {"seed": [(0, (0,)), (2, (1,))], "word": [(0, (0,)), (4, (0,)), (6.5, (1,))], "leaves": [(0, (1,))]}
    origins = {"seed": at(165 * .25, 104 * .92), "word": at(0, 27), "leaves": at(165 * .32, 104 * .34)}
    pad = 40  # room for the overshoots
    frames, fps = [], 30
    for f in range(round(1.6 * fps)):
        pct = f / fps / 15 * 100
        canvas = Image.new("RGBA", (W + 2 * pad, H + 2 * pad))
        for name, keys in (("leaves", leaves), ("seed", seed), ("word", word)):
            dx, dy, rot, sx, sy = track(keys, pct)
            alpha = track(fade[name], pct)[0]
            if sx == 0 or alpha == 0:
                continue
            ox, oy = origins[name]
            # inverse of: move to the origin, scale, rotate, move back, translate
            c, s = math.cos(math.radians(rot)), math.sin(math.radians(rot))
            tx, ty = ox + dx * k + pad, oy + dy * k + pad
            a, b, d, e = c / sx, s / sx, -s / sy, c / sy
            layer = parts[name].transform(canvas.size, Image.AFFINE,
                                          (a, b, ox - a * tx - b * ty, d, e, oy - d * tx - e * ty), Image.BICUBIC)
            if alpha < 1:
                layer.putalpha(layer.getchannel("A").point(lambda v: round(v * alpha)))
            canvas.alpha_composite(layer)
        frames.append(canvas)
    durations = [round(1000 / fps)] * (len(frames) - 1) + [15000 - 1000 * len(frames) // fps]  # again every 15 s
    frames[0].save(HERE / "logo.webp", save_all=True, append_images=frames[1:], duration=durations, loop=0,
                   quality=85, method=6)


def strips() -> None:
    """How a frame reaches the panel (site/charts.py strips_demo): 15 strips, each filled from the top by both cores,
    half each, then on the panel; two shots in turn, so every strip changes. Slow: 4.8 s a loop."""
    shot = Image.open(ROOT / "docs/looks/neogeo.png").convert("RGB")
    shot2 = Image.open(ROOT / "docs/looks/32bits.png").convert("RGB")
    W, H = shot.size
    sw = W // 15
    core = [(232, 52, 78, 217), (255, 201, 74, 217)]
    frames, fps, loop = [], 12, 4.8
    for f in range(round(loop * fps)):
        t = f / fps
        im = shot.copy().convert("RGBA")
        over = Image.new("RGBA", im.size)
        draw = ImageDraw.Draw(over)
        for i in range(15):
            p = ((t - i * .15) % loop) / loop * 100  # this strip's own place in the loop, in percent
            x0 = i * sw
            if 3.1 < p <= 53.1:  # the second shot is on the panel
                im.paste(shot2.crop((x0, 0, x0 + sw, H)), (x0, 0))
            for start in (0, 50):  # drawn by the cores, then gone in a moment
                q = p - start
                if 0 <= q < 5:
                    h = round(H * min(q / 3.1, 1))
                    a = 1 if q < 3.1 else 1 - (q - 3.1) / 1.9
                    for half, rgba in enumerate(core if h else ()):
                        x = x0 + half * sw // 2
                        draw.rectangle((x, 0, x + sw // 2 - 1, h - 1), fill=rgba[:3] + (round(rgba[3] * a),))
            if i < 14:
                for y in range(0, H, 6):  # the dashed line between strips
                    draw.line((x0 + sw - 1, y, x0 + sw - 1, y + 2), fill=(255, 255, 255, 46))
        im.alpha_composite(over)
        frames.append(im.convert("RGB").tobytes())
    # a GIF, so the pixels stay sharp; ffmpeg keeps only what changes from one frame to the next
    subprocess.run(["ffmpeg", "-v", "error", "-y", "-f", "rawvideo", "-pix_fmt", "rgb24", "-s", f"{W}x{H}", "-r", str(fps),
                    "-i", "-", "-filter_complex",
                    "split[a][b];[a]palettegen=stats_mode=full[p];[b][p]paletteuse=dither=none:diff_mode=rectangle",
                    "-loop", "0", str(HERE / "strips.gif")], input=b"".join(frames), check=True)


def main() -> None:
    logo()
    strips()
    # the console booting: the pinyol intro, Cirera's menu and some games, at the console's own 480x320
    webp(VIDEO / "consola.mp4", "console.webp", "fps=15,scale=480:-1:flags=lanczos")
    # LÍNEA 0 being made in the editor, eight times as fast
    webp(VIDEO / "linea0.mp4", "editor.webp", "setpts=PTS/8,fps=10,scale=640:-1:flags=lanczos")
    # the Library's tutorial, from the editor's .zip to the game on the site, eight times as fast
    webp(VIDEO / "subir.mp4", "library.webp", "setpts=PTS/8,fps=10,scale=640:-1:flags=lanczos")
    for out in ("logo.webp", "strips.gif", "console.webp", "editor.webp", "library.webp"):
        print(f"{out}: {(HERE / out).stat().st_size / 1e6:.1f} MB")


if __name__ == "__main__":
    main()
