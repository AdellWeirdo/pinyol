"""The shared cook: skeleton (pose -> joints) and the body parts every cook has (legs, boots, arms, hands, neck).
Each cook (chefcast.py) is a subclass that supplies its proportions, palette, clothes, head, props and weapon.

Pose dictionary (world coordinates: x forward, y down, origin = the hip pin; the floor is y = FLOOR):
    pelvis (x, y)          the hip joint centre
    lean                   torso tilt in radians (+ = forward)
    feet  ((x, y, pitch), (x, y, pitch))   near and far ankle targets; pitch + = toes down
    hands ((x, y), (x, y)) near and far wrist targets (None = the cook's rest pose for that hand)
    hang  (a_near, a_far)  hand/item direction in radians (0 = forward, -pi/2 = up)
    items (near, far)      what each hand holds: 'weapon', 'knife', 'fist', 'open', 'grip', 'flat', 'none'
    elbow (b_near, b_far)  IK bend sign for each arm
    head  (tilt, dx, dy)   relative to the neck
    face  (eyes, mouth)
    hat   (dx, dy, tilt)   secondary motion of the hat/hair (lags a frame behind the body)
    cloth                  -1..1 swing of aprons, tails, sashes
    breath                 0..1 chest expansion
"""
from __future__ import annotations

import math

from chefkit import Canvas, Mat, add, ik, lerp, polar, rot

FLOOR = 56          # the outline row under the soles (legs frame row 70)
OUTLINE = "#2a1420"

# shared materials
WHITE = Mat("#6c5a6e", "#b7b3cc", "#e9e6f0", "#fffdf6", "#ffffff")
EYEW = "#fffdf6"


class Fig:
    """Joints of one pose for one cook."""

    def __init__(self, chef, P: dict):
        d = chef.D
        self.chef, self.P = chef, P
        self.pel = P.get("pelvis", (0.0, d["hip_y"]))
        self.lean = P.get("lean", 0.0)
        br = P.get("breath", 0.0)
        self.T = lambda p: add(self.pel, rot(p, self.lean))
        sh = d["shoulder"]
        self.sh_n = self.T((sh[0], sh[1] - br))
        self.sh_f = self.T((sh[0] - d.get("sh_back", 2.5), sh[1] - br + 0.5))
        self.neck = self.T((d["neck"][0], d["neck"][1] - br))
        tilt, hdx, hdy = P.get("head", (0.0, 0.0, 0.0))
        hc = add(self.neck, rot(d["head_off"], self.lean * 0.6 + tilt))
        self.head = (round(hc[0] + hdx), round(hc[1] + hdy))
        self.head_tilt = tilt + self.lean * 0.6
        # legs
        hx = d.get("hip_dx", 1.5)
        self.hip_n = add(self.pel, rot((hx, 0), self.lean))
        self.hip_f = add(self.pel, rot((-hx, -0.5), self.lean))
        fn, ff = P.get("feet", chef.stand_feet())
        self.ank_n, self.pitch_n = chef.plant((fn[0], fn[1]), fn[2]), fn[2]
        self.ank_f, self.pitch_f = chef.plant((ff[0], ff[1]), ff[2]), ff[2]
        self.knee_n = ik(self.hip_n, self.ank_n, d["thigh"], d["shin"], 1)
        self.knee_f = ik(self.hip_f, self.ank_f, d["thigh"], d["shin"], 1)
        # arms
        hn, hf = P.get("hands", (None, None))
        rn, rf = chef.rest_hands(self)
        self.wr_n = hn if hn is not None else rn
        self.wr_f = hf if hf is not None else rf
        bn, bf = P.get("elbow", (-1, -1))
        self.el_n = ik(self.sh_n, self.wr_n, d["upper"], d["fore"], bn)
        self.el_f = ik(self.sh_f, self.wr_f, d["upper"], d["fore"], bf)
        self.hang = P.get("hang", (0.6, 0.6))
        self.items = P.get("items", ("weapon", "fist"))
        self.face = P.get("face", ("open", "smile"))
        self.hat = P.get("hat", (0.0, 0.0, 0.0))
        self.cloth = P.get("cloth", 0.0)


