# /// script
# requires-python = ">=3.10"
# dependencies = ["pillow>=10"]
# ///
"""Import a level drawn in Tiled (mapeditor.org) into an pinyol@2 game.

    uv run tools/tiled2asset.py level1.tmx games/mygame LEVEL1 [--palette WORLD] [--affine]

Each visible tile layer becomes a PPU background, assets/<ID>_<LAYER>.tiles/.map (bg(n, {map = "LEVEL1_GROUND"})),
drawn with its tileset and cut into 8x8 tiles; any tile size works, flipped and turned tiles too. Everything else
goes into <id>.lua in the game folder (require("level1")):

    width, height, tile_w, tile_h      the map, in tiles and pixels per tile
    layers.<name> = {asset, data}      each tile layer: its asset ID and its tile ids, row by row (0: empty)
    tiles[id] = {prop = value}         the custom properties of tiles (solid = true, ...), by tile id
    objects = {{name, type, x, y, w, h, props}}   the objects of the object layers, in pixels
    props                              the map's own custom properties

Tile ids are Tiled's global ids without the flip bits, so tiles[layers.ground.data[i]] tells what a cell is.
Maps are .tmx (CSV, base64, zlib or gzip data) or Tiled's JSON (.tmj/.json); tilesets embedded or in .tsx/.tsj.
"""
from __future__ import annotations

import argparse
import base64
import gzip
import json
import re
import subprocess
import sys
import tempfile
import xml.etree.ElementTree as ET
import zlib
from pathlib import Path

from PIL import Image

HERE = Path(__file__).resolve().parent
FLIP_H, FLIP_V, FLIP_D = 0x80000000, 0x40000000, 0x20000000
GID = 0x0FFFFFFF


def typed(kind: str, value):
    if kind == "bool":
        return value in (True, "true", "1", 1)
    if kind == "int":
        return int(value)
    if kind == "float":
        return float(value)
    return value


def props_xml(el: ET.Element | None) -> dict:
    if el is None or el.find("properties") is None:
        return {}
    return {p.get("name"): typed(p.get("type", "string"), p.get("value", p.text or ""))
            for p in el.find("properties").findall("property")}


def props_json(items: list | None) -> dict:
    return {p["name"]: typed(p.get("type", "string"), p["value"]) for p in items or []}


def decode_data(text: str, encoding: str | None, compression: str | None) -> list[int]:
    if encoding in (None, "csv"):
        return [int(v) for v in re.split(r"[,\s]+", text.strip()) if v]
    raw = base64.b64decode(text.strip())
    if compression == "zlib":
        raw = zlib.decompress(raw)
    elif compression == "gzip":
        raw = gzip.decompress(raw)
    elif compression:
        sys.exit(f"tile data compressed with {compression}: save the map with CSV, zlib or gzip")
    return [int.from_bytes(raw[i:i + 4], "little") for i in range(0, len(raw), 4)]


