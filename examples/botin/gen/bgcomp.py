"""bgcomp: the layer behind the ground, made of three pictures (the far sky, the mid hills, the near foreground) painted into ONE picture, the way GBA artists packed a scene
into the few layers the chip had. The first design drew a layer for each of the three, and each full-screen layer cost about a fifth of a 60 fps frame on the console, so the
pictures are painted over each other offline into two bands, each scrolled at its own speed by line_scroll:

    band A (picture rows 0..95):   the mid hills over the far sky       -> screen lines 0..79,  slow
    band B (picture rows 96..191): the near foreground over the far sky -> screen lines 80..159, faster

The result is a direct-colour background (`bg(2, {image = ...})`): a bitmap layer is cheaper for the console to draw than a tile map (measured: 2.8 ms of a frame), and it
keeps the exact colours of the three pictures, with no tile or bank limits. The ground (BG1) stays a tile map with palette banks."""
from __future__ import annotations

import subprocess
import sys
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent))
from PIL import Image  # noqa: E402

from gbakit import ART, ASSETS  # noqa: E402

BAND = 96        # lines of each band (80 shown + up to 16 of vertical parallax)
MID_TOP = 16     # the mid picture's row shown at the top of band A (its dark foot is below what is seen)
FAR_B = 80       # the far picture's row at the top of band B
TOOLS = Path(__file__).resolve().parents[3] / "tools"


def _rgb_of(set_: str, bank: str, idx: int):
    return ART.palettes[set_][bank][idx - 1]


def painted(biome: str):
    far, fset, fbank = ART.sceneries[f"{biome}_far"]
    mid, mset, mbank = ART.sceneries[f"{biome}_mid"]
    near, nset, nbank = ART.sceneries[f"{biome}_near"]
    w = len(far[0])
    img = [[None] * w for _ in range(2 * BAND)]
    for y in range(BAND):
        for x in range(w):
            m = mid[MID_TOP + y][x] if MID_TOP + y < len(mid) else 0
            img[y][x] = _rgb_of(mset, mbank, m) if m else _rgb_of(fset, fbank, far[min(len(far) - 1, y)][x])
    for y in range(BAND):
        for x in range(w):
            n = near[y][x] if y < len(near) else 0
            img[BAND + y][x] = _rgb_of(nset, nbank, n) if n else _rgb_of(fset, fbank, far[min(len(far) - 1, FAR_B + y)][x])
    return img


def compose(biome: str, tmp: Path) -> None:
    img = painted(biome)
    for k in ("far", "mid", "near", "agua"):  # (the sea's blended overlay is not used: a blended layer costs a frame)
        ART.sceneries.pop(f"{biome}_{k}", None)
    im = Image.new("RGB", (len(img[0]), len(img)))
    im.putdata([c for row in img for c in row])
    tmp.mkdir(exist_ok=True)
    png = tmp / f"{biome}_hills.png"
    im.save(png)
    ASSETS.mkdir(parents=True, exist_ok=True)
    subprocess.run([sys.executable, str(TOOLS / "png2asset.py"), str(png), str(ASSETS), f"{biome.upper()}_BGIMG", "--type", "background"], check=True, stdout=subprocess.DEVNULL)
    print(f"  {biome}: hills picture {im.size[0]}x{im.size[1]}")
