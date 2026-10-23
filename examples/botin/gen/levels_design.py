"""The levels of Botín, drawn with brush strokes (levelkit.Level) and checked by gen/reach.py before they are compiled.
Cells are 16x16 pixels; a level is 14 cells tall (224 px) and 90-130 wide. `thing(name, cx, cy, ...)` puts something at a cell: coins, hearts and jewels by
the cell they fill; the hero, enemies, the frog, the chest and the keyzer by their bottom-left cell (the row of their feet), so a thing standing on a floor
at row 11 is at row 10, whatever its height.

Things (read by core/things.lua):
  start            the vortex the hero comes out of and must come back to          jewel n=1..4 [box=True]   a piece of the jewel (a J box at the same cell hides it)
  coin s=1|2|3     a coin (1, 5, 10 points)   gem k="a"|"b"   diamond             heart            a heart that refills one
  frog             the switch that starts the escape (2x2 cells)                    keyzer           the spirit with the key       chest   the chest the key opens (2x2)
  enemy type=...   pelusa gusanito bichito fogata serpiente mono murcielago escarabajo pez_globo cangrejo medusa golem_chico  (dir=-1|1, range=cells it patrols)
  boss             the arena's boss
"""
from __future__ import annotations

import sys
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent))
from levelkit import Level  # noqa: E402

FLOOR_BOTTOM = 13


def ground(lv: Level, x0: int, x1: int, top: int, bottom: int = FLOOR_BOTTOM) -> Level:
    return lv.rect(x0, top, x1, bottom, "#")


def pit(lv: Level, x0: int, x1: int, floor: int = FLOOR_BOTTOM, spikes: bool = True) -> Level:
    lv.rect(x0, 0, x1, FLOOR_BOTTOM, ".")
    lv.h_(floor, x0, x1, "#")
    if spikes:
        lv.h_(floor - 1, x0, x1, "^")
    return lv


def decorate(lv: Level, xs, pieces="abcdefgh") -> Level:
    """Puts a decoration (cycling through the pieces) on the first ground cell below the top at each x."""
    for i, x in enumerate(xs):
        for y in range(lv.h):
            if lv.g[y][x] == "#":
                if y > 0 and lv.g[y - 1][x] == ".":
                    lv.put(x, y - 1, pieces[i % len(pieces)])
                break
    return lv


def coins(lv: Level, x0: int, x1: int, y: int, s: int = 1) -> Level:
    for x in range(x0, x1 + 1):
        lv.thing("coin", x, y, s=s)
    return lv


def arc(lv: Level, x0: int, x1: int, y: int, rise: int = 2, s: int = 1) -> Level:
    n = x1 - x0
    for i in range(n + 1):
        lv.thing("coin", x0 + i, y - round(rise * (1 - (2 * i / n - 1) ** 2)) if n else y, s=s)
    return lv


# ---------------------------------------------------------------------------------------------------------------------------- 1. selva

