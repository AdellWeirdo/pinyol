"""The map compiler of Cerezo: from text maps of terrain to the engine's tilemaps and the Lua data of each area.

An area is a grid of screens, each 15x9 metatiles of 16x16 pixels (240x144, what a screen shows under the 16-pixel
status bar). A content module (maps_overworld.py, ...) writes the screens as rows of characters and says what each
character means, then calls `area.compile(...)`:

    OW = Area("overworld", "overworld", 3, 3, legend={"g": ["grass_a", "grass_b"], "d": Family("dirt"), "b": "bush"})
    OW.screen(0, 0, ["ggggggggggggggg", ...])          # nine rows of fifteen characters
    OW.stamp("house_a", 4, 2)                           # a prefab laid over the map at cell 4, 2 (area coordinates)
    OW.thing("npc", id="yaya", cx=4, cy=3, face="down") # something that lives in the area, at a cell

What a legend value means: a name is that metatile; a list is one of those chosen by a fixed hash of the cell (so the
same map always draws the same); `Family("dirt")` is a terrain that borders itself (gbart.autotile: dirt_n, dirt_ne,
dirt_in_ne... and the plain `dirt_a`, `dirt_b`), which sees across the screens' edges.
"""
from __future__ import annotations

import sys
from dataclasses import dataclass, field
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent))
import gbart as g  # noqa: E402

SCREEN_W, SCREEN_H = 15, 9  # metatiles


@dataclass
class Family:
    name: str
    variants: tuple = ()  # the plain pieces; default <name>_a, <name>_b
    joins: str = ""       # characters that count as this terrain for its edges (sand joins the water that meets it)


@dataclass
class Member:
    """A thing lying on a terrain that borders itself (a shell on the sand): it draws its own tile (`tiles`, one by the cell's
    hash) but counts as the terrain `of` (a legend character) for the edges of that terrain, so it does not make a hole in it."""
    of: str
    tiles: object


@dataclass
class Connected:
    """A thing that joins its neighbours of the same character (a fence): the piece is chosen by which of the four sides
    have the same character: `table[mask]`, mask = N 1 + E 2 + S 4 + W 8; a name, or a list to choose from by the cell's hash."""
    table: dict


