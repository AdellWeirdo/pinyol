# /// script
# requires-python = ">=3.10"
# dependencies = ["pillow>=10.1", "numpy>=1.26"]
# ///
"""Generated Game Boy sheets (gen/*.png) to the game's sets (gb/<set>/<set>_N.png) and rooms (gb/rooms/bg_*.png).

    uv run design/build_gb.py

Each sheet goes back onto its pixel grid (pixelize.py), is cut into its frames and each frame goes to the set the
table below names. A sheet of one animation is one set; a sheet of stills is one set per still. art.py uses
gb/<set> in place of the board's converted drawing whenever it is there.
"""
from __future__ import annotations

import shutil
import sys
from pathlib import Path

from PIL import Image

HERE = Path(__file__).resolve().parent
sys.path.insert(0, str(HERE))
import pixelize  # noqa: E402

GEN, GB = HERE / "gen", HERE / "gb"
ADULT_H = 58     # a sitting grown Audrey, world px (the style sheet's)
PUPPY_H = 30     # a sitting puppy: half of her (the owner: smaller, at the grown cat's scale)

# sheet -> (frames, what each frame is): a list of set names (None: drop it), or one set name for all of them
STILLS = {
    "style_adult": (5, ["idle", "happy", "sleep", None, "sick"]),
    "still_a": (5, ["happy_love", "happy_playful", "happy_excited", "orgullosa", "idle_sad"]),
    "still_b": (5, ["idle_grumpy", "idle_curious", "idle_bored", "idle_lonely", "tired"]),
    "still_c": (4, ["hungry", "critical", "bola", "cojin"]),
    "sick": (4, ["sick_resfriado", "sick_indigestion", "sick_estres", "sick_agotamiento"]),
    "props": (4, ["caja", "pluma", "varita", "cepillo"]),
    "cachorro": (5, ["cachorro", "cachorro_happy", "cachorro_sleep", "cachorro_hungry", "cachorro_sick"]),
}
ANIMS = {  # one animation per sheet: frames
    "ear_twitch": 3, "tail_flick": 3, "yawn": 3, "happy_wiggle": 3, "vuelta": 4, "come": 4, "mimos": 3,
    "enamorada": 4, "negacion": 3, "molesta": 3, "juzgando": 3, "furiosa": 3, "sacude": 4, "despierta": 4,
    "saluda": 3, "pedir": 3, "celebra": 4, "curada": 4, "se_duerme": 3, "encontrada": 3, "salto": 5,
    "salto_falla": 3, "lo_tengo": 3, "caza_laser": 5, "caja_audrey": 5, "nudos": 6, "patas": 4,
}
SITTING = {"style_adult": 0, "still_a": 0, "still_b": 0, "still_c": 0, "ear_twitch": 0, "tail_flick": 0,
           "yawn": 0, "happy_wiggle": 0, "mimos": 0, "enamorada": 0, "negacion": 0, "molesta": 0, "juzgando": 0,
           "saluda": 0, "celebra": 3, "encontrada": 2, "lo_tengo": 0, "cachorro": 0, "pedir": 2, "furiosa": 0,
           "curada": 2, "despierta": 3, "se_duerme": 0, "sick": 0, "props": 0}  # a frame of her sitting
ROOMS = ("living", "kitchen", "rasca", "studio", "wc")


def frames_of(sheet: str, n: int, target_h: int | None) -> list[Image.Image]:
    """The sheet's n frames on its pixel grid; with a sitting frame named, the grid is scaled so it is target_h."""
    src = Image.open(GEN / f"{sheet}.png") if (GEN / f"{sheet}.png").exists() else Image.open(HERE / f"{sheet}.png")
    img = pixelize.pixelize(src, None, False)
    frames = pixelize.split(img, n)
    if target_h and sheet in SITTING:
        h = frames[SITTING[sheet]].getbbox()
        h = h[3] - h[1]
        if abs(h - target_h) > 3:  # drawn bigger or smaller: sample its grid again at the size it should be
            p = pixelize.LAST_P * h / target_h
            img = pixelize.pixelize(src, p, False)
            frames = pixelize.split(img, n)
    return frames


def write_set(name: str, frames: list[Image.Image]) -> None:
    d = GB / name
    if d.exists():
        shutil.rmtree(d)
    d.mkdir(parents=True)
    for i, f in enumerate(frames):
        f.save(d / f"{name}_{i}.png")


BOX_H = 40  # the Trile's closed box, world px: the props are drawn to its scale...
PROP_H = {"pluma": 28, "varita": 56, "cepillo": 16}  # ...and these, drawn too big beside it, to their own height


def to_height(im: Image.Image, h: int) -> Image.Image:
    im = im.crop(im.getbbox())
    return im.resize((max(1, round(im.width * h / im.height)), h), Image.NEAREST)


def stills(sheet: str, n: int, names: list) -> None:
    target = PUPPY_H if sheet == "cachorro" else BOX_H if sheet == "props" else ADULT_H
    for f, name in zip(frames_of(sheet, n, target), names):
        if name in PROP_H:
            write_set(name, [to_height(f, PROP_H[name])])
        elif name:
            write_set(name, [f.crop(f.getbbox()) if name == "caja" else f])


def main() -> None:
    GB.mkdir(exist_ok=True)
    for sheet, (n, names) in STILLS.items():
        if (GEN / f"{sheet}.png").exists() or (HERE / f"{sheet}.png").exists():
            stills(sheet, n, names)
            print("stills", sheet)
    for sheet, n in ANIMS.items():
        if not (GEN / f"{sheet}.png").exists():
            continue
        frames = frames_of(sheet, n, ADULT_H if sheet in SITTING else None)
        if sheet == "patas":  # her paws, first person: resting, reaching left and right, pulling
            write_set("patas", [frames[0], frames[0]])
            write_set("patas_alcanza", [frames[1], frames[2]])
            write_set("patas_tira", [frames[3], frames[3]])
        elif sheet == "nudos":
            write_set("nudos", frames)
            write_set("nudo_libre", [frames[-1]])
        else:
            write_set(sheet, frames)
        print("anim", sheet, len(frames))
    rooms = GB / "rooms"
    rooms.mkdir(exist_ok=True)
    for r in ROOMS:
        src = GEN / f"room_{r}.png" if r != "living" else HERE / "style_living.png"
        if src.exists():
            room = pixelize.pixelize(Image.open(src), None, True).resize((240, 160), Image.NEAREST)
            room.convert("RGB").save(rooms / f"bg_{r}.png")
            print("room", r)


if __name__ == "__main__":
    main()
