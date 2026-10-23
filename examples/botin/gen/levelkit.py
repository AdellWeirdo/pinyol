"""levelkit: how a level of Botín is built and compiled. A level is a grid of characters (cells of 16x16) drawn with brush strokes, plus a list of things (enemies, coins,
the vortex, the frog...). compile() turns the grid into the tile maps the engine scrolls (ground, and the layer in front of the hero) using the biome's metatiles, and into the
Lua data the game reads (data/levels.lua).

Characters of a level:
  .  air            ,  the wall behind (a back tile: cave walls, ruins)        #  ground (the 16 pieces by neighbours)       =  a one-way platform (l, m, r, s by neighbours)
  b  brown block    B  blue block   H  hard block    F  fire block (fragua)   T  tiki block (selva: hard)        J  a box with a jewel   K  a box with coins
  ^  spikes up      v  spikes down  m  mud (selva)   s  a spring (selva)     L  lava (fragua)                   ~  water (galeon: set by `water_row` instead of drawn)
  a-h  decoration pieces deco_a..deco_h (behind the hero)       1-8  front pieces front_a..front_h (over the hero)
  Animated cells (the game changes their tiles every few ticks):  L lava (fragua)   W waterfall (selva)   D drip (cristal)   Y bubble vent (galeon)   Z seaweed (galeon)
  G gear (fragua)   S steam (fragua)   l r u  a current pushing left / right / up (galeon: the hero is carried)
"""
from __future__ import annotations

import sys
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent))
import gbakit as g  # noqa: E402
from gbakit import ART, Layer, Tileset, write_tilemap  # noqa: E402

T = 16
SOLID_FOR_MASK = set("#")
# animated cells: char -> (frame names for a cell with nothing of its own kind above it, frame names otherwise)
def _fr(prefix, n=4): return [f"{prefix}_{i}" for i in range(n)]
ANIM = {
    "L": (_fr("lava_surface"), _fr("lava_fill")), "W": (_fr("waterfall_top"), _fr("waterfall")), "D": (_fr("drip"), _fr("drip")),
    "Y": (_fr("vent"), _fr("vent")), "Z": (["seaweed_a", "seaweed_b", "seaweed_c", "seaweed_b"], ["seaweed_a", "seaweed_b", "seaweed_c", "seaweed_b"]),
    "G": (_fr("gear"), _fr("gear")), "S": (_fr("steam"), _fr("steam")), "l": (_fr("current_l"), _fr("current_l")),
    "r": (_fr("current_r"), _fr("current_r")), "u": (_fr("current_u"), _fr("current_u")),
}


class Level:
    def __init__(self, n: int, biome: str, w: int, h: int, name: str, **notes):
        self.n, self.biome, self.w, self.h, self.name, self.notes = n, biome, w, h, name, notes
        self.g = [["."] * w for _ in range(h)]
        self.things: list[dict] = []

    # --- brush strokes
    def put(self, x: int, y: int, c: str) -> "Level":
        if 0 <= x < self.w and 0 <= y < self.h:
            self.g[y][x] = c
        return self

    def rect(self, x0: int, y0: int, x1: int, y1: int, c: str) -> "Level":
        for y in range(y0, y1 + 1):
            for x in range(x0, x1 + 1):
                self.put(x, y, c)
        return self

    def h_(self, y: int, x0: int, x1: int, c: str) -> "Level":
        return self.rect(x0, y, x1, y, c)

    def v_(self, x: int, y0: int, y1: int, c: str) -> "Level":
        return self.rect(x, y0, x, y1, c)

    def row(self, y: int, text: str, x0: int = 0) -> "Level":
        for i, c in enumerate(text):
            if c != " ":
                self.put(x0 + i, y, c)
        return self

    def thing(self, name: str, x: float, y: float, **props) -> "Level":
        self.things.append({"kind": name, "x": x, "y": y, **props})
        return self

    def rows(self) -> list[str]:
        return ["".join(r) for r in self.g]


def hash2(x: int, y: int, salt: int = 0) -> int:
    return ((x * 73856093) ^ (y * 19349663) ^ (salt * 83492791)) & 0xFFFF