@dataclass
class Area:
    id: str
    tileset: str
    sw: int
    sh: int
    legend: dict
    rows: dict = field(default_factory=dict)
    stamps: list = field(default_factory=list)
    things: list = field(default_factory=list)
    notes: dict = field(default_factory=dict)  # free data for the game: music, name, dark...

    def screen(self, sx: int, sy: int, rows: list[str]) -> None:
        if not (0 <= sx < self.sw and 0 <= sy < self.sh):
            raise ValueError(f"{self.id}: screen {sx},{sy} is outside {self.sw}x{self.sh}")
        if len(rows) != SCREEN_H or any(len(r) != SCREEN_W for r in rows):
            bad = [(i, len(r)) for i, r in enumerate(rows) if len(r) != SCREEN_W]
            raise ValueError(f"{self.id} screen {sx},{sy}: needs {SCREEN_H} rows of {SCREEN_W}, rows {len(rows)}, bad {bad}")
        if (sx, sy) in self.rows:
            raise ValueError(f"{self.id}: screen {sx},{sy} twice")
        self.rows[(sx, sy)] = list(rows)

    def stamp(self, name: str, cx: int, cy: int) -> None:
        self.stamps.append((name, cx, cy))

    def thing(self, kind: str, cx: int, cy: int, **props) -> dict:
        t = {"kind": kind, "cx": cx, "cy": cy, **props}
        self.things.append(t)
        return t

    # ------------------------------------------------------------------ compiling
    def grid(self) -> list[str]:
        """The whole area as one grid of characters, screens side by side (rows of screens missing are ocean/empty)."""
        gw, gh = self.sw * SCREEN_W, self.sh * SCREEN_H
        out = []
        for gy in range(gh):
            row = ""
            for gx in range(gw):
                sx, sy = gx // SCREEN_W, gy // SCREEN_H
                scr = self.rows.get((sx, sy))
                row += scr[gy % SCREEN_H][gx % SCREEN_W] if scr else self.legend.get("_empty_char", " ")
            out.append(row)
        return out

    def names(self, metas: dict, lenient: bool = False) -> list[list[str]]:
        grid = self.grid()
        fams, variants, fallback = {}, {}, {}
        for ch, spec in self.legend.items():
            if len(ch) > 1 and ch.startswith("_"):  # (a key of the legend that is not a character)
                continue
            if isinstance(spec, Family):
                fams[ch] = spec.name
                variants[spec.name] = list(spec.variants) or [n for n in (f"{spec.name}_a", f"{spec.name}_b") if n in metas]
                if not variants[spec.name]:
                    raise ValueError(f"{self.id}: family {spec.name} has no plain pieces {spec.name}_a/_b in the tileset")
            elif isinstance(spec, (Connected, Member)):
                continue
            elif isinstance(spec, str):
                fallback[ch] = [spec]
            else:
                fallback[ch] = list(spec)
        used = {c for r in grid for c in r}
        unknown = used - set(self.legend) - {" "}
        if unknown:
            raise ValueError(f"{self.id}: characters with no legend: {sorted(unknown)}")
        members = {ch: spec for ch, spec in self.legend.items() if isinstance(spec, Member)}
        if members:
            grid = ["".join(members[c].of if c in members else c for c in row) for row in grid]
        conns = {ch: spec.table for ch, spec in self.legend.items() if isinstance(spec, Connected)}
        for ch in conns:
            fallback[ch] = ["_pending"]
        joins = {ch: spec.joins for ch, spec in self.legend.items() if isinstance(spec, Family) and spec.joins}
        warnings = []
        names = g.autotile(grid, fams, variants, fallback, seed=sum(map(ord, self.id)), joins=joins,
                           warn=lambda x, y, ch, why: warnings.append(f"{self.id} {x},{y} {ch!r}: {why}"))
        self.warnings = warnings
        if members:
            raw = self.grid()
            for y, row in enumerate(raw):
                for x, c in enumerate(row):
                    if c in members:
                        t = members[c].tiles
                        names[y][x] = t if isinstance(t, str) else t[((x * 73856093) ^ (y * 19349663)) % len(t)]
        for ch, table in conns.items():
            for y, row in enumerate(grid):
                for x, c in enumerate(row):
                    if c != ch:
                        continue
                    mask = ((y > 0 and grid[y - 1][x] == ch) * 1 + (x < len(row) - 1 and grid[y][x + 1] == ch) * 2 +
                            (y < len(grid) - 1 and grid[y + 1][x] == ch) * 4 + (x > 0 and grid[y][x - 1] == ch) * 8)
                    pick = table.get(mask)
                    if pick is None:
                        raise ValueError(f"{self.id}: no piece for {ch!r} at {x},{y} with neighbours {mask}")
                    names[y][x] = pick if isinstance(pick, str) else pick[((x * 73856093) ^ (y * 19349663)) % len(pick)]
        for name, cx, cy in self.stamps:
            st = STAMPS.get(name)
            if st is None:
                raise ValueError(f"{self.id}: no stamp {name!r}")
            if not lenient:
                pass
            for dy, row in enumerate(st):
                for dx, n in enumerate(row):
                    if n is not None:
                        if not (0 <= cy + dy < len(names) and 0 <= cx + dx < len(names[0])):
                            raise ValueError(f"{self.id}: stamp {name} at {cx},{cy} leaves the area")
                        names[cy + dy][cx + dx] = n
        for y, row in enumerate(names):
            for x, n in enumerate(row):
                if n not in metas:
                    if not lenient:
                        raise ValueError(f"{self.id}: cell {x},{y} wants metatile {n!r}, which no art module defines")
                    self.missing = getattr(self, "missing", set()) | {n}
        return names


STAMPS: dict[str, list[list[str | None]]] = {}


def block(prefix: str, rows: int, cols: int) -> list[list[str]]:
    """A stamp of `rows` x `cols` metatiles named <prefix>_<r>_<c> (how the artists name big pieces)."""
    return [[f"{prefix}_{r}_{c}" for c in range(cols)] for r in range(rows)]


