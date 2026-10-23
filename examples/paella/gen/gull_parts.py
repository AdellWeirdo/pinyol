"""Paella de Combate: the mechanical seagull rig shared by gull_soldier, gull_bazooka, gull_drone and gull_kamikaze.

Every part is drawn in its own local coordinates (the gull faces LEFT, -x is forward) through a transform T, so a die
animation can throw the head one way and the legs another, and a pose is just numbers.
"""
from __future__ import annotations

import math

from enemies_kit import BRASS, CHROME, CREAM, OLIVE, ORANGE, STEEL, VISOR, WOOD, Canvas, hx, rot

EYE_Y = hx("#ffe040")
DARK = hx("#2a1430")
WHITE = hx("#ffffff")
SOCK = hx("#f4f0e8")
SWEAT = (154, 216, 255)


class T:
    """local (x, y) -> frame: scale, rotate by ang (clockwise on screen), translate to (ox, oy)."""

    def __init__(self, ox, oy, ang=0.0, sx=1.0, sy=1.0):
        self.ox, self.oy, self.ang, self.sx, self.sy = ox, oy, ang, sx, sy

    def p(self, x, y):
        x, y = x * self.sx, y * self.sy
        c, s = math.cos(self.ang), math.sin(self.ang)
        return self.ox + x * c - y * s, self.oy + x * s + y * c

    def r(self, r):
        return r * (self.sx + self.sy) / 2

    def child(self, x, y, ang=0.0):
        ox, oy = self.p(x, y)
        return T(ox, oy, self.ang + ang, self.sx, self.sy)

    # shape shortcuts in local coordinates
    def ell(self, c: Canvas, x, y, rx, ry, ramp, ang=0.0, **kw):
        px, py = self.p(x, y)
        c.ell(px, py, rx * self.sx, ry * self.sy, ramp, ang=ang + self.ang, **kw)

    def tube(self, c: Canvas, pts, ramp, **kw):
        c.tube([(*self.p(x, y), self.r(r)) for x, y, r in pts], ramp, **kw)

    def poly(self, c: Canvas, pts, ramp, **kw):
        if "center" in kw and kw["center"] is not None:
            kw["center"] = self.p(*kw["center"])
        c.poly([self.p(x, y) for x, y in pts], ramp, **kw)

    def fill(self, c: Canvas, pts, col):
        c.fill_poly([self.p(x, y) for x, y in pts], col)

    def px(self, c: Canvas, x, y, col):
        c.px(*self.p(x, y), col)

    def line(self, c: Canvas, x0, y0, x1, y1, col, width=1):
        a, b = self.p(x0, y0)
        d, e = self.p(x1, y1)
        c.line(a, b, d, e, col, width)

    def disc(self, c: Canvas, x, y, r, col):
        c.disc(*self.p(x, y), self.r(r), col)


# ------------------------------------------------------------------ parts

def key(c: Canvas, t: T, phase: float, sock=False):
    """The wind-up key in the gull's back: a stem and a bow whose two lobes turn (phase in radians)."""
    t.tube(c, [(0, 0, 1.6), (6, -5, 1.6)], BRASS)
    k = math.cos(phase)
    w = 1.0 + 4.5 * abs(k)
    b = t.child(8, -7, -0.7)
    # two lobes either side of the stem tip, squashed by the turn
    b.ell(c, 0, -4.0, w, 3.2, BRASS, seam=True)
    b.ell(c, 0, 4.0, w, 3.2, BRASS, seam=True)
    b.ell(c, 0, 0, 2.0, 2.2, BRASS, seam=True)
    if w > 2.6:
        b.ell(c, 0, -4.0, w - 2.3, 1.1, BRASS, tone=0, seam=False)
        b.ell(c, 0, 4.0, w - 2.3, 1.1, BRASS, tone=0, seam=False)
    if sock:
        # a stick tied to the key with a white sock for a flag
        t.line(c, 8, -8, 14, -30, WOOD[1])
        t.line(c, 9, -8, 15, -30, WOOD[0])
        s = t.child(14, -30)
        s.poly(c, [(0, 0), (12, 2), (14, 6), (13, 12), (9, 13), (8, 8), (1, 6)], CREAM, bulge=0.5)
        s.line(c, 10, 9, 12, 9, VISOR[1])
        s.line(c, 1, 2, 11, 3, VISOR[1])


