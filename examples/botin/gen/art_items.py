"""Botín: items, HUD, effects, map sprites and the title pictures.

Banks of set "obj" defined here: objetos, joyas, ui, fx, mapa, extra. Palette set "titulo" (logo, fondo, mapa_isla).
Sheets: ITEMS16, ITEMS32, UI8, UI16, FX8, FX16, MAPA16. Scenery: titulo_logo, titulo_fondo, mapa_fondo.
Most pictures are drawn by small raster routines (ellipses, polar swirls, facets) into colour slots, then outlined, as a
pixel artist builds a ramp per material; the small HUD glyphs are hand-written rows.
Run `python3 gen/art_items.py` to write the previews into art/.
"""
from __future__ import annotations

import math
import sys
from pathlib import Path

GEN = Path(__file__).resolve().parent
sys.path.insert(0, str(GEN))

from gbakit import ART, ART_DIR, blank, crop, flip_h, outline, overlay, pic, recolour, shift  # noqa: E402

TAU = math.tau
BAYER = [[0, 8, 2, 10], [12, 4, 14, 6], [3, 11, 1, 9], [15, 7, 13, 5]]

# ------------------------------------------------------------------ palettes (slot meaning noted per bank)

# objetos: 1 outline | 2 3 f bronze/wood dark..light, e deepest wood | 4 5 6 gold | 7 white | 8 9 a silver/stone | b c d red..pink
ART.palette("obj", "objetos", ["#2c1430", "#8c3c1c", "#dc7834", "#c88410", "#f8c830", "#fff088", "#ffffff",
                               "#5868a0", "#a8b8e0", "#e8f0ff", "#b81838", "#f04858", "#ffa8b0", "#5c2010", "#f8b070"])
# joyas: 1 outline | 2 3 4 emerald | 5 6 7 ruby | 8 9 a topaz | b c d sapphire | e white | f socket grey-violet
ART.palette("obj", "joyas", ["#201040", "#087848", "#20c868", "#a8ffb8", "#a00830", "#f03050", "#ffa0b8",
                             "#c06800", "#ffc020", "#fff4a0", "#1838b0", "#3890ff", "#b0e8ff", "#ffffff", "#7868b0"])
# ui: 1 outline | 2 3 4 gold, 5 white | 6 grey-blue (empty) | 7 8 9 red..pink | a b silver | c d bronze | e f green light, dark
ART.palette("obj", "ui", ["#200828", "#c06808", "#f8b818", "#fff070", "#ffffff", "#8890c0", "#a80c30",
                          "#f03048", "#ffa0b0", "#5868a0", "#c8d4f0", "#8c3c18", "#e08040", "#48d060", "#107040"])
# fx: 1 outline | 2 3 4 5 fire red..pale yellow, 6 white | 7 8 dust | 9 a smoke | b c d water | e f rubble
ART.palette("obj", "fx", ["#301038", "#e83010", "#ff8818", "#ffd828", "#fff8a0", "#ffffff", "#b07858",
                          "#f0d8a8", "#7870a8", "#c8c8e8", "#2870d0", "#58b8ff", "#b8f4ff", "#6c3c28", "#b07048"])
# mapa: 1 outline | 2 3 skin | 4 5 red | 6 7 sack | 8 white | 9 a gold | b c blue | d e grey | f navy
ART.palette("obj", "mapa", ["#200830", "#c86838", "#f8b878", "#a01828", "#f04040", "#9c5c24", "#e0a850",
                            "#ffffff", "#f8c820", "#b06810", "#3070e0", "#88d8ff", "#6a6890", "#b8b8d8", "#182c80"])
# extra (keyzer, frog switch, vortex): 1 navy outline | 2 3 4 5 ghost/portal blue..white | 6 7 8 gold | 9 pink |
# a dark red | b c d stone green | e red | f orange
ART.palette("obj", "extra", ["#1c1860", "#3c50c8", "#64a8f8", "#c0f0ff", "#ffffff", "#b86010", "#f8c018",
                             "#fff080", "#ff88b0", "#b01c40", "#26584c", "#46a070", "#9ee09a", "#ff3424", "#ffb030"])


# ------------------------------------------------------------------ raster toolkit

def canvas(w: int, h: int) -> list[list[int]]:
    return blank(w, h)


def get(p, x: int, y: int) -> int:
    return p[y][x] if 0 <= y < len(p) and 0 <= x < len(p[0]) else 0


def put(p, x: int, y: int, c: int) -> None:
    if 0 <= y < len(p) and 0 <= x < len(p[0]):
        p[y][x] = c


def plot(p, fn):
    """fn(x, y) at each pixel centre returns a slot (0 leaves the pixel as it is)."""
    for y in range(len(p)):
        for x in range(len(p[0])):
            c = fn(x + 0.5, y + 0.5)
            if c:
                p[y][x] = c
    return p


def ell(cx: float, cy: float, rx: float, ry: float):
    return lambda x, y: ((x - cx) / rx) ** 2 + ((y - cy) / ry) ** 2 <= 1.0


def fill(p, inside, c: int):
    return plot(p, lambda x, y: c if inside(x, y) else 0)


def clear(p, inside):
    """Cut out (see-through) what `inside` covers."""
    for y in range(len(p)):
        for x in range(len(p[0])):
            if inside(x + 0.5, y + 0.5):
                p[y][x] = 0
    return p


def in_poly(x: float, y: float, pts) -> bool:
    hit = False
    for i in range(len(pts)):
        (x0, y0), (x1, y1) = pts[i], pts[i - 1]
        if (y0 > y) != (y1 > y) and x < (x1 - x0) * (y - y0) / (y1 - y0) + x0:
            hit = not hit
    return hit


def poly(p, pts, c: int):
    return fill(p, lambda x, y: in_poly(x, y, pts), c)


def line(p, x0: int, y0: int, x1: int, y1: int, c: int) -> None:
    dx, dy = abs(x1 - x0), -abs(y1 - y0)
    sx, sy = (1 if x0 < x1 else -1), (1 if y0 < y1 else -1)
    err = dx + dy
    while True:
        put(p, x0, y0, c)
        if x0 == x1 and y0 == y1:
            return
        e2 = 2 * err
        if e2 >= dy:
            err += dy
            x0 += sx
        if e2 <= dx:
            err += dx
            y0 += sy


def outline8(p, slot: int):
    """A one-pixel line round what is drawn, corners included (chunky HUD glyphs)."""
    out = [r[:] for r in p]
    for y in range(len(p)):
        for x in range(len(p[0])):
            if not p[y][x] and any(get(p, x + dx, y + dy) for dx in (-1, 0, 1) for dy in (-1, 0, 1)):
                out[y][x] = slot
    return out


def bevel(p, light: int, dark: int, only=None, d=(-1, -1)):
    """Edge pixels facing the light (top-left) take `light`, those facing away take `dark`."""
    out = [r[:] for r in p]
    for y in range(len(p)):
        for x in range(len(p[0])):
            v = p[y][x]
            if not v or (only and v not in only):
                continue
            if not get(p, x + d[0], y + d[1]) or not get(p, x, y + d[1]):
                out[y][x] = light
            elif not get(p, x - d[0], y - d[1]) or not get(p, x - d[0], y):
                out[y][x] = dark
    return out


def recol(p, table: dict[int, int]):
    return recolour(p, table)


def star_pts(cx: float, cy: float, r1: float, r2: float, n: int = 5, rot: float = 0.0):
    return [(cx + (r1 if i % 2 == 0 else r2) * math.sin(rot + i * math.pi / n),
             cy - (r1 if i % 2 == 0 else r2) * math.cos(rot + i * math.pi / n)) for i in range(2 * n)]


def twinkle(p, cx: int, cy: int, size: int, c: int, core: int | None = None) -> None:
    """A four-point glint: arms of `size` pixels."""
    for k in range(-size, size + 1):
        put(p, cx + k, cy, c)
        put(p, cx, cy + k, c)
    if core:
        put(p, cx, cy, core)


def sheet_add(sheet, prefix: str, frames, bank: str | None = None) -> None:
    for i, f in enumerate(frames):
        sheet.add(f"{prefix}_{i}", f, bank)


# ------------------------------------------------------------------ ITEMS16

def coin(i: int, rx: float, edge: int, face: int, light: int, ring: int, hi: int):
    """A coin turning: half a turn over 6 frames (both faces alike); the edge band shows as it turns."""
    th = i * math.pi / 6
    c, s = math.cos(th), math.sin(th)
    p = canvas(16, 16)
    cx = cy = 8.0
    t = 1.0 if rx < 5 else 1.6
    hw = rx * abs(c)
    fo = -t / 2 * s
    for k in range(9):
        o = fo - 2 * fo * k / 8
        fill(p, ell(cx + o, cy, max(hw, 0.6), rx), edge)
    if hw < 1.0:  # edge on: a thick bar, lit on its left
        for y in range(16):
            if p[y][7] or p[y][8]:
                p[y][7], p[y][8] = light, edge
        p[int(cy - rx) + 1][7] = hi
    else:
        fx = cx + fo

        def face_fn(x, y):
            u, v = (x - fx) / hw, (y - cy) / rx
            r = math.hypot(u, v)
            if r > 1.0:
                return 0
            if r > 0.72:
                return light if (u + v) < -0.5 else face if (u + v) < 0.6 else ring
            if abs(u) < 0.22 and abs(v) < 0.42 and rx > 4:
                return light if u < 0 else ring
            if -0.62 < u < -0.12 and -0.62 < v < -0.1 and r > 0.3:
                return light
            return face
        plot(p, face_fn)
        if hw > rx * 0.7:
            put(p, int(fx - hw * 0.45), int(cy - rx * 0.5), hi)
    return outline(p, 1)


def gem(i: int, n: int, ramp, top: float, gird: float, bot: float, hw: float, table: float, facets: int = 8):
    """A cut stone turning on itself: the facets slide across a fixed silhouette, one facet a loop."""
    dark, mid, light, white = ramp
    fa = TAU / facets
    phase = i * fa / n
    p = canvas(16, 16)
    cx = 8.0

    def fn(x, y):
        if top <= y < gird:
            local, zone = table + (hw - table) * (y - top) / (gird - top), 0
        elif gird <= y < bot:
            local, zone = hw * (bot - y) / (bot - gird), 1
        else:
            return 0
        dx = x - cx
        if abs(dx) > local or local < 0.3:
            return 0
        a = math.asin(max(-1.0, min(1.0, dx / local)))
        k = math.floor((a + phase) / fa)
        b = math.cos(k * fa + fa / 2 - phase + 0.7)
        if zone == 0:
            b += 0.35 + (0.5 if y < top + 1.0 else 0)
        else:
            b -= 0.15 + 0.45 * (y - gird) / (bot - gird)
        return white if b > 1.1 else light if b > 0.55 else mid if b > -0.05 else dark
    plot(p, fn)
    return outline(p, 1)


def heart_fn(cx: float, cy: float, s: float, base: int, light: int, dark: int, white: int):
    def fn(x, y):
        u, v = (x - cx) / s, -(y - cy) / s
        f = (u * u + v * v - 1) ** 3 - u * u * v ** 3
        if f > 0:
            return 0
        if (u + 0.5) ** 2 + (v - 0.62) ** 2 < 0.03:
            return white
        if (u + 0.48) ** 2 + (v - 0.5) ** 2 < 0.14:
            return light
        b = -0.5 * u + 0.5 * v
        return dark if b < -0.45 else base
    return fn


def heart(size: int, s: float, slots=(12, 11, 13, 10, 7)):
    """slots: base, light, dark?, ... given as (base, light, white?) mapped below."""
    base, dark, light, deep, white = slots
    p = canvas(size, size)
    c = size / 2
    plot(p, heart_fn(c, c - 0.15 * s + 0.4, s, base, light, dark, white))
    p = bevel(p, base, deep, only=(base, dark))
    return outline(p, 1)


# the four pieces: quadrant signs, (tab or notch on the vertical cut, its span), (on the horizontal cut, its span)
PIECES = [(-1, -1, ("tab", 4, 7), ("notch", 3, 6)), (1, -1, ("notch", 4, 7), ("tab", 6, 9)),
          (-1, 1, ("notch", 7, 10), ("tab", 3, 6)), (1, 1, ("tab", 7, 10), ("notch", 6, 9))]


