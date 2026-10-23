"""Walls and floors of the tomb.

Walls are drawn by rule from the mask of open neighbours (N 1, E 2, S 4, W 8): the top of the wall is a dark purple mass with faint
brickwork; an open north edge gets a lit sand rim, an open west edge a softer lit rim, an open east edge a shaded side, and an open
south edge shows the carved sandstone face of the blocks (3/4 view, light from the top-left).
"""
from __future__ import annotations

from art_util import grid

# the colours of the wall, one place to tune them
TOP = "2"          # top surface of the wall mass
TOP_DK = "1"       # brick joints on the top surface
TOP_HI = "d"       # a few worn highlights on the top
RIM_N = "f"        # lit top rim (open to the north)
RIM_NW = "7"       # the brightest corner
RIM_W = "d"        # lit left rim (open to the west)
SIDE_E = "0"       # shaded right side (open to the east)
FACE_HI = "f"      # top line of the carved face (open to the south)
FACE = "9"         # the sandstone face
FACE_JOINT = "4"   # joints between the face blocks
FACE_LO = "4"      # the foot of the face, in shadow
FACE_E = "4"       # the face where it turns away east (shaded)

# the top surface inside a mass: plain (any texture repeats every 8 px and reads as a grid of dots at 1x)
TOP_TEXTURE = grid("""
22222222
22222222
22222222
22222222
22222222
22222222
22222222
22222222
""")


def wall(mask: int) -> list[str]:
    n, e, s, w = bool(mask & 1), bool(mask & 2), bool(mask & 4), bool(mask & 8)
    px = [list(r) for r in TOP_TEXTURE]
    face_top = 5 if s else 8           # rows face_top.. are the south face
    if s:
        for x in range(8):
            px[4][x] = TOP_DK          # the brick course under the rim: a dark lip before the face
            px[5][x] = FACE_HI
            px[6][x] = FACE
            px[7][x] = FACE_LO
        px[6][3] = FACE_JOINT
        px[5][3] = FACE
    if n:
        for x in range(8):
            px[0][x] = RIM_N
        for x in range(8):
            if px[1][x] == TOP_DK:
                px[1][x] = TOP
    if w:
        for y in range(face_top):
            px[y][0] = RIM_W if y else (RIM_NW if n else RIM_W)
        if s:
            px[5][0], px[6][0], px[7][0] = RIM_NW, FACE_HI, FACE
    if e:
        for y in range(face_top):
            px[y][7] = SIDE_E
        if n:
            px[0][7] = FACE  # the rim turns down into shade
        if s:
            px[5][7], px[6][7], px[7][7] = FACE, FACE_E, "0"
    if n and w:
        px[0][0] = RIM_NW
    if n and not w:
        px[0][0] = RIM_N
    return ["".join(r) for r in px]


FLOOR_A = grid("""
11111111
11111111
11111111
11111111
11111111
11111111
11111111
11111111
""")
FLOOR_B = grid("""
11111111
11111111
11101111
11110111
11110011
11111101
11111111
11111111
""")
FLOOR_C = grid("""
11111111
11111111
11111111
11151111
11101111
11111151
11111101
11111111
""")
FLOOR_D = grid("""
11111111
11111111
11121111
11211211
11121111
11111111
11111111
11111111
""")
SHADE_A = grid("""
00000000
01010101
11111111
11111111
11111111
11111111
11111111
11111111
""")
SHADE_B = grid("""
00000000
01010101
11111111
11101111
11110111
11111111
11111111
11111111
""")
START = grid("""
11111111
11dddd11
1d1111d1
1d1dd1d1
1d1dd1d1
1d1111d1
11dddd11
11111111
""")


def register(ART) -> None:
    for m in range(16):
        ART.tile(f"wall_m{m}", wall(m))
    for name, rows in [("floor_a", FLOOR_A), ("floor_b", FLOOR_B), ("floor_c", FLOOR_C), ("floor_d", FLOOR_D),
                       ("floor_shade_a", SHADE_A), ("floor_shade_b", SHADE_B), ("start", START)]:
        ART.tile(name, rows)
