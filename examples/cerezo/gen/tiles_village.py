"""The village of Isla Cerezo outdoors (tileset "overworld"): houses, fences, props, the treehouse, the pier.

Buildings are drawn whole and cut into cells `<name>_<row>_<col>`: casa_a (3x3, Yaya's cottage: hipped roof of red
barrel tiles, whitewash, shutters, geraniums), casa_b (3x3, thatch loaf, boards, round window, Z-braced door),
tienda (4x3, fish-scale roof, striped awning, cherry sign, barrels, apple crate), alcaldia (4x3, two floors of
ashlar; over the door cell a bay with the double door and step, the mayor's balcony, a clock and the flag).
Every building cell is solid but `<name>_2_1`, the door. Banks: roofs 5, walls 4 (the alcaldia's stone 6).
Letters inside the drawings are textures (Tex), so a roof tile or a plank is drawn the same everywhere.

Fences (bank 4, solid): a waist-high picket fence; a post stands on each east-west cell boundary, so a gate always
has a post each side. Pieces are named by WHERE they sit in a pen, like corners and ends: fence_nw joins E+S,
fence_end_n is the north end of a run (joins S); the T's: fence_tn joins E+S+W (the T on a north side), fence_ts
N+E+W, fence_te N+S+W, fence_tw N+E+S. fence_cross joins all four (extra). fence_gate_v puts its south post on
the front layer so the hero walks between the posts.

Props stand on the terrain's grass (tufts cut by a prop are left out), with the terrain's tone-2 contact shadow.
cabbage / cabbage_big stand on dirt_tilled (what cutting them leaves). lamp_post: head on the front layer.
The treehouse: rows 0-1 canopy and cabin on the front layer over plain grass (walkable), row 2 the trunk; the
ladder cell treehouse_2_1 is the door. The pier pieces lie over the terrain's deep water; the boat, the net, the
fish crate and the rope coil lie on sand (the map puts the boat on the beach).
The ground pictures come from tiles_terrain when it imports (copies otherwise), so a change there follows here.
"""
from __future__ import annotations

import sys
from collections import Counter
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent))
import gbart as g  # noqa: E402
from gbart import ART  # noqa: E402

SET = "overworld"


# ======================================================================== drawing helpers
def rows_of(text: str) -> list[str]:
    """Text rows, indented freely."""
    return [ln.strip() for ln in text.strip().split("\n")]


GROUND, SHADE, HALF = -1, -2, -3  # in a drawing: the ground shows here / a shadow on the ground / a dithered shadow


class Tex:
    """A texture that repeats (roof tiles, planks, stone): a small picture, anchored at pixel ox, oy of the drawing.
    `bend(x)`, if given, lowers the texture by that many pixels at column x (courses of thatch that follow a dome)."""

    def __init__(self, text: str, ox: int = 0, oy: int = 0, bend=None):
        self.p = g.pic(rows_of(text))
        self.ox, self.oy, self.bend = ox, oy, bend

    def at(self, x: int, y: int) -> int:
        dy = self.bend(x) if self.bend else 0
        return self.p[(y - self.oy - dy) % len(self.p)][(x - self.ox) % len(self.p[0])]


def dome(centre: float, half: float, depth: int):
    """A bend for Tex: 0 at `centre`, `depth` pixels at `half` pixels from it (a parabola)."""
    return lambda x: round(depth * min(1.0, ((x - centre) / half) ** 2))


def draw(text: str, tex: dict | None = None, w: int | None = None, h: int | None = None) -> g.Pic:
    """Rows of characters to a drawing: 0-3 tones; '.' the ground (or nothing, in a front picture); 's' a shadow on the
    ground and 'z' a dithered one; any other letter the pixel of that texture (`tex[letter]`) at this place."""
    rows = rows_of(text)
    out = []
    for y, r in enumerate(rows):
        row = []
        for x, ch in enumerate(r):
            if ch in "0123":
                row.append(int(ch))
            elif ch == ".":
                row.append(GROUND)
            elif ch == "s":
                row.append(SHADE)
            elif ch == "z":
                row.append(HALF)
            else:
                row.append(tex[ch].at(x, y))
        out.append(row)
    if w is not None and any(len(r) != w for r in out):
        bad = [(i, len(r)) for i, r in enumerate(out) if len(r) != w]
        raise ValueError(f"rows of the wrong width (want {w}): {bad}")
    if h is not None and len(out) != h:
        raise ValueError(f"{len(out)} rows, not {h}")
    return out


def front_of(p: g.Pic) -> g.Pic:
    """A drawing as a front picture: whatever is not drawn is see-through."""
    return [[v if v >= 0 else -1 for v in row] for row in p]


def base_tone(p: g.Pic) -> int:
    return Counter(v for row in p for v in row).most_common(1)[0][0]


def _details(p: g.Pic, base: int) -> list[list[tuple[int, int]]]:
    """Groups of touching (8-way) pixels that are not the base tone: the tufts of grass, the waves of the water."""
    h, w = len(p), len(p[0])
    seen, out = set(), []
    for y in range(h):
        for x in range(w):
            if p[y][x] != base and (x, y) not in seen:
                stack, comp = [(x, y)], []
                seen.add((x, y))
                while stack:
                    cx, cy = stack.pop()
                    comp.append((cx, cy))
                    for dx in (-1, 0, 1):
                        for dy in (-1, 0, 1):
                            nx, ny = cx + dx, cy + dy
                            if 0 <= nx < w and 0 <= ny < h and (nx, ny) not in seen and p[ny][nx] != base:
                                seen.add((nx, ny))
                                stack.append((nx, ny))
                out.append(comp)
    return out


def tiled(t: g.Pic, w: int, h: int) -> g.Pic:
    return [[t[y % len(t)][x % len(t[0])] for x in range(w)] for y in range(h)]


def on(ground: g.Pic, obj: g.Pic, shade: int | None = None, whole: bool = False) -> g.Pic:
    """A drawing laid on a ground tile (repeated to its size). Where the drawing leaves the ground, the ground shows,
    but only the ground's details (a tuft of grass, a wave) that lie wholly in the free space and do not touch the
    drawing: no half tufts cut by a wall. Shadows take `shade` (default: tone 2 on a light ground, 3 on a dark one)."""
    h, w = len(obj), len(obj[0])
    gr = tiled(ground, w, h)
    base = base_tone(gr)
    if shade is None:
        shade = 2 if base < 2 else 3
    free = {(x, y) for y in range(h) for x in range(w) if obj[y][x] == GROUND}
    near_obj = {(x + dx, y + dy) for y in range(h) for x in range(w) if obj[y][x] != GROUND
                for dx in (-1, 0, 1) for dy in (-1, 0, 1)}
    keep = set()
    for comp in _details(gr, base):
        if all(c in free and c not in near_obj for c in comp):
            keep.update(comp)
    out = []
    for y in range(h):
        row = []
        for x in range(w):
            v = obj[y][x]
            if v == GROUND:
                row.append(gr[y][x] if whole or (x, y) in keep else base)
            elif v == SHADE:
                row.append(shade)
            elif v == HALF:
                row.append(shade if (x + y) % 2 == 0 else base)
            else:
                row.append(v)
        out.append(row)
    return out


def cells(p: g.Pic, cols: int, rows: int) -> dict[tuple[int, int], g.Pic]:
    """A big picture cut into 16x16 cells: {(row, col): picture}."""
    return {(r, c): g.crop(p, c * 16, r * 16, 16, 16) for r in range(rows) for c in range(cols)}


