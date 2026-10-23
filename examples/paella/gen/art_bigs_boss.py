"""Paella de Combate: El Gran Gaviotrón, the boss, painted in parts (body, head, wing, leg, pot). All look LEFT.

Each painter takes a state dict and returns a Canvas the size of its sheet frame. Joints (in boss_body pixels):
head (100, 248), wing (228, 222), leg_l (165, 296), leg_r (228, 292), pot (212, 238). The gull is white enamel
underneath, chrome-grey on the back, black-tipped wings with white "mirrors", a yellow cannon beak with the red
gonys spot, orange hydraulic legs, a red visor, a monocle and a captain's cap; a brass wind-up key in its back.
"""
from __future__ import annotations

import math

import numpy as np

from art_bigs_kit import (BEAK, BRASS, CHROME, FEATH, FIRE, GREEN, IRON, NAVY, RICE, RUST, SMOKE, VISOR, WHITE,
                          Canvas, Xf, rad, rng)

BODY = (384, 320, (192, 300))
HEAD = (192, 160, (150, 120))
WING = (256, 192, (200, 40))
LEG = (160, 192, (80, 20))
POT = (224, 192, (112, 176))
FXS = (128, 128, (64, 64))
JOINTS = {"head": (100, 248), "wing": (228, 222), "leg_l": (165, 296), "leg_r": (228, 292), "pot": (212, 238)}

DARK_SMOKE = ("smoke0", "smoke0", "smoke1", "smoke2", "smoke3")


def rot_about(px, py, deg, dx=0.0, dy=0.0, s=1.0) -> Xf:
    a = rad(deg)
    c, si = math.cos(a), math.sin(a)
    x, y = px * s, py * s
    return Xf(px + dx - (c * x - si * y), py + dy - (si * x + c * y), a, s, s)


def puff(c, x, y, r, seed=0, dark=False, clip=None):
    if r < 1.5:
        return
    g = rng(seed)
    rmp = DARK_SMOKE if dark else SMOKE
    a = g.uniform(0, 2 * math.pi)
    for lx, ly, lr in ((x + math.cos(a) * r * 0.55, y + r * 0.25, r * 0.62), (x - math.cos(a) * r * 0.5, y + r * 0.3, r * 0.58),
                       (x, y - r * 0.1, r * 0.8)):
        c.ellipse(lx, ly, lr, lr * 0.92, rmp, spec=not dark, clip=clip)


def sparks(c, x, y, n, r, seed, tones=("fire4", "fire3", "rice3")):
    g = rng(seed)
    for i in range(n):
        a = g.uniform(0, 2 * math.pi)
        d0, d1 = r * g.uniform(0.15, 0.5), r * g.uniform(0.6, 1.0)
        c.line(x + math.cos(a) * d0, y + math.sin(a) * d0, x + math.cos(a) * d1, y + math.sin(a) * d1, tones[i % len(tones)])


def star(c, x, y, r, points=8, seed=0, tones=(1, 2, 3, 4), ramp=FIRE, ang=0.0):
    g = rng(seed)
    for i, t in enumerate(tones):
        k = 1 - i * 0.2
        pts = []
        for j in range(points * 2):
            a = rad(ang) + math.pi * j / points
            rr = r * k * (1.0 if j % 2 == 0 else 0.42) * g.uniform(0.85, 1.12)
            pts.append((x + math.cos(a) * rr, y + math.sin(a) * rr))
        c.poly(pts, ramp, tone=t, seam=(i == 0))


def rivets_along(c, pts, n, ramp=CHROME, xf=Xf(), rust=False):
    for i in range(n):
        u = (i + 0.5) / n
        k = u * (len(pts) - 1)
        j = min(int(k), len(pts) - 2)
        f = k - j
        x = pts[j][0] + (pts[j + 1][0] - pts[j][0]) * f
        y = pts[j][1] + (pts[j + 1][1] - pts[j][1]) * f
        c.rivet(x, y, ramp, xf=xf)
        if rust and i % 3 == 1:
            X, Y = xf.pt(x, y)
            c.line(X + 0.5, Y + 2, X + 0.5, Y + 5, RUST[2], only_on=True)
            c.px(X + 0.5, Y + 6, RUST[1])


CHAR_MAP = {"feath": ("iron0", "smoke0", "smoke1", "smoke1", "smoke2"), "chrome": ("iron0", "iron1", "iron2", "iron3", "smoke2"),
            "brass": ("rust0", "rust1", "rust1", "rust2", "rust3"), "beak": ("rust0", "rust1", "rust2", "rust2", "rust3"),
            "visor": ("iron0", "rust1", "rust1", "rust2", "rust3"), "navy": ("iron0", "iron1", "iron1", "iron2"),
            "rice": ("iron0", "rust1", "rust2", "rust3", "rust3"), "green": ("iron0", "iron1", "iron2", "iron2")}


def char(c: Canvas):
    """Burnt to a crisp: every material drops to soot and rust tones."""
    for name in set(c.p.flatten()):
        if not name or not name[-1].isdigit():
            continue
        base, i = name.rstrip("0123456789"), int(name[len(name.rstrip("0123456789")):])
        if base in CHAR_MAP:
            m = CHAR_MAP[base]
            c.p[c.p == name] = m[min(i, len(m) - 1)]


def flash(c: Canvas, keep_outline=True):
    from art_bigs_kit import PAL
    for name in set(c.p.flatten()):
        if not name or not name[-1].isdigit() or (keep_outline and name[-1] == "0"):
            continue
        base = name.rstrip("0123456789")
        top = next((f"{base}{k}" for k in (4, 3) if f"{base}{k}" in PAL), None)
        if top:
            c.p[c.p == name] = top


# ================================================================== BODY

def torso_mask(c: Canvas, xf: Xf):
    m = np.zeros((c.h, c.w), bool)
    tmp = Canvas(c.w, c.h)
    m |= tmp.ellipse(205, 256, 122, 58, FEATH, xf=xf)
    m |= tmp.ellipse(132, 258, 64, 54, FEATH, xf=xf)
    m |= tmp.ellipse(282, 246, 58, 40, FEATH, xf=xf)
    return m


