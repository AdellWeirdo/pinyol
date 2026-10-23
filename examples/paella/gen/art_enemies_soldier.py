"""Paella de Combate: gull_soldier (112x104, anchor [56, 102], faces left). Run through gen/art_enemies.py."""
from __future__ import annotations

import math

from enemies_kit import CHROME, CREAM, OLIVE, STEEL, Canvas, Sheet
from gull_parts import (T, body, far_wing, feather, head, key, leg, pea_pistol, screw, star, steam, sweat, tail, tin_helmet,
                        wing_arm)
from enemies_kit import ORANGE, SMOKE, FIRE

W, H = 112, 104
GROUND = 101

BASE = dict(bx=0.0, by=0.0, lean=0.0, sx=1.0, sy=1.0, hdx=0.0, hdy=0.0, hang=0.0, beak=0.0, eye="mean", helmet=True,
            aim=0.0, bend=0.6, gun=True, flash=0, fingers="grip", far_ang=0.0, far_spread=0.0,
            feet=((50.0, GROUND), (63.0, GROUND)), toe=(0.0, 0.0), keyph=0.0, flick=0.0, crack=0, steam=(), sweat=(),
            sock=False, reach=1.0, arm=True, legs=True, yell=False, extra=None, under=None, helmet_t=None)


def gull_soldier(**kw):
    p = dict(BASE)
    p.update(kw)
    c = Canvas(W, H)
    if p["under"]:
        p["under"](c)
    bx, by = 62 + p["bx"], 56 + p["by"]
    b = T(bx, by, p["lean"], p["sx"], p["sy"])
    far_wing(c, b.child(4, -6), p["far_ang"], p["far_spread"])
    key(c, b.child(13, -13), p["keyph"], sock=p["sock"])
    tail(c, b.child(19, 6), p["flick"])
    hips = (b.p(-4, 15), b.p(7, 14))
    if p["legs"]:
        leg(c, hips[1], p["feet"][1], far=True, toe_up=p["toe"][1])
    body(c, b, crack=p["crack"])
    if p["legs"]:
        leg(c, hips[0], p["feet"][0], toe_up=p["toe"][0])
    hd = b.child(-10 + p["hdx"], -12 + p["hdy"], p["hang"])
    head(c, hd, beak_open=p["beak"], eye=p["eye"], helmet=p["helmet"] and p["helmet_t"] is None, yell=p["yell"])
    if p["helmet_t"] is not None:
        tin_helmet(c, p["helmet_t"])
    if p["arm"]:
        wing_arm(c, b.child(-6, -2), p["aim"], p["bend"], p["gun"], p["flash"], p["fingers"], p["reach"])
    for s in p["steam"]:
        steam(c, *s)
    for s in p["sweat"]:
        sweat(c, *s)
    if p["extra"]:
        p["extra"](c)
    return c.done()


def walk_feet(ph):
    """Foot (x, y) for a cycle phase 0..1: stance slides back (right), swing comes forward lifted."""
    if ph < 0.5:
        x = 46 + 18 * (ph / 0.5)
        return (x, GROUND), 0.0
    q = (ph - 0.5) / 0.5
    return (64 - 18 * q, GROUND - 7 * math.sin(math.pi * q)), 0.35 * math.sin(math.pi * q)


