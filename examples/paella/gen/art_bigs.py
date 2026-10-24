"""Paella de Combate: only boss_fx (the beam shot and its charge) is still drawn by code; the boss itself is gpt-image art (gpt_jobs.py, ENEMIES["boss"]).
The rest of this builds the old parts of the boss, which nothing uses any more. The big pieces. Builds art/boss_*.* (the tractor is gpt-image art: gpt_jobs.py) (El Gran Gaviotrón)
plus their previews and art/boss_preview.png. Run: python3 gen/art_bigs.py

Modules: art_bigs_kit (cel-shaded shape renderer, palette, export), art_bigs_boss (+_anim).
"""
import sys
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent))

import art_bigs_boss_anim  # noqa: E402

if __name__ == "__main__":
    art_bigs_boss_anim.build()
