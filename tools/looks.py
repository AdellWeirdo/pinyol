# /// script
# requires-python = ">=3.10"
# ///
"""The look table: what a user means by "a game like <console>", as data (tools/looks.json).

    uv run tools/looks.py "un juego de metal slug"   # -> neogeo, or the candidates if the phrase fits several, or nothing
    uv run tools/looks.py --list                     # every look with its aliases
    uv run tools/looks.py --show neogeo              # one look's rules, limits and example
"""
from __future__ import annotations

import json
import re
import sys
import unicodedata
from pathlib import Path

DATA = Path(__file__).resolve().parent / "looks.json"


def load() -> dict:
    return json.loads(DATA.read_text(encoding="utf-8"))


def norm(text: str) -> str:
    """Lower case, no accents, punctuation as spaces ('Pico-8' and 'pico 8' match the same alias)."""
    t = unicodedata.normalize("NFKD", text.lower()).encode("ascii", "ignore").decode()
    return " " + re.sub(r"[^a-z0-9&]+", " ", t).strip() + " "


def get(look_id: str) -> dict:
    for k in load()["looks"]:
        if k["id"] == look_id:
            return k
    raise KeyError(f"no look {look_id!r}: " + ", ".join(k["id"] for k in load()["looks"]))


def resolve(phrase: str) -> tuple[list[str], str]:
    """(looks the phrase names, a note). One id = clear; several = ask which; none = ask. The longest alias wins ('game boy advance'
    beats 'game boy'); an exact look id is always understood."""
    data, t = load(), norm(phrase)
    best: dict[str, int] = {}
    for k in data["looks"]:
        for a in [k["id"], k["name"]] + k["aliases"]:
            if norm(a) in t:
                best[k["id"]] = max(best.get(k["id"], 0), len(norm(a)))
    if not best:
        for alias, (lid, note) in data["nearest"].items():
            if norm(alias) in t:
                return [lid], note
        return [], ""
    top = max(best.values())
    return [i for i, n in best.items() if n == top], ""


def main() -> None:
    a = sys.argv[1:]
    if not a or a[0] in ("-h", "--help"):
        print(__doc__)
    elif a[0] == "--list":
        for k in load()["looks"]:
            print(f"{k['id']:12} {k['name']:28} example {k['example']:10} {', '.join(k['aliases'])}")
    elif a[0] == "--show" and len(a) > 1:
        print(json.dumps(get(a[1]), ensure_ascii=False, indent=2))
    else:
        ids, note = resolve(" ".join(a))
        print(", ".join(ids) if ids else "none: ask which console", *([f"({note})"] if note else []))
        sys.exit(0 if len(ids) == 1 else 1)


if __name__ == "__main__":
    main()
