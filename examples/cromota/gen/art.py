"""CROMOTA' art, drawn by code (no AI-model images except the painting, cut from refs/).

    sh examples/cromota/gen/build.sh      (from the repo root; needs numpy and pillow, build.sh gets them with uv)

The three paintings are cut from public-domain scans (refs/fuentes/*.jpg, not in the repo): point CROMOTA_REFS at the folder
that holds refs/ to cut them again. Without it only the UI, the drops and the brush are redrawn and the paintings in art/
and layout.lua stay as they are. No word is drawn into any picture: every text is drawn by main.lua / dibujo.lua with
text() so it can be translated (strings.csv).

- GOTAS / GOTAS_S: the pieces, 11 frames in COLORES order (a drop each, then the sponge): 24x24 and 12x12.
  The symbol of each colour (circle, plus, triangle...) is redundant on purpose: no colour is told by hue alone.
- FONDO: the canonical screen at 480x320 (drawn at 240x160 and doubled: the world's pixel): wall, bench, board well,
  frames, plaques, panels. Everything dynamic (numbers, drops, tray contents, painting) is drawn over it by the game.
- BROCHA: the brush, frame 0 empty and 1..10 loaded with a colour.
- OBRA_GRIS and OBRA_<n>: the painting (refs/ Starry Night, 152x104) cut into colour regions: the grey parchment
  version, and one see-through layer per region in its real colours. obra.lua: which region each 4x4 block belongs to.
- layout.lua: where every box of the canonical UI is, and the colours (read by main.lua and ui.lua).
"""
import json
from pathlib import Path

import numpy as np
from PIL import Image, ImageEnhance

import os

GAME = Path(__file__).resolve().parent.parent  # examples/cromota
ROOT = Path(os.environ.get("CROMOTA_REFS", GAME))  # where refs/fuentes/ is, if the paintings are to be cut again
ART = GAME / "art"

# id order = frame order in GOTAS. (key, name, 0xRRGGBB body, symbol)
COLORES = [
    ("rojo", "ROJO", (216, 52, 44), "circulo"),
    ("amarillo", "AMARILLO", (242, 194, 48), "mas"),
    ("azul", "AZUL", (42, 93, 176), "triangulo"),
    ("blanco", "BLANCO", (236, 236, 240), "estrella"),
    ("negro", "NEGRO", (46, 46, 56), "rombo"),
    ("naranja", "NARANJA", (238, 122, 34), "cuadro"),
    ("verde", "VERDE", (62, 154, 72), "hoja"),
    ("violeta", "VIOLETA", (122, 62, 154), "espiral"),
    ("celeste", "CELESTE", (106, 180, 232), "onda"),
    ("marino", "MARINO", (30, 50, 130), "luna"),
]

# ----------------------------------------------------------------------------------------------- the canonical UI
# 480x320 boxes (x, y, w, h). All even, so the 240x160 drawing doubles exactly.
L = {
    "nivel": (10, 8, 48, 38),
    "mov": (10, 52, 48, 38),
    "combo": (4, 98, 58, 62),
    "tablero_marco": (62, 4, 242, 208),
    "celdas": (70, 10, 224, 196),  # 8 columns x 7 rows of 28 (the canonical image has 8x7)
    "reserva": (4, 164, 58, 68),
    "mensaje": (66, 214, 236, 18),
    "obra_marco": (306, 8, 166, 124),
    "obra_titulo": (340, 2, 104, 18),
    "obra": (313, 21, 152, 104),
    "rest_marco": (306, 138, 166, 116),
    "rest": (313, 145, 152, 104),
    "mesa": (0, 236, 480, 84),
    "mezcla": (18, 236, 196, 78),
    "mezcla_titulo": (84, 230, 64, 14),
    "ing_a": (26, 250, 36, 44),
    "ing_b": (86, 250, 36, 44),
    "res": (148, 250, 46, 44),
    "estado": (146, 296, 60, 12),
    "pincel": (222, 238, 76, 72),
    "obj_marco": (300, 262, 150, 54),
    "obj_titulo": (346, 256, 58, 12),
    "vaso": (454, 262, 22, 54),
}
CELDA, COLS, FILAS = 28, 8, 7
L_COLS, L_FILAS = COLS, FILAS
OBJ_SLOT = [(306 + i * 35, 268, 32, 46) for i in range(4)]

# ------------------------------------------------------------------------------------------------------ drops
SIMBOLOS = {
    "circulo": [".###.", "#...#", "#...#", "#...#", ".###."],
    "mas": ["..#..", "..#..", "#####", "..#..", "..#.."],
    "triangulo": ["..#..", ".#.#.", ".#.#.", "#...#", "#####"],
    "estrella": ["..#..", ".###.", "#####", ".###.", "..#.."],
    "rombo": ["..#..", ".#.#.", "#...#", ".#.#.", "..#.."],
    "cuadro": ["#####", "#...#", "#...#", "#...#", "#####"],
    "hoja": ["...##", "..###", ".###.", "###..", "##..."],
    "espiral": [".###.", "#...#", "#.#.#", "#..##", ".###."],
    "onda": [".....", ".#.#.", "#.#.#", ".....", "....."],
    "luna": [".###.", "#....", "#....", "#....", ".###."],
}


