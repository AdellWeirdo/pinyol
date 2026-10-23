"""Galeón (passage 3): a sunken pirate galleon. Palette set "galeon": the metatiles of the level and its four scenery pictures.

Warm rotted wood and brass against teal water, so the ship pops out of the sea. Banks of the set (slot meaning inside each):
    casco   hull wood: 1 outline indigo, 2-6 wood (wine shadow .. tan), 7-9 brass, a-c algae, d barnacle lilac, e cream, f white
    laton   iron and brass: 1 outline, 2-5 iron (indigo .. ice blue), 6-9 brass, a-c sea urchin violet, d-e verdigris, f white
    cajas   blocks and boxes: 1 outline, 2-5 coral clay, 6-9 blue, a-c gold, d-e gem pink, f white
    alga    sea life and water: 1 outline, 2-5 weed green, 6-8 rock blue, 9-c water (deep .. foam), d white, e-f anemone pink
    lejos, medio, cerca, agua   the far / mid / near scenery and the blended water layer
The ground is drawn by an edge field: every pixel of a tile knows how far the nearest open pixel is and on which side (the tile and its eight
neighbours laid out 48x48), so the 16 masks and the inner corners come out of one rule: a lit cap on top, a lit post on the left, shaded post right
and underside, mitred where they meet.
"""
from __future__ import annotations

import math
import sys
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent))
from gbakit import ART, flip_h, flip_v, overlay, pic, preview_metas, preview_scenery, shift  # noqa: E402

S = "galeon"

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

ART.palette(S, "casco", ["#1c1838", "#3a1e4e", "#702a4c", "#b04a3c", "#e07c40", "#ffb868", "#8a5014", "#e8a828", "#fff07a",
                         "#126a72", "#30b49c", "#98f0c0", "#a890d0", "#fff4d8", "#ffffff"])
ART.palette(S, "laton", ["#141838", "#2c2e68", "#4a54a0", "#7a8ad0", "#c0d0f8", "#7a4410", "#c07c20", "#f0c040", "#fff8a8",
                         "#4a1468", "#9a38b0", "#f070d8", "#1e7a78", "#58d0b0", "#ffffff"])
ART.palette(S, "cajas", ["#201838", "#7a2448", "#c84850", "#f07a58", "#ffbc88", "#1c3890", "#2c6ad8", "#68b0ff", "#c8ecff",
                         "#a05a10", "#f0b020", "#fff080", "#e83888", "#ffb0e0", "#ffffff"])
ART.palette(S, "alga", ["#0c2448", "#0e5a4e", "#1a9a5a", "#5ad06a", "#c4f080", "#28387a", "#4664b0", "#7c9ee0", "#1478b8",
                        "#28a8e0", "#68d8f8", "#b8f8ff", "#ffffff", "#e8507c", "#ffc0d8"])
ART.palette(S, "lejos", ["#b4f8f4", "#84e8f0", "#58cce8", "#38a8dc", "#2884cc", "#2264b8", "#1e48a0", "#1c3484", "#1a2266",
                         "#e8fffc", "#2a5cae", "#3070c0", "#1a3a8e", "#2a2a72", "#dcfcff"])
ART.palette(S, "medio", ["#14285e", "#1c4286", "#2a60a8", "#3c82c4", "#5aaada", "#94d8ee", "#3a2e7c", "#5a48a2", "#8270c4",
                         "#1e7a8a", "#3cb4a4", "#ffe07a", "#b8508e", "#f08cbc", "#e8fcff"])
ART.palette(S, "cerca", ["#081c3c", "#0c344e", "#0e5250", "#16744e", "#26985a", "#5cc874", "#162466", "#243c88", "#4260aa",
                         "#5a1e64", "#9c3a8c", "#e070b0", "#ffb0d8", "#b8f8c8", "#ffffff"])
ART.palette(S, "agua", ["#2c9ce0", "#50c4f0", "#8ce4fa", "#c8f8ff", "#ffffff", "#1c78c8", "#6ad8e8", "#a0f0e0", "#e0fff8",
                        "#3ab4e8", "#78d0f0", "#b0e8ff", "#d8f4ff", "#40a0d0", "#f0ffff"])

# ------------------------------------------------------------------ the hull: planks, caps and posts

JOINTS = (5, 13, 1, 9)  # a butt joint per plank row, staggered


def planks(seed: int = 0):
    """Four long horizontal planks: a lit top line, a dark seam, a long grain streak each; a butt joint (with its nail) in every other row."""
    c = grid()
    for y in range(16):
        r = y % 4
        for x in range(16):
            c[y][x] = 2 if r == 3 else 5 if r == 0 else 4
    for p in range(4):
        y0 = p * 4
        if (p + seed) % 2 == 0:
            jx = JOINTS[(p + seed) % 4]
            for r in range(3):
                c[y0 + r][jx] = 2
            c[y0 + 1][(jx + 2) % 16] = 8
            c[y0 + 1][(jx - 2) % 16] = 7
        gx, ln, gy = int(hsh(p, seed) * 16), 4 + int(hsh(p, seed, 1) * 7), y0 + 1 + (p + seed) % 2
        for d in range(ln):
            if c[gy][(gx + d) % 16] == 4:
                c[gy][(gx + d) % 16] = 3
        tx = int(hsh(p, seed, 2) * 16)
        if c[y0 + 2 - (p + seed) % 2][tx] == 4:
            c[y0 + 2 - (p + seed) % 2][tx] = 3
    return c


def shade_hull(side: str, d: int, x: int, y: int):
    if side == "n":
        moss = int(hsh(x, 7) * 5) - 1  # how far the algae hangs over the cap in this column
        if d - 1 <= moss and d <= 3:
            return (12, 11, 10)[d - 1]
        return {1: 1, 2: 6, 3: 5, 4: 4, 5: 2}.get(d)
    if side == "w":
        return {1: 1, 2: 6, 3: 5, 4: 4, 5: 2}.get(d) if d != 3 or y % 6 else 8
    if side == "e":
        return {1: 1, 2: 2, 3: 3, 4: 4, 5: 2}.get(d) if d != 3 or y % 6 else 7
    drip = hsh(x, 9) < 0.4
    return {1: 10 if drip else 1, 2: 10 if drip else 2, 3: 3, 4: 4, 5: 2}.get(d)


BARNACLE = ((0, 1, 1, 0), (1, 14, 13, 1), (1, 13, 2, 1), (0, 1, 1, 0))


def barnacles(c, pts) -> None:
    """Little lilac cones with a dark mouth, outlined (4x4 each, top-left at the point)."""
    for x, y in pts:
        for dy, row in enumerate(BARNACLE):
            for dx, v in enumerate(row):
                if v:
                    put(c, x + dx - 1, y + dy - 1, v)


