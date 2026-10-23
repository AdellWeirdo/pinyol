"""The shared pose table: legs frames, torso frames and their reference partners. Each cook tweaks it through its
STYLE (stride, bob, lean...) and its AIM table (how it holds its weapon), and supplies its own full-body frames.

Contract (paella/art):
  legs  96x72, pin (48,14), soles on row 70     -> world origin = pin, FLOOR = 56
  torso 128x112, pin (64,96)
  full  128x112, feet (64,108)
"""
from __future__ import annotations

import math

from chefbase import FLOOR
from chefkit import add, polar, rot

LEGS = ["idle"] + [f"run_{i}" for i in range(8)] + [f"jump_{i}" for i in range(4)] + ["crouch"] + [f"crawl_{i}" for i in range(6)]
TORSO = ([f"idle_{i}" for i in range(4)] + [f"run_{i}" for i in range(8)] + ["jump_0", "jump_1", "crouch_0", "crouch_1",
         "aim_fwd", "aim_up", "aim_down"] + [f"fire_fwd_{i}" for i in range(3)] + [f"fire_up_{i}" for i in range(3)]
         + [f"fire_down_{i}" for i in range(3)] + [f"crouch_fire_{i}" for i in range(3)] + [f"throw_{i}" for i in range(4)]
         + [f"stab_{i}" for i in range(4)] + ["crouch_aim"])
FULL = ["hurt_0", "hurt_1"] + [f"die_{i}" for i in range(8)] + [f"win_{i}" for i in range(6)] + [f"select_{i}" for i in range(4)]

CLIP = 13          # world row: body pixels above go to the torso sheet, below to the legs sheet
OVERLAP = 4        # the legs sheet keeps this many rows of body above CLIP (hidden under the torso)


def smooth(u):
    u = max(0.0, min(1.0, u))
    return u * u * (3 - 2 * u)


def shoulder(chef, pel, lean, breath=0.0):
    s = chef.D["shoulder"]
    return add(pel, rot((s[0], s[1] - breath), lean))


def far_shoulder(chef, pel, lean, breath=0.0):
    s = chef.D["shoulder"]
    return add(pel, rot((s[0] - chef.D.get("sh_back", 2.5), s[1] - breath + 0.5), lean))


# ------------------------------------------------------------------ legs

def run_foot(chef, p):
    """Ankle target (x, y, pitch) at run phase p in [0,1): contact at p=0 (forward), push-off at ~0.42."""
    st = chef.STYLE
    S, H = st["stride"], st["lift"]
    g = chef.ground()
    p %= 1.0
    if p < 0.42:
        u = p / 0.42
        x = S - 2 * S * u
        return (x, g, -0.15 + 0.5 * u if u > 0.6 else -0.15 * (1 - u / 0.6))
    u = (p - 0.42) / 0.58
    x = -S + 2 * S * smooth(u) - st["kick"] * math.sin(math.pi * u) * (1 - u)
    y = g - H * math.sin(math.pi * min(1.0, u * 1.15)) ** 0.8 - st["kick"] * 0.5 * math.sin(math.pi * u) * (1 - u)
    pitch = 0.75 * (1 - u) - 0.25 * u
    return (x, min(g, y), pitch)


