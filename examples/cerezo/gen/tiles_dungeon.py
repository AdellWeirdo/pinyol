"""La Raíz, the root cave under the mountain (tileset "dungeon"): 67 metatiles, the names of the brief.

Design: the room is a box seen from above like the houses' rooms (a dark 4-px band at the screen edge, the faces inside,
mitred corners); the back wall is a face of rocks with pale roots hanging out of the dark, the side walls are it turned
a quarter (shaded again so the light stays top-left), the front wall is the stone top. Rocks are letter maps shaded by
`rockify`; roots are polylines shaded by `stroke`/`shade_mask`. Wall variants share their edge columns, so they join in
any order. Doors are arches of root in the wall's own rock, one drawing turned for the four sides; open doors have a
front layer (the hero walks in under the arch); keyholes are always upright. stairs_exit sits in the SOUTH wall
(maps_dungeon puts it there). pit is a self-contained hole (R9 rings eight of them round a chest); cobweb stacks
vertically (R7's curtain). Animations: torch (torch_lit_a/b, 12), drip (drip_a/b, 26).
"""
from __future__ import annotations

import sys
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent))
import gbart as g  # noqa: E402
from gbart import ART  # noqa: E402

SET = "dungeon"


# ======================================================================== helpers
def rows_of(s: str) -> list[str]:
    """Text rows, indented freely."""
    return [ln.strip() for ln in s.strip().split("\n")]


def T(s: str, w: int = 16, h: int = 16) -> g.Pic:
    """Text rows to a w x h picture."""
    return g.pic(rows_of(s), w, h)


def on(base: g.Pic, top: str | g.Pic | None, dx: int = 0, dy: int = 0) -> g.Pic:
    """A drawing with see-through '.' laid over a picture."""
    if top is None:
        return base
    return g.overlay(base, T(top) if isinstance(top, str) else top, dx, dy)


def transpose(p: g.Pic) -> g.Pic:
    return [list(r) for r in zip(*p)]


def tr(rows: list[str]) -> list[str]:
    """A map's rows transposed (the back wall turned into the west wall)."""
    return ["".join(c) for c in zip(*rows)]


def mirror(rows: list[str]) -> list[str]:
    return [r[::-1] for r in rows]


# ======================================================================== rocks
# Rocks are drawn as letter maps: a letter is one rock, 3 the crevices between rocks, other digits stay as written.
# `rockify` shades them as the whole game is lit, from the top left: corners rounded off (3), the top edge lit (1), the
# left edge lit only just under the corner, the rest tone 2, and a sparkle (0) by the top-left corner of the big ones.
# `beyond(x, y)` says what lies outside the tile (the neighbouring piece's map), so a rock that goes on into the next
# piece is shaded as one rock.

def rockify(rows: list[str], beyond=None, hi: int = 1, body: int = 2, sparkle: bool = True) -> g.Pic:
    h, w = len(rows), len(rows[0])

    def at(x, y):
        if 0 <= x < w and 0 <= y < h:
            return rows[y][x]
        return beyond(x, y) if beyond else "3"

    def run(x, y, dx, dy, ch):
        n = 0
        while n < 20 and at(x + dx * (n + 1), y + dy * (n + 1)) == ch:
            n += 1
        return n
    out = g.blank(w, h)
    for y in range(h):
        for x in range(w):
            ch = rows[y][x]
            if ch in "0123":
                out[y][x] = int(ch)
            elif ch not in ". ":
                t, l, b, r = at(x, y - 1) != ch, at(x - 1, y) != ch, at(x, y + 1) != ch, at(x + 1, y) != ch
                if (t or b) and (l or r):
                    v = 3
                elif t or (l and at(x, y - 1) == ch and at(x, y - 2) != ch):
                    v = hi
                else:
                    v = body
                out[y][x] = v
    if sparkle:
        for y in range(h):
            for x in range(w):
                ch = rows[y][x]
                if (ch.isalpha() and at(x - 1, y) != ch and at(x, y - 1) != ch and run(x, y, 1, 0, ch) >= 4
                        and run(x, y, 0, 1, ch) >= 3 and x + 1 < w):
                    out[y][x + 1] = 0
    return out


def wrap_x(rows: list[str], above: str = "3", below: str = "1"):
    """Outside a piece of a wall that runs sideways: the same piece again to the left and right."""
    w, h = len(rows[0]), len(rows)
    return lambda x, y: rows[y][x % w] if 0 <= y < h else (above if y < 0 else below)


def wrap_y(rows: list[str], left: str = "3", right: str = "1"):
    """Outside a piece of a wall that runs down the screen: the same piece again above and below."""
    w, h = len(rows[0]), len(rows)
    return lambda x, y: rows[y % h][x] if 0 <= x < w else (left if x < 0 else right)


def shade_px(v: int, x: int, y: int) -> int:
    """A pixel of a face next to the floor, in the shade: 2 becomes a 2/3 checker, 0 and 1 become 2."""
    if v == 2 and (x + y) % 2 == 0:
        return 3
    return 2 if v in (0, 1) else v


def foot_shade(p: g.Pic, side: str, k: int) -> g.Pic:
    """Row (side "y") or column (side "x") k of a face, the one next to the floor, in the shade."""
    out = [r[:] for r in p]
    for y in range(16):
        for x in range(16):
            if (y if side == "y" else x) == k:
                out[y][x] = shade_px(out[y][x], x, y)
    return out


# ======================================================================== roots (strokes)
# A root is a polyline of (x, y, width) points: `stroke` rasterises it into a mask (a round brush that runs along it,
# its width changing smoothly), and `shade_mask` paints the mask lit from the top left: the left and top edges tone 0,
# the right and bottom edges (where it is 3 or more thick) tone 2, the rest tone 1; the pixels round it get tone 3 on
# the sides in `outline` ("rb": only right and below, its shadow; "all": an outline all round). The result is an
# overlay (see-through elsewhere).

def stroke(points: list[tuple], w: int = 16, h: int = 16, mask: set | None = None) -> set:
    mask = set() if mask is None else set(mask)
    for (x0, y0, r0), (x1, y1, r1) in zip(points, points[1:]):
        n = max(2, int(max(abs(x1 - x0), abs(y1 - y0)) * 4))
        for i in range(n + 1):
            t = i / n
            cx, cy, cw = x0 + (x1 - x0) * t, y0 + (y1 - y0) * t, r0 + (r1 - r0) * t
            rad = cw / 2
            for py in range(int(cy - rad) - 1, int(cy + rad) + 2):
                for px in range(int(cx - rad) - 1, int(cx + rad) + 2):
                    if (px + 0.5 - cx) ** 2 + (py + 0.5 - cy) ** 2 <= rad * rad + 0.05 and 0 <= px < w and 0 <= py < h:
                        mask.add((px, py))
    return mask


