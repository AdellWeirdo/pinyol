"""Builds Cerezo's art: every module of gen/ that defines pictures, into assets/ and the Lua data the game reads.

    python3 examples/cerezo/gen/build.py            # everything
    python3 examples/cerezo/gen/build.py --sheets   # contact sheets in art/ to look at (DMG and POCKET tones)
    python3 examples/cerezo/gen/build.py --only chars --sheets-only   # just your module(s), sheets only (artists)

A module of gen/ draws with `gbart.ART` (sheets of sprite frames, metatiles of a tileset) and is listed in MODULES.
This file turns what they registered into: assets/<SHEET>.idx, assets/<TILESET>.tiles/.map (the maps themselves come
from world.py), data/frames.lua (frame names to numbers), data/tiles.lua (each metatile's map entries and flags)
and data/palettes.lua.
"""
from __future__ import annotations

import importlib
import sys
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent))
import gbart as g  # noqa: E402
import palettes  # noqa: E402

MAPS = ["maps_overworld", "maps_interiors", "maps_dungeon"]  # the content modules that define areas (each makes `AREAS`, a list of world.Area)
MODULES = ["chars", "npcs", "monsters", "ui_fx", "tiles_terrain", "tiles_nature", "tiles_village", "tiles_interior", "tiles_dungeon", "title_art"]
DATA = g.HERE / "data"


def load_modules(only: list[str] | None = None) -> list[str]:
    loaded = []
    if only is None and "--dev" not in sys.argv:
        pass
    if "--dev" in sys.argv:  # placeholder art with the real names, to write the game before the art is done
        import dev_art
        dev_art.register()
        return ["dev_art"]
    for m in MODULES:
        if only is not None and m not in only:
            continue
        if (Path(__file__).resolve().parent / f"{m}.py").exists():
            try:
                importlib.import_module(m)
                loaded.append(m)
            except Exception as e:  # an artist's module in the middle of an edit: --lenient goes on without it
                if "--lenient" not in sys.argv:
                    raise
                print(f"skipped {m}: {type(e).__name__}: {e}")
                # what it had already registered stays: the rest of the build can still run
    return loaded


def lua_value(v, indent: int = 0) -> str:
    pad = "  " * indent
    if isinstance(v, dict):
        if not v:
            return "{}"
        items = [f"{pad}  {k if str(k).isidentifier() else '[' + repr(k) + ']'} = {lua_value(x, indent + 1)}" for k, x in v.items()]
        return "{\n" + ",\n".join(items) + f"\n{pad}}}"
    if isinstance(v, (list, tuple)):
        if all(isinstance(x, (int, float, str, bool)) for x in v):
            return "{" + ", ".join(lua_value(x) for x in v) + "}"
        return "{\n" + ",\n".join(f"{pad}  {lua_value(x, indent + 1)}" for x in v) + f"\n{pad}}}"
    if isinstance(v, bool):
        return "true" if v else "false"
    if isinstance(v, str):
        return '"' + v.replace("\\", "\\\\").replace('"', '\\"') + '"'
    return str(v)


def write_lua(name: str, value, header: str) -> None:
    DATA.mkdir(exist_ok=True)
    (DATA / f"{name}.lua").write_text(f"-- {header}\n-- made by gen/build.py: do not edit, change the art and build again\nreturn {lua_value(value)}\n")


def build_sheets() -> dict:
    frames = {}
    for sid, sh in g.ART.sheets.items():
        g.write_sheet(sid, [p for _, p in sh.frames], "OBJ", sh.ms)
        d = {"w": sh.w, "h": sh.h, "n": len(sh.frames), "bank": sh.bank}
        for i, (name, _) in enumerate(sh.frames):
            d[name] = i
        if sh.banks:
            d["banks"] = dict(sh.banks)
        frames[sid] = d
    return frames


def build_tilesets() -> dict:
    """Each tileset's ground and front tiles. Returns {tileset: {"ground": Tileset, "front": Tileset, ...}} for the maps."""
    out = {}
    lua = {}
    for tname, metas in g.ART.metas.items():
        ground, front = g.Tileset(), g.Tileset()
        entry = {"ground": {}, "front": {}, "flags": {}, "id": {}}
        for i, (name, m) in enumerate(metas.items()):
            entry["ground"][name] = ground.add(name, m.ground, m.bank)
            if m.front is not None:
                entry["front"][name] = front.add(name, m.front, m.front_bank)
            entry["flags"][name] = list(m.flags)
            entry["id"][name] = i
        for name, (p, bank) in g.ART.tiles8.get(tname, {}).items():
            entry.setdefault("tile8", {})[name] = ground.add_tile(name, p, bank)
        entry["tiles"], entry["front_tiles"] = len(ground.tiles), len(front.tiles)
        out[tname] = {"ground": ground, "front": front}
        lua[tname] = entry
    anims = {k: v for k, v in g.ART.anims.items()}
    return out, {"sets": lua, "anim": anims}


def tile_pixels(sets: dict) -> dict:
    """Every tile of every tileset as 64 characters (0 see-through, 1 to 4 the tones): for the explainer, which draws any
    tile of the screen magnified."""
    out = {}
    for name, s in sets.items():
        out[name] = {"ground": ["".join(str(v) for v in t) for t in s["ground"].tiles],
                     "front": ["".join(str(v) for v in t) for t in s["front"].tiles]}
    return out


