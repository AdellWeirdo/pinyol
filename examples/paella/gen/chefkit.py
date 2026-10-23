"""chefkit: a small paper-doll renderer for the Paella de Combate cooks.

A frame is painted at SS x supersampling into three buffers (colour index, part id, cel tone). Every part is a union of
simple shapes (circles, ellipses, tapered capsules, polygons) shaded as ONE inflated blob: the normal comes from the
distance to the part's own edge (a pillow), lit from the upper left, cut into three cel tones plus a highlight. The
buffers are then reduced to 1x by a weighted vote per pixel (no blending: every pixel is one palette colour or empty),
and outlined at 1x:
  * a pixel of a part that touches a part BEHIND it becomes that part's dark line colour (a seam, so limbs read);
  * an empty pixel next to the figure becomes the global outline colour (dark warm plum, never black).
Faces and fine details are 1x pixel stamps written straight into the supersampled buffers, so they survive the vote
exactly (and follow rotations of the whole figure).

World coordinates: x forward (the cooks face right), y down, origin = the hip PIN of the legs/torso contract.
"""
from __future__ import annotations

import json
import math
from pathlib import Path

import numpy as np
from PIL import Image, ImageDraw, ImageFont
from scipy import ndimage

SS = 4
LIGHT = np.array([-0.42, -0.60, 0.68])
LIGHT = LIGHT / np.linalg.norm(LIGHT)
BOUNCE = np.array([0.78, 0.50, 0.10])
BOUNCE = BOUNCE / np.linalg.norm(BOUNCE)
T_DARK, T_LIGHT, T_HI = 0.30, 0.74, 0.95
COVER_MIN = 7          # weighted subpixels (of 16) a pixel needs to be opaque

KINDS = {"upper": 0, "body": 1, "lower": 2}


def rgb(h: str) -> tuple:
    h = h.lstrip("#")
    return tuple(int(h[i:i + 2], 16) for i in (0, 2, 4))


class Mat:
    """A material: a dark line colour and a ramp dark, mid, light (and an optional highlight)."""

    def __init__(self, line, dark, mid, light, hi=None, bounce=True):
        self.line = rgb(line)
        self.ramp = [rgb(dark), rgb(mid), rgb(light), rgb(hi) if hi else rgb(light)]
        self.bounce = bounce

    def tone(self, i: int):
        return self.ramp[max(0, min(3, i))]


# ------------------------------------------------------------------ shapes

def _bbox(s):
    k = s[0]
    if k == "-":
        return _bbox(s[1])
    if k == "circ":
        _, x, y, r = s
        return x - r, y - r, x + r, y + r
    if k == "ell":
        _, x, y, rx, ry, a = s
        c, si = abs(math.cos(a)), abs(math.sin(a))
        ex, ey = rx * c + ry * si, rx * si + ry * c
        return x - ex, y - ey, x + ex, y + ey
    if k == "cap":
        _, x0, y0, x1, y1, r0, r1 = s
        r = max(r0, r1)
        return min(x0, x1) - r, min(y0, y1) - r, max(x0, x1) + r, max(y0, y1) + r
    if k == "poly":
        xs = [p[0] for p in s[1]]
        ys = [p[1] for p in s[1]]
        return min(xs), min(ys), max(xs), max(ys)
    if k == "rect":
        return s[1:5]
    raise ValueError(k)


def _mask(s, X, Y, ox, oy, sx0, sy0):
    k = s[0]
    if k == "circ":
        _, x, y, r = s
        return (X - x) ** 2 + (Y - y) ** 2 <= r * r
    if k == "ell":
        _, x, y, rx, ry, a = s
        c, si = math.cos(a), math.sin(a)
        dx, dy = X - x, Y - y
        u = dx * c + dy * si
        v = -dx * si + dy * c
        return (u / rx) ** 2 + (v / ry) ** 2 <= 1.0
    if k == "cap":
        _, x0, y0, x1, y1, r0, r1 = s
        vx, vy = x1 - x0, y1 - y0
        ll = vx * vx + vy * vy
        if ll < 1e-9:
            return (X - x0) ** 2 + (Y - y0) ** 2 <= max(r0, r1) ** 2
        t = np.clip(((X - x0) * vx + (Y - y0) * vy) / ll, 0, 1)
        px, py = x0 + t * vx, y0 + t * vy
        r = r0 + (r1 - r0) * t
        return (X - px) ** 2 + (Y - py) ** 2 <= r * r
    if k == "rect":
        _, x0, y0, x1, y1 = s
        return (X >= x0) & (X < x1) & (Y >= y0) & (Y < y1)
    if k == "poly":
        h, w = X.shape
        im = Image.new("L", (w, h), 0)
        pts = [((px + ox) * SS - sx0 - 0.5, (py + oy) * SS - sy0 - 0.5) for px, py in s[1]]
        ImageDraw.Draw(im).polygon(pts, fill=255)
        return np.asarray(im) > 0
    raise ValueError(k)


