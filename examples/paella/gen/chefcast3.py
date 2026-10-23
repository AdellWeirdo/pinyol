"""El Maestro Arrocero (rice master with the ladle and the paellera shield), Doña Brioche (pastry chef with the cream gun)
and El Sumiller Don Crianza (sommelier with the cava bottle)."""
from __future__ import annotations

import math

from chefbase import FLOOR, WHITE, Chef, Fig, Mat, add, hp, hpts, lerp, polar, rot, tpts
from chefcast import GOLD, KWOOD, LEATHER, STEEL, FaceGeom, draw_face, head_shapes
from chefcast2 import IRON, FOAM, foam_puffs

CREAM = Mat("#9a7a8a", "#f2dcd0", "#fff4ec", "#ffffff")
RICE = Mat("#8a6010", "#e8b628", "#ffd84a", "#fff2a0")


def settle_pos(cv, f, ang, p):
    """Where world point p of the figure ends after cv.transform(ang about the pelvis) and cv.settle(FLOOR)."""
    q = rot((p[0] - f.pel[0], p[1] - f.pel[1]), ang)
    return (q[0] + f.pel[0], q[1] + f.pel[1])


def lie(cv, f, ang, lift=None, dx=0.0):
    cv.transform(angle=ang, pivot=f.pel)
    before = (cv.pid >= 0).any(1).nonzero()[0]
    low0 = (before[-1] + 1) / 4 - cv.oy if len(before) else FLOOR
    if lift is None:
        cv.settle(FLOOR)
        dy = FLOOR - low0
    else:
        cv.shift(0, lift)
        dy = lift
    if dx:
        cv.shift(dx, 0)
    return dy


# ====================================================================== EL MAESTRO ARROCERO