class Tileset:
    def __init__(self, firstgid: int, image: Path, tw: int, th: int, columns: int, count: int, margin: int,
                 spacing: int, tile_props: dict[int, dict]):
        self.firstgid, self.tw, self.th, self.columns, self.count = firstgid, tw, th, columns, count
        self.margin, self.spacing, self.tile_props = margin, spacing, tile_props
        self.image = Image.open(image).convert("RGBA")

    def tile(self, local: int) -> Image.Image:
        x = self.margin + (local % self.columns) * (self.tw + self.spacing)
        y = self.margin + (local // self.columns) * (self.th + self.spacing)
        return self.image.crop((x, y, x + self.tw, y + self.th))


def tileset_xml(ts: ET.Element, base: Path, firstgid: int) -> Tileset:
    if ts.get("source"):  # an external .tsx
        path = base / ts.get("source")
        if path.suffix in (".tsj", ".json"):
            return tileset_json(json.loads(path.read_text()), path.parent, firstgid)
        return tileset_xml(ET.parse(path).getroot(), path.parent, firstgid)
    img = ts.find("image")
    if img is None:
        sys.exit(f"tileset {ts.get('name')}: a collection of images is not supported, use one tileset image")
    tw, th = int(ts.get("tilewidth")), int(ts.get("tileheight"))
    margin, spacing = int(ts.get("margin", 0)), int(ts.get("spacing", 0))
    image = base / img.get("source")
    columns = int(ts.get("columns", 0)) or (int(img.get("width")) - 2 * margin + spacing) // (tw + spacing)
    tile_props = {int(t.get("id")): props_xml(t) for t in ts.findall("tile") if props_xml(t)}
    return Tileset(firstgid, image, tw, th, columns, int(ts.get("tilecount", 0)), margin, spacing, tile_props)


def tileset_json(ts: dict, base: Path, firstgid: int) -> Tileset:
    if "source" in ts:
        path = base / ts["source"]
        if path.suffix == ".tsx":
            return tileset_xml(ET.parse(path).getroot(), path.parent, firstgid)
        return tileset_json(json.loads(path.read_text()), path.parent, firstgid)
    if "image" not in ts:
        sys.exit(f"tileset {ts.get('name')}: a collection of images is not supported, use one tileset image")
    tw, th = ts["tilewidth"], ts["tileheight"]
    margin, spacing = ts.get("margin", 0), ts.get("spacing", 0)
    columns = ts.get("columns") or (ts["imagewidth"] - 2 * margin + spacing) // (tw + spacing)
    tile_props = {t["id"]: props_json(t.get("properties")) for t in ts.get("tiles", []) if t.get("properties")}
    return Tileset(firstgid, base / ts["image"], tw, th, columns, ts.get("tilecount", 0), margin, spacing, tile_props)


def read_map(path: Path) -> dict:
    """The map as plain data: size, tilesets, tile layers (name, data) and objects, whatever the file format."""
    m: dict = {"layers": [], "objects": []}
    if path.suffix == ".tmx":
        root = ET.parse(path).getroot()
        if root.get("infinite") == "1":
            sys.exit("infinite maps are not supported: in Tiled, Map > Map Properties > Infinite off")
        m.update(width=int(root.get("width")), height=int(root.get("height")), tw=int(root.get("tilewidth")),
                 th=int(root.get("tileheight")), props=props_xml(root))
        m["tilesets"] = [tileset_xml(ts, path.parent, int(ts.get("firstgid"))) for ts in root.findall("tileset")]
        for el in root.iter():
            if el.tag == "layer" and el.get("visible", "1") != "0":
                d = el.find("data")
                m["layers"].append((el.get("name"), decode_data(d.text or "", d.get("encoding"), d.get("compression"))))
            elif el.tag == "objectgroup":
                for o in el.findall("object"):
                    m["objects"].append({"name": o.get("name", ""), "type": o.get("type", o.get("class", "")),
                                         "x": float(o.get("x", 0)), "y": float(o.get("y", 0)),
                                         "w": float(o.get("width", 0)), "h": float(o.get("height", 0)),
                                         "props": props_xml(o)})
        return m
    doc = json.loads(path.read_text())
    if doc.get("infinite"):
        sys.exit("infinite maps are not supported: in Tiled, Map > Map Properties > Infinite off")
    m.update(width=doc["width"], height=doc["height"], tw=doc["tilewidth"], th=doc["tileheight"],
             props=props_json(doc.get("properties")))
    m["tilesets"] = [tileset_json(ts, path.parent, ts["firstgid"]) for ts in doc["tilesets"]]

    def walk(layers: list) -> None:
        for la in layers:
            if la["type"] == "group":
                walk(la["layers"])
            elif la["type"] == "tilelayer" and la.get("visible", True):
                data = la["data"]
                if isinstance(data, str):
                    data = decode_data(data, la.get("encoding"), la.get("compression"))
                m["layers"].append((la["name"], data))
            elif la["type"] == "objectgroup":
                for o in la["objects"]:
                    m["objects"].append({"name": o.get("name", ""), "type": o.get("type", o.get("class", "")),
                                         "x": o.get("x", 0), "y": o.get("y", 0), "w": o.get("width", 0),
                                         "h": o.get("height", 0), "props": props_json(o.get("properties"))})
    walk(doc["layers"])
    return m


def tileset_of(tilesets: list[Tileset], gid: int) -> Tileset:
    return max((t for t in tilesets if t.firstgid <= gid), key=lambda t: t.firstgid)


def render(m: dict, data: list[int]) -> Image.Image:
    img = Image.new("RGBA", (m["width"] * m["tw"], m["height"] * m["th"]))
    for i, raw in enumerate(data):
        gid = raw & GID
        if not gid:
            continue
        ts = tileset_of(m["tilesets"], gid)
        t = ts.tile(gid - ts.firstgid)
        if raw & FLIP_D:
            t = t.transpose(Image.Transpose.TRANSPOSE)
        if raw & FLIP_H:
            t = t.transpose(Image.Transpose.FLIP_LEFT_RIGHT)
        if raw & FLIP_V:
            t = t.transpose(Image.Transpose.FLIP_TOP_BOTTOM)
        x, y = (i % m["width"]) * m["tw"], (i // m["width"]) * m["th"] + m["th"] - ts.th  # taller tiles grow up
        img.alpha_composite(t, (x, max(y, 0)))
    return img


LUA_KEYWORDS = {"and", "break", "do", "else", "elseif", "end", "false", "for", "function", "goto", "if", "in", "local",
                "nil", "not", "or", "repeat", "return", "then", "true", "until", "while"}


def lua_str(s: str) -> str:
    """A Lua string literal: quotes, backslashes and control characters escaped as \\ddd; UTF-8 kept as it is."""
    return '"' + "".join(f"\\{ord(c):03d}" if c in '"\\' or ord(c) < 32 or ord(c) == 127 else c for c in s) + '"'


def lua_key(k) -> str:
    if isinstance(k, int):
        return f"[{k}]"
    if re.fullmatch(r"[A-Za-z_][A-Za-z0-9_]*", k) and k not in LUA_KEYWORDS:
        return k
    return f"[{lua_str(k)}]"


def lua(v, indent: str = "") -> str:
    if isinstance(v, bool):
        return "true" if v else "false"
    if isinstance(v, (int, float)):
        return repr(int(v)) if float(v).is_integer() else repr(float(v))
    if isinstance(v, str):
        return lua_str(v)
    if isinstance(v, list):
        if all(isinstance(x, int) for x in v):
            rows = [", ".join(str(x) for x in v[k:k + 32]) for k in range(0, len(v), 32)]
            return "{\n" + "".join(f"{indent}  {r},\n" for r in rows) + indent + "}"
        return "{\n" + "".join(f"{indent}  {lua(x, indent + '  ')},\n" for x in v) + indent + "}"
    if isinstance(v, dict):
        if not v:
            return "{}"
        keys = [lua_key(k) for k in v]
        return "{\n" + "".join(f"{indent}  {k} = {lua(x, indent + '  ')},\n" for k, x in zip(keys, v.values())) + indent + "}"
    raise TypeError(type(v))


def main() -> None:
    ap = argparse.ArgumentParser(description=__doc__.split("\n")[0])
    ap.add_argument("map", type=Path, help="the Tiled map, .tmx or .tmj/.json")
    ap.add_argument("game", type=Path, help="the game's folder")
    ap.add_argument("id", help="the level's asset ID, e.g. LEVEL1: layers become LEVEL1_<LAYER>")
    ap.add_argument("--palette", default="WORLD", help="the shared background palette (default WORLD)")
    ap.add_argument("--affine", action="store_true", help="for affine layers (rotation, Mode 7): no flipped tiles")
    a = ap.parse_args()
    if not re.fullmatch(r"[A-Za-z0-9_]+", a.id):
        sys.exit(f"{a.id}: an ID is letters, digits and _")
    m = read_map(a.map)
    assets = a.game / "assets"
    assets.mkdir(parents=True, exist_ok=True)
    layers, used = {}, set()
    with tempfile.TemporaryDirectory() as tmp:
        for name, data in m["layers"]:
            if len(data) != m["width"] * m["height"]:
                sys.exit(f"layer {name}: {len(data)} cells for a {m['width']}x{m['height']} map")
            aid = f"{a.id}_{re.sub(r'[^A-Za-z0-9]+', '_', name).strip('_')}".upper()
            if aid in used:
                sys.exit(f"two layers make the same asset ID {aid}: rename one")
            used.add(aid)
            png = Path(tmp) / f"{aid}.png"
            render(m, data).save(png)
            cmd = [sys.executable, str(HERE / "png2asset.py"), str(png), str(assets), aid, "--tiles", "--palette", a.palette]
            subprocess.run(cmd + (["--affine"] if a.affine else []), check=True)
            layers[re.sub(r"[^A-Za-z0-9_]", "_", name)] = {"asset": aid, "data": [g & GID for g in data]}
    tiles = {ts.firstgid + k: v for ts in m["tilesets"] for k, v in ts.tile_props.items()}
    module = {"width": m["width"], "height": m["height"], "tile_w": m["tw"], "tile_h": m["th"], "layers": layers,
              "tiles": tiles, "objects": m["objects"], "props": m["props"]}
    out = a.game / f"{a.id.lower()}.lua"
    out.write_text(f"-- Made by tools/tiled2asset.py from {a.map.name}: change the map in Tiled and import it again.\n"
                   f"return {lua(module)}\n", encoding="utf-8")
    print(f"{out}: {len(layers)} layer(s), {len(m['objects'])} object(s), {len(tiles)} tile(s) with properties")


if __name__ == "__main__":
    main()
