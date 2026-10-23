"""Paella de Combate: the prisoners `grandma` and `fisherman` (96x104, anchor [48, 102], face left).

Same frame names for both: tied_0..5, free_0..3, give_0..5, run_0..7, salute_0..3.
"""
from __future__ import annotations

import math

from enemies_kit import (BRASS, CHROME, CREAM, FLESH, GREEN, NAVY, SEA, STEEL, VISOR, WOOD, YELLOW, Canvas, Ramp, Sheet,
                         rot)
from gull_parts import DARK, WHITE, T, sweat
from person_parts import (DARKCLOTH, ROPE, anger_mark, arm, eyes_face, heart, leg, shout, weapon_crate)

W, H = 96, 104
GROUND = 101
MAUVE = Ramp("#4a2448", "#7a3c74", "#a8649c", "#d8a0cc", ol="#24102a")


# ------------------------------------------------------------------ shared bits
def rope_band(c, a, b, sag=2.0):
    mx, my = (a[0] + b[0]) / 2, (a[1] + b[1]) / 2 + sag
    c.tube([(a[0], a[1], 1.6), (mx, my, 1.8), (b[0], b[1], 1.6)], ROPE)
    for t in (0.25, 0.5, 0.75):
        x = a[0] + (b[0] - a[0]) * t
        y = a[1] + (b[1] - a[1]) * t + sag * math.sin(math.pi * t)
        c.px(x, y - 1, ROPE[0])


def rope_bits(c, cx, cy, k):
    """Snapped rope pieces flying out (k = age)."""
    for i, (vx, vy) in enumerate(((-1, -1.2), (1.1, -0.9), (-1.3, 0.2), (1.2, 0.4), (0.2, -1.4))):
        x, y = cx + vx * 20 * k, cy + vy * 20 * k + 14 * k * k
        a = i * 1.3 + k * 4
        c.tube([(x - 3 * math.cos(a), y - 3 * math.sin(a), 1.4), (x + 3 * math.cos(a), y + 3 * math.sin(a), 1.4)], ROPE)


def beak_clamp(c, h: T):
    """The mechanical gull-beak muzzle clamped over the mouth, strapped round the head."""
    h.line(c, -3, 4, 10, 2, STEEL[1])
    h.line(c, -3, 5, 10, 3, STEEL[0])
    h.tube(c, [(-5, 4, 3.4), (-13, 5, 2.4), (-17, 7, 1.2)], BRASS)
    h.tube(c, [(-5, 7, 2.2), (-12, 8, 1.4)], BRASS, bias=-0.2)
    h.px(c, -8, 3, BRASS[3])
    h.px(c, -6, 4, STEEL[0])


def mouth(c, h: T, kind):
    if kind == "smile":
        h.line(c, -8, 5, -4, 6, DARK)
        h.px(c, -9, 4, DARK)
    elif kind == "open":
        h.ell(c, -6, 6, 2.6, 2.2, VISOR, tone=0, seam=False)
        h.px(c, -6, 7, VISOR[2])
    elif kind == "grin":
        h.ell(c, -6, 5.5, 3.4, 2.0, VISOR, tone=0, seam=False)
        h.line(c, -9, 5, -3, 5, WHITE)
    elif kind == "frown":
        h.line(c, -8, 6, -4, 5, DARK)
    elif kind == "clamp":
        beak_clamp(c, h)