def hull_alts():
    a0 = planks(1)
    a1 = planks(2)
    barnacles(a1, [(4, 9), (6, 11), (3, 12), (11, 5)])
    a2 = planks(3)  # a brass patch plate nailed over a split
    rect(a2, 5, 4, 11, 10, 8)
    rect(a2, 6, 5, 11, 10, 7)
    rect(a2, 5, 4, 10, 4, 9)
    rect(a2, 5, 4, 5, 9, 9)
    for x, y in ((6, 5), (10, 5), (6, 9), (10, 9)):
        put(a2, x, y, 1)
    rect(a2, 4, 11, 12, 11, 1)
    rect(a2, 12, 4, 12, 11, 1)
    a3 = planks(0)  # rot: a hole into the dark hold, algae round it
    for y, (x0, x1) in enumerate(((6, 9), (5, 10), (5, 11), (6, 10), (7, 9)), start=6):
        rect(a3, x0, y, x1, y, 1)
        put(a3, x0 - 1, y, 10)
        put(a3, x1 + 1, y, 3)
    rect(a3, 7, 7, 8, 8, 2)
    for x in (4, 5, 11, 12):
        put(a3, x, 11, 11)
    put(a3, 5, 5, 12)
    return [a0, a1, a2, a3]


def register_ground() -> None:
    base = planks()
    for m in range(16):
        ART.meta(S, f"ground_m{m}", ground_tile(m, base, shade_hull), "casco")
    for i, alt in enumerate(hull_alts()):
        ART.meta(S, f"ground_alt{i}", alt, "casco")
    top = ground_tile(1, base, shade_hull)
    b = [row[:] for row in top]  # barnacles grown on the rail
    barnacles(b, [(3, 7), (12, 6), (13, 9)])
    ART.meta(S, "ground_m1_b", b, "casco")
    cc = ground_tile(1, planks(2), shade_hull)  # a brass rail band with bolts
    rect(cc, 0, 5, 15, 5, 7)
    rect(cc, 0, 6, 15, 6, 8)
    for x in (2, 7, 12):
        put(cc, x, 6, 9)
        put(cc, x, 5, 1)
    ART.meta(S, "ground_m1_c", cc, "casco")
    for d in ("ne", "nw", "se", "sw"):
        ART.meta(S, f"ground_in_{d}", ground_tile(0, base, shade_hull, d), "casco")


# ------------------------------------------------------------------ platforms, planks, barrel, walls

def board(left: bool, right: bool, y0: int = 0, seed: int = 0):
    """A loose plank board 6 pixels thick, outlined, rounded at free ends."""
    c = grid()
    rows = (1, 6, 5, 4, 3, 1)
    for i, v in enumerate(rows):
        rect(c, 0, y0 + i, 15, y0 + i, v)
    for k in range(3):
        gx = int(hsh(k, seed, 5) * 13)
        rect(c, gx, y0 + 3, gx + 2, y0 + 3, 3)
    if left:
        for i in range(6):
            put(c, 0, y0 + i, 1)
        c[y0][0] = c[y0 + 5][0] = 0
        c[y0][1] = c[y0 + 5][1] = 1
        put(c, 1, y0 + 2, 5)
    if right:
        for i in range(6):
            put(c, 15, y0 + i, 1)
        c[y0][15] = c[y0 + 5][15] = 0
        c[y0][14] = c[y0 + 5][14] = 1
    return c


def rope_band(c, x: int, y0: int, y1: int) -> None:
    for y in range(y0, y1 + 1):
        put(c, x, y, 14 if y % 2 else 6)
        put(c, x + 1, y, 6 if y % 2 else 5)
        put(c, x - 1, y, 1)
        put(c, x + 2, y, 1)


def register_platforms() -> None:
    pl = board(True, False, seed=1)
    rope_band(pl, 4, 0, 5)
    put(pl, 4, 6, 6)
    put(pl, 4, 7, 14)
    put(pl, 5, 8, 6)
    pm = board(False, False, seed=2)
    put(pm, 6, 2, 8)
    put(pm, 6, 6, 10)
    put(pm, 6, 7, 11)
    put(pm, 7, 6, 11)
    pr = flip_h(pl)
    ps = board(True, True, seed=3)
    rect(ps, 3, 1, 12, 1, 6)
    put(ps, 5, 2, 8)
    put(ps, 10, 2, 8)
    for n, p in (("plat_l", pl), ("plat_m", pm), ("plat_r", pr), ("plat_s", ps)):
        ART.meta(S, n, p, "casco")
    # loose planks: two boards nailed in a cross, one hanging by a nail
    a = grid()
    for i in range(16):  # board one, rising to the right, three pixels thick
        y = 14 - (i * 10) // 15
        for k, v in enumerate((6, 5, 4, 3)):
            put(a, i, y - 1 + k, v)
        put(a, i, y - 2, 1)
        put(a, i, y + 3, 1)
    for i in range(2, 14):  # board two over it, falling to the right
        y = 2 + (i * 10) // 13
        for k, v in enumerate((5, 4, 4, 2)):
            put(a, i, y + k, v)
        put(a, i, y - 1, 1)
        put(a, i, y + 4, 1)
    for x in (2, 13):
        for y in range(16):
            if a[y][x] and a[y][x] != 1:
                pass
    put(a, 7, 8, 8)
    put(a, 8, 9, 7)
    ART.meta(S, "plank_a", a, "casco")
    b = grid()
    for y in range(2, 16):
        x0 = 6 + (y - 2) // 5
        rect(b, x0, y, x0 + 4, y, 4)
        put(b, x0, y, 1)
        put(b, x0 + 1, y, 6)
        put(b, x0 + 2, y, 5)
        put(b, x0 + 4, y, 3)
        put(b, x0 + 5, y, 1)
    rect(b, 6, 1, 11, 1, 1)
    for x, y in ((9, 14), (10, 15), (11, 15)):
        b[y][x] = 0
    put(b, 8, 3, 8)
    put(b, 8, 2, 9)
    put(b, 11, 10, 2)
    put(b, 10, 11, 2)
    ART.meta(S, "plank_b", b, "casco")


def barrel():
    c = grid()
    half = (5, 6, 7, 7, 7, 7, 7, 7, 7, 7, 7, 7, 7, 7, 6, 5)
    for y in range(16):
        h = half[y]
        for x in range(8 - h - 1, 8 + h + 1):
            t = (x - (8 - h - 1)) / (2 * h + 1)
            v = 6 if t < 0.16 else 5 if t < 0.36 else 4 if t < 0.66 else 3 if t < 0.86 else 2
            if (x - 1) % 4 == 0 and 0 < t < 1:
                v = 3 if v > 3 else 2
            c[y][x] = v
        c[y][8 - h - 1] = 1
        c[y][8 + h] = 1
    for yy in (2, 3, 12, 13):  # brass hoops
        h = half[yy]
        for x in range(8 - h, 8 + h):
            t = (x - (8 - h)) / (2 * h)
            c[yy][x] = (9 if t < 0.25 else 8 if t < 0.6 else 7) if yy in (2, 12) else 7
    rect(c, 3, 0, 12, 0, 1)
    rect(c, 3, 15, 12, 15, 1)
    rect(c, 4, 1, 11, 1, 5)
    put(c, 6, 7, 1)
    put(c, 7, 7, 1)  # the bung hole
    put(c, 6, 8, 7)
    barnacles(c, [(11, 9)])
    put(c, 3, 10, 10)
    put(c, 4, 11, 11)
    return c


