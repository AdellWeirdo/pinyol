"""Paella de Combate: gull_drone (128x112, anchor [64, 56] = body centre, faces left): a gull with a propeller beak and fish bombs."""
from __future__ import annotations

import math

from enemies_kit import BRASS, CHROME, CREAM, FIRE, ORANGE, SMOKE, STEEL, VISOR, WOOD, Canvas, Sheet
from enemies_kit import SEA as SEA_GLASS
from gull_parts import DARK, EYES, EYE_Y, WHITE, T, feather, key, sardine, screw, star, steam, sweat

W, H = 128, 112
CX, CY = 64, 56

BASE = dict(bx=0.0, by=0.0, ang=0.0, flap=0.0, prop=0.0, bombs=2, eye="mean", beak=0.0, drop=None, crack=0, smoke=(),
            extra=None, under=None, prop_off=False, key_ph=0.0, legs=0.0)


def wing(c, t: T, flap, far=False, length=50.0):
    """A long gull wing from the shoulder: flap -1 = up and back, 0 = straight back (foreshortened), 1 = down and back."""
    b = -0.3 if far else 0.0
    a = flap * 1.45 + t.ang
    d = (math.cos(a), math.sin(a))
    n = (-d[1], d[0]) if -d[1] > 0 or (abs(d[1]) < 0.2 and d[0] > 0) else (d[1], -d[0])
    if abs(d[1]) < 0.35:
        n = (0.0, 1.0) if flap >= 0 else (0.0, -1.0)
    L = length * (0.42 + 0.58 * abs(math.sin(flap * 1.3)))
    sx, sy = t.p(0, 0)

    def at(u, v):
        return sx + d[0] * u + n[0] * v, sy + d[1] * u + n[1] * v
    lead = [at(L * k / 8, -2 - 3 * math.sin(math.pi * k / 8)) for k in range(9)]
    trail = []
    for k in range(8, -1, -1):
        u = L * k / 8
        w = 9 * (1 - (k / 8) ** 1.4) + 3
        trail.append(at(u, w + (2 if k % 2 else -1)))
    c.poly(lead + trail, STEEL, bias=b, center=at(L * 0.45, 4))
    # black primaries with a white spot, feather lines
    tip = [at(L * 0.66, -4), at(L, -2), at(L + 2, 1.5), at(L * 0.9, 4.5), at(L * 0.66, 6)]
    c.poly(tip, STEEL, tone=0)
    if L > 22:
        c.px(*at(L * 0.86, 1), CHROME[2])
        c.px(*at(L * 0.86 + 1, 1), CHROME[2])
    for k in (0.3, 0.55):
        x0, y0 = at(L * k, -1)
        x1, y1 = at(L * k + 3, 10 * (1 - k))
        c.line(x0, y0, x1, y1, STEEL[0])
    for k in (0.15, 0.4):
        c.px(*at(L * k, -2.5), BRASS[2])


def propeller(c, t: T, ph, off=False):
    """Two blades spinning round the beak axis (seen from the side: their length swings with the phase)."""
    if not off:
        t.ell(c, -1, 0, 3.2, 3.2, BRASS)
    for k in (0, math.pi):
        a = ph + k
        L = 15 * math.cos(a)
        z = math.sin(a)
        if abs(L) < 1.5:
            continue
        blade_y = -L
        t.tube(c, [(-3, 0, 1.6), (-3 + z * 1.5, blade_y * 0.5, 2.6), (-3 + z * 2.5, blade_y, 1.6)], WOOD)
    # speed arcs
    if not off:
        t.line(c, -7, -14, -8, -8, CREAM[1])
        t.line(c, -7, 14, -8, 8, CREAM[1])


def fish_bomb(c, t: T, wob=0.0):
    """A fish-shaped bomb hanging nose forward: a fat tin sardine with a red band and tail fins."""
    sardine(c, T(*t.p(0, 0), t.ang + wob, 0.8, 0.95), fins=True, face="mean")
    t.line(c, -2, -3, -2, 3, VISOR[1])
    t.line(c, -1, -3, -1, 3, VISOR[1])


