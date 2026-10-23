"""Paella de Combate: the six playable cooks. Writes art/chef_<id>_{legs,torso,full}.png/.json, previews, test strips
and the line-up. Run: python3 gen/art_chefs.py [ids...]"""
from __future__ import annotations

import sys
from pathlib import Path

import numpy as np
from PIL import Image, ImageDraw

HERE = Path(__file__).resolve().parent
sys.path.insert(0, str(HERE))
from chefbase import Fig  # noqa: E402
from cast import CAST  # noqa: E402
from chefkit import _font, preview, save_sheet  # noqa: E402
from chefposes import CLIP, FULL, LEGS, OVERLAP, TORSO, family, legs_pose, torso_pose  # noqa: E402

ART = HERE.parent / "art"

LW, LH, LPIN = 96, 72, (48, 14)
TW, TH, TPIN = 128, 112, (64, 96)
FW, FH, FANC = 128, 112, (64, 108)
FOY = FANC[1] - 56          # world y 0 (the pin) in a full frame


def edge_check(img, tag, warn):
    a = np.asarray(img)[..., 3] > 0
    if a[0].any() or a[-1].any() or a[:, 0].any() or a[:, -1].any():
        warn.append(tag)


def legs_frame(chef, name):
    P = legs_pose_with_body(chef, name)
    cv = chef.render(P, LW, LH, *LPIN, kinds=("body", "lower"))
    r = cv.resolve()
    keep = (r.kind == 2) | ((r.kind == 1) & (r.wy() >= CLIP - OVERLAP))
    return r.select(keep).image()


def legs_pose_with_body(chef, name):
    """The legs frame's own lower-body pose, with the torso lean/breath of the torso frame that usually rides it."""
    P = dict(legs_pose(chef, name))
    if name.startswith("run_"):
        T = torso_pose(chef, name)
        P["lean"], P["cloth"] = T["lean"], T.get("cloth", 0.0)
    return P


def torso_frame(chef, name):
    P = torso_pose(chef, name)
    cv = chef.render(P, TW, TH, *TPIN)
    r = cv.resolve()
    keep = (r.kind == 0) | ((r.kind == 1) & (r.wy() < CLIP))
    f = Fig(chef, P)
    return r.select(keep).image(), f, P


def full_frame(chef, name):
    P, post = chef.full_pose(name)
    cv = chef.render(P, FW, FH, FANC[0], FOY, post=post)
    return cv.resolve().image()


def tp(p, pin):
    return [int(round(p[0] + pin[0])), int(round(p[1] + pin[1]))]


def build(cid):
    chef = CAST[cid]()
    warn = []
    out = {}
    # legs
    legs = [legs_frame(chef, n) for n in LEGS]
    for n, im in zip(LEGS, legs):
        edge_check(im, "legs:" + n, warn)
    nc = save_sheet(ART / f"chef_{cid}_legs.png", legs, LEGS, {"anchor": list(LPIN), "pin": list(LPIN), "feet_y": 70})
    out["legs"] = (legs, nc)
    # torso
    torso, muzzle, gh, sbox, marks = [], {}, {}, {}, {}
    for n in TORSO:
        im, f, P = torso_frame(chef, n)
        edge_check(im, "torso:" + n, warn)
        torso.append(im)
        if n.startswith(("aim", "fire", "crouch_fire", "crouch_aim")):
            muzzle[n] = tp(chef.muzzle(f), TPIN)
            marks[n] = [(*muzzle[n], (255, 40, 40))]
        if n == "throw_1":
            gh[n] = tp(chef.grenade_hand(f), TPIN)
            marks[n] = [(*gh[n], (40, 255, 40))]
        if n in ("stab_1", "stab_2"):
            b = chef.knife_box(f)
            sbox[n] = tp(b[:2], TPIN) + tp(b[2:], TPIN)
            marks[n] = [(sbox[n][0], sbox[n][1], (255, 200, 0)), (sbox[n][2], sbox[n][3], (255, 200, 0))]
    nc2 = save_sheet(ART / f"chef_{cid}_torso.png", torso, TORSO, {"anchor": list(TPIN), "pin": list(TPIN),
                     "muzzle": muzzle, "grenade_hand": gh, "stab_box": sbox})
    out["torso"] = (torso, nc2, marks)
    full = [full_frame(chef, n) for n in FULL]
    for n, im in zip(FULL, full):
        edge_check(im, "full:" + n, warn)
    nc3 = save_sheet(ART / f"chef_{cid}_full.png", full, FULL, {"anchor": list(FANC), "faces": "right"})
    out["full"] = (full, nc3)
    preview(ART / f"preview_chef_{cid}_legs.png", legs, LEGS, cols=10)
    preview(ART / f"preview_chef_{cid}_torso.png", torso, TORSO, cols=8, marks=marks)
    preview(ART / f"preview_chef_{cid}_full.png", full, FULL, cols=10)
    strip(cid, legs, torso)
    print(f"{cid}: colours legs {nc} torso {nc2} full {nc3}; edge-touching: {warn or 'none'}")
    return out


def compose(legs_im, torso_im):
    """Legs pin on torso pin, in a full-size frame (feet at 108)."""
    c = Image.new("RGBA", (FW, FH), (0, 0, 0, 0))
    c.paste(legs_im, (FANC[0] - LPIN[0], FOY - LPIN[1] + 0), legs_im)
    c.paste(torso_im, (FANC[0] - TPIN[0], FOY - TPIN[1]), torso_im)
    return c


def strip(cid, legs, torso):
    L = dict(zip(LEGS, legs))
    T = dict(zip(TORSO, torso))
    combos = [(f"run_{i}", "aim_fwd") for i in range(8)] + [(f"run_{i}", f"run_{i}") for i in range(8)] + [
        ("crouch", "crouch_aim"), ("crouch", "crouch_fire_0"), ("crawl_2", "crouch_aim"), ("jump_1", "aim_up"),
        ("jump_2", "aim_down"), ("idle", "stab_1"), ("idle", "stab_2"), ("idle", "throw_1"), ("idle", "idle_0"),
        ("jump_0", "jump_0"), ("jump_3", "jump_1"), ("idle", "fire_fwd_0")]
    frames = [compose(L[a], T[b]) for a, b in combos]
    names = [f"{a}+{b}" for a, b in combos]
    preview(ART / f"preview_chef_{cid}_composed.png", frames, names, cols=8)


def lineup(ids):
    ims = []
    for cid in ids:
        chef = CAST[cid]()
        legs = legs_frame(chef, "idle")
        torso = torso_frame(chef, "idle_0")[0]
        ims.append(compose(legs, torso))
    s = 2
    W = 84 * len(ims) + 40
    img = Image.new("RGB", (W * s, 120 * s), (0, 0, 0))
    sky = Image.new("RGB", (W * s, 60 * s), (150, 214, 248))
    img.paste((110, 110, 118), (0, 0, W * s, 120 * s))
    img.paste(sky, (0, 0))
    d = ImageDraw.Draw(img)
    for i, (cid, im) in enumerate(zip(ids, ims)):
        big = im.resize((FW * s, FH * s), Image.NEAREST)
        x = (20 + 84 * i - 22) * s
        img.paste(big, (x, 4 * s), big)
        d.text((x + 40 * s, 113 * s), cid, fill=(255, 240, 200), font=_font(14))
    img.save(ART / "chefs_lineup.png")


if __name__ == "__main__":
    ART.mkdir(exist_ok=True)
    ids = sys.argv[1:] or list(CAST)
    for cid in ids:
        build(cid)
    lineup(list(CAST))
