"""Botín: enemies and the boss (El Gran Gólem de Oro). Sheets ENEMY16, ENEMY32, BOSS64, BOSS32; banks enemigo_a..d, jefe_a, jefe_b.

The pictures are painted by a small shaded-shape renderer (spheres, tubes, polygons lit from the upper left, quantised to the 3-tone ramps
of a bank, then a one-pixel outline) plus hand-placed pixel details (eyes, mouths, teeth, cracks).

Slot meaning, the same in every enemy bank (so a picture drawn with another bank is that enemy's kind in another level):
    1        outline (deep saturated tone of the bank, never black)
    2 3 4    ramp A: the body (shadow, mid, light)
    5 6 7    ramp B: second material (shell, leaf, rock, fins)
    8 9 a    ramp C: warm accent (mouths, cheeks, claws, flame)
    b c d    ramp D: light accent (eyes glow, beaks, sparks, bellies)
    e        cream (eye whites, teeth)        f  white (specular)
Boss banks (jefe_a gold, jefe_b the same golem red-hot when enraged):
    1 outline   2 3 4 5 gold (dark..pale)   6 7 8 stone   9 a b gem   c glow orange   d glow cyan   e cream   f white
"""
from __future__ import annotations

import math
import sys
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent))
from gbakit import ART, ART_DIR, blank, flip_h, flip_v, outline, preview_sheet, shift, to_image  # noqa: E402

# ------------------------------------------------------------------ palettes

ART.palette("obj", "enemigo_a", [  # Selva: orange fur, lime leaf, red, yellow
    "#3a1048", "#a03c18", "#e07030", "#f8a050", "#1f8a3a", "#58c030", "#b8f058",
    "#a01848", "#e83860", "#ff98a8", "#d89020", "#f8d048", "#fff8a8", "#fff0e0", "#ffffff"])
ART.palette("obj", "enemigo_b", [  # Cristal: violet body, cyan crystal, pink, lime glow
    "#200c48", "#6020a8", "#a048e0", "#dc98ff", "#1070c0", "#30c8f0", "#b0f8ff",
    "#b01870", "#f050a8", "#ffb0dc", "#70b018", "#c8f040", "#f8ffb8", "#f0f0ff", "#ffffff"])
ART.palette("obj", "enemigo_c", [  # Galeón: coral body, teal, jelly magenta, yellow
    "#10204a", "#c02838", "#f86048", "#ffb488", "#087880", "#20b8a8", "#98f4d8",
    "#982890", "#e060d0", "#ffb8f0", "#d08800", "#f8c818", "#fff488", "#fff8e0", "#ffffff"])
ART.palette("obj", "enemigo_d", [  # Fragua: crimson body, basalt violet, orange flame, yellow flame
    "#300818", "#a01028", "#e02838", "#ff7860", "#4a3888", "#7a66c4", "#bcaaf4",
    "#d04000", "#f88010", "#ffbc40", "#e8b000", "#fff040", "#fffcc8", "#fff0e0", "#ffffff"])
ART.palette("obj", "jefe_a", [  # the golem: gold plates, lavender stone, ruby gem
    "#3a0c28", "#a04808", "#e08c10", "#f8c830", "#fff4a8", "#4a3878", "#7a68b0", "#b4a4d8",
    "#a00840", "#f02860", "#ff98b8", "#ff6a10", "#40d0ff", "#fff0d8", "#ffffff"])
ART.palette("obj", "jefe_b", [  # enraged: the gold red-hot, the stone scorched
    "#3a0810", "#a01808", "#e04818", "#f89038", "#ffe0a0", "#581830", "#904068", "#c880a8",
    "#a00840", "#f02860", "#ff98b8", "#fff040", "#ff6040", "#fff0d8", "#ffffff"])

A, B, C, D = (2, 3, 4), (5, 6, 7), (8, 9, 10), (11, 12, 13)
CREAM, WHITE, OL = 14, 15, 1
GOLD, STONE, GEM = (2, 3, 4, 5), (6, 7, 8), (9, 10, 11)
GLOW, CYAN = 12, 13
LIGHT = (-0.55, -0.83)


# ------------------------------------------------------------------ the renderer

class Canvas:
    """Shaded shapes painted in order (later over earlier); a part over another gets a dark seam where they meet."""

    def __init__(self, w: int, h: int):
        self.w, self.h = w, h
        self.p = blank(w, h)

    # region builders: dict (x, y) -> (nx, ny) the surface normal's x, y (|n| <= 1)
    def _ell(self, cx, cy, rx, ry, wob=None):
        reg = {}
        for y in range(max(0, int(cy - ry - 3)), min(self.h, int(cy + ry + 4))):
            for x in range(max(0, int(cx - rx - 3)), min(self.w, int(cx + rx + 4))):
                dx, dy = x + 0.5 - cx, y + 0.5 - cy
                k = 1.0
                if wob:
                    k = wob(math.atan2(dy, dx))
                nx, ny = dx / (rx * k), dy / (ry * k)
                if nx * nx + ny * ny <= 1.0:
                    reg[(x, y)] = (nx, ny)
        return reg

    def _tube(self, pts):
        reg = {}
        xs = [p[0] for p in pts]
        ys = [p[1] for p in pts]
        rm = max(p[2] for p in pts) + 2
        for y in range(max(0, int(min(ys) - rm)), min(self.h, int(max(ys) + rm + 1))):
            for x in range(max(0, int(min(xs) - rm)), min(self.w, int(max(xs) + rm + 1))):
                px, py = x + 0.5, y + 0.5
                best = None
                for (ax, ay, ar), (bx, by, br) in zip(pts, pts[1:]):
                    vx, vy = bx - ax, by - ay
                    ll = vx * vx + vy * vy or 1e-9
                    t = max(0.0, min(1.0, ((px - ax) * vx + (py - ay) * vy) / ll))
                    qx, qy, r = ax + vx * t, ay + vy * t, ar + (br - ar) * t
                    d = math.hypot(px - qx, py - qy)
                    if d <= r and (best is None or d / r < best[0]):
                        best = (d / r, (px - qx) / r, (py - qy) / r)
                if best:
                    reg[(x, y)] = (best[1], best[2])
        return reg

    def _poly(self, pts, normal=(0.0, 0.0), sphere=None):
        reg = {}
        ys = [p[1] for p in pts]
        for y in range(max(0, int(min(ys))), min(self.h, int(max(ys)) + 1)):
            cy = y + 0.5
            xs = []
            for (ax, ay), (bx, by) in zip(pts, pts[1:] + pts[:1]):
                if (ay <= cy < by) or (by <= cy < ay):
                    xs.append(ax + (cy - ay) * (bx - ax) / (by - ay))
            xs.sort()
            for a, b in zip(xs[::2], xs[1::2]):
                for x in range(max(0, int(math.ceil(a - 0.5))), min(self.w, int(math.floor(b - 0.5)) + 1)):
                    if sphere:
                        scx, scy, sr = sphere
                        nx, ny = (x + 0.5 - scx) / sr, (y + 0.5 - scy) / sr
                        k = math.hypot(nx, ny)
                        reg[(x, y)] = (nx / k * 0.97, ny / k * 0.97) if k > 0.97 else (nx, ny)
                    else:
                        reg[(x, y)] = normal
        return reg

    def _paint(self, reg, ramp, seam=True, spec=False, bias=0.0, flat=None, belly=None):
        if seam:
            border = [(x, y) for (x, y) in reg if any((x + dx, y + dy) not in reg and 0 <= x + dx < self.w and 0 <= y + dy < self.h
                                                       and self.p[y + dy][x + dx] for dx, dy in ((1, 0), (-1, 0), (0, 1), (0, -1)))]
        for (x, y), (nx, ny) in reg.items():
            if flat is not None:
                self.p[y][x] = flat
                continue
            z = math.sqrt(max(0.0, 1 - nx * nx - ny * ny))
            v = 0.45 * z + 0.75 * -(nx * LIGHT[0] + ny * LIGHT[1]) + bias
            n = len(ramp)
            if n == 3:
                i = 0 if v < 0.12 else 1 if v < 0.62 else 2
            elif n == 4:
                i = 0 if v < 0.0 else 1 if v < 0.42 else 2 if v < 0.8 else 3
            else:
                i = min(n - 1, max(0, int((v + 0.3) * n / 1.4)))
            self.p[y][x] = ramp[i]
            if belly and nx * belly[0] + ny * belly[1] > belly[2]:
                self.p[y][x] = belly[3][min(i, len(belly[3]) - 1)]
            if spec and v > 1.08 and z > 0.5:
                self.p[y][x] = WHITE
        if seam:
            for x, y in border:
                self.p[y][x] = OL

    def ell(self, cx, cy, rx, ry, ramp, wob=None, **kw):
        self._paint(self._ell(cx, cy, rx, ry, wob), ramp, **kw)

    def tube(self, pts, ramp, **kw):
        self._paint(self._tube(pts), ramp, **kw)

    def poly(self, pts, ramp, normal=(0.0, 0.0), sphere=None, **kw):
        self._paint(self._poly(pts, normal, sphere), ramp, **kw)

    def cols(self, x0, x1, top, bot, v):
        """A shape by columns: for each x, rows from top(x) to bot(x), flat slot v."""
        for x in range(max(0, x0), min(self.w, x1 + 1)):
            t, b = top(x + 0.5), bot(x + 0.5)
            for y in range(max(0, int(round(t))), min(self.h, int(round(b)))):
                self.p[y][x] = v

    def cut(self, pts):
        """Clear a polygon (a notch, a gap between jaws)."""
        for x, y in self._poly(pts):
            self.p[y][x] = 0

    def px(self, x, y, v):
        x, y = int(x), int(y)
        if 0 <= x < self.w and 0 <= y < self.h:
            self.p[y][x] = v

    def line(self, x0, y0, x1, y1, v):
        x0, y0, x1, y1 = int(round(x0)), int(round(y0)), int(round(x1)), int(round(y1))
        dx, dy = abs(x1 - x0), -abs(y1 - y0)
        sx, sy = (1 if x0 < x1 else -1), (1 if y0 < y1 else -1)
        err = dx + dy
        while True:
            self.px(x0, y0, v)
            if x0 == x1 and y0 == y1:
                return
            e2 = 2 * err
            if e2 >= dy:
                err += dy
                x0 += sx
            if e2 <= dx:
                err += dx
                y0 += sy

    def stamp(self, rows, x, y):
        """Hand pixels: hex slots, '.' leaves what is there, '0' clears."""
        if isinstance(rows, str):
            rows = rows.strip("\n").split("\n")
        for j, r in enumerate(rows):
            for i, ch in enumerate(r):
                if ch == ".":
                    continue
                if ch == "0":
                    if 0 <= x + i < self.w and 0 <= y + j < self.h:
                        self.p[y + j][x + i] = 0
                else:
                    self.px(x + i, y + j, int(ch, 16))

    def done(self, ol=OL):
        return outline(self.p, ol)


def fuzz(n=9, amp=0.13, phase=0.0):
    return lambda a: 1.0 + amp * math.cos(n * a + phase)


def rot_ccw(p):
    """A quarter turn anticlockwise (lossless): the top goes left; a right-facing creature then lies on its back."""
    n = len(p)
    return [[p[x][n - 1 - y] for x in range(n)] for y in range(n)]


STAR = ["..d..", ".dfd.", "..d.."]


def stars(p, cx, cy, k, r=6):
    """Two little stars circling over a dazed head (k = the frame)."""
    out = [row[:] for row in p]
    for j in range(2):
        a = k * 1.6 + j * math.pi
        x, y = int(cx + math.cos(a) * r) - 2, int(cy + math.sin(a) * r * 0.35) - 1
        for dy, row in enumerate(STAR):
            for dx, ch in enumerate(row):
                if ch != "." and 0 <= y + dy < len(out) and 0 <= x + dx < len(out[0]):
                    out[y + dy][x + dx] = int(ch, 16)
    return outline_keep(out)


