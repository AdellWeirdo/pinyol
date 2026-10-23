"""Botín, passage 1: SELVA. A sunny jungle with ancient sandstone ruins: orange soil under thick grass, mossy carved stone,
giant leaves, vines, turquoise waterfalls and golden light. Palette set "selva" (tile layers and scenery share it).

Run on its own: python3 gen/art_selva.py  (writes previews into art/, nothing into assets/)."""
from __future__ import annotations

import math
import sys
from pathlib import Path

GEN = Path(__file__).resolve().parent
sys.path.insert(0, str(GEN))

from gbakit import ART, ART_DIR, blank, flip_h, flip_v, overlay, pic, preview_metas, preview_scenery, to_image  # noqa: E402

SET = "selva"
BIG = 99

# ------------------------------------------------------------------ palettes (slot meaning noted per bank)
# suelo: 1 outline | 2-6 soil ramp plum..sand | 7-a grass teal..lime | b grass glint | c-e buried stone | f white
ART.palette(SET, "suelo", ["#1a1240", "#4a1c50", "#8c3438", "#c85a30", "#e8904a", "#f8c878", "#0a4a4a", "#13863a",
                           "#4cc22c", "#a8ec3c", "#f0ffa0", "#3c3c8c", "#7a74c4", "#b8b4ec", "#fff8e0"])
# ruina: 1 outline | 2-6 sandstone purple..cream | 7-9 moss | a-c turquoise inlay | d red paint | e gold | f white
ART.palette(SET, "ruina", ["#241448", "#5a2c5c", "#9c4c58", "#d07c5c", "#f0b070", "#fde4a0", "#106040", "#34a03c",
                           "#8ad83c", "#0c6c9c", "#24b4d0", "#8cf0f0", "#c81c3c", "#f8a818", "#fffcf0"])
# planta: 1 outline | 2-6 leaf ramp | 7-a mushroom red ramp | b cream | c stem shade | d purple flower | e yellow | f white
ART.palette(SET, "planta", ["#0c2440", "#0c5848", "#188a40", "#4cc030", "#a0e838", "#e8ff98", "#5a1438", "#b0203c",
                            "#f04848", "#ff9c8c", "#fff0d0", "#d8a870", "#8c58c0", "#f8d020", "#ffffff"])
# agua: 1-7 water deep..white | 8-a wet rock
ART.palette(SET, "agua", ["#102068", "#1848b0", "#2080e0", "#30b8f0", "#70e8f8", "#c8fcff", "#ffffff",
                          "#3a2a6a", "#6a4c8c", "#a07cb4"])
# barro: 1-7 mud ramp | 8-9 bubble shine
ART.palette(SET, "barro", ["#1c0c2c", "#401c48", "#6c2c5c", "#984470", "#c06c84", "#f0a8a8", "#fff0e8",
                           "#7c3c2c", "#b86040"])
# caja: 1 outline | 2-6 wood ramp | 7-a steel blue ramp | b-d gold | e jewel magenta | f white
ART.palette(SET, "caja", ["#1c1038", "#5c2830", "#9c4a2c", "#d8803c", "#f8c068", "#fff0b0", "#102c80", "#2060d0",
                          "#50a8f8", "#b0e8ff", "#a06008", "#f0b820", "#fff070", "#d01890", "#ffffff"])
# scenery banks
ART.palette(SET, "cielo", ["#2448c8", "#3068e8", "#4090f8", "#60b8fc", "#94dcfc", "#c8f4f4", "#ffffff", "#a8c4f4",
                           "#7c90e0", "#5864c0", "#30a8a0", "#1c7c84", "#fff4b0", "#f8d080", "#a8e8d0"])
ART.palette(SET, "monte", ["#0c2c48", "#0c5458", "#148250", "#30b04c", "#7cdc50", "#d0fc90", "#5c3c7c", "#9068a0",
                           "#d8a8b0", "#40c4f0", "#c8f8ff", "#4c2440", "#8c4c4c", "#f86890", "#f8e070"])
ART.palette(SET, "fronda", ["#081a34", "#0a3a44", "#0e6448", "#1c904c", "#48c040", "#a8ec60", "#ecffb0", "#c01c48",
                            "#f86070", "#f8d040", "#5a2850"])
ART.palette(SET, "luz", ["#fff8c8", "#f8ec98", "#f0d878", "#c8f8e8", "#90e8d8", "#ffffff"])


# ------------------------------------------------------------------ drawing helpers

def hsh(x: int, y: int, s: int = 0) -> float:
    """A repeatable noise value 0..1 for a pixel."""
    n = (x * 374761393 + y * 668265263 + s * 2246822519 + 12345) & 0xFFFFFFFF
    n = ((n ^ (n >> 13)) * 1274126177) & 0xFFFFFFFF
    return ((n ^ (n >> 16)) & 0xFFFF) / 65536.0


BAYER = [[0, 8, 2, 10], [12, 4, 14, 6], [3, 11, 1, 9], [15, 7, 13, 5]]


def dith(x: int, y: int, t: float) -> bool:
    """True where an ordered dither of strength t (0..1) puts the second colour."""
    return BAYER[y & 3][x & 3] < t * 16


def ramp_at(ramp: list[int], t: float, x: int, y: int) -> int:
    """A colour of a ramp (dark..light) for t in 0..1, dithered between neighbours."""
    t = min(0.999, max(0.0, t)) * (len(ramp) - 1)
    i = int(t)
    if i + 1 < len(ramp) and dith(x, y, t - i):
        return ramp[i + 1]
    return ramp[i]