def tail(c: Canvas, t: T, flick=0.0):
    tt = t.child(0, 0, flick)
    tt.poly(c, [(-2, -5), (16, -4), (19, 1), (14, 4), (17, 7), (2, 6)], STEEL, bulge=0.6)
    tt.poly(c, [(8, -3), (19, 0), (16, 2)], STEEL, tone=0, seam=False)
    tt.px(c, 18, 0, CHROME[2])


def body(c: Canvas, t: T, crack=0, belly=True):
    """Torso: a plump chrome egg with a white belly, a grey folded wing (mantle) on the back, rivets on the seams."""
    t.ell(c, 0, 0, 21, 19, CHROME, ang=-0.2)
    if belly:
        t.ell(c, -7, 5, 12, 11, CREAM, ang=-0.3, seam=False, rim=False)
        t.ell(c, -8, 3, 9, 8, CHROME, tone=2, seam=False)
        t.ell(c, -10, 1, 5, 4, CHROME, tone=3, seam=False)
    # rivets along the belly plate seam
    for a in (-1.2, -0.7, -0.2, 0.3, 0.8):
        x, y = -7 + 13 * math.cos(a + 1.6), 5 + 12 * math.sin(a + 1.6)
        t.px(c, x, y, STEEL[0])
        t.px(c, x - 1, y - 1, CHROME[3])
    # the folded grey wing on the back (mantle): a rounded grey shoulder, feather rows, black primaries to the tail
    t.ell(c, 9, -3, 14, 10.5, STEEL, ang=0.45)
    t.tube(c, [(14, 4, 4.5), (24, 10, 3.2), (31, 13, 1.6)], STEEL, tone=0)
    t.px(c, 25, 9, CHROME[2])
    t.px(c, 26, 9, CHROME[2])
    for x, y in ((2, -7), (8, -5), (14, -2)):
        t.line(c, x, y, x + 4, y + 6, STEEL[0])
    for x, y in ((4, -11), (11, -10), (17, -6)):
        t.px(c, x, y, BRASS[2])
        t.px(c, x + 1, y + 1, BRASS[0])
    if crack:
        t.line(c, -14, -6, -8, -2, DARK)
        t.line(c, -8, -2, -10, 4, DARK)
        t.line(c, -3, -12, 0, -7, DARK)
        if crack > 1:
            t.line(c, 2, 6, 8, 2, DARK)
            t.line(c, -4, 12, 0, 8, DARK)


EYES = {
    # 7x5 eye in the visor; y = yellow iris, k = pupil, w = white glint, r = visor (closed lid), o = outline
    "mean": ["oo.....", ".ooo...", "yyyyoo.", "ykkyy..", ".yyy..."],
    "look": ["o......", ".oo....", "yyyy...", "ykky...", ".yy...."],
    "shock": [".yyyy..", "yyyyyy.", "yykkyy.", "yykkyy.", ".yyyy.."],
    "x": ["k...k..", ".k.k...", "..k....", ".k.k...", "k...k.."],
    "closed": ["......", ".......", "ooooo..", ".......", "......."],
    "worried": ["...oo..", "..o....", "yyyy...", "yykk...", ".yyy..."],
    "dizzy": [".kkk...", "k...k..", "k.k.k..", "k..k...", ".kk...."],
}