def shade_mask(mask: set, w: int = 16, h: int = 16, outline: str = "rb", lit: int = 0, body: int = 1,
               dark: int = 2, edge: int = 3) -> g.Pic:
    out = g.blank(w, h)
    for (x, y) in mask:
        left, top = (x - 1, y) not in mask, (x, y - 1) not in mask
        right, bottom = (x + 1, y) not in mask, (x, y + 1) not in mask
        thick_x = (x - 1, y) in mask and (x - 2, y) in mask
        thick_y = (x, y - 1) in mask and (x, y - 2) in mask
        if left or top:
            v = lit
        elif (right and thick_x) or (bottom and thick_y):
            v = dark
        else:
            v = body
        out[y][x] = v
    if outline:
        for (x, y) in mask:
            sides = [(1, 0), (0, 1)] if outline == "rb" else [(1, 0), (0, 1), (-1, 0), (0, -1)]
            for dx, dy in sides:
                nx, ny = x + dx, y + dy
                if 0 <= nx < w and 0 <= ny < h and (nx, ny) not in mask:
                    out[ny][nx] = edge
    return out


def root(*paths: list[tuple], outline: str = "rb") -> g.Pic:
    """Roots from one or more polylines (the first is the main root, the others its branches)."""
    mask = set()
    for pts in paths:
        mask = stroke(pts, mask=mask)
    return shade_mask(mask, outline=outline)


# ======================================================================== floors
# Packed earth: tone 1, a few short dark strata (the earth was pressed flat in layers) and a pebble lit from the top
# left. Each variant puts them elsewhere, so a floor of the three does not show a grid.
FLOOR_A = T("""
    1111111111111111
    1111111111111111
    1111111111222111
    1111111111111111
    1111111111111111
    1111111111111111
    1111001111111111
    1110222311111111
    1111233111111111
    1111111111111111
    1111111111111111
    1111111111111111
    1111111111111111
    1111111111111111
    1222111111111221
    1111111111111111
""")
FLOOR_B = T("""
    1111111111111111
    1111111111111111
    1111111111111111
    1111111111111111
    1111112221111111
    1111111111111111
    1111111111111111
    1111111111111111
    1111111111111111
    1111111111111111
    1111111111101111
    1111111111022311
    1111111111123111
    1111111111111111
    1111111111111111
    1111111111111111
""")
FLOOR_C = T("""
    1111111111111111
    1111111111111111
    1111111111111111
    1111111111111111
    1111111111111111
    1111111111111111
    1111111111111111
    1111111111111111
    1122111111111111
    1111111111111111
    1111111111111111
    1111111112221111
    1111111111111111
    1111111111111111
    1111111111111111
    1111111111111111
""")

# ======================================================================== walls
# The room is a box seen from above, like the houses' rooms (tiles_interior): every wall has a dark band along the
# screen's edge (the darkness over the wall, rows/columns 0-3) and inside it its face. The back wall (north) is a face
# of rocks with roots hanging from the dark; the side walls are the back wall turned a quarter (shaded again, so the
# light stays at the top left); the front wall (south) is the stone top, slabs seen from above. The columns 0-1 and
# 14-15 of every back-wall face are the same in all its variants, so the variants join in any order.
BAND = ["3333333333333333"] * 4

FACE_N_A = rows_of("""
    AAAAAAAA3BBBBBB3
    AAAAAAAA3BBB3BB3
    AAAAAAA3BBBB3BB3
    AAAAAAA3BBBBB3B3
    3AAAAA3BBBBBBB33
    C33333DD33333CCC
    CC3DDDDDDDD3CCCC
    CC3DDDDDDDD3CCCC
    CC3DDDDDDDD3CCCC
    CC3DDDDDDDD3CCCC
    CC3DDDDDDDD3CCCC
    3333333333333333
""")
FACE_N_B = rows_of("""
    AAAA3BBBBBBBBBB3
    AAAA3BBBBBBBBBB3
    AAAAA3BBBBBBBBB3
    AAAAA3BBBBBBBBB3
    3AAAA3BBBBBBBB33
    C333DDD33333CCCC
    CC3DDDDDD3EE3CCC
    CC3DDDDDD3EEE3CC
    CC3DDDDDD3EEE3CC
    CC3DDDDDDD3EE3CC
    CC3DDDDDDD3EE3CC
    3333333333333333
""")
MAP_N_A = BAND + FACE_N_A
MAP_N_B = BAND + FACE_N_B

# a thick root out of the dark, down the face, forking at its end (variant a); a stub that pokes out (variant b)
ROOT_N_A = root([(11, -1, 4.2), (11, 3, 4), (10.5, 6, 3.6), (10, 9, 3), (9, 11, 2.6), (8, 13, 2), (7, 15, 1)],
                [(10, 9, 1.2), (12, 11, 1.2), (12.5, 13, 1)])
ROOT_N_B = root([(4, -1, 3.4), (4, 2, 3), (4.5, 4, 2), (5, 5, 1)])


def wall_n(rows: list[str], over: g.Pic | None = None) -> g.Pic:
    p = rockify(rows, wrap_x(rows))
    return on(foot_shade(p, "y", 14), over)


def map_w(rows_n: list[str]) -> list[str]:
    return tr(rows_n)


def map_e(rows_n: list[str]) -> list[str]:
    return mirror(tr(rows_n))


def turn_w(over: g.Pic | None) -> g.Pic | None:
    """A back-wall overlay turned for the west wall: what hung down now reaches right, toward the floor, and its lit
    side, which was the left, is the top."""
    return None if over is None else transpose(over)


def turn_e(over: g.Pic | None) -> g.Pic | None:
    return None if over is None else g.flip_h(transpose(over))


def wall_w(rows_n: list[str], over: g.Pic | None = None) -> g.Pic:
    rows = map_w(rows_n)
    return on(foot_shade(rockify(rows, wrap_y(rows, "3", "1")), "x", 14), turn_w(over))


