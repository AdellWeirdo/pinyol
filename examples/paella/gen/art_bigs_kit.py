"""Paella de Combate, the big pieces (tractor and boss): a small cel-shaded shape renderer.

Every shape is rasterised with hard edges, lit from the upper left by its surface normal, quantised to the
ramp of its material (outline, shadow, mid, light, highlight) and given a one-pixel inner outline in the
material's own dark tone (never black). Shapes painted later cover earlier ones and get a seam where they
meet. Parts are rigged with Xf transforms (translate, rotate, scale) so animation is done by tables.
"""
from __future__ import annotations

import json
import math
from pathlib import Path

import numpy as np
from PIL import Image, ImageDraw
from scipy import ndimage

ROOT = Path(__file__).resolve().parent.parent
ART = ROOT / "art"

# ------------------------------------------------------------------ palette (shared names, each sheet uses a subset)

PAL: dict[str, str] = {}


def ramp(name: str, cols: list[str]) -> tuple[str, ...]:
    keys = []
    for i, c in enumerate(cols):
        k = f"{name}{i}"
        PAL[k] = c
        keys.append(k)
    return tuple(keys)


def col(name: str, c: str) -> str:
    PAL[name] = c
    return name


# ramps: [outline, shadow, mid, light, highlight]
RED = ramp("red", ["#3a0c14", "#8a1c1c", "#c8301f", "#ee5a32", "#ffa070"])
CREAM = ramp("cream", ["#4a2418", "#b08454", "#dcbc8a", "#f6e4b8", "#fffaea"])
STEEL = ramp("steel", ["#1e2034", "#4a5270", "#7c8aa4", "#b6c2d4", "#eef4fc"])
RUBBER = ramp("rub", ["#1a1018", "#30242a", "#4a3c40", "#6e5e5e"])
WOOD = ramp("wood", ["#3a1c0c", "#80461e", "#b67a36", "#dcac62", "#f4d494"])
BRASS = ramp("brass", ["#3c2006", "#9a5e0c", "#d89a20", "#f8d050", "#fff6b0"])
TINB = ramp("tinb", ["#101c48", "#1c3c8c", "#2e66c4", "#62a2ec"])
FIRE = ramp("fire", ["#5a1408", "#d23a10", "#ff8a14", "#ffd040", "#fffac8"])
SMOKE = ramp("smoke", ["#2a2028", "#584c56", "#8a7e88", "#bcb4ba", "#ece6e8"])
IRON = ramp("iron", ["#141420", "#2a2a3a", "#40404e", "#5c5c6c"])
CHROME = ramp("chrome", ["#22203a", "#5a6084", "#9aa4c0", "#d4dcec", "#ffffff"])
RUST = ramp("rust", ["#2e1008", "#6e2e12", "#a8521e", "#d8823a"])
VISOR = ramp("visor", ["#3a0410", "#9a0c1c", "#e8202c", "#ff7060", "#ffd0b8"])
BEAK = ramp("beak", ["#4a1c04", "#b0560c", "#ec8e14", "#ffc23a", "#fff09a"])
NAVY = ramp("navy", ["#0e1028", "#1e2450", "#30407e", "#5068b0"])
RICE = ramp("rice", ["#5a2c00", "#d07a00", "#ffb000", "#ffe040", "#fffcc0"])
GREEN = ramp("green", ["#0c2a10", "#1e6a22", "#3ca434", "#8cdc5a"])
FEATH = ramp("feath", ["#2a2236", "#8a8aa0", "#c8c8d6", "#f2f2f8", "#ffffff"])

WHITE = col("white", "#ffffff")
BLACKISH = col("ink", "#1a0c10")
SEA = col("sky", "#7cc8f0")

LIGHT = np.array([-0.55, -0.72, 0.6])
LIGHT = LIGHT / np.linalg.norm(LIGHT)


def hex_rgb(h: str) -> tuple[int, int, int]:
    h = h.lstrip("#")
    return int(h[0:2], 16), int(h[2:4], 16), int(h[4:6], 16)


# ------------------------------------------------------------------ transforms