# ------------------------------------------------------------------ canvas

class Canvas:
    def __init__(self, w: int, h: int, ox: int, oy: int, outline: str):
        self.w, self.h, self.ox, self.oy = w, h, ox, oy
        H, W = h * SS, w * SS
        self.col = np.full((H, W), -1, np.int16)
        self.pid = np.full((H, W), -1, np.int16)
        self.tone = np.zeros((H, W), np.int8)
        self.colors: list[tuple] = []
        self._ci: dict[tuple, int] = {}
        self.parts: list[dict] = []
        self.outline = rgb(outline)
        self.cidx(self.outline)

    def cidx(self, c) -> int:
        if isinstance(c, str):
            c = rgb(c)
        if c not in self._ci:
            self._ci[c] = len(self.colors)
            self.colors.append(c)
        return self._ci[c]

    def _grid(self, x0, y0, x1, y1):
        H, W = self.col.shape
        sx0 = max(0, int(math.floor((x0 + self.ox) * SS)) - 2)
        sy0 = max(0, int(math.floor((y0 + self.oy) * SS)) - 2)
        sx1 = min(W, int(math.ceil((x1 + self.ox) * SS)) + 2)
        sy1 = min(H, int(math.ceil((y1 + self.oy) * SS)) + 2)
        if sx1 <= sx0 or sy1 <= sy0:
            return None
        xs = (np.arange(sx0, sx1) + 0.5) / SS - self.ox
        ys = (np.arange(sy0, sy1) + 0.5) / SS - self.oy
        X, Y = np.meshgrid(xs, ys)
        return (slice(sy0, sy1), slice(sx0, sx1)), X, Y, sx0, sy0

    def shapes_mask(self, shapes):
        pos = [s for s in shapes if s[0] != "-"]
        if not pos:
            return None
        bb = [_bbox(s) for s in pos]
        g = self._grid(min(b[0] for b in bb), min(b[1] for b in bb), max(b[2] for b in bb), max(b[3] for b in bb))
        if g is None:
            return None
        sl, X, Y, sx0, sy0 = g
        m = np.zeros(X.shape, bool)
        for s in shapes:
            if s[0] == "-":
                m &= ~_mask(s[1], X, Y, self.ox, self.oy, sx0, sy0)
            else:
                m |= _mask(s, X, Y, self.ox, self.oy, sx0, sy0)
        return sl, m

    def part(self, name, mat: Mat, shapes, kind="upper", group=None, weight=1.0, far=0, R=3.0, bias=0.0,
             flat=None, tilt=(0.0, 0.0), clip=None, seam=True, behind=False):
        """Paint one part (union of shapes, '-' entries subtract). Returns its id. clip: shapes the part is limited to.
        behind=True paints only where the canvas is still empty (a part tucked behind what is already drawn)."""
        pid = len(self.parts)
        self.parts.append(dict(name=name, mat=mat, kind=KINDS[kind], group=group if group is not None else pid,
                               weight=weight, seam=seam))
        r = self.shapes_mask(shapes)
        if r is None:
            return pid
        sl, m = r
        if clip is not None:
            rc = self.shapes_mask(clip)
            cm = np.zeros(self.col.shape, bool)
            if rc is not None:
                cm[rc[0]] = rc[1]
            m = m & cm[sl]
        if not m.any():
            return pid
        if flat is not None:
            tone = np.full(m.shape, flat, np.int8)
        else:
            pad = np.pad(m, 1)
            d = ndimage.distance_transform_edt(pad)
            gy, gx = np.gradient(d)
            d, gx, gy = d[1:-1, 1:-1], gx[1:-1, 1:-1], gy[1:-1, 1:-1]
            gl = np.hypot(gx, gy) + 1e-6
            dpx = (d - 0.5) / SS
            s = np.clip(1.0 - dpx / max(R, 0.3), 0, 1)
            nx, ny = -gx / gl * s + tilt[0], -gy / gl * s + tilt[1]
            nz = np.sqrt(np.clip(1 - s * s, 0, 1)) + 0.05
            nl = np.sqrt(nx * nx + ny * ny + nz * nz)
            nx, ny, nz = nx / nl, ny / nl, nz / nl
            dot = nx * LIGHT[0] + ny * LIGHT[1] + nz * LIGHT[2] + bias
            tone = np.where(dot < T_DARK, 0, np.where(dot < T_LIGHT, 1, np.where(dot < T_HI, 2, 3))).astype(np.int8)
            if mat.bounce:
                b = nx * BOUNCE[0] + ny * BOUNCE[1] + nz * BOUNCE[2]
                tone = np.where((tone == 0) & (b > 0.80) & (s > 0.55), 1, tone).astype(np.int8)
        if far:
            tone = np.maximum(tone - far, 0).astype(np.int8)
        if behind:
            m = m & (self.pid[sl] < 0)
        cols = np.array([self.cidx(mat.tone(i)) for i in range(4)], np.int16)
        self.col[sl][m] = cols[tone[m]]
        self.pid[sl][m] = pid
        self.tone[sl][m] = tone[m]
        return pid

    def paint(self, shapes, mat: Mat | None = None, color=None, within=None, tone_shift=0):
        """Recolour (keeping part ids) the area of shapes, only over the parts in `within` (ids).
        With mat: each subpixel takes mat's ramp at the tone already there (stripes, patterns); with color: flat."""
        r = self.shapes_mask(shapes)
        if r is None:
            return
        sl, m = r
        if within is not None:
            m = m & np.isin(self.pid[sl], list(within))
        else:
            m = m & (self.pid[sl] >= 0)
        if color is not None:
            self.col[sl][m] = self.cidx(color)
        else:
            cols = np.array([self.cidx(mat.tone(i)) for i in range(4)], np.int16)
            t = np.clip(self.tone[sl][m] + tone_shift, 0, 3)
            self.col[sl][m] = cols[t]

    def stamp(self, rows, x: int, y: int, legend: dict, pid: int, only_on=None):
        """1x pixel art written at world pixel (x, y) = top-left. '.' and ' ' are see-through.
        only_on: a set of part ids; stamp pixels land only where the canvas already shows one of them."""
        for j, row in enumerate(rows):
            for i, ch in enumerate(row):
                if ch in ". ":
                    continue
                sx = (x + i + self.ox) * SS
                sy = (y + j + self.oy) * SS
                if sx < 0 or sy < 0 or sx + SS > self.col.shape[1] or sy + SS > self.col.shape[0]:
                    continue
                blk = (slice(sy, sy + SS), slice(sx, sx + SS))
                if only_on is not None and not np.isin(self.pid[blk], list(only_on)).any():
                    continue
                self.col[blk] = self.cidx(legend[ch])
                self.pid[blk] = pid

    # -------------------------------------------------- whole-figure transforms (full-body frames)

    def transform(self, angle=0.0, sx=1.0, sy=1.0, pivot=(0.0, 0.0), shift=(0.0, 0.0)):
        """Rotate (radians, + = clockwise on screen) and scale the painted figure about a world pivot, then shift."""
        H, W = self.col.shape
        ys, xs = np.mgrid[0:H, 0:W]
        wx = (xs + 0.5) / SS - self.ox - pivot[0] - shift[0]
        wy = (ys + 0.5) / SS - self.oy - pivot[1] - shift[1]
        c, s = math.cos(-angle), math.sin(-angle)
        ux = (c * wx - s * wy) / sx + pivot[0]
        uy = (s * wx + c * wy) / sy + pivot[1]
        px = np.floor((ux + self.ox) * SS).astype(int)
        py = np.floor((uy + self.oy) * SS).astype(int)
        ok = (px >= 0) & (py >= 0) & (px < W) & (py < H)
        pxc, pyc = np.clip(px, 0, W - 1), np.clip(py, 0, H - 1)
        for name in ("col", "pid", "tone"):
            a = getattr(self, name)
            b = a[pyc, pxc]
            b = np.where(ok, b, -1 if name != "tone" else 0).astype(a.dtype)
            setattr(self, name, b)

    def shift(self, dx: float, dy: float):
        """Move everything painted by (dx, dy) world pixels (rounded to subpixels)."""
        sx, sy = int(round(dx * SS)), int(round(dy * SS))
        for name in ("col", "pid", "tone"):
            a = getattr(self, name)
            b = np.full_like(a, -1 if name != "tone" else 0)
            H, W = a.shape
            ys0, ys1 = max(0, sy), min(H, H + sy)
            xs0, xs1 = max(0, sx), min(W, W + sx)
            b[ys0:ys1, xs0:xs1] = a[ys0 - sy:ys1 - sy, xs0 - sx:xs1 - sx]
            setattr(self, name, b)

    def settle(self, floor: float):
        """Shift the figure vertically so its lowest painted subpixel lies just above world row `floor`."""
        rows = np.where((self.pid >= 0).any(1))[0]
        if len(rows) == 0:
            return
        low = (rows[-1] + 1) / SS - self.oy
        self.shift(0, floor - low)

    def recolor(self, fn, keep=()):
        """Replace every colour c (except those in keep) by fn(c)."""
        lut = np.arange(len(self.colors) + 1, dtype=np.int16)
        keepi = {self.cidx(k) for k in keep}
        for i, c in enumerate(list(self.colors)):
            if i == 0 or i in keepi:
                continue
            lut[i] = self.cidx(fn(c))
        self.col = np.where(self.col >= 0, lut[np.clip(self.col, 0, None)], -1).astype(np.int16)

    def mask_world(self):
        return self.pid >= 0

    # -------------------------------------------------- reduction to 1x

    def resolve(self):
        H, W = self.col.shape
        h, w = H // SS, W // SS
        pb = self.pid.reshape(h, SS, w, SS).transpose(0, 2, 1, 3).reshape(h, w, SS * SS)
        cb = self.col.reshape(h, SS, w, SS).transpose(0, 2, 1, 3).reshape(h, w, SS * SS)
        best = np.full((h, w), -1, np.int32)
        bests = np.zeros((h, w))
        cover = np.zeros((h, w))
        for p in np.unique(pb[pb >= 0]):
            sc = (pb == p).sum(-1) * self.parts[p]["weight"]
            cover += sc
            upd = sc > bests
            best[upd] = p
            bests[upd] = sc[upd]
        opaque = (cover >= COVER_MIN) & (best >= 0)
        best[~opaque] = -1
        col = np.full((h, w), -1, np.int32)
        bestc = np.zeros((h, w))
        mine = pb == best[..., None]
        for c in np.unique(cb[cb >= 0]):
            n = ((cb == c) & mine).sum(-1)
            upd = n > bestc
            col[upd] = c
            bestc[upd] = n[upd]
        col[~opaque] = -1
        return self._outline(col, best)

    def _outline(self, col, pid):
        h, w = col.shape
        out = col.copy()
        owner = pid.copy()
        grp = np.array([p["group"] for p in self.parts] + [-1])
        seamok = np.array([p["seam"] for p in self.parts] + [False])
        line = np.array([self.cidx(p["mat"].line) for p in self.parts] + [0])
        P = np.pad(pid, 1, constant_values=-1)
        isseam = np.zeros((h, w), bool)
        for dy, dx in ((0, 1), (0, -1), (1, 0), (-1, 0)):
            Q = P[1 + dy:1 + dy + h, 1 + dx:1 + dx + w]
            cond = (pid >= 0) & (Q >= 0) & (Q != pid) & (pid > Q) & (grp[pid] != grp[Q]) & seamok[pid]
            isseam |= cond
        out[isseam] = line[pid[isseam]]
        ext = np.zeros((h, w), bool)
        own = np.full((h, w), -1, np.int32)
        for dy, dx in ((0, 1), (0, -1), (1, 0), (-1, 0)):
            Q = P[1 + dy:1 + dy + h, 1 + dx:1 + dx + w]
            cond = (pid < 0) & (Q >= 0)
            ext |= cond
            own = np.where(cond & (Q > own), Q, own)
        out[ext] = 0
        owner[ext] = own[ext]
        kinds = np.array([p["kind"] for p in self.parts] + [-1])
        return Result(out, owner, kinds[owner], self.colors, self.ox, self.oy)


