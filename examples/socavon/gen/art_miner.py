"""The miner, 16x16, facing right (the game flips him). Ink only: he takes the colour of what he stands on.

His hooks: the helmet lamp with its ray, the bushy moustache, and the pickaxe he carries on his back hand.
"""
from __future__ import annotations

from art_lib import overlay, parse, shift_v, strip

HEAD = [  # rows 0-8, shared by most frames
    "........XXXX....",
    ".......XXXXXX.X.",
    ".XXX..XXXXXXXXXX",
    "X...X.XXXXXXX.XX",
    "..X..XXXXXXXXXX.",
    "..X.....XX.X....",
    "..X.....XXXXXX..",
    "..X....XXXXXXX..",
    "..X...XXX..XX...",
]

BODIES = strip("""
..XXXXX.XXXXXX..|..XXXXX.XXXXXX..|..XXXXX.XXXXXX..|..XXXXX.XXXXX...|..XXXXX.XXXXX...
..X....XXXXX.XX.|..X....XXXXX.XX.|..X....XXXXX.XX.|..X....XXXXX....|..X...XXXXXX....
..X....XXXXX.X..|..X....XXXXX.X..|..X....XXXXX.X..|..X...XXXXXX....|..X...X.XXXX....
..X....X.XXX....|..X....X.XXX....|..X....X.XXX....|..X....X.XXX....|..X....X.XXX....
.......XX.XX....|......XX...XX...|.......XXXXX....|......XX...XX...|.......XXXXXX...
.......XX.XX....|.....XX.....XX..|.....XXX..XX....|.....XX.....XX..|.......XX..XXX..
......XXX.XXX...|....XXX.....XXX.|..........XXX...|....XXX.....XXX.|......XXX.......
................|................|................|................|................
""", ["stand", "walk_0", "walk_1", "walk_2", "walk_3"], 16, 8)


def with_head(body: list[str], dy: int = 0) -> list[str]:
    """Head + body (8 rows below row 8). dy=1 sinks the head and shoulders a pixel (a stride's dip)."""
    pic = HEAD + body[:7]
    if dy:
        top = shift_v(pic[:12], dy)[:12]
        pic = overlay(top + ["." * 16] * 4, ["." * 16] * 12 + pic[12:])
    return pic


JUMPS = strip("""
........XXXX....|........XXXX....
.......XXXXXX.X.|.......XXXXXX.X.
.XXX..XXXXXXXXXX|.XXX..XXXXXXXXXX
X...X.XXXXXXX.XX|X...X.XXXXXXX.XX
..X..XXXXXXXXXX.|..X..XXXXXXXXXX.
..X.....XX.X....|..X.....XX.X....
..X.....XXXXXX..|..X.....XXXXXX..
..X....XXXXXXX..|..X....XXXXXXX..
..X...XXX..XX...|..X...XXX..XX...
..XXXXX.XXXXX.XX|..XXXXX.XXXXXX..
..X....XXXXX.XX.|..X....XXXXX.XX.
..X....XXXXX....|..X...XXXXXX.X..
..X....X.XXX....|..X...XX.XXX....
......XXXXXXX...|.....XX....XX...
......XX...X....|.....X......X...
.........XXX....|....XX......XX..
""", ["jump_up", "jump_down"])

SHOCK = parse("""
.......XXXX.....
......XXXXXX.X..
.....XXXXXXXXXXX
....XXXXXXXXXX..
................
X.....XXXXX....X
.X...XX.X.XX..X.
..X..XXXXXXX.X..
...X.XX...XX.X..
....XXXXXXXXXX..
.....XXXXXXX....
.....XXXXXXX....
.....XX.X.XX....
......XX.XX.....
......XX.XX.....
.....XXX.XXX....
""", 16, 16, "die_0")

FLAT = parse("""
................
................
................
................
................
................
................
................
................
................
......XXXX......
.....XXXXXX.XX..
....XXXXXXXXXXX.
..X.X.XXXX.X.X..
.XXXXXXXXXXXXXX.
XX.XX......XX.XX
""", 16, 16, "die_3")

WIN = strip("""
.XXX....XXXX....|.XXX....XXXX....
X.X.X..XXXXXX.X.|X.X.X..XXXXXX.X.
..X...XXXXXXXXXX|..X...XXXXXXXXXX
..X...XXXXXXX.XX|..X...XXXXXXX.XX
..X..XXXXXXXXXX.|..X..XXXXXXXXXX.
..XX....XX.X....|..XX....XX.X..X.
...X....XXXXXX..|...X....XXXXXXX.
....X..XXXXXXX..|....X..XXXXXXX..
.....XXXX..XX...|.....XXXX..XXX..
......XXXXXXXX..|......XXXXXXXX..
.......XXXXX.XX.|.......XXXXX....
.......XXXXX.X..|.......XXXXX....
.......X.XXX....|.......X.XXX....
.......XX.XX....|......XX...XX...
.......XX.XX....|.....XX.....XX..
......XXX.XXX...|....XXX.....XXX.
""", ["win_0", "win_1"])


def rot_cw(rows: list[str]) -> list[str]:
    n = len(rows)
    return ["".join(rows[n - 1 - y][x] for y in range(n)) for x in range(n)]


def register(ART) -> None:
    ART.sheet("MINER", 16, 16)
    ART.sprite("MINER", "stand", with_head(BODIES["stand"]))
    for i in range(4):
        ART.sprite("MINER", f"walk_{i}", with_head(BODIES[f"walk_{i}"], 1 if i % 2 == 0 else 0))
    for n in ("jump_up", "jump_down"):
        ART.sprite("MINER", n, JUMPS[n])
    # death: the shock (helmet jumps off), then he spins a quarter turn each frame, then a flat heap under the helmet
    ART.sprite("MINER", "die_0", SHOCK)
    ART.sprite("MINER", "die_1", rot_cw(SHOCK))
    ART.sprite("MINER", "die_2", rot_cw(rot_cw(SHOCK)))
    ART.sprite("MINER", "die_3", FLAT)
    for n in ("win_0", "win_1"):
        ART.sprite("MINER", n, WIN[n])