def head(c: Canvas, t: T, beak_open=0.0, eye="mean", helmet=True, beak="cannon", yell=False, goggles=False):
    """Pivot = neck base. Head round chrome, red visor band, a mean yellow eye, a brass cannon beak pointing left."""
    t.tube(c, [(0, 0, 6), (-6, -12, 6.5)], CHROME, seam=False)
    t.ell(c, -8, -18, 12, 11, CHROME, ang=0.1, seam=False)
    # lower mandible (opens), drawn under the upper beak
    lo = t.child(-17, -13, -beak_open * 0.6)
    lo.tube(c, [(0, 0, 3.4), (-13, 1, 2.2)], BRASS, bias=-0.15)
    lo.ell(c, -12, 1.5, 2.2, 1.8, VISOR, seam=True)  # the gull's red spot
    if beak_open > 0.3 or yell:
        mo = t.child(-17, -14, 0)
        mo.ell(c, -6, 2 + beak_open * 3, 5, 2 + beak_open * 3, VISOR, tone=0, seam=False)
    # upper beak = the cannon
    t.tube(c, [(-16, -17, 4.4), (-30, -16, 3.6), (-35, -15.5, 3.6)], BRASS)
    t.ell(c, -35.5, -15.5, 1.8, 3.6, BRASS, seam=True)
    t.ell(c, -36, -15.5, 1.0, 2.1, BRASS, tone=0, seam=False)
    t.px(c, -36, -16, DARK)
    t.px(c, -36, -15, DARK)
    t.tube(c, [(-24, -19.5, 0.6), (-31, -19, 0.6)], BRASS, tone=3, seam=False)
    for x in (-21, -27):  # barrel bands
        t.line(c, x, -20.5, x, -12, BRASS[0])
    # visor: a red glass band over the eye, angled down at the front (a frown built in)
    t.poly(c, [(-20, -24), (-4, -21), (-2, -15), (-17, -14), (-21, -18)], VISOR, bulge=0.5, center=(-12, -19))
    t.line(c, -18, -22, -6, -20, VISOR[3])
    ex, ey = t.p(-15, -21)
    rows = EYES[eye]
    cmap = {"y": EYE_Y, "k": DARK, "w": WHITE, "o": VISOR[0], "r": VISOR[1]}
    c.stamp(rows, int(ex), int(ey), cmap)
    if eye in ("mean", "look", "worried"):
        c.px(int(ex) + 1, int(ey) + 3, WHITE)
    if goggles:
        t.tube(c, [(-2, -22, 1.6), (6, -20, 1.6)], WOOD, seam=False)
    # cheek rivets
    t.px(c, -4, -12, STEEL[0])
    t.px(c, -5, -13, CHROME[3])
    t.px(c, 0, -15, STEEL[0])
    t.px(c, -1, -16, CHROME[3])
    if helmet:
        tin_helmet(c, t.child(-7, -27))


def tin_helmet(c: Canvas, t: T):
    """A dented tin helmet: dome, brim, a rivet; pivot = centre of the brim."""
    t.ell(c, 0, -1, 11, 7.5, OLIVE, ang=0.05)
    t.tube(c, [(-13, 2, 1.8), (12, 1, 1.8)], OLIVE, bias=-0.1)
    t.px(c, -3, -5, OLIVE[3])
    t.px(c, -2, -5, OLIVE[3])
    t.px(c, 4, -3, OLIVE[0])
    t.line(c, 2, -6, 5, -3, OLIVE[0])  # a dent


def leg(c: Canvas, hip, foot, far=False, l1=12.0, l2=16.0, toe_up=0.0):
    """A reverse-knee mech leg from hip to ankle (frame coordinates); the knee points backwards (+x)."""
    hx_, hy_ = hip
    ax, ay = foot[0] + 3, foot[1] - 3
    dx, dy = ax - hx_, ay - hy_
    d = min(math.hypot(dx, dy), l1 + l2 - 0.2)
    a0 = math.atan2(dy, dx)
    ca = max(-1.0, min(1.0, (l1 * l1 + d * d - l2 * l2) / (2 * l1 * d)))
    al = math.acos(ca)
    k1 = (hx_ + l1 * math.cos(a0 + al), hy_ + l1 * math.sin(a0 + al))
    k2 = (hx_ + l1 * math.cos(a0 - al), hy_ + l1 * math.sin(a0 - al))
    kx, ky = k1 if k1[0] > k2[0] else k2
    if math.hypot(dx, dy) > l1 + l2 - 0.2:  # out of reach: the ankle follows the shin
        ax, ay = kx + l2 * math.cos(a0), ky + l2 * math.sin(a0)
    b = -0.3 if far else 0.0
    c.tube([(hx_, hy_, 5.0), (kx, ky, 3.0)], CHROME, bias=b)
    c.tube([(kx, ky, 2.4), (ax, ay, 2.0)], STEEL, bias=b)
    # hydraulic piston beside the shin
    c.line(kx - 1.5, ky + 3, ax - 2, ay - 4, STEEL[3] if not far else STEEL[2])
    c.ell(kx, ky, 2.6, 2.6, BRASS, bias=b)
    c.px(kx - 1, ky - 1, BRASS[3])
    webbed_foot(c, ax, ay, far, toe_up)
    return kx, ky


