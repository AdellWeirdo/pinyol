"""Botín, passage 2: CRISTAL. A dark crystal cave: deep violet and blue faceted rock lit by glowing pink, cyan and green
crystals, wet glossy floors, stalactites and an old mine (planks, lanterns, chains). The game puts a spotlight on the hero, so
the cave stays in deep saturated violets and blues (never black) and the crystals pop. Palette set "cristal".

Run on its own: python3 gen/art_cristal.py  (writes previews into art/, nothing into assets/)."""
from __future__ import annotations

import math
import sys
from pathlib import Path

GEN = Path(__file__).resolve().parent
sys.path.insert(0, str(GEN))

from gbakit import ART, ART_DIR, blank, flip_h, flip_v, overlay, pic, preview_metas, preview_scenery, to_image  # noqa: E402

SET = "cristal"
BIG = 99

# ------------------------------------------------------------------ palettes (slot meaning noted per bank)
# roca: 1 outline | 2-7 violet rock ramp | 8-b wet floor blues | c glint | d-e cyan crystal | f pink fleck
ART.palette(SET, "roca", ["#0a0624", "#1a0f4a", "#2c1a78", "#4428a4", "#6440c8", "#8c68e4", "#c0a0ff", "#0c2a6c",
                          "#1a50b0", "#2c88e0", "#68d0ff", "#e8fcff", "#12a8b0", "#40f0d8", "#ff58c8"])
# cristal: 1 outline | 2-5 pink ramp | 6-9 cyan ramp | a-d green ramp | e white | f rock foot
ART.palette(SET, "cristal", ["#140a3c", "#6c1478", "#c02cb0", "#ff60d8", "#ffb8f0", "#0c3c8c", "#1898d8", "#40e4f8",
                             "#c0fcff", "#0c6048", "#1cb058", "#6cf878", "#d8ffc8", "#ffffff", "#3a2290"])
# mina: 1 outline | 2-6 wood/amber ramp | 7-a iron blue ramp | b-d gold | e jewel | f white
ART.palette(SET, "mina", ["#140a30", "#4a1c3c", "#8c3c34", "#d07434", "#f8b45c", "#fff0a8", "#1c2c6c", "#3c5cb0",
                          "#78a0e8", "#c8e0ff", "#a05808", "#f8c020", "#fff890", "#e01868", "#ffffff"])
# scenery banks
ART.palette(SET, "abismo", ["#0a0628", "#160c46", "#241466", "#32208a", "#4630aa", "#c050c8", "#7050d0", "#8c70e0",
                            "#c0a8ff", "#5a3cb8", "#7a2c9c", "#ffc0f0", "#1c4c9c", "#3cb0e8", "#ffffff"])
ART.palette(SET, "caverna", ["#08051e", "#140b3c", "#22165e", "#34237e", "#4a35a0", "#6a52c4", "#8a2aa0", "#e04cd4",
                             "#ffb0f4", "#1a64b0", "#3cc8f0", "#c8f8ff", "#148a58", "#3ce07c", "#c8ffd0"])
ART.palette(SET, "penumbra", ["#050318", "#0e0830", "#1a104c", "#2a1a6c", "#6a1a8c", "#c03ccc", "#ffa0f0", "#1a54a0", "#48c4f0"])
ART.palette(SET, "niebla", ["#6050c0", "#8070e0", "#ff90e8", "#90f0ff", "#ffffff", "#b0a0ff"])


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



# ------------------------------------------------------------------ CRISTAL ground: faceted violet rock, a wet glossy floor

def wrapd(ax: float, ay: float, bx: float, by: float) -> float:
    dx = min(abs(ax - bx), 16 - abs(ax - bx))
    dy = min(abs(ay - by), 16 - abs(ay - by))
    return dx * dx + dy * dy


BORDER_PTS = [(2, 1), (10, 0.5), (15.5, 5), (14, 12), (7, 15.5), (0.5, 10)]
INNER_PTS = {
    0: [(6, 6), (11, 8), (5, 11)],
    1: [(8, 5), (5, 9), (11, 10)],
    2: [(5, 5), (10, 6), (8, 11)],
    3: [(7, 7), (11, 4), (4, 12)],
    4: [(9, 8), (5, 6), (12, 10)],
}


def facet_id(x: float, y: float, seed: int) -> int:
    pts = BORDER_PTS + INNER_PTS[seed % 5]
    return min(range(len(pts)), key=lambda i: wrapd(x + 0.5, y + 0.5, *pts[i]))


def rock(x: int, y: int, seed: int = 0) -> int:
    """Chunky violet rock facets: each facet one tone, lit top-left edges, dark cracks bottom-right."""
    me = facet_id(x, y, seed)
    if facet_id((x + 1) % 16, (y + 1) % 16, seed) != me or facet_id((x + 1) % 16, y, seed) != me:
        return 2
    if facet_id((x - 1) % 16, (y - 1) % 16, seed) != me or facet_id(x, (y - 1) % 16, seed) != me:
        return 5
    tone = (4, 3, 4, 3, 3, 4, 4, 3, 3)[(me * 3 + seed) % 9]
    if dith(x, y, 0.18):
        return tone + 1 if tone == 3 else tone - 1
    return tone


def rock_props(seed: int) -> Canvas:
    c = Canvas(16, 16)
    if seed == 1:  # a cyan crystal vein
        for (ax, ay), (bx, by) in (((2, 12), (6, 9)), ((6, 9), (9, 9)), ((9, 9), (13, 5))):
            c.line(ax, ay, bx, by, 0xd)
            c.line(ax, ay - 1, bx, by - 1, 0xe)
        c.set(9, 8, 0xc)
    elif seed == 2:  # embedded pink gems
        for gx, gy in ((5, 6), (11, 11)):
            c.set(gx, gy, 0xf)
            c.set(gx + 1, gy, 0xf)
            c.set(gx, gy - 1, 0xc)
            c.set(gx + 1, gy + 1, 2)
            c.set(gx, gy + 1, 2)
    elif seed == 3:  # a wet streak
        for y in range(2, 14):
            c.set(7 + (y > 7), y, 9 if y % 3 else 0xa)
        c.set(8, 14, 0xa)
    elif seed == 4:  # a cyan crystal knot
        for x, y, v in ((7, 6, 1), (8, 6, 0xd), (9, 6, 1), (6, 7, 0xd), (7, 7, 0xe), (8, 7, 0xc), (9, 7, 0xd),
                        (7, 8, 0xd), (8, 8, 0xd), (8, 9, 2)):
            c.set(x, y, v)
    return c


