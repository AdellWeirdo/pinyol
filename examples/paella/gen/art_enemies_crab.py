"""Paella de Combate: crab_tank (192x128, anchor [96, 126], faces left).

A real crab shell bolted over a steel chassis on six scuttling legs, one huge claw with a cannon between the pincers,
eye-stalk periscopes, and a gull pilot peeking out of the hatch with his own periscope.
"""
from __future__ import annotations

import math

from enemies_kit import BRASS, CHROME, CREAM, FIRE, SEA, STEEL, VISOR, Canvas, Ramp, Sheet, overlay
from fx_parts import boom, debris
from gull_parts import DARK, EYES, EYE_Y, WHITE, T, muzzle_flash, screw, steam, tin_helmet

W, H = 192, 128
GROUND = 125
SHELL = Ramp("#7a1c10", "#c4401c", "#f07a3a", "#ffc888", ol="#3a0c08")   # cooked-crab red-orange
SHELL_DK = Ramp("#4a1008", "#7a1c10", "#c4401c", "#f07a3a", ol="#3a0c08")
SEAWEED = Ramp("#1c4a1c", "#2e7a28", "#5cb03c", "#b4e47c", ol="#102410")

BASE = dict(bx=0.0, by=0.0, ang=0.0, legs=None, claw=0.0, recoil=0.0, flash=0, pilot=1.0, pilot_eye="mean", scope=0.0,
            stalks=0.0, crack=0, smoke=(), extra=None, under=None, shell_only=False, pilot_beak=0.0)


def crab_leg(c, root, knee, tip, far=False):
    """A pointy crab leg: chassis root -> raised knee -> pointed tip on the ground."""
    b = -0.35 if far else 0.0
    c.tube([(root[0], root[1], 4.6), (knee[0], knee[1], 3.8)], SHELL, bias=b)
    c.tube([(knee[0], knee[1], 3.6), ((knee[0] + tip[0]) / 2, (knee[1] + tip[1]) / 2, 2.6), (tip[0], tip[1], 0.8)], SHELL, bias=b)
    c.ell(knee[0], knee[1], 3.0, 3.0, STEEL, bias=b)
    c.px(knee[0] - 1, knee[1] - 1, STEEL[3])
    # a spine on the joint
    c.poly([(knee[0] - 2, knee[1] - 2), (knee[0], knee[1] - 7), (knee[0] + 2, knee[1] - 2)], SHELL, bulge=0.3, bias=b)


NEAR_TIPS = (44, 96, 168)
FAR_TIPS = (62, 128, 176)


def leg_pose(i, ph, lift=0.0):
    """Leg i (0..2 near side, 3..5 far side): (root, knee, tip) for gait phase ph (0..1). Legs arch out like a crab's."""
    side = 0 if i < 3 else 1
    j = i % 3
    root = ([88, 108, 130][j] + side * 6, 98)
    tip0 = (FAR_TIPS if side else NEAR_TIPS)[j]
    swing = math.sin(ph * 2 * math.pi)
    up = max(0.0, math.cos(ph * 2 * math.pi)) * (7 + lift)
    tx = tip0 + swing * 7
    tip = (tx, GROUND - 1 - up)
    out = -1 if tx < root[0] else 1
    knee = (tx - out * 8 + (2 if j == 1 else 0), 90 - up * 0.6 - (6 if j != 1 else 0))
    return root, knee, tip


