"""Imports the art modules and runs each one's entry point (`register()` or `build_all()`), once, in a fixed order (bank numbers depend on it)."""
from __future__ import annotations

import importlib
from pathlib import Path

MODULES = ["art_hero", "art_enemies", "art_items", "art_selva", "art_cristal", "art_galeon", "art_fragua"]
_done = False


# modules that register only when asked (the others register when imported)
ENTRY = {"art_enemies": "register", "art_items": "build_all"}


def load(verbose: bool = False) -> list[str]:
    global _done
    loaded = []
    for m in MODULES:
        if not (Path(__file__).resolve().parent / f"{m}.py").exists():
            continue
        mod = importlib.import_module(m)
        if not _done and m in ENTRY:
            getattr(mod, ENTRY[m])()
        loaded.append(m)
    _done = True
    return loaded
