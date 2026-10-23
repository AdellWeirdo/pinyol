"""Paella de Combate: El Gran Gaviotrón animation tables -> art/boss_*.png/.json and art/boss_preview.png."""
from __future__ import annotations

import math

from PIL import Image, ImageDraw

from art_bigs_boss import (BODY, FXS, HEAD, JOINTS, LEG, POT, WING, char, flash, paint_body, paint_head, paint_leg,
                           paint_pot, paint_wing, puff, rice_dome, sparks, star, HATCH)
from art_bigs_kit import ART, CHROME, FIRE, IRON, RICE, SMOKE, Canvas, Xf, rad, rng, save_sheet

DRAW_ORDER = ["leg_r", "body", "leg_l", "pot", "wing", "head"]


def render(paint, frames):
    out = []
    for name, st in frames:
        c = paint(st)
        for f in st.get("post", []):
            f(c)
        out.append((name, c))
    return out


def fx_flash(c):
    flash(c)


def fx_char(c):
    char(c)


# ------------------------------------------------------------------ body

def body_frames():
    fr = []
    for k in range(6):
        fr.append((f"idle_{k}", dict(k=k, key=k * math.pi / 6, needle=-20 + 8 * math.sin(k * math.pi / 3),
                                     lamp=k < 3, dy=(0, 0, -1, -1, -1, 0)[k])))
    fr.append(("hurt_0", dict(k=0, key=0.3, dx=-3, needle=60, post=[fx_flash])))
    fr.append(("hurt_1", dict(k=1, key=0.3, dx=2, needle=40, post=[lambda c: sparks(c, 200, 250, 10, 26, 3)])))
    for i in range(3):
        fr.append((f"damaged_{i}", dict(k=i, key=0.5, dmg=i + 1, needle=(10, 60, 110)[i], lamp=i < 2,
                                        puffs=[] if i == 0 else [(250, 214 - i * 6, 7 + i * 2), (176, 222 - i * 4, 5 + i * 2)])))

    def boom(x, y, r, seed):
        def f(c):
            star(c, x, y, r, 9, seed)
        return f

    def fireballs(seed):
        def f(c):
            g = rng(seed)
            for _ in range(4):
                x, y, r = g.uniform(110, 300), g.uniform(220, 290), g.uniform(14, 24)
                puff(c, x, y - 10, r * 1.2, seed=int(x), dark=True)
                for i, t in enumerate((1, 2, 3, 4)):
                    c.ellipse(x, y, r * (1 - i * 0.22), r * (1 - i * 0.22) * 0.9, FIRE, tone=t, seam=(i == 0))
        return f

    fr.append(("dead_0", dict(k=0, dmg=3, key=0.5, needle=140, lamp=False, post=[boom(190, 256, 46, 1), boom(290, 240, 30, 2)])))
    fr.append(("dead_1", dict(k=1, dmg=3, key=0.5, needle=150, lamp=False, dy=2, post=[fireballs(5)])))
    fr.append(("dead_2", dict(k=2, dmg=3, key=0.6, needle=150, lamp=False, dy=4,
                              puffs=[(150, 210, 14), (230, 200, 16), (300, 214, 12)], post=[fx_char])))
    fr.append(("dead_3", dict(k=3, dmg=3, key=0.6, needle=150, lamp=False, dy=5,
                              puffs=[(170, 196, 8), (250, 186, 10)], post=[fx_char])))
    return fr


# ------------------------------------------------------------------ head

