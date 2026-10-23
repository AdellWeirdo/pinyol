"""Paella de Combate: the Tractor-Cañón animation tables -> art/tractor.png + .json."""
from __future__ import annotations

import math

from art_bigs_kit import FIRE, IRON, RED, SMOKE, STEEL, WOOD, Canvas, Xf, rad, rng, save_sheet
from art_bigs_tractor import (ANCHOR, FRONT, H, REAR, W, cannon, draw, flame, pan_shield, pivot_xf, puff, sparks,
                              star_flash, wheel)

EX = (176, 47)  # exhaust mouth


def flash(c: Canvas):
    """Hit flash: every tone jumps to its ramp's highlight, outlines stay."""
    for name in set(c.p.flatten()):
        if not name or name[-1] == "0" or not name[-1].isdigit():
            continue
        base = name.rstrip("0123456789")
        top = next((f"{base}{k}" for k in (4, 3) if f"{base}{k}" in _PAL), None)
        if top:
            c.p[c.p == name] = top


from art_bigs_kit import PAL as _PAL  # noqa: E402


def exhaust_puffs(k, n, drift=1.0, dark=False, big=1.0):
    """Puffs rising from the exhaust; k = frame, n = loop length."""
    out = []
    for j in range(2):
        t = ((k + j * n / 2) % n) / n
        out.append((EX[0] - t * 14 * drift, EX[1] - 3 - t * 22, (2.5 + t * 5) * big, dark))
    return out


def burning_fx(k, seed):
    def fx(c):
        for i, (x, y, s) in enumerate(((118, 84, 20), (142, 82, 28), (164, 84, 19), (102, 96, 12))):
            f = s * (0.8 + 0.25 * math.sin(k * 1.9 + i * 2.1))
            flame(c, x, y, f, -90 + 8 * math.sin(k * 1.3 + i), seed + i * 7 + k, layers=3)
        sparks(c, 140, 70, 4, 22, seed + k)
    return fx


