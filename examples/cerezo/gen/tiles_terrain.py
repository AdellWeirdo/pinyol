"""The ground of Isla Cerezo (tileset "overworld"): grass, dirt, sand, water, cobblestone and the small things on them.

What is here: 86 metatiles, each only a ground picture (no front layer).
  grass_a _b _c (plain), grass_flowers_a _b, grass_tufts, grass_clover                                   bank 0
  bush, weeds (3); rock_a (mossy), rock_b, rocks_c (a pair) (6); stump, log_h, log_v (4); mushrooms, pebbles (0);
  dirt_loose, hole_dug (1)
  dirt_a _b + the 12 edge pieces, dirt_tilled, dirt_sprouts                                               bank 1
  sand_a _b + the 12 edge pieces, shell, starfish, crab_hole, sand_dug (1); driftwood (4); sand_rocks (6)
  water_a _b (animation "water", 40 ticks) + the 12 edge pieces, shallow_a _b (animation "shallow"),
  water_rocks                                                                                            bank 2
  cobble_a _b + the 12 edge pieces                                                                        bank 6
Edge pieces are <family>_<piece>, the pieces of gbart.edge_piece: n e s w (a border along that side), ne se sw nw
(outer corners), in_ne in_se in_sw in_nw (inner corners: a notch of the background in that corner).

Design decisions
* A material is told by its tone-2/3 marks, never by 0 against 1 (in the DMG greens those two are one colour):
  grass is tone 0 with small "ʌ" tufts of 2; dirt is tone 1 with pebbles (0 over 2/3) inside a dark border; sand is
  tone 0 with a fine regular stipple of 1 and a few grains of 2; deep water is tone 2 with light swashes, each with a
  tone-3 trough; the plaza is round stones with a joint of 2 and a shadow of 3 under each stone.
* Light from the top left: a border is a tone-3 line with a dithered shadow on its north and west sides and a tone-2
  line on its south and east sides; things have their outline, highlight top left and shadow bottom right, and a
  short tone-2 shadow on the ground below and to the right.
* Edges are generated, so they always fit: each piece is drawn whole from a mask. The border runs K = 3 pixels in from
  the tile's edge where tiles meet (columns and rows 0, 7, 8, 15) and wobbles in between (PROFILE); the outer and inner
  corners are small hand masks that meet those depths. Grass tufts grow along a border where they fit wholly on grass,
  so the grass beside a path or a beach keeps its texture. Dirt and sand wobble; the plaza's kerb runs straight.
* Water lies over sand: dotted wet sand, a line of foam, a band of shallow water and a dither down into the deep, from
  the distance to the sand (the mask carried past the tile's edge, so the bands meet at every seam).
* The plaza ends in a kerb (a line, long stones with a joint every 8 pixels, a line of earth); the cobbles the kerb
  cuts are shaded again as whole stones.
* hole_dug has its crumbs on the sand stipple's places round the hole: on grass they read as thrown-up soil, on sand
  they continue the stipple, so one hole serves both dirt_loose and sand_dug.

Using the families: an area at least two cells wide; a family borders grass (water borders sand) and never touches
another family. Water lies over sand, so when the sand's pieces are chosen the water cells must count as sand, or a
grass lip appears between the beach and the sea.

python3 gen/tiles_terrain.py draws art/terrain_*.png (DMG over POCKET): every tile labelled, each family on a test
map with every piece at 3x, and two whole screens (beach, village) at 3x and 1x.
"""
from __future__ import annotations

import math
import sys
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent))
import gbart as g  # noqa: E402
from gbart import ART  # noqa: E402

SET = "overworld"
MINE: list[str] = []  # the metatiles this module registers, in order


def T(s: str, w: int = 16, h: int = 16) -> g.Pic:
    """Text rows, indented freely, to a w x h picture."""
    return g.pic([ln.strip() for ln in s.strip("\n").split("\n")], w, h)


def on(base: g.Pic, top: str) -> g.Pic:
    """A drawing with see-through '.' laid on a ground tile."""
    return g.overlay(base, T(top))


def meta(name: str, ground: g.Pic, flags: tuple = (), bank: int = 0) -> None:
    ART.meta(SET, name, ground, flags=flags, bank=bank)
    MINE.append(name)


