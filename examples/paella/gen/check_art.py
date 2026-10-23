"""Checks art/ against gen/contract.py: python3 gen/check_art.py"""
from __future__ import annotations

import json
import sys
from pathlib import Path

from PIL import Image

sys.path.insert(0, str(Path(__file__).resolve().parent))
import contract as C  # noqa: E402

ART = Path(__file__).resolve().parent.parent / "art"


def main() -> int:
    bad = 0
    for name, (w, h, anchor, frames) in C.SHEETS.items():
        p, j = ART / f"{name}.png", ART / f"{name}.json"
        if not p.exists() or not j.exists():
            print(f"missing {name}")
            bad += 1
            continue
        meta = json.loads(j.read_text())
        im = Image.open(p)
        problems = []
        if (meta.get("w"), meta.get("h")) != (w, h):
            problems.append(f"frame {meta.get('w')}x{meta.get('h')}, wanted {w}x{h}")
        if list(meta.get("anchor", [])) != list(anchor):
            problems.append(f"anchor {meta.get('anchor')}, wanted {list(anchor)}")
        missing = [f for f in frames if f not in meta.get("frames", [])]
        if missing:
            problems.append(f"{len(missing)} frames missing, first {missing[:6]}")
        if im.size != (w * len(meta.get("frames", [])), h):
            problems.append(f"png {im.size} for {len(meta.get('frames', []))} frames of {w}x{h}")
        for pr in problems:
            print(f"{name}: {pr}")
        bad += bool(problems)
    for name, (w, h) in C.BACKGROUNDS.items():
        p = ART / f"{name}.png"
        if not p.exists():
            print(f"missing {name}")
            bad += 1
        else:
            im = Image.open(p)
            if im.width != w or (h and im.height != h):
                print(f"{name}: {im.size}, wanted {w}x{h or '?'}")
                bad += 1
    print(f"{bad} problems")
    return 1 if bad else 0


if __name__ == "__main__":
    sys.exit(main())
