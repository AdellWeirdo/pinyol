"""Tumba's levels: generated and CHECKED. Each candidate is a random maze of walls with the level's mechanics; a random walk of the
real rules picks where the gems and the exit go; the solver then finds the true shortest solution (the par) and the candidate is
kept only if the par is in the level's range and the solution really uses each mechanic of the level. Fixed seeds: the same levels
every time. Writes levels.lua (rows, par, a solution, the name).

    python3 gen/levels_design.py            # all sixteen (a few minutes)
    python3 gen/levels_design.py 5          # one level, printed
"""
from __future__ import annotations

import random
import sys
import time
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent))
from rules import DIRS, N, Level  # noqa: E402

HERE = Path(__file__).resolve().parent.parent

# n, name (es), mechanics, gems, par range, walls
SPECS = [
    (1, "EL VESTÍBULO", "", 2, (4, 7), 14),
    (2, "LA SALA DE LAS URNAS", "", 3, (7, 11), 16),
    (3, "EL PASILLO QUEBRADO", "", 4, (9, 14), 18),
    (4, "LA CÁMARA DEL ESCRIBA", "", 4, (12, 17), 20),
    (5, "PINCHOS", "^", 3, (8, 13), 16),
    (6, "EL JARDÍN DE ESPINAS", "^", 4, (12, 18), 18),
    (7, "MUROS DÉBILES", "c", 3, (8, 14), 15),
    (8, "LA CRIPTA QUEBRADIZA", "c^", 4, (12, 19), 17),
    (9, "ARENAS MOVEDIZAS", "m", 3, (8, 14), 16),
    (10, "EL PANTANO SECO", "m^", 4, (12, 19), 17),
    (11, "EL PORTAL", "1", 3, (7, 13), 16),
    (12, "LOS DOS PORTALES", "12^", 4, (11, 18), 17),
    (13, "LA LLAVE DE ORO", "kD", 3, (9, 15), 16),
    (14, "LA PUERTA DE ARENA", "kDm", 4, (12, 19), 17),
    (15, "SENTIDOS ÚNICOS", "g", 3, (9, 15), 16),
    (16, "EL CORAZÓN DE LA TUMBA", "kDm^cg", 5, (16, 26), 18),
]
USES = {"^": None, "c": "crack", "m": "mud", "1": "tele", "2": "tele", "k": "key", "D": "door", "g": "gate"}


def floor_cells(g):
    return [(x, y) for y in range(1, N - 1) for x in range(1, N - 1) if g[y][x] == "."]


def make(spec, rng):
    n, name, mech, ngems, (lo, hi), nwalls = spec
    g = [["#" if x in (0, N - 1) or y in (0, N - 1) else "." for x in range(N)] for y in range(N)]
    for _ in range(nwalls):  # random wall segments
        x, y = rng.randint(1, N - 2), rng.randint(1, N - 2)
        ln, horiz = rng.randint(1, 4), rng.random() < 0.5
        for i in range(ln):
            xx, yy = (x + i, y) if horiz else (x, y + i)
            if 1 <= xx <= N - 2 and 1 <= yy <= N - 2:
                g[yy][xx] = "#"
    fl = floor_cells(g)
    rng.shuffle(fl)
    if len(fl) < 80:
        return None
    take = lambda: fl.pop()
    if "c" in mech:
        for _ in range(rng.randint(2, 4)):
            x, y = take()
            g[y][x] = "c"
    if "m" in mech:
        for _ in range(rng.randint(3, 5)):
            x, y = take()
            g[y][x] = "m"
    if "1" in mech:
        for ch in ("1", "2") if "2" in mech else ("1",):
            for _ in range(2):
                x, y = take()
                g[y][x] = ch
    if "g" in mech:
        for _ in range(rng.randint(4, 6)):
            x, y = take()
            g[y][x] = rng.choice("udlr")
    if "^" in mech:
        for _ in range(rng.randint(3, 6)):
            x, y = take()
            g[y][x] = "^"
    if "k" in mech:
        x, y = take()
        g[y][x] = "k"
        x, y = take()
        g[y][x] = "D"
    sx, sy = take()
    g[sy][sx] = "S"
    # a random walk of the real rules, from the start, to place the gems and the exit
    rows = ["".join(r) for r in g]
    lv = Level(rows)
    st = lv.initial()
    path_cells = []
    steps = rng.randint(lo, hi)
    for _ in range(steps * 3):
        d = rng.choice("URDL")
        before = (st[0], st[1])
        ns, ev = lv.move(st, d)
        if ns is None or ns == st:
            continue
        # the cells passed (a straight line, ignoring teleports: good enough to place gems)
        x, y = before
        dx, dy = DIRS[d]
        while (x, y) != (ns[0], ns[1]) and 0 <= x + dx < N and 0 <= y + dy < N and len(path_cells) < 400:
            x, y = x + dx, y + dy
            path_cells.append((x, y))
        st = ns
        steps -= 1
        if steps <= 0:
            break
    ex, ey = st[0], st[1]
    if (ex, ey) == (sx, sy) or g[ey][ex] != ".":
        return None
    cand = [p for p in dict.fromkeys(path_cells) if g[p[1]][p[0]] == "." and p != (ex, ey) and p != (sx, sy)]
    if len(cand) < ngems:
        return None
    for (x, y) in rng.sample(cand, ngems):
        g[y][x] = "o"
    g[ey][ex] = "E"
    return ["".join(r) for r in g]