class Arrocero(FaceGeom, Chef):
    """Old proud rice master: straw hat, big grey moustache, black waistcoat, red sash, espadrilles, the paellera
    strapped on his back as a shield. A long wooden ladle that flings rice and hot oil. Dignified and grumpy."""

    id = "arrocero"
    D = dict(hip_y=25.0, thigh=13.4, shin=12.8, ankle_h=3.8, foot=10.0, leg_r=(4.1, 3.3, 2.5), hip_dx=1.4,
             shoulder=(0.0, -26.5), sh_back=1.8, neck=(1.5, -29.0), head_off=(3.0, -10.0),
             upper=9.0, fore=8.6, arm_r=(3.0, 2.7, 2.1))
    eye, lip, lip2, blush = "#2a2a3a", "#a03030", "#c84848", "#e07a6a"
    STYLE = dict(Chef.STYLE, stride=6.5, lift=6.0, kick=2.5, bob=1.0, lean_idle=0.06, lean_run=0.16, crouch_drop=4.5,
                 crouch_lean=0.40)
    AIM = {
        "rest": dict(n=(7, 5), a=-2.35, f=("s", (3.0, 8.0))),
        "run": dict(n=(10, 5), a=-0.35, f=("w", 3.5, 1.0)),
        "fwd": dict(n=(10, 4), a=0.0, f=("w", 4.5, 0.5)),
        "up": dict(n=(13, -11), a=-1.45, f=("w", -4.0, 0.5)),
        "down": dict(n=(10, -5), a=1.45, f=("s", (3.0, 9.0)), choke=11.0),
        "crouch": dict(n=(13, -2), a=0.0, f=("w", 4.5, 0.5)),
        "crouch_rest": dict(n=(12, -1), a=-0.6, f=("s", (7.0, 0.0))),
    }
    RECOIL = (-2.0, 1.5, 0.5)
    KICK = (0.22, -0.15, -0.05)
    FACE = dict(idle=("squint", "frown"), aim=("angry", "flat"), run=("angry", "flat"), jump=("open", "o"),
                fire=("angry", "grit"))
    EYESET = {
        "squint": (["bbbb", "kkkk", "...."], ["bb", "kk", ".."]),
        "open": (["bbbb", "kwpk", ".kk."], ["bb", "pk", ".."]),
        "angry": (["bb..", "kbbb", "kwpk"], ["bb", "kk", "pk"]),
        "cool": (["bbbb", "kkpk", "...."], ["bb", "pk", ".."]),
        "spiral": (["bbbb", "kwk.", "kkk."], ["bb", "kk", ".."]),
    }
    EYE_N, EYE_F = (1, -3), (7, -3)
    BROW = None
    BROW_ANGRY = None
    NOSE = None
    MOUTH_R = (9, 6)
    BLUSH = None
    MOUTH_MAP = {"smile": "flat", "grin": "grit", "yell": "open"}

    def __init__(self):
        super().__init__()
        self.mats = dict(
            skin=Mat("#4e2016", "#a85a3a", "#d48a5e", "#f0b484", "#ffdcb8"),
            hair=Mat("#4a4450", "#9c98a8", "#ccc8d6", "#f2f0f8"),
            jacket=Mat("#6c5a6e", "#c8c2d2", "#ece8f2", "#fffdf6"),
            vest=Mat("#0c0a14", "#1e1a28", "#322c40", "#4a4460"),
            sash=Mat("#4a0a10", "#a01822", "#d8302e", "#ff6a4a"),
            trousers=Mat("#1a1414", "#3a2e2a", "#56443c", "#725c50"),
            boot=Mat("#5a4626", "#b8a070", "#e4d0a0", "#fff2cc"),
            straw=Mat("#6a4414", "#c09034", "#e8c25a", "#fff09a"),
            steel=STEEL, kwood=KWOOD, iron=IRON, rice=RICE,
            wood=Mat("#4a2410", "#9a5a28", "#c88440", "#eab468"),
        )

    # -------------------------------------------- body
    def draw_back(self, cv, f):
        if f.P.get("nopan"):
            return
        m = self.mats
        c = f.T((-10.5, -14.0))
        t = self.f.lean + 0.18
        cv.part("panhandle", m["sash"], [("ell", *f.T((-11.5, -29.0)), 2.2, 1.6, t), ("ell", *f.T((-9.5, 1.0)), 2.2, 1.6, t)],
                kind="body", R=1.5)
        cv.part("paellera", m["iron"], [("ell", *c, 5.4, 15.5, t)], kind="body", R=4.0, tilt=(-0.3, 0))
        cv.part("panrim", STEEL, [("ell", *add(c, (-0.6, 0)), 4.6, 15.0, t), ("-", ("ell", *add(c, (0.4, 0)), 3.6, 13.8, t))],
                kind="body", R=1.0)

    def draw_torso(self, cv, f: Fig):
        m = self.mats
        c = f.cloth
        shirt = [(-6.5, -28.0), (-8.2, -22.0), (-7.6, -12.0), (-7.0, -3.0), (-7.4, 3.0), (8.4, 3.0), (8.6, -3.0),
                 (8.2, -12.0), (9.0, -20.0), (7.0, -27.0), (2.0, -30.0)]
        cv.part("shirt", m["jacket"], [("poly", tpts(f, shirt))], kind="body", R=5.0)
        vest = [(-6.5, -28.0), (-8.4, -22.0), (-7.8, -12.0), (-7.2, -8.0), (3.0, -8.0), (5.0, -16.0), (3.0, -27.0)]
        v = cv.part("vest", m["vest"], [("poly", tpts(f, vest))], kind="body", R=3.5)
        for by in (-20.0, -15.0, -11.0):
            p = f.T((3.5, by))
            cv.stamp(["g"], round(p[0]), round(p[1]), {"g": GOLD.ramp[2]}, v)
        sash = [(-7.6, -9.5), (8.6, -10.0), (9.0, -2.0), (-7.6, -1.5)]
        sp = cv.part("sash", m["sash"], [("poly", tpts(f, sash))], kind="body", R=2.5)
        for k in (-4.0, 0.5, 5.0):
            cv.paint([("cap", *f.T((k, -9.5)), *f.T((k + 2.0, -1.5)), 0.4, 0.4)], color=m["sash"].ramp[0], within=[sp])
        tail = [(-7.4, -6.0), (-9.6 - 2.0 * c, 4.0), (-12.0 - 3.0 * c, 10.0), (-9.0 - 2.5 * c, 10.5), (-6.0, 1.0)]
        cv.part("sashtail", m["sash"], [("poly", tpts(f, tail))], kind="body", R=1.5)

    # -------------------------------------------- head
    def draw_head(self, cv, f: Fig):
        m = self.mats
        self.neck_part(cv, f, 2.6)
        hs = head_shapes(f, 9.0, 9.4, jaw=(3.6, 3.6, 5.8, 5.4), nose=(8.8, 0.6, 2.2))
        head = cv.part("head", m["skin"], hs, kind="upper", R=4.0)
        cv.part("ear", m["skin"], [("ell", *hp(f, (-2.6, 0.8)), 2.0, 2.8, f.head_tilt)], kind="upper", R=1.5)
        hair = [("poly", hpts(f, [(-9.4, -2.0), (-8.0, -6.0), (-4.5, -5.0), (-4.6, 2.0), (-7.0, 5.5), (-9.4, 3.0)]))]
        cv.part("hair", m["hair"], hair, kind="upper", R=2.0)
        L = {"q": m["skin"].ramp[0]}
        hx, hy = f.head
        cv.stamp(["q.q", ".q."], hx - 1, hy + 2, L, head)        # wrinkles at the cheek
        draw_face(self, cv, f, head)
        # bushy brows and the great handlebar moustache
        ang = f.face[0] == "angry"
        br = [("ell", *hp(f, (3.0, -5.6 + (0.6 if ang else 0))), 3.2, 1.3, -0.25 if not ang else 0.3),
              ("ell", *hp(f, (8.0, -5.0)), 1.6, 1.1, 0.2)]
        cv.part("brow", m["hair"], br, kind="upper", R=1.0)
        tw = f.P.get("twitch", 0.0)
        mo = [("ell", *hp(f, (6.8, 3.4)), 3.8, 1.9, -0.15), ("ell", *hp(f, (10.4, 3.4)), 2.6, 1.6, 0.2),
              ("cap", *hp(f, (4.0, 3.6)), *hp(f, (1.0, 1.0 - tw)), 1.4, 0.7), ("cap", *hp(f, (11.6, 3.6)), *hp(f, (13.4, 1.4 - tw)), 1.2, 0.6)]
        cv.part("moust", m["hair"], mo, kind="upper", R=1.5)
        if not f.P.get("nohat"):
            dx, dy, tl = f.hat
            self.draw_hat(cv, add(hp(f, (0.5, -7.5)), (dx, dy)), f.head_tilt + tl - 0.06)

    def draw_hat(self, cv, base, t, dx=0.0, dy=0.0):
        m = self.mats
        crown = [("poly", [add(base, rot(p, t)) for p in [(-6.6, 0.0), (6.8, 0.0), (6.0, -6.5), (3.0, -8.0), (-3.0, -8.0), (-6.0, -6.5)]])]
        cr = cv.part("crown", m["straw"], crown, kind="upper", R=3.5)
        cv.paint([("poly", [add(base, rot(p, t)) for p in [(-6.8, -0.2), (6.9, -0.2), (6.7, -2.6), (-6.7, -2.6)]])],
                 mat=m["sash"], within=[cr])
        for k in range(-5, 7, 2):
            cv.paint([("cap", *add(base, rot((k, -3.0), t)), *add(base, rot((k + 0.6, -7.5), t)), 0.35, 0.35)],
                     color=m["straw"].ramp[0], within=[cr])
        cv.part("brim", m["straw"], [("ell", *add(base, rot((0.6, 0.6), t)), 14.0, 2.6, t)], kind="upper", R=2.0, bias=0.1)

    # -------------------------------------------- weapon: the long wooden ladle
    def ladle(self, wr, ang, choke=0.0):
        c = add(wr, polar(ang, 2.2 - choke))
        return lambda u, v: add(c, rot((u, v), ang))

    def draw_weapon(self, cv, f, wr, ang, far):
        T = self.ladle(wr, ang, self.choke(f))
        m = self.mats
        cv.part("ladleH", m["wood"], [("cap", *T(-5.0, 0), *T(15.0, 0), 1.3, 1.1)], kind="upper", R=1.0, weight=2)
        cv.part("ladleB", m["wood"], [("ell", *T(18.0, 1.0), 3.8, 3.0, ang)], kind="upper", R=2.6)
        cv.part("ladleIn", m["wood"], [("ell", *T(18.0, -0.8), 3.2, 1.2, ang)], kind="upper", flat=0, weight=2)
        if not far and f.face[0] != "angry" or f.P.get("rice"):
            cv.part("rice", m["rice"], [("ell", *T(18.0, -1.6), 2.8, 1.4, ang)], kind="upper", R=1.2, weight=2)

    def choke(self, f):
        return f.P.get("choke", 0.0)

    def muzzle(self, f):
        return self.ladle(f.wr_n, f.hang[0], self.choke(f))(18.5, -1.0)

    # -------------------------------------------- full-body frames
    def floor_pan(self, cv, x, front=False, behind=False):
        m = self.mats
        y = FLOOR - 2.6
        if not front:
            cv.part("fpan", m["iron"], [("ell", x, y, 14.0, 3.0, 0)], kind="upper", R=2.0, behind=behind)
            cv.part("frice", m["rice"], [("ell", x, y - 0.9, 12.0, 1.8, 0)], kind="upper", R=1.0, behind=behind)
            for k in (-8, -3, 2, 7):
                cv.stamp(["r"], int(x + k), int(y - 1), {"r": m["sash"].ramp[1]}, len(cv.parts) - 1)
        else:
            cv.part("fpanF", m["iron"], [("poly", [(x - 14.5, y - 0.2), (x + 14.5, y - 0.2), (x + 12.5, y + 2.9), (x - 12.5, y + 2.9)])],
                    kind="upper", R=1.5)
            cv.part("fhand", m["sash"], [("ell", x - 16.0, y - 0.5, 2.4, 1.4, 0), ("ell", x + 16.0, y - 0.5, 2.4, 1.4, 0)],
                    kind="upper", R=1.0)

    def full_die(self, i):
        """Faints: eyes spinning, sets the paellera down, sways, and falls face first into it."""
        if i == 0:
            return self.mk(dpel=(-2, 0.5), lean=-0.2, hn=(10, 2), hf=(-8, -8), an=-1.0, af=-2.2, items=("weapon", "open"),
                           face=("open", "o"), head=(-0.25, 0, 0), hat=(0, -3, -0.2), elbow=(-1, 1)), None
        if i == 1:
            return self.mk(lean=0.04, dpel=(1, 0), hn=(9, 7), an=-1.1, face=("spiral", "o"), head=(0.15, 0, 0),
                           hat=(1, 0, 0.15)), None
        if i == 2:
            P = self.mk(lean=-0.12, dpel=(-1, 0), hn=(8, 6), an=-1.2, hf=(-4, 9), face=("spiral", "o"), head=(-0.2, 0, 0),
                        hat=(-1, 0, -0.2), nopan=True)
            return P, lambda cv, f, chef: chef.floor_pan(cv, 30.0)
        angs = {3: 0.45, 4: 0.95, 5: 1.35, 6: 1.57, 7: 1.57}
        ang = angs[i]
        P = self.mk(feet=((4, 0, 0), (-3, 0, 0)), hn=(9, 4), hf=(-5, 7), an=0.2, af=1.4,
                    items=("weapon" if i < 5 else "open", "open"), face=("spiral", "o"), nopan=True, nohat=i >= 6)

        def post(cv, f, chef, ang=ang, i=i):
            lie(cv, f, ang, lift=None)
            cols = (cv.pid >= 0).any(0).nonzero()[0]
            px = 30.0 if i < 5 else cols[-1] / 4 - cv.ox - 7.0
            if i >= 5:   # the ladle dropped flat beside him
                chef.mats and cv.part("ladleF", chef.mats["wood"], [("cap", -14.0, FLOOR - 1.6, 6.0, FLOOR - 1.6, 1.2, 1.2),
                                                                   ("ell", 9.0, FLOOR - 2.6, 3.6, 2.4, 0)], kind="upper", R=1.0)
            chef.floor_pan(cv, px, behind=True)
            if i >= 6:   # face first in the paellera, the straw hat rolled off beside it
                chef.floor_pan(cv, px, front=True)
                rows = (cv.pid >= 0).any(1).nonzero()[0]
                top = rows[0] / 4 - cv.oy
                chef.draw_hat(cv, (-6.0, top + (0.5 if i == 6 else 2.5)), -0.5 if i == 6 else -0.2)
        return P, post

    def full_win(self, i):
        """Raises the ladle like a sword, chin up; the moustache bristles."""
        P = self.mk(dpel=(0, [0, -1, -2, -1, 0, 0][i]), lean=-0.14, feet=((6, 0, 0), (-5, 0, 0)),
                    hn=(13, -14 + [0, -1, -2, -1, 0, 1][i]), an=-1.15 + [0, -0.1, -0.2, -0.1, 0, 0.1][i], hf=(2, 9),
                    face=("cool", "grit") if i in (2, 3) else ("squint", "flat"), head=(-0.15, 0, 0),
                    hat=(0, [0, 0, -1, -1, 0, 0][i], 0), twitch=[0, 1, 2, 1, 0, 0][i], rice=True)
        return P, None

    def full_select(self, i):
        """Leans on the ladle like a staff, taps his espadrille, twitches the moustache, unimpressed."""
        g = self.ground()
        P = self.mk(lean=-0.04, feet=((7, [0, 1.5, 0, 1.5][i], [0, -0.35, 0, -0.35][i]), (-5, 0, 0)), hn=(10, 6),
                    an=-1.35, hf=(3, 9), face=("squint", "frown") if i != 2 else ("cool", "frown"),
                    head=(-0.05, 0, 0), twitch=[0, 1, 0, 1][i] * 1.0)
        return P, None


