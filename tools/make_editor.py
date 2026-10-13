#!/usr/bin/env python3
"""np2d's editor, ready to be served: editor/ and the web player (built with Emscripten) in one folder.

    python3 tools/make_editor.py OUT --player build-web     # then serve OUT (python3 -m http.server -d OUT)

The editor plays its games in the player (OUT/player/player.html), so both must come from the same site.
"""
from __future__ import annotations

import argparse
import shutil
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
LIBS = ("kit.lua", "juice.lua", "particles.lua")  # editor/js/main.js fetches the same list


def main() -> None:
    ap = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    ap.add_argument("out", type=Path)
    ap.add_argument("--player", type=Path, required=True, help="the Emscripten build with player.html, .js, .wasm")
    a = ap.parse_args()
    files = [a.player / f"player.{ext}" for ext in ("html", "js", "wasm")]
    missing = [f for f in files if not f.exists()]
    if missing:
        raise SystemExit(f"no web player in {a.player} (build it as the README says): {missing[0].name} is missing")
    if a.out.exists():
        if any(a.out.iterdir()) and not (a.out / "player" / "player.wasm").exists():
            raise SystemExit(f"{a.out} has other things in it: give an empty folder or a previous editor's")
        shutil.rmtree(a.out)
    shutil.copytree(ROOT / "editor", a.out, ignore=shutil.ignore_patterns("test"))
    (a.out / "lib").mkdir()
    for name in LIBS:  # each game the editor makes carries these: it plays the same on a console with older firmware
        shutil.copy(ROOT / "lib" / name, a.out / "lib")
    (a.out / "player").mkdir()
    for f in files:
        shutil.copy(f, a.out / "player")
    print(f"editor in {a.out}: serve it (python3 -m http.server -d {a.out}) and open /")


if __name__ == "__main__":
    main()