def cell_names(lv: Level, metas: dict) -> tuple[list[list[str | None]], list[list[str | None]]]:
    """(ground layer names, front layer names) of every cell: a metatile name or None."""
    W, H = lv.w, lv.h
    gr = lv.g

    def at(x, y):
        return "#" if not (0 <= x < W and 0 <= y < H) else gr[y][x]

    def has(name):
        return name in metas

    ground: list[list[str | None]] = [[None] * W for _ in range(H)]
    front: list[list[str | None]] = [[None] * W for _ in range(H)]
    for y in range(H):
        for x in range(W):
            c = gr[y][x]
            nm = None
            if c == "#":
                m = (at(x, y - 1) != "#") * 1 + (at(x + 1, y) != "#") * 2 + (at(x, y + 1) != "#") * 4 + (at(x - 1, y) != "#") * 8
                if m == 0:
                    for dx, dy, nme in ((1, -1, "ground_in_ne"), (-1, -1, "ground_in_nw"), (1, 1, "ground_in_se"), (-1, 1, "ground_in_sw")):
                        if at(x + dx, y + dy) != "#" and has(nme):
                            nm = nme
                            break
                    if nm is None:
                        nm = f"ground_alt{hash2(x, y) % 4}" if hash2(x, y) % 3 == 0 else "ground_m0"
                elif m == 1 and hash2(x, y) % 4 == 0:
                    nm = ("ground_m1_b", "ground_m1_c")[hash2(x, y, 1) % 2]
                else:
                    nm = f"ground_m{m}"
            elif c == "=":
                l, r = at(x - 1, y) == "=", at(x + 1, y) == "="
                nm = "plat_m" if l and r else "plat_l" if r else "plat_r" if l else "plat_s"
                if lv.biome == "selva" and has("leaf_plat_m") and lv.notes.get("leaf_plats", True):
                    nm = {"plat_m": "leaf_plat_m", "plat_l": "leaf_plat_l", "plat_r": "leaf_plat_r", "plat_s": "leaf_plat_m"}[nm]
                if lv.biome == "cristal" and has("ice_plat_m"):
                    nm = {"plat_m": "ice_plat_m", "plat_l": "ice_plat_l", "plat_r": "ice_plat_r", "plat_s": "ice_plat_m"}[nm]
                if lv.biome == "fragua" and has("chain_plat_m"):
                    nm = {"plat_m": "chain_plat_m", "plat_l": "chain_plat_l", "plat_r": "chain_plat_r", "plat_s": "chain_plat_m"}[nm]
            elif c in "bBHFKJ":
                nm = {"b": "block_brown", "B": "block_blue", "H": "block_hard", "F": "block_fire", "K": "box_coin", "J": "box_jewel"}[c]
                if c == "b" and lv.biome == "galeon" and has("barrel") and lv.notes.get("barrels", False):
                    nm = "barrel"
            elif c == "T":
                nm = "tiki_block" if has("tiki_block") else "block_hard"
            elif c == "^":
                nm = "spikes_up"
            elif c == "v":
                nm = "spikes_down"
            elif c == "m":
                nm = "mud_top" if at(x, y - 1) == "." else "mud_fill"
            elif c == "s":
                nm = "spring_a"
            elif c in ANIM:
                nm = ANIM[c][0 if at(x, y - 1) != c else 1][0]
            elif c == ",":
                nm = f"back_{'abcd'[hash2(x, y) % 4]}"
            elif c in "abcdefgh":
                nm = f"deco_{c}"
            elif c in "12345678":
                front[y][x] = f"front_{'abcdefgh'[int(c) - 1]}"
            if nm is not None and nm not in metas:
                raise ValueError(f"level {lv.n}: cell {x},{y} {c!r} wants metatile {nm!r}, which the {lv.biome} art does not define")
            ground[y][x] = nm
    return ground, front


def compile_level(lv: Level, banks: dict) -> dict:
    """Writes assets/L<n>_FG (the ground layer, with the frames of the animated cells added to its tile set) and L<n>_FRONT (over the hero);
    returns the Lua data of the level."""
    metas = ART.metas[lv.biome]
    ground, front = cell_names(lv, metas)
    W, H = lv.w, lv.h
    bk = banks[lv.biome]
    ts, layer = Tileset(), Layer(W * 2, H * 2)
    for y in range(H):
        for x in range(W):
            nm = ground[y][x]
            if nm is not None:
                m = metas[nm]
                layer.put_meta(x, y, ts.meta(m.ground, bk[m.bank]))
    anim = []  # per animated character: its cells with the four-entry set of each frame, so the game swaps them with mset
    for ch, (top_frames, body_frames) in ANIM.items():
        cells = []
        for y in range(H):
            for x in range(W):
                if lv.g[y][x] != ch:
                    continue
                names = top_frames if (y == 0 or lv.g[y - 1][x] != ch) else body_frames
                cells.append([x, y, [ts.meta(metas[n].ground, bk[metas[n].bank]) for n in names]])
        if cells:
            anim.append({"ch": ch, "cells": cells})
    write_tilemap(f"L{lv.n}_FG", ts, layer, lv.biome.upper())
    ts, layer = Tileset(), Layer(W * 2, H * 2)
    for y in range(H):
        for x in range(W):
            nm = front[y][x]
            if nm is not None and metas[nm].front is not None:
                m = metas[nm]
                layer.put_meta(x, y, ts.meta(m.front, bk[m.front_bank]))
    write_tilemap(f"L{lv.n}_FRONT", ts, layer, lv.biome.upper())
    has_front = any(nm is not None and metas[nm].front is not None for row in front for nm in row)
    return {"n": lv.n, "biome": lv.biome, "name": lv.name, "w": W, "h": H, "rows": lv.rows(), "things": lv.things, "notes": lv.notes,
            "fg": f"L{lv.n}_FG", "front": f"L{lv.n}_FRONT", "has_front": has_front, "anim": anim}