def wall_e(rows_n: list[str], over: g.Pic | None = None) -> g.Pic:
    rows = map_e(rows_n)
    return on(foot_shade(rockify(rows, wrap_y(rows, "1", "3")), "x", 1), turn_e(over))


# the front wall: its edge (row 0, tone 3) over the floor, slabs seen from above, the band
TOP_S_A = rows_of("""
    3333333333333333
    AAAAA3BBBBBBB3CC
    AAAAA3BBBBBBB3CC
    AAAAA3BBBBBBB3CC
    AAAA3DDDDBBBB3CC
    3333DDDDDD333CCC
    EEE3DDDDDD3FFF3E
    EEE3DDDDD3FFFF3E
    EEEE3333FFFFFF3E
    EEEE3GGG3FFFF3EE
    3333333333333333
    3333333333333333
""")
TOP_S_B = rows_of("""
    3333333333333333
    AAAAAAA3BBBBB3CC
    AAAAAAA3BBBBB3CC
    AAAAAAA3BBBBB3CC
    AAAAAA3DDDBBB3CC
    3333333DDDD333CC
    EEE3HHH3DDD3FF3E
    EEE3HHHH333FFF3E
    EEEE3HHHH3FFFF3E
    EEEE3HHH3FFFF3EE
    3333333333333333
    3333333333333333
""")
MAP_S_A = TOP_S_A + BAND
MAP_S_B = TOP_S_B + BAND


def wall_s(rows: list[str], over: str | None = None) -> g.Pic:
    return on(rockify(rows, wrap_x(rows, "1", "3")), over)


# ------------------------------------------------------------------------ corners
# Two walls meet on the diagonal, like a mitred frame. The corner's map is made of both walls' maps (the second in
# lower case, so its rocks are other rocks), with a crevice on the seam; it is shaded knowing the pieces beside it.
def corner(kind: str, n: list[str] = MAP_N_A, s: list[str] = MAP_S_A) -> g.Pic:
    w, e = map_w(n), map_e(n)
    first, second = {"nw": (n, w), "ne": (n, e), "sw": (w, s), "se": (e, s)}[kind]
    second = [r.lower() for r in second]

    def side(x, y):  # > 0: the first wall's side of the seam, < 0 the second's
        return x - y if kind in ("nw", "se") else 15 - x - y
    rows = ["".join(first[y][x] if side(x, y) > 0 else second[y][x] if side(x, y) < 0 else "3" for x in range(16))
            for y in range(16)]

    def beyond(x, y):
        inside_x, inside_y = 0 <= x < 16, 0 <= y < 16
        if kind == "nw":
            return n[y][x - 16] if x > 15 and inside_y else w[y - 16][x].lower() if y > 15 and inside_x else "3"
        if kind == "ne":
            return n[y][x + 16] if x < 0 and inside_y else e[y - 16][x].lower() if y > 15 and inside_x else "3"
        if kind == "sw":
            return w[y + 16][x] if y < 0 and inside_x else s[y][x - 16].lower() if x > 15 and inside_y else "3"
        return e[y + 16][x] if y < 0 and inside_x else s[y][x + 16].lower() if x < 0 and inside_y else "3"
    p = rockify(rows, beyond)
    out = [r[:] for r in p]
    for y in range(16):
        for x in range(16):
            foot = {"nw": (y == 14 and x > y) or (x == 14 and x < y),
                    "ne": (y == 14 and x + y < 15) or (x == 1 and x + y > 15),
                    "sw": x == 14 and x + y < 15,
                    "se": x == 1 and x > y}[kind]
            if foot:
                out[y][x] = shade_px(p[y][x], x, y)
    return out


# ======================================================================== doors
# A door is the gap in the middle of a wall, framed by an arch of root that rises from the floor on each side (the
# cave's doors are passages between roots). Everything is drawn once for the back wall and turned for the others,
# as the walls are: the opening and the root are masks that are turned and shaded again (the light stays at the top
# left), the rock round them is the wall's own map with the opening carved out. The fills by state: open (the passage,
# its floor going into the dark), shut (pale root bars bound with iron), locked (dark planks, an iron plate with a
# keyhole), boss (a black door and a big keyhole that glows). Keyholes are always drawn upright. An open door has a
# front layer, the arch and the dark over the passage, so the hero walks in under it.

def arch_mask(x0: int, x1: int, top: int, r: int) -> set:
    """Columns x0..x1 from row `top` down to the bottom, the top corners rounded (an ellipse r rows tall)."""
    m = set()
    cx, half = (x0 + x1 + 1) / 2, (x1 - x0 + 1) / 2
    for y in range(top, 16):
        for x in range(x0, x1 + 1):
            dy = top + r - y
            if dy > 0 and ((x + 0.5 - cx) / half) ** 2 + (dy / (r + 0.5)) ** 2 > 1.0:
                continue
            m.add((x, y))
    return m


OPENING = arch_mask(4, 11, 6, 3)
ARCH = stroke([(2.6, 17, 3.4), (2.6, 12, 3), (3.2, 7.5, 3), (5, 4.6, 3), (8, 3.6, 3), (11, 4.6, 3), (12.8, 7.5, 3),
               (13.4, 12, 3), (13.4, 17, 3.4)])
TURN = {  # a pixel of the back-wall drawing, where it goes on each side
    "n": lambda x, y: (x, y),
    "w": lambda x, y: (y, x),
    "e": lambda x, y: (15 - y, x),
    "s": lambda x, y: (x, 15 - y),
}


def turned(mask: set, side: str) -> set:
    return {TURN[side](x, y) for (x, y) in mask}


def turn_pic(p: g.Pic, side: str) -> g.Pic:
    out = g.blank(16, 16)
    for y in range(16):
        for x in range(16):
            if p[y][x] >= 0:
                tx, ty = TURN[side](x, y)
                out[ty][tx] = p[y][x]
    return out


def fill_open(m: set, side: str) -> g.Pic:
    """The passage: dark, and its floor coming out of the dark next to the room (tone 2, then 1 at the edge)."""
    p = g.blank(16, 16)
    dist = {"n": lambda x, y: 15 - y, "s": lambda x, y: y, "w": lambda x, y: 15 - x, "e": lambda x, y: x}[side]
    for (x, y) in m:
        d = dist(x, y)
        p[y][x] = 1 if d == 0 else 2 if d == 1 else 3
    return p


