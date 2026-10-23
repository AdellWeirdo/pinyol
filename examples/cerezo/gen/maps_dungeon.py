"""La Raíz: the cave under the mountain. A grid of 4 x 3 rooms, each 15 x 9 metatiles (the border cells are the walls, the doors
are gaps in the middle of each side: north (7,0), south (7,8), west (0,4), east (14,4)). Nine rooms are used:

           x=0        x=1                x=2                   x=3
    y=0               R2 map/heart       R3 miniboss
    y=1    R5 entry   R6 hub             R7 dark room          R8 boss hall
    y=2               R9 pits, key 1     R10 lantern           R11 Topo Rey

Order: R5 -> R6 -> R9 (push the block into the pit, the key 1 chest) -> R10 (locked with key 1: the lantern) -> R7 through the hub's east door
(the cobwebs across it burn with the lantern; the chest has key 2) -> R3 (its door is locked with key 2: the miniboss, he drops the boss key)
-> R7 -> R8 -> the boss door (south) -> R11. R2, north of the hub, is optional: a chest with a piece of heart behind three caterpillars.
"""
from __future__ import annotations

from world import Area, Canvas, STAMPS

LEG = {
    ".": ["floor_a", "floor_b", "floor_c"], ":": "floor_cracked", "m": "floor_moss", "p": "floor_plate", "B": "floor_boss_a", "C": "floor_boss_b",
    "0": "pit", "1": "pit_filled", "w": "water_pool", "^": "spikes_up", "s": "switch_plate", "e": "eye_off", "x": "cobweb",
    "t": "torch_unlit", "T": "torch_lit_a", "S": "statue_a", "Z": "statue_b", "c": "chest_closed", "r": "roots_a", "R": "roots_b",
    "u": "mushroom_a", "U": "mushroom_b", "b": "bones", "k": "rubble", "q": "puddle", "d": "drip_a", "#": "rock_block", "o": "pillar",
    "=": ["wall_n_a", "wall_n_b"], "_": ["wall_s_a", "wall_s_b"], "[": ["wall_w_a", "wall_w_b"], "]": ["wall_e_a", "wall_e_b"],
    "7": "wall_nw", "9": "wall_ne", "3": "wall_sw", "5": "wall_se", "n": "wall_n_roots", "N": "wall_n_water",
    "D": "stairs_exit",
}

RAIZ = Area("raiz", "dungeon", 4, 3, LEG)
RAIZ.notes.update({"music": "raiz", "dungeon": "raiz", "name": "La Raíz"})
RAIZ.notes["dark"] = {"2,1": True}

SW, SH = 15, 9
DOOR_DIRS = {"n": (7, 0), "s": (7, 8), "w": (0, 4), "e": (14, 4)}


def room(sx, sy, doors, paint=None, seed=1):
    """A room: walls all round, floor inside, the doors given ({"n": "open"|"shut"|"locked"|"boss"|"none"}), and `paint(canvas)`
    for what is inside. Returns the canvas (for adding things)."""
    c = Canvas(".", seed=seed + sx * 10 + sy)
    c.hline(0, 1, 13, "=").hline(8, 1, 13, "_").vline(0, 1, 7, "[").vline(14, 1, 7, "]")
    c.put(0, 0, "7").put(14, 0, "9").put(0, 8, "3").put(14, 8, "5")
    if paint:
        paint(c)
    RAIZ.screen(sx, sy, c.rows())
    for d, state in doors.items():
        x, y = DOOR_DIRS[d]
        if state == "none":
            continue
        cx, cy = sx * SW + x, sy * SH + y
        name = f"door_{d}_{state}"
        STAMPS.setdefault(name, [[name]])
        RAIZ.stamp(name, cx, cy)
    return c


def cell(sx, sy, x, y):
    return sx * SW + x, sy * SH + y


def thing(sx, sy, kind, x, y, **kw):
    cx, cy = cell(sx, sy, x, y)
    RAIZ.thing(kind, cx, cy, **kw)


def gate(sx, sy, d, rule, flag=None):
    """A door that is shut until the rule is met: the room is cleared of pests ("clear") or a flag is set ("flag")."""
    x, y = DOOR_DIRS[d]
    cx, cy = cell(sx, sy, x, y)
    RAIZ.thing("gate", cx, cy, shut=f"door_{d}_shut", open=f"door_{d}_open", rule=rule, flag=flag)


# ---------------------------------------------------------------- R5 entry (0,1)
def r5(c):
    c.put(2, 2, "t").put(12, 2, "t").put(7, 5, "p").scatter("m", 3).scatter("q", 2, salt=3).scatter("r", 3, salt=5)
    c.put(7, 8, "D")
room(0, 1, {"e": "open", "n": "none", "s": "none", "w": "none"}, r5)
thing(0, 1, "exit", 7, 8, to="overworld", tx=15 + 7, ty=3, face="down")
thing(0, 1, "enemy", 4, 3, id="caracol", axis="h")
thing(0, 1, "enemy", 10, 6, id="caracol", axis="v")
thing(0, 1, "sign", 5, 1, text="estatua_b")

# ---------------------------------------------------------------- R6 hub (1,1)
def r6(c):
    c.rect(6, 3, 8, 5, "p").put(2, 2, "u").put(12, 2, "u").put(2, 6, "U").put(12, 6, "t").put(6, 1, "t").put(8, 1, "t")
    c.scatter("m", 4).scatter("q", 2, salt=2).scatter("k", 3, salt=4)