def outline_keep(p):
    """An outline round anything new that has none (stars added after the outline)."""
    return outline(p, OL)


def squash(k):
    """(sx, sy) for a squash amount k (>0 squashed, <0 stretched)."""
    return 1 + 0.5 * k, 1 - k


# ------------------------------------------------------------------ registration

E16 = ART.sheet("ENEMY16", 16, 16, "enemigo_a")
E32 = ART.sheet("ENEMY32", 32, 32, "enemigo_a")
B64 = ART.sheet("BOSS64", 64, 64, "jefe_a")
B32 = ART.sheet("BOSS32", 32, 32, "jefe_a")
STRIPS: list[tuple[str, object, list[str]]] = []


def reg(sheet, kind, frames: dict, bank):
    for name, p in frames.items():
        sheet.add(f"{kind}_{name}", p, bank)
    groups: dict[str, list[str]] = {}
    for name in frames:
        groups.setdefault(name.rstrip("0123456789").rstrip("_") or "anim", []).append(f"{kind}_{name}")
    for g, names in groups.items():
        STRIPS.append((f"{kind}_{g}", sheet, names))


# ================================================================== ENEMY16

def face_angry(c, x, y, mood="angry"):
    """Two big eyes with brows looking right; (x, y) is the top-left of a 7x5 face box."""
    p = {
        "angry": "1.....1|.11.11.|.ee.ee.|.e1.e1.|.e1.e1.",
        "calm": ".......|.......|.ee.ee.|.e1.e1.|.e1.e1.",
        "dazed": ".......|1.1.1.1|.1...1.|1.1.1.1|.......",
        "squeeze": ".......|11...11|..1.1..|11...11|.......",
        "shock": ".......|.ee.ee.|.ee.ee.|.e1.e1.|.ee.ee.",
        "hurt": ".......|.1...1.|..1.1..|.1...1.|.......",
    }[mood]
    c.stamp(p.split("|"), x, y)


def pelusa(sq=0.0, step=0, dy=0, mood="angry", mouth="frown", upside=False, kick=0):
    c = Canvas(16, 16)
    sx, sy = squash(sq)
    rx, ry = 5.4 * sx, 5.0 * sy
    cx, cy = 7.5, 12.4 - ry + dy
    # little feet (back one darker, drawn first)
    fy = 13.6 + (0 if not kick else -1)
    c.ell(cx - 2.3 + step, fy - (1 if step < 0 else 0), 1.9, 1.3, C)
    c.ell(cx + 2.6 - step, fy - (1 if step > 0 else 0) - kick, 1.9, 1.3, C)
    c.ell(cx, cy, rx, ry, A, wob=fuzz(11, 0.12), spec=True)
    fx, fy2 = int(cx) - 1, int(cy - 3)
    face_angry(c, fx, fy2, mood)
    if mouth == "frown":
        c.stamp(["..111", ".1..."], fx + 2, fy2 + 6)
    elif mouth == "teeth":
        c.stamp(["11111", "1e1e1"], fx + 1, fy2 + 6)
    elif mouth == "open":
        c.stamp([".111.", "18881", ".111."], fx + 1, fy2 + 5)
    p = c.done()
    return flip_v(p) if upside else p


def pelusa_frames():
    f = {}
    for i, (sq, st, dy) in enumerate([(0.12, 1, 0), (-0.06, 0, -1), (0.12, -1, 0), (-0.06, 0, -1)]):
        f[f"walk_{i}"] = pelusa(sq, st, dy, mouth="teeth")
    # stunned: on its back, dazed, feet up wiggling
    f["stun_0"] = shift(pelusa(0.15, 1, 0, "dazed", "open", upside=True), 0, 2)
    f["stun_1"] = shift(pelusa(0.10, -1, 0, "dazed", "open", upside=True), 0, 2)
    f["held_0"] = pelusa(-0.12, 1, 0, "squeeze", "open", kick=1)
    f["held_1"] = pelusa(-0.04, -1, -1, "squeeze", "teeth", kick=0)
    f["hurt"] = pelusa(0.3, 0, 0, "hurt", "open")
    return f


def fogata(phase=0, grow=0.0, mood="calm", sq=0.0):
    """A living flame blob: a round body with three tongues that sway; layered orange / yellow / cream."""
    c = Canvas(16, 16)
    cx, rx = 7.5, 5.6 * (1 + 0.4 * sq)
    base = 14.4
    by = 3.6 * (1 - sq)

    def top(scale, sway):
        def f(x):
            u = (x - cx) / (rx * scale)
            if abs(u) >= 1:
                return 99
            t = base - by * scale - (by + 0.6) * scale * math.sqrt(1 - u * u)
            for tx, th, tw in ((-3.2, 2.6, 1.5), (0.4, 5.6 + grow, 1.9), (3.6, 3.0, 1.4)):
                tx += sway
                t -= th * scale * math.exp(-((x - cx - tx * scale) / (tw * scale)) ** 2)
            return t
        return f

    def bot(scale):
        def f(x):
            u = (x - cx) / (rx * scale)
            if abs(u) >= 1:
                return -99
            return base - by * scale + (by * 0.85) * scale * math.sqrt(1 - u * u) + (1 - scale) * 2
        return f

    sw = [0.0, 1.4, 0.3, -1.3][phase % 4]
    c.cols(0, 15, top(1.0, sw), bot(1.0), 8)
    c.cols(0, 15, lambda x: top(1.0, sw)(x - 0.6) + 0.9, bot(0.92), 9)
    c.cols(0, 15, top(0.66, sw * 0.6), bot(0.66), 12)
    c.cols(0, 15, lambda x: top(0.34, sw * 0.3)(x) - 1.2, lambda x: bot(0.36)(x) - 1.6, 14)
    ey = int(base - by - 1.5)
    if mood == "calm":
        c.stamp(["e1.e1", "e1.e1"], 7, ey)
        c.stamp(["1..1", ".11."], 8, ey + 3)
    elif mood == "angry":
        c.stamp(["1....1", ".1..1.", ".11.11", ".11.11", "......", ".1111.", ".1ee1."], 6, ey - 2)
    else:  # hurt
        c.stamp(["1...1", ".1.1.", "1...1", ".....", ".111."], 7, ey - 1)
    return c.done()


def fogata_frames():
    f = {f"idle_{i}": fogata(i, 0.0, "calm", [0.0, 0.06, 0.0, -0.06][i]) for i in range(4)}
    for i in range(3):
        f[f"angry_{i}"] = fogata(i * 2 + 1, [1.0, 2.2, 1.6][i], "angry", [0.1, -0.12, -0.05][i])
    f["hurt"] = fogata(0, -2.5, "hurt", 0.25)
    return f


def gusanito(phase=0, upside=False, held=0, mood="calm", flat=0.0):
    """A harmless caterpillar: a plump green body in three humps, pale belly stripes, a big yellow head; inches along."""
    c = Canvas(16, 16)
    pts = []
    for i in range(5):
        x = 1.9 + i * 2.0
        if held:
            y = 9.2 + 0.55 * (i - 2.4) ** 2 + (0.7 if (i + held) % 2 else -0.3)
        else:
            hump = [0.0, 0.8, 1.9, 0.8, 0.0][(i + phase) % 4 if i in (1, 2, 3) else 0] if i in (1, 2, 3) else 0.0
            y = 11.4 - hump * (1 - flat) + flat
        r = [1.5, 2.2, 2.4, 2.4, 2.3][i] * (1 - flat * 0.25)
        pts.append((x, y, r))
    for x, y, r in pts[1:]:  # stubby feet
        c.px(x, y + r + 0.3, OL)
    c.tube(pts, B, bias=0.12)
    for x, y, r in pts[1:4]:  # segment creases and a light dot on each hump
        c.px(x + 1, y, 5)
        c.px(x + 1, y + 1, 5)
        c.px(x - 0.5, y - r + 1.2, 7)
    hx, hy = 11.9, (pts[4][1] - 1.6 if held else 9.3 + flat * 1.8 - (0.5 if phase % 2 else 0))
    c.line(hx - 0.8, hy - 2.6, hx - 2.0, hy - 5.0, OL)  # back antenna
    c.px(hx - 2.0, hy - 5.5, 9)
    c.ell(hx, hy, 3.0, 3.0 * (1 - flat * 0.3), D, seam=False)
    c.line(hx + 1.0, hy - 2.8, hx + 2.0, hy - 5.2, OL)
    c.px(hx + 2.0, hy - 5.7, 9)
    ex, ey = int(hx) + 1, int(hy - 0.9)
    if mood == "calm":
        c.stamp(["1f", "11"], ex, ey)
        c.px(ex - 2, ey + 2, 9)
        c.stamp(["1.", ".1"], ex, ey + 2)
    elif mood == "dazed":
        c.stamp(["1.1", ".1.", "1.1"], ex - 1, ey)
    else:
        c.stamp(["1..", ".1.", "1..", "...", ".11"], ex, ey)
    p = c.done()
    return shift(flip_v(p), 0, 1) if upside else p


def gusanito_frames():
    f = {f"walk_{i}": gusanito(i) for i in range(4)}
    f["stun_0"] = gusanito(0, upside=True, mood="dazed")
    f["stun_1"] = gusanito(2, upside=True, mood="dazed")
    f["held_0"] = gusanito(0, held=1, mood="hurt")
    f["held_1"] = gusanito(0, held=2, mood="hurt")
    f["hurt"] = gusanito(0, mood="hurt", flat=0.6)
    return f


def _spots(c, cx, cy, r, ang, slot, n=3, rr=0.55):
    for k in range(n):
        a = ang + k * 2 * math.pi / n
        x, y = cx + math.cos(a) * r * rr, cy + math.sin(a) * r * rr
        c.px(x, y, slot)
        c.px(x + 1, y, slot)


def bichito(step=0, upside=False, mood="calm", held=0, sq=0.0):
    """A tiny shiny beetle: a dome shell with light spots, a dark head with a white eye, three busy legs."""
    c = Canvas(16, 16)
    base = 14
    legy = base - 1
    for k, lx in enumerate((5, 8, 11)):
        off = [(-1, 0), (1, 0), (0, -1), (0, 0)][(step + k * 2) % 4] if not held else ((-1 if (held + k) % 2 else 1), 0)
        c.line(lx, legy - 2, lx + off[0], legy + off[1], OL)
        c.px(lx + off[0] + 1, legy + off[1], OL)
    sx, sy = squash(sq)
    c.ell(11.8, base - 5.0, 2.7, 2.5, (5, 6, 7), seam=False)  # head
    c.ell(7.4, base - 6.0, 5.4 * sx, 4.2 * sy, C, spec=True)
    c.line(3.0, base - 3.0, 12.0, base - 3.0, OL)  # shell rim
    for x, y in ((5, base - 8), (8, base - 9), (10, base - 7), (6, base - 6)):
        c.px(x, y, 13)
    if mood == "calm":
        c.stamp(["e1", "e1"], 12, base - 6)
    elif mood == "dazed":
        c.stamp(["1.1", ".1.", "1.1"], 12, base - 6)
    else:
        c.stamp(["1.", ".1", "1."], 13, base - 6)
    c.line(13, base - 7, 14, base - 9, OL)  # feeler
    p = c.done()
    return shift(flip_v(p), 0, 1) if upside else p


def bichito_ball(k):
    c = Canvas(16, 16)
    c.ell(7.5, 9.0, 5.4, 5.2, C, spec=True)
    a = k * math.pi / 2 * 0.5
    c.line(7.5 + math.cos(a) * 5, 9 + math.sin(a) * 5, 7.5 - math.cos(a) * 5, 9 - math.sin(a) * 5, OL)
    _spots(c, 7.5, 9.0, 5.2, a + 0.8, 13, 3, 0.5)
    c.px(7.5 + math.cos(a + 1.6) * 2.2, 9 + math.sin(a + 1.6) * 2.2, 8)
    return c.done()


