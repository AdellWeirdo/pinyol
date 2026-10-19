# /// script
# requires-python = ">=3.10"
# dependencies = ["pillow>=10.1", "fonttools>=4"]
# ///
"""Audreygotchi's art in four Game Boy tones, made from the board game's own drawings.

    uv run games/audreygotchi/art.py [AUDREYGOTCHI_ASSETS]

AUDREYGOTCHI_ASSETS is the board repo's `audreygotchi/assets` (default: ~/Desktop/DEV/pinyol/AUDREYGOTCHI-main/...).
Every picture is scaled down and each pixel goes to one of four tones by its brightness, as a Game Boy Camera did:
no image generation, the owner's drawings as they are. Packed (png2asset --packed), four colours each:

    A_<SET>    Audrey's sets (audrey/<set>/<set>_N.png), on their canvas, all at one scale (S)
    BG_<NAME>  backgrounds (backgrounds/bg_<name>.png), 240 wide, the bottom 144 rows (the floor stays)
    IC_<NAME>  icons (icons/<name>.png), 16 tall (status bars' 10, rooms' 18, effects 12, big ones 32)
"""
from __future__ import annotations

import json
import re
import shutil
import sys
from pathlib import Path

from PIL import Image

HERE = Path(__file__).resolve().parent
ROOT = HERE.parents[1]
ASSETS = HERE / "assets"
SRC = Path(sys.argv[1] if len(sys.argv) > 1 else
           Path.home() / "Desktop/DEV/pinyol/AUDREYGOTCHI-main/audreygotchi/assets")
TONES = [(224, 248, 208), (136, 192, 112), (52, 104, 86), (8, 24, 32)]  # BGB's greens, lightest to darkest
S_CINE = 1 / 3  # the cinematic sets (birth, farewell): the board's scene drawn whole, 240 board px to 160 world
CINE_SETS = ("rocket_", "audrey_", "nace_", "anda_despedida", "bg_balcony_front")
CINE_BGS = ("bg_nace_", "bg_living", "bg_balcony_open", "bg_casa_noche")
S = 0.364  # board canvas px -> world px: a sitting grown Audrey ~56 px tall on a 144 px room (77 of 220 on the board)
SPRITE_LUT = [0 if v > 200 else 1 if v > 140 else 2 if v > 70 else 3 for v in range(256)]  # her fur: tone 1
# props drawn pale and without an outline (pink feathers, a pink wand): darker tones and a dark outline, as a Game Boy
# sprite needs over a light room
PROPS = {"pluma", "pluma_fantasma", "varita", "cepillo", "nudo_pelo"}
PROP_LUT = [0 if v > 235 else 1 if v > 175 else 2 if v > 95 else 3 for v in range(256)]
BIG_ICONS = {"logo", "regalo", "deco_arbol", "deco_diada"}  # icons drawn larger than 16
SMALL_ICONS = {"moon", "fx_heart", "fx_sparkle", "fx_paw"}  # and smaller (bar_ 10, room_ 18)


sys.path.insert(0, str(ROOT / "tools"))
import png2asset  # noqa: E402  (the engine's converter)

GB = HERE / "design" / "gb"  # the Game Boy redraw (design/build_gb.py): sets, rooms; used wherever it exists
sys.path.insert(0, str(HERE / "design"))
from gb_icons import ICONS as GB_ICONS  # noqa: E402  (icons drawn by hand)


def exact_tones(im: Image.Image) -> Image.Image:
    """A Game Boy picture snapped to the four tones exactly (the redraw's are, give or take a rounding)."""
    im = im.convert("RGBA")
    tone = im.convert("L").point([0 if v > 192 else 1 if v > 120 else 2 if v > 50 else 3 for v in range(256)])
    out = Image.frombytes("P", im.size, tone.tobytes())
    out.putpalette([c for t in TONES for c in t])
    out = out.convert("RGBA")
    out.putalpha(im.getchannel("A").point(lambda a: 255 if a >= 128 else 0))
    return out


def text_icon(art: str) -> Image.Image:
    rows = art.strip("\n").split("\n")
    im = Image.new("RGBA", (len(rows[0]), len(rows)))
    for y, row in enumerate(rows):
        for x, ch in enumerate(row):
            if ch in "0123":
                im.putpixel((x, y), TONES[int(ch)] + (255,))
    return im


def shifted(im: Image.Image, by: int) -> Image.Image:
    """Every tone `by` steps darker (+) or lighter (-): a room at night, or pale under a game."""
    px = im.convert("RGB").load()
    out = Image.new("RGB", im.size)
    o = out.load()
    for y in range(im.height):
        for x in range(im.width):
            t = min(range(4), key=lambda k: sum(abs(a - b) for a, b in zip(px[x, y], TONES[k])))
            o[x, y] = TONES[max(0, min(3, t + by))]
    return out


def four_tones(im: Image.Image, size: tuple[int, int], lut: list[int]) -> Image.Image:
    """Scaled to size, each opaque pixel one of the four tones by brightness (lut), the rest see-through."""
    small = im.convert("RGBA").resize(size, Image.LANCZOS)
    tone = small.convert("L").point(lut)
    pal = Image.frombytes("P", size, tone.tobytes())
    pal.putpalette([c for t in TONES for c in t])
    out = pal.convert("RGBA")
    out.putalpha(small.getchannel("A").point(lambda a: 255 if a >= 128 else 0))
    return out