def frames_basic():
    fr = []
    # idle: the engine shakes, the exhaust coughs, the bell trembles
    for k in range(4):
        fr.append((f"idle_{k}", dict(dy=(0, -1, 0, -1)[k], dx=(0, 0, 0.6, 0)[k], flap=(35, 10, 0, 0)[k],
                                      swing=(0, 4, 1, -3)[k], puffs=exhaust_puffs(k, 4), sink=(0, 0.6, 0, 0.6)[k])))
    # drive: wheels turn, the body bobs on the bumps, the bell swings back
    for k in range(8):
        fr.append((f"drive_{k}", dict(rear=k * 11.25, front=k * 22.5, dy=(0, -1, -2, -1, 0, -1, -1, 0)[k],
                                       tilt=(0, -0.6, -0.8, 0, 0.6, 0.6, 0, 0)[k], swing=10 + 5 * math.sin(k * math.pi / 2),
                                       flap=(30, 15, 0, 0, 30, 15, 0, 0)[k], sink=(0, 0.8, 1.4, 0.8, 0, 0.8, 1.2, 0.4)[k],
                                       puffs=exhaust_puffs(k, 4, drift=2.2))))
    # jump: squash, rise (nose up), fall (nose down), land (squash + dust)
    dust = [(REAR[0] - 28, 134, 6, "dust"), (REAR[0] + 24, 135, 5, "dust"), (FRONT[0] + 20, 135, 4, "dust")]
    js = [dict(dy=4, sq=0.94, sink=3, swing=-6),
          dict(dy=-5, tilt=-6, rigid=True, sq=1.03, sink=-1, swing=14, flap=40),
          dict(dy=-3, tilt=5, rigid=True, sink=-2, swing=-12, flap=10),
          dict(dy=5, sq=0.92, sink=4, swing=6, puffs=dust)]
    for k, d in enumerate(js):
        fr.append((f"jump_{k}", d))
    for k in range(3):
        fr.append((f"crouch_{k}", dict(dy=(2, 4, 5)[k], sq=(0.98, 0.95, 0.94)[k], sink=(1, 2, 3)[k], swing=(3, 5, 2)[k])))
    # fire: the sardine cannon kicks the whole tractor back
    fire = [dict(recoil=7, flame=(32, 3), tilt=-2.5, dx=-2, swing=12, puffs=[]),
            dict(recoil=5, flame=(20, 8), tilt=-1.2, dx=-1, swing=8, puffs=[(203, 66, 6, False)]),
            dict(recoil=2, tilt=-0.4, swing=2, puffs=[(206, 64, 8, False), (196, 60, 5, False)]),
            dict(recoil=0, swing=-2, puffs=[(209, 60, 7, False), (201, 54, 4, False)])]
    for k, d in enumerate(fire):
        fr.append((f"fire_{k}", d))
    for k in range(2):
        fr.append((f"vulcan_{k}", dict(spin=k, vflash=(9, 6)[k], dx=(-1, 0)[k], recoil=(1, 0)[k])))
    for k in range(3):
        fr.append((f"cannon_up_{k}", dict(ang=(24, 48, 70)[k], swing=(2, 3, 1)[k])))
    for k in range(3):
        fr.append((f"cannon_down_{k}", dict(ang=(-7, -14, -20)[k])))
    fr.append(("hit_0", dict(dx=-2, tilt=-1, swing=10, flash=True)))
    fr.append(("hit_1", dict(dx=2, tilt=1, swing=-8, fx=lambda c: sparks(c, 150, 86, 7, 16, 5))))
    for k in range(4):
        fr.append((f"damaged_idle_{k}", dict(dmg=1, dy=(0, -1, 0, 0)[k], dx=(0, 0.6, -0.6, 0)[k], tilt=(0, 0.5, 0, -0.4)[k],
                                              hang=(1, 3, 1, -1)[k], swing=(0, 4, 0, -4)[k],
                                              puffs=exhaust_puffs(k, 4, dark=True) + [
                                                  (150 - k * 2, 76 - k * 5, 4 + k, True), (136 - (k + 2) % 4 * 2, 74 - (k + 2) % 4 * 5, 3 + (k + 2) % 4, True)])))
    for k in range(6):
        fr.append((f"burning_{k}", dict(dmg=2, tilt=(1.5, -1, 2, -1.5, 1, -2)[k], dx=(1, -1, 0, 1, -1, 0)[k], dy=(0, -1, 0, -1, 0, -1)[k],
                                         hang=(2, -2, 3, -1, 1, -3)[k], swing=(8, -8, 6, -6, 9, -9)[k],
                                         back_puffs=[(150 - ((k + j * 2) % 6) * 4, 62 - ((k + j * 2) % 6) * 9, 7 + ((k + j * 2) % 6) * 1.3, True) for j in range(3)],
                                         fx=burning_fx(k, 30))))
    enter = [dict(), dict(swing=2), dict(dy=3, tilt=-2.5, sink=5, swing=14, sq=0.96), dict(dy=-2, tilt=1, sink=-1, swing=-10, sq=1.02),
             dict(dy=1, tilt=-0.5, sink=1, swing=6), dict(swing=-2)]
    for k, d in enumerate(enter):
        fr.append((f"enter_{k}", d))
    exit_ = [dict(), dict(dy=2, tilt=-1.5, sink=3, swing=6, sq=0.97), dict(dy=-3, tilt=2, sink=-2, swing=-12, sq=1.02),
             dict(dy=0, tilt=-1.5, sink=0, swing=8), dict(tilt=0.7, swing=-4), dict(swing=1)]
    for k, d in enumerate(exit_):
        fr.append((f"exit_{k}", d))
    return fr


# ------------------------------------------------------------------ the big comic explosion

def fireball(c, x, y, r, seed, smoky=0.0):
    """Blobs of fire (and smoke as it cools), flattened on the ground line."""
    import numpy as np
    ground = np.zeros((c.h, c.w), bool)
    ground[:141] = True
    g = rng(seed)
    blobs = [(x + g.uniform(-0.5, 0.5) * r, y + g.uniform(-0.4, 0.4) * r, r * g.uniform(0.45, 0.7)) for _ in range(6)]
    if smoky > 0:
        for bx_, by_, br in blobs:
            puff(c, bx_ - 2, by_ - 6 - smoky * 8, br * (1 + smoky * 0.2), seed=int(bx_ + by_), dark=smoky > 0.4)
    for i, tone in enumerate((1, 2, 3, 4)):
        k = 1 - i * 0.2 - smoky * 0.3
        if k <= 0.15:
            break
        for bx_, by_, br in blobs:
            w = rng(int(bx_ * 3 + i)).uniform(0, 6)
            c.ellipse(bx_, by_, br * k, br * k * 0.9, FIRE, tone=tone, seam=(i == 0), wob=_wob(w), clip=ground)


