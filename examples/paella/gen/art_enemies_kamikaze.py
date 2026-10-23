"""Paella de Combate: gull_kamikaze (112x96, anchor [56, 48] = centre, faces left): a grinning gull strapped to a rocket."""
from __future__ import annotations

import math

from enemies_kit import BRASS, CHROME, CREAM, FIRE, ORANGE, SEA, STEEL, VISOR, WOOD, Canvas, Sheet
from fx_parts import boom, debris, puff
from gull_parts import DARK, WHITE, T, feather, key, screw, sweat, wing_arm

W, H = 112, 96

BASE = dict(ang=0.0, jx=0.0, jy=0.0, flame=1, fph=0, scarf=0.0, face="grin", sweat=(), lines=0, hot=False, arm="hold",
            extra=None, under=None, key_ph=0.0)


def flame(c, t: T, size, ph):
    """Rocket exhaust behind the nozzle (pivot = nozzle), pointing along +x: lobes flickering with the phase."""
    L = [0, 8, 14, 22][size]
    if not L:
        return
    wob = [0, 2, -1, 1][ph % 4]
    t.poly(c, [(0, -6), (L * 0.5, -8 - wob * 0.5), (L, -3 + wob), (L * 1.15, 0), (L, 3 - wob), (L * 0.5, 8 + wob * 0.5), (0, 6)],
           FIRE, bulge=0.5, seam=False, rim=False)
    t.poly(c, [(0, -4), (L * 0.55, -3.5 + wob * 0.5), (L * 0.8, 0), (L * 0.55, 3.5), (0, 4)], FIRE, tone=2, seam=False)
    t.ell(c, 3, 0, L * 0.25 + 1, 2.5, FIRE, tone=3, seam=False)


def rocket(c, t: T, p):
    """Pivot = middle of the rocket; nose along -x."""
    flame(c, t.child(34, 0), p["flame"], p["fph"])
    # fins
    t.poly(c, [(18, -8), (30, -18), (34, -18), (32, -7)], STEEL, bulge=0.5)
    t.poly(c, [(18, 8), (30, 18), (34, 18), (32, 7)], STEEL, bulge=0.5, bias=-0.2)
    t.poly(c, [(28, -4), (34, -4), (35, 4), (28, 4)], STEEL, tone=0)
    body_ramp = CREAM if p["hot"] else VISOR
    t.tube(c, [(-24, 0, 9), (30, 0, 9)], body_ramp)
    # nose cone
    t.poly(c, [(-24, -9), (-24, 9), (-34, 6), (-40, 0), (-34, -6)], CHROME, bulge=0.8, center=(-28, 0))
    t.line(c, -24, -8, -24, 8, STEEL[0])
    # a white band and a painted sardine
    t.tube(c, [(4, -9, 0.0), (4, 9, 0.0)], CREAM)
    for x in (2, 3, 5, 6):
        t.line(c, x, -8.4, x, 8.4, CREAM[2] if x in (3, 5) else CREAM[1])
    t.line(c, -16, 3, -6, 3, CREAM[2])
    t.px(c, -5, 2, CREAM[2])
    t.px(c, -5, 4, CREAM[2])
    t.px(c, -15, 2, DARK)
    for x in (-20, 14, 24):
        t.px(c, x, -7, VISOR[3] if not p["hot"] else CREAM[3])
    # leather straps
    for x in (-10, 14):
        t.tube(c, [(x, -10, 1.8), (x + 1, 10, 1.8)], WOOD, seam=True)
        t.px(c, x, -2, BRASS[2])


