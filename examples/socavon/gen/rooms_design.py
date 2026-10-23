"""Socavón's rooms, designed with brush strokes and CHECKED: a copy of the game's miner physics walks every jump from every
standing place and says whether each key and the portal can be reached without touching a hazard. Writes rooms.lua.

    python3 gen/rooms_design.py          # check, print each room, write rooms.lua
"""
from __future__ import annotations

import sys
from collections import deque
from pathlib import Path

HERE = Path(__file__).resolve().parent.parent
RW, RH = 28, 16
GRAVITY, JUMP, MAX_FALL, DEADLY = 0.19, -3.4, 3, 36  # the same numbers as main.lua
HAZARD = set("*^v")


class Room:
    def __init__(self, name: str, theme: int, scheme: dict, air: float = 1.0):
        self.name, self.theme, self.scheme, self.air = name, theme, scheme, air
        self.g = [["."] * RW for _ in range(RH)]
        for x in range(RW):
            self.g[0][x] = self.g[RH - 1][x] = "#"
        for y in range(RH):
            self.g[y][0] = self.g[y][RW - 1] = "#"
        self.guards: list[dict] = []

    def put(self, x, y, c):
        self.g[y][x] = c
        return self

    def h(self, y, x0, x1, c="="):
        for x in range(x0, x1 + 1):
            self.g[y][x] = c
        return self

    def v(self, x, y0, y1, c="#"):
        for y in range(y0, y1 + 1):
            self.g[y][x] = c
        return self

    def rect(self, x0, y0, x1, y1, c="#"):
        for y in range(y0, y1 + 1):
            self.h(y, x0, x1, c)
        return self

    def deco(self, c, *cells):
        """Decoration (background, nothing to touch): only onto air."""
        for x, y in cells:
            if self.g[y][x] == ".":
                self.g[y][x] = c
        return self

    def dh(self, y, x0, x1, c):
        return self.deco(c, *[(x, y) for x in range(x0, x1 + 1)])

    def dv(self, x, y0, y1, c):
        return self.deco(c, *[(x, y) for y in range(y0, y1 + 1)])

    def guard(self, kind, x, y, x0, x1, speed=0.6, **kw):
        """A guardian: its top-left cell, and the span of cells it patrols (horizontally, or vertically for a spider/flame)."""
        self.guards.append({"kind": kind, "x": x, "y": y, "min": x0, "max": x1, "speed": speed, **kw})
        return self

    def rows(self):
        return ["".join(r) for r in self.g]


# ------------------------------------------------------------------ the miner's physics, as in main.lua
def ch(r, tx, ty):
    if 0 <= ty < RH and 0 <= tx < RW:
        return r.g[ty][tx]
    return "#"


def solid(c):
    return c == "#"


def ledge(c):
    return c in "=->< "


TICKS = [0]  # the ticks the last simulate_jump took (for the solver)