def body_key(c, phase, xf: Xf):
    """The giant wind-up key: shaft out of the back, a flat two-lobed bow turning about the shaft."""
    c.tube([(298, 226, 9), (318, 204, 9)], BRASS, xf=xf)
    c.tube([(304, 219, 11), (308, 214, 11)], BRASS, xf=xf, bias=-0.2)
    c.tube([(316, 206, 6), (338, 180, 6)], BRASS, xf=xf)
    k = math.cos(phase)
    kx = Xf(*xf.pt(338, 176), xf.rot + rad(-49))
    w = 26 * abs(k) + 3
    shade = -0.45 if k < 0 else 0.0
    for side in (-1, 1):
        if abs(k) > 0.12:
            c.ellipse(15, side * w * 0.62, 16, max(2.5, w * 0.5), BRASS, xf=kx, bias=shade)
            if abs(k) > 0.45:
                c.ellipse(18, side * w * 0.7, 7, max(1.5, w * 0.17), BRASS, xf=kx, tone=1)
    c.poly([(-4, -w * 0.5), (26, -w * 0.4), (26, w * 0.4), (-4, w * 0.5)], BRASS, xf=kx, mode="cyly", bias=shade)
    c.ellipse(-2, 0, 6, max(2.5, w * 0.35), BRASS, xf=kx)
    c.rivet(-2.5, -0.5, BRASS, xf=kx)


def body_tail(c, xf: Xf, dmg=0):
    plates = [[(286, 232), (362, 196), (376, 202), (368, 212), (300, 250)],
              [(290, 244), (370, 214), (380, 222), (372, 232), (300, 262)],
              [(292, 256), (366, 234), (374, 244), (364, 250), (300, 272)]]
    for i, p in enumerate(plates):
        if dmg >= 2 and i == 1:
            continue
        c.poly(p, FEATH, xf=xf, mode="cyly", normal=(0.2, -0.3), bias=-0.1 * i)
        tip = [p[1], p[2], p[3], ((p[3][0] + p[4][0]) / 2 + 20, (p[3][1] + p[4][1]) / 2 - 6)]
        c.poly(tip, IRON, xf=xf, normal=(0.2, -0.4))
        c.rivet(p[0][0] + 14, p[0][1] + 6 + i, CHROME, xf=xf)


def body_exhaust(c, xf: Xf, k, n, dmg=0):
    """Two stubby steam stacks under the tail, puffing backwards."""
    for i, (x, y) in enumerate(((300, 284), (316, 274))):
        c.tube([(x - 10, y + 4, 5), (x + 8, y - 2, 5)], IRON, xf=xf)
        c.tube([(x + 7, y - 1.6, 6.2), (x + 9, y - 2.2, 6.2)], CHROME, xf=xf)
    return [((330 + ((k + j * n / 2) % n) / n * 34), 270 - ((k + j * n / 2) % n) / n * 22, 4 + ((k + j * n / 2) % n) / n * 8)
            for j in range(2)]