def mezcla(a, b, t):
    return tuple(int(round(x + (y - x) * t)) for x, y in zip(a, b))


def lum(c):
    return 0.3 * c[0] + 0.59 * c[1] + 0.11 * c[2]


def gota24(color, simbolo):
    """24x24 RGBA: a round teardrop lit from the top left. Five tones (contour, shade, body, light, shine), a bounce
    light along the lower right rim, a glossy highlight and the colour-blind symbol pressed into the body."""
    S = 24
    ys, xs = np.mgrid[0:S, 0:S]
    px, py = xs + 0.5, ys + 0.5
    ytip, cy, r = 1.6, 15.6, 7.9
    d = cy - ytip
    yt = cy - r * r / d  # where the straight sides meet the round belly (tangent)
    pend = r / np.sqrt(d * d - r * r)
    dx = px - 12
    hw = np.where(py <= yt, np.clip(py - ytip, 0, None) * pend, np.sqrt(np.clip(r * r - (py - cy) ** 2, 0, None)))
    dentro = (np.abs(dx) <= hw) & (py >= ytip) & (py <= cy + r)
    borde = dentro & ~(np.roll(dentro, 1, 0) & np.roll(dentro, -1, 0) & np.roll(dentro, 1, 1) & np.roll(dentro, -1, 1))
    nx = np.clip(dx / np.maximum(hw, 1.0), -1, 1)
    ny = np.clip((py - cy) / r, -1, 1) * 0.9
    nz = np.sqrt(np.clip(1 - nx ** 2 - ny ** 2 * 0.5, 0.02, 1))
    luz = np.clip(nx * -0.5 + ny * -0.55 + nz * 0.66, 0, 1)
    contorno = mezcla(color, (12, 8, 22), 0.74)
    tonos = [mezcla(color, (24, 14, 54), 0.5), mezcla(color, (24, 14, 54), 0.26), color,
             mezcla(color, (255, 240, 205), 0.28), mezcla(color, (255, 250, 235), 0.55)]
    rebote = mezcla(color, (255, 215, 235), 0.32)
    f = np.zeros((S, S, 4), np.uint8)
    nivel = np.digitize(luz, [0.3, 0.52, 0.8, 0.93])
    for y in range(S):
        for x in range(S):
            if not dentro[y, x]:
                continue
            if borde[y, x]:
                c = contorno
            else:
                c = tonos[nivel[y, x]]
                d_borde = hw[y, x] - abs(dx[y, x])
                if nx[y, x] > 0.45 and ny[y, x] > 0.15 and d_borde < 2.6:
                    c = rebote
            f[y, x] = (*c, 255)
    # glossy highlight (a tilted bar) and a pinpoint
    for y in range(S):
        for x in range(S):
            if dentro[y, x] and not borde[y, x]:
                u, v = (px[y, x] - 8.9) / 1.3, (py[y, x] - 12.0) / 2.9
                if u * u + v * v <= 1:
                    f[y, x] = (255, 255, 255, 255)
    for X, Y in ((10, 8), (9, 16)):
        if dentro[Y, X] and not borde[Y, X]:
            f[Y, X] = (255, 255, 255, 255)
    # symbol: 5x5 doubled, a dark offset under it so it looks pressed in
    tinta = mezcla(color, (20, 14, 34), 0.62) if lum(color) > 140 else mezcla(color, (255, 250, 240), 0.72)
    sombra = mezcla(color, (10, 6, 20), 0.5) if lum(color) <= 140 else mezcla(color, (255, 255, 255), 0.5)
    for pasada, (ox, oy, col) in enumerate(((1, 1, sombra), (0, 0, tinta))):
        for j, row in enumerate(SIMBOLOS[simbolo]):
            for i, ch in enumerate(row):
                if ch == "#":
                    for yy in range(2):
                        for xx in range(2):
                            X, Y = 7 + i * 2 + xx + ox, 12 + j * 2 + yy + oy
                            if 0 <= X < S and 0 <= Y < S and dentro[Y, X] and not borde[Y, X]:
                                f[Y, X] = (*col, 255)
    return f