def claw(c, t: T, p):
    """The big cannon claw; pivot = the shoulder on the shell. Arm goes forward (-x), claw at the end."""
    r = p["recoil"]
    t.tube(c, [(0, 0, 7), (-12 + r, 6, 6)], SHELL)
    t.ell(c, -12 + r, 6, 5, 5, STEEL)
    k = t.child(-12 + r, 6, p["claw"])
    k.tube(c, [(0, 0, 6), (-14, -2, 8)], SHELL)
    # cannon barrel out between the pincers
    k.tube(c, [(-14, -2, 4.2), (-40, -2, 3.6)], STEEL)
    k.ell(c, -41, -2, 2.4, 4.6, STEEL, seam=True)
    k.ell(c, -41.6, -2, 1.2, 2.6, STEEL, tone=0, seam=False)
    k.line(c, -26, -6, -26, 2, STEEL[0])
    k.line(c, -36, -5.5, -36, 1.5, STEEL[0])
    # pincers: upper big, lower small, wide open round the barrel
    k.poly(c, [(-10, -8), (-20, -17), (-32, -17), (-40, -11), (-30, -9), (-20, -7)], SHELL, bulge=0.7, center=(-22, -12))
    k.poly(c, [(-10, 4), (-20, 9), (-30, 9), (-34, 5), (-24, 3)], SHELL, bulge=0.7, center=(-22, 6), bias=-0.15)
    for x in (-26, -32, -37):
        k.px(c, x, -10, CREAM[2])
    if p["flash"]:
        muzzle_flash(c, k.child(-42, -2), p["flash"])


def shell(c, t: T, p, near_legs=True):
    t.ell(c, 0, -2, 52, 30, SHELL)
    # the rim, a bolted steel skirt under it
    t.poly(c, [(-44, 10), (44, 10), (38, 24), (-38, 24)], STEEL, bulge=0.5, center=(0, 12))
    for x in range(-34, 36, 10):
        t.px(c, x, 17, STEEL[0])
        t.px(c, x - 1, 16, STEEL[3])
    t.ell(c, 0, -4, 50, 26, SHELL, seam=False)
    # shell texture: bumps and a ridge, spiky edge
    for x, y, r in ((-24, -12, 5), (-6, -20, 6), (14, -18, 5), (30, -8, 4), (-34, 0, 4), (6, -6, 4)):
        t.ell(c, x, y, r, r * 0.8, SHELL, seam=False, bias=0.25)
        t.px(c, x - r * 0.3, y - r * 0.4, SHELL[3])
    for i in range(9):
        a = math.pi + i * math.pi / 8
        x, y = 50 * math.cos(a), -4 + 26 * math.sin(a) * 1.05
        t.poly(c, [(x - 3, y), (x + math.cos(a) * 5, y + math.sin(a) * 5 - 1), (x + 3, y)], SHELL, bulge=0.4)
    # stencilled number and a strand of seaweed draped over the back
    t.line(c, 18, 2, 18, 8, CREAM[1])
    t.line(c, 20, 2, 23, 2, CREAM[1])
    t.line(c, 23, 2, 21, 8, CREAM[1])
    t.poly(c, [(28, -24), (34, -20), (36, -6), (33, 4), (31, -6), (29, -16)], SEAWEED, bulge=0.4)
    t.poly(c, [(20, -26), (26, -24), (24, -14), (22, -12)], SEAWEED, bulge=0.4)
    if p["crack"]:
        t.line(c, -20, -20, -10, -10, SHELL.ol)
        t.line(c, -10, -10, -14, 0, SHELL.ol)
        t.line(c, 8, -24, 14, -12, SHELL.ol)
        if p["crack"] > 1:
            t.line(c, 20, -16, 30, 0, SHELL.ol)
            t.line(c, -30, 4, -20, 8, SHELL.ol)


def stalks(c, t: T, wob, eye="mean"):
    """Two eye-stalk periscopes on the front of the shell, red lenses glaring."""
    for i, (x, h) in enumerate(((-34, 18), (-24, 20))):
        a = wob * (1 if i else -1) * 0.15
        s = t.child(x, -18, a)
        s.tube(c, [(0, 0, 2.2), (0, -h, 2.0)], STEEL, bias=-0.1 * i)
        s.ell(c, 0, -h - 3, 4.5, 4.0, CHROME)
        s.ell(c, -2, -h - 3, 2.4, 2.6, VISOR, seam=True)
        s.px(c, -3, -h - 4, VISOR[3])
        if eye == "x":
            s.line(c, -4, -h - 5, -1, -h - 1, DARK)


