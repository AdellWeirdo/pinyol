"""Draws the areas of Cerezo as pictures to look at: every screen on its own and the whole area, in DMG and POCKET tones.

    python3 gen/preview_maps.py [--stubs]       # art/map_<area>_*.png
"""
from __future__ import annotations

import sys
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent))
import build  # noqa: E402
import gbart as g  # noqa: E402
import palettes  # noqa: E402
import rules  # noqa: E402


def main() -> None:
    build.load_modules()
    rules.apply()
    if "--stubs" in sys.argv:
        build.stub_missing()
    import importlib
    for m in build.MAPS:
        mod = importlib.import_module(m)
        for a in mod.AREAS:
            metas = g.ART.metas[a.tileset]
            names = a.names(metas)
            for label, tones in (("dmg", palettes.DMG), ("pocket", palettes.POCKET)):
                g.scene_image(names, metas, tones, scale=2).save(g.HERE / "art" / f"map_{a.id}_{label}.png")
            for (sx, sy) in a.rows:
                sub = [row[sx * 15:(sx + 1) * 15] for row in names[sy * 9:(sy + 1) * 9]]
                g.scene_image(sub, metas, palettes.DMG, scale=3).save(g.HERE / "art" / f"map_{a.id}_{sx}{sy}.png")
            print(a.id, len(names[0]), "x", len(names), "cells")


if __name__ == "__main__":
    main()
