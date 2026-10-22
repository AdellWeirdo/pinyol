"""Pack a game folder as a .zip: to copy onto the console's card, to share, or to play in the web player.

    python3 tools/pack_game.py examples/naves                # -> naves.zip, here
    python3 tools/pack_game.py examples/naves -o dist/       # -> dist/naves.zip
    python3 tools/pack_game.py examples/naves --sources      # also the art sources (art/, art.py, ...)

The zip holds one folder named after the game's id, so unzipping it into the card's games/ folder installs it.
Without --sources it holds what the console reads: game.json and the other .json, the Lua files, assets/, audio/,
fonts/, video/, story/, maps/, data/ (and zones/, dialogues/ for pinyol@1 games). Saves are never packed.
"""
from __future__ import annotations

import argparse
import json
import re
import sys
import zipfile
from pathlib import Path

RUNTIME_DIRS = {"assets", "audio", "fonts", "video", "story", "maps", "data",  # pinyol@2: video() reads video/,
                "zones", "dialogues"}  # file() any other file (story/es.txt, maps/...); pinyol@1 the last two
SKIP = {"saves", "__pycache__", ".git", ".DS_Store"}


def game_id(folder: Path) -> str:
    meta = json.loads((folder / "game.json").read_text(encoding="utf-8"))
    gid = str(meta.get("id", ""))
    if not re.fullmatch(r"[A-Za-z0-9_-]{1,40}", gid):
        sys.exit(f"{folder}/game.json: the id must be 1-40 letters, digits, _ or - (it is {gid!r})")
    return gid


def runtime_file(rel: Path) -> bool:
    if len(rel.parts) == 1:
        # (its cover in the console's menu; the words lang.lua reads: a game that left them out stopped in _init)
        return rel.suffix in {".json", ".lua"} or rel.name in {"cover.rgb565", "strings.csv"}
    return rel.parts[0] in RUNTIME_DIRS or rel.suffix == ".lua"


def pack(folder: Path, out_dir: Path, sources: bool) -> Path:
    if not (folder / "game.json").is_file():
        sys.exit(f"{folder}: no game.json, not a game folder")
    gid = game_id(folder)
    out_dir.mkdir(parents=True, exist_ok=True)
    out = out_dir / f"{gid}.zip"
    files = sorted(p for p in folder.rglob("*")  # links are left out: a zip holds the game, not what it points to
                   if p.is_file() and not p.is_symlink() and not SKIP & set(p.relative_to(folder).parts))
    n = 0
    with zipfile.ZipFile(out, "w", zipfile.ZIP_DEFLATED, compresslevel=9) as z:
        for p in files:
            rel = p.relative_to(folder)
            if sources or runtime_file(rel):
                z.write(p, f"{gid}/{rel.as_posix()}")
                n += 1
    print(f"{out}: {n} files, {out.stat().st_size / 1024:.0f} KB")
    return out


def budget(folder: Path) -> None:
    """What the game weighs: every file the console reads, by kind, with the memory a picture takes once loaded
    (its meta's memory_bytes), the biggest first. A game that is slow to start or short of memory shows here."""
    rows = []
    for p in sorted(folder.rglob("*")):
        if not p.is_file() or p.is_symlink():
            continue
        rel = p.relative_to(folder)
        if SKIP & set(rel.parts) or not runtime_file(rel):
            continue
        mem = 0
        if p.suffix == ".json" and p.name.endswith(".meta.json"):
            try:
                mem = int(json.loads(p.read_text(encoding="utf-8")).get("memory_bytes", {}).get("total", 0))
            except (OSError, ValueError, AttributeError):
                mem = 0
        kind = rel.parts[0] if len(rel.parts) > 1 else rel.suffix.lstrip(".")
        rows.append((p.stat().st_size, mem, kind, rel.as_posix()))
    by_kind: dict[str, list[int]] = {}
    for size, mem, kind, _ in rows:
        k = by_kind.setdefault(kind, [0, 0, 0])
        k[0] += size
        k[1] += mem
        k[2] += 1
    print(f"{'KB':>8} {'RAM KB':>8}  file")
    for size, mem, _, name in sorted(rows, reverse=True)[:30]:
        print(f"{size / 1024:8.1f} {mem / 1024 if mem else 0:8.1f}  {name}")
    print()
    print(f"{'KB':>8} {'RAM KB':>8} {'files':>6}  kind")
    for kind, (size, mem, n) in sorted(by_kind.items(), key=lambda kv: -kv[1][0]):
        print(f"{size / 1024:8.1f} {mem / 1024:8.1f} {n:6}  {kind}")
    total = sum(r[0] for r in rows)
    print(f"{total / 1024:8.1f} KB on the card in {len(rows)} files; pictures' memory as their metas say (packed pictures and canvases apart)")


def main() -> None:
    ap = argparse.ArgumentParser(description=__doc__.split("\n")[0])
    ap.add_argument("folder", type=Path)
    ap.add_argument("-o", "--out", type=Path, default=Path("."), help="folder for the .zip (default: here)")
    ap.add_argument("--sources", action="store_true", help="also the art sources and tools in the game folder")
    ap.add_argument("--budget", action="store_true", help="no zip: what the game weighs, file by file and by kind")
    a = ap.parse_args()
    if a.budget:
        budget(a.folder)
        return
    pack(a.folder, a.out, a.sources)


if __name__ == "__main__":
    main()