# ======================================================================== the ground under the pieces
# The terrain module's own tiles when it can be read, so that a change to the grass or the sea is a change here too;
# copies of its first drafts if not.
GRASS = draw("""
    0000000000000000
    0000000000000000
    0000000000000000
    0002020000000000
    0020202000000000
    0000000000000000
    0000000000000000
    0000000000000000
    0000000000000000
    0000000000000000
    0000000000020000
    0000000000202000
    0000000000000000
    0000000000000000
    0000000000000000
    0000000000000000
""")
SAND = draw("""
    0000000000000000
    0001000000000100
    0000000200000000
    0000000000000000
    0100000000010000
    0000001000000000
    0000000000000020
    0000000000000000
    0000020000000000
    0000000000010000
    0100000000000000
    0000000010000000
    0000000000000000
    0000100000000200
    0000000000000000
    0000000000000000
""")
WATER = draw("""
    2222222222222222
    2222222222222222
    2222111222222222
    2221222112222222
    2222222222222222
    2222222222222222
    2222222222222222
    2222222222111222
    2222222222222112
    2222222222222222
    2222222222222222
    2211122222222222
    2122211222222222
    2222222222222222
    2222222222222222
    2222222222222222
""")
COBBLE = None
try:
    import tiles_terrain as _terrain
    GRASS = getattr(_terrain, "GRASS_A", GRASS)
    SAND = getattr(_terrain, "SAND_A", SAND)
    WATER = getattr(_terrain, "WATER_A", WATER)
    COBBLE = getattr(_terrain, "COBBLE_A", None)
except Exception as e:  # the terrain module is being edited by its artist: carry on with the copies
    print(f"tiles_village: tiles_terrain not readable ({e}); using copies of its grass, sand and water")


def reg(name: str, ground: g.Pic, front: g.Pic | None = None, flags: tuple = (), bank: int = 0,
        front_bank: int | None = None) -> None:
    ART.meta(SET, name, ground, front=front, flags=flags, bank=bank, front_bank=front_bank)


def layer(*parts: g.Pic) -> g.Pic:
    """Drawings laid one over another (later ones in front); '.' (the ground) lets the ones behind show."""
    h, w = len(parts[0]), len(parts[0][0])
    out = [[GROUND] * w for _ in range(h)]
    for p in parts:
        for y in range(h):
            for x in range(w):
                if p[y][x] != GROUND:
                    out[y][x] = p[y][x]
    return out


# ======================================================================== fences
# A waist-high picket fence (the hero is 15 px, the fence 10). Along an east-west run every cell has a pointed picket
# at its middle (x 6..10) and a flat-capped post standing on its boundary with the next cell (x 14..15 of this one,
# 0..2 of that one): so a gate, which is a cell with nothing in its middle, always has a real post on each side. Two
# rails show between the uprights. A north-south run cannot show its pickets edge-on (they would be a 1 px line), so
# it is drawn as one picket a cell joined by its two rails seen from above. Corners, T's and ends put a capped post
# in the middle of the cell. Weathered: nail heads where the rails are, a chipped tip, a knot.
_E16 = "................"
F_RAIL_W = draw("\n".join([_E16] * 6 + ["222222.........."] + ["333333.........."] + [_E16] * 2
                          + ["222222.........."] + ["333333.........."] + [_E16] * 4))
F_RAIL_E = draw("\n".join([_E16] * 6 + ["..........222222"] + ["..........333333"] + [_E16] * 2
                          + ["..........222222"] + ["..........333333"] + [_E16] * 4))
F_POST_W = draw("""
    ................
    ................
    ................
    333.............
    013.............
    223.............
    123.............
    223.............
    123.............
    123.............
    223.............
    123.............
    123.............
    333.............
    sss.............
    ................
""")
F_POST_E = draw("""
    ................
    ................
    ................
    ..............33
    ..............30
    ..............32
    ..............30
    ..............30
    ..............30
    ..............30
    ..............30
    ..............30
    ..............30
    ..............33
    ...............s
    ................
""")
F_PICKET = draw("""
    ................
    ................
    ................
    ................
    ........3.......
    .......303......
    ......30123.....
    ......30223.....
    ......30123.....
    ......30123.....
    ......30123.....
    ......30223.....
    ......30123.....
    ......33333.....
    .......sssss....
    ................
""")
F_PICKET_CHIPPED = draw("""
    ................
    ................
    ................
    ................
    ................
    .......33.3.....
    ......30113.....
    ......30223.....
    ......30123.....
    ......30123.....
    ......30123.....
    ......30223.....
    ......30123.....
    ......33333.....
    .......sssss....
    ................
""")
F_CPOST = draw("""
    ................
    ................
    ................
    ......33333.....
    ......30013.....
    ......32223.....
    ......30123.....
    ......30223.....
    ......30123.....
    ......30133.....
    ......30123.....
    ......30223.....
    ......30123.....
    ......33333.....
    .......sssss....
    ................
""")
F_RAILS_N = draw("\n".join(["......23.23....."] * 4 + [_E16] * 12))
F_RAILS_S = draw("\n".join([_E16] * 14 + ["......23.23s...."] * 2))

FENCES = {  # name: (north, east, south, west) neighbours joined
    "fence_h": (0, 1, 0, 1), "fence_v": (1, 0, 1, 0),
    "fence_nw": (0, 1, 1, 0), "fence_ne": (0, 0, 1, 1), "fence_sw": (1, 1, 0, 0), "fence_se": (1, 0, 0, 1),
    "fence_tn": (0, 1, 1, 1), "fence_ts": (1, 1, 0, 1), "fence_te": (1, 0, 1, 1), "fence_tw": (1, 1, 1, 0),
    "fence_end_n": (0, 0, 1, 0), "fence_end_e": (0, 0, 0, 1), "fence_end_s": (1, 0, 0, 0), "fence_end_w": (0, 1, 0, 0),
}


def fence_piece(n: int, e: int, s: int, w: int) -> g.Pic:
    parts = []
    if w:
        parts += [F_RAIL_W, F_POST_W]
    if e:
        parts += [F_RAIL_E, F_POST_E]
    if n:
        parts.append(F_RAILS_N)
    if s:
        parts.append(F_RAILS_S)
    straight = (n, e, s, w) in ((0, 1, 0, 1), (1, 0, 1, 0))
    parts.append((F_PICKET if (n, e, s, w) == (0, 1, 0, 1) else F_PICKET_CHIPPED) if straight else F_CPOST)
    return on(GRASS, layer(*parts))


def fences() -> None:
    for name, nesw in FENCES.items():
        reg(name, fence_piece(*nesw), flags=("solid",), bank=4)
    # a gate across an east-west run: the posts of the two boundaries, hinge straps on the left one, a latch on the
    # right one, and nothing between them
    gate_h = layer(F_POST_W, F_POST_E, draw("""
        ................
        ................
        ................
        ................
        ................
        ................
        ...3............
        ...2............
        ................
        .............3..
        ...3.........3..
        ...2............
        ................
        ................
        ................
        ................
    """))
    reg("fence_gate_h", on(GRASS, gate_h), flags=(), bank=4)
    # a gate across a north-south run: the post that ends the run from the north stands behind the hero, the one that
    # starts the run to the south in front of him (front layer), so he walks between them
    top = draw("""
        ......23.23.....
        ......33333.....
        ......30013.....
        ......32223.....
        ......30123.....
        ......30123.....
        ......30223.....
        ......33333.....
        .......sssss....
        ................
        ................
        ................
        ................
        ................
        ................
        ................
    """)
    bottom = draw("""
        ................
        ................
        ................
        ................
        ................
        ................
        ................
        ................
        ................
        ......33333.....
        ......30013.....
        ......32223.....
        ......30123.....
        ......30223.....
        ......30123.....
        ......33333.....
    """)
    reg("fence_gate_v", on(GRASS, top), front=front_of(bottom), flags=(), bank=4)
    # not in the brief: the four-way crossing, for a map's mask 15
    reg("fence_cross", fence_piece(1, 1, 1, 1), flags=("solid",), bank=4)



