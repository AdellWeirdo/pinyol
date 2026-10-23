"""Botín: the hero, Zurrón. Sheet HERO (32x32 frames, facing right); banks zurron, zurron_fuego, zurron_golpe, zurron_hinchado.

The figure is assembled from hand-drawn parts (heads, torso, arms, legs, the sack, the bandana tails), each given its own one-pixel
outline before it is laid over the parts behind it, so every overlap keeps a dark separating line (the way GBA sprites were cut).
Odd bodies (puffy, fat, flat, the crawl and swim bodies) are drawn whole.

Slot meaning, the same in all four banks (the same picture recolours):
    1        outline (deep indigo, never black)          2 3 4    skin: shadow, mid, light
    5 6 7    red: bandana, shirt stripes, rope           8 9 a    teal waistcoat: shadow, mid, light (8 also the boot sheen)
    b c d    tan: trousers, sack, patch (d = cream stripe, gold light)
    e        dark plum: moustache, hair, boots           f        white: eye, glints
"""
from __future__ import annotations

import sys
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent))
from gbakit import ART, ART_DIR, blank, contact_sheet, crop, flip_h, flip_v, overlay, pic, preview_sheet, recolour, shift  # noqa: E402

# ------------------------------------------------------------------ palettes

ART.palette("obj", "zurron", [
    "#22183e", "#c45a34", "#f09a62", "#ffd6a6",   # outline, skin
    "#9a1634", "#e83a3a", "#ff8c76",              # red
    "#0e4a6a", "#1a9a92", "#5edcbc",              # teal
    "#a0602a", "#e0a852", "#fff0b0",              # tan / cream
    "#4a2a5e", "#ffffff"])                        # plum, white
ART.palette("obj", "zurron_fuego", [
    "#5a0a0a", "#e04412", "#ff8a22", "#ffd040",
    "#b01808", "#ff5410", "#ffa632",
    "#a02008", "#e85c16", "#ffa83e",
    "#c04210", "#ff9428", "#ffec74",
    "#7c1208", "#fff8c4"])
ART.palette("obj", "zurron_golpe", [
    "#86a4f4", "#e6e8ff", "#f4f4ff", "#ffffff",
    "#dfe4ff", "#f0f2ff", "#ffffff",
    "#d4dcff", "#eceeff", "#ffffff",
    "#dde2ff", "#eff1ff", "#ffffff",
    "#bccaff", "#ffffff"])
ART.palette("obj", "zurron_hinchado", [
    "#6a4c9c", "#f0a49c", "#ffcebe", "#fff0e2",
    "#e48aae", "#ffb6d0", "#ffe0ec",
    "#7cbcd6", "#ade2ec", "#e0fcff",
    "#dcb48e", "#f8dab0", "#fffcec",
    "#9c86c0", "#ffffff"])
BANKS = ["zurron", "zurron_fuego", "zurron_golpe", "zurron_hinchado"]

OUT = 1  # outline slot


# ------------------------------------------------------------------ editing helpers

def P(*rows: str) -> list[list[int]]:
    """Rows of text padded on the right to the widest row (the parts are drawn from their left edge)."""
    w = max(len(r) for r in rows)
    return pic([r.ljust(w, ".") for r in rows])


def size(p):
    return len(p[0]), len(p)


def pad(p, n: int = 1):
    w, h = size(p)
    out = blank(w + 2 * n, h + 2 * n)
    return overlay(out, p, n, n)


def outlined(p, slot: int = OUT):
    """The part with its one-pixel outline (the picture grows by one pixel on each side)."""
    q = pad(p)
    w, h = size(q)
    out = [row[:] for row in q]
    for y in range(h):
        for x in range(w):
            if q[y][x] == 0 and any(0 <= x + dx < w and 0 <= y + dy < h and q[y + dy][x + dx] for dx, dy in ((1, 0), (-1, 0), (0, 1), (0, -1))):
                out[y][x] = slot
    return out


def rot_cw(p):
    """A quarter turn clockwise (top goes right)."""
    h = len(p)
    return [[p[h - 1 - y][x] for y in range(h)] for x in range(len(p[0]))]


def rot_ccw(p):
    return flip_h(flip_v(rot_cw(p)))


def shear(p, dx: int):
    """Each row moved sideways, more the lower it is: the bottom row by dx (a limb swung forward or back)."""
    w, h = size(p)
    m = abs(dx)
    out = blank(w + m, h)
    for y, row in enumerate(p):
        off = round(dx * y / max(1, h - 1)) + (m if dx < 0 else 0)
        for x, v in enumerate(row):
            if v:
                out[y][x + off] = v
    return out


def squash(p, rows_out: int):
    """Fewer (or more) rows by dropping (or doubling) rows evenly: the vertical squash of a landing or a jump."""
    h = len(p)
    return [p[min(h - 1, int(i * h / rows_out))][:] for i in range(rows_out)]


DARKER = {4: 3, 3: 2, 7: 6, 6: 5, 5: 5, 0xa: 9, 9: 8, 0xd: 0xc, 0xc: 0xb, 0xf: 4}


def back(p):
    """The far limb: one tone darker everywhere."""
    return recolour(p, DARKER)


def frame(parts) -> list[list[int]]:
    """Parts laid in order (first = farthest) on a 32x32 frame; each entry (picture, x, y[, outline?]) places the part's top-left
    pixel (not its outline) at x, y."""
    f = blank(32, 32)
    for e in parts:
        if e is None:
            continue
        p, x, y = e[0], e[1], e[2]
        line = e[3] if len(e) > 3 else True
        if line:
            f = overlay(f, outlined(p), x - 1, y - 1)
        else:
            f = overlay(f, p, x, y)
    return f


# ------------------------------------------------------------------ parts: heads (facing right; 15 x 12; the bandana knot sits at x 0..1, y 2..3)