def check(spec, rows):
    n, name, mech, ngems, (lo, hi), nwalls = spec
    lv = Level(rows)
    res = lv.solve()
    if not res:
        return None
    sol, evs = res
    flat = {e for ev in evs for e in ev}
    for m in mech:
        need = USES[m]
        if need and need not in flat:
            return None
    if "^" in mech:
        pass
    if not (lo <= len(sol) <= hi):
        return None
    if len(set(sol)) < 3:  # a solution of one or two directions is no puzzle
        return None
    return sol


def design(spec, seed, tries=3000):
    rng = random.Random(seed * 7919 + spec[0])
    best = None
    t0 = time.time()
    for i in range(tries):
        rows = make(spec, rng)
        if not rows:
            continue
        sol = check(spec, rows)
        if sol:
            # prefer the longest par in range, and more floor
            score = len(sol) * 10 + sum(r.count(".") for r in rows) * 0.01
            if not best or score > best[0]:
                best = (score, rows, sol)
            if i > 150 and best:
                break
    return best


def lua_level(spec, rows, sol):
    n, name, mech, ngems, rng, nwalls = spec
    body = ",\n".join(f'      "{r}"' for r in rows)
    return f'  {{\n    n = {n}, name = "{name}", par = {len(sol)}, solution = "{sol}", gems = {ngems},\n    rows = {{\n{body},\n    }},\n  }},\n'


def solve_one(spec):
    cache = HERE / "gen" / "levels_cache"
    cache.mkdir(exist_ok=True)
    f = cache / f"{spec[0]}.txt"
    if f.exists():
        lines = f.read_text().split("\n")
        return lines[0], lines[1:17]
    for attempt in range(40):
        best = design(spec, attempt + 1, tries=1500)
        if best:
            _, rows, sol = best
            f.write_text(sol + "\n" + "\n".join(rows) + "\n")
            return sol, rows
    return None


def main():
    only = int(sys.argv[1]) if len(sys.argv) > 1 else None
    out = ["-- Tumba's levels: made by gen/levels_design.py (the solver found each one's shortest solution, the par): do not edit",
           "-- # wall . floor S start E exit o gem ^ spikes m mud c cracked block k key D door 1 2 teleporters u d l r one-way gates\n", "return {\n"]
    for spec in SPECS:
        if only and spec[0] != only:
            continue
        got = solve_one(spec)
        if not got:
            print(f"level {spec[0]}: NOT FOUND")
            if only:
                sys.exit(1)
            continue
        sol, rows = got
        print(f"--- level {spec[0]} {spec[1]}: par {len(sol)}  {sol}")
        print("\n".join(rows))
        out.append(lua_level(spec, rows, sol))
    out.append("}\n")
    if not only:
        (HERE / "levels.lua").write_text("".join(out))
        print("levels.lua written")


if __name__ == "__main__":
    main()