def level1() -> Level:
    lv = Level(1, "selva", 96, 14, "Selva Jade", music="selva", time=45)
    ground(lv, 0, 95, 11)
    # start, a lesson in walking and jumping
    lv.thing("start", 3, 10)
    coins(lv, 6, 8, 9)
    lv.thing("enemy", 9, 10, type="pelusa", dir=-1, range=4)
    ground(lv, 12, 17, 10)
    arc(lv, 11, 16, 7, 1)
    # the first pit: three cells, leaves above
    pit(lv, 18, 20)
    arc(lv, 18, 20, 8, 2)
    ground(lv, 21, 33, 10)
    lv.thing("heart", 22, 8)
    lv.thing("enemy", 25, 9, type="gusanito", dir=1, range=3)
    # the wall of brown blocks: a dash goes through it (the two lower rows are all the hero's body needs)
    lv.rect(29, 6, 29, 9, "b")
    coins(lv, 30, 32, 9, 2)
    lv.thing("gem", 31, 8, k="a")
    ground(lv, 34, 49, 11)
    # the mud pool and the first jewel on a ledge
    lv.rect(36, 11, 39, 11, "m")
    lv.rect(36, 12, 39, 13, "#")
    lv.h_(9, 40, 42, "=")
    lv.put(41, 6, "J")
    lv.thing("jewel", 41, 6, n=1, box=True)
    coins(lv, 43, 44, 9)
    # the spring that sends the hero up to the second jewel
    lv.put(45, 10, "s")
    lv.h_(5, 44, 48, "=")
    lv.thing("jewel", 47, 3, n=2)
    lv.thing("gem", 44, 3, k="b")
    # leaf platforms over the canopy
    pit(lv, 50, 61)
    lv.h_(9, 51, 52, "=")
    lv.h_(8, 54, 55, "=")
    lv.h_(9, 57, 58, "=")
    lv.h_(9, 60, 61, "=")
    coins(lv, 51, 52, 8)
    coins(lv, 54, 55, 7)
    coins(lv, 57, 58, 8)
    lv.thing("enemy", 56, 5, type="murcielago", dir=-1, range=5)
    # the hill with the hidden waterfall room (a ram opens it from the left; the way on goes over the top)
    ground(lv, 62, 70, 11)
    lv.rect(63, 8, 70, 10, "#")
    lv.rect(64, 9, 68, 10, ".")
    lv.rect(63, 9, 63, 10, "b")
    lv.rect(65, 9, 65, 10, "W")
    lv.rect(67, 9, 67, 10, "W")
    lv.thing("jewel", 66, 9, n=3)
    coins(lv, 64, 64, 9, 2)
    coins(lv, 68, 68, 9, 2)
    lv.thing("enemy", 66, 6, type="murcielago", dir=1, range=3)
    # the monkey's clearing
    ground(lv, 71, 95, 11)
    lv.thing("enemy", 76, 10, type="mono", dir=-1)
    lv.thing("enemy", 74, 10, type="pelusa", dir=1, range=3)
    coins(lv, 78, 81, 8)
    lv.thing("keyzer", 80, 6)
    lv.thing("chest", 71, 10)
    lv.h_(9, 84, 86, "=")
    lv.h_(7, 82, 84, "=")
    lv.put(84, 4, "J")
    lv.thing("jewel", 84, 4, n=4, box=True)
    lv.rect(88, 6, 88, 10, "b")
    lv.thing("frog", 91, 10)
    lv.thing("enemy", 93, 10, type="gusanito", dir=-1, range=2)
    # deco and a front fringe of leaves
    decorate(lv, [5, 13, 24, 35, 47, 72, 90])
    lv.rect(0, 0, 0, 13, "H")
    lv.rect(95, 0, 95, 13, "H")
    return lv



# ---------------------------------------------------------------------------------------------------------------------------- 2. cristal