def pilot(c, t: T, rise, eye="mean", beak=0.0):
    """The gull pilot in the hatch: rise 0 = hidden (just the hatch lid), 1 = peeking (head and shoulders)."""
    # hatch ring
    t.ell(c, 0, 2, 12, 4, STEEL)
    t.ell(c, 0, 1, 9, 2.5, STEEL, tone=0, seam=False)
    if rise > 0.05:
        y = 4 - rise * 16
        g = t.child(0, y)
        g.ell(c, 2, 0, 9, 8, CHROME)
        g.tube(c, [(-4, -2, 3.4), (-14, -1, 2.4)], BRASS)
        g.tube(c, [(-5, 2, 2.4), (-12, 3 + beak * 3, 1.6)], BRASS, bias=-0.2)
        g.poly(c, [(-7, -6), (4, -5), (5, -1), (-6, 0)], VISOR, bulge=0.5)
        ex, ey = g.p(-5, -6)
        c.stamp(EYES[eye], int(ex), int(ey), {"y": EYE_Y, "k": DARK, "w": WHITE, "o": VISOR[0], "r": VISOR[1]})
        tin_helmet(c, T(*g.p(2, -8), 0.0, 0.85, 0.85))
        # re-cut the bottom: the body stays inside the hatch
        t.ell(c, 0, 4, 12, 3.5, STEEL, seam=False)
    # hatch lid flipped open behind
    t.poly(c, [(6, -2), (16, -14), (20, -12), (12, 1)], STEEL, bulge=0.5)


def periscope(c, t: T, turn):
    t.tube(c, [(0, 0, 2.6), (0, -26, 2.6)], STEEL)
    k = math.cos(turn)
    w = 3 + 4 * abs(k)
    d = -1 if k >= 0 else 1
    t.poly(c, [(0, -24), (0, -34), (d * w, -33), (d * w, -26)], STEEL, bulge=0.5)
    t.ell(c, d * w, -30, 1.4, 3.2, SEA, seam=True)


def crab_tank(**kw):
    p = dict(BASE)
    p.update(kw)
    c = Canvas(W, H)
    if p["under"]:
        p["under"](c)
    legs = p["legs"] or [leg_pose(i, 0.0) for i in range(6)]
    ox, oy = p["bx"], p["by"]
    for i in (3, 4, 5):  # far legs
        r, k, t_ = legs[i]
        crab_leg(c, (r[0] + ox, r[1] + oy - 4), (k[0] + ox, k[1] + oy - 4), t_, far=True)
    b = T(110 + ox, 76 + oy, p["ang"])
    periscope(c, b.child(30, -22), p["scope"])
    pilot(c, b.child(8, -27), p["pilot"], p["pilot_eye"], p["pilot_beak"])
    # small claw behind
    sc = b.child(-38, 14)
    sc.tube(c, [(0, 0, 4), (-12, 6, 3.5)], SHELL, bias=-0.3)
    sc.poly(c, [(-10, 2), (-22, 0), (-24, 6), (-18, 10), (-10, 10)], SHELL, bias=-0.3, center=(-16, 6))
    shell(c, b, p)
    stalks(c, b, p["stalks"])
    for i in (0, 1, 2):
        r, k, t_ = legs[i]
        crab_leg(c, (r[0] + ox, r[1] + oy), (k[0] + ox, k[1] + oy), t_)
    claw(c, b.child(-40, 2), p)
    for s in p["smoke"]:
        steam(c, *s)
    if p["extra"]:
        p["extra"](c)
    return c.done()