# ======================================================================== buildings
# A building is one big drawing cut into cells `<name>_<row>_<col>`. Letters in the drawings are textures: the same
# roof tile, plank or stone is drawn the same way wherever it appears, and the hand-drawn digits sit on top of them.
def building(name: str, text: str, tex: dict, cols: int, rows: int, door: tuple[int, int], banks: dict,
             fronts: dict | None = None) -> dict[tuple[int, int], g.Pic]:
    """Registers a building: every cell solid but the door cell; `banks` {row: bank}; `fronts` {(row, col): picture}."""
    p = on(GRASS, draw(text, tex, cols * 16, rows * 16))
    out = cells(p, cols, rows)
    for (r, c), cell in out.items():
        flags = ("door",) if (r, c) == door else ("solid",)
        fr = (fronts or {}).get((r, c))
        reg(f"{name}_{r}_{c}", cell, front=fr, flags=flags, bank=banks[r])
    return out


WHITEWASH = Tex("""
    0000000000000000
    0000000000000000
    0000000000010000
    0000000000000000
    0000000000000000
    0100000000000000
    0000000000000000
    0000000000000000
""")
EAVE_SHADE = Tex("""
    20
    02
""")
BRICK = Tex("""
    1112
    2222
    1211
    2222
""", ox=1)

# Yaya's cottage. Barrel tiles of red clay laid in columns down a hipped roof (a scallop at each tile's end, the left
# strip of the roof lit and the right one in shade), a capped ridge, the open ends of the tiles along the eaves, a
# brick chimney that leans a little. Whitewashed walls under the eaves' shadow, shutters, geraniums, an arched door.
CASA_A_TEX = {
    "R": Tex("""
        2101112
        2101112
        3111223
        3311233
        2233322
    """, ox=2, oy=3),
    "L": Tex("""
        1101111
        1101111
        2111112
        3211123
        1223321
    """, ox=2, oy=3),
    "D": Tex("""
        2111222
        2111222
        3222223
        3322233
        2233322
    """, ox=2, oy=3),
    "Q": Tex("001113", ox=2),
    "q": Tex("122223", ox=2),
    "E": Tex("""
        2100112
        3033323
        3333333
    """, ox=2, oy=28),
    "W": WHITEWASH, "Y": EAVE_SHADE, "B": BRICK,
}
CASA_A = """
    ...................33333........................
    ..................3211223.......................
    .................333333333......................
    .......3333333333330000133333333333333333.......
    .......3QQQQQQQQQQ30WWW13QQQQQQQQQQQQQQQ3.......
    ......3qqqqqqqqqq30WWW13qqqqqqqqqqqqqqqqq3......
    ......30LLLRRRRRR30WWW133RRRRRRRRRRRRDDD23......
    ......30LLLRRRRRR30WWW1333RRRRRRRRRRRDDD23......
    ......30LLLRRRRRR30WWW13333RRRRRRRRRRDDD23......
    .....30LLLRRRRRRR333333333RRRRRRRRRRRRDDD23.....
    .....30LLLRRRRRRRRRRRRRRRRRRRRRRRRRRRRDDD23.....
    .....30LLLRRRRRRRRRRRRRRRRRRRRRRRRRRRRDDD23.....
    ....30LLLRRRRRRRRRRRRRRRRRRRRRRRRRRRRRRDDD23....
    ....30LLLRRRRRRRRRRRRRRRRRRRRRRDDDDDRRRDDD23....
    ....30LLLRRRRRRRRRRRRRRRRRRRRRRDDDDDRRRDDD23....
    ....30LLLRRRRRRRRRRRRRRRRRRRRRRDDDDDRRRDDD23....
    ...30LLLRRRRRRRRRRRRRRRRRRRRRRRDDDDDRRRRDDD23...
    ...30LLLRRRRRRRRRRRRRRRRRRRRRRRDDDDDRRRRDDD23...
    ...30LLLRRRRRRRRRRRRRRRRRRRRRRRRRRRRRRRRDDD23...
    ..30LLLRRRRRRRRRRRRRRRRRRRRRRRRRRRRRRRRRRDDD23..
    ..30LLLRRRRRRRRRRRRRRRRRRRRRRRRRRRRRRRRRRDDD23..
    ..30LLLRRRRRRRRRRRRRRRRRRRRRRRRRRRRRRRRRRDDD23..
    .30LLLRRRRRRRRRRRRRRRRRRRRRRRRRRRRRRRRRRRRDDD23.
    .30LLLRRRRLLLLLRRRRRRRRRRRRRRRRRRRRRRRRRRRDDD23.
    .30LLLRRRRLLLLLRRRRRRRRRRRRRRRRRRRRRRRRRRRDDD23.
    .30LLLRRRRLLLLLRRRRRRRRRRRRRRRRRRRRRRRRRRRDDD23.
    30LLLRRRRRLLLLLRRRRRRRRRRRRRRRRRRRRRRRRRRRRDDD23
    30LLLRRRRRLLLLLRRRRRRRRRRRRRRRRRRRRRRRRRRRRDDD23
    3EEEEEEEEEEEEEEEEEEEEEEEEEEEEEEEEEEEEEEEEEEEEEE3
    3EEEEEEEEEEEEEEEEEEEEEEEEEEEEEEEEEEEEEEEEEEEEEE3
    3EEEEEEEEEEEEEEEEEEEEEEEEEEEEEEEEEEEEEEEEEEEEEE3
    333333333333333333333333333333333333333333333333
    ..32222222222222222222222222222222222222222223ss
    ..3YYYYYYYYYYYYYYYYYYYYYYYYYYYYYYYYYYYYYYYYYY3ss
    ..3W33333333333WWWWW33333333WWWWW33333333333W3ss
    ..3W32303133323WWWW3111111123WWWW32303133323W3ss
    ..3W33311111333WWW311333333223WWW33311111333W3ss
    ..3W32333133323WWW313123122323WWW32333133323W3ss
    ..3W32333133323WWW313123122323WWW32333133323W3ss
    ..3W33111111133WWW313123122323WWW33111111133W3ss
    ..3WW33W333W33WWWW313123122323WWWW333WW333WWW3ss
    ..3W30232023203WWW313123102323WWW32023320233W3ss
    ..3W33333333333WWW313123122323WWW33333333333W3ss
    ..3WW322222223WWWW313123122323WWWW322222223WW3ss
    ..31111111111111113131231223231111111111111113ss
    ..32222222222222223133333333232222222222222223ss
    ..32222222222222223311111111332222222222222223ss
    ..33333333333333333333333333333333333333333333ss
"""