def back_planks(seed: int):
    """Vertical boards of the hold, in shade."""
    c = grid()
    for x in range(16):
        r = x % 4
        for y in range(16):
            c[y][x] = 1 if r == 3 else 3 if r == 0 else 2
    for b in range(4):
        jy = (3 + b * 5 + seed * 3) % 16
        rect(c, b * 4, jy, b * 4 + 2, jy, 1)
        put(c, b * 4, (jy + 1) % 16, 4)
        for k in range(2):
            gy = int(hsh(b, k, seed, 3) * 16)
            put(c, b * 4 + 1 + k % 2, gy, 1)
            put(c, b * 4 + 1 + k % 2, (gy + 1) % 16, 1)
    return c


def register_walls() -> None:
    a = back_planks(0)
    b = back_planks(1)  # a porthole looking out to the sea
    for y in range(16):
        for x in range(16):
            d = math.hypot(x - 7.5, y - 7.5)
            if d < 4.3:
                b[y][x] = 12 if (x + y < 12 and d < 3.2 and d > 1.8) else 11 if y < 7 else 10
            elif d < 5.4:
                b[y][x] = 9 if (x < 7 and y < 7) else 8 if x + y < 17 else 7
            elif d < 6.3:
                b[y][x] = 1
    for x, y in ((7, 2), (2, 7), (13, 8), (8, 13)):
        put(b, x, y, 9 if x + y < 12 else 1)
    c = back_planks(2)  # a cross beam bolted on
    rect(c, 0, 5, 15, 10, 4)
    rect(c, 0, 5, 15, 5, 5)
    rect(c, 0, 6, 15, 6, 6)
    rect(c, 0, 9, 15, 9, 3)
    rect(c, 0, 10, 15, 10, 1)
    rect(c, 0, 4, 15, 4, 1)
    for x in (3, 11):
        put(c, x, 7, 9)
        put(c, x, 8, 7)
        put(c, x + 1, 8, 1)
    d = back_planks(3)  # algae creeping up a dark corner, a ring bolt
    for x in range(16):
        top = 16 - int(2 + 4 * hsh(x, 4))
        for y in range(top, 16):
            d[y][x] = 10 if y > top else 11
    disc(d, 8, 5, 2, 7)
    disc(d, 8, 5, 1, 0)
    d[5][8] = 2
    put(d, 7, 3, 9)
    put(d, 8, 8, 7)
    put(d, 8, 9, 7)
    for n, p in (("back_a", a), ("back_b", b), ("back_c", c), ("back_d", d)):
        ART.meta(S, n, p, "casco")
    # the outside of the hull: thick strakes and a gun port; the copper-sheathed bottom
    w = grid()
    for y in range(16):
        r = y % 8
        for x in range(16):
            w[y][x] = 1 if r == 7 else 6 if r == 0 else 5 if r == 1 else 4 if r < 5 else 3
        if y % 8 in (2, 4):
            for x in range(16):
                if hsh(x // 3, y, 2) < 0.3:
                    w[y][x] = 3
    rect(w, 0, 8, 15, 9, 8)  # a painted yellow band of the hull
    rect(w, 0, 8, 15, 8, 9)
    rect(w, 0, 10, 15, 10, 7)
    for x in (2, 10):
        put(w, x, 9, 1)
    ART.meta(S, "ship_wall_a", w, "casco")
    s = grid()
    for y in range(16):
        for x in range(16):
            px, py = (x + (4 if (y // 8) % 2 else 0)) % 8, y % 8
            v = 13 if px + py < 5 else 14 if px + py < 9 else 13
            v = 7 if (px == 7 or py == 7) else v
            v = 8 if (px == 0 or py == 0) and (px == 7 or py == 7) is False else v
            s[y][x] = v
            if (px, py) in ((1, 1), (6, 1), (1, 6), (6, 6)):
                s[y][x] = 9
            if hsh(x, y, 11) < 0.07:
                s[y][x] = 13
    ART.meta(S, "ship_wall_b", s, "laton")
    ART.meta(S, "barrel", barrel(), "casco")


# ------------------------------------------------------------------ blocks and boxes (bank cajas, iron in laton)

def bevel_block(face, light, mid, dark, ol=1, edge=2):
    """A square block with an outline and a bevel `edge` pixels wide (lit top/left, dark bottom/right)."""
    c = grid(16, 16, face)
    for i in range(edge):
        rect(c, 1 + i, 1 + i, 14 - i, 1 + i, light)
        rect(c, 1 + i, 1 + i, 1 + i, 14 - i, light)
        rect(c, 1 + i, 14 - i, 14 - i, 14 - i, dark)
        rect(c, 14 - i, 1 + i, 14 - i, 14 - i, dark)
    for k in range(16):
        c[0][k] = c[15][k] = c[k][0] = c[k][15] = ol
    c[0][0] = c[0][15] = c[15][0] = c[15][15] = 0
    put(c, 1, 1, mid + 1 if mid < 15 else mid)
    return c


def register_blocks() -> None:
    # brown: a coral-clay brick, cracked, crumbly
    br = bevel_block(4, 5, 4, 3)
    for x, y in ((7, 3), (6, 4), (6, 5), (5, 6), (6, 7), (7, 8), (8, 8), (9, 9), (9, 10), (10, 11), (4, 9), (3, 10), (5, 8)):
        br[y][x] = 2
        put(br, x + 1, y, 5)
    for x, y in ((11, 4), (12, 5), (3, 4)):
        br[y][x] = 3
    ART.meta(S, "block_brown", br, "cajas")
    # blue: a reinforced crate of blue boards with gold corner irons
    bl = bevel_block(7, 8, 7, 6)
    for y in (5, 10):
        rect(bl, 2, y, 13, y, 6)
    rect(bl, 2, 4, 13, 4, 9)
    rect(bl, 2, 9, 13, 9, 9)
    for (x, y) in ((1, 1), (11, 1), (1, 11), (11, 11)):
        rect(bl, x, y, x + 3, y + 3, 11)
        rect(bl, x + 1, y + 1, x + 3, y + 3, 10)
        put(bl, x + 1 if x == 1 else x + 2, y + 1 if y == 1 else y + 2, 12)
    ART.meta(S, "block_blue", bl, "cajas")
    # hard: a cast iron ballast block, four big brass bolts
    hd = bevel_block(3, 4, 3, 2, edge=3)
    rect(hd, 4, 4, 11, 11, 3)
    rect(hd, 5, 5, 10, 10, 2)
    line(hd, 5, 5, 10, 10, 3)
    line(hd, 10, 5, 5, 10, 3)
    for x, y in ((2, 2), (12, 2), (2, 12), (12, 12)):
        rect(hd, x, y, x + 1, y + 1, 8)
        put(hd, x, y, 9)
        put(hd, x + 1, y + 1, 6)
    put(hd, 2, 1, 5)
    ART.meta(S, "block_hard", hd, "laton")
    # boxes: coral wood crates with a gold frame; one shows a jewel, one a pile of coins
    def crate():
        c = bevel_block(3, 4, 3, 2)
        for y in (5, 10):
            rect(c, 2, y, 13, y, 2)
            rect(c, 2, y + 1, 13, y + 1, 4)
        rect(c, 1, 1, 14, 1, 11)
        rect(c, 1, 14, 14, 14, 10)
        rect(c, 1, 1, 1, 14, 11)
        rect(c, 14, 1, 14, 14, 10)
        return c
    jw = crate()
    gem = txt("""
        ................
        ................
        ................
        ......1111......
        .....1dedd1.....
        ....1deffdd1....
        ...1dddeeddd1...
        ...1ddddddd21...
        ....1ddddd21....
        .....1dd221.....
        ......1221......
        .......11.......
        ................
        ................
        ................
        ................""")
    jw = overlay(jw, recolour_map(gem, {2: 1}))
    put(jw, 4, 4, 15)
    put(jw, 12, 9, 12)
    ART.meta(S, "box_jewel", jw, "cajas")
    cn = crate()
    for cx, cy in ((5, 6), (10, 6), (7, 10)):
        disc(cn, cx, cy, 2.6, 1)
        disc(cn, cx, cy, 1.8, 11)
        put(cn, cx - 1, cy - 1, 12)
        put(cn, cx + 1, cy + 1, 10)
        put(cn, cx, cy, 10)
    ART.meta(S, "box_coin", cn, "cajas")


def recolour_map(p, table):
    return [[table.get(v, v) for v in row] for row in p]


# ------------------------------------------------------------------ hazards: iron spikes (bank laton)

def spike_row():
    """Three iron spikes on a brass-bound beam, lit on the left, pale tips; a scrap of violet sea urchin caught between two of them."""
    c = grid()
    for cx in (2.5, 8, 13.5):
        for y in range(1, 13):
            half = (y - 1) / 11 * 2.6
            for x in range(16):
                dx = x + 0.5 - cx
                if abs(dx) <= half + 0.35:
                    c[y][x] = 5 if (dx < -half + 1.2 and y < 9) or y < 3 else 4 if dx < 0 else 3 if dx < half - 0.8 else 2
    c = outline_of(c, 1)
    rect(c, 0, 12, 15, 12, 1)
    rect(c, 0, 13, 15, 13, 8)
    rect(c, 0, 14, 15, 14, 7)
    rect(c, 0, 15, 15, 15, 1)
    for x in (1, 9):
        put(c, x, 14, 9)
    for x, y in ((6, 11), (5, 11)):
        put(c, x, y, 10)
    put(c, 6, 10, 11)
    return c


# ------------------------------------------------------------------ decor pieces

ANCHOR = """
    ......1111......
    .....145541.....
    .....14..41.....
    .....145541.....
    ......1441......
    ..111111111111..
    ..155554455551..
    ..122223322221..
    ..111114411111..
    ......1431......
    .1....1431....1.
    141...1431...141
    1441..1431..1441
    .14411143111441.
    ..14e444334441..
    ...1111111111..."""

SKULL = """
    ................
    .....111111.....
    ....1eeeeee1....
    ...1eeeeeeed1...
    ...1eeeeeeed1...
    ...1e11ee11d1...
    ...1e12ee12d1...
    ...1eee11eed1...
    ....1edeede1....
    ....1e1e1e11....
    .....111111.....
    ................
    ................
    ................
    ................
    ................"""


def skull_bones():
    c = grid()
    for (x0, y0, x1, y1) in ((2, 15, 13, 8), (2, 8, 13, 15)):
        line(c, x0, y0, x1, y1, 14)
        line(c, x0 + 1, y0, x1 + 1, y1, 13)
        for x, y in ((x0, y0), (x1, y1)):
            put(c, x - 1, y, 14)
            put(c, x, y + (1 if y < 12 else -1), 14)
    c = outline_of(c, 1)
    c = overlay(c, txt(SKULL), 0, 2)
    return c


def deco_pieces():
    out = {}
    # a: an anemone cluster on a rock (alga)
    a = grid()
    for cx, cy, r in ((5, 13, 3.5), (11, 14, 2.8)):
        disc(a, cx, cy, r, 6)
        disc(a, cx - 1, cy - 1, r - 1.4, 7)
        put(a, int(cx) - 2, int(cy) - 2, 8)
    for i, (bx, by, h) in enumerate(((4, 10, 6), (7, 10, 5), (10, 11, 4), (12, 11, 3))):
        for y in range(by - h, by + 1):
            sway = round(math.sin(y * 0.9 + i) * 0.8)
            put(a, bx + sway, y, 14 if y > by - h + 1 else 15)
            put(a, bx + sway + 1, y, 14 if y > by - h else 13)
        put(a, bx, by - h - 1, 15)
    out["deco_a"] = (outline_of(a, 1), "alga")
    # b: an orange starfish clinging to a lilac stone (casco)
    b = grid()
    for y in range(9, 16):
        for x in range(16):
            q = ((x - 8) / 7.5) ** 2 + ((y - 15.5) / 6.5) ** 2
            if q <= 1:
                b[y][x] = 14 if q > 0.55 and y < 12 and x < 9 else 13
    for x in range(16):
        if b[15][x]:
            b[15][x] = 2
    for x, y in ((11, 13), (4, 14), (12, 14)):
        put(b, x, y, 3)
    star = grid()
    for k in range(5):
        a_ = -math.pi / 2 + k * 2 * math.pi / 5 + 0.25
        for r in range(0, 6):
            w = 1.2 - r * 0.18
            disc(star, 7.5 + math.cos(a_) * r, 7 + math.sin(a_) * r * 0.9, w, 5)
    disc(star, 7.5, 7, 1.7, 5)
    for k in range(5):
        a_ = -math.pi / 2 + k * 2 * math.pi / 5 + 0.25
        for r in (1, 3):
            put(star, round(7.5 + math.cos(a_) * r), round(7 + math.sin(a_) * r * 0.9), 6 if k in (0, 4) else 4)
    put(star, 7, 6, 14)
    b = overlay(b, outline_of(star, 1), 0, 1)
    out["deco_b"] = (outline_of(b, 1), "casco")
    out["deco_c"] = (skull_bones(), "casco")
    # d: a brass lantern, still lit
    d = txt("""
        .......11.......
        ......1881......
        ......1..1......
        .....111111.....
        ....18999871....
        ....17eeee71....
        ....1effffe1....
        ....18eff8e1....
        ....17eeee71....
        ....1e8ee8e1....
        ....18999871....
        .....177771.....
        ......1111......
        ................
        ................
        ................""")
    out["deco_d"] = (shift(d, 0, 3), "casco")
    # e: a coil of rope on the floor, three turns stacked, the loose end trailing
    e = grid()
    for i in range(3):
        cy, rx, ry = 13 - i * 2.4, 6.6 - i * 0.9, 2.4
        for y in range(16):
            for x in range(16):
                q = ((x - 7.5) / rx) ** 2 + ((y - cy) / ry) ** 2
                if q <= 1:
                    e[y][x] = 1 if q > 0.78 and y > cy else (6 if y < cy - 0.5 else 5) if q > 0.3 else (2 if i == 2 else e[y][x] or 3)
                    if q > 0.3 and (x * 2 + y * 3 + i) % 5 == 0:
                        e[y][x] = 14
    rect(e, 12, 14, 15, 14, 5)
    rect(e, 12, 15, 15, 15, 1)
    put(e, 14, 14, 14)
    out["deco_e"] = (outline_of(e, 1), "casco")
    # f: a ship's wheel half sunk in sand
    f = grid()
    for k in range(8):
        a_ = k * math.pi / 4 + math.pi / 8
        line(f, 8, 8, round(8 + math.cos(a_) * 7), round(8 + math.sin(a_) * 7), 4)
    for y in range(16):
        for x in range(16):
            d_ = math.hypot(x - 8, y - 8)
            if 4.2 <= d_ < 5.6:
                f[y][x] = 6 if (x + y) < 16 else 4
            elif 5.6 <= d_ < 6.4 and f[y][x] == 0:
                f[y][x] = 1
    disc(f, 8, 8, 1.6, 8)
    put(f, 7, 7, 9)
    f = outline_of(f, 1)
    rect(f, 0, 14, 15, 15, 0)
    for x in range(16):
        h = 13 + (1 if hsh(x, 1) < 0.5 else 0)
        for y in range(h, 16):
            f[y][x] = 14 if y == h else 13
    out["deco_f"] = (f, "casco")
    # g: a giant clam open, a pearl inside, ridged shells
    g = grid()
    for y in range(16):
        for x in range(16):
            dx = (x - 7.5) / 7.5
            lower = 15 - 4.5 * math.sqrt(max(0.0, 1 - dx * dx))
            upper_bot, upper_top = 8 - 1.5 * (1 - dx * dx), 8 - 7 * math.sqrt(max(0.0, 1 - dx * dx))
            if lower <= y <= 15 and abs(dx) <= 1:
                g[y][x] = 7 if (x // 2) % 2 else 8
                if y >= 14:
                    g[y][x] = 6
            elif upper_top <= y <= upper_bot and abs(dx) <= 0.95:
                g[y][x] = 8 if (x // 2) % 2 else 7
                if y > upper_bot - 1.2:
                    g[y][x] = 6
            elif upper_bot < y < lower and abs(dx) < 0.85:
                g[y][x] = 14 if y > lower - 2 else 2
    disc(g, 8, 11, 1.8, 13)
    put(g, 7, 10, 13)
    put(g, 7, 11, 13)
    put(g, 9, 12, 12)
    out["deco_g"] = (outline_of(g, 1), "alga")
    # h: a tuft of sea grass
    h = grid()
    for i in range(7):
        bx = 2 + i * 2
        ht = 6 + int(hsh(i, 8) * 8)
        for y in range(15, 15 - ht, -1):
            t = (15 - y) / ht
            x = bx + round(math.sin(t * 2.2 + i) * 2 * t)
            put(h, x, y, 5 if t > 0.75 else 4 if t > 0.4 else 3)
            if t < 0.5:
                put(h, x + 1, y, 2)
    out["deco_h"] = (outline_of(h, 1), "alga")
    return out


def front_pieces():
    out = {}
    # a: kelp rising in front (alga)
    a = grid()
    for y in range(16):
        x = 7 + round(math.sin(y * 0.45) * 2)
        rect(a, x, y, x + 1, y, 3)
        put(a, x + 1, y, 2)
        if y % 5 == 1:
            for k in range(1, 5):
                put(a, x - k, y - k // 2, 4 if k < 3 else 5)
                put(a, x - k, y - k // 2 + 1, 3)
        if y % 5 == 3:
            for k in range(1, 5):
                put(a, x + 1 + k, y - k // 2, 4 if k < 3 else 5)
                put(a, x + 1 + k, y - k // 2 + 1, 2)
    out["front_a"] = (outline_of(a, 1), "alga")
    # b: seaweed hanging from above
    b = grid()
    for i, bx in enumerate((2, 6, 10, 13)):
        ln = 8 + int(hsh(i, 2) * 8)
        for y in range(ln):
            x = bx + round(math.sin(y * 0.6 + i * 2) * 1.2)
            put(b, x, y, 3 if y < ln - 3 else 4)
            put(b, x + 1, y, 2)
        put(b, bx, ln, 5)
    out["front_b"] = (outline_of(b, 1), "alga")
    # c: a corner of fishing net
    c = grid()
    for y in range(16):
        for x in range(16):
            if (x + y) % 5 == 0 or (x - y) % 5 == 0:
                if x + (15 - y) * 0.6 < 18:
                    c[y][x] = 14 if (x + y) % 10 in (0, 1) else 6 if (x * y) % 3 else 5
    for x, y in ((0, 5), (5, 0), (5, 10), (10, 5), (0, 15), (15, 0), (10, 15)):
        put(c, x, y, 3)
    out["front_c"] = (c, "casco")
    # d: a hanging rope with a knot
    d = grid()
    for y in range(16):
        x = 7 + (1 if y > 9 else 0)
        put(d, x, y, 6 if y % 2 else 5)
        put(d, x + 1, y, 5 if y % 2 else 4)
        put(d, x - 1, y, 1)
        put(d, x + 2, y, 1)
    rect(d, 6, 8, 10, 10, 5)
    rect(d, 6, 8, 9, 8, 6)
    put(d, 8, 9, 14)
    rect(d, 5, 8, 5, 10, 1)
    rect(d, 11, 8, 11, 10, 1)
    rect(d, 6, 11, 10, 11, 1)
    rect(d, 6, 7, 10, 7, 1)
    out["front_d"] = (d, "casco")
    # e: an iron chain hanging (links at x 6..9, matched by nothing else: free decor)
    e = grid()
    for k in range(4):
        y0 = k * 4
        if k % 2 == 0:
            rect(e, 6, y0, 9, y0 + 4, 1)
            rect(e, 7, y0 + 1, 8, y0 + 3, 0)
            put(e, 6, y0 + 1, 4)
            put(e, 6, y0 + 2, 3)
            put(e, 7, y0, 4)
        else:
            rect(e, 7, y0, 8, y0 + 4, 3)
            put(e, 7, y0 + 1, 5)
            put(e, 6, y0 + 2, 1)
            put(e, 9, y0 + 2, 1)
    out["front_e"] = (e, "laton")
    # f: a torn sail drape
    f = grid()
    for x in range(16):
        ln = 6 + int(5 * (0.5 + 0.5 * math.sin(x * 0.7))) + int(hsh(x, 3) * 3)
        for y in range(ln):
            fold = (x + y // 3) % 5
            f[y][x] = 14 if fold < 2 else 13 if fold < 4 else 3
        f[ln - 1][x] = 13
        if hsh(x, 6) < 0.3:
            f[ln - 2][x] = 0
    out["front_f"] = (outline_of(f, 1), "casco")
    # g: a stream of bubbles
    g = grid()
    for i, (x, y, r) in enumerate(((7, 13, 1.6), (9, 9, 1.1), (6, 6, 1.4), (8, 2, 0.9), (11, 4, 0.7), (5, 11, 0.6))):
        disc(g, x, y, r + 0.9, 11)
        disc(g, x, y, r, 0)
        put(g, round(x - r * 0.6), round(y - r * 0.6), 12)
    out["front_g"] = (g, "alga")
    # h: a sea fan coral in front, at the bottom
    h = grid()
    for k in range(7):
        a_ = math.pi * (1.1 + k * 0.8 / 6)
        x1, y1 = round(8 + math.cos(a_) * 8), round(16 + math.sin(a_) * 10)
        line(h, 8, 15, x1, y1, 14)
        mx, my = (8 + x1) // 2, (15 + y1) // 2
        line(h, mx, my, mx + (1 if x1 > 8 else -1) * 2, my - 3, 14)
        put(h, x1, y1, 15)
    out["front_h"] = (outline_of(h, 1), "alga")
    return out


def anchor_cannon():
    anchor = txt(ANCHOR)
    c = grid()  # a cannon on its carriage, pointing right
    for x in range(2, 15):
        r = 3.0 - (x - 2) * 0.09
        for y in range(16):
            dy = y - 7
            if abs(dy) <= r:
                t = (dy + r) / (2 * r)
                c[y][x] = 5 if t < 0.2 else 4 if t < 0.45 else 3 if t < 0.8 else 2
    for x in (13, 14):
        for y in range(4, 11):
            if abs(y - 7) <= 3:
                c[y][x] = 8 if y < 7 else 7
    for x in (6, 7):
        for y in range(4, 11):
            if abs(y - 7) <= 3:
                c[y][x] = 8 if y < 6 else 7 if y < 9 else 6
    disc(c, 1, 7, 1.3, 3)
    c = outline_of(c, 1)
    rect(c, 3, 11, 11, 12, 6)
    rect(c, 3, 11, 11, 11, 7)
    disc(c, 5, 13, 2.2, 1)
    disc(c, 5, 13, 1.4, 3)
    put(c, 5, 13, 8)
    disc(c, 10, 13, 2.2, 1)
    disc(c, 10, 13, 1.4, 3)
    put(c, 10, 13, 8)
    put(c, 15, 6, 1)
    put(c, 15, 7, 2)
    put(c, 15, 8, 1)
    return anchor, c


def register_decor() -> None:
    for name, (p, bank) in deco_pieces().items():
        ART.meta(S, name, p, bank)
    empty = grid()
    for name, (p, bank) in front_pieces().items():
        ART.meta(S, name, empty, bank, front=p, front_bank=bank)
    anchor, cannon = anchor_cannon()
    ART.meta(S, "anchor_decor", anchor, "laton")
    ART.meta(S, "cannon_decor", cannon, "laton")
    ART.meta(S, "spikes_up", spike_row(), "laton")
    ART.meta(S, "spikes_down", flip_v(spike_row()), "laton")


# ------------------------------------------------------------------ animated pieces (bank alga)

def seaweed(pose: int):
    """A tall weed rooted at the bottom, leaning by pose (-1, 0, 1) more towards its tip, the tip a frame behind."""
    c = grid()
    for y in range(15, -1, -1):
        t = (15 - y) / 15
        x = 7 + round(pose * 2.6 * t * t)
        rect(c, x, y, x + 1, y, 3)
        put(c, x + 1, y, 2)
        if y % 4 == 2 and y < 14:
            side = 1 if (y // 4) % 2 else -1
            lean = round(pose * t * 1.5)
            for k in range(1, 5):
                xx = x + (2 + k if side > 0 else -k) + lean * (k > 2)
                put(c, xx, y - (k > 2) - (k > 3), 4 if k < 4 else 5)
                put(c, xx, y + 1 - (k > 3), 3)
    put(c, 7 + round(pose * 2.6), 0, 5)
    rect(c, 5, 15, 10, 15, 6)
    put(c, 6, 15, 7)
    return outline_of(c, 1)


def current(dx: int, frame: int):
    """Flow lines: three streaks with fading tails, moved 4 pixels a frame (16 = one loop), heading towards dx."""
    c = grid()
    for sx, sy, ln in ((2, 3, 6), (9, 8, 7), (4, 13, 5)):
        for k in range(ln):
            t = k / ln
            c[sy][(sx - dx * k + dx * frame * 4) % 16] = 12 if t < 0.25 else 11 if t < 0.6 else 10
    return c


def vent(frame: int):
    """A rock chimney on the floor puffing bubbles: three bubbles 16 pixels apart in phase, 4 pixels up a frame (4 frames = one loop)."""
    c = grid()
    for y in range(10, 16):
        w = 2 + (y - 10) * 0.9
        for x in range(16):
            if abs(x - 7.5) <= w + 0.5:
                c[y][x] = 8 if x < 7.5 - w * 0.4 else 7 if x < 7.5 + w * 0.5 else 6
    rect(c, 6, 10, 9, 10, 2)
    rect(c, 6, 11, 9, 11, 1)
    c = outline_of(c, 1)
    for off, bx, r in ((0, 7, 1.6), (6, 9, 1.0), (11, 6, 1.3)):
        y = 9 - ((frame * 4 + off) % 16) + 2
        x = bx + (1 if (frame + off) % 4 >= 2 else 0)
        if y < 9:
            for yy in range(y - 3, y + 4):
                for xx in range(x - 3, x + 4):
                    d = math.hypot(xx - x, yy - y)
                    if r - 0.5 <= d <= r + 0.5 and 0 <= yy < 16:
                        put(c, xx, yy, 12)
            put(c, round(x - r * 0.6), round(y - r * 0.6), 13)
    return c


def water_surface(frame: int):
    c = grid()
    for x in range(16):
        top = 3 + round(1.4 * math.sin(2 * math.pi * (x / 16 + frame / 4)))
        put(c, x, top, 12)
        for y in range(top + 1, 16):
            dd = y - top
            v = 11 if dd == 1 else 10 if dd < 4 else 9
            if dd >= 6 and not dith(max(0.0, 1 - (dd - 6) / 8), x, y):
                continue
            c[y][x] = v
        if (x + frame * 4) % 16 in (2, 9):
            put(c, x, top - 1, 12)
    return c


def water_fill():
    c = grid(16, 16, 9)
    for x in range(16):
        y = 6 + round(1.2 * math.sin(2 * math.pi * x / 16))
        put(c, x, y, 10)
        put(c, (x + 8) % 16, (y + 8) % 16, 10)
    return c


def register_animated() -> None:
    for n, pose in (("seaweed_a", -1), ("seaweed_b", 0), ("seaweed_c", 1)):
        ART.meta(S, n, seaweed(pose), "alga")
    for f in range(4):
        ART.meta(S, f"current_l_{f}", current(-1, f), "alga")
        ART.meta(S, f"current_r_{f}", current(1, f), "alga")
        ART.meta(S, f"current_u_{f}", current_up(f), "alga")
        ART.meta(S, f"vent_{f}", vent(f), "alga")
        ART.meta(S, f"water_surface_{f}", water_surface(f), "alga")
    ART.meta(S, "water_fill", water_fill(), "alga")


def current_up(frame: int):
    c = grid()
    for sx, sy, ln in ((3, 2, 6), (8, 9, 7), (13, 5, 5)):
        for k in range(ln):
            t = k / ln
            c[(sy + k - frame * 4) % 16][sx] = 12 if t < 0.25 else 11 if t < 0.6 else 10
    return c


# ------------------------------------------------------------------ scenery

def scenery_far():
    """Deep water: light near the surface to deep indigo, rays from above, far reef hills and a wreck mast, darker than the water by fog."""
    W, H = 256, 160
    c = grid(W, H)
    ramp = tuple(range(1, 10))
    shape = grid(W, H)  # 0 water, 1 far shapes, 2 nearer shapes
    for x in range(W):
        h1 = 118 + wave(x, ((7, 2, 0.4), (4, 5, 1.3), (2, 11, 2.0)))
        h2 = 138 + wave(x, ((6, 3, 2.2), (3, 7, 0.1), (1.5, 17, 1.0)))
        for y in range(H):
            if y >= h2:
                shape[y][x] = 2
            elif y >= h1:
                shape[y][x] = 1
    for x0 in (70, 200):  # rock arches / sea stacks
        for y in range(66 + x0 % 9, 140):
            w = 4 + (y - 70) * 0.13 + 2.2 * math.sin(y * 0.16 + x0)
            ox = 3 * math.sin(y * 0.05 + x0)
            for x in range(int(x0 + ox - w), int(x0 + ox + w) + 1):
                if shape[y][x % W] == 0:
                    shape[y][x % W] = 1
    for y in range(52, 132):  # the far wreck: a leaning mast with a yard and a crow's nest
        mx = 150 + (y - 52) * 0.18
        for x in range(int(mx), int(mx) + 2):
            shape[y][x] = max(shape[y][x], 1)
    for x in range(138, 166):
        shape[68 + (x - 138) // 7][x] = 1
    for y in range(56, 61):
        for x in range(146, 156):
            shape[y][x] = 1
    for y in range(H):
        for x in range(W):
            t = (y / (H - 1)) ** 0.9 * 0.86
            # light rays slanting down from the surface
            u = (x + y * 0.42) % W
            ray = max(0.0, 1 - abs(((u + 16) % 64) - 16) / 7) * max(0.0, 1 - y / 125)
            ray2 = max(0.0, 1 - abs(((u + 40) % 128) - 40) / 4) * max(0.0, 1 - y / 150)
            t -= 0.14 * ray + 0.1 * ray2
            t += 0.11 * shape[y][x]
            c[y][x] = ramp_at(t, x, y, ramp)
    for y in range(H):  # rim light on the top edge of the shapes
        for x in range(W):
            if shape[y][x] and not shape[y - 1][x] and y > 0:
                c[y][x] = max(1, c[y][x] - 1)
    for x in range(W):  # the shimmer of the surface far above
        for y in range(0, 7):
            s = math.sin(2 * math.pi * (x * 4 / W) + y * 1.3) + math.sin(2 * math.pi * (x * 9 / W) + 1.7)
            if s > 1.3 - y * 0.12:
                c[y][x] = 10 if y < 3 else 1
    for i in range(70):  # a school of small fish and rising specks
        x, y = int(hsh(i, 1) * W), int(20 + hsh(i, 2) * 100)
        if i < 22:
            fx, fy = 30 + int(hsh(i, 3) * 40), 40 + int(hsh(i, 4) * 26)
            for k in range(3):
                c[fy][(fx + k) % W] = min(9, c[fy][(fx + k) % W] + 2)
            c[fy - 1][(fx + 3) % W] = min(9, c[fy][fx % W] + 1)
            c[fy + 1][(fx + 3) % W] = c[fy - 1][(fx + 3) % W]
        else:
            c[y][x] = 15 if y < 60 else 3
    return c


def hull_shape(x: int, y: int):
    """The sunken galleon of the mid layer: (slot or None). Stern castle at the left, the bow and bowsprit rising to the right, a hole with ribs."""
    x0, x1 = 36, 214
    if not x0 <= x < x1:
        return None
    u = (x - x0) / (x1 - x0)
    deck = 64 - u * 12 - (12 if u < 0.2 else 0) - max(0.0, (u - 0.86) / 0.14) ** 2 * 10
    depth = 40 * (1 - max(0.0, (u - 0.72) / 0.28) ** 1.7) + (12 if u < 0.2 else 0)
    keel = deck + depth
    if not deck <= y < keel:
        return None
    dd = y - deck
    if 0.46 < u < 0.62 and dd > 7 and y < keel - 5:
        return 7 if (x % 7) < 2 else 0  # the hole: ribs and the sea behind
    if dd < 1:
        return 15
    if u < 0.2 and 4 <= dd < 9 and x % 8 in (2, 3, 4):
        return 12  # stern windows, lit
    if 0.24 < u < 0.44 and int(dd) == 16 and x % 12 in (5, 6):
        return 12  # portholes
    band = int(dd + (x - x0) * 0.0) % 5
    if u < 0.2 and int(dd) == 11:
        return 6
    v = 9 if band == 0 else 8 if band < 3 else 7
    if dd > depth - 4:
        v = 7 if dith(0.5, x, y) else 6
    return v


def scenery_mid():
    """The sunken galleon itself lying on a reef: violet hull with lit portholes, exposed ribs, broken masts and a torn sail; teal rock and weed."""
    W, H = 256, 128
    c = grid(W, H)
    for y in range(H):
        for x in range(W):
            v = hull_shape(x, y)
            if v:
                c[y][x] = v
    for y in range(6, 54):  # the broken main mast leaning back, a yard, the torn sail
        mx = 114 - (54 - y) * 0.25
        for x in range(int(mx), int(mx) + 3):
            c[y][x] = 9 if x == int(mx) else 8
    for x in range(94, 134):
        yy = 18 + (x - 94) // 9
        c[yy][x] = 8
        c[yy + 1][x] = 7
    for x in range(98, 126):
        ln = int(16 + 7 * math.sin(x * 0.4) + hsh(x, 5) * 6)
        for y in range(20 + (x - 98) // 9, 20 + (x - 98) // 9 + ln):
            if c[y][x] == 0:
                c[y][x] = 15 if (x + y // 2) % 5 else 6
    for y in range(30, 56):  # the fore mast, snapped
        x = 176 + (56 - y) // 6
        c[y][x] = 9
        c[y][x + 1] = 8
    for i in range(26):  # the bowsprit
        c[44 - i // 2][212 + i // 2 * 0 + i] = 9 if i % 3 else 8
    for x in range(W):  # reef rocks in front of the keel
        top = int(98 + wave(x, ((6, 3, 0.3), (4, 7, 1.1), (2, 19, 0.6))))
        for y in range(top, H):
            d = y - top
            v = 6 if d == 0 else 5 if d < 3 else 4 if d < 7 else (3 if dith(max(0.0, 1 - (d - 7) / 14), x, y) else 2)
            if d > 18:
                v = 2 if dith(0.6, x, y) else 1
            c[y][x] = v
    for x in range(W):  # weed on the reef and the deck
        if hsh(x, 77) < 0.16:
            top = next((y for y in range(H) if c[y][x]), H)
            ln = 6 + int(hsh(x, 78) * 16)
            for k in range(ln):
                xx = (x + round(math.sin(k * 0.5 + x) * 1.2)) % W
                if 0 <= top - k and c[top - k][xx] in (0, 11, 10):
                    c[top - k][xx] = 11 if k > ln - 3 else 10
    for cx in (22, 80, 248, 160):  # sea fans
        top = next((y for y in range(H) if c[y][cx]), H)
        for k in range(8):
            a_ = math.pi * (1.15 + k * 0.7 / 7)
            for r in range(8):
                xx, yy = round(cx + math.cos(a_) * r), round(top + math.sin(a_) * r)
                if 0 <= yy < H:
                    c[yy][xx % W] = 14 if r > 5 else 13
    return c


def scenery_near():
    """The foreground band: broad kelp blades, branching coral and dark rocks, see-through between."""
    W, H = 256, 96
    c = grid(W, H)
    for x in range(W):
        top = int(82 + wave(x, ((5, 4, 0.2), (3, 9, 1.7), (2, 23, 0.4))))
        for y in range(top, H):
            d = y - top
            c[y][x] = 9 if d == 0 else 8 if d < 3 else 7
    for i in range(11):  # kelp stalks with broad blades
        bx = int(i * 256 / 11 + hsh(i, 1) * 12)
        ht = 44 + int(hsh(i, 2) * 46)
        for k in range(ht):
            y = 94 - k
            if y < 0:
                break
            x = bx + round(math.sin(k * 0.07 + i) * 5 * k / ht)
            for dx, v in ((0, 6), (1, 4), (2, 3)):
                c[y][(x + dx) % W] = v
            if k % 11 == 5 and k < ht - 4:
                side = 1 if (k // 11 + i) % 2 else -1
                a = -math.pi / 2 + side * (0.9 + 0.3 * hsh(i, k))
                ln = 12 + int(hsh(k, i) * 6)
                nx, ny = -math.sin(a), math.cos(a)
                for j in range(ln * 4):
                    t = j / (ln * 4)
                    px, py = x + 1 + math.cos(a) * t * ln, y + math.sin(a) * t * ln - t * t * 3
                    wd = 2.8 * math.sin(math.pi * min(1.0, t * 1.1))
                    for w10 in range(-30, 31, 5):
                        w = w10 / 10
                        if abs(w) <= wd:
                            xx, yy = round(px + nx * w), round(py + ny * w)
                            if 0 <= yy < H:
                                c[yy][xx % W] = 6 if (w * ny) < -wd + 1.2 else 5 if w * ny < 0.6 else 4
    for cx in (40, 132, 214):  # branching coral
        def branch(x, y, a, ln, depth):
            for k in range(ln):
                xx, yy = round(x + math.cos(a) * k), round(y + math.sin(a) * k)
                for dx in (0, 1):
                    if 0 <= yy < H:
                        c[yy][(xx + dx) % W] = 12 if depth == 0 and k > ln - 3 else 11 if dx == 0 else 10
                if depth > 1 and 0 <= yy < H:
                    c[yy][(xx + 2) % W] = 9
            if depth:
                ex, ey = x + math.cos(a) * ln, y + math.sin(a) * ln
                branch(ex, ey, a - 0.5, int(ln * 0.78), depth - 1)
                branch(ex, ey, a + 0.42, int(ln * 0.72), depth - 1)
        branch(cx, 92, -math.pi / 2 - 0.1, 13, 3)
    return c


def scenery_agua():
    """The blended water layer: a caustic net of light near the top and slanting light shafts; the rest see-through."""
    W, H = 256, 160
    c = grid(W, H)
    for y in range(H):
        for x in range(W):
            fy = y / 160
            u = 2 * math.pi * x / W
            n = (math.sin(u * 8 + math.sin(y * 0.21) * 1.6) + math.sin(u * 12 - y * 0.17 + math.sin(u * 4) * 1.4)
                 + math.sin(u * 5 + y * 0.11))
            if abs(n) < 0.16 and fy < 0.55 and dith(1 - fy / 0.55, x, y):
                c[y][x] = 3 if fy < 0.2 else 2
            s = (x + y * 0.42) % W
            shaft = max(0.0, 1 - abs(((s + 16) % 64) - 16) / 6)
            if not c[y][x] and shaft > 0 and dith(shaft * 0.5 * (1 - fy), x, y) and (x + y) % 2 == 0:
                c[y][x] = 1 if fy > 0.3 else 2
    for x in range(W):
        y = 2 + round(1.5 * math.sin(2 * math.pi * x * 6 / W))
        c[y][x] = 4
        c[y + 1][x] = 3
    return c


def register_scenery() -> None:
    ART.scenery("galeon_far", scenery_far(), S, "lejos")
    ART.scenery("galeon_mid", scenery_mid(), S, "medio")
    ART.scenery("galeon_near", scenery_near(), S, "cerca")
    ART.scenery("galeon_agua", scenery_agua(), S, "agua")


register_ground()
register_platforms()
register_walls()
register_blocks()
register_decor()
register_animated()
register_scenery()

if __name__ == "__main__":
    print(preview_metas(S, cols=10, scale=3))
    for n in ("galeon_far", "galeon_mid", "galeon_near", "galeon_agua"):
        print(preview_scenery(n))