def webbed_foot(c: Canvas, ax, ay, far=False, toe_up=0.0):
    t = T(ax, ay - toe_up * 2, toe_up)
    b = -0.3 if far else 0.0
    t.poly(c, [(1, -1), (-3, 0), (-12, 2.5), (-11, 3.5), (-6, 3.5), (2, 3.5), (3, 1)], ORANGE, bias=b, center=(-4, 0))
    t.line(c, -4, 1, -10, 3, ORANGE[0])
    t.line(c, -2, 1, -5, 3, ORANGE[0])
    t.px(c, -12, 3, ORANGE[0])
    t.ell(c, 2, 2.5, 2.2, 1.2, ORANGE, bias=b)


def pea_pistol(c: Canvas, t: T, flash=0):
    """The pea-shooter ('pistola de pipas'): pivot = the grip in the hand, barrel along -x."""
    t.poly(c, [(-2, 0), (3, 0), (4, 8), (0, 9)], WOOD, bulge=0.5)
    t.tube(c, [(4, -2, 2.4), (-13, -2, 2.2)], STEEL)
    t.ell(c, -14, -2, 1.4, 2.6, STEEL, seam=True)
    t.px(c, -15, -2, DARK)
    # seed hopper (a brass funnel full of sunflower seeds)
    t.poly(c, [(-6, -3), (0, -3), (2, -9), (-8, -9)], BRASS, bulge=0.5)
    t.ell(c, -3, -9, 5, 1.6, BRASS, tone=0, seam=False)
    for x in (-6, -3, -1):
        t.px(c, x, -10, CREAM[2])
        t.px(c, x, -9, DARK)
    t.line(c, 1, 1, 1, 4, DARK)  # trigger
    if flash:
        muzzle_flash(c, t.child(-17, -2), flash)


def muzzle_flash(c: Canvas, t: T, size=1):
    s = 1.0 if size == 1 else 0.6
    pts = []
    for i in range(10):
        a = math.pi + (i - 4.5) * 0.55
        r = (9 if i % 2 == 0 else 4) * s
        pts.append((math.cos(a) * r * 1.3 - 3 * s, math.sin(a) * r))
    t.poly(c, pts, ORANGE, bulge=0.4, seam=False)
    t.ell(c, -4 * s, 0, 4.5 * s, 3 * s, ORANGE, tone=3, seam=False)


def wing_arm(c: Canvas, t: T, aim=0.0, bend=0.6, gun=True, flash=0, fingers="grip", reach=1.0):
    """The front wing used as an arm; pivot = shoulder. aim 0 = forward (-x); negative aims up."""
    aim = -aim  # rot() turns clockwise on screen: from pointing left that is upwards
    sh = (0, 0)
    el = rot(-9 * reach, 4, 0, 0, aim + bend * 0.3)
    hd = rot(-20 * reach, 2, 0, 0, aim)
    el = (el[0], el[1] + 2 * bend)
    t.tube(c, [(sh[0], sh[1], 5.5), (el[0], el[1], 4.2)], STEEL)
    t.tube(c, [(el[0], el[1], 4.0), (hd[0], hd[1], 3.4)], STEEL)
    # feather trailing edge under the arm
    t.poly(c, [(2, 2), (el[0] + 1, el[1] + 3), (el[0] + 4, el[1] + 8), (4, 8)], STEEL, tone=0, seam=False)
    g = t.child(hd[0], hd[1], aim)
    if gun:
        pea_pistol(c, g, flash)
        # feather fingers wrapped over the grip
        for i in range(3):
            g.ell(c, 1 + i * 0.5, 1 + i * 2.3, 3.4, 1.5, STEEL, seam=True)
    elif fingers == "splay":
        for i, a in enumerate((-0.6, -0.1, 0.4)):
            f = g.child(0, 0, a)
            f.tube(c, [(0, 0, 2.4), (-10, 0, 1.6)], STEEL)
            f.px(c, -10, 0, CHROME[2])
    else:
        g.ell(c, -1, 0, 4, 3, STEEL)


