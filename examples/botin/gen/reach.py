"""A cheap check that a level can be played: from the start, which cells can the hero stand on, with walking, jumps of up to two cells high and three wide
(four across a flat gap: a dash), falls, springs, and breaking the blocks that can be broken (they count as air). Every thing that has to be taken (jewels, the frog, the
keyzer, the chest, the boss) must be near a reachable cell, and the way back from the frog to the start must exist. Run: python3 gen/reach.py"""
from __future__ import annotations

import sys
from collections import deque
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent))

WALL = set("#THm")          # stops the body (mud is a floor to stand on, never a wall)
BREAK = set("bBKJF")        # solid until broken: counted as air for walking, and as floor to stand on
FLOOR = WALL | BREAK | set("=sM")
HURT = set("^vL")
JUMP_UP, JUMP_ACROSS, JUMP_FLAT, SPRING_UP = 2, 3, 4, 6


class Grid:
    def __init__(self, lv):
        self.lv, self.W, self.H, self.g = lv, lv.w, lv.h, lv.g

    def at(self, x, y):
        return "H" if not (0 <= x < self.W) else ("." if y < 0 else ("#" if y >= self.H else self.g[y][x]))

    def body_free(self, x, y):  # the hero's two cells: (x, y) and (x, y-1)
        return all(self.at(x, yy) not in WALL | HURT for yy in (y, y - 1))

    def crawl_ok(self, x, y):
        return self.at(x, y) not in WALL | HURT

    def support(self, x, y):
        return self.at(x, y + 1) in FLOOR

    def standing(self, x, y):
        return self.body_free(x, y) and self.support(x, y)

    def land(self, x, y):
        for yy in range(y, self.H + 1):
            if not self.body_free(x, yy):
                return None
            if self.support(x, yy):
                return (x, yy)
        return None

    def flood(self, starts):
        seen = set(starts)
        q = deque(starts)
        while q:
            x, y = q.popleft()
            nxt = []
            wr = self.lv.notes.get("water_row")
            if wr is not None and y >= wr - 1:
                # swimming: any free cell next to this one, and up to the surface
                for dx in (-1, 0, 1):
                    for dy in (-1, 0, 1):
                        nx, ny = x + dx, y + dy
                        if ny >= wr - 1 and self.body_free(nx, ny):
                            nxt.append((nx, ny))
            for dx in (-1, 1):
                if self.body_free(x + dx, y):
                    nxt.append((x + dx, y) if self.support(x + dx, y) else self.land(x + dx, y))
                elif self.at(x + dx, y) not in WALL | HURT and self.at(x + dx, y - 1) in WALL and self.support(x + dx, y):
                    nxt.append((x + dx, y))  # a crawl under a one-cell ceiling
            up = SPRING_UP if self.at(x, y + 1) in "sS" or self.at(x, y) == "S" else JUMP_UP
            if self.at(x, y) == "S":
                for k in range(1, 6):
                    if self.body_free(x, y - k):
                        nxt.append((x, y - k))
            for dx in range(-JUMP_FLAT, JUMP_FLAT + 1):
                for rise in range(-8, up + 1):
                    if abs(dx) > JUMP_ACROSS and rise != 0 and not (rise < 0 and abs(dx) <= JUMP_ACROSS + 1):
                        continue
                    tx, ty = x + dx, y - rise
                    if not self.standing(tx, ty):
                        continue
                    if rise > 0 and any(self.at(x, y - k) in WALL for k in range(2, rise + 2)):
                        continue  # head hits a wall going up
                    nxt.append((tx, ty))
            for t in nxt:
                if t and t not in seen and 0 <= t[0] < self.W and 0 <= t[1] < self.H:
                    seen.add(t)
                    q.append(t)
        return seen


def check(lv, verbose=True):
    gr = Grid(lv)
    start = next(t for t in lv.things if t["kind"] == "start")
    s0 = (int(start["x"]), int(start["y"]))
    seen = gr.flood([s0])
    problems = []

    def near(cx, cy):
        return any(abs(x - cx) <= 2 and cy - 5 <= y <= cy + 2 for x, y in seen)

    for t in lv.things:
        if t["kind"] in ("jewel", "frog", "keyzer", "chest", "boss", "heart", "diamond", "gem") and not near(int(t["x"]), int(t["y"])):
            problems.append(f"{lv.name}: {t['kind']} {t.get('n', '')} at {t['x']},{t['y']} out of reach")
    frog = next((t for t in lv.things if t["kind"] == "frog"), None)
    if frog:
        pick = sorted(seen, key=lambda c: abs(c[0] - frog["x"]) + abs(c[1] - frog["y"] - 1))[0]
        if s0 not in gr.flood([pick]):
            problems.append(f"{lv.name}: no way back to the start from the frog")
    if verbose:
        for p in problems:
            print("  PROBLEM", p)
        print(f"  {lv.name}: {len(seen)} standing cells reached" + (", ok" if not problems else ""))
    return problems, seen


if __name__ == "__main__":
    import levels_design as L

    bad = 0
    for lv in L.LEVELS:
        bad += len(check(lv)[0])
    sys.exit(1 if bad else 0)
