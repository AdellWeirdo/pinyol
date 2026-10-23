"""The rules of Tumba, the one place they are written in Python (core/rules.lua is the same in Lua and tests/tumba.script plays the
solutions found here through it to prove they agree).

A level is 16 rows of 16 characters:
  #  wall            .  floor            S  start (a floor)        E  the exit (a wall until every gem is taken; entering it wins)
  o  a gem           ^  spikes (entering them is death)             m  mud (a slide ends on it)
  c  a cracked block (a slide into it breaks it, and stops before it)   k  a key   D  a locked door (opens when you slide into it holding the key)
  1 2  teleporters: two cells of the same digit are a pair; entering one puts you on the other and you go on sliding (once a move)
  u d l r  one-way gates: passable only moving up, down, left, right (a wall to anything else)
The hero slides in a direction until something stops him. A move that changes nothing is not a move.
"""
from __future__ import annotations

from collections import deque

N = 16
DIRS = {"U": (0, -1), "D": (0, 1), "L": (-1, 0), "R": (1, 0)}
GATE = {"u": "U", "d": "D", "l": "L", "r": "R"}


class Level:
    def __init__(self, rows):
        assert len(rows) == N and all(len(r) == N for r in rows), [len(r) for r in rows]
        self.g = [list(r) for r in rows]
        self.start = None
        self.pads = {}
        self.gems = []
        for y in range(N):
            for x in range(N):
                c = self.g[y][x]
                if c == "S":
                    self.start = (x, y)
                    self.g[y][x] = "."
                elif c in "12":
                    self.pads.setdefault(c, []).append((x, y))
                elif c == "o":
                    self.gems.append((x, y))
        self.gem_index = {p: i for i, p in enumerate(self.gems)}
        self.cracks = [(x, y) for y in range(N) for x in range(N) if self.g[y][x] == "c"]
        self.crack_index = {p: i for i, p in enumerate(self.cracks)}
        self.doors = [(x, y) for y in range(N) for x in range(N) if self.g[y][x] == "D"]
        self.keys = [(x, y) for y in range(N) for x in range(N) if self.g[y][x] == "k"]
        self.key_index = {p: i for i, p in enumerate(self.keys)}
        self.door_index = {p: i for i, p in enumerate(self.doors)}

    def initial(self):
        # state: x, y, gems taken (bit mask), keys held (count), cracks broken (mask), doors opened (mask), keys taken (mask)
        return (self.start[0], self.start[1], 0, 0, 0, 0, 0)

    def move(self, st, d):
        """(new state, events) or (None, events) for death; the state is the same if nothing happened. Events: gem key door crack mud tele gate."""
        x, y, gm, kh, cm, dm, km = st
        dx, dy = DIRS[d]
        ev = []
        tele_used = False  # a slide teleports once: two pads in a line could otherwise loop for ever
        all_gems = gm == (1 << len(self.gems)) - 1
        while True:
            nx, ny = x + dx, y + dy
            if not (0 <= nx < N and 0 <= ny < N):
                break
            c = self.g[ny][nx]
            if c == "#":
                break
            if c == "c":
                i = self.crack_index[(nx, ny)]
                if not cm >> i & 1:
                    cm |= 1 << i
                    ev.append("crack")
                    break
            if c == "D":
                i = self.door_index[(nx, ny)]
                if not dm >> i & 1:
                    if kh > 0:
                        kh -= 1
                        dm |= 1 << i
                        ev.append("door")
                    else:
                        break
            if c == "E" and not all_gems:
                break
            if c in GATE:
                if GATE[c] != d:
                    break
                ev.append("gate")
            x, y = nx, ny
            if c == "^":
                return None, ev + ["dead"]
            if c == "o":
                i = self.gem_index[(x, y)]
                if not gm >> i & 1:
                    gm |= 1 << i
                    ev.append("gem")
                    all_gems = gm == (1 << len(self.gems)) - 1
            if c == "k":
                i = self.key_index[(x, y)]
                if not km >> i & 1:
                    km |= 1 << i
                    kh += 1
                    ev.append("key")
            if c == "E":
                ev.append("win")
                return (x, y, gm, kh, cm, dm, km), ev
            if c == "m":
                ev.append("mud")
                break
            if c in "12" and not tele_used:
                a, b = self.pads[c]
                x, y = b if (x, y) == a else a
                tele_used = True
                ev.append("tele")
        return (x, y, gm, kh, cm, dm, km), ev

    def solve(self, limit=60000):
        """The shortest list of moves ("RDLU"...) that wins, or None."""
        s0 = self.initial()
        parent = {s0: None}
        q = deque([s0])
        while q and len(parent) < limit:
            st = q.popleft()
            for d in "URDL":
                ns, ev = self.move(st, d)
                if ns is None or (ns == st and not ev):
                    continue
                if ns in parent:
                    continue
                parent[ns] = (st, d, ev)
                if "win" in ev:
                    out, cur = [], ns
                    evs = []
                    while parent[cur]:
                        cur, dd, e = parent[cur][0], parent[cur][1], parent[cur][2]
                        out.append(dd)
                        evs.append(e)
                    return "".join(reversed(out)), list(reversed(evs))
                q.append(ns)
        return None
