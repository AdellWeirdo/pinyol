"""Socavón's art, drawn in code in the ZX Spectrum way. Run: python3 gen/art.py

  art_blocks.py   the 8x8 blocks (two colours each; the game picks ink and paper per room)
  art_miner.py    the miner, 16x16
  art_enemies.py  the guardians, 16x16
  art_fx.py       8x8 effects (key twinkle, dust)
  art_preview.py  art/zx_preview.png: a room in Spectrum colours with the sprites on it, to judge in context
"""
from __future__ import annotations

import sys
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent))
import art_blocks  # noqa: E402
import art_enemies  # noqa: E402
import art_fx  # noqa: E402
import art_miner  # noqa: E402
import art_preview  # noqa: E402
from zxkit import ART, build  # noqa: E402

art_blocks.register(ART)
art_miner.register(ART)
art_enemies.register(ART)
art_fx.register(ART)

if __name__ == "__main__":
    build()
    art_preview.make(ART)