def head_frames():
    fr = []
    for k in range(4):
        fr.append((f"idle_{k}", dict(visor=(0, 0.5, 1, 0.5)[k], dy=(0, -1, -1, 0)[k], hat=(0, (0, -1, -1, 0)[k] * 0.0, -9 + (0, -1, -1.5, -0.5)[k]))))
    for k in range(4):
        fr.append((f"open_{k}", dict(jaw=(8, 18, 28, 34)[k], glow=(0, 5, 9, 13)[k], brow=(1, 2, 3, 4)[k], visor=1.0)))

    def muzzle(scale, seed):
        def f(c):
            star(c, 22, 111, 20 * scale, 9, seed)
            sparks(c, 22, 111, 8, 22 * scale, seed)
        return f
    fr.append(("fire_0", dict(jaw=34, tilt=-7, dx=3, brow=4, visor=1.0, post=[muzzle(1.0, 1)])))
    fr.append(("fire_1", dict(jaw=30, tilt=-4, dx=2, brow=3, visor=1.0, post=[lambda c: puff(c, 20, 104, 11, 3)])))
    fr.append(("fire_2", dict(jaw=18, tilt=-1, brow=2, visor=1.0, post=[lambda c: puff(c, 16, 92, 8, 4)])))
    fr.append(("hurt_0", dict(jaw=10, tilt=-10, dx=3, brow=-6, post=[fx_flash])))
    fr.append(("hurt_1", dict(jaw=14, tilt=-7, dx=2, brow=-5, monocle=(64, 96), hat=(4, -6, -18),
                               post=[lambda c: sparks(c, 100, 60, 8, 22, 7)])))
    fr.append(("hurt_2", dict(jaw=6, tilt=-2, brow=-2, monocle=(70, 80), hat=(1, -2, -12))))
    for k in range(4):
        fr.append((f"laugh_{k}", dict(jaw=(22, 4, 26, 6)[k], tilt=(-9, -5, -11, -6)[k], visor=(0.2, 0.4, 0.6, 0.4)[k],
                                      hat=(0, (-5, 0, -6, -1)[k], -9 + (-4, 0, -5, -1)[k]), brow=(-3, -2, -3, -2)[k])))

    def spring(c):
        # a coil spring boinging out of the cracked dome
        for i in range(7):
            y = 40 - i * 4
            c.tube([(96 - 5, y + 2, 1.4), (96 + 5, y, 1.4)], CHROME, tone=2 + (i % 2))
        c.ellipse(96, 10, 4, 3, CHROME)
    fr.append(("dead_0", dict(dead=1, jaw=16, tilt=6, monocle=(70, 92), post=[fx_flash, lambda c: sparks(c, 96, 70, 14, 34, 11)])))
    fr.append(("dead_1", dict(dead=1, jaw=26, tilt=12, monocle=(76, 112), hat=(-30, 0, -22),
                               post=[lambda c: puff(c, 120, 46, 12, 5, dark=True)])))
    fr.append(("dead_2", dict(dead=1, jaw=34, tilt=18, monocle=(84, 126), hat=None,
                               post=[lambda c: puff(c, 112, 34, 14, 6, dark=True), fx_char, spring])))
    fr.append(("dead_3", dict(dead=1, jaw=36, tilt=22, monocle=(86, 130), hat=None,
                               post=[lambda c: puff(c, 104, 24, 9, 7, dark=True), fx_char, spring])))
    return fr


# ------------------------------------------------------------------ wing

def wing_frames():
    fr = []
    for k in range(4):
        fr.append((f"rest_{k}", dict(rot=(0, 1.2, 0, -1.2)[k], flutter=(0, 1.5, 0, -1.5)[k])))
    for k in range(4):
        fr.append((f"open_{k}", dict(open=(0.25, 0.5, 0.78, 1.0)[k], rot=(-0.5, -1, -1.5, -2)[k])))
    shots = [[20, None, None], [72, 18, None], [124, 70, 18], [-1, 122, 70]]
    for k in range(4):
        pf = [(150 + 6 * k, 66 - 4 * k, 5 + 2 * k)] if k else []
        fr.append((f"fire_{k}", dict(open=1.0, fired=shots[k], rot=(-2, -1.5, -2, -1)[k], puffs=pf)))
    fr.append(("hurt_0", dict(rot=4, dx=2, post=[fx_flash])))
    fr.append(("hurt_1", dict(rot=2.5, dx=-1, post=[lambda c: sparks(c, 160, 70, 8, 20, 4)])))
    for k in range(2):
        fr.append((f"broken_{k}", dict(broken=1, k=k, rot=(-7, -8.5)[k], flutter=(3, -3)[k], open=0.4,
                                       puffs=[(150 - k * 3, 92 - k * 8, 8 + k * 2)])))
    return fr


# ------------------------------------------------------------------ leg

STEP = [((64, 158), 0), ((76, 158), 0), ((88, 158), 0), ((100, 158), 0), ((108, 146), -18), ((100, 134), -10), ((80, 128), 8),
        ((72, 144), 12)]


def leg_frames():
    fr = [("stand", dict(ankle=(78, 158)))]
    for k, (a, p) in enumerate(STEP):
        d = dict(ankle=a, pitch=p)
        if k == 0:
            d["puffs"] = [(30, 176, 6), (104, 178, 5)]
        fr.append((f"step_{k}", d))
    lines = [(52, 96, 52, 124), (64, 92, 64, 128), (40, 104, 40, 126)]
    fr.append(("stomp_0", dict(ankle=(74, 120), pitch=16)))
    fr.append(("stomp_1", dict(ankle=(70, 160), pitch=0, lines=lines)))
    fr.append(("stomp_2", dict(ankle=(70, 160), pitch=0, puffs=[(22, 172, 11), (130, 172, 12), (46, 178, 7), (108, 178, 7)])))
    fr.append(("stomp_3", dict(ankle=(72, 159), pitch=0, puffs=[(14, 168, 9), (144, 168, 9)])))
    for k in range(2):
        fr.append((f"broken_{k}", dict(ankle=(92, 156), pitch=-6, broken=1, k=k)))
    return fr


