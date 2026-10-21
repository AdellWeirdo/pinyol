# /// script
# requires-python = ">=3.10"
# ///
"""The letters a game's texts need that its fonts lack, and the keys a language misses:

    python3 tools/strings_check.py games/mygame               # strings.csv against fonts/*.fnt
    python3 tools/strings_check.py games/mygame --pseudo      # also writes strings.pseudo.csv: every text 40% longer and
                                                              # accented, to find what overflows its box

A FNT1 font (tools/font2fnt.py) has 256 cp1252 glyphs; one with no advance is missing. Exit code 1 when something
is missing, so a build can check.
"""
from __future__ import annotations

import argparse
import csv
import sys
from pathlib import Path


def font_coverage(path: Path) -> set[int]:
    d = path.read_bytes()
    if len(d) < 264 or d[:4] != b"FNT1":
        raise ValueError(f"{path}: not a FNT1 font")
    return {i for i in range(256) if d[8 + i] != 0}


def check(game: Path, pseudo: bool) -> int:
    csv_path = game / "strings.csv"
    rows = list(csv.reader(csv_path.open(encoding="utf-8", newline="")))
    if not rows:
        print(f"{csv_path}: empty")
        return 1
    langs = rows[0][1:]
    missing_keys = {l: [] for l in langs}
    needed: set[str] = set()
    for r in rows[1:]:
        if not r or not r[0].strip():
            continue
        for i, l in enumerate(langs):
            v = r[i + 1] if i + 1 < len(r) else ""
            if not v.strip():
                missing_keys[l].append(r[0])
            needed |= set(v)
    problems = 0
    for l, keys in missing_keys.items():
        if keys:
            problems += 1
            print(f"{l}: {len(keys)} keys without a text: {', '.join(keys[:12])}{' ...' if len(keys) > 12 else ''}")
    for fnt in sorted((game / "fonts").glob("*.fnt")):
        have = font_coverage(fnt)
        lacking = []
        for ch in sorted(needed):
            if ch in "\n\r\t":
                continue
            try:
                code = ch.encode("cp1252")[0]
            except UnicodeEncodeError:
                lacking.append(ch)
                continue
            if code not in have:
                lacking.append(ch)
        if lacking:
            problems += 1
            print(f"{fnt.name}: lacks {' '.join(lacking)}")
    if pseudo:
        out = game / "strings.pseudo.csv"
        table = str.maketrans("aeiouAEIOUcn", "àéíóúÀÉÍÓÚçñ")
        with out.open("w", encoding="utf-8", newline="") as f:
            w = csv.writer(f)
            w.writerow(rows[0])
            for r in rows[1:]:
                w.writerow([r[0]] + [(v.translate(table) + " " + "~" * max(1, len(v) * 2 // 5)) if v else v for v in r[1:]])
        print(f"{out}: every text longer and accented (point lang.load at it to see what overflows)")
    if not problems:
        print(f"{csv_path}: {len(rows) - 1} keys, {len(langs)} languages, every letter in every font")
    return 1 if problems else 0


def main() -> None:
    ap = argparse.ArgumentParser(description=__doc__.split("\n\n")[0])
    ap.add_argument("game", type=Path)
    ap.add_argument("--pseudo", action="store_true")
    a = ap.parse_args()
    sys.exit(check(a.game, a.pseudo))


if __name__ == "__main__":
    main()