class Result:
    def __init__(self, col, owner, kind, colors, ox, oy):
        self.col, self.owner, self.kind, self.colors, self.ox, self.oy = col, owner, kind, colors, ox, oy

    def select(self, keep):
        r = Result(np.where(keep & (self.col >= 0), self.col, -1), self.owner, self.kind, self.colors, self.ox, self.oy)
        return r

    def wy(self):
        """World y of each pixel row (broadcastable column)."""
        return (np.arange(self.col.shape[0]) - self.oy)[:, None]

    def image(self) -> Image.Image:
        h, w = self.col.shape
        pal = np.array(self.colors + [(0, 0, 0)], np.uint8)
        idx = np.where(self.col >= 0, self.col, len(self.colors))
        a = np.zeros((h, w, 4), np.uint8)
        a[..., :3] = pal[idx]
        a[..., 3] = np.where(self.col >= 0, 255, 0)
        return Image.fromarray(a, "RGBA")


# ------------------------------------------------------------------ rig helpers

def ik(a, t, l1, l2, bend=1.0):
    """Two-bone IK: from joint a toward target t; returns the middle joint. bend=+1 puts it to the left of a->t."""
    dx, dy = t[0] - a[0], t[1] - a[1]
    d = math.hypot(dx, dy)
    d = max(abs(l1 - l2) + 0.05, min(l1 + l2 - 0.05, d))
    ca = (l1 * l1 + d * d - l2 * l2) / (2 * l1 * d)
    ang = math.atan2(dy, dx) - bend * math.acos(max(-1, min(1, ca)))
    return (a[0] + l1 * math.cos(ang), a[1] + l1 * math.sin(ang))


