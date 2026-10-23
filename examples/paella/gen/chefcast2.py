"""Don Pinche (the big showman with the croquette pan) and Chef Espuma (the mad foam scientist)."""
from __future__ import annotations

import math
import random

from chefbase import FLOOR, WHITE, Chef, Fig, Mat, add, hp, hpts, lerp, polar, rot, tpts
from chefcast import GOLD, KWOOD, LEATHER, STEEL, FaceGeom, draw_face, head_shapes, lie_post

IRON = Mat("#16141e", "#34323e", "#55536a", "#848aa4", "#c8d0e8")
CROQ = Mat("#4a1e0a", "#a2521c", "#d88a34", "#f6c060", "#fff0b0")
FOAM = Mat("#7a7e9a", "#c8d4e8", "#eef4fa", "#ffffff")


def croquette(cv, c, ang=0.0, r=1.9, L=2.6):
    a, b = add(c, polar(ang, -L / 2)), add(c, polar(ang, L / 2))
    return cv.part("croq", CROQ, [("cap", *a, *b, r, r)], kind="upper", R=1.6, weight=2)


CHAR = [(30, 20, 26), (58, 42, 46), (92, 70, 70), (134, 108, 100)]


def char_tone(c):
    """Burnt to a crisp: every colour to one of four charcoal tones by its brightness."""
    lum = 0.3 * c[0] + 0.59 * c[1] + 0.11 * c[2]
    return CHAR[0 if lum < 70 else 1 if lum < 130 else 2 if lum < 195 else 3]


def foam_puffs(cv, pts, seed=0):
    rnd = random.Random(seed)
    for (x, y, r) in pts:
        sh = [("circ", x, y, r)] + [("circ", x + rnd.uniform(-r, r) * 0.7, y + rnd.uniform(-r, r) * 0.6, r * 0.7)
                                    for _ in range(2)]
        cv.part("foam", FOAM, sh, kind="upper", R=r * 0.8)


# ====================================================================== DON PINCHE