HEAD = P(
    "....5677665....",
    "..56777666665..",
    ".5566666666665.",
    ".e33444eeee43..",
    ".e324444f12343.",
    ".e323444432f443",
    "..d333443324432",
    "..c23eeeee23322",
    "...2eeeeeeee22.",
    "...2e133311132.",
    "....223334322..",
)

# ------------------------------------------------------------------ parts: body

TORSO = P(  # 16 x 7, waistcoat (teal) open on a striped shirt and belly, belt with a gold buckle; the head covers the two top rows
    "..aaa999999ddd..",
    ".aa99999998d66d.",
    ".a99cc99998dddd9",
    ".a99cb9998666698",
    ".89999998dddddd8",
    "..8999886666668.",
    "..eeeeeeeeedeee.",
)
STRAP = [(9, 0), (8, 1), (7, 2), (6, 3), (5, 4), (4, 5)]  # the sack's strap across the chest (c, with b below it)

ARM = P(  # 5 x 8: rolled-up striped sleeve, thick forearm, fist
    ".dd.",
    "d66d",
    "dddd",
    "3443",
    "3443",
    "34432",
    "34322",
    ".222.",
)

ARM_UP = P(  # 5 x 10: raised, open hand on top (holding something overhead)
    "3.3.",
    "34343",
    "34432",
    ".3432",
    ".3443",
    ".3443",
    ".3432",
    ".dddd",
    ".d66d",
    "..dd.",
)

ARM_BENT = P(  # 7 x 6: elbow back, fist forward at chest height (the charge)
    ".dd....",
    "d66d...",
    "ddd4433",
    ".344443",
    ".233432",
    "....22.",
)

ARM_FWD = P(  # 9 x 5: reaching straight forward (throw, swim stroke, push)
    ".d.......",
    "d6d34433.",
    "d6d344443",
    "dd.333432",
    ".......2.",
)

LEG = P(  # 7 x 7: tan trouser (the top row is under the belt), a big dark boot with the toe forward
    "cdcb",
    "cdcb",
    "bccb",
    "e8ee",
    "e8eee",
    "e8eeee",
    "eeeeeee",
)

SACK = P(  # 11 x 12: the zurrón, tied at the neck with red rope, a red patch
    "....cdc....",
    "...bcdcb...",
    "....565....",
    "...cdddc...",
    "..cddddddb.",
    ".cdddddccbb",
    "cd66dddccbb",
    "cd55ddcccbb",
    "cdddccccbbb",
    "ccdcccccbbb",
    ".cccbbbbbb.",
    "..bbbbbb...",
)

TAILS = {  # the bandana's knot tails; the right end is the knot (it touches the head's back at x 0..1, y 2..3)
    "hang": P(
        "...667",
        "..5665",
        ".566..",
        "566...",
        "55....",
    ),
    "flut": P(
        "56..67",
        "5666665",
        ".55566.",
        "...55..",
    ),
    "stream": P(
        "6666677",
        "5555566",
        "..55555",
    ),
    "up": P(
        "5.....",
        "56..6.",
        ".5666.",
        "..5667",
        "...665",
    ),
}


def strapped(t):
    t = [row[:] for row in t]
    for x, y in STRAP:
        t[y][x] = 0xc
        if y + 1 < len(t) and t[y + 1][x] not in (0, 0xe):
            t[y + 1][x] = 0xb
    return t


TORSO_S = strapped(TORSO)


def edit(p, changes: dict):
    """A copy with single pixels changed: {(x, y): 'slot char'}."""
    q = [row[:] for row in p]
    for (x, y), ch in changes.items():
        q[y][x] = 0 if ch == "." else int(ch, 16)
    return q


MOUTH_GRIN = {(8, 9): "1", (9, 9): "f", (10, 9): "f", (11, 9): "f", (12, 9): "1", (8, 10): "1", (9, 10): "5", (10, 10): "5", (11, 10): "1"}
MOUTH_TEETH = {(8, 9): "1", (9, 9): "f", (10, 9): "f", (11, 9): "f", (12, 9): "1", (9, 10): "1", (10, 10): "1", (11, 10): "1"}
MOUTH_O = {(8, 9): "1", (9, 9): "5", (10, 9): "5", (11, 9): "1", (9, 10): "1", (10, 10): "1"}
MOUTH_SMALL = {(9, 9): "3", (10, 9): "1", (11, 9): "3"}
EYE_SHUT = {(8, 4): "1", (9, 4): "1"}
EYE_BACK = {(8, 4): "1", (9, 4): "f"}
EYE_WIDE = {(7, 3): "4", (8, 4): "f", (9, 4): "f", (8, 5): "f", (9, 5): "1"}
EYE_SQUEEZE = {(7, 3): "e", (8, 4): "1", (9, 4): "1", (8, 5): "2", (10, 3): "e"}
EYE_DIZZY = {(8, 4): "1", (9, 4): "f", (8, 5): "f", (9, 5): "1"}
EYE_HAPPY = {(8, 4): "1", (9, 4): "1", (8, 5): "3", (7, 4): "3", (10, 4): "2"}

HEADS = {
    "normal": HEAD,
    "blink": edit(HEAD, EYE_SHUT),
    "look": edit(HEAD, EYE_BACK),
    "smug": edit(HEAD, {**EYE_SHUT, (9, 9): "3", (12, 9): "1"}),
    "grin": edit(HEAD, {**EYE_HAPPY, **MOUTH_GRIN}),
    "fierce": edit(HEAD, MOUTH_TEETH),
    "strain": edit(HEAD, {**EYE_SQUEEZE, **MOUTH_TEETH}),
    "worried": edit(HEAD, {**EYE_WIDE, **MOUTH_SMALL}),
    "panic": edit(HEAD, {**EYE_WIDE, **MOUTH_O}),
    "pain": edit(HEAD, {**EYE_SQUEEZE, **MOUTH_O}),
    "dizzy": edit(HEAD, {**EYE_DIZZY, **MOUTH_O}),
}
SACK_BACK = rot_cw(SACK)       # streaming back behind a dash (the neck towards the shoulder)
SACK_TILT = shear(SACK, -2)    # swinging back
SACK_FWD = shear(SACK, 2)      # swinging forward
TORSO_LEAN = shear(TORSO_S, -2)  # top forward
TORSO_BACK = shear(TORSO_S, 2)   # top back