class Canvas:
    def __init__(self, w: int, h: int, v: int = 0, wrap: bool = False):
        self.w, self.h, self.wrap = w, h, wrap
        self.p = [[v] * w for _ in range(h)]

    def set(self, x: int, y: int, v: int) -> None:
        if self.wrap:
            x %= self.w
        if 0 <= x < self.w and 0 <= y < self.h and v:
            self.p[y][x] = v

    def get(self, x: int, y: int) -> int:
        if self.wrap:
            x %= self.w
        return self.p[y][x] if 0 <= x < self.w and 0 <= y < self.h else 0

    def rect(self, x: int, y: int, w: int, h: int, v: int) -> None:
        for yy in range(y, y + h):
            for xx in range(x, x + w):
                self.set(xx, yy, v)

    def blob(self, cx: float, cy: float, rx: float, ry: float, ramp: list[int], light=(-0.55, -0.7), only_empty=False,
             rim: int = 0) -> None:
        """A shaded ellipse (a sphere-lit blob: canopy, cloud, cap), lit from the top left, dithered between ramp tones."""
        lx, ly = light
        lz = math.sqrt(max(0.0, 1 - lx * lx - ly * ly))
        for y in range(int(cy - ry) - 1, int(cy + ry) + 2):
            for x in range(int(cx - rx) - 1, int(cx + rx) + 2):
                nx, ny = (x + 0.5 - cx) / rx, (y + 0.5 - cy) / ry
                r2 = nx * nx + ny * ny
                if r2 > 1:
                    continue
                if only_empty and self.get(x, y):
                    continue
                nz = math.sqrt(1 - r2)
                t = 0.5 + 0.5 * (nx * lx + ny * ly + nz * lz) * 1.15 - 0.15
                c = ramp_at(ramp, t, x, y)
                if rim and r2 > 0.82 and nx * lx + ny * ly > 0.2:
                    c = rim
                self.set(x, y, c)

    def foliage(self, cx: float, cy: float, r: float, ramp: list[int], seed: int = 0) -> None:
        """A canopy: a big lit blob with clumps of leaves round its edge (a scalloped GBA tree top)."""
        self.blob(cx, cy, r, r * 0.8, ramp[:-1])
        n = max(5, int(r * 0.8))
        for i in range(n):
            a = math.pi * (0.95 + 1.25 * i / (n - 1)) + (hsh(i, seed, 3) - 0.5) * 0.4
            rr = r * (0.32 + 0.12 * hsh(i, seed, 4))
            self.blob(cx + math.cos(a) * r * 0.72, cy + math.sin(a) * r * 0.6, rr, rr * 0.8, ramp)
        for i in range(n // 2):
            a = math.pi * (0.1 + 0.8 * i / max(1, n // 2 - 1))
            rr = r * 0.3
            self.blob(cx + math.cos(a) * r * 0.75, cy + math.sin(a) * r * 0.55, rr, rr * 0.8, ramp[:-2])

    def line(self, x0: float, y0: float, x1: float, y1: float, v: int) -> None:
        n = int(max(abs(x1 - x0), abs(y1 - y0))) + 1
        for i in range(n + 1):
            t = i / n
            self.set(round(x0 + (x1 - x0) * t), round(y0 + (y1 - y0) * t), v)

    def poly(self, pts: list[tuple[float, float]], v) -> None:
        """A filled polygon; v is a slot or a function (x, y) -> slot."""
        ys = [p[1] for p in pts]
        for y in range(int(min(ys)), int(max(ys)) + 1):
            yc = y + 0.5
            xs = []
            for i in range(len(pts)):
                (ax, ay), (bx, by) = pts[i], pts[(i + 1) % len(pts)]
                if (ay <= yc < by) or (by <= yc < ay):
                    xs.append(ax + (yc - ay) * (bx - ax) / (by - ay))
            xs.sort()
            for a, b in zip(xs[::2], xs[1::2]):
                for x in range(int(math.ceil(a - 0.5)), int(math.floor(b - 0.5)) + 1):
                    self.set(x, y, v(x, y) if callable(v) else v)

    def leaf(self, x0: float, y0: float, ang: float, length: float, width: float, cols: tuple[int, int, int, int],
             bend: float = 0.0, vein: bool = True, ribs: int = 0) -> None:
        """A pointed leaf from (x0, y0) along angle `ang` (degrees, 0 = right, 90 = down), bending by `bend`.
        cols = (dark side, light side, vein, edge highlight)."""
        dark, lightc, veinc, edge = cols
        a = math.radians(ang)
        dx, dy = math.cos(a), math.sin(a)
        px, py = -dy, dx
        steps = int(length * 3)
        for i in range(steps + 1):
            u = i / 3
            f = u / length
            half = width * (math.sin(math.pi * min(1, f * 1.08)) ** 0.7) if f < 1 else 0
            cx = x0 + dx * u + px * bend * f * f * length
            cy = y0 + dy * u + py * bend * f * f * length
            vv = -half
            while vv <= half:
                x, y = round(cx + px * vv - 0.5), round(cy + py * vv - 0.5)
                if vein and abs(vv) < 0.5 and f < 0.92:
                    c = veinc
                elif vv < 0:
                    c = edge if vv < -half + 0.9 else lightc
                    if ribs and int(u - vv * 0.6) % ribs == 0 and vv < -0.8:
                        c = dark
                else:
                    c = dark
                    if ribs and int(u + vv * 0.6) % ribs == 0 and vv > 0.8:
                        c = veinc
                self.set(x, y, c)
                vv += 0.34

    def outline(self, slot: int, only=None) -> None:
        """A 1-pixel line of `slot` round what is drawn (inside the canvas)."""
        old = [r[:] for r in self.p]
        for y in range(self.h):
            for x in range(self.w):
                if old[y][x]:
                    continue
                for ddx, ddy in ((1, 0), (-1, 0), (0, 1), (0, -1)):
                    xx, yy = x + ddx, y + ddy
                    if self.wrap:
                        xx %= self.w
                    if 0 <= xx < self.w and 0 <= yy < self.h and old[yy][xx] and (only is None or old[yy][xx] in only):
                        self.p[y][x] = slot
                        break

    def shade_edges(self, dark: int, light: int | None = None, inner=None) -> None:
        """Pixels of the shape whose lower/right neighbour is empty get `dark`; upper/left get `light`."""
        old = [r[:] for r in self.p]
        for y in range(self.h):
            for x in range(self.w):
                if not old[y][x] or (inner and old[y][x] not in inner):
                    continue
                g = lambda a, b: old[b][a % self.w if self.wrap else a] if 0 <= b < self.h and (self.wrap or 0 <= a < self.w) else 0
                if dark and (not g(x + 1, y) or not g(x, y + 1)):
                    self.p[y][x] = dark
                elif light and (not g(x - 1, y) or not g(x, y - 1)):
                    self.p[y][x] = light


def txt(rows: str) -> list[list[int]]:
    return pic([r.strip() for r in rows.strip().split("\n")], 16, 16)


# ------------------------------------------------------------------ the autotile engine (depth of each pixel from open edges)

def depths(mask: int, x: int, y: int, rt: float = 4.6, rb: float = 3.4):
    """Distances of pixel (x, y) to the open sides of a ground tile (mask N1 E2 S4 W8), with rounded outer corners;
    None where the pixel is cut away by a rounded corner."""
    n, e, s, w = mask & 1, mask & 2, mask & 4, mask & 8
    d = {"n": y if n else BIG, "e": 15 - x if e else BIG, "s": 15 - y if s else BIG, "w": x if w else BIG}
    px, py = x + 0.5, y + 0.5
    for on, k1, k2, r, cx, cy, inx, iny in (
            (n and w, "n", "w", rt, rt, rt, px < rt, py < rt),
            (n and e, "n", "e", rt, 16 - rt, rt, px > 16 - rt, py < rt),
            (s and w, "s", "w", rb, rb, 16 - rb, px < rb, py > 16 - rb),
            (s and e, "s", "e", rb, 16 - rb, 16 - rb, px > 16 - rb, py > 16 - rb)):
        if on and inx and iny:
            depth = r - math.hypot(px - cx, py - cy)
            if depth < 0:
                return None
            d[k1] = d[k2] = int(depth)
    return d


def nook(x: int, y: int, diag: str):
    """For an inner corner: (k, along_side) where k is the distance to the open diagonal corner, along_side True for the
    pixels hugging the vertical edge (they continue the neighbour that is open above/below)."""
    cx = 16 if "e" in diag else 0
    cy = 0 if "n" in diag else 16
    ax, ay = abs(cx - (x + 0.5)), abs((y + 0.5) - cy)
    k = int(math.hypot(ax, ay) - 0.7)
    return k, ay >= ax


# ------------------------------------------------------------------ SELVA ground

WAVE = [0, 0, 1, 1, 1, 1, 0, 0, -1, -1, -1, -1, 0, 0, 0, 0]
TOPS_A = [0, 1, 1, 0, 0, 0, 1, 1, 0, 0, 0, 1, 1, 0, 0, 0]
GT_A = [5, 5, 4, 4, 5, 6, 6, 5, 4, 4, 5, 6, 5, 4, 4, 5]
BOTS = [0, 0, 1, 0, 0, 0, 0, 1, 1, 0, 0, 0, 0, 1, 0, 0]


def soil(x: int, y: int) -> int:
    """The soil texture: terracotta with wavy strata and specks, repeating every 16 pixels both ways."""
    yy = (y - WAVE[x]) % 16
    if yy == 6 or yy == 13 and x % 8 not in (6, 7):
        return 3
    if (yy == 5 and x % 5 in (1, 2)) or (yy == 12 and x % 6 in (3, 4)):
        return 5
    if yy in (7, 14) and dith(x, y, 0.4):
        return 3
    r = hsh(x, y, 7)
    if r < 0.05:
        return 5
    if r < 0.09:
        return 3
    return 4


def stone(c: Canvas, cx: float, cy: float, rx: float, ry: float) -> None:
    """A buried blue-violet stone with a soil shadow under it."""
    for y in range(int(cy - ry) - 1, int(cy + ry) + 3):
        for x in range(int(cx - rx) - 1, int(cx + rx) + 2):
            nx, ny = (x + 0.5 - cx) / rx, (y + 0.5 - cy) / ry
            r2 = nx * nx + ny * ny
            if r2 <= 1:
                c.set(x, y, 0xe if (nx + ny < -0.75 and r2 > 0.25) else (0xc if nx + ny > 0.55 else 0xd))
            elif r2 <= 1.6 and ny > 0.3:
                c.set(x, y, 2)


def soil_props(seed: int) -> Canvas:
    """What is buried in a piece of soil (drawn only over the plain soil part)."""
    c = Canvas(16, 16)
    if seed == 0:
        stone(c, 5.5, 10.5, 2.0, 1.4)
        stone(c, 11, 4, 1.2, 1)
    elif seed == 1:  # a big carved brick of the old ruins, buried
        c.rect(3, 4, 10, 7, 0xd)
        c.rect(3, 4, 10, 1, 0xe)
        c.rect(3, 4, 1, 7, 0xe)
        c.rect(12, 5, 1, 6, 0xc)
        c.rect(4, 10, 9, 1, 0xc)
        c.rect(3, 11, 11, 1, 2)
        for x, y in ((6, 6), (7, 6), (8, 6), (6, 7), (8, 7), (6, 8), (7, 8), (8, 8), (9, 8)):
            c.set(x, y, 0xc)
    elif seed == 2:
        stone(c, 4, 4, 1.4, 1.1)
        stone(c, 11.5, 9.5, 2.6, 1.8)
    elif seed == 3:  # an old bone, half buried
        for x in range(5, 11):
            c.set(x, 9, 6)
            c.set(x, 10, 5)
        for x, y in ((4, 8), (4, 9), (11, 9), (11, 10), (4, 11), (11, 11)):
            c.set(x, y, 6 if y < 10 else 5)
        for x in range(4, 12):
            c.set(x, 11 + (x in (4, 11)), 2)
        stone(c, 12, 4, 1.2, 1)
    elif seed == 4:  # a root
        pts = [(1, 3), (3, 4), (5, 6), (6, 9), (8, 10), (11, 10), (13, 12), (14, 14)]
        for (ax, ay), (bx, by) in zip(pts, pts[1:]):
            c.line(ax, ay, bx, by, 2)
            c.line(ax, ay - 1, bx, by - 1, 3)
        c.line(6, 9, 4, 12, 2)
    elif seed == 5:
        stone(c, 9, 8, 1.3, 1)
    elif seed == 6:
        stone(c, 3.5, 11, 1.4, 1)
        stone(c, 12, 6, 1.6, 1.2)
    return c


def selva_ground(mask: int, seed: int = 0, diag: str | None = None, tops=TOPS_A, gt=GT_A, extra=None):
    t = blank(16, 16)
    props = soil_props(seed)
    for y in range(16):
        for x in range(16):
            d = depths(mask, x, y)
            if d is None:
                continue
            dn, de, ds, dw = d["n"], d["e"], d["s"], d["w"]
            v = soil(x, y)
            plain = True
            if dn < BIG:
                k = dn - tops[x]
                if k < 0:
                    continue
                g = gt[x]
                if k <= g:
                    if k == 0 or de == 0 or dw == 0 or k == g:
                        v = 7
                    elif k == 1:
                        v = 0xb if hsh(x, seed, 3) < 0.22 else 0xa
                    elif k <= 3:
                        v = 9
                    else:
                        v = 8
                    if de == 1 and v in (0xa, 0xb, 9):
                        v = 8 if v == 9 else 9
                    if dw == 1 and v in (9, 8):
                        v = 0xa if v == 9 else 9
                    t[y][x] = v
                    continue
                if k == g + 1:
                    v, plain = 2, False
                elif k == g + 2 and dith(x, y, 0.5):
                    v, plain = 3, False
            m = min(ds, de, dw)
            if m <= 3:
                plain = False
                if ds == m:
                    k = ds - BOTS[x]
                    if k < 0:
                        continue
                    v = (1, 2, 2 if x % 2 else 3, 3 if dith(x, y, 0.5) else v)[k] if k <= 3 else v
                elif de == m:
                    v = (1, 2, 3, 3 if dith(x, y, 0.5) else v)[de]
                else:
                    v = (1, 6, 5, 5 if dith(x, y, 0.5) else v)[dw]
                    if v == 6 and dn <= gt[x] + 3:
                        v = 5
            if diag:
                k, side = nook(x, y, diag)
                if k <= 2:
                    plain = False
                    if "n" in diag:
                        if side:
                            v = (7, 9, 8)[k]
                        else:
                            v = (1, 2, 3)[k] if "e" in diag else (1, 6, 5)[k]
                    else:
                        v = (1, 2, 3)[k] if (side or "e" in diag) else (1, 6, 5)[k]
            if plain and props.get(x, y):
                v = props.get(x, y)
            t[y][x] = v
    if extra:
        t = overlay(t, extra)
    return t


def grass_tops_b():
    return [0, 1, 0, 0, 1, 1, 0, 0, 0, 1, 0, 0, 1, 1, 0, 0], [5, 4, 5, 6, 6, 5, 4, 5, 6, 5, 4, 4, 5, 6, 5, 5]


def top_flowers() -> list[list[int]]:
    c = Canvas(16, 16)
    for x, y in ((3, 0), (10, 1)):
        c.set(x, y, 0xf)
        c.set(x - 1, y + 1, 0xf)
        c.set(x + 1, y + 1, 0xf)
        c.set(x, y + 2, 0xf)
        c.set(x, y + 1, 6)
    return c.p


def top_stone() -> list[list[int]]:
    c = Canvas(16, 16)
    stone(c, 11.5, 3.2, 2.6, 2.2)
    c.set(10, 1, 0xe)
    c.set(13, 5, 7)
    c.set(9, 5, 8)
    return c.p


def register_ground() -> None:
    for m in range(16):
        ART.meta(SET, f"ground_m{m}", selva_ground(m, seed=(5 if m == 0 else (6 if m in (5, 10) else 7))), "suelo", flags=("solid",))
    for i in range(4):
        ART.meta(SET, f"ground_alt{i}", selva_ground(0, seed=(1, 2, 3, 4)[i]), "suelo", flags=("solid",))
    tb, gb = grass_tops_b()
    ART.meta(SET, "ground_m1_b", selva_ground(1, seed=6, tops=tb, gt=gb, extra=top_flowers()), "suelo", flags=("solid",))
    ART.meta(SET, "ground_m1_c", selva_ground(1, seed=0, extra=top_stone()), "suelo", flags=("solid",))
    for dg in ("ne", "nw", "se", "sw"):
        ART.meta(SET, f"ground_in_{dg}", selva_ground(0, seed=7, diag=dg), "suelo", flags=("solid",))
    # mud (barro): a glossy purple-brown bog
    ART.meta(SET, "mud_top", mud(True), "barro", flags=("mud",))
    ART.meta(SET, "mud_fill", mud(False), "barro", flags=("mud",))


def mud(top: bool) -> list[list[int]]:
    """Glossy bog mud (barro): slow horizontal swirls, sunken bubbles; `top` has the rippled surface."""
    c = Canvas(16, 16)
    surf = [3, 3, 2, 2, 2, 3, 3, 4, 4, 4, 3, 3, 2, 2, 3, 3]
    for y in range(16):
        for x in range(16):
            w = (y * 2 + round(2 * math.sin(2 * math.pi * x / 16))) % 16
            v = 3
            if w in (0, 1):
                v = 2
            elif w == 2:
                v = 4 if x % 4 else 3
            elif w in (8, 9) and dith(x, y, 0.5):
                v = 2
            if top:
                s0 = surf[x]
                if y < s0:
                    continue
                v = (1, 6 if x % 6 else 7, 5, 4, 4)[y - s0] if y - s0 <= 4 else v
            c.set(x, y, v)
    for bx, by in ((4, 11), (12, 6)) if not top else ((5, 11), (12, 13)):
        for ddx, ddy, v in ((0, -1, 2), (-1, 0, 2), (1, 0, 4), (0, 1, 5), (0, 0, 3), (-1, -1, 2), (1, 1, 4)):
            c.set(bx + ddx, by + ddy, v)
        c.set(bx - 1, by - 1, 6)
    if top:  # a bubble swelling out of the surface
        for x, y, v in ((7, 0, 1), (8, 0, 1), (6, 1, 1), (9, 1, 1), (7, 1, 6), (8, 1, 5)):
            c.set(x, y, v)
    return c.p


# ------------------------------------------------------------------ platforms, blocks, hazards

def plank_platform(kind: str) -> list[list[int]]:
    """A one-way plank platform (caja): planks lashed with rope; see-through below."""
    c = Canvas(16, 16)
    x0 = 1 if kind in ("l", "s") else 0
    x1 = 14 if kind in ("r", "s") else 15
    rows = {0: 1, 1: 5, 2: 4, 3: 4, 4: 3, 5: 2, 6: 1}
    for y, v in rows.items():
        for x in range(x0, x1 + 1):
            vv = v
            if y == 3 and (x * 7 + 3) % 5 == 0:
                vv = 3
            if x in (7,) and 1 <= y <= 5:
                vv = 2
            if x == 8 and 1 <= y <= 4:
                vv = 5
            c.set(x, y, vv)
    if kind in ("l", "s"):
        for y in range(1, 6):
            c.set(0, y, 1)
        c.set(1, 1, 5)
        c.set(1, 5, 2)
    if kind in ("r", "s"):
        for y in range(1, 6):
            c.set(15, y, 1)
        c.set(14, 1, 4)
    rope = (3, 12) if kind == "m" else ((4,) if kind == "l" else ((11,) if kind == "r" else (4, 11)))
    for rx in rope:
        for y in range(0, 7):
            c.set(rx, y, 6 if (y % 2 == 0) else 5)
            c.set(rx + 1, y, 5 if (y % 2 == 0) else 3)
        for y in range(7, 10 if rx % 2 else 9):
            c.set(rx + (y > 7), y, 5)
            c.set(rx + 1 + (y > 7), y, 2)
    return c.p


def bevel_block(base: int, hi: int, hi2: int, lo: int, lo2: int, ol: int = 1) -> Canvas:
    c = Canvas(16, 16, base)
    for i in range(16):
        c.set(i, 0, ol)
        c.set(i, 15, ol)
        c.set(0, i, ol)
        c.set(15, i, ol)
    for i in range(1, 15):
        c.set(i, 1, hi)
        c.set(1, i, hi)
        c.set(i, 14, lo)
        c.set(14, i, lo)
    for i in range(2, 14):
        c.set(i, 2, hi2)
        c.set(2, i, hi2)
        c.set(i, 13, lo2)
        c.set(13, i, lo2)
    c.set(1, 14, lo2)
    c.set(14, 1, lo2)
    return c


def block_brown() -> list[list[int]]:
    c = bevel_block(4, 5, 4, 2, 3)
    for y in range(3, 13):
        for x in range(3, 13):
            if hsh(x, y, 41) < 0.12:
                c.set(x, y, 5 if hsh(x, y, 42) < 0.5 else 3)
    for (ax, ay), (bx, by) in (((3, 6), (7, 8)), ((7, 8), (6, 12)), ((7, 8), (12, 6)), ((10, 3), (12, 6)), ((12, 6), (12, 11))):
        c.line(ax, ay, bx, by, 2)
    for x, y in ((4, 6), (8, 8), (7, 11), (11, 4), (13, 9)):
        c.set(x, y - 1, 5)
    return c.p


def block_blue() -> list[list[int]]:
    """A reinforced block (caja steel blue): blue stone held by two riveted straps; a dash or a pound breaks it."""
    c = bevel_block(8, 0xa, 9, 7, 7)
    for y in range(3, 13):
        for x in range(3, 13):
            if (x * 3 + y * 5) % 11 == 0:
                c.set(x, y, 7)
            elif (x * 3 + y * 5) % 11 == 1:
                c.set(x, y, 9)
    for x0 in (3, 10):
        for y in range(1, 15):
            c.set(x0 - 1, y, 7)
            c.set(x0, y, 0xa)
            c.set(x0 + 1, y, 9)
            c.set(x0 + 2, y, 7)
        for y in (3, 7, 11):
            c.set(x0, y, 0xf)
            c.set(x0 + 1, y, 0xa)
            c.set(x0 + 1, y + 1, 7)
    return c.p


def block_hard() -> list[list[int]]:
    """Heavy carved sandstone with a gold spiral (ruina)."""
    c = bevel_block(3, 5, 4, 1, 2)
    for y in range(3, 13):
        for x in range(3, 13):
            if hsh(x, y, 51) < 0.08:
                c.set(x, y, 2)
    sp = [(8, 8), (8, 7), (9, 7), (10, 8), (10, 9), (9, 10), (8, 10), (7, 10), (6, 9), (6, 8), (6, 7), (6, 6), (7, 5),
          (8, 5), (9, 5), (10, 5), (11, 6), (12, 7)]
    for x, y in sp:
        c.set(x, y, 0xe)
        c.set(x + 1, y + 1, 1) if c.get(x + 1, y + 1) not in (0xe,) else None
    for x, y in ((3, 3), (12, 3), (3, 12), (12, 12)):
        c.set(x, y, 1)
        c.set(x, y - 1, 6) if y == 3 else None
    for x in range(2, 14):  # moss on top
        if hsh(x, 0, 52) < 0.6:
            c.set(x, 1, 8)
            if hsh(x, 1, 53) < 0.4:
                c.set(x, 2, 7)
    c.set(1, 1, 9)
    return c.p


TIKI = """
1111111111111111
1989668966989631
1658555555555321
1651111441111321
1652fcb44fcb2321
1652bba44bba2321
1655222442224321
1654445663444321
1654442112444321
1654444444444321
1654111111114321
16541f6f6f614321
16541dddddd14321
1653111111113321
1632222222222221
1111111111111111
"""


def tiki_block() -> list[list[int]]:
    t = txt(TIKI)
    t[1][13] = 3
    return t


def crate(emblem: str) -> list[list[int]]:
    """A wooden crate (caja) with a gem or a coin on its face."""
    c = bevel_block(3, 5, 4, 2, 2)
    for y in range(3, 13):
        for x in range(3, 13):
            c.set(x, y, 3 if (x + 2 * y) % 7 else 2)
    for x in range(3, 13):
        c.set(x, 3, 2)
    for x, y in ((2, 2), (13, 2), (2, 13), (13, 13)):
        c.set(x, y, 0xc)
    if emblem == "gem":
        g = [".....1111.....", "....1ecce1....", "...1eeeeee1...", "...1eeffee1...", "....1eeee1....", ".....1ee1.....", "......11......"]
        for yy, row in enumerate(g):
            for xx, ch in enumerate(row):
                if ch != ".":
                    c.set(xx + 1, yy + 4, int(ch, 16))
        for xx, yy in ((5, 5), (10, 5), (5, 6), (10, 6)):
            c.set(xx, yy, 0xc)
        c.p[5][7], c.p[5][8] = 0xf, 0xc
    else:
        coin = ["...1111...", "..1dddc1..", ".1dfdccc1.", ".1ddcccb1.", ".1dcccbb1.", ".1dccbbb1.", "..1cbbb1..", "...1111..."]
        for yy, row in enumerate(coin):
            for xx, ch in enumerate(row):
                if ch != ".":
                    c.set(xx + 3, yy + 4, int(ch, 16))
        for xx, yy in ((7, 6), (7, 7), (7, 8), (7, 9)):
            c.set(xx, yy, 0xb)
            c.set(xx + 1, yy, 0xd)
    return c.p


def spikes() -> list[list[int]]:
    """Two big steel spikes (caja) on a riveted base plate; lit from the left."""
    c = Canvas(16, 16)
    for cx in (4, 12):
        for y in range(1, 12):
            half = (y - 0.5) / 11 * 3.6
            for x in range(16):
                fx = x + 0.5 - cx
                if abs(fx) <= half:
                    c.set(x, y, 0xa if fx < -half * 0.35 else (9 if fx < 0.3 else (8 if fx < half * 0.6 else 7)))
        c.set(cx - 1, 2, 0xf)
        c.set(cx - 1, 3, 0xf)
        c.set(cx - 1, 1, 0xa)
    c.outline(1)
    for x in range(16):
        c.set(x, 12, 1)
        c.set(x, 13, 9 if x % 4 else 0xf)
        c.set(x, 14, 8 if x % 4 != 1 else 7)
        c.set(x, 15, 1)
    return c.p


# ------------------------------------------------------------------ plants: decor, front layer, vines, leaves, mushroom

def fern(c: Canvas, x: int, y: int, scale: float = 1.0, flip: bool = False) -> None:
    s = -1 if flip else 1
    for ang, ln in ((-150, 9), (-115, 11), (-80, 12), (-50, 11), (-25, 9)):
        a = ang if not flip else -180 - ang
        c.leaf(x, y, a, ln * scale, 2.2 * scale, (3, 4, 5, 6), bend=0.22 * s)


def deco(name: str) -> tuple[list[list[int]], str]:
    c = Canvas(16, 16)
    if name == "deco_a":  # a fern clump
        fern(c, 8, 16, 0.95)
        c.outline(1)
        return c.p, "planta"
    if name == "deco_b":  # red hibiscus bush
        for ang in (-160, -120, -60, -20):
            c.leaf(8, 15, ang, 8, 2.4, (2, 3, 4, 5), bend=0.15)
        for fx, fy in ((5, 6), (11, 8)):
            for ddx, ddy in ((0, -2), (2, 0), (0, 2), (-2, 0), (-1, -1), (1, -1), (1, 1), (-1, 1), (0, -1), (1, 0), (0, 1), (-1, 0)):
                c.set(fx + ddx, fy + ddy, 9 if ddy < 0 or ddx < 0 else 8)
            c.set(fx, fy, 0xe)
            c.set(fx - 1, fy - 2, 0xa)
        c.outline(1)
        return c.p, "planta"
    if name == "deco_c":  # a small tiki idol
        idol = """
        ................
        ......1111......
        .....189981.....
        ....16555531....
        ....15411451....
        ....15bc5bc1....
        ....15444441....
        ....14522541....
        ....141dd141....
        ....14411431....
        ....14444431....
        ...1655555321...
        ...1544444321...
        ..133333333321..
        ..122222222221..
        ..111111111111..
        """
        return txt(idol), "ruina"
    if name == "deco_d":  # a skull and bones
        sk = """
        ................
        ................
        ................
        ................
        ................
        ......1111......
        .....1ff651.....
        ....1fff6651....
        ....1f11f115....
        ....1f11f115....
        ....1ff6f651....
        .....1f5f51.....
        .1...161651..11.
        1f11..1111..1f61
        1ff6666666666651
        .111111111111111
        """
        return txt(sk), "ruina"
    if name == "deco_e":  # a wooden arrow sign
        sg = """
        ................
        ................
        ...111111111....
        ...1555555551...
        ...15444444451..
        ...154444444451.
        ...154222244451.
        ...15444444451..
        ...1333333331...
        ...111311311....
        ......121.......
        ......121.......
        ......121.......
        ......131.......
        .....11211......
        ....1222221.....
        """
        return txt(sg), "caja"
    if name == "deco_f":  # a stone brazier with fire
        fb = """
        .......e........
        ......eee.......
        .....eefe..e....
        ....deeffe.ee...
        ...ddeffffeed...
        ...ddefffffed...
        ...1ddefffdd1...
        .11111111111111.
        .16555555555531.
        ..16444ee444321.
        ..13333333333l1.
        ...1222222221...
        ....13333331....
        ....14444421....
        ...1555555321...
        ...1111111111...
        """
        return txt(fb.replace("l", "2")), "ruina"
    if name == "deco_g":  # little mushrooms
        c.blob(5, 9, 4, 3, [7, 8, 9, 10])
        c.blob(12, 12, 2.6, 2, [7, 8, 9, 10])
        for x, y in ((4, 8), (6, 9), (3, 10)):
            c.set(x, y, 0xb)
        c.rect(4, 12, 2, 4, 0xb)
        c.rect(6, 12, 1, 4, 0xc)
        c.rect(11, 14, 2, 2, 0xb)
        c.outline(1)
        return c.p, "planta"
    if name == "deco_h":  # a broken mossy column
        col = """
        ................
        ................
        ................
        ....1.11..1.....
        ...1515611611...
        ...16555555321..
        ...15899998321..
        ...15444444321..
        ...16455443321..
        ...15444444321..
        ...154ab4a4321..
        ...15444444321..
        ...16455443321..
        ..1655555553321.
        ..1544444444321.
        ..1111111111111.
        """
        return txt(col), "ruina"
    raise KeyError(name)


def front(name: str) -> tuple[list[list[int]], str]:
    c = Canvas(16, 16)
    if name == "front_a":  # leaves hanging from above
        for x, ang, ln in ((2, 100, 13), (6, 75, 15), (9, 105, 12), (13, 80, 14)):
            c.leaf(x, -2, ang, ln, 2.3, (2, 3, 4, 5), bend=0.15)
        c.outline(1)
    elif name == "front_b":  # vine strands
        for x0, ln, ph in ((3, 16, 0), (9, 12, 1.5), (13, 15, 3)):
            for y in range(ln):
                x = x0 + round(math.sin(y / 3 + ph))
                c.set(x, y, 2)
                c.set(x + 1, y, 3)
                if y % 5 == 2:
                    c.leaf(x + 1, y, -20 if y % 10 == 2 else 200, 4, 1.4, (3, 4, 5, 6), vein=False)
        c.outline(1)
    elif name == "front_c":  # a big leaf from the left
        c.leaf(-2, 14, -25, 19, 4.6, (2, 3, 5, 4), bend=0.2)
        c.outline(1)
    elif name == "front_d":  # tall grass in front
        for x in range(0, 16, 2):
            hgt = 6 + int(hsh(x, 1, 9) * 8)
            lean = (hsh(x, 2, 9) - 0.5) * 4
            c.line(x, 16, x + lean, 16 - hgt, 3 if x % 4 else 4)
            c.line(x + 1, 16, x + 1 + lean, 17 - hgt, 2)
        c.outline(1)
    elif name == "front_e":  # moss beard
        for x in range(1, 15):
            ln = 3 + int(hsh(x, 0, 21) * 9)
            for y in range(ln):
                c.set(x, y, 4 if y < 2 else (3 if (x + y) % 3 else 2))
            c.set(x, ln, 5 if x % 3 == 0 else 0)
        c.outline(1)
    elif name == "front_f":  # flowering creeper
        for y in range(16):
            x = 8 + round(2 * math.sin(y / 2.5))
            c.set(x, y, 2)
            c.set(x + 1, y, 3)
        for y, side in ((2, 1), (6, -1), (10, 1), (14, -1)):
            x = 8 + round(2 * math.sin(y / 2.5))
            c.leaf(x, y, -10 if side > 0 else 190, 5, 1.6, (3, 4, 5, 6), vein=False)
        for fx, fy in ((5, 4), (12, 9), (6, 13)):
            for ddx, ddy in ((0, -1), (1, 0), (0, 1), (-1, 0)):
                c.set(fx + ddx, fy + ddy, 0xd)
            c.set(fx, fy, 0xe)
        c.outline(1)
    elif name == "front_g":  # a fern in the foreground, from below
        fern(c, 8, 18, 1.15)
        c.outline(1)
    elif name == "front_h":  # roots hanging from the ceiling (soil colours)
        for x0, ln in ((2, 11), (6, 15), (10, 9), (13, 13)):
            x = x0
            for y in range(ln):
                if y % 4 == 3:
                    x += 1 if (x0 + y) % 8 < 4 else -1
                c.set(x, y, 3)
                c.set(x + 1, y, 2)
            c.set(x + 1, ln, 2)
        c.outline(1)
        return c.p, "suelo"
    return c.p, "planta"


def vine(end: bool) -> list[list[int]]:
    c = Canvas(16, 16)
    stop = 11 if end else 16
    for y in range(stop):
        x = 7 + round(1.4 * math.sin(y * 2 * math.pi / 16))
        c.set(x, y, 2)
        c.set(x + 1, y, 3)
    for y, side in ((1, 1), (5, -1), (9, 1), (13, -1)):
        if end and y > 10:
            continue
        x = 7 + round(1.4 * math.sin(y * 2 * math.pi / 16))
        c.leaf(x + (2 if side > 0 else -0), y, -30 if side > 0 else 210, 6, 2.0, (3, 4, 5, 6))
    if end:  # the curled tip and a flower
        for x, y in ((8, 11), (9, 12), (9, 13), (8, 14), (7, 13)):
            c.set(x, y, 3)
        for ddx, ddy in ((0, -1), (1, 0), (0, 1), (-1, 0)):
            c.set(5 + ddx, 11 + ddy, 9)
        c.set(5, 11, 0xe)
    c.outline(1)
    return c.p


def leaf_platform(kind: str) -> list[list[int]]:
    """A giant leaf, one-way: the thick leaf top; the left tip, a middle and the right base with its stalk."""
    c = Canvas(16, 16)
    top, bot = 1, 7
    for x in range(16):
        t0, b0 = top, bot
        if kind == "l":
            f = x / 15
            t0 = top + round(4 * (1 - f) ** 2)
            b0 = bot - round(4 * (1 - f) ** 1.5)
            if x < 2:
                continue
        if kind == "r":
            f = x / 15
            b0 = bot - round(2 * f)
        for y in range(t0, b0 + 1):
            if y == t0:
                v = 6 if x % 5 else 5
            elif y == t0 + 1:
                v = 5
            elif y == b0:
                v = 2
            elif y == (t0 + b0) // 2:
                v = 6 if (x // 2) % 2 else 5
            else:
                v = 4 if y < (t0 + b0) / 2 else 3
            c.set(x, y, v)
        if (x + (1 if kind == "m" else 0)) % 6 == 0:  # side veins
            for y in range(t0 + 2, b0):
                if y != (t0 + b0) // 2:
                    c.set(x, y, 5 if y < (t0 + b0) / 2 else 2)
    if kind == "r":
        for y in range(5, 16):
            x = 12 - (y - 5) // 4
            c.set(x, y, 3)
            c.set(x + 1, y, 2)
    c.outline(1)
    if kind == "m":
        for y in range(16):
            for x in (0, 15):
                if c.p[y][x] == 1 and 2 <= y <= 7:
                    c.p[y][x] = c.p[y][1 if x == 0 else 14]
    if kind == "l":
        for y in range(16):
            if c.p[y][15] == 1 and 2 <= y <= 7:
                c.p[y][15] = c.p[y][14]
    if kind == "r":
        for y in range(16):
            if c.p[y][0] == 1 and 2 <= y <= 7:
                c.p[y][0] = c.p[y][1]
    return c.p


def mushroom(squash: bool) -> list[list[int]]:
    c = Canvas(16, 16)
    if squash:
        c.rect(6, 12, 4, 4, 0xb)
        c.rect(9, 12, 1, 4, 0xc)
        c.blob(8, 11.5, 8.2, 3.6, [7, 8, 9, 10])
        spots = ((4, 10), (9, 9), (13, 11))
    else:
        c.rect(6, 9, 4, 7, 0xb)
        c.rect(9, 9, 1, 7, 0xc)
        c.rect(6, 15, 4, 1, 0xc)
        c.blob(8, 6.5, 7.4, 5.6, [7, 8, 9, 10])
        spots = ((4, 4), (9, 2), (12, 6), (7, 7))
    for sx, sy in spots:
        for ddx, ddy in ((0, 0), (1, 0), (0, 1), (1, 1)):
            c.set(sx + ddx, sy + ddy, 0xb)
        c.set(sx, sy, 0xf)
    bottom = 14 if squash else 11
    for x in range(1, 15):  # the gills under the cap
        if c.get(x, bottom) in (7, 8, 9, 10) and c.get(x, bottom + 1) in (0, 0xb, 0xc):
            c.set(x, bottom, 7)
    c.outline(1)
    for x in range(16):
        c.p[15][x] = c.p[15][x] if c.p[15][x] else 0
    return c.p


# ------------------------------------------------------------------ water

def water_column(frame: int, top: bool) -> list[list[int]]:
    """One-tile-wide falling water (agua); the streaks move 4 pixels a frame; `top` is the lip where it pours out."""
    c = Canvas(16, 16)
    streak = {0: 1, 1: 2, 2: 3, 3: 4, 4: 3, 5: 4, 6: 5, 7: 4, 8: 3, 9: 4, 10: 5, 11: 4, 12: 3, 13: 2, 14: 1}
    for y in range(16):
        for x in range(1, 15):
            v = streak.get(x, 3)
            yy = (y - frame * 4) % 16
            ph = (yy + (x * 5) % 16) % 16
            if v >= 3 and ph in (0, 1):
                v = min(7, v + 2)
            elif v >= 3 and ph in (8,):
                v = v - 1
            c.set(x, y, v)
    if top:
        lip = [6, 4, 3, 2, 2, 2, 1, 1, 1, 1, 2, 2, 2, 3, 4, 6]
        for x in range(16):
            for y in range(16):
                if y < lip[x] - 1 or (x in (0, 15) and y < 9):
                    c.p[y][x] = 0
            ly = max(0, lip[x] - 1)
            if 0 < x < 15:
                c.p[ly][x] = 7 if (x + frame) % 3 else 6
                c.p[ly + 1][x] = 6
                c.p[ly + 2][x] = 5 if c.p[ly + 2][x] < 5 else c.p[ly + 2][x]
    return c.p


# ------------------------------------------------------------------ back walls (opaque, darker than the ground so the hero pops)

def bricks(x: int, y: int) -> int:
    row = y // 4
    bx = (x + (4 if row % 2 else 0)) % 8
    by = y % 4
    if by == 3 or bx == 7:
        return 1 if (bx == 7 and by == 3) else 2
    if by == 0 or bx == 0:
        return 4
    return 3


def back(name: str) -> list[list[int]]:
    c = Canvas(16, 16)
    for y in range(16):
        for x in range(16):
            v = bricks(x, y)
            if v == 3 and hsh(x, y, 61) < 0.07:
                v = 2
            c.set(x, y, v)
    if name == "back_b":  # a carved glyph slab
        c.rect(3, 3, 10, 10, 3)
        for i in range(3, 13):
            c.set(i, 3, 4)
            c.set(3, i, 4)
            c.set(i, 12, 1)
            c.set(12, i, 1)
        for x, y in ((5, 5), (6, 5), (7, 5), (8, 5), (9, 5), (10, 5), (5, 6), (5, 7), (7, 7), (8, 7), (9, 7), (10, 7),
                     (10, 8), (10, 9), (5, 9), (6, 9), (7, 9), (8, 9), (5, 10), (10, 10)):
            c.set(x, y, 0xa)
    elif name == "back_c":  # creepers over the wall
        for x0 in (3, 11):
            for y in range(16):
                x = x0 + round(math.sin(y / 2.5 + x0))
                c.set(x, y, 7)
                if y % 4 == 1:
                    c.set(x + 1, y, 8)
                    c.set(x + 2, y, 7)
                    c.set(x - 1, y + 1, 8)
    elif name == "back_d":  # moss patches and a crack
        for y in range(16):
            for x in range(16):
                if hsh(x // 2, y // 2, 63) < 0.25 and c.get(x, y) in (3, 4):
                    c.set(x, y, 7 if c.get(x, y) == 3 else 8)
        c.line(9, 0, 7, 6, 1)
        c.line(7, 6, 10, 11, 1)
    return c.p


# ------------------------------------------------------------------ scenery

def selva_far() -> list[list[int]]:
    W, H = 256, 160
    c = Canvas(W, H, wrap=True)
    sky = [1, 2, 3, 4, 5, 6]
    for y in range(H):
        t = (y / 118) ** 1.1
        for x in range(W):
            c.p[y][x] = ramp_at(sky, t, x, y)
    # golden glow near the horizon, left of centre
    for y in range(60, 125):
        for x in range(W):
            dx = min(abs(x - 70), W - abs(x - 70))
            r = math.hypot(dx / 1.8, (y - 112) * 1.0) / 60
            if r < 1 and dith(x, y, (1 - r) * 0.9):
                c.p[y][x] = 0xd if r < 0.45 else (6 if c.p[y][x] in (5, 6) else c.p[y][x])
    # clouds: piles of puffs, shaded bottoms
    for cx, cy, sc in ((30, 30, 1.0), (120, 18, 0.8), (196, 40, 1.15), (80, 62, 0.6), (240, 70, 0.55), (160, 74, 0.5)):
        for ox, oy, r in ((-14, 4, 9), (-4, -3, 12), (9, -1, 10), (19, 4, 8), (2, 6, 10), (-22, 8, 6), (27, 8, 6)):
            c.blob(cx + ox * sc, cy + oy * sc, r * sc * 1.1, r * sc * 0.8, [8, 7, 7, 7])
        for x in range(int(cx - 30 * sc), int(cx + 34 * sc)):  # flat cloud base
            for y in range(int(cy + 9 * sc), int(cy + 12 * sc)):
                if c.get(x, y - 1) in (7, 8):
                    c.set(x, y, 8)
    # far blue mountains (left-lit faces) with a stepped temple on one peak
    def ridge(x: float, base: float, parts) -> float:
        return base - sum(a * math.sin(2 * math.pi * (k * x / W) + ph) for a, k, ph in parts)
    far_parts = ((10, 2, 0.4), (6, 5, 1.3), (3, 11, 2.0))
    for x in range(W):
        r = ridge(x, 100, far_parts)
        up = ridge(x + 1, 100, far_parts) < r
        for y in range(int(r), 128):
            c.p[y][x] = 9 if (up and y < r + 14) else (0xa if y < r + 14 else 9)
        c.p[int(r)][x] = 8 if up else 9
    tx, ty = 176, int(ridge(176, 100, far_parts)) + 6
    for i, w in enumerate((40, 32, 25, 18, 12)):  # a stepped temple, pale in the haze
        y0 = ty - 6 * (i + 1)
        for y in range(y0, y0 + 6):
            for x in range(tx - w // 2, tx + w // 2):
                v = 7 if x < tx - w // 2 + 2 else (9 if x >= tx + w // 2 - 4 else 8)
                if y == y0 + 5:
                    v = 9
                c.set(x, y, v)
    c.rect(tx - 3, ty - 38, 6, 8, 8)
    c.rect(tx - 3, ty - 38, 2, 8, 7)
    c.rect(tx - 1, ty - 34, 2, 4, 0xa)
    c.rect(tx - 4, ty - 39, 8, 1, 9)
    for y in range(ty - 30, ty):  # the stair down its face
        for x in (tx - 2, tx + 1):
            c.set(x, y, 9 if (y % 2) else 8)
    # far jungle canopy and mist
    for x in range(-8, W + 8, 7):
        rr = 7 + hsh(x, 0, 5) * 6
        cy = 124 - hsh(x, 1, 5) * 8
        c.blob(x, cy, rr, rr * 0.8, [0xc, 0xb, 0xb, 0xf])
    for y in range(128, H):
        for x in range(W):
            if not c.p[y][x] or c.p[y][x] in sky + [0xd, 9, 0xa, 8]:
                c.p[y][x] = 0xc
    for y in range(134, 150):
        for x in range(W):
            if dith(x, y, 0.55 - abs(y - 142) / 16):
                c.p[y][x] = 0xf
    for y in range(150, H):
        for x in range(W):
            c.p[y][x] = 0xb if dith(x, y, 0.3) else 0xc
    return c.p


def selva_mid() -> list[list[int]]:
    W, H = 256, 128
    c = Canvas(W, H, wrap=True)
    leaf = [1, 2, 3, 4, 5]
    # the ruined temple with its waterfall
    tx = 96
    steps = ((60, 18), (48, 14), (36, 12), (24, 12))
    y = H - 30
    for w, hgt in steps:
        y0 = y - hgt
        for yy in range(y0, y):
            for x in range(tx - w // 2, tx + w // 2):
                v = 8 if (yy - y0) % 6 else 7
                if x < tx - w // 2 + 2 or yy == y0:
                    v = 9
                elif x >= tx + w // 2 - 3:
                    v = 7
                c.set(x, yy, v)
        y = y0
    c.rect(tx - 4, y - 12, 8, 12, 8)
    c.rect(tx - 2, y - 8, 4, 8, 1)
    c.rect(tx - 4, y - 12, 8, 1, 9)
    for yy in range(y, H):  # the waterfall pouring from the temple door
        for x in range(tx - 3, tx + 3):
            c.set(x, yy, 0xb if (yy * 3 + x * 5) % 11 < 3 else 0xa)
    for x in range(tx - 9, tx + 9):
        for yy in range(H - 10, H - 4):
            if dith(x, yy, 0.6):
                c.set(x, yy, 0xb)
    # trees: trunks and canopies (left-lit)
    trees = ((14, 52, 22), (44, 40, 18), (150, 46, 24), (186, 58, 16), (222, 38, 22), (250, 60, 14))
    for x0, ctop, r in trees:
        for yy in range(ctop, H):
            for x in range(x0 - 2, x0 + 3):
                c.set(x, yy, 0xd if x < x0 else 0xc)
        for i, (ox, oy, rr) in enumerate(((-r * 0.7, r * 0.5, 0.7), (r * 0.7, r * 0.55, 0.75), (0, 0, 1.0))):
            c.foliage(x0 + ox, ctop + oy, r * rr, leaf, seed=x0 + i)
    for x in range(-10, W + 10, 11):  # a low wall of darker bushes
        r = 10 + hsh(x, 9, 4) * 6
        c.foliage(x, 100 - hsh(x, 8, 4) * 8, r, [1, 2, 3, 4], seed=x + 99)
    for x in range(W):
        for yy in range(108, H):
            c.set(x, yy, 1 if yy > 114 or dith(x, yy, (yy - 106) / 8) else c.get(x, yy) or 1)
    for i in range(10):
        x, yy = int(hsh(i, 2, 13) * W), 92 + int(hsh(i, 3, 13) * 12)
        if c.get(x, yy) in (2, 3, 4):
            for ddx, ddy in ((0, -1), (1, 0), (0, 1), (-1, 0)):
                c.set(x + ddx, yy + ddy, 0xd)
            c.set(x, yy, 0xe)
    return c.p


def selva_near() -> list[list[int]]:
    """Jungle undergrowth just behind the level: banana leaves, bush clumps and a few flowers."""
    W, H = 256, 96
    c = Canvas(W, H, wrap=True)
    bush = [1, 2, 3, 4]
    for x0 in range(0, W, 64):  # tall banana leaves, ribbed
        for i, (ang, ln, b) in enumerate(((-160, 44, -0.8), (-125, 52, -0.55), (-92, 50, 0.2), (-58, 52, 0.55), (-22, 44, 0.8))):
            j = hsh(x0, i, 77)
            c.leaf(x0 + 22, H - 30, ang + j * 8, ln * (0.85 + j * 0.25), 7.5, (2, 3, 4, 5), bend=b, ribs=3)
        c.rect(x0 + 21, H - 32, 3, 20, 2)
    for x0 in range(0, W, 64):
        for ang, b in ((-140, -0.4), (-40, 0.4)):
            c.leaf(x0 + 52, H - 16, ang, 26, 4.5, (2, 3, 4, 5), bend=b, ribs=3)
    c.outline(1)
    for x in range(-12, W + 12, 13):  # bush clumps along the bottom
        r = 9 + hsh(x, 3, 8) * 7
        c.foliage(x, H - 18 - hsh(x, 4, 8) * 8, r, bush, seed=x)
    for x in range(W):
        top = H - 14 + round(2 * math.sin(2 * math.pi * x / 32))
        for y in range(top, H):
            c.set(x, y, 1)
    for i in range(14):  # flowers in the bushes
        x, y = int(hsh(i, 0, 31) * W), H - 20 - int(hsh(i, 1, 31) * 14)
        col = 8 if i % 3 else 9
        for ddx, ddy in ((0, -1), (1, 0), (0, 1), (-1, 0)):
            c.set(x + ddx, y + ddy, col)
        c.set(x, y, 9 if col == 8 else 7)
    return c.p


def selva_agua() -> list[list[int]]:
    """Golden light shafts falling through the canopy and a low mist (the engine blends it)."""
    W, H = 256, 160
    c = Canvas(W, H, wrap=True)
    for x0, wd, col in ((20, 18, 1), (64, 9, 2), (110, 24, 1), (170, 12, 2), (214, 16, 1)):
        for y in range(H):
            sx = x0 + y * 0.45
            fade = 1 - y / H
            for x in range(int(sx), int(sx + wd)):
                e = min(x - sx, sx + wd - x) / (wd / 2)
                if dith(x, y, min(1, e * 1.4) * (0.35 + 0.65 * fade)):
                    c.set(x, y, col if e > 0.45 else col + 1)
    for y in range(H - 28, H):
        for x in range(W):
            m = 0.5 + 0.5 * math.sin(2 * math.pi * x / 128 + y / 7)
            if dith(x, y, (y - (H - 28)) / 28 * 0.8 * (0.5 + 0.5 * m)):
                c.set(x, y, 4 if y > H - 10 else 5)
    for i in range(40):
        x, y = int(hsh(i, 0, 91) * W), int(hsh(i, 1, 91) * (H - 40))
        c.set(x, y, 6)
    return c.p


# ------------------------------------------------------------------ registration

def register() -> None:
    register_ground()
    ART.meta(SET, "plat_l", plank_platform("l"), "caja", flags=("oneway",))
    ART.meta(SET, "plat_m", plank_platform("m"), "caja", flags=("oneway",))
    ART.meta(SET, "plat_r", plank_platform("r"), "caja", flags=("oneway",))
    ART.meta(SET, "plat_s", plank_platform("s"), "caja", flags=("oneway",))
    ART.meta(SET, "block_brown", block_brown(), "caja", flags=("solid", "break"))
    ART.meta(SET, "block_blue", block_blue(), "caja", flags=("solid", "break_strong"))
    ART.meta(SET, "block_hard", block_hard(), "ruina", flags=("solid", "break_super"))
    ART.meta(SET, "box_jewel", crate("gem"), "caja", flags=("solid", "break", "jewel"))
    ART.meta(SET, "box_coin", crate("coin"), "caja", flags=("solid", "break", "coin"))
    ART.meta(SET, "spikes_up", spikes(), "caja", flags=("hurt",))
    ART.meta(SET, "spikes_down", flip_v(spikes()), "caja", flags=("hurt",))
    for n in "abcdefgh":
        p, bank = deco(f"deco_{n}")
        ART.meta(SET, f"deco_{n}", p, bank)
    for n in "abcdefgh":
        p, bank = front(f"front_{n}")
        ART.meta(SET, f"front_{n}", blank(16, 16), bank, front=p, front_bank=bank)
    for n in "abcd":
        ART.meta(SET, f"back_{n}", back(f"back_{n}"), "ruina")
    ART.meta(SET, "spring_a", mushroom(False), "planta", flags=("solid", "spring"))
    ART.meta(SET, "spring_b", mushroom(True), "planta", flags=("solid", "spring"))
    ART.meta(SET, "tiki_block", tiki_block(), "ruina", flags=("solid", "break_super"))
    for f in range(4):
        ART.meta(SET, f"waterfall_{f}", water_column(f, False), "agua")
    for f in range(4):
        ART.meta(SET, f"waterfall_top_{f}", water_column(f, True), "agua")
    ART.meta(SET, "vine_a", vine(False), "planta")
    ART.meta(SET, "vine_b", vine(True), "planta")
    for k in "lmr":
        ART.meta(SET, f"leaf_plat_{k}", leaf_platform(k), "planta", flags=("oneway",))
    ART.scenery("selva_far", selva_far(), SET, "cielo")
    ART.scenery("selva_mid", selva_mid(), SET, "monte")
    ART.scenery("selva_near", selva_near(), SET, "fronda")
    ART.scenery("selva_agua", selva_agua(), SET, "luz")


register()


# ------------------------------------------------------------------ the composed test scene (preview only)

SCENE = [
    "....................",
    "......ff......a.....",
    "..........LMR.......",
    "...........v...gg...",
    "...vw........SPSB...",
    "...v...........##...",
    ".p...J.......c#d##.d",
    "###C####..###1#####.",
    "########^^#########.",
    "#########mm#########",
]


def autotile(grid: list[str], solid: str = "#") -> dict[tuple[int, int], str]:
    hgt, wid = len(grid), len(grid[0])
    def s(x: int, y: int) -> bool:
        if y < 0:
            return False
        if y >= hgt or x < 0 or x >= wid:
            return True
        return grid[y][x] in solid
    out = {}
    for y in range(hgt):
        for x in range(wid):
            if not s(x, y) or grid[y][x] != "#":
                continue
            m = (not s(x, y - 1)) * 1 + (not s(x + 1, y)) * 2 + (not s(x, y + 1)) * 4 + (not s(x - 1, y)) * 8
            name = f"ground_m{m}"
            if m == 0:
                for dg, (ddx, ddy) in (("ne", (1, -1)), ("nw", (-1, -1)), ("se", (1, 1)), ("sw", (-1, 1))):
                    if not s(x + ddx, y + ddy):
                        name = f"ground_in_{dg}"
                        break
                else:
                    r = hsh(x, y, 5)
                    if r < 0.45:
                        name = f"ground_alt{int(r * 9) % 4}"
            elif m == 1:
                r = hsh(x, y, 6)
                name = "ground_m1_b" if r < 0.25 else ("ground_m1_c" if r < 0.4 else name)
            out[(x, y)] = name
    return out


def compose(set_: str, grid: list[str], legend: dict[str, str], layers: list[tuple[str, float]], out_name: str,
            scale: int = 2) -> Path:
    W, H = len(grid[0]) * 16, len(grid) * 16
    img = to_image([[0] * W for _ in range(H)], [(0, 0, 0)] * 15, 1, back=(0, 0, 0))
    pal = ART.palettes[set_]
    for name, k in layers:
        p, _, bank = ART.sceneries[name]
        layer = to_image(p, pal[bank], 1)
        mask = Image_mask(p)
        pw, ph = len(p[0]), len(p)
        ox = int(k * 40)
        for x0 in range(-pw, W + pw, pw):
            img.paste(layer, (x0 - ox % pw, H - ph), mask)
    tiles = autotile(grid)
    fronts = []
    for y, row in enumerate(grid):
        for x, ch in enumerate(row):
            name = tiles.get((x, y)) or legend.get(ch)
            if not name:
                continue
            m = ART.metas[set_][name]
            img.paste(to_image(m.ground, pal[m.bank], 1), (x * 16, y * 16), Image_mask(m.ground))
            if m.front is not None:
                fronts.append((x, y, m))
    hero = Image_hero()
    img.paste(hero, (6 * 16, 7 * 16 - hero.size[1]), hero)
    for x, y, m in fronts:
        img.paste(to_image(m.front, pal[m.front_bank], 1), (x * 16, y * 16), Image_mask(m.front))
    if "agua" in layers[-1][0]:
        pass
    out = ART_DIR / out_name
    ART_DIR.mkdir(exist_ok=True)
    img.resize((W * scale, H * scale), 0).save(out)
    return out


def Image_mask(p):
    from PIL import Image
    m = Image.new("L", (len(p[0]), len(p)), 0)
    px = m.load()
    for y, row in enumerate(p):
        for x, v in enumerate(row):
            if v:
                px[x, y] = 255
    return m


def Image_hero():
    """A stand-in silhouette the size of the hero (to judge scale and contrast in the scene)."""
    from PIL import Image
    im = Image.new("RGBA", (22, 26), (0, 0, 0, 0))
    px = im.load()
    for y in range(26):
        for x in range(22):
            if ((x - 11) / 10) ** 2 + ((y - 15) / 11) ** 2 <= 1:
                px[x, y] = (230, 200, 40, 255) if y < 14 else (140, 40, 160, 255)
    return im


def blend_layer(img_path: Path, set_: str, name: str, alpha: float = 0.35) -> None:
    from PIL import Image
    img = Image.open(img_path).convert("RGB")
    p, _, bank = ART.sceneries[name]
    sc = img.size[0] // (len(SCENE[0]) * 16)
    lay = to_image(p, ART.palettes[set_][bank], 1).convert("RGB")
    W, H = img.size[0] // sc, img.size[1] // sc
    full = Image.new("RGB", (W, H))
    msk = Image.new("L", (W, H), 0)
    pm = Image_mask(p)
    for x0 in range(0, W, len(p[0])):
        full.paste(lay, (x0, H - len(p)))
        msk.paste(pm, (x0, H - len(p)))
    full = full.resize(img.size, 0)
    msk = msk.resize(img.size, 0).point(lambda v: int(v * alpha))
    img.paste(full, (0, 0), msk)
    img.save(img_path)


if __name__ == "__main__":
    LEGEND = {"p": "spring_a", "J": "box_jewel", "C": "box_coin", "c": "deco_c", "d": "deco_a", "f": "front_a", "a": "front_e",
              "L": "leaf_plat_l", "M": "leaf_plat_m", "R": "leaf_plat_r", "v": "vine_a", "w": "waterfall_top_0",
              "S": "plat_l", "P": "plat_m", "B": "plat_r", "g": "deco_b", "^": "spikes_up", "m": "mud_top", "1": "tiki_block"}
    print(preview_metas(SET, cols=10, scale=3))
    for n in ("selva_far", "selva_mid", "selva_near", "selva_agua"):
        print(preview_scenery(n, 2))
    out = compose(SET, SCENE, LEGEND, [("selva_far", 0.2), ("selva_mid", 0.5), ("selva_near", 0.8)], "scene_selva.png")
    blend_layer(out, SET, "selva_agua", 0.3)
    print(out)
