"""Decor: a skull on the floor, a wall torch (3 frames) and the carved hieroglyph column pieces for the margins."""
from __future__ import annotations

from art_util import grid, over
from art_walls import FLOOR_A, wall as wall_tile

SKULL = """
........
..7777..
.777776.
.700706.
.777766.
..6766..
..0606..
...000..
"""

TORCH = [
    """
    ....a...
    ...a9...
    ..a7a9..
    ..9779..
    ...88...
    ..4444..
    ...44...
    ...55...
    """,
    """
    ...a....
    ...9a...
    ..a77a..
    ..9a79..
    ...88...
    ..4444..
    ...44...
    ...55...
    """,
    """
    ........
    ....a...
    ..a9a...
    ..97a9..
    ...88...
    ..4444..
    ...44...
    ...55...
    """,
]
# warm light the flame throws on the stone around it (sparse dots, so it reads as glow and not as a shape)
TORCH_GLOW = """
.4....4.
........
4......4
........
.4....4.
........
........
........
"""

# the column pieces: a 6-px carving between a lit left edge (f) and a shaded right edge (4); the last row is the joint
GLYPHS = {
    "border_a": ["999999", "944449", "999999", "940049", "994499", "994999", "999999"],   # eye
    "border_b": ["994499", "949949", "994499", "944449", "994499", "994499", "999999"],   # ankh
    "border_c": ["999999", "949949", "494494", "999999", "949949", "494494", "999999"],   # water
    "border_d": ["999999", "944999", "994999", "944449", "944444", "949499", "999999"],   # bird
}


def column(rows: list[str]) -> list[str]:
    return ["f" + r + "4" for r in rows] + ["44444442"]


def register(ART) -> None:
    ART.tile("deco_skull", over(FLOOR_A, grid(SKULL)))
    wall = over(wall_tile(4), grid(TORCH_GLOW))  # mounted on a wall that faces the room (south face open)
    for i, t in enumerate(TORCH):
        ART.tile(f"deco_torch_{i}", over(wall, grid(t)))
    for name, rows in GLYPHS.items():
        ART.tile(name, column(rows))