def rot(p, ang, about=(0.0, 0.0)):
    c, s = math.cos(ang), math.sin(ang)
    x, y = p[0] - about[0], p[1] - about[1]
    return (about[0] + c * x - s * y, about[1] + s * x + c * y)


def add(a, b, k=1.0):
    return (a[0] + k * b[0], a[1] + k * b[1])


def lerp(a, b, t):
    return (a[0] + (b[0] - a[0]) * t, a[1] + (b[1] - a[1]) * t)


def polar(ang, r):
    return (math.cos(ang) * r, math.sin(ang) * r)


# ------------------------------------------------------------------ sheets & previews

def save_sheet(path_png: Path, frames: list[Image.Image], names: list[str], meta: dict):
    w, h = frames[0].size
    sheet = Image.new("RGBA", (w * len(frames), h), (0, 0, 0, 0))
    for i, f in enumerate(frames):
        sheet.paste(f, (i * w, 0))
    sheet.save(path_png)
    data = {"w": w, "h": h}
    data.update(meta)
    data["frames"] = names
    path_png.with_suffix(".json").write_text(json.dumps(data, indent=1))
    cols = {tuple(c) for c in np.asarray(sheet).reshape(-1, 4) if c[3] == 255}
    return len(cols)


def _font(size=10):
    for p in ("/System/Library/Fonts/Menlo.ttc", "/System/Library/Fonts/Monaco.ttf", "/System/Library/Fonts/Geneva.ttf"):
        try:
            return ImageFont.truetype(p, size)
        except OSError:
            pass
    return ImageFont.load_default()