room(1, 1, {"w": "open", "n": "open", "s": "open", "e": "open"}, r6)
thing(1, 1, "enemy", 3, 4, id="topo")
thing(1, 1, "enemy", 11, 4, id="topo")
thing(1, 1, "enemy", 7, 7, id="moho")
thing(1, 1, "sign", 7, 3, text="estatua_a")

# ---------------------------------------------------------------- R2 optional chest (1,0)
def r2(c):
    c.put(2, 2, "u").put(12, 2, "u").put(7, 2, "c").scatter("r", 4).scatter("m", 3, salt=3).put(5, 2, "S").put(9, 2, "S")
room(1, 0, {"s": "open", "n": "none", "e": "none", "w": "none"}, r2)
thing(1, 0, "chest", 7, 2, item="pieza_corazon", flag="heart_raiz")
thing(1, 0, "enemy", 4, 5, id="oruga", face="right")
thing(1, 0, "enemy", 10, 5, id="oruga", face="left")
thing(1, 0, "enemy", 7, 6, id="oruga", face="up")
gate(1, 0, "s", "clear")

# ---------------------------------------------------------------- R9 pits and the first key (1,2)
def r9(c):
    c.rect(6, 4, 8, 6, "0").put(7, 5, "c")
    c.put(2, 2, "t").put(12, 2, "t").put(2, 6, "u").put(12, 6, "u").scatter("m", 3)
room(1, 2, {"n": "open", "e": "locked", "s": "none", "w": "none"}, r9)
thing(1, 2, "block", 7, 2)
thing(1, 2, "chest", 7, 5, item="llave_pequena", flag="key1")
thing(1, 2, "lock", 14, 4, open="door_e_open", dungeon="raiz")
thing(1, 2, "enemy", 3, 4, id="moho")
thing(1, 2, "enemy", 11, 4, id="moho")

# ---------------------------------------------------------------- R10 the lantern (2,2)
def r10(c):
    c.put(2, 2, "t").put(12, 2, "t").put(7, 4, "p").scatter("m", 3).scatter("k", 2, salt=3)
room(2, 2, {"w": "open", "n": "open", "e": "none", "s": "none"}, r10)
thing(2, 2, "enemy", 4, 3, id="oruga", face="right")
thing(2, 2, "enemy", 10, 6, id="oruga", face="left")
thing(2, 2, "enemy", 7, 2, id="avispa")
thing(2, 2, "enemy", 7, 6, id="avispa")
thing(2, 2, "keydrop", 7, 4, item="linterna", flag="got_linterna")
gate(2, 2, "w", "clear")

# ---------------------------------------------------------------- R7 the dark room (2,1)
def r7(c):
    for y in range(1, 8):
        c.put(8, y, "x")
    c.put(3, 1, "T").put(12, 6, "u").put(4, 6, "U").scatter("m", 3).scatter("b", 2, salt=3).put(12, 2, "c")
room(2, 1, {"w": "open", "s": "open", "e": "open", "n": "locked"}, r7)
thing(2, 1, "torch", 3, 1)
thing(2, 1, "chest", 12, 2, item="llave_pequena", flag="key2")
thing(2, 1, "lock", 7, 0, open="door_n_open", dungeon="raiz")
for x, y in [(11, 4), (12, 5), (10, 6), (13, 3)]:
    thing(2, 1, "enemy", x, y, id="murcielago")

# ---------------------------------------------------------------- R3 the miniboss (2,0)
def r3(c):
    c.put(2, 2, "t").put(12, 2, "t").scatter("m", 2).scatter("k", 3, salt=2)
room(2, 0, {"s": "open", "n": "none", "e": "none", "w": "none"}, r3)
thing(2, 0, "enemy", 7, 3, id="gran_escarabajo")
thing(2, 0, "keydrop", 7, 5, item="llave_jefe", flag="got_llave_jefe")
gate(2, 0, "s", "clear")

# ---------------------------------------------------------------- R8 the boss hall (3,1)
def r8(c):
    c.put(2, 2, "S").put(12, 2, "Z").put(2, 6, "t").put(12, 6, "t").rect(6, 3, 8, 5, "p").scatter("m", 2)
room(3, 1, {"w": "open", "s": "boss", "n": "none", "e": "none"}, r8)
thing(3, 1, "lock", 7, 8, open="door_s_open", dungeon="raiz", boss=True)

# ---------------------------------------------------------------- R11 the arena (3,2)
def r11(c):
    c.rect(2, 2, 12, 6, "B")
    for x in range(2, 13):
        c.put(x, 4, "C")
    c.put(2, 2, "S").put(12, 2, "S").put(2, 6, "t").put(12, 6, "t")
room(3, 2, {"n": "open", "s": "none", "e": "none", "w": "none"}, r11)
thing(3, 2, "boss", 7, 4, id="topo_rey")
thing(3, 2, "zone", 5, 1, w=5, h=1, event="boss_intro", flag="topo_intro")
gate(3, 2, "n", "flag", flag="topo_dead")

# the unused screens are solid rock
for sx in range(4):
    for sy in range(3):
        if (sx, sy) not in RAIZ.rows:
            c = Canvas("#")
            RAIZ.screen(sx, sy, c.rows())

AREAS = [RAIZ]