# ------------------------------------------------------------------ pot

def pot_frames():
    fr = [("closed", dict(wave=0.0))]
    hx, hy = HATCH
    for k in range(6):
        o = (0.06, 0.18, 0.36, 0.56, 0.76, 0.92)[k]
        jets = [(hx - 30 * o - 6, hy - 4, hx - 30 * o - 22 - k * 3, hy - 22 - k * 4, 3 + k * 0.6),
                (hx + 30 * o + 6, hy - 4, hx + 30 * o + 22 + k * 3, hy - 22 - k * 4, 3 + k * 0.6)]
        fr.append((f"opening_{k}", dict(open=o, wave=k * 0.9, jets=jets, dx=(1, -1, 1, -1, 0, 0)[k])))
    for k in range(4):
        p = (0.0, 0.55, 1.0, 0.55)[k]
        fr.append((f"open_{k}", dict(open=1.0, pulse=p, wave=k * 1.5,
                                     puffs=[(hx - 34 + k * 2, 66 - k * 6, 5 + k), (hx + 40 - k * 2, 72 - ((k + 2) % 4) * 6, 4 + (k + 2) % 4)])))

    def popcorn(seed):
        def f(c):
            g = rng(seed)
            for _ in range(10):
                x, y = hx + g.uniform(-40, 40), hy - g.uniform(20, 60)
                c.ellipse(x, y, 2.4, 1.6, RICE, tone=3)
        return f
    fr.append(("hit_0", dict(open=1.0, pulse=1.0, dx=-1, post=[fx_flash])))
    fr.append(("hit_1", dict(open=1.0, pulse=0.8, dx=1, post=[popcorn(3), lambda c: sparks(c, hx, hy - 20, 9, 30, 2)])))
    fr.append(("hit_2", dict(open=1.0, pulse=0.3, post=[popcorn(4)])))
    for k in range(3):
        fr.append((f"cracked_{k}", dict(open=1.0, cracked=k + 1, pulse=(0.2, 0.6, 1.0)[k], wave=k * 1.3,
                                        puffs=[(40 + k * 4, 112 - k * 4, 5 + k * 2), (170, 120 - k * 5, 4 + k * 2)][:k + 1], dark=k > 1)))

    def eruption(k):
        def f(c):
            g = rng(20 + k)
            if k == 0:
                star(c, hx, hy - 10, 70, 12, 3, tones=(2, 3, 4), ramp=RICE)
                return
            if k == 1:   # a column of rice and steam
                for i, t in enumerate((1, 2, 3, 4)):
                    w = 34 * (1 - i * 0.24)
                    c.poly([(hx - w, hy), (hx - w * 0.6, 40), (hx - w * 1.3, 6), (hx + w * 1.3, 6), (hx + w * 0.6, 40), (hx + w, hy)],
                           RICE, tone=t, seam=(i == 0))
                for x in (hx - 50, hx + 46, hx - 20, hx + 20):
                    puff(c, x, 30 + g.uniform(-10, 10), 16, seed=int(x))
            if k >= 1:
                for _ in range((60, 46, 0)[k - 1] if k < 3 else 0):
                    x, y = hx + g.uniform(-100, 100), g.uniform(8, 130)
                    c.ellipse(x, y, 2.4, 1.5, RICE, tone=3 if g.random() < 0.6 else 4)
            if k == 2:
                for x in (hx - 60, hx - 20, hx + 24, hx + 64):
                    puff(c, x, 70 + g.uniform(-14, 14), 20, seed=int(x) + 3)
                for _ in range(8):
                    x, y = hx + g.uniform(-90, 90), g.uniform(10, 60)
                    pr = Xf(x, y, g.uniform(0, 6))
                    c.tube([(0, 0, 2.2), (4, -2, 2), (7, 1, 1.6)], ("visor0", "visor1", "visor2", "visor3", "visor4"), xf=pr, bias=0.4)
            if k == 3:
                pr = Xf(hx + 6, 132, rad(-12))
                c.tube([(0, 0, 2.8), (5, -2, 2.6), (9, 1, 2.2), (10, 5, 1.6)], ("visor0", "visor1", "visor2", "visor3", "visor4"), xf=pr,
                       bias=0.4)
        return f
    fr.append(("destroyed_0", dict(open=1.0, pulse=1.0, post=[eruption(0)])))
    fr.append(("destroyed_1", dict(gone=True, back_puffs=[(hx - 70, 120, 16), (hx + 70, 116, 16)], post=[eruption(1)])))
    fr.append(("destroyed_2", dict(gone=True, back_puffs=[(hx - 40, 100, 20), (hx + 50, 96, 18)], dark=True, post=[eruption(2)])))
    fr.append(("destroyed_3", dict(gone=True, puffs=[(hx - 20, 110, 8), (hx + 30, 100, 10)], dark=True, post=[eruption(3)])))
    return fr