def jewel_piece_mask(q: int, R: float = 11.5, ox: float = 0.0, oy: float = 0.0):
    """One quarter of the ancient medallion, its two broken edges keyed like a puzzle (a tab here, a notch there)."""
    sx, sy, vcut, hcut = PIECES[q]
    cx, cy = (13.5 if sx < 0 else 2.5) + ox, (13.5 if sy < 0 else 2.5) + oy

    def inside(x, y):
        X, Y = (x - cx) * sx, (y - cy) * sy       # both positive inside the quadrant
        if math.hypot(X, Y) > R:
            return False
        lo_x, lo_y = 0.5, 0.5
        kind, a, b = vcut
        if a <= Y < b:
            lo_x = -2.0 if kind == "tab" else 2.5
        kind, a, b = hcut
        if a <= X < b:
            lo_y = -2.0 if kind == "tab" else 2.5
        return X > lo_x and Y > lo_y
    return inside, cx, cy, sx, sy


def jewel_piece(q: int, i: int, ramp):
    dark, mid, light, white = ramp
    inside, cx, cy, sx, sy = jewel_piece_mask(q)
    glint = [None, 3.0, 8.0, 13.0][i]

    def fn(x, y):
        if not inside(x, y):
            return 0
        X, Y = (x - cx) * sx, (y - cy) * sy
        r = math.hypot(X, Y)
        gx, gy = x - cx - sx * 4.0, y - cy - sy * 4.0    # from the middle of the piece's inner field
        if glint is not None and abs((x - 1) + (y - 1) - 2 * glint) < 1.2 and r < 10.5:
            return white
        if 6.8 < r < 7.8:            # the engraved ring of the medallion
            return dark
        if r >= 7.8:                 # the rim: lit where it faces up and left
            out_x, out_y = (x - cx) / r, (y - cy) / r
            return light if out_x + out_y < -0.6 or (r < 8.8 and out_x + out_y < 0.5) else mid
        if (gx + 1.2) ** 2 + (gy + 1.2) ** 2 < 2.2:
            return light
        return mid
    p = plot(canvas(16, 16), fn)
    p = bevel(p, light, dark, only=(mid,))
    put(p, int(cx + sx * 3.0), int(cy + sy * 3.0), white if i != 1 else light)
    p = outline(p, 1)
    if i == 3:
        twinkle(p, int(cx + sx * 7), int(cy + sy * 7), 2, white)
    return p


def jewel_ghost(q: int):
    inside = jewel_piece_mask(q)[0]
    m = plot(canvas(16, 16), lambda x, y: 15 if inside(x, y) else 0)
    out = canvas(16, 16)
    for y in range(16):
        for x in range(16):
            if m[y][x] and any(not get(m, x + dx, y + dy) for dx, dy in ((1, 0), (-1, 0), (0, 1), (0, -1))):
                out[y][x] = 15
    return outline(out, 1)


def chest(stage: int):
    """stage 0 closed, 1 ajar with light leaking, 2 open with gold, 3 open with rays."""
    p = canvas(16, 16)
    body_top = 8
    for y in range(body_top, 14):
        for x in range(2, 14):
            p[y][x] = 3
    for x in range(2, 14):
        p[11][x] = 2
        p[13][x] = 2
    for y in range(body_top, 14):
        p[y][2] = 15
    if stage == 0:
        lid = [(4, 12, 3), (3, 13, 4), (2, 14, 5), (2, 14, 6), (2, 14, 7)]
        for y, (x0, x1, yy) in zip(range(3, 8), lid):
            for x in range(x0, x1):
                p[yy][x] = 15 if yy == 3 or x == x0 else 3
        for x in range(2, 14):
            p[7][x] = 4
            p[8][x] = 14
        for x in (4, 11):
            for y in range(3, 14):
                if p[y][x]:
                    p[y][x] = 6 if y in (3, 4) else 4 if y in (7, 13) else 5
        for y in range(7, 11):
            for x in range(6, 10):
                p[y][x] = 5
        p[7][6], p[7][7] = 6, 6
        p[9][7], p[9][8] = 1, 1
        p[10][6], p[10][9] = 4, 4
    else:
        if stage == 1:
            for y, (x0, x1) in zip(range(1, 6), [(4, 12), (3, 13), (2, 14), (2, 14), (2, 14)]):
                for x in range(x0, x1):
                    p[y][x] = 15 if y == 1 or x == x0 else 3
            for x in range(2, 14):
                p[5][x] = 4
                p[6][x] = 7 if 4 < x < 11 else 6
                p[7][x] = 6
            for x in (4, 11):
                for y in range(1, 6):
                    p[y][x] = 6 if y < 3 else 5
        else:  # lid thrown back: its inner face shows above the body
            for y in range(2, 7):
                for x in range(2, 14):
                    p[y][x] = 14 if y > 3 else 2
            for x in range(2, 14):
                p[2][x] = 4
            for x in range(2, 14):  # the gold inside
                p[7][x] = 5 if x % 3 else 6
                p[8][x] = 4 if x % 4 else 5
            for x in range(4, 12):
                p[6][x] = 6 if x % 2 else 5
            p[5][6], p[5][7], p[5][9] = 5, 6, 5
            p[5][8] = 11  # a ruby on top of the heap
            p[4][8] = 12
        for x in (4, 11):
            for y in range(8, 14):
                p[y][x] = 4 if y == 13 else 5
        for y in range(8, 11):
            for x in range(6, 10):
                p[y][x] = 5
        p[9][7], p[9][8] = 1, 1
    p = outline(p, 1)
    if stage == 3:
        for x, y in ((3, 0), (8, 0), (13, 1)):
            put(p, x, y, 6)
        twinkle(p, 12, 3, 1, 7)
        twinkle(p, 4, 2, 1, 7)
    return p


def bag(i: int):
    sq = [(6.0, 5.0, 0), (6.6, 4.5, 1), (6.0, 5.0, 0), (5.5, 5.4, -1)][i]
    rx, ry, dy = sq
    p = canvas(16, 16)
    cx, cy = 8.0, 15.0 - ry
    fill(p, ell(cx, cy, rx, ry), 3)
    neck_y = int(cy - ry) + 1
    for y in (neck_y - 1, neck_y):
        for x in range(6, 10):
            p[y][x] = 3
    tuft = [(5, 11), (6, 10)] if i != 3 else [(6, 12), (7, 11)]
    for y, (x0, x1) in zip((neck_y - 3, neck_y - 2), tuft):
        for x in range(x0, x1):
            p[y][x] = 3
    p = bevel(p, 15, 2)
    for y in range(16):          # shadow side of the sack
        for x in range(16):
            if p[y][x] == 3 and (x - cx) / rx + (y - cy) / ry > 0.75:
                p[y][x] = 2
    for x in range(6, 10):       # the gold cord
        p[neck_y][x] = 5 if x < 8 else 4
    p[neck_y + 1][9] = 5
    p[neck_y + 2][10] = 4
    ec = int(cy) + (1 if i == 1 else 0)
    for x, y, c in ((7, ec - 1, 5), (8, ec - 1, 5), (6, ec, 5), (7, ec, 6), (8, ec, 5), (9, ec, 4),
                    (7, ec + 1, 4), (8, ec + 1, 4)):
        put(p, x, y, c)
    return outline(p, 1)


def key_pic(i: int):
    p = canvas(16, 16)
    dy = [0, -1, -1, 0][i]
    cy = 8 + dy
    fill(p, ell(4.5, cy, 3.3, 3.3), 5)
    clear(p, ell(4.5, cy, 1.2, 1.2))
    for x in range(7, 14):
        p[cy - 1][x] = 5
        p[cy][x] = 4
    for x, y in ((11, cy + 1), (11, cy + 2), (13, cy + 1), (13, cy + 2), (12, cy + 1)):
        put(p, x, y, 4)
    p = bevel(p, 6, 4, only=(5,))
    g = [None, 8, 11, None][i]
    if g:
        put(p, g, cy - 1, 7)
    if i == 3:
        put(p, 3, cy - 2, 7)
    p = outline(p, 1)
    if i == 2:
        twinkle(p, 13, cy - 4, 1, 7)
    return p


def rock(i: int):
    w, h = [(6.4, 5.0), (6.4, 5.0), (7.0, 4.4), (6.4, 5.0)][i]
    p = canvas(16, 16)
    cx, cy = 8.0, 15.0 - h

    def fn(x, y):
        a = math.atan2(y - cy, x - cx)
        r = 1 + 0.09 * math.sin(3 * a + 1) + 0.06 * math.sin(5 * a)
        u, v = (x - cx) / (w * r), (y - cy) / (h * r)
        if u * u + v * v > 1:
            return 0
        b = -0.6 * u - 0.7 * v
        return 10 if b > 0.55 else 9 if b > -0.25 else 8
    plot(p, fn)
    for x, y in ((6, int(cy) + 1), (10, int(cy) - 1), (9, int(cy) + 3)):  # pits
        put(p, x, y, 8)
    if i == 1:
        put(p, 5, int(cy - h) + 2, 7)
    if i == 3:  # cracked
        for x, y in ((8, int(cy - h) + 1), (8, int(cy - h) + 2), (9, int(cy - h) + 3), (9, int(cy)), (8, int(cy) + 1)):
            put(p, x, y, 1)
    return outline(p, 1)


def crate(i: int):
    p = canvas(16, 16)
    for y in range(2, 15):
        for x in range(1, 15):
            p[y][x] = 3
    for x in range(1, 15):
        for y in (2, 3, 13, 14):
            p[y][x] = 2 if y in (3, 14) else 15
    for y in range(2, 15):
        for x in (1, 2, 13, 14):
            p[y][x] = 2 if x in (2, 14) else 15
    for k in range(9):   # the cross brace
        put(p, 3 + k, 4 + k, 15)
        put(p, 4 + k, 4 + k, 2)
    for x, y in ((2, 2), (13, 2), (2, 13), (13, 13)):
        put(p, x, y, 6)
    if i == 1:  # split and dented
        for x, y in ((9, 2), (9, 3), (8, 4), (9, 5), (10, 6), (5, 10), (4, 11), (5, 12)):
            put(p, x, y, 1)
        put(p, 14, 2, 0)
        put(p, 13, 2, 0)
        put(p, 14, 3, 0)
        put(p, 1, 14, 0)
    return outline(p, 1)


def build_items16():
    s = ART.sheet("ITEMS16", 16, 16, "objetos")
    sheet_add(s, "coin_s", [coin(i, 3.6, 2, 3, 15, 2, 7) for i in range(6)])
    sheet_add(s, "coin_m", [coin(i, 5.0, 8, 9, 10, 8, 7) for i in range(6)])
    sheet_add(s, "coin_l", [coin(i, 6.6, 4, 5, 6, 4, 7) for i in range(6)])
    sheet_add(s, "gem_a", [gem(i, 6, (11, 12, 13, 14), 3, 6.5, 14, 5.6, 3.0) for i in range(6)], "joyas")
    sheet_add(s, "gem_b", [gem(i, 6, (5, 6, 7, 14), 3, 6.5, 14, 5.6, 3.0) for i in range(6)], "joyas")
    dia = []
    for i in range(6):
        d = gem(i, 6, (11, 13, 13, 14), 2, 6, 15, 7.2, 4.0, facets=10)
        d = [[12 if (v == 13 and (x + y + i) % 5 == 0) else v for x, v in enumerate(r)] for y, r in enumerate(d)]
        if i in (1, 2, 3):
            twinkle(d, 4, 3, [1, 2, 1][i - 1], 14)
        if i == 4:
            put(d, 11, 4, 14)
        dia.append(d)
    sheet_add(s, "diamond", dia, "joyas")
    sheet_add(s, "heart_item", [heart(16, sc, (12, 11, 13, 11, 7)) for sc in (5.4, 5.9, 5.4, 5.0)])
    sheet_add(s, "heart_small", [heart(16, sc, (12, 11, 13, 11, 7)) for sc in (3.4, 3.8, 3.4, 3.1)])
    ramps = [(2, 3, 4, 14), (5, 6, 7, 14), (8, 9, 10, 14), (11, 12, 13, 14)]
    for q in range(4):
        sheet_add(s, f"jewel_{q + 1}", [jewel_piece(q, i, ramps[q]) for i in range(4)], "joyas")
    for q in range(4):
        s.add(f"jewel_ghost_{q + 1}", jewel_ghost(q), "joyas")
    s.add("chest_closed", chest(0))
    sheet_add(s, "chest_open", [chest(k) for k in (1, 2, 3)])
    sheet_add(s, "bag", [bag(i) for i in range(4)])
    sheet_add(s, "key", [key_pic(i) for i in range(4)])
    sheet_add(s, "carry_rock", [rock(i) for i in range(4)])
    sheet_add(s, "crate", [crate(i) for i in range(2)])
    return s


