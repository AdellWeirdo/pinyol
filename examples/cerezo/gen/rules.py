"""What the game does with each metatile, owned by the game and not by the artists: flags changed or added after the
art modules are loaded, and aliases (the same picture with other rules: a bush that hides a hole, a cabbage that hides a
dig spot). build.py calls `apply()` right after the modules load.

A flag is a string: "solid" (blocks), "water" (deep: blocks), "shallow", "pit" (falls), "cut" (the pala cuts it, `becomes=NAME`),
"dig" (the pala digs it, `becomes=NAME`), "door", "chest", "sign", "stairs", "switch", "switch_floor", "burn" (the lantern burns
it), "light" (a lit torch), "lock", "spikes".
"""
from __future__ import annotations

import sys
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent))
import gbart as g  # noqa: E402

# tileset -> name -> the flags it has in the game
OVERRIDES: dict[str, dict[str, tuple]] = {
    "overworld": {
        "cabbage_big": ("solid", "cut", "becomes=dirt_loose"),  # the garden's secret: cut it, and the soil under it is loose
    },
}

# tileset -> new name -> (name of the picture it copies, its flags)
ALIASES: dict[str, dict[str, tuple[str, tuple]]] = {
    "overworld": {
        "bush_secret": ("bush", ("solid", "cut", "becomes=hole_dug")),   # a bush over a hole that leads under the ground
        "bush_dig": ("bush", ("solid", "cut", "becomes=dirt_loose")),    # a bush that hides a dig spot
        "rock_secret": ("rock_cracked", ("solid", "secret")),
    },
}


def apply() -> None:
    for tileset, table in OVERRIDES.items():
        metas = g.ART.metas.get(tileset, {})
        for name, flags in table.items():
            if name in metas:
                metas[name].flags = tuple(flags)
    for tileset, table in ALIASES.items():
        metas = g.ART.metas.get(tileset, {})
        for new, (src, flags) in table.items():
            if src in metas and new not in metas:
                m = metas[src]
                metas[new] = g.Metatile(new, m.ground, m.front, tuple(flags), m.bank, m.front_bank)