# ====================================================================== DOÑA BRIOCHE

class Brioche(FaceGeom, Chef):
    """Doña Brioche: round sweet pastry chef in pink, frilly cap with a bow, lace apron, piping bag at the hip,
    golden curls. A whipped-cream gun. Sweet but ferocious."""

    id = "brioche"
    D = dict(hip_y=26.0, thigh=12.8, shin=12.0, ankle_h=3.8, foot=9.0, leg_r=(4.6, 3.6, 2.6), hip_dx=1.8,
             shoulder=(0.5, -25.5), sh_back=2.0, neck=(2.0, -28.0), head_off=(2.8, -10.0),
             upper=8.4, fore=8.0, arm_r=(3.4, 3.0, 2.3))
    eye, lip, lip2, blush = "#7a3a8a", "#d03a6a", "#f06a8a", "#ff8a9a"
    STYLE = dict(Chef.STYLE, stride=6.5, lift=7.0, kick=3.0, bob=1.6, sway=0.6, lean_run=0.12, crouch_drop=3.5,
                 crouch_lean=0.36)
    AIM = {
        "rest": dict(n=(8, 9), a=0.25, f=("w", 5.0, -1.0)),
        "run": dict(n=(9, 8), a=0.08, f=("w", 5.0, -1.0)),
        "fwd": dict(n=(10, 8), a=0.0, f=("w", 6.0, -1.0)),
        "up": dict(n=(13, -10), a=-1.45, f=("w", 5.0, 1.0)),
        "down": dict(n=(10, -5), a=1.45, f=("w", 5.0, 1.0)),
        "crouch": dict(n=(13, 1), a=0.0, f=("w", 6.0, -1.0)),
        "crouch_rest": dict(n=(12, 1), a=0.12, f=("w", 5.0, -1.0)),
    }
    RECOIL = (1.6, 0.8, 0.3)
    KICK = (-0.06, -0.03, 0.0)
    FACE = dict(idle=("open", "lipsmile"), aim=("angry", "lipsmile"), run=("open", "lipsmile"), jump=("wide", "lipo"),
                fire=("angry", "lipgrit"))
    EYESET = {
        "open": (["kkkkk", "kwwpk", ".wwp.", "..k.."], ["kk", "pk", "p."]),
        "wide": (["kkkkk", "kwwpk", "kwwpk", ".kkk."], ["kk", "pk", "pk"]),
        "angry": ([".....", "kk...", "kkkkk", "kwwpk"], ["..", "kk", "pk"]),
        "happy": ([".....", ".kkk.", "k...k"], ["..", "kk"]),
        "blink": ([".....", ".....", "kkkkk", ".k.k."], ["..", "kk"]),
    }
    EYE_N, EYE_F = (1, -3), (7, -2)
    BROW = ([".bb."], (2, -5), ["b"], (7, -4))
    BROW_ANGRY = (["bb...", "..bb."], (1, -6), ["b."], (7, -5))
    NOSE = (["s"], (8, 1))
    MOUTH_R = (7, 5)
    BLUSH = (["hhh"], (1, 2))
    MOUTH_MAP = {"smile": "lipsmile", "grin": "lipgrin", "open": "lipo", "o": "lipo", "yell": "lipyell", "grit": "lipgrit"}

    def __init__(self):
        super().__init__()
        self.mats = dict(
            skin=Mat("#6a2a2a", "#d8907a", "#f6c0a4", "#ffe0cc", "#fff4ea"),
            hair=Mat("#6a3a0a", "#c88a1c", "#f0c040", "#ffe68a", "#fff8d0"),
            jacket=Mat("#7a1e4a", "#d8588e", "#f48cb6", "#ffbcd8", "#ffe8f2"),
            apron=WHITE,
            trousers=Mat("#6c5a6e", "#d0c6dc", "#f0eaf4", "#ffffff"),
            boot=Mat("#4a0a24", "#a0204e", "#d84476", "#ff7aa6", "#ffd0e0"),
            mint=Mat("#1a5a54", "#4aa8a0", "#86dccc", "#c8fff2", "#ffffff"),
            cream=CREAM, steel=STEEL, kwood=KWOOD,
        )

    def leg_mats(self):
        return self.mats["trousers"], self.mats["boot"]

    def draw_torso(self, cv, f: Fig):
        m = self.mats
        c = f.cloth
        dress = [(-7.5, -26.0), (-11.0, -18.0), (-11.6, -8.0), (-10.2, 0.0), (-12.6 - 2 * c, 9.5), (14.8 - c, 9.5),
                 (12.6, 0.0), (13.4, -8.0), (12.8, -17.0), (9.0, -25.0), (3.0, -28.5)]
        cv.part("dress", m["jacket"], [("poly", tpts(f, dress))], kind="body", R=6.0)
        ap = [(2.0, -18.0), (10.0, -18.0), (13.0, -8.0), (12.0, 0.0), (13.4 - c, 8.5), (-2.0 - 1.5 * c, 8.5),
              (-1.0, 0.0), (0.0, -8.0)]
        apr = cv.part("apron", m["apron"], [("poly", tpts(f, ap))], kind="body", R=4.0)
        lace = []
        for k in range(6):
            x = -1.5 - 1.5 * c + (14.5 + 0.5 * c) * k / 5
            lace.append(("circ", *f.T((x, 8.8)), 1.6))
        cv.part("lace", m["apron"], lace, kind="body", R=1.2, group=apr)
        # pink bow belt and heart pocket
        cv.paint([("cap", *f.T((-11.0, -9.0)), *f.T((13.0, -9.0)), 1.1, 1.1)], mat=m["jacket"], within=[apr], tone_shift=0)
        hp_ = f.T((6.5, -2.0))
        cv.stamp([".j.j.", "jjjjj", ".jjj.", "..j.."], round(hp_[0]) - 2, round(hp_[1]) - 2, {"j": m["jacket"].ramp[1]}, apr)
        # the piping bag at the hip
        a, b = f.T((-9.5, -7.0)), f.T((-10.5, 3.0))
        cv.part("bag", CREAM, [("poly", [add(a, (-2.4, 0)), add(a, (2.4, 0)), b])], kind="body", R=2.0)
        cv.part("bagtip", m["jacket"], [("cap", *b, *add(b, (0.6, 2.0)), 0.9, 0.5)], kind="body", R=0.6, weight=2)

    def draw_head(self, cv, f: Fig):
        m = self.mats
        self.neck_part(cv, f, 2.6)
        cl = tpts(f, [(-2.0, -29.0), (6.0, -29.0), (7.0, -25.5), (-2.5, -25.5)])
        collar = cv.part("collar", m["apron"], [("poly", cl)], kind="upper", R=1.2)
        hs = head_shapes(f, 9.4, 9.4, jaw=(3.0, 3.8, 6.2, 5.6), nose=(8.6, 1.0, 1.5))
        curls = [("circ", *hp(f, (x, y)), r) for (x, y, r) in
                 ((-8.0, 3.0, 3.4), (-9.0, -2.0, 3.4), (-6.5, -6.6, 3.4), (-3.0, 6.0, 2.8), (5.5, -7.6, 2.8), (8.5, -5.0, 2.4))]
        cv.part("curls", m["hair"], curls, kind="upper", R=2.5)
        head = cv.part("head", m["skin"], hs, kind="upper", R=4.5)
        cv.part("ear", m["skin"], [("ell", *hp(f, (-2.6, 1.0)), 1.6, 2.2, f.head_tilt)], kind="upper", R=1.4)
        cv.part("curls2", m["hair"], [("circ", *hp(f, (-4.0, -5.0)), 2.8), ("circ", *hp(f, (0.5, -6.6)), 2.6),
                                      ("circ", *hp(f, (-5.0, 3.0)), 2.2)], kind="upper", R=2.0)
        draw_face(self, cv, f, head)
        if not f.P.get("nohat"):
            dx, dy, tl = f.hat
            self.draw_hat(cv, add(hp(f, (-0.5, -8.0)), (dx, dy)), f.head_tilt + tl - 0.15)

    def draw_hat(self, cv, base, t, dx=0.0, dy=0.0):
        m = self.mats
        cap = [("ell", *add(base, rot((0.0, -2.6), t)), 10.0, 5.0, t)]
        cv.part("cap", m["apron"], cap, kind="upper", R=4.0)
        frill = [("circ", *add(base, rot((x, 1.0), t)), 1.7) for x in (-9.0, -6.0, -3.0, 0.0, 3.0, 6.0, 9.0)]
        cv.part("frill", m["apron"], frill, kind="upper", R=1.4)
        bc = add(base, rot((-8.0, -3.0), t))
        bow = [("poly", [bc, add(bc, (-4.4, -3.4)), add(bc, (-4.4, 2.8))]), ("poly", [bc, add(bc, (3.6, -3.8)), add(bc, (3.8, 2.2))]),
               ("cap", *bc, *add(bc, (-2.0, 5.5)), 1.0, 0.8)]
        cv.part("bow", m["jacket"], bow, kind="upper", R=1.8)
        cv.part("knot", m["jacket"], [("circ", *bc, 1.5)], kind="upper", R=1.0, bias=0.15)

    # -------------------------------------------- weapon: the whipped-cream gun
    def gun(self, wr, ang):
        c = add(wr, polar(ang, 1.5))
        return lambda u, v: add(c, rot((u, v), ang))

    def draw_weapon(self, cv, f, wr, ang, far):
        T = self.gun(wr, ang)
        m = self.mats
        cv.part("grip", m["jacket"], [("cap", *T(0.0, 1.5), *T(-1.6, -3.0), 1.8, 1.8)], kind="upper", R=1.4)
        cv.part("can", m["mint"], [("cap", *T(-5.0, -4.8), *T(8.0, -4.8), 3.4, 3.4)], kind="upper", R=3.2)
        can = len(cv.parts) - 1
        for k in (-2.0, 2.0, 6.0):
            cv.paint([("cap", *T(k, -8.5), *T(k + 1.0, -1.0), 0.5, 0.5)], mat=m["jacket"], within=[can])
        cv.part("cone", STEEL, [("poly", [T(8.0, -7.4), T(8.0, -2.2), T(14.5, -3.9), T(14.5, -5.7)])], kind="upper", R=1.5)
        cv.part("tip", m["apron"], [("circ", *T(15.2, -4.8), 1.6)], kind="upper", R=1.0, weight=2)
        cv.part("trig", m["jacket"], [("cap", *T(2.5, -1.5), *T(2.8, 1.2), 0.6, 0.6)], kind="upper", R=0.5, weight=2)

    def muzzle(self, f):
        return self.gun(f.wr_n, f.hang[0])(16.5, -4.8)

    def cream(self, cv, pts):
        for k, (x, y, r) in enumerate(pts):
            sh = [("circ", x, y, r), ("circ", x + r * 0.6, y - r * 0.5, r * 0.6), ("circ", x - r * 0.5, y + r * 0.3, r * 0.7)]
            cv.part("cream", CREAM, sh, kind="upper", R=r * 0.9)

    def full_die(self, i):
        """Splattered with whipped cream, slips and slides away on her back; a cherry lands on top."""
        if i == 0:
            return self.mk(dpel=(-2, 0.5), lean=-0.22, hn=(10, 2), hf=(-8, -8), an=0.4, af=-2.2, items=("weapon", "open"),
                           face=("wide", "lipo"), head=(-0.2, 0, 0), hat=(0, -3, -0.2), elbow=(-1, 1)), None
        if i in (1, 2):
            P = self.mk(dpel=(-1, 0), lean=-0.1, hn=(9, 4), hf=(-7, -6), an=0.6, af=-2.2, items=("weapon", "open"),
                        face=("wide", "lipo"), elbow=(-1, 1))

            def post(cv, f, chef, i=i):
                h = f.head
                pts = [(h[0] - 1, h[1] - 9, 5.0), (h[0] + 6, h[1] + 3, 3.2), (4.0, -12.0, 4.4), (6.0, 4.0, 3.6)]
                if i == 2:
                    pts += [(h[0] + 2, h[1] - 2, 5.6), (-2.0, -2.0, 5.0), (8.0, -6.0, 4.6), (0.0, 14.0, 4.0)]
                chef.cream(cv, pts)
            return P, post
        P = self.mk(feet=((4, 0, 0), (-3, 0, 0)) if i > 3 else ((10, 3, -0.5), (6, 1, -0.3)), hn=(8, -8), hf=(-4, -10),
                    an=-1.0, af=-1.6, items=("weapon", "open"), face=("x", "lipo"), elbow=(-1, 1))
        ang = -0.6 if i == 3 else -1.57
        dx = {3: 0, 4: -3, 5: -6, 6: -8, 7: -8}[i]

        def post(cv, f, chef, ang=ang, dx=dx, i=i):
            lie(cv, f, ang, lift=None if i > 3 else -2, dx=dx)
            if i == 3:
                chef.cream(cv, [(-4.0, -14.0, 5.0), (6.0, -6.0, 4.2), (2.0, 8.0, 4.0)])
                return
            mound = [(dx - 14.0 + 9 * k, FLOOR - 7.0 - (3 if k in (1, 2) else 0), 6.0 - abs(k - 1.5)) for k in range(4)]
            chef.cream(cv, mound + [(dx + 22.0 + 6 * j, FLOOR - 1.5, 1.8) for j in range(3 if i > 4 else 0)])
            if i >= 6:
                top = dx - 5.0
                y = FLOOR - 15.5 - (3 if i == 6 else 0)
                cv.part("cherry", Mat("#4a0010", "#b0101e", "#e83038", "#ff8080", "#ffffff"), [("circ", top, y, 2.6)],
                        kind="upper", R=2.2)
                cv.part("stem", Mat("#1a3a10", "#2a6a1a", "#4a9a2a", "#7ac84a"),
                        [("cap", top + 0.5, y - 2.0, top + 2.5, y - 6.0, 0.6, 0.5)], kind="upper", R=0.5, weight=2)
        return P, post

    def full_win(self, i):
        """Hops, pipes a swirl of cream into the air, blows a kiss."""
        hop = [0, -3, -4, -2, 0, 1][i]
        h = max(0.0, -hop - 1)
        P = self.mk(dpel=(0, hop), lean=-0.12, feet=((5, h, 0.3 if h else 0), (-6, h * 1.2, 0.5 if h else 0)),
                    hn=(12, -10), an=-1.0, hf=(-6, -8), af=-2.0, items=("weapon", "open"),
                    face=("happy", "lipgrin") if i % 2 else ("blink", "lipsmile"), hat=(0, [0, 2, 3, 1, -1, -1][i], 0),
                    cloth=[0, -0.6, -0.9, -0.5, 0.3, 0.4][i], elbow=(-1, 1))

        def post(cv, f, chef, i=i):
            m = chef.muzzle(f)
            sw = [(m[0] + 2 + 2 * math.cos(k + i), m[1] - 3 - 3 * k, 2.6 - 0.4 * k) for k in range(1 + i % 3 + 1)]
            chef.cream(cv, sw)
        return P, post

    def full_select(self, i):
        """Hugs the cream gun to her cheek, sways sweetly; a wink; then the ferocious glare."""
        P = self.mk(lean=[-0.04, 0.0, 0.04, 0.0][i], dpel=([-1, 0, 1, 0][i], 0), feet=((4, 0, 0), (-5, 0, 0)),
                    hn=(10, 1), an=-1.35, hf=(9, 4), af=-0.6, items=("weapon", "fist"),
                    face=[("open", "lipsmile"), ("blink", "lipsmile"), ("open", "lipsmile"), ("angry", "lipgrin")][i],
                    head=([0.1, 0.12, 0.1, 0.0][i], 0, 0), hat=(0, 0, [0.05, 0.08, 0.05, 0][i]))
        return P, None


