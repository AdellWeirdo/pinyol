# /// script
# requires-python = ">=3.10"
# dependencies = ["pillow>=10"]
# ///
"""A picture drawn in Aseprite, straight from its .aseprite file (no Aseprite needed to export): its frames become a
pinyol picture, its tags the animations and its slices the boxes.

    uv run tools/ase2asset.py hero.aseprite games/mygame HERO            # assets/HERO.* and hero_anims.lua
    uv run tools/ase2asset.py hero.aseprite games/mygame HERO --layer Body --packed --anchor 12,29

Every visible layer is composed (normal blending; a layer named with --layer alone), each frame with its own
duration. The animations go to <game>/<id>_anims.lua, ready for lib/anim:
    local A = require("hero_anims")      -- {run = {frames = {1, 2, 3}, ms = {100, 100, 100}, mode = "pingpong"}, ...}
    a = anim.new(A)                      -- (frames count from 1, as img's frame option does from 0: anim takes care)
and the slices with them: A.slices.hitbox = {x, y, w, h, pivot = {x, y}} (the first key's).
The file format: github.com/aseprite/aseprite/blob/main/docs/ase-file-specs.md
"""
from __future__ import annotations

import argparse
import re
import struct
import sys
import zlib
from pathlib import Path

from PIL import Image

sys.path.insert(0, str(Path(__file__).resolve().parent))
import png2asset  # noqa: E402


def read_ase(data: bytes) -> dict:
    """The file as frames (each a list of cels), layers, tags, slices, palette."""
    (size, magic, nframes, w, h, depth, flags, speed, _, _, transparent, _, ncolors, pw, ph) = _header(data)
    if magic != 0xA5E0:
        raise ValueError("not an .aseprite file (bad magic)")
    layers, tags, slices, palette = [], [], {}, [None] * 256
    frames = []
    pos = 128
    for _ in range(nframes):
        fsize, fmagic, nchunks_old, duration, _, nchunks_new = struct.unpack_from("<IHHHHI", data, pos)
        if fmagic != 0xF1FA:
            raise ValueError("a frame has a bad magic")
        nchunks = nchunks_new or nchunks_old
        cp = pos + 16
        cels = []
        for _ in range(nchunks):
            csize, ctype = struct.unpack_from("<IH", data, cp)
            body = data[cp + 6:cp + csize]
            if ctype == 0x2004:  # layer
                lflags, ltype, _, _, _, _, _ = struct.unpack_from("<HHHHHHH", body, 0)
                blend, opacity = struct.unpack_from("<HB", body, 14)
                nlen = struct.unpack_from("<H", body, 17)[0]
                name = body[19:19 + nlen].decode("utf-8", "replace")
                layers.append({"name": name, "visible": bool(lflags & 1), "type": ltype, "opacity": opacity, "blend": blend})
            elif ctype == 0x2005:  # cel
                layer, x, y, opacity, celtype, zindex = struct.unpack_from("<HhhBHh", body, 0)
                p = 16
                if celtype in (0, 2):
                    cw, ch_ = struct.unpack_from("<HH", body, p)
                    raw = body[p + 4:]
                    if celtype == 2:
                        raw = zlib.decompress(raw)
                    cels.append({"layer": layer, "x": x, "y": y, "opacity": opacity, "w": cw, "h": ch_, "pixels": raw})
                elif celtype == 1:  # linked: the same as frame n's cel of this layer
                    link = struct.unpack_from("<H", body, p)[0]
                    src = next((c for c in frames[link]["cels"] if c["layer"] == layer), None)
                    if src:
                        cels.append(dict(src))
                # (tilemap cels are not drawn)
            elif ctype == 0x2019:  # palette
                _, first, last = struct.unpack_from("<III", body, 0)
                p = 20
                for i in range(first, last + 1):
                    eflags, r, g, b, a = struct.unpack_from("<HBBBB", body, p)
                    p += 6
                    if eflags & 1:
                        nlen = struct.unpack_from("<H", body, p)[0]
                        p += 2 + nlen
                    if i < 256:
                        palette[i] = (r, g, b, a)
            elif ctype == 0x2018:  # tags
                n = struct.unpack_from("<H", body, 0)[0]
                p = 10
                for _ in range(n):
                    a, b, direction, repeat = struct.unpack_from("<HHBH", body, p)
                    nlen = struct.unpack_from("<H", body, p + 17)[0]
                    name = body[p + 19:p + 19 + nlen].decode("utf-8", "replace")
                    tags.append({"name": name, "from": a, "to": b, "direction": direction, "repeat": repeat})
                    p += 19 + nlen
            elif ctype == 0x2022:  # slice
                nkeys, sflags, _ = struct.unpack_from("<III", body, 0)
                nlen = struct.unpack_from("<H", body, 12)[0]
                name = body[14:14 + nlen].decode("utf-8", "replace")
                p = 14 + nlen
                keys = []
                for _ in range(nkeys):
                    frame, sx, sy, sw, sh = struct.unpack_from("<IiiII", body, p)
                    p += 20
                    key = {"frame": frame, "x": sx, "y": sy, "w": sw, "h": sh}
                    if sflags & 1:
                        key["center"] = struct.unpack_from("<iiII", body, p)
                        p += 16
                    if sflags & 2:
                        key["pivot"] = struct.unpack_from("<ii", body, p)
                        p += 8
                    keys.append(key)
                slices[name] = keys
            cp += csize
        frames.append({"duration": duration, "cels": cels})
        pos += fsize
    return {"w": w, "h": h, "depth": depth, "transparent": transparent, "layers": layers, "frames": frames,
            "tags": tags, "slices": slices, "palette": palette}


