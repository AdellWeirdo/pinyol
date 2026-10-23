"""Paella de Combate: gull_bazooka (112x104, anchor [56, 102], faces left): a gull sitting on its hocks with a sardine launcher."""
from __future__ import annotations

import math

import numpy as np

from enemies_kit import BRASS, CHROME, CREAM, FIRE, OLIVE, ORANGE, SMOKE, STEEL, VISOR, WOOD, Canvas, Sheet, overlay
from gull_parts import (DARK, T, body, far_wing, feather, head, key, muzzle_flash, sardine, screw, star, steam, sweat, tail,
                        tin_helmet, webbed_foot, wing_arm)

W, H = 112, 104
GROUND = 101

BASE = dict(bx=0.0, by=0.0, lean=0.0, hdx=0.0, hdy=0.0, hang=0.0, beak=0.0, eye="mean", helmet=True, tilt=0.0, recoil=0.0,
            loaded=True, keyph=0.0, flick=0.0, crack=0, steam=(), sweat=(), blast=0, flash=0, rocket_out=None, arm="grip",
            held=None, extra=None, under=None, launcher=True, helmet_t=None)


def kneel_leg(c, hip, far=False):
    """Sitting on the hocks: thigh down to a knee on the ground behind, the tarsus flat on the ground, foot forward."""
    b = -0.3 if far else 0.0
    kx, ky = hip[0] + 7, GROUND - 3
    ax, ay = hip[0] - 13, GROUND - 3
    c.tube([(hip[0], hip[1], 5.0), (kx, ky - 1, 3.2)], CHROME, bias=b)
    c.tube([(kx, ky, 2.5), (ax, ay, 2.2)], STEEL, bias=b)
    c.ell(kx, ky - 1, 2.6, 2.6, BRASS, bias=b)
    webbed_foot(c, ax - 2, ay + 0.5, far)


def launcher(c, t: T, p):
    """The sardine launcher: pivot = where it rests on the shoulder; muzzle along -x."""
    r = p["recoil"]
    lt = t.child(r, 0, p["tilt"])
    if p["loaded"]:
        sardine(c, lt.child(-33, 0), fins=False)
    # rear bell and the tube
    lt.poly(c, [(18, -5), (28, -8.5), (29, 8.5), (18, 5)], STEEL, bulge=0.6)
    lt.ell(c, 28.5, 0, 1.6, 8.5, STEEL, tone=0, seam=True)
    lt.tube(c, [(-27, 0, 5.4), (19, 0, 5.4)], OLIVE)
    lt.ell(c, -28, 0, 2.2, 6.2, STEEL, seam=True)
    lt.ell(c, -28.5, 0, 1.0, 4.0, STEEL, tone=0, seam=False)
    for x in (-19, -17):  # a yellow warning band
        lt.line(c, x, -5, x, 5, BRASS[2])
    lt.line(c, 6, -5, 6, 5, OLIVE[0])
    # stencil fish on the tube
    lt.line(c, -6, 0, 2, 0, OLIVE[3])
    lt.px(c, 3, -1, OLIVE[3])
    lt.px(c, 3, 1, OLIVE[3])
    lt.px(c, -7, 0, OLIVE[3])
    # sight and grips
    lt.poly(c, [(-14, -5), (-8, -5), (-9, -10), (-13, -10)], STEEL, bulge=0.4)
    lt.ell(c, -11, -10, 2.4, 1.6, VISOR, seam=True)
    lt.poly(c, [(-6, 4), (-1, 4), (0, 13), (-4, 13)], WOOD, bulge=0.5)
    lt.poly(c, [(10, 4), (14, 4), (15, 10), (11, 10)], WOOD, bulge=0.5)
    if p["flash"]:
        muzzle_flash(c, lt.child(-31, 0), p["flash"])
    if p["blast"]:
        backblast(c, lt.child(30, 0), p["blast"])
    return lt


