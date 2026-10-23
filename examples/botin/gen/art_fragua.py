"""Fragua (passage 4): a volcano forge. Palette set "fragua": the metatiles of the level and its four scenery pictures.

Cool blue-violet basalt (never black) set against hot oranges, reds and white-yellow lava, so heat is the only warm thing and it glows.
Banks of the set (slot meaning inside each):
    basalto  rock: 1 outline indigo, 2-6 basalt (deep indigo .. lilac), 7-b ember (dark red .. white-yellow), c magenta reflected glow,
             d pink rim light, e cream, f white
    lava     molten rock: 1 outline crimson, 2-7 lava (dark red .. white-hot), 8-a crust (violet .. pink), b-f spare warm tones
    metal    forged metal: 1 outline, 2-5 steel, 6-9 copper, a-c red-hot (red, orange, yellow), d violet shadow, e cream, f white
    cajas    blocks and boxes: 1 outline, 2-5 terracotta, 6-9 blue steel, a-c gold, d-e gem cyan, f white
    vapor    steam and smoke: 1-5 violet shadow .. white, 6-7 fire-lit steam, 8-9 ember, a-b smoke, c pale yellow
    lejos, medio, cerca, calor   the far / mid / near scenery and the blended heat-haze layer
The ground is the same edge-field rule as Galeón (see gen/art_galeon.py for the idea; the code is repeated here so each biome stands alone):
basalt columns inside, a rim of pink fire-light on top, the underside lit magenta by the lava below.
"""
from __future__ import annotations

import math
import sys
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent))
from gbakit import ART, flip_h, flip_v, overlay, pic, preview_metas, preview_scenery, shift  # noqa: E402

S = "fragua"

# ------------------------------------------------------------------ drawing helpers (pictures are lists of rows of slots)

BAYER = ((0, 8, 2, 10), (12, 4, 14, 6), (3, 11, 1, 9), (15, 7, 13, 5))
SIDES = ("n", "w", "e", "s")  # priority where two sides are equally near: the cap wins, then the lit post


def grid(w: int = 16, h: int = 16, v: int = 0) -> list[list[int]]:
    return [[v] * w for _ in range(h)]


def copy(p):
    return [row[:] for row in p]


def put(c, x: int, y: int, v: int) -> None:
    if 0 <= y < len(c) and 0 <= x < len(c[0]):
        c[y][x] = v


def rect(c, x0, y0, x1, y1, v) -> None:
    for y in range(y0, y1 + 1):
        for x in range(x0, x1 + 1):
            put(c, x, y, v)


def line(c, x0, y0, x1, y1, v) -> None:
    dx, dy = abs(x1 - x0), -abs(y1 - y0)
    sx, sy = (1 if x0 < x1 else -1), (1 if y0 < y1 else -1)
    err = dx + dy
    while True:
        put(c, x0, y0, v)
        if x0 == x1 and y0 == y1:
            return
        e2 = 2 * err
        if e2 >= dy:
            err += dy
            x0 += sx
        if e2 <= dx:
            err += dx
            y0 += sy


def disc(c, cx: float, cy: float, r: float, v: int) -> None:
    for y in range(int(cy - r - 1), int(cy + r + 2)):
        for x in range(int(cx - r - 1), int(cx + r + 2)):
            if (x - cx) ** 2 + (y - cy) ** 2 <= r * r + 0.3:
                put(c, x, y, v)


def hsh(*a: int) -> float:
    """A repeatable 0..1 value of some integers."""
    h = 2166136261
    for v in a:
        h = ((h ^ (v & 0xFFFFFFFF)) * 16777619) & 0xFFFFFFFF
    h ^= h >> 13
    h = (h * 0x5BD1E995) & 0xFFFFFFFF
    h ^= h >> 15
    return (h & 0xFFFF) / 65536


def dith(t: float, x: int, y: int) -> bool:
    return t * 16 > BAYER[y & 3][x & 3]


def ramp_at(t: float, x: int, y: int, slots) -> int:
    """A dithered pick along a ramp of slots, t in 0..1."""
    f = max(0.0, min(0.9999, t)) * (len(slots) - 1)
    i = int(f)
    return slots[min(len(slots) - 1, i + (1 if dith(f - i, x, y) else 0))]


def txt(s: str):
    return pic([r.strip() for r in s.strip("\n").split("\n")], 16, 16)


def outline_of(p, slot: int):
    """A one-pixel line of `slot` round what is drawn."""
    h, w = len(p), len(p[0])
    out = copy(p)
    for y in range(h):
        for x in range(w):
            if not p[y][x] and any(0 <= x + dx < w and 0 <= y + dy < h and p[y + dy][x + dx] for dx, dy in ((1, 0), (-1, 0), (0, 1), (0, -1))):
                out[y][x] = slot
    return out


def wave(x: float, terms, period: int = 256) -> float:
    """A sum of sines whose periods divide `period`, so the line wraps."""
    return sum(a * math.sin(2 * math.pi * k * x / period + ph) for a, k, ph in terms)


# ------------------------------------------------------------------ the edge field of the ground