class Pinche(FaceGeom, Chef):
    """Don Pinche: huge, jovial, black beret, a giant smile and moustache, round belly in a blue striped apron,
    rolled-up sleeves. A frying pan that flings croquettes. Waddles."""

    id = "pinche"
    D = dict(hip_y=26.0, thigh=12.6, shin=11.6, ankle_h=4.2, foot=11.0, leg_r=(5.8, 4.8, 3.7), hip_dx=2.6,
             shoulder=(0.5, -27.5), sh_back=2.0, neck=(2.0, -30.0), head_off=(3.0, -11.5),
             upper=9.5, fore=9.0, arm_r=(4.2, 3.9, 3.0))
    eye, lip, lip2, blush = "#2a1a14", "#b8283a", "#e2485a", "#f07a6a"
    STYLE = dict(Chef.STYLE, stride=6.5, lift=5.5, kick=2.0, bob=1.6, sway=1.0, lean_run=0.08, crouch_drop=4.0,
                 crouch_lean=0.36)
    AIM = {
        "rest": dict(n=(8, 6), a=0.25, f=("s", (4.0, 7.0))),
        "run": dict(n=(10, 5), a=0.12, f=("s", (-2.0, 9.0))),
        "fwd": dict(n=(10, 3), a=0.0, f=("s", (4.0, 9.0))),
        "up": dict(n=(13, -14), a=-0.30, f=("s", (4.0, 9.0))),
        "down": dict(n=(9, -8), a=1.25, f=("s", (4.0, 9.0))),
        "crouch": dict(n=(13, -3), a=0.0, f=("s", (7.0, 0.0))),
        "crouch_rest": dict(n=(12, -3), a=0.1, f=("s", (7.0, -1.0))),
    }
    RECOIL = (1.0, 0.5, 0.0)
    KICK = (-0.55, -0.25, -0.05)
    FACE = dict(idle=("happy", "biggrin"), aim=("open", "biggrin"), run=("happy", "biggrin"), jump=("wide", "yell"),
                fire=("angry", "grin"))
    EYESET = {
        "happy": (["....", ".kk.", "k..k"], ["..", "kk", ".."]),
        "open": (["kkkk", "wwpk", "wwpk"], ["kk", "pk", "pk"]),
        "cool": (["kkkk", "wwpk", "...."], ["kk", "pk", ".."]),
        "angry": (["kk..", "kkkk", "wwpk"], [".k", "kk", "pk"]),
    }
    EYE_N, EYE_F = (2, -4), (8, -4)
    BROW = (["bbbb.", "b...."], (1, -7), ["bb"], (8, -6))
    BROW_ANGRY = (["bb...", ".bbb.", "...b."], (1, -7), ["bb", "b."], (8, -6))
    NOSE = None
    MOUTH_R = (10, 4)
    BLUSH = (["hhh"], (1, 1))
    MOUTH_MAP = {"smile": "biggrin", "grin": "biggrin2", "open": "bigopen", "yell": "bigopen"}
    THROW = [((-9, -7), -2.4, "fist", -0.12), ((19, -4), -0.4, "open", 0.08), ((16, 4), 0.5, "open", 0.14),
             ((9, 8), 0.9, "fist", 0.04)]
    STAB = [((0, 7), 0.15, -0.04), ((13, 4), 0.02, 0.14), ((16, 4), 0.0, 0.16), ((7, 7), 0.15, 0.04)]

    def __init__(self):
        super().__init__()
        self.mats = dict(
            skin=Mat("#5a2018", "#c46a4a", "#ec9c74", "#ffc8a0", "#ffe6d0"),
            hair=Mat("#140c12", "#2a1c24", "#3e2c36", "#5a4450"),
            jacket=Mat("#6c5a5a", "#c8bca8", "#efe6d2", "#fffaee"),
            trousers=Mat("#24160e", "#4a3020", "#6c4630", "#8c6040"),
            boot=Mat("#120a0e", "#2a1a1e", "#463036", "#6a5058", "#a08890"),
            apron=Mat("#283a6a", "#c6d2ee", "#eaf0ff", "#ffffff"),
            stripe=Mat("#14204a", "#1e3478", "#2c4ca8", "#4070cc"),
            beret=Mat("#0e0a12", "#1e1824", "#302a3a", "#4a4458"),
            steel=STEEL, kwood=KWOOD,
        )

    # -------------------------------------------- body
    def draw_torso(self, cv, f: Fig):
        m = self.mats
        c = f.cloth
        br = f.P.get("breath", 0.0)
        body = [(-8.5, -28.0), (-11.0, -21.0), (-11.4, -10.0), (-10.0, -2.0), (-8.0, 3.0), (11.0, 3.0),
                (15.5 + br * 0.6, -4.0), (17.0 + br, -12.0), (14.5 + br * 0.6, -21.0), (9.0, -27.5), (3.0, -30.5)]
        shirt = cv.part("shirt", m["jacket"], [("poly", tpts(f, body))], kind="body", R=6.0)
        # the striped apron: bib over the chest, skirt over the belly down to the knees
        ap = [(1.0, -25.5), (8.0, -26.0), (14.0 + br * 0.6, -20.0), (17.4 + br, -11.0), (16.2 + br * 0.6, -3.0),
              (13.0 + c, 5.0), (11.5 + 2.5 * c, 13.0), (-3.0 + 2.0 * c, 13.5), (-5.0 + c, 6.0), (-4.0, -9.0)]
        apron = cv.part("apron", m["apron"], [("poly", tpts(f, ap))], kind="body", R=5.0)
        for k in range(-6, 20, 3):
            p0 = f.T((k + 0.5, -27.0))
            p1 = f.T((k + 0.5 + 1.6 * c, 14.0))
            cv.paint([("cap", *p0, *p1, 0.8, 0.8)], mat=m["stripe"], within=[apron])
        # neck strap and waist tie
        cv.paint([("cap", *f.T((1.6, -25.0)), *f.T((-1.0, -30.0)), 0.9, 0.9)], mat=m["stripe"], within=[shirt])
        cv.paint([("cap", *f.T((-11.5, -9.5)), *f.T((-3.5, -9.0)), 0.9, 0.9)], mat=m["stripe"], within=[shirt])
        # pocket with a wooden spoon
        pk = tpts(f, [(6.0, -1.0), (12.0, -1.0), (11.5, 4.0), (6.5, 4.0)])
        cv.part("spoon", KWOOD, [("cap", *f.T((8.0, 1.0)), *f.T((6.5, -7.0)), 0.8, 1.4)], kind="body", R=0.8)
        cv.part("pocket", m["apron"], [("poly", pk)], kind="body", R=1.5, bias=-0.1)

    def draw_forearm(self, cv, f, el, wr, far, g):
        ru, rf, rw = self.D["arm_r"]
        k = 1 if far else 0
        # rolled-up sleeve cuff at the elbow, hairy forearm
        cv.part(g + "fore", self.mats["skin"], [("cap", *el, *wr, rf, rw)], kind="upper", far=k, R=rf)
        cuff = lerp(el, wr, 0.12)
        cv.part(g + "cuff", self.mats["jacket"], [("cap", *el, *cuff, rf + 0.9, rf + 0.9)], kind="upper", far=k, R=1.6)

    # -------------------------------------------- head
    def draw_head(self, cv, f: Fig):
        m = self.mats
        self.neck_part(cv, f, 4.2)
        hs = head_shapes(f, 10.4, 10.2, jaw=(4.0, 4.6, 7.4, 6.2), nose=None)
        hs.append(("ell", *hp(f, (1.0, 7.5)), 7.0, 3.6, f.head_tilt))   # double chin
        head = cv.part("head", m["skin"], hs, kind="upper", R=5.0)
        cv.part("ear", m["skin"], [("ell", *hp(f, (-3.4, 1.0)), 2.0, 2.6, f.head_tilt)], kind="upper", R=1.5)
        hair = [("poly", hpts(f, [(-10.8, -1.0), (-9.8, -6.0), (-6.0, -6.4), (-5.0, -1.0), (-6.5, 5.0), (-9.5, 4.5)]))]
        cv.part("hair", m["hair"], hair, kind="upper", R=2.0)
        draw_face(self, cv, f, head)
        # the big round nose and the moustache over the grin
        cv.part("nose", m["skin"], [("ell", *hp(f, (10.0, 0.2)), 2.6, 2.3, 0)], kind="upper", R=2.2, bias=0.05)
        mo = [("ell", *hp(f, (7.0, 3.0)), 3.6, 1.7, -0.25), ("ell", *hp(f, (10.8, 2.8)), 2.6, 1.6, 0.35)]
        cv.part("moust", m["hair"], mo, kind="upper", R=1.5)
        if not f.P.get("nohat"):
            dx, dy, tl = f.hat
            self.draw_hat(cv, add(hp(f, (-0.5, -9.0)), (dx, dy)), f.head_tilt + tl - 0.18)

    def draw_hat(self, cv, base, t, dx=0.0, dy=0.0):
        m = self.mats
        b = [("ell", *add(base, rot((0.0, -1.5), t)), 12.0, 4.4, t), ("ell", *add(base, rot((-2.0, -3.6), t)), 9.0, 3.2, t)]
        cv.part("beret", m["beret"], b, kind="upper", R=3.5)
        st = add(base, rot((0.5, -5.8), t))
        cv.part("stem", m["beret"], [("cap", *st, *add(st, rot((0.6, -2.2), t)), 0.8, 0.6)], kind="upper", R=0.6, weight=2)

    # -------------------------------------------- weapon: the croquette pan
    def pan_pts(self, wr, ang):
        c = add(wr, polar(ang, 2.2))
        T = lambda u, v: add(c, rot((u, v), ang))
        return c, T

    def draw_weapon(self, cv, f, wr, ang, far):
        c, T = self.pan_pts(wr, ang)
        cv.part("handle", KWOOD, [("cap", *T(-2.5, 0), *T(8.5, -0.6), 1.5, 1.5)], kind="upper", R=1.2, weight=2)
        bowl = [T(8.5, -1.4), T(22.0, -1.4), T(21.0, 2.6), T(9.5, 2.6)]
        cv.part("pan", IRON, [("poly", bowl), ("ell", *T(15.2, 2.4), 5.8, 1.0, ang)], kind="upper", R=2.0, tilt=(0, -0.2))
        cv.part("panin", IRON, [("ell", *T(15.2, -1.4), 6.8, 1.5, ang)], kind="upper", flat=0, weight=2)
        if not far and f.P.get("croq", True) and f.P.get("face", ("", ""))[0] != "angry":
            croquette(cv, T(15.0, -3.2), ang)

    def muzzle(self, f):
        c, T = self.pan_pts(f.wr_n, f.hang[0])
        return T(15.0, -4.0)

    # -------------------------------------------- full-body frames
    def full_die(self, i):
        """Flattened into a pancake, peels back up dizzy, then flops on his back, belly up, beret on the belly."""
        hit = self.mk(dpel=(-2, 0.5), lean=-0.2, hn=(10, 2), hf=(-8, -8), an=0.4, af=-2.2, items=("weapon", "open"),
                      face=("x", "bigopen"), head=(-0.2, 0, 0), hat=(0, -3, -0.2), elbow=(-1, 1))
        if i == 0:
            return hit, None
        squash = {1: (1.18, 0.62), 2: (1.38, 0.30), 3: (1.52, 0.16), 4: (1.50, 0.18), 5: (1.2, 0.62), 6: (0.94, 1.08)}
        if i in squash:
            sx, sy = squash[i]
            face = ("x", "bigopen") if i < 5 else ("spiral", "o")
            P = self.mk(feet=((7, 0, 0), (-7, 0, 0)), hn=(10, 3) if i < 5 else (9, -2), hf=(-9, 3), an=0.3, af=2.6,
                        items=("weapon", "open"), face=face, hat=(0, -1 if i < 4 else -3, 0.2 * (i - 3)))

            def post(cv, f, chef, sx=sx, sy=sy):
                cv.transform(sx=sx, sy=sy, pivot=(0.0, FLOOR))
            return P, post
        P = self.mk(feet=((4, 0, 0), (-3, 0, 0)), hn=(7, 6), hf=(-6, 7), an=1.2, af=2.0, items=("weapon", "open"),
                    face=("x", "biggrin"), nohat=True)

        def hat_on_belly(cv, f, chef):
            rows = (cv.pid >= 0).any(1).nonzero()[0]
            top = rows[0] / 4 - cv.oy
            chef.draw_hat(cv, (4.0, top + 4.0), 0.25)
        return P, lie_post(-1.57, extra=hat_on_belly)

    def full_win(self, i):
        """Tosses a croquette from the pan and laughs, belly bouncing."""
        ph = i / 6
        P = self.mk(dpel=(0, [0, 1, 0, -1, 0, 1][i]), lean=-0.10, feet=((6, 0, 0), (-6, 0, 0)),
                    hn=(9, -2 + [0, 2, 0, -2, -3, -1][i]), an=-0.25 + [0, 0.15, 0, -0.35, -0.2, 0][i], hf=(4, 8),
                    face=("happy", "bigopen") if i % 2 else ("happy", "biggrin"), breath=[0, 1, 0, 1, 0, 1][i],
                    head=(-0.12, 0, 0), hat=(0, [0, -1, 0, 1, 0, -1][i], 0), croq=False)
        h = [3, 12, 20, 24, 20, 10][i]

        def post(cv, f, chef, h=h, i=i):
            c, T = chef.pan_pts(f.wr_n, f.hang[0])
            croquette(cv, add(T(15.0, -3.0), (0, -h + 3)), ang=i * 1.1)
        return P, post

    def full_select(self, i):
        """The showman: pan on the hip, belly laugh, waving to the crowd."""
        P = self.mk(lean=-0.08 + [0, -0.03, 0, -0.03][i], feet=((6, 0, 0), (-6, 0, 0)), hn=(15, 3 + [0, -1, 0, -1][i]),
                    an=-1.4 + [0, -0.3, 0, 0.2][i], hf=(3, 8), af=0.5, items=("open", "weapon"),
                    face=("happy", "bigopen" if i % 2 else "biggrin"), breath=[0, 1, 0, 1][i], head=(-0.1, 0, 0),
                    hat=(0, [0, -1, 0, -1][i], 0))
        return P, None