# ------------------------------------------------------------------ fx

def paint_fx(st):
    W, H, (cx, cy) = FXS
    c = Canvas(W, H)
    kind, k = st["kind"], st["k"]
    g = rng(k * 7 + len(kind))
    if kind == "charge":
        r = (5, 8, 11, 14, 17, 19)[k]
        for i in range(10):   # sparks streaming inwards
            a = 2 * math.pi * i / 10 + k * 0.5
            d0 = r + 8 + ((i * 7 + k * 11) % 26)
            d1 = d0 + 6 + (i % 3) * 3
            c.line(cx + math.cos(a) * d0, cy + math.sin(a) * d0, cx + math.cos(a) * d1, cy + math.sin(a) * d1,
                   RICE[4] if i % 2 else FIRE[3], w=2 if i % 3 == 0 else 1)
        for i, t in enumerate((1, 2, 3, 4)):
            rr = r * (1.25 - i * 0.25) + (k % 2)
            w = (lambda ph: (lambda a: 1 + 0.12 * math.cos(7 * a + ph)))(k * 0.8 + i)
            c.ellipse(cx, cy, rr, rr, RICE, tone=t, seam=(i == 0), wob=w)
        c.ellipse(cx - r * 0.3, cy - r * 0.3, max(1.2, r * 0.25), max(1.2, r * 0.25), FIRE, tone=4, seam=False)
    elif kind == "beam":
        # a thick bolt, tileable left-right (the period is 128 / 2 waves), flowing by a quarter each frame
        ph = k * math.pi / 2
        for i, (t, hw, amp) in enumerate(((0, 30, 4), (1, 26, 3.5), (2, 20, 3), (3, 13, 2), (4, 6, 1.2))):
            top = [(x, cy - hw - amp * math.sin(2 * math.pi * 2 * x / W + ph + i)) for x in range(0, W + 1, 4)]
            bot = [(x, cy + hw + amp * math.sin(2 * math.pi * 2 * x / W + ph * 1.0 + i + 1.3)) for x in range(W, -1, -4)]
            pts = [(-1, top[0][1])] + top + [(W + 1, top[-1][1]), (W + 1, bot[0][1])] + bot + [(-1, bot[-1][1])]
            c.poly(pts, RICE if i < 4 else FIRE, tone=t if i < 4 else 4, seam=False)
        for i in range(6):   # streaks flowing along the core
            x0 = (i * 23 + k * 32) % W
            y = cy + (-8, 6, -3, 10, -11, 2)[i]
            c.line(x0, y, min(W - 1, x0 + 14), y, RICE[4])
        # outline only along the top and bottom edges (the bolt continues left and right)
        m = c.mask()
        for x in range(W):
            col = [y for y in range(H) if m[y, x]]
            if col:
                c.p[col[0], x] = RICE[0]
                c.p[col[-1], x] = RICE[0]
    elif kind == "spark":
        puff(c, cx + 6 + k * 3, cy - 6 - k * 6, 8 + k * 4, seed=3 + k, dark=False)
        if k < 3:
            star(c, cx, cy, (22, 16, 9)[k], 7, k, tones=(2, 3, 4))
        sparks(c, cx, cy, 12 - k * 2, 18 + k * 12, 5 + k)
        for i in range(5):
            a = rad(-160 + i * 35 + k * 5)
            d = 14 + k * 11
            c.ellipse(cx + math.cos(a) * d, cy + math.sin(a) * d + k * k * 1.5, 1.6, 1.6, FIRE, tone=4 - min(3, k), seam=False)
    elif kind == "bolt":
        # a hex-head bolt with its nut, tumbling a quarter turn per frame
        xf = Xf(cx, cy, rad(k * 90 + 20))
        c.rect(-4, -18, 4, 10, CHROME, xf=xf, mode="cylx", rim=True)
        for j in range(-16, 10, 3):
            c.lline(xf, -4, j, 4, j + 1.5, CHROME[1])
        c.poly([(-11, 10), (11, 10), (12, 16), (8, 20), (-8, 20), (-12, 16)], CHROME, xf=xf, mode="cylx", rim=True)
        c.lline(xf, -4, 11, -4, 19, CHROME[1])
        c.lline(xf, 4, 11, 4, 19, CHROME[1])
        c.poly([(-9, -10), (9, -10), (10, -6), (-10, -6)], IRON, xf=xf, mode="cylx")
        for i in range(3):
            a = rad(k * 90 + 200 + i * 25)
            c.line(cx + math.cos(a) * 26, cy + math.sin(a) * 26, cx + math.cos(a) * 34, cy + math.sin(a) * 34, SMOKE[3])
    return c


