"""Paella de Combate: `explosions` (192x192, anchor centre) and `shots` (40x40, anchor centre)."""
from __future__ import annotations

import math
import random

from enemies_kit import (BRASS, CHROME, CREAM, FIRE, ORANGE, PINK, SMOKE, STEEL, VISOR, WOOD, YELLOW, Canvas, Ramp, Sheet)
from fx_parts import EMBER, SOOT, boom, cloud_lobes, debris, paint_cloud
from gull_parts import DARK, WHITE, T, feather, sardine, screw

# ================================================================== explosions
EW = 192
C = 96


def gear(c, x, y, r, a=0.0):
    pts = []
    for i in range(16):
        ang = a + i * math.pi / 8
        rr = r if (i // 1) % 2 == 0 else r * 0.72
        pts.append((x + math.cos(ang) * rr, y + math.sin(ang) * rr))
    c.poly(pts, STEEL, bulge=0.6)
    c.ell(x, y, r * 0.35, r * 0.35, STEEL, tone=0, seam=False)


def mushroom(c, k, R=52):
    """The large blast: a fireball whose smoke column rises into a mushroom cap."""
    cx, cy = C, C + 22
    if k < 0.08:
        boom(c, cx, cy, R, k, seed=31)
        return
    g = min(1.0, (k - 0.08) / 0.3)
    s = 0.35 + 0.65 * (1 - (1 - g) ** 2.4)
    rise = max(0.0, k - 0.2) / 0.8
    heat_shift = max(0.0, k - 0.22) * 0.85
    smoke_level = -1.0 if k < 0.4 else (k - 0.4) * 1.7
    # ground ring of dust spreading
    if k > 0.15:
        for side in (-1, 1):
            for j in range(3):
                x = cx + side * (R * 0.7 + rise * 30 + j * 10)
                r = 10 - j * 2 - rise * 4
                if r > 2:
                    c.ell(x, cy + R * 0.45 - j * 2, r * 1.3, r, SMOKE, rim=False)
    lobes = []
    for lx, ly, lr, life in cloud_lobes(31, 10, R * 0.85):
        lobes.append((lx * s, ly * s * 0.8 + R * 0.1, lr * s * (1 - 0.4 * max(0.0, rise - 0.5)), life))
    # the stem
    top = -R * (0.3 + 1.0 * rise)
    nst = 5
    for j in range(nst):
        t = j / (nst - 1)
        lobes.append((math.sin(j * 1.7) * 3, top * t, R * (0.28 - 0.08 * t) * s, 1.0))
    # the cap
    if rise > 0.05:
        cw = R * (0.55 + 0.4 * rise)
        for j in range(7):
            a = math.pi + j * math.pi / 6
            lobes.append((math.cos(a) * cw, top + math.sin(a) * cw * 0.35 - 4, R * (0.22 + 0.12 * rise), 1.0))
        lobes.append((0, top - 6, R * (0.34 + 0.1 * rise), 1.0))
    if k > 0.8:  # breaking up at the very end
        q = (k - 0.8) / 0.2
        lobes = [(lx, ly - q * 6, lr * max(0.0, 1 - q * (0.5 + 0.5 * ((i * 7) % 5) / 4)), l)
                 for i, (lx, ly, lr, l) in enumerate(lobes)]
    paint_cloud(c, cx, cy, lobes, heat_shift, smoke_level, SMOKE if k < 0.75 else SOOT, top_bias=R * 0.15)
    if 0.12 < k < 0.95:
        debris(c, cx, cy - 10, R, min(1.0, (k - 0.12) * 1.3), seed=13, feathers=6, screws=4)


def grenade(c, k):
    """Pressure-cooker blast: the lid pops in a big puff of steam, then the shock and a fireball."""
    cx, cy = C, C + 10
    if k < 0.32:  # steam first
        q = k / 0.32
        lobes = [(lx * (0.5 + q), ly * (0.5 + q) - q * 14, lr * (0.5 + q), life) for lx, ly, lr, life in cloud_lobes(41, 9, 44)]
        paint_cloud(c, cx, cy, lobes, 0.0, 5.0, CREAM)
        # the lid flying up, spinning, with its little red valve
        lt = T(cx - 6 + q * 18, cy - 40 - q * 46, q * 7, 1.3, 1.3)
        lt.ell(c, 0, 0, 12, 4, CHROME)
        lt.ell(c, 0, -3, 2.5, 2.5, VISOR)
        lt.tube(c, [(10, 0, 1.6), (18, -1, 1.6)], STEEL)
        return
    kk = (k - 0.32) / 0.68
    if kk < 0.12:
        boom(c, cx, cy, 52, 0.04, seed=43)
    else:
        boom(c, cx, cy, 52, 0.08 + kk * 0.88, seed=43, n=10)
    # the shock ring
    if 0.05 < kk < 0.55:
        r = 30 + kk * 110
        ring = []
        for i in range(24):
            a = i * math.pi / 12
            ring.append((cx + math.cos(a) * r, cy + math.sin(a) * r * 0.55))
        for i in range(24):
            a, b = ring[i], ring[(i + 1) % 24]
            if 2 < a[0] < EW - 3 and 2 < a[1] < EW - 3 and 2 < b[0] < EW - 3 and 2 < b[1] < EW - 3:
                c.line(a[0], a[1], b[0], b[1], CREAM[2], width=2)
    if kk > 0.2:  # chickpeas from the stew flying out
        rnd = random.Random(5)
        for j in range(8):
            a = rnd.uniform(-math.pi, 0)
            d = (kk - 0.2) * 90 * rnd.uniform(0.7, 1.1)
            x, y = cx + math.cos(a) * d, cy + math.sin(a) * d * 0.7 + (kk - 0.2) ** 2 * 120
            if 6 < x < EW - 6 and 6 < y < EW - 6:
                c.ell(x, y, 2.4, 2.4, YELLOW, seam=False)


def smoke(c, k):
    cx, cy = C, C + 20 - k * 40
    s = 0.5 + k * 0.8
    lobes = []
    for lx, ly, lr, life in cloud_lobes(51, 7, 34):
        fade = max(0.0, 1 - max(0.0, k - 0.45) / 0.55 / life) if k > 0.45 else 1.0
        lobes.append((lx * s, ly * s - k * 6 * (lx > 0), lr * s * fade, life))
    paint_cloud(c, cx, cy, lobes, 0.0, 5.0, SMOKE)


def feathers_burst(c, k):
    rnd = random.Random(61)
    for i in range(14):
        a = rnd.uniform(-math.pi, math.pi)
        v = rnd.uniform(40, 80)
        x = C + math.cos(a) * v * min(1.0, k * 2.2)
        y = C - 10 + math.sin(a) * v * 0.7 * min(1.0, k * 2.2) + 60 * max(0.0, k - 0.3) ** 1.5
        # loose feathers rock side to side as they fall
        sway = math.sin(k * 9 + i) * 0.8 * min(1.0, k * 2)
        if not (8 < x < EW - 8 and 8 < y < EW - 8):
            continue
        if i % 4 == 3:
            gear(c, x, y, 7 if i % 8 == 3 else 5, k * 6 + i)
        elif i % 5 == 4:
            screw(c, x, y, k * 8 + i)
        else:
            feather(c, x, y, a * 0.3 + sway, 1.8 if i % 3 else 1.4, CHROME if i % 2 else STEEL)
    if k < 0.25:  # the initial puff
        paint_cloud(c, C, C - 10, [(lx * (1 + k * 3), ly * (1 + k * 3), lr * (1 - k * 3), l) for lx, ly, lr, l in cloud_lobes(62, 7, 30)],
                    0.0, 5.0, CREAM)


def explosions_sheet():
    s = Sheet("explosions", EW, EW, [96, 96], notes="centred; boom_l rises above the centre (mushroom), boom_grenade starts with steam")
    for i in range(8):
        c = Canvas(EW, EW)
        boom(c, C, C, 22, i / 7 * 0.94, seed=2, n=6)
        s.add(f"boom_s_{i}", c.done())
    for i in range(10):
        c = Canvas(EW, EW)
        boom(c, C, C + 6, 44, i / 9 * 0.95, seed=7, n=9)
        if 2 <= i <= 8:
            debris(c, C, C, 44, (i - 2) / 6, seed=8, feathers=3, screws=3)
        s.add(f"boom_m_{i}", c.done())
    for i in range(12):
        c = Canvas(EW, EW)
        mushroom(c, i / 11, R=60)
        s.add(f"boom_l_{i}", c.done())
    for i in range(10):
        c = Canvas(EW, EW)
        grenade(c, i / 9)
        s.add(f"boom_grenade_{i}", c.done())
    for i in range(8):
        c = Canvas(EW, EW)
        smoke(c, i / 7)
        s.add(f"smoke_{i}", c.done())
    for i in range(8):
        c = Canvas(EW, EW)
        feathers_burst(c, i / 7)
        s.add(f"feathers_{i}", c.done())
    s.save()


# ================================================================== shots
SW = 40
S = 20


def knife(c, a):
    t = T(S, S, a)
    t.poly(c, [(-2, -2.5), (12, -2.5), (15, 0), (12, 1.5), (-2, 2.5)], CHROME, bulge=0.5, center=(6, 0))
    t.line(c, 0, -1.5, 12, -1.5, WHITE)
    t.tube(c, [(-11, 0, 2.2), (-3, 0, 2.6)], WOOD)
    t.ell(c, -3, 0, 1.2, 3.4, STEEL)
    for x in (-9, -6):
        t.px(c, x, 0, BRASS[2])


FOAM = Ramp("#9cb4c8", "#dce8f0", "#ffffff", "#ffffff", ol="#2a3a50")


def foam(c, k):
    r = 4 + k * 1.8
    rnd = random.Random(70 + k)
    lobes = [(0, 0, r, 1)] + [(math.cos(a) * r * 0.8, math.sin(a) * r * 0.6, r * rnd.uniform(0.4, 0.6), 1)
                              for a in [j * 1.2 + k * 0.4 for j in range(5)]]
    paint_cloud(c, S + 4 - k, S, lobes, 0.0, 5.0, FOAM)
    for j in range(3):  # bubbles trailing
        x, y = S + 2 - r - 3 - j * 3, S + math.sin(k * 2 + j * 2) * 4
        c.ell(x, y, 1.6, 1.6, FOAM, tone=1)
        c.px(x - 0.5, y - 0.5, WHITE)


def croqueta(c, a):
    t = T(S, S, a)
    t.tube(c, [(-7, 0, 5), (7, 0, 5)], ORANGE, bias=0.1)
    for x, y in ((-5, -2), (-1, 1), (3, -3), (6, 2), (-3, 3), (1, -1)):
        t.px(c, x, y, ORANGE[0])
        t.px(c, x + 1, y - 1, YELLOW[3])


def rice(c, k):
    rnd = random.Random(80 + k)
    for j in range(9):
        x = S - 8 + j * 2.2 + rnd.uniform(-1, 1)
        y = S + math.sin(j * 0.9 + k * 1.6) * 5 + rnd.uniform(-1, 1)
        t = T(x, y, rnd.uniform(0, 3))
        if j % 3 == 2:
            t.ell(c, 0, 0, 2.2, 1.8, YELLOW)  # oil drop
        else:
            t.ell(c, 0, 0, 2.2, 1.2, CREAM)
    c.ell(S + 9, S + math.sin(k * 1.6 + 8) * 3, 3, 2.4, YELLOW)


def cream(c, k):
    """A swirl of whipped cream: a star-nozzle dollop with a spiral tip, turning."""
    t = T(S, S + 2, k * math.pi / 2)
    for j, (x, y, r) in enumerate(((0, 4, 8), (1, -1, 6), (2, -5, 4), (3, -8, 2.2))):
        t.ell(c, x, y, r, r * 0.7, FOAM)
        t.line(c, x - r * 0.6, y + 1, x + r * 0.5, y - r * 0.3 + 1, FOAM[0])
    t.ell(c, 4, -9, 2.2, 2, VISOR)  # a cherry on top
    t.px(c, 3, -10, VISOR[3])
    t.line(c, -5, 5, 4, 2, PINK[2])


def cork(c, k):
    for j in range(5):  # the fizzy trail behind (shots fly right)
        x = S - 3 - j * 3
        y = S + math.sin(k * 1.7 + j * 1.3) * 3
        r = 2.2 - j * 0.3
        c.ell(x, y, r, r, CREAM, tone=2 if j % 2 else 1)
    t = T(S + 7, S, math.sin(k * 1.6) * 0.15)
    t.tube(c, [(-5, 0, 3.2), (2, 0, 3.4)], WOOD, bias=0.2)
    t.ell(c, 3, 0, 3, 5.2, WOOD, bias=0.25)
    t.line(c, -3, -3, 3, -4, STEEL[2])  # wire cage
    t.line(c, -3, 3, 3, 4, STEEL[2])


def pot(c, a, steam_k=0):
    t = T(S, S, a)
    t.ell(c, 0, 2, 9, 7, CHROME)
    t.ell(c, 0, -4, 9.5, 3, CHROME, tone=2)
    t.tube(c, [(8, -3, 1.8), (16, -6, 1.8)], STEEL)
    t.tube(c, [(-8, -2, 1.6), (-12, -2, 1.6)], STEEL)
    t.ell(c, 0, -7, 2.4, 2.4, VISOR)
    t.line(c, -6, 4, 6, 4, CHROME[0])
    if steam_k:
        t.ell(c, 1, -12, 2.6 + steam_k, 2.2 + steam_k, CREAM, rim=False)


def pea(c, a):
    t = T(S, S, a)
    t.ell(c, 0, 0, 4, 2.4, CREAM, tone=1)
    t.line(c, -3, 0, 3, 0, DARK)
    t.px(c, -1, -1, DARK)
    t.px(c, 2, 1, DARK)


def fish_bomb_fall(c, wob):
    sardine(c, T(S, S, -math.pi / 2 + wob, 0.85, 1.0), fins=True)
    t = T(S, S, -math.pi / 2 + wob)
    t.line(c, -2, -3, -2, 3, VISOR[1])


def rocket(c, k):
    sardine(c, T(S - 5, S, 0.0, 0.75, 0.8), flame=[1, 2, 3, 2][k], wiggle=[0.15, -0.1, 0.1, -0.15][k])


def hit_star(c, k):
    r = [5, 10, 12, 9][k]
    pts = []
    for i in range(16):
        a = i * math.pi / 8 + k * 0.2
        rr = r if i % 2 == 0 else r * 0.4
        pts.append((S + math.cos(a) * rr, S + math.sin(a) * rr))
    if k < 3:
        c.poly(pts, FIRE, tone=2 if k else 3, seam=False)
        c.ell(S, S, r * 0.35, r * 0.35, FIRE, tone=3, seam=False)
    else:
        for i in range(0, 16, 2):
            a = i * math.pi / 8
            c.ell(S + math.cos(a) * r, S + math.sin(a) * r, 1.6, 1.6, EMBER, tone=2, seam=False)


def shots_sheet():
    s = Sheet("shots", SW, SW, [20, 20], notes="player shots fly right (knife..cork, pot); enemy shots: pea and rocket fly left, bomb falls")

    def add(name, fn):
        c = Canvas(SW, SW)
        fn(c)
        s.add(name, c.done())
    for i in range(4):
        add(f"knife_{i}", lambda c, i=i: knife(c, i * math.pi / 2))
    for i in range(4):
        add(f"foam_{i}", lambda c, i=i: foam(c, i))
    for i in range(4):
        add(f"croqueta_{i}", lambda c, i=i: croqueta(c, i * math.pi / 4))
    for i in range(4):
        add(f"rice_{i}", lambda c, i=i: rice(c, i))
    for i in range(4):
        add(f"cream_{i}", lambda c, i=i: cream(c, i))
    for i in range(4):
        add(f"cork_{i}", lambda c, i=i: cork(c, i))
    for i in range(8):
        add(f"pot_{i}", lambda c, i=i: pot(c, i * math.pi / 4, steam_k=i % 2 + (i == 4)))
    for i in range(4):
        add(f"pea_{i}", lambda c, i=i: pea(c, i * math.pi / 4))
    for i in range(4):
        add(f"bomb_{i}", lambda c, i=i: fish_bomb_fall(c, [0.0, 0.12, 0.0, -0.12][i]))
    for i in range(4):
        add(f"rocket_{i}", lambda c, i=i: rocket(c, i))
    for i in range(4):
        add(f"hit_{i}", lambda c, i=i: hit_star(c, i))
    s.save()


def build():
    explosions_sheet()
    shots_sheet()


if __name__ == "__main__":
    build()