BODY_H = P(  # 14 x 8: the torso seen lying along (back on top, belly below, belt at the left end, shoulders at the right)
    "..aaaaaaa99...",
    ".eaa999999999.",
    "ea99cc9999999a",
    "ea99cb99999999",
    "e9999999999998",
    "e8998d6d6d6d8.",
    "dd8d6d6d6d6d..",
    ".e.8888888....",
)
KNEEL = P(  # 8 x 5: a knee on the ground, the shin lying back, the boot on its toe
    ".....cdc",
    "ee...cdc",
    "e8eecccb",
    "e8eebbbb",
    "eeee....",
)


# ------------------------------------------------------------------ the pose builder

def hero(dy=0, head="normal", hd=(0, 0), torso=None, td=(0, 0), fa=ARM, fad=(0, 0), ba=ARM, bad=(0, 0),
         bl=(0, 0), fl=(0, 0), sack=SACK, sd=(0, 0), tails="hang", tld=(0, 0), under=(), over=(), legs=True, ba_over=False):
    """Zurrón standing (feet on row 31) with every part movable. dy moves the whole upper body; the legs stay planted unless moved.
    `under` and `over` are extra (picture, x, y[, outline]) entries drawn first / last (fx lines, flames, sparks)."""
    hx, hy = 9 + hd[0], 9 + dy + hd[1]
    t = TORSO_S if torso is None else torso
    tx = 8 + td[0] - (len(t[0]) - 16 if t is TORSO_LEAN else 0)
    tp = TAILS[tails]
    parts = list(under)
    parts += [
        (back(ba), 7 + bad[0], 20 + dy + bad[1]) if ba is not None and not ba_over else None,
        (sack, 2 + sd[0], 14 + dy + sd[1]) if sack is not None else None,
        (back(ba), 7 + bad[0], 20 + dy + bad[1]) if ba is not None and ba_over else None,
        (back(LEG), 9 + bl[0], 24 + bl[1]) if legs else None,
        (LEG, 15 + fl[0], 24 + fl[1]) if legs else None,
        (t, tx, 18 + dy + td[1]),
        (HEADS[head] if isinstance(head, str) else head, hx, hy),
        (tp, hx + 2 - len(tp[0]) + tld[0], hy + 1 + tld[1]),
        (fa, 21 + fad[0], 20 + dy + fad[1]) if fa is not None else None,
    ]
    parts += list(over)
    return frame(parts)


S = ART.sheet("HERO", 32, 32, "zurron")


def lag(seq, i, n=1):
    """The value of a cycle `n` frames earlier (the sack and the tails follow the body a frame late)."""
    return seq[(i - n) % len(seq)]


# ------------------------------------------------------------------ idle: breathing, a blink, a look back, a nose scratch

ARM_SCRATCH = flip_v(ARM_BENT)
IDLE = [
    dict(dy=0),
    dict(dy=1, sd=(0, 0)),
    dict(dy=1, head="blink", sd=(0, 1)),
    dict(dy=0, head="look", sd=(0, 1), tails="flut", tld=(1, -1)),
    dict(dy=0, head="smug", fa=ARM_SCRATCH, fad=(-1, -4)),
    dict(dy=1, head="smug", fa=ARM_SCRATCH, fad=(-1, -3), sd=(0, 0)),
]
for i, kw in enumerate(IDLE):
    S.add(f"idle_{i}", hero(**kw))

# ------------------------------------------------------------------ walk: heavy and bouncy, the sack a frame late

WALK_BOB = [1, 0, -1, 0, 1, 0, -1, 0]
WALK_A = [(3, 0), (1, 0), (-1, 0), (-3, 0), (-2, -1), (0, -3), (2, -3), (3, -1)]  # one foot: stance back, then swing forward
for i in range(8):
    a, b = WALK_A[i], WALK_A[(i + 4) % 8]
    swing = a[0]
    S.add(f"walk_{i}", hero(
        dy=WALK_BOB[i], fl=a, bl=b,
        fa=shear(ARM, -1 if swing > 0 else 1), fad=(-1 if swing <= 0 else 0, 0),
        ba=shear(ARM, 1 if swing > 0 else -1),
        sd=(0, lag(WALK_BOB, i) + (1 if lag(WALK_BOB, i, 2) > 0 else 0)),
        sack=SACK_TILT if i in (1, 5) else SACK,
        tails="flut" if i % 4 in (1, 2) else "hang"))

# ------------------------------------------------------------------ run: the dash attack, shoulder first, leaning far forward

RUN_A = [(5, -1), (2, 0), (-2, 0), (-4, -1), (-1, -4), (3, -4)]
RUN_BOB = [0, 1, 0, -1, 0, -1]
for i in range(6):
    a, b = RUN_A[i], RUN_A[(i + 3) % 6]
    S.add(f"run_{i}", hero(
        dy=2 + RUN_BOB[i], head="fierce", hd=(4, 1), torso=TORSO_LEAN, td=(1, 0),
        fa=ARM_BENT, fad=(1, 1), ba=shear(ARM, -3), bad=(1, 0),
        fl=a, bl=b, sack=SACK_BACK, sd=(-1, -2 + lag(RUN_BOB, i)), tails="stream", tld=(0, -1 + (i % 2))))