def backblast(c, t: T, k):
    """The big backblast out of the rear: a cone of fire then rolling smoke (k = 1 fire, 2 fire+smoke, 3 smoke, 4 wisps)."""
    if k in (1, 2):
        L = 15 if k == 1 else 11
        t.poly(c, [(0, -6), (L * 0.6, -12), (L, -4), (L + 4, 2), (L * 0.7, 10), (0, 6)], FIRE, bulge=0.5, seam=False)
        t.ell(c, 6, 0, 8, 4.5, FIRE, tone=3, seam=False)
    if k >= 2:
        sm = {2: [(11, -11, 6), (12, 3, 5), (6, 9, 5)], 3: [(10, -12, 7), (15, -1, 6), (8, 8, 5), (4, -5, 5)],
              4: [(10, -16, 5), (8, -6, 4), (14, -4, 3)]}[k]
        for x, y, r in sm:
            t.ell(c, x, y, r, r * 0.85, SMOKE if k > 2 else CREAM, rim=False)


def gull_bazooka(**kw):
    p = dict(BASE)
    p.update(kw)
    c = Canvas(W, H)
    if p["under"]:
        p["under"](c)
    bx, by = 57 + p["bx"], 70 + p["by"]
    b = T(bx, by, p["lean"])
    key(c, b.child(13, -13), p["keyph"])
    tail(c, b.child(19, 6, 0.25), p["flick"])
    kneel_leg(c, b.p(7, 13), far=True)
    body(c, b, crack=p["crack"])
    kneel_leg(c, b.p(-4, 14))
    hd = b.child(-10 + p["hdx"], -12 + p["hdy"], p["hang"])
    head(c, hd, beak_open=p["beak"], eye=p["eye"], helmet=p["helmet"] and p["helmet_t"] is None)
    if p["helmet"] and p["helmet_t"] is None:
        # a sardine tucked in the helmet strap, for luck
        sardine(c, T(*hd.p(-2, -33), -0.9 + p["hang"] + p["lean"], 0.45, 0.45), fins=False)
    if p["helmet_t"] is not None:
        tin_helmet(c, p["helmet_t"])
    if p["launcher"]:
        lt = launcher(c, b.child(-2, -14), p)
        target = lt.p(-3, 9)
    else:
        target = b.p(-26, -2)
    if p["held"]:
        p["held"](c)
    sh = b.p(-6, -2)
    if p["arm"] == "reach":
        target = (bx + 30, by + 4)
    dx, dy = target[0] - sh[0], target[1] - sh[1]
    ai = math.atan2(dy, dx) - math.atan2(2, -20)
    wing_arm(c, T(sh[0], sh[1]), -ai, 0.3, gun=False, fingers="fist", reach=math.hypot(dx, dy) / 20)
    for s in p["steam"]:
        steam(c, *s)
    for s in p["sweat"]:
        sweat(c, *s)
    if p["extra"]:
        p["extra"](c)
    return c.done()


def burnt(img):
    """Recolour a finished frame as soot: each pixel to one of the four smoke tones by its brightness, outlines kept."""
    out = img.copy()
    a = out[..., 3] > 0
    lum = out[..., 0] * 0.3 + out[..., 1] * 0.55 + out[..., 2] * 0.15
    tones = np.array([SMOKE[0], SMOKE[1], SMOKE[2], SMOKE[3]], np.uint8)
    idx = np.clip(((lum - 90) / 52).astype(int), 0, 3)
    dark = lum < 60
    out[a & ~dark, :3] = tones[idx[a & ~dark]]
    out[a & dark, :3] = SMOKE.ol
    return out