class Xf:
    """world = t + R(rot) * diag(sx, sy) * local."""

    def __init__(self, tx=0.0, ty=0.0, rot=0.0, sx=1.0, sy=1.0):
        self.tx, self.ty, self.rot, self.sx, self.sy = tx, ty, rot, sx, sy
        self.c, self.s = math.cos(rot), math.sin(rot)

    def pt(self, x, y):
        x, y = x * self.sx, y * self.sy
        return self.tx + self.c * x - self.s * y, self.ty + self.s * x + self.c * y

    def pts(self, ps):
        return [self.pt(x, y) for x, y in ps]

    def inv(self, X, Y):
        dx, dy = X - self.tx, Y - self.ty
        lx = (self.c * dx + self.s * dy) / self.sx
        ly = (-self.s * dx + self.c * dy) / self.sy
        return lx, ly

    def vec(self, nx, ny):
        """Rotate a normal field (scale sign flips mirror it)."""
        nx = nx * (1 if self.sx >= 0 else -1)
        ny = ny * (1 if self.sy >= 0 else -1)
        return self.c * nx - self.s * ny, self.s * nx + self.c * ny

    def then(self, other: "Xf") -> "Xf":
        """Compose: apply self (local) inside other (parent). Scales assumed uniform-ish."""
        tx, ty = other.pt(self.tx, self.ty)
        return Xf(tx, ty, self.rot + other.rot, self.sx * other.sx, self.sy * other.sy)

    @property
    def scale(self):
        return (abs(self.sx) + abs(self.sy)) / 2


ID = Xf()


def rad(deg):
    return deg * math.pi / 180


# ------------------------------------------------------------------ canvas

