"""Tumba's art, drawn in code in PICO-8's sixteen colours. Run: python3 gen/art.py  (--preview: only the preview PNGs)"""
from __future__ import annotations

import sys
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent))
from p8kit import ART, build  # noqa: E402

import art_decor  # noqa: E402
import art_logo  # noqa: E402
import art_objects  # noqa: E402
import art_sprites  # noqa: E402
import art_walls  # noqa: E402

art_walls.register(ART)
art_objects.register(ART)
art_sprites.register(ART)
art_decor.register(ART)
art_logo.register(ART)

if __name__ == "__main__":
    import art_preview
    if "--preview" not in sys.argv:
        build()
    art_preview.save()
    art_preview.save_sheets()
    art_preview.save_logo()
    art_preview.save_screen()