def legs_pose(chef, name):
    """Lower-body pose (pelvis, lean, feet, cloth) for a legs frame; torso frames reuse these for their family."""
    st = chef.STYLE
    d = chef.D
    g = chef.ground()
    hy = d["hip_y"]
    if name == "idle":
        return dict(pelvis=(0.0, hy + 1.0), lean=st["lean_idle"], feet=chef.stand_feet(), cloth=0.0)
    if name.startswith("run_"):
        i = int(name[4:])
        p = i / 8
        bob = st["bob"] * math.cos(4 * math.pi * p)
        sway = st.get("sway", 0.0) * math.sin(2 * math.pi * p)
        fn = run_foot(chef, p)
        ff = run_foot(chef, p + 0.5)
        return dict(pelvis=(sway * 0.3, hy + bob), lean=st["lean_run"] + sway * 0.04, feet=(fn, ff),
                    cloth=-0.6 - 0.4 * math.cos(4 * math.pi * p))
    if name.startswith("jump_"):
        i = int(name[5:])
        if i == 0:   # rise: front knee up, back leg trailing
            return dict(pelvis=(0, hy), lean=0.05, feet=((6, hy + 16, 0.5), (-5, hy + 22, 0.7)), cloth=0.8)
        if i == 1:   # peak: both tucked
            return dict(pelvis=(0, hy), lean=0.06, feet=((5, hy + 13, 0.6), (-2, hy + 15, 0.8)), cloth=0.3)
        if i == 2:   # fall: legs reaching down, apart
            return dict(pelvis=(0, hy), lean=0.0, feet=((5, hy + 21, -0.1), (-6, hy + 19.5, 0.5)), cloth=-0.6)
        # land squash (soles on the floor)
        return dict(pelvis=(0, hy + 5), lean=0.10, feet=((5.5, g, 0.0), (-6.5, g, 0.0)), cloth=-0.9)
    if name == "crouch":
        return crouch_base(chef, 0.0)
    if name.startswith("crawl_"):
        i = int(name[6:])
        return crawl_pose(chef, i)
    raise KeyError(name)


def crouch_base(chef, breath):
    d = chef.D
    g = chef.ground()
    st = chef.STYLE
    drop = st["crouch_drop"]
    return dict(pelvis=(-2.0, d["hip_y"] + drop), lean=st["crouch_lean"],
                feet=((8.0, g, 0.0), (-6.0, g - 0.5, 0.55)), cloth=-0.3, breath=breath)


def crawl_pose(chef, i):
    """A crouched duck-walk: short shuffling steps, the pelvis bobbing."""
    P = crouch_base(chef, 0.0)
    g = chef.ground()
    p = i / 6
    S = 4.5
    def foot(q, base_x):
        q %= 1.0
        if q < 0.5:
            u = q / 0.5
            return (base_x + S - 2 * S * u, g, 0.0 if base_x > 0 else 0.5)
        u = (q - 0.5) / 0.5
        return (base_x - S + 2 * S * smooth(u), g - 3.5 * math.sin(math.pi * u), 0.35)
    P["feet"] = (foot(p, 6.0), foot(p + 0.5, -5.0))
    P["pelvis"] = (P["pelvis"][0], P["pelvis"][1] + 0.8 * math.cos(4 * math.pi * p))
    P["cloth"] = -0.3 - 0.3 * math.cos(4 * math.pi * p)
    return P


# ------------------------------------------------------------------ torso

def family(name):
    """The legs frame a torso frame is drawn over (hidden behind it) and its lower-body pose."""
    if name.startswith("run_"):
        return name
    if name.startswith("jump_"):
        return "jump_1" if name == "jump_1" else "jump_0"
    if name.startswith("crouch") :
        return "crouch"
    if name in ("aim_down",) or name.startswith("fire_down"):
        return "jump_1"
    return "idle"


def with_aim(chef, P, aim, recoil=0.0, kick=0.0):
    """Set both hands for an aim ('rest', 'fwd', 'up', 'down', 'run', 'crouch') with recoil (px back) and kick (rad)."""
    spec = chef.AIM[aim]
    pel, lean, br = P["pelvis"], P.get("lean", 0.0), P.get("breath", 0.0)
    sh = shoulder(chef, pel, lean, br)
    a = spec["a"] + kick
    base = spec["a"]
    n = spec["n"]
    wr = add(sh, n)
    wr = add(wr, polar(base, -recoil))
    hands = [wr, None]
    items = [spec.get("item", "weapon"), spec.get("fitem", "fist")]
    hang = [a, spec.get("fa", 0.6)]
    f = spec.get("f")
    if f is not None:
        if f[0] == "w":   # far hand on the weapon: distance along it, offset across it
            hands[1] = add(add(wr, polar(a, f[1])), polar(a + math.pi / 2, f[2]))
            hang[1] = a + f[3] if len(f) > 3 else a
        else:             # free far hand, offset from the far shoulder
            fs = far_shoulder(chef, pel, lean, br)
            hands[1] = add(fs, f[1])
    P["hands"] = tuple(hands)
    P["hang"] = tuple(hang)
    P["items"] = tuple(items)
    P["elbow"] = tuple(spec.get("elbow", (-1, -1)))
    P["choke"] = spec.get("choke", 0.0)
    return P