class Canvas:
    def __init__(self, w: int, h: int):
        self.w, self.h = w, h
        self.p = np.full((h, w), "", dtype=object)
        self.YY, self.XX = np.mgrid[0:h, 0:w].astype(np.float64) + 0.5

    # ---- masks
    def _poly_mask(self, wpts):
        im = Image.new("1", (self.w, self.h), 0)
        ImageDraw.Draw(im).polygon([(x - 0.5, y - 0.5) for x, y in wpts], fill=1)
        return np.array(im, dtype=bool)

    def _bbox(self, wpts, pad=2):
        xs = [p[0] for p in wpts]
        ys = [p[1] for p in wpts]
        x0, x1 = max(0, int(min(xs)) - pad), min(self.w, int(max(xs)) + pad + 1)
        y0, y1 = max(0, int(min(ys)) - pad), min(self.h, int(max(ys)) + pad + 1)
        return x0, x1, y0, y1

    # ---- painting
    def _shade(self, mask, nx, ny, rmp, bias=0.0, flat=None, seam=True, spec=True, rim=False, tone=None, clip=None):
        if clip is not None:
            mask = mask & clip
        if not mask.any():
            return
        if tone is not None:
            self.p[mask] = rmp[tone]
            if seam:
                self._seam(mask, rmp[0])
            return
        if flat is not None:
            self.p[mask] = flat
            if seam:
                self._seam(mask, rmp[0])
            return
        nz = np.sqrt(np.clip(1 - nx * nx - ny * ny, 0, 1))
        v = -(nx * LIGHT[0] + ny * LIGHT[1]) * 0.9 + nz * LIGHT[2] * 0.75 + bias
        tones = rmp[1:]
        n = len(tones)
        if n >= 4:
            idx = np.where(v < 0.18, 0, np.where(v < 0.62, 1, np.where(v < 1.0, 2, 3)))
            if not spec:
                idx = np.minimum(idx, 2)
        elif n == 3:
            idx = np.where(v < 0.2, 0, np.where(v < 0.7, 1, 2))
        else:
            idx = np.where(v < 0.4, 0, 1) if n == 2 else np.zeros_like(v, dtype=int)
        out = np.array(tones, dtype=object)[idx]
        if rim:
            # back-light: a thin lighter band on the lower-right rim
            er = ndimage.binary_erosion(mask, iterations=2)
            band = mask & ~er & ((nx * 0.7 + ny * 0.7) > 0.55)
            out = np.where(band, tones[min(2, n - 1)], out)
        self.p[mask] = out[mask]
        if seam:
            self._seam(mask, rmp[0])

    def _seam(self, mask, c):
        er = ndimage.binary_erosion(mask, structure=np.array([[0, 1, 0], [1, 1, 1], [0, 1, 0]]), border_value=0)
        self.p[mask & ~er] = c

    def ellipse(self, cx, cy, rx, ry, rmp, xf: Xf = ID, wob=None, n=None, **kw):
        n = n or max(24, int((abs(rx) + abs(ry)) * xf.scale * 0.9))
        pts = []
        for i in range(n):
            a = 2 * math.pi * i / n
            k = wob(a) if wob else 1.0
            pts.append((cx + math.cos(a) * rx * k, cy + math.sin(a) * ry * k))
        wpts = xf.pts(pts)
        mask = self._poly_mask(wpts)
        lx, ly = xf.inv(self.XX, self.YY)
        nx, ny = (lx - cx) / rx, (ly - cy) / ry
        r = np.sqrt(nx * nx + ny * ny)
        sc = np.where(r > 0.98, 0.98 / np.maximum(r, 1e-6), 1.0)
        nx, ny = nx * sc, ny * sc
        wx, wy = xf.vec(nx, ny)
        self._shade(mask, wx, wy, rmp, **kw)
        return mask

    def poly(self, pts, rmp, xf: Xf = ID, normal=(0.0, 0.0), mode="flat", **kw):
        """mode: flat (normal), cylx (curved across local x: a vertical drum), cyly (curved across local y: a horizontal pipe),
        dome (spherical round the bbox centre)."""
        wpts = xf.pts(pts)
        mask = self._poly_mask(wpts)
        if mode == "flat":
            wx, wy = xf.vec(np.full(mask.shape, normal[0]), np.full(mask.shape, normal[1]))
        else:
            lx, ly = xf.inv(self.XX, self.YY)
            xs = [p[0] for p in pts]
            ys = [p[1] for p in pts]
            cx, cy = (min(xs) + max(xs)) / 2, (min(ys) + max(ys)) / 2
            hx, hy = (max(xs) - min(xs)) / 2 or 1, (max(ys) - min(ys)) / 2 or 1
            if mode == "cylx":
                nx = np.clip((lx - cx) / hx, -0.97, 0.97) * 0.95
                ny = np.full(mask.shape, normal[1])
            elif mode == "cyly":
                ny = np.clip((ly - cy) / hy, -0.97, 0.97) * 0.95
                nx = np.full(mask.shape, normal[0])
            else:
                nx = np.clip((lx - cx) / hx, -1, 1) * 0.8
                ny = np.clip((ly - cy) / hy, -1, 1) * 0.8
            wx, wy = xf.vec(nx, ny)
        self._shade(mask, wx, wy, rmp, **kw)
        return mask

    def rect(self, x0, y0, x1, y1, rmp, xf: Xf = ID, **kw):
        return self.poly([(x0, y0), (x1, y0), (x1, y1), (x0, y1)], rmp, xf=xf, **kw)

    def tube(self, pts, rmp, xf: Xf = ID, cap=True, **kw):
        """pts: [(x, y, r), ...] local; a capsule chain with rounded normals."""
        wp = [(*xf.pt(x, y), r * xf.scale) for x, y, r in pts]
        rm = max(p[2] for p in wp) + 2
        x0, x1, y0, y1 = self._bbox([(p[0], p[1]) for p in wp], pad=int(rm) + 1)
        if x0 >= x1 or y0 >= y1:
            return np.zeros((self.h, self.w), bool)
        X, Y = self.XX[y0:y1, x0:x1], self.YY[y0:y1, x0:x1]
        best = np.full(X.shape, 9.0)
        bnx = np.zeros(X.shape)
        bny = np.zeros(X.shape)
        for (ax, ay, ar), (bx, by, br) in zip(wp, wp[1:]):
            vx, vy = bx - ax, by - ay
            ll = vx * vx + vy * vy or 1e-9
            t = np.clip(((X - ax) * vx + (Y - ay) * vy) / ll, 0, 1)
            if not cap:
                t = ((X - ax) * vx + (Y - ay) * vy) / ll
                inside = (t >= 0) & (t <= 1)
                t = np.clip(t, 0, 1)
            qx, qy, r = ax + vx * t, ay + vy * t, ar + (br - ar) * t
            d = np.hypot(X - qx, Y - qy) / np.maximum(r, 0.3)
            if not cap:
                d = np.where(inside, d, 9.0)
            better = d < best
            best = np.where(better, d, best)
            bnx = np.where(better, (X - qx) / np.maximum(r, 0.3), bnx)
            bny = np.where(better, (Y - qy) / np.maximum(r, 0.3), bny)
        sub = best <= 1.0
        mask = np.zeros((self.h, self.w), bool)
        mask[y0:y1, x0:x1] = sub
        nx = np.zeros((self.h, self.w))
        ny = np.zeros((self.h, self.w))
        nx[y0:y1, x0:x1] = np.clip(bnx, -0.97, 0.97)
        ny[y0:y1, x0:x1] = np.clip(bny, -0.97, 0.97)
        self._shade(mask, nx, ny, rmp, **kw)
        return mask

    # ---- hand detail
    def px(self, x, y, c):
        x, y = int(math.floor(x)), int(math.floor(y))
        if 0 <= x < self.w and 0 <= y < self.h:
            self.p[y, x] = c

    def line(self, x0, y0, x1, y1, c, w=1, only_on=False):
        x0, y0, x1, y1 = int(math.floor(x0)), int(math.floor(y0)), int(math.floor(x1)), int(math.floor(y1))
        dx, dy = abs(x1 - x0), -abs(y1 - y0)
        sx, sy = (1 if x0 < x1 else -1), (1 if y0 < y1 else -1)
        err = dx + dy
        while True:
            for ox in range(w):
                for oy in range(w):
                    xx, yy = x0 + ox - w // 2, y0 + oy - w // 2
                    if 0 <= xx < self.w and 0 <= yy < self.h and (not only_on or self.p[yy, xx] != ""):
                        self.p[yy, xx] = c
            if x0 == x1 and y0 == y1:
                return
            e2 = 2 * err
            if e2 >= dy:
                err += dy
                x0 += sx
            if e2 <= dx:
                err += dx
                y0 += sy

    def lline(self, xf: Xf, x0, y0, x1, y1, c, w=1, only_on=True):
        a, b = xf.pt(x0, y0), xf.pt(x1, y1)
        self.line(a[0], a[1], b[0], b[1], c, w, only_on)

    def rivet(self, x, y, rmp, xf: Xf = ID):
        X, Y = xf.pt(x, y)
        X, Y = int(math.floor(X)), int(math.floor(Y))
        self.px(X, Y, rmp[min(4, len(rmp) - 1)])
        self.px(X + 1, Y, rmp[2])
        self.px(X, Y + 1, rmp[2])
        self.px(X + 1, Y + 1, rmp[0])

    def stamp(self, x, y, rows, cmap, xf: Xf = ID, only_on=False):
        """Hand pixels: rows of chars, cmap char -> colour; '.' skip."""
        for j, r in enumerate(rows):
            for i, ch in enumerate(r):
                if ch == "." or ch == " ":
                    continue
                X, Y = xf.pt(x + i + 0.5, y + j + 0.5)
                xx, yy = int(math.floor(X)), int(math.floor(Y))
                if 0 <= xx < self.w and 0 <= yy < self.h and (not only_on or self.p[yy, xx] != ""):
                    self.p[yy, xx] = cmap[ch]

    def text(self, x, y, s, c, xf: Xf = ID, only_on=True, gap=1):
        cx = x
        for ch in s:
            g = FONT.get(ch)
            if g is None:
                cx += 3
                continue
            self.stamp(cx, y, [r.replace("#", "a") for r in g], {"a": c}, xf=xf, only_on=only_on)
            cx += len(g[0]) + gap

    def clear_poly(self, pts, xf: Xf = ID):
        m = self._poly_mask(xf.pts(pts))
        self.p[m] = ""

    def mask(self):
        return self.p != ""

    def recolor(self, mapping: dict, region=None):
        for a, b in mapping.items():
            m = self.p == a
            if region is not None:
                m &= region
            self.p[m] = b

    def outline_outer(self, c):
        """One pixel outline outside the silhouette (used sparingly on loose fx)."""
        m = self.mask()
        d = ndimage.binary_dilation(m, structure=np.array([[0, 1, 0], [1, 1, 1], [0, 1, 0]]))
        self.p[d & ~m] = c

    def paste(self, other: "Canvas", ox=0, oy=0):
        x0, y0 = max(0, ox), max(0, oy)
        x1, y1 = min(self.w, ox + other.w), min(self.h, oy + other.h)
        if x0 >= x1 or y0 >= y1:
            return
        src = other.p[y0 - oy:y1 - oy, x0 - ox:x1 - ox]
        dst = self.p[y0:y1, x0:x1]
        m = src != ""
        dst[m] = src[m]

    def rgba(self) -> Image.Image:
        out = np.zeros((self.h, self.w, 4), np.uint8)
        cache = {}
        for name in set(self.p.flatten()):
            if name == "":
                continue
            cache[name] = (*hex_rgb(PAL[name]), 255)
        for name, c in cache.items():
            out[self.p == name] = c
        return Image.fromarray(out, "RGBA")


