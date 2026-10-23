"""Paella de Combate: `items` (48x48, anchor [24, 46]) pickups and food, and `props` (128x128, anchor [64, 126])."""
from __future__ import annotations

import math
import random

from enemies_kit import (BRASS, CHROME, CREAM, FLESH, GREEN, NAVY, OLIVE, ORANGE, SEA, SMOKE, STEEL, VISOR, WOOD, YELLOW,
                         Canvas, Ramp, Sheet)
from fx_parts import puff
from gull_parts import DARK, WHITE, T, sardine
from person_parts import DARKCLOTH, weapon_crate

IW = 48
BOB = [0, -1, -2, -1]


def sparkle(c, x, y, r=3):
    c.line(x - r, y, x + r, y, WHITE)
    c.line(x, y - r, x, y + r, WHITE)
    c.px(x - 1, y - 1, YELLOW[3])
    c.px(x + 1, y + 1, YELLOW[3])


def shadow(c, w=14):
    c.oval(24, 44.5, w, 1.8, (58, 44, 60), ol=(30, 20, 32))


# ------------------------------------------------------------------ pickups
def crate_item(c, mark, k):
    shadow(c)
    weapon_crate(c, T(24, 32 + BOB[k], 0.0, 1.25, 1.25), mark, w=22, h=17)
    if k == 2:
        sparkle(c, 36, 20 + BOB[k], 3)


def ammo_item(c, k):
    shadow(c)
    t = T(24, 34 + BOB[k])
    t.poly(c, [(-14, -9), (14, -9), (14, 9), (-14, 9)], OLIVE, bulge=0.35)
    for x in (-8, 0, 8):  # three little pressure-cooker lids peeking out
        t.ell(c, x, -10, 4.4, 2.4, CHROME)
        t.ell(c, x, -12, 1.4, 1.4, VISOR, seam=False)
    t.line(c, -12, 0, 12, 0, OLIVE[0])
    t.line(c, -10, 4, 10, 4, BRASS[2])
    if k == 2:
        sparkle(c, 38, 20 + BOB[k], 3)


def heart_item(c, k):
    """A tiny red-hot pepper heart: two chilli lobes curled into a heart, a green stem, a hot glow."""
    shadow(c, 10)
    y = 30 + BOB[k]
    if k in (1, 2):
        c.ell(24, y, 15, 13, ORANGE, tone=3, seam=False, rim=False)
    t = T(24, y)
    t.ell(c, -5, -3, 6.5, 6, VISOR)
    t.ell(c, 5, -3, 6.5, 6, VISOR)
    t.poly(c, [(-11, -1), (11, -1), (0, 12)], VISOR, bulge=0.5, center=(0, 0), seam=False)
    t.ell(c, -6, -5, 2.2, 1.6, VISOR, tone=3, seam=False)
    t.tube(c, [(0, -8, 1.6), (2, -13, 1.4), (5, -14, 1.2)], GREEN)
    if k == 2:
        sparkle(c, 35, 18, 3)


def shield_item(c, k):
    """A paella-pan badge: a round pan with two handles, a gold star on it."""
    shadow(c)
    t = T(24, 30 + BOB[k])
    t.tube(c, [(-19, 0, 2.6), (19, 0, 2.6)], STEEL)
    t.ell(c, 0, 0, 15, 15, STEEL)
    t.ell(c, 0, 0, 12, 12, YELLOW, bias=-0.1)
    pts = []
    for i in range(10):
        a = -math.pi / 2 + i * math.pi / 5
        r = 8 if i % 2 == 0 else 3.6
        pts.append((24 + math.cos(a) * r, 30 + BOB[k] + math.sin(a) * r))
    c.poly(pts, VISOR, bulge=0.3)
    sweep = [(-9, -6), (-4, -9), (2, -10), (7, -8)][k]
    c.line(24 + sweep[0], 30 + BOB[k] + sweep[1], 24 + sweep[0] + 3, 30 + BOB[k] + sweep[1] + 2, WHITE)