# ------------------------------------------------------------------ grandma
def granny_head(c, h: T, mood="plain", mth="smile"):
    # headscarf behind the head and its knot under the chin
    h.ell(c, 3, -1, 12, 12.5, NAVY)
    h.ell(c, -1, 1, 11, 11, FLESH, seam=True)
    # grey curls peeking out under the scarf
    for x, y in ((-9, -6), (-5, -8)):
        h.ell(c, x, y, 2.4, 2.1, CHROME, seam=False)
    h.poly(c, [(-8, -9), (-2, -13), (6, -13), (13, -7), (14, 4), (9, 10), (6, 2), (3, -7), (-3, -9)], NAVY,
           bulge=0.6, center=(5, -4))
    for x, y in ((2, -11), (9, -8), (11, -1), (8, 4)):
        h.px(c, x, y, CREAM[2])
    h.poly(c, [(6, 8), (12, 9), (11, 13), (6, 12)], NAVY, bulge=0.4)  # knot tail
    # big round nose, blush, eyes, mouth
    h.ell(c, -11, 2, 3.0, 2.8, FLESH)
    h.px(c, -12, 1, FLESH[3])
    h.px(c, -3, 3, (240, 122, 122))
    h.px(c, -2, 3, (240, 122, 122))
    eyes_face(c, h, mood, glasses=True)
    mouth(c, h, mth)


def trolley(c, x, y, tilt=0.0):
    """The tartan shopping trolley (pivot = wheel axle)."""
    t = T(x, y, tilt)
    t.tube(c, [(4, -6, 1.6), (6, -44, 1.6)], STEEL)
    t.tube(c, [(2, -44, 1.8), (9, -45, 1.8)], DARKCLOTH)
    t.poly(c, [(-7, -36), (7, -37), (8, -6), (-7, -5)], NAVY, bulge=0.45)
    for yy in (-30, -20, -12):
        t.line(c, -6, yy, 7, yy - 0.5, VISOR[1])
    for xx in (-3, 3):
        t.line(c, xx, -35, xx, -6, GREEN[2])
    t.ell(c, 0, -36.5, 7.2, 2, NAVY, tone=2)
    t.ell(c, 1, 0, 5, 5, DARKCLOTH)
    t.ell(c, 1, 0, 1.8, 1.8, STEEL, seam=False)
    # a leek and a baguette sticking out
    t.tube(c, [(-3, -36, 1.4), (-6, -47, 1.2)], GREEN)
    t.tube(c, [(2, -37, 1.8), (5, -50, 1.8)], WOOD)
    t.px(c, 4, -46, WOOD[3])


def handbag(c, x, y, ang=0.0):
    t = T(x, y, ang)
    t.line(c, -4, -6, 0, -10, DARKCLOTH[1])
    t.line(c, 0, -10, 4, -6, DARKCLOTH[1])
    t.poly(c, [(-6, -6), (6, -6), (7, 3), (-7, 3)], VISOR, bulge=0.5)
    t.px(c, 0, -4, BRASS[2])
    t.px(c, 1, -4, BRASS[2])