# ------------------------------------------------------------------ tiny pixel font (3x5, a few 4/5 wide)

FONT = {
    "A": ["###", "#.#", "###", "#.#", "#.#"], "B": ["##.", "#.#", "##.", "#.#", "##."],
    "C": ["###", "#..", "#..", "#..", "###"], "D": ["##.", "#.#", "#.#", "#.#", "##."],
    "E": ["###", "#..", "##.", "#..", "###"], "F": ["###", "#..", "##.", "#..", "#.."],
    "G": ["###", "#..", "#.#", "#.#", "###"], "H": ["#.#", "#.#", "###", "#.#", "#.#"],
    "I": ["#", "#", "#", "#", "#"], "K": ["#.#", "#.#", "##.", "#.#", "#.#"],
    "L": ["#..", "#..", "#..", "#..", "###"], "M": ["#...#", "##.##", "#.#.#", "#...#", "#...#"],
    "N": ["#..#", "##.#", "#.##", "#..#", "#..#"], "O": ["###", "#.#", "#.#", "#.#", "###"],
    "P": ["###", "#.#", "###", "#..", "#.."], "R": ["##.", "#.#", "##.", "#.#", "#.#"],
    "S": ["###", "#..", "###", "..#", "###"], "T": ["###", ".#.", ".#.", ".#.", ".#."],
    "U": ["#.#", "#.#", "#.#", "#.#", "###"], "V": ["#.#", "#.#", "#.#", "#.#", ".#."],
    "Y": ["#.#", "#.#", ".#.", ".#.", ".#."], "Z": ["###", "..#", ".#.", "#..", "###"],
    "0": ["###", "#.#", "#.#", "#.#", "###"], "1": [".#", "##", ".#", ".#", ".#"],
    "!": ["#", "#", "#", ".", "#"], "-": ["...", "...", "###", "...", "..."],
    ".": [".", ".", ".", ".", "#"], "?": ["###", "..#", ".##", "...", ".#."],
}