def esponja24():
    S = 24
    f = np.zeros((S, S, 4), np.uint8)
    rng = np.random.default_rng(3)
    ys, xs = np.mgrid[0:S, 0:S]
    d = np.maximum(np.abs(xs - 11.5), np.abs(ys - 11.5))
    redond = (np.abs(xs - 11.5) > 8.2) & (np.abs(ys - 11.5) > 8.2)
    dentro = (d <= 9.6) & ~redond
    borde = dentro & ~(np.roll(dentro, 1, 0) & np.roll(dentro, -1, 0) & np.roll(dentro, 1, 1) & np.roll(dentro, -1, 1))
    base = (226, 188, 62)
    for y in range(S):
        for x in range(S):
            if not dentro[y, x]:
                continue
            t = (x + y) / (2 * S)
            c = mezcla(mezcla(base, (255, 236, 150), 0.45), mezcla(base, (120, 80, 20), 0.5), t)
            if borde[y, x]:
                c = (110, 74, 22)
            f[y, x] = (*c, 255)
    for _ in range(9):
        cx, cy = int(rng.integers(5, 19)), int(rng.integers(5, 19))
        rx, ry = int(rng.integers(1, 3)), int(rng.integers(1, 3))
        for y in range(cy - ry, cy + ry + 1):
            for x in range(cx - rx, cx + rx + 1):
                if 0 <= x < S and 0 <= y < S and dentro[y, x] and not borde[y, x]:
                    f[y, x] = (*(122, 84, 26), 255)
                    if y == cy + ry and x > cx - rx:
                        f[y, x] = (*(244, 214, 120), 255)
    return f


def ampliar(a, k):
    return np.kron(a, np.ones((k, k, 1), np.uint8))


def pincel24():
    """The wide brush piece: a golden plate with a brush across it and a spark."""
    S = 24
    f = np.zeros((S, S, 4), np.uint8)
    ys, xs = np.mgrid[0:S, 0:S]
    d = np.maximum(np.abs(xs - 11.5), np.abs(ys - 11.5))
    redond = (np.abs(xs - 11.5) > 9.2) & (np.abs(ys - 11.5) > 9.2)
    dentro = (d <= 10.5) & ~redond
    borde = dentro & ~(np.roll(dentro, 1, 0) & np.roll(dentro, -1, 0) & np.roll(dentro, 1, 1) & np.roll(dentro, -1, 1))
    for y in range(S):
        for x in range(S):
            if not dentro[y, x]:
                continue
            t = (x + y) / (2 * S)
            c = mezcla((250, 214, 110), (150, 96, 30), t)
            if d[y, x] <= 8.4:
                c = mezcla((44, 52, 100), (22, 26, 60), (y / S))
            if borde[y, x]:
                c = (70, 44, 12)
            f[y, x] = (*c, 255)
    for i in range(101):  # the brush, top right to bottom left
        t = i / 100
        x, y = 18.5 - t * 13, 4.5 + t * 14
        if t < 0.55:
            col, w = ((196, 134, 70) if i % 2 else (222, 160, 92)), 1.1
        elif t < 0.7:
            col, w = (206, 212, 222), 1.6
        else:
            col, w = ((255, 232, 150) if t < 0.9 else (255, 250, 220)), 2.3 - (t - 0.7) * 3
        for dy in range(-2, 3):
            for dx in range(-2, 3):
                if dx * dx + dy * dy <= w * w:
                    px, py = int(round(x + dx)), int(round(y + dy))
                    if 3 <= px < 21 and 3 <= py < 21:
                        f[py, px] = (*col, 255)
    for X, Y in ((6, 6), (7, 5), (5, 7), (17, 18), (18, 17)):  # sparks
        f[Y, X] = (255, 255, 255, 255)
    return f


def tubo24():
    """The paint tube piece: the same golden plate, a white tube across it with a red cap and a blob of paint."""
    S = 24
    f = pincel24()
    ys, xs = np.mgrid[0:S, 0:S]
    d = np.maximum(np.abs(xs - 11.5), np.abs(ys - 11.5))
    f[(d <= 8.4)] = (*mezcla((44, 52, 100), (22, 26, 60), 0.5), 255)  # clear the brush: keep plate and border
    for y in range(S):
        for x in range(S):
            if d[y, x] <= 8.4:
                f[y, x] = (*mezcla((44, 52, 100), (22, 26, 60), y / S), 255)
    for i in range(101):  # the tube, bottom left (cap) to top right (crimped end)
        t = i / 100
        x, y = 5.5 + t * 13, 17.5 - t * 12
        if t < 0.16:
            col, w = (210, 48, 40), 1.9
        elif t < 0.86:
            col, w = ((250, 250, 255) if (i % 9) > 1 else (200, 204, 216)), 2.3
            if 0.46 < t < 0.6:
                col = (60, 120, 210)
        else:
            col, w = (160, 168, 184), 1.9 - (t - 0.86) * 4
        for dy in range(-3, 4):
            for dx in range(-3, 4):
                if dx * dx + dy * dy <= w * w:
                    px, py = int(round(x + dx)), int(round(y + dy))
                    if 3 <= px < 21 and 3 <= py < 21:
                        f[py, px] = (*col, 255)
    for X, Y, col in ((4, 19, (255, 220, 60)), (3, 18, (255, 220, 60)), (4, 20, (240, 90, 60)), (6, 20, (80, 170, 240))):
        f[Y, X] = (*col, 255)
    for X, Y in ((17, 17), (18, 16), (6, 6)):
        f[Y, X] = (255, 255, 255, 255)
    return f


def tira(frames):
    return np.concatenate(frames, axis=1)