# The wooden house. A loaf of thatch: courses of straw (the left of the loaf lit, the right in shade), a ridge of
# finer straw with its edge cut in teeth, a ragged fringe at the eaves over the wall's deep shadow, a chimney of
# round stones. Walls of overlapping boards on a stone footing, a round window, a door of planks on a Z of battens,
# a small window with a curtain and a pot on its shelf.
CASA_B_TEX = {
    "T": Tex("""
        111011
        121121
        211211
        222322
        332333
    """, oy=1, bend=dome(23.5, 24, 3)),
    "t": Tex("""
        101111
        111111
        111112
        121212
        221222
    """, oy=1, bend=dome(23.5, 24, 3)),
    "u": Tex("""
        121121
        221221
        212212
        232323
        332333
    """, oy=1, bend=dome(23.5, 24, 3)),
    "Z": Tex("""
        100101
        121112
        111211
    """, oy=3),
    "P": Tex("""
        11111112
        11111112
        22222223
        11121111
        11121111
        22232222
    """, oy=34),
    "S": Tex("""
        10123
        11223
        33333
    """, oy=44),
    "Y": Tex("""
        21
        12
    """),
}
CASA_B = """
    ...........................33333................
    ..........................3001123...............
    ...............333333333333222223...............
    ..........33333ZZZZZZZZZZZ301310333333..........
    .......333ZZZZZZZZZZZZZZZZ3123213ZZZZZ333.......
    .....33ZZZZZZZZZZZZZZZZZZZ3331333ZZZZZZZZ33.....
    ....3tttZZT33TZZT33TZZT33T3103013ZT33TZZuuu3....
    ...3tttttTTTTTTTTTTTTTTTTT3213123TTTTTTuuuuu3...
    ..3tttttTTTTTTTTTTTTTTTTTT3333333TTTTTTTuuuuu3..
    ..3tttttTTTTTTTTTTTTTTTTTTTTTTTTTTTTTTTTuuuuu3..
    .3tttttTTTTTTTTTTTTTTTTTTTTTTTTTTTTTTTTTTuuuuu3.
    .3tttttTTTTTTTTTTTTTTTTTTTTTTTTTTTTTTTTTTuuuuu3.
    .3tttttTTTTTTTTTTTTTTTTTTTTTTTTTTTTTTTTTTuuuuu3.
    3tttttTTTTTTTTTTTTTTTTTTTTTTTTTTTTTTTTTTTTuuuuu3
    3tttttTTTTTTTTTTTTTTTTTTTTTTTTTTTTTTTTTTTTuuuuu3
    3tttttTTTTTTTTTTTTTTTTTTTTTTTTTTTTTTTTTTTTuuuuu3
    3tttttTTTTTTTTTTTTTTTTTTTTTTTTTTTTTTTTTTTTuuuuu3
    3tttttTTTTTTTTTTTTTTTTTTTTTTTTTTTTTTTTTTTTuuuuu3
    3tttttTTTTTTTTTTTTTTTTTTTTTTTTTTTTTTTTTTTTuuuuu3
    3tttttTTTTTTTTTTTTTTTTTTTTTTTTTTTTTTTTTTTTuuuuu3
    3tttttTTTTTTTTTTTTTTTTTTTTTTTTTTTTTTTTTTTTuuuuu3
    3ttttTTTTTTTTTTTTTTTTTTTTTTTTTTTTTTTTTTTTTuuuuu3
    3ttttTTTTTTTTTTTTTTTTTTTTTTTTTTTTTTTTTTTTTuuuuu3
    3ttttTTTTTTTTTTTTTTTTTTTTTTTTTTTTTTTTTTTTTuuuuu3
    3ttttTTTTTTTTTTTTTTTTTTTTTTTTTTTTTTTTTTTTTuuuuu3
    3ttttTTTTTTTTTTTTTTTTTTTTTTTTTTTTTTTTTTTTTuuuuu3
    3ttttTTTTTTTTTTTTTTTTTTTTTTTTTTTTTTTTTTTTTuuuuu3
    3ttttTTTTTTTTTTTTTTTTTTTTTTTTTTTTTTTTTTTTTuuuuu3
    3ttttTTTTTTTTTTTTTTTTTTTTTTTTTTTTTTTTTTTTTTuuuu3
    322323223223232232223222322322322322322232232233
    333232332323332323332333233233233233233323323323
    333333333333333333333333333333333333333333333333
    ..32222222222222222222222222222222222222222223ss
    ..3YYYYYYYYYYYYYYYYYYYYYYYYYYYYYYYYYYYYYYYYYY3ss
    ..3PPPP33333PPPPPPP3333333333PPPPPP3333333PPP3ss
    ..3PPP3111113PPPPPP3222222223PPPPPP3100013PPP3ss
    ..3PP313313313PPPPP3333333333PPPPPP3101113PPP3ss
    ..3PP313013313PPPPP3112112123PPPPPP3011113PPP3ss
    ..3PP311111113PPPPP3222222223PPPPPP3331333PPP3ss
    ..3PP313313313PPPPP3112112323PPPPPP3311133PPP3ss
    ..3PP313313313PPPPP3112113123PPPPPP3333333PPP3ss
    ..3PPP3111113PPPPPP3112311123PPPPP333333333PP3ss
    ..3PPPP33333PPPPPPP3113112123PPPPP322222223PP3ss
    ..3PPPPPPPPPPPPPPPP3131120123PPPPPP3333333PPP3ss
    ..3SSSSSSSSSSSSSSSP3222222223PSSSSSSSSSSSSSSS3ss
    ..3SSSSSSSSSSSSSSSP3112112123PSSSSSSSSSSSSSSS3ss
    ..3SSSSSSSSSSSSSSS331111111133SSSSSSSSSSSSSSS3ss
    ..33333333333333333333333333333333333333333333ss
"""


# Tio Nogal's shop. A roof of fish-scale shingles with a tin stovepipe, a striped awning with a scalloped edge over
# the whole front, walls of upright boards on a stone footing. Against the wall a barrel and a sack of walnuts, a
# glazed shop door, the sign (a walnut, for Nogal) hanging from an iron bar, and a crate of apples.
TIENDA_TEX = {
    "R": Tex("""
        100112
        101112
        311123
        233332
        112100
        112101
        123311
        332233
    """, ox=1, oy=6),
    "L": Tex("""
        100111
        101111
        111112
        123321
        111100
        111101
        112211
        221233
    """, ox=1, oy=6),
    "D": Tex("""
        111222
        112222
        322223
        233333
        222111
        222112
        223322
        333333
    """, ox=1, oy=6),
    "Q": Tex("000111", ox=2),
    "q": Tex("112223", ox=2),
    "Y": Tex("""
        21
        12
    """),
    "A": Tex("""
        11113333
        00012223
        00012223
        00012223
        00012223
        00012223
        00012223
    """, ox=1, oy=21),
    "V": Tex("""
        11112223
        00012223
        30013223
        23322332
    """, ox=1, oy=27),
    "p": Tex("""
        2223
        2223
        3333
        2223
    """, ox=3, oy=16),
    "P": Tex("""
        1112
        1112
        1112
        1102
        1112
        1112
    """, ox=3),
    "S": CASA_B_TEX["S"],
}
TIENDA = """
    ................................................33333...........
    ...............................................3100023..........
    ................................................33333...........
    .33333333333333333333333333333333333333333333333330233333333333.
    30QQQQQQQQQQQQQQQQQQQQQQQQQQQQQQQQQQQQQQQQQQQQQQQ312QQQQQQQQQQ23
    30qqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqq302qqqqqqqqqq23
    30LLLLRRRRRRRRRRRRRRRRRRRRRRRRRRRRRRRRRRRRRRRRRRR312RRRRRRDDDD23
    30LLLLRRRRRRRRRRRRRRRRRRRRRRRRRRRRRRRRRRRRRRRRRRR3023RRRRRDDDD23
    30LLLLRRRRRRRRRRRRRRRRRRRRRRRRRRRRRRRRRRRRRRRRRRR33333RRRRDDDD23
    30LLLLRRRRRRRRRRRRRRRRRRRRRRRRRRRRRRRRRRRRRRRRRRRRRRRRRRRRDDDD23
    30LLLLRRRRRRRRRRRRRRRRRRRRRRRRRRRRRRRRRRRRRRRRRRRRRRRRRRRRDDDD23
    30LLLLRRRRRRRRRRRRRRRRRRRRRRRRRRRRRRRRRRRRRRRRRRRRRRRRRRRRDDDD23
    30LLLLRRRRRRRRRRRRRRRRRRRRRRRRRRRRRRRRRRRRRRRRRRRRRRRRRRRRDDDD23
    30LLLLRRRRRRRRRRRRRRRRRRRRRRRRRRRRRRRRRRRRRRRRRRRRRRRRRRRRDDDD23
    30LLLLRRRRRRRRRRRRRRRRRRRRRRRRRRRRRRRRRRRRRRRRRRRRRRRRRRRRDDDD23
    3333333333333333333333333333333333333333333333333333333333333333
    3222222222222222222222222222222222222222222222222222222222222223
    3pppppppppppppppppppppppppppppppppppppppppppppppppppppppppppppp3
    3pppppppppppppppppppppppppppppppppppppppppppppppppppppppppppppp3
    3pppppppppppppppppppppppppppppppppppppppppppppppppppppppppppppp3
    3333333333333333333333333333333333333333333333333333333333333333
    3AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA3
    3AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA3
    3AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA3
    3AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA3
    3AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA3
    3333333333333333333333333333333333333333333333333333333333333333
    3VVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVV3
    3VVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVV3
    3VVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVV3
    VVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVV
    .22222222222222222222222222222222222222222222222222222222222222.
    ..322222222222222222222222222222222222222222222222222222222223ss
    ..3YYYYYYYYYYYYYYYYYYYYYYYYYYYYYY33333333333333YYYYYYYYYYYYYY3ss
    ..3PPPPPPPPPPPPPPPP3333333333PPPPP3PPPPPPPP3PPPPPPPPPPPPPPPPP3ss
    ..3PPPPPPPPPPPPPPPP3111111113PPPPP3PPPPPPPP3PPPPPPPPPPPPPPPPP3ss
    ..3PP33333PPPPPPPPP3133333313PPPP3333333333333PPPPPPPPPPPPPPP3ss
    ..3P3100013P33333PP3130331313PPPP3111111311113PPPP33P33P33PPP3ss
    ..3P32111233100013P3133333313PPPP3111113111113PPP3103013013PP3ss
    ..3P33333333211123P3111111113PPPP3111131311113PP330130130133P3ss
    ..3P31011233333333P3122122213PPPP3113331331113PP31111111111233ss
    ..3P31011233101123P3122122213PPPP3130313003113PP31333333333233ss
    ..3P33333333333333P3122122203PPPP3133313333113PP31212121212233ss
    ..3P31011233101123P3122122213PPPP3113311331123PP31333333333233ss
    ..3S32112233211223S3133333313SSSS3222222222223SS31212121212233ss
    ..3S33333333333333311111111113SSS3333333333333SS32222222222233ss
    ..3SS32223SS32223S333333333333SSSSSSSSSSSSSSSSSS33333333333333ss
    ..333333333333333333333333333333333333333333333333333333333333ss
"""


