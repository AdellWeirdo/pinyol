"""Paella de Combate: el Tractor-Cañón (player vehicle), 224x144 frames, anchor [112, 140], looks right.

A red-and-cream village tractor armoured with fish-box planks, a paella pan welded on as a front shield,
a sardine-tin-and-drainpipe cannon with a small vulcan under it, a brass bell, a bulb horn and an exhaust.
The seat is left empty (the game draws the seated chef on top at "seat").
"""
from __future__ import annotations

import math

from art_bigs_kit import (BRASS, CREAM, FIRE, IRON, RED, RUBBER, SMOKE, STEEL, TINB, WHITE, WOOD, Canvas, Xf,
                          rad, rng, wobble)

W, H = 224, 144
ANCHOR = (112, 140)
REAR = (72, 108, 31)      # rear wheel centre and radius (with lugs)
FRONT = (160, 122, 17)
PIVOT = (128, 70)         # cannon trunnion, body coordinates
BARREL = 64               # pivot to muzzle
SEAT = (73, 64)           # top of the cushion, body coordinates


def pivot_xf(px, py, rot=0.0, dx=0.0, dy=0.0, sx=1.0, sy=1.0) -> Xf:
    c, s = math.cos(rot), math.sin(rot)
    x, y = px * sx, py * sy
    return Xf(px + dx - (c * x - s * y), py + dy - (s * x + c * y), rot, sx, sy)


# ------------------------------------------------------------------ wheels

def wheel(c: Canvas, cx, cy, r, ang, big=True, dent=False, lift=0.0):
    xf = Xf(cx, cy - lift, rad(ang))
    body = r - 2.2
    n_lug = 14 if big else 9
    # chunky tread blocks proud of the tyre (they turn with the wheel)
    for i in range(n_lug):
        a = 2 * math.pi * i / n_lug
        w = math.pi / n_lug * 0.62
        rr = r + 0.3
        pts = [(math.cos(a - w) * (body - 2), math.sin(a - w) * (body - 2)),
               (math.cos(a - w * 0.8) * rr, math.sin(a - w * 0.8) * rr),
               (math.cos(a + w * 0.8) * rr, math.sin(a + w * 0.8) * rr),
               (math.cos(a + w) * (body - 2), math.sin(a + w) * (body - 2))]
        c.poly(pts, RUBBER, xf=xf, normal=(math.cos(a) * 0.85, math.sin(a) * 0.85))
    c.ellipse(0, 0, body, body, RUBBER, xf=xf, rim=True)
    # tread grooves across the shoulder
    for i in range(n_lug):
        a = 2 * math.pi * (i + 0.5) / n_lug
        x0, y0 = math.cos(a) * (body - 0.5), math.sin(a) * (body - 0.5)
        x1, y1 = math.cos(a + 0.12) * (body - 4), math.sin(a + 0.12) * (body - 4)
        c.lline(xf, x0, y0, x1, y1, RUBBER[0])
    side = body * 0.8
    c.ellipse(0, 0, side, side, RUBBER, xf=xf, bias=-0.3, spec=False)
    # rim: pressed cream disc with a dish, holes and bolts
    rim = body * 0.6
    c.ellipse(0, 0, rim, rim, CREAM, xf=xf, rim=True)
    c.ellipse(0, 0, rim * 0.74, rim * 0.74, CREAM, xf=xf, bias=-0.3, spec=False)
    for i in range(4):
        a = 2 * math.pi * i / 4 + math.pi / 4
        hx, hy = math.cos(a) * rim * 0.52, math.sin(a) * rim * 0.52
        hr = rim * 0.17
        c.ellipse(0, 0, hr * 1.25, hr, RUBBER, xf=Xf(*xf.pt(hx, hy), xf.rot + a + math.pi / 2), tone=1)
    hub = rim * 0.42
    c.ellipse(0, 0, hub, hub, RED, xf=xf)
    nb = 8 if big else 4
    for i in range(nb):
        a = 2 * math.pi * i / nb
        c.rivet(math.cos(a) * hub * 0.6 - 0.5, math.sin(a) * hub * 0.6 - 0.5, STEEL, xf=xf)
    c.ellipse(0, 0, max(1.2, hub * 0.3), max(1.2, hub * 0.3), STEEL, xf=xf)
    # a white chalk mark on the tyre so the spin reads even in silhouette
    c.lline(xf, body * 0.84, -2, body * 0.84, 2, RUBBER[3])
    if dent:
        c.lline(xf, -rim * 0.6, -rim * 0.2, -rim * 0.1, -rim * 0.6, CREAM[1])