class Chef:
    """Base cook. Subclasses set D (dimensions), mats, and override the drawing hooks."""

    id = "base"
    D: dict = {}

    def __init__(self):
        self.ids = {}

    # ------------------------------------------------ poses the cook falls back to
    def stand_feet(self):
        g = FLOOR - self.D["ankle_h"]
        return (5.0, g, 0.0), (-5.5, g, 0.0)

    def ground(self):
        return FLOOR - self.D["ankle_h"]

    def rest_hands(self, f: Fig):
        return add(f.sh_n, (4, self.D["upper"] + 2)), add(f.sh_f, (-2, self.D["upper"] + 3))

    # ------------------------------------------------ rendering
    def render(self, P: dict, w: int, h: int, ox: int, oy: int, kinds=("upper", "body", "lower"), post=None) -> Canvas:
        cv = Canvas(w, h, ox, oy, OUTLINE)
        f = Fig(self, P)
        self.cv, self.f, self.kinds = cv, f, set(kinds)
        self.draw(cv, f)
        if post:
            post(cv, f, self)
        return cv

    def on(self, kind):
        return kind in self.kinds

    def draw(self, cv: Canvas, f: Fig):
        if self.on("upper"):
            self.draw_arm(cv, f, far=True)
        if self.on("lower"):
            self.draw_leg(cv, f, far=True)
        if self.on("body"):
            self.draw_back(cv, f)
        if self.on("lower"):
            self.draw_leg(cv, f, far=False)
        if self.on("body"):
            self.draw_lower_clothes(cv, f)
            self.draw_torso(cv, f)
        if self.on("upper"):
            self.draw_head(cv, f)
            self.draw_arm(cv, f, far=False)

    # ------------------------------------------------ legs
    def leg_mats(self):
        return self.mats["trousers"], self.mats["boot"]

    def draw_leg(self, cv: Canvas, f: Fig, far: bool):
        d = self.D
        hip, knee, ank = (f.hip_f, f.knee_f, f.ank_f) if far else (f.hip_n, f.knee_n, f.ank_n)
        pitch = f.pitch_f if far else f.pitch_n
        tr, bt = self.leg_mats()
        k = 1 if far else 0
        g = f"leg{'F' if far else 'N'}"
        rt, rk, ra = d["leg_r"]
        cv.part(g + "thigh", tr, [("cap", *hip, *knee, rt, rk), ("circ", *hip, rt + 0.5)], kind="lower",
                group=g, far=k, R=rt)
        cv.part(g + "shin", tr, [("cap", *knee, *ank, rk, ra)], kind="lower", group=g, far=k, R=rk)
        self.draw_boot(cv, ank, pitch, far, g)

    def boot_pts(self, ank, pitch):
        d = self.D
        L, hgt = d["foot"], d["ankle_h"]
        pts = [(-3.0, -2.0), (1.5, -2.5), (L - 3, -0.5), (L, 1.5), (L, hgt - 0.1), (-3.5, hgt - 0.1), (-4.0, 1.0)]
        return [add(ank, rot(p, pitch)) for p in pts]

    def plant(self, ank, pitch):
        """Lift an ankle so no part of the boot sinks under the floor (a pitched foot stands on its toe or heel)."""
        low = max(p[1] for p in self.boot_pts(ank, pitch))
        lim = FLOOR - 0.1
        return (ank[0], ank[1] - (low - lim)) if low > lim else ank

    def draw_boot(self, cv, ank, pitch, far, g):
        bt = self.leg_mats()[1]
        pts = self.boot_pts(ank, pitch)
        cv.part(g + "boot", bt, [("poly", pts)], kind="lower", far=1 if far else 0, R=2.0)

    # ------------------------------------------------ arms
    def sleeve_mat(self):
        return self.mats["jacket"]

    def draw_arm(self, cv: Canvas, f: Fig, far: bool):
        d = self.D
        sh, el, wr = (f.sh_f, f.el_f, f.wr_f) if far else (f.sh_n, f.el_n, f.wr_n)
        item = f.items[1 if far else 0]
        ang = f.hang[1 if far else 0]
        k = 1 if far else 0
        g = f"arm{'F' if far else 'N'}"
        ru, rf, rw = d["arm_r"]
        if not far and item == "weapon":
            self.draw_weapon(cv, f, wr, ang, far=False)
        if not far and item == "knife":
            self.draw_knife(cv, wr, ang, far=False)
        sm = self.sleeve_mat()
        cv.part(g + "up", sm, [("cap", *sh, *el, ru, rf), ("circ", *sh, ru + 0.3)], kind="upper", group=g, far=k, R=ru)
        self.draw_forearm(cv, f, el, wr, far, g)
        self.draw_hand(cv, wr, ang, item, far)
        if far and item == "weapon":
            self.draw_weapon(cv, f, wr, ang, far=True)
        if far and item == "knife":
            self.draw_knife(cv, wr, ang, far=True)

    def draw_forearm(self, cv, f, el, wr, far, g):
        ru, rf, rw = self.D["arm_r"]
        cv.part(g + "fore", self.sleeve_mat(), [("cap", *el, *wr, rf, rw)], kind="upper", group=g,
                far=1 if far else 0, R=rf)

    def draw_hand(self, cv: Canvas, wr, ang, item, far):
        skin = self.mats["skin"]
        k = 1 if far else 0
        c = add(wr, polar(ang, 2.2))
        if item in ("none",):
            return
        if item == "open":
            sh = [("ell", *c, 3.2, 2.4, ang), ("cap", *c, *add(c, polar(ang - 0.5, 4.2)), 1.0, 0.8),
                  ("cap", *c, *add(c, polar(ang + 0.1, 4.6)), 1.0, 0.8), ("cap", *c, *add(c, polar(ang + 0.6, 4.0)), 1.0, 0.8),
                  ("cap", *c, *add(c, polar(ang - 1.4, 3.6)), 1.0, 0.8)]
        elif item == "flat":
            sh = [("ell", *add(c, polar(ang, 1.0)), 4.0, 2.0, ang), ("cap", *c, *add(c, polar(ang - 1.3, 3.0)), 1.0, 0.8)]
        else:
            sh = [("ell", *c, 3.0, 2.7, ang), ("cap", *add(c, polar(ang - 1.2, 1.2)), *add(c, polar(ang - 0.5, 3.0)), 1.1, 0.9)]
        cv.part("hand" + ("F" if far else "N"), skin, sh, kind="upper", far=k, R=2.0)

    def draw_knife(self, cv: Canvas, wr, ang, far):
        """The big carving knife used for the stab: dark handle in the fist, a long wide blade."""
        m = self.mats
        c = add(wr, polar(ang, 2.2))
        a = add(c, polar(ang, -3.5))
        b = add(c, polar(ang, 2.5))
        cv.part("knifeH", m["kwood"], [("cap", *a, *b, 1.3, 1.3)], kind="upper", R=1.0, weight=2)
        p0 = add(c, polar(ang, 2.5))
        n = polar(ang + math.pi / 2, 1.0)
        tip = add(c, polar(ang, 17.0))
        pts = [add(p0, n, -1.6), add(p0, n, 2.4), add(add(c, polar(ang, 12)), n, 2.6), add(tip, n, 0.6), tip,
               add(add(c, polar(ang, 9)), n, -1.6)]
        cv.part("knifeB", m["steel"], [("poly", pts)], kind="upper", R=1.5, weight=2, tilt=(0, -0.3))

    # ------------------------------------------------ hooks for the cooks
    def draw_back(self, cv, f):
        pass

    def draw_lower_clothes(self, cv, f):
        pass

    def draw_torso(self, cv, f):
        raise NotImplementedError

    def draw_head(self, cv, f):
        raise NotImplementedError

    def draw_weapon(self, cv, f, wr, ang, far):
        pass

    def muzzle(self, f: Fig):
        """Where the projectile leaves (world coords) for the current pose."""
        raise NotImplementedError

    # ------------------------------------------------ action poses shared by all cooks
    STYLE = dict(stride=7.0, lift=7.0, kick=3.0, bob=1.2, lean_idle=0.0, lean_run=0.14, crouch_drop=10.0,
                 crouch_lean=0.32)
    RECOIL = (3.0, 1.6, 0.5)
    KICK = (-0.22, -0.10, -0.02)
    FACE = dict(idle=("open", "smile"), aim=("cool", "smile"), run=("open", "smile"), jump=("wide", "open"),
                fire=("angry", "grit"))
    THROW = [((-9, -7), -2.4, "fist", -0.12), ((16, -8), -0.5, "open", 0.10), ((14, 3), 0.5, "open", 0.18),
             ((9, 8), 0.9, "fist", 0.06)]
    MOUTH_MAP: dict = {}
    STAB = [((-1, 7), 0.15, -0.06), ((13, 4), 0.02, 0.20), ((16, 4), 0.0, 0.24), ((7, 7), 0.15, 0.06)]

    def full_pose(self, name):
        kind, i = name.rsplit("_", 1)
        return getattr(self, "full_" + kind)(int(i))

    def mk(self, dpel=(0.0, 0.0), lean=0.0, feet=None, hn=None, hf=None, an=0.6, af=0.6, items=None, face=None,
           head=(0.0, 0.0, 0.0), hat=(0.0, 0.0, 0.0), cloth=0.0, breath=0.0, elbow=(-1, -1), **extra):
        """A full-body pose from relative specs: pelvis offset from standing, feet as (x, height above ground, pitch),
        hands relative to their shoulders."""
        from chefposes import far_shoulder, shoulder
        pel = (dpel[0], self.D["hip_y"] + dpel[1])
        g = self.ground()
        if feet is None:
            feet = self.stand_feet()
        else:
            feet = tuple((x, g - h, pt) for (x, h, pt) in feet)
        sh = shoulder(self, pel, lean, breath)
        fs = far_shoulder(self, pel, lean, breath)
        P = dict(pelvis=pel, lean=lean, feet=feet, hands=(add(sh, hn) if hn else None, add(fs, hf) if hf else None),
                 hang=(an, af), items=items or ("weapon", "fist"), face=face or self.FACE["idle"], head=head, hat=hat,
                 cloth=cloth, breath=breath, elbow=elbow)
        P.update(extra)
        return P

    def full_hurt(self, i):
        """Knocked back: arms flung, hat jumping, eyes squeezed."""
        if i == 0:
            P = self.mk(dpel=(-2, 0.5), lean=-0.22, feet=((6, 0, 0), (-6, 0, 0)), hn=(9, 4), hf=(-8, -9), an=0.6, af=-2.2,
                        items=("weapon", "open"), face=("shut", "o"), head=(-0.25, -1, 0), hat=(-2, -3, -0.25), cloth=0.8,
                        elbow=(-1, 1))
        else:
            P = self.mk(dpel=(-4, 1.0), lean=-0.32, feet=((7, 2.5, -0.3), (-6, 0, 0)), hn=(11, 0), hf=(-9, -12), an=0.2,
                        af=-2.0, items=("weapon", "open"), face=("x", "yell"), head=(-0.35, -1, 0), hat=(-3, -5, -0.35),
                        cloth=1.0, elbow=(-1, 1))
        return P, None

    def far_carry(self, P):
        """The weapon moved to the far hand, held low, while the near hand throws or stabs."""
        from chefposes import far_shoulder
        fs = far_shoulder(self, P["pelvis"], P.get("lean", 0.0))
        return add(fs, (5.0, 5.0)), -1.0

    def throw_pose(self, P, i):
        from chefposes import shoulder
        (dx, dy), ang, item, lean = self.THROW[i]
        P["lean"] = P.get("lean", 0.0) + lean
        sh = shoulder(self, P["pelvis"], P["lean"])
        fw, fa = self.far_carry(P)
        P["hands"] = (add(sh, (dx, dy)), fw)
        P["hang"] = (ang, fa)
        P["items"] = (item, "weapon")
        P["elbow"] = (-1 if i else 1, -1)
        P["face"] = ("angry", "grit") if i < 2 else ("cool", "open")
        P["hat"] = ((1.0, -0.5, 0.06), (-1.0, 0.5, -0.06), (-0.6, 0.3, -0.04), (0.2, 0, 0.0))[i]
        return P

    def stab_pose(self, P, i):
        from chefposes import shoulder
        (dx, dy), ang, lean = self.STAB[i]
        P["lean"] = P.get("lean", 0.0) + lean
        sh = shoulder(self, P["pelvis"], P["lean"])
        fw, fa = self.far_carry(P)
        P["hands"] = (add(sh, (dx, dy)), fw)
        P["hang"] = (ang, fa)
        P["items"] = ("knife", "weapon")
        P["elbow"] = (-1, -1)
        P["face"] = ("angry", "yell") if i in (1, 2) else ("angry", "grit")
        P["hat"] = ((0.6, 0, 0.04), (-1.0, 0.3, -0.07), (-0.7, 0.2, -0.05), (0.3, 0, 0.02))[i]
        return P

    def knife_box(self, f):
        c = add(f.wr_n, polar(f.hang[0], 2.2))
        a, b = add(c, polar(f.hang[0], 3.0)), add(c, polar(f.hang[0], 17.0))
        return (min(a[0], b[0]) - 1, min(a[1], b[1]) - 3, max(a[0], b[0]) + 1, max(a[1], b[1]) + 3)

    def grenade_hand(self, f):
        return add(f.wr_n, polar(f.hang[0], 2.5))

    # ------------------------------------------------ helpers for subclasses
    def neck_part(self, cv, f, r=2.6, mat=None):
        top = add(f.head, (-1.5, 4))
        return cv.part("neck", mat or self.mats["skin"], [("cap", *f.neck, *top, r, r)], kind="upper", R=r)

    def face_stamp(self, cv, rows, dx, dy, legend, pid):
        cv.stamp(rows, self.f.head[0] + dx, self.f.head[1] + dy, legend, pid)


def tpts(f: Fig, pts, extra=0.0, about=None):
    """Torso-local points -> world (rotated with the lean)."""
    if about is None:
        return [f.T(p) for p in pts]
    return [add(f.pel, rot(rot(p, extra, about), f.lean)) for p in pts]


def hpts(f: Fig, pts, tilt=None):
    """Head-local points (origin = head centre) -> world, with the head tilt."""
    t = f.head_tilt if tilt is None else tilt
    return [add(f.head, rot(p, t)) for p in pts]


def hp(f: Fig, p, tilt=None):
    return hpts(f, [p], tilt)[0]


__all__ = ["Fig", "Chef", "FLOOR", "OUTLINE", "WHITE", "tpts", "hpts", "hp", "lerp", "add", "rot", "polar", "Mat"]
