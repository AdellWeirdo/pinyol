"""Isla Cerezo: the overworld, nine screens of 15 x 9 metatiles (3 x 3), drawn with brush strokes (world.Canvas) and then
touched up by hand. Cell coordinates in `thing(...)` are the area's (screen x * 15 + x, screen y * 9 + y).

        0 Bosque Norte      1 Monte y la Raíz     2 El Mirador
        0 El Huerto         1 La plaza del cerezo 2 Calle Este (tienda, alcaldía)
        0 Playa Oeste       1 Playa Sur           2 El embarcadero

The roads cross the edges of the screens at fixed places (the cells on both sides must match):
  A0|B0 y 5-6    B0|C0 y 5-6    A1|B1 y 4-5    B1|C1 y 4-5    A2|B2 y 6      B2|C2 y 6
  A0/A1 x 6-7    B0/B1 x 2-3 and 11-12         C0/C1 x 12-13  A1/A2 x 3-4    B1/B2 x 6-8    C1/C2 x 5-6
"""
from __future__ import annotations

from world import Area, Canvas, Connected, Family, Member, STAMPS, block

SW, SH = 15, 9

LEG = {
    "g": ["grass_a", "grass_b", "grass_c"], ",": ["grass_flowers_a", "grass_flowers_b"], "'": "grass_tufts", '"': "grass_clover",
    "w": "weeds", "b": "bush", "B": "bush_flowers", "r": ["rock_a", "rock_b"], "R": "rocks_c", "s": "stump", "l": "log_h",
    "L": "log_v", "m": "mushrooms", "p": "pebbles", "x": "dirt_loose", "o": "hole_dug", "&": "bush_secret", "%": "bush_dig",
    "d": Family("dirt", joins="c"), "t": "dirt_tilled", "T": "dirt_sprouts", "c": Family("cobble", joins="d"),
    "S": Family("sand", joins="~-"), "~": Family("water", joins="-"),
    "-": "shallow_a", "Y": "tree_small", "F": ["forest_a", "forest_b"], "h": "cabbage", "H": "cabbage_big", "k": ["flowerbed_a", "flowerbed_b"],
    "i": "signpost_cobble", "n": "barrel", "N": "crate", "z": "haystack", "q": "woodpile", "v": "flowerpot", "P": "scarecrow_post",
    "1": Member("S", "shell"), "2": Member("S", "starfish"), "3": Member("S", "driftwood"), "4": Member("S", "sand_rocks"),
    "5": Member("S", "crab_hole"), "6": Member("S", "sand_dug"), "U": "lamp_post",
    "M": ["mount_face_a", "mount_face_b", "mount_face_c"], "A": ["mount_crest_a", "mount_crest_b", "mount_crest_c"],
    "O": ["mount_base_a", "mount_base_b", "mount_base_c"], "C": ["cliff_a", "cliff_b"], "u": "stairs_up", "G": "fence_gate_h", "K": "chest_closed",
    "f": Connected({  # a fence joins its neighbours: N 1, E 2, S 4, W 8
        0: "fence_end_n", 1: "fence_end_s", 2: "fence_end_w", 4: "fence_end_n", 8: "fence_end_e", 3: "fence_sw", 6: "fence_nw",
        12: "fence_ne", 9: "fence_se", 5: "fence_v", 10: "fence_h", 7: "fence_tw", 11: "fence_ts", 13: "fence_te", 14: "fence_tn",
        15: "fence_cross",
    }),
}

# stamps: the big pieces, named as the artists name them
STAMPS.update({
    "casa_a": block("casa_a", 3, 3), "casa_b": block("casa_b", 3, 3), "tienda": block("tienda", 3, 4), "alcaldia": block("alcaldia", 3, 4),
    "treehouse": block("treehouse", 3, 3), "cherry_dead": block("cherry_dead", 4, 4), "cherry_bloom": block("cherry_bloom", 4, 4),
    "cavedoor": block("cavedoor", 3, 3), "caveopen": block("caveopen", 3, 3),
    "well": [["well_tl", "well_tr"], ["well_bl", "well_br"]],
    "tree_big": [["tree_big_tl", "tree_big_tr"], ["tree_big_bl", "tree_big_br"]],
    "tree2": [["tree2_tl", "tree2_tr"], ["tree2_bl", "tree2_br"]],
    "pine": [["pine_top"], ["pine_base"]],
    "rock_big": [["rock_big_tl", "rock_big_tr"], ["rock_big_bl", "rock_big_br"]],
    "bench": [["bench_l", "bench_r"]], "bench_cobble": [["bench_l_cobble", "bench_r_cobble"]], "boat": [["boat_l", "boat_r"]],
})

