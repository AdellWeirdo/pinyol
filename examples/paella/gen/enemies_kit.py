"""Paella de Combate: the painter shared by the enemy / ally / fx sheets (gen/art_enemies*.py).

A small shaded-shape renderer: ellipses, tubes (capsule chains) and polygons get a surface normal, are lit from the
upper left and quantised to a 4-tone material ramp (shadow, mid, light, highlight) with a rim light on the lower-right
edge; a part laid over another gets a one-pixel seam in its material's dark outline colour, and the finished frame gets
an outer outline (per material, never black). Everything is opaque: no alpha blends, no dithering.
"""
from __future__ import annotations

import json
import math
from pathlib import Path

import numpy as np
from PIL import Image, ImageDraw

ROOT = Path(__file__).resolve().parent.parent
ART = ROOT / "art"
LIGHT = np.array([-0.6, -0.8])
RIM = np.array([0.72, 0.62])


def hx(s: str) -> tuple[int, int, int]:
    s = s.lstrip("#")
    return int(s[0:2], 16), int(s[2:4], 16), int(s[4:6], 16)


class Ramp:
    """Four tones dark..light plus the outline colour of the material."""

    def __init__(self, *cols: str, ol: str):
        self.c = [hx(c) for c in cols]
        self.ol = hx(ol)

    def __getitem__(self, i):
        return self.c[max(0, min(len(self.c) - 1, i))]


# ------------------------------------------------------------------ shared palette (one ramp per material)
OL_PLUM = "#2a1430"     # metal outline
OL_BROWN = "#3a1a0e"    # warm / organic outline
OL_RED = "#4a0c14"

CHROME = Ramp("#7c86a0", "#b4bed0", "#e2e8f0", "#ffffff", ol=OL_PLUM)      # gull body: white-grey chrome
STEEL = Ramp("#3e4058", "#666c88", "#979db8", "#cfd3e2", ol=OL_PLUM)       # joints, wings, gun metal
VISOR = Ramp("#7c0c1c", "#c8202c", "#ff5c40", "#ffd0a0", ol=OL_RED)        # red visor, rocket fins
BRASS = Ramp("#7c4010", "#c8801c", "#f4c038", "#fff4a0", ol=OL_BROWN)      # cannon beaks, keys, rivet heads
OLIVE = Ramp("#38421c", "#5e7028", "#90a240", "#ccd884", ol=OL_BROWN)      # tin helmets, crates of ammo
WOOD = Ramp("#5a2c12", "#925018", "#c8823a", "#f0bc70", ol=OL_BROWN)       # stocks, barrels, crates
FLESH = Ramp("#8c4430", "#d07a54", "#f2aa7c", "#ffdcb4", ol=OL_BROWN)
ORANGE = Ramp("#9a3008", "#e05a10", "#ff9a28", "#ffe070", ol=OL_BROWN)     # gull feet, flames
FIRE = Ramp("#c02808", "#ff7010", "#ffc830", "#fff8c0", ol="#5a1408")    # explosions
SMOKE = Ramp("#4a3c48", "#76687a", "#a89aa8", "#d8ccd0", ol="#24181e")
SEA = Ramp("#0c4a5a", "#18808a", "#3cb8b0", "#a0ecd8", ol="#0a2430")
CREAM = Ramp("#b89878", "#e8d4b8", "#fff4e0", "#ffffff", ol=OL_BROWN)     # foam, cream, eye whites
PINK = Ramp("#8c2c50", "#d85a80", "#ff96b0", "#ffd4e0", ol="#401028")
NAVY = Ramp("#1c2048", "#323a7c", "#5262b0", "#8ca0e0", ol="#100c28")
GREEN = Ramp("#1c4a1c", "#2e7a28", "#5cb03c", "#b4e47c", ol="#102410")
YELLOW = Ramp("#a06808", "#e8b010", "#ffe040", "#fffcb0", ol=OL_BROWN)


def rot(x, y, ox, oy, a):
    """Point (x, y) rotated by a radians about (ox, oy)."""
    c, s = math.cos(a), math.sin(a)
    dx, dy = x - ox, y - oy
    return ox + dx * c - dy * s, oy + dx * s + dy * c