# ======================================================================== grass
GRASS_A = T("""
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
GRASS_B = T("""
    0000000000000000
    0000000000200000
    0000000002020000
    0000000000000000
    0000000000000000
    0000000000000000
    0000000000000000
    0000000000000000
    0020200000000000
    0202020000000000
    0000000000000000
    0000000000000000
    0000000000000000
    0000000002000000
    0000000020200000
    0000000000000000
""")
GRASS_C = T("""
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
    0000000000000000
    0000202020000000
    0002020202000000
    0000000000000000
    0000000000000000
    0000000000000000
""")
GRASS_FLOWERS_A = T("""
    0000000000000000
    0000000000000000
    0000200000000000
    0002020000000000
    0020312000000000
    0002120000000000
    0000200000000000
    0000000000000000
    0000000000000000
    0000000000020000
    0000000000202000
    0000000002031200
    0000000000212000
    0000000000020000
    0000000000000000
    0000000000000000
""")
GRASS_FLOWERS_B = T("""
    0000000000000000
    0000000000020000
    0000000000202000
    0000000002031200
    0000000000212000
    0000200000020000
    0002020000000000
    0020312000000000
    0002120000000000
    0000200000000000
    0000000000000000
    0000000000000000
    0000000000000000
    0000000002020000
    0000000020202000
    0000000000000000
""")
GRASS_TUFTS = T("""
    0000000000000000
    0000000000000000
    0000000000000000
    0000000000000000
    0000000200000000
    0000200200200000
    0000020202002000
    0002020202020000
    0000222222200000
    0000021212000000
    0000000000000000
    0000000000000000
    0000000000000000
    0000000000000000
    0000000000000000
    0000000000000000
""")
GRASS_CLOVER = T("""
    0000000000000000
    0000000000000000
    0000000000000000
    0001201200000000
    0002202200000000
    0000012000120120
    0000022000220220
    0000000000001200
    0000000001202200
    0000000002200000
    0001201200000000
    0002202200000000
    0000012000000000
    0000022000000000
    0000000000000000
    0000000000000000
""")

# ======================================================================== dirt (a path or garden soil over grass)
DIRT_A = T("""
    1111111111111111
    1111111111111111
    1111111111110111
    1111111111112111
    1110011111111111
    1112311111111111
    1111111112111111
    1111111111111111
    1111111111111111
    1111111111111111
    1111111111100111
    1111111111123111
    1111101111111111
    1111121111111121
    1111111111111111
    1111111111111111
""")
DIRT_B = T("""
    1111111111111111
    1111111111111111
    1111110111111111
    1111112111111111
    1111111111111111
    1111111111111111
    1111111111110111
    1111111111122111
    1111111111111111
    1101111111111111
    1121111111111111
    1111111111111111
    1111111111111111
    1111111110011111
    1111111112311111
    1111111111111111
""")
DIRT_TILLED = T("""
    1101110111011101
    1111111111111111
    1111211111121111
    1111111111111111
    2222222222222222
    3323332333233323
    2111211121112111
    1111111111111111
    1101110111011101
    1111111111111111
    1121111112111111
    1111111111111111
    2222222222222222
    3323332333233323
    2111211121112111
    1111111111111111
""")
DIRT_SPROUTS = T("""
    1101110111011101
    1131311111313111
    1113111111131111
    1111111111111111
    2222222222222222
    3323332333233323
    2111211121112111
    1111111111111111
    1101110111011101
    1111113131111313
    1121111311111131
    1111111111111111
    2222222222222222
    3323332333233323
    2111211121112111
    1111111111111111
""")

# ======================================================================== sand (a beach over grass): a fine stipple
SAND_A = T("""
    0000000000000000
    0100010001000100
    0000000000000000
    0000002000000000
    0000000000000000
    0001000100010001
    0000000000000000
    0000000000000000
    0000000000000200
    0100010001000100
    0000000000000000
    0002000000000000
    0000000000000000
    0001000100010001
    0000000000000000
    0000000000000000
""")
SAND_B = T("""
    0000000000000000
    0100010001000100
    0000000000200000
    0000000000000000
    0000000000000000
    0001000100010001
    0000020000000000
    0000000000000000
    0000000000000000
    0100010001000100
    0000000000000000
    0000000000000000
    0000000000000000
    0001000100010001
    0000000000002000
    0000000000000000
""")

# ======================================================================== water (sea or lake over sand)
WATER_A = T("""
    2222222222222222
    2222222222222222
    2220111222222222
    2212222322222222
    2222222222222222
    2222222222211122
    2222222222122232
    2222222222222222
    2222222222222222
    2222221111222222
    2222212222322222
    2222222222222222
    2222222222222222
    2222222222011222
    2222222221222322
    2222222222222222
""")
WATER_B = T("""
    2222222222222222
    2222222222222222
    2222111022222222
    2221222232222222
    2222222222222222
    2222222222111222
    2222222221222322
    2222222222222222
    2222222222222222
    2222222111122222
    2222221222232222
    2222222222222222
    2222222222222222
    2222222221102222
    2222222212223222
    2222222222222222
""")
SHALLOW_A = T("""
    1111111111111111
    1111111111111111
    1100110011111111
    1022002211111111
    1111111111111111
    1111111111111111
    1111111110011001
    1111111102200221
    1111111111111111
    1111111111111111
    1111001100111111
    1110220022111111
    1111111111111111
    1111111111111111
    1111111111001101
    1111111110220022
""")
SHALLOW_B = T("""
    1111111111111111
    1111111111111111
    1110011001111111
    1102200221111111
    1111111111111111
    1111111111111111
    1111111100110011
    1111111022002211
    1111111111111111
    1111111111111111
    1111100110011111
    1111022002211111
    1111111111111111
    1111111111111111
    1111111110011001
    1111111102200221
""")

# ======================================================================== cobblestone (the plaza, over grass)
COBBLE_STONE = T("""
    ..000..
    .00111.
    0011112
    0111112
    1111112
    .11112.
    ..222..
""", 7, 7)
COBBLE_AT = ((0, 0), (8, 0), (4, 8), (12, 8))  # four stones a tile, rows staggered; the last one runs over the edge


def cobble_tile(marks: str | None = None) -> tuple[g.Pic, set]:
    """Rounded stones set in earth: a line of tone 2 round each stone, tone 3 in the gap under it (its shadow), and
    tone 1 earth in the hollows where three stones meet; `marks` (a 16x16 drawing with '.') adds wear to the
    stones. Returns the picture and the set of stone pixels."""
    p = [[1] * 16 for _ in range(16)]
    stones = set()
    for ox, oy in COBBLE_AT:
        for j, row in enumerate(COBBLE_STONE):
            for i, v in enumerate(row):
                if v >= 0:
                    x, y = (ox + i) % 16, (oy + j) % 16
                    p[y][x] = v
                    stones.add((x, y))
    for y in range(16):
        for x in range(16):
            if (x, y) in stones:
                continue
            near = [((x + dx) % 16, (y + dy) % 16) in stones for dx, dy in ((-1, 0), (1, 0), (0, -1), (0, 1))]
            if any(near):
                p[y][x] = 3 if near[2] else 2
    if marks:
        p = g.overlay(p, T(marks))
    return p, stones


COBBLE_A, COBBLE_STONES = cobble_tile()
COBBLE_B, _ = cobble_tile("""
    ................
    ................
    ..........2.....
    ..........12....
    ...........2....
    ................
    ................
    .......1........
    ................
    ................
    ......0.........
    ................
    ................
    ................
    ................
    ................
""")


# ======================================================================== the edge generator
# A family is drawn over a background (dirt, sand and cobble over grass; water over sand). Its border runs K pixels in
# from the tile's edge at the places where tiles meet (columns and rows 0, 7, 8 and 15) and wobbles in between, by
# the profiles below; the outer and inner corners are small masks that meet those depths, so every piece fits every
# neighbour it can have. Each piece is drawn whole from its mask: the background's texture outside, the family's
# inside, and between them a line that is heavier on the north and west sides (they face away from the light).
K = 3
O, L, I = "o", "L", "i"
PROFILE = {
    "n": [3, 3, 2, 2, 3, 3, 4, 3, 3, 4, 4, 3, 3, 2, 3, 3],
    "s": [3, 3, 3, 4, 4, 3, 2, 3, 3, 3, 2, 2, 3, 4, 3, 3],
    "w": [3, 3, 2, 2, 3, 4, 4, 3, 3, 3, 4, 3, 2, 2, 3, 3],
    "e": [3, 3, 4, 4, 3, 3, 2, 3, 3, 2, 2, 3, 3, 4, 3, 3],
}
STRAIGHT = {side: [K] * 16 for side in "nesw"}  # a built edge (the plaza's kerb) runs straight
CORNER_NW = ["oooooooo", "oooooooo", "oooooooo", "ooooooLL", "ooooLLii", "ooooLiii", "oooLiiii", "oooLiiii"]
INNER_NW = ["oooLiiii", "oooLiiii", "ooLiiiii", "LLiiiiii", "iiiiiiii", "iiiiiiii", "iiiiiiii", "iiiiiiii"]
PIECES = ["n", "e", "s", "w", "ne", "se", "sw", "nw", "in_ne", "in_se", "in_sw", "in_nw"]
QUAD = {"nw": (0, 0), "ne": (8, 0), "sw": (0, 8), "se": (8, 8)}


def _mirrors(m: list[str]) -> dict[str, list[str]]:
    """A north-west mask and its three mirrors (a line K pixels from the top mirrors to K from the bottom)."""
    h = [r[::-1] for r in m]
    return {"nw": m, "ne": h, "sw": m[::-1], "se": h[::-1]}


OUTER, INNER = _mirrors(CORNER_NW), _mirrors(INNER_NW)


def side_mask(prof: dict, sides: str) -> list[list[str]]:
    """o (background), L (the border line) or i (the family) for each pixel of a piece bordered along `sides`."""
    m = [[I] * 16 for _ in range(16)]
    for y in range(16):
        for x in range(16):
            v = I
            if "n" in sides:
                d = prof["n"][x]
                v = O if y < d else (L if y == d else v)
            if "s" in sides and v != O:
                d = 15 - prof["s"][x]
                v = O if y > d else (L if y == d else v)
            if "w" in sides and v != O:
                d = prof["w"][y]
                v = O if x < d else (L if x == d and v == I else v)
            if "e" in sides and v != O:
                d = 15 - prof["e"][y]
                v = O if x > d else (L if x == d and v == I else v)
            m[y][x] = v
    return m


def piece_mask(piece: str, prof: dict = PROFILE) -> list[list[str]]:
    """The mask of one of the 12 edge pieces: its sides from the profiles, its corner from the corner masks."""
    if piece.startswith("in_"):
        c = piece[3:]
        m = [[I] * 16 for _ in range(16)]
        qx, qy = QUAD[c]
        for y in range(8):
            for x in range(8):
                m[qy + y][qx + x] = INNER[c][y][x]
        return m
    m = side_mask(prof, piece)
    if len(piece) == 2:
        qx, qy = QUAD[piece]
        for y in range(8):
            for x in range(8):
                m[qy + y][qx + x] = OUTER[piece][y][x]
    return m


def components(p: g.Pic, base: int) -> list[list[tuple[int, int]]]:
    """Groups of touching (8-way) pixels that are not the base tone: the details of a texture."""
    seen, out = set(), []
    for y in range(16):
        for x in range(16):
            if p[y][x] != base and (x, y) not in seen:
                stack, comp = [(x, y)], []
                seen.add((x, y))
                while stack:
                    cx, cy = stack.pop()
                    comp.append((cx, cy))
                    for dx in (-1, 0, 1):
                        for dy in (-1, 0, 1):
                            nx, ny = cx + dx, cy + dy
                            if 0 <= nx < 16 and 0 <= ny < 16 and (nx, ny) not in seen and p[ny][nx] != base:
                                seen.add((nx, ny))
                                stack.append((nx, ny))
                out.append(comp)
    return out


def texture_in(region: set, tex: g.Pic, base: int, keep_off: set) -> dict:
    """The details of `tex` that lie wholly in `region` and do not touch `keep_off`: {(x, y): tone}."""
    near = {(x + dx, y + dy) for x, y in keep_off for dx in (-1, 0, 1) for dy in (-1, 0, 1)}
    out = {}
    for comp in components(tex, base):
        if all(c in region and c not in near for c in comp):
            for x, y in comp:
                out[(x, y)] = tex[y][x]
    return out


def sets_of(mask) -> tuple[set, set, set]:
    o = {(x, y) for y in range(16) for x in range(16) if mask[y][x] == O}
    ln = {(x, y) for y in range(16) for x in range(16) if mask[y][x] == L}
    i = {(x, y) for y in range(16) for x in range(16) if mask[y][x] == I}
    return o, ln, i


def line_sides(mask, ln: set) -> tuple[set, set]:
    """The line pixels facing away from the light (outside above or left of them) and those facing it."""
    heavy, light = set(), set()
    for x, y in ln:
        up = y > 0 and mask[y - 1][x] == O
        left = x > 0 and mask[y][x - 1] == O
        (heavy if up or left else light).add((x, y))
    return heavy, light


TUFT = [(1, 0), (0, 1), (2, 1)]  # a small grass tuft, as in the grass tiles: offsets of its tone-2 pixels
# where tufts of the background's grass may grow along a border (top-left of the tuft); each one is drawn in the
# pieces where it lies wholly on grass, so the grass beside a path or a beach has its texture too
TUFT_SPOTS = [(9, 1), (2, 13), (1, 5), (12, 2), (12, 12), (1, 9)]


def stamp_tufts(p: g.Pic, mask, spots=TUFT_SPOTS, tone: int = 2) -> None:
    """Grass tufts at those of `spots` that lie wholly on the background and do not touch one already drawn."""
    placed: set = set()
    for sx, sy in spots:
        px = [(sx + dx, sy + dy) for dx, dy in TUFT]
        if not all(0 <= x < 16 and 0 <= y < 16 and mask[y][x] == O for x, y in px):
            continue
        if any((x + dx, y + dy) in placed for x, y in px for dx in (-1, 0, 1) for dy in (-1, 0, 1)):
            continue
        for x, y in px:
            p[y][x] = tone
            placed.add((x, y))


def render_edge(mask, outside: g.Pic, out_base: int, inside: g.Pic, in_base: int, style: dict) -> g.Pic:
    """Dirt or sand against grass: the grass's tufts outside, the family's pebbles or grains inside (only those that lie
    wholly clear of the border), the line (style heavy / light) and under a heavy line a shadow (style shade)."""
    o_set, l_set, i_set = sets_of(mask)
    heavy, light = line_sides(mask, l_set)
    shade = set()
    for x, y in heavy:
        if y > 0 and mask[y - 1][x] == O and (x, y + 1) in i_set:
            shade.add((x, y + 1))
        if x > 0 and mask[y][x - 1] == O and (x + 1, y) in i_set:
            shade.add((x + 1, y))
    p = [[in_base] * 16 for _ in range(16)]
    for (x, y) in o_set:
        p[y][x] = out_base
    for (x, y), v in texture_in(o_set, outside, out_base, l_set).items():
        p[y][x] = v
    for (x, y), v in texture_in(i_set - shade, inside, in_base, l_set | shade).items():
        p[y][x] = v
    for x, y in shade:
        if not style.get("shade_dither") or (x + y) % 2 == 0:
            p[y][x] = style["shade"]
    for x, y in heavy:
        p[y][x] = style["heavy"]
    for x, y in light:
        p[y][x] = style["light"]
    stamp_tufts(p, mask)
    return p


def distances(mask, inward: bool, R: int = 5) -> dict:
    """For each pixel of the family (inward) or of the background: (distance to the nearest pixel of the other, dx, dy).
    The mask is carried on past the tile's edge (clamped), which is what the neighbouring piece has there, so bands
    measured from a border meet at every seam."""
    def at(x, y):
        return mask[min(15, max(0, y))][min(15, max(0, x))]
    other = [(x, y) for y in range(-R, 16 + R) for x in range(-R, 16 + R) if (at(x, y) == O) == inward]
    field = {}
    for y in range(16):
        for x in range(16):
            if (mask[y][x] != O) != inward:
                continue
            best = (99.0, 0, 0)
            for ox, oy in other:
                if abs(ox - x) <= R and abs(oy - y) <= R:
                    d = math.hypot(ox - x, oy - y)
                    if d < best[0]:
                        best = (d, ox - x, oy - y)
            field[(x, y)] = best
    return field


def render_shore(mask, outside: g.Pic, out_base: int, inside: g.Pic, in_base: int, style: dict) -> g.Pic:
    """Water against sand: dotted wet sand, a line of foam, a band of shallow water and a dither down into the deep."""
    p = [[out_base] * 16 for _ in range(16)]
    band = set()
    for (x, y), (d, _, _) in distances(mask, inward=False).items():
        if d < 1.5:
            p[y][x] = style["wet"] if (x + y) % 2 == 0 else style["shallow"]
            band.add((x, y))
    for (x, y), (d, _, _) in distances(mask, inward=True).items():
        if d < 1.5:
            p[y][x] = style["foam"]
        elif d < 2.5:
            p[y][x] = style["shallow"]
        elif d < 3.5:
            p[y][x] = style["shallow"] if (x + y) % 2 else in_base
        else:
            p[y][x] = in_base
        if d < 3.5:
            band.add((x, y))
    o_set, l_set, i_set = sets_of(mask)
    for (x, y), v in texture_in(o_set - band, outside, out_base, band).items():
        p[y][x] = v
    for (x, y), v in texture_in((i_set | l_set) - band, inside, in_base, band).items():
        p[y][x] = v
    return p


def render_curb(mask, outside: g.Pic, out_base: int, inside: g.Pic, in_base: int, style: dict) -> g.Pic:
    """The plaza's edge: a dark line, a kerb of long stones (lit where it faces the light, a joint every 8 pixels), a
    line of earth, then the cobbles, the cut ones shaded again as whole stones."""
    o_set, l_set, i_set = sets_of(mask)
    stones = style["stones"]
    field = distances(mask, inward=True)
    p = [[out_base] * 16 for _ in range(16)]
    for (x, y), v in texture_in(o_set, outside, out_base, l_set).items():
        p[y][x] = v
    inner = set()
    for (x, y), (d, dx, dy) in field.items():
        lit = dy < 0 or dx < 0
        horizontal = abs(dy) >= abs(dx)
        if d < 1.5:
            p[y][x] = 3
        elif d < 3.5:
            joint = (x % 8 == 4) if horizontal else (y % 8 == 4)
            if joint:
                p[y][x] = 2
            elif d < 2.5:
                p[y][x] = 0 if lit else 1
            else:
                p[y][x] = 1 if lit else 2
        elif d < 4.5:
            p[y][x] = 2 if lit else 3
            inner.add((x, y))
        else:
            p[y][x] = inside[y][x]
    for (x, y), (d, dx, dy) in field.items():
        if d < 4.5 or (x, y) not in stones:
            continue
        up, dn = (x, y - 1) in inner, (x, y + 1) in inner
        lf, rt = (x - 1, y) in inner, (x + 1, y) in inner
        if (up or dn) and (lf or rt):
            p[y][x] = 2
        elif up:
            p[y][x] = 0
        elif dn:
            p[y][x] = 2
        elif lf and inside[y][x] == 1:
            p[y][x] = 0
        elif rt:
            p[y][x] = 2
    stamp_tufts(p, mask)
    return p


def family(fam: str, plain: list[g.Pic], in_base: int, outside: g.Pic, out_base: int, render, style: dict, bank: int,
           flags: tuple = (), prof: dict = PROFILE) -> dict[str, g.Pic]:
    """Registers <fam>_a, <fam>_b (the plain pictures) and the 12 edge pieces drawn by `render` over `outside`."""
    pics = {f"{fam}_a": plain[0], f"{fam}_b": plain[1]}
    for piece in PIECES:
        pics[f"{fam}_{piece}"] = render(piece_mask(piece, prof), outside, out_base, plain[0], in_base, style)
    for name, p in pics.items():
        meta(name, p, flags=flags, bank=bank)
    return pics


# ======================================================================== things on the ground
BUSH = on(GRASS_A, """
    ................
    .....333..333...
    ...330013300133.
    ..30001120011123
    ..30001120111123
    .300011122111223
    3000111220112223
    3001222200011223
    3122300111111123
    3220011111112223
    .30011111122223.
    .31111111222223.
    ..311112222233..
    ...3322222333...
    .....3333333....
    ......22222.....
""")
WEEDS = on(GRASS_A, """
    ........3.......
    ....3...3.......
    ....3...3...3...
    ....3..13..33...
    .3..13.13.13....
    ..3.13.13113..3.
    .13.13.1313..3..
    ..1313.1313313..
    ..13113131333...
    ..21113111313...
    ..2131311133....
    ..2131331133....
    ...21113133.....
    ....22131322....
    .....222222.....
    ................
""")
ROCK_A = on(GRASS_B, """
    ................
    ......33333.....
    ....332222133...
    ...32212222113..
    ..3221222221113.
    ..3212212222123.
    .30222122212223.
    .30112121111223.
    3011111111112223
    3111111111122223
    3211111111222233
    .32211111222233.
    ..332222222333..
    ...2333333332...
    .....2222222....
    ................
""")
ROCK_B = on(GRASS_C, """
    ................
    ................
    .....333333.....
    ...3300011133...
    ..300011111123..
    .30011111211123.
    .30111111211223.
    3011111112112223
    3111111121122223
    3111111111222223
    3211111112222233
    .32211112222233.
    ..332222222333..
    ...2333333332...
    .....2222222....
    ................
""")
ROCKS_C = on(GRASS_A, """
    ................
    ................
    ...3333333......
    ..300011113.....
    .30011111123....
    .301111111223...
    3011111112223...
    311111112333333.
    3211111230001113
    .322112301111123
    .322222301111223
    ..33333321112223
    .......322222233
    ........3333333.
    .........222222.
    ................
""")
STUMP = on(GRASS_C, """
    ................
    ................
    ................
    .....333333.....
    ...3300000133...
    ..300001111113..
    ..300222111113..
    ..302111121113..
    ..302111112113..
    ..311111111223..
    ..322333333223..
    .31112321232223.
    3011223212322213
    3122223333222213
    .33333....33333.
    ..222222222222..
""")
LOG_H = on(GRASS_B, """
    ................
    ................
    ................
    ..333333333333..
    .30013000000013.
    3022231111111123
    3023231212122123
    3022232221221223
    3100132222222223
    .31133333333333.
    ..333.222222222.
    ................
    ................
    ................
    ................
    ................
""")
LOG_V = on(GRASS_A, """
    ................
    ......3333......
    .....300113.....
    ....30011123....
    ....30112123....
    ....31111223....
    ....30112123....
    ....30111223....
    ....31121123....
    ....30112123....
    ....33333333....
    ....30000113....
    ....30121123....
    ....31211213....
    .....333333.....
    ......22222.....
""")
MUSHROOMS = on(GRASS_C, """
    ................
    ................
    ................
    ....333333......
    ...30100113.....
    ..3010001013....
    ..3111111113....
    ..3222222223....
    ...33300333.....
    .....3003...333.
    .....3003..30013
    .....3013..31113
    ....330133.32223
    ....222222..303.
    .........333033.
    ..........22222.
""")
PEBBLES = on(GRASS_B, """
    ................
    ................
    ................
    ................
    ....333.........
    ...30113........
    ...31123........
    ....3332...333..
    .....22...30113.
    ..........31123.
    ...........3332.
    ....33.....222..
    ...3013.........
    ...3123.........
    ....332.........
    ................
""")
DIRT_LOOSE = on(GRASS_C, """
    ................
    ................
    ................
    ................
    .....111111.....
    ...1121212111...
    ..112121212121..
    ..121232121212..
    ..212121200121..
    ..121212123312..
    ..212121212121..
    ...2121212122...
    ....22222222....
    ................
    ................
    ................
""")
HOLE_DUG = T("""
    0000000000000000
    0000010001000000
    0000101101000000
    0010211222110100
    0012333333331000
    0123222222223100
    0133222222233100
    0133333333333100
    0013333333331000
    0121333333312100
    0002211111220000
    0001001001010000
    0000000000000000
    0001000100010000
    0000000000000000
    0000000000000000
""")
SHELL = on(SAND_A, """
    ................
    ................
    ................
    ................
    ................
    ......333.......
    .....30203......
    ....3020203.....
    ....3202023.....
    .....32023......
    ....3333333.....
    .....22222......
    ................
    ................
    ................
    ................
""")
STARFISH = on(SAND_B, """
    ................
    ................
    .......3........
    ......303.......
    ......313.......
    ..33331013333...
    ...301101113....
    ....3011113.....
    ....3111113.....
    ...311323113....
    ...3123.3213....
    ...333...333....
    ....22....22....
    ................
    ................
    ................
""")
DRIFTWOOD = on(SAND_A, """
    ................
    ................
    ................
    ................
    ................
    ...3333333333...
    ..300000000003..
    .30011211121103.
    301123211112133.
    .31122222222223.
    ..333333333333..
    ...222222222222.
    ................
    ................
    ................
    ................
""")
SAND_ROCKS = on(SAND_B, """
    ................
    ................
    ....33333.......
    ...3000113......
    ..300111123.....
    ..301111123.....
    ..311111223.33..
    ..32112223.3013.
    ...3333333.3112.
    ....222222.3223.
    ............33..
    ............22..
    ................
    ................
    ................
    ................
""")
CRAB_HOLE = on(SAND_A, """
    ................
    ................
    ................
    ................
    .....1.1........
    ...1.......1....
    ......222.......
    ....1.2332.1....
    ......2332......
    ...1...22...1...
    .....1...1......
    ............2.2.
    ..........2.2...
    ........2.2.....
    ................
    ................
""")
SAND_DUG = on(SAND_B, """
    ................
    ................
    ................
    ................
    ................
    .....111111.....
    ...1100000011...
    ..10003003002...
    ..10000330002...
    ..10000330002...
    ..10003003002...
    ...2200000022...
    ....22222222....
    ................
    ................
    ................
""")
WATER_ROCKS = on(WATER_A, """
    ................
    ................
    ................
    ....33333.......
    ...3000113......
    ..300111123.....
    ..301111123.....
    ..311112223.....
    .0322222233.....
    ..0333333310....
    ...000101000....
    ................
    .........333....
    ........30113...
    .......0322230..
    ........00000...
""")


# ======================================================================== registration
def register() -> None:
    for name, p in (("grass_a", GRASS_A), ("grass_b", GRASS_B), ("grass_c", GRASS_C), ("grass_flowers_a", GRASS_FLOWERS_A),
                    ("grass_flowers_b", GRASS_FLOWERS_B), ("grass_tufts", GRASS_TUFTS), ("grass_clover", GRASS_CLOVER)):
        meta(name, p, bank=0)
    meta("bush", BUSH, ("solid", "cut", "becomes=grass_a"), bank=3)
    meta("weeds", WEEDS, ("cut", "becomes=grass_a"), bank=3)
    meta("rock_a", ROCK_A, ("solid",), bank=6)
    meta("rock_b", ROCK_B, ("solid",), bank=6)
    meta("rocks_c", ROCKS_C, ("solid",), bank=6)
    meta("stump", STUMP, ("solid",), bank=4)
    meta("log_h", LOG_H, ("solid",), bank=4)
    meta("log_v", LOG_V, ("solid",), bank=4)
    meta("mushrooms", MUSHROOMS, bank=0)
    meta("pebbles", PEBBLES, bank=0)
    meta("dirt_loose", DIRT_LOOSE, ("dig", "becomes=hole_dug"), bank=1)
    meta("hole_dug", HOLE_DUG, bank=1)
    family("dirt", [DIRT_A, DIRT_B], 1, GRASS_A, 0, render_edge, {"heavy": 3, "light": 2, "shade": 2, "shade_dither": True}, 1)
    meta("dirt_tilled", DIRT_TILLED, bank=1)
    meta("dirt_sprouts", DIRT_SPROUTS, bank=1)
    family("sand", [SAND_A, SAND_B], 0, GRASS_A, 0, render_edge, {"heavy": 2, "light": 2, "shade": 1}, 1)
    meta("shell", SHELL, bank=1)
    meta("starfish", STARFISH, bank=1)
    meta("driftwood", DRIFTWOOD, ("solid",), bank=4)
    meta("sand_rocks", SAND_ROCKS, ("solid",), bank=6)
    meta("crab_hole", CRAB_HOLE, bank=1)
    meta("sand_dug", SAND_DUG, ("dig", "becomes=hole_dug"), bank=1)
    family("water", [WATER_A, WATER_B], 2, SAND_A, 0, render_shore, {"wet": 2, "foam": 0, "shallow": 1}, 2, flags=("water",))
    meta("shallow_a", SHALLOW_A, ("shallow",), bank=2)
    meta("shallow_b", SHALLOW_B, ("shallow",), bank=2)
    meta("water_rocks", WATER_ROCKS, ("water", "solid"), bank=2)
    family("cobble", [COBBLE_A, COBBLE_B], 1, GRASS_A, 0, render_curb, {"line": 3, "stones": COBBLE_STONES}, 6,
           prof=STRAIGHT)
    ART.animate("water", ["water_a", "water_b"], ticks=40)
    ART.animate("shallow", ["shallow_a", "shallow_b"], ticks=40)


register()


# ======================================================================== previews (python3 gen/tiles_terrain.py)
TEST_MAP = [
    "....................",
    ".XXXXXX......XX.....",
    ".XXXXXX......XX.....",
    ".XX..XX......XX.....",
    ".XX..XXXX....XXXXXX.",
    ".XXXXXXXX....XXXXXX.",
    ".XXXXXX.............",
    "..........XXXXXXXX..",
    "..XXXXXX..XXXXXXXX..",
    "..XXXXXX..XX....XX..",
    "..........XX....XX..",
    "..........XXXXXXXX..",
    "..........XXXXXXXX..",
    "....................",
]
SCREENS = {
    "beach": [
        "gbbgggGgggggRgg",
        "ggggfgggddggggg",
        "gGgggggdddgggfg",
        "ggggggdddggggbg",
        "ggpgggdddgggggg",
        "sssssssssssgggg",
        "sssessssssssssg",
        "wwwwwssss*sssDs",
        "wwwwwwwwsssssss",
    ],
    "village": [
        "ggggggcccccccgg",
        "gWgggcccccccccg",
        "ggggccccccccccg",
        "gvggccccccccggg",
        "ggggggggddddddg",
        "gmgguggddttttdg",
        "gggggggddyyyydg",
        "gkgLgngdddddddg",
        "gggggggglggHggg",
    ],
}


def screen_names(screen: list[str]) -> list[list[str]]:
    """Terrain characters to metatile names: g grass, f flowers, G tufts, r rock, b bush, d dirt, s sand, w water,
    c cobble, h shallow. Water counts as sand when the sand is bordered (the beach runs under the sea)."""
    h, w = len(screen), len(screen[0])
    fb = {"g": ["grass_a", "grass_b", "grass_c"], "f": ["grass_flowers_a", "grass_flowers_b"], "G": ["grass_tufts"],
          "r": ["rock_a"], "b": ["bush"], "w": ["water_a"], "s": ["sand_a"], "d": ["dirt_a"], "c": ["cobble_a"],
          "h": ["shallow_a"], "R": ["rock_b"], "k": ["rocks_c"], "u": ["stump"], "W": ["weeds"], "m": ["mushrooms"],
          "p": ["pebbles"], "l": ["log_h"], "L": ["log_v"], "e": ["shell"], "*": ["starfish"], "D": ["driftwood"],
          "x": ["sand_rocks"], "o": ["crab_hole"], "q": ["sand_dug"], "Q": ["water_rocks"], "t": ["dirt_tilled"],
          "y": ["dirt_sprouts"], "n": ["dirt_loose"], "H": ["hole_dug"], "v": ["grass_clover"]}
    base = g.autotile(screen, {}, {}, fb)
    for ch_, fam, over in (("d", "dirt", "tyn"), ("c", "cobble", ""), ("s", "sand", "weo*Dxq"), ("w", "water", "Q")):
        grid = ["".join(ch_ if (c == ch_ or c in over) else "." for c in row) for row in screen]
        names = g.autotile(grid, {ch_: fam}, {fam: [f"{fam}_a", f"{fam}_b"]}, {".": ["-"]})
        for y in range(h):
            for x in range(w):
                if screen[y][x] == ch_:
                    base[y][x] = names[y][x]
    return base


def preview() -> None:
    import palettes
    from PIL import Image, ImageDraw

    metas = ART.metas[SET]
    out = g.HERE / "art"
    out.mkdir(exist_ok=True)

    def both(names_map, scale):
        a = g.scene_image(names_map, metas, palettes.DMG, scale)
        b = g.scene_image(names_map, metas, palettes.POCKET, scale)
        img = Image.new("RGB", (a.width, a.height * 2 + 6), (200, 200, 200))
        img.paste(a, (0, 0))
        img.paste(b, (0, a.height + 6))
        return img

    for label, tones in (("dmg", palettes.DMG), ("pocket", palettes.POCKET)):
        cols, sc, cw, ch = 10, 4, 16 * 4 + 8, 16 * 4 + 18
        rows = (len(MINE) + cols - 1) // cols
        img = Image.new("RGB", (cols * cw + 8, rows * ch + 8), (200, 200, 200))
        d = ImageDraw.Draw(img)
        for i, n in enumerate(MINE):
            x, y = 8 + (i % cols) * cw, 8 + (i // cols) * ch
            img.paste(g.to_image(metas[n].ground, tones, sc), (x, y))
            d.text((x, y + 16 * sc + 1), n[:12], fill=(0, 0, 0))
        img.save(out / f"terrain_tiles_{label}.png")

    for fam, ch_, back in (("dirt", "d", "g"), ("sand", "s", "g"), ("cobble", "c", "g"), ("water", "w", "s")):
        grid = [r.replace("X", ch_).replace(".", back) for r in TEST_MAP]
        if back == "s":  # water lies in sand, and the sand in grass
            grid = ["s" + r + "s" for r in grid]
            grid = ["s" * len(grid[0])] + grid + ["s" * len(grid[0])]
            grid = ["g" + r + "g" for r in grid]
            grid = ["g" * len(grid[0])] + grid + ["g" * len(grid[0])]
        names_map = screen_names(grid)
        used = {n for r in names_map for n in r}
        miss = [f"{fam}_{p}" for p in PIECES if f"{fam}_{p}" not in used]
        if miss:
            print(fam, "pieces not on the test map:", miss)
        both(names_map, 3).save(out / f"terrain_seams_{fam}.png")

    for key, scr in SCREENS.items():
        names_map = screen_names(scr)
        both(names_map, 3).save(out / f"terrain_screen_{key}.png")
        both(names_map, 1).save(out / f"terrain_screen_{key}_1x.png")


if __name__ == "__main__":
    preview()