def far_wing(c: Canvas, t: T, ang=0.0, spread=0.0):
    """The far wing seen behind the body; ang raises it (negative = up), spread opens the feathers."""
    if ang == 0.0 and spread == 0.0:
        return
    w = t.child(0, 0, ang)
    w.poly(c, [(0, -4), (-4, -24 - spread * 8), (2, -30 - spread * 6), (10, -18), (8, 2)], STEEL, bias=-0.25, center=(3, -12))
    w.poly(c, [(-4, -24 - spread * 8), (2, -30 - spread * 6), (6, -22), (0, -20)], STEEL, tone=0)
    w.px(c, 0, -26 - spread * 6, CHROME[1])


def steam(c: Canvas, x, y, k, size=1.0, ramp=None):
    """A small opaque puff of steam (k = age 0..3); pass ramp=SMOKE for dark smoke."""
    ramp = ramp or CREAM
    r = (2 + k * 1.2) * size
    c.ell(x, y - k * 3, r, r * 0.85, ramp, rim=False)
    c.ell(x + r * 0.8, y - k * 3 + 1, r * 0.7, r * 0.6, ramp, rim=False, seam=False)


def sweat(c: Canvas, x, y):
    c.ell(x, y, 1.6, 2.4, SWEAT, seam=False)
    c.px(x - 0.5, y - 1, WHITE)


def screw(c: Canvas, x, y, a=0.0):
    t = T(x, y, a)
    t.tube(c, [(-3, 0, 1.0), (2, 0, 1.0)], STEEL, seam=False)
    t.ell(c, 3, 0, 1.2, 2.2, STEEL, seam=False)
    t.px(c, -1, 0, STEEL[0])


def feather(c: Canvas, x, y, a=0.0, s=1.0, ramp=CHROME):
    t = T(x, y, a, s, s)
    t.poly(c, [(-6, 0), (-2, -2.5), (5, -1.5), (6, 0), (5, 1.5), (-2, 2.5)], ramp, bulge=0.5)
    t.line(c, -6, 0, 5, 0, STEEL[1])


def star(c: Canvas, x, y, r, col_ramp=ORANGE, n=5, tone=None):
    pts = []
    for i in range(n * 2):
        a = -math.pi / 2 + i * math.pi / n
        rr = r if i % 2 == 0 else r * 0.45
        pts.append((x + math.cos(a) * rr, y + math.sin(a) * rr))
    c.poly(pts, col_ramp, bulge=0.4, tone=tone)


def sardine(c: Canvas, t: T, flame=0, wiggle=0.0, face="mean", fins=True):
    """A sardine (rocket / bomb): pivot = middle, the head points along -x. flame 0..3 = exhaust size at the tail."""
    from enemies_kit import FIRE, SEA
    if flame:
        fl = [0, 6, 10, 8][flame]
        t.poly(c, [(13, -3), (13 + fl, -4 - fl * 0.2), (15 + fl * 1.6, 0), (13 + fl, 4 + fl * 0.2), (13, 3)], FIRE, bulge=0.4, seam=False)
        t.ell(c, 15 + fl * 0.4, 0, 3 + fl * 0.3, 2.2, FIRE, tone=3, seam=False)
    tl = t.child(10, 0, wiggle)
    tl.poly(c, [(0, 0), (8, -6), (6, 0), (8, 6)], SEA, bulge=0.5)
    t.ell(c, 0, 0, 12, 4.6, CHROME)
    t.poly(c, [(-11, -1), (10, -3.5), (10, -0.5), (-10, 0.5)], SEA, normal=(0, -0.6), seam=False)
    for x in (-4, 0, 4):
        t.px(c, x, -3, SEA[3])
    if fins:
        t.poly(c, [(0, -4), (5, -8), (6, -4)], SEA, bulge=0.4)
        t.poly(c, [(-2, 3), (2, 7), (3, 3)], SEA, bulge=0.4)
    t.line(c, -7, -3, -7, 3, SEA[0])  # gill
    t.px(c, -9, -1, WHITE)
    t.px(c, -10, -1, DARK)
    if face == "mean":
        t.line(c, -11, -3, -8, -2, DARK)
    t.line(c, -12, 1, -9, 2, DARK)