def level2() -> Level:
    lv = Level(2, "cristal", 100, 16, "Cueva de Cristal", music="cristal", time=55, dark=60)
    ground(lv, 0, 99, 12, 15)
    lv.rect(0, 0, 99, 1, "#")                      # the roof
    lv.thing("start", 3, 11)
    coins(lv, 6, 8, 10)
    lv.thing("enemy", 10, 11, type="bichito", dir=-1, range=3)
    lv.put(16, 11, "^")
    lv.put(17, 11, "^")
    # the floor of blue blocks: smash down into the room under it
    lv.rect(20, 12, 24, 12, "B")
    lv.rect(20, 13, 32, 14, ".")
    lv.thing("jewel", 26, 14, n=1)
    coins(lv, 21, 24, 14)
    lv.thing("enemy", 29, 14, type="escarabajo", dir=1, range=3)
    lv.rect(31, 12, 32, 12, ".")                   # the hole that leads out of it
    lv.put(31, 13, "=")
    lv.thing("gem", 28, 13, k="a")
    # the low tunnel to crawl through
    lv.rect(40, 2, 46, 10, "#")
    lv.thing("jewel", 43, 11, n=2)
    coins(lv, 41, 45, 11, 2)
    lv.thing("enemy", 36, 11, type="murcielago", dir=1, range=4)
    lv.thing("enemy", 50, 3, type="murcielago", dir=-1, range=4)
    # drips, ice plats over a spiked pit
    pit(lv, 52, 64, floor=15)
    lv.rect(52, 12, 64, 14, ".")
    lv.h_(14, 52, 64, "^")
    lv.rect(52, 15, 64, 15, "#")
    lv.h_(11, 53, 55, "=")
    lv.h_(10, 57, 58, "=")
    lv.h_(11, 60, 61, "=")
    lv.h_(11, 63, 64, "=")
    coins(lv, 53, 55, 10)
    coins(lv, 57, 58, 9)
    lv.rect(56, 2, 56, 7, "D")
    # a wall of brown blocks and the key alcove behind it
    lv.rect(70, 8, 70, 11, "b")
    lv.thing("keyzer", 75, 10)
    lv.thing("chest", 82, 11)
    lv.thing("enemy", 78, 11, type="escarabajo", dir=-1, range=3)
    lv.thing("heart", 73, 10)
    # steps up to the last stretch: jewels 3 and 4
    ground(lv, 84, 99, 11, 15)
    lv.h_(9, 86, 88, "=")
    lv.h_(7, 89, 91, "=")
    lv.put(90, 4, "J")
    lv.thing("jewel", 90, 4, n=3, box=True)
    lv.h_(5, 84, 86, "=")
    lv.put(85, 2, "J")
    lv.thing("jewel", 85, 2, n=4, box=True)
    lv.thing("enemy", 94, 10, type="bichito", dir=-1, range=3)
    lv.thing("frog", 96, 10)
    decorate(lv, [6, 13, 27, 35, 48, 66, 74, 93])
    lv.rect(0, 0, 0, 15, "H")
    lv.rect(99, 0, 99, 15, "H")
    return lv


# ---------------------------------------------------------------------------------------------------------------------------- 3. galeon

def level3() -> Level:
    lv = Level(3, "galeon", 100, 18, "Galeón Hundido", music="galeon", time=60, water_row=4)
    ground(lv, 0, 99, 16, 17)
    lv.rect(0, 0, 99, 0, "#")
    # the beach at the start: a dock above the water
    ground(lv, 0, 7, 4, 17)
    lv.thing("start", 3, 3)
    coins(lv, 9, 12, 8)
    lv.thing("enemy", 14, 10, type="pez_globo", dir=1, range=5)
    # the wreck: hull walls with gaps, one of brown blocks
    ground(lv, 8, 99, 16, 17)
    lv.rect(8, 4, 8, 15, "#")
    lv.rect(20, 2, 22, 11, "T")
    lv.rect(20, 14, 22, 15, "T")
    lv.rect(20, 12, 22, 13, "b")
    lv.thing("jewel", 18, 14, n=1)
    coins(lv, 24, 28, 12, 2)
    lv.rect(30, 6, 32, 15, "#")
    lv.rect(31, 6, 31, 7, ".")
    lv.thing("enemy", 26, 15, type="cangrejo", dir=1, range=4)
    lv.thing("enemy", 27, 9, type="medusa")
    lv.rect(36, 6, 36, 15, "l")                    # a current that pushes left
    lv.rect(40, 6, 44, 6, "r")
    lv.thing("jewel", 42, 10, n=2)
    lv.rect(46, 12, 48, 15, "Y")
    lv.rect(52, 5, 54, 15, "#")
    lv.rect(53, 9, 53, 12, ".")
    lv.thing("heart", 53, 10)
    coins(lv, 56, 60, 10)
    lv.rect(62, 8, 62, 15, "b")
    lv.thing("keyzer", 66, 9)
    lv.thing("chest", 68, 15)
    lv.thing("enemy", 70, 11, type="pez_globo", dir=-1, range=5)
    lv.thing("enemy", 74, 8, type="medusa")
    lv.rect(76, 3, 78, 9, "B")
    lv.rect(76, 10, 78, 15, "#")
    lv.rect(77, 10, 77, 12, ".")
    lv.thing("jewel", 77, 12, n=3)
    lv.h_(5, 80, 90, "=")
    lv.put(85, 2, "J")
    lv.thing("jewel", 85, 2, n=4, box=True)
    for x in (10, 34, 50, 60, 72, 92):
        lv.put(x, 15, "Z")
    lv.thing("frog", 95, 15)
    lv.rect(99, 0, 99, 17, "H")
    return lv