def simulate_jump(r: Room, x, y, vx, jump=True):
    """From a standing place, one jump (or a step off an edge): returns (landing (x, y) or None, touched cells, died)."""
    touched = set()
    TICKS[0] = 0
    ground, vy, top = not jump, 0.0, y
    if jump:
        vy, ground, top = JUMP, False, y
    for _ in range(400):
        TICKS[0] += 1
        nx = x + vx
        edge = nx + 11 if vx > 0 else nx + 4
        if vx == 0 or not (solid(ch(r, int(edge) // 8, int(y + 2) // 8)) or solid(ch(r, int(edge) // 8, int(y + 13) // 8))):
            x = nx
        vy = min(vy + GRAVITY, MAX_FALL)
        old = y + 16
        y = y + vy
        if vy < 0 and solid(ch(r, int(x + 8) // 8, int(y) // 8)):
            y, vy = (int(y) // 8 + 1) * 8, 0
        for p in ((x + 5, y + 4), (x + 10, y + 4), (x + 5, y + 14), (x + 10, y + 14)):
            c = ch(r, int(p[0]) // 8, int(p[1]) // 8)
            touched.add((int(p[0]) // 8, int(p[1]) // 8))
            if c in HAZARD:
                return None, touched, True
        if vy > 0:
            for px in (x + 4, x + 11):
                fy = int(y + 16)
                c = ch(r, int(px) // 8, fy // 8)
                t = (fy // 8) * 8
                if (solid(c) or ledge(c)) and old <= t + 1:
                    if t - 16 - top > DEADLY:
                        return None, touched, True
                    return (int(x), t - 16), touched, False
        if y > RH * 8:
            return None, touched, True
    return None, touched, True


def under_ok(r, x, y):
    under = ch(r, (x + 8) // 8, (y + 16) // 8)
    return solid(under) or ledge(under) or ledge(ch(r, (x + 4) // 8, (y + 16) // 8)) or ledge(ch(r, (x + 11) // 8, (y + 16) // 8))


def reach(r: Room, start=None):
    if start is None:
        for y, row in enumerate(r.g):
            for x, c in enumerate(row):
                if c == "P":
                    start = (x * 8, y * 8)
    assert start, f"{r.name}: no P"
    seen, q, touched = {start}, deque([start]), set()
    while q:
        x, y = q.popleft()
        for vx in (-1, 0, 1):
            land, t, died = simulate_jump(r, x, y, vx, True)
            touched |= t
            if land and land not in seen:
                seen.add(land)
                q.append(land)
        for dx in (-1, 1):  # walking: a step; maybe off an edge
            nx = x + dx
            edge = nx + 11 if dx > 0 else nx + 4
            if solid(ch(r, edge // 8, (y + 2) // 8)) or solid(ch(r, edge // 8, (y + 13) // 8)):
                continue
            if any(ch(r, int(px) // 8, int(py) // 8) in HAZARD for px, py in ((nx + 5, y + 4), (nx + 10, y + 4), (nx + 5, y + 14), (nx + 10, y + 14))):
                continue
            if under_ok(r, nx, y):
                if (nx, y) not in seen:
                    seen.add((nx, y))
                    q.append((nx, y))
                for px, py in ((nx + 5, y + 4), (nx + 10, y + 4), (nx + 5, y + 14), (nx + 10, y + 14)):
                    touched.add((int(px) // 8, int(py) // 8))
            else:
                land, t, died = simulate_jump(r, nx, y, dx, False)
                touched |= t
                if land and land not in seen:
                    seen.add(land)
                    q.append(land)
    return seen, touched


def has_belts(r: Room) -> bool:
    return any(c in "<>" for row in r.g for c in row)


def solve(r: Room):
    """The inputs that take the miner to every key and then the portal, as a list of (ticks, buttons) found by a search over the same
    jumps and steps as reach(). Returns None for a room with belts (they shift the miner's x by a fraction and this search does not)."""
    if has_belts(r):
        return None
    start = None
    for y, row in enumerate(r.g):
        for x, c in enumerate(row):
            if c == "P":
                start = (x * 8, y * 8)

    def successors(st):
        x, y = st
        for vx in (-1, 0, 1):
            land, t, died = simulate_jump(r, x, y, vx, True)
            n = TICKS[0]
            if not died:
                yield land, t, ("jump", vx, n)
        for dx in (-1, 1):
            nx = x + dx
            edge = nx + 11 if dx > 0 else nx + 4
            if solid(ch(r, edge // 8, (y + 2) // 8)) or solid(ch(r, edge // 8, (y + 13) // 8)):
                continue
            pts = ((nx + 5, y + 4), (nx + 10, y + 4), (nx + 5, y + 14), (nx + 10, y + 14))
            if any(ch(r, int(px) // 8, int(py) // 8) in HAZARD for px, py in pts):
                continue
            t = {(int(px) // 8, int(py) // 8) for px, py in pts}
            if under_ok(r, nx, y):
                yield (nx, y), t, ("walk", dx, 1)
            else:
                land, t2, died = simulate_jump(r, nx, y, dx, False)
                if not died:
                    yield land, t | t2, ("off", dx, TICKS[0] + 1)

    def path_to(frm, wants):
        """BFS from frm to the first transition that touches a cell in `wants`; returns (end state, [moves], cell)."""
        parent = {frm: None}
        q = deque([frm])
        while q:
            st = q.popleft()
            for nxt, t, mv in successors(st):
                hit = t & wants
                if hit:
                    moves = [mv]
                    cur = st
                    while parent[cur]:
                        cur, m = parent[cur]
                        moves.append(m)
                    moves.reverse()
                    return nxt, moves, next(iter(hit))
                if nxt not in parent:
                    parent[nxt] = (st, mv)
                    q.append(nxt)
        return None

    keys = {(x, y) for y, row in enumerate(r.g) for x, c in enumerate(row) if c == "k"}
    portal = {(x, y) for y, row in enumerate(r.g) for x, c in enumerate(row) if c == "X"}

    def feasible(st, want):
        return want <= reach(r, st)[1]

    def search(cur, keys, depth=0):
        """The moves from `cur` that take every key in `keys` and then the portal, or None. Nearest key first, but only into places from
        which the rest can still be reached (a high ledge may have no way down)."""
        if not keys:
            got = path_to(cur, portal)
            return got[1] if got else None
        cands = []
        for k in keys:
            got = path_to(cur, {k})
            if got:
                cands.append((len(got[1]), k, got))
        cands.sort(key=lambda c: c[0])
        for _, k, (nxt, mv, cell) in cands:
            rest = keys - {cell}
            if feasible(nxt, rest | portal):
                tail = search(nxt, rest, depth + 1)
                if tail is not None:
                    return mv + tail
        return None

    moves = search(start, keys)
    if moves is None:
        return None
    # the moves as inputs: (ticks, buttons)
    out = []
    for kind, dx, n in moves:
        b = "RIGHT" if dx > 0 else "LEFT" if dx < 0 else ""
        if kind == "walk":
            out.append((1, b))
        elif kind == "jump":
            out.append((1, (b + "+A") if b else "A"))
            if n > 1:
                out.append((n - 1, ""))
        else:
            out.append((1, b))
            if n > 1:
                out.append((n - 1, ""))
    return out


def check(r: Room) -> list[str]:
    seen, touched = reach(r)
    probs = []
    for y, row in enumerate(r.g):
        for x, c in enumerate(row):
            if c in "kX" and (x, y) not in touched:
                probs.append(f"{r.name}: {c} at {x},{y} cannot be reached")
    return probs


# ------------------------------------------------------------------ the rooms
S = lambda **kw: kw  # a colour scheme: kind -> "ink/paper"; a "+" in front means bright
ROOMS: list[Room] = []

# 1 ------------------------------------------------------------------------ the mine's mouth
r = Room("bocamina", 1, S(air="white/black", wall="red/black", floor="yellow/black", crumble="yellow/black", conveyor="cyan/black",
                          hazard="+green/black", key="+yellow/black", portal="+white/blue", deco="blue/black"))
r.h(12, 5, 11).h(12, 16, 22).h(9, 1, 6).h(9, 11, 16).h(9, 21, 26).h(6, 5, 10).h(6, 17, 22).h(3, 1, 6).h(3, 12, 17).h(3, 22, 26)
r.put(2, 13, "P").rect(25, 13, 26, 14, "X").put(7, 2, "l")
for x, y in ((3, 8), (14, 8), (23, 8), (8, 5), (19, 5), (14, 2)):
    r.put(x, y, "k")
r.put(9, 11, "*").put(19, 11, "*").put(12, 8, "*").put(24, 8, "*")
r.guard("robot", 9, 13, 5, 21, 0.6)
ROOMS.append(r)

# 2 ------------------------------------------------------------------------ the bats' shaft
r = Room("murcielagos", 2, S(air="cyan/black", wall="+magenta/black", floor="+cyan/black", crumble="cyan/black", conveyor="white/black",
                            hazard="+red/black", key="+yellow/black", portal="+white/magenta", deco="blue/black"))
r.h(12, 3, 8).h(12, 12, 16).h(12, 20, 25).h(9, 8, 12).h(9, 17, 21).h(6, 2, 7).h(6, 13, 17).h(6, 22, 26).h(3, 8, 13).h(3, 19, 23)
r.put(2, 13, "P").rect(25, 13, 26, 14, "X")
for x, y in ((5, 11), (14, 11), (10, 8), (4, 5), (15, 5), (24, 5), (10, 2), (21, 2)):
    r.put(x, y, "k")
for x in (4, 15, 17, 26):
    r.put(x, 1, "v")
r.put(16, 2, "v").put(6, 2, "v")
r.guard("murcielago", 4, 9, 2, 25, 0.9, wave=14).guard("murcielago", 20, 4, 3, 24, 0.7, wave=10)
ROOMS.append(r)

# 3 ------------------------------------------------------------------------ the belts
r = Room("cinta", 3, S(air="+white/black", wall="white/blue", floor="+yellow/blue", crumble="yellow/blue", conveyor="+red/black",
                       hazard="+green/blue", key="+yellow/blue", portal="+white/red", deco="blue/black"))
r.h(12, 2, 11, ">").h(12, 16, 25, "<").h(9, 4, 13, "<").h(9, 17, 24, ">").h(6, 2, 10, ">").h(6, 15, 25, "<").h(3, 5, 12, "=").h(3, 16, 23, "=")
r.rect(13, 10, 13, 12, "#")
r.put(2, 13, "P").rect(25, 13, 26, 14, "X")
for x, y in ((6, 11), (20, 11), (8, 8), (20, 8), (4, 5), (22, 5), (9, 2), (20, 2)):
    r.put(x, y, "k")
r.put(14, 14, "*").put(15, 14, "*").put(11, 5, "*").put(14, 2, "*")
r.guard("robot", 6, 13, 3, 23, 0.7).guard("robot", 17, 4, 12, 24, 0.5)
ROOMS.append(r)

# 4 ------------------------------------------------------------------------ the cave-in
r = Room("derrumbe", 4, S(air="+yellow/black", wall="+red/black", floor="+yellow/black", crumble="+yellow/black", conveyor="+cyan/black",
                          hazard="+red/black", key="+white/black", portal="+white/yellow", deco="red/black"))
r.h(13, 1, 4, "=").h(14, 5, 20, "^").h(13, 21, 26, "=")
r.h(11, 5, 10, "-").h(11, 14, 18, "-").h(11, 22, 25, "-").h(8, 2, 7, "-").h(8, 11, 15, "-").h(8, 19, 24, "-")
r.h(5, 4, 9, "-").h(5, 13, 18, "-").h(5, 22, 26, "-").h(2, 8, 12, "-").h(2, 16, 20, "-")
r.put(2, 11, "P").rect(24, 11, 25, 12, "X")
for x, y in ((8, 10), (16, 10), (4, 7), (13, 7), (21, 7), (6, 4), (15, 4), (24, 4)):
    r.put(x, y, "k")
r.guard("arana", 14, 2, 2, 11, 0.5).guard("arana", 8, 3, 3, 9, 0.4)
ROOMS.append(r)

# 5 ------------------------------------------------------------------------ the mushroom gallery
r = Room("hongos", 1, S(air="+green/black", wall="green/black", floor="+green/black", crumble="green/black", conveyor="cyan/black",
                        hazard="+magenta/black", key="+yellow/black", portal="+white/green", deco="green/black"))
r.h(12, 3, 10).h(12, 15, 24).h(9, 6, 13).h(9, 18, 26).h(6, 1, 8).h(6, 12, 20).h(3, 4, 9).h(3, 14, 23)
r.rect(11, 10, 12, 12, "#").rect(2, 1, 3, 2, "#")
r.put(2, 13, "P").rect(25, 13, 26, 14, "X")
for x, y in ((7, 11), (20, 11), (9, 8), (24, 8), (3, 5), (18, 5), (6, 2), (21, 2)):
    r.put(x, y, "k")
for x, y in ((5, 11), (17, 11), (22, 11), (8, 8), (20, 8), (2, 5), (15, 5), (7, 2), (17, 2), (21, 2)):
    r.put(x, y, "*")
r.guard("rata", 6, 13, 2, 20, 0.9).guard("rata", 22, 13, 12, 23, 0.7)
ROOMS.append(r)

# 6 ------------------------------------------------------------------------ the cursed well
r = Room("pozo", 2, S(air="+white/black", wall="+blue/black", floor="+white/black", crumble="white/black", conveyor="cyan/black",
                      hazard="+yellow/black", key="+yellow/black", portal="+white/cyan", deco="blue/black"))
r.h(12, 3, 7).h(12, 13, 17).h(12, 22, 26).h(9, 8, 12).h(9, 18, 21).h(6, 3, 8).h(6, 14, 19).h(6, 23, 26).h(3, 9, 13).h(3, 18, 22)
r.rect(1, 4, 1, 9, "#").rect(26, 8, 26, 11, "#")
r.put(2, 13, "P").rect(24, 13, 25, 14, "X")
for x, y in ((5, 11), (15, 11), (10, 8), (19, 8), (5, 5), (17, 5), (11, 2), (20, 2)):
    r.put(x, y, "k")
r.guard("ojo", 1, 10, 0, 0, 0).guard("llama", 11, 13, 9, 13, 0.4).guard("llama", 20, 13, 9, 13, 0.5)
r.guard("ojo", 26, 5, 0, 0, 0)
ROOMS.append(r)

# 7 ------------------------------------------------------------------------ the foundry
r = Room("fundicion", 3, S(air="+red/black", wall="red/yellow", floor="+yellow/red", crumble="yellow/red", conveyor="+white/red",
                           hazard="+cyan/black", key="+white/red", portal="+yellow/red", deco="red/black"))
r.h(12, 2, 9, ">").h(12, 17, 25, "<").h(9, 5, 14, "<").h(9, 19, 26, "=").h(6, 1, 9, "=").h(6, 14, 22, ">").h(3, 4, 10, "-").h(3, 15, 24, "=")
r.rect(12, 7, 12, 12, "#")
r.put(2, 13, "P").rect(25, 13, 26, 14, "X")
for x, y in ((6, 11), (22, 11), (8, 8), (24, 8), (4, 5), (20, 5), (7, 2), (20, 2)):
    r.put(x, y, "k")
r.put(15, 14, "^").put(16, 14, "^").put(11, 8, "*")
r.guard("vagoneta", 4, 13, 2, 22, 1.1).guard("llama", 14, 12, 8, 12, 0.4).guard("llama", 17, 6, 3, 6, 0.5)
ROOMS.append(r)

# 8 ------------------------------------------------------------------------ the mine's heart
r = Room("corazon", 4, S(air="+magenta/black", wall="+white/red", floor="+yellow/black", crumble="+yellow/black", conveyor="+cyan/black",
                         hazard="+green/black", key="+yellow/red", portal="+white/magenta", deco="red/black"))
r.h(12, 2, 8, "-").h(12, 13, 17, "=").h(12, 20, 24, ">").h(9, 6, 11, "=").h(9, 16, 20, "-").h(6, 2, 7, "<").h(6, 12, 17, "=").h(6, 22, 26, "-")
r.h(3, 8, 12, "=").h(3, 17, 22, "=").rect(10, 4, 10, 8, "#").rect(14, 13, 14, 14, "#")
r.put(2, 13, "P").rect(25, 13, 26, 14, "X")
for x, y in ((4, 11), (15, 11), (8, 8), (18, 8), (4, 5), (14, 5), (24, 5), (10, 2), (20, 2)):
    r.put(x, y, "k")
r.put(9, 14, "^").put(10, 14, "^").put(17, 14, "*").put(21, 14, "*").put(12, 11, "*").put(19, 8, "*")
r.guard("robot", 5, 13, 2, 13, 0.7).guard("murcielago", 4, 5, 2, 25, 0.8, wave=12).guard("llama", 23, 13, 9, 13, 0.5)
r.guard("arana", 21, 4, 2, 7, 0.5)
ROOMS.append(r)

# decoration: what makes a room a place (only onto air; nothing to touch)
ROOMS[0].dh(14, 1, 24, "r").deco("l", (20, 1), (13, 2)).deco("w", (1, 1), (26, 1))
ROOMS[1].deco("c", (4, 11), (21, 11), (19, 8), (14, 5), (23, 5)).deco("w", (1, 1), (25, 1)).deco("s", (10, 14), (18, 14))
ROOMS[2].dh(1, 1, 26, "3").dv(1, 2, 12, "4").deco("l", (13, 2), (22, 5))
ROOMS[3].dh(1, 1, 26, "1").deco("2", (4, 2), (12, 2), (20, 2), (26, 2)).deco("l", (14, 3)).deco("s", (9, 13), (15, 13))
ROOMS[4].deco("w", (26, 1), (4, 1)).deco("s", (10, 14), (23, 14)).deco("l", (14, 1))
ROOMS[5].deco("w", (2, 1), (25, 1)).deco("c", (10, 14), (19, 14), (5, 14)).deco("s", (8, 14), (23, 14))
ROOMS[6].dh(1, 1, 26, "3").dv(26, 2, 7, "4").deco("l", (13, 2), (24, 2))
ROOMS[7].deco("c", (3, 14), (12, 14), (18, 14), (24, 11)).deco("w", (1, 1), (26, 1)).deco("s", (6, 14), (24, 14))

for _r in ROOMS:  # a sprite over a decoration takes its ink: the decoration shares the air's, so nothing is lost
    _r.scheme['deco'] = _r.scheme['air']

BORDERS = ["blue", "black", "red", "black", "blue", "black", "red", "magenta"]
IDS = ["bocamina", "murcielagos", "cinta", "derrumbe", "hongos", "pozo", "fundicion", "corazon"]


def lua_str(v):
    if isinstance(v, str):
        return '"' + v.replace('"', '\\"') + '"'
    if isinstance(v, dict):
        return "{" + ", ".join(f"{k} = {lua_str(x)}" for k, x in v.items()) + "}"
    if isinstance(v, (list, tuple)):
        return "{" + ", ".join(lua_str(x) for x in v) + "}"
    return repr(v)


def write_lua():
    out = ["-- Socavon's rooms: made by gen/rooms_design.py (which checks that every key and the portal can be reached): do not edit",
           "-- # wall  = ledge  - crumbles  > < belts  * plant  ^ spikes  v stalactite  k key  X portal (2x2)  P start  . air",
           "-- 1 2 beams  3 4 pipes  l lamp  w web  r rail  s skull  c crystal (decoration)", "return {"]
    for i, r in enumerate(ROOMS):
        out.append("  {")
        out.append(f'    id = "{IDS[i]}", theme = {r.theme}, border = "{BORDERS[i]}", air = {r.air},')
        out.append("    scheme = " + lua_str(r.scheme) + ",")
        out.append("    tiles = {")
        out += [f'      "{row}",' for row in r.rows()]
        out.append("    },")
        out.append("    guards = {")
        for g in r.guards:
            out.append("      " + lua_str(g) + ",")
        out.append("    },")
        out.append("  },")
    out.append("}")
    (HERE / "rooms.lua").write_text("\n".join(out) + "\n")
    sols = ["-- Socavon: the inputs that cross each room without belts, found by gen/rooms_design.py's search: {ticks, buttons}",
            "-- (the demo of the title plays them; tests/socavon.script plays them in the game to check the physics are the same)", "return {"]
    for i, r in enumerate(ROOMS):
        if "--solve" not in sys.argv:
            break
        sol = solve(r)
        if sol is None:
            continue
        runs = []
        for n, b in sol:  # run-length: the same buttons next to each other join
            if runs and runs[-1][1] == b:
                runs[-1][0] += n
            else:
                runs.append([n, b])
        sols.append(f"  [{i + 1}] = {{" + ", ".join(f'{{{n}, "{b}"}}' for n, b in runs) + "},")
    sols.append("}")
    (HERE / "solutions.lua").write_text("\n".join(sols) + "\n")


if __name__ == "__main__":
    bad = []
    for room in ROOMS:
        probs = check(room)
        bad += probs
        print(f"--- {room.name}: {len(probs)} problems")
        print("\n".join(room.rows()))
    print("\n".join(bad) or "all keys and portals reachable")
    if bad:
        sys.exit(1)
    write_lua()