# The mayor's house: two floors of ashlar under a low slate roof. Over the door cell rises a bay that carries
# everything that says "town hall": the double door under a stone arch and its step, the balcony with its iron
# railing where the mayor speaks, a clock, a slate cap and the island's flag. Upper windows framed in stone, the
# ground floor's behind iron grilles (rejas), a lantern by the door, a string course between the floors.
ALCALDIA_TEX = {
    "R": Tex("""
        1112311123
        2222322223
        3333333333
        1231112311
        2232222322
        3333333333
    """, ox=1, oy=8),
    "L": Tex("""
        0011201112
        1112211112
        2222222222
        1121011211
        1122111221
        2222222222
    """, ox=1, oy=8),
    "D": Tex("""
        2223322233
        2223322233
        3333333333
        2332223322
        2333223332
        3333333333
    """, ox=1, oy=8),
    "Q": Tex("1"),
    "A": Tex("""
        00111112
        11111112
        22222222
        11120011
        11121111
        22222222
    """, ox=2, oy=16),
    "B": Tex("0"),
    "b": Tex("2"),
    "Y": Tex("""
        21
        12
    """),
}
ALCALDIA = """
    ......................3.........................................
    ......................33333.....................................
    ......................30013.....................................
    ......................30123.....................................
    ......................33333.....................................
    .....................3333.......................................
    .33333333333333333333RRRR33333333333333333333333333333333333333.
    3QQQQQQQQQQQQQQQQQ33RRRRRR33QQQQQQQQQQQQQQQQQQQQQQQQQQQQQQQQQQQ3
    3LLLLRRRRRRRRRRR33RRRRRRRRRR33RRRRRRRRRRRRRRRRRRRRRRRRRRRRRDDDD3
    3LLLLRRRRRRRRRR333333333333333333RRRRRRRRRRRRRRRRRRRRRRRRRRDDDD3
    3LLLLRRRRRRRRRRR3BAAA333333AAAb3RRRRRRRRRRRRRRRRRRRRRRRRRRRDDDD3
    3LLLLRRRRRRRRRRR3BAA30000003AAb3RRRRRRRRRRRRRRRRRRRRRRRRRRRDDDD3
    3LLLLRRRRRRRRRRR3BA3000030013Ab3RRRRRRRRRRRRRRRRRRRRRRRRRRRDDDD3
    3LLLLRRRRRRRRRRR3BA3000030013Ab3RRRRRRRRRRRRRRRRRRRRRRRRRRRDDDD3
    3LLLLRRRRRRRRRRR3BA3000033313Ab3RRRRRRRRRRRRRRRRRRRRRRRRRRRDDDD3
    33333333333333333BA3000000013Ab333333333333333333333333333333333
    .3222222222222223BAA31111113AAb3Y222222222222222222222222222223s
    .3YYYYYYYYYYYYYY3BAAA333333AAAb3YYYYYYYYYYYYYYYYYYYYYYYYYYYYYY3s
    .3AA333333333AAA3BAA33333333AAb3YAAAA333333333AAAAA333333333AA3s
    .3AA300000123AAA3BA3111111113Ab3YAAAA300000123AAAAA300000123AA3s
    .3AA333333333AAA3BA3133333313Ab3YAAAA333333333AAAAA333333333AA3s
    .3AAA3330333AAAA3BA3130330313Ab3YAAAAA3330333AAAAAAA3330333AAA3s
    .3AAA3303333AAAA3BA3133333313Ab3YAAAAA3303333AAAAAAA3303333AAA3s
    .3AAA3111113AAAA3BA3133333313Ab3YAAAAA3111113AAAAAAA3111113AAA3s
    .3AAA3330333AAAA3BA3133333313Ab3YAAAAA3330333AAAAAAA3330333AAA3s
    .3AAA3330333AAAA3B333333333333b3YAAAAA3330333AAAAAAA3330333AAA3s
    .3AA331111133AAA3B3A3A3A3A3A33b3YAAAA331111133AAAAA331111133AA3s
    .3AA322222223AAA3B3A3A3A3A3A33b3YAAAA322222223AAAAA322222223AA3s
    .3AA333333333AAA3B333333333333b3YAAAA333333333AAAAA333333333AA3s
    .3AAAAAAAAAAAAAA3B300000000013b3YAAAAAAAAAAAAAAAAAAAAAAAAAAAAA3s
    .3000000000000003B322222222223b3Y000000000000000000000000000003s
    .3111111111111113BAAAAAAAAAAAAb3Y111111111111111111111111111113s
    .3333333333333333BAA33333333AAb3Y333333333333333333333333333333s
    .3YYYYYYYYYYYYYY3BA3111111113Ab3YYYYYYYYYYYYYYYYYYYYYYYYYYYYYY3s
    .3AA333333333AAA3B311333333123b3YAAAA333333333AAAAA333333333AA3s
    .3AA310000013AAA3B313132231312b3YA3AA310000013AAAAA310000013AA3s
    .3AA330303033AAA3B313132231312b3Y333A330303033AAAAA330303033AA3s
    .3AA313131313AAA3B313132231312b3Y303A313131313AAAAA313131313AA3s
    .3AA330303033AAA3B313130231312b3Y313A330303033AAAAA330303033AA3s
    .3AA313131313AAA3B313132231312b3Y333A313131313AAAAA313131313AA3s
    .3AA330303033AAA3B313132231312b3YAAAA330303033AAAAA330303033AA3s
    .3AA322222223AAA3B313333333312b3YAAAA322222223AAAAA322222223AA3s
    .3AA333333333AAA3B311111111112b3YAAAA333333333AAAAA333333333AA3s
    .3333333333333333A333333333333A33333333333333333333333333333333s
    .31111111111111133333333333333331111111111111111111111111111113s
    .32222222222222230000000000001232222222222222222222222222222223s
    .32222222222222233333333333333332222222222222222222222222222223s
    .33333333333333333333333333333333333333333333333333333333333333s
"""