GREY = (110, 110, 118)
SKY = (150, 214, 248)


def preview(path: Path, frames, names, cols=10, scale=2, marks=None):
    """2x contact sheet, each frame shown on mid grey and on bright sky, labelled. marks: name -> [(x,y,color)]."""
    w, h = frames[0].size
    fw, fh = w * scale, h * scale
    lab = 12
    rows = (len(frames) + cols - 1) // cols
    img = Image.new("RGB", (cols * (fw * 2 + 6) + 4, rows * (fh + lab + 6) + 4), (40, 36, 44))
    d = ImageDraw.Draw(img)
    f = _font(10)
    for i, (fr, nm) in enumerate(zip(frames, names)):
        cx = 4 + (i % cols) * (fw * 2 + 6)
        cy = 4 + (i // cols) * (fh + lab + 6)
        big = fr.resize((fw, fh), Image.NEAREST)
        for k, bg in enumerate((GREY, SKY)):
            tile = Image.new("RGB", (fw, fh), bg)
            tile.paste(big, (0, 0), big)
            img.paste(tile, (cx + k * fw, cy + lab))
        d.text((cx + 2, cy), nm, fill=(240, 230, 200), font=f)
        if marks and nm in marks:
            for (mx, my, mc) in marks[nm]:
                for k in range(2):
                    px, py = cx + k * fw + mx * scale, cy + lab + my * scale
                    d.rectangle([px - 2, py - 2, px + 2, py + 2], outline=mc)
    img.save(path)
