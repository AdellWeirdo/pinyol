"""Socavón's 8x8 blocks: X ink, . paper. Each block has two colours only, chosen per room by the game."""
from __future__ import annotations

from art_lib import cut, parse, shift_h, strip, transpose


def b(text: str, name: str) -> list[str]:
    return parse(text, 8, 8, name)


WALLS = {
    # brick with mortar: half-brick offset rows, a chip in each brick so a big wall is not flat
    "wall_a": """
XXX.XXXX
XXX.XXXX
XXX.XXXX
........
XXXXXXX.
XXXXXXX.
XXXXXXX.
........
""",
    # rough rock: lumps outlined by cracks that run on into the next block
    "wall_b": """
XXXXXXX.
XXXX.X..
XXX.XXXX
X..XXXXX
.XXXXXXX
XXXX.XXX
XXX.X.XX
XXXXXXX.
""",
    # riveted metal plate: seam right and bottom, two rivets, a sheen line
    "wall_c": """
........
XXXXXXXX
X.XXX.XX
XXXXXXXX
XXXXXXXX
XXXXXXXX
XXXXXXXX
XXXXXXXX
""",
    # big dressed stone: rounded corners, a worn speck, a crack
    "wall_d": """
XXXXXXX.
X...XXX.
X.XXXXX.
XXXXXXX.
XXXXX.X.
XXXX.XX.
XXXXXXX.
........
""",
}

FLOORS = {
    # wooden planks on a joist (brick rooms): board, grain, nail heads, a crosspiece under
    "floor_a": """
XXXXXXXX
X.XXX.X.
XXXXXXX.
........
........
........
........
........
""",
    # rock shelf: a lumpy lip that thins to drips
    "floor_b": """
XXXXXXXX
XXXXXXXX
X.XXXX.X
XX.XX.XX
.XX..XX.
..X...X.
........
........
""",
    # riveted girder (metal rooms): flanges and a zigzag truss
    "floor_c": """
XXXXXXXX
X..XX..X
.XX..XX.
XXXXXXXX
........
........
........
........
""",
    # stone slab: a thick dressed slab with a joint
    "floor_d": """
XXXXXXXX
XXXXXXX.
XX.XXXX.
XXXXXXX.
XXXXXXX.
........
........
........
""",
}

CRUMBLE = strip("""
XXXXXXXX|X.XXX.XX|..X...X.
XX.XXX.X|.X.X.X.X|X...X...
X.X.X.X.|X...X.X.|..X...X.
.X.X.X.X|..X...X.|........
X...X...|X...X...|.X...X..
..X...X.|........|........
........|.X...X..|X...X...
........|........|........
""", ["crumble_0", "crumble_1", "crumble_2"], 8, 8)

HAZARDS = strip("""
X..X..X.|.X..X..X|...X....|XXXXXXXX
.X.X.X..|..X.X.X.|...X....|XXXXXXXX
..XXX...|...XXX..|..XX...X|.XXX.XX.
XXX.XXX.|.XXX.XXX|..XXX..X|.XXX.XX.
..XXX...|...XXX..|X.XXX.XX|..X..X..
XX.X.XX.|XX.X.XX.|X.XXX.XX|..X..X..
.XXXXX..|.XXXXX..|XXXXXXXX|..X.....
...X....|...X....|XXXXXXXX|.....X..
""", ["plant_a", "plant_b", "spike", "stalac"], 8, 8)

KEY = b("""
........
.XX.....
X..X....
X..XXXXX
X..X.X.X
.XX..X..
........
........
""", "key")

PORTAL = parse("""
XXXXXXXXXXXXXXXX
X..............X
X.XXXXXXXXXXXX.X
X.X.XXX..XXX.X.X
X.XXXX.XX.XXXX.X
X.XXXX.XX.XXXX.X
X.XXX......XXX.X
X.XXX......XXX.X
X.XXX..XX..XXX.X
X.XXX..XX..XXX.X
X.XXX..XX..XXX.X
X.XXX......XXX.X
X.X.XXXXXXXX.X.X
X.XXXXXXXXXXXX.X
X..............X
XXXXXXXXXXXXXXXX
""", 16, 16, "portal")

PORTAL_OPEN = parse("""
...XXXXXXXXXX...
..XX...XX...XX..
.XX.X..XX..X.XX.
.X...X.XX.X...X.
XX....X..X....XX
X.XX........XX.X
X...XX....XX...X
X......XX......X
X......XX......X
X...XX....XX...X
X.XX........XX.X
X.....X..X.....X
X....X.XX.X....X
X...X..XX..X...X
X..X...XX...X..X
XXXXXXXXXXXXXXXX
""", 16, 16, "portal_open")

DECO = strip("""
........|......XX|...XX...|XXXXXXXX|........|........|...X....
XXXXXXXX|XXXXXXXX|...XX...|XXX..X..|........|..XXXX..|..XXX...
X..XXXXX|......XX|..XXXX..|XXX.X...|........|.XXXXXX.|..X.X.X.
XXXXX..X|XXXXXXXX|.X.XX.X.|X..X..X.|........|.X.XX.X.|X.X.X.XX
XXXXXXXX|XXXXXXXX|..XXXX..|X.X.X.X.|........|.XXXXXX.|XXX.XXX.
........|XXXXXXXX|X.XXXX.X|XX...X..|XXXXXXXX|..X.X...|X.XX.XX.
........|......XX|...XX...|X..XX...|.X...X..|X......X|XXXXXXXX
........|........|.X....X.|XXX.....|XXX.XXX.|XXXXXXXX|XXXXXXXX
""", ["deco_beam_h", "deco_pipe_h", "deco_lamp", "deco_web", "deco_rail", "deco_skull", "deco_crystal"], 8, 8)
# the upright beam and pipe are the lying ones turned a quarter
DECO["deco_beam_v"] = transpose(DECO["deco_beam_h"])
DECO["deco_pipe_v"] = transpose(DECO["deco_pipe_h"])


def conveyor(direction: int) -> dict[str, list[str]]:
    """A belt over rollers. The top run's marks move `direction`, the bottom run's the other way.
    Marks repeat every 8 px so the belt tiles; three frames step 3, 2, 3 px (always forward, less than half
    the period, so the eye reads one direction)."""
    top = ["XXXXXXXX", "X..XXXXX"]
    rollers = ["........", ".XX..XX.", "X..XX..X", ".XX..XX."]
    bottom = ["XXXX..XX"]
    out = {}
    tag = "r" if direction > 0 else "l"
    for i, s in enumerate((0, 3, 5)):
        t = shift_h(top, s * direction)
        bt = shift_h(bottom, -s * direction)
        out[f"conv_{tag}_{i}"] = t + rollers + bt + ["........"]
    return out


def register(ART) -> None:
    ART.tile("air", ["........"] * 8)
    for n, t in WALLS.items():
        ART.tile(n, b(t, n))
    for n, t in FLOORS.items():
        ART.tile(n, b(t, n))
    for n, r in CRUMBLE.items():
        ART.tile(n, r)
    for d in (1, -1):
        for n, r in conveyor(d).items():
            ART.tile(n, r)
    for n, r in HAZARDS.items():
        ART.tile(n, r)
    ART.tile("key", KEY)
    for big, pre in ((PORTAL, "portal"), (PORTAL_OPEN, "portal_open")):
        for suf, (x, y) in (("tl", (0, 0)), ("tr", (8, 0)), ("bl", (0, 8)), ("br", (8, 8))):
            ART.tile(f"{pre}_{suf}", cut(big, x, y))
    for n, r in DECO.items():
        ART.tile(n, r)
