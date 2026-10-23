"""Builds everything Botín draws and loads: the art modules register their pictures (gen/art_*.py), gbakit writes palettes, sprite sheets and scenery
tile maps, levelkit compiles the levels of gen/levels_design.py into tile maps and data/levels.lua. Run from anywhere: python3 gen/build.py"""
from __future__ import annotations

import importlib
import sys
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent))
import contract as C  # noqa: E402
import gbakit as g  # noqa: E402
from gbakit import ART, DATA, Layer, Tileset, crop, lua_table, write_tilemap  # noqa: E402

ART_MODULES = ["art_hero", "art_enemies", "art_items", "art_selva", "art_cristal", "art_galeon", "art_fragua"]


def main() -> None:
    import artload
    artload.load()
    import bgcomp
    for b in C.BIOMES:
        bgcomp.compose(b, g.HERE / "art")
    banks = g.build_common()
    import levels_design as L  # noqa: E402
    import levelkit as K  # noqa: E402

    data = [K.compile_level(lv, banks) for lv in L.LEVELS]
    (DATA / "levels.lua").write_text("-- made by gen/build.py from gen/levels_design.py\nreturn " + lua_table(data) + "\n")
    (DATA / "worlds.lua").write_text("-- made by gen/build.py: which tile map holds which biome\nreturn " + lua_table({b: f"{b.upper()}_BG" for b in C.BIOMES}) + "\n")
    print(f"{len(data)} levels, {len(ART.sheets)} sheets, {len(ART.sceneries)} sceneries")


if __name__ == "__main__":
    main()
