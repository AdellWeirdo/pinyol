"""The palettes of Cerezo: four tones each, as the Game Boy's screens and its colourisers gave them.

A *mode* is what the player picks (C in the pause menu); each has eight BG banks and eight sprite banks of four tones.
In the monochrome modes every bank holds the same four tones, so a picture is the same whatever bank it is drawn in;
in COLOR each bank is its own set, the way a Game Boy Color coloured a game: the grass one green, the water one blue.
"""
from __future__ import annotations

Tones = list[tuple[int, int, int]]


def hexc(v: int) -> tuple[int, int, int]:
    return (v >> 16) & 255, (v >> 8) & 255, v & 255


def mono(*cols: int) -> Tones:
    return [hexc(c) for c in cols]


DMG = mono(0x9BBC0F, 0x8BAC0F, 0x306230, 0x0F380F)
POCKET = mono(0xE8E8E0, 0xA8A8A0, 0x585850, 0x181810)
SGB = mono(0xF8E8C8, 0xD89048, 0xA82820, 0x301850)
MARRON = mono(0xFFF8E0, 0xF0A860, 0x844018, 0x200800)
AZUL = mono(0xF0F8FF, 0x70A8F8, 0x2040C0, 0x000818)

# (name, tones) of the monochrome modes, in the order the player meets them
MONO_MODES = [("DMG", DMG), ("POCKET", POCKET), ("SGB", SGB), ("MARRON", MARRON), ("AZUL", AZUL)]


def modes() -> list[dict]:
    """[{name, bg: [8 banks], obj: [8 banks]}]: what data/palettes.lua says and WORLD.pal / OBJ.pal start from."""
    out = []
    for name, tones in MONO_MODES:
        out.append({"name": name, "bg": [tones] * 8, "obj": [tones] * 8})
    try:
        import palettes_color  # the colour banks, once the art says what each bank is for
        out.append(palettes_color.mode())
    except ImportError:
        pass
    return out
