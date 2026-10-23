"""Small 8x8 effects: the key's twinkle and a puff of dust."""
from __future__ import annotations

from art_lib import strip

FX = strip("""
........|...X....|........|........|........|........
........|...X....|...X....|........|..X.X...|.X...X..
...X....|.X.X.X..|...X....|...XX...|.X...X..|X......X
..XXX...|..XXX...|.XXXXX..|..XXXX..|...X..X.|........
...X....|XXXXXXX.|...X....|..XXXX..|X.....X.|.X......
........|..XXX...|...X....|...XX...|.X..X...|......X.
........|.X.X.X..|........|........|...X.X..|..X..X..
........|...X....|........|........|........|........
""", ["glint_0", "glint_1", "glint_2", "dust_0", "dust_1", "dust_2"], 8, 8)


def register(ART) -> None:
    ART.sheet("FX", 8, 8)
    for n, r in FX.items():
        ART.sprite("FX", n, r)
