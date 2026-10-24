"""The names the game uses, as data: every sheet the art must provide (art/<name>.png + art/<name>.json), its frame size, its anchor and its frame names.
gen/check_art.py checks the real art against it; gen/build.py packs it all."""
from __future__ import annotations

import sys
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent))
import gpt_jobs as _J  # noqa: E402

HEROES = list(_J.HEROES)
STAGES = ["calle", "fabrica", "torre"]

# name: (frame w, frame h, anchor, frames)
SHEETS: dict[str, tuple[int, int, tuple[int, int], list[str]]] = {}
for _id, _c in _J.CHARS.items():
    _frames = [f for sh in _c["sheets"] for f in sh[3]]
    SHEETS[_id] = (_c["frame"][0], _c["frame"][1], _c["anchor"], _frames)
    if _id in _J.HEROES:
        SHEETS[_id + "_b"] = (_c["frame"][0], _c["frame"][1], _c["anchor"], _frames)   # the second colours (same pixels, another palette in the same order)
for _id, _o in _J.OBJECTS.items():
    SHEETS[_id] = (_o["frame"][0], _o["frame"][1], _o["anchor"], [f for sh in _o["sheets"] for f in sh[3]])
SHEETS["pillars"] = (128, 320, (64, 319), STAGES)

# pictures that are not sprite rows: name: (w, h)
BACKGROUNDS = {}
for _z in STAGES:
    BACKGROUNDS[f"far_{_z}"] = (614, 230)
    for _k in "abc":
        BACKGROUNDS[f"near_{_z}_{_k}"] = (960, 320)
BACKGROUNDS["title"] = (480, 320)
BACKGROUNDS["select"] = (480, 320)
