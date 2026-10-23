"""Checks the maps of Cerezo against what the game does with each metatile: everything the hero has to reach can be reached, no thing
stands inside a wall, every exit lands on a floor.

    python3 gen/check_world.py [--stubs] [--verbose]

The walk is a flood from the cell where the hero arrives in each area. Things that open on their own (gates, locks, the block puzzle,
the cobwebs, the seal of the cave) count as open: this finds the map's mistakes, not the puzzles' order. Bushes (cut) and
dig spots are walls until the pala is used, so what lies behind them is reported as "behind a bush" and not as an error.
"""
from __future__ import annotations

import importlib
import sys
from collections import deque
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent))
import build  # noqa: E402
import gbart as g  # noqa: E402
import rules  # noqa: E402
import world  # noqa: E402

WALL = {"solid", "water", "pit"}
OPENS = {"gate", "lock", "block", "keydrop", "socket", "zone", "plant"}   # things that stand in the way until the game opens them
ON_FLOOR = {"exit", "enemy"}                                              # things the hero meets by walking onto them
BESIDE = {"npc", "sign", "chest", "nest", "buried", "boss", "torch", "socket", "block", "plant"}  # things the hero meets from a neighbouring cell


def load():
    build.load_modules()
    rules.apply()
    if "--stubs" in sys.argv:
        build.stub_missing()
    out = []
    for m in build.MAPS:
        mod = importlib.import_module(m)
        out.extend(mod.AREAS)
    return {a.id: a for a in out}


def flags_of(area: world.Area, names: list[list[str]]):
    metas = g.ART.metas[area.tileset]
    return [[set(metas[n].flags) if n in metas else {"solid"} for n in row] for row in names]


def walkable(fl: set) -> bool:
    if "door" in fl or "stairs" in fl:
        return True
    return not (fl & WALL)


def flood(area, flags, start, opened):
    h, w = len(flags), len(flags[0])
    seen, q = {start}, deque([start])
    behind = set()
    while q:
        x, y = q.popleft()
        for dx, dy in ((1, 0), (-1, 0), (0, 1), (0, -1)):
            nx, ny = x + dx, y + dy
            if not (0 <= nx < w and 0 <= ny < h) or (nx, ny) in seen:
                continue
            fl = flags[ny][nx]
            if (nx, ny) in opened or walkable(fl):
                seen.add((nx, ny))
                q.append((nx, ny))
            elif "cut" in fl:
                behind.add((nx, ny))
    return seen, behind


def main() -> int:
    areas = load()
    problems = []
    arrivals = {a: [] for a in areas}
    for a in areas.values():
        for t in a.things:
            if t["kind"] == "exit":
                if t["to"] not in areas:
                    problems.append(f"{a.id}: exit at {t['cx']},{t['cy']} goes to {t['to']!r}, which does not exist")
                else:
                    arrivals[t["to"]].append((t["tx"], t["ty"], a.id))
    for a in areas.values():
        names = a.names(g.ART.metas[a.tileset])
        flags = flags_of(a, names)
        h, w = len(flags), len(flags[0])
        opened = {(t["cx"], t["cy"]) for t in a.things if t["kind"] in OPENS}
        starts = arrivals[a.id] or [(None, None, None)]
        reach = set()
        for tx, ty, src in starts:
            if tx is None:
                continue
            if not (0 <= tx < w and 0 <= ty < h):
                problems.append(f"{src} -> {a.id}: arrival {tx},{ty} is outside the area")
                continue
            if not walkable(flags[ty][tx]):
                problems.append(f"{src} -> {a.id}: arrival {tx},{ty} is on {names[ty][tx]} {sorted(flags[ty][tx])}")
            seen, behind = flood(a, flags, (tx, ty), opened)
            reach |= seen
        if not reach:
            continue
        for t in a.things:
            x, y, k = t["cx"], t["cy"], t["kind"]
            where = f"{a.id} {k} {t.get('id') or t.get('text') or t.get('item') or ''} at {x},{y} on {names[y][x]}"
            fl = flags[y][x]
            if k in ON_FLOOR and not walkable(fl) and (x, y) not in opened:
                problems.append(f"{where}: inside a wall {sorted(fl)}")
            elif k in ON_FLOOR and (x, y) not in reach:
                problems.append(f"{where}: not reachable")
            if k in BESIDE:
                near = any((x + dx, y + dy) in reach for dx, dy in ((1, 0), (-1, 0), (0, 1), (0, -1)))
                if not near and (x, y) not in reach:
                    problems.append(f"{where}: no walkable cell beside it")
            if k == "npc" and not walkable(fl):
                problems.append(f"{where}: stands on a wall {sorted(fl)}")
        if "--verbose" in sys.argv:
            print(f"{a.id}: {len(reach)} cells reachable of {w * h}")
    for p in problems:
        print("PROBLEM", p)
    print(f"{len(problems)} problems in {len(areas)} areas")
    return 1 if problems else 0


if __name__ == "__main__":
    sys.exit(main())