def _header(data: bytes) -> tuple:
    size, magic, nframes, w, h, depth = struct.unpack_from("<IHHHHH", data, 0)
    flags, speed = struct.unpack_from("<IH", data, 14)
    transparent = data[28]
    ncolors, pw, ph = struct.unpack_from("<HBB", data, 32)
    return (size, magic, nframes, w, h, depth, flags, speed, 0, 0, transparent, 0, ncolors, pw, ph)


def cel_image(ase: dict, cel: dict) -> Image.Image:
    w, h, px = cel["w"], cel["h"], cel["pixels"]
    if ase["depth"] == 32:
        return Image.frombytes("RGBA", (w, h), px[:w * h * 4])
    if ase["depth"] == 16:
        out = bytearray()
        for i in range(w * h):
            out += bytes((px[2 * i], px[2 * i], px[2 * i], px[2 * i + 1]))
        return Image.frombytes("RGBA", (w, h), bytes(out))
    out = bytearray()
    for i in range(w * h):
        idx = px[i]
        c = ase["palette"][idx] or (0, 0, 0, 255)
        out += bytes(c if idx != ase["transparent"] else (0, 0, 0, 0))
    return Image.frombytes("RGBA", (w, h), bytes(out))


def compose(ase: dict, frame: dict, only: str | None) -> Image.Image:
    img = Image.new("RGBA", (ase["w"], ase["h"]), (0, 0, 0, 0))
    for cel in sorted(frame["cels"], key=lambda c: c["layer"]):
        layer = ase["layers"][cel["layer"]] if cel["layer"] < len(ase["layers"]) else None
        if not layer or layer["type"] != 0:
            continue
        if only is not None and layer["name"] != only:
            continue
        if only is None and not layer["visible"]:
            continue
        piece = cel_image(ase, cel)
        opacity = cel["opacity"] * layer["opacity"] // 255
        if opacity < 255:
            a = piece.getchannel("A").point(lambda v: v * opacity // 255)
            piece.putalpha(a)
        img.alpha_composite(piece, (cel["x"], cel["y"]))
    return img


def lua_anims(ase: dict, stem: str) -> str:
    """The tags as lib/anim's table, and the slices, as Lua source."""
    lines = [f"-- {stem}: the animations and slices of its .aseprite, made by tools/ase2asset.py", "return {"]
    for t in ase["tags"]:
        a, b = t["from"], t["to"]
        frames = list(range(a + 1, b + 2))
        ms = [ase["frames"][i]["duration"] for i in range(a, b + 1)]
        mode = {1: '"reverse"', 2: '"pingpong"', 3: '"pingpong"'}.get(t["direction"], "nil")
        key = re.sub(r"[^A-Za-z0-9_]", "_", t["name"])
        extra = f", mode = {mode}" if mode != "nil" else ""
        if t["repeat"]:
            extra += f", loop = false"
        lines.append(f"  {key} = {{frames = {{{', '.join(map(str, frames))}}}, ms = {{{', '.join(map(str, ms))}}}{extra}}},")
    if ase["slices"]:
        lines.append("  slices = {")
        for name, keys in ase["slices"].items():
            k = keys[0]
            key = re.sub(r"[^A-Za-z0-9_]", "_", name)
            pivot = f", pivot = {{{k['pivot'][0]}, {k['pivot'][1]}}}" if "pivot" in k else ""
            lines.append(f"    {key} = {{x = {k['x']}, y = {k['y']}, w = {k['w']}, h = {k['h']}{pivot}}},")
        lines.append("  },")
    lines.append("}")
    return "\n".join(lines) + "\n"


def main() -> None:
    p = argparse.ArgumentParser(description=__doc__.split("\n\n")[0])
    p.add_argument("ase", type=Path)
    p.add_argument("game", type=Path, help="the game folder (assets/ inside it)")
    p.add_argument("id", help="asset ID")
    p.add_argument("--layer", help="this layer only (default: every visible one)")
    p.add_argument("--anchor", help="x,y inside a frame; default bottom centre")
    p.add_argument("--packed", action="store_true", help="a packed picture (its own palette, opaque runs)")
    p.add_argument("--colours", type=int, help="with --packed: at most this many colours")
    p.add_argument("--type", default="sprite", choices=("sprite", "background", "ui"))
    a = p.parse_args()
    if not re.fullmatch(r"[A-Za-z0-9_]+", a.id):
        p.error("IDs: letters, digits and _ only")
    ase = read_ase(a.ase.read_bytes())
    frames = [compose(ase, f, a.layer) for f in ase["frames"]]
    anchor = tuple(int(v) for v in a.anchor.split(",")) if a.anchor else None
    assets = a.game / "assets"
    if a.packed:
        png2asset.export_packed(assets, a.id, frames, a.colours, 0, anchor)
    else:
        png2asset.export(assets, a.id, frames, 0, anchor, a.type)
    meta_path = assets / f"{a.id}.meta.json"
    import json
    meta = json.loads(meta_path.read_text())
    meta["frame_ms"] = [f["duration"] for f in ase["frames"]]
    meta_path.write_text(json.dumps(meta, indent=2) + "\n")
    stem = a.id.lower() + "_anims"
    (a.game / f"{stem}.lua").write_text(lua_anims(ase, stem))
    print(f"{assets / a.id}: {len(frames)} frames of {ase['w']}x{ase['h']}, {len(ase['tags'])} animations, "
          f"{len(ase['slices'])} slices -> {a.game / stem}.lua")


if __name__ == "__main__":
    main()