# ------------------------------------------------------------------ food (2 frames: the second shines)
def f_jamon(c):
    t = T(22, 34, -0.35)
    t.poly(c, [(-16, -4), (-4, -9), (10, -7), (15, 0), (8, 7), (-6, 7), (-16, 3)], VISOR, bulge=0.6, center=(0, 0))
    t.poly(c, [(-16, -4), (-8, -7), (-10, 4), (-16, 3)], CREAM, bulge=0.4)
    t.tube(c, [(14, 0, 3), (22, -1, 2.2)], CREAM)
    t.ell(c, 23, -1, 2.4, 3, DARKCLOTH)
    t.line(c, -2, -4, 8, 2, VISOR[3])
    return (16, 22)


def f_cheese(c):
    t = T(24, 34)
    t.poly(c, [(-15, 6), (15, 6), (12, -6), (-8, -10)], YELLOW, bulge=0.4)
    t.poly(c, [(-15, 6), (15, 6), (15, 9), (-15, 9)], YELLOW, tone=0)
    for x in range(-13, 14, 4):  # the woven rind of a manchego
        t.line(c, x, 6, x + 2, 9, YELLOW[1])
    for x, y in ((-4, -2), (4, 1), (8, -3)):
        t.ell(c, x, y, 1.6, 1.2, YELLOW, tone=0, seam=False)
    return (14, 24)


def f_paella(c):
    t = T(24, 33)
    t.tube(c, [(-20, 0, 2.0), (20, 0, 2.0)], STEEL)
    t.ell(c, 0, 0, 16, 8.5, STEEL)
    t.ell(c, 0, -1, 13.5, 6.5, YELLOW, bias=0.1)
    for x, y in ((-8, -2), (6, 1), (-1, 2)):  # prawns
        t.tube(c, [(x - 2, y, 1.6), (x + 2, y - 1, 1.4)], ORANGE)
    for x, y in ((-3, -4), (9, -3), (-10, 2)):  # red pepper strips
        t.line(c, x, y, x + 3, y, VISOR[1])
    for x, y in ((2, -3), (-5, 3), (10, 2), (-12, -1)):
        t.px(c, x, y, GREEN[2])
    t.poly(c, [(10, -6), (15, -4), (12, -1)], YELLOW, tone=3)  # lemon
    return (16, 22)


def f_tortilla(c):
    t = T(24, 34)
    t.ell(c, 0, 2, 16, 6, YELLOW, bias=-0.2)
    t.ell(c, 0, -1, 15, 6, YELLOW, bias=0.15)
    t.poly(c, [(0, -1), (12, -5), (15, -1)], CREAM, normal=(0, 0.2))  # a slice cut out
    t.line(c, 0, -1, 15, -1, YELLOW[0])
    for x, y in ((-6, -2), (4, 0), (-2, -4)):
        t.px(c, x, y, ORANGE[1])
    return (14, 26)


def f_melon(c):
    t = T(22, 33, 0.1)
    t.ell(c, 0, 0, 14, 9.5, GREEN, bias=0.05)
    for y in (-5, 0, 5):
        t.ell(c, 0, y * 0.9, 12 - abs(y), 0.9, GREEN, tone=0, seam=False)
    s = T(36, 37, 0.0)
    s.poly(c, [(-8, 3), (8, 3), (0, -7)], ORANGE, tone=3, bulge=0.2)
    s.tube(c, [(-8, 3, 1.4), (8, 3, 1.4)], GREEN, tone=1)
    for x in (-3, 0, 3):
        s.px(c, x, 0, DARKCLOTH[1])
    return (12, 24)


def f_sardine(c):
    t = T(24, 32)
    t.line(c, -18, 0, 18, 0, WOOD[2])
    sardine(c, T(24, 32, 0.0, 1.15, 1.1), fins=True, face="none")
    for x in (-4, 0, 4):  # grill marks
        t.line(c, x - 1, -3, x + 1, 3, DARKCLOTH[1])
    return (12, 24)


def f_orange(c):
    t = T(24, 33)
    t.ell(c, 0, 0, 11, 10.5, ORANGE, bias=0.1)
    for x, y in ((-4, -3), (3, 2), (-2, 4), (5, -4)):
        t.px(c, x, y, ORANGE[0])
    t.tube(c, [(0, -10, 1.2), (1, -12, 1.2)], WOOD)
    t.poly(c, [(1, -12), (8, -16), (12, -13), (5, -10)], GREEN, bulge=0.4)
    return (16, 22)


