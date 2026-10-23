"""Sprites: the explorer (HERO), small effects (FX) and HUD icons (SMALL). 8x8 each, '.' = see-through.

The explorer: brown hat with a lit orange brim, peach face, red scarf with a pink fold, blue tunic, brown boots.
"""
from __future__ import annotations

import math

from art_util import flip_x, grid

HERO = {
    "idle_0": """
    ..4444..
    .444444.
    9999999a
    .f0ff0f.
    .e88888.
    .fcccc88
    ..cccc..
    ..4..4..
    """,
    "idle_1": """
    ........
    ..4444..
    .444444.
    9999999a
    .f0ff0f.
    .e88888.
    .fcccc88
    ..4..4..
    """,
    "down": """
    8.4444..
    e444444.
    8999999a
    8f0ff0f.
    .e8888..
    ..fccf..
    ..cccc..
    ...44...
    """,
    "up": """
    ..4444..
    .444444.
    a9999999
    .f4444f.
    .e88888.
    .fccc8c.
    ..cc8c..
    ..4..4..
    """,
    "right": """
    ...4444.
    ..444444
    ..999999
    .44ff0f.
    8e8888..
    8.cccf..
    ..ccc...
    .44..4..
    """,
    "bump": """
    ........
    ........
    ..4444..
    .444444.
    99999999
    f0ffff0f
    e8888888
    44cccc44
    """,
    "dead_0": """
    ..7777..
    .777777.
    77777777
    .777777.
    .777777.
    .777777.
    ..7777..
    ..7..7..
    """,
    "dead_1": """
    a.4444.a
    .444444.
    9999999a
    .f5ff5f.
    .e88888.
    .fcccc88
    ..cccc..
    a.4..4.a
    """,
    "dead_2": """
    ...a....
    a.....a.
    ..4444..
    .444444.
    9999999a
    .f5ff5f.
    e8888888
    fcccccc4
    """,
    "dead_3": """
    ........
    ........
    ........
    ...44...
    ..4444..
    .999999a
    e888ccc8
    fcccccc4
    """,
    "win_0": """
    ...7c...
    f..cc..f
    f.4444.f
    f999999a
    .f0ff0f.
    .e88888.
    ..cccc88
    ..4..4..
    """,
    "win_1": """
    ...c7...
    ...77...
    f.4444.f
    f999999a
    ff0ff0ff
    .e88888.
    ..cccc8.
    .4....4.
    """,
}


RING_LAST = """
..c..c..
........
c......c
........
........
c......c
........
..c..c..
"""


def ring(r: float, inner: str, outer: str) -> list[str]:
    out = []
    for y in range(8):
        row = ""
        for x in range(8):
            d = math.hypot(x - 3.5, y - 3.5)
            row += inner if abs(d - r) < 0.5 else (outer if abs(d - r) < 0.85 else ".")
        out.append(row)
    return out


FX = {
    "spark_0": """
    ........
    ........
    ........
    ...7....
    ..7a7...
    ...7....
    ........
    ........
    """,
    "spark_1": """
    ...a....
    ...7....
    ...7....
    a77777a.
    ...7....
    ...7....
    ...a....
    ........
    """,
    "spark_2": """
    .a...a..
    ........
    ...7....
    ..7.7...
    ...7....
    ........
    .a...a..
    ........
    """,
    "dust_0": """
    ........
    ........
    ........
    ........
    ...66...
    ..6776..
    ...66...
    ........
    """,
    "dust_1": """
    ........
    ........
    ..66.6..
    .67766..
    .677766.
    ..6665..
    ...55...
    ........
    """,
    "dust_2": """
    ........
    .5....5.
    ..6..6..
    ........
    6.....5.
    ..5..6..
    ........
    ...5....
    """,
}

SMALL = {
    "gem_icon": """
    ........
    .cccccc.
    c77cccdc
    7cccccdd
    .ccccdd.
    ..ccdd..
    ...cd...
    ........
    """,
    "key_icon": """
    ........
    .aa.....
    a00a....
    a00aaaaa
    .aa.9.9.
    ....9.9.
    ........
    ........
    """,
    "heart": """
    ........
    .88.88..
    87888e8.
    8888888.
    .88888..
    ..888...
    ...8....
    ........
    """,
    "skull": """
    ........
    .777777.
    77777776
    70077006
    77707766
    .676766.
    .6.6.6..
    ........
    """,
    "cursor": """
    .0......
    070.....
    0770....
    07770...
    077770..
    07700...
    00.70...
    ....0...
    """,
}


def register(ART) -> None:
    ART.sheet("HERO")
    order = ["idle_0", "idle_1", "up", "down", "left", "right", "bump", "dead_0", "dead_1", "dead_2", "dead_3", "win_0", "win_1"]
    pics = {k: grid(v) for k, v in HERO.items()}
    pics["left"] = flip_x(pics["right"])
    for name in order:
        ART.sprite("HERO", name, pics[name])
    ART.sheet("FX")
    for name, rows in FX.items():
        ART.sprite("FX", name, grid(rows))
    for i, (r, a, b) in enumerate([(1.0, "7", "c"), (2.0, "7", "c"), (3.0, "c", "d")]):
        ART.sprite("FX", f"ring_{i}", ring(r, a, b))
    ART.sprite("FX", "ring_3", grid(RING_LAST))
    ART.sheet("SMALL")
    for name, rows in SMALL.items():
        ART.sprite("SMALL", name, grid(rows))