# ------------------------------------------------------------------ ITEMS32

def keyzer(i: int, flee: bool = False):
    """The key ghost (bank extra): a round head like a key's bow, a tail like its shaft with two teeth, a big key held in front."""
    bobs = [0, -1, -2, -3, -2, -1]
    bob = 0 if flee else bobs[i % 6]
    kb = 0 if flee else bobs[(i - 1) % 6]       # the key follows a frame late
    if flee:
        cx, cy, rx, ry = 17.0, 10.0 - i % 2, 7.2, 9.0
    else:
        cx, cy, rx, ry = 15.0, 12.0 + bob, 8.5, 8.0
    ph = i * TAU / (4 if flee else 6)
    p = canvas(32, 32)
    fill(p, ell(cx, cy, rx, ry), 4)
    path = []
    for k in range(11):
        t = k / 10
        if flee:
            x = cx - 3 - 10 * t + 1.2 * math.sin(ph + 4 * t)
            y = cy + 7 + 12 * t
        else:
            x = cx - 2 - 7 * t + 1.8 * math.sin(ph + 3.2 * t)
            y = cy + 6 + 10 * t
        r = 4.4 * (1 - t) + 0.6
        path.append((x, y, r))
        fill(p, ell(x, y, r, r), 4)

    def shade(x, y):
        if not p[int(y)][int(x)]:
            return 0
        nx, ny = (x - cx) / rx, (y - cy) / ry
        if nx * nx + ny * ny <= 1:
            b = -0.55 * nx - 0.7 * ny
            return 5 if b > 0.62 else 3 if b < -0.5 else 4
        return 0
    plot(p, shade)
    p = bevel(p, 5, 3, only=(4,))
    for x, y, r in path[3:]:     # the tail sinks into blue
        for yy in range(int(y - r), int(y + r) + 1):
            for xx in range(int(x), int(x + r) + 1):
                if get(p, xx, yy) == 4:
                    put(p, xx, yy, 3)
    put(p, int(cx - 4), int(cy - 5), 5)
    put(p, int(cx - 3), int(cy - 6), 5)
    p = outline(p, 1)
    ex, ey = int(cx) - 1, int(cy)
    if flee:
        for x, y in ((ex + 1, ey - 4), (ex + 2, ey - 3), (ex + 1, ey - 2), (ex + 6, ey - 4), (ex + 5, ey - 3), (ex + 6, ey - 2)):
            put(p, x, y, 1)
        for x, y in ((ex + 3, ey), (ex + 4, ey), (ex + 2, ey + 1), (ex + 5, ey + 1), (ex + 2, ey + 2), (ex + 5, ey + 2),
                     (ex + 3, ey + 3), (ex + 4, ey + 3)):
            put(p, x, y, 1)
        for x, y in ((ex + 3, ey + 1), (ex + 4, ey + 1), (ex + 3, ey + 2), (ex + 4, ey + 2)):
            put(p, x, y, 10)
        drop = canvas(32, 32)
        dx, dy = ex - 9, ey - 6 + (i % 2)
        for x, y, c in ((dx, dy, 4), (dx, dy + 1, 4), (dx - 1, dy + 1, 5), (dx + 1, dy + 2, 4), (dx, dy + 2, 4), (dx - 1, dy + 2, 4)):
            put(drop, x, y, c)
        p = overlay(p, outline(drop, 1))
        for k in range(3):       # speed lines below
            yy = 22 + 3 * k + (i + k) % 2
            x0 = 1 + (i * 2 + k * 3) % 5
            for x in range(x0, x0 + 4 - k):
                if not p[yy][x]:
                    p[yy][x] = 4
    else:
        for ox in (1, 5):
            for y in range(ey - 4, ey):
                for x in (ex + ox, ex + ox + 1):
                    put(p, x, y, 1)
            put(p, ex + ox, ey - 4, 5)
            put(p, ex + ox, ey - 3, 5 if ox == 1 else 1)
        if i in (2, 3):   # a blink-free smile that widens at the top of the hover
            mouth = [(ex + 2, ey + 1, 1), (ex + 3, ey + 2, 1), (ex + 4, ey + 2, 1), (ex + 5, ey + 1, 1), (ex + 3, ey + 1, 10), (ex + 4, ey + 1, 10)]
        else:
            mouth = [(ex + 2, ey + 1, 1), (ex + 3, ey + 2, 1), (ex + 4, ey + 2, 1), (ex + 5, ey + 1, 1)]
        for x, y, c in mouth:
            put(p, x, y, c)
        put(p, ex + 7, ey + 1, 9)
        put(p, ex + 6, ey + 1, 9)
    # the big key, held across the body: a ring bow, a long shaft, two teeth; two mitts grip it
    k = canvas(32, 32)
    ky = int(cy + 6 + (kb - bob)) if not flee else int(cy + 8)
    bx = 5 if not flee else 7
    fill(k, ell(bx + 0.5, ky + 0.5, 3.9, 3.9), 7)
    for x in range(bx + 4, bx + 22):
        k[ky - 1][x] = 7
        k[ky][x] = 6
    for x in (bx + 16, bx + 17, bx + 19, bx + 20):
        for y in range(ky + 1, ky + (4 if x < bx + 19 else 3)):
            put(k, x, y, 6 if x in (bx + 17, bx + 20) else 7)
    k = bevel(k, 8, 6, only=(7,))
    for x in range(bx + 6, bx + 15, 4):
        put(k, x, ky - 1, 8)
    k = outline(k, 1)
    for x in (bx, bx + 1):
        for y in (ky, ky + 1):
            k[y][x] = 1
    put(k, bx + 1, ky, 0)
    p = overlay(p, k)
    hands = canvas(32, 32)
    for hx in (bx + 7, bx + 13):
        for x, y, c in ((hx, ky - 3, 4), (hx + 1, ky - 3, 4), (hx, ky - 2, 4), (hx + 1, ky - 2, 3)):
            put(hands, x, y, c)
    hands = outline(hands, 1)
    for y in range(32):
        for x in range(32):
            if hands[y][x] == 1 and p[y][x] in (6, 7, 8):
                hands[y][x] = 0
    p = overlay(p, hands)
    return p