# ------------------------------------------------------------------ body pieces (rest coordinates = frame coordinates)

def exhaust(c, bx: Xf, flap=0.0, damaged=False):
    c.tube([(176, 86, 3.4), (176, 56, 3.2), (176, 52, 3.6)], IRON, xf=bx)
    c.tube([(176, 66, 3.8), (176, 64, 3.8)], STEEL, xf=bx)  # clamp
    # the rain flap on top, hinged at the back
    fx = Xf(*bx.pt(173, 49), bx.rot - rad(flap))
    c.poly([(0, -1), (8, -1), (8, 1), (0, 1)], STEEL, xf=fx, normal=(0, -0.6))
    if damaged:
        c.lline(bx, 174, 60, 178, 72, IRON[0])


def crate(c, bx: Xf, damaged=False):
    # rear rack + fish box with fish sticking out (drawn first so the box hides their bodies)
    for fx, ang, col, big in ((37, -16, STEEL, 1.0), (47, 12, TINB, 1.15)):
        xf = Xf(*bx.pt(fx, 60), rad(ang - 90), big, big)
        c.ellipse(1, 0, 7, 3.0, col, xf=xf)
        c.poly([(6, 0), (13, -5), (11, 0), (13, 5)], col, xf=xf, normal=(0, -0.3))
    hx = Xf(*bx.pt(53, 57), rad(-62))
    c.ellipse(1, 0, 7, 3.2, STEEL, xf=hx)   # one sardine head-up, looking out, worried
    c.px(*hx.pt(4.5, -1.2), WHITE)
    c.px(*hx.pt(5.5, -1.2), "ink")
    c.lline(hx, 7, 1, 5, 1.5, STEEL[0])
    c.rect(30, 74, 58, 77, IRON, xf=bx, normal=(0, -0.5))
    c.rect(31, 58, 57, 75, WOOD, xf=bx, normal=(-0.3, -0.2))
    for y in (63, 69):
        c.lline(bx, 32, y, 56, y, WOOD[0])
    c.lline(bx, 44, 59, 44, 74, WOOD[1])
    for x, y in ((33, 60), (54, 60), (33, 71), (54, 71)):
        c.rivet(x, y, STEEL, xf=bx)
    c.text(36, 64, "PACO", "wood1", xf=bx)
    if damaged:
        c.clear_poly([(48, 58), (58, 58), (58, 66)], xf=bx)
        c.lline(bx, 48, 58, 57, 66, WOOD[0])


def seat(c, bx: Xf, sink=0.0):
    # spring stalk, pan seat, seat back (empty: the chef is drawn by the game)
    sy = sink
    for i in range(4):
        y = 72 + i * 2.2 + sy * (1 - i / 4) * 0.6
        c.tube([(68, y, 1.2), (78, y + 0.8, 1.2)], STEEL, xf=bx)
    c.tube([(56, 46 + sy, 3.0), (54, 58 + sy, 3.6), (58, 68 + sy, 3.0)], STEEL, xf=bx, rim=True)
    c.poly([(51, 43 + sy), (60, 44 + sy), (60, 66 + sy), (52, 64 + sy)], RED, xf=bx, mode="cylx", normal=(0, -0.2))
    c.lline(bx, 53, 47 + sy, 53, 62 + sy, RED[3])
    c.poly([(58, 64 + sy), (88, 63 + sy), (90, 66 + sy), (86, 71 + sy), (60, 71 + sy)], RED, xf=bx, mode="cyly")
    c.lline(bx, 60, 65 + sy, 87, 64 + sy, RED[4])