def bichito_frames():
    f = {f"walk_{i}": bichito(i) for i in range(4)}
    f.update({f"ball_{i}": bichito_ball(i) for i in range(4)})
    f["stun_0"] = bichito(0, upside=True, mood="dazed")
    f["stun_1"] = bichito(1, upside=True, mood="dazed")
    f["held_0"] = bichito(0, mood="hurt", held=1, sq=-0.1)
    f["held_1"] = bichito(0, mood="hurt", held=2, sq=0.05)
    f["hurt"] = bichito(0, mood="hurt", sq=0.3)
    return f


ROCK = [(5.0, 0.0), (4.0, 0.8), (4.6, 1.6), (3.6, 2.3), (4.8, 3.1), (4.2, 3.9), (5.2, 4.7), (3.8, 5.5)]


def rock(k):
    c = Canvas(16, 16)
    a = k * math.pi / 8
    pts = [(7.8 + r * math.cos(t + a), 8.2 + r * math.sin(t + a)) for r, t in ROCK]
    c.poly(pts, B, sphere=(7.8, 8.2, 5.4), spec=True)
    for r0, r1, t in ((0.6, 3.4, 1.2), (1.6, 3.0, 4.2)):
        c.line(7.8 + r0 * math.cos(t + a), 8.2 + r0 * math.sin(t + a), 7.8 + r1 * math.cos(t + a + 0.3), 8.2 + r1 * math.sin(t + a + 0.3), 5)
    return c.done()


def coconut(k):
    c = Canvas(16, 16)
    c.ell(7.8, 8.2, 5.2, 5.0, A, spec=True)
    a = k * math.pi / 2 + 0.6
    for j in range(3):  # the three dark eyes of a coconut, turning
        t = a + j * 0.7
        c.px(7.8 + math.cos(t) * 2.2, 8.2 + math.sin(t) * 2.2, OL)
    for j in range(5):  # fibres
        t = a + 2.4 + j * 0.8
        c.px(7.8 + math.cos(t) * 4.0, 8.2 + math.sin(t) * 4.0, 2)
    return c.done()


