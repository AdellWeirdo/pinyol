#!/usr/bin/env python3
"""Rasterize a pixel TTF (e.g. Pixelify Sans) to the engine's FNT1 format, 256 cp1252 glyphs.

The font is drawn at its native pixel size (one design pixel = one pixel, 11 px for Pixelify Sans)
and then scaled by an integer factor with nearest neighbour, so letters keep the same chunky pixel
size as the world (which is drawn at 2x).

usage: ttf2fnt.py in.ttf out.fnt --px 11 --scale 2 [--weight 700] [--spacing 1]
"""
from __future__ import annotations

import argparse

from PIL import Image, ImageDraw, ImageFont


def build(ttf: str, out: str, px: int, scale: int, weight: int | None, spacing: int) -> None:
    font = ImageFont.truetype(ttf, px)
    pixelify = "Pixelify" in ttf  # its C and G nearly close at small sizes; other fonts are left alone
    if weight is not None:
        font.set_variation_by_axes([weight])
    ascent, descent = font.getmetrics()
    h = ascent + descent
    glyphs, advs = [], []
    for code in range(256):
        try:
            ch = bytes([code]).decode("cp1252")
        except UnicodeDecodeError:
            ch = "?"
        if code < 0x20:
            ch = " "
        img = Image.new("L", (px * 2, h + 2), 0)
        ImageDraw.Draw(img).text((0, 0), ch, font=font, fill=255)
        g = img.point(lambda v: 255 if v >= 128 else 0)
        if pixelify and ch in "CÇ" and g.getbbox():  # Pixelify's C nearly closes at small sizes: open its mouth
            x0, y0, x1, y1 = g.getbbox()
            mouth = (x1 - max(2, (x1 - x0) // 3), y0 + (y1 - y0) * 3 // 10, x1, y0 + (y1 - y0) * 6 // 10 + 1)
            g.paste(0, mouth)
        if pixelify and ch == "G" and g.getbbox():  # same for G, above its bar
            x0, y0, x1, y1 = g.getbbox()
            g.paste(0, (x1 - max(2, (x1 - x0) // 3), y0 + (y1 - y0) * 2 // 10, x1, y0 + (y1 - y0) * 45 // 100))
        glyphs.append(g)
        advs.append(round(font.getlength(ch)) + spacing)
    w = max(max(a for a in advs), max((g.getbbox() or (0, 0, 0, 0))[2] for g in glyphs))
    boxes = [g.getbbox() for g in glyphs if g.getbbox()]
    top, bottom = min(b[1] for b in boxes), max(b[3] for b in boxes)  # trim unused rows: tighter lines
    glyphs = [g.crop((0, top, g.width, bottom)) for g in glyphs]
    h, ascent = bottom - top, ascent - top
    cw, ch_ = w * scale, h * scale
    stride = (cw + 7) // 8
    bits = bytearray(256 * ch_ * stride)
    for code, g in enumerate(glyphs):
        big = g.crop((0, 0, w, h)).resize((cw, ch_), Image.NEAREST)
        data = big.tobytes()
        for y in range(ch_):
            for x in range(cw):
                if data[y * cw + x]:
                    bits[(code * ch_ + y) * stride + x // 8] |= 0x80 >> (x % 8)
    with open(out, "wb") as f:
        f.write(b"FNT1" + bytes([cw, ch_, ascent * scale, 0]) + bytes(min(255, a * scale) for a in advs) + bytes(bits))


if __name__ == "__main__":
    ap = argparse.ArgumentParser()
    ap.add_argument("ttf")
    ap.add_argument("out")
    ap.add_argument("--px", type=int, default=11)
    ap.add_argument("--scale", type=int, default=2)
    ap.add_argument("--weight", type=int, default=None)
    ap.add_argument("--spacing", type=int, default=0)
    a = ap.parse_args()
    build(a.ttf, a.out, a.px, a.scale, a.weight, a.spacing)