def frames():
    f = {}
    for i in range(4):
        f[f"idle_{i}"] = gull_bazooka(by=[0, 0.6, 1, 0.6][i], hdy=[0, 0.5, 1, 0.5][i], keyph=i * math.pi / 8,
                                      tilt=[0, 0.01, 0.02, 0.01][i], eye="closed" if i == 2 else "mean", flick=[0, 0.05, 0.1, 0.05][i])
    aims = [dict(tilt=-0.06, hdy=1, eye="look"), dict(tilt=-0.03, hdy=3, hdx=1, eye="mean", hang=0.06),
            dict(tilt=0.0, hdy=3, hdx=1, eye="mean", hang=0.06, beak=0.15)]
    for i, a in enumerate(aims):
        f[f"aim_{i}"] = gull_bazooka(keyph=i * 0.3, **a)
    fires = [dict(loaded=False, flash=1, blast=1, recoil=4, bx=2, hdy=2, hdx=2, eye="shock", beak=0.6,
                  extra=lambda c: sardine(c, T(16, 54, -0.04), flame=2)),
             dict(loaded=False, blast=2, recoil=2, bx=1, lean=0.06, hdx=3, eye="shock", beak=0.8, tilt=-0.08,
                  extra=lambda c: steam(c, 22, 58, 1, 1.4)),
             dict(loaded=False, blast=3, recoil=2, bx=1, lean=0.03, hdx=2, eye="dizzy", beak=0.3, tilt=-0.04,
                  extra=lambda c: steam(c, 20, 54, 2, 1.2)),
             dict(loaded=False, blast=4, recoil=1, bx=1, eye="look", tilt=-0.01)]
    for i, fr in enumerate(fires):
        f[f"fire_{i}"] = gull_bazooka(keyph=i * 0.5, **fr)
    # reload: reach back into the ammo can for a sardine, push it in the front, click
    can = lambda c: _ammo_can(c)  # noqa: E731
    f["reload_0"] = gull_bazooka(loaded=False, arm="reach", tilt=0.04, eye="look", hang=0.25, hdx=3, under=can)
    f["reload_1"] = gull_bazooka(loaded=False, tilt=0.06, eye="mean", hang=0.1, under=can,
                                 held=lambda c: sardine(c, T(24, 62, 0.3), fins=False, face="mean"))
    f["reload_2"] = gull_bazooka(loaded=False, tilt=0.04, eye="look", beak=0.3, under=can,
                                 held=lambda c: sardine(c, T(22, 57, 0.05), fins=False))
    f["reload_3"] = gull_bazooka(loaded=True, tilt=0.0, eye="closed", beak=0.0, under=can,
                                 extra=lambda c: star(c, 30, 46, 5, CREAM, tone=2))
    f["hit_0"] = gull_bazooka(bx=3, lean=0.12, hdx=3, hang=0.2, eye="shock", beak=0.7, tilt=-0.15, crack=1,
                              steam=((84, 54, 1),), extra=lambda c: screw(c, 92, 34, 0.5))
    f["hit_1"] = gull_bazooka(bx=1, lean=0.05, hdx=1, hang=0.1, eye="x", beak=0.3, tilt=-0.06, crack=1, steam=((86, 48, 2),))
    f.update(die())
    return f


def _ammo_can(c):
    """A tin of sardine rockets beside the gull."""
    t = T(92, GROUND - 7)
    t.poly(c, [(-9, -7), (9, -7), (9, 7), (-9, 7)], OLIVE, bulge=0.4)
    t.ell(c, 0, -7, 9, 2.2, OLIVE, tone=2)
    for x in (-5, 0, 5):
        t.ell(c, x, -8, 2, 2.2, CHROME, seam=True)
        t.px(c, x, -9, DARK)
    t.line(c, -6, 0, 6, 0, BRASS[2])
    t.line(c, -6, 2, 6, 2, BRASS[0])