def frames():
    f = {}
    for i in range(4):
        legs = [leg_pose(j, 0.25 + 0.03 * math.sin(i * math.pi / 2 + j)) for j in range(6)]
        f[f"idle_{i}"] = crab_tank(legs=legs, by=[0, 1, 1, 0][i], stalks=math.sin(i * math.pi / 2), scope=i * math.pi / 2,
                                   claw=[0, -0.03, -0.05, -0.02][i], pilot=1.0, pilot_eye="look" if i in (1, 2) else "mean")
    for i in range(8):
        ph = i / 8
        legs = [leg_pose(j, (ph + (0.5 if (j % 2) ^ (j >= 3) else 0.0)) % 1) for j in range(6)]
        f[f"move_{i}"] = crab_tank(legs=legs, by=[0, -1, -2, -1, 0, -1, -2, -1][i], stalks=math.sin(ph * 4 * math.pi),
                                   scope=ph * 2 * math.pi, claw=0.04 * math.sin(ph * 2 * math.pi), ang=0.015 * math.sin(ph * 4 * math.pi))
    fire = [dict(claw=-0.08, pilot=1.0, pilot_eye="look"),
            dict(claw=-0.12, recoil=0, flash=1, pilot=0.5, pilot_eye="closed", stalks=-1),
            dict(claw=-0.2, recoil=6, flash=2, pilot=0.0, bx=2, smoke=((28, 52, 0, 1.6),), stalks=-1),
            dict(claw=-0.14, recoil=4, pilot=0.0, bx=1, smoke=((24, 46, 1, 1.8),), stalks=0.5),
            dict(claw=-0.08, recoil=2, pilot=0.4, pilot_eye="look", smoke=((22, 40, 2, 1.8),)),
            dict(claw=-0.04, recoil=0, pilot=1.0, pilot_eye="mean", smoke=((20, 34, 3, 1.4),))]
    legs0 = [leg_pose(j, 0.25) for j in range(6)]
    for i, fr in enumerate(fire):
        f[f"fire_{i}"] = crab_tank(legs=legs0, scope=i * 0.6, **fr)
    f["hit_0"] = crab_tank(legs=legs0, bx=4, by=1, ang=0.04, crack=1, pilot=0.6, pilot_eye="shock", stalks=1.5,
                           smoke=((130, 40, 1, 1.4),), extra=lambda c: (screw(c, 150, 30, 0.5), screw(c, 60, 34, 2.0)))
    f["hit_1"] = crab_tank(legs=legs0, bx=2, ang=0.02, crack=1, pilot=0.9, pilot_eye="x", stalks=-1.0,
                           smoke=((134, 34, 2, 1.4),))
    f.update(die())
    return f


def spring_pilot(c, base, top, ang=0.0, face="shock"):
    """The pilot gull on an ejector spring (base -> top), arms flailing, beak wide open screaming."""
    bx, by = base
    tx, ty = top
    n = 7
    for i in range(n):
        y0 = by + (ty - by) * i / n
        y1 = by + (ty - by) * (i + 0.5) / n
        x0 = bx + (tx - bx) * i / n
        c.line(x0 - 5, y0, x0 + 5, y1, STEEL[2])
        c.line(x0 + 5, y1, x0 - 5, by + (ty - by) * (i + 1) / n, STEEL[1])
    g = T(tx, ty - 10, ang)
    g.tube(c, [(-8, -2, 3), (-18, -12, 2.4)], STEEL)  # flailing wings
    g.tube(c, [(8, -2, 3), (18, -14, 2.4)], STEEL)
    g.ell(c, 0, 0, 9, 11, CHROME)
    g.ell(c, -1, 3, 6, 7, CREAM, seam=False)
    h = g.child(0, -14)
    h.ell(c, 0, 0, 8, 7, CHROME)
    h.tube(c, [(-5, -1, 3), (-14, -1, 2)], BRASS)
    h.tube(c, [(-5, 3, 2.2), (-12, 7, 1.6)], BRASS, bias=-0.2)
    h.ell(c, -8, 3, 3, 3, VISOR, tone=0, seam=False)
    ex, ey = h.p(-6, -5)
    c.stamp(EYES[face], int(ex), int(ey), {"y": EYE_Y, "k": DARK, "w": WHITE, "o": VISOR[0], "r": VISOR[1]})


