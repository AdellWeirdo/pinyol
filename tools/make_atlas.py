# /// script
# requires-python = ">=3.10"
# dependencies = ["pillow>=10"]
# ///
"""Pack single-frame pictures into one 128x128 texture page for quad UVs.

    uv run tools/build_art.py GAME
    uv run tools/make_atlas.py GAME PROPS ICO_KEY SPR_SIGN

Reads GAME/art/.built/<ID>.png and its asset metadata. Writes assets/PROPS.pk,
assets/PROPS.meta.json, art/.built/PROPS.png and props_atlas.lua. A picture must
fit with a one-pixel duplicated edge. Use separate pages for more pictures.
"""
from __future__ import annotations

import argparse
import json
import re
from pathlib import Path

from PIL import Image

from png2asset import export_packed

PAGE = 128  # 32 KB unpacked RGB565: the measured sweet spot for quad textures
NAME = re.compile(r"[A-Za-z0-9_]+\Z")


def edge(page: Image.Image, image: Image.Image, x: int, y: int) -> None:
    """Copy the picture and one texel of its border, so an edge UV never reads a neighbour."""
    w, h = image.size
    page.paste(image, (x, y))
    page.paste(image.crop((0, 0, w, 1)), (x, y - 1))
    page.paste(image.crop((0, h - 1, w, h)), (x, y + h))
    page.paste(image.crop((0, 0, 1, h)), (x - 1, y))
    page.paste(image.crop((w - 1, 0, w, h)), (x + w, y))
    for xx, yy, px, py in ((x - 1, y - 1, 0, 0), (x + w, y - 1, w - 1, 0),
                           (x - 1, y + h, 0, h - 1), (x + w, y + h, w - 1, h - 1)):
        page.putpixel((xx, yy), image.getpixel((px, py)))


def build(game: Path, name: str, ids: list[str]) -> dict[str, tuple[int, int, int, int]]:
    if not NAME.fullmatch(name) or not ids or len(ids) != len(set(ids)) or name in ids:
        raise ValueError("use a unique asset name and distinct picture IDs (letters, digits, _)")
    assets, built = game / "assets", game / "art" / ".built"
    old = assets / f"{name}.meta.json"
    if old.exists() and "atlas_sources" not in json.loads(old.read_text()):
        raise ValueError(f"{name} already names a non-atlas asset")
    if (assets / f"{name}.pk").exists() and not old.exists():
        raise ValueError(f"{name} already has an untracked packed asset")
    module = game / f"{name.lower()}_atlas.lua"
    if module.exists() and not module.read_text().startswith("-- made by tools/make_atlas.py"):
        raise ValueError(f"{module.name} is not a generated atlas module")
    if (built / f"{name}.png").exists() and not old.exists():
        raise ValueError(f"{name} already has an untracked built picture")
    pictures = []
    for aid in ids:
        if not NAME.fullmatch(aid):
            raise ValueError(f"invalid picture ID: {aid!r}")
        meta = json.loads((assets / f"{aid}.meta.json").read_text())
        image = Image.open(built / f"{aid}.png").convert("RGBA")
        w, h = image.size
        if meta.get("frames") != 1 or (w, h) != (meta.get("w"), meta.get("h")):
            raise ValueError(f"{aid}: atlas needs one built frame with its recorded size")
        if not 0 < w <= PAGE - 2 or not 0 < h <= PAGE - 2:
            raise ValueError(f"{aid}: {w}x{h} exceeds a {PAGE}x{PAGE} page with its border")
        pictures.append((aid, image))
    page = Image.new("RGBA", (PAGE, PAGE))
    uv = {}
    x = y = 1
    row_h = 0
    for aid, image in sorted(pictures, key=lambda p: (-p[1].height, -p[1].width, p[0])):
        w, h = image.size
        if x + w + 1 > PAGE:
            x, y, row_h = 1, y + row_h + 2, 0
        if y + h + 1 > PAGE:
            raise ValueError(f"{name}: pictures do not fit in one {PAGE}x{PAGE} page")
        edge(page, image, x, y)
        uv[aid] = (x, y, x + w, y + h)
        x += w + 2
        row_h = max(row_h, h)
    export_packed(assets, name, [page], 256, kind="atlas")
    meta = json.loads(old.read_text())
    meta["atlas_sources"] = ids
    old.write_text(json.dumps(meta, indent=2) + "\n")
    built.mkdir(parents=True, exist_ok=True)
    page.save(built / f"{name}.png")
    lines = ["-- made by tools/make_atlas.py; pass entry.id to quad and entry.uv in its options", "return {"]
    for aid in ids:
        u1, v1, u2, v2 = uv[aid]
        lines.append(f'  ["{aid}"] = {{id = "{name}", uv = {{{u1}, {v1}, {u2}, {v1}, {u2}, {v2}, {u1}, {v2}}}}},')
    lines.append("}")
    module.write_text("\n".join(lines) + "\n")
    return uv


def main() -> None:
    parser = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    parser.add_argument("game", type=Path)
    parser.add_argument("name")
    parser.add_argument("ids", nargs="+")
    args = parser.parse_args()
    try:
        uv = build(args.game, args.name, args.ids)
    except (OSError, ValueError, KeyError, json.JSONDecodeError) as err:
        parser.error(str(err))
    print(f"{args.name}: {len(uv)} picture(s), {PAGE}x{PAGE} page; {args.name.lower()}_atlas.lua")


if __name__ == "__main__":
    main()
