"""Paella de Combate: explosion / smoke / debris painters shared by the enemy deaths and the explosions sheet.

Metal Slug explosions are chunky: overlapping opaque fire lobes (pale core, orange body, red rim, dark outline) that swell
fast, then the outer lobes turn into dark rolling smoke that rises and breaks up while a few embers fall.
"""
from __future__ import annotations

import math
import random

from enemies_kit import CREAM, FIRE, SMOKE, STEEL, Canvas, Ramp
from gull_parts import T, feather, screw

EMBER = Ramp("#c02808", "#ff7010", "#ffc830", "#fff8c0", ol="#5a1408")
SOOT = Ramp("#2e2430", "#4a3c48", "#76687a", "#a89aa8", ol="#18101a")


def _lobes(seed, n, spread=0.55):
    rnd = random.Random(seed)
    out = []
    for i in range(n):
        a = i * 2 * math.pi / n + rnd.uniform(-0.35, 0.35)
        d = rnd.uniform(0.35, 1.0) * spread
        r = rnd.uniform(0.38, 0.55)
        out.append((math.cos(a) * d, math.sin(a) * d * 0.85, r))
    return out


def cloud_lobes(seed, n, R, spread=0.62, rmin=0.24, rmax=0.46):
    """A cauliflower of lobes round (0, 0): one big centre lobe and n around it (x, y, r, life)."""
    rnd = random.Random(seed)
    out = [(0.0, 0.0, R * 0.62, 1.0)]
    for i in range(n):
        a = i * 2 * math.pi / n + rnd.uniform(-0.3, 0.3)
        d = R * spread * rnd.uniform(0.75, 1.15)
        out.append((math.cos(a) * d, math.sin(a) * d * 0.85, R * rnd.uniform(rmin, rmax), rnd.uniform(0.75, 1.0)))
    return out


def paint_cloud(c: Canvas, cx, cy, lobes, heat_shift, smoke_level, smoke_ramp=SMOKE, fire=FIRE, top_bias=0.0):
    """Paint a metaball cloud. Fire tones come from the 'heat' (depth from the edge of the whole cloud toward its hot
    centre), cooling with heat_shift; pixels colder than smoke_level are smoke, lit from the upper left per lobe."""
    import numpy as np
    X, Y = c.X, c.Y
    best = np.full(X.shape, -1.0)
    nx = np.zeros(X.shape)
    ny = np.zeros(X.shape)
    for lx, ly, lr, _ in lobes:
        if lr < 1.0:
            continue
        dx, dy = X - (cx + lx), Y - (cy + ly)
        d = np.sqrt(dx * dx + dy * dy)
        f = 1 - d / lr
        take = f > best
        best = np.where(take, f, best)
        nx = np.where(take, dx / lr, nx)
        ny = np.where(take, dy / lr, ny)
    m = best > 0
    if not m.any():
        return
    # heat: distance from the cloud's (weighted) centre, normalised by its size, plus the lobe depth
    wsum = sum(lr for *_, lr, _l in lobes) or 1
    hx = cx + sum(lx * lr for lx, _, lr, _l in lobes) / wsum
    hy = cy + sum(ly * lr for _, ly, lr, _l in lobes) / wsum + top_bias
    span = max(math.hypot(lx, ly) + lr for lx, ly, lr, _ in lobes) or 1
    dc = np.hypot(X - hx, Y - hy) / span
    heat = (1 - dc) * 0.85 + best * 0.35 - heat_shift
    fire_pal = np.array([fire.ol, fire[0], fire[1], fire[2], fire[3]], np.uint8)
    fidx = np.where(heat > 0.78, 4, np.where(heat > 0.56, 3, np.where(heat > 0.34, 2, np.where(heat > 0.12, 1, 1))))
    img = fire_pal[fidx]
    smoke = m & (heat < smoke_level)
    if smoke.any():
        lam = nx * -0.6 + ny * -0.8 + np.sqrt(np.clip(1 - nx * nx - ny * ny, 0, 1)) * 0.5
        sidx = np.where(lam > 0.75, 2, np.where(lam > 0.2, 1, 0))
        spal = np.array([smoke_ramp[0], smoke_ramp[1], smoke_ramp[2]], np.uint8)
        simg = spal[sidx]
        # the smoke just outside the fire glows red underneath
        glow = smoke & (heat > smoke_level - 0.08) & (smoke_level < 0.9)
        img = np.where(smoke[..., None], simg, img)
        img = np.where(glow[..., None], np.array(fire[0], np.uint8), img)
    # a one-pixel seam where this cloud sits over earlier paint
    pad = np.pad(m, 1)
    border = m & ~(pad[:-2, 1:-1] & pad[2:, 1:-1] & pad[1:-1, :-2] & pad[1:-1, 2:])
    pa = np.pad(c.a & ~m, 1)
    seam = border & (pa[:-2, 1:-1] | pa[2:, 1:-1] | pa[1:-1, :-2] | pa[1:-1, 2:])
    c.rgb[m] = img[m]
    olc = np.where(smoke[..., None], np.array(smoke_ramp.ol, np.uint8), np.array(fire.ol, np.uint8))
    c.ol[m] = olc[m]
    c.a |= m
    c.rgb[seam] = olc[seam]


