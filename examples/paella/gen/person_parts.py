"""Paella de Combate: a small cartoon-human rig for the prisoners (grandma, fisherman) and the shared weapon crate.

The figure faces LEFT. Limb angles: 0 = straight down, +pi/2 = forward (left), pi = up, -pi/2 = backward (right).
"""
from __future__ import annotations

import math

from enemies_kit import CREAM, FLESH, STEEL, VISOR, WOOD, Canvas, Ramp, hx
from gull_parts import DARK, WHITE, T

ROPE = Ramp("#7a5420", "#b8863c", "#e0b868", "#fff0b0", ol="#3a2408")
DARKCLOTH = Ramp("#24182a", "#3c2c40", "#5a4860", "#806c84", ol="#140c18")
BLUSH = hx("#f07a7a")


def limb_pts(start, angles, lengths):
    pts = [start]
    x, y = start
    for a, L in zip(angles, lengths):
        x, y = x - math.sin(a) * L, y + math.cos(a) * L
        pts.append((x, y))
    return pts


def arm(c: Canvas, shoulder, a1, a2, sleeve: Ramp, far=False, L=(10, 9), r=(3.6, 3.0), hand=True, cuff=None, fist=False):
    b = -0.3 if far else 0.0
    s, e, h = limb_pts(shoulder, (a1, a1 + a2), L)
    c.tube([(s[0], s[1], r[0]), (e[0], e[1], r[1])], sleeve, bias=b)
    c.tube([(e[0], e[1], r[1]), (h[0], h[1], r[1] - 0.3)], sleeve, bias=b)
    if cuff:
        c.ell(h[0] + (e[0] - h[0]) * 0.15, h[1] + (e[1] - h[1]) * 0.15, r[1], r[1], cuff, bias=b)
    if hand:
        c.ell(h[0], h[1], 3.0 if not fist else 3.2, 2.8, FLESH, bias=b)
        if not fist:
            c.px(h[0] - 2, h[1] + 1, FLESH[0])
    return h


def leg(c: Canvas, hip, a1, a2, cloth: Ramp, shoe: Ramp, far=False, L=(11, 11), r=(4.4, 3.4), toe=0.0, sock=None):
    b = -0.3 if far else 0.0
    hp, kn, an = limb_pts(hip, (a1, a1 + a2), L)
    c.tube([(hp[0], hp[1], r[0]), (kn[0], kn[1], r[1] + 0.4)], cloth, bias=b)
    c.tube([(kn[0], kn[1], r[1]), (an[0], an[1], r[1] - 0.6)], sock or cloth, bias=b)
    st = T(an[0], an[1], toe + (a1 + a2) * 0.0)
    st.ell(c, -2.5, 1.5, 5.2, 2.8, shoe, bias=b)
    st.px(c, -5, 0.5, shoe[3])
    return an


def weapon_crate(c: Canvas, t: T, mark="pepper", w=20, h=15):
    """The weapon crate: a slatted wooden box, iron corners, a stencilled mark (pepper / chilli / bottle / pot)."""
    hw, hh = w / 2, h / 2
    t.poly(c, [(-hw, -hh), (hw, -hh), (hw, hh), (-hw, hh)], WOOD, bulge=0.35)
    for y in (-hh + h / 3, -hh + 2 * h / 3):
        t.line(c, -hw + 1, y, hw - 1, y, WOOD[0])
    t.line(c, -hw + 1, -hh + 1, hw - 1, -hh + 1, WOOD[3])
    for sx, sy in ((-1, -1), (1, -1), (-1, 1), (1, 1)):
        t.fill(c, [(sx * hw, sy * hh), (sx * (hw - 3), sy * hh), (sx * hw, sy * (hh - 3))], STEEL[1])
    stencil(c, t, mark, h)