def paint_body(st: dict) -> Canvas:
    W, H, _ = BODY
    c = Canvas(W, H)
    g = st.get
    k = g("k", 0)
    dmg = g("dmg", 0)
    xf = Xf(g("dx", 0.0), g("dy", 0.0))
    for (x, y, r) in g("back_puffs", []):
        puff(c, x, y, r, seed=int(x + y * 3), dark=dmg >= 2)
    body_key(c, g("key", 0.0), xf)
    body_tail(c, xf, dmg)
    steam = body_exhaust(c, xf, k, 6, dmg)
    # hip housings (the legs pin here)
    for j in ("leg_r", "leg_l"):
        x, y = JOINTS[j]
        c.ellipse(x, y - 4, 24, 18, CHROME, xf=xf, bias=-0.15)
    torso = torso_mask(c, xf)
    # white enamel underside, chrome-grey mantle on top
    c.ellipse(205, 256, 122, 58, FEATH, xf=xf, rim=True)
    c.ellipse(282, 246, 58, 40, FEATH, xf=xf, seam=False)
    c.ellipse(132, 258, 64, 54, FEATH, xf=xf, rim=True)
    mantle = [(60, 160), (380, 160), (380, 238), (300, 236), (240, 232), (180, 230), (130, 228), (60, 236)]
    c.poly(mantle, CHROME, xf=xf, mode="cyly", clip=torso, bias=0.05)
    c.lline(xf, 82, 236, 130, 228, CHROME[0])
    # seam where the mantle meets the white
    pts = [(78, 236), (130, 229), (180, 231), (240, 233), (300, 237), (338, 240)]
    for a, b in zip(pts, pts[1:]):
        c.lline(xf, a[0], a[1], b[0], b[1], CHROME[0])
    rivets_along(c, pts, 16, CHROME, xf, rust=True)
    # enamel feather scallops on the breast
    for row in range(4):
        y = 244 + row * 14
        for j in range(5 - row // 2):
            x = 84 + j * 18 + (row % 2) * 9
            pts = [(x - 8 + i * 2, y + math.sin(i / 8 * math.pi) * 5) for i in range(9)]
            for a2, b2 in zip(pts, pts[1:]):
                c.lline(xf, a2[0], a2[1], b2[0], b2[1], FEATH[1])
    # plate seams on the white belly (curved), with rivets
    for x0 in (186, 236, 286):
        arc = [(x0 + 6 * math.sin(t / 6), 236 + t * 12) for t in range(7)]
        arc = [(x, y) for x, y in arc if y < 312]
        for a, b in zip(arc, arc[1:]):
            c.lline(xf, a[0], a[1], b[0], b[1], FEATH[1])
        rivets_along(c, arc, 4, FEATH, xf, rust=x0 in (168, 282))
    # mantle panel lines and a stencilled serial
    for x0 in (150, 210, 270):
        c.lline(xf, x0, 202, x0 + 4, 228, CHROME[1])
        rivets_along(c, [(x0 + 3, 206), (x0 + 6, 226)], 2, CHROME, xf)
    c.text(176, 212, "GV-01", NAVY[1], xf=xf)
    # the pressure gauge on the chest, needle by state
    gx, gy = 120, 268
    c.ellipse(gx, gy, 13, 13, BRASS, xf=xf)
    c.ellipse(gx, gy, 9.5, 9.5, FEATH, xf=xf, bias=0.4, spec=False)
    for t in range(-3, 4):
        a = rad(-90 + t * 30)
        c.lline(xf, gx + math.cos(a) * 7, gy + math.sin(a) * 7, gx + math.cos(a) * 8.5, gy + math.sin(a) * 8.5, FEATH[0])
    na = rad(-90 + g("needle", -20))
    c.lline(xf, gx, gy, gx + math.cos(na) * 7, gy + math.sin(na) * 7, VISOR[1])
    c.px(*xf.pt(gx, gy), IRON[0])
    c.ellipse(gx + 3, gy + 15, 3.5, 2.6, VISOR, xf=xf, tone=4 if g("lamp", 1) else 1)   # a little warning lamp
    # neck collar and shoulder socket
    c.ellipse(0, 0, 25, 17, CHROME, xf=Xf(*xf.pt(*JOINTS["head"]), rad(-38)))
    c.ellipse(0, 0, 17, 11, IRON, xf=Xf(*xf.pt(*JOINTS["head"]), rad(-38)), bias=0.2)
    c.ellipse(*JOINTS["wing"], 22, 22, CHROME, xf=xf)
    c.ellipse(*JOINTS["wing"], 12, 12, IRON, xf=xf)
    # damage overlays
    damage_body(c, xf, dmg, k, torso)
    for (x, y, r) in steam:
        puff(c, x, y, r, seed=int(x * 7 + y), dark=dmg >= 2)
    for (x, y, r) in g("puffs", []):
        puff(c, x, y, r, seed=int(x * 11 + y), dark=dmg >= 2)
    return c


def damage_body(c, xf, dmg, k, torso):
    if dmg >= 1:   # scratches
        for (x0, y0, x1, y1) in ((150, 252, 176, 262), (156, 248, 180, 260), (240, 270, 262, 290), (96, 250, 104, 270),
                                 (250, 210, 276, 216)):
            c.lline(xf, x0, y0, x1, y1, FEATH[1])
            c.lline(xf, x0 + 1, y0 + 1, x1 + 1, y1 + 1, FEATH[4])
    if dmg >= 2:   # dents, scorch, rust bloom
        for (x, y, rx, ry) in ((196, 276, 12, 8), (268, 254, 9, 7), (110, 238, 8, 6)):
            c.ellipse(x, y, rx, ry, FEATH, xf=xf, bias=-0.7, spec=False, clip=torso)
            c.ellipse(x - 1, y - 1, rx * 0.5, ry * 0.5, RUST, xf=xf, tone=2, seam=False, clip=torso)
        c.ellipse(232, 214, 20, 9, IRON, xf=xf, tone=2, clip=torso, seam=False)
        c.ellipse(160, 300, 16, 7, IRON, xf=xf, tone=2, clip=torso, seam=False)
    if dmg >= 3:   # wrecked: plates torn off, wires and sparks
        for (x, y, rx, ry) in ((200, 262, 22, 15), (290, 254, 15, 12)):
            c.ellipse(x, y, rx, ry, IRON, xf=xf, tone=0, seam=False)
            c.ellipse(x + 2, y + 2, rx - 3, ry - 3, IRON, xf=xf, tone=1, seam=False)
            for i in range(4):
                a = rad(i * 75 + 20)
                c.tube([(x + math.cos(a) * 3, y + math.sin(a) * 3, 1.5),
                        (x + math.cos(a) * rx * 0.8, y + math.sin(a) * ry * 0.9 + 3, 1.5)],
                       (VISOR, BRASS, NAVY, GREEN)[i], xf=xf, spec=False)
            c.lline(xf, x - rx, y - ry * 0.4, x - rx - 6, y - ry * 0.8, FEATH[0], only_on=False)
            c.lline(xf, x + rx, y + ry * 0.2, x + rx + 5, y + ry * 0.6, FEATH[0], only_on=False)
        sparks(c, *xf.pt(200, 262), 8, 20, 70 + k)
        sparks(c, *xf.pt(290, 254), 6, 16, 90 + k)


# ================================================================== HEAD

def paint_head(st: dict) -> Canvas:
    W, H, (ax, ay) = HEAD
    c = Canvas(W, H)
    g = st.get
    jaw = g("jaw", 0.0)            # lower jaw opening, degrees
    tilt = g("tilt", 0.0)          # whole head about the neck top (negative = chin up / back)
    hx = rot_about(128, 106, tilt, 4 + g("dx", 0.0), g("dy", 0.0))
    dead = g("dead", 0)
    for (x, y, r) in g("back_puffs", []):
        puff(c, x, y, r, seed=int(x + y), dark=True)
    # accordion neck from the joint to the head
    top = hx.pt(130, 108)
    for i in range(5):
        u = i / 4
        x, y = ax + (top[0] - ax) * u, ay + (top[1] - ay) * u
        c.ellipse(0, 0, 9, 21 - 3 * (i % 2), CHROME, xf=Xf(x, y, rad(-40)), bias=-0.15 if i % 2 else 0.1)
    hinge = (68, 98)
    # mouth interior and the hidden cannon (under the jaws)
    if jaw > 2:
        c.poly([(80, 86), (80, 104), (12, 108 + jaw * 0.95), (6, 100)], IRON, xf=hx, tone=0)
        c.poly([(76, 92), (76, 102), (18, 106 + jaw * 0.6), (14, 100)], VISOR, xf=hx, tone=1, seam=False)
        mz = (28 - jaw * 0.25, 101 + jaw * 0.3)
        c.tube([(72, 98, 9), (mz[0] + 4, mz[1], 8)], IRON, xf=hx, rim=True)
        for x in (56, 44):
            c.tube([(x + mz[0] * 0.1, 98 + jaw * 0.15, 9.5), (x + 3 + mz[0] * 0.1, 98 + jaw * 0.15, 9.5)], CHROME, xf=hx)
        c.tube([(mz[0] + 6, mz[1], 10), (mz[0], mz[1], 10)], CHROME, xf=hx, rim=True)
        c.ellipse(mz[0] - 0.5, mz[1], 3, 7.5, IRON, xf=hx, tone=0)
        glow = g("glow", 0.0)
        if glow > 0:
            mx, my = hx.pt(mz[0] - 2, mz[1])
            for i, t in enumerate((2, 3, 4)):
                rr = glow * (1 - i * 0.3)
                if rr > 0.8:
                    c.ellipse(mx, my, rr, rr, RICE, tone=t, seam=(i == 0))
    # lower jaw (rotates about the hinge)
    ljx = rot_about(*hinge, -jaw).then(hx)
    lower = [(74, 96), (60, 106), (28, 112), (10, 112), (3, 108), (8, 104), (38, 102), (68, 94)]
    c.poly(lower, BEAK, xf=ljx, mode="cyly", normal=(0, 0.2))
    c.ellipse(20, 109, 5.5, 2.8, VISOR, xf=ljx, tone=2)      # the gull's red spot
    c.lline(ljx, 66, 100, 24, 108, BEAK[1])
    # head dome: white enamel, grey nape, panel lines
    dome = c.ellipse(98, 80, 50, 46, FEATH, xf=hx, rim=True)
    c.ellipse(132, 86, 30, 46, CHROME, xf=hx, clip=dome, bias=-0.05)
    c.lline(hx, 74, 40, 92, 35, FEATH[1])
    rivets_along(c, [(104, 40), (106, 54)], 2, FEATH, hx)
    rivets_along(c, [(110, 46), (104, 84), (110, 120)], 7, CHROME, hx, rust=True)
    for i in range(4):   # ear vent
        c.lline(hx, 116 + i * 5, 94, 120 + i * 5, 108, CHROME[0])
        c.lline(hx, 117 + i * 5, 94, 121 + i * 5, 108, CHROME[3])
    # upper beak: long, hooked, cannon bore at the tip
    up = rot_about(*hinge, jaw * 0.18).then(hx)
    upper = [(84, 74), (82, 94), (70, 100), (16, 102), (9, 106), (3, 111), (1, 104), (5, 95), (20, 88), (54, 80)]
    c.poly(upper, BEAK, xf=up, mode="cyly", normal=(0, -0.25), rim=True)
    c.lline(up, 78, 79, 20, 89, BEAK[4])
    c.lline(up, 58, 89, 48, 90, BEAK[0])                     # nostril
    c.ellipse(6, 98, 3.8, 5, IRON, xf=up)                     # the bore
    c.ellipse(6, 98, 1.8, 3, IRON, xf=up, tone=0, seam=False)
    rivets_along(c, [(76, 82), (26, 91)], 6, BEAK, up)
    # visor band, scanning light, angry brow, monocle
    v = g("visor", 0.0)
    vis = [(48, 64), (116, 54), (120, 76), (52, 90)]
    vm = c.poly(vis, VISOR, xf=hx, mode="cyly", rim=True)
    if not dead:
        sx = 56 + v * 50
        lean = (sx - 48) * 0.15
        c.poly([(sx, 64 - lean), (sx + 9, 62 - lean), (sx + 8, 86 - lean * 1.1), (sx - 1, 88 - lean * 1.1)],
               VISOR, xf=hx, tone=4, seam=False, clip=vm)
    else:
        for (x0, y0, x1, y1) in ((60, 66, 76, 84), (76, 66, 60, 84), (94, 60, 104, 74), (100, 66, 112, 58), (84, 72, 96, 80)):
            c.lline(hx, x0, y0, x1, y1, VISOR[0])
            c.lline(hx, x0 + 1, y0, x1 + 1, y1, VISOR[4])
    brow = [(44, 60), (110, 42), (124, 48), (120, 58), (50, 70)]
    c.poly(brow, CHROME, xf=rot_about(86, 56, g("brow", 0)).then(hx), mode="cyly", normal=(0, -0.3), rim=True)
    rivets_along(c, [(56, 64), (112, 50)], 4, CHROME, rot_about(86, 56, g("brow", 0)).then(hx))
    mono = g("monocle", (72, 76))
    if mono:
        mx, my = mono
        chain = [(mx + 8, my + 11), (mx + 16, my + 28), (mx + 30, my + 36), (126, 108)]
        for a2, b2 in zip(chain, chain[1:]):
            for i in range(0, 9, 2):
                u = i / 9
                c.px(*hx.pt(a2[0] + (b2[0] - a2[0]) * u, a2[1] + (b2[1] - a2[1]) * u), BRASS[3])
        c.ellipse(mx, my, 13, 13, BRASS, xf=hx, rim=True)
        c.ellipse(mx, my, 9.5, 9.5, VISOR, xf=hx, bias=0.6, seam=False)
        c.ellipse(mx + 1, my + 1, 3.6, 3.6, VISOR, xf=hx, tone=4 if not dead else 0, seam=False)
        for d in ((-5, -5), (-4, -5), (-5, -4), (-3, -6)):
            c.px(*hx.pt(mx + d[0], my + d[1]), WHITE)
    # captain's cap, tilted back
    hat = g("hat", (0.0, 0.0, -9.0))
    if hat is not None:
        hdx, hdy, hang = hat
        cx = rot_about(104, 40, hang, hdx, hdy).then(hx)
        c.ellipse(104, 28, 46, 15, FEATH, xf=cx, rim=True)            # white crown
        c.rect(64, 27, 144, 42, NAVY, xf=cx, mode="cyly")              # band
        c.lline(cx, 64, 31, 144, 31, BRASS[3])
        c.poly([(64, 40), (38, 46), (33, 52), (52, 52), (76, 45)], IRON, xf=cx, normal=(0, -0.6), rim=True)  # peak
        c.lline(cx, 40, 47, 64, 42, IRON[3])
        bx = Xf(*cx.pt(88, 33), cx.rot)
        c.stamp(-7, -4, ["##.......##", ".###...###.", "..###o###..", "....###....", ".....#....."],
                {"#": BRASS[3], "o": BRASS[1]}, xf=bx, only_on=False)
    return c


# ================================================================== WING

def wing_shapes(c, xf: Xf, st):
    g = st.get
    broken = g("broken", 0)
    flutter = g("flutter", 0.0)
    # primaries: long black-tipped feathers with white mirrors
    prim = [((128, 116), (20, 170)), ((136, 118), (30, 176)), ((146, 122), (44, 179)), ((156, 124), (60, 180)), ((166, 126), (78, 179))]
    for i, ((x0, y0), (x1, y1)) in enumerate(prim):
        if broken and i in (1, 3):
            continue
        fx = rot_about(x0, y0, flutter * (1 if i % 2 else -1) * (i + 1) * 0.4).then(xf)
        if broken:   # snapped feathers
            x1, y1 = x0 + (x1 - x0) * (0.55 + 0.1 * (i % 2)), y0 + (y1 - y0) * (0.55 + 0.1 * (i % 2))
        dx, dy = x1 - x0, y1 - y0
        L = math.hypot(dx, dy)
        ux, uy = dx / L, dy / L
        nx, ny = -uy, ux
        wdt = 9
        pts = [(x0 + nx * wdt, y0 + ny * wdt), (x1 + nx * 3, y1 + ny * 3), (x1 + ux * 4, y1 + uy * 4),
               (x1 - nx * 4, y1 - ny * 4), (x0 - nx * wdt, y0 - ny * wdt)]
        c.poly(pts, CHROME, xf=fx, normal=(-0.2, -0.3), bias=0.1 - i * 0.05)
        tip = [(x0 + dx * 0.55 + nx * 7, y0 + dy * 0.55 + ny * 7), (x1 + nx * 3, y1 + ny * 3), (x1 + ux * 4, y1 + uy * 4),
               (x1 - nx * 4, y1 - ny * 4), (x0 + dx * 0.55 - nx * 7, y0 + dy * 0.55 - ny * 7)]
        c.poly(tip, IRON, xf=fx, normal=(-0.2, -0.3))
        mx, my = x0 + dx * 0.82, y0 + dy * 0.82
        c.ellipse(mx, my, 4.5, 3, FEATH, xf=Xf(*fx.pt(mx, my), fx.rot + math.atan2(dy, dx)), bias=0.2)
        c.lline(fx, x0 + ux * 4, y0 + uy * 4, x0 + dx * 0.5, y0 + dy * 0.5, CHROME[1])
    # secondaries along the trailing edge (white edges)
    for i in range(6):
        x0, y0 = 186 - i * 12, 56 + i * 11
        x1, y1 = x0 - 8, y0 + 46 - i * 2
        pts = [(x0 + 7, y0), (x1 + 6, y1 - 4), (x1, y1 + 2), (x1 - 6, y1 - 2), (x0 - 7, y0)]
        c.poly(pts, CHROME, xf=xf, normal=(0.1, 0.2), bias=-0.1)
        c.lline(xf, x1 - 5, y1 - 1, x1 + 5, y1 - 3, FEATH[3])
    # the arm / coverts plate
    arm = [(214, 26), (226, 48), (206, 66), (170, 96), (138, 124), (106, 138), (90, 134), (96, 116), (126, 90), (164, 56), (190, 30)]
    c.poly(arm, CHROME, xf=xf, mode="dome", rim=True, bias=0.1)
    edge = [(200, 30), (160, 60), (120, 96), (96, 122)]
    for a, b in zip(edge, edge[1:]):
        c.lline(xf, a[0], a[1] + 10, b[0], b[1] + 10, CHROME[1])
    rivets_along(c, [(p[0], p[1] + 14) for p in edge], 9, CHROME, xf, rust=True)
    # leading edge white enamel strip
    c.poly([(190, 30), (164, 56), (126, 90), (96, 116), (92, 112), (122, 84), (160, 50), (186, 26)], FEATH, xf=xf, normal=(-0.3, -0.5))


def rack(c, xf: Xf, st):
    g = st.get
    rk = Xf(*xf.pt(158, 82), xf.rot + rad(-28))
    c.rect(-36, -20, 30, 20, IRON, xf=rk, normal=(0, -0.2), rim=True)
    c.rect(-32, -16, 26, 16, IRON, xf=rk, tone=1, seam=False)
    box = Canvas(c.w, c.h).rect(-32, -16, 26, 16, IRON, xf=rk)
    fired = g("fired", [])   # per rocket: distance travelled (None = in the rack)
    for i, y in enumerate((-9, 0, 9)):
        d = fired[i] if i < len(fired) else None
        if d is None:
            sardine_rocket(c, Xf(*rk.pt(-6, y), rk.rot + rad(14)), box)
    opn = g("open", 0.0)       # 0..1 cover slides up
    cover_dy = -opn * 34
    cv = Xf(*rk.pt(0, cover_dy), rk.rot)
    c.rect(-32, -16, 26, 16, CHROME, xf=cv, normal=(-0.2, -0.3), clip=box)
    c.rect(-29, -13, 23, 13, NAVY, xf=cv, mode="cyly", clip=box, rim=True)
    c.stamp(-20, -5, ["....###.....#", "..#######..##", ".##o#######.#", "..#######..##", "....###.....#"],
            {"#": BRASS[3], "o": NAVY[0]}, xf=cv, only_on=True)
    c.lline(cv, -26, 8, 20, 8, BRASS[3], only_on=True)
    c.lline(cv, -26, -9, 20, -9, VISOR[2], only_on=True)
    if opn < 0.98:
        c.lline(cv, -32, -16, 26, -16, CHROME[0])
    if opn < 0.5:
        c.tube([(-32, 12, 2.6), (-37, 8, 2.6), (-35, 3, 2.2)], CHROME, xf=cv)   # the rolled tin-lid key
        c.ellipse(-38, 1, 3, 3, CHROME, xf=cv)
    c.rect(-36, -20, 30, -16, IRON, xf=rk, normal=(0, -0.6))
    c.rivet(-34, -18, CHROME, xf=rk)
    c.rivet(27, -18, CHROME, xf=rk)
    c.rivet(-34, 17, CHROME, xf=rk)
    c.rivet(27, 17, CHROME, xf=rk)
    return rk


def sardine_rocket(c, xf: Xf, clip=None, flame=0.0, seed=0):
    """A sardine with fins and a red warhead nose, pointing left (-x)."""
    if flame > 0:
        g = rng(seed)
        for i, t in enumerate((1, 2, 3, 4)):
            L = flame * (1 - i * 0.22)
            wd = 3.6 * (1 - i * 0.2)
            c.poly([(14, -wd), (14 + L, g.uniform(-1, 1)), (14, wd)], FIRE, xf=xf, tone=t, seam=(i == 0))
    c.ellipse(0, 0, 14, 4.2, CHROME, xf=xf, clip=clip)
    c.lline(xf, -10, -1, 10, -1, CHROME[4], only_on=True)
    c.lline(xf, -8, 1.5, 9, 1.5, NAVY[3], only_on=True)
    c.poly([(11, 0), (18, -5), (16, 0), (18, 5)], CHROME, xf=xf, clip=clip)
    c.ellipse(-12, 0, 4, 3.6, VISOR, xf=xf, clip=clip)
    c.px(*xf.pt(-7, -2), IRON[0])


def paint_wing(st: dict) -> Canvas:
    W, H, (ax, ay) = WING
    c = Canvas(W, H)
    g = st.get
    xf = rot_about(ax, ay, g("rot", 0.0), g("dx", 0.0), g("dy", 0.0))
    wing_shapes(c, xf, st)
    rk = rack(c, xf, st)
    # rockets in flight (drawn over everything)
    for i, d in enumerate(g("fired", [])):
        if d is None or d < 0:
            continue
        y = (-9, 0, 9)[i]
        sx, sy = rk.pt(-6, y)
        a = rk.rot + rad(14)
        x = sx - math.cos(a) * d
        yy = sy - math.sin(a) * d
        sardine_rocket(c, Xf(x, yy, a), flame=10 + min(d, 40) * 0.35, seed=i + int(d))
    c.ellipse(ax, ay, 19, 19, CHROME, xf=Xf(g("dx", 0.0), g("dy", 0.0)), rim=True)
    c.ellipse(ax + 1, ay + 1, 8, 8, IRON, xf=Xf(g("dx", 0.0), g("dy", 0.0)))
    c.rivet(ax - 1, ay - 1, CHROME, xf=Xf(g("dx", 0.0), g("dy", 0.0)))
    if g("broken"):
        k = g("k", 0)
        for (x, y) in ((140, 120), (172, 70)):
            X, Y = xf.pt(x, y)
            c.ellipse(X, Y, 7, 5, IRON, tone=0)
            sparks(c, X, Y, 7, 18, 40 + k * 3 + x)
        c.tube([xf.pt(140, 120) + (1.2,), (*xf.pt(132, 140), 1.2), (*xf.pt(136, 152), 1.2)], VISOR, spec=False)
        c.tube([xf.pt(141, 121) + (1.2,), (*xf.pt(150, 142), 1.2), (*xf.pt(146, 156), 1.2)], NAVY, spec=False)
    for (x, y, r) in g("puffs", []):
        puff(c, x, y, r, seed=int(x * 5 + y), dark=g("broken", 0))
    return c


# ================================================================== LEG

def leg_ik(hip, ankle, l1, l2, back=1):
    hx, hy = hip
    ax, ay = ankle
    dx, dy = ax - hx, ay - hy
    d = min(math.hypot(dx, dy), l1 + l2 - 0.01)
    a = math.atan2(dy, dx)
    cosb = (l1 * l1 + d * d - l2 * l2) / (2 * l1 * d)
    b = math.acos(max(-1, min(1, cosb)))
    t = a - b * back
    return hx + math.cos(t) * l1, hy + math.sin(t) * l1


def paint_leg(st: dict) -> Canvas:
    W, H, (hx, hy) = LEG
    c = Canvas(W, H)
    g = st.get
    ank = g("ankle", (78, 158))
    pitch = g("pitch", 0.0)
    kn = leg_ik((hx, hy), ank, 80, 74, back=1)
    if g("broken"):
        kn = (kn[0] + 10, kn[1] - 4)
    for (x, y, r) in g("back_puffs", []):
        puff(c, x, y, r, seed=int(x + y))
    # thigh: armoured white drumstick
    c.tube([(hx, hy, 17), ((hx + kn[0]) / 2 + 2, (hy + kn[1]) / 2, 18), (kn[0], kn[1], 12)], FEATH, rim=True)
    th = math.atan2(kn[1] - hy, kn[0] - hx)
    for t in (0.3, 0.55, 0.78):
        x, y = hx + (kn[0] - hx) * t, hy + (kn[1] - hy) * t
        r = 22 - 10 * t
        # feather-plate scallops across the drumstick
        for j in range(-2, 3):
            q = th + math.pi / 2
            px_, py_ = x + math.cos(q) * j * r * 0.38, y + math.sin(q) * j * r * 0.38
            c.line(px_ - math.cos(th) * 3, py_ - math.sin(th) * 3 + 2, px_, py_ + 3, FEATH[1], only_on=True)
    # hydraulic piston behind the knee
    p0 = (hx + (kn[0] - hx) * 0.35 + 10, hy + (kn[1] - hy) * 0.35)
    p1 = (kn[0] + (ank[0] - kn[0]) * 0.45 + 8, kn[1] + (ank[1] - kn[1]) * 0.45)
    mid = ((p0[0] + p1[0]) / 2, (p0[1] + p1[1]) / 2)
    c.tube([(*p0, 4.5), (*mid, 4.5)], IRON)
    c.tube([(*mid, 2.2), (*p1, 2.2)], CHROME)
    # tarsus: orange, scaled like a bird leg
    c.tube([(kn[0], kn[1], 11), (ank[0], ank[1], 9)], BEAK, rim=True)
    ta = math.atan2(ank[1] - kn[1], ank[0] - kn[0])
    for i in range(1, 7):
        u = i / 7
        x, y = kn[0] + (ank[0] - kn[0]) * u, kn[1] + (ank[1] - kn[1]) * u
        c.line(x - math.sin(ta) * 9, y + math.cos(ta) * 9, x + math.sin(ta) * 9, y - math.cos(ta) * 9, BEAK[1], only_on=True)
    if g("broken"):
        c.line(*kn, ank[0] + 6, ank[1] - 30, IRON[0], 2)
    # knee ball
    c.ellipse(kn[0], kn[1], 14, 14, CHROME, rim=True)
    c.ellipse(kn[0] + 1, kn[1] + 1, 6, 6, IRON, tone=1)
    c.ellipse(kn[0] + 1, kn[1] + 1, 2.5, 2.5, RUST, tone=2)
    c.rivet(kn[0] - 1, kn[1] - 1, CHROME)
    # foot: pitched about the ankle; three webbed toes forward, a spur back
    fx = Xf(ank[0], ank[1], rad(pitch))
    toes = [(-50, 18), (-40, 22), (-26, 22)]
    if not g("broken"):
        c.poly([(-4, 6), toes[0], (-42, 20), toes[1], (-30, 21), toes[2], (-6, 14)], BEAK, xf=fx, tone=1)  # webbing
    for i, (tx, ty) in enumerate(toes):
        if g("broken") and i == 1:
            continue
        c.tube([(0, 6, 8 - i * 0.6), (tx * 0.55, ty * 0.75, 6.2 - i * 0.4), (tx, ty - 1, 4.4)], BEAK, xf=fx)
        cl = Xf(*fx.pt(tx - 1, ty - 1), fx.rot)
        c.poly([(1, -4.5), (-9, 0), (-11, 4.5), (-1, 4)], IRON, xf=cl, normal=(-0.4, -0.5), rim=True)
        c.lline(fx, tx * 0.35, ty * 0.5 - 2, tx * 0.35, ty * 0.5 + 2, BEAK[1])
        c.lline(fx, tx * 0.7, ty * 0.82 - 2, tx * 0.7, ty * 0.82 + 2, BEAK[1])
    c.tube([(4, 8, 5), (20, 18, 3.2)], BEAK, xf=fx)
    c.poly([(19, 15), (28, 21), (20, 22)], IRON, xf=fx)
    c.ellipse(0, 4, 12, 11, CHROME, xf=fx, rim=True)
    c.rivet(-3, 1, CHROME, xf=fx)
    # the hip ball (the pin)
    c.ellipse(hx, hy, 18, 18, CHROME, rim=True)
    c.ellipse(hx + 1, hy + 1, 7, 7, IRON)
    c.rivet(hx - 6, hy - 8, CHROME)
    c.rivet(hx + 7, hy - 6, CHROME)
    if g("broken"):
        sparks(c, kn[0], kn[1], 9, 20, 7 + g("k", 0) * 5)
    for (x, y, r) in g("puffs", []):
        puff(c, x, y, r, seed=int(x * 3 + y))
    for (x0, y0, x1, y1) in g("lines", []):
        c.line(x0, y0, x1, y1, FEATH[3])
    return c


# ================================================================== POT (the paellera on its back)

HATCH = (104, 106)   # centre of the hatch on the lid, pot pixels


def rice_dome(c, xf, cx, cy, rise, pulse, wide=28, garnish=True, seed=5):
    c.ellipse(cx, cy - rise * 0.5, wide + pulse * 2, 7 + rise * 0.8, RICE, xf=xf, rim=True, bias=0.35)
    c.ellipse(cx - 5, cy - rise * 0.75, wide * 0.5 + pulse * 3, 3 + rise * 0.45, RICE, xf=xf, tone=4 if pulse > 0.3 else 3, seam=False)
    gg = rng(seed)
    for i in range(34):
        a = gg.uniform(0, 2 * math.pi)
        r = gg.uniform(0.2, 0.92)
        x = cx + math.cos(a) * wide * r
        y = cy - rise * 0.5 + math.sin(a) * (6 + rise * 0.7) * r
        c.px(*xf.pt(x, y), RICE[4] if i % 3 else RICE[1])
        c.px(*xf.pt(x + 1, y), RICE[3])
    if garnish and rise > 6:   # a prawn, peas and a strip of red pepper
        pr = Xf(*xf.pt(cx + 10, cy - rise * 0.95), rad(-20))
        c.tube([(0, 0, 2.8), (5, -2, 2.6), (9, 1, 2.2), (10, 5, 1.6)], VISOR, xf=pr, bias=0.45)
        c.poly([(-1, -1), (-6, -4), (-5, 2)], VISOR, xf=pr, tone=3)
        c.line(*pr.pt(-1, -1), *pr.pt(-7, -8), VISOR[1])
        c.tube([(cx - 18, cy - rise * 0.55, 1.6), (cx - 9, cy - rise * 0.8 - 2, 1.6)], VISOR, xf=xf, tone=2)
        for (px_, py_) in ((-4, -0.6), (3, -0.25), (-13, -0.2), (18, -0.4)):
            c.ellipse(cx + px_, cy + py_ * rise - 1, 2, 1.8, GREEN, xf=xf)


def paint_pot(st: dict) -> Canvas:
    W, H, (ax, ay) = POT
    c = Canvas(W, H)
    g = st.get
    xf = Xf(g("dx", 0.0), g("dy", 0.0))
    opn = g("open", 0.0)       # 0 closed .. 1 the clamshell doors fully apart
    pulse = g("pulse", 0.0)
    cracked = g("cracked", 0)
    gone = g("gone", False)
    for (x, y, r) in g("back_puffs", []):
        puff(c, x, y, r, seed=int(x * 3 + y), dark=g("dark", False))
    # red handles, the pan wall (polished steel, armour plates), the rim
    for side in (-1, 1):
        c.tube([(ax + side * 94, 140, 3.0), (ax + side * 104, 134, 3.0), (ax + side * 106, 143, 3.0), (ax + side * 98, 150, 3.0)], VISOR, xf=xf)
    rim_out = Canvas(W, H).ellipse(ax, 140, 104, 26, IRON, xf=xf)
    c.ellipse(ax, 156, 98, 20, CHROME, xf=xf, bias=-0.15)
    c.rect(ax - 103, 140, ax + 103, 156, CHROME, xf=xf, mode="cylx", seam=False)
    wall = Canvas(W, H).ellipse(ax, 156, 98, 20, IRON, xf=xf) | Canvas(W, H).rect(ax - 103, 140, ax + 103, 156, IRON, xf=xf)
    for i in range(8):
        x0 = ax - 96 + i * 24
        sag = abs(i - 3.5) * 1.6
        c.poly([(x0 + 1, 150), (x0 + 23, 150), (x0 + 22, 170 - sag * 1.6), (x0 + 2, 170 - sag * 1.6)], CHROME, xf=xf,
               normal=((i - 3.5) * 0.17, 0.15), clip=wall & ~rim_out)
        c.rivet(x0 + 4, 152, CHROME, xf=xf)
        c.rivet(x0 + 19, 152, CHROME, xf=xf)
        if i % 3 == 1:
            c.lline(xf, x0 + 4, 155, x0 + 4, 160, RUST[2])
    c.lline(xf, ax - 102, 150, ax + 102, 150, CHROME[0])
    # rim lip and the golden socarrat ring inside it
    c.ellipse(ax, 140, 104, 26, CHROME, xf=xf, bias=0.2)
    c.ellipse(ax, 139, 97, 22, RICE, xf=xf, tone=1)
    gg = rng(1)
    for i in range(60):
        a = gg.uniform(0, 2 * math.pi)
        x, y = ax + math.cos(a) * gg.uniform(88, 95), 139 + math.sin(a) * gg.uniform(17, 20.5)
        c.px(*xf.pt(x, y), RICE[3] if i % 2 else RICE[0])
    if gone:
        c.ellipse(ax, 139, 90, 18, IRON, xf=xf, tone=1, seam=False)
        c.ellipse(ax, 141, 80, 14, RUST, xf=xf, tone=0, seam=False)
        for i in range(26):
            gg2 = rng(i + 3)
            c.ellipse(ax + gg2.uniform(-76, 76), 141 + gg2.uniform(-11, 11), 2.5, 1.6, RICE if i % 3 else IRON, xf=xf,
                      tone=1, seam=False)
        return finish_pot(c, xf, st)
    # the armoured lid dome
    lid = [(ax + math.cos(math.pi + math.pi * i / 24) * 86, 138 + math.sin(math.pi + math.pi * i / 24) * 42) for i in range(25)]
    lid += [(ax + math.cos(math.pi * i / 12) * 86, 138 + math.sin(math.pi * i / 12) * 17) for i in range(13)]
    lm = c.poly(lid, CHROME, xf=xf, mode="dome", rim=True, bias=0.05)
    for t in (-0.7, -0.35, 0.0, 0.35, 0.7):
        pts = [(ax + t * 86 * (0.15 + 0.85 * v), 138 + 17 * v * math.sqrt(1 - t * t) - 42 * math.sqrt(max(0, 1 - t * t)) * (1 - v)) for v in
               [j / 8 for j in range(9)]]
        for a2, b2 in zip(pts, pts[1:]):
            c.lline(xf, a2[0], a2[1], b2[0], b2[1], CHROME[1])
    band = [(ax + math.cos(math.pi * i / 20) * 86, 138 + math.sin(math.pi * i / 20) * 17 - 5) for i in range(21)]
    for a2, b2 in zip(band, band[1:]):
        c.lline(xf, a2[0], a2[1], b2[0], b2[1], CHROME[0])
        c.lline(xf, a2[0], a2[1] + 1, b2[0], b2[1] + 1, CHROME[3])
    rivets_along(c, [(p[0], p[1] - 3) for p in band], 16, CHROME, xf, rust=True)
    # the hatch: hazard ring, clamshell doors that slide apart, the saffron core underneath
    hx_, hy_ = HATCH
    c.ellipse(hx_, hy_, 40, 14, BEAK, xf=xf, tone=3)
    for i in range(12):
        a = 2 * math.pi * i / 12
        c.poly([(hx_ + math.cos(a) * 40, hy_ + math.sin(a) * 14), (hx_ + math.cos(a + 0.26) * 40, hy_ + math.sin(a + 0.26) * 14),
                (hx_ + math.cos(a + 0.4) * 31, hy_ + math.sin(a + 0.4) * 10.5), (hx_ + math.cos(a + 0.14) * 31, hy_ + math.sin(a + 0.14) * 10.5)],
               IRON, xf=xf, tone=1, seam=False)
    c.ellipse(hx_, hy_, 40, 14, BEAK, xf=xf, flat=BEAK[0], seam=False, clip=~Canvas(W, H).ellipse(hx_, hy_, 39, 13, BEAK, xf=xf))
    hole = c.ellipse(hx_, hy_, 31, 10.5, IRON, xf=xf, tone=0)
    if opn > 0:
        c.ellipse(hx_, hy_ + 1, 29, 9, RICE, xf=xf, tone=2, seam=False, clip=hole)
        rise = 3 + 12 * opn + pulse * 3
        rice_dome(c, xf, hx_, hy_ + 2, rise, pulse, garnish=opn > 0.6)
        if opn > 0.8:   # glow rays (opaque)
            for i in range(9):
                a = rad(200 + i * 17.5 + pulse * 6)
                r0, r1 = 34 + pulse * 2, 42 + (i % 2) * 6 + pulse * 5
                c.line(*xf.pt(hx_ + math.cos(a) * r0, hy_ - rise * 0.6 + math.sin(a) * r0 * 0.6),
                       *xf.pt(hx_ + math.cos(a) * r1, hy_ - rise * 0.6 + math.sin(a) * r1 * 0.6), RICE[4] if i % 2 else RICE[3], w=2)
    ring = Canvas(W, H).ellipse(hx_, hy_, 33, 11.5, IRON, xf=xf)
    for side in (-1, 1):
        d = opn * 30
        door = [(hx_, hy_ - 10.5)] + [(hx_ + side * math.sin(math.pi * j / 12) * 31, hy_ - math.cos(math.pi * j / 12) * 10.5)
                                       for j in range(13)]
        dx = Xf(*xf.pt(side * d, opn * 3), 0)
        dm = c.poly(door, CHROME, xf=dx, mode="dome", bias=0.1 - 0.2 * (side > 0), clip=ring)
        c.lline(dx, hx_ + side * 1, hy_ - 10, hx_ + side * 1, hy_ + 10, CHROME[0])
        for j in range(3):
            c.poly([(hx_ + side * (5 + j * 8), hy_ - 9 + j), (hx_ + side * (9 + j * 8), hy_ - 9 + j),
                    (hx_ + side * (9 + j * 8), hy_ + 9 - j), (hx_ + side * (5 + j * 8), hy_ + 9 - j)], BEAK, xf=dx, tone=3, seam=False, clip=dm)
        X, Y = dx.pt(hx_ + side * 24, hy_ - 2)
        if ring[int(Y), int(X)]:
            c.rivet(hx_ + side * 24, hy_ - 2, CHROME, xf=dx)
    c.tube([(hx_ - 4, hy_ - 13, 2.6), (hx_ + 4, hy_ - 13, 2.6)], IRON, xf=xf)   # the latch
    # flag and a steam whistle
    fp = (166, 116)
    c.tube([(fp[0], fp[1], 1.5), (fp[0] - 1, 80, 1.5)], IRON, xf=xf)
    c.ellipse(fp[0] - 1, 79, 2.4, 2.4, BRASS, xf=xf)
    ph = g("wave", 0.0)
    top_ = [(fp[0] + i * 5, 82 + 2 * math.sin(ph + i * 0.9)) for i in range(6)]
    bot_ = [(fp[0] + i * 5, 98 + 2 * math.sin(ph + i * 0.9 + 0.4) - i * 0.7) for i in range(5, -1, -1)]
    fm = c.poly(top_ + bot_, FEATH, xf=xf, normal=(0, -0.2))
    c.stamp(fp[0] + 7, 86 + 2 * math.sin(ph + 2.2), ["#.....#", "##...##", ".##.##.", "..###..", "...#..."], {"#": VISOR[2]}, xf=xf)
    c.tube([(ax + 46, 112, 3), (ax + 46, 100, 3)], BRASS, xf=xf)
    c.ellipse(ax + 46, 99, 4.4, 2.4, BRASS, xf=xf)
    if cracked:
        cr = [[(ax - 70, 128), (ax - 58, 120), (ax - 62, 112), (ax - 50, 104)],
              [(ax + 30, 136), (ax + 40, 124), (ax + 34, 116), (ax + 48, 108), (ax + 46, 100)],
              [(ax - 34, 140), (ax - 24, 130), (ax - 36, 120), (ax - 30, 112)]][:cracked]
        for line in cr:
            for a2, b2 in zip(line, line[1:]):
                c.lline(xf, a2[0], a2[1], b2[0], b2[1], RICE[3], w=2)
                c.lline(xf, a2[0] + 1, a2[1] + 1, b2[0] + 1, b2[1] + 1, CHROME[0])
    return finish_pot(c, xf, st)


def finish_pot(c, xf, st):
    g = st.get
    for (x, y, r) in g("puffs", []):
        puff(c, x, y, r, seed=int(x * 9 + y), dark=g("dark", False))
    for j, (x0, y0, x1, y1, w) in enumerate(g("jets", [])):
        for i in range(5):   # a hissing jet of steam: puffs growing along the line
            u = i / 4
            r = w * (0.5 + u * 0.9)
            c.ellipse(x0 + (x1 - x0) * u, y0 + (y1 - y0) * u, r, r * 0.85, SMOKE, bias=0.3, spec=False, seam=(i == 4))
    return c