def scarf(c, t: T, ph, streak=False):
    """A white aviator scarf with red stripes flowing back from the neck (pivot = the knot)."""
    pts_top, pts_bot = [], []
    n = 6
    for i in range(n + 1):
        u = i / n
        x = u * (34 if not streak else 40)
        y = math.sin(ph + u * 4.0) * (4 if not streak else 1.5) * u - u * 2
        w = 3.2 - 1.4 * u
        pts_top.append((x, y - w))
        pts_bot.append((x, y + w))
    t.poly(c, pts_top + pts_bot[::-1], CREAM, bulge=0.4, center=(10, 0))
    for i in (2, 4):
        u = i / n
        x = u * (34 if not streak else 40)
        y = math.sin(ph + u * 4.0) * (4 if not streak else 1.5) * u - u * 2
        t.line(c, x, y - 3, x + 1, y + 3, VISOR[1])
    t.ell(c, 0, 0, 4, 3.5, CREAM)


def goggles_face(c, h: T, face):
    """Round brass goggles; the eyes inside tell the mood. Then the grin."""
    for ox in (-9, -2):
        h.ell(c, ox, -3, 4.8, 4.8, BRASS)
        h.ell(c, ox - 0.3, -3.3, 3.3, 3.3, SEA, seam=False)
    h.tube(c, [(2, -4, 1.3), (11, -3, 1.3)], WOOD, seam=False)
    eyes = {"grin": [(-10, -3), (-3, -3)], "scared": [(-10, -4), (-3, -4)], "yell": None, "x": None}
    if face in ("grin", "scared"):
        for ex, ey in eyes[face]:
            h.px(c, ex, ey, DARK)
            h.px(c, ex - 1, ey, DARK)
            if face == "grin":
                h.px(c, ex - 1, ey - 1, DARK)
                h.px(c, ex, ey - 1, DARK)
                h.px(c, ex + 0.5, ey - 1.5, WHITE)
    elif face == "yell":
        for ox in (-9, -2):
            h.line(c, ox - 2, -5, ox + 2, -3, DARK)
    else:
        for ox in (-9, -2):
            h.line(c, ox - 2, -6, ox + 1, -2, DARK)
            h.line(c, ox - 2, -2, ox + 1, -6, DARK)
    # beak: upper hook, the lower jaw open in a huge grin
    open_ = {"grin": 0.35, "scared": 0.15, "yell": 0.8, "x": 0.5}[face]
    lo = h.child(-8, 3, -open_ * 0.5)
    lo.tube(c, [(0, 0, 3.0), (-11, 1, 1.8)], BRASS, bias=-0.15)
    lo.ell(c, -9, 1, 1.8, 1.6, VISOR)
    h.ell(c, -12, 3 + open_ * 3, 5, 1 + open_ * 4, VISOR, tone=0, seam=False)
    if face == "grin":
        h.line(c, -16, 2, -9, 4, WHITE)
    h.tube(c, [(-6, 0, 3.8), (-17, 1, 2.6), (-20, 3, 1.4)], BRASS)
    h.px(c, -14, 0, BRASS[3])