def frames():
    f = {}
    # idle: breathing, the key turns slowly, a blink on the last frame, the tail flicks
    for i in range(4):
        f[f"idle_{i}"] = gull_soldier(by=[0, 0.6, 1.2, 0.6][i], hdy=[0, 0.4, 1, 0.4][i], keyph=i * math.pi / 8,
                                      flick=[0, 0, 0.12, 0.05][i], eye="closed" if i == 3 else "mean", aim=[0, 0.03, 0.06, 0.03][i])
    # walk: pigeon head-bob, the key turns, arm swings a little
    for i in range(8):
        ph = i / 8
        (f0, t0), (f1, t1) = walk_feet(ph), walk_feet((ph + 0.5) % 1)
        bob = math.cos(ph * 4 * math.pi)
        f[f"walk_{i}"] = gull_soldier(feet=(f0, f1), toe=(t0, t1), by=1.2 * bob - 0.6, bx=-1, lean=-0.05,
                                      hdx=[-3, -1, 1, 0, -3, -1, 1, 0][i], hdy=[0, -1, 0, 0, 0, -1, 0, 0][i],
                                      keyph=i * math.pi / 4, aim=0.08 * math.sin(ph * 2 * math.pi), flick=0.06 * bob)
    # shoot: aim, BANG (beak open, flash, recoil), recoil, settle
    sh = [dict(aim=-0.05, bend=0.2, hdx=-1),
          dict(aim=-0.12, bend=0.15, flash=1, beak=0.5, yell=True, lean=0.05, bx=1, hdx=0, eye="mean"),
          dict(aim=-0.25, bend=0.5, flash=2, lean=0.06, bx=2, hdx=1, beak=0.2),
          dict(aim=-0.08, bend=0.35, lean=0.02, bx=1)]
    for i, s in enumerate(sh):
        f[f"shoot_{i}"] = gull_soldier(keyph=i * 0.4, **s)
    # peck: rear back, lunge with the beak, SNAP, recover
    pk = [dict(lean=0.18, bx=3, hdx=4, hdy=-2, hang=0.2, beak=0.7, aim=-0.5, bend=1.0, eye="mean", feet=((48, GROUND), (64, GROUND))),
          dict(lean=-0.3, bx=-4, by=4, hdx=-2, hdy=1, hang=0.22, beak=0.9, aim=0.3, bend=0.8, feet=((44, GROUND), (62, GROUND)), toe=(0, 0.4)),
          dict(lean=-0.36, bx=-5, by=5, hdx=-1, hdy=1, hang=0.3, beak=0.0, aim=0.4, bend=0.8, feet=((44, GROUND), (62, GROUND)),
               toe=(0, 0.5), extra=lambda c: star(c, 16, 50, 6, CREAM)),
          dict(lean=-0.1, bx=-2, by=1, hdx=-3, beak=0.2, aim=0.1, feet=((47, GROUND), (64, GROUND)))]
    for i, s in enumerate(pk):
        f[f"peck_{i}"] = gull_soldier(keyph=i * 0.5, **s)
    # hit: knocked back, shocked, a puff of steam and a rivet popping
    f["hit_0"] = gull_soldier(lean=0.18, bx=4, by=1, hdx=4, hang=0.25, eye="shock", beak=0.6, aim=-0.4, bend=1.0, crack=1,
                              steam=((80, 44, 1),), feet=((52, GROUND), (65, GROUND)), helmet=True,
                              extra=lambda c: screw(c, 88, 30, 0.6))
    f["hit_1"] = gull_soldier(lean=0.08, bx=2, hdx=2, hang=0.1, eye="x", beak=0.3, aim=-0.2, bend=0.8, crack=1,
                              steam=((82, 40, 2),), extra=lambda c: screw(c, 94, 22, 1.8))
    # jump back: crouch, push off (legs long), tucked in the air flapping, land
    f["jump_0"] = gull_soldier(by=6, lean=0.1, hdy=2, feet=((48, GROUND), (64, GROUND)), aim=0.3, bend=1.0, eye="look")
    f["jump_1"] = gull_soldier(by=-3, bx=4, lean=0.2, hdx=2, hang=0.15, feet=((52, GROUND), (63, GROUND - 2)), toe=(0.5, 0.6),
                               far_ang=-0.9, far_spread=1, aim=-0.6, bend=0.9, eye="shock", beak=0.5)
    f["jump_2"] = gull_soldier(by=-4, bx=6, lean=0.25, hdx=2, hang=0.2, feet=((60, GROUND - 14), (70, GROUND - 13)), toe=(0.6, 0.8),
                               far_ang=-1.6, far_spread=1, aim=-0.9, bend=0.8, eye="shock", beak=0.7, yell=True)
    f["jump_3"] = gull_soldier(by=4, bx=2, lean=0.05, hdy=1, feet=((50, GROUND), (63, GROUND)), far_ang=-0.4, aim=0.2, bend=1.0,
                               steam=((44, 98, 0, 0.8), (72, 98, 0, 0.8)))
    f.update(die_a())
    f.update(die_b())
    f.update(surrender())
    return f


