"""Builds the game's assets from art/: every sprite row and background is packed (tools/png2asset.py --packed), sheets of more than 10 frames are cut into pieces
(tools/pk_split.py: a picture needs one block of memory on the console), and data/sheets.lua says where everything is.

    python3 gen/build.py [--art DIR] [--out GAMEDIR]       # default: art/ and the game folder next to gen/
"""
from __future__ import annotations

import argparse
import json
import subprocess
import sys
from pathlib import Path

HERE = Path(__file__).resolve().parent
sys.path.insert(0, str(HERE))
import contract as C  # noqa: E402

import os  # noqa: E402

ROOT = Path(os.environ.get("PINYOL_ROOT", HERE.parents[2]))  # the repository
PIECE = 10


def lua(v, indent=0) -> str:
    pad = "  " * indent
    if isinstance(v, dict):
        items = [f'{pad}  [{json.dumps(str(k))}] = {lua(x, indent + 1)}' for k, x in v.items()]
        return "{\n" + ",\n".join(items) + f"\n{pad}}}"
    if isinstance(v, (list, tuple)):
        return "{" + ", ".join(lua(x) for x in v) + "}"
    if isinstance(v, bool):
        return "true" if v else "false"
    if isinstance(v, str):
        return json.dumps(v)
    return str(v)


def run(*args) -> None:
    subprocess.run([sys.executable, *map(str, args)], check=True, stdout=subprocess.DEVNULL)


def main() -> None:
    ap = argparse.ArgumentParser()
    ap.add_argument("--art", default=str(HERE.parent / "art"))
    ap.add_argument("--out", default=str(HERE.parent))
    a = ap.parse_args()
    art, out = Path(a.art), Path(a.out)
    assets, data = out / "assets", out / "data"
    assets.mkdir(exist_ok=True)
    data.mkdir(exist_ok=True)
    sheets = {}
    for name, (w, h, anchor, frames) in C.SHEETS.items():
        meta = json.loads((art / f"{name}.json").read_text())
        n = len(meta["frames"])
        sid = "SPR_" + name.upper()
        run(ROOT / "tools/png2asset.py", art / f"{name}.png", assets, sid, "--packed", "--frames", n, "--anchor", f"{meta['anchor'][0]},{meta['anchor'][1]}")
        pieces = n > PIECE
        if pieces:
            run(ROOT / "tools/pk_split.py", assets / f"{sid}.pk", "--frames", PIECE, "--remove")
        entry = {"id": sid, "w": meta["w"], "h": meta["h"], "ax": meta["anchor"][0], "ay": meta["anchor"][1], "n": n, "pieces": pieces,
                 "frames": {f: i for i, f in enumerate(meta["frames"])}}
        for k, v in meta.items():
            if k not in ("w", "h", "anchor", "frames"):
                entry[k] = v
        sheets[name] = entry
    backs = {}
    for name in C.BACKGROUNDS:
        meta = json.loads((art / f"{name}.json").read_text()) if (art / f"{name}.json").exists() else {}
        from PIL import Image
        im = Image.open(art / f"{name}.png")
        bid = "BG_" + name.upper()
        run(ROOT / "tools/png2asset.py", art / f"{name}.png", assets, bid, "--packed", "--type", "background")
        backs[name] = {"id": bid, "w": im.width, "h": im.height}
        for k, v in meta.items():
            if k not in ("w", "h"):
                backs[name][k] = v
    (data / "sheets.lua").write_text("-- made by gen/build.py from art/: where each picture is\nreturn " + lua({"sheets": sheets, "backs": backs}) + "\n")
    print(f"{len(sheets)} sheets, {len(backs)} backgrounds")


if __name__ == "__main__":
    main()