def edge_field(mask: int, diag: str = ""):
    """(side, depth) of the nearest open pixel for each pixel of a tile, and a test `is_open(x, y)` in tile pixels (-16..31).
    mask: N 1 + E 2 + S 4 + W 8 open; `diag` names open diagonal neighbours ("ne", "sw"...) for inner corners."""
    o = {"n": mask & 1, "e": mask & 2, "s": mask & 4, "w": mask & 8}
    opn = {(1, 0): o["n"], (2, 1): o["e"], (1, 2): o["s"], (0, 1): o["w"], (1, 1): 0}
    for d in ("ne", "nw", "se", "sw"):
        opn[(2 if d[1] == "e" else 0, 0 if d[0] == "n" else 2)] = o[d[0]] or o[d[1]] or d in diag

    def is_open(x: int, y: int) -> bool:
        return bool(opn[((x + 16) // 16, (y + 16) // 16)])

    def side(dx: int, dy: int) -> str:
        if dy < 0 and -dy >= abs(dx):
            return "n"
        if dy > 0 and dy >= abs(dx):
            return "s"
        return "w" if dx < 0 else "e"

    out = [[None] * 16 for _ in range(16)]
    for y in range(16):
        for x in range(16):
            for r in range(1, 8):
                c = [(dx * dx + dy * dy, SIDES.index(side(dx, dy))) for dy in range(-r, r + 1) for dx in range(-r, r + 1)
                     if max(abs(dx), abs(dy)) == r and is_open(x + dx, y + dy)]
                if c:  # the nearest open pixel (straight across beats diagonal), ties by side priority
                    out[y][x] = (SIDES[min(c)[1]], r)
                    break
    return out, is_open


def ground_tile(mask: int, base, shade, diag: str = ""):
    """The base texture with the edges of `mask` shaded by shade(side, depth, x, y) -> slot or None, outer corners rounded off."""
    field, is_open = edge_field(mask, diag)
    c = copy(base)
    for y in range(16):
        for x in range(16):
            if field[y][x]:
                v = shade(field[y][x][0], field[y][x][1], x, y)
                if v is not None:
                    c[y][x] = v
    for y in range(16):
        for x in range(16):
            if (is_open(x, y - 1) or is_open(x, y + 1)) and (is_open(x - 1, y) or is_open(x + 1, y)):
                c[y][x] = 0
    return c



# ------------------------------------------------------------------ palettes

ART.palette(S, "basalto", ["#140a24", "#24123c", "#3a2058", "#523278", "#704ea0", "#a07ccc", "#7a1030", "#d82818", "#ff6c10",
                           "#ffb420", "#fff070", "#a02c78", "#ff7c8c", "#ffdca0", "#ffffff"])
ART.palette(S, "lava", ["#5a0828", "#a01020", "#e42c14", "#ff6410", "#ffa420", "#ffdc40", "#fffcb8", "#3c1046", "#6c2052",
                        "#b04064", "#ff8a50", "#ffc070", "#c81848", "#ff4080", "#ffffff"])
ART.palette(S, "metal", ["#160e30", "#2c2c5c", "#464e90", "#6c84c4", "#b4ccf4", "#6a2618", "#b85628", "#f08c48", "#ffd0a0",
                         "#d81c10", "#ff7410", "#ffd440", "#5a3074", "#fff4e0", "#ffffff"])
ART.palette(S, "cajas", ["#200c28", "#7a1c24", "#c43c22", "#f0782c", "#ffb464", "#1a2a80", "#2c5ac8", "#60a0f0", "#c0e4ff",
                         "#a85010", "#f0a820", "#fff070", "#18b8d8", "#b0f8ff", "#ffffff"])
ART.palette(S, "vapor", ["#3a2a6a", "#6a5aa8", "#a090d8", "#d8d0f8", "#ffffff", "#ffd0b8", "#ff9a70", "#ff6a20", "#ffd040",
                         "#2a1848", "#4a3070", "#fff0a0", "#c04070", "#806ab8", "#f4f0ff"])
ART.palette(S, "lejos", ["#120a30", "#1e0e48", "#30105a", "#4c1466", "#741a6a", "#a42062", "#d43a4c", "#ff6a30", "#ffa040",
                         "#ffe080", "#2a1050", "#3e1862", "#5a2074", "#ff3a20", "#fff4c0"])
ART.palette(S, "medio", ["#1a0a30", "#2a1040", "#3a1650", "#4e1c5e", "#6a2a70", "#a8406c", "#ff7a30", "#ffc040", "#fff0a0",
                         "#c02018", "#ff4a10", "#22124a", "#9c3c6c", "#ff9c60", "#4c2c84"])
ART.palette(S, "cerca", ["#100828", "#1e1040", "#301a5c", "#46287c", "#ff6a20", "#ffb040", "#c02818", "#5c3494", "#fff0a0",
                         "#7a1838", "#ff9a40", "#241650", "#3a2068", "#e04020", "#ffd880"])
ART.palette(S, "calor", ["#ff5a20", "#ff9a30", "#ffd060", "#fff4b0", "#ff3a6a", "#ff7a40", "#ffb850", "#ffe890", "#fffce0",
                         "#e83a50", "#ff6a80", "#ffa0a0", "#ff8a20", "#ffc848", "#ffffff"])

# ------------------------------------------------------------------ basalt: columns, a fire-lit rim, a glowing underside

COLS = ((0, 5, 3), (5, 11, 11), (11, 16, 7))  # x from, x to, the row of its joint


def basalt(seed: int = 0):
    """Basalt columns: a dark gap, a lit left face, a shaded right face; each column broken by one joint with a lit cap under it; pitting."""
    c = grid()
    for i, (a, b, jy) in enumerate(COLS):
        jy = (jy + seed * 5) % 16
        for y in range(16):
            for x in range(a, b):
                v = 2 if x == a else 5 if x == a + 1 else 3 if x == b - 1 else 4
                c[y][x] = v
            if y == jy:
                for x in range(a, b):
                    c[y][x] = 2
            elif y == (jy + 1) % 16:
                for x in range(a + 1, b - 1):
                    c[y][x] = 5 if x < b - 2 else 4
        for y in range(16):
            for x in range(a + 2, b - 1):
                h = hsh(x, y, seed, 31)
                if c[y][x] == 4 and h < 0.09:
                    c[y][x] = 3
                elif c[y][x] == 4 and h > 0.96:
                    c[y][x] = 5
    return c


def shade_basalt(side: str, d: int, x: int, y: int):
    if side == "n":
        if d == 2 and hsh(x, 3) < 0.22:
            return 10
        return {1: 1, 2: 9, 3: 13, 4: 6, 5: 2}.get(d)
    if side == "w":
        return {1: 1, 2: 6, 3: 5}.get(d)
    if side == "e":
        return {1: 1, 2: 2, 3: 3}.get(d)
    return {1: 1, 2: 12, 3: 7 if hsh(x, 5) < 0.4 else 3, 4: 3}.get(d)


def ember_crack(c, pts, core: int = 11, glow: int = 10) -> None:
    """A glowing crack along a path: a white-yellow core, an orange glow, a dark red halo on the rock."""
    for (x0, y0), (x1, y1) in zip(pts, pts[1:]):
        line(c, x0, y0, x1, y1, -1)
    cells = [(x, y) for y in range(len(c)) for x in range(len(c[0])) if c[y][x] == -1]
    for x, y in cells:
        for dx, dy in ((1, 0), (-1, 0), (0, 1), (0, -1)):
            if 0 <= y + dy < len(c) and 0 <= x + dx < len(c[0]) and c[y + dy][x + dx] not in (-1, glow, core):
                c[y + dy][x + dx] = 8 if (dx, dy) in ((0, -1), (-1, 0)) else 7
    for i, (x, y) in enumerate(cells):
        c[y][x] = core if i % 3 else glow


def basalt_alts():
    a0 = basalt(1)
    a1 = basalt(2)
    ember_crack(a1, [(2, 1), (5, 5), (4, 8), (8, 11), (12, 12), (14, 15)])
    a2 = basalt(0)  # an obsidian shard set in the rock
    for y in range(4, 12):
        w = (y - 4) // 2 if y < 8 else (11 - y)
        for x in range(8 - w, 9 + w):
            a2[y][x] = 2 if x > 8 else 6 if x == 8 - w + 1 and y < 9 else 3
    put(a2, 8, 5, 15)
    a3 = basalt(3)  # a pocket of magma glowing through
    for y in range(16):
        for x in range(16):
            d = math.hypot(x - 7.5, (y - 9) * 1.2)
            if d < 2.2:
                a3[y][x] = 11
            elif d < 3.4:
                a3[y][x] = 10
            elif d < 4.4:
                a3[y][x] = 9 if y < 9 else 8
            elif d < 5.2:
                a3[y][x] = 1 if y > 9 else 7
    return [a0, a1, a2, a3]


def register_ground() -> None:
    base = basalt()
    for m in range(16):
        ART.meta(S, f"ground_m{m}", ground_tile(m, base, shade_basalt), "basalto")
    for i, alt in enumerate(basalt_alts()):
        ART.meta(S, f"ground_alt{i}", alt, "basalto")
    b = ground_tile(1, basalt(1), shade_basalt)  # embers glowing in the rim
    ember_crack(b, [(3, 4), (5, 7), (4, 10)])
    ART.meta(S, "ground_m1_b", b, "basalto")
    cc = ground_tile(1, basalt(2), shade_basalt)  # a cooled lava crust poured over the top
    for x in range(16):
        h = 3 + int(hsh(x, 13) * 2.5) + (2 if 5 <= x <= 9 else 0)
        for y in range(1, h + 1):
            cc[y][x] = 6 if y == 1 else 12 if y == h else 4 if y < h - 1 else 3
        cc[h + 1][x] = 1
    put(cc, 7, 6, 10)
    ART.meta(S, "ground_m1_c", cc, "basalto")
    for d in ("ne", "nw", "se", "sw"):
        ART.meta(S, f"ground_in_{d}", ground_tile(0, base, shade_basalt, d), "basalto")


# ------------------------------------------------------------------ platforms, walls

def slab(left: bool, right: bool, seed: int = 0):
    """A basalt slab ledge: pink-lit top, a magenta glow underneath, rock teeth hanging below."""
    c = grid()
    for i, v in enumerate((1, 13, 6, 5, 4, 12, 1)):
        rect(c, 0, i, 15, i, v)
    for x in range(16):
        ln = int(hsh(x // 2, seed, 4) * 3)
        for k in range(ln):
            put(c, x, 6 + k, 3 if k < ln - 1 else 2)
        put(c, x, 6 + ln, 1)
        if x % 5 == seed % 5:
            put(c, x, 3, 6)
    for x in (4, 11):
        put(c, x, 1, 10)
    if left:
        for y in range(7):
            put(c, 0, y, 1)
        c[0][0] = 0
        c[0][1] = 1
        for y in range(6, 10):
            put(c, 0, y, 0)
            put(c, 1, y, 1 if y < 8 else 0)
    if right:
        for y in range(7):
            put(c, 15, y, 1)
        c[0][15] = 0
        c[0][14] = 1
        for y in range(6, 10):
            put(c, 15, y, 0)
            put(c, 14, y, 1 if y < 8 else 0)
    return c


def girder(left: bool, right: bool):
    """A riveted iron girder hung by chains (the chain comes down to the eye bolt at x 6..9 of the end pieces)."""
    c = grid()
    for i, v in enumerate((1, 5, 4, 3, 3, 2, 1)):
        rect(c, 0, i, 15, i, v)
    for x in range(1, 16, 4):
        put(c, x, 3, 1)
        put(c, x, 2, 5)
    for x in range(16):  # lightening holes in the web below
        for y in range(7, 11):
            put(c, x, y, 0)
    for x0 in (0, 8):
        rect(c, x0 + 1, 7, x0 + 6, 9, 2)
        rect(c, x0 + 2, 7, x0 + 5, 8, 0)
        put(c, x0 + 1, 10, 1)
        rect(c, x0 + 1, 10, x0 + 6, 10, 1)
    for x in range(16):
        c[7][x] = c[7][x] or 1
    if left or right:
        rect(c, 6, 1, 9, 2, 6)
        put(c, 6, 1, 8)
        put(c, 7, 1, 7)
        rect(c, 7, 0, 8, 0, 1)
    if left:
        for y in range(11):
            put(c, 0, y, 1 if c[y][0] else 0)
        c[0][0] = 0
    if right:
        for y in range(11):
            put(c, 15, y, 1 if c[y][15] else 0)
        c[0][15] = 0
    return c


def masonry(seed: int):
    """Dark forge masonry: courses of basalt blocks in shade, mortar lines, soot."""
    c = grid()
    for y in range(16):
        course = y // 4
        off = 4 if course % 2 else 0
        for x in range(16):
            r, bx = y % 4, (x + off + seed * 3) % 8
            c[y][x] = 1 if r == 3 or bx == 7 else 3 if r == 0 or bx == 0 else 2
            if r in (1, 2) and 1 <= bx <= 6 and hsh(x, y, seed) < 0.12:
                c[y][x] = 3
    return c


def register_platforms_walls() -> None:
    for n, (l, r) in (("plat_l", (True, False)), ("plat_m", (False, False)), ("plat_r", (False, True)), ("plat_s", (True, True))):
        ART.meta(S, n, slab(l, r, len(n)), "basalto")
        if n != "plat_s":
            ART.meta(S, "chain_" + n, girder(l, r), "metal")
    a = masonry(0)
    b = masonry(1)  # a furnace slot glowing in the wall
    rect(b, 3, 5, 12, 10, 1)
    rect(b, 4, 6, 11, 9, 8)
    rect(b, 4, 8, 11, 9, 9)
    rect(b, 5, 9, 10, 9, 10)
    for x in (5, 8, 11):
        rect(b, x, 6, x, 9, 1)
    rect(b, 3, 4, 12, 4, 3)
    c = masonry(2)  # an iron plate bolted to the wall (lilac tones of the rock bank)
    rect(c, 2, 2, 13, 13, 1)
    rect(c, 3, 3, 12, 12, 4)
    rect(c, 3, 3, 12, 3, 5)
    rect(c, 3, 3, 3, 12, 5)
    rect(c, 4, 12, 12, 12, 3)
    rect(c, 12, 4, 12, 12, 3)
    for x, y in ((4, 4), (11, 4), (4, 11), (11, 11)):
        put(c, x, y, 6)
        put(c, x + (1 if x < 8 else -1), y + (1 if y < 8 else -1), 2)
    d = masonry(3)  # a crack with a faint glow behind
    ember_crack(d, [(9, 0), (7, 4), (8, 7), (6, 11), (7, 15)], core=9, glow=8)
    for n, p in (("back_a", a), ("back_b", b), ("back_c", c), ("back_d", d)):
        ART.meta(S, n, p, "basalto")


# ------------------------------------------------------------------ blocks and boxes

def bevel_block(face, light, dark, ol=1, edge=2):
    c = grid(16, 16, face)
    for i in range(edge):
        rect(c, 1 + i, 1 + i, 14 - i, 1 + i, light)
        rect(c, 1 + i, 1 + i, 1 + i, 14 - i, light)
        rect(c, 1 + i, 14 - i, 14 - i, 14 - i, dark)
        rect(c, 14 - i, 1 + i, 14 - i, 14 - i, dark)
    for k in range(16):
        c[0][k] = c[15][k] = c[k][0] = c[k][15] = ol
    c[0][0] = c[0][15] = c[15][0] = c[15][15] = 0
    return c


def register_blocks() -> None:
    # brown: four fired terracotta bricks, chipped and cracked
    br = grid(16, 16, 3)
    for y in range(16):
        for x in range(16):
            bx, by = x % 8, y % 8
            off = (x + (4 if (y // 8) % 2 else 0)) % 8
            if by == 7 or off == 7:
                br[y][x] = 1
            elif by == 0 or off == 0:
                br[y][x] = 4
            elif by == 6 or off == 6:
                br[y][x] = 2
    for x, y in ((3, 2), (4, 3), (4, 4), (11, 10), (12, 11), (10, 12)):
        br[y][x] = 1
        put(br, x + 1, y, 4)
    for k in range(16):
        br[0][k] = br[15][k] = br[k][0] = br[k][15] = 1
    br[0][0] = br[0][15] = br[15][0] = br[15][15] = 0
    ART.meta(S, "block_brown", br, "cajas")
    # blue: a blue steel crate, cross-braced, riveted
    bl = bevel_block(7, 8, 6)
    line(bl, 3, 3, 12, 12, 6)
    line(bl, 3, 4, 11, 12, 8)
    line(bl, 12, 3, 3, 12, 6)
    line(bl, 12, 4, 4, 12, 8)
    for x, y in ((2, 2), (13, 2), (2, 13), (13, 13)):
        put(bl, x, y, 11)
    ART.meta(S, "block_blue", bl, "cajas")
    # hard: forged iron, four bolts, a white-hot seam
    hd = bevel_block(3, 4, 2, edge=3)
    rect(hd, 4, 4, 11, 11, 2)
    rect(hd, 5, 5, 10, 10, 3)
    rect(hd, 4, 7, 11, 8, 10)
    rect(hd, 5, 7, 10, 7, 11)
    rect(hd, 6, 8, 9, 8, 12)
    for x, y in ((2, 2), (12, 2), (2, 12), (12, 12)):
        rect(hd, x, y, x + 1, y + 1, 5)
        put(hd, x + 1, y + 1, 2)
    ART.meta(S, "block_hard", hd, "metal")
    # fire: black rock full of ember cracks, burns away only under a burning hero
    fb = grid(16, 16, 2)
    for y in range(16):
        for x in range(16):
            if hsh(x, y, 61) < 0.18:
                fb[y][x] = 3
    ember_crack(fb, [(1, 3), (5, 5), (8, 3), (12, 6), (15, 5)])
    ember_crack(fb, [(3, 15), (5, 11), (9, 10), (11, 13), (14, 12)])
    ember_crack(fb, [(8, 4), (7, 8), (9, 10)])
    for k in range(16):
        fb[0][k] = fb[15][k] = fb[k][0] = fb[k][15] = 1
    rect(fb, 1, 1, 14, 1, 4)
    rect(fb, 1, 1, 1, 14, 3)
    fb[0][0] = fb[0][15] = fb[15][0] = fb[15][15] = 0
    ART.meta(S, "block_fire", fb, "basalto")

    def crate():
        c = bevel_block(3, 4, 2)
        for y in (5, 10):
            rect(c, 2, y, 13, y, 2)
            rect(c, 2, y + 1, 13, y + 1, 4)
        for x in (1, 14):  # iron straps
            rect(c, x, 1, x, 14, 6 if x == 14 else 7)
        rect(c, 1, 1, 14, 1, 7)
        rect(c, 1, 14, 14, 14, 6)
        for x, y in ((1, 1), (14, 1), (1, 14), (14, 14)):
            put(c, x, y, 11)
        return c
    jw = crate()
    gem = txt("""
        ................
        ................
        ................
        ......1111......
        .....1deed1.....
        ....1deffed1....
        ...1ddeeeddd1...
        ...1ddddddd51...
        ....1ddddd51....
        .....1dd551.....
        ......1551......
        .......11.......
        ................
        ................
        ................
        ................""")
    gem = [[{5: 6}.get(v, v) for v in row] for row in gem]
    jw = overlay(jw, gem)
    put(jw, 4, 4, 15)
    ART.meta(S, "box_jewel", jw, "cajas")
    cn = crate()
    for cx, cy in ((5, 6), (10, 6), (7, 10)):
        disc(cn, cx, cy, 2.6, 1)
        disc(cn, cx, cy, 1.8, 11)
        put(cn, cx - 1, cy - 1, 12)
        put(cn, cx + 1, cy + 1, 10)
        put(cn, cx, cy, 10)
    ART.meta(S, "box_coin", cn, "cajas")


def spike_row():
    """Three steel spikes heated red at the tips, on a riveted steel base."""
    c = grid()
    for cx in (2.5, 8, 13.5):
        for y in range(1, 13):
            half = (y - 1) / 11 * 2.6
            for x in range(16):
                dx = x + 0.5 - cx
                if abs(dx) <= half + 0.35:
                    if y < 4:
                        v = 12 if y < 2 else 11
                    elif y < 6:
                        v = 10
                    else:
                        v = 5 if (dx < -half + 1.2 and y < 10) else 4 if dx < 0 else 3 if dx < half - 0.8 else 2
                    c[y][x] = v
    c = outline_of(c, 1)
    rect(c, 0, 12, 15, 12, 1)
    rect(c, 0, 13, 15, 13, 4)
    rect(c, 0, 14, 15, 14, 3)
    rect(c, 0, 15, 15, 15, 1)
    for x in (2, 8, 13):
        put(c, x, 14, 5)
    return c


# ------------------------------------------------------------------ animated pieces

def lava_value(x: int, y: int, f: int) -> float:
    """A 16-periodic flow field: bright streaks drifting right 4 pixels a frame, slow swirl."""
    u = 2 * math.pi * (x - f * 4) / 16
    v = 2 * math.pi * y / 16
    return 0.5 + 0.28 * math.sin(u + math.sin(v) * 1.2) + 0.22 * math.sin(v * 2 + math.cos(u) * 1.5 + f * math.pi / 2)


def lava_fill(f: int):
    c = grid()
    for y in range(16):
        for x in range(16):
            t = lava_value(x, y, f)
            c[y][x] = 6 if t > 0.92 else 5 if t > 0.72 else 4 if t > 0.42 else 3
            if t < 0.16:
                c[y][x] = 9 if t > 0.08 else 8
    return c


def lava_surface(f: int):
    c = lava_fill(f)
    for x in range(16):
        top = 4 + round(1.3 * math.sin(2 * math.pi * (x / 16 - f / 4)) + 0.6 * math.sin(2 * math.pi * (2 * x / 16 + f / 4)))
        for y in range(16):
            if y < top:
                c[y][x] = 0
            elif y == top:
                c[y][x] = 7
            elif y == top + 1:
                c[y][x] = 6
            elif y == top + 2:
                c[y][x] = 5
    bx = 10  # a bubble growing and bursting at the surface
    if f == 0:
        disc(c, bx, 4, 1.2, 6)
        put(c, bx, 3, 7)
    elif f == 1:
        disc(c, bx, 3, 2.2, 5)
        disc(c, bx - 0.5, 2.5, 1, 7)
        put(c, bx - 2, 1, 0)
    elif f == 2:
        for dx, dy in ((-3, 0), (3, 0), (-2, -2), (2, -2), (0, -3)):
            put(c, bx + dx, 3 + dy, 6)
    else:
        put(c, bx - 4, 0, 5)
        put(c, bx + 3, 1, 4)
    return c


def gear(f: int):
    """A steel gear of 8 teeth turned a quarter of a tooth a frame (4 frames = one tooth): flat faces, a lit rim top-left, a sunk ring, a copper hub."""
    c = grid()
    rot = f * (2 * math.pi / 8) / 4
    for y in range(16):
        for x in range(16):
            dx, dy = x + 0.5 - 8, y + 0.5 - 8
            r = math.hypot(dx, dy)
            a = (math.atan2(dy, dx) - rot) % (2 * math.pi / 8)
            tooth = a / (2 * math.pi / 8) < 0.46
            lit = dx * -0.6 + dy * -0.8
            if r <= 5.6:
                c[y][x] = 4
                if r > 4.6:
                    c[y][x] = 5 if lit > 1.5 else 2 if lit < -1.5 else 3
                elif 2.4 < r <= 3.6:
                    c[y][x] = 2 if lit > 0 else 3
            elif tooth and r <= 7.5:
                c[y][x] = 5 if lit > 2.5 else 2 if lit < -2.5 else 3
            if r <= 2.4:
                c[y][x] = 8 if lit > 0.3 else 7
            if r < 0.8:
                c[y][x] = 1
    return outline_of(c, 1)


def puff(c, cx: float, cy: float, r: float, fade: float) -> None:
    """A billowing cloud of steam: three round lobes, lit white on the upper left, fire-lit underneath, thinned by a dither as it fades."""
    lobes = ((-r * 0.45, 0, r * 0.6), (r * 0.45, r * 0.05, r * 0.58), (0, -r * 0.35, r * 0.66), (0, r * 0.3, r * 0.55))
    for y in range(16):
        for x in range(16):
            px, py = x + 0.5, y + 0.5
            if not any(math.hypot(px - cx - ox, py - cy - oy) <= rr for ox, oy, rr in lobes):
                continue
            if fade and dith(fade, x, y):
                continue
            rel = (px - cx) * 0.5 + (py - cy)
            c[y][x] = 5 if rel < -r * 0.3 else 6 if py - cy > r * 0.6 else 4 if rel < r * 0.35 else 3


def steam(f: int):
    """A puff of steam rising, swelling and dissolving while the next one is born below (4 frames loop)."""
    c = grid()
    big = ((8, 11, 4.4, 0.0), (8, 8.5, 5.6, 0.0), (8.5, 6, 6.6, 0.3), (9, 4, 7.2, 0.62))[f]
    small = (None, None, (7.5, 13, 2.6, 0.0), (7.5, 11.5, 3.6, 0.0))[f]
    puff(c, *big)
    if small:
        puff(c, *small)
    return c


def register_animated() -> None:
    for f in range(4):
        ART.meta(S, f"lava_surface_{f}", lava_surface(f), "lava")
        ART.meta(S, f"lava_fill_{f}", lava_fill(f), "lava")
        ART.meta(S, f"gear_{f}", gear(f), "metal")
        ART.meta(S, f"steam_{f}", steam(f), "vapor")


# ------------------------------------------------------------------ forge decor

def pipes():
    a = grid()  # horizontal copper pipe with a flange and a rivet band
    for y in range(4, 12):
        t = (y - 4) / 7
        v = 9 if t < 0.15 else 8 if t < 0.35 else 7 if t < 0.7 else 6
        rect(a, 0, y, 15, y, v)
    for x in (9, 10, 11):
        for y in range(3, 13):
            put(a, x, y, 8 if y < 6 else 7 if y < 10 else 6)
    put(a, 10, 4, 9)
    rect(a, 9, 2, 11, 2, 1)
    rect(a, 9, 13, 11, 13, 1)
    rect(a, 0, 3, 8, 3, 1)
    rect(a, 12, 3, 15, 3, 1)
    rect(a, 0, 12, 8, 12, 1)
    rect(a, 12, 12, 15, 12, 1)
    put(a, 3, 6, 14)
    b = [list(r) for r in zip(*a)]  # vertical: the same pipe turned, the light kept on its left
    c = grid()  # an elbow from the left going down, with a pressure gauge
    for y in range(16):
        for x in range(16):
            dx, dy = x - 0, y - 16
            r = math.hypot(dx - 0.5, dy + 0.5)
            if 4 <= r <= 11.5 and x <= 15:
                t = (r - 4) / 7.5
                c[y][x] = 9 if t < 0.15 else 8 if t < 0.4 else 7 if t < 0.75 else 6
            elif 3 <= r < 4 or 11.5 < r <= 12.5:
                c[y][x] = 1
    disc(c, 11, 4, 3.4, 1)
    disc(c, 11, 4, 2.6, 14)
    line(c, 11, 4, 12, 2, 10)
    put(c, 11, 4, 1)
    put(c, 9, 3, 2)
    put(c, 13, 6, 2)
    return a, b, c


def anvil():
    return txt("""
        ................
        ................
        ......aabba.....
        .....abcccba....
        11111111111111..
        145555555554431.
        .1444444444331..
        ..11133332111...
        .....1332d1.....
        .....1322d1.....
        ....133322d1....
        ...1666666661...
        ...1877777661...
        ...1766666651...
        ...1666666651...
        ...1111111111...""")


def deco_pieces():
    out = {}
    # a: a brazier of coals on three legs
    a = grid()
    for y in range(7, 11):
        w = 7 - (y - 7)
        rect(a, 8 - w, y, 7 + w, y, 3 if y > 7 else 4)
    rect(a, 1, 7, 14, 7, 4)
    for x in range(2, 14):
        put(a, x, 6, 11 if hsh(x, 1) < 0.5 else 10)
        put(a, x, 5, 12 if hsh(x, 2) < 0.3 else 11 if hsh(x, 3) < 0.6 else 0)
    for x, y in ((5, 4), (8, 3), (10, 4), (7, 2), (9, 1)):
        put(a, x, y, 11 if y > 2 else 12)
    line(a, 5, 11, 3, 15, 2)
    line(a, 10, 11, 12, 15, 2)
    line(a, 8, 11, 8, 15, 2)
    out["deco_a"] = (outline_of(a, 1), "metal")
    # b: a warning sign on a post
    b = txt("""
        .......11.......
        ......1bb1......
        .....1bbbb1.....
        ....1bb11bb1....
        ...1bbb11bbb1...
        ..1bbbb11bbbb1..
        .1bbbbb11bbbbb1.
        1bbbbbbbbbbbbbb1
        1bbbbbb11bbbbbb1
        .1aaaaaaaaaaaa1.
        ..111111111111..
        .......23.......
        .......23.......
        .......23.......
        ......1231......
        .....122221.....""")
    out["deco_b"] = (b, "cajas")
    # c: a stack of gold ingots
    c = grid()
    for (x0, y0) in ((1, 11), (8, 11), (4, 7)):
        rect(c, x0, y0, x0 + 6, y0 + 3, 11)
        rect(c, x0 + 1, y0, x0 + 5, y0, 12)
        rect(c, x0, y0 + 3, x0 + 6, y0 + 3, 10)
        put(c, x0 + 1, y0 + 1, 15)
    out["deco_c"] = (outline_of(c, 1), "cajas")
    # d: a smith's hammer and tongs leaning on a rack
    d = grid()
    line(d, 3, 15, 5, 3, 7)
    line(d, 4, 15, 6, 3, 6)
    rect(d, 3, 1, 8, 3, 3)
    rect(d, 3, 1, 8, 1, 5)
    rect(d, 3, 3, 8, 3, 2)
    line(d, 11, 15, 10, 4, 3)
    line(d, 13, 15, 10, 4, 4)
    rect(d, 9, 2, 11, 4, 3)
    put(d, 10, 2, 11)
    rect(d, 0, 14, 15, 15, 2)
    rect(d, 0, 14, 15, 14, 3)
    out["deco_d"] = (outline_of(d, 1), "metal")
    # e: obsidian shards growing from the floor
    e = grid()
    for cx, h, w in ((5, 11, 2), (9, 14, 2.5), (12, 8, 1.6)):
        for y in range(16 - h, 16):
            half = w * (y - (16 - h)) / h + 0.6
            for x in range(16):
                dx = x + 0.5 - cx
                if abs(dx) <= half:
                    e[y][x] = 6 if dx < -half + 1 else 3 if dx < 0.3 else 2
        put(e, int(cx), 16 - h, 15)
    out["deco_e"] = (outline_of(e, 1), "basalto")
    # f: a pair of bellows
    f = grid()
    for y in range(16):
        for x in range(16):
            dx, dy = (x - 6) / 6, (y - 9) / 5.5
            if dx * dx + dy * dy <= 1:
                f[y][x] = 4 if dy < -0.3 else 3 if (y % 2 == 0) else 2
    rect(f, 11, 8, 15, 10, 6)
    rect(f, 11, 8, 15, 8, 8)
    rect(f, 2, 2, 3, 6, 10)
    put(f, 2, 2, 11)
    rect(f, 8, 2, 9, 5, 10)
    out["deco_f"] = (outline_of(f, 1), "cajas")
    # g: a little furnace mouth in a stone hump
    g = grid()
    for y in range(4, 16):
        for x in range(16):
            dx, dy = (x - 7.5) / 7.5, (y - 16) / 12
            if dx * dx + dy * dy <= 1:
                g[y][x] = 5 if dx < -0.5 and dy < -0.4 else 4 if dx < 0 else 3
    for y in range(9, 16):
        for x in range(16):
            dx, dy = (x - 7.5) / 3.6, (y - 16) / 6
            if dx * dx + dy * dy <= 1:
                g[y][x] = 11 if dy > -0.4 and abs(dx) < 0.5 else 10 if dy > -0.7 else 9
    for x in (5, 10):
        rect(g, x, 10, x, 15, 1)
    rect(g, 3, 8, 12, 8, 2)
    put(g, 7, 5, 10)
    out["deco_g"] = (outline_of(g, 1), "basalto")
    # h: a rock spire with a drip of molten rock
    h = grid()
    for y in range(2, 16):
        half = (y - 2) / 13 * 4 + 0.6
        for x in range(16):
            dx = x + 0.5 - 7
            if abs(dx) <= half:
                h[y][x] = 6 if dx < -half + 1 else 4 if dx < 0 else 3
    for y in range(5, 11):
        put(h, 8, y, 9 if y < 9 else 10)
    put(h, 8, 11, 11)
    put(h, 7, 2, 13)
    out["deco_h"] = (outline_of(h, 1), "basalto")
    return out


def front_pieces():
    out = {}
    a = grid()  # a chain hanging, links at x 6..9 (the eye bolts of the chain platforms)
    for k in range(4):
        y0 = k * 4
        if k % 2 == 0:
            rect(a, 6, y0, 9, y0 + 4, 1)
            rect(a, 7, y0 + 1, 8, y0 + 3, 0)
            put(a, 6, y0 + 1, 4)
            put(a, 6, y0 + 2, 3)
            put(a, 7, y0, 4)
        else:
            rect(a, 7, y0, 8, y0 + 4, 3)
            put(a, 7, y0 + 1, 5)
            put(a, 6, y0 + 2, 1)
            put(a, 9, y0 + 2, 1)
    out["front_a"] = (a, "metal")
    b = [row[:] for row in a]  # the chain ending in a hook
    for y in range(8, 16):
        for x in range(16):
            b[y][x] = 0
    rect(b, 7, 8, 8, 10, 3)
    hook = [(8, 11), (8, 12), (7, 13), (6, 13), (5, 12), (5, 11), (4, 10)]
    for x, y in hook:
        put(b, x, y, 4)
        put(b, x + 1, y, 2)
    out["front_b"] = (outline_of(b, 1), "metal")
    c = grid()  # a basalt stalactite with a molten drip
    for y in range(0, 12):
        half = (11 - y) / 11 * 5 + 0.4
        for x in range(16):
            dx = x + 0.5 - 8
            if abs(dx) <= half:
                c[y][x] = 6 if dx < -half + 1.2 else 4 if dx < 0 else 3 if dx < half - 1 else 2
    for y in range(3, 12):
        put(c, 8, y, 9 if y < 9 else 10)
    disc(c, 8, 13.5, 1.0, 10)
    put(c, 8, 13, 11)
    out["front_c"] = (outline_of(c, 1), "basalto")
    d = grid()  # a wisp of dark smoke
    for k in range(5):
        cx, cy, r = 5 + k * 1.6, 14 - k * 3, 2.2 + k * 0.4
        for y in range(16):
            for x in range(16):
                if math.hypot(x - cx, y - cy) <= r and dith(0.9 - k * 0.14, x, y):
                    d[y][x] = 11 if (x - cx) + (y - cy) < 0 else 10
    out["front_d"] = (d, "vapor")
    e = pipes()[1]  # a copper pipe running past in front
    out["front_e"] = (e, "metal")
    f = grid()  # drifting embers
    for i, (x, y) in enumerate(((3, 12), (9, 4), (12, 10), (6, 7), (14, 2), (2, 3))):
        put(f, x, y, 5 if i % 2 else 6)
        put(f, x + 1, y, 4)
        if i % 3 == 0:
            put(f, x, y - 1, 7)
    out["front_f"] = (f, "lava")
    g = grid()  # a bank of steam rolling along the floor
    for cx, cy, r in ((3, 14, 4), (9, 13, 5), (14, 14, 3.5)):
        for y in range(16):
            for x in range(16):
                if math.hypot(x - cx, (y - cy) * 1.2) <= r:
                    g[y][x] = 5 if y < cy - r * 0.5 else 4 if (x + y) % 3 else 3
    out["front_g"] = (g, "vapor")
    h = grid()  # foreground basalt spires
    for cx, top, w in ((3, 4, 3.4), (10, 8, 2.6), (14, 11, 2.2)):
        for y in range(top, 16):
            half = (y - top) / (16 - top) * w + 0.6
            for x in range(16):
                dx = x + 0.5 - cx
                if abs(dx) <= half:
                    h[y][x] = 13 if dx < -half + 1 else 2 if dx < 0.5 else 1
    out["front_h"] = (h, "basalto")
    return out


def register_decor() -> None:
    for name, (p, bank) in deco_pieces().items():
        ART.meta(S, name, p, bank)
    empty = grid()
    for name, (p, bank) in front_pieces().items():
        ART.meta(S, name, empty, bank, front=p, front_bank=bank)
    a, b, c = pipes()
    ART.meta(S, "forge_pipe_a", a, "metal")
    ART.meta(S, "forge_pipe_b", b, "metal")
    ART.meta(S, "forge_pipe_c", c, "metal")
    ART.meta(S, "anvil_decor", anvil(), "metal")
    ART.meta(S, "spikes_up", spike_row(), "metal")
    ART.meta(S, "spikes_down", flip_v(spike_row()), "metal")
    ma = grid()  # a boulder split by a glowing crack
    for y in range(4, 16):
        for x in range(16):
            dx, dy = (x - 7.5) / 7.5, (y - 15.5) / 11
            if dx * dx + dy * dy <= 1:
                ma[y][x] = 6 if dx < -0.4 and dy < -0.5 else 5 if dx < -0.2 else 4 if dx < 0.4 else 3
    ember_crack(ma, [(8, 5), (7, 8), (9, 11), (8, 15)])
    ART.meta(S, "magma_crack_a", outline_of(ma, 1), "basalto")
    mb = grid()  # a flat crust broken, glow welling up
    for y in range(10, 16):
        for x in range(16):
            mb[y][x] = 5 if y == 10 else 4 if y < 13 else 3
    ember_crack(mb, [(0, 13), (4, 12), (7, 14), (11, 12), (15, 13)])
    for x, y in ((5, 9), (9, 8), (12, 9)):
        put(mb, x, y, 9)
    put(mb, 9, 7, 10)
    ART.meta(S, "magma_crack_b", outline_of(mb, 1), "basalto")


# ------------------------------------------------------------------ scenery

def scenery_far():
    """A violet night sky burning orange at the horizon; two volcanoes, lit pink on the side facing the glow, crater halos, meandering lava
    rivers, a smoke plume; a lava lake along the bottom."""
    W, H = 256, 160
    c = grid(W, H)
    sky = (1, 2, 3, 4, 5, 6, 7, 8, 9)
    cones = ((70, 44, 0.66), (190, 64, 0.82))
    for y in range(H):
        for x in range(W):
            t = min(1.0, (y / 128) ** 1.7)
            for cx, top, _ in cones:  # the sky glows above each crater
                dx = min(abs(x - cx), W - abs(x - cx))
                g = max(0.0, 1 - math.hypot(dx, (y - top) * 1.4) / 34)
                t = max(t, 0.55 * g + t * (1 - g))
            c[y][x] = ramp_at(t, x, y, sky)
    hs = [0.0] * W
    for x in range(W):
        h = 112 + wave(x, ((5, 3, 0.2), (3, 7, 1.0), (1.5, 19, 2.0)))
        for cx, top, slope in cones:
            dx = min(abs(x - cx), W - abs(x - cx))
            h = min(h, top + max(0, dx - 6) * slope + wave(x, ((1.2, 23, cx),)) * (dx > 8))
        hs[x] = h
    for x in range(W):
        for y in range(int(hs[x]), 140):
            d = y - int(hs[x])
            lit = hs[(x + 1) % W] > hs[x] + 0.2 or hs[(x - 1) % W] > hs[x] + 0.2
            ridge = math.sin(x * 0.55 + y * 0.12 + 2 * math.sin(y * 0.07 + x * 0.02)) > 0.9 and hsh(x // 3, y // 9) < 0.6
            c[y][x] = 13 if d < 2 and lit else 12 if (ridge or dith(max(0.0, 0.45 - d / 60), x, y)) else 11
    for cx, top, slope in cones:  # crater lips and rivers of lava meandering down
        for x in range(cx - 6, cx + 7):
            c[top][x % W] = 15 if abs(x - cx) < 4 else 10
            c[top + 1][x % W] = 14
        for k, sgn in enumerate((-1, 1, 1)):
            x = float(cx + sgn * (2 + k * 2))
            for y in range(top + 2, 138):
                x += sgn * slope ** -1 * 0.35 + math.sin(y * 0.25 + k * 2) * 0.45
                hot = y < top + 16
                c[y][int(x) % W] = 15 if hot and y < top + 6 else 14 if hot else 9
                c[y][(int(x) + 1) % W] = 8 if y % 2 else c[y][(int(x) + 1) % W]
    for y in range(2, 44):  # a smoke plume drifting right from the big crater
        k = 44 - y
        cx = 70 + k * 0.9 + math.sin(y * 0.2) * 4
        r = 3 + k * 0.33
        for x in range(int(cx - r), int(cx + r) + 1):
            if dith(0.62 - k / 90, x, y):
                c[y][x % W] = 12 if x < cx + r * 0.3 else 11
    for y in range(138, H):  # the lava lake at the foot: bright shore line, slow crusted surface
        for x in range(W):
            t = math.sin(2 * math.pi * x * 5 / W + y * 0.9) + 0.6 * math.sin(2 * math.pi * x * 13 / W - y * 0.5)
            c[y][x] = 10 if t > 1.3 else 9 if t > 0.5 else 8 if t > -0.9 else 14
        if y == 138:
            for x in range(W):
                c[y][x] = 15 if x % 9 else 10
    for i in range(60):  # stars and drifting embers
        x, y = int(hsh(i, 1) * W), int(hsh(i, 2) * 74)
        if c[y][x] <= 4:
            c[y][x] = 15 if i % 4 == 0 else 6
    return c


def kiln(c, cx: int, base: int, r: int) -> None:
    """A beehive kiln: a dome of brick courses with a glowing arched mouth."""
    W = len(c[0])
    for y in range(base - r, base):
        for x in range(cx - r, cx + r + 1):
            dx, dy = (x - cx) / r, (y - base) / r
            if dx * dx + dy * dy <= 1:
                v = 5 if dx < -0.55 else 4 if dx < 0.1 else 3
                if (y - base) % 5 == 0:
                    v = 2
                c[y][x % W] = v
    mw, mh = r // 3, r // 2
    for y in range(base - mh, base):
        for x in range(cx - mw, cx + mw + 1):
            dx, dy = (x - cx) / (mw + 0.5), (y - base) / (mh + 0.5)
            if dx * dx + dy * dy <= 1:
                c[y][x % W] = 8 if dy > -0.4 and abs(dx) < 0.5 else 7 if dy > -0.75 else 10
    for y in range(base - r - 8, base - r + 2):  # its flue
        for x in range(cx - 2, cx + 3):
            c[y][x % W] = 5 if x == cx - 2 else 3


def chimney(c, cx: int, top: int, base: int, w: int) -> None:
    W = len(c[0])
    for y in range(top, base):
        half = w + (y - top) * 0.06
        for x in range(int(cx - half), int(cx + half) + 1):
            lx = (x - (cx - half)) / (2 * half)
            v = 5 if lx < 0.2 else 4 if lx < 0.5 else 3 if lx < 0.85 else 2
            if (y - top) in (3, 4):
                v = 6 if lx < 0.5 else 13
            c[y][x % W] = v
    for x in range(cx - w - 1, cx + w + 2):
        c[top][x % W] = 6
    for y in range(max(0, top - 34), top):  # smoke leaning with the wind
        k = top - y
        sx, r = cx + k * 0.6, 1.5 + k * 0.22
        for x in range(int(sx - r), int(sx + r) + 1):
            if dith(0.6 - k / 80, x, y):
                c[y][x % W] = 13 if x < sx else 15


def scenery_mid():
    """The forge works on a rock shelf: beehive kilns with glowing mouths, tall smokestacks, a pipe bridge, a giant cog half buried,
    a crucible pouring lava down the cliff; sky see-through between."""
    W, H = 256, 128
    c = grid(W, H)
    for x in range(W):  # the rock shelf
        top = int(96 + wave(x, ((5, 4, 0.3), (3, 9, 1.2), (2, 21, 2.1))))
        for y in range(top, H):
            d = y - top
            c[y][x] = 6 if d == 0 else 5 if d < 2 else 4 if d < 5 else 3 if dith(max(0.0, 1 - (d - 5) / 10), x, y) else 2
    for y in range(64, 104):  # a giant cog half buried
        for x in range(136, 200):
            dx, dy = x + 0.5 - 168, y + 0.5 - 104
            r = math.hypot(dx, dy)
            a = math.atan2(dy, dx) % (2 * math.pi / 12)
            if r <= 30 or (a < 0.26 and r <= 36):
                v = 3 if r > 26 or r < 9 else 2
                if 26 < r <= 28 and dx < 0:
                    v = 5
                if 14 < r < 22 and int((math.atan2(dy, dx) + 7) * 6 / math.pi) % 2 == 0:
                    v = 0
                if c[y][x] == 0:
                    c[y][x] = v
    chimney(c, 30, 26, 100, 4)
    chimney(c, 118, 12, 100, 5)
    chimney(c, 222, 34, 100, 3)
    kiln(c, 62, 100, 24)
    kiln(c, 238, 100, 18)
    for x in range(30, 118):  # a pipe bridge between the stacks
        y = 54
        for k, v in enumerate((6, 5, 4, 3, 2)):
            c[y + k][x] = v
        if x % 16 == 0:
            for yy in range(59, 100):
                if c[yy][x] == 0:
                    c[yy][x] = 2
                    c[yy][x + 1] = 3
    sx = 196  # the crucible on its pillar, tipped, spilling lava down
    for y in range(50, 100):
        for x in range(sx - 5, sx + 6):
            c[y][x] = 5 if x == sx - 5 else 4 if x < sx else 3 if x < sx + 4 else 2
            if (y - 50) % 9 == 0:
                c[y][x] = 2 if x > sx - 5 else 5
    for y in range(40, 52):
        for x in range(sx - 8, sx + 8):
            dx, dy = (x - sx) / 8, (y - 40) / 12
            if dx * dx + dy * dy <= 1:
                c[y][x] = 5 if dx < -0.4 else 4 if dx < 0.3 else 3
    for x in range(sx - 7, sx + 7):
        c[40][x] = 8
    for y in range(41, 104):
        x0 = sx + 8 + min(6, (y - 41) // 3)
        for k, v in ((0, 9), (1, 7), (2, 8), (3, 10)):
            c[y][x0 + k] = v if (y + k) % 6 else 9
    for x in range(sx + 8, sx + 22):
        c[103][x] = 7 if x % 2 else 8
        c[104][x] = 10
    return c


def scenery_near():
    """The near band: jagged basalt spires, black-violet, rimmed orange by the lava, veins of fire in the bigger ones."""
    W, H = 256, 96
    c = grid(W, H)
    hs = [0.0] * W
    for x in range(W):
        hs[x] = 74 + wave(x, ((5, 5, 0.4), (3, 11, 2.2)))
    spires = []
    for i in range(16):
        cx, top = int(i * 256 / 16 + hsh(i, 3) * 8), 26 + int(hsh(i, 4) * 44)
        w = 5 + int(hsh(i, 5) * 7)
        spires.append((cx, top, w))
        for x in range(cx - w * 2, cx + w * 2):
            d = abs(x - cx) / w
            hs[x % W] = min(hs[x % W], top + d * d * 10 + d * 6)
    for x in range(W):
        for y in range(int(hs[x]), H):
            d = y - int(hs[x])
            left_lit = hs[(x - 1) % W] > hs[x] + 0.6
            c[y][x] = 5 if d == 0 else 4 if d < 2 and left_lit else 7 if d < 3 else 3 if d < 8 else 2 if dith(0.6, x, y) else 1
    for cx, top, w in spires:  # a vein of fire down the big ones
        if top < 44:
            x = float(cx)
            for y in range(top + 8, 90):
                x += math.sin(y * 0.3 + cx) * 0.6
                c[y][int(x) % W] = 14 if y % 5 else 7
                c[y][(int(x) + 1) % W] = 7 if y % 3 else 5
    return c


def scenery_agua():
    """Heat haze: short rising ribbons of warm light, thin and broken, and sparks; the game blends it, the rest is see-through."""
    W, H = 256, 160
    c = grid(W, H)
    for band in range(8):
        base = 156 - band * 20
        for x in range(W):
            if math.sin(2 * math.pi * x * (5 + band % 4) / W + band * 1.7) < 0.2:
                continue  # the ribbon breaks into pieces
            y = base + 3 * math.sin(2 * math.pi * x * (3 + band % 3) / W + band) + 2 * math.sin(2 * math.pi * x * 7 / W + band * 2)
            yy = int(y)
            if 0 <= yy < H and dith(0.7 - band * 0.07, x, yy):
                c[yy][x] = 1 if band < 3 else 6 if band < 6 else 7
    for i in range(70):
        x, y = int(hsh(i, 9) * W), int(hsh(i, 10) * H)
        c[y][x] = 3 if i % 3 else 4
        if i % 5 == 0 and y + 1 < H:
            c[y + 1][x] = 1
    return c


def register_scenery() -> None:
    ART.scenery("fragua_far", scenery_far(), S, "lejos")
    ART.scenery("fragua_mid", scenery_mid(), S, "medio")
    ART.scenery("fragua_near", scenery_near(), S, "cerca")
    ART.scenery("fragua_agua", scenery_agua(), S, "calor")


register_ground()
register_platforms_walls()
register_blocks()
register_animated()
register_decor()
register_scenery()

if __name__ == "__main__":
    print(preview_metas(S, cols=10, scale=3))
    for n in ("fragua_far", "fragua_mid", "fragua_near", "fragua_agua"):
        print(preview_scenery(n))