def _wob(ph):
    return lambda a: 1 + 0.16 * math.cos(6 * a + ph) + 0.06 * math.cos(11 * a + ph * 2)


def wreck(c: Canvas, smoke_k=0, spring=0.0):
    """The charred chassis left behind."""
    c.tube([(58, 128, 3), (176, 132, 3)], IRON, bias=-0.2)
    c.rect(96, 120, 160, 132, IRON, mode="cyly", bias=-0.3)
    for x in range(104, 156, 10):
        c.ellipse(x, 125, 3, 3, IRON, tone=0)
    c.poly([(98, 112), (130, 108), (150, 112), (158, 120), (100, 121)], IRON, mode="dome", bias=-0.2)
    c.lline(Xf(), 105, 114, 120, 111, FIRE[1])
    c.tube([(92, 124, 1.6), (90, 104, 1.4), (82, 98, 1.4)], IRON)
    # the seat on its spring, boinging
    for i in range(5):
        y = 126 - i * (3.2 + spring)
        c.tube([(66, y, 1.2), (76, y - 0.8, 1.2)], STEEL, tone=2)
    top = 126 - 5 * (3.2 + spring)
    c.poly([(58, top - 3), (84, top - 4), (86, top), (60, top + 2)], IRON, mode="cyly")
    c.ellipse(64, 133, 6, 4, IRON, tone=1)


def piece_pan(c, x, y, ang):
    pan_shield(c, Xf(), xf_override=Xf(x, y, rad(ang), 0.8, 0.8))


def piece_cannon(c, x, y, ang):
    cannon(c, pivot_xf(128, 74, rad(ang), x - 128, y - 74, 0.85, 0.85))


def piece_plank(c, x, y, ang, seed):
    xf = Xf(x, y, rad(ang))
    c.rect(-9, -2.5, 9, 2.5, WOOD, xf=xf, normal=(0, -0.5))
    c.rivet(-7, -1, STEEL, xf=xf)


def piece_fish(c, x, y, ang):
    xf = Xf(x, y, rad(ang))
    c.ellipse(0, 0, 7, 3, STEEL, xf=xf)
    c.poly([(-6, 0), (-12, -4), (-10, 0), (-12, 4)], STEEL, xf=xf)
    c.px(*xf.pt(4, -1), "ink")


def _path(t, keys):
    """Piecewise-linear interpolation of keyframes [(t, x, y, ang), ...]."""
    for (t0, *a), (t1, *b) in zip(keys, keys[1:]):
        if t0 <= t <= t1:
            u = (t - t0) / (t1 - t0)
            return [p + (q - p) * u for p, q in zip(a, b)]
    return list(keys[-1][1:]) if t > keys[-1][0] else list(keys[0][1:])


def _arc(t0, t1, x0, y0, x1, y1, peak, a0, a1, n=6):
    """Keyframes along a parabola from (x0, y0) at t0 to (x1, y1) at t1 reaching y = peak."""
    ks = []
    for i in range(n + 1):
        u = i / n
        x = x0 + (x1 - x0) * u
        lin = y0 + (y1 - y0) * u
        top = min(y0, y1) - peak
        y = lin - 4 * top * u * (1 - u)
        ks.append((t0 + (t1 - t0) * u, x, y, a0 + (a1 - a0) * u))
    return ks


REAR_K = _arc(0, 5, REAR[0], REAR[1], 46, REAR[1], 66, 0, -400) + [(6, 40, 100, -440), (7, 36, REAR[1], -470),
                                                                   (8, 35, REAR[1] - 2, -478), (9, 35, REAR[1], -480)]
FRONT_K = _arc(0, 4, FRONT[0], FRONT[1], 186, FRONT[1], 70, 0, 520) + [(5, 184, 108, 560), (6, 181, FRONT[1], 590),
                                                                     (7, 180, FRONT[1], 600)]