SPROUTS = [1, 1, 1, 0, 1, 1, 1, 1, 1, 1, 0, 0, 1, 1, 1, 1]
FLOOR_T = [4, 4, 3, 3, 4, 4, 5, 5, 4, 3, 3, 4, 4, 5, 4, 4]
STAL = [0, 1, 2, 1, 0, 0, 0, 1, 2, 3, 2, 1, 0, 0, 1, 0]


def cristal_ground(mask: int, seed: int = 0, diag: str | None = None, tops=SPROUTS, ft=FLOOR_T, extra=None):
    t = blank(16, 16)
    props = rock_props(seed)
    for y in range(16):
        for x in range(16):
            d = depths(mask, x, y)
            if d is None:
                continue
            dn, de, ds, dw = d["n"], d["e"], d["s"], d["w"]
            v = rock(x, y, seed)
            plain = True
            if dn < BIG:
                k = dn - tops[x]
                if k < 0:
                    continue
                g = ft[x]
                if k <= g:  # the wet floor: a glossy blue lip catching the crystal light
                    if k == 0 or de == 0 or dw == 0:
                        v = 1
                    elif k == 1:
                        v = 0xc if hsh(x, seed, 3) < 0.25 else 0xb
                    elif k == 2:
                        v = 0xa
                    elif k == g:
                        v = 8
                    else:
                        v = 9 if (x + k) % 5 else 0xa
                    if de == 1 and v in (0xb, 0xc, 0xa):
                        v = 9
                    if dw == 1 and v in (9, 0xa):
                        v = 0xb
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
                    k = ds - STAL[x]
                    if k < 0:
                        continue
                    v = (1, 2, 2 if x % 2 else 3, 3 if dith(x, y, 0.5) else v)[k] if k <= 3 else v
                elif de == m:
                    v = (1, 8, 2, 2 if dith(x, y, 0.5) else v)[de]
                else:
                    v = (1, 7, 6, 6 if dith(x, y, 0.4) else v)[dw]
                    if v == 7 and dn <= ft[x] + 3:
                        v = 6
            if diag:
                k, side = nook(x, y, diag)
                if k <= 2:
                    plain = False
                    if "n" in diag:
                        if side:
                            v = (1, 0xa, 9)[k]
                        else:
                            v = (1, 8, 2)[k] if "e" in diag else (1, 7, 6)[k]
                    else:
                        v = (1, 2, 3)[k] if (side or "e" in diag) else (1, 7, 6)[k]
            if plain and props.get(x, y):
                v = props.get(x, y)
            t[y][x] = v
    if extra:
        t = overlay(t, extra)
    return t


def floor_sprouts() -> list[list[int]]:
    """Little crystal tips poking up through the floor (alternate top)."""
    c = Canvas(16, 16)
    for x0, hgt in ((3, 3), (11, 4)):
        for y in range(hgt):
            c.set(x0, 1 - y + 1, 0xe if y < hgt - 1 else 0xc)
            c.set(x0 + 1, 1 - y + 1, 0xd)
        c.set(x0 - 1, 2, 1)
        c.set(x0 + 2, 2, 1)
    return [[v if y >= 0 else 0 for v in row] for y, row in enumerate(c.p)]


def floor_puddle() -> list[list[int]]:
    c = Canvas(16, 16)
    for x in range(4, 13):
        c.set(x, 2, 0xc if x in (6, 7) else 0xb)
        c.set(x, 3, 0xb if x % 3 else 0xc)
    c.set(3, 2, 0xa)
    c.set(13, 2, 0xa)
    return c.p


def register_ground() -> None:
    for m in range(16):
        ART.meta(SET, f"ground_m{m}", cristal_ground(m, seed=0), "roca", flags=("solid",))
    for i in range(4):
        ART.meta(SET, f"ground_alt{i}", cristal_ground(0, seed=i + 1), "roca", flags=("solid",))
    tb = [1, 1, 0, 1, 1, 1, 1, 1, 0, 1, 1, 1, 1, 1, 1, 0]
    ART.meta(SET, "ground_m1_b", cristal_ground(1, seed=2, tops=tb, extra=floor_sprouts()), "roca", flags=("solid",))
    ART.meta(SET, "ground_m1_c", cristal_ground(1, seed=3, extra=floor_puddle()), "roca", flags=("solid",))
    for dg in ("ne", "nw", "se", "sw"):
        ART.meta(SET, f"ground_in_{dg}", cristal_ground(0, seed=0, diag=dg), "roca", flags=("solid",))


# ------------------------------------------------------------------ crystals (bank cristal)

PINK, CYAN, GREEN = (2, 3, 4, 5), (6, 7, 8, 9), (0xa, 0xb, 0xc, 0xd)


def shard(c: Canvas, x: float, y: float, ang: float, length: float, width: float, ramp, glint: int = 0xe) -> None:
    """A six-sided crystal prism growing from (x, y) at angle `ang` (degrees, -90 = straight up): lit left face,
    darker right face, a bright edge and a pointed tip."""
    dark, mid, light, pale = ramp
    a = math.radians(ang)
    dx, dy = math.cos(a), math.sin(a)
    px, py = -dy, dx
    tip = length * 0.72
    steps = int(length * 3) + 1
    for i in range(steps + 1):
        u = i / 3
        half = width if u < tip else width * max(0.0, (length - u) / (length - tip))
        vv = -half
        while vv <= half:
            xx, yy = round(x + dx * u + px * vv - 0.5), round(y + dy * u + py * vv - 0.5)
            f = vv / max(half, 0.01)
            if f < -0.55:
                col = pale if u > tip * 0.2 else light
            elif f < 0.0:
                col = light
            elif f < 0.45:
                col = mid
            else:
                col = dark
            if u > tip and f < 0:
                col = pale
            c.set(xx, yy, col)
            vv += 0.3
    gx, gy = x + dx * length * 0.45 + px * -width * 0.35, y + dy * length * 0.45 + py * -width * 0.35
    c.set(round(gx), round(gy), glint)