def fender(c, bx: Xf, damaged=False):
    cx, cy = REAR[0], REAR[1]
    a0, a1, n = 192, 330, 24
    pts = []
    for i in range(n + 1):
        a = rad(a0 + i * (a1 - a0) / n)
        pts.append((cx + math.cos(a) * 39, cy + math.sin(a) * 39))
    for i in range(n + 1):
        a = rad(a1 - i * (a1 - a0) / n)
        pts.append((cx + math.cos(a) * 33, cy + math.sin(a) * 33))
    c.poly(pts, RED, xf=bx, mode="dome", rim=True)
    for i in range(n):
        u0, u1 = rad(a0 + 3 + i * (a1 - a0 - 6) / n), rad(a0 + 3 + (i + 1) * (a1 - a0 - 6) / n)
        c.lline(bx, cx + math.cos(u0) * 37, cy + math.sin(u0) * 37, cx + math.cos(u1) * 37,
                cy + math.sin(u1) * 37, CREAM[3])
    for ang in (215, 250, 290):
        u = rad(ang)
        c.rivet(cx + math.cos(u) * 35, cy + math.sin(u) * 35 - 0.5, STEEL, xf=bx)
    if damaged:
        u = rad(300)
        c.lline(bx, cx + math.cos(u) * 39, cy + math.sin(u) * 39, cx + math.cos(u) * 34, cy + math.sin(u) * 34, RED[0])
        c.clear_poly([(cx + 30, cy - 22), (cx + 36, cy - 20), (cx + 33, cy - 16)], xf=bx)


def hood(c, bx: Xf, dmg=0):
    # engine block and chassis under the hood
    c.rect(96, 112, 176, 120, IRON, xf=bx, mode="cyly")
    for x in range(124, 168, 9):
        c.ellipse(x, 116, 2.5, 2.5, IRON, xf=bx)
    c.tube([(60, 112, 3), (178, 120, 3)], IRON, xf=bx)
    # the hood itself
    hp = [(94, 82), (176, 82), (183, 85), (187, 92), (188, 113), (94, 115)]
    c.poly(hp, RED, xf=bx, mode="cyly", rim=True)
    c.lline(bx, 96, 84, 176, 84, RED[4])
    c.lline(bx, 96, 85, 178, 85, RED[3])
    # grille (cream, slats)
    c.poly([(181, 88), (188, 92), (188, 113), (181, 113)], CREAM, xf=bx, normal=(0.6, 0))
    for y in range(92, 113, 3):
        c.lline(bx, 182, y, 187, y, CREAM[1])
    # fish-box planks as side armour, with the faded stencil
    c.poly([(104, 92), (172, 92), (174, 112), (103, 112)], WOOD, xf=bx, normal=(-0.15, -0.25), rim=True)
    for y in (98, 105):
        c.lline(bx, 104, y, 173, y, WOOD[1])
    for x, y in ((106, 94), (170, 94), (106, 109), (170, 109), (138, 94), (138, 109)):
        c.rivet(x, y, STEEL, xf=bx)
    c.text(109, 93, "PESCADOS Y", "red1", xf=bx)
    c.text(109, 100, "VERDURAS", "red1", xf=bx)
    c.text(109, 106, "PACO", "tinb1", xf=bx)
    # little stencil fish
    c.stamp(126, 107, ["..###.#", ".#####.", "..###.#"], {"#": "tinb1"}, xf=bx, only_on=True)
    if dmg >= 1:
        # dents: dark creases and a scorch on the hood, a plank missing
        for (x0, y0, x1, y1) in ((120, 83, 126, 88), (150, 84, 147, 90), (164, 83, 170, 87)):
            c.lline(bx, x0, y0, x1, y1, RED[0])
            c.lline(bx, x0 + 1, y0, x1 + 1, y1, RED[3])
        c.poly([(150, 99), (166, 99), (168, 105), (152, 106)], IRON, xf=bx, tone=1)
        c.lline(bx, 150, 99, 152, 106, WOOD[0])
        c.lline(bx, 166, 99, 168, 105, WOOD[0])
        c.ellipse(112, 107, 5, 3, IRON, xf=bx, tone=2)
    if dmg >= 2:
        c.ellipse(140, 86, 9, 3, IRON, xf=bx, tone=1)
        c.ellipse(172, 96, 4, 6, IRON, xf=bx, tone=1)


def firewall(c, bx: Xf):
    c.poly([(88, 74), (98, 74), (98, 112), (90, 112)], CREAM, xf=bx, normal=(-0.5, -0.2))
    c.ellipse(93, 80, 2.6, 2.6, STEEL, xf=bx)
    c.px(*bx.pt(93, 79), "red2")


def dash(c, bx: Xf, steer=0.0):
    # steering column and wheel (the chef's hands go there)
    c.tube([(98, 84, 1.6), (92, 66, 1.4)], IRON, xf=bx)
    wx = Xf(*bx.pt(91, 64), bx.rot + rad(-28 + steer))
    c.ellipse(0, 0, 2.6, 9, IRON, xf=wx)
    c.ellipse(0, 0, 1.0, 6.5, IRON, xf=wx, tone=1, seam=False)
    # bulb horn: brass trumpet forward, red bulb back
    c.tube([(100, 76, 1.2), (110, 74, 2.0), (114, 73, 3.6)], BRASS, xf=bx)
    c.ellipse(97, 77, 3.2, 2.6, RED, xf=bx)