def die():
    """The sardine goes off inside the tube: shock, BOOM, a sooty gull blinking, it slumps into a smoking pile."""
    f = {}
    f["die_0"] = gull_bazooka(eye="shock", beak=0.8, lean=0.08, bx=2, hang=0.2, crack=1, tilt=0.1, sweat=((44, 22),),
                              extra=lambda c: (steam(c, 86, 50, 0), steam(c, 26, 52, 0)))
    c = Canvas(W, H)
    for x, y, r in ((58, 58, 22), (40, 54, 14), (80, 52, 16), (60, 40, 15)):
        c.ell(x, y, r, r * 0.85, CREAM, rim=False)
    for x, y, r in ((58, 60, 14), (44, 54, 8), (74, 52, 9)):
        c.ell(x, y, r, r * 0.8, FIRE, rim=False)
    star(c, 58, 58, 12, FIRE, n=7, tone=3)
    for i in range(5):
        a = i * 1.26 + 0.4
        feather(c, 58 + math.cos(a) * 32, 56 + math.sin(a) * 28, a)
    f["die_1"] = c.done()
    sooty = dict(launcher=False, helmet=False, eye="closed", beak=0.4, crack=2)
    f["die_2"] = burnt(gull_bazooka(**sooty))
    f["die_3"] = _blink(burnt(gull_bazooka(**sooty, hdy=1)))
    sag = burnt(gull_bazooka(**sooty, by=6, lean=0.25, hang=0.5, hdy=3))
    f["die_4"] = sag
    for i in range(5, 8):
        c = Canvas(W, H)
        _pile(c)
        steam(c, 58 + (i - 5) * 3, 76, i - 5, 1.2)
        steam(c, 70, 80, (i - 4) % 3, 0.9)
        f[f"die_{i}"] = _pile_img(i)
    return f


def _blink(img, dx=0, dy=0):
    out = img.copy()
    for x, y in ((28 + dx, 35 + dy), (32 + dx, 35 + dy)):
        out[y:y + 2, x:x + 2] = (255, 255, 255, 255)
    return out


def _pile(c):
    """A heap of sooty parts: the body tipped over, legs sticking out, a few feathers, the bent launcher."""
    t = T(56, GROUND - 10, 0.15)
    t.ell(c, 0, 0, 18, 10, CHROME)
    t.tube(c, [(10, -4, 2), (22, -16, 2)], STEEL)
    t.tube(c, [(16, -2, 2), (30, -10, 2)], STEEL)
    webbed_foot(c, 80, 74, toe_up=-0.9)
    webbed_foot(c, 88, 78, toe_up=-1.1)
    t.ell(c, -18, 2, 9, 7, CHROME)
    feather(c, 36, 92, 0.3)
    feather(c, 74, 94, -0.4)


def _pile_img(i):
    c = Canvas(W, H)
    _pile(c)
    pile = burnt(c.done())
    c2 = Canvas(W, H)
    k = i - 5
    steam(c2, 54 + k * 2, 80, k, 1.3)
    steam(c2, 66 - k, 84, (k + 1) % 3, 0.9)
    lc = Canvas(W, H)
    launcher_bent(lc)
    out = overlay(pile, lc.done())
    return overlay(out, c2.done())


def launcher_bent(c):
    t = T(30, GROUND - 8, 0.08)
    t.tube(c, [(-14, 0, 4.5), (0, -2, 4.5), (12, 3, 4.5)], OLIVE)
    t.ell(c, -15, 0, 2, 5, STEEL)


def build():
    s = Sheet("gull_bazooka", W, H, [56, 102], faces="left",
              notes="fire_0 shows the sardine leaving the muzzle (the game may spawn rocket from the muzzle at about x=10, y=54)")
    order = ([f"idle_{i}" for i in range(4)] + [f"aim_{i}" for i in range(3)] + [f"fire_{i}" for i in range(4)] +
             [f"reload_{i}" for i in range(4)] + [f"die_{i}" for i in range(8)] + ["hit_0", "hit_1"])
    fr = frames()
    for n in order:
        s.add(n, fr[n])
    s.save()
    return fr


if __name__ == "__main__":
    build()