def f_bread(c):
    t = T(24, 34, -0.2)
    t.tube(c, [(-17, 0, 5), (17, 0, 5)], WOOD, bias=0.2)
    for x in (-10, -3, 4, 11):
        t.line(c, x - 2, -3, x + 2, -1, WOOD[0])
        t.px(c, x, -3, WOOD[3])
    return (14, 24)


def f_olive_can(c):
    t = T(24, 32)
    t.poly(c, [(-10, -11), (10, -11), (10, 11), (-10, 11)], CHROME, bulge=0.5)
    t.poly(c, [(-10, -6), (10, -6), (10, 6), (-10, 6)], GREEN, bulge=0.5, seam=False)
    t.ell(c, 0, -11, 10, 2.6, CHROME, tone=2)
    for x, y in ((-4, -1), (2, 1), (5, -2)):
        t.ell(c, x, y, 2.4, 1.8, OLIVE)
        t.px(c, x - 1, y, VISOR[1])
    t.ell(c, 4, -12, 3, 1.2, CHROME, tone=0, seam=False)
    return (16, 20)


def f_wine_skin(c):
    t = T(24, 34, 0.2)
    t.poly(c, [(-14, -4), (-6, -10), (8, -9), (15, 0), (8, 9), (-8, 8), (-15, 2)], WOOD, bulge=0.7, bias=-0.25)
    t.tube(c, [(-14, -2, 1.6), (-20, -6, 1.6)], WOOD)
    t.ell(c, -21, -7, 2.4, 2.4, VISOR)
    t.line(c, -14, -6, 6, -14, VISOR[1])
    t.line(c, 6, -14, 15, -2, VISOR[1])
    t.px(c, -4, -5, WOOD[3])
    return (14, 24)


def f_churro(c):
    for i, (x, a) in enumerate(((20, -0.5), (28, 0.45))):
        t = T(x, 31, a)
        t.tube(c, [(0, -11, 3.2), (0, 11, 3.2)], ORANGE, bias=0.15)
        for y in range(-9, 10, 4):
            t.line(c, -2, y, 2, y + 1, ORANGE[0])
            t.px(c, 1, y + 2, CREAM[3])
    return (14, 18)


def f_ensaimada(c):
    t = T(24, 34)
    t.ell(c, 0, 0, 16, 7.5, YELLOW, bias=0.1)
    pts = []
    for i in range(40):
        a = i * 0.42
        r = 1 + i * 0.36
        pts.append((math.cos(a) * r, math.sin(a) * r * 0.45 - 1))
    for (x0, y0), (x1, y1) in zip(pts, pts[1:]):
        t.line(c, x0, y0, x1, y1, YELLOW[0])
    for x, y in ((-8, -3), (4, -4), (9, 0), (-3, 1), (1, -1), (-11, 1), (12, -2)):
        t.px(c, x, y, WHITE)
    return (14, 26)


FOODS = [("jamon", f_jamon), ("cheese", f_cheese), ("paella", f_paella), ("tortilla", f_tortilla), ("melon", f_melon),
         ("sardine", f_sardine), ("orange", f_orange), ("bread", f_bread), ("olive_can", f_olive_can), ("wine_skin", f_wine_skin),
         ("churro", f_churro), ("ensaimada", f_ensaimada)]


def items_sheet():
    s = Sheet("items", IW, IW, [24, 46], notes="crate_a pepper, crate_b chilli, crate_c bottle; food_* frame 1 is the shine")

    def add(name, fn):
        c = Canvas(IW, IW)
        fn(c)
        s.add(name, c.done())
    for key, mark in (("crate_a", "pepper"), ("crate_b", "chilli"), ("crate_c", "bottle")):
        for k in range(4):
            add(f"{key}_{k}", lambda c, k=k, mark=mark: crate_item(c, mark, k))
    for k in range(4):
        add(f"ammo_{k}", lambda c, k=k: ammo_item(c, k))
    for k in range(4):
        add(f"heart_{k}", lambda c, k=k: heart_item(c, k))
    for k in range(4):
        add(f"shield_{k}", lambda c, k=k: shield_item(c, k))
    for name, fn in FOODS:
        for k in range(2):
            def draw(c, fn=fn, k=k):
                shadow(c, 13)
                sp = fn(c)
                if k:
                    sparkle(c, 24 + sp[0] - 2, sp[1], 3)
            add(f"food_{name}_{k}", draw)
    s.save()