def buildings() -> None:
    building("casa_a", CASA_A, CASA_A_TEX, 3, 3, door=(2, 1), banks={0: 5, 1: 5, 2: 4})
    building("casa_b", CASA_B, CASA_B_TEX, 3, 3, door=(2, 1), banks={0: 5, 1: 5, 2: 4})
    building("tienda", TIENDA, TIENDA_TEX, 4, 3, door=(2, 1), banks={0: 5, 1: 5, 2: 4})
    building("alcaldia", ALCALDIA, ALCALDIA_TEX, 4, 3, door=(2, 1), banks={0: 5, 1: 6, 2: 6})


# ======================================================================== props on the grass
# Each stands on the terrain's grass (its tufts kept only where they fit whole), outlined in tone 3, lit from the top
# left, with the terrain's contact shadow: tone 2 under the bottom right.
TILLED = draw("\n".join(["0000000000000000", "1111111111111111", "2222222222222222", "3333333333333333"] * 4))
try:
    TILLED = getattr(_terrain, "DIRT_TILLED", TILLED)
except NameError:
    pass


def prop(text: str, ground: g.Pic | None = None) -> g.Pic:
    return on(GRASS if ground is None else ground, draw(text, None, 16, 16))


BARREL = """
    ................
    ................
    .....333333.....
    ....30000113....
    ...3011111123...
    ...3322222233...
    ...3101112123...
    ...3333333333...
    ...3101112123...
    ...3101112123...
    ...3101112123...
    ...3333333333...
    ...3101112123...
    ...3211112223s..
    ....33333333ss..
    .....sssssss....
"""
CRATE = """
    ................
    ................
    ................
    ...3333333333...
    ...3000000013...
    ...3111111123...
    ...3333333333...
    ...3133113133...
    ...3121331223...
    ...3123113123...
    ...3133113133...
    ...3121331223...
    ...3222222223s..
    ...3333333333s..
    ....sssssssss...
    ................
"""
CRATES = """
    .....33333333...
    .....30000013...
    .....33333333...
    .....31313123...
    .....31131123...
    ..33333333333...
    ..30000000133s..
    ..31111111233s..
    ..33333333333s..
    ..31331133133s..
    ..31213312123s..
    ..31331133133s..
    ..32222222223s..
    ..33333333333s..
    ...ssssssssss...
    ................
"""
HAYSTACK = """
    ................
    ......3333......
    ....33101133....
    ...3100110113...
    ..301011101123..
    ..310110111123..
    .30101101111123.
    .31011011112123.
    .31101111121223.
    .31111112112123.
    .32111211212223.
    .32212122122223.
    .32222222222233s
    ..333333333333ss
    ...ssssssssssss.
    ................
"""
WOODPILE = """
    ................
    ................
    ................
    ....333..333....
    ...30123301233..
    ...31323313233..
    ...30123301233..
    ..333.333.333...
    .30123012301233.
    .31323132313233.
    .30123012301233.
    .3333333333333s.
    .3222222222223s.
    .3333333333333s.
    ..sssssssssssss.
    ................
"""
SIGNPOST = """
    ................
    ..333333333333..
    .30000000000013.
    .30333033033013.
    .30000000000013.
    .30330333303013.
    .31111111111123.
    ..333333333333..
    ......3013......
    ......3013......
    ......3013......
    ......3013......
    ......3013s.....
    .....330133s....
    ......ssss......
    ................
"""
MAILBOX = """
    ................
    ................
    ....333333......
    ...30000113.....
    ..3011111123....
    ..3111111123.3..
    ..3133333323333.
    ..3122222223323.
    ..3111111123.3..
    ..3333333333....
    ......323.......
    ......323.......
    ......323s......
    ......323s......
    .....33333s.....
    ......sssss.....
"""
FLOWERPOT = """
    ................
    ................
    ......33.33.....
    .....3003003....
    ....303333303...
    ...3003023003...
    ...3333223333...
    ....3322223.....
    ....33333333....
    ....30111123....
    .....311123.....
    .....311223.....
    .....312223s....
    ......3333ss....
    .......sss......
    ................
"""
WATERING_CAN = """
    ................
    ................
    ................
    ................
    ......3333......
    .....3....3.....
    ...33333333.....
    ..3000011113..33
    ..3011111123.303
    ..3111111123303.
    ..3111111123333.
    ..3111111223....
    ..3222222223s...
    ...33333333ss...
    ....ssssssss....
    ................
"""
WELL_BUCKET = """
    ................
    ................
    ................
    ......3333......
    .....3....3.....
    ....3......3....
    ...3333333333...
    ...3000000013...
    ...3311111133...
    ....31011123....
    ....33333333....
    ....31011123....
    ....32111223s...
    .....333333ss...
    ......ssssss....
    ................
"""
BEEHIVE = """
    ................
    ......3333......
    .....310013.....
    ....33333333....
    ...3011111123...
    ...3333333333...
    ..301111111123..
    ..333333333333..
    ..311113311123..
    ..311130031123..
    ..333333333333..
    ...3222222223...
    ..333333333333s.
    ...3.3....3.3ss.
    ...3.3....3.3s..
    ....s.....s.s...
"""
SCARECROW_POST = """
    ................
    ................
    ................
    ................
    ......3333......
    ......3013......
    ......3013......
    ......3013......
    ......3023......
    ......3013......
    ......3013......
    .....330133.....
    ....33201233s...
    ....32222223s...
    .....333333s....
    ......ssss......
"""
CHEST_CLOSED = """
    ................
    ................
    ....33333333....
    ...3001110113...
    ..300111101123..
    ..301111101123..
    ..311111101223..
    ..333333333333..
    ..312113312123..
    ..312130032123..
    ..312130312123..
    ..312113312123..
    ..322222322223s.
    ..333333333333s.
    ...sssssssssss..
    ................
"""
CHEST_OPEN = """
    ....33333333....
    ...3112221223...
    ..311222212223..
    ..311222212223..
    ..333333333333..
    ..300000000013..
    ..333333333333..
    ..312113312123..
    ..312130032123..
    ..312130312123..
    ..312113312123..
    ..312222322123..
    ..322222322223s.
    ..333333333333s.
    ...sssssssssss..
    ................
"""
LAMP_BASE = """
    ................
    ................
    ................
    ................
    ................
    ................
    .......33.......
    .......33.......
    ......3013......
    ......3013......
    ......3013......
    ......3023......
    ......3013......
    .....330133s....
    ....30111123s...
    ....33333333s...
"""
LAMP_HEAD = """
    ......3333......
    .....300013.....
    ....33333333....
    ...1.30003.1....
    ....3000003.....
    ..1.3000003.1...
    ....3000003.....
    ...1.31113.1....
    ....33333333....
    ......3333......
    .......33.......
    ................
    ................
    ................
    ................
    ................
"""
CABBAGE = """
    ................
    ................
    ................
    .....333333.....
    ....30111123....
    ...3013111313...
    ..301131313123..
    ..311311113123..
    ..313113131113..
    ..312131112223..
    ...3213122223...
    ..33223322233...
    ..3123333332133.
    ...33..ss..33...
    ................
    ................
"""
CABBAGE_BIG = """
    ...33333333.....
    ..3011111123....
    .301131113133...
    3011311131113...
    3113113131111333
    3131131311311123
    3113113111311123
    3131111113111223
    3113131311312223
    3122113131122223
    .31221311212223.
    3312221112222333
    3123333333322213
    .33.ssssssss.33.
    ................
    ................
"""
BENCH = """
    ................................
    ................................
    ................................
    ................................
    ...3333333333333333333333333....
    ...3000000000000000000000013....
    ...3333333333333333333333333....
    ...3000000000000000000000013....
    ...3111111111111111111111123....
    ...3333333333333333333333333s...
    ....3213..............3213ss....
    ....3333333333333333333333s.....
    ....3213..............3213s.....
    ....3213..............3213s.....
    ....3333..............3333s.....
    .....ssss..............ssss.....
"""
FLOWERBED_A = """
    ................
    ....33333333....
    ..33111011113...
    .3110302111113..
    .3111011101113..
    3111111103011113
    3110111111011113
    3103011111111113
    3110111110111123
    .311111103011123
    .3211111110112s.
    ..322222222223s.
    ..3332222223333s
    ....33333333ss..
    .....sssssss....
    ................
"""
FLOWERBED_B = """
    ................
    ....33333333....
    ..33111111113...
    .3111101110113..
    .3111030103011..
    3110111110111113
    3111111111111113
    3111110111011113
    3101103011030123
    .303011101111123
    .3101111111112s.
    ..322222222223s.
    ..3332222223333s
    ....33333333ss..
    .....sssssss....
    ................
"""
WELL = """
    ................................
    ......33333333333333333333......
    .....3000000000000000000123.....
    ....300011111111111111111123....
    ...33333333333333333333333333...
    ...32222222222222222222222223...
    ...33333333333333333333333333...
    .....3013..............3013.....
    .....3013....333333....3013.....
    .....3013...30000003...3013.....
    .....3013....311113....3013.....
    .....3013....333333....3013.....
    .....3013......33......3013.....
    .....3013......33......3013.....
    ....33013333333333333333013.....
    ...3001333333333333333333133....
    ..30111033333333333333301113s...
    .3011110133333333333331011123s..
    .3101101011111111111110110123s..
    .3311331133113311331133113323s..
    .3011301130113011301130113013s..
    .3112311231123112311231123123s..
    .3333333333333333333333333333s..
    .3101130113011301130113011323s..
    .3211321132113211321132113223s..
    ..33333333333333333333333333s...
    ...32222222222222222222222233s..
    ....333333333333333333333333s...
    .....sssssssssssssssssssssss....
    ................................
    ................................
    ................................
"""