def pan_shield(c, bx: Xf, dmg=0, xf_override: Xf | None = None):
    xf = xf_override or Xf(*bx.pt(197, 104), bx.rot)
    # handles top and bottom, then the pan seen three-quarters (its burnt inside towards us)
    c.tube([(-2, -27, 2.0), (2, -31, 2.0), (6, -28, 2.0)], IRON, xf=xf)
    c.tube([(-2, 27, 2.0), (2, 31, 2.0), (6, 28, 2.0)], IRON, xf=xf)
    c.ellipse(1, 0, 11, 28, STEEL, xf=xf, rim=True)
    c.ellipse(-0.5, 0, 8, 24, IRON, xf=xf, bias=0.3)
    c.ellipse(-1.5, -3, 5, 15, IRON, xf=xf, bias=0.75, seam=False)
    # weld beads holding it to the grille
    for y in (-10, 0, 10):
        c.rivet(-10, y, BRASS, xf=xf)
    # dents from gull pellets
    for (x, y) in ((-2, -12), (1, 8), (-3, 17)):
        c.px(*xf.pt(x, y), STEEL[4])
        c.px(*xf.pt(x + 1, y + 1), IRON[0])
    if dmg >= 1:
        c.lline(xf, -4, -18, 3, -8, STEEL[0])
        c.lline(xf, 3, -8, -2, 2, STEEL[0])


def lamp(c, bx: Xf, hanging=0.0):
    if hanging:
        a = bx.pt(176, 84)
        b = bx.pt(178 + hanging * 0.3, 96)
        c.line(a[0], a[1], b[0], b[1], "ink")
        xf = Xf(b[0], b[1] + 3, rad(70 + hanging * 4))
        c.ellipse(0, 0, 4, 4, STEEL, xf=xf)
        c.ellipse(1.5, 0, 2.2, 3, BRASS, xf=xf, tone=2)
        return
    xf = Xf(*bx.pt(174, 80), bx.rot)
    c.rect(-1, 2, 1, 5, IRON, xf=xf)
    c.ellipse(0, 0, 4.6, 4.2, STEEL, xf=xf)
    c.ellipse(1.8, -0.2, 2.2, 3.2, BRASS, xf=xf, bias=0.4)
    c.px(*xf.pt(2.4, -1.8), WHITE)


def bell(c, bx: Xf, swing=0.0):
    c.tube([(33, 60, 1.0), (33, 44, 1.0), (26, 44, 1.0)], IRON, xf=bx)
    xf = Xf(*bx.pt(26, 45), bx.rot + rad(swing))
    c.poly([(-2, 0), (2, 0), (4, 5), (6, 9), (-6, 9), (-4, 5)], BRASS, xf=xf, mode="cylx")
    c.lline(xf, -5, 7.5, 5, 7.5, BRASS[1])
    c.ellipse(0, 10.5, 1.5, 1.5, BRASS, xf=xf, tone=1)