def gull_drone(**kw):
    p = dict(BASE)
    p.update(kw)
    c = Canvas(W, H)
    if p["under"]:
        p["under"](c)
    b = T(CX + p["bx"], CY + p["by"], p["ang"])
    for s in p["smoke"]:
        steam(c, *s)
    wing(c, b.child(4, -6), p["flap"] * 0.9 + 0.1, far=True)
    key(c, b.child(12, -10, 0.3), p["key_ph"])
    # tail fan
    b.poly(c, [(18, -6), (36, -8), (38, -2), (36, 4), (18, 6)], STEEL, bulge=0.5, center=(26, -1))
    b.poly(c, [(30, -7), (38, -2), (36, 4), (31, 3)], STEEL, tone=0)
    # tucked legs trailing behind
    for dx in (0, 5):
        lg = b.child(8 + dx, 10, 0.9 + p["legs"])
        lg.tube(c, [(0, 0, 2.2), (10, 0, 1.8)], STEEL, bias=-0.1 * dx)
        lg.poly(c, [(9, -2), (19, -4), (20, 0), (19, 3), (9, 2)], ORANGE, bulge=0.4)
    # bomb rack and the bombs under the belly
    b.tube(c, [(-10, 14, 1.6), (12, 14, 1.6)], STEEL)
    for i in range(p["bombs"]):
        x = -4 + i * 12
        b.line(c, x, 14, x, 17, STEEL[0])
        fish_bomb(c, b.child(x, 21), wob=0.04 * math.sin(p["prop"] + i))
    # the body: a horizontal chrome egg with a white belly
    b.ell(c, 0, 0, 22, 14, CHROME, ang=0.05)
    b.ell(c, -6, 5, 13, 7, CREAM, seam=False, rim=False)
    b.ell(c, -8, 3, 9, 5, CHROME, tone=2, seam=False)
    for x in (-14, -6, 2, 10):
        b.px(c, x, -11, STEEL[0])
        b.px(c, x - 1, -12, CHROME[3])
    b.line(c, 8, -12, 14, 10, STEEL[1])
    if p["crack"]:
        b.line(c, -8, -10, -2, -4, DARK)
        b.line(c, -2, -4, -6, 2, DARK)
    # head
    h = b.child(-20, -6)
    h.ell(c, 0, 0, 12, 11, CHROME)
    # the beak is the propeller shaft: short brass cone
    h.tube(c, [(-8, 1, 4.2), (-17, 1, 2.6)], BRASS)
    h.line(c, -14, -2, -14, 4, BRASS[0])
    # visor and eye (aviator goggles)
    h.poly(c, [(-10, -6), (4, -5), (6, 0), (-9, 1)], VISOR, bulge=0.5)
    h.tube(c, [(4, -3, 1.4), (11, -1, 1.4)], STEEL, seam=False)
    ex, ey = h.p(-7, -6)
    c.stamp(EYES[p["eye"]], int(ex), int(ey), {"y": EYE_Y, "k": DARK, "w": WHITE, "o": VISOR[0], "r": VISOR[1]})
    # aviator cap with ear flaps
    h.ell(c, 2, -8, 8, 4, WOOD)
    h.ell(c, 0, -10, 3.2, 2.6, BRASS, seam=True)
    h.ell(c, -0.5, -10.5, 1.8, 1.4, SEA_GLASS, seam=False)
    if not p["prop_off"]:
        propeller(c, h.child(-18, 1), p["prop"])
    # near wing last
    wing(c, b.child(-2, -4), p["flap"])
    if p["drop"] is not None:
        k = p["drop"]
        fish_bomb(c, T(CX + p["bx"] + 8, CY + p["by"] + 26 + k * 8, 0.25 + k * 0.5))
    if p["extra"]:
        p["extra"](c)
    return c.done()


def frames():
    f = {}
    flaps = [-1.0, -0.6, -0.1, 0.85, 0.55, -0.5]
    bob = [1, 0, -1, -2, -1, 0]
    for i in range(6):
        f[f"fly_{i}"] = gull_drone(flap=flaps[i], by=bob[i], prop=i * 1.1, key_ph=i * math.pi / 6, legs=0.05 * math.sin(i))
    # drop: the rack opens, a bomb falls, the gull pops up lighter and grins
    f["drop_0"] = gull_drone(flap=-0.5, prop=0.4, eye="look", beak=0.2)
    f["drop_1"] = gull_drone(flap=0.2, prop=1.5, bombs=1, drop=0.0, eye="mean", by=-2, extra=lambda c: _click(c))
    f["drop_2"] = gull_drone(flap=0.7, prop=2.6, bombs=1, drop=1.0, by=-4, eye="mean")
    f["drop_3"] = gull_drone(flap=-0.3, prop=3.7, bombs=1, drop=1.8, by=-2, eye="closed")
    f["hit_0"] = gull_drone(flap=-0.9, ang=0.15, bx=3, prop=0.2, eye="shock", crack=1, extra=lambda c: screw(c, 100, 26, 0.7))
    f["hit_1"] = gull_drone(flap=0.4, ang=0.06, bx=1, prop=1.4, eye="x", crack=1, smoke=((92, 40, 1),))
    f.update(die())
    return f


def _click(c):
    star(c, 60, 82, 4, CREAM, tone=2)


def die():
    """Spinning down trailing smoke: tilts nose-down, spins, the propeller unscrews and bounces off comically."""
    f = {}
    for i in range(8):
        k = i / 7
        ang = -0.25 - k * 1.1 + (0.25 * math.sin(i * 2.1))
        trail = tuple((CX + 22 + j * 9, CY - 10 + i * 3 - j * 6, min(3, j), 1.0 + 0.2 * j, SMOKE) for j in range(1 + min(i, 3)))
        prop_off = i >= 4
        extra = None
        if prop_off:
            # the propeller on its own: pops up then bounces down
            px = 24 - (i - 4) * 2
            py = [22, 18, 28, 40][i - 4]
            extra = (lambda c, px=px, py=py, i=i: (propeller(c, T(px, py, (i - 4) * 0.9), i * 1.3, off=True),
                                                     c.ell(px, py, 2.6, 2.6, BRASS)))
        f[f"die_{i}"] = gull_drone(flap=[0.6, -0.8, 0.3, -1.0, 0.8, -0.2, 0.5, 0.9][i], ang=ang, by=min(i * 3, 16),
                                   bx=-i * 1.5, prop=i * 0.9, eye="dizzy" if i % 2 else "x", crack=1, smoke=trail,
                                   prop_off=prop_off, extra=extra, bombs=2 if i < 3 else 1)
    return f


def build():
    s = Sheet("gull_drone", W, H, [64, 56], faces="left",
              notes="drop_1..3 show the released bomb under the gull; the game spawns the falling bomb (shots bomb_*) at drop_1")
    order = [f"fly_{i}" for i in range(6)] + [f"drop_{i}" for i in range(4)] + ["hit_0", "hit_1"] + [f"die_{i}" for i in range(8)]
    fr = frames()
    for n in order:
        s.add(n, fr[n])
    s.save()
    return fr


if __name__ == "__main__":
    build()