def guardar(a, name):
    ART.mkdir(parents=True, exist_ok=True)
    Image.fromarray(a, "RGBA").save(ART / f"{name}.png")


def reducir(f, k=2):
    im = Image.fromarray(f, "RGBA")
    pre = np.asarray(im).astype(float)
    a = pre[..., 3:] / 255
    pre[..., :3] *= a
    im2 = Image.fromarray(pre.astype(np.uint8), "RGBA").resize((f.shape[1] // k, f.shape[0] // k), Image.BOX)
    o = np.asarray(im2).astype(float)
    alfa = o[..., 3:] / 255
    rgb = np.where(alfa > 0, o[..., :3] / np.maximum(alfa, 1e-3), 0)
    out = np.concatenate([rgb.clip(0, 255), np.where(alfa >= 0.5, 255, 0)], -1).astype(np.uint8)
    return out


def hacer_gotas():
    grandes = [gota24(c, s) for _, _, c, s in COLORES] + [esponja24(), pincel24(), tubo24()]
    guardar(tira(grandes), "gotas")
    guardar(tira([reducir(g) for g in grandes]), "gotas_s")


# ------------------------------------------------------------------------------------------------------ brush
def hacer_brocha():
    """22x20 doubled to 44x40: handle top right, ferrule, tuft bottom left (frame 0 bare, 1..10 loaded)."""
    marcos = []
    for k in range(len(COLORES) + 1):
        f = np.zeros((20, 22, 4), np.uint8)
        pintura = None if k == 0 else COLORES[k - 1][2]
        for i in range(101):
            t = i / 100
            x, y = 21 - t * 19, 0.5 + t * 17.5
            if t < 0.6:
                col, w = (126, 78, 38) if i % 2 else (150, 98, 50), 1
            elif t < 0.72:
                col, w = (170, 176, 184), 1.5
            else:
                col, w = (pintura if pintura else (214, 188, 138)), 2.4 - (t - 0.72) * 3
                if pintura and t > 0.9:
                    col = mezcla(pintura, (255, 255, 255), 0.2)
            for dy in range(-2, 3):
                for dx in range(-2, 3):
                    if dx * dx + dy * dy <= w * w:
                        px, py = int(round(x + dx)), int(round(y + dy))
                        if 0 <= px < 22 and 0 <= py < 20:
                            f[py, px] = (*col, 255)
        marcos.append(ampliar(f, 2))
    guardar(tira(marcos), "brocha")


# --------------------------------------------------------------------------------------------------- the screen
class Lienzo:
    """The 480x320 canvas in float RGB, with the bits a wooden workshop is made of."""

    def __init__(self, w, h, rng):
        self.a = np.zeros((h, w, 3), np.float32)
        self.w, self.h, self.rng = w, h, rng

    def rect(self, x, y, w, h, c):
        self.a[y:y + h, x:x + w] = c

    def grad_v(self, x, y, w, h, c1, c2):
        t = np.linspace(0, 1, h)[:, None, None]
        self.a[y:y + h, x:x + w] = np.array(c1) * (1 - t) + np.array(c2) * t

    def mul(self, x, y, w, h, k):
        self.a[max(y, 0):y + h, max(x, 0):x + w] *= k

    def sombra(self, x, y, w, h, off=3, k=0.55):
        self.mul(x + off, y + off + 1, w, h, k)
        self.mul(x + off + 1, y + off + 2, w - 1, h - 1, 0.92)

    def ruido(self, x, y, w, h, amp):
        self.a[y:y + h, x:x + w] += self.rng.normal(0, amp, (h, w, 1))

    def madera(self, x, y, w, h, base, tablones=0, vertical=False):
        r = self.rng
        base = np.array(base, np.float32)
        veta = np.cumsum(r.normal(0, 1.1, (h, 1)), 0)
        veta = veta - veta.mean()
        fino = r.normal(0, 3.0, (h, w))
        suave = np.convolve(r.normal(0, 4, w + 30), np.ones(30) / 30, "valid")[:w]
        for j in range(h):
            fila = base + veta[j] * 3 + fino[j][:, None] + suave[:, None] * 0.8
            self.a[y + j, x:x + w] = fila
        for _ in range(w * h // 600):  # darker dashes along the grain
            gx, gy = x + int(r.integers(0, w)), y + int(r.integers(0, h))
            n = int(r.integers(6, 26))
            self.a[gy, gx:min(gx + n, x + w)] *= 0.86
        if tablones:
            for i in range(1, tablones):
                ty = y + i * h // tablones
                self.a[ty, x:x + w] *= 0.55
                self.a[ty + 1, x:x + w] *= 1.12
                self.a[y + (i - 1) * h // tablones:ty, x:x + w] *= 1 + 0.05 * ((i % 2) * 2 - 1)

    def bisel(self, x, y, w, h, g=2, claro=1.28, oscuro=0.6, hundido=False):
        a, b = (oscuro, claro) if hundido else (claro, oscuro)
        for i in range(g):
            self.a[y + i, x + i:x + w - i] *= a
            self.a[y + i:y + h - i, x + i] *= a
            self.a[y + h - 1 - i, x + i:x + w - i] *= b
            self.a[y + i:y + h - i, x + w - 1 - i] *= b

    def tachuela(self, cx, cy):
        for dy in range(-2, 3):
            for dx in range(-2, 3):
                d = dx * dx + dy * dy
                if d <= 5:
                    self.a[cy + dy, cx + dx] = (214, 170, 80) if (dx + dy) < 1 else (130, 92, 36)
        self.a[cy - 1, cx - 1] = (255, 236, 170)

    def marco(self, x, y, w, h, grosor, base=(150, 100, 52), tachuelas=True):
        self.sombra(x, y, w, h, 3, 0.5)
        self.madera(x, y, w, h, base)
        self.bisel(x, y, w, h, 2, 1.32, 0.58)
        ix, iy, iw, ih = x + grosor, y + grosor, w - 2 * grosor, h - 2 * grosor
        self.bisel(ix - 2, iy - 2, iw + 4, ih + 4, 2, 1.0, 1.0)
        self.bisel(ix - 2, iy - 2, iw + 4, ih + 4, 2, 1.25, 0.55, hundido=True)
        if tachuelas:
            for cx, cy in ((x + 5, y + 5), (x + w - 6, y + 5), (x + 5, y + h - 6), (x + w - 6, y + h - 6)):
                self.tachuela(cx, cy)

    def pergamino(self, x, y, w, h, sombra=True):
        if sombra:
            self.sombra(x, y, w, h, 2, 0.6)
        base = np.array((238, 218, 172), np.float32)
        self.rect(x, y, w, h, base)
        self.ruido(x, y, w, h, 3.2)
        yy, xx = np.mgrid[0:h, 0:w]
        d = np.minimum(np.minimum(xx, w - 1 - xx), np.minimum(yy, h - 1 - yy)).astype(np.float32)
        self.a[y:y + h, x:x + w] *= (0.78 + 0.22 * np.clip(d / 7, 0, 1))[..., None]
        b = (118, 78, 44)
        self.rect(x, y, w, 1, b)
        self.rect(x, y + h - 1, w, 1, b)
        self.rect(x, y, 1, h, b)
        self.rect(x + w - 1, y, 1, h, b)
        self.a[y + 2, x + 2:x + w - 2] = (192, 156, 108)
        self.a[y + h - 3, x + 2:x + w - 2] = (192, 156, 108)
        self.a[y + 2:y + h - 2, x + 2] = (192, 156, 108)
        self.a[y + 2:y + h - 2, x + w - 3] = (192, 156, 108)
        for cx, cy in ((x + 3, y + 3), (x + w - 4, y + 3), (x + 3, y + h - 4), (x + w - 4, y + h - 4)):
            self.a[cy, cx] = (150, 104, 58)

    def pozo(self, x, y, w, h, c=(214, 190, 142)):
        self.rect(x, y, w, h, c)
        self.ruido(x, y, w, h, 2.5)
        self.bisel(x, y, w, h, 2, 1.12, 0.74, hundido=True)


def fondo_pared(c):
    h, w = c.h, c.w
    c.grad_v(0, 0, w, h, (46, 64, 118), (18, 28, 66))
    ys, xs = np.mgrid[0:h, 0:w]
    rombo = ((xs // 2 + ys // 2) % 8 == 0) | (((xs // 2 + 4) + (ys // 2 + 4)) % 16 == 0)
    c.a[rombo] *= 1.07
    for x in range(0, w, 40):  # panel seams
        c.a[:, x] *= 0.86
        c.a[:, x + 1] *= 1.1
    c.ruido(0, 0, w, h, 2.2)
    # warm light spilling from above the painting wall
    cx, cy = 300, -20
    d = np.sqrt((xs - cx) ** 2 + ((ys - cy) * 1.5) ** 2)
    c.a += (np.clip(1 - d / 330, 0, 1) ** 2)[..., None] * np.array((60, 44, 18), np.float32)
    # old paint splatters
    r = c.rng
    for _ in range(26):
        sx, sy = int(r.integers(0, w)), int(r.integers(0, 230))
        col = [(170, 60, 56), (206, 170, 60), (62, 110, 170), (80, 150, 90)][int(r.integers(0, 4))]
        rad = int(r.integers(1, 4))
        for yy in range(sy - rad, sy + rad + 1):
            for xx in range(sx - rad, sx + rad + 1):
                if (xx - sx) ** 2 + (yy - sy) ** 2 <= rad * rad and 0 <= xx < w and 0 <= yy < h:
                    c.a[yy, xx] = c.a[yy, xx] * 0.45 + np.array(col) * 0.55


def hacer_fondo():
    rng = np.random.default_rng(11)
    c = Lienzo(480, 320, rng)
    fondo_pared(c)
    box = lambda k: L[k]

    # the bench, with the wall darkened where it meets it
    x, y, w, hh = box("mesa")
    c.grad_v(0, y - 14, w, 14, (0, 0, 0), (0, 0, 0))
    for j in range(14):
        c.a[y - 14 + j] *= 1 - 0.38 * (j / 13) ** 1.5
    c.madera(x, y, w, hh, (122, 80, 44), tablones=4)
    c.a[y:y + 3] *= 1.35
    c.a[y + 3:y + 4] *= 0.7
    c.a[y + 4:y + 40] *= np.linspace(1.0, 0.82, 36)[:, None, None]
    for (px, py, col) in ((6, 304, (200, 50, 44)), (14, 308, (234, 192, 50)), (24, 305, (44, 94, 182)),
                          (240, 309, (70, 160, 76)), (440, 304, (234, 192, 50)), (462, 309, (200, 50, 44))):
        c.rect(px, py, 8, 3, col)
        c.rect(px + 2, py - 1, 5, 1, col)
        c.rect(px + 1, py + 3, 6, 1, np.array(col) * 0.6)

    # board well: frame, inset, cells like sockets
    x, y, w, hh = box("tablero_marco")
    c.marco(x, y, w, hh, 6, (146, 98, 52))
    cx, cy, cw, ch = box("celdas")
    c.rect(cx - 2, cy - 2, cw + 4, ch + 4, (10, 11, 17))
    c.bisel(cx - 2, cy - 2, cw + 4, ch + 4, 2, 1.0, 1.0)
    for j in range(L_FILAS):
        for i in range(L_COLS):
            x0, y0 = cx + i * CELDA, cy + j * CELDA
            base = (30, 33, 44) if (i + j) % 2 else (24, 26, 36)
            c.grad_v(x0 + 1, y0 + 1, CELDA - 2, CELDA - 2, np.array(base) * 0.85, np.array(base) * 1.18)
            c.a[y0 + 1, x0 + 1:x0 + CELDA - 1] *= 0.6
            c.a[y0 + CELDA - 2, x0 + 1:x0 + CELDA - 1] *= 1.35
            c.a[y0 + 1:y0 + CELDA - 1, x0 + 1] *= 0.75
            for k in (0, 1):  # rounded corners
                for e in (0, 1):
                    c.a[y0 + 1 + k * (CELDA - 3), x0 + 1 + e * (CELDA - 3)] = (12, 13, 20)
    c.a[cy - 2:cy + ch + 2, cx + cw // 2 - 1:cx + cw // 2 + 1] *= 1.0

    # message plank
    x, y, w, hh = box("mensaje")
    c.sombra(x, y, w, hh, 2, 0.5)
    c.madera(x, y, w, hh, (88, 56, 32))
    c.bisel(x, y, w, hh, 2, 1.3, 0.6)
    c.rect(x + 3, y + 3, w - 6, hh - 6, (14, 14, 22))
    c.bisel(x + 3, y + 3, w - 6, hh - 6, 1, 0.7, 1.2)
    # stock cabinet
    x, y, w, hh = box("reserva")
    c.marco(x, y, w, hh, 4, (112, 74, 40), tachuelas=False)
    c.rect(x + 4, y + 4, w - 8, hh - 8, (38, 26, 20))
    c.bisel(x + 4, y + 4, w - 8, hh - 8, 2, 0.6, 1.25)
    for fila in range(4):
        c.a[y + 28 + fila * 13, x + 6:x + w - 6] *= 0.7

    # the paintings
    for marco, lienzo in (("obra_marco", "obra"), ("rest_marco", "rest")):
        x, y, w, hh = box(marco)
        c.marco(x, y, w, hh, 6, (170, 118, 54))
        ox, oy, ow, oh = box(lienzo)
        c.rect(ox - 2, oy - 2, ow + 4, oh + 4, (232, 208, 156))  # passe-partout
        c.bisel(ox - 2, oy - 2, ow + 4, oh + 4, 1, 0.75, 1.2, hundido=True)
        c.rect(ox - 1, oy - 1, ow + 2, oh + 2, (16, 10, 6))

    # the tray
    x, y, w, hh = box("mezcla")
    c.marco(x, y, w, hh, 5, (142, 94, 50))
    c.pergamino(x + 5, y + 5, w - 10, hh - 10, sombra=False)
    for k in ("ing_a", "ing_b", "res"):
        sx, sy, sw, sh = box(k)
        c.pozo(sx, sy, sw, sh - 4)
    sx, sy, sw, sh = box("res")
    c.a[sy + 2:sy + sh - 6, sx + 2:sx + sw - 2] *= np.array((1.04, 1.0, 0.92))
    # the brush pad
    x, y, w, hh = box("pincel")
    c.pergamino(x, y, w, hh)
    for i in range(1, w - 1, 3):
        c.a[y + hh - 2, x + i] = (176, 148, 106)
    # objectives
    x, y, w, hh = box("obj_marco")
    c.marco(x, y, w, hh, 5, (142, 94, 50))
    c.pergamino(x + 5, y + 5, w - 10, hh - 10, sombra=False)
    for sx, sy, sw, sh in OBJ_SLOT:
        c.pozo(sx, sy, sw, 34)
    # water glass
    x, y, w, hh = box("vaso")
    c.sombra(x, y, w, hh, 3, 0.5)
    c.rect(x, y, w, hh, (206, 228, 232))
    c.grad_v(x + 2, y + 2, w - 4, hh - 4, (86, 160, 190), (40, 100, 140))
    c.rect(x + 2, y + 2, w - 4, 7, (170, 210, 224))
    c.a[y + 9, x + 2:x + w - 2] = (214, 238, 244)
    c.rect(x + 4, y + 12, 2, hh - 22, (210, 238, 246))
    c.bisel(x, y, w, hh, 1, 1.1, 0.7)
    # plaques
    for k in ("nivel", "mov", "mezcla_titulo", "obj_titulo", "obra_titulo"):
        c.pergamino(*box(k))
    # corner vignette and a touch of grain over everything
    ys, xs = np.mgrid[0:320, 0:480]
    d = np.sqrt(((xs - 240) / 280) ** 2 + ((ys - 160) / 200) ** 2)
    c.a *= (1.04 - 0.30 * np.clip(d - 0.35, 0, 1.2) ** 1.4)[..., None]
    c.a += rng.normal(0, 1.4, (320, 480, 1))
    out = np.clip(c.a, 0, 255).astype(np.uint8)
    Image.fromarray(out, "RGB").save(ART / "fondo.png")


# ------------------------------------------------------------------------------------------------------ painting
OBRA_W, OBRA_H = 152, 104


def lum_arr(rgb):
    return rgb[..., 0] * 0.3 + rgb[..., 1] * 0.59 + rgb[..., 2] * 0.11


def moda(cl, k):
    """3x3 majority filter, so the regions are blobs and not salt and pepper."""
    h, w = cl.shape
    p = np.pad(cl, 1, mode="edge")
    votos = np.zeros((k, h, w), np.int32)
    for dy in range(3):
        for dx in range(3):
            v = p[dy:dy + h, dx:dx + w]
            for i in range(k):
                votos[i] += v == i
    return votos.argmax(0)


def noche(im, cl, regiones):
    """Starry Night has no orange of its own: the darker half of its yellows (the glows' ochre rims) is the orange."""
    nombres = [n for n, _ in regiones]
    amar, nar = nombres.index("amarillo"), nombres.index("naranja")
    luz = lum_arr(np.asarray(im).astype(float))
    ambar = cl == amar
    cl[ambar & (luz < np.percentile(luz[ambar], 50))] = nar
    return cl


def nenufares(im, cl, regiones):
    """The pond is mostly water: the darker third of it is the deep blue region."""
    nombres = [n for n, _ in regiones]
    azul, marino = nombres.index("azul"), nombres.index("marino")
    luz = lum_arr(np.asarray(im).astype(float))
    agua = cl == azul
    cl[agua & (luz < np.percentile(luz[agua], 35))] = marino
    return cl


def realce_nenufares(im):
    im = ImageEnhance.Color(im).enhance(2.0)
    im = ImageEnhance.Contrast(im).enhance(1.35)
    return ImageEnhance.Brightness(im).enhance(1.05)


def realce_noche(im):
    im = ImageEnhance.Brightness(im).enhance(1.18)
    im = ImageEnhance.Color(im).enhance(1.6)
    im = ImageEnhance.Contrast(im).enhance(1.2)
    px = np.asarray(im).astype(float)
    amarillo = (px[..., 0] > 150) & (px[..., 1] > 130) & (px[..., 2] < 150)  # lift the yellows: stars and moon glow
    px[amarillo] *= np.array([1.05, 1.03, 0.9])
    return Image.fromarray(px.clip(0, 255).astype(np.uint8))


def realce_ola(im):
    im = ImageEnhance.Color(im).enhance(1.35)
    return ImageEnhance.Contrast(im).enhance(1.15)


# one entry per painting. regiones: (the pigment that restores it, an RGB to match pixels to), region id = position + 1.
# recorte: how to cut the source to our 152x104 frame (x0 fraction of the spare width, y0 in source pixels)
OBRAS = [
    {"id": "noche", "fuente": ROOT / "refs" / "fuentes" / "van_gogh_noche_estrellada_1889_GAC.jpg", "y0": 40,
     "x0": 0.0, "colores": 48, "realce": realce_noche, "post": noche,
     "regiones": [("azul", (40, 95, 175)), ("celeste", (120, 175, 225)), ("marino", (18, 35, 95)),
                  ("verde", (35, 60, 40)), ("amarillo", (235, 200, 60)), ("naranja", (215, 140, 45))]},
    {"id": "ola", "fuente": ROOT / "refs" / "fuentes" / "hokusai_gran_ola_1831_Met.jpg", "y0": 0,
     "x0": 0.5, "colores": 40, "realce": realce_ola, "post": None,
     "regiones": [("marino", (25, 45, 95)), ("azul", (50, 100, 150)), ("celeste", (130, 170, 190)),
                  ("blanco", (228, 236, 238)), ("amarillo", (236, 220, 172)), ("naranja", (198, 158, 102))]},
    {"id": "nenufares", "fuente": ROOT / "refs" / "fuentes" / "monet_nenufares_1906_AIC.jpg", "y0": 160,
     "x0": 0.0, "colores": 44, "realce": realce_nenufares, "post": nenufares,
     "regiones": [("azul", (50, 120, 200)), ("marino", (30, 80, 130)), ("celeste", (120, 190, 235)),
                  ("verde", (50, 135, 105)), ("amarillo", (185, 215, 150)), ("violeta", (150, 90, 150))]},
]


def hacer_obra(o):
    ident, regiones = o["id"], o["regiones"]
    im = Image.open(o["fuente"]).convert("RGB")
    w, h = im.size
    cw, ch = min(w, int(h * OBRA_W / OBRA_H)), min(h, int(w * OBRA_H / OBRA_W))
    x0 = int((w - cw) * o["x0"])
    im = im.crop((x0, o["y0"], x0 + cw, o["y0"] + ch)).resize((OBRA_W, OBRA_H), Image.BOX)
    im = o["realce"](im).quantize(colors=o["colores"], method=Image.Quantize.MEDIANCUT,
                                  dither=Image.Dither.NONE).convert("RGB")  # pixel art: few colours
    a = np.asarray(im).astype(float)
    cs = np.array([c for _, c in regiones], float)
    cl = moda(((a[:, :, None, :] - cs[None, None]) ** 2).sum(-1).argmin(-1), len(regiones))
    if o["post"]:
        cl = o["post"](im, cl, regiones)
    rgb = np.asarray(im)
    gris = lum_arr(rgb)
    pergamino = np.stack([gris * 0.9 + 70, gris * 0.82 + 60, gris * 0.64 + 48], -1).clip(0, 255).astype(np.uint8)
    Image.fromarray(pergamino, "RGB").convert("RGBA").save(ART / f"obra_{ident}_gris.png")
    for i in range(len(regiones)):
        capa = np.zeros((OBRA_H, OBRA_W, 4), np.uint8)
        m = cl == i
        capa[m, :3] = rgb[m]
        capa[m, 3] = 255
        Image.fromarray(capa, "RGBA").save(ART / f"obra_{ident}_{i + 1}.png")
    filas = []  # hit grid: majority region of each 4x4 block
    for by in range(OBRA_H // 4):
        s = ""
        for bx in range(OBRA_W // 4):
            blk = cl[by * 4:by * 4 + 4, bx * 4:bx * 4 + 4].ravel()
            s += str(np.bincount(blk, minlength=len(regiones)).argmax() + 1)
        filas.append(s)
    return filas, [int((cl == i).sum()) for i in range(len(regiones))]


def escribir_layout(obras):
    def tabla(d):
        return "{" + ", ".join(f"{k} = {{{', '.join(map(str, v))}}}" for k, v in d.items()) + "}"

    cols = ",\n  ".join(
        f'{{clave = "{k}", nombre = "{n}", rgb = 0x{c[0]:02X}{c[1]:02X}{c[2]:02X}}}' for k, n, c, _ in COLORES)
    slots = ", ".join("{" + ", ".join(map(str, s)) + "}" for s in OBJ_SLOT)
    bloques = []
    for o, (grid, tam) in obras:
        reg = ", ".join(f'"{k}"' for k, _ in o["regiones"])
        lineas = ",\n      ".join(f'"{g}"' for g in grid)
        bloques.append(
            f"    {o['id']} = {{\n"
            f"      regiones = {{{reg}}}, -- region id -> the colour that restores it\n"
            f"      region_px = {{{', '.join(map(str, tam))}}},\n"
            f"      rejilla = {{ -- the painting in 4x4 blocks: each character a region id\n      {lineas},\n      }},\n    }},")
    (GAME / "layout.lua").write_text(
        "-- made by tools/art.py: the canonical UI's boxes (480x320), the colours and each painting's regions. Do not edit.\n"
        "return {\n"
        f"  caja = {tabla(L)},\n"
        f"  celda = {CELDA}, cols = {COLS}, filas = {FILAS},\n"
        f"  slots_obj = {{{slots}}},\n"
        f"  colores = {{\n  {cols},\n  }},\n"
        f"  obra_w = {OBRA_W}, obra_h = {OBRA_H},\n"
        "  obras = {\n" + "\n".join(bloques) + "\n  },\n"
        "}\n")


if __name__ == "__main__":
    ART.mkdir(parents=True, exist_ok=True)
    hacer_gotas()
    hacer_brocha()
    hacer_fondo()
    if all(o["fuente"].exists() for o in OBRAS):
        hechas = [(o, hacer_obra(o)) for o in OBRAS]
        escribir_layout(hechas)
        for o, (_, tam) in hechas:
            print(o["id"], "regions (px):", dict(zip([k for k, _ in o["regiones"]], tam)))
    else:
        print("no refs/fuentes: the paintings (art/obra_*.png) and layout.lua stay as they are (CROMOTA_REFS=dir to cut them again)")