def build_ui(sets: dict) -> None:
    """The status bar and the dialogue window are a layer of tiles of their own (the Game Boy's window): UI.tiles has
    the ui tileset's tiles and UI.map is empty, 30x20 tiles, for the game to fill with mset."""
    if "ui" not in sets:
        return
    g.write_tilemap("UI", sets["ui"]["ground"], g.Layer(30, 20))


def stub_missing() -> None:
    """For laying out maps before all the art exists (--stubs): every metatile a map wants and no module defines gets a
    crosshatched placeholder, so the screens can be seen and tuned. It says which ones are missing."""
    import world
    missing = {}
    for m in MAPS:
        if (Path(__file__).resolve().parent / f"{m}.py").exists():
            mod = importlib.import_module(m)
            for a in mod.AREAS:
                a.missing = set()
                a.names(g.ART.metas.get(a.tileset, {}), lenient=True)
                if a.missing:
                    missing[a.tileset] = missing.get(a.tileset, set()) | a.missing
    for tileset, names in missing.items():
        hatch = g.pic(["3.3.3.3.3.3.3.3."[i % 2:] [:16] if False else ("3" + "0" * 15 if (i % 4 == 0) else "0" * 16) for i in range(16)], 16, 16)
        for n in sorted(names):
            g.ART.meta(tileset, n, g.pic([("32" * 8 if i % 2 == 0 else "23" * 8) for i in range(16)], 16, 16), flags=("solid",), bank=0)
        print(f"stubbed in {tileset}: {' '.join(sorted(names))}")


def build_areas(sets: dict, tiles_lua: dict) -> dict:
    import world
    out = {}
    for m in MAPS:
        if (Path(__file__).resolve().parent / f"{m}.py").exists():
            mod = importlib.import_module(m)
            for a in mod.AREAS:
                out[a.id] = world.compile_area(a, sets, tiles_lua)
    return out


def main() -> None:
    only = None
    if "--only" in sys.argv:  # an artist builds just their own module(s): --only chars,npcs
        only = sys.argv[sys.argv.index("--only") + 1].split(",")
    loaded = load_modules(only)
    if only is None:
        import rules
        rules.apply()
        if "--stubs" in sys.argv:
            stub_missing()
    if "--sheets-only" in sys.argv:  # pictures to look at, and nothing written into assets/ or data/
        sheets(only)
        print(f"modules {loaded}: sheets in art/")
        return
    frames = build_sheets()
    sets, tiles_lua = build_tilesets()
    areas = build_areas(sets, tiles_lua)
    build_ui(sets)
    g.write_palette("WORLD", [palettes.DMG] * 8)
    g.write_palette("OBJ", [palettes.DMG] * 8)
    write_lua("frames", frames, "sprite sheets: frame names to numbers")
    write_lua("world", {"areas": areas}, "the areas: cells, things, notes")
    write_lua("tilepix", tile_pixels(sets), "the pixels of every tile (for the explainer)")
    write_lua("tiles", tiles_lua, "metatiles: the map entries of each, and what the game does with it")
    write_lua("palettes", {"modes": [{"name": m["name"], "bg": [[r << 16 | gg << 8 | b for r, gg, b in bank] for bank in m["bg"]],
                                      "obj": [[r << 16 | gg << 8 | b for r, gg, b in bank] for bank in m["obj"]]}
                                     for m in palettes.modes()]}, "the palettes the player can choose")
    n_frames = sum(len(s.frames) for s in g.ART.sheets.values())
    n_meta = sum(len(m) for m in g.ART.metas.values())
    print(f"modules {loaded}: {len(g.ART.sheets)} sheets, {n_frames} frames, {n_meta} metatiles in {len(g.ART.metas)} tilesets")
    for t, s in sets.items():
        print(f"  {t}: {len(s['ground'].tiles)} ground tiles, {len(s['front'].tiles)} front tiles")
    if "--sheets" in sys.argv:
        sheets(only)


def sheets(only: list[str] | None = None) -> None:
    from PIL import Image
    out = g.HERE / "art"
    out.mkdir(exist_ok=True)
    for sid, sh in g.ART.sheets.items():
        pics = [p for _, p in sh.frames]
        cols = max(1, min(len(pics), 480 // (sh.w * 6 + 4)))
        for label, tones in (("dmg", palettes.DMG), ("pocket", palettes.POCKET)):
            g.contact_sheet(pics, cols=cols, scale=6, tones=tones).save(out / f"sheet_{sid.lower()}_{label}.png")
    for tname, metas in g.ART.metas.items():
        pics = [m.ground for m in metas.values()]
        tag = ("_" + "_".join(only)) if only else ""
        for label, tones in (("dmg", palettes.DMG), ("pocket", palettes.POCKET)):
            g.contact_sheet(pics, cols=10, scale=4, tones=tones).save(out / f"tiles_{tname}{tag}_{label}.png")
        fronts = [m.front for m in metas.values() if m.front is not None]
        if fronts:
            g.contact_sheet(fronts, cols=10, scale=4, tones=palettes.POCKET).save(out / f"tiles_{tname}{tag}_front_pocket.png")


if __name__ == "__main__":
    main()