def cluster(kind: str) -> list[list[int]]:
    c = Canvas(16, 16)
    ramp = {"a": PINK, "b": CYAN, "c": GREEN}[kind]
    if kind == "a":
        parts = ((8, 16, -95, 15, 2.6), (4, 16, -125, 10, 2.0), (12, 16, -62, 11, 2.0), (6, 16, -105, 6, 1.5))
    elif kind == "b":
        parts = ((6, 16, -100, 13, 2.4), (11, 16, -75, 9, 2.2), (3, 16, -135, 7, 1.6), (13, 16, -45, 6, 1.5))
    else:
        parts = ((9, 16, -88, 12, 2.4), (5, 16, -118, 9, 2.0), (13, 16, -60, 7, 1.6))
    for x, y, a, ln, w in parts:
        shard(c, x, y, a, ln, w, ramp)
    c.outline(1)
    for x in range(3, 14):  # a rock foot
        c.set(x, 15, 0xf)
        if 4 < x < 12:
            c.set(x, 14, 0xf if c.get(x, 14) in (0, 1) else c.get(x, 14))
    return c.p


def crystal_block() -> list[list[int]]:
    """A hard block of clear cyan crystal: bevelled glass with facets and a sparkle."""
    c = bevel_block(8, 0xe, 9, 6, 7)
    for y in range(3, 13):
        for x in range(3, 13):
            if x + y < 11:
                c.set(x, y, 9)
            elif x - y > 4:
                c.set(x, y, 7)
            elif x + y > 20:
                c.set(x, y, 7)
    c.line(3, 7, 7, 3, 0xe)
    c.line(4, 12, 12, 4, 9)
    c.line(5, 12, 12, 5, 7)
    for x, y in ((5, 5), (11, 10)):
        c.set(x, y, 0xe)
    c.set(10, 10, 0xe)
    c.set(9, 10, 9)
    c.set(11, 9, 9)
    c.set(10, 11, 9)
    return c.p


def ice_platform(kind: str) -> list[list[int]]:
    """A one-way slab of cyan crystal with a faceted underside."""
    c = Canvas(16, 16)
    under = {"l": [0, 0, 1, 2, 3, 3, 4, 5, 4, 3, 4, 5, 6, 5, 4, 3], "m": [3, 4, 5, 4, 3, 4, 6, 7, 6, 4, 3, 4, 5, 4, 3, 3],
             "r": [3, 4, 5, 4, 3, 4, 5, 6, 5, 4, 3, 3, 2, 1, 0, 0]}[kind]
    for x in range(16):
        if kind == "l" and x < 1 or kind == "r" and x > 14:
            continue
        for y in range(0, 5 + under[x]):
            if y == 0:
                v = 1
            elif y == 1:
                v = 0xe if x % 5 == 2 else 9
            elif y == 2:
                v = 8
            elif y < 5:
                v = 8 if (x + y) % 6 else 9
            else:
                v = 7 if y < 4 + under[x] else 6
            c.set(x, y, v)
    c.outline(1)
    if kind == "m":
        for y in range(16):
            for x in (0, 15):
                if c.p[y][x] == 1 and 1 <= y <= 4:
                    c.p[y][x] = c.p[y][1 if x == 0 else 14]
    elif kind == "l":
        for y in range(1, 5):
            if c.p[y][15] == 1:
                c.p[y][15] = c.p[y][14]
    else:
        for y in range(1, 5):
            if c.p[y][0] == 1:
                c.p[y][0] = c.p[y][1]
    return c.p


def glow(kind: str) -> list[list[int]]:
    """A soft glow (decor): a dithered halo round a bright core, with motes."""
    c = Canvas(16, 16)
    ramp = PINK if kind == "a" else CYAN
    cx, cy = (8, 8) if kind == "a" else (7, 9)
    for y in range(16):
        for x in range(16):
            r = math.hypot(x + 0.5 - cx, (y + 0.5 - cy) * 1.1) / 7.5
            if r < 0.22:
                c.set(x, y, 0xe)
            elif r < 0.4:
                c.set(x, y, ramp[3])
            elif r < 0.62 and dith(x, y, (0.62 - r) / 0.22):
                c.set(x, y, ramp[2])
            elif r < 1.0 and dith(x, y, (1.0 - r) / 0.38 * 0.35):
                c.set(x, y, ramp[1])
    motes = ((2, 3), (13, 2), (12, 13)) if kind == "a" else ((3, 2), (14, 6), (2, 14))
    for x, y in motes:
        c.set(x, y, ramp[3])
    return c.p


def crystal_spikes() -> list[list[int]]:
    """Spikes: a row of sharp pink crystal points on a rock ledge."""
    c = Canvas(16, 16)
    for x0, ln, a in ((2, 12, -96), (6, 9, -84), (9, 13, -92), (13, 10, -80)):
        shard(c, x0, 14, a, ln, 1.6, PINK)
    c.outline(1)
    for x in range(16):
        c.set(x, 13, 1)
        c.set(x, 14, 0xf)
        c.set(x, 15, 1)
    for x in (1, 7, 12):
        c.set(x, 14, 3)
    return c.p


# ------------------------------------------------------------------ mine things (bank mina): blocks, crates, planks, lamps, chains