def fx_frames():
    fr = []
    for kind, n in (("charge", 6), ("beam", 4), ("spark", 4), ("bolt", 4)):
        for k in range(n):
            fr.append((f"{kind}_{k}", dict(kind=kind, k=k)))
    return fr


# ------------------------------------------------------------------ preview

def assemble(parts: dict, size=(480, 340), off=(63, -125)) -> Image.Image:
    scr = Canvas(*size)
    for key in DRAW_ORDER:
        c = parts[key]
        if key == "body":
            joint, anchor = BODY[2], BODY[2]
        else:
            joint = JOINTS[key]
            anchor = {"head": HEAD, "wing": WING, "pot": POT, "leg_l": LEG, "leg_r": LEG}[key][2]
        scr.paste(c, off[0] + joint[0] - anchor[0], off[1] + joint[1] - anchor[1])
    return scr.rgba()


def boss_preview(sheets):
    def get(part, name):
        return dict(sheets[part])[name]
    rest = {"body": get("body", "idle_0"), "head": get("head", "idle_0"), "wing": get("wing", "rest_0"),
            "leg_l": get("leg", "stand"), "leg_r": get("leg", "stand"), "pot": get("pot", "closed")}
    opn = dict(rest, head=get("head", "open_3"), pot=get("pot", "open_2"), wing=get("wing", "open_3"))
    out = Image.new("RGBA", (960 + 8, 340), (40, 40, 40, 255))
    for i, parts in enumerate((rest, opn)):
        bg = Image.new("RGBA", (480, 340), (120, 200, 245, 255))
        d = ImageDraw.Draw(bg)
        d.rectangle([0, 336, 479, 339], fill=(214, 180, 120, 255))
        d.rectangle([0, 0, 479, 319], outline=(255, 255, 255, 255))   # a 480x320 screen for scale
        bg.alpha_composite(assemble(parts))
        out.alpha_composite(bg, (i * 488, 0))
    out.save(ART / "boss_preview.png")


def build():
    sheets = {}
    specs = [("body", paint_body, body_frames(), BODY, {"joints": {k: list(v) for k, v in JOINTS.items()},
                                                         "draw_order": DRAW_ORDER,
                                                         "notes": "place each part's anchor on its joint (boss_body pixels); "
                                                                  "leg_r is the far leg (draw it first)"}),
             ("head", paint_head, head_frames(), HEAD, {"muzzle": [22, 111], "notes": "muzzle = where the beak shot leaves (open/fire)"}),
             ("wing", paint_wing, wing_frames(), WING, {"rocket_mouths": [[133, 81], [137, 89], [141, 97]], "rocket_dir_deg": 166,
                                                         "notes": "rocket_mouths = rocket noses in the rack at rest (rack tilts with the wing a few degrees); rockets fly along rocket_dir_deg (screen degrees, 180 = left)"}),
             ("leg", paint_leg, leg_frames(), LEG, {"ground_y": 183, "notes": "ground_y = the sole line in leg pixels (hip anchor at y 20)"}),
             ("pot", paint_pot, pot_frames(), POT, {"core": list(HATCH), "notes": "core = the weak point's centre"}),
             ("fx", paint_fx, fx_frames(), FXS, {"notes": "beam tiles horizontally; charge/spark/bolt are centred"})]
    for part, paint, frames, (w, h, anchor), extras in specs:
        rendered = render(paint, frames)
        sheets[part] = rendered
        ex = {"faces": "left"}
        ex.update(extras)
        n = save_sheet(f"boss_{part}", rendered, w, h, anchor, ex)
        print(f"boss_{part}", len(rendered), "frames,", n, "colours")
    boss_preview(sheets)


if __name__ == "__main__":
    build()
