"""The six cooks: proportions, palettes, clothes, heads, props and weapons (appearance is data + drawing hooks)."""
from __future__ import annotations

import math

from chefbase import FLOOR, WHITE, Chef, Fig, Mat, add, hp, hpts, lerp, polar, rot, tpts

# ------------------------------------------------------------------ shared material ramps
GOLD = Mat("#6a3a10", "#c27a1c", "#f2b630", "#ffe27a", "#fffbd0")
STEEL = Mat("#3a3c58", "#7e86a8", "#c2cae0", "#eef4ff", "#ffffff")
KWOOD = Mat("#3a1a12", "#5e2c1a", "#8a4424", "#b0662e")
LEATHER = Mat("#3c1c14", "#6e3420", "#9c5228", "#c47a3a")


def legend_base(chef):
    m = chef.mats
    return {
        "k": m["hair"].line, "b": m["hair"].ramp[0], "B": m["hair"].ramp[1],
        "w": "#fffdf6", "W": "#d8d4e8", "p": chef.eye, "P": "#1c1020",
        "s": m["skin"].ramp[0], "S": m["skin"].ramp[1], "L": m["skin"].ramp[2], "x": m["skin"].line,
        "r": chef.lip, "R": chef.lip2, "h": chef.blush, "o": "#2a1420", "t": "#fffdf6",
    }


EYES = {
    # near eye block 3x3 at (ex, ey), far eye 2x3 at (fx, fy)
    "open": (["kkkk", "wwpk", ".wp."], ["kk", "pk", "p."]),
    "cool": (["kkkk", "kwpk", "...."], ["kk", "pk", ".."]),
    "wide": (["kkkk", "wwpk", "wwpk", ".ww."], ["kk", "pk", "pk"]),
    "blink": (["....", "kkkk", "...."], ["..", "kk", ".."]),
    "shut": (["....", "kkkk", ".kk."], ["..", "kk", ".."]),
    "angry": (["....", "kkkk", "wwpk"], ["..", "kk", "pk"]),
    "x": (["k.k", ".k.", "k.k"], ["k.", ".k", "k."]),
    "spiral": (["kkk", "kwk", "kkk"], ["kk", "kk", ".."]),
    "up": (["kkk", "wPp", "ww."], ["kp", "k.", ".."]),
}

MOUTHS = {
    "smile": ["x...x", ".xxx."],
    "smirk": ["....x", ".xxx."],
    "grin": ["xxxxx", "xtttx", ".xxx."],
    "open": [".xxx.", "xooox", ".xxx."],
    "o": [".x.", "xox", ".x."],
    "grit": ["xxxxx", "xtxtx", "xxxxx"],
    "frown": [".xxx.", "x...x"],
    "flat": ["xxxx"],
    "yell": ["xxxxx", "xooox", "xooox", ".xxx."],
    "lips": [".rr.", "rRRr", ".rr."],
    "lipsmile": ["r...r", ".rRr."],
    "lipo": [".r.", "rPr", ".r."],
    "biggrin": ["xxxxxxx", "xtttttx", ".xRRRx.", "..xxx.."],
    "biggrin2": ["xxxxxxx", "xtttttx", "xtttttx", ".xxxxx."],
    "bigopen": [".xxxxx.", "xtttttx", "xoooRRx", "xooRRRx", ".xxxxx."],
    "lipyell": [".rr.", "rPPr", "rPPr", ".rr."],
    "lipgrit": ["rrrr", "tttt", "rRRr"],
    "lipgrin": ["r..r", "tttt", ".rr."],
}


class FaceGeom:
    """Where a cook's face features sit, relative to the head centre (1x pixels), and their brow stamps."""
    EYE_N = (2, -2)
    EYE_F = (7, -2)
    BROW = ([".bbb", "b..."], (1, -5), ["bb"], (7, -4))
    BROW_ANGRY = (["bb...", "..bb."], (1, -4), ["b.", "b"], (7, -4))
    NOSE = (["s", "x"], (8, 1))
    MOUTH_R = (7, 5)
    BLUSH = (["hh"], (2, 3))
    EYESET: dict = {}