def fill_bars(m: set, side: str) -> g.Pic:
    """Root bars across the opening, three of them, bound by two iron straps."""
    p = g.blank(16, 16)
    along = side in ("n", "s")  # bars stand up (n, s) or lie across (w, e)
    for (x, y) in m:
        u, v = (x, y) if along else (y, x)       # u across the bars, v along them
        vv = v if side in ("n", "w") else 15 - v
        k = (u - 4) % 3
        if vv in (9, 13):                         # an iron strap, its rivets on the bars
            p[y][x] = 0 if k == 0 else 3
        else:
            p[y][x] = (0, 1, 3)[k]
    return p


PLATE_TALL = T("""
    .0000.
    003300
    033330
    003300
    003300
    033330
    033330
    .0000.
""", 6, 8)
PLATE_SHORT = T("""
    .0000.
    003300
    033330
    003300
    033330
    .0000.
""", 6, 6)
BOSS_KEY = T("""
    .1111.
    100001
    100001
    .1001.
    100001
    100001
    .1111.
""", 6, 7)


def fill_locked(m: set, side: str) -> g.Pic:
    """Dark planks with an iron strap, an iron plate with the keyhole in the middle (upright on every side)."""
    p = g.blank(16, 16)
    along = side in ("n", "s")
    for (x, y) in m:
        u, v = (x, y) if along else (y, x)
        vv = v if side in ("n", "w") else 15 - v
        k = (u - 4) % 3
        p[y][x] = 3 if vv == 7 else (1, 2, 3)[k]
    if along:
        return g.overlay(p, PLATE_TALL, 5, 8 if side == "n" else 0)
    return g.overlay(p, PLATE_SHORT, 8 if side == "w" else 2, 5)


def fill_boss(m: set, side: str) -> g.Pic:
    """A black door, a big keyhole that glows (0) with a ring of light (1) round it."""
    p = g.blank(16, 16)
    for (x, y) in m:
        p[y][x] = 2 if (x + y) % 2 == 0 and ((side in ("n", "s") and y % 4 == 0) or (side in ("w", "e") and x % 4 == 0)) else 3
    pos = {"n": (5, 7), "s": (5, 2), "w": (8, 5), "e": (2, 5)}[side]
    return g.overlay(p, BOSS_KEY, *pos)


FILLS = {"open": fill_open, "shut": fill_bars, "locked": fill_locked, "boss": fill_boss}

# the rock of each side's door frame: that side's wall map (the back one for n/w/e, turned; the stone top for s)
DOOR_ROCK = {"n": MAP_N_B, "w": map_w(MAP_N_B), "e": map_e(MAP_N_B), "s": MAP_S_A}


def door(side: str, state: str) -> tuple:
    opening, arch_m = turned(OPENING, side), turned(ARCH, side)
    rows = ["".join("." if (x, y) in opening else c for x, c in enumerate(r)) for y, r in enumerate(DOOR_ROCK[side])]
    beyond = {"n": wrap_x(rows), "s": wrap_x(rows, "1", "3"), "w": wrap_y(rows, "3", "1"), "e": wrap_y(rows, "1", "3")}[side]
    p = rockify(rows, beyond)
    if side == "n":
        p = foot_shade(p, "y", 14)
    elif side == "w":
        p = foot_shade(p, "x", 14)
    elif side == "e":
        p = foot_shade(p, "x", 1)
    p = g.overlay(p, FILLS[state](opening, side))
    p = g.overlay(p, shade_mask(arch_m, outline="all"))
    front = None
    if state == "open":
        box = {"n": (0, 0, 15, 8), "s": (0, 7, 15, 15), "w": (0, 3, 8, 12), "e": (7, 3, 15, 12)}[side]
        x0, y0, x1, y1 = box
        front = g.blank(16, 16)
        for y in range(y0, y1 + 1):
            for x in range(x0, x1 + 1):
                if (x, y) not in opening:
                    front[y][x] = p[y][x]
    return p, front


DOOR_FLAGS = {"open": (), "shut": ("solid",), "locked": ("solid", "lock"), "boss": ("solid", "lock", "bosslock")}


# ======================================================================== the stairs out (in the front wall)
def fill_stairs(m: set, side: str) -> g.Pic:
    """Steps climbing out of the room toward the daylight at the screen's edge: treads brighter as they rise, risers
    darker, the stairwell's sides in the shade."""
    p = g.blank(16, 16)
    tone = [1, 2, 1, 1, 2, 0, 0, 1, 0, 0]
    for (x, y) in m:
        v = tone[min(y, 9)]
        if (x - 1, y) not in m or (x + 1, y) not in m:
            v = 3 if y < 5 else 2
        p[y][x] = v
    return p


def stairs_exit() -> tuple:
    opening, arch_m = turned(OPENING, "s"), turned(ARCH, "s")
    rows = ["".join("." if (x, y) in opening else c for x, c in enumerate(r)) for y, r in enumerate(MAP_S_A)]
    p = rockify(rows, wrap_x(rows, "1", "3"))
    p = g.overlay(p, fill_stairs(opening, "s"))
    p = g.overlay(p, shade_mask(arch_m, outline="all"))
    front = g.blank(16, 16)
    for y in range(7, 16):
        for x in range(16):
            if (x, y) not in opening:
                front[y][x] = p[y][x]
    return p, front


# ======================================================================== more of the back wall
def disc(cx: float, cy: float, r: float) -> set:
    return {(x, y) for y in range(16) for x in range(16) if (x + 0.5 - cx) ** 2 + (y + 0.5 - cy) ** 2 <= r * r}


WALL_N_ROOTS = on(wall_n(MAP_N_A), root(
    [(2.5, -1, 3.8), (3, 3, 3.4), (4.5, 7, 3), (5, 10, 2.6), (4, 13, 2), (3, 15.5, 1.2)],
    [(4.5, 7, 1.2), (7, 9, 1.2), (7.5, 11, 1)],
    [(13, -1, 4.2), (12.5, 3, 3.6), (10.5, 6, 3), (9.5, 9, 2.6), (10.5, 12, 2), (11.5, 15.5, 1.2)],
    [(8, -1, 2.4), (8.5, 2, 2), (7.5, 4, 1.4), (7, 5.5, 1)], outline="all"))