def _flying_parts(c, k):
    """die_a debris at age k (0..1): screws and feathers burst outwards from the body centre."""
    rng = [(-1.0, -0.8, 0.2), (1.1, -0.6, 1.4), (-0.6, -1.2, 2.2), (0.8, -1.1, 0.9), (-1.3, -0.2, 2.7),
           (1.3, 0.1, 0.4), (0.2, -1.4, 1.9), (-0.2, -0.9, 3.1), (0.6, -0.4, 2.5)]
    for i, (vx, vy, a) in enumerate(rng):
        x = 60 + vx * 46 * k
        y = 52 + vy * 46 * k + 50 * k * k
        if 10 < x < W - 10 and 10 < y < GROUND - 8:
            if i % 3 == 0:
                screw(c, x, y, a + k * 6)
            else:
                feather(c, x, y, a + k * 3, 1.0, CHROME if i % 2 else STEEL)


def die_a():
    """Flies apart: shock, swells with cracks, BURST (cloud of feathers and screws), the helmet spins off, a pile."""
    f = {}
    f["die_a_0"] = gull_soldier(eye="shock", beak=0.8, yell=True, lean=0.12, bx=2, hang=0.2, aim=-0.6, bend=1.0, crack=1,
                                steam=((80, 42, 0), (40, 60, 1)))
    f["die_a_1"] = gull_soldier(eye="x", beak=0.4, lean=0.05, sx=1.12, sy=1.1, bx=1, crack=2, aim=-1.0, bend=1.0,
                                steam=((82, 36, 1), (36, 56, 1), (70, 76, 0)), helmet=False,
                                helmet_t=T(50, 14, -0.3))
    # 2..7: the body has gone; a cloud of feathers and gears, the helmet spinning up and away
    for i in range(2, 8):
        k = (i - 2) / 5
        c = Canvas(W, H)
        if i <= 4:
            r = [26, 30, 24][i - 2]
            _poof(c, 60, 58 - (i - 2) * 3, r, i - 2)
        _flying_parts(c, 0.25 + k * 0.75)
        hx_, hy_ = 54 + 30 * k, 8 + 70 * k * k - 10 * k
        if i < 7:
            tin_helmet(c, T(hx_, max(18, hy_), [0.5, -0.4, 0.9, 3.0, 2.2][i - 2]))
        else:
            tin_helmet(c, T(70, GROUND - 10, 3.14))  # it lands upside down, rocking
        if i >= 5:  # the legs are left standing for a beat, then topple
            fall = (i - 5) * 0.6
            lc = T(56, GROUND - 4, fall)
            lc.tube(c, [(0, -26, 5), (4, -12, 3.5)], CHROME)
            lc.tube(c, [(4, -12, 2.4), (0, 0, 2.0)], STEEL)
            lc.poly(c, [(1, -1), (-12, 2.5), (-11, 4), (3, 4)], ORANGE)
        f[f"die_a_{i}"] = c.done()
    return f


def _poof(c, x, y, r, k):
    """A chunky cloud of the shared explosion painter with feathers in it (k = 0 fresh fire .. 2 thinning smoke)."""
    from fx_parts import boom, cloud_lobes, paint_cloud
    if k == 0:
        boom(c, x, y, r, 0.3, seed=17, n=7, embers=False)
    else:
        lobes = [(lx, ly - k * 3, lr * (1.0 if k == 1 else 0.7), life) for lx, ly, lr, life in cloud_lobes(17, 7, r)]
        paint_cloud(c, x, y, lobes, 0.0, 5.0, CREAM if k == 1 else SMOKE)
    for j in range(3 - k):
        a = j * 2.1 + k
        feather(c, x + math.cos(a) * r * 0.7, y + math.sin(a) * r * 0.6, a)