class Canvas:
    def __init__(self, w: int, h: int):
        self.w, self.h = w, h
        self.rgb = np.zeros((h, w, 3), np.uint8)
        self.a = np.zeros((h, w), bool)
        self.ol = np.zeros((h, w, 3), np.uint8)
        yy, xx = np.mgrid[0:h, 0:w]
        self.X = xx + 0.5
        self.Y = yy + 0.5

    # ---------------------------------------------------------- shape builders: (mask, nx, ny)
    def _ell(self, cx, cy, rx, ry, ang=0.0):
        dx, dy = self.X - cx, self.Y - cy
        c, s = math.cos(-ang), math.sin(-ang)
        lx, ly = dx * c - dy * s, dx * s + dy * c
        u, v = lx / max(rx, 0.3), ly / max(ry, 0.3)
        m = u * u + v * v <= 1.0
        c2, s2 = math.cos(ang), math.sin(ang)
        return m, u * c2 - v * s2, u * s2 + v * c2

    def _tube(self, pts):
        best = np.full((self.h, self.w), 9.0)
        nx = np.zeros((self.h, self.w))
        ny = np.zeros((self.h, self.w))
        if len(pts) == 1:
            pts = [pts[0], pts[0]]
        for (ax, ay, ar), (bx, by, br) in zip(pts, pts[1:]):
            vx, vy = bx - ax, by - ay
            ll = vx * vx + vy * vy or 1e-9
            t = np.clip(((self.X - ax) * vx + (self.Y - ay) * vy) / ll, 0, 1)
            qx, qy, r = ax + vx * t, ay + vy * t, np.maximum(ar + (br - ar) * t, 0.3)
            d = np.hypot(self.X - qx, self.Y - qy) / r
            take = d < best
            best = np.where(take, d, best)
            nx = np.where(take, (self.X - qx) / r, nx)
            ny = np.where(take, (self.Y - qy) / r, ny)
        return best <= 1.0, nx, ny

    def _polymask(self, pts):
        n = len(pts)
        inside = np.zeros((self.h, self.w), bool)
        X, Y = self.X, self.Y
        j = n - 1
        for i in range(n):
            xi, yi = pts[i]
            xj, yj = pts[j]
            cond = ((yi > Y) != (yj > Y))
            with np.errstate(divide="ignore", invalid="ignore"):
                xint = (xj - xi) * (Y - yi) / ((yj - yi) if yj != yi else 1e-9) + xi
            inside ^= cond & (X < xint)
            j = i
        return inside

    # ---------------------------------------------------------- painting
    def _paint(self, m, nx, ny, ramp, seam=True, rim=True, bias=0.0, spec=True, flat=None, tone=None):
        if not m.any():
            return
        if isinstance(ramp, tuple):
            ramp = _solid(ramp)
        if flat is not None or tone is not None:
            col = np.array(ramp[tone if tone is not None else flat], np.uint8)
            img = np.broadcast_to(col, self.rgb.shape)
        else:
            r2 = np.minimum(nx * nx + ny * ny, 1.0)
            z = np.sqrt(1.0 - r2)
            lam = nx * LIGHT[0] + ny * LIGHT[1] + z * 0.55 + bias
            idx = np.where(lam < 0.02, 0, np.where(lam < 0.66, 1, np.where(lam < 1.0, 2, 3 if spec else 2)))
            if rim:
                rimv = nx * RIM[0] + ny * RIM[1]
                idx = np.where((rimv > 0.86) & (r2 > 0.7) & (idx == 0), 1, idx)
            pal = np.array([ramp[i] for i in range(4)], np.uint8)
            img = pal[idx]
        if seam:
            pad = np.pad(m, 1)
            border = m & ~(pad[:-2, 1:-1] & pad[2:, 1:-1] & pad[1:-1, :-2] & pad[1:-1, 2:])
            # the border pixel is a seam if just outside it there is paint that is not this shape
            pa = np.pad(self.a & ~m, 1)
            outside_paint = pa[:-2, 1:-1] | pa[2:, 1:-1] | pa[1:-1, :-2] | pa[1:-1, 2:]
            seamm = border & outside_paint
        self.rgb[m] = img[m]
        self.ol[m] = ramp.ol
        self.a |= m
        if seam:
            self.rgb[seamm] = ramp.ol

    def ell(self, cx, cy, rx, ry, ramp, ang=0.0, **kw):
        m, nx, ny = self._ell(cx, cy, rx, ry, ang)
        self._paint(m, nx, ny, ramp, **kw)

    def tube(self, pts, ramp, **kw):
        m, nx, ny = self._tube(pts)
        self._paint(m, nx, ny, ramp, **kw)

    def poly(self, pts, ramp, bulge=0.7, normal=None, center=None, **kw):
        m = self._polymask(pts)
        if normal is not None:
            nx = np.full(m.shape, float(normal[0]))
            ny = np.full(m.shape, float(normal[1]))
        else:
            if center is None:
                center = (sum(p[0] for p in pts) / len(pts), sum(p[1] for p in pts) / len(pts))
            rr = max(math.hypot(p[0] - center[0], p[1] - center[1]) for p in pts) or 1
            nx = (self.X - center[0]) / rr * bulge
            ny = (self.Y - center[1]) / rr * bulge
        self._paint(m, nx, ny, ramp, **kw)

    def fill_poly(self, pts, col, ol=None):
        m = self._polymask(pts)
        self._flat(m, col, ol)

    def _flat(self, m, col, ol=None):
        self.rgb[m] = col
        self.ol[m] = ol if ol is not None else _darken(col)
        self.a |= m

    def disc(self, cx, cy, r, col, ol=None):
        m = (self.X - cx) ** 2 + (self.Y - cy) ** 2 <= r * r
        self._flat(m, col, ol)

    def oval(self, cx, cy, rx, ry, col, ang=0.0, ol=None):
        m, _, _ = self._ell(cx, cy, rx, ry, ang)
        self._flat(m, col, ol)

    def cut_ell(self, cx, cy, rx, ry, ang=0.0):
        m, _, _ = self._ell(cx, cy, rx, ry, ang)
        self.a &= ~m

    def cut_poly(self, pts):
        self.a &= ~self._polymask(pts)

    def px(self, x, y, col, ol=None):
        x, y = int(math.floor(x)), int(math.floor(y))
        if 0 <= x < self.w and 0 <= y < self.h:
            self.rgb[y, x] = col
            self.ol[y, x] = ol if ol is not None else _darken(col)
            self.a[y, x] = True

    def line(self, x0, y0, x1, y1, col, width=1, ol=None):
        n = int(max(abs(x1 - x0), abs(y1 - y0)) * 1.5) + 1
        for i in range(n + 1):
            t = i / n
            x, y = x0 + (x1 - x0) * t, y0 + (y1 - y0) * t
            if width <= 1:
                self.px(x, y, col, ol)
            else:
                self.disc(x, y, width / 2, col, ol)

    def stamp(self, rows, x, y, cmap):
        """Hand pixels: rows of characters, cmap maps a character to an rgb (missing / '.' leaves what is there)."""
        if isinstance(rows, str):
            rows = rows.strip("\n").split("\n")
        for j, r in enumerate(rows):
            for i, ch in enumerate(r):
                if ch in cmap:
                    self.px(x + i, y + j, cmap[ch])

    def rivet(self, x, y, ramp=STEEL):
        self.px(x, y, ramp[0])
        self.px(x - 1, y - 1, ramp[3])

    # ---------------------------------------------------------- finishing
    def done(self, outline=True):
        a = self.a.copy()
        rgb = self.rgb.copy()
        if outline:
            pa = np.pad(a, 1)
            po = np.pad(self.ol, ((1, 1), (1, 1), (0, 0)))
            out = np.zeros_like(a)
            col = np.zeros_like(rgb)
            for dy, dx in ((0, 1), (2, 1), (1, 0), (1, 2)):
                nb = pa[dy:dy + self.h, dx:dx + self.w]
                take = nb & ~a & ~out
                col[take] = po[dy:dy + self.h, dx:dx + self.w][take]
                out |= take
            rgb[out] = col[out]
            a |= out
        img = np.zeros((self.h, self.w, 4), np.uint8)
        img[..., :3] = rgb
        img[..., 3] = np.where(a, 255, 0)
        img[~a, :3] = 0
        return img


