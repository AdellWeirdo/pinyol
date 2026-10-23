"""The insides of the houses of Isla Cerezo (tileset "interior"): floors, walls, the front door and the furniture.

Rooms are one screen, 15x9 cells, seen as a box from above (as Link's Awakening's houses): every wall has a thin dark top
along the screen's edge and, inside it, its inner face. The back wall (row 0) is lit plaster over a rail and a dark
wainscot; the side walls (columns 0 and 14) and the front wall (row 8) are the same wall in shade, turned (the sides are
the back wall transposed, the front is it flipped), so the corners meet on a diagonal crease. The front wall shows its
thin top on the screen's bottom edge; `idoor` is a doorway in it with a mat on the threshold and daylight beyond.

Names: ifloor_* (wood a/b/c, stone a/b, tile a/b), iwall_n_a / iwall_n_b (b has a timber post) and the back-wall
features iwall_n_window / _clock / _map / _shelf, iwall_w / _e / _s, the corners iwall_nw / ne / sw / se, idoor.
Furniture: ibed_tl/tr/bl/br, itable_l/r, ichair_down/up/left/right, ishelf_l/r, ibookshelf_a/b, istove,
icounter_l/m/r, ishop_shelf_a/b, icupboard, ibarrel, icrate, iplant_a/b, idesk_l/r, imap_table, iladder,
ichest_closed/open, irug_tl..br (9-slice, the edges and centre repeat), ifireplace_l/r (+ _b frames, animations "fire"
and "fire_r"), itoys, iquilt_line (line and quilt on the front layer).

Floors under furniture: a map cell holds one metatile, so each free-standing piece carries its floor. The plain name
stands on wood (the counter and the stove on the tile chequer, their natural place); the same piece on the other floors
is `<name>_stone`, `<name>_tile` (or `<name>_wood`). Pieces that fill their cell (shelves, bookshelves, shop shelves,
cupboard, fireplace) and the rug (its fringe covers its rows) go on any floor. Furniture is drawn as see-through
sprites and composited by `on_floor`, which also casts a shadow one tone darker towards the bottom right.

Tones: floors 0/1 with grain in 1/2, walls 1 with 2/3 detail, furniture outlined in 3, lit from the top left.
`python3 gen/tiles_interior.py` writes previews: art/interior_tiles_*.png and furnished rooms art/interior_room_*.png.
"""
from __future__ import annotations

import sys
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent))
import gbart as g  # noqa: E402
from gbart import ART  # noqa: E402

SET = "interior"


def T(s: str, w: int = 16, h: int = 16) -> g.Pic:
    """Text rows, indented freely, to a w x h picture (a row of the wrong length is named)."""
    rows = [ln.strip() for ln in s.strip("\n").split("\n")]
    bad = [(i, len(r)) for i, r in enumerate(rows) if len(r) != w]
    if bad or len(rows) != h:
        raise ValueError(f"picture of {len(rows)} rows, rows of the wrong length (row, length): {bad}")
    return g.pic(rows, w, h)


def R(rows: list[str], w: int, h: int) -> g.Pic:
    """Rows built in code (repetitions), checked."""
    return T("\n".join(rows), w, h)


def transpose(p: g.Pic) -> g.Pic:
    return [list(r) for r in zip(*p)]


def split(a: g.Pic, b: g.Pic, take_a) -> g.Pic:
    return [[a[y][x] if take_a(x, y) else b[y][x] for x in range(16)] for y in range(16)]


def cells(p: g.Pic) -> list[list[g.Pic]]:
    """A big picture cut into rows of 16x16 cells."""
    return [[g.crop(p, x, y, 16, 16) for x in range(0, len(p[0]), 16)] for y in range(0, len(p), 16)]


def tiled(floor: g.Pic, cw: int, ch: int) -> g.Pic:
    return g.paste_rows(*[g.side_by_side(*[floor] * cw) for _ in range(ch)])


def darker(v: int) -> int:
    return min(v + 1, 2) if v < 2 else v