def mine_platform(kind: str) -> list[list[int]]:
    """A mine plank on iron brackets; a beam under the ends."""
    c = Canvas(16, 16)
    x0 = 1 if kind in ("l", "s") else 0
    x1 = 14 if kind in ("r", "s") else 15
    for y, v in {0: 1, 1: 5, 2: 4, 3: 4, 4: 3, 5: 1}.items():
        for x in range(x0, x1 + 1):
            vv = v
            if y in (2, 3) and (x * 5 + y) % 7 == 0:
                vv = 3
            if x in (5, 13) and 1 <= y <= 4:
                vv = 2
            c.set(x, y, vv)
    if kind in ("l", "s"):
        for y in range(1, 5):
            c.set(0, y, 1)
    if kind in ("r", "s"):
        for y in range(1, 5):
            c.set(15, y, 1)
    brackets = {"l": (3,), "m": (8,), "r": (11,), "s": (3, 11)}[kind]
    for bx in brackets:
        for y in range(1, 9):
            c.set(bx, y, 9 if y < 5 else 8)
            c.set(bx + 1, y, 8 if y < 5 else 7)
        c.set(bx, 2, 0xa)
        c.set(bx + 1, 7, 0xa)
        for y in range(5, 9):
            c.set(bx - 1, y, 1)
            c.set(bx + 2, y, 1)
        c.set(bx, 9, 1)
        c.set(bx + 1, 9, 1)
    return c.p


def rubble_block() -> list[list[int]]:
    """A breakable block of amber rubble: four chunks mortared together."""
    c = bevel_block(4, 6, 5, 2, 3)
    for (x0, y0, w, hg) in ((2, 2, 7, 6), (9, 2, 5, 5), (2, 8, 5, 6), (7, 7, 7, 7)):
        for y in range(y0, y0 + hg):
            for x in range(x0, x0 + w):
                v = 4
                if y == y0 or x == x0:
                    v = 5
                if y == y0 + hg - 1 or x == x0 + w - 1:
                    v = 2
                if v == 4 and hsh(x, y, 3) < 0.12:
                    v = 3
                c.set(x, y, v)
    for i in range(16):
        c.set(i, 0, 1)
        c.set(0, i, 1)
        c.set(15, i, 1)
        c.set(i, 15, 1)
    c.set(4, 4, 6)
    c.set(11, 4, 6)
    return c.p