# ------------------------------------------------------------------ ram: the standing shoulder bash

S.add("ram_0", hero(dy=1, head="fierce", hd=(-2, 0), torso=TORSO_BACK, td=(-1, 0), fa=shear(ARM, -2), fad=(-3, 0),
                    ba=shear(ARM, -2), bl=(-1, 0), fl=(-2, 0), sd=(-1, 1), tails="hang"))
S.add("ram_1", hero(dy=2, head="strain", hd=(4, 1), torso=TORSO_LEAN, td=(2, 0), fa=ARM_BENT, fad=(2, 1), ba=shear(ARM, -3),
                    bl=(-2, 0), fl=(3, 0), sack=SACK_TILT, sd=(-2, 0), tails="stream", tld=(0, -1)))
S.add("ram_2", hero(dy=1, head="pain", hd=(1, 0), td=(0, 0), fa=ARM_BENT, fad=(0, 1), ba=shear(ARM, -1),
                    bl=(-1, 0), fl=(2, 0), sack=SACK_FWD, sd=(-1, 0), tails="flut"))
S.add("ram_3", hero(dy=0, head="normal", fa=shear(ARM, 1), fad=(-1, 0), bl=(0, 0), fl=(1, 0), sd=(0, 1), tails="hang"))

# ------------------------------------------------------------------ jump, fall, land

S.add("jump_up", hero(dy=-1, fa=ARM_UP, fad=(0, -9), ba=ARM_UP, bad=(1, -9), bl=(1, -4), fl=(2, -2), sd=(0, 2), tails="hang", tld=(0, 2)))
S.add("jump_peak", hero(dy=-1, head="look", fa=shear(ARM, 3), fad=(0, -2), ba=shear(ARM, -3), bad=(-2, -2), bl=(0, -4), fl=(2, -4),
                        sd=(0, 0), tails="flut"))
S.add("fall_0", hero(dy=-2, head="worried", fa=ARM_UP, fad=(1, -10), ba=ARM_UP, bad=(0, -10), bl=(-1, -1), fl=(2, -2), sd=(0, -3), tails="up", tld=(0, -2)))
S.add("fall_1", hero(dy=-2, head="worried", fa=ARM_UP, fad=(1, -9), ba=ARM_UP, bad=(0, -11), bl=(-1, -2), fl=(2, -1), sd=(0, -2), tails="up", tld=(0, -3)))
S.add("land_0", hero(dy=3, head="strain", fa=shear(ARM, 2), fad=(1, -1), ba=shear(ARM, -2), bad=(-2, -1), bl=(-2, 0), fl=(2, 0), sd=(0, 3), tails="flut"))
S.add("land_1", hero(dy=1, head="normal", fa=shear(ARM, 1), ba=shear(ARM, -1), bl=(-1, 0), fl=(1, 0), sd=(0, 3), tails="hang"))

# ------------------------------------------------------------------ small effects drawn into the frames (they take the bank's colours)

STAR = P("..d..", ".ddd.", "ddfdd", ".ddd.", "..d..")
SPARK = P(".d.", "dfd", ".d.")
DUST = P(".dd.", "dffd", ".dd.")


def streak(n: int, slot: str = "f"):
    return P(*([slot] * n))


def hstreak(n: int, slot: str = "f"):
    return P(slot * n)


FLAME_S = P(
    "..d..",
    ".dfd.",
    ".7f7.",
    "67f76",
    "57776",
    ".565.",
)
FLAME_B = P(
    "...d...",
    "..dfd..",
    "..7f7.d",
    ".67f76.",
    "d6777f6",
    "57dff76",
    "5677765",
    ".55665.",
)

# ------------------------------------------------------------------ ground pound

S.add("smash_0", hero(dy=-3, head="strain", fa=ARM_BENT, fad=(-2, 1), ba=None, bl=(1, -6), fl=(2, -6), sd=(0, -1), tails="up", tld=(0, -1)))
DIVE = frame([  # head first, fists leading, boots up, the sack trailing above
    (flip_v(SACK), 3, 3),
    (back(flip_v(ARM_UP)), 7, 19),
    (back(shear(flip_v(LEG), 3)), 6, 3),
    (shear(flip_v(LEG), -3), 15, 2),
    (flip_v(TORSO_S), 8, 7),
    (flip_v(HEADS["fierce"]), 9, 12),
    (flip_v(TAILS["hang"]), 4, 18),
    (flip_v(ARM_UP), 21, 19),
])
S.add("smash_1", DIVE)
S.add("smash_2", hero(dy=5, head="strain", fa=shear(ARM, 3), fad=(1, 0), ba=shear(ARM, -3), bad=(-3, 0), bl=(-3, 0), fl=(3, 0), sd=(0, 5),
                      tails="flut", over=[(DUST, 1, 28), (DUST, 27, 28), (SPARK, 4, 23), (SPARK, 26, 23)]))
FORCE = [(streak(9), 4, 0), (streak(6), 8, 0), (streak(6), 23, 0), (streak(9), 27, 0)]
S.add("supersmash_0", overlay(DIVE, frame(FORCE)))
S.add("supersmash_1", overlay(shift(DIVE, 0, 1), frame([(streak(12), 3, 0), (streak(5), 7, 2), (streak(5), 24, 1), (streak(12), 28, 0),
                                                       (SPARK, 1, 27), (SPARK, 28, 26)])))

# ------------------------------------------------------------------ crouch and crawl

S.add("crouch", hero(dy=5, head="normal", fa=shear(ARM, 2), fad=(0, -1), ba=shear(ARM, -2), bad=(-1, -1), bl=(-2, 0), fl=(2, 0), sd=(0, 5)))

SACK_LOW = squash(SACK, 8)