# ---------------------------------------------------------------------------------------------------------------------------- 4. fragua

def level4() -> Level:
    lv = Level(4, "fragua", 100, 14, "Fragua del Volcán", music="fragua", time=60)
    ground(lv, 0, 99, 11)
    lv.thing("start", 3, 10)
    coins(lv, 6, 9, 9)
    lv.thing("enemy", 10, 10, type="golem_chico", dir=-1, range=3)
    # a lava pool crossed by chain platforms
    lv.rect(16, 11, 28, 13, "L")
    lv.h_(13, 16, 28, "#")
    lv.h_(11, 17, 19, "=")
    lv.h_(10, 21, 22, "=")
    lv.h_(11, 24, 25, "=")
    lv.h_(10, 27, 28, "=")
    coins(lv, 17, 19, 9)
    coins(lv, 21, 22, 8)
    # the fogata and the fire blocks: touch the flame to burn through them
    ground(lv, 29, 50, 11)
    lv.thing("enemy", 33, 10, type="fogata", dir=-1)
    lv.rect(40, 5, 41, 10, "F")
    lv.thing("jewel", 44, 10, n=1)
    coins(lv, 43, 46, 9, 2)
    # steam vents lift the hero up to a high ledge
    lv.put(35, 10, "S")
    lv.rect(35, 6, 35, 9, "S")
    lv.h_(4, 33, 37, "=")
    lv.thing("jewel", 36, 3, n=2)
    # the gear room
    lv.rect(52, 11, 60, 13, "L")
    lv.h_(13, 52, 60, "#")
    lv.h_(10, 53, 54, "=")
    lv.h_(9, 56, 57, "=")
    lv.h_(10, 59, 60, "=")
    lv.put(55, 6, "G")
    lv.thing("enemy", 58, 4, type="murcielago", dir=1, range=4)
    ground(lv, 61, 99, 11)
    lv.rect(64, 6, 64, 10, "b")
    lv.thing("keyzer", 70, 8)
    lv.thing("chest", 66, 10)
    lv.thing("heart", 68, 9)
    lv.thing("enemy", 72, 10, type="golem_chico", dir=-1, range=3)
    lv.h_(8, 76, 78, "=")
    lv.h_(6, 79, 81, "=")
    lv.put(80, 3, "J")
    lv.thing("jewel", 80, 3, n=3, box=True)
    lv.rect(84, 6, 84, 10, "S")
    lv.h_(4, 85, 88, "=")
    lv.thing("jewel", 87, 2, n=4)
    lv.thing("enemy", 91, 10, type="fogata", dir=-1)
    lv.thing("frog", 95, 10)
    decorate(lv, [5, 14, 31, 47, 62, 74, 90], "abcdefgh")
    lv.rect(0, 0, 0, 13, "H")
    lv.rect(99, 0, 99, 13, "H")
    return lv


# ---------------------------------------------------------------------------------------------------------------------------- 5. the golem's arena

def level5() -> Level:
    lv = Level(5, "fragua", 15, 10, "Gran Gólem de Oro", music="fragua", boss=True)
    ground(lv, 0, 14, 8, 9)
    lv.rect(0, 0, 0, 9, "H")
    lv.rect(14, 0, 14, 9, "H")
    lv.thing("start", 2, 7)
    lv.thing("boss", 11, 7)
    return lv


LEVELS = [level1(), level2(), level3(), level4(), level5()]
