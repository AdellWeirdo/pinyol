# /// script
# requires-python = ">=3.10"
# dependencies = ["pillow>=10"]
# ///
"""A level made in LDtk (ldtk.io), from its "Super simple export" folder (one per level, with the level's composite
PNG, a CSV per IntGrid layer and data.json), into a pinyol@2 game:

    uv run tools/ldtk2asset.py world/simplified/Level_0 games/mygame LEVEL0 [--tiles] [--palette WORLD]

The picture becomes assets/LEVEL0 (a full-colour background to show with bg(n, {image = "LEVEL0"}) or img; with
--tiles, indexed 8x8 tiles and a map for a PPU layer, bg(n, {map = "LEVEL0"})), and the rest goes to level0.lua
(require("level0")):
    w, h                      the level in pixels
    grids.<name> = {size, w, h, data}     each IntGrid layer: its cell size, size in cells and values row by row (0: empty)
    entities = {{name, x, y, w, h, fields = {...}}, ...}   every entity, in pixels, with its fields
    neighbours = {{dir, id}}  the levels next to this one
    bg                        the level's background colour
lib/autotile can draw a grid, grid() can walk it, lib/rooms can put the levels together.
"""
from __future__ import annotations

import argparse
import json
import re
import sys
from pathlib import Path

from PIL import Image

sys.path.insert(0, str(Path(__file__).resolve().parent))
import png2asset  # noqa: E402


def lua(v, indent: int = 0) -> str:
    pad = "  " * indent
    if isinstance(v, bool):
        return "true" if v else "false"
    if isinstance(v, (int, float)):
        return repr(v)
    if v is None:
        return "nil"
    if isinstance(v, str):
        return '"' + v.replace("\\", "\\\\").replace('"', '\\"').replace("\n", "\\n") + '"'
    if isinstance(v, list):
        return "{" + ", ".join(lua(x, indent) for x in v) + "}"
    if isinstance(v, dict):
        items = []
        for k, x in v.items():
            key = k if re.fullmatch(r"[A-Za-z_][A-Za-z0-9_]*", str(k)) else f'["{k}"]'
            items.append(f"{pad}  {key} = {lua(x, indent + 1)}")
        return "{\n" + ",\n".join(items) + f"\n{pad}}}"
    return lua(str(v), indent)


def main() -> None:
    p = argparse.ArgumentParser(description=__doc__.split("\n\n")[0])
    p.add_argument("level", type=Path, help="the level's folder in LDtk's simplified export")
    p.add_argument("game", type=Path)
    p.add_argument("id", help="asset ID for the level's picture")
    p.add_argument("--tiles", action="store_true", help="indexed 8x8 tiles and a map (a PPU layer) instead of a full-colour picture")
    p.add_argument("--palette", help="with --tiles: share assets/PALETTE.pal")
    a = p.parse_args()
    if not re.fullmatch(r"[A-Za-z0-9_]+", a.id):
        p.error("IDs: letters, digits and _ only")
    data = json.loads((a.level / "data.json").read_text(encoding="utf-8"))
    assets = a.game / "assets"
    assets.mkdir(parents=True, exist_ok=True)
    composite = a.level / "_composite.png"
    if composite.exists():
        img = Image.open(composite).convert("RGBA")
        if a.tiles:
            if img.width % 8 or img.height % 8:
                p.error(f"{img.width}x{img.height}: --tiles needs a size in whole 8x8 tiles")
            pal_path = assets / f"{a.palette or a.id}.pal"
            pal = png2asset.load_palette(pal_path)
            tiles, entries = png2asset.tiles_and_map(png2asset.indices(img, pal), img.width, img.height)
            (assets / f"{a.id}.tiles").write_bytes(b"".join(tiles))
            (assets / f"{a.id}.map").write_bytes(b"".join(e.to_bytes(2, "little") for e in entries))
            meta = {"asset": a.id, "type": "tilemap", "tiles": len(tiles), "map_w": img.width // 8, "map_h": img.height // 8,
                    "palette": a.palette or a.id}
            (assets / f"{a.id}.meta.json").write_text(json.dumps(meta, indent=2) + "\n")
            png2asset.save_palette(pal_path, pal)
        else:
            png2asset.export(assets, a.id, [img], 0, None, "background")
    grids = {}
    for csv in sorted(a.level.glob("*.csv")):
        rows = [r for r in csv.read_text(encoding="utf-8").splitlines() if r.strip()]
        cells = [[int(v) for v in r.strip(",").split(",") if v != ""] for r in rows]
        gw, gh = (len(cells[0]) if cells else 0), len(cells)
        size = data["width"] // gw if gw else 0
        grids[re.sub(r"[^A-Za-z0-9_]", "_", csv.stem)] = {"size": size, "w": gw, "h": gh, "data": [v for r in cells for v in r]}
    entities = []
    for name, lst in data.get("entities", {}).items():
        for e in lst:
            fields = {k: v for k, v in e.items() if k not in ("id", "iid", "layer", "x", "y", "width", "height", "color", "customFields")}
            fields.update(e.get("customFields", {}))
            entities.append({"name": name, "x": e.get("x", 0), "y": e.get("y", 0), "w": e.get("width", 0), "h": e.get("height", 0),
                             "fields": fields})
    out = {"w": data.get("width", 0), "h": data.get("height", 0), "bg": data.get("bgColor", "#000000"),
           "neighbours": [{"dir": n.get("dir", ""), "id": n.get("levelIid", "")} for n in data.get("neighbourLevels", [])],
           "grids": grids, "entities": entities}
    stem = a.id.lower()
    (a.game / f"{stem}.lua").write_text(f"-- {stem}: LDtk's {a.level.name}, made by tools/ldtk2asset.py\nreturn {lua(out)}\n")
    print(f"{a.game / stem}.lua: {len(grids)} grids, {len(entities)} entities; the picture as assets/{a.id}")


if __name__ == "__main__":
    main()