def _darken(col):
    return tuple(int(c * 0.3) for c in col)


_SOLID_CACHE: dict = {}


def _solid(col):
    if col not in _SOLID_CACHE:
        r = Ramp("#000000", "#000000", "#000000", "#000000", ol="#000000")
        r.c = [col] * 4
        r.ol = _darken(col)
        _SOLID_CACHE[col] = r
    return _SOLID_CACHE[col]


# ------------------------------------------------------------------ frame helpers
def overlay(base, top, dx=0, dy=0):
    """Paste RGBA `top` over `base` (opaque pixels win), offset by (dx, dy)."""
    out = base.copy()
    h, w = base.shape[:2]
    th, tw = top.shape[:2]
    for y in range(th):
        yy = y + dy
        if not 0 <= yy < h:
            continue
        row = top[y]
        msk = row[:, 3] > 0
        xs = np.nonzero(msk)[0]
        for x in xs:
            xx = x + dx
            if 0 <= xx < w:
                out[yy, xx] = row[x]
    return out


def shift(img, dx, dy):
    out = np.zeros_like(img)
    return overlay(out, img, dx, dy)


def flip_h(img):
    return img[:, ::-1].copy()


# ------------------------------------------------------------------ sheets
class Sheet:
    def __init__(self, name, w, h, anchor, faces=None, **extra):
        self.name, self.w, self.h, self.anchor = name, w, h, anchor
        self.faces = faces
        self.extra = extra
        self.frames: list[tuple[str, np.ndarray]] = []

    def add(self, name, img):
        assert img.shape == (self.h, self.w, 4), (self.name, name, img.shape)
        self.frames.append((name, img))

    def save(self, max_colors=64, preview_cols=None):
        ART.mkdir(parents=True, exist_ok=True)
        n = len(self.frames)
        strip = np.zeros((self.h, self.w * n, 4), np.uint8)
        for i, (_, f) in enumerate(self.frames):
            strip[:, i * self.w:(i + 1) * self.w] = f
        cols = {tuple(c) for c in strip[strip[..., 3] > 0][:, :3]}
        warn = []
        if len(cols) > max_colors:
            warn.append(f"{len(cols)} colours > {max_colors}")
        for name, f in self.frames:
            al = f[..., 3] > 0
            if al[0].any() or al[-1].any() or al[:, 0].any() or al[:, -1].any():
                ys, xs = np.nonzero(al)
                warn.append(f"{name} edge x{xs.min()}-{xs.max()} y{ys.min()}-{ys.max()}")
        Image.fromarray(strip, "RGBA").save(ART / f"{self.name}.png")
        meta = {"w": self.w, "h": self.h, "anchor": list(self.anchor), "frames": [n for n, _ in self.frames]}
        if self.faces:
            meta["faces"] = self.faces
        meta.update(self.extra)
        (ART / f"{self.name}.json").write_text(json.dumps(meta, indent=1) + "\n")
        self.preview(preview_cols)
        print(f"{self.name}: {n} frames {self.w}x{self.h}, {len(cols)} colours" + ("  WARN " + "; ".join(warn) if warn else ""))
        return warn

    def preview(self, cols=None):
        n = len(self.frames)
        cols = cols or max(1, min(n, 1600 // (self.w * 2 + 4)))
        rows = (n + cols - 1) // cols
        cw, ch = self.w * 2 + 4, self.h * 2 + 14
        bgs = [(128, 128, 128), (140, 206, 240)]
        img = Image.new("RGB", (cols * cw * 2 + 12, rows * ch + 4), (40, 36, 44))
        d = ImageDraw.Draw(img)
        for b, bg in enumerate(bgs):
            ox = b * (cols * cw + 12)
            for i, (name, f) in enumerate(self.frames):
                x, y = ox + (i % cols) * cw, (i // cols) * ch + 2
                tile = Image.new("RGB", (self.w * 2, self.h * 2), bg)
                fi = Image.fromarray(f, "RGBA").resize((self.w * 2, self.h * 2), Image.NEAREST)
                tile.paste(fi, (0, 0), fi)
                # anchor mark
                ax, ay = self.anchor
                td = ImageDraw.Draw(tile)
                td.line([(ax * 2 - 3, ay * 2 + 1), (ax * 2 + 3, ay * 2 + 1)], fill=(255, 0, 255))
                img.paste(tile, (x, y + 12))
                d.text((x + 1, y), name, fill=(230, 230, 230))
        img.save(ART / f"preview_{self.name}.png")


def grid_sheet(img_list, cols, scale=1, bg=(128, 128, 128)):
    """A quick look image (not a product)."""
    h, w = img_list[0].shape[:2]
    rows = (len(img_list) + cols - 1) // cols
    out = Image.new("RGB", (cols * w, rows * h), bg)
    for i, f in enumerate(img_list):
        fi = Image.fromarray(f, "RGBA")
        out.paste(fi, ((i % cols) * w, (i // cols) * h), fi)
    if scale != 1:
        out = out.resize((out.width * scale, out.height * scale), Image.NEAREST)
    return out
