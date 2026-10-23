"""The names the game uses, as data: every sheet the art must provide (art/<name>.png + art/<name>.json), its frame size, its anchor and its frame names, written from
the briefs. gen/check_art.py checks the real art against it; gen/stub_art.py draws stand-ins from it so the engine can run before the art exists."""
from __future__ import annotations

import sys
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent))

CHEFS = ["estrella", "espuma", "pinche", "arrocero", "brioche", "crianza"]


def seq(prefix: str, n: int) -> list[str]:
    return [f"{prefix}_{i}" for i in range(n)]


def cat(*groups) -> list[str]:
    out: list[str] = []
    for g in groups:
        out += g if isinstance(g, list) else [g]
    return out


import gpt_jobs as _J  # noqa: E402

CHEF_FRAMES = [f for _, (_, _, names, _, _) in _J.SHEETS.items() for f in names]   # the frames of a cook, in the order of the sheets they were made in (gen/gpt_jobs.py)

# name: (frame w, frame h, anchor, frames)
SHEETS: dict[str, tuple[int, int, tuple[int, int], list[str]]] = {}
for c in CHEFS:
    SHEETS[f"chef_{c}"] = (_J.CHEF_FRAME[0], _J.CHEF_FRAME[1], _J.CHEF_ANCHOR, CHEF_FRAMES)

for _id, _e in _J.ENEMIES.items():
    SHEETS[_id] = (_e["frame"][0], _e["frame"][1], _e["anchor"], [f for sh in _e["sheets"] for f in sh[3]])
SHEETS["tractor"] = (_J.TRACTOR["frame"][0], _J.TRACTOR["frame"][1], _J.TRACTOR["anchor"], [f for sh in _J.TRACTOR["sheets"] for f in sh[3]])
for _id, _o in _J.OBJECTS.items():
    SHEETS[_id] = (_o["frame"][0], _o["frame"][1], _o["anchor"], [f for sh in _o["sheets"] for f in sh[3]])
FOODS = ["jamon", "cheese", "paella", "tortilla", "melon", "sardine", "orange", "bread", "olive_can", "wine_skin", "churro", "ensaimada"]
SHEETS["boss_body"] = (384, 320, (192, 300), cat(seq("idle", 6), seq("hurt", 2), seq("damaged", 3), seq("dead", 4)))
SHEETS["boss_head"] = (192, 160, (150, 120), cat(seq("idle", 4), seq("open", 4), seq("fire", 3), seq("hurt", 3), seq("laugh", 4), seq("dead", 4)))
SHEETS["boss_wing"] = (256, 192, (200, 40), cat(seq("rest", 4), seq("open", 4), seq("fire", 4), seq("hurt", 2), seq("broken", 2)))
SHEETS["boss_leg"] = (160, 192, (80, 20), cat(["stand"], seq("step", 8), seq("stomp", 4), seq("broken", 2)))
SHEETS["boss_pot"] = (224, 192, (112, 176), cat(["closed"], seq("opening", 6), seq("open", 4), seq("hit", 3), seq("cracked", 3), seq("destroyed", 4)))
SHEETS["boss_fx"] = (128, 128, (64, 64), cat(seq("charge", 6), seq("beam", 4), seq("spark", 4), seq("bolt", 4)))

# pictures that are not sprite rows: name: (w, h)
BACKGROUNDS = {}
for z in ("puerto", "calle", "playa"):
    BACKGROUNDS[f"far_{z}"] = (614, None)
    BACKGROUNDS[f"near_{z}_a"] = (960, 320)
    BACKGROUNDS[f"near_{z}_b"] = (960, 320)
BACKGROUNDS["arena_playa"] = (480, 320)
BACKGROUNDS["title"] = (480, 320)
BACKGROUNDS["select"] = (480, 320)