def granny(**kw):
    p = dict(hip=(52, 79), lean=0.0, hang=0.0, mood="plain", mth="smile", armf=(0.3, 0.5), armb=(-0.2, 0.4), legf=(0.15, -0.1),
             legb=(-0.1, 0.05), sit=False, tied=False, bag=None, trolley=None, crate=None, extra=None, under=None, fist=False)
    p.update(kw)
    c = Canvas(W, H)
    if p["under"]:
        p["under"](c)
    if p["trolley"]:
        trolley(c, *p["trolley"])
    hx_, hy_ = p["hip"]
    ln = p["lean"]

    def R(dx, dy):
        x, y = rot(hx_ + dx, hy_ + dy, hx_, hy_, ln)
        return x, y
    if not p["tied"] and p["armb"]:
        hb = arm(c, R(4, -17), p["armb"][0] + ln, p["armb"][1], MAUVE, far=True, fist=p["fist"])
    stock = DARKCLOTH
    shoe = WOOD
    if p["sit"]:
        leg(c, (hx_ + 3, hy_ + 2), p["legb"][0], p["legb"][1], stock, shoe, far=True, L=(9, 9), r=(3.4, 2.6))
    else:
        leg(c, (hx_ + 4, hy_), p["legb"][0], p["legb"][1], stock, shoe, far=True, L=(9, 9), r=(3.0, 2.6))
    # body: round cardigan, skirt, apron
    if p["sit"]:
        kx, ky = hx_ - 13, hy_ - 7
        c.poly([R(10, -6), R(-10, -6), (kx - 3, ky - 2), (kx - 2, ky + 5), (hx_ + 12, hy_ + 7)], DARKCLOTH, bulge=0.5)
    else:
        c.poly([R(10, -6), R(-10, -6), R(-14, 10), R(14, 10)], DARKCLOTH, bulge=0.45)
        c.line(*R(-6, 9), *R(-5, 0), DARKCLOTH[0])
        c.line(*R(5, 9), *R(4, 0), DARKCLOTH[0])
    cx, cy = R(0, -12)
    c.ell(cx, cy, 12, 13, MAUVE, ang=ln)
    c.poly([R(-11, -16), R(-3, -18), R(-2, 4 if not p["sit"] else -2), R(-12, 6 if not p["sit"] else -3)], CREAM, bulge=0.4, rim=False)
    for dy in (-12, -6):
        c.px(*R(-7, dy), VISOR[1])
        c.px(*R(-4, dy + 3), VISOR[1])
    for dy in (-16, -11, -6):
        c.px(*R(1, dy), BRASS[2])
    if p["sit"]:
        leg(c, (hx_ - 2, hy_ + 2), p["legf"][0], p["legf"][1], stock, shoe, L=(9, 9), r=(3.6, 2.8))
    else:
        leg(c, (hx_ - 3, hy_), p["legf"][0], p["legf"][1], stock, shoe, L=(9, 9), r=(3.0, 2.6))
    if p["bag"] is not None and not p["tied"] and p["armb"]:
        handbag(c, hb[0] + 3, hb[1] - 9, p["bag"])
    hd = T(*R(-2, -33), ln + p["hang"])
    granny_head(c, hd, p["mood"], p["mth"])
    if p["tied"]:
        for dy, sag in ((-18, 2.5), (-11, 3.0), (-5, 2.0)):
            rope_band(c, R(-12, dy), R(12, dy - 1), sag)
        c.ell(*R(10, -12), 2.6, 2.2, ROPE)  # the knot
        c.tube([(R(10, -11)[0], R(10, -11)[1], 1.2), (R(15, -4)[0], R(15, -4)[1], 1.2)], ROPE)
    if p["crate"]:
        weapon_crate(c, T(*p["crate"]), "pepper")
    if not p["tied"] and p["armf"]:
        arm(c, R(-3, -17), p["armf"][0] + ln, p["armf"][1], MAUVE, fist=p["fist"])
    if p["extra"]:
        p["extra"](c)
    return c.done()


