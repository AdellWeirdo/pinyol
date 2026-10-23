"""COLOR: the palette mode that colours the game the way a Game Boy Color coloured a game, a bank at a time.

Every picture of the game is drawn in four tones; the bank of a tile or a sprite says what kind of thing it is (art brief),
and here each bank is four colours, lightest to darkest: so the grass is green, the water blue, the roofs red, and the
hero's straw hat yellow, from the same pictures. The tones keep their order (tone 0 the lightest), so the picture reads
as well as it does in four greens.
"""
from __future__ import annotations

BG = [
    [(232, 248, 176), (176, 216, 96), (72, 136, 64), (24, 56, 40)],      # 0 grass and ground
    [(255, 240, 200), (232, 200, 136), (168, 120, 72), (72, 40, 24)],    # 1 sand and dirt
    [(216, 240, 255), (128, 192, 248), (56, 112, 200), (16, 40, 96)],    # 2 water
    [(200, 232, 144), (120, 184, 88), (40, 104, 64), (8, 40, 32)],       # 3 trees and leaves
    [(255, 236, 208), (216, 168, 112), (144, 88, 56), (56, 32, 24)],     # 4 walls and wood
    [(255, 224, 208), (232, 128, 104), (176, 56, 56), (72, 16, 32)],     # 5 roofs and red things
    [(232, 232, 240), (176, 176, 200), (96, 96, 128), (32, 32, 56)],     # 6 stone and rock
    [(255, 240, 248), (248, 176, 208), (200, 72, 136), (80, 24, 64)],    # 7 flowers and blossom
]
OBJ = [
    [(255, 244, 224), (240, 212, 128), (56, 128, 72), (32, 24, 24)],     # 0 the hero: straw hat, green tunic
    [(255, 240, 224), (240, 176, 136), (120, 88, 160), (40, 24, 48)],    # 1 villagers A
    [(255, 240, 224), (232, 200, 120), (80, 144, 176), (40, 32, 24)],    # 2 villagers B
    [(232, 255, 200), (144, 216, 96), (56, 128, 56), (16, 48, 24)],      # 3 green pests
    [(255, 236, 200), (248, 176, 88), (200, 72, 40), (64, 24, 16)],      # 4 orange and red pests
    [(255, 255, 224), (255, 224, 96), (216, 144, 32), (80, 48, 16)],     # 5 items and gold
    [(255, 255, 255), (255, 248, 176), (248, 176, 96), (120, 64, 48)],   # 6 effects
    [(240, 224, 208), (176, 144, 120), (104, 72, 80), (32, 16, 24)],     # 7 bosses
]


def mode() -> dict:
    return {"name": "COLOR", "bg": BG, "obj": OBJ}