def props() -> None:
    for name, text, flags, bank in (
            ("barrel", BARREL, ("solid",), 4), ("crate", CRATE, ("solid",), 4), ("crates", CRATES, ("solid",), 4),
            ("haystack", HAYSTACK, ("solid",), 7), ("woodpile", WOODPILE, ("solid",), 4),
            ("signpost", SIGNPOST, ("solid", "sign"), 4), ("mailbox", MAILBOX, ("solid",), 5),
            ("flowerpot", FLOWERPOT, ("solid",), 7), ("watering_can", WATERING_CAN, ("solid",), 6),
            ("well_bucket", WELL_BUCKET, ("solid",), 4), ("beehive", BEEHIVE, ("solid",), 7),
            ("scarecrow_post", SCARECROW_POST, ("solid",), 4),
            ("chest_closed", CHEST_CLOSED, ("solid", "chest"), 4), ("chest_open", CHEST_OPEN, ("solid",), 4),
            ("flowerbed_a", FLOWERBED_A, ("solid",), 7), ("flowerbed_b", FLOWERBED_B, ("solid",), 7)):
        reg(name, prop(text), flags=flags, bank=bank)
    reg("lamp_post", prop(LAMP_BASE), front=front_of(draw(LAMP_HEAD, None, 16, 16)), flags=("solid",), bank=6,
        front_bank=7)
    cut = ("solid", "cut", "becomes=dirt_tilled")
    reg("cabbage", prop(CABBAGE, TILLED), flags=cut, bank=3)
    reg("cabbage_big", prop(CABBAGE_BIG, TILLED), flags=cut, bank=3)
    bench = on(GRASS, draw(BENCH, None, 32, 16))
    reg("bench_l", g.crop(bench, 0, 0, 16, 16), flags=("solid",), bank=4)
    reg("bench_r", g.crop(bench, 16, 0, 16, 16), flags=("solid",), bank=4)
    # the same on the plaza's cobble (the stones show whole, they are a pattern, not tufts)
    cob = COBBLE if COBBLE is not None else GRASS
    bench_c = on(cob, draw(BENCH, None, 32, 16), whole=True)
    reg("bench_l_cobble", g.crop(bench_c, 0, 0, 16, 16), flags=("solid",), bank=4)
    reg("bench_r_cobble", g.crop(bench_c, 16, 0, 16, 16), flags=("solid",), bank=4)
    reg("signpost_cobble", on(cob, draw(SIGNPOST, None, 16, 16), whole=True), flags=("solid", "sign"), bank=4)
    well = on(GRASS, draw(WELL, None, 32, 32))
    for (r, c), cell in cells(well, 2, 2).items():
        reg("well_" + "tb"[r] + "lr"[c], cell, flags=("solid",), bank=6 if r else 4)


# ======================================================================== the treehouse in the old oak
# Rows 0-1 are the canopy and the little house, drawn on the front layer over plain grass (the hero walks under
# them); row 2 is the trunk on its roots, a ladder nailed up the middle (the door cell).
LEAF = Tex("""
    11011210
    10112111
    21121012
    11210111
    12111211
    01112121
""")
LEAF_D = Tex("""
    22122321
    21223222
    32232123
    22321222
    23222322
    12223232
""")
TREEHOUSE_TOP = """
    ..........3333.......33333333...........333.....
    ......3333LLLL333..33LLLLLLLL33.....3333LLL33...
    ....33LLLLLLLLLLL33LLLLLLLLLLLLL3.33LLLLLLLLLL3.
    ...3LLLLLLLLLLLLLLLLLLLLLLLLLLLLL3LLLLLLLLLLLLL3
    ..3LLLLLLLLLLLLLLLLLLLL333333LLLLLLLLLLLLLLLLLL3
    .3LLLLLLLLLLLLLLLLLL3330000013333LLLLLLLLLLLKKK3
    .3LLLLLLLLLLLLLLL333000000000011333LLLLLLLLLKKK3
    3LLLLLLLLLLLLL3330000000000000011233LLLLLLKKKKK3
    3LLLLLLLLLLLL3333333333333333333333333LLLKKKKKK3
    3LLLLLLLLLLLLL31111111111111111111123LLLLKKKKKK3
    3LLLLLLLLLLLLL31112131121311213111223LLLKKKKKKK3
    3LLLLLLLLLLLLL31112131121311213111223LLKKKKKKKK3
    3LLLLLLLLLLLLL31133331121311333311223LKKKKKKKKK3
    .3LLLLLLLLLLLL31130031121311300311223LKKKKKKKK3.
    .3LLLLLLLLLLLL31133331121311333311223KKKKKKKKK3.
    3LLLLLLLLLLLLL31112131121311213111223KKKKKKKKKK3
    3LLLLLLLLLLLLL31112131333331213111223KKKKKKKKKK3
    3LLLLLLLLLLLLL31112131322231213111223KKKKKKKKKK3
    3LLLLLLLLLLLLL31112131322231213111223KKKKKKKKKK3
    3LLLLLLLLLLLLL33333333322233333333333KKKKKKKKKK3
    3LLLLLLLLLLL3000000000000000000000013KKKKKKKKKK3
    .3LLLLLLLLLL3222222222222222222222223KKKKKKKKK3.
    .3LLLLLLLLLLL33333333333333333333333KKKKKKKKKK3.
    ..3LLLLLLLLLLLLLLLLL3.3221.3LLLKKKKKKKKKKKKKKK3.
    ..3LLLLLLLLLLLLLLLL33.3221.33KKKKKKKKKKKKKKKK3..
    ...33LLLLLLLLLLL333...3221...33KKKKKKKKKKKK33...
    .....333LLLLL333......3221.....333KKKKKKK33.....
    ........33333.........3221.........3333333......
    ......................3221......................
    ......................3221......................
    ......................3221......................
    ......................3221......................
"""
TREEHOUSE_TRUNK = """
    ..................33321112333...................
    ..................321333333123..................
    ..................3213211112123.................
    .................32132333312123.................
    .................32132111112123.................
    .................32132333312123.................
    ................321132111112123.................
    ................321132333312123s................
    ...............3211132111112123ss...............
    ..............32111323333121123ss...............
    ............3321111321111121112333..............
    ..........332111113233331211112223ss............
    ........33221113333211112333311222333s..........
    .......3222333....3211112233..333222233ss.......
    ........333.......3333333333.....3333ss.........
    .........................ssssssss.......ss......
"""