def stencil(c: Canvas, t: T, mark, h):
    s = h / 15
    col = VISOR[1]
    if mark == "pepper":   # a round bell pepper
        t.ell(c, 0, 0.5 * s, 4.2 * s, 3.6 * s, VISOR, seam=False, tone=1)
        t.line(c, 0, -3.5 * s, 1, -5 * s, (60, 140, 50))
    elif mark == "chilli":  # a curved chilli with a flame tip
        t.tube(c, [(-4 * s, -2 * s, 1.6 * s), (0, 1 * s, 2.2 * s), (4 * s, 3 * s, 0.8 * s)], VISOR, seam=False, tone=1)
        t.line(c, -5 * s, -3 * s, -6 * s, -5 * s, (60, 140, 50))
    elif mark == "bottle":
        t.tube(c, [(0, -5 * s, 1.1 * s), (0, -2 * s, 1.1 * s)], VISOR, seam=False, tone=1)
        t.tube(c, [(0, -1 * s, 2.6 * s), (0, 4 * s, 2.6 * s)], VISOR, seam=False, tone=1)
    elif mark == "pot":
        t.ell(c, 0, 1 * s, 4 * s, 3 * s, VISOR, seam=False, tone=1)
        t.line(c, -5 * s, 0, 5 * s, 0, col)
        t.px(c, 0, -3 * s, col)


def eyes_face(c: Canvas, h: T, mood, glasses=False):
    """Eyes and brows for a left-facing cartoon head (h = head centre)."""
    ex = (-6, -1)
    if mood == "angry":
        for x in ex:
            h.px(c, x, -1, DARK)
            h.px(c, x, 0, DARK)
        h.line(c, -8, -4, -5, -2, DARK)
        h.line(c, -2, -2, 1, -4, DARK)
    elif mood == "happy":
        for x in ex:
            h.line(c, x - 1, 0, x, -1, DARK)
            h.line(c, x, -1, x + 1, 0, DARK)
    elif mood == "shock":
        for x in ex:
            h.ell(c, x, -1, 1.8, 2.2, CREAM, tone=3, seam=False)
            h.px(c, x - 0.5, -1, DARK)
        h.line(c, -8, -5, -5, -5, DARK)
        h.line(c, -2, -5, 1, -5, DARK)
    elif mood == "wink":
        h.px(c, -6, -1, DARK)
        h.px(c, -6, 0, DARK)
        h.line(c, -2, 0, 0, 0, DARK)
    else:  # plain
        for x in ex:
            h.px(c, x, -1, DARK)
            h.px(c, x, 0, DARK)
    if glasses:
        for x in ex:
            h.ell(c, x, -0.5, 2.6, 2.4, STEEL, tone=2, seam=False)
            h.ell(c, x, -0.5, 1.6, 1.4, CREAM, tone=3, seam=False)
            h.px(c, x - 0.5, -0.5, DARK)
            if mood in ("happy",):
                h.line(c, x - 1, 0, x + 1, 0, DARK)
        h.line(c, -4, -1, -3, -1, STEEL[2])
        if mood == "angry":
            h.line(c, -8, -4, -5, -3, DARK)
            h.line(c, -2, -3, 1, -4, DARK)


def anger_mark(c: Canvas, x, y, s=1.0):
    """The cartoon anger cross (four little bulging arcs)."""
    t = T(x, y, 0, s, s)
    for a in range(4):
        u = t.child(0, 0, a * math.pi / 2)
        u.line(c, 1, -3, 3, -1, VISOR[1])
        u.line(c, 1, -2, 2, -1, VISOR[1])


def heart(c: Canvas, x, y, s=1.0):
    t = T(x, y, 0, s, s)
    t.ell(c, -2, -1, 2.4, 2.2, VISOR)
    t.ell(c, 2, -1, 2.4, 2.2, VISOR)
    t.poly(c, [(-4.2, 0), (4.2, 0), (0, 4.5)], VISOR, bulge=0.3, seam=False)
    t.px(c, -2.5, -2, VISOR[3])


def shout(c: Canvas, x, y, k):
    """A muffled shout balloon: a spiky puff with '#!' scribbles."""
    pts = []
    for i in range(12):
        a = i * math.pi / 6
        r = 8 if i % 2 == 0 else 5.5
        pts.append((x + math.cos(a) * r * 1.2, y + math.sin(a) * r * 0.85))
    c.poly(pts, CREAM, tone=2, seam=False)
    sym = [["x.x", ".x.", "x.x"], ["#.#", "###", "#.#"]][k % 2]
    c.stamp(sym, int(x - 4), int(y - 1), {"x": DARK, "#": DARK})
    c.stamp(["!", "!", ".", "!"], int(x + 2), int(y - 2), {"!": VISOR[1]})
