"""A small area to develop the game's code on, with the placeholder art (build.py --dev)."""
from __future__ import annotations

from world import Area

LEG = {"g": ["grass_a", "grass_b", "grass_c"], ",": "grass_flowers_a", "b": "bush", "r": "rock_a", "w": ["water_a"],
       "t": "tree_trunk", "C": "chest_closed", "x": "dirt_loose", "T": "tree_top", "d": "dirt_a", "s": "sand_a", "h": "roof_m", "D": "door"}

DEV = Area("overworld", "overworld", 2, 2, LEG)
DEV.screen(0, 0, [
    "ggggggggggggggg",
    "gg,gggbbgggggTg",
    "ggggggbbggggggg",
    "gggggggggggggtg",
    "ggg,ggggggggggg",
    "gggggggrgggggCg",
    "ggxgggggggggggg",
    "gggg,ggggggg,gg",
    "ggggggggggggggg",
])
DEV.screen(1, 0, [
    "ggggggggggggggg",
    "gggggghhhggggbg",
    "gggggghDhggggbg",
    "ggggggdddgggggg",
    "gggggggdggggggg",
    "gwwwwgggggggggg",
    "gwwwwgggggg,ggg",
    "gwwwwggggggggbb",
    "ggggggggggggggg",
])
DEV.screen(0, 1, [
    "ggggggggggggggg",
    "gggg,gggggggggg",
    "ggggggggbbggggg",
    "gggggggggggggrg",
    "ggggggggggggggg",
    "ggg,ggggggggggg",
    "ggggggggggggggg",
    "gggggbgggggggbg",
    "ggggggggggggggg",
])
DEV.screen(1, 1, [
    "ggggggggggggggg",
    "gggggggggggggbg",
    "ggggbggggggggbg",
    "ggggggggggggggg",
    "gggggggrggggggg",
    "ggggggggggggggg",
    "ggg,gggggg,gggg",
    "ggggggggggggggg",
    "ggggggggggggggg",
])
DEV.thing("spawn", 7, 5, face="down")
DEV.thing("npc", 9, 3, id="yaya", face="left")
DEV.thing("sign", 11, 2, text="cartel_plaza")
DEV.thing("chest", 13, 5, item="tirachinas", flag="chest_tirachinas")
DEV.thing("buried", 2, 6, item="cherries", n=6, flag="buried_a")
DEV.thing("enemy", 10, 6, id="pulgon")
DEV.thing("enemy", 12, 6, id="pulgon")
DEV.thing("enemy", 3, 3, id="pulgon")
DEV.notes["dark"] = {"1,1": True}
DEV.notes["waves"] = {"0,1": [96, 143]}
AREAS = [DEV]