def compile_area(area: Area, sets: dict, tiles_lua: dict) -> dict:
    """Writes the area's tilemaps (assets/<ID>_G, <ID>_F) and returns its Lua data."""
    ts = sets[area.tileset]
    metas = g.ART.metas[area.tileset]
    names = area.names(metas)
    gw, gh = area.sw * SCREEN_W, area.sh * SCREEN_H
    ground, front = g.Layer(gw * 2, gh * 2), g.Layer(gw * 2, gh * 2)
    ids = tiles_lua["sets"][area.tileset]["id"]
    cells = []
    for y in range(gh):
        for x in range(gw):
            n = names[y][x]
            ground.put_meta(x, y, ts["ground"].meta[n])
            if metas[n].front is not None:
                front.put_meta(x, y, ts["front"].meta[n])
            cells.append(ids[n])
    g.write_tilemap(f"{area.id.upper()}_G", ts["ground"], ground)
    g.write_tilemap(f"{area.id.upper()}_F", ts["front"], front)
    # the tiles each screen needs (what a console would hold in video memory for it)
    per_screen = {}
    for sy in range(area.sh):
        for sx in range(area.sw):
            seen = set()
            for lay in (ground, front):
                for ty in range(sy * 18, sy * 18 + 18):
                    for tx in range(sx * 30, sx * 30 + 30):
                        e = lay.entries[ty * lay.w + tx] & 0x3FF
                        if e:
                            seen.add((id(lay), e))
            per_screen[f"{sx},{sy}"] = len(seen)
    return {"tileset": area.tileset, "sw": area.sw, "sh": area.sh, "gw": gw, "gh": gh, "cells": cells,
            "things": area.things, "notes": area.notes, "screen_tiles": per_screen,
            "ground": f"{area.id.upper()}_G", "front": f"{area.id.upper()}_F"}


class Canvas:
    """A screen drawn with brush strokes instead of typed characters: `Canvas("g")` is a field of grass, and the strokes
    paint over it. Coordinates are cells of the screen (x 0-14, y 0-8). `scatter` strews a character over the cells of
    another (flowers over grass) by a fixed hash, so the same canvas is always the same screen."""

    def __init__(self, base: str = "g", w: int = SCREEN_W, h: int = SCREEN_H, seed: int = 1):
        self.w, self.h, self.seed = w, h, seed
        self.c = [[base] * w for _ in range(h)]

    def put(self, x: int, y: int, ch: str) -> "Canvas":
        if 0 <= x < self.w and 0 <= y < self.h:
            self.c[y][x] = ch
        return self

    def rect(self, x0: int, y0: int, x1: int, y1: int, ch: str) -> "Canvas":
        for y in range(y0, y1 + 1):
            for x in range(x0, x1 + 1):
                self.put(x, y, ch)
        return self

    def hline(self, y: int, x0: int, x1: int, ch: str) -> "Canvas":
        return self.rect(x0, y, x1, y, ch)

    def vline(self, x: int, y0: int, y1: int, ch: str) -> "Canvas":
        return self.rect(x, y0, x, y1, ch)

    def frame(self, x0: int, y0: int, x1: int, y1: int, ch: str) -> "Canvas":
        self.hline(y0, x0, x1, ch).hline(y1, x0, x1, ch).vline(x0, y0, y1, ch).vline(x1, y0, y1, ch)
        return self

    def scatter(self, ch: str, n: int, over: str = "g", salt: int = 0) -> "Canvas":
        """n cells that are `over` become `ch`, chosen by a fixed hash."""
        cells = [(x, y) for y in range(self.h) for x in range(self.w) if self.c[y][x] == over]
        cells.sort(key=lambda p: ((p[0] * 73856093) ^ (p[1] * 19349663) ^ ((self.seed + salt) * 83492791)) & 0xFFFFFF)
        for x, y in cells[:n]:
            self.c[y][x] = ch
        return self

    def rows(self) -> list[str]:
        return ["".join(r) for r in self.c]
