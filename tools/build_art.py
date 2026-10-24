# /// script
# requires-python = ">=3.10"
# dependencies = ["pillow>=10"]
# ///
"""Makes all of a game's pictures from its raw art in one go, from a list (GAME/art.json), and again only those whose source or
entry changed: the step between an image generator's PNGs and the engine's assets, without a script of your own for each game.

    uv run tools/build_art.py GAME                # every picture in GAME/art.json that changed
    uv run tools/build_art.py GAME --all          # every one
    uv run tools/build_art.py GAME --sheet out.png  # then a picture of them all, to look at

art.json (paths relative to the game):

  {"defaults": {"colours": 128},
   "pictures": [
     {"id": "SPR_YURI_WALK", "src": "raw/yuri_walk.png", "split": 6, "frame": [64, 64], "height": 50, "key_bg": true, "ms": 100},
     {"id": "SPR_YURI_IDLE", "src": "raw/yuri_idle.png", "frame": [64, 64], "height": 50, "key_bg": true},
     {"id": "SPR_MORRIS", "src": "raw/morris.png", "like": "art/morris_ref.png", "split": 4, "anchor": "left", "keep_main": true},
     {"id": "BG_BAR", "src": "raw/bar.png", "size": [480, 320], "type": "background", "depth": {"map": "raw/bar_depth.png", "z_from_bottom": true}},
     {"id": "ICO_LLAVE", "src": "art/llave.png", "copy": true, "colours": 16}
   ]}

A sprite (frame, or like): the image (or a sheet cut into `split` frames along its empty columns) has its background removed
(`key_bg`: white or a fake checkerboard; else it must have real transparency), each frame scaled so the character's body is
`height` pixels tall (the largest blob: motion lines and sparks do not shrink it) and stood on the frame's foot, `feet` pixels
above it (default 1), centred (`anchor`: "left"/"right" for a punch that reaches out). `like` takes the size, scale and foot from a
frame you already have instead. A picture with `size` is resized to cover it and cut to it (a background). `copy` packs a PNG as it
is. `"fit": "feet"` fits it with tools/sprite_kit.py instead (docs/art.md, "Sprites that fit"): each sheet is scaled by an UPRIGHT frame of it
(`scale_frame`, 0 by default; -1: none, for a jump or a fall), every frame stands with the soles of its body on the frame's foot row and the middle of its feet on the middle
column (an arm that reaches out does not drag it), nothing is cut (a frame is moved inside its cell), and `flying` centres the body on the anchor instead. `depth` cuts a background's pieces that pass in front of the characters (tools/depthcut.py's map and z). Every picture is
packed (a palette of `colours`, only the opaque runs, as png2asset --packed): `art/.built/<ID>.png` keeps what was packed, to look at.
"""
from __future__ import annotations

import argparse
import hashlib
import json
import sys
from pathlib import Path

from PIL import Image, ImageDraw

sys.path.insert(0, str(Path(__file__).resolve().parent))
import depthcut  # noqa: E402
from fit_sprite import fit  # noqa: E402
from png2asset import export_packed  # noqa: E402

TOOLS = Path(__file__).resolve().parent
KNOWN = {"id", "src", "split", "frame", "height", "feet", "like", "key_bg", "keep_main", "anchor", "scale_frame", "ms", "colours",
         "type", "size", "copy", "depth", "anchor_point", "fit", "flying", "cell"}