def outlined(im: Image.Image) -> Image.Image:
    """A dark ring (tone 3) round the drawing, inside its canvas."""
    out = im.copy()
    a = im.getchannel("A").load()
    px = out.load()
    w, h = im.size
    for y in range(h):
        for x in range(w):
            if a[x, y]:
                continue
            if any(0 <= x + dx < w and 0 <= y + dy < h and a[x + dx, y + dy]
                   for dx, dy in ((1, 0), (-1, 0), (0, 1), (0, -1))):
                px[x, y] = TONES[3] + (255,)
    return out


def night_lut(im: Image.Image) -> list[int]:
    """A night's cuts: a dark picture stays dark: 20 % tone 0, 30 % tone 1, 30 % tone 2, 20 % tone 3."""
    lum = sorted(im.convert("L").tobytes())
    q80, q50, q20 = (lum[int(len(lum) * p)] for p in (0.80, 0.50, 0.20))
    return [0 if v > q80 else 1 if v > q50 else 2 if v > q20 else 3 for v in range(256)]


def is_night(stem: str) -> bool:
    return "noche" in stem or (stem.startswith("bg_nace_") and "dia" not in stem)


def quantile_lut(im: Image.Image) -> list[int]:
    """A background's own cuts, washed out so Audrey stands out on it (as Game Boy rooms were): its brightest 55 %
    tone 0, then 28 % tone 1, 12 % tone 2, the darkest 5 % tone 3."""
    lum = sorted(im.convert("L").tobytes())
    q50, q18, q05 = (lum[int(len(lum) * p)] for p in (0.45, 0.17, 0.05))
    return [0 if v > q50 else 1 if v > q18 else 2 if v > q05 else 3 for v in range(256)]


def pack(aid: str, frames: list[Image.Image]) -> int:
    png2asset.export_packed(ASSETS, aid, frames, 4)
    return (ASSETS / f"{aid}.pk").stat().st_size


def numbered(folder: Path) -> list[Path]:
    files = [p for p in folder.glob("*.png") if re.search(r"_(\d+)\.png$", p.name)]
    return sorted(files, key=lambda p: int(re.search(r"_(\d+)\.png$", p.name).group(1)))


KNOT_ENDS: list[list[int]] = []  # the Game Boy knot's ends, frame by frame (world px from its left)