PAN_K = _arc(1, 8, 197, 107, 128, 104, 92, 0, 810)
CAN_K = _arc(1, 7, 128, 70, 190, 74, 72, 0, -270) + [(8, 190, 74, -282), (9, 190, 74, -262), (10, 190, 74, -274), (11, 190, 74, -270)]
FISH_K = _arc(2, 10, 150, 80, 76, 98, 70, 0, 270)


def frames_explode():
    out = []
    sx, sy = 112, 90
    for k in range(12):
        if k == 0:
            out.append(("explode_0", dict(dx=0, dy=-1, sq=1.04, flash=True, swing=14, fx=lambda c: star_flash(c, 140, 92, 26, 10, 9, 1))))
            continue
        c = Canvas(W, H)
        t = k
        if t >= 3:   # the smoke column behind everything, rising and thinning
            for j in range(4):
                life = (t - 3) / 8
                r = (13 + 10 * life) * (1 - max(0.0, life - 0.6) * 1.6)
                puff(c, 68 + j * 28 + (j - 1.5) * life * 10, 96 - life * 50 - (j % 2) * 8, r, seed=j * 31 + t, dark=t < 8)
        if t >= 2:
            wreck(c, spring=(0, 0, 0, 3, 5, 1, -1, 2, 0.5, -0.5, 0.6, 0)[k])
        x, y, a = _path(t, REAR_K)
        wheel(c, x, y, REAR[2], a)
        x, y, a = _path(t, FRONT_K)
        wheel(c, x, y, FRONT[2], a, big=False)
        if t >= 8:   # the pan lands on the wreck like a lid and wobbles flat
            x, y = 126, 104
            ang = 90 + (8, -5, 3, 0)[t - 8]
        else:
            x, y, ang = _path(t, PAN_K)
        piece_pan(c, x, y, ang)
        x, y, a = _path(t, CAN_K)
        piece_cannon(c, x, y, a)
        if 2 <= t <= 7:
            piece_plank(c, 140 - 6 * t, 90 - 14 * t + 2.2 * t * t, 70 * t, t)
            piece_plank(c, 100 + 9 * t, 96 - 12 * t + 1.8 * t * t, -50 * t, t + 1)
        if t >= 2:
            x, y, a = _path(t, FISH_K)
            piece_fish(c, x, y, a)
        if t <= 7:
            r = (0, 30, 50, 56, 52, 44, 34, 22)[t]
            fireball(c, sx, sy, r, 100 + t, smoky=max(0.0, (t - 3) / 5))
        if t == 1:
            star_flash(c, sx, sy - 4, 44, 0, 12, 4)
            sparks(c, sx, sy - 6, 16, 44, 9)
        if 2 <= t <= 4:
            sparks(c, sx, sy - 14, 10, 44, 11 + t)
        if t >= 9:
            puff(c, 118 + (t - 9) * 2, 92 - (t - 9) * 7, 5 - (t - 9) * 1.2, seed=t, dark=False)
        out.append((f"explode_{k}", dict(canvas=c)))
    return out


def build():
    frames = frames_basic() + frames_explode()
    order = ["idle", "drive", "jump", "crouch", "fire", "vulcan", "cannon_up", "cannon_down", "hit", "damaged_idle",
             "burning", "explode", "enter", "exit"]
    frames.sort(key=lambda f: order.index(f[0].rsplit("_", 1)[0]))
    out, mc, mv, seats = [], {}, {}, {}
    for name, st in frames:
        if "canvas" in st:
            out.append((name, st["canvas"]))
            continue
        c, info = draw(st)
        if st.get("flash"):
            flash(c)
        if st.get("fx") and st.get("flash"):
            st["fx"](c)
        out.append((name, c))
        mc[name], mv[name], seats[name] = list(info["cannon"]), list(info["vulcan"]), list(info["seat"])
    rest = draw({})[1]
    extras = {"faces": "right", "muzzle_cannon": mc, "muzzle_vulcan": mv, "seat": list(rest["seat"]),
              "seat_frames": seats,
              "notes": "seat = top centre of the empty cushion (the seated chef's pin); seat_frames gives it per frame "
                       "so the chef bounces with the suspension. Muzzles are the barrel mouths per frame."}
    n = save_sheet("tractor", out, W, H, ANCHOR, extras)
    print("tractor", len(out), "frames,", n, "colours")


if __name__ == "__main__":
    build()