def cannon(c, bx: Xf, ang=0.0, recoil=0.0, spin=0):
    """ang in degrees (positive = up). Returns (muzzle_cannon, muzzle_vulcan) in frame pixels."""
    # turret ring on the hood
    c.rect(116, 76, 142, 83, IRON, xf=bx, mode="cyly")
    c.poly([(121, 76), (124, 66), (132, 66), (136, 76)], IRON, xf=bx, mode="cylx")
    tx = Xf(*bx.pt(*PIVOT), bx.rot - rad(ang))
    rx = Xf(*tx.pt(-recoil, 0), tx.rot)
    # the sardine tin breech (with its rolled lid and key at the back)
    c.rect(-24, -9, 6, 8, TINB, xf=rx, mode="cyly", rim=True)
    c.rect(-24, -9, -19, 8, STEEL, xf=rx, mode="cyly")
    c.rect(1, -9, 6, 8, STEEL, xf=rx, mode="cyly")
    c.stamp(-16, -5, ["....#...........",
                      "..#####.....#...",
                      ".#######...##...",
                      "#.#######.###...",
                      ".#########.##...",
                      "..#######...#...",
                      "....#..........."], {"#": "steel3"}, xf=rx, only_on=True)
    c.lline(rx, -18, 5, 0, 5, "brass3")
    c.tube([(-26, -9, 2.4), (-28, -3, 2.4), (-26, 1, 2.0)], STEEL, xf=rx)   # rolled lid
    c.tube([(-28, -3, 0.8), (-34, -5, 0.8)], STEEL, xf=rx)                    # the key
    c.ellipse(-35, -5, 2.2, 2.2, STEEL, xf=rx)
    # drainpipe barrel with joints and a flared mouth
    c.tube([(4, 0, 6.0), (BARREL - 4, 0, 6.0)], STEEL, xf=rx, cap=False, rim=True)
    for x in (16, 34):
        c.tube([(x, 0, 6.8), (x + 3, 0, 6.8)], STEEL, xf=rx, cap=False, bias=0.1)
        c.rivet(x + 1, -5, STEEL, xf=rx)
    c.tube([(BARREL - 6, 0, 7.4), (BARREL, 0, 7.8)], IRON, xf=rx, cap=False)
    c.ellipse(BARREL, 0, 1.6, 6.4, IRON, xf=rx, tone=0)
    c.tube([(-6, 0, 3.2), (6, 0, 3.2)], BRASS, xf=Xf(*tx.pt(0, 0), tx.rot + rad(90)))  # trunnion
    c.rect(-10, -11, -4, -7, IRON, xf=rx)
    # vulcan riding on the tin: three barrels round a drum (spin shifts which barrel is lit)
    vx = Xf(*rx.pt(-12, -13), rx.rot)
    c.tube([(-4, 0, 5.0), (8, 0, 5.0)], IRON, xf=vx, rim=True)
    for k in range(3):
        off = (-2.8, 0.0, 2.8)[(k + spin) % 3]
        c.tube([(6, off, 1.5), (30, off, 1.5)], STEEL, xf=vx, tone=(3, 2, 1)[k])
    c.tube([(27, 0, 4.2), (28, 0, 4.2)], STEEL, xf=vx)
    c.tube([(10, 0, 4.4), (12, 0, 4.4)], BRASS, xf=vx)
    c.tube([(6, 0, 5.4), (7, 0, 5.4)], BRASS, xf=vx)
    m = rx.pt(BARREL + 2, 0)
    v = vx.pt(32, 0)
    return (round(m[0]), round(m[1])), (round(v[0]), round(v[1]))


# ------------------------------------------------------------------ effects

def puff(c, x, y, r, seed=0, dark=False):
    """A round cloud of three lumps (lit from the upper left)."""
    if r < 1.5:
        return
    g = rng(seed)
    if dark == "dust":
        rmp, bias = CREAM, 0.15
    elif dark:
        rmp, bias = ("smoke0", "smoke0", "smoke1", "smoke2", "smoke3"), 0.0
    else:
        rmp, bias = SMOKE, 0.3
    a = g.uniform(0, 2 * math.pi)
    lumps = [(x + math.cos(a) * r * 0.55, y + r * 0.25, r * 0.62), (x - math.cos(a) * r * 0.5, y + r * 0.3, r * 0.58),
             (x, y - r * 0.1, r * 0.8)]
    for lx, ly, lr in lumps:
        c.ellipse(lx, ly, lr, lr * 0.92, rmp, spec=not dark, bias=bias)


def flame(c, x, y, size, ang=0.0, seed=0, layers=3):
    """A tongue of fire pointing along ang (degrees, 0 = right), opaque layered tones."""
    g = rng(seed)
    xf = Xf(x, y, rad(ang))
    tones = [(FIRE, 1), (FIRE, 2), (FIRE, 3), (FIRE, 4)][:layers + 1]
    for i, (rmp, t) in enumerate(tones):
        k = 1 - i * 0.24
        L = size * k
        wid = size * 0.42 * k
        pts = [(0, -wid * 0.6)]
        n = 7
        for j in range(n + 1):
            u = j / n
            jag = (g.uniform(-0.18, 0.18) if 0 < j < n else 0) * wid
            pts.append((u * L, -wid * (1 - u) ** 0.7 * (1 + 0.25 * math.sin(u * 9 + seed)) + jag))
        for j in range(n, -1, -1):
            u = j / n
            jag = (g.uniform(-0.18, 0.18) if 0 < j < n else 0) * wid
            pts.append((u * L * 0.92, wid * (1 - u) ** 0.7 * (1 + 0.25 * math.cos(u * 8 + seed)) + jag))
        c.poly(pts, rmp, xf=xf, tone=t, seam=(i == 0))