def frog(sq: float = 0.0, eyes: str = "closed", mouth: str = "closed", flash: bool = False, glint: bool = False,
         crack: bool = False, angry: bool = False):
    """The stone frog switch (bank extra) on its pedestal; `sq` squashes it (negative stretches)."""
    p = canvas(32, 32)
    for y in range(26, 31):
        for x in range(3, 29):
            p[y][x] = 12
    for x in range(3, 29):
        p[28][x] = 11
    p = bevel(p, 13, 11)
    h = 1 - sq
    ry = 7.5 * h
    rx = 11.5 + 2.5 * sq
    cy = 26.5 - ry
    body = canvas(32, 32)
    fill(body, ell(16, cy, rx, ry), 12)
    ey = cy - ry + 2.5
    for ex in (10, 22):
        fill(body, ell(ex, ey, 4.2, 3.8 * max(0.7, h)), 12)
    for lx in (7.5, 24.5):
        fill(body, ell(lx, 25.5, 3.4, 2.0), 12)
    body = bevel(body, 13, 11)
    for x, y in ((14, cy + 3), (19, cy + 4), (16, cy + 5), (8, cy + 1), (24, cy)):   # stone pits
        put(body, int(x), int(y), 11)
    for x in range(12, 21):   # pale belly
        if get(body, x, int(cy + 3)) == 12:
            put(body, x, int(cy + 3), 13)
    for ex in (10, 22):
        iy = int(ey)
        if eyes == "closed":
            for x in range(ex - 2, ex + 3):
                put(body, x, iy + 1, 11)
            for x in range(ex - 1, ex + 2):
                put(body, x, iy, 13)
        else:
            core, inner = (5, 1) if eyes == "open" else (14, 15)
            fill(body, ell(ex + 0.5, iy + 0.5, 2.3, 2.1 * max(0.7, h)), core)
            put(body, ex, iy, inner)
            put(body, ex + 1, iy, inner)
            put(body, ex, iy + 1, inner if eyes == "open" else 15)
            put(body, ex + 1, iy + 1, inner)
            put(body, ex - 1, iy - 1, 5)
    my = int(cy + 1)
    if mouth == "closed":
        for x in range(8, 25):
            put(body, x, my, 11)
        put(body, 7, my - 1, 11)
        put(body, 25, my - 1, 11)
    else:
        mh = 3 if mouth == "open" else 4
        fill(body, lambda x, y: 7.5 < x < 24.5 and my - 0.5 < y < my + mh + 0.5 - abs(x - 16) / 6, 1)
        fill(body, lambda x, y: 9 < x < 23 and my + 0.5 < y < my + mh - abs(x - 16) / 6, 10)
        fill(body, lambda x, y: 13 < x < 19 and my + mh - 1.5 < y < my + mh - 0.5, 14)
    if crack:
        for x, y in ((15, cy - ry + 1), (16, cy - ry + 2), (15, cy - ry + 3), (16, cy - ry + 4), (17, cy - ry + 4)):
            put(body, int(x), int(y), 1)
    p = overlay(p, body)
    p = outline(p, 1)
    if angry:
        for ex, d in ((10, 1), (22, -1)):
            iy = int(ey) - 3
            for k in range(4):
                put(p, ex - 2 * d + k * d, iy + (k // 2), 1)
    if flash:
        p = recol(p, {11: 10, 12: 14, 13: 15, 14: 5})
    if glint:
        twinkle(p, 7, int(ey) - 3, 1, 5)
    return p


def vortex(phase: float, R: float, dull: bool = False, sparkle: bool = True):
    """A swirling portal: three arms wound by log radius, turning with `phase`; brighter towards the eye."""
    p = canvas(32, 32)
    cx = cy = 16.0
    ramp = [1, 2, 2, 3] if dull else [1, 2, 3, 4, 5]

    def fn(x, y):
        dx, dy = x - cx, y - cy
        r = math.hypot(dx, dy)
        if r > R:
            return 0
        a = math.atan2(dy, dx)
        t = (a * 3 / TAU + 2.4 * math.log(r + 1) - phase) % 1
        v = 0.5 + 0.5 * math.cos(TAU * t)
        lvl = v * 0.75 + (1 - r / max(R, 1)) * 0.65 - (0.25 if r > R - 1.3 else 0)
        lvl += (BAYER[int(y) % 4][int(x) % 4] / 16 - 0.5) * 0.18
        return ramp[max(0, min(len(ramp) - 1, int(lvl * len(ramp))))]
    plot(p, fn)
    if R > 2:
        p = outline(p, 1)
    if sparkle and not dull and R > 6:
        for k in range(3):
            a = phase * TAU * 0.6 + k * TAU / 3
            sx, sy = int(cx + (R + 1.5) * math.cos(a)), int(cy + (R + 1.5) * math.sin(a))
            twinkle(p, sx, sy, 1, 5 if k else 4)
    return p


def treasure(i: int):
    """A heap of gold with a ruby glowing on top (bank objetos)."""
    p = canvas(32, 32)
    top = 14

    def heap(x, y):
        dx = (x - 16) / 14.5
        return abs(dx) <= 1 and y >= 31 - (31 - top) * (1 - dx * dx) ** 0.55
    fill(p, heap, 4)
    rnd = __import__("random").Random(7)
    coins = []
    for _ in range(140):
        x, y = rnd.uniform(2, 30), rnd.uniform(top, 31)
        if heap(x, y):
            coins.append((y, x, rnd.random()))
    for y, x, kind in sorted(coins):      # back to front: each coin a little lit ellipse
        face, lit, rim = (9, 10, 8) if kind < 0.05 else (3, 15, 2) if kind < 0.1 else (5, 6, 4)
        cx, cy = int(x), int(y)
        for dx, dy, c in ((-1, 0, face), (0, 0, face), (1, 0, face), (2, 0, rim), (-1, -1, lit), (0, -1, lit), (1, -1, face),
                          (0, 1, rim), (1, 1, rim), (-1, 1, rim)):
            if heap(cx + dx + 0.5, cy + dy + 0.5):
                put(p, cx + dx, cy + dy, c)
    for y in range(32):           # the shadow side
        for x in range(32):
            if p[y][x] in (4, 5, 6) and (x - 16) / 14.5 + (y - top) / 17 > 0.95:
                p[y][x] = {6: 5, 5: 4, 4: 2}[p[y][x]]
    gem_pts = [(16, top - 6), (20, top - 2), (16, top + 2), (12, top - 2)]
    g = canvas(32, 32)
    poly(g, gem_pts, 12)
    plot(g, lambda x, y: (13 if x < 16 and y < top - 2 else 11 if x >= 16 and y >= top - 2 else 0) if g[int(y)][int(x)] else 0)
    put(g, 14, top - 4, 7)
    p = overlay(p, g)
    p = outline(p, 1)
    glow = [3.0, 4.0, 5.0, 4.0][i]
    for k in range(8):
        a = k * TAU / 8 + i * 0.2
        gx, gy = int(16 + glow * 1.5 * math.cos(a)), int(top - 2 + glow * math.sin(a))
        if not get(p, gx, gy):
            put(p, gx, gy, 13 if k % 2 else 7)
    spots = [(6, 24), (25, 22), (11, 18), (21, 27)]
    sx, sy = spots[i]
    twinkle(p, sx, sy, 1, 7)
    return p


def build_items32():
    s = ART.sheet("ITEMS32", 32, 32, "extra")
    sheet_add(s, "keyzer", [keyzer(i) for i in range(6)])
    sheet_add(s, "keyzer_flee", [keyzer(i, flee=True) for i in range(4)])
    sheet_add(s, "frog_off", [frog(), frog(glint=True)])
    sheet_add(s, "frog_hit", [frog(0.25), frog(0.42, crack=True), frog(-0.12, eyes="open", crack=True)])
    sheet_add(s, "frog_on", [frog(0.0, "glow", "open", angry=True), frog(0.08, "glow", "wide", flash=True, angry=True),
                             frog(0.0, "glow", "open", angry=True), frog(-0.06, "glow", "wide", flash=True, angry=True)])
    sheet_add(s, "vortex_open", [vortex(i / 8, 14.0) for i in range(8)])
    sheet_add(s, "vortex_close", [vortex(i / 8, r) for i, r in enumerate((12.0, 9.5, 7.0, 4.8, 3.0, 1.6))])
    sheet_add(s, "vortex_closed", [vortex(0.0, 6.0, dull=True), vortex(0.35, 5.4, dull=True)])
    sheet_add(s, "treasure", [treasure(i) for i in range(4)], "objetos")
    return s


# ------------------------------------------------------------------ UI8 and UI16 (bank ui; full jewel minis in joyas)

GLYPHS = {
    "0": [".####.", "##..##", "##..##", "##..##", "##..##", ".####."],
    "1": ["..##..", ".###..", "..##..", "..##..", "..##..", ".####."],
    "2": [".####.", "##..##", "...##.", "..##..", ".##...", "######"],
    "3": ["#####.", "....##", "..###.", "....##", "....##", "#####."],
    "4": ["##.##.", "##.##.", "##.##.", "######", "...##.", "...##."],
    "5": ["######", "##....", "#####.", "....##", "....##", "#####."],
    "6": [".####.", "##....", "#####.", "##..##", "##..##", ".####."],
    "7": ["######", "....##", "...##.", "..##..", "..##..", "..##.."],
    "8": [".####.", "##..##", ".####.", "##..##", "##..##", ".####."],
    "9": [".####.", "##..##", "##..##", ".#####", "....##", ".####."],
    "x": ["......", "##..##", ".####.", "..##..", ".####.", "##..##"],
    "slash": ["....##", "...##.", "..##..", "..##..", ".##...", "##...."],
    "colon": ["......", "..##..", "..##..", "......", "..##..", "..##.."],
    "dot": ["......", "......", "......", "......", "..##..", "..##.."],
}


def glyph(rows: list[str]):
    """A HUD glyph: white above, gold below (the GBA counters' look), a chunky dark outline round it."""
    p = canvas(8, 8)
    ramp = [5, 5, 5, 4, 3, 2]
    for y, r in enumerate(rows):
        for x, ch in enumerate(r):
            if ch == "#":
                p[y + 1][x + 1] = ramp[y]
    return outline8(p, 1)


HEART_MINI = ["........", ".11.11..", "1951881.", "1988871.", "1888871.", ".18871..", "..171...", "...1...."]
HEART_MINI_EMPTY = ["........", ".11.11..", "1a61aa1.", "1aaaaa1.", "1aaaaa1.", ".1aaa1..", "..1a1...", "...1...."]
COIN_MINI = ["..1111..", ".143331.", "14533321", "14343321", "13343221", "13333221", ".132221.", "..1111.."]
KEY_MINI = ["........", "........", ".443....", ".4.3333.", ".332..2.", "........", "........", "........"]  # filled, then outlined
CLOCK_MINI = ["..1111..", ".135531.", "13551531", "13551531", "13511531", "13555521", ".122221.", "..1111.."]


def fix8(rows: list[str]) -> list[str]:
    """Hand rows padded/cut to 8 (a slip of the pen should not stop the build; the picture is checked by eye)."""
    return [(r + "........")[:8] for r in rows]


def jewel_mini(q: int, full: bool):
    sx, sy = PIECES[q][0], PIECES[q][1]
    big = canvas(16, 16)
    ramps = [(2, 3, 4, 14), (5, 6, 7, 14), (8, 9, 10, 14), (11, 12, 13, 14)]
    dark, mid, light, white = ramps[q] if full else (10, 10, 6, 6)

    def fn(x, y):
        X, Y = x - 8, y - 8
        if math.hypot(X, Y) > 6.6 or X * sx < 1 or Y * sy < 1:
            return 0
        b = -(x - 8 - sx * 3.5) - (y - 8 - sy * 3.5)
        return light if b > 1.5 else mid if b > -2.5 else dark
    plot(big, fn)
    if full:
        put(big, 8 + sx * 3 - (1 if sx > 0 else 0), 8 + sy * 3 - (1 if sy > 0 else 0), white)
    big = outline(big, 1)
    ox, oy = (0 if sx < 0 else 8), (0 if sy < 0 else 8)
    return crop(big, ox, oy, 8, 8)


def build_ui8():
    s = ART.sheet("UI8", 8, 8, "ui")
    for d in "0123456789":
        s.add(f"d_{d}", glyph(GLYPHS[d]))
    for n in ("x", "slash", "colon", "dot"):
        s.add(n, glyph(GLYPHS[n]))
    s.add("heart_mini_full", pic(fix8(HEART_MINI)))
    s.add("heart_mini_empty", pic(fix8(HEART_MINI_EMPTY)))
    s.add("coin_mini", pic(fix8(COIN_MINI)))
    for q in range(4):
        s.add(f"jewel_mini_empty_{q + 1}", jewel_mini(q, False))
    for q in range(4):
        s.add(f"jewel_mini_full_{q + 1}", jewel_mini(q, True), "joyas")
    s.add("key_mini", outline8(pic(fix8(KEY_MINI)), 1))
    s.add("clock_mini", pic(fix8(CLOCK_MINI)))
    return s


def crown(dark: int, mid: int, light: int, white: int, gem: int = 8):
    p = canvas(16, 16)
    tips = [(2.5, 4.0), (8.0, 2.5), (13.5, 4.0)]

    def top(x):
        # the rim's top edge: three points with valleys between
        return min(min(ty + abs(x - tx) * 1.6 for tx, ty in tips), 9.5)
    fill(p, lambda x, y: 1.5 < x < 14.5 and top(x) < y < 13.5, mid)
    for tx, ty in tips:
        fill(p, ell(tx, ty - 0.6, 1.4, 1.4), light)
    for x in range(2, 14):
        p[10][x] = light
        p[12][x] = dark
    p = bevel(p, light, dark, only=(mid,))
    for x in (4, 8, 12):
        p[11][x] = gem if x != 8 else 11 if gem == 8 else gem
    p[11][8] = gem
    p = outline(p, 1)
    put(p, 7, 2, white)
    put(p, 3, 7, white)
    return p


def frog_icon(i: int):
    red = i % 2 == 1
    body, dark = (8, 7) if red else (14, 15)
    p = canvas(16, 16)
    fill(p, ell(8, 10.5, 7, 4.6), body)
    for ex in (4.5, 11.5):
        fill(p, ell(ex, 5.5, 2.8, 2.6), body)
    p = bevel(p, 4 if red else 4, dark, only=(body,))
    for ex in (4, 11):
        fill(p, ell(ex + 0.5, 5.5, 1.6, 1.6), 5)
        put(p, ex + (1 if red else 0), 6, 1)
        put(p, ex, 5, 1 if red else 5)
    if red:
        mh = 2 if i == 1 else 3
        fill(p, lambda x, y: 3 < x < 13 and 9.5 < y < 9.5 + mh + 1 - abs(x - 8) / 4, 1)
        fill(p, lambda x, y: 5 < x < 11 and 10.5 < y < 9.5 + mh - abs(x - 8) / 4, 7)
    else:
        for x in range(3, 13):
            put(p, x, 10, dark)
        put(p, 2, 9, dark)
        put(p, 13, 9, dark)
    p = outline(p, 1)
    return p


def arrow_right(i: int):
    p = canvas(16, 16)
    dx = [0, 1, 2][i]
    fill(p, lambda x, y: 1.5 + dx < x < 9 + dx and 5.5 < y < 10.5, 3)
    poly(p, [(8.0 + dx, 1.5), (14.5 + dx - (1 if i == 2 else 0), 8.0), (8.0 + dx, 14.5)], 3)
    p = bevel(p, 4, 2)
    put(p, 3 + dx, 6, 5)
    put(p, 9 + dx, 4, 5)
    return outline(p, 1)


def skull(i: int):
    p = canvas(16, 16)
    fill(p, ell(8, 7, 6.2, 5.6), 5)
    jaw = 1 if i else 0
    fill(p, lambda x, y: 4.5 < x < 11.5 and 10 + jaw < y < 14 + jaw, 5)
    p = bevel(p, 5, 6)
    for ex in (5, 9):
        fill(p, lambda x, y, ex=ex: ex - 0.2 < x < ex + 2.4 and 6 < y < 9.6, 1)
    put(p, 8, 10, 1)
    put(p, 7, 10, 1)
    for x in (6, 8, 10):
        put(p, x, 12 + jaw, 6)
    if jaw:
        for x in range(5, 12):
            put(p, x, 11, 1)
    p = outline(p, 1)
    put(p, 4, 4, 5)
    return p


def build_ui16():
    s = ART.sheet("UI16", 16, 16, "ui")
    red = (8, 7, 9, 7, 5)
    sheet_add(s, "heart_full", [heart(16, 6.0, red), heart(16, 6.6, red)])
    s.add("heart_empty", heart(16, 6.0, (10, 10, 6, 10, 6)))
    full = heart(16, 6.0, red)
    crack = [(8, 4), (7, 5), (8, 6), (9, 7), (8, 8), (7, 9), (8, 10), (8, 11)]
    b0 = [r[:] for r in full]
    for x, y in crack:
        put(b0, x, y, 1)
    left = [[v if x < 8 else 0 for x, v in enumerate(r)] for r in b0]
    right = [[v if x >= 8 else 0 for x, v in enumerate(r)] for r in b0]
    b1 = overlay(shift(left, -1, 1), shift(right, 1, 0))
    b2 = overlay(shift(left, -2, 3), shift(right, 2, 2))
    sheet_add(s, "heart_break", [b0, b1, b2])
    s.add("crown_gold", crown(2, 3, 4, 5))
    s.add("crown_silver", crown(10, 11, 5, 5, 8))
    s.add("crown_bronze", crown(12, 13, 4, 5, 8))
    sheet_add(s, "frog_alarm", [frog_icon(i) for i in range(4)])
    sheet_add(s, "arrow_right", [arrow_right(i) for i in range(3)])
    sheet_add(s, "skull", [skull(i) for i in range(2)])
    return s


# ------------------------------------------------------------------ FX8 and FX16 (bank fx)

def puff(size: int, circles, light: int, dark: int, edge: int | None = 1, hole=None):
    """A cloud of circles (x, y, r), lit top-left; `hole` circles are cut out as it thins."""
    p = canvas(size, size)
    for x, y, r in circles:
        fill(p, ell(x, y, r, r), light)
    for x, y, r in hole or []:
        clear(p, ell(x, y, r, r))
    p = bevel(p, light, dark)
    for yy in range(size):          # the lower right of each lump in shade
        for xx in range(size):
            if p[yy][xx] == light and any(((xx + 0.5 - x) / r) + ((yy + 0.5 - y) / r) > 0.75 and
                                          (xx + 0.5 - x) ** 2 + (yy + 0.5 - y) ** 2 <= r * r for x, y, r in circles):
                p[yy][xx] = dark
    return outline(p, edge) if edge else p


def star_frame(size: int, cx: float, cy: float, r1: float, r2: float, rot: float, fillc: int, light: int, dark: int,
               n: int = 5, edge: int | None = 1):
    p = canvas(size, size)
    poly(p, star_pts(cx, cy, r1, r2, n, rot), fillc)
    p = bevel(p, light, dark, only=(fillc,))
    return outline(p, edge) if edge else p


def build_fx8():
    s = ART.sheet("FX8", 8, 8, "fx")
    sheet_add(s, "star_stun", [star_frame(8, 4, 4.2, 3.4, 1.5, i * TAU / 20, 4, 5, 3) for i in range(4)])
    sheet_add(s, "dust", [puff(8, [(4, 5, 1.6)], 8, 7), puff(8, [(3, 5, 2.0), (5.5, 4.5, 1.8)], 8, 7),
                          puff(8, [(2.5, 4.5, 2.0), (5.5, 4, 2.2), (4, 6, 1.6)], 8, 7, None),
                          puff(8, [(1.5, 4, 1.2), (6, 3.5, 1.3), (4, 6.5, 1.0)], 8, 7, None)])
    sp = []
    for i in range(4):
        p = canvas(8, 8)
        if i == 0:
            twinkle(p, 3, 4, 1, 5, 6)
        elif i == 1:
            twinkle(p, 3, 4, 3, 4, 6)
            for d in (-1, 1):
                put(p, 3 + d, 4 + d, 5)
                put(p, 3 + d, 4 - d, 5)
        elif i == 2:
            for k in range(-3, 4):
                put(p, 3 + k, 4 + k, 4 if abs(k) == 3 else 5)
                put(p, 3 + k, 4 - k, 4 if abs(k) == 3 else 5)
            put(p, 3, 4, 6)
        else:
            for x, y in ((0, 1), (6, 1), (0, 7), (6, 7), (3, 4)):
                put(p, x, y, 4)
        sp.append(p)
    sheet_add(s, "spark", sp)
    sheet_add(s, "smoke", [puff(8, [(4, 5, 1.8)], 10, 9), puff(8, [(3.5, 4.5, 2.4), (5, 5.5, 1.8)], 10, 9),
                           puff(8, [(3.5, 3.5, 2.6), (5.5, 4.5, 2.2)], 10, 9, None),
                           puff(8, [(2.5, 2.5, 1.6), (5.5, 3, 1.8), (4, 5, 1.2)], 10, 9, None, hole=[(4, 3.5, 1.0)])])
    bub = []
    for i, (rx, ry) in enumerate(((2.6, 2.6), (2.9, 2.3), (2.6, 2.6), (2.3, 2.9))):
        p = canvas(8, 8)
        fill(p, ell(4, 4, rx + 0.6, ry + 0.6), 12)
        clear(p, ell(4, 4, rx - 0.5, ry - 0.5))
        put(p, 2, 3, 6)
        put(p, 3, 2, 13)
        put(p, 5, 5, 11)
        bub.append(p)
    sheet_add(s, "bubble", bub)
    rock = [(1.5, 3.0), (4.0, 1.0), (6.5, 2.5), (6.0, 5.5), (3.0, 6.5)]
    deb = []
    for i in range(4):
        a = i * TAU / 4
        pts = [(4 + (x - 4) * math.cos(a) - (y - 4) * math.sin(a), 4 + (x - 4) * math.sin(a) + (y - 4) * math.cos(a)) for x, y in rock]
        p = canvas(8, 8)
        poly(p, [(4 + (x - 4) * 0.85, 4 + (y - 4) * 0.85) for x, y in pts], 15)
        p = bevel(p, 8, 14, only=(15,))
        deb.append(outline(p, 1))
    sheet_add(s, "debris", deb)
    cs = []
    for i, k in enumerate((1, 2, 3, 1)):
        p = canvas(8, 8)
        twinkle(p, 4, 4, k, 4 if k > 1 else 5, 6)
        if k == 3:
            for d in (-1, 1):
                put(p, 4 + d, 4 + d, 5)
                put(p, 4 - d, 4 + d, 5)
        cs.append(p)
    sheet_add(s, "coin_spark", cs)
    em = []
    for i in range(4):
        p = canvas(8, 8)
        y0 = 5 - i
        shape = [(3, y0, 3), (4, y0, 2), (3, y0 + 1, 2), (4, y0 + 1, 3), (3, y0 - 1, 4 if i % 2 else 5)]
        if i == 3:
            shape = [(3, y0 + 1, 2), (4, y0, 3)]
        for x, y, c in shape:
            put(p, x + (1 if i == 2 else 0), y, c)
        em.append(p)
    sheet_add(s, "ember", em)
    return s


def flame(i: int, size: int = 16):
    """A flame flickering: three tongues of fire stacked, tips swaying out of step."""
    p = canvas(size, size)
    ph = i * TAU / 6
    layers = [(2, 6.0, 12.5, 0), (3, 4.6, 10.5, 0.8), (4, 3.2, 8.0, 1.6), (5, 1.6, 5.0, 2.4)]
    for c, w, h, lag in layers:
        def fn(x, y, c=c, w=w, h=h, lag=lag):
            base = 15.0
            t = (base - y) / h            # 0 at the base, 1 at the tip
            if t < 0 or t > 1:
                return 0
            sway = 1.6 * math.sin(ph - lag + t * 2.2) * t
            half = w * (math.sin(math.pi * min(1.0, 0.35 + t * 0.9)) if t > 0.1 else 0.8 + t * 2) * (1 - t) ** 0.6
            return c if abs(x - 8 - sway) <= half else 0
        plot(p, fn)
    tip = [(8 + int(2 * math.sin(ph)), 1), (7 + int(2 * math.sin(ph + 1)), 2)]
    for x, y in tip[: 1 + i % 2]:
        put(p, x, y, 3)
    return outline(p, 1)


def explosion(i: int):
    p = canvas(16, 16)
    if i == 0:
        fill(p, ell(8, 8, 3.2, 3.2), 6)
        twinkle(p, 8, 8, 6, 5, 6)
        return outline(p, 4)
    if i in (1, 2):
        r = 6.0 if i == 1 else 7.0
        lumps = [(8 + r * 0.55 * math.cos(a), 8 + r * 0.55 * math.sin(a), r * 0.5) for a in [k * TAU / 7 + i for k in range(7)]]
        for x, y, rr in lumps:
            fill(p, ell(x, y, rr, rr), 2)
        fill(p, ell(8, 8, r * 0.85, r * 0.85), 3)
        fill(p, ell(7.5, 7.5, r * 0.6, r * 0.6), 4)
        fill(p, ell(7, 7, r * 0.35, r * 0.35), 5 if i == 2 else 6)
        return outline(p, 1)
    if i == 3:
        c = puff(16, [(5, 7, 3.6), (10.5, 6.5, 3.6), (8, 10.5, 3.6), (8, 4, 2.6)], 3, 2)
        for x, y in ((6, 6), (9, 5), (10, 9), (5, 9)):
            put(c, x, y, 4)
        put(c, 7, 7, 5)
        return c
    if i == 4:
        c = puff(16, [(5, 7, 3.4), (11, 6, 3.2), (8, 11, 3.0), (8, 3.5, 2.2)], 10, 9)
        for x, y in ((5, 7), (10, 6), (8, 10)):
            put(c, x, y, 3)
            put(c, x + 1, y, 2)
        return c
    return puff(16, [(4, 6, 2.2), (11, 5, 2.4), (8, 11, 2.0)], 10, 9, None, hole=[(7.5, 7, 1.5)])


def build_fx16():
    s = ART.sheet("FX16", 16, 16, "fx")
    imp = []
    for i in range(4):
        if i == 0:
            p = star_frame(16, 8, 8, 4.5, 2.0, 0.4, 6, 6, 5, 4, edge=4)
        elif i == 1:
            p = star_frame(16, 8, 8, 7.6, 3.4, 0.2, 5, 6, 4, 8, edge=3)
            fill(p, ell(8, 8, 2.2, 2.2), 6)
        elif i == 2:
            p = star_frame(16, 8, 8, 7.8, 4.2, 0.0, 4, 5, 3, 8, edge=2)
            clear(p, ell(8, 8, 3.6, 3.6))
        else:
            p = canvas(16, 16)
            for k in range(8):
                a = k * TAU / 8 + 0.2
                x, y = int(8 + 6.5 * math.cos(a)), int(8 + 6.5 * math.sin(a))
                put(p, x, y, 4)
                put(p, int(8 + 5.2 * math.cos(a)), int(8 + 5.2 * math.sin(a)), 3)
        imp.append(p)
    sheet_add(s, "impact", imp)
    sm = []
    for i, (rx, ry) in enumerate(((2.5, 1.0), (4.5, 1.6), (6.3, 2.2), (7.2, 2.6))):
        p = canvas(16, 16)
        for k in range(64):     # the shock ring lying on the ground: its near half bright, its far half pale
            a = k * TAU / 64
            x, y = 8 + rx * math.cos(a), 13 + ry * math.sin(a)
            if i < 3 or k % 3 == 0:
                put(p, int(x), int(y), 6 if math.sin(a) > 0 else 5)
        if i >= 1:
            r = [0, 1.6, 2.0, 1.4][i]
            for d in (-1, 1):
                pf = puff(16, [(8 + d * rx, 12.5 - i * 0.6, r)], 8, 7, None)
                p = overlay(p, pf)
        if i == 1:
            for x, y in ((3, 8), (12, 8)):
                put(p, x, y, 5)
        if i == 2:
            for x, y in ((1, 7), (14, 6)):
                put(p, x, y, 4)
        sm.append(p)
    sheet_add(s, "smash", sm)
    sheet_add(s, "explode", [explosion(i) for i in range(6)])
    sheet_add(s, "flame", [flame(i) for i in range(6)])
    spl = []
    for i in range(4):
        p = canvas(16, 16)
        if i < 2:   # a crown of water: two jets leaning out, a column in the middle
            hgt = 5 if i == 0 else 10
            for d in (-1, 1):
                for k in range(hgt):
                    x = 8 + d * (3 + k * 0.45)
                    put(p, int(x), 14 - k, 13 if k > hgt - 3 else 12)
                    put(p, int(x - d), 14 - k, 12 if k > hgt - 3 else 11)
            for k in range(hgt - 3):
                put(p, 7, 14 - k, 13)
                put(p, 8, 14 - k, 12)
            fill(p, ell(8, 14.5, 6.5, 1.6), 12)
            if i == 1:
                for x, y in ((2, 4), (14, 3), (8, 2)):
                    fill(p, ell(x + 0.5, y + 0.5, 1.0, 1.2), 13)
        else:
            drops = [(3, 6), (13, 5), (8, 4), (5, 9), (11, 8)] if i == 2 else [(2, 11), (14, 10), (6, 12), (10, 12)]
            for x, y in drops:
                put(p, x, y, 13)
                put(p, x, y + 1, 12)
            fill(p, ell(8, 14.5, 5.0 if i == 2 else 3.5, 1.2), 12)
        spl.append(outline(p, 11))
    sheet_add(s, "splash", spl)
    rip = []
    for i in range(4):
        p = canvas(16, 16)
        for k, r in enumerate((2.0 + 2 * i, 2 * i - 1.0)):
            if r <= 0.5:
                continue
            ring = ell(8, 11, r + 0.6, r * 0.38 + 0.6)
            hole = ell(8, 11, max(0.3, r - 0.6), max(0.3, r * 0.38 - 0.4))
            fill(p, lambda x, y, ring=ring, hole=hole: ring(x, y) and not hole(x, y) and y < 11, 13 if k == 0 and i < 3 else 12)
            fill(p, lambda x, y, ring=ring, hole=hole: ring(x, y) and not hole(x, y) and y >= 11, 12 if k == 0 and i < 3 else 11)
        rip.append(p)
    sheet_add(s, "ripple", rip)
    spd = []
    for i in range(3):
        p = canvas(16, 16)
        for k, (y, ln) in enumerate(((3, 7), (6, 11), (9, 9), (12, 6))):
            x0 = (k * 5 + i * 4) % 9
            for x in range(x0, min(16, x0 + ln)):
                put(p, x, y, 6 if x > x0 + ln * 2 // 3 else 10 if x > x0 + ln // 3 else 9)
        spd.append(p)
    sheet_add(s, "speed", spd)
    sheet_add(s, "poof", [puff(16, [(8, 9, 3.4)], 6, 10), puff(16, [(5, 9, 3.6), (11, 9, 3.6), (8, 5.5, 3.6), (8, 11.5, 3)], 6, 10),
                          puff(16, [(4, 8, 3.2), (12, 8, 3.2), (8, 4.5, 3), (8, 12, 2.8)], 6, 10, 9, hole=[(8, 8.5, 2.6)]),
                          puff(16, [(3, 7, 1.8), (13, 7, 1.8), (8, 2.5, 1.6), (8, 13.5, 1.6)], 6, 10, None)])
    spk = []
    for i, k in enumerate((1, 3, 5, 6, 4, 2)):
        p = canvas(16, 16)
        twinkle(p, 8, 8, k, 4 if k > 2 else 5, 6)
        if k >= 3:
            for d in range(1, k // 2 + 1):
                for sx, sy in ((1, 1), (-1, 1), (1, -1), (-1, -1)):
                    put(p, 8 + sx * d, 8 + sy * d, 5)
            for d in range(1, 3):
                put(p, 8 - d, 8, 6)
                put(p, 8 + d, 8, 6)
                put(p, 8, 8 - d, 6)
                put(p, 8, 8 + d, 6)
        if i in (2, 3):
            put(p, 3, 3, 4)
            put(p, 13, 12, 5)
        spk.append(p)
    sheet_add(s, "sparkle", spk)
    hits = []
    jag = [7.5, 4.0, 6.5, 3.5, 7.8, 3.8, 6.0, 3.2, 7.2, 4.2, 6.8, 3.6]
    for i, sc in enumerate((0.6, 1.0, 0.85)):
        p = canvas(16, 16)
        pts = [(8 + sc * r * math.sin(k * TAU / 12 + i * 0.25), 8 - sc * r * math.cos(k * TAU / 12 + i * 0.25)) for k, r in enumerate(jag)]
        poly(p, pts, 6)
        p = outline(p, 4)
        p = outline(p, 3)
        if i == 2:
            clear(p, ell(8, 8, 2.5, 2.5))
        hits.append(p)
    sheet_add(s, "hit", hits)
    return s


# ------------------------------------------------------------------ MAPA16 (bank mapa)

def node_pad(top: int, rim: int, side: int, glow: int | None = None):
    """A round stone pad seen from above at an angle: a lit top face and a band of side below it."""
    p = canvas(16, 16)
    fill(p, ell(8, 12.0, 6.6, 3.4), side)
    fill(p, ell(8, 10.5, 6.6, 3.4), rim)
    fill(p, ell(8, 10.2, 5.4, 2.6), top)
    put(p, 4, 9, 8 if glow is None else glow)
    return p


def map_node(kind: str, i: int = 0):
    if kind == "idle":
        p = node_pad(14, 13, 15)
        r = [1.6, 2.2, 2.8, 2.2][i]
        fill(p, ell(8, 10.2, r, r * 0.6), 11)
        fill(p, ell(8, 10.2, r * 0.5, r * 0.35), 8 if i == 2 else 12)
        for k in range(1, i + 1):          # a beam of light rising and falling
            put(p, 8, 9 - 2 * k, 12 if k < i else 8)
    elif kind == "done":
        p = node_pad(9, 10, 6)
        for y in range(2, 11):
            put(p, 7, y, 15)
        wave = [0, 1, 0, -1][i]
        for y in range(2, 6):
            for x in range(8, 13):
                yy = y + (wave if x > 10 else 0) + (1 if x == 12 and i % 2 else 0)
                put(p, x, yy, 5 if y < 4 else 4)
        put(p, 7, 1, 9)
    elif kind == "locked":
        p = node_pad(13, 14, 15)
        fill(p, lambda x, y: 5 <= x <= 11 and 6 <= y <= 11, 9)
        fill(p, lambda x, y: 6 <= x <= 10 and 2.5 <= y <= 6, 13)
        clear(p, lambda x, y: 7 <= x <= 9 and 3.5 <= y <= 6)
        p = bevel(p, 8, 10, only=(9,))
        put(p, 8, 8, 1)
        put(p, 8, 9, 1)
    else:  # boss
        p = node_pad(5, 4, 15)
        lift = [0, -1, -1, 0][i]
        sk = canvas(16, 16)
        fill(sk, ell(8, 6 + lift, 3.6, 3.2), 8)
        fill(sk, lambda x, y: 6 <= x <= 10 and 8.5 + lift <= y <= 10.5 + lift, 8)
        sk = bevel(sk, 8, 14)
        for x in (6, 9):
            put(sk, x, 6 + lift, 1)
            put(sk, x + 1, 6 + lift, 1 if i % 2 == 0 else 5)
        put(sk, 8, 10 + lift, 1)
        sk = outline(sk, 1)
        p = overlay(p, sk)
    return outline(p, 1)


def map_token(i: int):
    """Zurrón on the map, walking right in six frames: bandana, big nose, a sack on his back."""
    ph = i * TAU / 6
    bob = -1 if i in (1, 4) else 0
    p = canvas(16, 16)
    # legs first (behind the body)
    for k, d in enumerate((1, -1)):
        lx = 8.5 + d * 1.8 * math.sin(ph)
        top = 11 + bob
        for y in range(top, 15):
            put(p, int(lx), y, 15)
        put(p, int(lx) + 1, 14, 6)
        put(p, int(lx), 14, 6)
    fill(p, ell(9, 10 + bob, 3.3, 2.6), 11)
    fill(p, ell(5, 8 + bob, 3.0, 3.4), 7)       # the sack
    fill(p, ell(9.5, 5 + bob, 3.2, 3.0), 3)     # the head
    for y in range(16):
        for x in range(16):
            if p[y][x] == 3 and y <= 4 + bob:
                p[y][x] = 5
    head = canvas(16, 16)
    fill(head, ell(12.6, 6.6 + bob, 1.4, 1.2), 3)    # the nose
    p = overlay(p, head)
    p = bevel(p, 8, 4, only=(5,))
    p = bevel(p, 7, 6, only=(7,))
    for y in range(16):
        for x in range(16):
            if p[y][x] == 11 and x <= 7:
                p[y][x] = 15
    tail = int(math.sin(ph) > 0)
    put(p, 6, 3 + bob + tail, 5)
    put(p, 5, 4 + bob, 4)
    put(p, 11, 5 + bob, 1)
    put(p, 10, 7 + bob, 2)
    put(p, 11, 7 + bob, 2)
    put(p, 13, 7 + bob, 2)
    sw = int(1.5 * math.sin(ph + math.pi))
    put(p, 10 + sw, 10 + bob, 3)
    put(p, 4, 5 + bob, 6)
    return outline(p, 1)


def map_arrow(up: bool, i: int):
    p = canvas(16, 16)
    off = [0, -1, -2][i] * (1 if up else -1)
    if up:
        poly(p, [(8, 3 + off), (13.5, 10 + off), (2.5, 10 + off)], 9)
        fill(p, lambda x, y: 6 < x < 10 and 10 + off <= y < 13 + off, 9)
    else:
        poly(p, [(8, 13 - off), (13.5, 6 - off), (2.5, 6 - off)], 9)
        fill(p, lambda x, y: 6 < x < 10 and 3 - off < y <= 6 - off, 9)
    p = bevel(p, 8, 10)
    return outline(p, 1)


def build_mapa16():
    s = ART.sheet("MAPA16", 16, 16, "mapa")
    sheet_add(s, "node_idle", [map_node("idle", i) for i in range(4)])
    sheet_add(s, "node_done", [map_node("done", i) for i in range(4)])
    s.add("node_locked", map_node("locked"))
    sheet_add(s, "node_boss", [map_node("boss", i) for i in range(4)])
    sheet_add(s, "token", [map_token(i) for i in range(6)])
    sheet_add(s, "arrow_up", [map_arrow(True, i) for i in range(3)])
    sheet_add(s, "arrow_down", [map_arrow(False, i) for i in range(3)])
    return s


# ------------------------------------------------------------------ title pictures (palette set "titulo")

# logo: 1 outline | 2 3 4 extrusion brown..orange | 5 6 7 8 gold deep..pale | 9 white | a b c ruby | d e blue | f cream
ART.palette("titulo", "logo", ["#2a0c28", "#6c2410", "#a84410", "#d87018", "#c07800", "#f0a810", "#ffd030", "#fff070",
                               "#ffffff", "#800c30", "#e02048", "#ff90a8", "#1848b8", "#58b0ff", "#fff8d0"])
# fondo: 1..7 dusk sky indigo..cream | 8 9 a sea | b c d jungle | e volcano rock | f lava
ART.palette("titulo", "fondo", ["#1a1040", "#3c2470", "#7c3c8c", "#d8587c", "#ff9848", "#ffd060", "#fff4c0",
                                "#142858", "#1c6890", "#40b0c0", "#0c3020", "#1c6830", "#48a838", "#5a2848", "#e83818"])
# mapa_isla: 1 2 3 4 sea deep..surf | 5 6 sand | 7 8 9 jungle | a b crystal rock | c volcano | d e lava | f outline
ART.palette("titulo", "mapa_isla", ["#102050", "#1c4890", "#2c80c8", "#60c8e0", "#fff4c8", "#f0c870", "#1c6830",
                                    "#3ca040", "#90d850", "#5a4888", "#a888f0", "#5a2840", "#e83818", "#ffa030", "#2a1430"])


def _hash(ix: int, iy: int, seed: int) -> float:
    h = (ix * 374761393 + iy * 668265263 + seed * 2147483647) & 0xFFFFFFFF
    h = ((h ^ (h >> 13)) * 1274126177) & 0xFFFFFFFF
    return (h ^ (h >> 16)) / 0xFFFFFFFF


def vnoise(x: float, y: float, seed: int = 0, period: int | None = None) -> float:
    """Smooth value noise in 0..1; `period` (in lattice cells) makes it wrap horizontally."""
    ix, iy = math.floor(x), math.floor(y)
    fx, fy = x - ix, y - iy
    sx, sy = fx * fx * (3 - 2 * fx), fy * fy * (3 - 2 * fy)

    def v(a, b):
        return _hash(a % period if period else a, b, seed)
    top = v(ix, iy) + (v(ix + 1, iy) - v(ix, iy)) * sx
    bot = v(ix, iy + 1) + (v(ix + 1, iy + 1) - v(ix, iy + 1)) * sx
    return top + (bot - top) * sy


def fbm(x: float, y: float, seed: int = 0, period: int | None = None, octaves: int = 3) -> float:
    total, amp, norm = 0.0, 1.0, 0.0
    for o in range(octaves):
        total += amp * vnoise(x * 2 ** o, y * 2 ** o, seed + o, period * 2 ** o if period else None)
        norm += amp
        amp *= 0.5
    return total / norm


def dth(x: int, y: int) -> float:
    return (BAYER[y % 4][x % 4] + 0.5) / 16


# --- the logo

LETTERS = {
    "B": ["#####.", "##..##", "##..##", "#####.", "##..##", "##..##", "#####."],
    "T": ["######", "######", "..##..", "..##..", "..##..", "..##..", "..##.."],
    "I": ["##", "##", "##", "##", "##", "##", "##"],
    "N": ["##...##", "###..##", "####.##", "##.####", "##..###", "##...##", "##...##"],
}


def round_corners(m, passes: int = 1):
    for _ in range(passes):
        out = [r[:] for r in m]
        for y in range(len(m)):
            for x in range(len(m[0])):
                if m[y][x]:
                    n = [get(m, x + dx, y + dy) for dx, dy in ((1, 0), (-1, 0), (0, 1), (0, -1))]
                    if sum(1 for v in n if v) <= 2 and ((not n[0] or not n[1]) and (not n[2] or not n[3])):
                        out[y][x] = 0
        m = out
    return m


def paint_logo():
    W, H = 160, 48
    CW, CH, TOP = 4, 5, 6
    face = canvas(W, H)
    letter_of = canvas(W, H)
    x = 10
    coin_c = None
    for k, ch in enumerate("BOTIN"):
        if ch == "O":
            coin_c = (x + 17, TOP + 17.5)
            fill(face, ell(coin_c[0], coin_c[1], 17.5, 17.5), 1)
            x += 35 + 4
            continue
        rows = LETTERS[ch]
        lm = canvas(W, H)
        for ry, r in enumerate(rows):
            for rx, c in enumerate(r):
                if c == "#":
                    for yy in range(CH):
                        for xx in range(CW):
                            put(lm, x + rx * CW + xx, TOP + ry * CH + yy, 1)
        lm = round_corners(lm)
        for yy in range(H):
            for xx in range(W):
                if lm[yy][xx]:
                    face[yy][xx] = 1
                    letter_of[yy][xx] = k + 1
        x += len(rows[0]) * CW + 4
    ex = canvas(W, H)                  # the extrusion: the faces pushed down and right
    for d in range(1, 5):
        for yy in range(H):
            for xx in range(W):
                if get(face, xx - d, yy - d) and not face[yy][xx]:
                    ex[yy][xx] = 3
    for yy in range(H):
        for xx in range(W):
            if ex[yy][xx] and not get(ex, xx + 1, yy + 1) and not get(face, xx + 1, yy + 1):
                ex[yy][xx] = 2
            elif ex[yy][xx] and get(face, xx - 1, yy - 1) and get(face, xx, yy - 1):
                ex[yy][xx] = 4
    p = canvas(W, H)
    grad = [(0.0, 8), (0.18, 7), (0.45, 6), (0.75, 5)]
    for yy in range(H):
        for xx in range(W):
            if ex[yy][xx]:
                p[yy][xx] = ex[yy][xx]
            if face[yy][xx]:
                t = (yy - TOP) / 35 + (dth(xx, yy) - 0.5) * 0.12
                c = 8
                for th, col in grad:
                    if t >= th:
                        c = col
                p[yy][xx] = c
    for yy in range(H):     # bevel inside the faces: a white lip top-left, a deep lip bottom-right; the shine band
        for xx in range(W):
            if not face[yy][xx]:
                continue
            if not get(face, xx - 1, yy) or not get(face, xx, yy - 1):
                p[yy][xx] = 9 if (yy - TOP) < 18 else 8
            elif not get(face, xx + 1, yy) or not get(face, xx, yy + 1):
                p[yy][xx] = 5
            elif TOP + 11 <= yy <= TOP + 12 and letter_of[yy][xx]:
                p[yy][xx] = 8
    cx, cy = coin_c       # the O is a big gold coin: rim, face, an embossed star
    for yy in range(H):
        for xx in range(W):
            dx, dy = xx + 0.5 - cx, yy + 0.5 - cy
            r = math.hypot(dx, dy)
            if r > 17.5:
                continue
            lit = -(dx + dy) / max(r, 0.1)
            if r > 15.5:
                p[yy][xx] = 9 if lit > 0.6 else 7 if lit > -0.2 else 5
            elif r > 13.5:
                p[yy][xx] = 5 if lit > 0.3 else 7
            else:
                t = (dy + 13) / 26 + (dth(xx, yy) - 0.5) * 0.15
                p[yy][xx] = 8 if t < 0.2 else 7 if t < 0.55 else 6
    st = canvas(W, H)
    poly(st, star_pts(cx, cy + 0.5, 10.5, 4.6, 5, 0.0), 6)
    st = bevel(st, 8, 5, only=(6,))
    for yy in range(H):
        for xx in range(W):
            if st[yy][xx]:
                p[yy][xx] = st[yy][xx]
    gem_x = 10 + 24 + 4 + 39 + 24 + 4 + 4            # the accent of the I is a ruby
    g = canvas(W, H)
    pts = [(gem_x + 2, 0.5), (gem_x + 7.5, 4.0), (gem_x + 3.0, 9.5), (gem_x - 2.5, 5.0)]
    poly(g, pts, 11)
    for yy in range(H):
        for xx in range(W):
            if g[yy][xx]:
                g[yy][xx] = 12 if xx + 0.5 < gem_x + 2.5 and yy < 5 else 10 if xx >= gem_x + 2 and yy >= 5 else 11
    put(g, gem_x, 3, 9)
    p = overlay(p, g)
    p = outline8(p, 1)
    p = outline(p, 1)
    for sx, sy, k in ((13, 8, 2), (int(cx) - 9, int(cy) - 11, 3), (gem_x + 6, 2, 1), (150, 34, 2)):
        twinkle(p, sx, sy, k, 9)
    return p


# --- the title illustration

def paint_titulo_fondo():
    W, H, HZ = 256, 160, 94
    p = canvas(W, H)
    sun = (205, 88)
    sky = [(0, 1), (16, 2), (36, 3), (56, 4), (72, 5), (84, 6)]
    for y in range(HZ):
        for x in range(W):
            yy = y + (dth(x, y) - 0.5) * 9
            c = 1
            for y0, col in sky:
                if yy >= y0:
                    c = col
            p[y][x] = c
    for y in range(HZ):               # the sun and its halo
        for x in range(W):
            r = math.hypot((x - sun[0]) * 1.0, (y - sun[1]) * 1.25)
            if r < 14:
                p[y][x] = 7
            elif r < 22 + dth(x, y) * 6:
                p[y][x] = max(p[y][x], 6) if p[y][x] < 6 else p[y][x]
            elif r < 34 + dth(x, y) * 10 and p[y][x] < 5:
                p[y][x] = 5 if p[y][x] >= 4 else p[y][x] + 1
    clouds = [(30, 22, 30, 5.0), (122, 14, 22, 4.0), (172, 38, 34, 5.5), (62, 50, 26, 4.5), (236, 20, 22, 4.0),
              (104, 66, 38, 4.5), (8, 74, 30, 4.0), (156, 76, 24, 3.5)]
    for ci, (cx, cy, w, h) in enumerate(clouds):     # cumulus: overlapping lumps on a flat base, lit from the low sun
        step = w * 2 / 5
        lumps = [(cx - w + step * k, cy - h * 0.3 * _hash(ci, k, 5), step * (0.75 + 0.45 * _hash(ci, k, 6)) * (1.0 if 0 < k < 5 else 0.7))
                 for k in range(6)]
        base = cy + h * 0.6

        def inside(x, y, lumps=lumps, base=base):
            return y <= base and any(math.hypot(x - lx, (y - ly) * 1.6) <= lr for lx, ly, lr in lumps)
        for y in range(int(cy - h * 4), int(base) + 1):
            if not 0 <= y < HZ:
                continue
            for x in range(int(cx - w - step), int(cx + w + step)):
                if not inside(x, y):
                    continue
                xx = x % W
                near = math.hypot(xx - sun[0], y - sun[1]) < 75
                rim = not inside(x + 2, y) or not inside(x, y + 2) or y >= base - 1
                top = not inside(x - 1, y - 2)
                body = 4 if near or cy > 55 else 3
                p[y][xx] = (6 if near else 5) if rim else (body if not top or near else body - 1 if body > 3 else 3)
    for y in range(HZ, H):            # the sea, darker as it comes near
        for x in range(W):
            d = (y - HZ) / (H - HZ)
            n = fbm(x / 8, y / 2.2, 3, period=32)
            base = 10 if d < 0.05 else 9 if d < 0.45 else 8
            if n > 0.66 - d * 0.1:
                base = 10 if base == 9 else 9 if base == 8 else 7 if d < 0.05 else 10
            spread = 10 + (y - HZ) * 0.55
            if abs(x - sun[0]) < spread and fbm(x / 6, y / 1.5, 5, period=43) > 0.55 - 0.25 * (1 - abs(x - sun[0]) / spread):
                base = 7 if abs(x - sun[0]) < spread * 0.4 and d < 0.6 else 6
            p[y][x] = base
    # the volcano
    for x in range(36, 176):
        vh = max(0.0, 68 - abs(x - 104) * 1.05 - (4 if abs(x - 104) < 6 else 0))
        top = int(HZ - vh)
        for y in range(top, HZ):
            lit = (x - 104) > 0 and (x - 104) > (y - top) * 0.2
            ridge = fbm(x / 3.0, y / 14.0, 9) > 0.62
            p[y][x] = (3 if not ridge else 14) if lit and x > 104 + (y - top) * 0.15 else (2 if ridge else 14)
        if abs(x - 104) < 5:
            for y in range(top, top + 2):
                p[y][x] = 15 if y == top else 5
    for k in range(40):               # a lava stream down the left flank
        t = k / 40
        x = int(102 - 22 * t + 3 * math.sin(t * 7))
        y = int(HZ - 64 + 50 * t)
        put(p, x, y, 15)
        put(p, x + 1, y, 5 if k % 3 else 15)
    path = [(104 - 60 * t - 8 * t * t, 25 - 22 * t + 6 * t * t, 2.5 + 5.5 * t) for t in [k / 30 for k in range(31)]]
    for y in range(0, 40):            # the smoke plume, leaning away from the sun
        for x in range(30, 112):
            for px_, py_, r in path:
                d = math.hypot(x - px_, (y - py_) * 1.3)
                rr = r * (0.7 + 0.6 * fbm(x / 6, y / 6, 71))
                if d < rr:
                    lit = (x - px_) > rr * 0.35 or (y - py_) > rr * 0.6
                    p[y][x] = 4 if lit else 3
                    break
    # jungle hills in front of the volcano, lit from the sun on the right
    for x in range(22, 190):
        edge = min(1.0, (x - 22) / 26, (190 - x) / 26)
        hh = (18 + 6 * math.sin(x / 9.0) + 8 * fbm(x / 14, 0.5, 11)) * edge
        top = int(HZ - hh)
        for y in range(top, HZ):
            depth = (y - top) / max(1, hh)
            n = fbm(x / 4.0, y / 4.0, 13)
            c = 13 if n > 0.6 and depth < 0.5 else 12 if depth < 0.75 - (0.25 if n < 0.4 else 0) else 11
            if depth > 0.85 and dth(x, y) > 0.5:
                c = 11
            p[y][x] = c
        if hh > 2:
            p[top][x] = 13
    for bx, by, r in ((60, 79, 6), (78, 75, 7), (132, 76, 7), (150, 80, 6), (112, 78, 5), (168, 84, 5), (40, 84, 5)):
        for y in range(by - r, by + r):
            for x in range(bx - r, bx + r):
                dd = math.hypot(x - bx, y - by)
                if dd <= r and y < HZ:
                    p[y][x] = 13 if (x - bx) - (y - by) > r * 0.3 else 12 if dd < r - 1 or y < by else 11
    # the treasure glowing in a cave mouth
    gx, gy = 88, 86
    for y in range(gy - 10, gy + 6):
        for x in range(gx - 14, gx + 15):
            r = math.hypot(x - gx, (y - gy) * 1.6)
            if r < 4:
                p[y][x] = 7
            elif r < 7 and dth(x, y) < 0.75:
                p[y][x] = 6
            elif r < 11 and dth(x, y) < 0.3:
                p[y][x] = 6
    twinkle(p, gx, gy - 7, 3, 7)
    # palms on the beach
    for px0, lean, hgt in ((30, 1, 26), (44, 1, 20), (178, -1, 24)):
        tops = None
        for k in range(hgt):
            x = int(px0 + lean * (k * k) / (hgt * 2.2))
            y = HZ - 1 - k
            put(p, x, y, 11)
            put(p, x + 1, y, 11 if k % 3 else 12)
            tops = (x, y)
        tx, ty = tops
        for ang in (-2.6, -2.0, -1.2, -0.4, 0.3):
            for k in range(11):
                a = ang + lean * 0.1
                x = int(tx + math.cos(a) * k * 1.3)
                y = int(ty + math.sin(a) * k * 0.9 + (k * k) / 22)
                put(p, x, y, 11)
                put(p, x, y + 1, 12 if k < 7 else 11)
    for x in range(14, 200):          # the beach
        edge = min(1.0, (x - 14) / 12, (200 - x) / 12)
        for y in range(HZ - 2, HZ + int(3 * edge)):
            p[y][x] = 6 if y < HZ else 5
        p[HZ + int(3 * edge)][x] = 10
    # the wreck against the sun
    hull = [(186, 101), (224, 93), (232, 99), (226, 107), (192, 108)]
    poly(p, hull, 1)
    top_rows = {}
    for x in range(186, 233):
        for y in range(88, 110):
            if p[y][x] == 1:
                top_rows.setdefault(x, y)
    for x, y in top_rows.items():      # only a rim of sunlight on the deck
        p[y][x] = 5
    for x in range(190, 226, 5):       # gun ports
        y = top_rows.get(x, 100) + 4
        if p[y][x] == 1:
            p[y][x] = 2
    line(p, 205, 98, 213, 52, 1)
    line(p, 206, 98, 214, 52, 1)
    line(p, 200, 66, 224, 70, 1)
    poly(p, [(203, 68), (222, 71), (219, 86), (210, 80), (205, 88)], 2)
    for x, y in ((210, 74), (214, 78), (216, 73)):
        p[y][x] = 4
    line(p, 186, 101, 178, 96, 1)
    for x in range(176, 240):
        if p[110][x] in (8, 9):
            p[110][x] = 10 if x % 3 else 9
    return p


# --- the island seen from above, for the map screen

MAP_NODES = {"selva": (58, 96), "cristal": (106, 40), "galeon": (212, 100), "fragua": (146, 72), "jefe": (128, 128)}


def paint_mapa_fondo():
    W, H = 256, 160
    p = canvas(W, H)
    cx, cy = 132.0, 84.0

    def land(x, y):
        a = math.atan2(y - cy, x - cx)
        r = math.hypot((x - cx) / 104, (y - cy) / 62)
        wob = 0.12 * math.sin(3 * a + 0.5) + 0.08 * math.sin(5 * a + 2) + 0.18 * (fbm(x / 26, y / 26, 21) - 0.5)
        if 0.2 < a < 0.9:     # a bay on the south-east where the galleon lies
            wob -= 0.22 * math.sin((a - 0.2) / 0.7 * math.pi)
        return 1.0 + wob - r      # > 0 on land
    for y in range(H):
        for x in range(W):
            v = land(x + 0.5, y + 0.5)
            n = fbm(x / 9, y / 9, 31, period=28)
            if v > 0.06:
                c = 6
            elif v > 0.0:
                c = 5
            elif v > -0.05:
                c = 4
            elif v > -0.14 - n * 0.06:
                c = 3
            elif v > -0.3 - n * 0.1:
                c = 2
            else:
                c = 1
            if c in (1, 2) and fbm(x / 5, y / 1.6, 33, period=51) > 0.68:
                c += 1
            p[y][x] = c
    for y in range(H):        # jungle over the west and south, grass at its edge
        for x in range(W):
            if p[y][x] != 6:
                continue
            v = land(x + 0.5, y + 0.5)
            n = fbm(x / 7, y / 7, 41)
            if v > 0.12:
                p[y][x] = 9 if n > 0.62 else 8 if n > 0.42 else 7
    for y in range(18, 64):   # the crystal ridge to the north
        for x in range(76, 140):
            if p[y][x] in (7, 8, 9) and fbm(x / 8, y / 6, 51) + (1 - abs(y - 40) / 24) * 0.4 > 0.72:
                p[y][x] = 10 if fbm(x / 3, y / 3, 52) > 0.5 else 11
    for k in range(18):
        x0, y0 = 80 + (k * 37) % 56, 22 + (k * 23) % 36
        if p[y0][x0] in (10, 11):
            for d in range(3):
                put(p, x0, y0 - d, 4 if d < 2 else 5)
            put(p, x0 + 1, y0, 4)
    vx, vy = MAP_NODES["fragua"]   # the volcano in the middle, with its lava
    for y in range(H):
        for x in range(W):
            r = math.hypot(x - vx, (y - vy) * 1.2)
            if r < 20 + 3 * (fbm(x / 5, y / 5, 61) - 0.5):
                p[y][x] = 12 if r > 7 else 13 if r > 4.5 else 14
                if 7 <= r < 20 and fbm(x / 2.5, y / 2.5, 62) > 0.7:
                    p[y][x] = 15
    for k in range(60):
        t = k / 60
        x, y = int(vx + 6 + 26 * t + 3 * math.sin(t * 9)), int(vy + 4 + 22 * t)
        if p[y][x] not in (1, 2, 3, 4):
            put(p, x, y, 13)
            put(p, x, y + 1, 14 if k % 4 else 13)
    gx, gy = MAP_NODES["galeon"]   # the galleon in the shallows of a lagoon on the east coast
    for y in range(H):
        for x in range(W):
            r = math.hypot(x - gx - 6, (y - gy) * 1.2)
            if r < 17 + 3 * fbm(x / 6, y / 6, 81) and p[y][x] in (5, 6, 7, 8, 9):
                p[y][x] = 5 if r > 15 + 3 * fbm(x / 6, y / 6, 81) else 4 if r > 13 else 3
    hull = [(gx - 10, gy + 6), (gx - 4, gy + 1), (gx + 8, gy - 3), (gx + 12, gy - 1), (gx + 6, gy + 5), (gx - 6, gy + 9)]
    poly(p, hull, 12)
    for x in range(gx - 9, gx + 11, 3):
        for y in range(gy - 3, gy + 9):
            if p[y][x] == 12:
                p[y][x] = 6
    line(p, gx - 6, gy + 4, gx + 8, gy - 1, 15)
    bx, by = MAP_NODES["jefe"]      # the golden ruin of the Golem
    for y in range(by - 7, by + 7):
        for x in range(bx - 9, bx + 10):
            edge = abs(x - bx) > 7 or abs(y - by) > 5
            if (abs(x - bx) + abs(y - by)) % 4 == 0 and not edge:
                p[y][x] = 14
            else:
                p[y][x] = 6 if not edge else 15 if (x + y) % 2 else 5
    order = ["selva", "cristal", "galeon", "fragua", "jefe"]
    for a, b in zip(order, order[1:]):   # the dotted trail between the nodes
        (x0, y0), (x1, y1) = MAP_NODES[a], MAP_NODES[b]
        n = int(math.hypot(x1 - x0, y1 - y0))
        for k in range(10, n - 9, 4):
            t = k / n
            x = int(x0 + (x1 - x0) * t + 6 * math.sin(t * math.pi))
            y = int(y0 + (y1 - y0) * t - 4 * math.sin(t * math.pi))
            put(p, x, y, 5)
            put(p, x + 1, y, 5)
            put(p, x, y + 1, 15)
            put(p, x + 1, y + 1, 15)
    for x0, y0, x1, y1 in ((8, 136, 26, 154), (230, 10, 248, 28)):    # a compass rose and a sea mark
        mx, my = (x0 + x1) // 2, (y0 + y1) // 2
        poly(p, [(mx + 0.5, y0), (mx + 3, my), (mx + 0.5, y1), (mx - 2, my)], 5)
        poly(p, [(x0, my + 0.5), (mx, my - 2), (x1, my + 0.5), (mx, my + 3)], 5)
        put(p, mx, my, 13)
    return p


def build_titulo():
    ART.scenery("titulo_logo", paint_logo(), "titulo", "logo")
    ART.scenery("titulo_fondo", paint_titulo_fondo(), "titulo", "fondo")
    ART.scenery("mapa_fondo", paint_mapa_fondo(), "titulo", "mapa_isla")


# ------------------------------------------------------------------ previews (my own, beside the kit's)

def bank_cols(name: str, set_: str = "obj"):
    return ART.palettes[set_][name]


def frame_cols(sheet, name: str):
    return bank_cols(sheet.banks.get(name, sheet.bank))


def preview_both(sid: str, cols: int = 12, scale: int = 3) -> Path:
    """The sheet on a dark and on a bright ground, one above the other."""
    from PIL import Image
    from gbakit import contact_sheet
    s = ART.sheets[sid]
    items = [(p, frame_cols(s, n)) for n, p in s.frames]
    a = contact_sheet(items, cols, scale, back=(28, 24, 44))
    b = contact_sheet(items, cols, scale, back=(150, 220, 250))
    img = Image.new("RGB", (a.width, a.height * 2 + 6), (0, 0, 0))
    img.paste(a, (0, 0))
    img.paste(b, (0, a.height + 6))
    ART_DIR.mkdir(exist_ok=True)
    out = ART_DIR / f"items_check_{sid.lower()}.png"
    img.save(out)
    return out


def build_all() -> None:
    """Registers everything of this module in ART (the shared build calls this, or imports and calls each)."""
    build_items16()
    build_items32()
    build_ui8()
    build_ui16()
    build_fx8()
    build_fx16()
    build_mapa16()
    build_titulo()


def _img(p, cols, scale=1, back=None):
    from gbakit import to_image
    from PIL import Image
    if back is None:
        im = Image.new("RGBA", (len(p[0]) * scale, len(p) * scale), (0, 0, 0, 0))
        px = im.load()
        for y, row in enumerate(p):
            for x, v in enumerate(row):
                if v:
                    for dy in range(scale):
                        for dx in range(scale):
                            px[x * scale + dx, y * scale + dy] = cols[v - 1] + (255,)
        return im
    return to_image(p, cols, scale, back)


def preview_hud() -> Path:
    """A GBA screen (240x160) with the HUD over the title picture's sea, at 1x and 3x."""
    from PIL import Image
    ui8, ui16 = ART.sheets["UI8"], ART.sheets["UI16"]
    fondo, _, _ = ART.sceneries["titulo_fondo"]
    screen = _img(crop(fondo, 8, 0, 240, 160), bank_cols("fondo", "titulo")).convert("RGBA")

    def put_frame(sheet, name, x, y):
        screen.alpha_composite(_img(sheet.get(name), frame_cols(sheet, name)), (x, y))
    for k, name in enumerate(("heart_full_0", "heart_full_0", "heart_full_1", "heart_empty")):
        put_frame(ui16, name, 4 + k * 15, 4)
    put_frame(ui8, "coin_mini", 168, 8)
    put_frame(ui8, "x", 177, 8)
    for k, d in enumerate("01250"):
        put_frame(ui8, f"d_{d}", 186 + k * 8, 8)
    for q, full in enumerate((True, False, True, False)):
        name = f"jewel_mini_{'full' if full else 'empty'}_{q + 1}"
        put_frame(ui8, name, 112 + (q % 2) * 8, 4 + (q // 2) * 8)
    put_frame(ui8, "key_mini", 132, 8)
    put_frame(ui16, "frog_alarm_1", 92, 140)
    put_frame(ui8, "clock_mini", 110, 144)
    for k, ch in enumerate(("d_2", "colon", "d_4", "d_7")):
        put_frame(ui8, ch, 119 + k * 8, 144)
    i16 = ART.sheets["ITEMS16"]
    for k, n in enumerate(("coin_l_0", "coin_m_1", "coin_s_2", "gem_a_0", "gem_b_3", "diamond_1", "heart_item_0", "jewel_2_2", "key_0", "chest_closed", "bag_0")):
        put_frame(i16, n, 20 + k * 18, 120)
    i32 = ART.sheets["ITEMS32"]
    for k, n in enumerate(("keyzer_0", "frog_on_1", "vortex_open_2", "treasure_0")):
        put_frame(i32, n, 30 + k * 50, 62)
    big = screen.resize((720, 480), Image.NEAREST)
    out = Image.new("RGBA", (240 + 8 + 720, 480), (0, 0, 0, 255))
    out.paste(screen, (0, 0))
    out.paste(big, (248, 0))
    path = ART_DIR / "items_check_hud.png"
    out.convert("RGB").save(path)
    return path


def preview_strip(sid: str, prefixes, scale: int = 3) -> Path:
    """Animation strips, one row per animation, at 3x."""
    from PIL import Image
    s = ART.sheets[sid]
    rows = [[(n, p) for n, p in s.frames if n.rsplit("_", 1)[0] == pre] for pre in prefixes]
    w = max(len(r) for r in rows) * (s.w * scale + 4) + 4
    img = Image.new("RGB", (w, len(rows) * (s.h * scale + 4) + 4), (20, 18, 30))
    for j, r in enumerate(rows):
        for i, (n, p) in enumerate(r):
            back = (40, 40, 70) if j % 2 else (110, 170, 200)
            img.paste(_img(p, frame_cols(s, n), scale, back), (4 + i * (s.w * scale + 4), 4 + j * (s.h * scale + 4)))
    path = ART_DIR / f"items_strip_{sid.lower()}.png"
    img.save(path)
    return path


def preview_pictures() -> list[Path]:
    from PIL import Image
    out = []
    for name in ("titulo_logo", "titulo_fondo", "mapa_fondo"):
        p, set_, bank = ART.sceneries[name]
        cols = bank_cols(bank, set_)
        one = _img(p, cols, 1, (60, 40, 90))
        two = _img(p, cols, 2, (60, 40, 90))
        img = Image.new("RGB", (one.width + two.width + 8, two.height), (0, 0, 0))
        img.paste(one, (0, 0))
        img.paste(two, (one.width + 8, 0))
        path = ART_DIR / f"items_pic_{name}.png"
        img.save(path)
        out.append(path)
    return out


if __name__ == "__main__":
    build_all()
    for sid in ("ITEMS16", "ITEMS32", "UI8", "UI16", "FX8", "FX16", "MAPA16"):
        print(preview_both(sid, 12 if sid != "ITEMS32" else 8))
    print(preview_hud())
    print(preview_strip("ITEMS32", ["keyzer", "keyzer_flee", "frog_off", "frog_hit", "frog_on", "vortex_open", "vortex_close", "vortex_closed", "treasure"]))
    for path in preview_pictures():
        print(path)