WALL_N_WATER = on(on(wall_n(MAP_N_B), root([(8, -1, 3.4), (8, 2, 3), (8.5, 4, 2), (8.5, 5.5, 1.2)], outline="all")), """
    ................
    ................
    ................
    ................
    ................
    ................
    ........3.......
    ........3.......
    .......303......
    .......303......
    ........3.......
    ........3.......
    ....33333333....
    ...3001112223...
    ...3222222223...
    ....33333333....
""")


def medallion(eye: str) -> g.Pic:
    p = on(wall_n(MAP_N_A), shade_mask(disc(8, 9.5, 5.9), outline="all"))
    return on(p, T(eye, 8, 6), 4, 7)


EYE_OPEN = """
    ..3333..
    .300003.
    30033003
    30033003
    .300003.
    ..3333..
"""
EYE_SHUT = """
    ........
    3......3
    .3....3.
    ..3333..
    .3.3.3..
    ........
"""

# ======================================================================== floors with something on them
BARE = g.pic(["1111111111111111"] * 16, 16, 16)


def floor_with(top: str, base: g.Pic = BARE) -> g.Pic:
    return on(base, top)


FLOOR_CRACKED = T("""
    1111111111111111
    1111111111112111
    1121111111121111
    1112111111211111
    1111211112111111
    1111121111211111
    1111112332111111
    1111123333211111
    1222223303211111
    1111112332211111
    1111112111121111
    1111121111112111
    1111211111111211
    1112111111111121
    1111111111111111
    1111111111111111
""")
FLOOR_MOSS = T("""
    1111111111111111
    1111111111111111
    1111212111111111
    1112202211111111
    1112222221111111
    1122222222111111
    1112222221211111
    1111212121111111
    1111111111111111
    1111111111121211
    1111111111222221
    1111111112202221
    1111111111222211
    1111111111212111
    1111111111111111
    1111111111111111
""")
FLOOR_PLATE = T("""
    0000000000000003
    0111111111111123
    0111122111111123
    0111200211111123
    0111200211111123
    0122122122111123
    0200233200211123
    0200233200211123
    0122122122111123
    0111200211111123
    0111200211111123
    0111122111111123
    0111111111111123
    0111111111111123
    0222222222222223
    3333333333333333
""")


def boss_floor(scuffed: bool) -> g.Pic:
    p = [r[:] for r in BARE]
    for y in range(16):
        for x in range(16):
            d = ((x + 0.5 - 8) ** 2 + (y + 0.5 - 8) ** 2) ** 0.5
            if 6.6 <= d < 7.6:
                p[y][x] = 0
            elif 5.7 <= d < 6.6:
                p[y][x] = 2
            elif 1.6 <= d < 2.6:
                p[y][x] = 0
    for x, y in ((0, 0), (15, 0), (0, 15), (15, 15)):
        p[y][x] = 0
    if scuffed:
        for k in range(3):
            for i in range(6):
                x, y = 3 + i + 2 * k, 9 - i + k
                if 0 <= x < 16 and 0 <= y < 16:
                    p[y][x] = 2
        for x, y in ((12, 3), (13, 4), (3, 12)):
            p[y][x] = 1
    return p


# ======================================================================== hazards and puzzles
PIT = on(T("""
    1111111111111111
    1113333333333111
    1132222222222311
    1322212222122231
    1322222222222231
    1323232323232331
    1332323232323231
    1333333333333331
    1333333333333331
    1333333333333331
    1333333333333331
    1333333333333331
    1333333333333331
    1133333333333311
    1110000000000111
    1111111111111111
"""), root([(10.5, 1, 2.2), (10.5, 4, 2), (10, 6, 1.4), (10.5, 8, 1)]))
PIT_FILLED = T("""
    1111111111111111
    1113333333333111
    1130000000000311
    1301111111111231
    1301111111111231
    1301112111111231
    1301111211111231
    1301111121111231
    1301111112111231
    1301111111211231
    1301111111111231
    1301111111111231
    1302222222222231
    1133333333333311
    1111111111111111
    1111111111111111
""")
WATER_POOL = T("""
    2222222222222222
    2222222222222222
    2220111222222222
    2212222322222222
    2222222222222222
    2222222222222222
    2222222222201112
    2222222222122223
    2222222222222222
    2222222222222222
    2222220111222222
    2222212222322222
    2222222222222222
    2222222222222222
    2011122222222222
    2122223222222222
""")


def spikes(up: bool) -> g.Pic:
    p = [[2] * 16 for _ in range(16)]
    for i in range(16):
        p[0][i] = p[15][i] = p[i][0] = p[i][15] = 3
    for i in range(1, 15):
        p[1][i] = 1 if p[1][i] == 2 else p[1][i]
        p[i][1] = 1
    for ox, oy in ((1, 1), (8, 1), (1, 8), (8, 8)):
        for y in range(7):
            for x in range(7):
                if up:
                    if x in (0, 6) or y in (0, 6):
                        v = 3
                    else:
                        a, b, c, d = x - 1, y - 1, 5 - x, 5 - y
                        mm = min(a, b, c, d)
                        v = 0 if mm == b else 1 if mm == a else 2
                        if x == 3 and y == 3:
                            v = 0
                    p[oy + y][ox + x] = v
                elif 2 <= x <= 4 and 2 <= y <= 4:
                    p[oy + y][ox + x] = 1 if (x == 4 or y == 4) else 3
    return p


def switch(pressed: bool) -> g.Pic:
    m = disc(8, 8, 5.6)
    if pressed:
        p = on(BARE, shade_mask(m, outline="all", lit=3, body=2, dark=1))
        return on(p, T("""
            ....
            .00.
            .00.
            ....
        """, 4, 4), 6, 6)
    p = on(BARE, shade_mask(m, outline="all"))
    p = on(p, T("""
        .22.
        2..2
        2..2
        .22.
    """, 4, 4), 6, 6)
    for x in range(5, 15):
        if p[14][x] == 1:
            p[14][x] = 2
    return p