def granny_frames():
    f = {}
    sit = dict(sit=True, tied=True, hip=(50, 88), legf=(1.9, -1.9), legb=(1.7, -1.6), mth="clamp", mood="angry",
               trolley=(76, 96, 0.08))
    wr = [0.0, -0.08, 0.06, -0.06, 0.08, 0.0]
    for i in range(6):
        ex = None
        if i in (1, 2, 4):
            ex = (lambda c, i=i: (shout(c, 18, 40 - (i % 2) * 3, i), anger_mark(c, 44, 46, 1.0)))
        elif i == 5:
            ex = (lambda c: (heart(c, 22, 42, 1.0), anger_mark(c, 44, 46, 1.0)))
        f[f"tied_{i}"] = granny(**{**sit, "lean": wr[i], "hang": -wr[i] * 0.6,
                                   "legf": (1.9 + (0.2 if i % 2 else 0), -1.9 - (0.3 if i % 2 else 0))}, extra=ex)
    # free: ropes burst, she springs up, fists up, settles
    f["free_0"] = granny(**{**sit, "mood": "shock", "mth": "open"}, extra=lambda c: (rope_bits(c, 50, 70, 0.3), _clamp_off(c, 30, 48, 0.4)))
    f["free_1"] = granny(hip=(50, 82), lean=-0.1, legf=(0.9, -1.2), legb=(0.6, -0.9), armf=(2.0, 0.5), armb=(3.4, -0.2), mood="angry",
                         mth="open", trolley=(76, 96, 0.08), fist=True, extra=lambda c: (rope_bits(c, 50, 70, 0.8), _clamp_off(c, 20, 30, 1.0)))
    f["free_2"] = granny(hip=(52, 79), armf=(2.2, 0.5), armb=(3.5, -0.2), mood="happy", mth="grin", trolley=(76, 96, 0.08), fist=True)
    f["free_3"] = granny(hip=(52, 80), mood="happy", mth="smile", trolley=(76, 96, 0.08))
    # give: rummage in the trolley, out comes the crate, hand it over, then pat the player's cheek
    f["give_0"] = granny(lean=0.25, hang=0.1, armf=(-0.6, 0.3), armb=(-0.4, 0.2), mood="plain", mth="smile", trolley=(76, 96, 0.08))
    f["give_1"] = granny(lean=0.1, armf=(0.9, 1.0), armb=(0.7, 1.0), mood="happy", mth="smile", trolley=(76, 96, 0.08),
                         crate=(42, 62))
    f["give_2"] = granny(lean=-0.1, armf=(1.5, 0.2), armb=(1.3, 0.3), mood="happy", mth="grin", trolley=(76, 96, 0.08),
                         crate=(26, 58))
    f["give_3"] = granny(lean=-0.12, armf=(1.6, 0.1), armb=(1.2, 0.3), mood="wink", mth="grin", trolley=(76, 96, 0.08),
                         crate=(22, 60))
    f["give_4"] = granny(lean=-0.15, armf=(2.2, -0.2), armb=(0.2, 0.4), mood="happy", mth="smile", trolley=(76, 96, 0.08),
                         extra=lambda c: heart(c, 20, 26, 0.9))
    f["give_5"] = granny(lean=-0.12, armf=(1.9, 0.1), armb=(0.2, 0.4), mood="happy", mth="smile", trolley=(76, 96, 0.08),
                         extra=lambda c: (heart(c, 16, 20, 1.1), _pat_lines(c)))
    # run off to the left, shaking her handbag over her head
    for i in range(8):
        ph = i / 8 * 2 * math.pi
        s = math.sin(ph)
        f[f"run_{i}"] = granny(hip=(52, 80 - abs(math.cos(ph)) * 2), lean=-0.22, hang=0.12, legf=(0.9 * s + 0.2, -0.3 - 0.9 * max(0, -s)),
                               legb=(-0.9 * s + 0.2, -0.3 - 0.9 * max(0, s)), armb=(3.5 + 0.25 * math.sin(ph * 2), -0.4),
                               armf=(0.8 * s + 0.3, 1.0), bag=0.5 * math.sin(ph * 2), mood="angry", mth="open",
                               extra=(lambda c, i=i: anger_mark(c, 60, 34 + (i % 2), 0.9)) if i % 4 < 2 else None)
    for i in range(4):
        f[f"salute_{i}"] = granny(armf=(1.9 + [0, 0.25, 0, -0.25][i], 0.6), armb=(0.1, 0.4), mood="happy", mth="grin",
                                  hang=[0, 0.05, 0, -0.05][i], trolley=(76, 96, 0.08))
    return f


def _clamp_off(c, x, y, k):
    t = T(x, y, k * 3)
    t.tube(c, [(0, 0, 3.4), (-8, 1, 2.4), (-12, 3, 1.2)], BRASS)
    t.tube(c, [(0, 3, 2.2), (-7, 4, 1.4)], BRASS, bias=-0.2)


def _pat_lines(c):
    for x0, y0, x1, y1 in ((14, 34, 10, 31), (16, 38, 11, 38), (14, 42, 10, 45)):
        c.line(x0, y0, x1, y1, CREAM[2])