def on_floor(floor: g.Pic, sprite: g.Pic, dx: int = 1, dy: int = 1) -> g.Pic:
    """A sprite (with see-through) standing on a floor, casting its shadow dx, dy towards the bottom right: the floor
    under the shadow is one tone darker (so the planks or joints still show through it). `floor` is tiled to fit."""
    h, w = len(sprite), len(sprite[0])
    base = tiled(floor, w // 16, h // 16)
    for y in range(h):
        for x in range(w):
            sx, sy = x - dx, y - dy
            if sprite[y][x] < 0 and 0 <= sx < w and 0 <= sy < h and sprite[sy][sx] >= 0:
                base[y][x] = darker(base[y][x])
    return g.overlay(base, sprite)


# ======================================================================== floors
WOOD_A = T("""
    0000000000000000
    0000000000000000
    0000000000000000
    1111111111111111
    0000000000000000
    0000000000000000
    0000000000000000
    1111111111111111
    0000000000010000
    0000000000010000
    0000000000010000
    1111111111111111
    0000000000000000
    0000000000000000
    0000000000000000
    1111111111111111
""")
WOOD_B = T("""
    0000000000000000
    0000000000000000
    0000000000000000
    1111111111111111
    0000010000000000
    0000010000000000
    0000010000000000
    1111111111111111
    0000000000000000
    0000000000000000
    0000000000000000
    1111111111111111
    0000000000000000
    0000000000000000
    0000000000000000
    1111111111111111
""")
WOOD_C = T("""
    0000000000000000
    0000000000000000
    0000000000000000
    1111111111111111
    0000000000000000
    0000000000000000
    0000000000000000
    1111111111111111
    0000000000000000
    0000000000000000
    0000000000000000
    1111111111111111
    0000000001000000
    0000000001000000
    0000000001000000
    1111111111111111
""")
STONE_A = T("""
    1000000000000002
    0000000000000002
    0000000000000002
    0000000000000002
    0000000010000002
    0000000000000002
    0000000000000002
    0000000000000002
    0000000000000012
    0000000000000002
    0000000000000002
    0010000000000002
    0000000000000002
    0000000000000012
    0000000000001112
    2222222222222222
""")
STONE_B = T("""
    1000000210000002
    0000000200000002
    0000000200000002
    0000000200000002
    0000000200000002
    0000000200000002
    0000001200000002
    2222222222222222
    1000000000000002
    0000000000010002
    0000000000000002
    0000000000000002
    0000000000000002
    0000000000000002
    0000000000001112
    2222222222222222
""")
TILE_A = T("""
    0000000011111111
    0000000011111111
    0000000011111111
    0000000011111111
    0000000011111111
    0000000011111111
    0000000011111111
    0000000011111111
    1111111100000000
    1111111100000000
    1111111100000000
    1111111100000000
    1111111100000000
    1111111100000000
    1111111100000000
    1111111100000000
""")
TILE_B = TILE_A

# ======================================================================== walls
WALL_N = T("""
    3333333333333333
    2222222222222222
    3333333333333333
    2121212121212121
    1111111111111111
    1111111111111111
    1111111111111111
    1111111111111111
    1111111111111111
    0000000000000000
    3333333333333333
    2122212221222122
    2122212221222122
    2122212221222122
    2122212221222122
    3333333333333333
""")
WALL_N_B = T("""
    3333333333333333
    2222222222222222
    3333333333333333
    2121212332121212
    1111111312111111
    1111111312111111
    1111111312111111
    1111111312111111
    1111111312111111
    0000000302000000
    3333333333333333
    2122212321222122
    2122212321222122
    2122212321222122
    2122212321222122
    3333333333333333
""")
WALL_SHADE = T("""
    3333333333333333
    2222222222222222
    3333333333333333
    3232323232323232
    2222222222222222
    2222222222222222
    2222222222222222
    2222222222222222
    2222222222222222
    1111111111111111
    3333333333333333
    3233323332333233
    3233323332333233
    3233323332333233
    3233323332333233
    3333333333333333
""")
WALL_W = transpose(WALL_SHADE)
WALL_E = g.flip_h(WALL_W)
WALL_S = g.flip_v(WALL_SHADE)


def corners():
    nw = split(WALL_N, WALL_W, lambda x, y: x >= y)
    ne = split(WALL_N, WALL_E, lambda x, y: x <= 15 - y)
    sw = split(WALL_S, WALL_W, lambda x, y: x >= 15 - y)
    se = split(WALL_S, WALL_E, lambda x, y: x <= y)
    for i in range(3, 16):
        nw[i][i] = ne[i][15 - i] = sw[15 - i][i] = se[15 - i][15 - i] = 3
    return nw, ne, sw, se


WALL_WINDOW = T("""
    3333333333333333
    2222222222222222
    3333333333333333
    2333333333333331
    1312233333322131
    1312200220022131
    1312000220002131
    1300300220030031
    1320300220030231
    0312200220022130
    3312233333322133
    2300000000000032
    2322222222222232
    2133333333333322
    2122212221222122
    3333333333333333
""")
WALL_CLOCK = T("""
    3333333333333333
    2222222222222222
    3333333333333333
    2121233333121212
    1111300200311111
    1113000300031111
    1113000300031111
    1113000333031111
    1113000000131111
    0003000001130000
    3333300111333333
    2122233333222122
    2122212321222122
    2122212321222122
    2122213031222122
    3333333333333333
""")
WALL_MAP = T("""
    3333333333333333
    2222222222222222
    3333333333333333
    2121212121212121
    1133033333303311
    1130000000000311
    1130000222000311
    1130002232200311
    1130022333220311
    0030222222220300
    3330222202220333
    2130022222200322
    2130002202200322
    2133333333333322
    2122212221222122
    3333333333333333
""")
WALL_SHELF = T("""
    3333333333333333
    2222222222222222
    3333333333333333
    2121212121212121
    1133111111111111
    1322311113311111
    1300031130031131
    1300031300003303
    1322231300013303
    3322233122233223
    3000000000000003
    3222222222222223
    2133222222222332
    2122312221223122
    2122232221232122
    3333333333333333
""")
# the front door: the front wall with a doorway, a mat on the threshold and daylight beyond the step
DOOR = T("""
    3332222222222333
    3232101010102333
    3232010101012333
    3232101010102333
    3232222222222333
    3330101010101333
    1130000000000311
    2232222222222322
    2230000000000322
    2230000002000322
    2230000020200322
    2230000000000322
    3233333333333332
    3333333333333333
    2222222222222222
    3333333333333333
""")

# ======================================================================== furniture (see-through sprites)
BARREL = T("""
    ................
    ....33333333....
    ..332222222233..
    .32200000011223.
    .32011111111123.
    .33222222222233.
    .31001211121223.
    .33333333333333.
    .31001211121223.
    .31001211121223.
    .31001211121223.
    .33333333333333.
    .31001211121223.
    ..311121112123..
    ...3333333333...
    ................
""")
CRATE = T("""
    ................
    .33333333333333.
    .30000000000003.
    .31111111111113.
    .30000000000003.
    .33333333333333.
    .32222222222223.
    .32111111112223.
    .32111111221123.
    .32111122111123.
    .32112211111123.
    .32221111111123.
    .32222222222223.
    .33333333333333.
    ................
    ................
""")
PLANT_A = T("""
    ................
    .....333.333....
    ....300130113...
    ...30011211123..
    ..3001111211223.
    ..3011211112223.
    ..3111112122223.
    ...31221222223..
    ....332222233...
    ....33333333....
    ....30000013....
    ....32222223....
    .....311223.....
    .....312223.....
    ......3333......
    ................
""")
PLANT_B = T("""
    ........3.......
    .......303......
    ..3....313...3..
    .303...313..303.
    .3133..313.3313.
    ..3133.313.313..
    ...313.313313...
    ...3133131313...
    ....33133133....
    ....33333333....
    ....30000013....
    ....32222223....
    .....311223.....
    .....312223.....
    ......3333......
    ................
""")
CHEST_C = T("""
    ................
    ................
    ...3333333333...
    ..300000000003..
    ..301111111113..
    ..312111111223..
    ..333332233333..
    ..321133003123..
    ..321113003123..
    ..321113333123..
    ..321111111123..
    ..322222222223..
    ..333333333333..
    ................
    ................
    ................
""")
CHEST_O = T("""
    ................
    .33333333333333.
    .32111111111123.
    ..322222222223..
    ..321111111123..
    ..333333333333..
    ..323333333323..
    ..300000000003..
    ..321113333123..
    ..321113003123..
    ..321113333123..
    ..321111111123..
    ..322222222223..
    ..333333333333..
    ................
    ................
""")
CHAIR_DOWN = T("""
    ................
    ....33333333....
    ....30000003....
    ....32111123....
    ....33333333....
    ....32.33.23....
    ....32.33.23....
    ...3333333333...
    ...3000000003...
    ...3111111113...
    ...3222222223...
    ...3333333333...
    ...32......23...
    ...32......23...
    ...33......33...
    ................
""")
CHAIR_UP = T("""
    ................
    ....33333333....
    ....30000003....
    ....32222223....
    ....33333333....
    ....32133123....
    ....32133123....
    ...3332332333...
    ...3333333333...
    ....32....23....
    ....32....23....
    ....32....23....
    ....33....33....
    ................
    ................
    ................
""")
CHAIR_RIGHT = T("""
    ................
    ....33..........
    ....303.........
    ....313.........
    ....313.........
    ....313.........
    ....3133333333..
    ....3100000003..
    ....3111111113..
    ....3222222223..
    ....3333333333..
    ....323....323..
    ....323....323..
    ....333....333..
    ................
    ................
""")

BOWL = T("""
    ....33...
    ..3..3.3.
    .03.03.03
    .33.33.33
    333333333
    300000013
    .3000113.
    ..33333..
""", 9, 8)


def _table() -> g.Pic:
    r = ["." * 32, "." * 32, "." + "3" * 30 + ".", ".3" + "0" * 28 + "3.", ".3" + "0" * 28 + "3.",
         ".3" + "1" * 28 + "3.", ".3" + "0" * 28 + "3.", ".3" + "0" * 28 + "3.", ".3" + "1" * 27 + "23.",
         "." + "3" * 30 + ".", ".3" + "2" * 28 + "3.", "." + "3" * 30 + ".",
         "..32" + "." * 24 + "23..", "..32" + "." * 24 + "23..", "..33" + "." * 24 + "33..", "." * 32]
    return g.overlay(R(r, 32, 16), BOWL, 4, 0)


TABLE = _table()


def _bed() -> g.Pic:
    post = "3123"
    r = [".33." + "." * 24 + ".33.", "3003" + "3" * 24 + "3003", post + "0" * 24 + post,
         post + "2" * 6 + "3" + "2" * 10 + "3" + "2" * 6 + post, post + "2" * 6 + "3" + "2" * 10 + "3" + "2" * 6 + post,
         post + "2" * 24 + post, post + "3" * 24 + post,
         post + "3" + "000" + "3" * 16 + "000" + "3" + post,
         post + "3" + "00" + "3" + "0" * 16 + "3" + "00" + "3" + post,
         post + "3" + "00" + "3" + "0" * 7 + "11" + "0" * 7 + "3" + "00" + "3" + post,
         post + "3" + "00" + "3" + "1" * 16 + "3" + "00" + "3" + post,
         post + "3" + "000" + "3" * 16 + "000" + "3" + post,
         post + "3" + "0" * 22 + "3" + post, post + "3" + "1" * 22 + "3" + post, post + "3" * 24 + post]
    for y in range(11):
        line = "".join("2" if x % 6 == 5 or y % 4 == 3 else ("0" if (x // 6 + y // 4) % 2 == 0 else "1") for x in range(22))
        r.append(post + "3" + line + "3" + post)
    r += [post + "3" + "2" * 22 + "3" + post, "3" * 32, "3123" + "0" * 24 + "3123", "3223" + "2" * 24 + "3223",
          "3" * 32, ".33." + "." * 24 + ".33."]
    return R(r, 32, 32)


BED = _bed()

BAND = {0: "2", 1: "3", 2: "0"}


def books(spec: list[tuple], h: int = 4) -> list[str]:
    """Rows of book spines standing on a shelf, h rows tall: each book (width, tone, height, band row or None);
    tone 3 is a gap showing the dark back of the shelf. A band is a label across the spine."""
    rows = [""] * h
    for w, tone, bh, band in spec:
        for i in range(h):
            if i < h - bh or tone == 3:
                ch = "3"
            elif band is not None and i == band:
                ch = BAND[tone]
            else:
                ch = str(tone)
            rows[i] += ch * w
    return rows


POTS = ["3223" + "3" + "311113" + "3" + "323" + "3" + "333333" + "3" + "3113" + "3",
        "0001" + "3" + "001112" + "3" + "001" + "3" + "311113" + "3" + "0001" + "3",
        "0221" + "3" + "011122" + "3" + "021" + "3" + "011122" + "3" + "0001" + "3",
        "0111" + "3" + "311223" + "3" + "011" + "3" + "311223" + "3" + "1111" + "3"]


def _shelf() -> g.Pic:
    """The tall shelf, two cells: books above, pots and jars in the middle, baskets below."""
    tier1 = books([(2, 0, 4, 1), (2, 2, 3, None), (1, 3, 4, None), (2, 1, 4, 2), (2, 0, 3, None), (2, 2, 4, 1),
                   (1, 1, 4, None), (1, 3, 4, None), (2, 0, 4, 2), (2, 2, 3, None), (2, 1, 4, 1), (1, 0, 4, None),
                   (2, 2, 4, 2), (1, 3, 4, None), (2, 0, 3, None), (3, 1, 4, 1)])
    r = ["3" * 32, "3" + "0" * 29 + "13", "3" + "2" * 30 + "3"]
    r += ["31" + t + "23" for t in tier1]
    r += ["31" + "0" * 28 + "23"]
    r += ["31" + t + "23" for t in POTS]
    r += ["31" + "0" * 28 + "23"]
    r += ["31" + ("3121212123" * 3)[:28] + "23", "31" + ("3212121213" * 3)[:28] + "23"]
    r += ["3" * 32]
    return R(r, 32, 16)


SHELF = _shelf()


def _bookshelf(tier1: list[str], tier2: list[str]) -> g.Pic:
    """A one-cell bookcase: a lit top, two tiers, a cupboard with two doors below."""
    r = ["3" * 16, "3" + "0" * 13 + "13", "3" + "2" * 14 + "3"]
    r += ["31" + t + "23" for t in tier1]
    r += ["31" + "0" * 12 + "23"]
    r += ["31" + t + "23" for t in tier2]
    r += ["31" + "0" * 12 + "23", "3111111331111123", "3122202332022223", "3" * 16]
    return R(r, 16, 16)


BOOKSHELF_A = _bookshelf(books([(2, 0, 4, 1), (1, 3, 4, None), (2, 2, 4, None), (2, 1, 3, 1), (1, 0, 4, None), (2, 2, 4, 2), (2, 0, 3, None)]),
                         books([(2, 1, 4, 2), (2, 0, 4, 1), (1, 2, 3, None), (1, 3, 4, None), (2, 2, 4, 1), (2, 0, 4, None), (2, 1, 3, None)]))
BOOKSHELF_B = _bookshelf(books([(2, 2, 4, 1), (2, 0, 3, None), (1, 1, 4, None), (2, 0, 4, 2), (1, 3, 4, None), (2, 1, 4, 1), (2, 2, 3, None)]),
                         ["333333033333", "333333133113", "000013013001", "222223013011"])

STOVE = T("""
    ..........3123..
    ....33....3123..
    ...3333...3123..
    ..300013..3123..
    ..321123..3123..
    ..322223.333333.
    .33333333333333.
    .32222223311323.
    .33333333333333.
    .31333333233323.
    .31300003231323.
    .31322223231323.
    .31333333233323.
    .33333333333333.
    .33..........33.
    ................
""")

SCALES = T("""
    ......33......
    ..3333333333..
    ..3...33...3..
    ..3...33...3..
    30003.33.30003
    .333..33..333.
    .....3223.....
    ....322223....
""", 14, 8)
TILL = T("""
    ...33333...
    ...30003...
    ...33333...
    .333333333.
    .302020203.
    .320202023.
    .333333333.
    .311131113.
    .333333333.
""", 11, 9)
BOTTLES = T("""
    ..3.....3..
    .303...303.
    .303...303.
    30003.30003
    32223.32223
    30203.30203
    32223.32223
    .333...333.
""", 11, 8)


def _counter() -> g.Pic:
    r = ["." * 48] * 5 + ["3" * 48, "3" + "0" * 46 + "3", "3" + "1" * 45 + "23", "3" * 48]
    r += ["3" + ("1222" * 12)[:46] + "3"] * 6 + ["3" * 48]
    p = R(r, 48, 16)
    p = g.overlay(p, SCALES, 1, 0)
    p = g.overlay(p, BOTTLES, 18, 0)
    return g.overlay(p, TILL, 35, 0)


COUNTER = _counter()

def _shop_shelf(tier1: list[str], tier2: list[str], bottom: list[str]) -> g.Pic:
    r = ["3" * 16, "3" + "0" * 13 + "13", "3" + "2" * 14 + "3"]
    r += ["31" + t + "23" for t in tier1] + ["31" + "0" * 12 + "23"]
    r += ["31" + t + "23" for t in tier2] + ["31" + "0" * 12 + "23"]
    r += ["31" + t + "23" for t in bottom] + ["3" * 16]
    return R(r, 16, 16)


SHOP_SHELF_A = _shop_shelf(  # bottles of cherry juice, baskets of cherries, sacks of pits
    ["322" * 4, "332" * 4, "002" * 4, "332" * 4],
    ["33233" + "2" + "33233" + "2", "33333" + "2" + "33333" + "2", "00000" + "2" + "00000" + "2", "10101" + "2" + "10101" + "2"],
    ["2332" * 3, "3003" * 3])
SHOP_SHELF_B = _shop_shelf(  # oil lamps, jars of jam, folded cloth
    ["2022" * 3, "0002" * 3, "3332" * 3, "2322" * 3],
    ["3332" * 3, "0002" * 3, "3332" * 3, "1112" * 3],
    ["011101110111", "322232223222"])
CUPBOARD = T("""
    3333333333333333
    3000000000000013
    3222222222222223
    3223332222333223
    3230003223000323
    3230203223020323
    3223332222333223
    3333333333333333
    3000000000000013
    3333333333333333
    3111111331111123
    3122221331222123
    3122321331232123
    3122221331222123
    3222222332222223
    3333333333333333
""")
PAPERS = T("""
    ..3333333
    .33000003
    303022203
    303000003
    303022003
    313333333
    3333333..
""", 9, 7)
INKWELL = T("""
    .....3.
    ....303
    ...303.
    ..333..
    .31333.
    3123333
    3223333
    .33333.
""", 7, 8)


def _desk() -> g.Pic:
    drawer_top, drawer_knob = "1" * 8, "22200222"
    r = ["." * 32] * 5 + ["." + "3" * 30 + ".", ".3" + "0" * 28 + "3.", ".3" + "1" * 27 + "23.", "." + "3" * 30 + "."]
    r += [".3" + drawer_top + "3" + "3" * 10 + "3" + drawer_top + "3.",
          ".3" + drawer_knob + "3" + "3" * 10 + "3" + drawer_knob + "3.",
          ".3" + "3" * 8 + "3" + "3" * 10 + "3" + "3" * 8 + "3.",
          ".3" + drawer_top + "3" + "3" * 10 + "3" + drawer_top + "3.",
          ".3" + drawer_knob + "3" + "3" * 10 + "3" + drawer_knob + "3.",
          "." + "3" * 30 + ".", ".33" + "." * 26 + "33."]
    p = R(r, 32, 16)
    p = g.overlay(p, PAPERS, 4, 1)
    return g.overlay(p, INKWELL, 22, 0)


DESK = _desk()

MAP_TABLE = T("""
    ................
    ................
    ................
    .33..........33.
    3013333333333123
    3013000000003123
    3013002222003123
    3013022322203123
    3013002220203123
    3013000000003123
    3333333333333333
    3222222222222223
    3333333333333333
    .32..........23.
    .33..........33.
    ................
""")
LADDER = T("""
    ................
    ....33....33....
    ...3013..3013...
    .33303333330333.
    .32313333331323.
    .3231111111 1323.
    .32313333331323.
    .32313333331323.
    .32312222221323.
    .32313333331323.
    .32313333331323.
    .32322222222323.
    .32333333333323.
    .33333333333333.
    ................
    ................
""".replace("1 1", "11"))
BALL = T("""
    ..3333..
    .300223.
    30002223
    30002223
    30012223
    31112223
    .311223.
    ..3333..
""", 8, 8)
BOAT = T("""
    ......3.
    ....303.
    ...3003.
    ..30003.
    .300003.
    33333333
    32222223
    .322223.
    ..3333..
""", 8, 9)
BLOCK = T("""
    333333
    300003
    322223
    311113
    313113
    333333
""", 6, 6)
TOYS = g.overlay(g.overlay(g.overlay(g.blank(16, 16), BALL, 0, 1), BOAT, 8, 5), BLOCK, 2, 9)

def _quilt() -> g.Pic:
    """The washing line (front layer): a rope across the cell and a patchwork quilt pegged to it."""
    r = ["." * 16, "....3......3....", "3" * 16, "..3" + "3" * 10 + "3.."]
    for y in range(9):
        line = "".join("2" if x % 4 == 3 or y % 4 == 3 else ("0" if (x // 4 + y // 4) % 2 == 0 else "1") for x in range(10))
        r.append("..3" + line + "3..")
    r += ["..3" + "3" * 10 + "3..", "." * 16, "." * 16]
    return R(r, 16, 16)


QUILT = _quilt()
QUILT_SHADE = T("""
    ................
    ................
    ................
    ................
    ................
    ................
    ................
    ................
    ................
    ................
    ................
    ................
    ................
    ....21212121....
    ...1212121212...
    ................
""")


def _rug_px(X: int, Y: int, W: int, H: int) -> int:
    """One pixel of a woven rug W x H pixels (fringe on the short ends top and bottom): -1 where the floor shows."""
    if Y < 3 or Y >= H - 3:  # the fringe: light strands with dark gaps between, the knots where it is sewn on
        o = Y if Y < 3 else H - 1 - Y
        if o == 2:
            return 2
        return (0 if o == 0 else 1) if X % 2 == 0 else 2
    yy = Y - 3
    hh = H - 6
    if X == 0 or X == W - 1 or yy == 0 or yy == hh - 1:
        return 3
    d = min(X, W - 1 - X, yy, hh - 1 - yy)
    if d <= 4:  # the border band, a zigzag of light thread on dark
        along = X if d in (yy, hh - 1 - yy) else Y
        k = d - 1
        if k == 0 or k == 3:
            return 2
        return 0 if (along + k) % 4 == 0 or (along - k) % 4 == 0 else 2
    if d == 5:
        return 3
    u, v = (X - 6) % 8, (yy - 6) % 8
    m = abs(u - 4) + abs(v - 4)
    if m == 0:
        return 2
    if m == 3:
        return 0
    return 1


def _rug() -> g.Pic:
    return [[_rug_px(x, y, 48, 48) for x in range(48)] for y in range(48)]


RUG = _rug()


def _fireplace(frame: int) -> g.Pic:
    stones = ["3101001", "3122213", "3333333", "3100133", "3122133", "3333333", "3101001", "3122213", "3333333"]
    r = ["3" * 32, "3" + "0" * 29 + "13", "3" + "2" * 30 + "3", "3" * 32]
    fire = [
        ["333333333333333333", "333333330333333333", "333333301333033333", "333330300133013333",
         "333310100013013333", "333310000001113333", "333311000000113333", "332221111111222333",
         "322222232222322223"],
        ["333333333333333333", "333303333333333333", "333303333330133333", "333301330300133333",
         "333101300010113333", "333110000001013333", "333311000000113333", "332221111111222333",
         "322232222222232223"],
][frame]
    for i in range(9):
        r.append(stones[i] + fire[i] + stones[i][::-1])
    r += ["3" * 32, "3" + "0" * 30 + "3", "3" * 32]
    return R(r, 32, 16)


FIREPLACE = _fireplace(0)
FIREPLACE_B = _fireplace(1)

# ======================================================================== registration
WOOD = WOOD_A  # what the furniture stands on unless said otherwise


def register() -> None:
    m = ART.meta
    for name, p in (("ifloor_wood_a", WOOD_A), ("ifloor_wood_b", WOOD_B), ("ifloor_wood_c", WOOD_C),
                    ("ifloor_stone_a", STONE_A), ("ifloor_stone_b", STONE_B), ("ifloor_tile_a", TILE_A),
                    ("ifloor_tile_b", TILE_B)):
        m(SET, name, p, bank=4)
    solid = ("solid",)
    for name, p in (("iwall_n_a", WALL_N), ("iwall_n_b", WALL_N_B), ("iwall_n_window", WALL_WINDOW),
                    ("iwall_n_clock", WALL_CLOCK), ("iwall_n_map", WALL_MAP), ("iwall_n_shelf", WALL_SHELF),
                    ("iwall_w", WALL_W), ("iwall_e", WALL_E), ("iwall_s", WALL_S)):
        m(SET, name, p, flags=solid, bank=4)
    for name, p in zip(("iwall_nw", "iwall_ne", "iwall_sw", "iwall_se"), corners()):
        m(SET, name, p, flags=solid, bank=4)
    m(SET, "idoor", DOOR, flags=("door",), bank=4)

    floors = {"wood": WOOD, "stone": STONE_A, "tile": TILE_A}

    def put(name, sprite, flags=(), bank=4, floor="wood"):
        for fname, fl in floors.items():
            m(SET, name if fname == floor else f"{name}_{fname}", on_floor(fl, sprite), flags=flags, bank=bank)

    def put_big(names, sprite, flags, bank=4, floor="wood", shadow=True):
        for fname, fl in floors.items():
            if not shadow and fname != floor:
                continue
            p = on_floor(fl, sprite) if shadow else g.overlay(tiled(fl, len(sprite[0]) // 16, len(sprite) // 16), sprite)
            for row_names, row_pics in zip(names, cells(p)):
                for n, cp in zip(row_names, row_pics):
                    m(SET, n if fname == floor else f"{n}_{fname}", cp, flags=flags.get(n, flags.get("*", ())), bank=bank)

    put_big([["ibed_tl", "ibed_tr"], ["ibed_bl", "ibed_br"]], BED, {"*": solid, "ibed_bl": ("solid", "bed")}, bank=5)
    put_big([["itable_l", "itable_r"]], TABLE, {"*": solid})
    put("ichair_down", CHAIR_DOWN)
    put("ichair_up", CHAIR_UP)
    put("ichair_left", g.flip_h(CHAIR_RIGHT))
    put("ichair_right", CHAIR_RIGHT)
    put_big([["ishelf_l", "ishelf_r"]], SHELF, {"*": solid})
    m(SET, "ibookshelf_a", BOOKSHELF_A, flags=solid, bank=4)
    m(SET, "ibookshelf_b", BOOKSHELF_B, flags=solid, bank=4)
    put("istove", STOVE, solid, floor="tile")
    put_big([["icounter_l", "icounter_m", "icounter_r"]], COUNTER, {"*": solid}, floor="tile")
    m(SET, "ishop_shelf_a", SHOP_SHELF_A, flags=solid, bank=4)
    m(SET, "ishop_shelf_b", SHOP_SHELF_B, flags=solid, bank=4)
    m(SET, "icupboard", CUPBOARD, flags=solid, bank=4)
    put("ibarrel", BARREL, solid)
    put("icrate", CRATE, solid)
    put("iplant_a", PLANT_A, solid, bank=3)
    put("iplant_b", PLANT_B, solid, bank=3)
    put_big([["idesk_l", "idesk_r"]], DESK, {"*": solid})
    put("imap_table", MAP_TABLE, solid)
    put("iladder", LADDER, ("door",))
    put("ichest_closed", CHEST_C, ("solid", "chest"))
    put("ichest_open", CHEST_O, solid)
    put_big([["irug_tl", "irug_t", "irug_tr"], ["irug_l", "irug_c", "irug_r"], ["irug_bl", "irug_b", "irug_br"]],
            RUG, {}, shadow=False)
    m(SET, "ifireplace_l", g.crop(FIREPLACE, 0, 0, 16, 16), flags=solid, bank=6)
    m(SET, "ifireplace_r", g.crop(FIREPLACE, 16, 0, 16, 16), flags=solid, bank=6)
    m(SET, "ifireplace_l_b", g.crop(FIREPLACE_B, 0, 0, 16, 16), flags=solid, bank=6)
    m(SET, "ifireplace_r_b", g.crop(FIREPLACE_B, 16, 0, 16, 16), flags=solid, bank=6)
    ART.animate("fire", ["ifireplace_l", "ifireplace_l_b"], 14)
    ART.animate("fire_r", ["ifireplace_r", "ifireplace_r_b"], 14)
    put("itoys", TOYS, bank=7)
    m(SET, "iquilt_line", g.overlay(WOOD, [[darker(WOOD[y][x]) if QUILT_SHADE[y][x] == 2 else -1 for x in range(16)] for y in range(16)]), front=QUILT, bank=4, front_bank=5)


register()


# ======================================================================== previews (python3 gen/tiles_interior.py)
def hero_pics():
    try:
        import chars
        return {"down": chars.DOWN_0, "up": chars.UP_0, "side": chars.SIDE_0}
    except Exception:  # the hero's module is someone else's and may be mid-edit
        return None


def room(floors: list[str], items: list[tuple[str, int, int]]) -> list[list[str]]:
    rows = []
    for y in range(9):
        row = []
        for x in range(15):
            if y == 0:
                n = "iwall_nw" if x == 0 else "iwall_ne" if x == 14 else ("iwall_n_a", "iwall_n_a", "iwall_n_b")[x % 3]
            elif y == 8:
                n = "iwall_sw" if x == 0 else "iwall_se" if x == 14 else "iwall_s"
            elif x == 0:
                n = "iwall_w"
            elif x == 14:
                n = "iwall_e"
            else:
                n = floors[((x * 7) ^ (y * 13)) % len(floors)]
            row.append(n)
        rows.append(row)
    kind = "stone" if "stone" in floors[0] else "tile" if "tile" in floors[0] else "wood"
    metas = ART.metas[SET]
    for n, x, y in items:
        rows[y][x] = f"{n}_{kind}" if f"{n}_{kind}" in metas else n
    return rows


def big(prefix: str, x: int, y: int, names: list[list[str]]) -> list[tuple[str, int, int]]:
    return [(prefix + n, x + i, y + j) for j, row in enumerate(names) for i, n in enumerate(row)]


RUG9 = [["tl", "t", "tr"], ["l", "c", "r"], ["bl", "b", "br"]]
WOODS = ["ifloor_wood_a", "ifloor_wood_b", "ifloor_wood_c"]
ROOMS = {
    "yaya": (WOODS, [("iwall_n_window", 3, 0), ("iwall_n_clock", 7, 0), ("iwall_n_window", 11, 0), ("iwall_n_shelf", 5, 0),
                     ("idoor", 7, 8), ("ifireplace_l", 9, 1), ("ifireplace_r", 10, 1), ("icupboard", 12, 1), ("istove", 13, 1),
                     ("itable_l", 6, 4), ("itable_r", 7, 4), ("ichair_down", 6, 3), ("ichair_up", 7, 5),
                     ("ichair_right", 5, 4), ("ichair_left", 8, 4), ("iplant_a", 1, 7), ("iplant_b", 13, 7),
                     ("ibookshelf_a", 4, 1), ("ibookshelf_b", 5, 1), ("ibarrel", 13, 6), ("iquilt_line", 2, 5)]
             + big("ibed_", 1, 1, [["tl", "tr"], ["bl", "br"]]) + big("irug_", 9, 3, RUG9),
             (7 * 16, 6 * 16)),
    "shop": (["ifloor_tile_a"], [("iwall_n_window", 2, 0), ("iwall_n_window", 12, 0), ("iwall_n_clock", 7, 0), ("idoor", 7, 8),
                                 ("ishop_shelf_a", 4, 1), ("ishop_shelf_b", 5, 1), ("ishop_shelf_a", 6, 1), ("ishop_shelf_b", 8, 1),
                                 ("ishop_shelf_a", 9, 1), ("ishop_shelf_b", 10, 1), ("icounter_l", 6, 3), ("icounter_m", 7, 3),
                                 ("icounter_r", 8, 3), ("ibarrel", 1, 1), ("ibarrel", 2, 1), ("icrate", 1, 2), ("icrate", 13, 1),
                                 ("ibarrel", 13, 2), ("iplant_b", 1, 7), ("iplant_a", 13, 7), ("ichest_closed", 12, 6)],
             (7 * 16, 5 * 16)),
    "mayor": (["ifloor_stone_a", "ifloor_stone_b"], [("iwall_n_map", 7, 0), ("iwall_n_window", 3, 0), ("iwall_n_window", 11, 0),
                                                       ("iwall_n_clock", 9, 0), ("iwall_n_shelf", 5, 0), ("idoor", 7, 8),
                                                       ("ibookshelf_a", 1, 1), ("ibookshelf_b", 2, 1), ("ibookshelf_a", 12, 1),
                                                       ("ibookshelf_b", 13, 1), ("idesk_l", 6, 2), ("idesk_r", 7, 2),
                                                       ("ichair_up", 6, 3), ("imap_table", 11, 4), ("iplant_a", 1, 7),
                                                       ("iplant_b", 13, 7), ("ishelf_l", 3, 1), ("ishelf_r", 4, 1)]
              + big("irug_", 6, 4, RUG9), (9 * 16, 6 * 16)),
    "treehouse": (WOODS, [("iwall_n_window", 7, 0), ("idoor", 7, 8), ("iladder", 11, 5), ("itoys", 4, 5), ("ichest_closed", 1, 1),
                          ("ichest_open", 2, 1), ("icrate", 13, 1), ("ibarrel", 12, 1), ("iplant_a", 1, 7)]
                  + big("ibed_", 4, 1, [["tl", "tr"], ["bl", "br"]]), (7 * 16, 6 * 16)),
}


def preview() -> None:
    import palettes
    from PIL import Image, ImageDraw

    metas = ART.metas[SET]
    out = g.ART_DIR
    out.mkdir(exist_ok=True)
    names = list(metas)
    for label, tones in (("dmg", palettes.DMG), ("pocket", palettes.POCKET)):
        cols, sc, cw, ch = 10, 4, 16 * 4 + 8, 16 * 4 + 18
        rows = (len(names) + cols - 1) // cols
        img = Image.new("RGB", (cols * cw + 8, rows * ch + 8), (200, 200, 200))
        d = ImageDraw.Draw(img)
        for i, n in enumerate(names):
            x, y = 8 + (i % cols) * cw, 8 + (i // cols) * ch
            img.paste(g.to_image(metas[n].ground, tones, sc), (x, y))
            if metas[n].front is not None:
                fi = g.to_image(metas[n].front, tones, sc)
                img.paste(fi, (x, y), fi)
            d.text((x, y + 16 * sc + 1), n[:13], fill=(0, 0, 0))
        img.save(out / f"interior_tiles_{label}.png")

    hero = hero_pics()
    for rname, (floors, items, pos) in ROOMS.items():
        grid = room(floors, items)
        hp = (hero["down"], pos[0], pos[1]) if hero else None
        a = g.scene_image(grid, metas, palettes.DMG, 3, hp)
        b = g.scene_image(grid, metas, palettes.POCKET, 3, hp)
        img = Image.new("RGB", (a.width, a.height * 2 + 6), (60, 60, 70))
        img.paste(a, (0, 0))
        img.paste(b, (0, a.height + 6))
        img.save(out / f"interior_room_{rname}.png")
        s1 = g.scene_image(grid, metas, palettes.DMG, 1, hp)
        s2 = g.scene_image(grid, metas, palettes.POCKET, 1, hp)
        img = Image.new("RGB", (s1.width * 2 + 4, s1.height * 2 + s1.height + 8), (60, 60, 70))
        img.paste(s1.resize((s1.width * 2, s1.height * 2)), (0, 0))
        img.paste(s2, (0, s1.height * 2 + 4))
        img.paste(s1, (s1.width + 4, s1.height * 2 + 4))
        img.save(out / f"interior_room_{rname}_small.png")


if __name__ == "__main__":
    preview()