def cobweb() -> g.Pic:
    web = set()

    def line(x0, y0, x1, y1):
        n = max(abs(x1 - x0), abs(y1 - y0))
        for i in range(n + 1):
            web.add((round(x0 + (x1 - x0) * i / n), round(y0 + (y1 - y0) * i / n)))
    hub = (7, 7)
    spokes = [(7, 0), (7, 15), (0, 7), (15, 7), (0, 0), (15, 0), (0, 15), (15, 15)]
    for sx, sy in spokes:
        line(*hub, sx, sy)
    for r in (3, 6):
        pts = [(round(7 + (sx - 7) * r / 7.5), round(7 + (sy - 7) * r / 7.5)) for sx, sy in
               [(7, 0), (15, 0), (15, 7), (15, 15), (7, 15), (0, 15), (0, 7), (0, 0)]]
        for a, b in zip(pts, pts[1:] + pts[:1]):
            line(*a, *b)
    p = [r[:] for r in FLOOR_A]
    for (x, y) in web:
        if (x + 1, y + 1) not in web and x + 1 < 16 and y + 1 < 16:
            p[y + 1][x + 1] = 2
    for (x, y) in web:
        p[y][x] = 0
    p[7][7] = p[7][8] = p[8][7] = 3
    return p


TORCH_BASE = """
    ................
    ................
    ................
    ................
    ................
    ................
    ...3333333333...
    ..300000000003..
    ..323323323323..
    ...3222222223...
    ....32222223....
    ......3223......
    .....301123.....
    ....30111123....
    ...3333333333...
    ....22222222....
"""
FLAME_A = """
    ........3.......
    .......303......
    ......3013......
    ......30013.....
    .....300013.3...
    ....3000013303..
    ...3000000013...
    ..300000000003..
    ..310101010113..
"""
FLAME_B = """
    ......3.........
    ......303.......
    ......3103......
    .....31003......
    ...3.310003.....
    ..3033100003....
    ...3100000003...
    ..300000000003..
    ..311010101013..
"""


def torch(flame: str | None) -> g.Pic:
    p = floor_with(TORCH_BASE)
    if flame:
        p = on(p, T(flame, 16, 9))
    return p


STATUE_A = """
    ................
    .....333333.....
    ....30000113....
    ...3001111123...
    ...3011111123...
    ..301311113123..
    ..301112211123..
    ..301112311123..
    ..330112211333..
    .3001331133103..
    .3011123211123..
    .3131313131313..
    ..333333333333..
    .30000000000003.
    .32222222222223.
    ..333333333333..
"""
STATUE_B = """
    .........33.....
    .....33333013...
    ....30000313....
    ...300111313....
    ...301111133....
    ..3013111313....
    ..30111221313...
    ..30111231313...
    ..33011221313...
    .300133133133...
    .3011123130003..
    .3131313130003..
    ..333333333333..
    .30000000000003.
    .32222222222223.
    ..333333333333..
"""
CHEST_CLOSED = """
    ................
    ................
    ................
    ..333333333333..
    .31111111111113.
    .30122222222103.
    .32322222222323.
    .33333300333333.
    .32322300322323.
    .32322303322323.
    .32322333322323.
    .32322222222323.
    .32322222222323.
    ..333333333333..
    ...2222222222...
    ................
"""
CHEST_OPEN = """
    ................
    ..333333333333..
    .32222222222223.
    .32322222222323.
    .33333333333333.
    .30000000000003.
    .33333333333333.
    .32333333333323.
    .32322222222323.
    .32322222222323.
    .32322222222323.
    .32322222222323.
    .32322222222323.
    ..333333333333..
    ...2222222222...
    ................
"""

PILLAR = """
    ..333333333333..
    .33333333333333.
    .33300111333333.
    .33333333333333.
    .31111131111123.
    .30122231222223.
    .30222231222233.
    .33333333323333.
    .31113111111233.
    .30223122222333.
    .30223122223333.
    .30223122222333.
    .33333333333333.
    ..222222222222..
    ....22222222....
    ................
"""
ROCK_BLOCK = """
    ................
    .....3333333....
    ...33111112233..
    ..3110111222223.
    ..3101112222223.
    .31111122223223.
    .31111222232223.
    .31112222322223.
    .31222223222223.
    .31222232222233.
    .31222222222333.
    ..3122222223333.
    ..3332222233333.
    ....333333333...
    ....222222222...
    ................
"""

# ======================================================================== decoration
ROOTS_A = root([(-1, 11, 2.6), (3, 10, 2.6), (7, 7.5, 2.4), (11, 6.5, 2), (14, 4, 1.4), (16, 3, 1)],
               [(7, 7.5, 1.2), (8.5, 10, 1.2), (8, 12.5, 1)], outline="rb")
ROOTS_B = root([(2, -1, 2.2), (3, 3, 2), (5.5, 6, 2), (9, 7, 1.8), (12, 10, 1.6), (13, 14, 1.2), (12.5, 16, 1)],
               [(5.5, 6, 1.2), (3, 8.5, 1)], outline="rb")


def floor_roots(r: g.Pic) -> g.Pic:
    q = [[2 if v == 3 else v for v in row] for row in r]  # the shadow of a root lying flat is soft
    return g.overlay(FLOOR_C, q)


MUSH_A = """
    ................
    ................
    .......0.0......
    ................
    ....333....0....
    ...30003........
    ..3001003.333...
    ..3333333300003.
    .0..313..300103.
    ....313..333333.
    ...3333....313..
    ..30003....313..
    ..33333...33333.
    ...313..........
    ...333...0......
    ................
"""
MUSH_B = """
    ......33333.....
    ....330000033...
    ...30001000003..
    ..3000000010003.
    ..3010000000003.
    ..3333333333333.
    ...0..31113..0..
    ......31113.....
    ..333.31113.333.
    .30003.313.3003.
    .33333.313.3333.
    ..313..313..33..
    ..313.33133.....
    .33333333333....
    ..2222222222....
    ................
"""
BONES = """
    ................
    ................
    ................
    .....3333.......
    ....300003......
    ...30000003.....
    ...30330303.....
    ...30000003.....
    ....303033......
    .....333.....33.
    ..33........303.
    .30033333333003.
    .30000000000003.
    ..33333333333033
    ...........33...
    ................
"""
RUBBLE = """
    ................
    ................
    ...333..........
    ..30113....33...
    ..31223...3013..
    ...333....3223..
    ...........33...
    ................
    ......33........
    .....3013..333..
    .....3223.30113.
    ......33..31223.
    ...33......333..
    ..3013..........
    ...33...........
    ................
"""
PUDDLE = """
    ................
    ................
    ................
    ................
    ................
    .....2222222....
    ...222333332222.
    ..22333333333322
    ..23300333333332
    ..22333330033322
    ...223333333222.
    .....2222222....
    ................
    ................
    ................
    ................
"""
DRIP_A = """
    ................
    .......3........
    ......303.......
    ......303.......
    .......3........
    ................
    ................
    ................
    ................
    ....2222222.....
    ...223333322....
    ..22330333322...
    ...223333322....
    ....2222222.....
    ................
    ................
"""
DRIP_B = """
    ................
    ................
    ................
    ................
    ................
    .....0...0......
    ......0.0.......
    ................
    ...0.......0....
    ....2222222.....
    ...220000022....
    ..22303330322...
    ...220000022....
    ....2222222.....
    ................
    ................
"""