def boom(c: Canvas, cx, cy, R, k, seed=1, n=9, smoke_dark=False, rise=0.5, embers=True):
    """One explosion at age k (0..1) and radius R: flash star, swelling fireball, cooling into rising, breaking smoke."""
    if k < 0.08:  # the first flash: a white-hot star
        s = 0.5 + k * 6
        pts = []
        for i in range(16):
            a = i * math.pi / 8
            rr = R * s * (1.0 if i % 2 == 0 else 0.42)
            pts.append((cx + math.cos(a) * rr, cy + math.sin(a) * rr))
        c.poly(pts, FIRE, tone=2, seam=False)
        c.ell(cx, cy, R * s * 0.4, R * s * 0.4, FIRE, tone=3, seam=False)
        return
    g = min(1.0, (k - 0.08) / 0.3)
    s = 0.35 + 0.65 * (1 - (1 - g) ** 2.4)
    up = rise * R * max(0.0, k - 0.25)
    rnd = random.Random(seed * 3)
    lobes = []
    for lx, ly, lr, life in cloud_lobes(seed, n, R):
        age = max(0.0, k - 0.55) / 0.45
        shrink = max(0.0, 1 - (age / life) ** 1.5) if age > 0 else 1.0
        drift = 1 + 0.35 * max(0.0, k - 0.3)
        lift = up * (1.0 + 0.6 * (-ly / R)) + rnd.uniform(0, 2) * k
        lobes.append((lx * s * drift, ly * s * drift - lift, lr * s * shrink * (1 + 0.15 * max(0.0, k - 0.3)), life))
    heat_shift = max(0.0, k - 0.2) * 0.9
    smoke_level = -1.0 if k < 0.38 else (k - 0.38) * 1.8
    paint_cloud(c, cx, cy, lobes, heat_shift, smoke_level, SOOT if smoke_dark else SMOKE)
    if embers and 0.15 < k < 0.85:
        rnd = random.Random(seed * 7)
        for j in range(7):
            a = rnd.uniform(0, 2 * math.pi)
            d = R * (0.75 + 0.9 * k) * rnd.uniform(0.85, 1.2)
            ex, ey = cx + math.cos(a) * d, cy + math.sin(a) * d * 0.8 + k * k * R * 0.6
            if 3 < ex < c.w - 4 and 3 < ey < c.h - 4:
                c.ell(ex, ey, 1.7, 1.7, EMBER, tone=2, seam=False)


def puff(c: Canvas, x, y, r, ramp=SMOKE, seed=3, n=5):
    """A soft rising smoke puff: a clump of opaque round blobs (the top ones lit)."""
    for lx, ly, lr in sorted(_lobes(seed, n, 0.6), key=lambda q: -q[1]):
        c.ell(x + lx * r, y + ly * r, lr * r * 1.3, lr * r * 1.15, ramp, rim=False)


def debris(c: Canvas, cx, cy, R, k, seed=5, feathers=6, screws=4, ramp=None):
    """Feathers and screws thrown out and falling (k = age 0..1)."""
    rnd = random.Random(seed)
    for i in range(feathers + screws):
        a = rnd.uniform(-math.pi, 0.2) if i % 2 else rnd.uniform(-math.pi, math.pi)
        v = rnd.uniform(0.6, 1.1) * R
        x = cx + math.cos(a) * (R * 0.45 + v * k * 1.3)
        y = cy + math.sin(a) * (R * 0.4 + v * k) + R * 1.1 * k * k
        if not (7 < x < c.w - 7 and 7 < y < c.h - 7):
            continue
        if i < feathers:
            feather(c, x, y, a + k * rnd.uniform(3, 8), 1.0)
        else:
            screw(c, x, y, a + k * 9)