def die_b():
    """Flattened: squash, a pancake with eyes, it peels up as a flat cardboard gull (a feather duster), wobbles, poof."""
    f = {}
    f["die_b_0"] = gull_soldier(sy=0.72, sx=1.15, by=10, eye="shock", beak=0.6, hdy=4, aim=0.2, bend=1.0,
                                feet=((44, GROUND), (68, GROUND)), legs=True)
    pan = dict(sy=0.22, sx=1.12, by=33, eye="x", legs=False, arm=False, hdy=0)
    f["die_b_1"] = gull_soldier(**pan, extra=lambda c: _feet_flat(c))
    f["die_b_2"] = gull_soldier(**pan, extra=lambda c: (_feet_flat(c), star(c, 40, 76, 4, CREAM, tone=2), star(c, 76, 72, 3, CREAM, tone=2)))
    # popping back up: paper-thin (sx tiny), with a crown of ruffled feathers like a feather duster
    for i, (sx, ang, tag) in enumerate(((0.35, 0.0, 3), (0.28, -0.18, 4), (0.28, 0.2, 5))):
        c_img = gull_soldier(sx=sx, sy=1.05, by=-2, eye="dizzy", legs=False, arm=False, lean=ang,
                             under=lambda c, a=ang: _duster(c, a))
        f[f"die_b_{tag}"] = c_img
    for i in (6, 7):
        c = Canvas(W, H)
        _poof(c, 58, 60 - (i - 6) * 6, 24 if i == 6 else 18, 1 if i == 6 else 2)
        if i == 7:
            for j in range(4):
                feather(c, 30 + j * 16, 80 + (j % 2) * 8, j * 0.9)
        f[f"die_b_{i}"] = c.done()
    return f


def _feet_flat(c):
    for x in (36, 70):
        T(x, GROUND - 3).poly(c, [(1, -1), (-12, 1.5), (-11, 3), (3, 3)], ORANGE)


def _duster(c, ang):
    """A fan of ruffled feathers bursting out round the head and a tuft at the tail: the flat gull is a feather duster."""
    t = T(62, 40, ang)
    for i in range(9):
        a = -math.pi / 2 + (i - 4) * 0.36
        r = 20 + (i % 2) * 5
        feather(c, *t.p(math.cos(a) * r, math.sin(a) * r * 0.9 + 4), a + ang, 1.25, CHROME if i % 2 else STEEL)


def surrender():
    """Drops the gun, wings up, a white sock flag tied to the key; trembling and sweating."""
    f = {}
    def dropped_gun(y, a):
        return lambda c: pea_pistol(c, T(30, y, a))
    f["surrender_0"] = gull_soldier(arm=True, gun=False, fingers="splay", aim=-1.2, bend=0.2, far_ang=0.6, reach=1.7, eye="shock",
                                    beak=0.5, yell=True, lean=0.05, sock=True, extra=dropped_gun(74, 0.8))
    for i in range(1, 4):
        jit = [0, 1, -1][i - 1]
        f[f"surrender_{i}"] = gull_soldier(arm=True, gun=False, fingers="splay", aim=-1.42 + 0.06 * jit, bend=0.0, reach=1.85, lean=0.08, hang=0.12,
                                           far_ang=0.7 + 0.06 * jit, far_spread=1, eye="worried", beak=0.25, bx=jit * 0.8,
                                           by=0.5 * abs(jit), sock=True, keyph=i * 0.3,
                                           sweat=((40, 18 + i, ), (78, 22 + (i % 2) * 2)),
                                           extra=lambda c: pea_pistol(c, T(30, GROUND - 9, 0.0)))
    return f


def build():
    s = Sheet("gull_soldier", W, H, [56, 102], faces="left",
              notes="jump_* is a pose only: the game moves the gull back; the gun lies on the ground in surrender_1..3")
    order = ([f"idle_{i}" for i in range(4)] + [f"walk_{i}" for i in range(8)] + [f"shoot_{i}" for i in range(4)] +
             [f"peck_{i}" for i in range(4)] + ["hit_0", "hit_1"] + [f"jump_{i}" for i in range(4)] +
             [f"die_a_{i}" for i in range(8)] + [f"die_b_{i}" for i in range(8)] + [f"surrender_{i}" for i in range(4)])
    fr = frames()
    for n in order:
        s.add(n, fr[n])
    s.save()
    return fr


if __name__ == "__main__":
    build()