# ------------------------------------------------------------------ helpers

def wobble(n=7, amp=0.15, phase=0.0, n2=None, amp2=0.0, ph2=0.0):
    def f(a):
        v = 1 + amp * math.cos(n * a + phase)
        if n2:
            v += amp2 * math.cos(n2 * a + ph2)
        return v
    return f


def rng(seed):
    return np.random.default_rng(seed)


# ------------------------------------------------------------------ export

def save_sheet(name: str, frames: list[tuple[str, Canvas]], w: int, h: int, anchor, extras: dict | None = None,
               max_colours=64):
    ART.mkdir(parents=True, exist_ok=True)
    sheet = Image.new("RGBA", (w * len(frames), h), (0, 0, 0, 0))
    for i, (_, c) in enumerate(frames):
        assert (c.w, c.h) == (w, h), (name, c.w, c.h)
        sheet.paste(c.rgba(), (i * w, 0))
    a = np.array(sheet)
    a[..., 3] = np.where(a[..., 3] > 0, 255, 0)
    sheet = Image.fromarray(a, "RGBA")
    cols = {tuple(px) for px in a.reshape(-1, 4) if px[3]}
    assert len(cols) <= max_colours, f"{name}: {len(cols)} colours"
    sheet.save(ART / f"{name}.png")
    meta = {"w": w, "h": h, "anchor": list(anchor), "frames": [n for n, _ in frames]}
    if extras:
        meta.update(extras)
    (ART / f"{name}.json").write_text(json.dumps(meta, indent=1) + "\n")
    preview(name, sheet, w, h, [n for n, _ in frames], anchor)
    return len(cols)


def preview(name, sheet: Image.Image, w, h, names, anchor, scale=2, cols=None):
    n = len(names)
    cols = cols or max(1, min(n, 2400 // (w * scale + 4)))
    rows = (n + cols - 1) // cols
    cw, ch = w * scale + 4, h * scale + 4
    out = Image.new("RGB", (cols * cw, rows * ch * 2 + 8), (40, 40, 40))
    for bi, bg in enumerate([(128, 128, 128), (150, 210, 245)]):
        for i in range(n):
            fr = sheet.crop((i * w, 0, (i + 1) * w, h)).resize((w * scale, h * scale), Image.NEAREST)
            cell = Image.new("RGB", (w * scale, h * scale), bg)
            cell.paste(fr, (0, 0), fr)
            d = ImageDraw.Draw(cell)
            ax, ay = anchor[0] * scale, anchor[1] * scale
            d.line([(ax - 4, ay), (ax + 4, ay)], fill=(255, 0, 255))
            d.line([(ax, ay - 4), (ax, ay + 4)], fill=(255, 0, 255))
            d.text((3, 2), names[i], fill=(20, 20, 20))
            x, y = (i % cols) * cw + 2, (i // cols) * ch + 2 + bi * (rows * ch + 8)
            out.paste(cell, (x, y))
    out.save(ART / f"preview_{name}.png")
