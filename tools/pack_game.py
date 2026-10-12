"""Pack a game folder as a .zip: to copy onto the console's card, to share, or to play in the web player.

    python3 tools/pack_game.py examples/naves                # -> naves.zip, here
    python3 tools/pack_game.py examples/naves -o dist/       # -> dist/naves.zip
    python3 tools/pack_game.py examples/naves --sources      # also the art sources (art/, art.py, ...)

The zip holds one folder named after the game's id, so unzipping it into the card's games/ folder installs it.
Without --sources it holds what the console reads: game.json and the other .json, the Lua files, assets/, audio/,
fonts/ (and zones/, dialogues/ for np2d@1 games). Saves are never packed.
"""
from __future__ import annotations

import argparse
import json
import re
import sys
import zipfile
from pathlib import Path

RUNTIME_DIRS = {"assets", "audio", "fonts", "zones", "dialogues"}  # np2d@2 uses the first three
SKIP = {"saves", "__pycache__", ".git", ".DS_Store"}


def game_id(folder: Path) -> str:
    meta = json.loads((folder / "game.json").read_text(encoding="utf-8"))
    gid = str(meta.get("id", ""))
    if not re.fullmatch(r"[A-Za-z0-9_-]{1,40}", gid):
        sys.exit(f"{folder}/game.json: the id must be 1-40 letters, digits, _ or - (it is {gid!r})")
    return gid


def runtime_file(rel: Path) -> bool:
    if len(rel.parts) == 1:
        return rel.suffix in {".json", ".lua"}
    return rel.parts[0] in RUNTIME_DIRS or rel.suffix == ".lua"


def pack(folder: Path, out_dir: Path, sources: bool) -> Path:
    if not (folder / "game.json").is_file():
        sys.exit(f"{folder}: no game.json, not a game folder")
    gid = game_id(folder)
    out_dir.mkdir(parents=True, exist_ok=True)
    out = out_dir / f"{gid}.zip"
    files = sorted(p for p in folder.rglob("*") if p.is_file() and not SKIP & set(p.relative_to(folder).parts))
    n = 0
    with zipfile.ZipFile(out, "w", zipfile.ZIP_DEFLATED, compresslevel=9) as z:
        for p in files:
            rel = p.relative_to(folder)
            if sources or runtime_file(rel):
                z.write(p, f"{gid}/{rel.as_posix()}")
                n += 1
    print(f"{out}: {n} files, {out.stat().st_size / 1024:.0f} KB")
    return out


def main() -> None:
    ap = argparse.ArgumentParser(description=__doc__.split("\n")[0])
    ap.add_argument("folder", type=Path)
    ap.add_argument("-o", "--out", type=Path, default=Path("."), help="folder for the .zip (default: here)")
    ap.add_argument("--sources", action="store_true", help="also the art sources and tools in the game folder")
    a = ap.parse_args()
    pack(a.folder, a.out, a.sources)


if __name__ == "__main__":
    main()