# ------------------------------------------------------------------ fisherman
def fisher_head(c, h: T, mood="plain", mth="smile", pipe=True):
    h.ell(c, 0, 0, 10.5, 10.5, FLESH)
    # white beard round the jaw and a bushy moustache
    h.poly(c, [(-9, 2), (-4, 11), (3, 13), (9, 8), (8, 2), (2, 6), (-4, 5)], CHROME, bulge=0.5, center=(1, 7))
    h.ell(c, -7, 3, 4.5, 2.2, CHROME, seam=True)
    # red beanie with a turned-up brim
    h.ell(c, 2, -9, 11.5, 7.5, VISOR)
    h.tube(c, [(-10, -5, 2.4), (12, -4, 2.4)], VISOR, bias=-0.1)
    for x in (-5, -1, 3, 7):
        h.line(c, x, -14, x, -7, VISOR[0])
    h.ell(c, 4, -17, 3, 2.6, VISOR, tone=2)
    h.ell(c, -10, 1, 2.8, 2.8, FLESH)  # nose
    h.px(c, -11, 0, FLESH[3])
    eyes_face(c, h, mood)
    h.line(c, -8, -2.5, -5, -3, CHROME[3])  # bushy brows
    h.line(c, -2, -3, 1, -2.5, CHROME[3])
    if mth == "clamp":
        beak_clamp(c, h)
    elif mth in ("open", "grin"):
        h.ell(c, -6, 7, 2.4, 2.0, VISOR, tone=0, seam=False)
    if pipe and mth != "clamp":
        h.tube(c, [(-6, 6, 0.8), (-14, 8, 0.8)], WOOD)
        h.tube(c, [(-14, 9, 2.0), (-15, 4, 2.4)], WOOD)
        h.px(c, -15, 2, CREAM[2])


def bollard(c, x, y):
    t = T(x, y)
    t.poly(c, [(-8, 0), (8, 0), (6, -22), (-6, -22)], DARKCLOTH, bulge=0.4)
    t.ell(c, 0, -23, 9, 4, DARKCLOTH)
    t.ell(c, 0, -24, 6, 2, DARKCLOTH, tone=2, seam=False)
    t.tube(c, [(-9, -1, 1.4), (9, -1, 1.4)], DARKCLOTH, tone=0)


def fish(c, t: T, wag=0.0):
    t.ell(c, 0, 0, 10, 4, CHROME)
    t.poly(c, [(-9, -1), (8, -3.5), (8, 0), (-8, 0)], SEA, normal=(0, -0.6), seam=False)
    tl = t.child(9, 0, wag)
    tl.poly(c, [(0, 0), (6, -5), (5, 0), (6, 5)], SEA, bulge=0.4)
    t.px(c, -7, -1, DARK)
    t.line(c, -9, 1, -7, 1, DARK)