# ====================================================================== EL SUMILLER DON CRIANZA

class Crianza(FaceGeom, Chef):
    """El Sumiller Don Crianza: tall thin sommelier, black tailcoat, burgundy waistcoat, bow tie, silver tastevin on a
    chain, napkin on the arm, slicked hair, pointy nose and pencil moustache. Fires corks from a cava bottle. Snooty."""

    id = "crianza"
    D = dict(hip_y=23.0, thigh=14.8, shin=14.4, ankle_h=3.4, foot=11.0, leg_r=(3.3, 2.7, 2.1), hip_dx=1.2,
             shoulder=(0.5, -28.5), sh_back=1.6, neck=(2.0, -31.0), head_off=(2.2, -10.5),
             upper=9.8, fore=9.4, arm_r=(2.7, 2.4, 1.9))
    eye, lip, lip2, blush = "#3a2a4a", "#9a3040", "#c04858", "#e0907e"
    STYLE = dict(Chef.STYLE, stride=9.0, lift=6.0, kick=4.0, bob=0.8, lean_idle=-0.03, lean_run=0.10, crouch_drop=6.0,
                 crouch_lean=0.45)
    AIM = {
        "rest": dict(n=(8, 7), a=-0.55, f=("s", (2.0, 11.0))),
        "run": dict(n=(10, 6), a=-0.15, f=("w", 4.0, 2.4)),
        "fwd": dict(n=(11, 3), a=0.0, f=("w", 4.5, 2.6)),
        "up": dict(n=(13, -12), a=-1.45, f=("w", 4.5, -2.6)),
        "down": dict(n=(9, -7), a=1.45, f=("w", 4.5, -2.6)),
        "crouch": dict(n=(14, 0), a=0.0, f=("w", 4.5, 2.6)),
        "crouch_rest": dict(n=(13, 0), a=-0.3, f=("s", (7.0, -1.0))),
    }
    RECOIL = (3.4, 1.6, 0.4)
    KICK = (-0.28, -0.12, -0.02)
    FACE = dict(idle=("snoot", "smirk"), aim=("snoot", "flat"), run=("snoot", "flat"), jump=("open", "o"),
                fire=("angry", "smirk"))
    EYESET = {
        "snoot": (["....", "kkkk", "kwpk"], ["..", "kk", "pk"]),
        "open": (["kkkk", "kwpk", ".kk."], ["kk", "pk", ".."]),
        "angry": (["k...", "kkkk", "kwpk"], ["kk", "kk", "pk"]),
        "blink": (["....", "....", "kkkk"], ["..", "..", "kk"]),
        "wide": (["kkkk", "kwpk", "kwpk", ".kk."], ["kk", "pk", "pk"]),
    }
    EYE_N, EYE_F = (1, -3), (6, -3)
    BROW = (["bbbb"], (1, -6), ["bb"], (6, -5))
    BROW_ANGRY = (["bb..", "..bb"], (1, -6), ["b.", ".b"], (6, -6))
    NOSE = None
    MOUTH_R = (8, 5)
    BLUSH = None
    MOUTH_MAP = {"smile": "smirk", "grin": "smirk", "yell": "open"}
    THROW = [((-9, -7), -2.4, "fist", -0.12), ((19, -4), -0.4, "open", 0.08), ((16, 4), 0.5, "open", 0.14),
             ((9, 8), 0.9, "fist", 0.04)]

    def __init__(self):
        super().__init__()
        self.mats = dict(
            skin=Mat("#5a2c2c", "#c89076", "#ecc0a0", "#ffe2c8", "#fff4ea"),
            hair=Mat("#0a0610", "#1a1222", "#2e2440", "#5a4a7a", "#a898d0"),
            jacket=Mat("#06040c", "#1a1622", "#2e2838", "#4c4458", "#7a7090"),
            vest=Mat("#3a0614", "#6e1024", "#9a1c34", "#c83a4a"),
            shirt=WHITE,
            trousers=Mat("#06040c", "#16121e", "#28222e", "#423a4c"),
            boot=Mat("#000000", "#100c14", "#241e2c", "#463e52", "#c0b8d0"),
            glass=Mat("#0a2a14", "#1a5a2a", "#2e8a3e", "#5ac06a", "#c8ffd0"),
            label=Mat("#6a5a40", "#d8c8a0", "#f4ead0", "#fffaee"),
            steel=STEEL, kwood=KWOOD, gold=GOLD,
            silver=Mat("#3a3c58", "#9098b8", "#cdd4ea", "#f4f8ff", "#ffffff"),
        )

    def leg_mats(self):
        return self.mats["trousers"], self.mats["boot"]

    def boot_pts(self, ank, pitch):
        L, hgt = self.D["foot"], self.D["ankle_h"]
        pts = [(-3.0, -1.6), (2.0, -1.8), (L - 2, 0.2), (L + 1.0, hgt - 0.6), (L, hgt - 0.1), (-3.5, hgt - 0.1), (-3.6, 0.8)]
        return [add(ank, rot(p, pitch)) for p in pts]

    def draw_back(self, cv, f):
        m = self.mats
        c = f.cloth
        tails = [(-5.5, -10.0), (-7.6, -2.0), (-9.0 - 3.0 * c, 8.0), (-10.0 - 4.5 * c, 15.5), (-6.6 - 4.0 * c, 16.0),
                 (-4.0 - 2.0 * c, 8.0), (-1.0, -4.0)]
        cv.part("tails", m["jacket"], [("poly", tpts(f, tails))], kind="body", R=2.0, far=0)

    def draw_torso(self, cv, f: Fig):
        m = self.mats
        coat = [(-5.6, -29.5), (-7.4, -23.0), (-6.4, -14.0), (-6.0, -7.0), (-6.4, 0.0), (1.0, 0.5), (4.0, -8.0),
                (6.0, -16.0), (7.0, -23.0), (5.5, -29.0), (2.0, -31.5)]
        cv.part("coat", m["jacket"], [("poly", tpts(f, coat))], kind="body", R=3.5)
        front = [(1.5, -30.0), (6.0, -28.0), (7.6, -21.0), (6.8, -12.0), (5.6, -4.0), (5.0, 2.0), (0.8, 1.5), (3.0, -12.0)]
        sh = cv.part("shirtfront", m["shirt"], [("poly", tpts(f, front))], kind="body", R=2.5)
        vest = [(3.0, -21.0), (7.4, -20.0), (7.0, -12.0), (5.8, -4.0), (5.2, 1.0), (2.0, 1.0), (3.2, -12.0)]
        v = cv.part("vest", m["vest"], [("poly", tpts(f, vest))], kind="body", R=2.0)
        for by in (-15.0, -10.0, -5.0):
            p = f.T((5.0, by))
            cv.stamp(["g"], round(p[0]), round(p[1]), {"g": GOLD.ramp[2]}, v)
        lap = [(1.0, -30.5), (3.5, -27.5), (2.5, -10.0), (0.5, -10.0)]
        cv.part("lapel", m["jacket"], [("poly", tpts(f, lap))], kind="body", R=1.2, bias=0.2)
        # the tastevin on its chain
        a, b = f.T((3.0, -28.5)), f.T((5.0, -18.0))
        cv.paint([("cap", *a, *b, 0.45, 0.45)], color=m["silver"].ramp[1], within=[sh, v])
        cv.part("tastevin", m["silver"], [("ell", *add(b, (0.5, 1.6)), 2.8, 1.8, 0)], kind="body", R=1.6, weight=2)

    def draw_forearm(self, cv, f, el, wr, far, g):
        super().draw_forearm(cv, f, el, wr, far, g)
        if not far:   # the napkin draped over the forearm
            p = lerp(el, wr, 0.45)
            q = lerp(el, wr, 0.8)
            cv.part("napkin", self.mats["shirt"], [("poly", [add(p, (0, -1.6)), add(q, (0, -1.4)), add(q, (1.0, 5.5)),
                                                            add(p, (-1.0, 6.5))])], kind="upper", R=1.6)

    def draw_head(self, cv, f: Fig):
        m = self.mats
        self.neck_part(cv, f, 2.2)
        cl = tpts(f, [(-1.0, -32.5), (5.0, -32.5), (6.0, -29.5), (-1.5, -29.5)])
        cv.part("collar", m["shirt"], [("poly", cl)], kind="upper", R=1.0)
        bt = f.T((5.2, -30.6))
        cv.part("bowtie", m["jacket"], [("poly", [add(bt, (-3.0, -2.2)), add(bt, (3.0, 2.2)), add(bt, (3.0, -2.2)), add(bt, (-3.0, 2.2))])],
                kind="upper", R=1.0, weight=2)
        hs = head_shapes(f, 7.8, 10.0, jaw=(3.0, 4.6, 5.0, 5.4), nose=None)
        hs.append(("poly", hpts(f, [(6.0, -2.0), (13.5, 2.6), (7.0, 3.2)])))    # the long pointed nose
        head = cv.part("head", m["skin"], hs, kind="upper", R=4.0)
        cv.part("ear", m["skin"], [("ell", *hp(f, (-2.4, 1.0)), 1.5, 2.4, f.head_tilt)], kind="upper", R=1.3)
        hair = [("poly", hpts(f, [(-8.2, 0.0), (-8.6, -6.0), (-4.0, -10.6), (3.0, -11.8), (9.0, -9.6), (10.0, -7.0),
                                  (5.0, -7.4), (0.0, -6.4), (-3.2, -4.0), (-4.2, 2.0), (-6.4, 3.4)]))]
        hr = cv.part("hair", m["hair"], hair, kind="upper", R=2.6)
        cv.paint([("cap", *hp(f, (-3.0, -9.0)), *hp(f, (4.0, -10.0)), 0.6, 0.6)], color=m["hair"].ramp[3], within=[hr])
        draw_face(self, cv, f, head)
        hx, hy = f.head
        cv.stamp(["bbbb."], hx + 5, hy + 3, {"b": m["hair"].ramp[0]}, head)      # pencil moustache
        if f.P.get("cork"):
            cv.part("corkeye", Mat("#3a1a0a", "#8a5a2a", "#c08a4a", "#e8b878"),
                    [("cap", *hp(f, (3.0, -1.0)), *hp(f, (5.0, 0.5)), 2.4, 2.4)], kind="upper", R=1.8, weight=2)

    # -------------------------------------------- weapon: the cava bottle
    def bottle(self, wr, ang):
        c = add(wr, polar(ang, 1.0))
        return lambda u, v: add(c, rot((u, v), ang))

    def draw_weapon(self, cv, f, wr, ang, far):
        T = self.bottle(wr, ang)
        m = self.mats
        body = [("cap", *T(-3.0, 0.0), *T(6.0, 0.0), 3.3, 3.3),
                ("poly", [T(6.0, -3.3), T(9.5, -1.4), T(9.5, 1.4), T(6.0, 3.3)]), ("cap", *T(9.0, 0.0), *T(13.0, 0.0), 1.4, 1.3)]
        b = cv.part("bottle", m["glass"], body, kind="upper", R=2.6)
        cv.paint([("poly", [T(-0.5, -3.6), T(4.5, -3.6), T(4.5, 3.6), T(-0.5, 3.6)])], mat=m["label"], within=[b])
        cv.paint([("cap", *T(1.0, -0.4), *T(3.0, -0.4), 0.7, 0.7)], color=m["vest"].ramp[1], within=[b])
        cv.part("foil", m["gold"], [("cap", *T(9.6, 0.0), *T(13.6, 0.0), 1.7, 1.6)], kind="upper", R=1.3, weight=2)

    def muzzle(self, f):
        return self.bottle(f.wr_n, f.hang[0])(14.5, 0.0)

    def gush(self, cv, f, n=4, k=0):
        m = self.muzzle(f)
        a = f.hang[0]
        pts = [(m[0] + math.cos(a) * 3 * j + (j % 2) * 1.2, m[1] + math.sin(a) * 3 * j - 2.5 * j, 2.6 + 0.5 * j - 0.1 * k)
               for j in range(1, n + 1)]
        foam_puffs(cv, pts, seed=k)

    def full_die(self, i):
        """A cork pops straight into his eye: he staggers, the bottle gushes, he folds and lies spouting cava."""
        if i == 0:
            return self.mk(dpel=(-2, 0.5), lean=-0.25, hn=(10, -2), hf=(-8, -6), an=-0.6, af=-2.2, items=("weapon", "open"),
                           face=("wide", "o"), head=(-0.35, -1, 0), cork=True, elbow=(-1, 1)), None
        seq = {
            1: dict(dpel=(-4, 1), lean=-0.15, feet=((4, 0, 0), (-8, 0, 0)), hn=(9, -6), an=-1.0),
            2: dict(dpel=(-3, 7), lean=0.05, feet=((6, 0, 0), (-7, 0, 0.6)), hn=(9, -4), an=-1.2),
            3: dict(dpel=(-2, 13), lean=0.15, feet=((7, 0, 0), (-9, 0, 1.4)), hn=(8, -4), an=-1.35),
        }
        if i in seq:
            P = self.mk(hf=(-6, 4), af=2.0, items=("weapon", "open"), face=("blink", "o"), cork=True,
                        head=(-0.1, 0, 0), elbow=(-1, 1), **seq[i])
            return P, (lambda cv, f, chef, i=i: chef.gush(cv, f, n=2 + i, k=i))
        P = self.mk(feet=((4, 0, 0), (-3, 0, 0)), hn=(7, -10), hf=(-5, 6), an=-1.5, af=2.0, items=("weapon", "open"),
                    face=("blink", "o"), cork=True, elbow=(-1, 1))
        ang = -0.7 if i == 4 else -1.57

        def post(cv, f, chef, ang=ang, i=i):
            m0 = chef.muzzle(f)
            lie(cv, f, ang, lift=None if i > 4 else 4)
            rows = (cv.pid >= 0).any(1).nonzero()[0]
            top = rows[0] / 4 - cv.oy
            n = {4: 3, 5: 5, 6: 4, 7: 2}[i]
            cols = (cv.pid >= 0).any(0).nonzero()[0]
            bx = cols[0] / 4 - cv.ox + 7.0 if i > 4 else m0[0] - 4.0
            foam_puffs(cv, [(bx + (j % 2) * 2.0, top - 1 - 4.0 * j, 2.2 + 0.4 * j) for j in range(n)], seed=i)
        return P, post

    def full_win(self, i):
        """Pops the cava: a fountain of foam from the raised bottle, a snooty little bow of the head."""
        P = self.mk(lean=-0.10, feet=((6, 0, 0), (-5, 0, 0)), hn=(16, -6 + [0, -1, -1, 0, 1, 1][i]), an=-0.95,
                    hf=(2, 10), face=("snoot", "smirk") if i < 4 else ("blink", "smirk"),
                    head=([-0.12, -0.12, -0.1, -0.05, 0.05, -0.05][i], 0, 0))

        def post(cv, f, chef, i=i):
            chef.gush(cv, f, n=1 + (i % 3), k=i)
        return P, post

    def full_select(self, i):
        """Swirls the bottle under his nose, sniffs, raises an eyebrow at you."""
        P = self.mk(lean=-0.04, feet=((5, 0, 0), (-5, 0, 0)), hn=(10, -10 + [0, -0.5, 0, 0.5][i]),
                    an=-0.75 + [0, 0.2, 0, -0.2][i], hf=(2, 11), face=[("snoot", "smirk"), ("blink", "o"), ("blink", "o"),
                                                                       ("angry", "smirk")][i],
                    head=([-0.15, -0.2, -0.2, -0.12][i], 0, 0))
        return P, None