def bomb(k):
    c = Canvas(16, 16)
    c.ell(7.0, 9.6, 5.0, 4.9, B, spec=True)
    c.poly([(8.6, 3.2), (11.6, 5.2), (10.4, 7.0), (7.4, 5.0)], (5, 6, 7), normal=(-0.2, -0.6))
    fuse = [(10.6, 4.4), (11.6, 3.4), (12.4, 3.0), (13.0, 2.0)][: 4 - (k // 2)]
    for (x0, y0), (x1, y1) in zip(fuse, fuse[1:]):
        c.line(x0, y0, x1, y1, 10)
    sx, sy = fuse[-1]
    star = ["f", ".c.|cfc|.c.", "9.9|.f.|9.9", ".c.|cfc|.c."][k]
    rows = star.split("|")
    c.stamp(rows, int(sx) - len(rows[0]) // 2, int(sy) - len(rows) // 2 - 1)
    p = c.done()
    for y, x in ((0, 13), (1, 14)) if k % 2 else ((0, 12), (1, 11)):
        if not p[y][x]:
            p[y][x] = 12  # flying sparks
    return p


def projectile_frames():
    f = {f"rock_{i}": rock(i) for i in range(4)}
    f.update({f"coconut_{i}": coconut(i) for i in range(4)})
    f.update({f"bomb_{i}": bomb(i) for i in range(4)})
    return f


# ================================================================== ENEMY32

EYES = {  # a 4x5 eye looking right, by mood
    "open": ".ee.|ee11|ee11|eeee|.ee.",
    "angry": "....|ee11|ee11|eeee|.ee.",
    "dazed": "1..1|.11.|.11.|1..1|....",
    "squeeze": "....|11..|..11|11..|....",
    "shut": "....|....|1111|.11.|....",
    "wide": "eeee|ee11|ee11|eeee|eeee",
}


def eye(c, x, y, mood="open", brow=0):
    """brow: +1 slants down toward the front (angry), -1 the other way, 0 none."""
    c.stamp(EYES[mood].split("|"), x, y)
    if brow:
        c.line(x - 1, y - (1 if brow > 0 else 0) - 1 + (1 if brow > 0 else 0) * 0, x + 4, y + (1 if brow > 0 else -1) - 1, OL)
        c.line(x - 1, y - (2 if brow > 0 else 0), x + 4, y + (0 if brow > 0 else -2), OL)


def snake_head(c, hx, hy, mood="angry", open_=0, tongue=0, sq=0.0):
    sx, sy = squash(sq)
    c.ell(hx, hy, 6.2 * sx, 4.7 * sy, B, belly=(0.1, 1, 0.45, (11, 12, 12)), spec=True)
    c.ell(hx + 4.4, hy + 0.9, 3.5 * sx, 3.0 * sy, B, seam=False, belly=(0, 1, 0.3, (11, 12, 13)))
    if open_:
        c.poly([(hx - 0.5, hy + 1), (hx + 8.5, hy - 2.5 - open_), (hx + 8.5, hy + 4 + open_)], (8, 8, 9), normal=(0.3, 0.2))
        c.line(hx + 0.5, hy + 1, hx + 7, hy + 1.5, 10)
        c.px(hx + 6, hy - 1 - open_ * 0.6, CREAM)
        c.px(hx + 6, hy - 0 - open_ * 0.6, CREAM)
        c.px(hx + 6, hy + 3 + open_ * 0.6, CREAM)
    else:
        c.line(hx + 1, hy + 1.6, hx + 7, hy + 1.4, OL)
        c.px(hx + 6.5, hy - 0.4, OL)  # nostril
    if tongue:
        tx, ty = hx + 7.6 + (open_ * 0.5), hy + 1.6
        c.line(tx, ty, tx + tongue, ty, 9)
        c.px(tx + tongue + 1, ty - 1, 9)
        c.px(tx + tongue + 1, ty + 1, 9)
    ey = hy - 4.2 * sy + 0.5
    c.ell(hx + 0.6, ey + 1.2, 2.3, 2.1, D, seam=True)
    if mood in ("angry", "open"):
        c.line(hx + 0.6, ey + 0.4, hx + 0.6, ey + 2.4, OL)
        c.line(hx + 1.6, ey + 0.4, hx + 1.6, ey + 2.4, OL)
        c.line(hx - 2.2, ey - 0.6, hx + 3.0, ey + 0.8, OL)
    else:
        c.stamp(EYES[mood].split("|")[1:4], int(hx - 1), int(ey))


def snake_body(c, pts, back=True):
    c.tube(pts, B, belly=(0.85, 0.5, 0.5, (11, 12, 13)), bias=0.05)
    if back:  # diamond marks along the back
        for (ax, ay, _), (bx, by, br) in list(zip(pts, pts[1:]))[1:]:
            mx, my = (ax + bx) / 2, (ay + by) / 2
            nx, ny = by - ay, -(bx - ax)
            k = math.hypot(nx, ny) or 1
            px, py = mx - nx / k * br * 0.35, my - ny / k * br * 0.35
            c.stamp(["1.", "51", "1."], int(px), int(py) - 1)


def serpiente(kind="idle", k=0):
    c = Canvas(32, 32)
    c.tube([(10, -4, 1.4), (10, 1, 1.4)], (5, 6, 7), seam=False)  # vine stub it hangs from
    tongue, mood, open_, sq = 0, "angry", 0, 0.0
    if kind == "idle":
        sw = math.sin(k * math.pi / 2)
        pts = [(11, -3, 2.6), (11 + sw * 0.8, 4, 2.8), (10 + sw * 1.8, 10, 3.0), (11 + sw * 1.5, 15.5, 3.2), (14 + sw * 0.6, 19, 3.2)]
        hx, hy = 18.5 + sw * 0.6, 20.0 + abs(sw) * 0.5
        tongue = [0, 3, 0, 2][k]
    elif kind == "strike":
        if k == 0:  # anticipation: coiled up and back
            pts = [(11, -3, 2.6), (12, 2, 2.9), (8, 7, 3.1), (9, 12, 3.3), (13, 13, 3.3)]
            hx, hy, mood, sq = 16.5, 12.0, "angry", 0.12
        elif k == 1:  # the lunge
            pts = [(11, -3, 2.5), (12, 4, 2.6), (15, 10, 2.8), (19, 14, 2.9), (21, 16.5, 3.0)]
            hx, hy, open_, sq = 23.5, 17.5, 2, -0.08
        else:
            pts = [(11, -3, 2.6), (11, 4, 2.8), (12, 10, 3.0), (14, 15, 3.2), (17, 18, 3.2)]
            hx, hy, open_ = 21.0, 19.5, 1
    elif kind == "stun":
        sw = [0.6, -0.6][k]
        pts = [(11, -3, 2.6), (11 + sw, 5, 2.7), (11 - sw, 12, 2.8), (12, 18, 2.9)]
        hx, hy, mood, tongue = 14.5 + sw, 23.5, "dazed", 2
    elif kind == "held":
        w = [1, -1][k]
        c = Canvas(32, 32)
        pts = [(3, 17 + w, 1.8), (7, 13 - w, 2.6), (12, 18 + w, 3.0), (17, 13 - w, 3.1), (20, 15, 3.1)]
        hx, hy, mood, open_ = 23.5, 15.0 - w * 0.5, "squeeze", 1
    else:  # hurt
        pts = [(11, -3, 2.6), (11, 4, 2.8), (10, 10, 3.0), (11, 15.5, 3.2), (14, 19.5, 3.2)]
        hx, hy, mood, sq, open_ = 18.5, 21.0, "squeeze", 0.3, 1
    snake_body(c, pts)
    snake_head(c, hx, hy, mood, open_, tongue, sq)
    return c.done()


def serpiente_frames():
    f = {f"idle_{i}": serpiente("idle", i) for i in range(4)}
    f.update({f"strike_{i}": serpiente("strike", i) for i in range(3)})
    f.update({f"stun_{i}": serpiente("stun", i) for i in range(2)})
    f.update({f"held_{i}": serpiente("held", i) for i in range(2)})
    f["hurt"] = serpiente("hurt")
    return f


def monkey(arm_pose="rest", k=0, mood="angry", mouth="grin", nut=None, sq=0.0, dy=0.0, tail=0.0, legs="sit"):
    c = Canvas(32, 32)
    sx, sy = squash(sq)
    by = 22.5 + dy
    c.tube([(10, by + 2, 1.6), (5, by - 2, 1.6), (4 + tail, by - 9, 1.5), (7 + tail, by - 12, 1.4), (9 + tail, by - 10, 1.3)], A)  # tail
    # far arm
    arm_far = {"rest": [(17, by - 4, 1.8), (21, by + 1, 1.7)], "up": [(17, by - 5, 1.8), (21, by - 13, 1.7)],
               "flail": [(17, by - 5, 1.8), (22 + k, by - 13 + k * 2, 1.7)]}.get(arm_pose, [(17, by - 4, 1.8), (21, by + 1, 1.7)])
    c.tube(arm_far, (2, 2, 3))
    c.ell(arm_far[-1][0] + 0.6, arm_far[-1][1] + 0.6, 1.9, 1.7, D)
    c.ell(14.5, by, 7.0 * sx, 6.4 * sy, A)  # body
    c.ell(16.5, by + 1, 4.2 * sx, 4.6 * sy, D, seam=False)  # belly
    if legs == "sit":
        c.ell(11.5, by + 6.2 * sy, 3.4, 1.9, D)
        c.ell(20.0, by + 6.2 * sy, 3.4, 1.9, D)
    else:  # kicking
        c.tube([(12, by + 4, 2.0), (9 - k, by + 8, 1.8)], A)
        c.tube([(18, by + 4, 2.0), (21 + k, by + 8 - k, 1.8)], A)
        c.ell(9 - k, by + 8.5, 2.3, 1.6, D)
        c.ell(21 + k, by + 8.5 - k, 2.3, 1.6, D)
    hx, hy = 17.0, by - 11.5 + (0.6 if sq > 0 else 0)
    c.ell(hx - 7.0, hy + 0.5, 2.6, 3.0, A)  # ear
    c.ell(hx - 7.0, hy + 0.7, 1.4, 1.8, (8, 9, 9), seam=False)
    c.ell(hx, hy, 7.0 * sx, 6.2 * sy, A, spec=True)  # head
    c.ell(hx + 2.4, hy - 0.8, 5.0, 3.6, (11, 12, 12), seam=False)  # face mask
    c.ell(hx + 3.4, hy + 3.0, 4.2, 2.8, (11, 12, 13), seam=False)  # muzzle
    ex, ey = int(hx), int(hy - 3)
    if mood in ("angry", "open"):
        c.stamp(["eee.eee", "e11.e11", "e11.e11"], ex, ey)
        if mood == "angry":
            c.line(ex - 1, ey - 2, ex + 2, ey - 1, OL)
            c.line(ex + 4, ey - 1, ex + 7, ey - 2, OL)
    elif mood == "dazed":
        c.stamp(["1.1.1.1", ".1...1.", "1.1.1.1"], ex, ey)
    else:
        c.stamp(["11...11", "..1.1..", "11...11"], ex, ey)
    c.px(hx + 6, hy + 2, OL)  # nostril
    mx, my = int(hx + 2), int(hy + 4)
    if mouth == "grin":
        c.stamp(["1111111", ".1e1e1."], mx - 1, my)
    elif mouth == "open":
        c.stamp([".11111.", "1eeeee1", "1888881", ".11111."], mx - 1, my - 1)
    elif mouth == "hoot":
        c.stamp([".111.", "18881", ".111."], mx + 1, my - 1)
    # near arm and what it holds
    near = {"rest": [(12, by - 4, 2.0), (14, by + 2.5, 1.8)],
            "back": [(12, by - 4, 2.0), (6, by - 10, 1.8)],
            "up": [(12, by - 5, 2.0), (12, by - 15, 1.8)],
            "fwd": [(13, by - 5, 2.0), (25, by - 8, 1.8)],
            "down": [(13, by - 4, 2.0), (22, by + 1, 1.8)],
            "flail": [(12, by - 5, 2.0), (8 - k, by - 13 + k, 1.8)]}[arm_pose]
    c.tube(near, A)
    nx_, ny_ = near[-1][0], near[-1][1]
    if nut:
        c.ell(nx_ + nut[0], ny_ + nut[1], 3.2, 3.0, A, spec=True)
        c.px(nx_ + nut[0] + 1, ny_ + nut[1], OL)
        c.px(nx_ + nut[0] - 1, ny_ + nut[1] - 1, OL)
    c.ell(nx_ + 0.5, ny_ + 0.5, 2.0, 1.8, D)
    return c.done()


def mono_frames():
    f = {}
    for i in range(4):
        f[f"idle_{i}"] = monkey("rest", mood="angry", mouth=["grin", "grin", "hoot", "grin"][i], sq=[0.0, 0.05, 0.0, -0.04][i],
                                tail=[0, 1, 2, 1][i], dy=[0, 0.4, 0, -0.4][i])
    f["throw_0"] = monkey("back", nut=(-1, -2), mouth="grin", sq=0.08)
    f["throw_1"] = monkey("up", nut=(0, -2.5), mouth="open", sq=-0.08, dy=-1)
    f["throw_2"] = monkey("fwd", mouth="hoot", sq=0.05)
    f["throw_3"] = monkey("down", mouth="grin")
    for i in range(2):
        f[f"stun_{i}"] = stars(monkey("rest", mood="dazed", mouth="open", legs="kick", k=i, sq=0.18, dy=1), 16, 4, i)
    f["held_0"] = monkey("flail", k=0, mood="squeeze", mouth="open", legs="kick", sq=-0.1, dy=-2)
    f["held_1"] = monkey("flail", k=1, mood="squeeze", mouth="open", legs="kick", sq=-0.05, dy=-2)
    f["hurt"] = monkey("rest", mood="squeeze", mouth="open", sq=0.25)
    return f


def bat(wing=0.0, mood="angry", mouth="fangs", sq=0.0, fold=False, swoop=None):
    """A front-on cave bat: round violet body, tall ears, membrane wings with dark finger bones, glowing eyes."""
    c = Canvas(32, 32)
    sx, sy = squash(sq)
    cx, cy = 16.0, 15.5
    if swoop is not None:  # wings swept up and back in a dive
        for m in (1, -1):
            sh = (cx + m * 3.5, cy - 1)
            tip = (cx + m * (8.0 + swoop * 3), cy - 12 + swoop * 3)
            pts = [sh, (cx + m * 5.5, cy - 8), tip, (cx + m * (6 + swoop * 2), cy - 6 + swoop * 2), (cx + m * 5, cy - 2), (cx + m * 4, cy + 2)]
            c.poly(pts, (2, 2, 3), sphere=(cx, cy, 16))
            c.line(sh[0], sh[1], tip[0], tip[1], OL)
    elif not fold:
        a = math.radians(wing)
        for m in (1, -1):
            sh = (cx + m * 3.5, cy - 1.5)
            el = (cx + m * (3.5 + 6.0 * math.cos(a + 0.35)), cy - 1.5 - 6.0 * math.sin(a + 0.35) - 1)
            tip = (cx + m * (3.5 + 12.5 * math.cos(a)), cy - 1.5 - 12.5 * math.sin(a))
            low = (cx + m * 3.2, cy + 4.5)
            pts = [sh, el, tip]
            for j in range(1, 4):  # scalloped trailing edge: three fingers
                t = j / 4
                fx, fy = tip[0] + (low[0] - tip[0]) * t, tip[1] + (low[1] - tip[1]) * t
                pts.append((fx - m * 1.4 * (1 if j % 2 else 0) + m * 0.5, fy - 1.6 + 2.8 * (j % 2 == 0)))
            pts.append(low)
            c.poly(pts, (2, 2, 3), sphere=(cx + m * 6, cy - 4, 13))
            c.line(el[0], el[1], tip[0], tip[1], OL)
            for j in (1, 3):
                t = j / 4
                c.line(el[0], el[1], tip[0] + (low[0] - tip[0]) * t, tip[1] + (low[1] - tip[1]) * t + 0.5, OL)
            c.line(sh[0], sh[1], el[0], el[1], OL)
    for m in (1, -1):  # ears
        c.poly([(cx + m * 1.2, cy - 3), (cx + m * 4.6, cy - 11.5 * sy), (cx + m * 5.2, cy - 3)], A, normal=(m * 0.2, -0.5))
        c.poly([(cx + m * 2.4, cy - 4), (cx + m * 4.4, cy - 9.5 * sy), (cx + m * 4.4, cy - 4)], C, normal=(0, 0), seam=False)
    if fold:  # wrapped in its wings
        c.ell(cx, cy + 1.5, 7.0, 9.0 * sy, (2, 2, 3), spec=False)
        c.line(cx - 3, cy - 4, cx - 4, cy + 9, OL)
        c.line(cx + 3, cy - 4, cx + 4, cy + 9, OL)
        c.ell(cx, cy - 1, 4.4, 4.6, A, spec=True)
    else:
        c.ell(cx, cy, 5.4 * sx, 5.8 * sy, A, spec=True)
        c.ell(cx, cy + 2.6, 3.2 * sx, 2.8 * sy, (3, 4, 4), seam=False)  # chest fluff
        for m in (-1, 1):
            c.px(cx + m * 2 - 0.5, cy + 6 * sy, OL)
    ex, ey = int(cx - 4), int(cy - 3)
    if mood == "angry":
        c.stamp(["1......1", ".11..11.", "dd1.dd1.", "dd1.dd1."], ex, ey - 1)
    elif mood == "open":
        c.stamp(["........", "dd...dd.", "dd1..d1.", "........"], ex + 1, ey - 1)
    elif mood == "shut":
        c.stamp(["........", "........", ".11..11.", "1..11..1"], ex, ey - 1)
    elif mood == "dazed":
        c.stamp(["1.1..1.1", ".1....1.", "1.1..1.1"], ex, ey)
    else:
        c.stamp(["11....11", "..1..1..", "11....11"], ex, ey)
    mx, my = int(cx - 2), int(cy + 1)
    if mouth == "fangs":
        c.stamp(["11111", ".e.e."], mx, my)
    elif mouth == "open":
        c.stamp(["11111", "1e8e1", ".888.", "..1.."], mx, my)
    elif mouth == "small":
        c.stamp([".111."], mx, my)
    return c.done()


def murcielago_frames():
    wings = [40, 15, -15, -35, -10, 20]
    f = {f"fly_{i}": shift(bat(wings[i], sq=[-0.05, 0, 0.06, 0.08, 0.02, -0.03][i]), 0, [-1, 0, 1, 1, 0, -1][i]) for i in range(6)}
    f["hang_0"] = flip_v(bat(fold=True, mood="shut", mouth="small"))
    f["hang_1"] = flip_v(bat(fold=True, mood="open", mouth="fangs", sq=-0.05))
    for i in range(3):
        f[f"swoop_{i}"] = bat(mood="angry", mouth="open", swoop=[0.0, 0.6, 1.4][i], sq=[-0.12, -0.15, -0.05][i])
    for i in range(2):
        f[f"stun_{i}"] = stars(shift(bat([-40, -45][i], mood="dazed", mouth="open", sq=0.1), 0, 6), 16, 5, i, 7)
    f["held_0"] = bat(55, mood="squeeze", mouth="open", sq=-0.1)
    f["held_1"] = bat(-25, mood="squeeze", mouth="open", sq=0.05)
    f["hurt"] = bat(5, mood="hurt", mouth="open", sq=0.25)
    return f


SHELL = [(4.5, 21.5), (6, 15.5), (10, 11), (16, 9), (22, 10.5), (26, 15), (27.5, 21.5)]


def beetle(step=0, head=True, dy=0.0, shine=-1, mood="angry", legs="walk", sq=0.0):
    """An armoured beetle with a faceted crystal shell over a violet body: only a ground pound cracks it."""
    c = Canvas(32, 32)
    base = 27.5
    oy = dy + (base - 27.5)
    c.ell(15, 22 + oy, 10.0, 3.4, A)  # belly under the shell
    if legs != "none":
        for k, lx in enumerate((9, 15, 21)):
            ph = (step + k * 2) % 4
            if legs == "walk":
                dx, lift = [(-2, 0), (0, -1), (2, 0), (0, 0)][ph]
            else:
                dx, lift = ((-2, -2) if (step + k) % 2 else (2, -1))
            c.line(lx, 22 + oy, lx + dx * 0.5, 25 + oy + lift, OL)
            c.line(lx + dx * 0.5, 25 + oy + lift, lx + dx, 27 + oy + lift, OL)
            c.px(lx + dx + 1, 27 + oy + lift, OL)
    sx, sy = squash(sq)
    T = lambda x, y: (16 + (x - 16) * sx, 21.5 + (y - 21.5) * sy + oy)  # noqa: E731
    for x, y, h, w in ((10.5, 12.5, 6, 2.2), (16.5, 10.5, 8, 2.6), (21.5, 12.0, 5, 2.0)):  # crystal spikes
        c.poly([T(x - w, y + 2), T(x, y - h), T(x, y + 2)], B, normal=(-0.6, -0.6), seam=False)
        c.poly([T(x, y + 2), T(x, y - h), T(x + w, y + 2)], B, normal=(0.7, 0.3), seam=False)
    pts = [T(x, y) for x, y in SHELL]
    ridge = [T(11.5, 15.5), T(18.5, 14.5)]
    for i, (p0, p1) in enumerate(zip(pts, pts[1:])):
        ctr = ridge[0] if i < 3 else ridge[1]
        mx, my = (p0[0] + p1[0]) / 2 - ctr[0], (p0[1] + p1[1]) / 2 - ctr[1]
        k = math.hypot(mx, my) or 1
        c.poly([ctr, p0, p1], B, normal=(mx / k * 0.8, my / k * 0.8), seam=False)
        if i == shine:
            c.line(p0[0], p0[1], ctr[0], ctr[1], WHITE)
    c.poly([ridge[0], pts[3], ridge[1]], B, normal=(0.1, -0.85), seam=False)
    c.poly([ridge[0], ridge[1], (16, 21.5 + oy)], B, normal=(0.15, 0.1), seam=False)
    for p in (pts[2], pts[3], pts[4]):
        c.line(ridge[0 if p[0] < 17 else 1][0], ridge[0 if p[0] < 17 else 1][1], p[0], p[1], 7)
    c.line(ridge[0][0], ridge[0][1], ridge[1][0], ridge[1][1], 7)
    c.line(pts[0][0], pts[0][1], pts[-1][0], pts[-1][1], OL)
    c.px(ridge[0][0] - 1, ridge[0][1] - 2, WHITE)
    if head:
        c.ell(26.5, 20.0 + oy, 4.2, 3.8, A, spec=True)
        c.poly([(28, 18.5 + oy), (31, 16 + oy), (30.5, 19 + oy), (29, 20 + oy)], D, normal=(0.2, -0.6))  # horn
        if mood == "angry":
            c.stamp(["11..", ".1dd", ".ddd", "..dd"], 25, int(17.5 + oy))
        elif mood == "dazed":
            c.stamp(["1.1", ".1.", "1.1"], 26, int(18.5 + oy))
        else:
            c.stamp(["1..", ".1.", "1.."], 27, int(18.5 + oy))
        c.stamp(["1.1", ".1."], 28, int(22 + oy))
    return c.done()


def escarabajo_frames():
    f = {f"walk_{i}": beetle(i, dy=[0, -0.6, 0, -0.6][i]) for i in range(4)}
    for i in range(3):
        f[f"shell_{i}"] = beetle(0, head=False, dy=2.5, shine=[1, 3, 5][i], legs="none")
    f["stun_0"] = shift(flip_v(beetle(0, mood="dazed", legs="kick")), 0, -1)
    f["stun_1"] = shift(flip_v(beetle(1, mood="dazed", legs="kick")), 0, -1)
    f["held_0"] = beetle(0, mood="hurt", legs="kick", sq=-0.06)
    f["held_1"] = beetle(1, mood="hurt", legs="kick", sq=0.04)
    f["hurt"] = beetle(0, mood="hurt", sq=0.18, dy=1)
    return f


def puffer(r=6.5, k=0, spines=0, mood="angry", mouth="pout", upside=False, sq=0.0):
    """A yellow puffer fish with teal spots; it swells into a spiky ball."""
    c = Canvas(32, 32)
    cx, cy = 15.5, 16.0
    sx, sy = squash(sq)
    rx, ry = (r + 1.6) * sx, r * sy
    wig = [0, 1.2, 0, -1.2][k % 4]
    t0 = cx - rx + 1.5
    c.poly([(t0, cy), (t0 - 5.5, cy - 4.5 + wig), (t0 - 4, cy + wig * 0.5), (t0 - 5.5, cy + 4.5 + wig)], C, normal=(-0.3, 0))  # tail
    c.poly([(cx - 3, cy - ry + 1), (cx - 1, cy - ry - 3 + (k % 2)), (cx + 2, cy - ry + 1)], C, normal=(0, -0.5))  # dorsal fin
    if spines:
        n = 14
        for j in range(n):
            a = j * 2 * math.pi / n + 0.2
            x0, y0 = cx + math.cos(a) * (rx - 0.5), cy + math.sin(a) * (ry - 0.5)
            x1, y1 = cx + math.cos(a) * (rx + spines), cy + math.sin(a) * (ry + spines)
            c.line(x0, y0, x1, y1, CREAM)
    c.ell(cx, cy, rx, ry, D, spec=True, belly=(0, 1, 0.45, (13, 14, 14)))
    for j, (u, v) in enumerate(((-0.45, -0.5), (0.0, -0.7), (-0.7, -0.05), (0.35, -0.35), (-0.25, -0.15))):
        c.px(cx + u * rx, cy + v * ry, 5)
        if r > 8:
            c.px(cx + u * rx + 1, cy + v * ry, 5)
    fy = cy + ry * 0.25
    c.ell(cx - 1 + (k % 2) * 0.5, fy, 2.6, 1.6 + (k % 2) * 0.6, C)  # side fin
    ex, ey = int(cx + rx * 0.3), int(cy - ry * 0.55)
    c.stamp(EYES[{"angry": "angry", "dazed": "dazed", "squeeze": "squeeze"}.get(mood, mood)].split("|"), ex, ey)
    if mood == "angry":
        c.line(ex - 1, ey - 1, ex + 4, ey + 1, OL)
    mx, my = int(cx + rx - 1.5), int(cy + ry * 0.15)
    if mouth == "pout":
        c.stamp(["88", "91"], mx, my)
    else:
        c.stamp([".1.", "181", ".1."], mx, my)
    p = c.done()
    return flip_v(p) if upside else p


def pez_globo_frames():
    f = {f"swim_{i}": shift(puffer(6.5, i), 0, [0, -1, 0, 1][i]) for i in range(4)}
    for i in range(4):
        f[f"puff_{i}"] = puffer([7.5, 9.5, 11.0, 11.5][i], i, spines=[0, 1, 2, 2][i], mouth="o", sq=[0.1, -0.05, 0.03, 0][i])
    f["stun_0"] = puffer(6.5, 0, mood="dazed", mouth="o", upside=True)
    f["stun_1"] = shift(puffer(6.5, 1, mood="dazed", mouth="o", upside=True), 0, -1)
    f["held_0"] = puffer(8.0, 1, spines=1, mood="squeeze", mouth="o", sq=-0.1)
    f["held_1"] = puffer(8.5, 3, spines=1, mood="squeeze", mouth="o", sq=0.08)
    f["hurt"] = puffer(6.5, 0, mood="squeeze", mouth="o", sq=0.25)
    return f


def claw(c, cx, cy, s, open_, ang=0.0):
    """A big crab pincer at (cx, cy): a fat palm and two jaws that open by `open_` (0..1), pointing at angle `ang`."""
    ca, sa = math.cos(ang), math.sin(ang)
    R = lambda u, v: (cx + u * ca - v * sa, cy + u * sa + v * ca)  # noqa: E731
    c.ell(cx, cy, 3.6 * s, 3.2 * s, A, spec=True)
    up = [R(0, -1.0 * s), R(3 * s, -3.6 * s - open_ * 1.5), R(6.5 * s, -1.8 * s - open_ * 3), R(3.2 * s, 0.2 * s)]
    lo = [R(0, 1.0 * s), R(3.4 * s, 0.5 * s), R(6.0 * s, 1.6 * s + open_ * 2.2), R(2.6 * s, 2.8 * s)]
    c.poly(up, A, sphere=(cx, cy - 2, 7 * s))
    c.poly(lo, A, sphere=(cx, cy + 1, 7 * s))
    if open_ > 0.1:
        c.cut([R(2.4 * s, -0.2 * s), R(7.5 * s, -0.6 * s - open_ * 2.4), R(7.5 * s, 0.6 * s + open_ * 1.8)])
    else:
        c.line(*R(2.2 * s, 0), *R(6 * s, 0.4 * s), OL)
    tip = R(6.2 * s, -1.8 * s - open_ * 3)
    c.px(tip[0], tip[1], CREAM)


def crab(step=0, open_=0.3, front=(23.5, 15.0, 0.1), mood="angry", upside=False, sq=0.0, legs="walk"):
    c = Canvas(32, 32)
    sx, sy = squash(sq)
    cx, cy = 15.5, 21.0
    claw(c, 5.5, 15.5 + (step % 2) * 0.5, 0.75, 0.2, -2.6)  # back claw, smaller
    for m in (-1, 1):
        for j in range(3):
            ph = (step + j + (m > 0) * 2) % 4
            lift = [0, -1, 0, 0][ph] if legs == "walk" else [-2, 1][(step + j) % 2]
            x0 = cx + m * (3 + j * 2.3)
            c.tube([(x0, cy + 2, 1.1), (x0 + m * 2.2, cy + 4.5 + lift, 1.0), (x0 + m * 3.0, cy + 8 + lift, 0.7)], (2, 2, 3))
    for m, ex in ((0, 14.0), (1, 19.5)):  # eye stalks
        c.line(ex, cy - 4, ex + m * 0.5, cy - 9 * sy, OL)
    c.ell(cx, cy, 9.5 * sx, 5.6 * sy, A, spec=True)
    # bandana over the top of the shell, knot tails at the back
    c.poly([(cx - 8.5, cy - 1.5), (cx - 6, cy - 4.8 * sy), (cx, cy - 5.9 * sy), (cx + 6, cy - 4.8 * sy), (cx + 8.5, cy - 1.5),
            (cx + 5, cy - 2.6), (cx, cy - 3.2), (cx - 5, cy - 2.6)], B, normal=(-0.1, -0.6))
    c.poly([(cx - 8, cy - 2), (cx - 12, cy - 4 + (step % 2)), (cx - 11, cy - 1)], B, normal=(-0.5, -0.3))
    c.poly([(cx - 8, cy - 1.5), (cx - 12, cy + 1 + (step % 2)), (cx - 9.5, cy + 0.5)], B, normal=(-0.5, 0.3))
    for x in (-4, 0, 4):
        c.px(cx + x, cy - 4.2, CREAM)
    ey = cy - 10.5 * sy
    c.ell(14.0, ey, 2.6, 2.8, (14, 14, 15))
    c.ell(20.0, ey - 0.5, 2.6, 2.8, (1, 1, 1))  # the eye-patch
    c.line(17.0, ey - 3, 23.0, ey + 1, OL)
    c.px(19, ey - 1.5, 5)
    ix, iy = 14, int(ey - 1)
    if mood in ("angry", "open"):
        c.stamp(["..", "11", "11"], ix, iy)
        c.line(11, ey - 4, 16, ey - 2, OL)
    elif mood == "dazed":
        c.stamp(["1.1", ".1.", "1.1"], ix - 1, iy)
    else:
        c.stamp(["1..", ".11", "1.."], ix - 1, iy)
    c.stamp(["1111", ".e.."] if mood != "squeeze" else [".11.", "1881"], int(cx + 2), int(cy + 1))
    fx, fy, fa = front
    c.tube([(cx + 7, cy - 1, 1.4), (fx - 3, fy + 2, 1.3)], A)
    claw(c, fx - 1, fy, 1.25, open_, fa)
    p = c.done()
    return shift(flip_v(p), 0, -2) if upside else p


def cangrejo_frames():
    f = {f"walk_{i}": shift(crab(i, 0.2 + 0.2 * (i % 2), (23.5, 15.0, 0.1)), 0, [0, -1, 0, -1][i]) for i in range(4)}
    f["claw_0"] = crab(0, 1.0, (22.5, 9.0, -0.9), sq=0.08)
    f["claw_1"] = crab(0, 0.0, (24.5, 17.0, 0.2), sq=-0.06)
    f["claw_2"] = crab(0, 0.5, (23.5, 13.0, -0.3))
    f["stun_0"] = crab(0, 0.6, mood="dazed", upside=True, legs="kick")
    f["stun_1"] = crab(1, 0.9, mood="dazed", upside=True, legs="kick")
    f["held_0"] = crab(0, 1.0, (24.5, 9.0, -1.0), mood="squeeze", legs="kick", sq=-0.08)
    f["held_1"] = crab(1, 0.0, (25.5, 12.0, -0.4), mood="squeeze", legs="kick")
    f["hurt"] = crab(0, 0.2, mood="squeeze", sq=0.25)
    return f


def jelly(k=0, sq=0.0, mood="angry", tilt=0.0, mouth="frown"):
    """A magenta jellyfish: a domed bell with a frilly hem, wavy tentacles trailing; it pulses (squash and stretch)."""
    c = Canvas(32, 32)
    sx, sy = squash(sq)
    cx, cy = 16.0, 11.0 + sq * 3
    hem = cy + 2.5 * sy
    c.ell(cx, cy, 9.5 * sx, 8.0 * sy, C, spec=True)
    c.cut([(0, hem + 0.5), (32, hem + 0.5), (32, 32), (0, 32)])
    for j in range(7):  # scalloped hem
        c.ell(cx - 8.4 * sx + j * 2.8 * sx, hem, 1.6, 1.3, (9, 10, 10), seam=False)
    for j, x0 in enumerate((10.5, 14.0, 18.0, 21.5)):  # thin tentacles
        pts = []
        for t in range(6):
            yy = hem + 1.5 + t * 3.0 * (1 - sq * 0.6)
            xx = x0 + (x0 - cx) * sq * 0.6 + math.sin(t * 1.1 - k * 1.05 + j * 1.7) * (0.6 + t * 0.35) + tilt * t
            pts.append((xx, yy, 0.8 - t * 0.06))
        c.tube(pts, (8, 9, 10), seam=False)
    for x0 in (13.0, 19.0):  # two frilly oral arms
        pts = [(x0 + math.sin(t * 0.9 - k * 1.05 + x0) * 1.2 + tilt * t, hem + 1.5 + t * 2.6 * (1 - sq * 0.5), 1.6 - t * 0.2) for t in range(5)]
        c.tube(pts, C)
    for u, v in ((-4, -3), (-1, -5), (3, -4)):  # inner glowing spots
        c.px(cx + u * sx, cy + v * sy, 13)
    ex, ey = int(cx - 4), int(cy - 2)
    c.stamp(EYES[mood].split("|"), ex - 1, ey)
    c.stamp(EYES[mood].split("|"), ex + 4, ey)
    if mood == "angry":
        c.line(ex - 2, ey - 1, ex + 2, ey + 1, OL)
        c.line(ex + 4, ey + 1, ex + 8, ey - 1, OL)
    mx, my = ex + 2, ey + 6
    c.stamp(["1111", "1..1"] if mouth == "frown" else [".11.", "1881", ".11."], mx, my - (1 if mouth != "frown" else 0))
    return c.done()


def medusa_frames():
    sqs = [0.0, 0.14, 0.22, 0.08, -0.12, -0.1]
    f = {f"pulse_{i}": shift(jelly(i, sqs[i]), 0, [0, 1, 1, 0, -1, -1][i]) for i in range(6)}
    f["stun_0"] = stars(jelly(0, 0.1, "dazed", tilt=0.6, mouth="o"), 16, 3, 0, 8)
    f["stun_1"] = stars(jelly(2, 0.1, "dazed", tilt=-0.6, mouth="o"), 16, 3, 1, 8)
    f["held_0"] = jelly(1, -0.15, "squeeze", tilt=0.5, mouth="o")
    f["held_1"] = jelly(3, 0.1, "squeeze", tilt=-0.5, mouth="o")
    f["hurt"] = jelly(0, 0.3, "squeeze", mouth="o")
    return f


def golem_small(pose="walk", k=0, mood="angry", sq=0.0, hammer=True, dy=0.0, legs="walk"):
    """A small basalt golem with lava in its cracks and a big stone hammer."""
    c = Canvas(32, 32)
    sx, sy = squash(sq)
    cx, base = 14.5, 29.5 + dy
    # legs
    lk = [(0, 0), (-1, -1), (0, 0), (1, -1)][k % 4] if legs == "walk" else [(-2, -2), (2, -1)][k % 2]
    for m, (dxl, lift) in ((-1, lk), (1, (-lk[0], lk[1] if legs != "walk" else [-1, 0, -1, 0][k % 4] + 0))):
        c.poly([(cx + m * 2 - 2.2 + dxl, base - 6), (cx + m * 2 + 2.2 + dxl, base - 6), (cx + m * 2 + 2.6 + dxl, base + lift),
                (cx + m * 2 - 2.6 + dxl, base + lift)], B, normal=(m * 0.3, 0.2))
    by = base - 6 - 7.5 * sy
    hpos = {"walk": ((cx + 6, by + 2), (cx - 5, by - 9)), "up": ((cx + 1, by - 6), (cx - 2, by - 14)),
            "peak": ((cx - 1, by - 7), (cx - 8, by - 12)), "slam": ((cx + 8, by + 4), (cx + 14, base - 4)),
            "rec": ((cx + 7, by + 3), (cx + 12, by - 4))}
    if hammer and pose in hpos:
        (hx, hy), (tx, ty) = hpos[pose]
        c.tube([(hx, hy, 1.0), (tx, ty, 1.0)], (8, 8, 9))  # handle
        ang = math.atan2(ty - hy, tx - hx) + math.pi / 2
        ca, sa = math.cos(ang) * 4.2, math.sin(ang) * 4.2
        da, db = math.cos(ang - math.pi / 2) * 2.8, math.sin(ang - math.pi / 2) * 2.8
        head = [(tx + ca - da, ty + sa - db), (tx + ca + da, ty + sa + db), (tx - ca + da, ty - sa + db), (tx - ca - da, ty - sa - db)]
        c.poly(head, B, sphere=(tx, ty, 5.5), spec=True)
        c.line(tx + ca * 0.6 - da, ty + sa * 0.6 - db, tx + ca * 0.6 + da, ty + sa * 0.6 + db, 12)
        c.line(tx - ca * 0.6 - da, ty - sa * 0.6 - db, tx - ca * 0.6 + da, ty - sa * 0.6 + db, 12)
    body = [(cx - 7 * sx, by + 7.5 * sy), (cx - 8 * sx, by - 1), (cx - 5 * sx, by - 7 * sy), (cx + 4 * sx, by - 7.5 * sy),
            (cx + 8 * sx, by - 2), (cx + 7 * sx, by + 7.5 * sy)]
    c.poly(body, B, sphere=(cx, by, 9.5), spec=True)
    # lava cracks
    c.line(cx - 4, by + 6, cx - 2, by + 2, 9)
    c.line(cx - 2, by + 2, cx - 4, by - 1, 9)
    c.px(cx - 2, by + 2, 12)
    c.line(cx + 5, by + 5, cx + 3, by + 3, 9)
    c.px(cx - 5, by - 4, 6)
    c.px(cx + 1, by - 6, 7)
    ex, ey = int(cx + 1), int(by - 4)
    if mood == "angry":
        c.stamp(["11....", ".111.1", ".dd1dd", "..c.c."], ex - 1, ey)
        c.stamp(["999999", "1d1d1."], ex - 1, ey + 5)
    elif mood == "dazed":
        c.stamp(["1.1.1.1", ".1...1.", "1.1.1.1"], ex - 1, ey + 1)
        c.stamp([".9999."], ex - 1, ey + 5)
    else:
        c.stamp(["11..11", "..11..", "11..11"], ex - 1, ey + 1)
        c.stamp([".9999.", "9....9"], ex - 1, ey + 5)
    # boulder fists
    fpos = {"walk": (cx + 6, by + 2), "up": (cx + 1, by - 6), "peak": (cx - 1, by - 7), "slam": (cx + 8, by + 4),
            "rec": (cx + 7, by + 3), "flail": (cx + 7 + k, by - 5 - k * 2), "rest": (cx + 7, by + 4)}[pose]
    c.ell(fpos[0], fpos[1], 2.8, 2.6, B, spec=True)
    c.ell(cx - 7.5, by + 2 + (k % 2), 2.6, 2.4, B)
    return c.done()


def dust(p, x, y, k):
    out = [row[:] for row in p]
    for dx, dy, r in ((0, 0, 1.6 + k), (-3 - k, 1, 1.2 + k * 0.5), (3 + k, 1, 1.3 + k * 0.5)):
        for yy in range(int(y + dy - r - 1), int(y + dy + r + 2)):
            for xx in range(int(x + dx - r - 1), int(x + dx + r + 2)):
                if 0 <= yy < len(out) and 0 <= xx < len(out[0]) and (xx + 0.5 - x - dx) ** 2 + (yy + 0.5 - y - dy) ** 2 <= r * r and not out[yy][xx]:
                    out[yy][xx] = 14 if yy < y + dy else 7
    return outline(out, OL)


def golem_chico_frames():
    f = {f"walk_{i}": golem_small("walk", i, dy=[0, -1, 0, -1][i], sq=[0.06, -0.03, 0.06, -0.03][i]) for i in range(4)}
    f["smash_0"] = golem_small("up", 0, sq=-0.08)
    f["smash_1"] = golem_small("peak", 0, sq=-0.14, dy=-1)
    f["smash_2"] = dust(golem_small("slam", 0, sq=0.18), 28, 28, 0)
    f["smash_3"] = dust(golem_small("rec", 0, sq=0.06), 28, 28, 1)
    for i in range(2):
        f[f"stun_{i}"] = stars(golem_small("rest", i, mood="dazed", sq=0.15, hammer=False), 15, 6, i, 7)
    f["held_0"] = golem_small("flail", 0, mood="hurt", hammer=False, legs="kick", sq=-0.08, dy=-1)
    f["held_1"] = golem_small("flail", 1, mood="hurt", hammer=False, legs="kick", sq=0.0, dy=-1)
    f["hurt"] = golem_small("rest", 0, mood="hurt", sq=0.25, hammer=False)
    return f


# ================================================================== THE BOSS: El Gran Gólem de Oro

def crack(c, pts, glow=True):
    """A crack: a dark zigzag with a lava glow in the middle."""
    for (x0, y0), (x1, y1) in zip(pts, pts[1:]):
        c.line(x0, y0, x1, y1, OL)
    if glow:
        for (x0, y0), (x1, y1) in zip(pts[1:-1], pts[2:-1]):
            c.px((x0 + x1) / 2, (y0 + y1) / 2, GLOW)
        for x, y in pts[1:-1]:
            c.px(x, y, GLOW)


TORSO_CRACKS = [
    [(20, 24), (23, 29), (21, 33), (25, 37)],
    [(44, 25), (41, 30), (44, 34), (42, 40), (45, 44)],
    [(12, 44), (16, 47), (15, 52), (19, 56)],
    [(29, 41), (27, 45), (30, 49)],
    [(50, 46), (47, 50), (49, 55)],
    [(8, 30), (12, 33), (10, 37)],
]


def torso(b=0, cracks=0, hurt=False):
    c = Canvas(64, 64)
    up = b * 0.7
    sq = 0.06 if hurt else 0.0
    c.poly([(11, 22 - up), (53, 22 - up), (60, 40), (52, 61), (12, 61), (4, 40)], STONE, sphere=(32, 36, 32))
    for y, x0, x1 in ((44, 8, 26), (50, 38, 56), (56, 14, 30)):  # stone courses
        c.line(x0, y, x1, y, 6)
    c.ell(32, 17 - up, 8, 4.5, (1, 1, 6), seam=False)  # the neck socket
    for m in (-1, 1):  # pauldrons
        px_ = 32 + m * 20.5
        c.ell(px_, 21 - b, 11.5, 9.5, GOLD, spec=True)
        c.line(px_ - 9, 24 - b, px_ + 9, 24 - b, 2)
        for j in (-6, 0, 6):
            c.px(px_ + j, 17 - b, 5)
    plate = [(17, 24 - up), (47, 24 - up), (50 + sq * 20, 39), (32, 54 + sq * 10), (14 - sq * 20, 39)]
    c.poly(plate, GOLD, sphere=(30, 30, 26), spec=True)
    c.poly([(21, 28 - up), (43, 28 - up), (45, 38), (32, 49), (19, 38)], (2, 3, 3, 4), sphere=(30, 32, 22), seam=False)  # engraved inner field
    c.poly([(23, 30 - up), (41, 30 - up), (42.5, 38), (32, 46.5), (21.5, 38)], GOLD, sphere=(30, 30, 20), seam=False)
    for x, y in ((18, 26), (46, 26), (16, 38), (48, 38), (32, 52)):
        c.px(x, y - (up if y < 30 else 0), 5)
        c.px(x + 1, y + 1 - (up if y < 30 else 0), 2)
    c.ell(32, 36.5 - up * 0.5, 5.2, 6.0, GEM, spec=True)  # the heart gem
    c.px(30, 33 - up * 0.5, WHITE)
    c.poly([(13, 55), (51, 55), (50, 61), (14, 61)], GOLD, normal=(0, -0.3))  # belt
    c.poly([(28, 54), (36, 54), (36, 61.5), (28, 61.5)], GOLD, normal=(-0.4, -0.5), spec=True)
    c.stamp(["1111", "1..1", "1111"], 30, 56)
    for crk in TORSO_CRACKS[:cracks]:
        crack(c, [(x, y - (up if y < 30 else 0)) for x, y in crk])
    if cracks >= 3:  # chips knocked out of the plate
        c.cut([(46, 24 - up), (49, 24 - up), (49.5, 30)])
        c.cut([(14, 38), (17, 37), (16, 42)])
    if hurt:
        for x, y in ((24, 30), (40, 33), (32, 45), (20, 40)):
            c.stamp([".f.", "fff", ".f."], x, y)
    return c.done()


def boss_head(eyes="smug", mouth="smirk", dy=0, cracks=0, crumble=0, tilt=0):
    c = Canvas(32, 32)
    oy = dy
    c.ell(16, 18.5 + oy, 11.0, 10.5, STONE, spec=True)  # stone face
    for m in (-1, 1):  # ears / side plates
        c.ell(16 + m * 11.5, 18 + oy, 2.6, 4.0, GOLD)
    c.poly([(4, 16 + oy), (5.5, 8 + oy), (11, 3 + oy), (21, 3 + oy), (26.5, 8 + oy), (28, 16 + oy), (24, 13.5 + oy), (8, 13.5 + oy)],
           GOLD, sphere=(15, 10 + oy, 13), spec=True)  # helmet
    c.poly([(13.5, 3.5 + oy), (16, -1 + oy), (18.5, 3.5 + oy)], GOLD, normal=(-0.4, -0.7))  # crest spike
    c.ell(16, 7.5 + oy, 2.2, 2.4, GEM, spec=True)
    for x in (8, 24):
        c.px(x, 9 + oy, 5)
    c.line(6, 13 + oy, 26, 13 + oy, 2)
    # brows: one cocked (smug)
    by = 14 + oy
    if eyes in ("smug", "glance"):
        c.poly([(7, by - 0.5), (14, by - 0.5), (14, by + 1.5), (7, by + 1.8)], GOLD, normal=(-0.3, -0.5))
        c.poly([(18, by + 0.5), (25, by - 2.5), (25.5, by), (18, by + 2)], GOLD, normal=(-0.3, -0.5))
    ey = int(16 + oy)
    if eyes == "smug":
        c.stamp(["111111..111111", "1dddd1..1dddd1", ".1111....1111."], 8, ey)
    elif eyes == "glance":
        c.stamp(["111111..111111", "1ddfd1..1ddfd1", ".1111....1111."], 8, ey)
    elif eyes == "laugh":
        c.stamp([".1111....1111.", "1....1..1....1"], 8, ey)
    elif eyes == "wide":
        c.stamp([".1111....1111.", "1dddd1..1dddd1", "1ddfd1..1ddfd1", ".1111....1111."], 8, ey - 1)
    elif eyes == "hurt":
        c.stamp(["11..11..11..11", "..11......11..", "11..11..11..11"], 8, ey)
    elif eyes == "dead":
        c.stamp(["1..1....1..1", ".11......11.", "1..1....1..1"], 9, ey)
    c.poly([(15, 18 + oy), (17, 18 + oy), (18.5, 22 + oy), (13.5, 22 + oy)], STONE, normal=(-0.5, -0.2))  # nose
    my = int(24 + oy)
    if mouth == "smirk":
        c.stamp(["..........1.", "1........1..", ".11111111..."], 10, my - 1)
    elif mouth == "laugh":
        c.poly([(9, my - 1), (23, my - 2), (21, my + 4), (11, my + 4)], (1, 1, 1), seam=False)
        c.stamp(["eeeeeeeeeeee"], 10, my - 1)
        c.poly([(13, my + 2), (19, my + 2), (18, my + 4), (14, my + 4)], (9, 9, 10), seam=False)
    elif mouth == "open":
        c.ell(16, my + 1.5, 6.5, 4.5, (1, 1, 1), seam=False)
        c.stamp(["e.e.e.e.e.e", ".........."], 11, my - 2)
    elif mouth == "grimace":
        c.stamp(["111111111111", "1e1e1e1e1e11", "111111111111"], 10, my - 1)
    elif mouth == "slack":
        c.stamp(["..11111111..", ".1.......1.", ".........."], 10, my)
    c.poly([(10, 28 + oy), (22, 28 + oy), (19, 31 + oy), (13, 31 + oy)], GOLD, normal=(0, 0.3))  # chin plate
    for crk in [[(7, 18), (9, 22), (8, 26)], [(24, 6), (22, 10), (24, 12)], [(23, 19), (25, 23), (23, 27)], [(12, 4), (14, 9)]][:cracks]:
        crack(c, [(x, y + oy) for x, y in crk])
    if crumble:  # chunks breaking off
        cuts = [[(0, 0), (12, 0), (5, 14)], [(26, 0), (32, 0), (32, 20), (25, 12)], [(0, 20), (9, 25), (6, 32), (0, 32)],
                [(20, 26), (32, 22), (32, 32), (18, 32)]]
        for cp in cuts[:crumble]:
            c.cut([(x, y + oy) for x, y in cp])
    p = c.done()
    return shift(p, tilt, 0) if tilt else p


def head_open(k):
    c = Canvas(32, 32)
    c.p = boss_head("wide", "open")
    r = 2.8 + k * 0.6
    c.ell(16, 25.5, r, r * 0.9, GEM, spec=True)
    c.px(15, 24, WHITE)
    if k:
        for x, y in ((10, 23), (22, 23), (16, 20)):
            c.px(x, y, GLOW)
    return outline(c.p, OL)


def fist(kind="closed", k=0):
    c = Canvas(32, 32)
    if kind == "open":
        for j, (ang, ln) in enumerate(((-2.0, 8.5), (-1.7, 10), (-1.4, 10), (-1.1, 8.5))):
            bx, by = 12 + j * 3.4, 15
            tx, ty = bx + math.cos(ang) * ln * 0.25 + (j - 1.5) * 1.5, by - ln
            c.tube([(bx, by, 2.2), (tx, ty, 1.9)], STONE)
            c.ell(tx, ty, 2.2, 2.0, GOLD, spec=True)
        c.ell(16, 21, 10.0, 8.5, STONE, spec=True)
        c.tube([(7, 22, 2.6), (3, 15, 2.2)], STONE)  # thumb
        c.ell(3, 14.5, 2.4, 2.2, GOLD)
        c.poly([(8, 25), (25, 25), (24, 30.5), (9, 30.5)], GOLD, normal=(0, 0.2))  # cuff
        c.line(12, 20, 20, 21, 6)
        c.line(14, 23, 21, 23, 6)
    else:
        sq = 0.2 if kind == "slam1" else 0.0
        sx, sy = squash(sq)
        cy = 17 + (4 if kind == "slam1" else 0)
        c.ell(16, cy, 12.0 * sx, 10.0 * sy, STONE, spec=True)
        for j in range(4):  # gold knuckle plates
            c.ell(8 + j * 5.4 * sx + (1 - sx) * 8, cy - 7 * sy + abs(j - 1.5) * 0.8, 2.9, 2.5, GOLD, spec=True)
        for j in range(3):
            c.line(10.5 + j * 5.4, cy - 4 * sy, 10.5 + j * 5.4, cy + 2 * sy, 6)
        c.tube([(4, cy + 2, 2.8), (13, cy + 4, 2.6)], STONE)  # thumb across
        c.ell(14, cy + 4, 2.3, 2.1, GOLD)
        c.poly([(7, cy + 7 * sy), (25, cy + 7 * sy), (24, min(31.5, cy + 12)), (8, min(31.5, cy + 12))], GOLD, normal=(0, 0.2))
        if kind == "slam0":
            p = c.done()
            for x in (5, 11, 21, 27):
                for y in range(0, 5 + (x % 3)):
                    if not p[y][x]:
                        p[y][x] = 14
            return p
        if kind == "slam1":
            p = c.done()
            return dust(p, 16, 30, 1)
    return c.done()


def arm(kind="a"):
    c = Canvas(32, 32)
    if kind == "a":
        c.tube([(8.5, 16, 7.0), (23.5, 16, 6.2)], STONE, spec=True)
        for x in (12, 20):
            r = 7.3 if x < 16 else 6.6
            c.poly([(x - 1.8, 16 - r - 0.6), (x + 1.8, 16 - r - 0.6), (x + 1.8, 16 + r + 0.6), (x - 1.8, 16 + r + 0.6)], GOLD, sphere=(x, 16, r + 3), spec=True)
        crack(c, [(15, 11), (17, 14), (16, 17)], glow=False)
    else:
        c.tube([(8, 16, 6.0), (22, 16, 7.0)], STONE, spec=True)
        c.tube([(16, 16, 7.6), (21.5, 16, 8.0)], GOLD, spec=True)  # bracer
        for x in (15, 18, 21):
            c.px(x, 10, 5)
        c.line(14, 21, 23, 21, 2)
        c.ell(19, 16, 2.2, 2.4, GEM, spec=True)
    return c.done()


def shield(k=0):
    """The golden mask that covers the head: a smug idol face; it cracks and sheds when hurt."""
    c = Canvas(32, 32)
    c.poly([(3, 6), (9, 2), (23, 2), (29, 6), (29, 20), (24, 28), (16, 31), (8, 28), (3, 20)], GOLD, sphere=(13, 12, 20), spec=True)
    c.stamp(["11111111..11111111", ".1....1....1....1.", "..1111......1111.."], 7, 11)
    c.stamp([".1.", "1.1"], 15, 17)
    c.stamp(["..........11", "1111111111..", ".1........1."], 9, 22)
    c.line(5, 5, 27, 5, 2)
    for x in (8, 16, 24):
        c.px(x, 3, 5)
    if k:
        crack(c, [(10, 2), (12, 7), (10, 11), (13, 16)])
        crack(c, [(27, 8), (24, 13), (26, 19), (23, 25)])
        c.cut([(29, 13), (32, 13), (32, 30), (25, 27)])
        c.cut([(0, 22), (6, 21), (9, 32), (0, 32)])
    return c.done()


def debris(k):
    c = Canvas(32, 32)
    a = k * math.pi / 4
    pts = [(16 + r * math.cos(t + a), 16 + r * math.sin(t + a)) for r, t in ((7, 0), (5, 1), (8, 2), (6, 3.1), (7.5, 4), (5.5, 5.2))]
    c.poly(pts, STONE, sphere=(16, 16, 8), spec=True)
    gp = [(16 + r * math.cos(t + a), 16 + r * math.sin(t + a)) for r, t in ((7.2, -0.2), (5.2, 1), (2, 0.5))]
    c.poly(gp, GOLD, sphere=(16, 16, 8), seam=False)
    c.line(*pts[1], 16, 16, 6)
    for j in range(2):  # small chips flying with it
        t = a * 1.5 + j * 2.5
        x, y = 16 + math.cos(t) * 12, 16 + math.sin(t) * 12
        c.ell(x, y, 1.6, 1.4, STONE)
    return c.done()


def egg(k):
    c = Canvas(32, 32)
    wob = [0, 0.8, -0.8, 0][k]
    c.ell(16 + wob, 17, 8.5, 11, STONE, spec=True)
    c.poly([(8 + wob, 19), (24 + wob, 19), (23.5 + wob, 22), (8.5 + wob, 22)], GOLD, normal=(0, 0), seam=False)  # gold band
    for x in (11, 16, 21):
        c.px(x + wob, 20, 5)
    if k >= 2:
        crack(c, [(10 + wob, 11), (13 + wob, 14), (15 + wob, 11), (18 + wob, 15), (21 + wob, 11), (23 + wob, 13)])
    if k == 3:  # split open: the bomb duck peeks out
        c.cut([(6, 0), (26, 0), (25, 11), (21, 13), (18, 10), (15, 13), (12, 10), (7, 12)])
        c.ell(16, 11, 4.5, 4.0, (6, 7, 8))
        c.poly([(19, 11), (24, 11.5), (19, 13)], GOLD, normal=(0, -0.5))
        c.stamp(["e1"], 17, 9)
        c.line(15, 7, 14, 4, 4)
        c.px(14, 3, GLOW)
    return c.done()


def duck(k):
    """A walking bomb duck: a round stone bomb body, gold beak and feet, a lit fuse on its head."""
    c = Canvas(32, 32)
    bob = [0, -1, 0, -1][k]
    for m, ph in ((-1, k), (1, k + 2)):
        lift = [0, -1, 0, 0][ph % 4]
        fx = 14 + m * 3 + [0, 1, 0, -1][ph % 4]
        c.poly([(fx - 1, 27 + lift), (fx + 4, 27 + lift), (fx + 4, 29.5 + lift), (fx - 2, 29.5 + lift)], GOLD, normal=(0, -0.3))
    c.ell(14, 19 + bob, 9.5, 8.5, STONE, spec=True)
    c.poly([(4.5, 16 + bob), (2, 12 + bob), (7, 14 + bob)], STONE, normal=(-0.3, -0.5))  # tail tuft
    c.ell(11, 21 + bob, 4.5, 3, (6, 7, 7), seam=True)  # wing
    c.ell(19, 11 + bob, 5.5, 5.0, STONE, spec=True)  # head
    c.poly([(22.5, 11 + bob), (29, 12 + bob), (28, 14.5 + bob), (22.5, 14.5 + bob)], GOLD, normal=(0, -0.4))  # beak
    c.line(23, 13 + bob, 28, 13 + bob, 2)
    c.stamp(["1....", "e11..", "e1..."], 19, int(8 + bob))
    fuse = [(17, 6), (16, 4), (17, 2), (16, 1)]
    for (x0, y0), (x1, y1) in zip(fuse, fuse[1:]):
        c.line(x0, y0 + bob, x1, y1 + bob, 4)
    star = [".c.|cfc|.c.", "c.c|.f.|c.c"][k % 2].split("|")
    c.stamp(star, 15, int(0 + bob) - 1 if bob else 0)
    return c.done()


def lips(k):
    c = Canvas(32, 32)
    if k == 0:  # a smug pout
        c.ell(16, 13, 11, 4.5, GEM, spec=True)
        c.ell(16, 19.5, 10, 5.0, GEM, spec=True)
        c.cut([(15, 7), (17, 7), (16, 10)])
        c.line(6, 16, 26, 16, OL)
        c.line(26, 16, 28, 14, OL)
    else:  # hurt: pursed and quivering
        c.ell(16, 13, 8.5, 5.0, GEM, spec=True)
        c.ell(16, 19.5, 8, 5.0, GEM, spec=True)
        c.stamp(["1.1.1.1.1"], 12, 16)
        c.stamp(["e.e", ".e."], 6, 6)
        c.stamp(["e.e", ".e."], 23, 6)
    return c.done()


def boss_frames():
    big = {f"torso_{i}": torso(i) for i in range(3)}
    big["torso_hurt"] = torso(1, cracks=1, hurt=True)
    for i in range(3):
        big[f"torso_crack_{i}"] = torso(0, cracks=[2, 4, 6][i])
    small = {}
    for i in range(4):
        small[f"head_idle_{i}"] = boss_head("glance" if i == 2 else "smug", "smirk", dy=[0, 0, 1, 1][i])
    small["head_laugh_0"] = boss_head("laugh", "laugh", dy=-1)
    small["head_laugh_1"] = boss_head("laugh", "laugh", dy=0, tilt=1)
    small["head_open_0"] = head_open(0)
    small["head_open_1"] = head_open(1)
    for i in range(3):
        small[f"head_hurt_{i}"] = boss_head("hurt", "grimace", cracks=i + 1, tilt=[-1, 1, 0][i])
    for i in range(4):
        small[f"head_dead_{i}"] = boss_head("dead", "slack", dy=i, cracks=4, crumble=i + 1 if i else 0)
    small["fist_open"] = fist("open")
    small["fist_closed"] = fist("closed")
    small["fist_slam_0"] = fist("slam0")
    small["fist_slam_1"] = fist("slam1")
    small["arm_a"] = arm("a")
    small["arm_b"] = arm("b")
    small["shield_0"] = shield(0)
    small["shield_1"] = shield(1)
    small.update({f"debris_{i}": debris(i) for i in range(4)})
    small.update({f"egg_{i}": egg(i) for i in range(4)})
    small.update({f"duck_{i}": duck(i) for i in range(4)})
    small.update({f"lips_{i}": lips(i) for i in range(2)})
    return big, small


def boss_small():
    return boss_frames()[1]


def boss_big():
    return boss_frames()[0]


# ================================================================== registration and previews

def register():
    """Every frame into its sheet, each kind drawn with its home level's bank (the game may draw any frame with another bank)."""
    for kind, fn, bank in (("pelusa", pelusa_frames, "enemigo_a"), ("fogata", fogata_frames, "enemigo_d"),
                           ("gusanito", gusanito_frames, "enemigo_a"), ("bichito", bichito_frames, "enemigo_b")):
        reg(E16, kind, fn(), bank)
    pf = projectile_frames()
    for kind, bank in (("rock", "enemigo_d"), ("coconut", "enemigo_a"), ("bomb", "enemigo_d")):
        reg(E16, kind, {n.split("_", 1)[1]: p for n, p in pf.items() if n.startswith(kind)}, bank)
    for kind, fn, bank in (("serpiente", serpiente_frames, "enemigo_a"), ("mono", mono_frames, "enemigo_a"),
                           ("murcielago", murcielago_frames, "enemigo_b"), ("escarabajo", escarabajo_frames, "enemigo_b"),
                           ("pez_globo", pez_globo_frames, "enemigo_c"), ("cangrejo", cangrejo_frames, "enemigo_c"),
                           ("medusa", medusa_frames, "enemigo_c"), ("golem_chico", golem_chico_frames, "enemigo_d")):
        reg(E32, kind, fn(), bank)
    big, small = boss_frames()
    for n, p in big.items():
        B64.add(n, p, "jefe_a")
    for n, p in small.items():
        B32.add(n, p, "jefe_a")
    for sheet, frames in ((B64, big), (B32, small)):
        groups: dict[str, list[str]] = {}
        for n in frames:
            groups.setdefault(n.rstrip("0123456789").rstrip("_"), []).append(n)
        for g, names in groups.items():
            STRIPS.append((g, sheet, names))


def _img(sheet, name, scale, back, bank=None):
    return to_image(sheet.get(name), ART.palettes["obj"][bank or sheet.banks.get(name, sheet.bank)], scale, back)


def preview_strips(sheet, out_name, scale=3):
    """Each animation in a row at `scale`, on a dark and on a bright background side by side."""
    from PIL import Image
    rows = [(g, names) for g, s_, names in STRIPS if s_ is sheet]
    fw, fh = sheet.w * scale, sheet.h * scale
    most = max(len(n) for _, n in rows)
    img = Image.new("RGB", (2 * most * (fw + 2) + 12, len(rows) * (fh + 4) + 4), (12, 12, 16))
    for j, (_, names) in enumerate(rows):
        for i, n in enumerate(names):
            img.paste(_img(sheet, n, scale, (36, 32, 52)), (4 + i * (fw + 2), 4 + j * (fh + 4)))
            img.paste(_img(sheet, n, scale, (196, 228, 248)), (8 + (most + i) * (fw + 2), 4 + j * (fh + 4)))
    ART_DIR.mkdir(exist_ok=True)
    out = ART_DIR / out_name
    img.save(out)
    return out


def preview_kinds(scale=3):
    """The enemies drawn with every enemy bank (how they look as another level's kind)."""
    from PIL import Image
    picks = [(E16, n) for n in ("pelusa_walk_0", "fogata_idle_0", "gusanito_walk_0", "bichito_walk_0", "bomb_0")] + \
            [(E32, n) for n in ("serpiente_idle_0", "mono_idle_0", "murcielago_fly_0", "escarabajo_walk_0", "pez_globo_swim_0",
                                "cangrejo_walk_0", "medusa_pulse_0", "golem_chico_walk_0")]
    banks = ["enemigo_a", "enemigo_b", "enemigo_c", "enemigo_d"]
    cw = 32 * scale + 4
    img = Image.new("RGB", (len(picks) * cw + 4, len(banks) * cw + 4), (12, 12, 16))
    for j, b in enumerate(banks):
        for i, (sh, n) in enumerate(picks):
            img.paste(_img(sh, n, scale, (36, 32, 52), b), (4 + i * cw, 4 + j * cw))
    out = ART_DIR / "enemies_banks.png"
    img.save(out)
    return out


def preview_boss(scale=3, bank="jefe_a"):
    """The boss put together on a dark background: torso, head, two arms, two fists."""
    from PIL import Image
    W, H = 160, 150
    canvas = blank(W, H)

    def put(p, x, y):
        for yy, row in enumerate(p):
            for xx, v in enumerate(row):
                if v and 0 <= y + yy < H and 0 <= x + xx < W:
                    canvas[y + yy][x + xx] = v

    tx, ty = 48, 26
    upper = rot_ccw(rot_ccw(rot_ccw(B32.get("arm_a"))))
    put(upper, tx - 16, ty + 18)
    put(upper, tx + 48, ty + 18)
    fore = rot_ccw(rot_ccw(rot_ccw(B32.get("arm_b"))))
    put(fore, tx - 18, ty + 42)
    put(flip_h(fore), tx + 50, ty + 42)
    put(B64.get("torso_0"), tx, ty)
    put(B32.get("head_idle_0"), tx + 16, ty - 13)
    put(B32.get("fist_closed"), tx - 28, ty + 66)
    put(flip_h(B32.get("fist_open")), tx + 60, ty + 60)
    img = to_image(canvas, ART.palettes["obj"][bank], scale, (22, 14, 34))
    out = ART_DIR / ("boss_preview.png" if bank == "jefe_a" else f"boss_preview_{bank}.png")
    img.save(out)
    return out


def main():
    register()
    outs = [preview_sheet(sid, cols, 4) for sid, cols in (("ENEMY16", 12), ("ENEMY32", 12), ("BOSS64", 7), ("BOSS32", 10))]
    outs += [preview_strips(E16, "strips_enemy16.png"), preview_strips(E32, "strips_enemy32.png"),
             preview_strips(B64, "strips_boss64.png"), preview_strips(B32, "strips_boss32.png"), preview_kinds(),
             preview_boss(), preview_boss(bank="jefe_b")]
    for sid in ("ENEMY16", "ENEMY32", "BOSS64", "BOSS32"):
        print(sid, len(ART.sheets[sid].frames), "frames")
    for o in outs:
        print(o)


if __name__ == "__main__":
    main()