def torso_pose(chef, name):
    st = chef.STYLE
    base = dict(legs_pose(chef, family(name)))
    base.setdefault("breath", 0.0)
    base["face"] = chef.FACE["aim"]
    if name.startswith("idle_"):
        i = int(name[5:])
        br = [0.0, 0.5, 1.0, 0.5][i]
        base["breath"] = br
        base["head"] = (0.0, 0, [0, 0, 1, 1][i] * 0)
        base["hat"] = (0.0, [0, 0, -0.6, -0.3][i], 0.0)
        base["face"] = chef.FACE["idle"] if i != 2 else (("blink",) + chef.FACE["idle"][1:])
        return with_aim(chef, base, "rest")
    if name.startswith("run_"):
        i = int(name[4:])
        p = i / 8
        P = with_aim(chef, base, "run")
        bob = st["bob"] * math.cos(4 * math.pi * p)
        P["hat"] = (-0.8, -bob * 0.8, -0.06 - 0.04 * math.sin(4 * math.pi * p))
        sw = math.sin(2 * math.pi * p)
        hn, hf = P["hands"]
        hn = add(hn, (0.8 * sw, 0.5 * math.cos(4 * math.pi * p)))
        if chef.AIM["run"].get("f", (None,))[0] == "s":   # a free far arm pumps
            hf = add(hf, (5.5 * sw, -2.0 * abs(sw)))
        else:
            hf = add(hf, (0.8 * sw, 0.5 * math.cos(4 * math.pi * p)))
        P["hands"] = (hn, hf)
        P["face"] = chef.FACE["run"]
        return P
    if name.startswith("jump_"):
        i = int(name[5:])
        P = with_aim(chef, base, "run")
        hn, hf = P["hands"]
        P["hands"] = (add(hn, (0, -2 - i)), add(hf, (-1, -4 - 2 * i)))
        P["hat"] = (0.6, 1.2 if i == 0 else -0.6, 0.06)
        P["face"] = chef.FACE["jump"]
        return P
    if name.startswith("crouch_fire_"):
        i = int(name[12:])
        P = with_aim(chef, base, "crouch", recoil=chef.RECOIL[i], kick=chef.KICK[i])
        P["face"] = chef.FACE["fire"]
        P["head"] = (-0.04 * (3 - i), -0.5 * (2 - i), 0)
        return P
    if name == "crouch_aim":
        return with_aim(chef, base, "crouch")
    if name.startswith("crouch_"):
        i = int(name[7:])
        base["breath"] = 0.5 * i
        base["face"] = chef.FACE["idle"]
        return with_aim(chef, base, "crouch_rest")
    if name in ("aim_fwd", "aim_up", "aim_down"):
        return with_aim(chef, base, name[4:])
    if name.startswith("fire_"):
        aim, i = name[5:].rsplit("_", 1)
        i = int(i)
        P = with_aim(chef, base, aim, recoil=chef.RECOIL[i], kick=chef.KICK[i] * (1 if aim != "down" else -1))
        P["face"] = chef.FACE["fire"]
        P["head"] = (-0.04 * (2 - i), -0.6 * (2 - i), 0)
        P["hat"] = (-0.5 * (2 - i), 0, -0.04 * (2 - i))
        return P
    if name.startswith("throw_"):
        return chef.throw_pose(base, int(name[6:]))
    if name.startswith("stab_"):
        return chef.stab_pose(base, int(name[5:]))
    raise KeyError(name)