# ======================================================================== registration
def register() -> None:
    m = ART.meta
    for name, p in (("floor_a", FLOOR_A), ("floor_b", FLOOR_B), ("floor_c", FLOOR_C)):
        m(SET, name, p, bank=1)
    m(SET, "wall_n_a", wall_n(MAP_N_A, ROOT_N_A), flags=("solid",), bank=6)
    m(SET, "wall_n_b", wall_n(MAP_N_B, ROOT_N_B), flags=("solid",), bank=6)
    m(SET, "wall_s_a", wall_s(MAP_S_A), flags=("solid",), bank=6)
    m(SET, "wall_s_b", wall_s(MAP_S_B), flags=("solid",), bank=6)
    m(SET, "wall_w_a", wall_w(MAP_N_A, ROOT_N_A), flags=("solid",), bank=6)
    m(SET, "wall_w_b", wall_w(MAP_N_B, ROOT_N_B), flags=("solid",), bank=6)
    m(SET, "wall_e_a", wall_e(MAP_N_A, ROOT_N_A), flags=("solid",), bank=6)
    m(SET, "wall_e_b", wall_e(MAP_N_B, ROOT_N_B), flags=("solid",), bank=6)
    for k in ("nw", "ne", "sw", "se"):
        m(SET, f"wall_{k}", corner(k), flags=("solid",), bank=6)
    for side in "nsew":
        for state in ("open", "shut", "locked", "boss"):
            ground, front = door(side, state)
            m(SET, f"door_{side}_{state}", ground, front=front, flags=DOOR_FLAGS[state], bank=6)

    st_g, st_f = stairs_exit()
    m(SET, "stairs_exit", st_g, front=st_f, flags=("door",), bank=6)
    for name, p in (("floor_cracked", FLOOR_CRACKED), ("floor_moss", FLOOR_MOSS), ("floor_plate", FLOOR_PLATE),
                    ("floor_boss_a", boss_floor(False)), ("floor_boss_b", boss_floor(True))):
        m(SET, name, p, bank=1)
    m(SET, "pillar", floor_with(PILLAR), flags=("solid",), bank=6)
    m(SET, "rock_block", floor_with(ROCK_BLOCK), flags=("solid",), bank=6)
    m(SET, "wall_n_roots", WALL_N_ROOTS, flags=("solid",), bank=6)
    m(SET, "wall_n_water", WALL_N_WATER, flags=("solid",), bank=6)
    m(SET, "pit", PIT, flags=("pit",), bank=1)
    m(SET, "pit_filled", PIT_FILLED, bank=1)
    m(SET, "water_pool", WATER_POOL, flags=("water",), bank=2)
    m(SET, "spikes_up", spikes(True), flags=("spikes",), bank=6)
    m(SET, "spikes_down", spikes(False), bank=6)
    m(SET, "switch_plate", switch(False), flags=("switch_floor",), bank=6)
    m(SET, "switch_plate_on", switch(True), bank=6)
    m(SET, "eye_off", medallion(EYE_OPEN), flags=("solid", "switch"), bank=6)
    m(SET, "eye_on", medallion(EYE_SHUT), flags=("solid",), bank=6)
    m(SET, "cobweb", cobweb(), flags=("solid", "burn", "becomes=floor_a"), bank=1)
    m(SET, "torch_unlit", torch(None), flags=("solid",), bank=5)
    m(SET, "torch_lit_a", torch(FLAME_A), flags=("solid", "light"), bank=5)
    m(SET, "torch_lit_b", torch(FLAME_B), flags=("solid", "light"), bank=5)
    m(SET, "statue_a", floor_with(STATUE_A), flags=("solid",), bank=6)
    m(SET, "statue_b", floor_with(STATUE_B), flags=("solid",), bank=6)
    m(SET, "chest_closed", floor_with(CHEST_CLOSED), flags=("solid", "chest"), bank=4)
    m(SET, "chest_open", floor_with(CHEST_OPEN), flags=("solid",), bank=4)
    m(SET, "roots_a", floor_roots(ROOTS_A), bank=3)
    m(SET, "roots_b", floor_roots(ROOTS_B), bank=3)
    m(SET, "mushroom_a", floor_with(MUSH_A), bank=7)
    m(SET, "mushroom_b", floor_with(MUSH_B), flags=("solid",), bank=7)
    m(SET, "bones", floor_with(BONES), bank=1)
    m(SET, "rubble", floor_with(RUBBLE), bank=6)
    m(SET, "puddle", floor_with(PUDDLE), bank=2)
    m(SET, "drip_a", floor_with(DRIP_A), bank=2)
    m(SET, "drip_b", floor_with(DRIP_B), bank=2)
    ART.animate("torch", ["torch_lit_a", "torch_lit_b"], 12)
    ART.animate("drip", ["drip_a", "drip_b"], 26)


register()


# ======================================================================== previews (python3 gen/tiles_dungeon.py)
FALLBACK_HERO = T("""
    ................
    .....333333..33.
    ....300011133123
    ....30111123223.
    ..333222222333..
    .30000000000113.
    .33222222222233.
    ...3200000023...
    ...3103003013...
    ..333130031333..
    ..312222222113..
    ..323222211323..
    ..303331133303..
    ...3122222223...
    ....32333323....
    ....333..333....
""")


def hero_frames() -> dict:
    """The hero's frames from chars.py (someone else's module, maybe mid-edit: a copy of his stand pose otherwise)."""
    try:
        import chars  # noqa: F401
        sh = ART.sheets["HERO"]
        return {n: sh.get(n) for n, _ in sh.frames}
    except Exception:
        return {"down_0": FALLBACK_HERO}