def fisher(**kw):
    p = dict(hip=(52, 76), lean=0.0, hang=0.0, mood="plain", mth="smile", armf=(0.3, 0.5), armb=(-0.2, 0.4), legf=(0.15, -0.1),
             legb=(-0.1, 0.05), sit=False, tied=False, fishpos=None, bollard=None, crate=None, extra=None, under=None, fist=False,
             pipe=True, fish_hand=False)
    p.update(kw)
    c = Canvas(W, H)
    if p["under"]:
        p["under"](c)
    if p["bollard"]:
        bollard(c, *p["bollard"])
    hx_, hy_ = p["hip"]
    ln = p["lean"]

    def R(dx, dy):
        return rot(hx_ + dx, hy_ + dy, hx_, hy_, ln)
    boot = DARKCLOTH
    if not p["tied"] and p["armb"]:
        hb = arm(c, R(4, -21), p["armb"][0] + ln, p["armb"][1], YELLOW, far=True, L=(11, 10), fist=p["fist"])
    lg = dict(L=(11, 10), r=(3.8, 3.2))
    if p["sit"]:
        leg(c, (hx_ + 3, hy_ + 2), p["legb"][0], p["legb"][1], NAVY, boot, far=True, **lg)
    else:
        leg(c, (hx_ + 4, hy_), p["legb"][0], p["legb"][1], NAVY, boot, far=True, **lg)
    # oilskin coat
    cx, cy = R(0, -12)
    c.poly([R(-10, -24), R(9, -24), R(13, 6), R(-13, 6)], YELLOW, bulge=0.55, center=(cx, cy))
    c.line(*R(-2, -22), *R(-2, 5), YELLOW[0])
    for dy in (-18, -10, -2):
        c.px(*R(-4, dy), DARKCLOTH[2])
    c.poly([R(-8, -25), R(0, -21), R(8, -25), R(0, -27)], YELLOW, tone=0, seam=False)  # collar
    if p["fishpos"] and not p["fish_hand"]:
        fish(c, T(*R(*p["fishpos"]), ln + 0.15))
    if p["sit"]:
        leg(c, (hx_ - 2, hy_ + 2), p["legf"][0], p["legf"][1], NAVY, boot, **lg)
    else:
        leg(c, (hx_ - 3, hy_), p["legf"][0], p["legf"][1], NAVY, boot, **lg)
    hd = T(*R(-2, -35), ln + p["hang"])
    fisher_head(c, hd, p["mood"], p["mth"], p["pipe"])
    if p["fish_hand"] and not p["tied"] and p["armb"]:
        fish(c, T(hb[0] + 2, hb[1] - 6, -1.2 + p["hang"]), wag=0.4)
    if p["tied"]:
        for dy, sag in ((-19, 2.5), (-12, 3.0), (-4, 2.0)):
            rope_band(c, R(-13, dy), R(13, dy - 1), sag)
        c.ell(*R(11, -12), 2.6, 2.2, ROPE)
        c.tube([(R(11, -11)[0], R(11, -11)[1], 1.2), (p["bollard"][0], p["bollard"][1] - 18, 1.2)], ROPE)
    if p["crate"]:
        weapon_crate(c, T(*p["crate"]), "pepper")
    if not p["tied"] and p["armf"]:
        arm(c, R(-3, -21), p["armf"][0] + ln, p["armf"][1], YELLOW, L=(11, 10), fist=p["fist"])
    if p["extra"]:
        p["extra"](c)
    return c.done()