def draw_face(chef, cv, f, head, extra=None):
    L = legend_base(chef)
    if extra:
        L.update(extra)
    eyes, mouth = f.face
    ne, fe = chef.EYESET[eyes] if eyes in chef.EYESET else EYES[eyes]
    hx, hy = f.head
    br = chef.BROW_ANGRY if eyes == "angry" else chef.BROW
    if br:
        cv.stamp(br[0], hx + br[1][0], hy + br[1][1], L, head)
        cv.stamp(br[2], hx + br[3][0], hy + br[3][1], L, head)
    cv.stamp(ne, hx + chef.EYE_N[0], hy + chef.EYE_N[1], L, head)
    if fe:
        cv.stamp(fe, hx + chef.EYE_F[0], hy + chef.EYE_F[1], L, head)
    if chef.NOSE:
        cv.stamp(chef.NOSE[0], hx + chef.NOSE[1][0], hy + chef.NOSE[1][1], L, head)
    rows = MOUTHS[chef.MOUTH_MAP.get(mouth, mouth)]
    cv.stamp(rows, hx + chef.MOUTH_R[0] - len(rows[0]) + 1, hy + chef.MOUTH_R[1], L, head)
    if chef.BLUSH:
        cv.stamp(chef.BLUSH[0], hx + chef.BLUSH[1][0], hy + chef.BLUSH[1][1], L, head)


def head_shapes(f, rx, ry, jaw=(3.4, 3.6, 5.4, 5.2), nose=(8.3, 1.0, 1.5), cy=-0.5):
    s = [("ell", *hp(f, (0.0, cy)), rx, ry, f.head_tilt), ("ell", *hp(f, jaw[:2]), jaw[2], jaw[3], f.head_tilt)]
    if nose:
        s.append(("circ", *hp(f, nose[:2]), nose[2]))
    return s


def lie_post(ang, lift=None, extra=None, dx=0.0):
    """A post-render hook: rotate the whole figure about the pelvis, then settle it on the floor (or lift it)."""
    def post(cv, f, chef):
        cv.transform(angle=ang, pivot=f.pel)
        if lift is None:
            cv.settle(FLOOR)
        else:
            cv.shift(0, lift)
        if dx:
            cv.shift(dx, 0)
        if extra:
            extra(cv, f, chef)
    return post