def audrey() -> tuple[int, int, list[str], dict]:
    total, count, sets, crops = 0, 0, [], {}
    folders = {f.name: f for f in (SRC / "audrey").iterdir() if f.is_dir()}
    if GB.is_dir():
        folders.update({f.name: f for f in GB.iterdir() if f.is_dir() and f.name != "rooms"})
    for name in sorted(folders):
        folder = folders[name]
        files = numbered(folder)
        if not files:
            continue
        if folder.parent == GB:  # redrawn for the Game Boy: as it is, on its own canvas
            frames = [exact_tones(Image.open(f)) for f in files]
            if name == "nudos":  # the knot's three ends: the lowest point of each third of the drawing
                for f in frames:
                    box = f.getbbox()
                    ends = []
                    for k in range(3):
                        x0 = box[0] + (box[2] - box[0]) * k // 3
                        x1 = box[0] + (box[2] - box[0]) * (k + 1) // 3
                        low = max(((y, x) for x in range(x0, x1) for y in range(box[1], box[3])
                                   if f.getpixel((x, y))[3]), default=(0, (x0 + x1) // 2))
                        ends.append(low[1])
                    KNOT_ENDS.append(ends)
            crops[name] = frames[0].getbbox() or (0, 0) + frames[0].size
            total += pack("A_" + name.upper(), frames)
            count += len(frames)
            sets.append(name)
            continue
        first = Image.open(files[0])
        k = S_CINE if folder.name.startswith(CINE_SETS) else S
        size = (round(first.width * k), round(first.height * k))
        if folder.name in PROPS:
            frames = [outlined(four_tones(Image.open(f), size, PROP_LUT)) for f in files]
        else:
            frames = [four_tones(Image.open(f), size, SPRITE_LUT) for f in files]
        crops[folder.name] = frames[0].getbbox() or (0, 0, size[0], size[1])  # her drawing in its canvas
        total += pack("A_" + folder.name.upper(), frames)
        count += len(frames)
        sets.append(folder.name)
    return total, count, sets, crops


def backgrounds() -> int:
    total = 0
    for f in sorted((GB / "rooms").glob("bg_*.png")) if (GB / "rooms").is_dir() else []:
        im = Image.open(f).convert("RGB")  # a Game Boy room: 240x160, the whole screen
        name = "BG_" + f.stem[3:].upper()
        total += pack(name, [exact_tones(im)])
        total += pack(name + "_NOCHE", [shifted(im, 1).convert("RGBA")])
        total += pack(name + "_PALE", [shifted(im, -1).convert("RGBA")])
    redrawn = {f.stem for f in (GB / "rooms").glob("bg_*.png")} if (GB / "rooms").is_dir() else set()
    for f in sorted((SRC / "backgrounds").glob("bg_*.png")):
        if f.stem in redrawn or f.stem.removesuffix("_noche") in redrawn:
            continue
        im = Image.open(f).convert("RGB")
        h = round(im.height * 240 / im.width)
        im = im.resize((240, h), Image.LANCZOS).crop((0, max(0, h - 144), 240, h))
        lut = night_lut(im) if is_night(f.stem) else quantile_lut(im)
        frame = four_tones(im.convert("RGBA"), im.size, lut)
        total += pack("BG_" + f.stem[3:].upper(), [frame])
        if not f.stem.startswith("bg_nace"):  # the games' rooms, a tone lighter: their pieces stand out on them
            pale = four_tones(im.convert("RGBA"), im.size, [max(0, t - 1) for t in lut])
            total += pack("BG_" + f.stem[3:].upper() + "_PALE", [pale])
    for f in sorted((SRC / "backgrounds").glob("bg_*.png")):  # the cinema: the whole picture, 160x160
        if not f.stem.startswith(CINE_BGS):
            continue
        im = Image.open(f).convert("RGB").resize((160, 160), Image.LANCZOS)
        lut = night_lut(im) if is_night(f.stem) else quantile_lut(im)
        total += pack("C_" + f.stem[3:].upper(), [four_tones(im.convert("RGBA"), im.size, lut)])
    dawn = Image.open(SRC / "audrey" / "splash_fondo" / "splash_fondo_0.png").convert("RGB")
    dawn = dawn.resize((240, round(dawn.height * 240 / dawn.width)), Image.LANCZOS)
    top = (dawn.height - 160) // 2
    dawn = dawn.crop((0, top, 240, top + 160))
    total += pack("C_SPLASH_FONDO", [four_tones(dawn.convert("RGBA"), dawn.size, quantile_lut(dawn))])
    return total


def icons() -> int:
    total = 0
    for stem, art in GB_ICONS.items():
        total += pack("IC_" + stem.upper(), [text_icon(art)])
    for f in sorted((SRC / "icons").glob("*.png")):
        if f.stem in GB_ICONS:
            continue
        im = Image.open(f).convert("RGBA")
        im = im.crop(im.getbbox())
        h = (32 if f.stem in BIG_ICONS or f.stem.startswith(("visita_", "deco_")) else
             10 if f.stem.startswith("bar_") else 18 if f.stem.startswith("room_") else
             12 if f.stem in SMALL_ICONS else 16)
        w = max(1, round(im.width * h / im.height))
        total += pack("IC_" + f.stem.upper(), [four_tones(im, (w, h), SPRITE_LUT)])
    logo = Image.open(SRC / "icons" / "logo.png").convert("RGBA")
    logo = logo.crop(logo.getbbox())
    total += pack("TITLE_LOGO", [four_tones(logo, (180, round(logo.height * 180 / logo.width)), SPRITE_LUT)])
    return total


def fonts() -> None:
    import font2fnt
    (HERE / "fonts").mkdir(exist_ok=True)
    font2fnt.build("pressstart2p", str(HERE / "fonts" / "gb.fnt"), None, 2)  # 8x8 letters, 16x16 on the screen
    for f in ("FONT_MAIN.fnt", "FONT_BOLD.fnt", "FONT_MAIN_L.fnt", "FONT_BOLD_L.fnt"):  # the engine's own
        shutil.copy(ROOT / "examples" / "bolsillo" / "fonts" / f, HERE / "fonts" / f)


def main() -> None:
    if not (SRC / "audrey").is_dir():
        raise SystemExit(f"no Audreygotchi art at {SRC}: pass the board repo's audreygotchi/assets")
    if ASSETS.exists():
        shutil.rmtree(ASSETS)
    ASSETS.mkdir()
    a_bytes, a_frames, sets, crops = audrey()
    b_bytes, i_bytes = backgrounds(), icons()
    (HERE / "sets.lua").write_text("-- made by art.py: Audrey's sets that have art (A_<SET>)\nreturn {\n" +
                                   "".join(f'  {s} = true,\n' for s in sets) + "}\n")
    (HERE / "ends.lua").write_text("-- made by art.py: the Game Boy knot's three ends, frame by frame, world px from its left\nreturn {\n" +
                                   "".join(f"  {{{a}, {b}, {c}}},\n" for a, b, c in KNOT_ENDS) + "}\n")
    (HERE / "crops.lua").write_text("-- made by art.py: where each set's first frame is drawn in its canvas, {x, y, w, h} world px\nreturn {\n" +
                                    "".join(f'  {k} = {{{b[0]}, {b[1]}, {b[2] - b[0]}, {b[3] - b[1]}}},\n' for k, b in sorted(crops.items())) + "}\n")
    fonts()
    print(json.dumps({"audrey_sets": len(sets), "audrey_frames": a_frames, "audrey_kb": a_bytes // 1024,
                      "backgrounds_kb": b_bytes // 1024, "icons_kb": i_bytes // 1024}))


if __name__ == "__main__":
    main()