def fisher_frames():
    f = {}
    sit = dict(sit=True, tied=True, hip=(46, 86), legf=(1.9, -1.9), legb=(1.7, -1.6), mth="clamp", mood="angry",
               bollard=(66, GROUND - 2), fishpos=(14, 4), pipe=False)
    wr = [0.0, -0.08, 0.06, -0.06, 0.08, 0.0]
    for i in range(6):
        ex = None
        if i in (1, 2, 4):
            ex = (lambda c, i=i: (shout(c, 14, 34 - (i % 2) * 3, i), anger_mark(c, 40, 36, 1.0)))
        elif i == 5:
            ex = (lambda c: (heart(c, 18, 34, 1.0), anger_mark(c, 40, 36, 1.0)))
        f[f"tied_{i}"] = fisher(**{**sit, "lean": wr[i], "hang": -wr[i] * 0.6,
                                   "legf": (1.9 + (0.2 if i % 2 else 0), -1.9 - (0.3 if i % 2 else 0))}, extra=ex)
    f["free_0"] = fisher(**{**sit, "mood": "shock", "mth": "open"}, extra=lambda c: (rope_bits(c, 46, 64, 0.3), _clamp_off(c, 26, 42, 0.4)))
    f["free_1"] = fisher(hip=(48, 76), lean=-0.1, legf=(0.9, -1.2), legb=(0.6, -0.9), armf=(2.0, 0.5), armb=(3.4, -0.2), mood="angry",
                         mth="open", bollard=(70, GROUND - 2), fist=True, pipe=False,
                         extra=lambda c: (rope_bits(c, 48, 62, 0.8), _clamp_off(c, 18, 24, 1.0)))
    f["free_2"] = fisher(armf=(2.2, 0.5), armb=(3.5, -0.2), mood="happy", mth="grin", bollard=(72, GROUND - 2), fist=True, fish_hand=True)
    f["free_3"] = fisher(mood="happy", bollard=(72, GROUND - 2), fishpos=(12, -12))
    f["give_0"] = fisher(lean=0.2, armf=(-0.3, 0.4), armb=(-0.5, 0.3), mood="plain", bollard=(72, GROUND - 2), fishpos=(12, -12),
                         extra=lambda c: weapon_crate(c, T(80, 92, 0.1), "pepper"))
    f["give_1"] = fisher(lean=0.05, armf=(0.9, 1.0), armb=(0.7, 1.0), mood="happy", bollard=(72, GROUND - 2), crate=(40, 60),
                         fishpos=(12, -12))
    f["give_2"] = fisher(lean=-0.1, armf=(1.5, 0.2), armb=(1.3, 0.3), mood="happy", mth="grin", bollard=(72, GROUND - 2), crate=(24, 56),
                         fishpos=(12, -12))
    f["give_3"] = fisher(lean=-0.12, armf=(1.6, 0.1), armb=(1.2, 0.3), mood="wink", mth="grin", bollard=(72, GROUND - 2), crate=(20, 58),
                         fishpos=(12, -12))
    f["give_4"] = fisher(lean=-0.15, armf=(2.2, -0.2), armb=(0.2, 0.4), mood="happy", bollard=(72, GROUND - 2), fishpos=(12, -12),
                         extra=lambda c: heart(c, 18, 22, 0.9))
    f["give_5"] = fisher(lean=-0.12, armf=(1.9, 0.1), armb=(0.2, 0.4), mood="happy", bollard=(72, GROUND - 2), fishpos=(12, -12),
                         extra=lambda c: (heart(c, 14, 16, 1.1), _pat_lines(c)))
    for i in range(8):
        ph = i / 8 * 2 * math.pi
        s = math.sin(ph)
        f[f"run_{i}"] = fisher(hip=(52, 76 - abs(math.cos(ph)) * 2), lean=-0.25, hang=0.1, legf=(0.9 * s + 0.2, -0.3 - 1.0 * max(0, -s)),
                               legb=(-0.9 * s + 0.2, -0.3 - 1.0 * max(0, s)), armb=(3.3 + 0.3 * math.sin(ph * 2), -0.3),
                               armf=(0.8 * s + 0.3, 1.0), mood="happy", mth="open", fish_hand=True,
                               extra=(lambda c, i=i: sweat(c, 66, 34 + i % 2)) if i % 4 == 0 else None)
    for i in range(4):
        f[f"salute_{i}"] = fisher(armf=(1.9 + [0, 0.25, 0, -0.25][i], 0.6), armb=(0.1, 0.4), mood="happy", mth="smile",
                                  hang=[0, 0.05, 0, -0.05][i], bollard=(72, GROUND - 2), fishpos=(12, -12))
    return f


ORDER = ([f"tied_{i}" for i in range(6)] + [f"free_{i}" for i in range(4)] + [f"give_{i}" for i in range(6)] +
         [f"run_{i}" for i in range(8)] + [f"salute_{i}" for i in range(4)])


def build():
    out = {}
    for name, fn, note in (("grandma", granny_frames, "give_1..3 carry the weapon crate (the game spawns the pickup at give_3)"),
                           ("fisherman", fisher_frames, "give_1..3 carry the weapon crate (the game spawns the pickup at give_3)")):
        s = Sheet(name, W, H, [48, 102], faces="left", notes=note)
        fr = fn()
        for n in ORDER:
            s.add(n, fr[n])
        s.save()
        out[name] = fr
    return out


if __name__ == "__main__":
    build()