def crawl(i: int):
    """On all fours, low enough for a one-tile gap (16 px): hands and knees alternate, the sack rides the back a frame late."""
    a = [2, 1, -1, -2, -1, 1][i]
    bob = [0, 0, 1, 0, 0, 1][i]
    return frame([
        (back(ARM), 19 - a, 24 + bob),
        (back(KNEEL), 2 - a // 2, 27),
        (SACK_LOW, 3, 16 + lag([0, 0, 1, 0, 0, 1], i)),
        (BODY_H, 5, 20 + bob),
        (KNEEL, 4 + a // 2, 27),
        (HEADS["normal" if i != 3 else "blink"], 15, 17 + bob),
        (TAILS["flut" if i % 3 else "hang"], 15 + 2 - 7, 18 + bob),
        (ARM, 21 + a, 24 + bob),
    ])


for i in range(6):
    S.add(f"crawl_{i}", crawl(i))

# ------------------------------------------------------------------ carrying: lift, hold overhead, walk with it, throw

UP_F, UP_B = (-1, -19), (3, -19)    # hands just above the head (fad / bad for ARM_UP)
for i in range(2):
    S.add(f"grab_idle_{i}", hero(dy=i, head="strain" if i else "fierce", fa=ARM_UP, fad=UP_F, ba=ARM_UP, bad=UP_B, ba_over=True,
                                 sd=(0, i), tails="hang"))
for i in range(6):
    a, b = WALK_A[(i * 4) // 3 % 8], WALK_A[((i * 4) // 3 + 4) % 8]
    bob = [1, 0, -1, 1, 0, -1][i]
    S.add(f"grab_walk_{i}", hero(dy=max(0, bob), head="fierce", fa=ARM_UP, fad=UP_F, ba=ARM_UP, bad=UP_B, ba_over=True, fl=a, bl=b,
                                 sd=(0, [1, 1, 0, 1, 1, 0][i]), tails="flut" if i % 3 == 1 else "hang"))
S.add("lift_0", hero(dy=5, head="strain", hd=(1, 0), fa=shear(ARM, 3), fad=(1, 1), ba=shear(ARM, 3), bad=(6, 1), bl=(-2, 0), fl=(2, 0), sd=(0, 5)))
S.add("lift_1", hero(dy=3, head="strain", fa=ARM_SCRATCH, fad=(0, -3), ba=ARM_SCRATCH, bad=(6, -3), bl=(-1, 0), fl=(1, 0), sd=(0, 4)))
S.add("lift_2", hero(dy=1, head="fierce", fa=ARM_UP, fad=(-1, -17), ba=ARM_UP, bad=(3, -17), ba_over=True, sd=(0, 2)))
S.add("throw_0", hero(dy=0, head="fierce", hd=(-2, 0), torso=TORSO_BACK, td=(-1, 0), fa=ARM_UP, fad=(-5, -17), ba=ARM_UP, bad=(-1, -17),
                      ba_over=True, bl=(-1, 0), fl=(1, 0), sd=(-1, 1), tails="hang"))
S.add("throw_1", hero(dy=1, head="fierce", hd=(3, 1), torso=TORSO_LEAN, td=(1, 0), fa=ARM_FWD, fad=(0, -1), ba=ARM_FWD, bad=(9, -2),
                      bl=(-2, 0), fl=(3, 0), sack=SACK_TILT, sd=(-1, -1), tails="stream", tld=(0, -1)))
S.add("throw_2", hero(dy=2, head="normal", hd=(2, 1), torso=TORSO_LEAN, td=(1, 0), fa=shear(ARM, 3), fad=(1, 0), ba=shear(ARM, 3), bad=(8, 0),
                      bl=(-2, 0), fl=(3, 0), sack=SACK_FWD, sd=(0, 0), tails="flut"))
S.add("throw_3", hero(dy=1, head="smug", fa=shear(ARM, 1), ba=shear(ARM, 1), bl=(-1, 0), fl=(1, 0), sd=(0, 1)))
S.add("throw_up_0", hero(dy=4, head="strain", fa=ARM_SCRATCH, fad=(-1, -4), ba=ARM_SCRATCH, bad=(5, -4), bl=(-2, 0), fl=(2, 0), sd=(0, 4)))
S.add("throw_up_1", hero(dy=-1, head="look", fa=ARM_UP, fad=(-1, -18), ba=ARM_UP, bad=(3, -18), ba_over=True, bl=(0, -1), fl=(0, -1),
                         sd=(0, 1), tails="hang", tld=(0, 1)))
S.add("throw_up_2", hero(dy=1, head="smug", fa=shear(ARM, -1), ba=shear(ARM, 1), sd=(0, -1), tails="flut"))

# ------------------------------------------------------------------ hurt and the comic death

S.add("hurt_0", hero(dy=-2, head="pain", hd=(-2, 0), torso=TORSO_BACK, td=(-1, 0), fa=ARM_UP, fad=(-2, -9), ba=ARM_UP, bad=(-2, -9), ba_over=True,
                     bl=(2, -2), fl=(4, -3), sack=SACK_FWD, sd=(2, -1), tails="up", tld=(1, -1), over=[(SPARK, 27, 6)]))
S.add("hurt_1", hero(dy=-1, head="pain", hd=(-2, 1), torso=TORSO_BACK, td=(-1, 0), fa=shear(ARM_UP, 2), fad=(-1, -8), ba=shear(ARM, -3), bad=(-3, -1),
                     bl=(3, -1), fl=(4, -2), sack=SACK_FWD, sd=(2, 0), tails="flut", over=[(STAR, 26, 3)]))

die_shock = hero(dy=-2, head="panic", fa=ARM_UP, fad=(0, -11), ba=ARM_UP, bad=(2, -11), ba_over=True, bl=(-1, -2), fl=(1, -3), sd=(0, 1), tails="up")
die_spin = hero(dy=-1, head="dizzy", fa=shear(ARM, 3), fad=(1, -2), ba=shear(ARM, -3), bad=(-3, -2), bl=(0, -1), fl=(2, -1), sd=(0, -1), tails="flut")
S.add("die_0", die_shock)
S.add("die_1", flip_h(die_spin))
S.add("die_2", die_spin)
S.add("die_3", hero(dy=1, head="dizzy", fa=shear(ARM, 1), ba=shear(ARM, -1), sd=(0, 2), tails="hang",
                    over=[(STAR, 6, 3), (SPARK, 15, 1), (STAR, 23, 3)]))


def grounded(p, cx: int = 16):
    """The picture moved so its lowest pixel is on row 31 and its middle at column cx."""
    rows = [y for y, r in enumerate(p) if any(r)]
    cols = [x for x in range(len(p[0])) if any(r[x] for r in p)]
    q = blank(32, 32)
    dx = cx - (cols[0] + cols[-1] + 1) // 2
    return overlay(q, crop(p, 0, 0, len(p[0]), len(p)), dx, 31 - rows[-1])


tip = shear(hero(dy=1, head="dizzy", fa=shear(ARM, -2), ba=shear(ARM, -2), sd=(0, 1), tails="flut"), 7)
S.add("die_4", grounded(tip, 15))
S.add("die_5", frame([  # flat on his back, boots up, seeing stars
    (rot_ccw(back(LEG)), 23, 22),
    (rot_ccw(LEG), 24, 24),
    (flip_h(flip_v(BODY_H)), 11, 23),
    (rot_ccw(HEADS["dizzy"]), 2, 16),
    (rot_ccw(ARM), 13, 20),
    (STAR, 6, 6), (SPARK, 13, 4), (STAR, 18, 9),
]))

# ------------------------------------------------------------------ swimming

for i in range(4):
    b = [0, -1, -1, 0][i]
    k = [(0, -2), (1, -1), (0, 0), (1, -1)][i]
    S.add(f"swim_idle_{i}", hero(dy=b - 1, head="normal" if i != 2 else "blink",
                                 fa=ARM_FWD if i % 2 == 0 else ARM_BENT, fad=(-2, -1) if i % 2 == 0 else (-1, 0),
                                 ba=ARM_BENT if i % 2 == 0 else ARM_FWD, bad=(10, -1),
                                 bl=(k[0] - 1, k[1] - 1), fl=(k[0] + 1, -1 - k[1] - 2), sack=SACK_TILT, sd=(-1, -3 + lag([0, -1, -1, 0], i)),
                                 tails="up", tld=(0, -1 + (i % 2))))

LEG_H = rot_cw(LEG)                          # a leg stretched back, toe down
STROKE = [  # (picture, x, y) of an arm through the stroke: reach forward, pull down, push back, bend over
    (ARM_FWD, 21, 20),
    (ARM, 19, 22),
    (rot_cw(ARM), 10, 24),
    (ARM_BENT, 17, 18),
]


def swim(i: int):
    f, b = STROKE[[0, 0, 1, 1, 2, 2, 3, 3][i]], STROKE[[2, 2, 3, 3, 0, 0, 1, 1][i]]
    bob = [0, 0, 1, 1, 0, 0, 1, 1][i]
    kick = [0, 1, 2, 1, 0, 1, 2, 1][i]
    return frame([
        (back(b[0]), b[1] - 2, b[2] + bob),
        (back(LEG_H), 0, 15 + kick),
        (SACK_BACK, 0, 6 + lag([0, 0, 1, 1, 0, 0, 1, 1], i, 2)),
        (LEG_H, 1, 19 - kick),
        (BODY_H, 5, 17 + bob),
        (HEADS["fierce" if i in (2, 3) else "normal"], 15, 11 + bob),
        (TAILS["stream"], 10, 12 + bob + (i % 2)),
        (f[0], f[1], f[2] + bob),
    ])


for i in range(8):
    S.add(f"swim_{i}", swim(i))

# ------------------------------------------------------------------ win: jumping for joy with the sack of gold held high

COINS = P(".d.c.", "dfdcd", ".dc.d")
SACK_HELD = squash(SACK, 9)


def win(h, face="grin", sparks=()):
    """h = how high he is off the ground (0 squatting to 3 at the top of the hop); the sack is held over his head."""
    dy = 3 - h
    top = max(0, 2 - h)
    return hero(dy=dy, head=face, fa=ARM_UP, fad=(-1, top + 3 - 20 - dy), ba=ARM_UP, bad=(-1, top + 3 - 20 - dy), ba_over=True,
                bl=(0, -h), fl=(1, -h + (1 if h else 0)), sack=None, tails="flut" if h >= 2 else "hang", tld=(0, -1 if h >= 2 else 0),
                over=[(SACK_HELD, 10, top), (COINS, 12, max(0, top - 1), False)] + list(sparks))


S.add("win_0", win(0, "smug"))
S.add("win_1", win(2, sparks=[(SPARK, 3, 5)]))
S.add("win_2", win(3, sparks=[(STAR, 2, 2), (SPARK, 26, 6)]))
S.add("win_3", win(2, sparks=[(SPARK, 27, 2), (STAR, 25, 9)]))
S.add("win_4", win(0, sparks=[(SPARK, 4, 9)]))
S.add("win_5", win(1, sparks=[(STAR, 26, 3), (SPARK, 3, 5)]))

# ------------------------------------------------------------------ on fire: running about with the bandana ablaze (blazes in zurron_fuego)

for i in range(6):
    a, b = RUN_A[i], RUN_A[(i + 3) % 6]
    up = i % 2 == 0
    fl_top = FLAME_B if i % 3 != 1 else flip_h(FLAME_B)
    S.add(f"fire_run_{i}", hero(
        dy=RUN_BOB[i] - 1, head="panic", hd=(2, 0), torso=TORSO_LEAN, td=(1, 0),
        fa=shear(ARM_UP, 2 if up else -1), fad=(1, -10 if up else -7), ba=shear(ARM_UP, -2 if up else 1), bad=(-2, -7 if up else -10), ba_over=True,
        fl=a, bl=b, sack=SACK_TILT, sd=(-1, lag(RUN_BOB, i)), tails="stream", tld=(0, -1 + i % 2),
        over=[(fl_top, 12 + (i % 2), 1 + RUN_BOB[i]), (FLAME_S if i % 2 else flip_h(FLAME_S), 0, 17 + (i % 3)),
              (FLAME_S, 5 - (i % 2), 9 + (i % 2))]))


# ------------------------------------------------------------------ round bodies: a small shaded-ball painter

import math  # noqa: E402

LIGHT = (-0.5, -0.62, 0.6)


def ball(w: int, h: int, mat):
    """An ellipse w x h shaded from the top left; mat(nx, ny, x, y) gives the (dark, mid, light) slots of the material there
    (or four slots: the fourth is a specular glint for the brightest spot)."""
    ln = math.sqrt(sum(c * c for c in LIGHT))
    lx, ly, lz = (c / ln for c in LIGHT)
    p = blank(w, h)
    for y in range(h):
        for x in range(w):
            nx, ny = (x + 0.5 - w / 2) / (w / 2), (y + 0.5 - h / 2) / (h / 2)
            r2 = nx * nx + ny * ny
            if r2 > 1:
                continue
            nz = math.sqrt(1 - r2)
            d = lx * nx + ly * ny + lz * nz
            m = mat(nx, ny, x, y)
            if len(m) > 3 and d > 0.975:
                p[y][x] = m[3]
            else:
                p[y][x] = m[2] if d > 0.82 else m[1] if d > 0.38 else m[0]
    return p


def outfit(cap: float = -0.38, face=(0.4, 0.02, 0.62, 0.55), coat: float = -0.42, stripe: int = 2):
    """The material map of an inflated Zurrón: bandana on top, a round face at the front, the waistcoat behind, the striped shirt
    curving round the belly. face = (centre x, centre y, radius x, radius y) in the ball's -1..1 units."""
    def mat(nx, ny, x, y):
        if ny < cap - 0.18 * nx * nx + 0.1 * nx:
            return (5, 6, 7, 0xf)
        fx, fy, rx, ry = face
        if ((nx - fx) / rx) ** 2 + ((ny - fy) / ry) ** 2 < 1:
            return (2, 3, 4)
        if nx < coat - 0.3 * ny * ny:
            return (8, 9, 0xa)
        band = int((y + 2.5 * nx * nx * stripe) // stripe) % 2
        return (0xc, 0xd, 0xd) if band == 0 else (5, 6, 6)
    return mat


NOSE = P(".343.", "3f443", "34432", ".222.")
MOUSTACHE = P(".eeee", "eeeee1", "e1..e")
EYE_BIG = P("ff", "f1")
FIST = P("dd.", "343", "322")
BOOT = P("e8ee.", "eeeee")


def face_on(parts, cx: int, cy: int, face: str):
    """Eye, brow, nose, moustache and mouth stamped round (cx, cy)."""
    eye = {"worried": EYE_BIG, "pain": P("1.", ".1", "1."), "calm": P("f1")}[face]
    mouth = {"worried": P("1", "1"), "pain": P("1f1", "111"), "calm": P("11")}[face]
    parts += [
        (P("eee") if face != "worried" else P(".ee", "e.."), cx - 2, cy - 4, False),
        (eye, cx - 1, cy - 3, False),
        (NOSE, cx + 2, cy - 2),
        (MOUSTACHE, cx - 3, cy + 1),
        (mouth, cx + 1, cy + 4, False),
    ]
    return parts


def puffy(dy: int, arms: int, face: str = "worried", w: int = 26, h: int = 24):
    body = ball(w, h, outfit())
    x0, y0 = 16 - w // 2, 27 - h + dy
    cx, cy = x0 + round(w / 2 * 1.42), y0 + h // 2
    parts = [
        (back(FIST), x0 - 2, y0 + h // 2 - 1 - arms),
        (body, x0, y0),
        (back(BOOT), x0 + w // 2 - 8, y0 + h - 2),
        (BOOT, x0 + w // 2 + 1, y0 + h - 2 + (arms % 2)),
        (TAILS["up"], x0 + 1, y0 + 1),
    ]
    face_on(parts, cx - 2, cy - 1, face)
    parts.append((FIST, x0 + w - 3, y0 + round(h * 0.68) + arms))
    return frame(parts)


for i in range(4):
    S.add(f"puffy_{i}", puffy([0, -1, -2, -1][i], [0, 1, 2, 1][i]))
S.add("puffy_hurt", puffy(1, 0, "pain", 28, 22))

# ------------------------------------------------------------------ fat: a huge round invulnerable belly, stomping

BOOT_BIG = [row[:] for row in LEG[3:]]


def belly(w: int, h: int):
    def mat(nx, ny, x, y):
        bend = ny + 0.12 * nx * nx
        if 0.5 < bend < 0.68:
            return (1, 0xe, 8) if abs(nx - 0.15) > 0.09 else (0xb, 0xc, 0xd)   # belt and buckle
        if nx < -0.45 - 0.2 * ny * ny or nx > 0.82:
            return (8, 9, 0xa)
        band = int((y + 3 * nx * nx) // 2) % 2
        return (0xc, 0xd, 0xd, 0xf) if band == 0 else (5, 6, 6)
    return ball(w, h, mat)


BELLY = belly(28, 20)
BELLY_SQ = belly(30, 18)


def fat(i: int, run: bool):
    lift = [(-3, 0), (0, 0), (0, -3), (0, 0)][i]
    sq = i % 2 == 1
    b = BELLY_SQ if sq else BELLY
    by = 31 - len(b) - 1
    bx = 16 - len(b[0]) // 2 + (1 if run else 0)
    lean = 2 if run else 0
    swing = (-2 if i < 2 else 2) if run else 0
    return frame([
        (back(ARM), bx - 2 - swing, by + 4),
        (back(BOOT_BIG), 8 - (2 if run and i < 2 else 0), 27 + lift[0]),
        (BOOT_BIG, 17 + (2 if run and i >= 2 else 0), 27 + lift[1]),
        (b, bx, by),
        (HEADS["fierce" if run else ("smug" if i == 3 else "normal")], 9 + lean, by - 8),
        (TAILS["stream" if run else ("flut" if sq else "hang")], 9 + lean + 2 - len(TAILS["stream" if run else ("flut" if sq else "hang")][0]),
         by - 7),
        (ARM, bx + len(b[0]) - 5 + swing, by + 4),
    ])


for i in range(4):
    S.add(f"fat_{i}", fat(i, False))
for i in range(4):
    S.add(f"fat_run_{i}", fat(i, True))

# ------------------------------------------------------------------ flat as a pancake, then puffing back up

PANCAKE = P(  # squashed flat: bandana, the face stretched wide (brow, eye, the nose squeezed out in front, the long moustache), body below
    "......55667777776666666655...",
    "...5566677766666666666666655.",
    "..e2344444444444444eeee44....",
    ".e2334444444444444ff14433343.",
    "e22333333333333333f1332344f43",
    "e2233eeeeeeeeeeeeee333234443.",
    ".e2eeeeee1eeeeee1eee3322222..",
    ".8aa999999d6d6d6d6d6d68.......",
    "..88888899999999999998........",
)


def flat(i: int):
    step = [0, 1, 0, -1][i]
    x0 = 1 + (i % 2)
    return frame([
        (back(P("e8e", "eee")), x0 + 1 - step, 29),
        (TAILS["stream"], x0 - 4, 22 + (i % 2)),
        (PANCAKE if i != 2 else edit(PANCAKE, {(18, 3): "1", (18, 4): "2"}), x0, 22),
        (P("e8ee", "eeeee"), x0 + 18 + step, 29),
    ])


for i in range(4):
    S.add(f"flat_{i}", flat(i))


def reinflate(w: int, h: int, dy: int = 0):
    body = ball(w, h, outfit())
    x0, y0 = 16 - w // 2, 30 - h + dy
    cx, cy = x0 + round(w / 2 * 1.4), y0 + h // 2
    parts = [
        (body, x0, y0),
        (back(P("e8e", "eee")), x0 + w // 2 - 6, 29),
        (P("e8e", "eee"), x0 + w // 2 + 2, 29),
        (TAILS["up"], x0, y0 + 1),
    ]
    face_on(parts, cx - 2, cy - 1, "worried")
    return frame(parts)


S.add("flat_float_0", reinflate(24, 12))
S.add("flat_float_1", reinflate(21, 18, -1))


# ------------------------------------------------------------------ previews (python3 gen/art_hero.py)

GROUPS = ["idle", "walk", "run", "ram", "jump", "fall", "land", "smash", "supersmash", "crouch", "crawl", "grab_idle", "grab_walk", "lift",
          "throw_", "throw_up", "hurt", "die", "swim_idle", "swim_", "win", "fire_run", "puffy", "fat_", "fat_run", "flat_", "flat_float"]


def preview_banks(scale: int = 3) -> Path:
    """Every animation as a strip, in each of the four banks (one column block per bank), on a bright and a dark ground."""
    from PIL import Image
    rows = []
    for g in GROUPS:
        rows.append([p for n, p in S.frames if n.startswith(g) and not (g == "throw_" and n.startswith("throw_up"))
                     and not (g == "swim_" and n.startswith("swim_idle")) and not (g == "fat_" and n.startswith("fat_run"))
                     and not (g == "flat_" and n.startswith("flat_float"))])
    n = max(len(r) for r in rows)
    cw = 32 * scale + 2
    img = Image.new("RGB", (len(BANKS) * (n * cw + 8), len(rows) * (32 * scale + 2) * 2), (24, 24, 30))
    for bi, bank in enumerate(BANKS):
        cols = ART.palettes["obj"][bank]
        for ri, r in enumerate(rows):
            for k, back_ in enumerate(((60, 60, 76), (236, 244, 255))):
                sheet = contact_sheet([(p, cols) for p in r], cols=n, scale=scale, gap=2, back=back_)
                img.paste(sheet, (bi * (n * cw + 8), (ri * 2 + k) * (32 * scale + 2)))
    ART_DIR.mkdir(exist_ok=True)
    out = ART_DIR / "hero_banks.png"
    img.save(out)
    return out


def preview_1x() -> Path:
    """The whole sheet at 1x on a bright and a dark ground (how it looks in the game)."""
    from PIL import Image
    cols = ART.palettes["obj"]["zurron"]
    a = contact_sheet([(p, cols) for _, p in S.frames], cols=20, scale=1, gap=2, back=(56, 72, 120))
    b = contact_sheet([(p, cols) for _, p in S.frames], cols=20, scale=1, gap=2, back=(168, 220, 120))
    img = Image.new("RGB", (a.width, a.height * 2))
    img.paste(a, (0, 0))
    img.paste(b, (0, a.height))
    out = ART_DIR / "hero_1x.png"
    img.save(out)
    return out


if __name__ == "__main__":
    print(preview_sheet("HERO", cols=10), preview_banks(), preview_1x(), f"{len(S.frames)} frames")