# ================================================================== props
PW = 128
PG = 125


def barrel(c, t: T, hoops=True):
    t.poly(c, [(-16, -46), (16, -46), (20, -24), (16, 0), (-16, 0), (-20, -24)], WOOD, bulge=0.75, center=(0, -24))
    for x in (-10, -3, 4, 11):
        t.line(c, x * 1.05, -45, x * 1.25, -24, WOOD[0])
        t.line(c, x * 1.25, -24, x * 1.0, -1, WOOD[0])
    if hoops:
        for y, w in ((-40, 17.5), (-8, 17.5)):
            t.tube(c, [(-w, y, 1.6), (w, y, 1.6)], STEEL)
    t.ell(c, 0, -46, 16, 4, WOOD, tone=2)
    t.ell(c, 0, -46, 13, 2.6, WOOD, tone=1, seam=False)
    # a stencilled anchor
    t.line(c, 2, -32, 2, -20, WOOD[0])
    t.line(c, -2, -22, 6, -22, WOOD[0])
    t.line(c, -1, -30, 5, -30, WOOD[0])


def stave(c, x, y, a, L=24):
    t = T(x, y, a)
    t.poly(c, [(-L / 2, -3), (L / 2, -3), (L / 2 - 1, 3), (-L / 2 + 1, 3)], WOOD, bulge=0.5)
    t.line(c, -L / 2 + 2, 0, L / 2 - 2, 0, WOOD[0])


def hoop(c, x, y, a, r=17):
    t = T(x, y, a)
    t.ell(c, 0, 0, r, 4, STEEL)
    t.ell(c, 0, 0, r - 2.5, 2.2, STEEL, tone=0, seam=False)


def barrel_frames():
    out = []
    for k in range(6):
        c = Canvas(PW, PW)
        if k == 0:
            barrel(c, T(64, PG))
        elif k == 1:  # cracked, a hoop slipped, splinters
            barrel(c, T(64, PG, 0.04))
            c.line(56, 92, 62, 104, DARK)
            c.line(62, 104, 58, 112, DARK)
            c.line(72, 86, 70, 98, DARK)
            stave(c, 44, 84, 0.9, 8)
        elif k == 2:  # bulging: staves spring apart
            for i, (dx, a) in enumerate(((-14, -0.25), (-5, -0.08), (5, 0.08), (14, 0.25))):
                t = T(64 + dx, PG - 2, a)
                t.poly(c, [(-5, -46), (5, -46), (6, 0), (-6, 0)], WOOD, bulge=0.5)
                t.line(c, 0, -44, 0, -2, WOOD[0])
            hoop(c, 64, PG - 48, 0.1, 21)
        else:  # flying apart, falling, a pile
            q = (k - 3) / 2
            if k == 3:
                puff(c, 64, PG - 26, 20, CREAM, seed=4, n=6)
            rnd = random.Random(3)
            for i in range(7):
                a = -math.pi / 2 + (i - 3) * 0.45
                d = 10 + 40 * min(1.0, q + 0.3)
                x = 64 + math.cos(a) * d
                y = PG - 30 + math.sin(a) * d * 0.8 + 70 * q * q
                if k == 5:
                    x = 40 + i * 8 + rnd.uniform(-2, 2)
                    y = PG - 6 - (i % 3) * 3
                y = min(y, PG - 6)
                stave(c, x, y, a + q * 4 if k < 5 else rnd.uniform(-0.3, 0.3))
            hoop(c, 64 + (q * 20 if k < 5 else 18), (PG - 60 + 50 * q) if k < 5 else PG - 7, (0.5 + q) if k < 5 else 0.0, 17)
            if k == 3:
                for i in range(6):  # splinters
                    c.line(64 + i * 6 - 18, PG - 50 - i % 2 * 6, 66 + i * 6 - 18, PG - 56 - i % 2 * 6, WOOD[2])
        out.append(c.done())
    return out