# ====================================================================== CHEF ESPUMA

class Espuma(FaceGeom, Chef):
    """Chef Espuma: wiry mad scientist of foams. Wild orange hair under a tilted toque, goggles on the forehead,
    a mint lab coat over a white jacket, a backpack of N2O tanks with tubes to his siphon. Bouncy and excitable."""

    id = "espuma"
    D = dict(hip_y=24.5, thigh=14.0, shin=13.4, ankle_h=4.0, foot=10.5, leg_r=(3.4, 2.8, 2.3), hip_dx=1.2,
             shoulder=(1.5, -26.5), sh_back=1.5, neck=(3.0, -28.5), head_off=(2.8, -9.5),
             upper=9.0, fore=8.6, arm_r=(2.7, 2.4, 1.8))
    eye, lip, lip2, blush = "#1c6a5a", "#b04040", "#d86060", "#e8907e"
    STYLE = dict(Chef.STYLE, stride=8.0, lift=9.0, kick=4.5, bob=2.0, lean_idle=0.08, lean_run=0.20, crouch_drop=4.5,
                 crouch_lean=0.42)
    AIM = {
        "rest": dict(n=(9, 6), a=0.40, f=("w", 6.0, 2.6)),
        "run": dict(n=(10, 5), a=0.10, f=("w", 6.0, 2.6)),
        "fwd": dict(n=(11, 4), a=0.0, f=("w", 6.0, 2.6)),
        "up": dict(n=(13, -12), a=-1.45, f=("w", 6.0, -2.6)),
        "down": dict(n=(10, -3), a=1.45, f=("w", 6.0, -2.6)),
        "crouch": dict(n=(14, -2), a=0.0, f=("w", 6.0, 2.6)),
        "crouch_rest": dict(n=(13, -1), a=0.15, f=("w", 6.0, 2.6)),
    }
    RECOIL = (3.0, 1.5, 0.4)
    KICK = (-0.12, -0.05, 0.0)
    FACE = dict(idle=("open", "grin"), aim=("wide", "grin"), run=("wide", "grin"), jump=("wide", "yell"),
                fire=("mad", "yell"))
    EYESET = {
        "open": (["kkkk", "wwPk", "wwwk", ".kk."], ["kk", "Pk", "kk"]),
        "wide": (["kkkk", "wwwk", "wPwk", "wwwk", ".kk."], ["kk", "kk", "Pk", "kk"]),
        "mad": (["kkkk", "wwwk", "wwPk", ".kk."], ["kk", "kP", "kk"]),
        "angry": (["....", "kkkk", "wwPk"], ["..", "kk", "Pk"]),
    }
    EYE_N, EYE_F = (1, -2), (7, -2)
    BROW = (["b..b", ".bb."], (1, -5), ["b"], (7, -4))
    BROW_ANGRY = (["bb..", "..bb"], (1, -5), ["b", "b"], (7, -4))
    NOSE = None
    MOUTH_R = (8, 5)
    BLUSH = None
    MOUTH_MAP = {"smile": "grin"}

    def __init__(self):
        super().__init__()
        self.mats = dict(
            skin=Mat("#5a2c22", "#c0805e", "#e8ae86", "#fcd2ae", "#fff0dc"),
            hair=Mat("#6a1c08", "#c2440e", "#f07a1a", "#ffb03a", "#ffe08a"),
            jacket=Mat("#3e6660", "#9cc8bc", "#cdeee4", "#effffa"),
            chef=WHITE,
            trousers=Mat("#24123a", "#462466", "#643a8e", "#8456b4"),
            boot=Mat("#6a4a06", "#d29a10", "#f8cc2a", "#fff07a", "#fffbd0"),
            copper=Mat("#4a1c0e", "#a0461e", "#d47838", "#f6aa64", "#ffe2b8"),
            tube=Mat("#0e3a20", "#1e7a3a", "#36b04e", "#7ae07a"),
            steel=STEEL, kwood=KWOOD, gold=GOLD,
            lens=Mat("#0c2a36", "#1e6a80", "#46b4c8", "#b4f4ff", "#ffffff"),
        )

    def sleeve_mat(self):
        return self.mats["jacket"]

    # -------------------------------------------- body
    def draw_back(self, cv, f):
        m = self.mats
        for k, (x, w) in enumerate(((-12.5, 3.4), (-8.8, 3.4))):
            a, b = f.T((x, -27.0)), f.T((x, -8.0))
            cv.part("tank", m["copper"], [("cap", *a, *b, w, w)], kind="body", R=w, far=1 - k)
            cv.part("valve", STEEL, [("cap", *a, *add(a, rot((0, -3.0), f.lean)), 1.2, 1.0)], kind="body", R=1.0, weight=2)
        g = f.T((-14.0, -18.0))
        cv.part("gauge", STEEL, [("circ", *g, 2.4)], kind="body", R=1.6)
        cv.stamp(["w.", ".k"], round(g[0]) - 1, round(g[1]) - 1, {"w": "#fffdf6", "k": "#2a1420"}, len(cv.parts) - 1)

    def draw_torso(self, cv, f: Fig):
        m = self.mats
        c = f.cloth
        coat = [(-6.0, -28.0), (-7.6, -22.0), (-7.0, -12.0), (-7.4 - c, 0.0), (-8.6 - 2.2 * c, 11.0), (-1.0 - 1.5 * c, 12.0),
                (2.0, 0.0), (5.0, -12.0), (7.6, -22.0), (5.5, -28.0), (2.0, -30.0)]
        cv.part("coat", m["jacket"], [("poly", tpts(f, coat))], kind="body", R=4.0)
        front = [(2.0, -28.5), (6.0, -27.5), (8.4, -21.0), (7.0, -12.0), (6.0, -4.0), (5.5, 1.0), (2.0, 1.0), (3.0, -12.0)]
        jk = cv.part("chefjk", m["chef"], [("poly", tpts(f, front))], kind="body", R=3.0)
        for by in (-21.0, -16.0, -11.0, -6.0):
            p = f.T((5.5, by))
            cv.stamp(["g"], round(p[0]), round(p[1]), {"g": m["chef"].ramp[0]}, jk)
        # lapel of the coat over the jacket, pens in the breast pocket
        lap = [(1.5, -29.0), (4.0, -27.0), (3.0, -14.0), (1.0, -14.0)]
        cv.part("lapel", m["jacket"], [("poly", tpts(f, lap))], kind="body", R=1.5, bias=-0.15)
        for k, col in enumerate(("#e83a3a", "#3a7ae8")):
            p = f.T((-2.5 + k * 1.6, -21.5))
            cv.stamp(["c", "c", "k"], round(p[0]), round(p[1]), {"c": col, "k": "#2a1420"}, jk)
        # straps of the backpack
        cv.part("strapE", LEATHER, [("cap", *f.T((-3.5, -28.0)), *f.T((-4.5, -12.0)), 1.2, 1.2)], kind="body", R=1.0)

    # -------------------------------------------- head
    def hair_shapes(self, f, frizz=1.0, seed=3):
        rnd = random.Random(seed)
        pts = []
        n = 15
        for k in range(n):
            a = math.pi * 0.55 + (math.pi * 1.35) * k / (n - 1)     # from the lower back over the top to the front
            r = (11.5 if k % 2 == 0 else 7.6) * frizz + rnd.uniform(-1.0, 1.0)
            pts.append((math.cos(a) * r - 2.0, math.sin(a) * r * 0.95 - 3.0))
        pts.append((4.0, -6.5))
        pts.append((-1.0, -3.0))
        pts.append((-4.5, 2.0))
        return [("poly", hpts(f, pts))]

    def draw_head(self, cv, f: Fig):
        m = self.mats
        frizz = f.P.get("frizz", 1.0)
        self.neck_part(cv, f, 2.2)
        cl = tpts(f, [(-1.0, -30.5), (5.0, -30.5), (6.0, -27.5), (-1.5, -27.0)])
        cv.part("collar", m["chef"], [("poly", cl)], kind="upper", R=1.2)
        hs = head_shapes(f, 8.4, 9.0, jaw=(3.4, 3.4, 5.4, 5.6), nose=(8.5, 0.6, 1.9))
        hs.append(("cap", *hp(f, (7.0, -1.0)), *hp(f, (10.6, 1.8)), 1.4, 1.0))   # long pointed nose
        cv.part("hairback", m["hair"], self.hair_shapes(f, frizz), kind="upper", R=3.5)
        head = cv.part("head", m["skin"], hs, kind="upper", R=4.0)
        cv.part("ear", m["skin"], [("ell", *hp(f, (-2.4, 1.2)), 1.7, 2.3, f.head_tilt)], kind="upper", R=1.4)
        side = [("poly", hpts(f, [(-3.5, -6.0), (2.0, -9.0), (0.0, -5.0), (-2.0, -1.0), (-2.6, 3.0), (-5.0, 2.0)]))]
        cv.part("hairside", m["hair"], side, kind="upper", R=2.0)
        draw_face(self, cv, f, head)
        # goggles pushed up on the forehead
        cv.part("gstrap", LEATHER, [("cap", *hp(f, (-6.0, -5.0)), *hp(f, (5.0, -7.2)), 1.1, 1.1)], kind="upper", R=1.0)
        for k, (x, r) in enumerate(((2.6, 2.6), (7.2, 2.0))):
            cv.part("goggle", m["gold"], [("circ", *hp(f, (x, -7.0)), r + 0.9)], kind="upper", R=1.5)
            cv.part("lens", m["lens"], [("circ", *hp(f, (x, -7.0)), r - 0.3)], kind="upper", R=r, weight=2)
        if not f.P.get("nohat"):
            dx, dy, tl = f.hat
            self.draw_hat(cv, add(hp(f, (-1.5, -10.0)), (dx, dy)), f.head_tilt + tl - 0.42, dx * 0.3, dy * 0.3)

    def draw_hat(self, cv, base, t, dx=0.0, dy=0.0):
        m = self.mats
        top = add(base, rot((-0.5 + dx, -9.0 + dy), t))
        puff = [("poly", [add(base, rot(p, t)) for p in [(-5.4, 0.0), (5.4, 0.0), (6.4, -6.5), (-6.2, -6.5)]]),
                ("ell", *top, 7.0, 3.6, t)]
        tq = cv.part("toque", m["chef"], puff, kind="upper", R=4.0)
        for k in (-3.0, 0.0, 3.0):
            cv.paint([("cap", *add(base, rot((k, 0.0), t)), *add(base, rot((k * 1.15, -9.0), t)), 0.5, 0.5)],
                     color=m["chef"].ramp[0], within=[tq])
        cv.part("tband", m["chef"], [("poly", [add(base, rot(p, t)) for p in [(-5.8, -0.6), (5.8, -0.6), (5.6, 2.2), (-5.6, 2.2)]])],
                kind="upper", R=1.4, bias=-0.05)

    # -------------------------------------------- weapon: the foam siphon on a hose
    def siphon(self, wr, ang):
        c = add(wr, polar(ang, 2.4))
        return lambda u, v: add(c, rot((u, v), ang))

    def draw_weapon(self, cv, f, wr, ang, far):
        T = self.siphon(wr, ang)
        m = self.mats
        # hose from the bottle's base back to the tanks
        tank = f.T((-9.0, -10.0))
        a = T(-3.0, 1.0)
        mid = add(lerp(a, tank, 0.5), (0, 5.0))
        cv.part("hose", m["tube"], [("cap", *a, *mid, 1.1, 1.1), ("cap", *mid, *tank, 1.1, 1.1)], kind="upper", R=1.0,
                behind=True)
        cv.part("bottle", STEEL, [("cap", *T(-3.0, 0.0), *T(7.5, 0.0), 3.1, 3.1)], kind="upper", R=3.0)
        cv.part("bband", m["tube"], [("cap", *T(1.0, 0.0), *T(2.6, 0.0), 3.3, 3.3)], kind="upper", R=2.0)
        cv.part("bhead", m["gold"], [("cap", *T(8.0, 0.0), *T(10.0, 0.0), 2.4, 2.4), ("cap", *T(8.5, -2.0), *T(4.0, -4.6), 0.9, 0.9)],
                kind="upper", R=1.6)
        cv.part("nozzle", STEEL, [("cap", *T(10.0, 0.0), *T(14.0, 0.0), 1.6, 1.0)], kind="upper", R=1.0, weight=2)

    def muzzle(self, f):
        return self.siphon(f.wr_n, f.hang[0])(15.0, 0.0)

    # -------------------------------------------- full-body frames
    def bones(self, cv, f):
        """The x-ray: a flat bright silhouette with dark bones (drawn after the flash recolour)."""
        bone = Mat("#2a1420", "#2a1420", "#2a1420", "#2a1420")
        for a, b in ((f.hip_n, f.knee_n), (f.knee_n, f.ank_n), (f.hip_f, f.knee_f), (f.knee_f, f.ank_f),
                     (f.sh_n, f.el_n), (f.el_n, f.wr_n), (f.pel, f.neck)):
            cv.part("bone", bone, [("cap", *a, *b, 0.9, 0.9)], kind="upper", flat=1, weight=2)
        for k in range(4):
            y = -24 + k * 4
            cv.part("rib", bone, [("cap", *f.T((-4, y)), *f.T((5, y + 1.5)), 0.6, 0.6)], kind="upper", flat=1, weight=2)
        skull = [("ell", *hp(f, (1.5, -1.0)), 6.0, 6.4, 0), ("ell", *hp(f, (3.5, 4.0)), 3.2, 2.4, 0)]
        sk = cv.part("skull", bone, skull, kind="upper", flat=1)
        hx, hy = f.head
        cv.stamp(["yy..y", "yy..y", ".....", "..yy."], hx + 1, hy - 2, {"y": "#fffdf6"}, sk)

    def full_die(self, i):
        """Frizzled: flashes as an x-ray skeleton, smokes charred with frizzy hair, then flops face first."""
        stand = dict(feet=((6, 0, 0), (-6, 0, 0)), hn=(10, -6), hf=(-8, -10), an=-0.8, af=-2.2, items=("weapon", "open"),
                     elbow=(-1, 1))
        if i == 0:
            return self.mk(dpel=(-2, 0.5), lean=-0.2, face=("wide", "yell"), hat=(0, -4, -0.3), **stand), None
        charred = char_tone
        if i in (1, 3):
            P = self.mk(dpel=(0, -1), face=("wide", "yell"), hat=(0, -6, 0.3), frizz=1.35, **stand)

            def post(cv, f, chef):
                cv.recolor(lambda c: (255, 236, 92))
                chef.bones(cv, f)
            return P, post
        if i in (2, 4):
            P = self.mk(face=("blink", "o"), hat=(0, -2, 0.5), frizz=1.3, **stand)

            def post(cv, f, chef, i=i):
                cv.recolor(charred, keep=("#fffdf6",))
                h = f.head
                foam_puffs(cv, [(h[0] - 2, h[1] - 18 - i, 3.0), (h[0] + 3, h[1] - 23 - i, 2.2)], seed=i)
            return P, post
        ang = {5: 0.45, 6: 1.1, 7: 1.57}[i]
        P = self.mk(face=("x", "o"), hat=(0, -2, 0.6), frizz=1.3, feet=((5, 0, 0), (-4, 0, 0)), hn=(9, 6), hf=(-6, 6),
                    an=1.0, af=1.6, items=("weapon", "open"))

        def extra(cv, f, chef, i=i):
            cv.recolor(charred, keep=("#fffdf6",))
            if i == 7:
                foam_puffs(cv, [(30, 44, 2.6), (33, 38, 1.8)], seed=7)
        return P, lie_post(ang, lift=None, extra=extra, dx=-8.0 if i == 7 else -3.0 if i == 6 else 0.0)

    def full_win(self, i):
        """Jumps for joy, siphon to the sky, foam everywhere."""
        hop = [0, -4, -7, -4, 0, 1][i]
        h = max(0.0, -hop - 1)
        P = self.mk(dpel=(0, hop), lean=-0.15, feet=((6, h * 1.2, 0.3 if h else 0), (-4, h, 0.4 if h else 0)),
                    hn=(13, -14), an=-1.2, hf=(-8, -8), af=-2.0, items=("weapon", "open"),
                    face=("mad", "yell") if i % 2 else ("wide", "grin"), hat=(0, [0, 3, 4, 2, -1, -1][i], 0.1),
                    cloth=[0, -0.6, -1.0, -0.6, 0.3, 0.4][i], elbow=(-1, 1))

        def post(cv, f, chef, i=i):
            m = chef.muzzle(f)
            k = (i % 3)
            foam_puffs(cv, [(m[0] + 2, m[1] - 2 - 2 * k, 2.6 + k * 0.4), (m[0] + 5, m[1] - 6 - k, 2.0),
                            (m[0] - 1, m[1] - 7 - k, 1.6)], seed=i)
        return P, post

    def full_select(self, i):
        """Rubs his hands, bouncing on his toes, cackling."""
        P = self.mk(dpel=(0, [0, -1, 0, -1][i]), lean=0.12, feet=((5, 0, 0), (-5, 0, 0)), hn=(9, 4 + [0, 1, 0, 1][i]),
                    hf=(10, 4 + [1, 0, 1, 0][i]), an=-0.3, af=0.2, items=("fist", "fist"),
                    face=("mad", "grin") if i % 2 else ("wide", "grin"), head=(0.08, 0, [0, 1, 0, 1][i]),
                    hat=(0, [0, -1, 0, -1][i], 0))
        return P, None

    def draw(self, cv, f):
        super().draw(cv, f)
        # the siphon hangs on its hose when no hand holds it (select screen)
        if self.on("upper") and "weapon" not in f.items:
            self.draw_weapon(cv, f, f.T((6.0, 2.0)), 1.45, far=True)