OW = Area("overworld", "overworld", 3, 3, LEG)
OW.notes.update({"music": "overworld", "name": "Isla Cerezo"})


def at(sx: int, sy: int, x: int, y: int) -> tuple[int, int]:
    """The area's cell of the cell x, y of screen sx, sy."""
    return sx * SW + x, sy * SH + y


def stamp(sx: int, sy: int, name: str, x: int, y: int) -> None:
    OW.stamp(name, *at(sx, sy, x, y))


def thing(sx: int, sy: int, kind: str, x: int, y: int, **kw) -> None:
    cx, cy = at(sx, sy, x, y)
    OW.thing(kind, cx, cy, **kw)


# ======================================================================== (0,0) Bosque Norte
c = Canvas("F", seed=11)
c.rect(1, 1, 13, 7, "g")                     # the clearing
c.rect(6, 3, 7, 8, "d").rect(8, 5, 14, 6, "d")  # the path from the garden, and on east to the mountain
c.rect(6, 8, 7, 8, "d")
for x, y in [(2, 2), (3, 4), (11, 2), (12, 4), (2, 6), (10, 7), (4, 8)]:
    c.put(x, y, "Y")
c.rect(10, 2, 11, 3, "b").put(1, 5, "s").put(12, 7, "m")
c.put(2, 7, "&")                              # a bush over a hole: the secret grotto
c.scatter(",", 7).scatter("w", 8, salt=2).scatter("'", 6, salt=4).scatter("m", 3, salt=6)
OW.screen(0, 0, c.rows())
stamp(0, 0, "treehouse", 5, 0)
stamp(0, 0, "pine", 1, 3)
stamp(0, 0, "pine", 13, 6)
stamp(0, 0, "tree_big", 8, 1)
thing(0, 0, "exit", 6, 2, to="casa_arbol", tx=7, ty=7, face="up", dir="up")
thing(0, 0, "exit", 2, 7, to="cueva_secreta", tx=7, ty=7, face="up")
thing(0, 0, "sign", 8, 7, text="cartel_bosque")
for x, y in [(4, 4), (10, 5), (3, 7), (11, 7)]:
    thing(0, 0, "enemy", x, y, id="pulgon", quest="bellota")

# ======================================================================== (1,0) Monte y la Raíz
c = Canvas("g", seed=12)
for x in range(15):
    c.put(x, 0, "A").put(x, 1, "M").put(x, 2, "O")
c.rect(2, 4, 12, 5, "d").rect(0, 5, 14, 6, "d").rect(2, 4, 3, 8, "d").rect(11, 4, 12, 8, "d")
c.rect(6, 3, 8, 3, "g")
c.scatter(",", 5).scatter("r", 5, salt=2).scatter("'", 6, salt=3).scatter("w", 4, salt=5)
c.put(0, 4, "r").put(14, 4, "r").put(4, 7, "R").put(9, 7, "r")
OW.screen(1, 0, c.rows())
stamp(1, 0, "cavedoor", 6, 0)
thing(1, 0, "socket", 6, 3, n=1)
thing(1, 0, "socket", 7, 3, n=2)
thing(1, 0, "socket", 8, 3, n=3)
OW.notes["seal"] = at(1, 0, 6, 0)
thing(1, 0, "exit", 7, 2, to="raiz", tx=7, ty=7 + 9 * 1, face="up", dir="up")
thing(1, 0, "sign", 4, 4, text="cartel_monte")
thing(1, 0, "enemy", 3, 3, id="cuervo")
thing(1, 0, "enemy", 11, 3, id="cuervo")