def star_flash(c, x, y, r, ang=0.0, points=7, seed=0, tones=(1, 2, 3, 4)):
    g = rng(seed)
    for i, t in enumerate(tones):
        k = 1 - i * 0.22
        pts = []
        for j in range(points * 2):
            a = rad(ang) + math.pi * j / points
            rr = r * k * (1.0 if j % 2 == 0 else 0.45) * g.uniform(0.85, 1.1)
            pts.append((x + math.cos(a) * rr, y + math.sin(a) * rr))
        c.poly(pts, FIRE, tone=t, seam=(i == 0))


def sparks(c, x, y, n, r, seed):
    g = rng(seed)
    for _ in range(n):
        a = g.uniform(0, 2 * math.pi)
        d0, d1 = r * g.uniform(0.2, 0.6), r * g.uniform(0.7, 1.0)
        c.line(x + math.cos(a) * d0, y + math.sin(a) * d0, x + math.cos(a) * d1, y + math.sin(a) * d1,
               FIRE[4] if g.random() < 0.5 else FIRE[3])


# ------------------------------------------------------------------ the whole vehicle

def draw(st: dict) -> tuple[Canvas, dict]:
    """st keys (all optional): dx dy tilt sq rear front ang recoil spin flame vflash flap dmg swing sink hang
    puffs [(x, y, r, dark)] fx(c) after-hook. Returns the canvas and {"cannon": (x, y), "vulcan": (x, y), "seat": (x, y)}."""
    c = Canvas(W, H)
    g = st.get
    bx = pivot_xf(112, 112, rad(g("tilt", 0.0)), g("dx", 0.0), g("dy", 0.0), 1.0, g("sq", 1.0))
    dmg = g("dmg", 0)
    wl = g("wheel_dy", 0.0)
    for (x, y, r, dark) in g("back_puffs", []):
        puff(c, x, y, r, seed=int(x * 7 + y), dark=dark)
    exhaust(c, bx, g("flap", 0.0), dmg >= 1)
    crate(c, bx, dmg >= 1)
    seat(c, bx, g("sink", 0.0))
    bell(c, bx, g("swing", 0.0))
    hood(c, bx, dmg)
    firewall(c, bx)
    if g("rigid"):
        fx_, fy_ = bx.pt(FRONT[0], FRONT[1])
        rx_, ry_ = bx.pt(REAR[0], REAR[1])
        # the wheels follow the tilt but not the squash
    else:
        fx_, fy_, rx_, ry_ = FRONT[0], FRONT[1] + wl, REAR[0], REAR[1] + wl
    wheel(c, fx_, fy_, FRONT[2], g("front", 0.0), big=False, dent=dmg >= 1)
    wheel(c, rx_, ry_, REAR[2], g("rear", 0.0), big=True, dent=dmg >= 1)
    fender(c, bx, dmg >= 1)
    dash(c, bx, g("steer", 0.0))
    pan_shield(c, bx, dmg)
    if dmg >= 1:
        lamp(c, bx, hanging=g("hang", 1.0))
    else:
        lamp(c, bx)
    mc, mv = cannon(c, bx, g("ang", 0.0), g("recoil", 0.0), g("spin", 0))
    if g("flame"):
        size, seed = g("flame")
        a = -g("ang", 0.0) + g("tilt", 0.0)
        flame(c, mc[0] - 2 * math.cos(rad(a)), mc[1] - 2 * math.sin(rad(a)), size, a, seed)
        star_flash(c, mc[0], mc[1], size * 0.45, a, 6, seed, (1, 3, 4))
    if g("vflash"):
        a = -g("ang", 0.0) + g("tilt", 0.0)
        star_flash(c, mv[0] + 3 * math.cos(rad(a)), mv[1] + 3 * math.sin(rad(a)), g("vflash"), a + 20, 5, 3, (1, 3, 4))
    for (x, y, r, dark) in g("puffs", []):
        puff(c, x, y, r, seed=int(x * 13 + y * 3), dark=dark)
    if g("fx"):
        g("fx")(c)
    seat_px = bx.pt(*SEAT)
    return c, {"cannon": mc, "vulcan": mv, "seat": (round(seat_px[0]), round(seat_px[1]))}
