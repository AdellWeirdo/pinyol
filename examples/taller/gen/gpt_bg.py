"""The backgrounds of Taller de los Autómatas, made with the image model and fitted: three stages (three 960x320 street chunks each, whole scenes), the pillars that stand in front of
the seams, the title and the character-select backdrop.

    python3 gen/gpt_bg.py gen     # the raw pictures (resumes)
    python3 gen/gpt_bg.py make    # raw -> art/*.png, 254 colours
"""
from __future__ import annotations

import json
import os
import subprocess
import sys
import time
from concurrent.futures import ThreadPoolExecutor
from pathlib import Path

import numpy as np
from PIL import Image

HERE = Path(__file__).resolve().parent
sys.path.insert(0, str(HERE))
import gpt_make as M  # noqa: E402

RAW = M.RAW
ART = M.ART
BRIDGE = Path.home() / ".claude/skills/gpt-image-bridge/bin/gpt-image-2"
STYLE = ("Mid-1990s Capcom CPS2 arcade game background art (Armored Warriors, Battle Circuit, Final Fight): hand-pixelled, painterly, dark warm outlines, rich saturated colours with strong "
         "lighting, steampunk Victorian city of clockmakers in 1890 (brass, copper, gears, steam, gas lamps, clock faces). Side view, no characters, no text, no signs with letters.")
STAGES = {
    "calle": ("a night street of clockmakers' shops: shopfronts with giant clock faces and gears in their windows, gas lamps, bell towers, iron balconies, a cobbled street, warm window light under a blue night sky",
              "a night skyline of a Victorian clockwork city: tall clock towers with lit clock faces, chimneys with steam, a huge pale moon like a clock face, layered hazy blue silhouettes"),
    "fabrica": ("the inside of a roaring brass factory floor: furnaces glowing orange, conveyor belts, giant rotating gears and flywheels, steam pipes and pressure gauges, riveted iron walls, a metal-plate floor",
                "a vast factory interior far wall in hazy orange glow: rows of smokestacks seen through huge arched windows, gantry cranes, steam, giant gears in the dark, layered silhouettes"),
    "torre": ("the inside of a great clock tower: a giant wall of interlocking brass gears, hanging chains and pendulums, wooden beams, a stained-glass clock-face window glowing gold, a stone and wood floor",
              "the dark depths of a clock tower mechanism: an enormous glowing clock face seen from behind through a mesh of gears, pendulums and chains, layered shadowy silhouettes, golden light shafts"),
}
FLOOR = ("Wide panoramic strip, exactly 3:1. The scenery fills the upper two thirds; the lower third is the walkable FLOOR of the street seen at a slight angle, with horizontal paving lines "
         "and a clear level edge, empty and clean (characters will walk there), flat even lighting on the floor so strips join. Nothing important touches the left and right edges.")


def ask(prompt: str, out: Path, ref: Path | None, size: str) -> bool:
    if out.exists() and out.stat().st_size > 10_000:
        return True
    for _ in range(2):
        cmd = [str(BRIDGE), prompt, str(out), "--size", size] + (["--ref", str(ref)] if ref else [])
        subprocess.run(cmd, capture_output=True, text=True, timeout=1500)
        if out.exists() and out.stat().st_size > 10_000:
            print("ok", out.name, flush=True)
            return True
        print("FAILED", out.name, flush=True)
        time.sleep(5)
    return False


def gen() -> None:
    style = RAW / "style_ref.png"
    jobs = []
    variants = ("a long view with a big central feature", "a different stretch, with a doorway or arch and some clutter on the left", "another stretch with machinery or shop details dense on the right")
    for st, (near, far) in STAGES.items():
        for k, v in zip("abc", variants):
            jobs.append((f"{near}. Variant: {v}. {FLOOR} {STYLE}", RAW / f"bg_near_{st}_{k}.png", style, "1920x640"))
    jobs.append(("Three tall support PILLARS side by side in one row for the foreground of a beat 'em up, front-on, each full height of the picture and about one fifth of its width, with wide gaps: "
                 "1) a cast-iron lamp-post column with brass rings and a gas lantern halfway up, 2) a riveted factory girder column with a pipe and a pressure gauge, 3) a carved wooden clock-tower beam "
                 f"wrapped in a chain with a small brass gear. {STYLE} Plain flat transparent background.", RAW / "bg_pillars.png", style, "1536x1024"))
    jobs.append((f"Title screen backdrop: a grand view of the clockmakers' city at dusk with a colossal clock tower in the middle, its huge lit clock face glowing, gears turning in the sky, steam, an empty open "
                 f"foreground street. Dramatic, leave the top third calm for a title. {STYLE}", RAW / "bg_title.png", style, "1536x1024"))
    jobs.append((f"Character-select backdrop: the inside of an inventor's workshop with a dark wall, three equal arched alcoves evenly spaced at left, centre and right, each with a lit brass pedestal and "
                 f"empty space above it, tools and gears hung around, a wooden floor in front. {STYLE}", RAW / "bg_select.png", style, "1536x1024"))
    with ThreadPoolExecutor(int(os.environ.get("GPT_WORKERS", 5))) as ex:
        res = list(ex.map(lambda j: ask(*j), jobs))
    print(f"{sum(res)}/{len(res)} done")


def quant(im: Image.Image, colours: int = 254) -> Image.Image:
    return im.convert("RGB").quantize(colours, method=Image.Quantize.MEDIANCUT, dither=Image.Dither.NONE).convert("RGB")


def make() -> None:
    ART.mkdir(exist_ok=True)
    for st in STAGES:
        for k in "abc":
            im = Image.open(RAW / f"bg_near_{st}_{k}.png").convert("RGB").resize((960, 320), Image.LANCZOS)
            quant(im).save(ART / f"near_{st}_{k}.png")
    for name in ("title", "select"):
        quant(Image.open(RAW / f"bg_{name}.png").convert("RGB").resize((480, 320), Image.LANCZOS)).save(ART / f"{name}.png")
    # the pillars: three tall pictures, each scaled to 320 rows tall and 96 wide at most, on one strip
    sheet = M.key_background(Image.open(RAW / "bg_pillars.png"))
    pieces = M.split_frames(sheet, 3)
    frames = []
    for p in pieces:
        k = min(320 / p.height, 120 / p.width)
        p = p.resize((max(1, round(p.width * k)), max(1, round(p.height * k))), Image.LANCZOS)
        fr = Image.new("RGBA", (128, 320))
        fr.alpha_composite(p, (64 - p.width // 2, 320 - p.height))
        frames.append(M.solid(fr))
    strip = Image.new("RGBA", (128 * 3, 320))
    for i, f in enumerate(frames):
        strip.alpha_composite(f, (i * 128, 0))
    M.quantized(strip, 15).save(ART / "pillars.png")
    (ART / "pillars.json").write_text(json.dumps({"w": 128, "h": 320, "anchor": [64, 319], "frames": ["calle", "fabrica", "torre"], "edge_ok": True}))
    print("backgrounds made")


if __name__ == "__main__":
    {"gen": gen, "make": make}[sys.argv[1]]()