class Estrella(FaceGeom, Chef):
    """Chef Estrella: slim, elegant, tall pleated toque, double-breasted white jacket with three gold stars on the
    collar, navy trousers, a knife roll strapped across the chest. Throws knives. Glides."""

    id = "estrella"
    D = dict(hip_y=24.0, thigh=14.0, shin=13.5, ankle_h=4.0, foot=10.0, leg_r=(4.3, 3.5, 2.8), hip_dx=1.4,
             shoulder=(1.0, -27.5), sh_back=1.5, neck=(2.0, -30.0), head_off=(1.8, -10.5),
             upper=9.5, fore=9.0, arm_r=(3.1, 2.8, 2.1))
    eye, lip, lip2, blush = "#25536a", "#b8283a", "#e2485a", "#f08a7e"
    STYLE = dict(Chef.STYLE, stride=8.5, lift=7.5, kick=4.0, bob=1.0, lean_run=0.12, crouch_drop=5.0, crouch_lean=0.42)
    AIM = {
        "rest": dict(n=(7, 8), a=0.15, f=("s", (2.0, 8.0))),
        "run": dict(n=(9, 8), a=0.25, f=("s", (-1.0, 10.0))),
        "fwd": dict(n=(12, 2), a=0.0, f=("s", (1.0, 11.0))),
        "up": dict(n=(14, -11), a=-1.50, f=("s", (1.0, 11.0))),
        "down": dict(n=(10, 0), a=1.45, f=("s", (1.0, 11.0))),
        "crouch": dict(n=(15, -2), a=0.0, f=("s", (7.0, 0.0))),
        "crouch_rest": dict(n=(12, 0), a=0.2, f=("s", (7.0, 0.0))),
    }
    RECOIL = (-2.5, 1.5, 0.5)
    MOUTH_MAP = {"smile": "lipsmile", "smirk": "lipsmile", "open": "lipo", "o": "lipo", "yell": "lipyell",
                 "grit": "lipgrit", "grin": "lipgrin"}
    KICK = (0.30, -0.12, 0.0)

    def __init__(self):
        super().__init__()
        self.mats = dict(
            skin=Mat("#5e2a26", "#c87a5c", "#efae88", "#ffd5b4", "#fff0dc"),
            hair=Mat("#1e0f1a", "#3a1a2a", "#5e2c3e", "#8a4658"),
            jacket=WHITE,
            trousers=Mat("#141a3a", "#232e66", "#34489a", "#5068c0"),
            boot=Mat("#2c0c14", "#5a1624", "#8a2434", "#c0404a", "#f07a7a"),
            gold=GOLD, steel=STEEL, kwood=KWOOD, leather=LEATHER,
            toque=Mat("#6c5a6e", "#c3bfd6", "#eeebf4", "#fffdf6", "#ffffff"),
        )

    # -------------------------------------------- body
    def draw_torso(self, cv, f: Fig):
        m = self.mats
        c = f.cloth
        hem = 2.5
        pts = [(-6.5, -29.5), (-8.5, -24.0), (-7.6, -15.0), (-6.4, -8.0), (-7.6 - c, -1.0), (-8.6 - 1.5 * c, hem),
               (9.6 - 0.5 * c, hem), (8.6, -1.0), (7.0, -8.0), (9.0, -16.0), (10.2, -22.0), (8.0, -28.5), (3.0, -30.8)]
        body = cv.part("jacket", m["jacket"], [("poly", tpts(f, pts))], kind="body", R=5.0)
        # double-breast flap line, buttons (gold), and the waist cinch
        flap = tpts(f, [(2.2, -27.0), (8.0, -20.0), (6.3, -8.5), (7.5, 3.0)])
        cv.paint([("cap", *flap[0], *flap[1], 0.45, 0.45), ("cap", *flap[1], *flap[2], 0.45, 0.45),
                  ("cap", *flap[2], *flap[3], 0.45, 0.45)], color=m["jacket"].ramp[0], within=[body])
        for (bx, by) in ((1.5, -21.0), (5.0, -21.5), (1.5, -15.5), (4.5, -15.5), (1.6, -10.0), (4.2, -10.0)):
            p = f.T((bx, by))
            cv.stamp(["g"], round(p[0]), round(p[1]), {"g": GOLD.ramp[1]}, body)
        # the knife roll: a leather strap from the back shoulder to the front hip, knife handles in its pockets
        a, b = f.T((-5.0, -27.5)), f.T((6.5, -6.0))
        strap = cv.part("strap", m["leather"], [("cap", *a, *b, 1.6, 1.6)], kind="body", R=1.2,
                        clip=[("poly", tpts(f, pts))])
        ang = math.atan2(b[1] - a[1], b[0] - a[0])
        for t in (0.28, 0.48, 0.68):
            p = lerp(a, b, t)
            q0, q1 = add(p, polar(ang - math.pi / 2, 1.6)), add(p, polar(ang - math.pi / 2, 4.6))
            cv.part("handle", m["kwood"], [("cap", *q0, *q1, 1.0, 1.0)], kind="body", R=0.8, weight=2)
            cv.stamp(["s"], round(q1[0] + 0.3), round(q1[1] - 0.4), {"s": STEEL.ramp[2]}, strap)

    def draw_lower_clothes(self, cv, f):
        pass

    # -------------------------------------------- head
    def draw_head(self, cv, f: Fig):
        m = self.mats
        self.neck_part(cv, f, 2.4)
        # collar: a band around the neck with three gold stars
        cl = tpts(f, [(-3.0, -31.5), (5.5, -31.5), (6.5, -28.0), (-3.5, -27.5)])
        collar = cv.part("collar", m["jacket"], [("poly", cl)], kind="upper", R=1.5)
        for (sx, sy) in ((0.0, -30.6), (2.6, -30.4), (5.0, -30.0)):
            p = f.T((sx, sy))
            cv.stamp([".g.", "gYg", ".g."], round(p[0]) - 1, round(p[1]) - 1, {"g": GOLD.ramp[1], "Y": GOLD.ramp[3]}, collar)
        # skull, jaw and nose
        hs = [("ell", *hp(f, (0.0, -0.5)), 9.0, 9.8, f.head_tilt), ("ell", *hp(f, (3.4, 3.6)), 5.4, 5.2, f.head_tilt),
              ("circ", *hp(f, (8.3, 1.0)), 1.5)]
        head = cv.part("head", m["skin"], hs, kind="upper", R=4.0)
        cv.part("ear", m["skin"], [("ell", *hp(f, (-2.6, 0.8)), 1.6, 2.2, f.head_tilt)], kind="upper", R=1.5)
        # sleek hair, swept to a low bun under the toque
        hair = [("poly", hpts(f, [(-9.4, -2.0), (-7.6, -8.2), (0.0, -10.6), (7.0, -8.6), (8.6, -5.2), (5.0, -6.2),
                                  (1.0, -4.6), (-2.6, -2.6), (-4.4, 0.0), (-4.6, 4.0), (-7.0, 5.6), (-9.2, 3.6)])),
                ("circ", *hp(f, (-8.6, 3.6)), 3.4)]
        cv.part("hair", m["hair"], hair, kind="upper", R=3.0)
        self.draw_face(cv, f, head)
        self.draw_toque(cv, f)

    def draw_face(self, cv, f, head):
        draw_face(self, cv, f, head)

    def draw_toque(self, cv, f):
        if f.P.get("nohat"):
            return
        dx, dy, tl = f.hat
        t = f.head_tilt + tl - 0.08
        base = add(hp(f, (0.0, -7.2)), (dx, dy))
        self.draw_hat(cv, base, t, dx * 0.3, dy * 0.3)

    def draw_hat(self, cv, base, t, dx=0.0, dy=0.0):
        m = self.mats
        top = add(base, rot((-1.2 + dx, -13.0 + dy), t))
        band = [("poly", [add(base, rot(p, t)) for p in [(-7.2, -1.0), (7.4, -1.0), (7.2, 2.6), (-7.4, 2.6)]])]
        puff = [("poly", [add(base, rot(p, t)) for p in [(-7.0, -0.5), (7.2, -0.5), (8.2 + dx * 0.3, -9.0), (-8.0, -9.0)]]),
                ("ell", *top, 8.6, 4.2, t)]
        tq = cv.part("toque", m["toque"], puff, kind="upper", R=4.5)
        for k in (-4.4, -1.0, 2.6, 5.8):
            p0 = add(base, rot((k * 0.95, -1.0), t))
            p1 = add(base, rot((k * 1.15 - 0.4, -13.0), t))
            cv.paint([("cap", *p0, *p1, 0.5, 0.5)], color=m["toque"].ramp[0], within=[tq])
        cv.part("tband", m["toque"], band, kind="upper", R=1.5, bias=-0.05)

    # -------------------------------------------- full-body frames
    def full_die(self, i):
        """Spins backwards, the toque pops off and flies, she lands flat on her back; the toque lands upright on her."""
        lie = dict(feet=((3, 0, 0), (-2, 0, 0)), hn=(6, 4), hf=(-6, 6), an=-0.4, af=2.6, items=("weapon", "open"))
        if i == 0:
            P = self.mk(dpel=(-3, 1), lean=-0.30, feet=((7, 2, -0.3), (-6, 0, 0)), hn=(8, -10), hf=(-9, -6), an=-1.4,
                        af=-2.6, items=("weapon", "open"), face=("x", "lipyell"), head=(-0.4, -1, 0), hat=(-2, -6, -0.4),
                        cloth=1.0, elbow=(-1, 1))
            return P, None
        spins = {1: (-0.7, -6, (-6, -26), 0.9), 2: (-1.5, -12, (-10, -40), 2.2), 3: (-2.3, -10, (-12, -40), 3.6),
                 4: (-1.57, None, (-16, -38), 4.9), 5: (-1.57, None, (-18, -18), 5.9), 6: (-1.57, None, (-1, 0), 6.28),
                 7: (-1.57, None, (-1, 0), 6.28)}
        ang, lift, hat, hat_t = spins[i]
        face = ("x", "lipo") if i < 6 else ("x", "lipgrin")
        if i == 5:
            P = self.mk(feet=((9, 6, -0.6), (6, 9, -0.3)), hn=(4, -12), hf=(-2, -12), an=-1.6, af=-1.8, items=("weapon", "open"),
                        face=("x", "lipo"), nohat=True, elbow=(-1, 1))
        else:
            P = self.mk(face=face, nohat=True, **lie)
        sx, sy = self.D["hip_y"], 0

        def post(cv, f, chef, ang=ang, lift=lift, hat=hat, hat_t=hat_t, i=i):
            cv.transform(angle=ang, pivot=f.pel)
            if lift is None:
                cv.settle(FLOOR)
            else:
                cv.shift(0, lift)
            if i >= 6:   # the toque has landed upright on her chest
                rows = (cv.pid >= 0).any(1).nonzero()[0]
                top = rows[0] / 4 - cv.oy
                chef.draw_hat(cv, (2.0, top + 1.5), 0.0)
            else:
                chef.draw_hat(cv, hat, hat_t)
        return P, post

    def full_win(self, i):
        hop = [0, -3, -5, -3, 0, 1][i]
        h = max(0.0, -hop - 1)
        P = self.mk(dpel=(0, hop), lean=-0.16, feet=((5, h, 0.2 if h else 0), (-5, h * 0.8, 0.3 if h else 0)),
                    hn=(14, -15 + [0, 1, 2, 1, 0, -1][i]), an=-1.3 + [0, 0.2, 0.4, 0.2, 0, -0.1][i], hf=(1, 11), af=0.6,
                    face=("shut", "lipgrin") if i % 3 else ("cool", "lipsmile"), hat=(0, [0, 2, 3, 1, -1, -1][i], 0.04),
                    cloth=[0, -0.4, -0.8, -0.4, 0.2, 0.3][i], elbow=(-1, -1))
        return P, None

    def full_select(self, i):
        spin = [0.0, -1.6, -3.14, -4.7][i]
        P = self.mk(lean=-0.04, feet=((4, 0, 0), (-4, 0, 0)), hn=(9, 3), an=spin, hf=(1, 11), face=("cool", "smirk"),
                    hat=(0, [0, -0.5, 0, 0.5][i], 0), head=(-0.06, 0, 0))
        return P, None

    # -------------------------------------------- weapon: a fan of throwing knives
    def draw_weapon(self, cv, f, wr, ang, far):
        c = add(wr, polar(ang, 2.6))
        for k, da in enumerate((-0.42, 0.0, 0.42)):
            a2 = ang + da
            h0, h1 = add(c, polar(a2, -3.0)), add(c, polar(a2, 1.5))
            cv.part("tkH", KWOOD, [("cap", *h0, *h1, 1.1, 1.1)], kind="upper", R=0.8, weight=2)
            b0, b1 = add(c, polar(a2, 1.5)), add(c, polar(a2, 10.5))
            cv.part("tkB", STEEL, [("cap", *b0, *b1, 1.7, 0.4)], kind="upper", R=1.2, weight=3, tilt=(0, -0.4))

    def muzzle(self, f):
        return add(f.wr_n, polar(f.hang[0], 12.0))