def fish_crate(c, t: T):
    # sardines heaped in the crate, heads and tails poking out
    for i in range(6):
        x = -22 + i * 9
        sardine(c, T(*t.p(x, -18 - (i % 2) * 3), -0.5 + (i % 3) * 0.4, 0.8, 0.8), fins=False, face="none")
    t.poly(c, [(-28, -18), (28, -18), (28, 0), (-28, 0)], WOOD, bulge=0.4)
    for y in (-12, -6):
        t.line(c, -27, y, 27, y, WOOD[0])
    for x in (-28, 26):
        t.poly(c, [(x, -20), (x + 2, -20), (x + 2, 0), (x, 0)], WOOD, tone=0)
    t.line(c, -10, -15, 10, -15, NAVY[2])  # stencil: PESCA
    t.line(c, -10, -3, 10, -3, NAVY[2])


def crate_frames():
    out = []
    for k in range(6):
        c = Canvas(PW, PW)
        if k == 0:
            fish_crate(c, T(64, PG))
        elif k == 1:
            fish_crate(c, T(64, PG, 0.03))
            c.line(52, 108, 60, 118, DARK)
            c.line(74, 110, 70, 122, DARK)
        else:
            q = (k - 2) / 3
            rnd = random.Random(7)
            if k in (2, 3):
                puff(c, 64, PG - 14 - (k - 2) * 6, 16 + (k - 2) * 4, CREAM if k == 2 else SMOKE, seed=6, n=6)
            for i in range(6):  # planks
                a = -math.pi / 2 + (i - 2.5) * 0.55
                d = 8 + 36 * min(1.0, q + 0.25)
                x = 64 + math.cos(a) * d
                y = min(PG - 7, PG - 16 + math.sin(a) * d * 0.7 + 60 * q * q)
                x = max(14, min(PW - 14, x))
                if k == 5:
                    x, y = 36 + i * 11 + rnd.uniform(-2, 2), PG - 6 - (i % 2) * 3
                stave(c, x, y, (a + q * 5) if k < 5 else rnd.uniform(-0.2, 0.2), 20)
            for i in range(5):  # sardines flip-flopping out
                a = -math.pi / 2 + (i - 2) * 0.6
                d = 14 + 40 * min(1.0, q + 0.2)
                x = 64 + math.cos(a) * d * 1.1
                y = min(PG - 8, PG - 30 + math.sin(a) * d + 70 * q * q)
                x = max(16, min(PW - 16, x))
                if k == 5:
                    x, y = 30 + i * 16, PG - 8
                sardine(c, T(x, y, (i * 1.3 + q * 6) if k < 5 else (0.15 if i % 2 else -0.15), 0.8, 0.8), fins=False)
        out.append(c.done())
    return out


def buoy(c, a):
    """A round fishing buoy rolling left: white ball, two crossed red bands turning with angle a (4-fold, so it loops)."""
    cx, cy, r = 64, PG - 18, 18
    c.ell(cx, cy, r, r, CHROME)
    w = 4.5
    L = math.sqrt(r * r - w * w) - 0.6
    for j in range(2):
        t = T(cx, cy, a + j * math.pi / 2)
        t.poly(c, [(-L, -w), (L, -w), (L, w), (-L, w)], VISOR, normal=(0, 0), tone=1, seam=False)
    # re-light the ball: a highlight and a shadow crescent over the bands
    c.ell(cx - 6, cy - 7, 4, 3, CHROME, tone=3, seam=False)
    c.ell(cx, cy, 3.6, 3.6, STEEL)
    tx, ty = cx + math.cos(a - 1.2) * 13, cy + math.sin(a - 1.2) * 13
    c.ell(tx, ty, 2.2, 2.2, STEEL)


def props_sheet():
    s = Sheet("props", PW, PW, [64, 126], notes="barrel_0 / crate_0 intact, 1 cracked, then breaking; buoy_* rolls (loop)")
    for i, img in enumerate(barrel_frames()):
        s.add(f"barrel_{i}", img)
    for i, img in enumerate(crate_frames()):
        s.add(f"crate_{i}", img)
    for i in range(4):
        c = Canvas(PW, PW)
        buoy(c, -i * math.pi / 8)
        s.add(f"buoy_{i}", c.done())
    s.save()


def build():
    items_sheet()
    props_sheet()


if __name__ == "__main__":
    build()