def scene(names: list[list[str]], sprites: list[tuple], tones, scale: int = 3):
    """The map drawn as the engine will: ground, then the sprites (pic, x, y), then the front layer over them."""
    from PIL import Image
    metas = ART.metas[SET]
    h, w = len(names), len(names[0])
    base = Image.new("RGBA", (w * 16, h * 16), tones[0] + (255,))
    front = Image.new("RGBA", (w * 16, h * 16), (0, 0, 0, 0))
    for y, row in enumerate(names):
        for x, n in enumerate(row):
            m = metas[n]
            base.alpha_composite(g.to_image(m.ground, tones), (x * 16, y * 16))
            if m.front is not None:
                front.alpha_composite(g.to_image(m.front, tones), (x * 16, y * 16))
    for p, sx, sy in sprites:
        base.alpha_composite(g.to_image(p, tones), (sx, sy))
    base.alpha_composite(front)
    img = base.convert("RGB")
    return img.resize((img.width * scale, img.height * scale), Image.NEAREST) if scale != 1 else img


def pick(names: list[str], x: int, y: int, seed: int = 7) -> str:
    return names[((x * 73856093) ^ (y * 19349663) ^ (seed * 83492791)) % len(names)]


# what a character of a room plan means (a list: one chosen by a fixed hash of the cell, as world.py does)
LEGEND = {
    ".": ["floor_a", "floor_b", "floor_c"],
    "N": ["wall_n_a", "wall_n_b"], "S": ["wall_s_a", "wall_s_b"], "W": ["wall_w_a", "wall_w_b"], "E": ["wall_e_a", "wall_e_b"],
    "1": ["wall_nw"], "2": ["wall_ne"], "3": ["wall_sw"], "4": ["wall_se"],
}


def room(plan: list[str], extra: dict | None = None, seed: int = 7) -> list[list[str]]:
    leg = dict(LEGEND)
    if extra:
        leg.update({k: ([v] if isinstance(v, str) else v) for k, v in extra.items()})
    return [[pick(leg[ch], x, y, seed) for x, ch in enumerate(row)] for y, row in enumerate(plan)]


ROOMS = {
    "doors": ([
        "1NNNNNNaNNNNNN2",
        "W.............E",
        "W.............E",
        "W.............E",
        "b.............c",
        "W.............E",
        "W.............E",
        "W.............E",
        "3SSSSSSdSSSSSS4",
    ], {"a": "door_n_open", "b": "door_w_shut", "c": "door_e_locked", "d": "door_s_boss"},
        [("up_0", 7 * 16, 0 * 16 + 4), ("side_0", 1 * 16 + 2, 4 * 16 - 3), ("down_0", 7 * 16, 6 * 16 + 9)]),
    "doors2": ([
        "1NNNNNNaNNNNNN2",
        "W.............E",
        "W.............E",
        "W.............E",
        "b.............c",
        "W.............E",
        "W.............E",
        "W.............E",
        "3SSSSSSdSSSSSS4",
    ], {"a": "door_n_boss", "b": "door_w_open", "c": "door_e_open", "d": "door_s_open"},
        [("down_0", 7 * 16, 1 * 16 + 4), ("side_0", 0 * 16 + 6, 4 * 16 - 4), ("down_0", 7 * 16, 8 * 16 - 6)]),
    "doors3": ([
        "1NNNNNNaNNNNNN2",
        "W.............E",
        "W.............E",
        "W.............E",
        "b.............c",
        "W.............E",
        "W.............E",
        "W.............E",
        "3SSSSSSdSSSSSS4",
    ], {"a": "door_n_shut", "b": "door_w_locked", "c": "door_e_boss", "d": "door_s_shut"}, []),
    "doors4": ([
        "1NNNNNNaNNNNNN2",
        "W.............E",
        "W.............E",
        "W.............E",
        "b.............c",
        "W.............E",
        "W.............E",
        "W.............E",
        "3SSSSSSdSSSSSS4",
    ], {"a": "door_n_locked", "b": "door_w_boss", "c": "door_e_shut", "d": "door_s_locked"}, []),
    "plain": ([
        "1NNNNNNNNNNNNN2",
        "W.............E",
        "W.............E",
        "W.............E",
        "W.............E",
        "W.............E",
        "W.............E",
        "W.............E",
        "3SSSSSSSSSSSSS4",
    ], {}, [("down_0", 7 * 16, 4 * 16), ("up_0", 3 * 16, 1 * 16 - 8), ("side_0", 12 * 16 + 3, 6 * 16),
            ("down_0", 1 * 16 - 3, 6 * 16), ("down_0", 9 * 16, 7 * 16 + 1)]),
}


def preview() -> None:
    import palettes
    from PIL import Image, ImageDraw

    out = g.ART_DIR
    out.mkdir(exist_ok=True)
    metas = ART.metas[SET]
    names = list(metas)
    for label, tones in (("dmg", palettes.DMG), ("pocket", palettes.POCKET)):
        cols, sc, cw, ch = 10, 4, 16 * 4 + 8, 16 * 4 + 18
        rows = (len(names) + cols - 1) // cols
        img = Image.new("RGB", (cols * cw + 8, rows * ch + 8), (200, 200, 200))
        d = ImageDraw.Draw(img)
        for i, n in enumerate(names):
            x, y = 8 + (i % cols) * cw, 8 + (i // cols) * ch
            img.paste(g.to_image(metas[n].ground, tones, sc), (x, y))
            d.text((x, y + 16 * sc + 1), n[:13], fill=(0, 0, 0))
        img.save(out / f"dungeon_tiles_{label}.png")
    heroes = hero_frames()
    for rname, (plan, extra, spr) in ROOMS.items():
        names_map = room(plan, extra)
        sprites = [(heroes.get(f, heroes["down_0"]), x, y) for f, x, y in spr]
        a = scene(names_map, sprites, palettes.DMG, 3)
        b = scene(names_map, sprites, palettes.POCKET, 3)
        img = Image.new("RGB", (a.width, a.height * 2 + 6), (60, 60, 70))
        img.paste(a, (0, 0))
        img.paste(b, (0, a.height + 6))
        img.save(out / f"dungeon_room_{rname}.png")
        one = Image.new("RGB", (240 * 2 + 4, 144), (60, 60, 70))
        one.paste(scene(names_map, sprites, palettes.DMG, 1), (0, 0))
        one.paste(scene(names_map, sprites, palettes.POCKET, 1), (244, 0))
        one.save(out / f"dungeon_room_{rname}_1x.png")


if __name__ == "__main__":
    preview()