def kamikaze(**kw):
    p = dict(BASE)
    p.update(kw)
    c = Canvas(W, H)
    if p["under"]:
        p["under"](c)
    g = T(56 + p["jx"], 48 + p["jy"], p["ang"])
    for i in range(p["lines"]):
        y = [-22, -4, 14, 26][i % 4]
        g.line(c, 30 + i * 3, y, 44 + i * 2, y, CREAM[1])
    # far wing hanging on the far side, the key, the gull body seated on the rocket
    key(c, g.child(12, -18), p["key_ph"])
    r = g.child(-4, 12)
    g.tube(c, [(4, -6, 4), (18, 4, 3)], STEEL, bias=-0.3)  # far leg strapped
    rocket(c, r, p)
    g.ell(c, 4, -10, 16, 12, CHROME, ang=-0.25)
    g.ell(c, -3, -6, 9, 7, CREAM, seam=False, rim=False)
    g.poly(c, [(2, -20), (16, -16), (24, -6), (14, -2), (6, -8)], STEEL, bulge=0.6)
    g.tube(c, [(-2, -2, 4.5), (-8, 8, 3)], CHROME)  # near thigh hugging the rocket
    g.poly(c, [(-8, 7), (-17, 9), (-16, 12), (-6, 12)], ORANGE, bulge=0.4)
    # head
    h = g.child(-14, -26)
    g.tube(c, [(-4, -14, 6), (-12, -22, 6)], CHROME, seam=False)
    h.ell(c, 0, 0, 13, 11.5, CHROME, seam=False)
    h.ell(c, 3, -6, 11, 7, WOOD, ang=0.15)
    h.poly(c, [(6, -4), (12, -3), (11, 6), (7, 6)], WOOD, bulge=0.4)
    h.px(c, 0, -10, WOOD[3])
    h.px(c, 1, -10, WOOD[3])
    goggles_face(c, h, p["face"])
    scarf(c, g.child(-4, -14), p["scarf"], streak=p["lines"] > 0)
    # the near wing: holding the strap / waving / clutching
    if p["arm"] == "hold":
        wing_arm(c, g.child(-2, -12), aim=0.9, bend=0.7, gun=False, fingers="fist", reach=0.8)
    elif p["arm"] == "thumb":
        wing_arm(c, g.child(-2, -12), aim=-0.9, bend=0.2, gun=False, fingers="splay", reach=0.9)
    else:  # tucked back in a dive
        wing_arm(c, g.child(-2, -12), aim=2.6, bend=0.0, gun=False, fingers="fist", reach=0.9)
    for s in p["sweat"]:
        sweat(c, *s)
    if p["extra"]:
        p["extra"](c)
    return c.done()


def frames():
    f = {}
    for i in range(4):
        f[f"idle_{i}"] = kamikaze(jy=[0, -1, -2, -1][i], fph=i, scarf=i * math.pi / 2, key_ph=i * 0.4,
                                  arm="thumb" if i in (1, 2) else "hold")
    for i in range(4):
        j = [(-1, 0), (1, -1), (-1, 1), (1, 0)][i]
        f[f"windup_{i}"] = kamikaze(jx=j[0], jy=j[1], flame=2, fph=i, scarf=i * 1.9, face="scared", key_ph=i * 1.2,
                                    sweat=((30 + i % 2 * 3, 14), (56, 10 + i % 2 * 2)))
    for i in range(4):
        f[f"dive_{i}"] = kamikaze(ang=-0.42, flame=3, fph=i, face="yell", lines=4, arm="tuck", scarf=i * 2.2, jy=6, jx=-7,
                                  key_ph=i * 1.5)
    f["hit_0"] = kamikaze(jx=3, ang=0.1, face="x", flame=1, extra=lambda c: screw(c, 84, 18, 0.4))
    f["hit_1"] = kamikaze(jx=1, ang=0.04, face="scared", flame=1, fph=2)
    f.update(explode())
    return f


def explode():
    f = {}
    f["explode_0"] = kamikaze(hot=True, face="scared", flame=2, sweat=((30, 12),), jx=1)
    for i in range(1, 8):
        k = (i - 1) / 6 * 0.95 + 0.04
        c = Canvas(W, H)
        boom(c, 56, 50, 36, k, seed=11, n=8)
        if i >= 3:
            debris(c, 56, 44, 28, (i - 2) / 5, seed=4, feathers=5, screws=3)
        if i >= 5:  # the scarf flutters down out of the smoke
            scarf(c, T(36 + i * 2, 18 + (i - 5) * 7, 0.6 + i * 0.3), i * 1.3)
        f[f"explode_{i}"] = c.done()
    return f


def build():
    s = Sheet("gull_kamikaze", W, H, [56, 48], faces="left", notes="explode_* is centred on the anchor; dive_* already tilts nose-down")
    order = ([f"idle_{i}" for i in range(4)] + [f"windup_{i}" for i in range(4)] + [f"dive_{i}" for i in range(4)] +
             [f"explode_{i}" for i in range(8)] + ["hit_0", "hit_1"])
    fr = frames()
    for n in order:
        s.add(n, fr[n])
    s.save()
    return fr


if __name__ == "__main__":
    build()