def treehouse() -> None:
    tex = {"L": LEAF, "K": LEAF_D}
    top = draw(TREEHOUSE_TOP, tex, 48, 32)
    trunk = on(GRASS, draw(TREEHOUSE_TRUNK, tex, 48, 16))
    plain = on(GRASS, draw("\n".join(["." * 16] * 16), None, 16, 16))
    for c in range(3):
        for r in range(2):
            fr = front_of(g.crop(top, c * 16, r * 16, 16, 16))
            reg(f"treehouse_{r}_{c}", plain, front=fr, flags=(), bank=0, front_bank=4 if c == 1 else 3)
        reg(f"treehouse_2_{c}", g.crop(trunk, c * 16, 0, 16, 16), flags=("door",) if c == 1 else ("solid",),
            bank=4 if c == 1 else 3)


# ======================================================================== the pier and the sea's edge
# Over the terrain's deep water (its waves kept only where they fit whole); a shadow on the water is tone 3. The
# boat lies beached on the sand (the map puts it on the beach row), and the net, the fish crate and the rope coil
# are beach things, on sand.
PLANK_H = """
    ................
    ................
    3333333333333333
    3000300030003000
    3112311231123112
    3112311201123112
    3112311231123112
    3112311231123112
    3102311231123112
    3112311231123112
    3222322232223222
    3333333333333333
    3223223223223223
    3333333333333333
    ssssssssssssssss
    ................
"""
PLANK_V = """
    ..302223223203s.
    ..312223223213s.
    ..312223223213s.
    ..333333333333s.
    ..301111111103s.
    ..312222222213s.
    ..312222222213s.
    ..333333333333s.
    ..301111111103s.
    ..312222222213s.
    ..312222222213s.
    ..333333333333s.
    ..301111111103s.
    ..312222222213s.
    ..312222222213s.
    ..333333333333s.
"""
PLANK_END_E = """
    ................
    ...........333..
    3333333333330133
    3000300030000123
    3112311231120123
    3112311201120123
    3112311231120123
    3112311231120123
    3102311231120123
    3112311231120123
    3222322232220223
    3333333333330123
    322322322323013s
    33333333333333ss
    ssssssssssssss..
    ................
"""
PLANK_END_S = """
    ..302223223203s.
    ..312223223213s.
    ..312223223213s.
    ..333333333333s.
    ..301111111103s.
    ..312222222213s.
    ..312222222213s.
    ..333333333333s.
    ..301111111103s.
    ..312222222213s.
    ..333333333333s.
    ..301333333103s.
    ..30133..33103s.
    ..32233..33223s.
    ..3333s..s3333s.
    ...ssss...ssss..
"""
PIER_POST = """
    ................
    ................
    ................
    ......3333......
    .....300013.....
    .....311123.....
    .....333333.....
    .....310123.....
    .....312123.....
    .....333333.....
    .....310123.....
    .....312123.....
    ...11312123s1...
    ..1..333333s.1..
    ...1111ssss11...
    ................
"""
BRIDGE_H = """
    ..3........3....
    .303......303...
    3333333333333333
    3000000000000013
    3333333333333333
    3001300130013003
    3112311231123113
    3112311231123113
    3112311231123113
    3222322232223223
    3333333333333333
    .303......303...
    3333333333333333
    3111111111111123
    3333333333333333
    ssssssssssssssss
"""
BRIDGE_V = """
    3033001300130333
    3133112311231133
    3133112311231133
    3133222322232133
    3333333333333333
    3033001300130333
    3133112311231133
    3133112311231133
    3133222322232133
    3333333333333333
    3033001300130333
    3133112311231133
    3133112311231133
    3133222322232133
    3333333333333333
    3s3............3
"""
BOAT = """
    ................................
    ................................
    ................................
    .....3333333333333333333333.....
    ...33000000000000000000001133...
    ..3011111111111111111111111123..
    .301333333333333333333333331123.
    .3013222232222222322222233311233
    .3013222232222222322222233311233
    .3013333333333333333333333311233
    ..30111111111111111111111111123s
    ...332222222222222222222222233ss
    .....3333333333333333333333sss..
    .......ssssssssssssssssssss.....
    ................................
    ................................
"""
NET = """
    ................
    .33..........33.
    .303333333333033
    .313131313131313
    .303030303030303
    .313131313131313
    .303.30303.30303
    .313..313..31313
    .303...3...30303
    .313.......31313
    .303.......30303
    .313.......31313
    .303s......303s.
    .333s......333s.
    ..ss........ss..
    ................
"""
FISH_CRATE = """
    ................
    ................
    ................
    ...3333333333...
    ...3033003303...
    ..330300330303..
    ..303330033033..
    ..311111111123..
    ..333333333333..
    ..313113113123..
    ..312112112123..
    ..333333333333..
    ..322222222223s.
    ..333333333333s.
    ...sssssssssss..
    ................
"""
ROPE_COIL = """
    ................
    ................
    ................
    ................
    .....333333.....
    ....30101013....
    ...3013333103...
    ...3130000313...
    ...3103333013...
    ...3313131333...
    ....33333333s...
    .....ssssssss...
    ...........33...
    ..........3003..
    ...........33...
    ................
"""


def pier() -> None:
    w = lambda t, wd=16: on(WATER, draw(t, None, wd, 16))  # noqa: E731
    reg("plank_h", w(PLANK_H), flags=(), bank=4)
    reg("plank_v", w(PLANK_V), flags=(), bank=4)
    reg("plank_end_e", w(PLANK_END_E), flags=(), bank=4)
    reg("plank_end_s", w(PLANK_END_S), flags=(), bank=4)
    reg("pier_post", w(PIER_POST), flags=("solid",), bank=4)
    reg("bridge_h", w(BRIDGE_H), flags=(), bank=4)
    reg("bridge_v", w(BRIDGE_V), flags=(), bank=4)
    boat = on(SAND, draw(BOAT, None, 32, 16))
    reg("boat_l", g.crop(boat, 0, 0, 16, 16), flags=("solid",), bank=4)
    reg("boat_r", g.crop(boat, 16, 0, 16, 16), flags=("solid",), bank=4)
    reg("net", on(SAND, draw(NET, None, 16, 16)), flags=("solid",), bank=4)
    reg("fish_crate", on(SAND, draw(FISH_CRATE, None, 16, 16)), flags=("solid",), bank=4)
    reg("rope_coil", on(SAND, draw(ROPE_COIL, None, 16, 16)), flags=(), bank=4)


# ======================================================================== registration
def register() -> None:
    fences()
    buildings()
    props()
    treehouse()
    pier()


register()