def ref_frame(w: int, h: int, height: int, feet: int) -> Image.Image:
    """A stand-in for a frame to match: its size, and a body `height` tall standing `feet` above its foot, in its middle."""
    ref = Image.new("RGBA", (w, h), (0, 0, 0, 0))
    ImageDraw.Draw(ref).rectangle((w // 2 - 1, h - feet - height, w // 2, h - feet - 1), fill=(255, 255, 255, 255))
    return ref


def digest(game: Path, e: dict) -> str:
    """What a picture depends on: its entry, its files and the tools' code. The same digest: nothing to do."""
    h = hashlib.sha256(json.dumps(e, sort_keys=True).encode())
    for key in ("src", "like"):
        if e.get(key):
            h.update((game / e[key]).read_bytes())
    if e.get("depth", {}).get("map"):
        h.update((game / e["depth"]["map"]).read_bytes())
    for tool in ("build_art.py", "fit_sprite.py", "sprite_kit.py", "png2asset.py", "depthcut.py"):
        h.update((TOOLS / tool).read_bytes())
    return h.hexdigest()


def frames_of(game: Path, e: dict) -> list[Image.Image]:
    src = Image.open(game / e["src"])
    if e.get("copy"):
        im = src.convert("RGBA")
        n = int(e.get("split", 1))
        if n > 1:  # a strip of n equal frames, as drawn
            fw = im.width // n
            return [im.crop((i * fw, 0, (i + 1) * fw, im.height)) for i in range(n)]
        return [im]
    if e.get("size"):  # a background: cover the size, cut to it
        w, h = e["size"]
        im = src.convert("RGBA")
        k = max(w / im.width, h / im.height)
        im = im.resize((max(w, round(im.width * k)), max(h, round(im.height * k))), Image.LANCZOS)
        x, y = (im.width - w) // 2, (im.height - h) // 2
        return [im.crop((x, y, x + w, y + h))]
    if e.get("fit") == "feet":  # tools/sprite_kit.py: the sheet's own scale from an upright frame, soles on the ground row, feet centred, never cut
        if not (e.get("frame") and e.get("height")):
            raise ValueError('"fit": "feet" needs frame and height')
        import sprite_kit  # (numpy and scipy: only a game that asks for this fit needs them)
        w, h = int(e["frame"][0]), int(e["frame"][1])
        keyed = sprite_kit.key_background(src) if e.get("key_bg") else src.convert("RGBA")
        kf = int(e.get("scale_frame", 0))
        return sprite_kit.fit_sheet(keyed, int(e.get("split", 1)), (w, h), (w // 2, h - 1 - int(e.get("feet", 1))), None if kf < 0 else kf, int(e["height"]),
                                    flying=bool(e.get("flying")))
    if e.get("like"):
        ref = Image.open(game / e["like"])
    elif e.get("frame") and e.get("height"):
        ref = ref_frame(int(e["frame"][0]), int(e["frame"][1]), int(e["height"]), int(e.get("feet", 1)))
    else:
        raise ValueError("a sprite needs frame and height, or like (or size for a background, or copy)")
    return fit(src, ref, None, bool(e.get("key_bg")), int(e.get("split", 1)), int(e.get("scale_frame", 0)),
               bool(e.get("keep_main")), e.get("anchor", "center"))


def build_one(game: Path, e: dict) -> dict:
    assets = game / "assets"
    frames = frames_of(game, e)
    w, h = frames[0].size
    strip = Image.new("RGBA", (w * len(frames), h), (0, 0, 0, 0))
    for i, f in enumerate(frames):
        strip.paste(f, (i * w, 0))
    built = game / "art" / ".built"
    built.mkdir(parents=True, exist_ok=True)
    strip.save(built / f"{e['id']}.png")
    anchor = tuple(e["anchor_point"]) if e.get("anchor_point") else (w // 2, h - 1 - int(e.get("feet", 1)) if e.get("frame") else h - 1)
    kind = e.get("type", "background" if e.get("size") else "sprite")
    export_packed(assets, e["id"], frames, e.get("colours"), int(e.get("ms", 0)), anchor, kind)
    if e.get("depth"):
        d = e["depth"]
        bg = Image.open(game / e["src"]).convert("RGBA") if not e.get("size") else frames[0]
        mp = Image.open(game / d["map"]).convert("RGBA")
        if e.get("size") and mp.size != frames[0].size:  # the map was painted on the raw image: the same cover and cut
            k = max(frames[0].width / mp.width, frames[0].height / mp.height)
            mp = mp.resize((max(frames[0].width, round(mp.width * k)), max(frames[0].height, round(mp.height * k))), Image.NEAREST)
            x, y = (mp.width - frames[0].width) // 2, (mp.height - frames[0].height) // 2
            mp = mp.crop((x, y, x + frames[0].width, y + frames[0].height))
        pieces = depthcut.cut(bg, mp, depthcut.parse_z(d["z"]) if d.get("z") else None, e.get("colours"))
        lines = [f"-- made by tools/build_art.py: the pieces of {e['id']} that pass in front of the characters", "return {"]
        for n, (box, piece, z) in enumerate(pieces, 1):
            export_packed(assets, f"{e['id']}_{n}", [piece], e.get("colours"), 0, (0, 0), "sprite")
            lines.append(f'  {{pic = "{e["id"]}_{n}", x = {box[0]}, y = {box[1]}, z = {z}}},')
        lines.append("}")
        (game / f"{e['id'].lower()}_depth.lua").write_text("\n".join(lines) + "\n")
    meta = json.loads((assets / f"{e['id']}.meta.json").read_text())
    return {"frames": len(frames), "w": w, "h": h, "colours": meta["colours"], "bytes": meta["memory_bytes"]["total"]}


def sheet(game: Path, ids: list[str], out: Path) -> None:
    """Every built picture (its first frames) on a grey and black check, with its id: what the game will draw."""
    tiles = []
    for i in ids:
        p = game / "art" / ".built" / f"{i}.png"
        if p.exists():
            tiles.append((i, Image.open(p).convert("RGBA")))
    if not tiles:
        return
    cell = 200
    cols = 4
    rows = (len(tiles) + cols - 1) // cols
    pic = Image.new("RGB", (cols * cell, rows * (cell + 16)), (30, 30, 36))
    d = ImageDraw.Draw(pic)
    for k, (i, im) in enumerate(tiles):
        x0, y0 = (k % cols) * cell, (k // cols) * (cell + 16)
        for yy in range(0, cell, 8):
            for xx in range(0, cell, 8):
                d.rectangle((x0 + xx, y0 + yy, x0 + xx + 7, y0 + yy + 7), fill=(70, 70, 76) if (xx + yy) // 8 % 2 else (50, 50, 56))
        s = min((cell - 8) / im.width, (cell - 8) / im.height, 4.0)
        t = im.resize((max(1, int(im.width * s)), max(1, int(im.height * s))), Image.NEAREST)
        pic.paste(t, (x0 + (cell - t.width) // 2, y0 + (cell - t.height) // 2), t)
        d.text((x0 + 4, y0 + cell + 2), i, fill=(200, 210, 230))
    pic.save(out)


def main() -> None:
    ap = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    ap.add_argument("game", type=Path)
    ap.add_argument("--all", action="store_true", help="rebuild every picture, changed or not")
    ap.add_argument("--only", nargs="+", metavar="ID", help="only these")
    ap.add_argument("--sheet", type=Path, help="a picture of every built one, to check them by eye")
    a = ap.parse_args()
    spec = json.loads((a.game / "art.json").read_text())
    defaults = spec.get("defaults", {})
    cache_path = a.game / "art" / ".built" / "cache.json"
    cache = json.loads(cache_path.read_text()) if cache_path.exists() else {}
    seen, failed, total = set(), 0, 0
    print(f"{'id':24} {'frames':>6} {'size':>9} {'colours':>7} {'KB':>6}")
    for raw in spec["pictures"]:
        e = {**defaults, **raw}
        unknown = set(e) - KNOWN
        if unknown:
            print(f"{e.get('id', '?')}: unknown keys {sorted(unknown)}", file=sys.stderr)
            failed += 1
            continue
        if not e.get("id") or not e.get("src") or e["id"] in seen:
            print(f"{e.get('id', '?')}: needs a unique id and a src", file=sys.stderr)
            failed += 1
            continue
        seen.add(e["id"])
        if a.only and e["id"] not in a.only:
            continue
        try:
            dg = digest(a.game, e)
            done = cache.get(e["id"])
            if not a.all and done and done.get("digest") == dg and (a.game / "assets" / f"{e['id']}.pk").exists():
                info, state = done["info"], "unchanged"
            else:
                info, state = build_one(a.game, e), "built"
                cache[e["id"]] = {"digest": dg, "info": info}
        except (OSError, ValueError, KeyError) as err:
            print(f"{e['id']}: {err}", file=sys.stderr)
            failed += 1
            continue
        total += info["bytes"]
        print(f"{e['id']:24} {info['frames']:>6} {info['w']:>4}x{info['h']:<4} {info['colours']:>7} {info['bytes'] // 1024:>6}  {state}")
    cache = {k: v for k, v in cache.items() if k in seen}
    cache_path.parent.mkdir(parents=True, exist_ok=True)
    cache_path.write_text(json.dumps(cache, indent=1))
    print(f"{len(seen)} picture(s), {total // 1024} KB packed (the engine keeps up to 4096 KB of packed pictures in memory at a time, "
          "the oldest let go)")
    if a.sheet:
        sheet(a.game, list(seen), a.sheet)
    sys.exit(1 if failed else 0)


if __name__ == "__main__":
    main()
