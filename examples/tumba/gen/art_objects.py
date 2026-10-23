"""The things on the tomb floor: gems, spikes, the exit, mud, cracked blocks, teleporters, key, door, gates.

Every tile carries its own floor (floor_a) so it can stand alone; the object is drawn with '.' holes and laid over the floor.
"""
from __future__ import annotations

import math

from art_util import grid, over, put, rot90
from art_walls import FLOOR_A


def on_floor(text: str) -> list[str]:
    return over(FLOOR_A, grid(text))


# --- gem: a cut blue gem turning, with a pink/white sparkle -------------------------------------------------------------
COIN = [
    """
    ........
    ..cccc..
    .c77ccd.
    .7cccdd.
    ..ccdd..
    ...cd...
    ..0000..
    ........
    """,
    """
    ........
    ...cc...
    ..c7cd..
    ..7ccd..
    ..ccdd..
    ...cd...
    ...00...
    ........
    """,
    """
    ........
    ...77...
    ...7c...
    ...7c...
    ...7c...
    ...7c...
    ...00...
    ........
    """,
    """
    .....7..
    ...cc7e7
    ..cc7c7.
    ..cce7d.
    ..ccdd..
    ...cd...
    ...00...
    ........
    """,
]

# --- spikes: two rows of steel spikes, blood-red tips; frame 1 a gleam runs over them --------------------------------
SPIKE = [
    """
    ..8..8..
    ..7..6..
    .676665.
    .000000.
    ..8..8..
    ..6..6..
    .666665.
    .000000.
    """,
    """
    ..e..8..
    ..7..6..
    .777665.
    .000000.
    ..8..e..
    ..6..7..
    .666775.
    .000000.
    """,
]

# --- exit: a sandstone lid with a gem slot, then the open stairs with a glow from below -------------------------------
EXIT_CLOSED = grid("""
7aaaaaa9
a666666 5
a66c0d65
a6c00065
a66c0d65
a6dddd 65
95555555
00000000
""".replace(" ", ""))
EXIT_OPEN = [
    grid(f"""
    7aaaaaa9
    a000000 9
    a0ffff09
    a0444409
    a00{a}{a}009
    a0{a}{b}{b}{a}09
    99999999
    00000000
    """.replace(" ", ""))
    for a, b in [("9", "a"), ("a", "7"), ("9", "a")]
]
# frame 2 differs from 0 by a brighter step edge, so the glow breathes in three steps
EXIT_OPEN[2] = put(EXIT_OPEN[2], {(2, 2): "a", (5, 2): "a"})

# --- mud: a brown sucking pool with a bubble that rises and pops ------------------------------------------------------
MUD = [
    """
    .444444.
    44494444
    44444494
    4944f444
    444444f4
    44444444
    44449444
    .444444.
    """,
    """
    .444444.
    444f4444
    4444f494
    49444444
    44444494
    44f44444
    44444444
    .444444.
    """,
]

# --- a cracked sandstone block (breaks when hit) and the rubble it leaves ---------------------------------------------
CRACK = grid("""
7fff0ff9
ff9f0f94
f99009 94
f9909094
9f090994
44404444
45444544
00000000
""".replace(" ", ""))
RUBBLE = """
........
.9f.....
.44..f9.
.....44.
..f9....
.f944.9.
.44...4.
........
"""

# --- key: a gold key lying on the floor; frame 1 glints --------------------------------------------------------------
KEY = [
    """
    ........
    ........
    .aa.....
    a..aaaaa
    .99.9.9.
    ..0.0.0.
    ........
    ........
    """,
    """
    ........
    .7......
    7aa.....
    a..aa7aa
    .99.9.9.
    ..0.0.0.
    ........
    ........
    """,
]

# --- door: a heavy plank door with iron bands and a gold lock; open: just the stone jambs ----------------------------
DOOR = grid("""
7f4224f9
f4244249
f5655659
f42aa249
f42a0249
f5655659
f4244249
94444444
""")
DOOR_OPEN = """
f4000049
f2.....4
f4.....4
f2.....4
f4.....4
f2.....4
f4.....4
94.....4
"""

# --- one-way gate: a stone slab with a double chevron pointing the way you may pass --------------------------------
GATE_SLAB = grid("""
dddddddd
d5555550
d5555550
d5555550
d5555550
d5555550
d5555550
d0000000
""")
CHEVRON_UP = """
...77...
..7667..
.76..67.
.6....6.
...77...
..7667..
.76..67.
.6....6.
"""


def swirl(phase: int, ring: str, arm: str, core: str) -> list[str]:
    """A round pad with a two-armed spiral turning 60 degrees a frame (three frames make a half turn: a loop).
    (Two arms, not four: a four-armed pinwheel at 8 px reads as a swastika in some frames.)"""
    out = []
    for y in range(8):
        row = ""
        for x in range(8):
            dx, dy = x - 3.5, y - 3.5
            r = math.hypot(dx, dy)
            if r > 3.9:
                row += "1"
            elif r > 3.0:
                row += ring
            elif r < 1.0:
                row += core
            else:
                turn = (math.atan2(dy, dx) / (2 * math.pi) * 2 - r * 0.32 + phase / 3) % 1
                row += arm if turn < 0.45 else "0"
        out.append(row)
    return out


def register(ART) -> None:
    for i, c in enumerate(COIN):
        ART.tile(f"coin_{i}", on_floor(c))
    for i, s in enumerate(SPIKE):
        ART.tile(f"spike_{i}", on_floor(s))
    ART.tile("exit_closed", EXIT_CLOSED)
    for i, e in enumerate(EXIT_OPEN):
        ART.tile(f"exit_open_{i}", e)
    for i, m in enumerate(MUD):
        ART.tile(f"mud_{i}", on_floor(m))
    ART.tile("crack_0", CRACK)
    ART.tile("rubble", on_floor(RUBBLE))
    for i in range(3):
        ART.tile(f"tele_a_{i}", swirl(i, "c", "c", "7"))
        ART.tile(f"tele_b_{i}", swirl(i, "8", "e", "7"))
    for i, k in enumerate(KEY):
        ART.tile(f"key_{i}", on_floor(k))
    ART.tile("door", DOOR)
    ART.tile("door_open", on_floor(DOOR_OPEN))
    up = over(GATE_SLAB, grid(CHEVRON_UP))
    ART.tile("gate_u", up)
    arrow = grid(CHEVRON_UP)
    turns = {"gate_r": 1, "gate_d": 2, "gate_l": 3}
    for name, n in turns.items():
        a = arrow
        for _ in range(n):
            a = rot90(a)
        ART.tile(name, over(GATE_SLAB, a))