def iron_block(kind: str) -> list[list[int]]:
    """block_blue: blue iron frame with an X brace; block_hard: a thick riveted iron plate."""
    c = bevel_block(8, 0xa, 9, 7, 7)
    if kind == "blue":
        for y in range(3, 13):
            for x in range(3, 13):
                c.set(x, y, 7)
        for i in range(3, 13):
            c.set(i, i, 9)
            c.set(i, i + 1, 8) if i < 12 else None
            c.set(15 - i, i, 9)
            c.set(16 - i, i, 8) if i > 3 else None
        c.set(7, 7, 0xa)
        c.set(8, 8, 0xa)
        for x, y in ((3, 3), (12, 3), (3, 12), (12, 12)):
            c.set(x, y, 0xf)
    else:
        for y in range(3, 13):
            for x in range(3, 13):
                c.set(x, y, 8 if (x // 5 + y // 5) % 2 else 7)
        for x, y in ((4, 4), (11, 4), (4, 11), (11, 11), (7, 4), (4, 7), (11, 7), (7, 11)):
            c.set(x, y, 0xa)
            c.set(x + 1, y + 1, 1)
            c.set(x + 1, y, 9)
        c.rect(6, 6, 4, 4, 9)
        c.rect(7, 7, 2, 2, 7)
        c.set(6, 6, 0xa)
    return c.p


def mine_crate(emblem: str) -> list[list[int]]:
    c = bevel_block(3, 5, 4, 2, 2)
    for y in range(3, 13):
        for x in range(3, 13):
            c.set(x, y, 3 if y % 4 else 2)
    for x, y in ((1, 1), (2, 1), (1, 2), (14, 1), (13, 1), (14, 2), (1, 14), (1, 13), (2, 14), (14, 14), (13, 14), (14, 13)):
        c.set(x, y, 9)
    for x, y in ((2, 2), (13, 2), (2, 13), (13, 13)):
        c.set(x, y, 0xa)
    if emblem == "gem":
        g = ["....1111....", "...1effe1...", "..1eeeeee1..", "..1eefeee1..", "...1eeee1...", "....1ee1....", ".....11....."]
        for yy, row in enumerate(g):
            for xx, ch in enumerate(row):
                if ch != ".":
                    c.set(xx + 2, yy + 4, int(ch, 16))
        c.set(4, 6, 0xc)
        c.set(11, 6, 0xc)
    else:
        coin = ["...1111...", "..1dddc1..", ".1dfdccc1.", ".1ddcccb1.", ".1dcccbb1.", ".1dccbbb1.", "..1cbbb1..", "...1111..."]
        for yy, row in enumerate(coin):
            for xx, ch in enumerate(row):
                if ch != ".":
                    c.set(xx + 3, yy + 4, int(ch, 16))
        for yy in range(6, 10):
            c.set(7, yy, 0xb)
            c.set(8, yy, 0xd)
    return c.p


def lamp(on: bool) -> list[list[int]]:
    """A miner's lantern hanging on a chain: unlit dark glass, or lit with a warm glow round it."""
    c = Canvas(16, 16)
    if on:
        for y in range(16):
            for x in range(16):
                r = math.hypot(x + 0.5 - 8, y + 0.5 - 10) / 8
                if 0.45 < r < 1 and dith(x, y, (1 - r) * 0.55):
                    c.set(x, y, 6 if r < 0.7 else 5)
    for y in range(0, 5):
        c.set(7 + (y % 2), y, 9 if y % 2 else 8)
    lamp_rows = [
        "....1111....",
        "...199a91...",
        "..11111111..",
        "..19GGGG81..",
        "..19GHHG81..",
        "..18GHHG71..",
        "..18GGGG71..",
        "..11111111..",
        "...199871...",
        "....1111....",
    ]
    glass = {"G": 0xc if on else 7, "H": 0xd if on else 8}
    for yy, row in enumerate(lamp_rows):
        for xx, ch in enumerate(row):
            if ch == ".":
                continue
            v = glass[ch] if ch in glass else int(ch, 16)
            c.set(xx + 2, yy + 5, v)
    if on:
        c.set(6, 9, 0xf)
        c.set(6, 10, 0xd)
    else:
        c.set(6, 9, 9)
    return c.p


def drip(frame: int) -> list[list[int]]:
    """A water drip (roca wet blues): it swells under the ceiling, stretches, falls, and splashes."""
    c = Canvas(16, 16)
    if frame == 0:
        for x, y, v in ((7, 0, 9), (8, 0, 0xa), (7, 1, 0xb), (8, 1, 0xa)):
            c.set(x, y, v)
    elif frame == 1:
        for x, y, v in ((7, 0, 9), (8, 0, 0xa), (7, 1, 0xa), (8, 1, 0xa), (7, 2, 0xb), (8, 2, 0xa), (7, 3, 0xc), (8, 3, 0xb), (7, 4, 0xb)):
            c.set(x, y, v)
    elif frame == 2:
        c.set(7, 0, 9)
        for x, y, v in ((7, 6, 0xb), (7, 7, 0xc), (8, 7, 0xb), (7, 8, 0xb), (8, 8, 0xa), (7, 9, 0xa)):
            c.set(x, y, v)
    else:
        for x, y, v in ((7, 13, 0xc), (8, 13, 0xb), (5, 12, 0xb), (10, 12, 0xb), (4, 11, 0xa), (11, 11, 0xa), (6, 14, 0xa), (9, 14, 0xa),
                        (5, 15, 9), (6, 15, 0xb), (7, 15, 0xb), (8, 15, 0xb), (9, 15, 0xb), (10, 15, 9)):
            c.set(x, y, v)
    return c.p


# ------------------------------------------------------------------ decor, front, back

def stalactite(c: Canvas, x: int, ln: int, w: int, up: bool = False) -> None:
    """A rock stalactite (roca) hanging from the top (or a stalagmite rising from the bottom)."""
    for i in range(ln):
        half = w * (1 - i / ln)
        y = i if not up else 15 - i
        for xx in range(int(x - half), int(x + half) + 1):
            fx = (xx + 0.5 - x) / max(half, 0.5)
            c.set(xx, y, 6 if fx < -0.4 else (4 if fx < 0.3 else 3))
    c.set(x, ln if not up else 15 - ln, 0xb if not up else 0)


def deco(name: str) -> tuple[list[list[int]], str]:
    c = Canvas(16, 16)
    if name == "deco_a":  # little cyan shards in the ground
        for x0, ln, a in ((4, 7, -110), (7, 10, -88), (11, 6, -65)):
            shard(c, x0, 16, a, ln, 1.4, CYAN)
        c.outline(1)
        return c.p, "cristal"
    if name == "deco_b":  # glowing cave mushrooms
        for cx, cy, r, st in ((5, 8, 3.6, 8), (11, 11, 2.6, 4)):
            c.rect(int(cx) - 1, int(cy) + 1, 2, 16 - int(cy) - 1, 0xd)
            c.blob(cx, cy, r, r * 0.65, [0xa, 0xb, 0xc, 0xd])
        c.outline(1)
        for x, y in ((2, 3), (13, 6), (9, 4)):
            c.set(x, y, 0xc)
        return c.p, "cristal"
    if name == "deco_c":  # a pickaxe left in a pile of rubble
        c.line(5, 4, 11, 13, 3)
        c.line(6, 4, 12, 13, 4)
        c.line(7, 4, 12, 12, 5)
        for x, y, v in ((1, 6, 8), (2, 5, 9), (3, 4, 9), (4, 3, 0xa), (5, 3, 0xa), (6, 3, 9), (7, 3, 9), (8, 3, 8),
                        (9, 4, 8), (10, 5, 7), (11, 6, 7), (4, 4, 8), (5, 4, 8), (6, 2, 0xa), (7, 2, 9)):
            c.set(x, y, v)
        c.outline(1)
        for x, y, r in ((4, 15, 3), (10, 15, 3.6), (14, 15, 2.2)):
            c.blob(x, y, r, r * 0.75, [2, 3, 4, 5])
        c.outline(1)
        return c.p, "mina"
    if name == "deco_d":  # a stalagmite
        stalactite(c, 8, 14, 4, up=True)
        stalactite(c, 3, 6, 2, up=True)
        stalactite(c, 13, 8, 2, up=True)
        c.outline(1)
        return c.p, "roca"
    if name == "deco_e":  # a timber prop (mine support)
        c.rect(3, 0, 3, 16, 4)
        c.rect(10, 0, 3, 16, 4)
        c.rect(1, 1, 14, 3, 5)
        for x in (3, 10):
            c.rect(x + 2, 4, 1, 12, 3)
            c.rect(x, 4, 1, 12, 5)
        c.rect(1, 3, 14, 1, 3)
        c.line(6, 4, 9, 8, 3)
        for x, y in ((4, 2), (11, 2)):
            c.set(x, y, 0xa)
        c.outline(1)
        return c.p, "mina"
    if name == "deco_f":  # stones with glinting flecks
        for x, y, r in ((5, 12, 5), (12, 11, 4), (9, 15, 4)):
            c.blob(x, y, r, r * 0.8, [2, 3, 4, 5, 6])
        c.outline(1)
        for x, y in ((3, 10), (11, 9), (8, 14)):
            c.set(x, y, 0xf)
            c.set(x + 1, y + 1, 2)
        c.set(13, 12, 0xe)
        return c.p, "roca"
    if name == "deco_g":  # glow bulbs: a cave flower
        c.line(8, 15, 8, 6, 0xa)
        c.line(8, 10, 4, 7, 0xa)
        c.line(8, 9, 12, 5, 0xa)
        for x, y, ramp in ((8, 4, PINK), (4, 6, CYAN), (12, 4, PINK)):
            c.blob(x, y, 2.2, 2.2, list(ramp[1:]))
        c.outline(1)
        return c.p, "cristal"
    if name == "deco_h":  # a split geode: a rock shell full of pink crystals
        c.blob(8, 10, 7.5, 6, [0xf, 0xf, 0xf])
        for y in range(16):
            for x in range(16):
                if ((x + 0.5 - 8) / 5.2) ** 2 + ((y + 0.5 - 10.5) / 4.2) ** 2 < 1:
                    c.set(x, y, 1)
        for x0, a, ln in ((5, -60, 4), (6, -95, 6), (8, -82, 7), (10, -105, 5), (11, -120, 4)):
            shard(c, x0, 14, a, ln, 1.2, PINK)
        for x in range(3, 13):  # the rim lit on top
            if c.get(x, 4) == 0xf or c.get(x, 5) == 0xf:
                c.set(x, 4 if c.get(x, 4) == 0xf else 5, 6)
        c.outline(1)
        return c.p, "cristal"
    raise KeyError(name)


def front(name: str) -> tuple[list[list[int]], str]:
    c = Canvas(16, 16)
    if name == "front_a":  # stalactites
        for x, ln, w in ((3, 9, 2.4), (8, 14, 3.4), (13, 7, 2.2)):
            stalactite(c, x, ln, w)
        c.outline(1)
        return c.p, "roca"
    if name == "front_b":  # crystals hanging from the ceiling
        for x0, ln, a, ramp in ((4, 10, 95, PINK), (9, 14, 85, CYAN), (13, 7, 70, PINK)):
            shard(c, x0, -1, a, ln, 1.8, ramp)
        c.outline(1)
        return c.p, "cristal"
    if name == "front_c":  # a hanging chain with a hook
        for y in range(13):
            if y % 3 == 0:
                c.set(7, y, 9)
                c.set(8, y, 8)
            else:
                c.set(6, y, 9)
                c.set(9, y, 7)
        c.line(8, 13, 8, 14, 9)
        c.line(8, 14, 10, 14, 8)
        c.set(10, 13, 9)
        c.set(6, 13, 9)
        c.set(7, 14, 9)
        c.outline(1)
        return c.p, "mina"
    if name == "front_d":  # rocks in the foreground
        c.blob(4, 15, 6, 5, [2, 3, 4, 5])
        c.blob(12, 16, 5, 4, [2, 3, 4, 5])
        stalactite(c, 9, 8, 2, up=True)
        c.outline(1)
        return c.p, "roca"
    if name == "front_e":  # glowing hanging roots
        for x0, ln in ((2, 13), (6, 8), (10, 15), (13, 10)):
            x = x0
            for y in range(ln):
                if y % 5 == 4:
                    x += 1 if x0 % 2 else -1
                c.set(x, y, 0xa)
            c.set(x, ln, 0xc)
            c.set(x, ln + 1, 0xd)
        c.outline(1)
        return c.p, "cristal"
    if name == "front_f":  # crystals in the foreground
        for x0, ln, a, ramp in ((3, 9, -110, CYAN), (7, 13, -92, PINK), (12, 8, -70, CYAN)):
            shard(c, x0, 16, a, ln, 2.0, ramp)
        c.outline(1)
        return c.p, "cristal"
    if name == "front_g":  # a rope with a pulley
        for y in range(9):
            c.set(7, y, 5 if y % 2 else 4)
            c.set(8, y, 3)
        c.blob(8, 11, 3.2, 3.2, [7, 8, 9, 0xa])
        c.set(8, 11, 1)
        c.set(7, 11, 7)
        c.line(11, 11, 11, 16, 4)
        c.line(12, 11, 12, 16, 3)
        c.outline(1)
        return c.p, "mina"
    if name == "front_h":  # a dark rock overhang
        for x in range(16):
            ln = 5 + round(3 * math.sin(x / 2.6)) + (x % 3 == 0)
            for y in range(ln):
                c.set(x, y, 2 if y < ln - 2 else (3 if x % 2 else 2))
            c.set(x, ln - 1, 4 if x % 4 == 1 else 3)
        c.outline(1)
        return c.p, "roca"
    raise KeyError(name)


def back(name: str) -> tuple[list[list[int]], str]:
    """Back walls: darker than the ground so the hero and the floor read clearly."""
    c = Canvas(16, 16)
    if name == "back_c":  # mine timber wall, dark boards
        for y in range(16):
            for x in range(16):
                r = y % 5
                v = 1 if r == 4 else (3 if r == 0 else 2)
                if x in (4, 12) and r != 4:
                    v = 1 if (y // 5) % 2 == (x == 4) else v
                if v == 2 and (x * 7 + y * 3) % 13 == 0:
                    v = 3
                c.set(x, y, v)
        for x, y in ((2, 1), (10, 6), (6, 11), (14, 11)):
            c.set(x, y, 7)
        return c.p, "mina"
    for y in range(16):
        for x in range(16):
            v = rock(x, y, 4)
            v = {6: 3, 5: 3, 4: 2, 3: 2, 2: 1}.get(v, v)
            c.set(x, y, v)
    if name == "back_b":  # embedded crystals glowing in the wall
        for y in range(16):
            for x in range(16):
                if c.get(x, y) == 3 and x > 8:
                    c.set(x, y, 8)
        for x, y, v in ((4, 5, 0xd), (5, 4, 0xe), (5, 5, 0xd), (4, 6, 1), (11, 10, 0xf), (12, 9, 0xf), (12, 10, 3), (11, 11, 1)):
            c.set(x, y, v)
    elif name == "back_d":  # a glowing cyan vein
        pts = [(0, 4), (4, 6), (7, 5), (10, 9), (13, 9), (16, 12)]
        for (ax, ay), (bx, by) in zip(pts, pts[1:]):
            c.line(ax, ay, bx, by, 0xd)
            c.line(ax, ay - 1, bx, by - 1, 8)
        c.set(7, 5, 0xe)
    return c.p, "roca"


# ------------------------------------------------------------------ scenery

def cristal_far() -> list[list[int]]:
    """The far cavern: a vault glowing violet in the middle, huge distant crystal spires and arches."""
    W, H = 256, 160
    c = Canvas(W, H, wrap=True)
    vault = [1, 2, 3, 4, 5]
    for y in range(H):
        t = 1 - abs(y - 92) / 92
        for x in range(W):
            c.p[y][x] = ramp_at(vault, t ** 1.4 * 0.95, x, y)
    for gx, gy, r, col in ((60, 96, 42, 0xb), (190, 84, 50, 0xd)):  # big soft glows
        for y in range(H):
            for x in range(gx - r * 2, gx + r * 2):
                d = math.hypot(min(abs(x - gx), W - abs(x - gx)) / 1.6, y - gy) / r
                if d < 1 and dith(x, y, (1 - d) * 0.5):
                    c.set(x, y, col if d > 0.4 else (6 if col == 0xb else 0xe))
    for x0, base, ln, sc in ((22, 138, 64, 1.0), (104, 136, 84, 1.3), (176, 138, 56, 0.9), (226, 138, 90, 1.4)):
        for k, (dx, a, f) in enumerate(((0, -92, 1.0), (-7 * sc, -112, 0.6), (8 * sc, -70, 0.7), (-3 * sc, -100, 0.4))):
            shard(c, x0 + dx, base, a, ln * f, 5.5 * sc * (0.7 if k else 1), (0xa, 8, 9, 9), glint=0xc)
    for x in range(W):  # the cavern ceiling and floor silhouettes
        top = 18 + round(8 * math.sin(2 * math.pi * x / 128) + 5 * math.sin(2 * math.pi * x / 32 + 1))
        for y in range(top):
            c.p[y][x] = 1 if y < top - 2 else 2
        if x % 16 in (3, 4, 5, 11, 12):  # distant stalactites
            ln = 6 + (x * 7) % 11
            for y in range(top, top + ln - abs(x % 16 - 4) * 2 if x % 16 < 8 else top + ln // 2):
                c.p[y][x] = 2
        bot = 134 + round(4 * math.sin(2 * math.pi * x / 64 + 2) + 3 * math.sin(2 * math.pi * x / 16))
        for y in range(bot, H):
            c.p[y][x] = 2 if y < bot + 3 else 1
    for i in range(70):  # sparkles
        x, y = int(hsh(i, 0, 17) * W), 30 + int(hsh(i, 1, 17) * 95)
        c.set(x, y, 0xf if i % 3 else 0xc)
    return c.p


def cristal_mid() -> list[list[int]]:
    """Rock pillars and curtains of stalactites with glowing crystal clusters; open between them."""
    W, H = 256, 128
    c = Canvas(W, H, wrap=True)
    rockr = [1, 2, 3, 4, 5]
    for x in range(W):  # ceiling curtain
        top = 14 + round(6 * math.sin(2 * math.pi * x / 64) + 4 * math.sin(2 * math.pi * x / (W / 12)))
        for y in range(top):
            c.set(x, y, 2 if y > top - 3 else 1)
        c.set(x, top - 1, 3 if (x // 3) % 2 else 2)
    for i, x0 in enumerate(range(6, W, 19)):  # stalactites
        ln = 14 + int(hsh(i, 0, 23) * 26)
        w = 3 + hsh(i, 1, 23) * 4
        for y in range(ln):
            half = w * (1 - y / ln) ** 0.8
            for x in range(int(x0 - half), int(x0 + half) + 1):
                fx = (x + 0.5 - x0) / max(half, 0.5)
                c.set(x, y + 10, 4 if fx < -0.4 else (3 if fx < 0.3 else 2))
    for x0, w in ((40, 26), (148, 34), (224, 20)):  # pillars, widening at both ends
        for y in range(H):
            f = abs(y - 64) / 64
            half = w / 2 * (0.55 + 0.6 * f ** 2.5)
            for x in range(int(x0 - half), int(x0 + half) + 1):
                fx = (x + 0.5 - x0) / half
                t = 0.5 - 0.45 * fx + (hsh(x // 3, y // 4, 29) - 0.5) * 0.3
                c.set(x, y, ramp_at(rockr, t, x, y))
    for x in range(W):  # floor of rubble
        bot = 104 + round(5 * math.sin(2 * math.pi * x / 64 + 1) + 3 * math.sin(2 * math.pi * x / (W / 11)))
        for y in range(bot, H):
            c.set(x, y, 3 if y < bot + 2 else 2 if y < bot + 8 else 1)
    for x0, y0, ramp, n in ((52, 100, (7, 8, 9), 4), (140, 101, (0xa, 0xb, 0xc), 5), (232, 99, (7, 8, 9), 3),
                            (92, 106, (0xd, 0xe, 0xf), 3), (196, 104, (0xa, 0xb, 0xc), 4), (36, 48, (0xa, 0xb, 0xc), 3)):
        for k in range(n):
            a = -90 + (k - n / 2) * 22
            ln = 12 + (k * 7) % 10
            dark, mid, light = ramp
            shard(c, x0 + (k - n / 2) * 4, y0, a, ln, 2.6, (dark, mid, light, light), glint=0xf if ramp[0] != 0xd else 0xc)
    for i in range(30):  # glints
        x, y = int(hsh(i, 0, 37) * W), 30 + int(hsh(i, 1, 37) * 70)
        if not c.get(x, y):
            c.set(x, y, 0xc if i % 2 else 9)
    return c.p


def cristal_near() -> list[list[int]]:
    """A dark rock band with crystal shards, just behind the level."""
    W, H = 256, 96
    c = Canvas(W, H, wrap=True)
    for x in range(W):
        top = 60 + round(10 * math.sin(2 * math.pi * x / 128 + 0.5) + 6 * math.sin(2 * math.pi * x / 32) + 3 * math.sin(2 * math.pi * x / (W / 23)))
        for y in range(top, H):
            c.set(x, y, 4 if y == top else (3 if y < top + 3 else (2 if y < top + 14 else 1)))
    for i, x0 in enumerate(range(10, W, 23)):
        top = 60 + round(10 * math.sin(2 * math.pi * x0 / 128 + 0.5) + 6 * math.sin(2 * math.pi * x0 / 32) + 3 * math.sin(2 * math.pi * x0 / (W / 23)))
        ramp = (5, 6, 7, 7) if i % 2 else (8, 9, 9, 7)
        for k in range(2 + i % 2):
            shard(c, x0 + k * 4, top + 4, -100 + k * 25, 14 + (i * 5 + k * 7) % 14, 2.4, ramp, glint=7)
    for x in range(W):  # stalagmites rising
        if x % 37 == 5:
            for y in range(30):
                half = 3.5 * y / 30
                for xx in range(int(x - half), int(x + half) + 1):
                    c.set(xx, 40 + y, 3 if xx >= x else 4)
    c.outline(1)
    return c.p


def cristal_agua() -> list[list[int]]:
    """Cave haze: drifting fog bands, light falling from cracks and glow motes (the engine blends it)."""
    W, H = 256, 160
    c = Canvas(W, H, wrap=True)
    for x0, wd in ((30, 26), (140, 34), (210, 18)):
        for y in range(H):
            sx = x0 - y * 0.22 + 4 * math.sin(y / 23)
            for x in range(int(sx), int(sx + wd)):
                e = min(x - sx, sx + wd - x) / (wd / 2)
                if dith(x, y, max(0.0, min(1, e * 1.2)) ** 1.5 * (0.5 - y / H * 0.4)):
                    c.set(x, y, 6 if e > 0.55 else 1)
    for band_y, amp, col in ((70, 6, 2), (118, 8, 1), (146, 5, 4)):
        for x in range(W):
            yc = band_y + amp * math.sin(2 * math.pi * x / 128) + 3 * math.sin(2 * math.pi * x / (W / 7))
            for y in range(int(yc - 9), int(yc + 9)):
                f = 1 - abs(y - yc) / 9
                if dith(x, y, f * 0.6):
                    c.set(x, y, col)
    for i in range(60):
        x, y = int(hsh(i, 0, 47) * W), int(hsh(i, 1, 47) * H)
        col = 3 if i % 3 == 0 else (4 if i % 3 == 1 else 5)
        c.set(x, y, col)
        if i % 4 == 0:
            for ddx, ddy in ((1, 0), (-1, 0), (0, 1), (0, -1)):
                c.set(x + ddx, y + ddy, 1)
    return c.p


# ------------------------------------------------------------------ registration

def register() -> None:
    register_ground()
    for k in ("l", "m", "r", "s"):
        ART.meta(SET, f"plat_{k}", mine_platform(k), "mina", flags=("oneway",))
    ART.meta(SET, "block_brown", rubble_block(), "mina", flags=("solid", "break"))
    ART.meta(SET, "block_blue", iron_block("blue"), "mina", flags=("solid", "break_strong"))
    ART.meta(SET, "block_hard", iron_block("hard"), "mina", flags=("solid", "break_super"))
    ART.meta(SET, "box_jewel", mine_crate("gem"), "mina", flags=("solid", "break", "jewel"))
    ART.meta(SET, "box_coin", mine_crate("coin"), "mina", flags=("solid", "break", "coin"))
    ART.meta(SET, "spikes_up", crystal_spikes(), "cristal", flags=("hurt",))
    ART.meta(SET, "spikes_down", flip_v(crystal_spikes()), "cristal", flags=("hurt",))
    for n in "abcdefgh":
        p, bank = deco(f"deco_{n}")
        ART.meta(SET, f"deco_{n}", p, bank)
    for n in "abcdefgh":
        p, bank = front(f"front_{n}")
        ART.meta(SET, f"front_{n}", blank(16, 16), bank, front=p, front_bank=bank)
    for n in "abcd":
        p, bank = back(f"back_{n}")
        ART.meta(SET, f"back_{n}", p, bank)
    for k in "abc":
        ART.meta(SET, f"crystal_{k}", cluster(k), "cristal")
    ART.meta(SET, "crystal_block", crystal_block(), "cristal", flags=("solid", "break_super"))
    ART.meta(SET, "lamp_off", lamp(False), "mina")
    ART.meta(SET, "lamp_on", lamp(True), "mina")
    ART.meta(SET, "glow_a", glow("a"), "cristal")
    ART.meta(SET, "glow_b", glow("b"), "cristal")
    for f in range(4):
        ART.meta(SET, f"drip_{f}", drip(f), "roca")
    for k in "lmr":
        ART.meta(SET, f"ice_plat_{k}", ice_platform(k), "cristal", flags=("oneway",))
    ART.scenery("cristal_far", cristal_far(), SET, "abismo")
    ART.scenery("cristal_mid", cristal_mid(), SET, "caverna")
    ART.scenery("cristal_near", cristal_near(), SET, "penumbra")
    ART.scenery("cristal_agua", cristal_agua(), SET, "niebla")


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
    SCENE = [
        "..a......b......h...",
        "......o.....LMR.....",
        "..........k.........",
        "...SPB..........##..",
        ".............x..##..",
        "..y..q..r...#####..u",
        "#####.###.#######.##",
        "#####.###^^######.##",
        "######################"[:20],
        "####################",
    ]
    LEGEND = {"a": "front_a", "b": "front_b", "h": "front_c", "o": "lamp_on", "k": "lamp_off", "L": "ice_plat_l",
              "M": "ice_plat_m", "R": "ice_plat_r", "S": "plat_l", "P": "plat_m", "B": "plat_r", "x": "crystal_block",
              "y": "crystal_a", "q": "box_jewel", "r": "crystal_b", "u": "deco_d", "^": "spikes_up"}
    print(preview_metas(SET, cols=10, scale=3))
    for n in ("cristal_far", "cristal_mid", "cristal_near", "cristal_agua"):
        print(preview_scenery(n, 2))
    out = compose(SET, SCENE, LEGEND, [("cristal_far", 0.2), ("cristal_mid", 0.5), ("cristal_near", 0.8)], "scene_cristal.png")
    blend_layer(out, SET, "cristal_agua", 0.3)
    print(out)