# ======================================================================== (2,0) El Mirador
c = Canvas("g", seed=13)
for x in range(15):
    c.put(x, 3, "C")
c.put(7, 3, "u")
c.rect(0, 5, 7, 6, "d").rect(4, 6, 5, 8, "d").rect(12, 6, 13, 8, "d").rect(7, 4, 7, 6, "d")
c.rect(0, 0, 14, 0, "F").rect(0, 1, 1, 2, "F").rect(13, 1, 14, 2, "F")
c.scatter(",", 8).scatter("r", 4, salt=3).scatter("'", 5, salt=4)
c.put(11, 1, "b").put(3, 1, "b").put(12, 7, "b").put(2, 1, "K")
c.rect(7, 1, 7, 2, "g")                       # the stair stays clear
c.put(9, 6, "%")                              # a bush that hides loose soil
OW.screen(2, 0, c.rows())
stamp(2, 0, "tree_big", 11, 0)
stamp(2, 0, "bench", 4, 1)
thing(2, 0, "sign", 6, 1, text="cartel_mirador")
thing(2, 0, "nest", 12, 2, flag="pit_nest")
thing(2, 0, "enemy", 9, 1, id="cuervo")
thing(2, 0, "enemy", 3, 2, id="cuervo")
thing(2, 0, "chest", 2, 1, item="pieza_corazon", flag="heart_mirador")
thing(2, 0, "buried", 9, 6, item="cherries", n=8, flag="buried_mirador")

# ======================================================================== (0,1) El Huerto
c = Canvas("g", seed=21)
c.rect(0, 0, 0, 8, "F")
c.rect(6, 0, 7, 5, "d").rect(2, 4, 14, 5, "d").rect(3, 4, 4, 8, "d")
c.frame(8, 0, 13, 3, "f").put(10, 3, "G")
c.rect(9, 1, 12, 2, "t")
for x, y in [(9, 1), (11, 1), (10, 2), (12, 2)]:
    c.put(x, y, "h")
c.put(11, 2, "H").put(10, 1, "T").put(12, 1, "T").put(9, 2, "T")
c.put(8, 6, "n").put(5, 2, "N").put(0, 2, "F")
c.scatter(",", 8).scatter("w", 6, salt=2).scatter("'", 5, salt=5)
c.put(12, 7, "z").put(13, 7, "z").put(1, 7, "b").put(2, 7, "b").put(7, 7, "s")
OW.screen(0, 1, c.rows())
stamp(0, 1, "casa_a", 1, 1)
stamp(0, 1, "well", 9, 6)
stamp(0, 1, "pine", 0, 6)
thing(0, 1, "exit", 2, 3, to="casa_yaya", tx=7, ty=7, face="up", dir="up")
thing(0, 1, "npc", 12, 4, id="espantajo", face="down")
thing(0, 1, "sign", 5, 6, text="cartel_huerto")
thing(0, 1, "buried", 11, 2, item="pinyol_dorado", flag="pit_garden")
thing(0, 1, "enemy", 5, 7, id="pulgon")

# ======================================================================== (1,1) La plaza del cerezo
c = Canvas("g", seed=22)
c.rect(4, 3, 10, 7, "c")
c.rect(2, 0, 3, 6, "d").rect(11, 0, 12, 6, "d").rect(0, 4, 3, 5, "d").rect(11, 4, 14, 5, "d").rect(6, 8, 8, 8, "d")
c.rect(6, 7, 8, 7, "c")
c.put(4, 3, "k").put(10, 3, "k").put(4, 7, "k").put(10, 7, "k").put(7, 6, "i")
c.scatter(",", 9).scatter("'", 6, salt=3)
OW.screen(1, 1, c.rows())
stamp(1, 1, "cherry_dead", 5, 0)
stamp(1, 1, "bench_cobble", 4, 5)
stamp(1, 1, "bench_cobble", 9, 5)
OW.notes["tree"] = at(1, 1, 5, 0)
OW.notes["crowd_y"] = at(1, 1, 0, 6)[1]
thing(1, 1, "plant", 6, 3, w=2, h=1)
thing(1, 1, "sign", 7, 6, text="cartel_plaza")
thing(1, 1, "npc", 6, 5, id="higuera", face="down")
thing(1, 1, "npc", 9, 6, id="mostaza", face="down", wander=2)
thing(1, 1, "npc", 3, 6, id="aldeano_a", face="right", wander=3)