def die():
    """Shell cracks, BOOM, the pilot is ejected on a spring and flies off screaming, the shell rolls away."""
    f = {}
    legs0 = [leg_pose(j, 0.25) for j in range(6)]
    f["die_0"] = crab_tank(legs=legs0, crack=2, pilot=1.0, pilot_eye="shock", pilot_beak=1, stalks=2.0,
                           smoke=((120, 44, 0, 1.4), (70, 50, 1, 1.2), (140, 60, 0, 1.0)))
    c = Canvas(W, H)
    boom(c, 96, 74, 40, 0.04, seed=21)
    f["die_1"] = overlay(crab_tank(legs=legs0, crack=2, pilot=0.6, pilot_eye="x"), c.done())
    # 2..9: the fireball grows and smokes away; the pilot rides a spring up and off; the shell tumbles right
    pil = [((112, 56), (112, 48)), ((112, 56), (108, 38)), None, None, None, None, None, None]
    for i in range(2, 10):
        k = (i - 2) / 7
        c = Canvas(W, H)
        # the shell tumbling away to the right
        sx = 104 + (i - 2) * 8
        sh = T(sx, 92 - (6 if i in (4, 5) else 0), (i - 2) * 0.55)
        boom(c, 92, 80, 44, 0.12 + k * 0.85, seed=21, n=9, smoke_dark=i > 6)
        debris(c, 96, 70, 40, min(1.0, k * 1.2 + 0.1), seed=9, feathers=4, screws=6)
        if i >= 4:
            sh.ell(c, 0, 0, 25, 17, SHELL)
            for x, y, r in ((-12, -8, 4), (4, -12, 5), (16, -4, 3)):
                sh.ell(c, x, y, r, r * 0.8, SHELL, seam=False, bias=0.25)
            sh.ell(c, 0, 10, 24, 7, STEEL, bias=-0.2)
        if pil[i - 2]:
            base, top = pil[i - 2]
            spring_pilot(c, base, top, ang=0.2 * i)
        elif i in (4, 5):
            # a speck flying away high with a scream trail
            x, y = 40 - (i - 4) * 14, 18 - (i - 4) * 6
            g = T(x, y, i * 0.9, 0.6, 0.6)
            g.ell(c, 0, 0, 9, 11, CHROME)
            g.tube(c, [(-8, -2, 3), (-18, -12, 2.4)], STEEL)
            g.tube(c, [(0, -10, 4), (-10, -12, 2)], BRASS)
            for j in range(3):
                c.line(x + 8 + j * 5, y + 3 + j * 2, x + 11 + j * 5, y + 4 + j * 2, CREAM[2])
        if i >= 8:
            # a crab leg twitching on the ground
            crab_leg(c, (60, GROUND - 4), (50, GROUND - 12 + (i - 8) * 3), (38, GROUND - 1))
        img = c.done()
        if i in (2, 3):
            img = overlay(crab_tank(legs=legs0, crack=2, pilot=0.0, stalks=2.0 + i), img)
        f[f"die_{i}"] = img
    return f


def build():
    s = Sheet("crab_tank", W, H, [96, 126], faces="left",
              notes="cannon muzzle at about x=10, y=76 (fire_1); the pilot hides in the hatch in fire_2..3")
    order = ([f"idle_{i}" for i in range(4)] + [f"move_{i}" for i in range(8)] + [f"fire_{i}" for i in range(6)] +
             ["hit_0", "hit_1"] + [f"die_{i}" for i in range(10)])
    fr = frames()
    for n in order:
        s.add(n, fr[n])
    s.save()
    return fr


if __name__ == "__main__":
    build()
