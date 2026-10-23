"""Checks the art against the contract: every sheet, frame, metatile, scenery and bank the game uses is there, with the right sizes.

    python3 gen/check_art.py        # imports the art modules that exist and lists what is missing
"""
from __future__ import annotations

import importlib
import sys
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent))
import contract as C  # noqa: E402
import gbakit as g  # noqa: E402

MODULES = ["art_hero", "art_enemies", "art_items", "art_selva", "art_cristal", "art_galeon", "art_fragua"]


def main() -> int:
    import artload
    loaded = artload.load()
    bad = 0
    for sid, (w, h, frames) in C.SHEETS.items():
        sh = g.ART.sheets.get(sid)
        if not sh:
            print(f"missing sheet {sid}")
            bad += 1
            continue
        have = {n for n, _ in sh.frames}
        miss = [f for f in frames if f not in have]
        if (sh.w, sh.h) != (w, h):
            print(f"sheet {sid}: {sh.w}x{sh.h}, wanted {w}x{h}")
            bad += 1
        if miss:
            print(f"sheet {sid}: {len(miss)} frames missing, first: {miss[:8]}")
            bad += len(miss)
    for b in C.BIOMES:
        metas = g.ART.metas.get(b)
        if not metas:
            print(f"missing biome {b}")
            bad += 1
            continue
        miss = [n for n in C.metas_of(b) if n not in metas]
        if miss:
            print(f"biome {b}: {len(miss)} metatiles missing, first: {miss[:10]}")
            bad += len(miss)
        for sc in C.SCENERY[b]:
            if sc not in g.ART.sceneries:
                print(f"biome {b}: scenery {sc} missing")
                bad += 1
    for name, (w, h) in C.TITULO_SCENERY.items():
        if name not in g.ART.sceneries:
            print(f"scenery {name} missing")
            bad += 1
    obj = g.ART.palettes.get("obj", {})
    for b in C.OBJ_BANKS:
        if b not in obj:
            print(f"obj bank {b} missing")
            bad += 1
    print(f"loaded {loaded}; {bad} problems")
    return 1 if bad else 0


if __name__ == "__main__":
    sys.exit(main())