# ======================================================================== (2,1) Calle Este
c = Canvas("g", seed=23)
c.rect(0, 4, 14, 6, "d").rect(12, 0, 13, 3, "d").rect(5, 7, 6, 8, "d").rect(0, 4, 1, 5, "d")
c.put(11, 7, "U").put(2, 7, "n").put(3, 7, "N").put(8, 7, "k").put(9, 7, "k")
c.scatter(",", 8).scatter("'", 5, salt=2).scatter("w", 3, salt=4)
OW.screen(2, 1, c.rows())
stamp(2, 1, "tienda", 1, 1)
stamp(2, 1, "alcaldia", 6, 1)
thing(2, 1, "exit", 2, 3, to="tienda", tx=7, ty=7, face="up", dir="up")
thing(2, 1, "exit", 7, 3, to="casa_higuera", tx=7, ty=7, face="up", dir="up")
thing(2, 1, "npc", 4, 5, id="aldeano_b", face="down", wander=3)
thing(2, 1, "npc", 11, 5, id="bellota", face="left")

# ======================================================================== (0,2) Playa Oeste
c = Canvas("g", seed=31)
c.rect(0, 1, 14, 8, "S")
c.rect(0, 5, 3, 8, "~").rect(0, 8, 14, 8, "~")
c.rect(3, 0, 4, 2, "d").rect(2, 2, 5, 3, "d")
c.scatter("1", 3, over="S").scatter("2", 2, over="S", salt=3).scatter("3", 2, over="S", salt=4).scatter("5", 2, over="S", salt=6)
c.put(9, 4, "6").put(8, 3, "4").put(12, 6, "4").put(13, 3, "b")
OW.screen(0, 2, c.rows())
thing(0, 2, "sign", 5, 3, text="cartel_playa")
thing(0, 2, "buried", 9, 4, item="pieza_corazon", flag="heart_beach")
thing(0, 2, "enemy", 7, 6, id="caracol", axis="h")
thing(0, 2, "enemy", 11, 4, id="caracol", axis="v")

# ======================================================================== (1,2) Playa Sur
c = Canvas("g", seed=32)
c.rect(0, 1, 14, 8, "S")
c.rect(0, 6, 14, 8, "~")
c.rect(6, 0, 8, 2, "d")
c.scatter("1", 3, over="S").scatter("2", 2, over="S", salt=3).scatter("3", 2, over="S", salt=4).scatter("5", 3, over="S", salt=6)
OW.screen(1, 2, c.rows())
stamp(1, 2, "boat", 2, 5)
thing(1, 2, "enemy", 4, 3, id="caracol", axis="h")
thing(1, 2, "enemy", 11, 3, id="pulgon")
OW.notes["waves"] = {"1,2": [96, 143], "0,2": [96, 143], "2,2": [96, 143]}

# ======================================================================== (2,2) El embarcadero
c = Canvas("g", seed=33)
c.rect(0, 1, 6, 5, "S").rect(0, 5, 14, 5, "S")
c.rect(7, 1, 14, 8, "~").rect(0, 6, 6, 8, "~")
c.rect(5, 0, 6, 1, "d")
OW.screen(2, 2, c.rows())
STAMPS.update({"plank": [["plank_h"]], "pier_end": [["plank_end_e"]], "post": [["pier_post"]]})
for x in range(4, 12):
    stamp(2, 2, "plank", x, 5)
stamp(2, 2, "pier_end", 12, 5)
stamp(2, 2, "post", 7, 4)
stamp(2, 2, "post", 7, 6)
stamp(2, 2, "post", 9, 4)
stamp(2, 2, "post", 9, 6)
thing(2, 2, "npc", 11, 5, id="sardina", face="right")
thing(2, 2, "sign", 3, 4, text="cartel_muelle")

AREAS = [OW]
