# /// script
# requires-python = ">=3.10"
# dependencies = ["pillow>=10.1", "fonttools>=4"]
# ///
"""Any font to the engine's FNT1 format (docs/game-format.md, 256 cp1252 glyphs, 1 bit): a game's own letters.

    uv run tools/font2fnt.py SOURCE out.fnt [--px N] [--scale K] [--spacing S] [--weight W] [--cell WxH] [--first C]
    uv run tools/font2fnt.py --list                     the fonts that come with np2d (third_party/fonts)

SOURCE is a .ttf/.otf file, a .bdf file, a .png sheet, or the name of a font in the list.
- TTF/OTF: drawn at --px pixels. Without --px, the font's own pixel size is found (the smallest at which a pixel
  font's squares land on whole pixels, so its letters stay crisp).
- BDF: the bitmaps as they are (X11 and u8g2 fonts, Cozette, Spleen...).
- PNG: a grid of glyphs, 16 a row from character --first (32 by default), each --cell big (default: a square, the
  sheet's width / 16). Ink is anything neither transparent nor the colour of the top-left pixel. A glyph is as
  wide as its ink plus one pixel, or, if it has magenta (#FF00FF) on its right as GB Studio sheets do, up to there.
Each pixel then becomes --scale x --scale (default 2: the size of the world's pixels on the 480x320 screen).
"""
from __future__ import annotations

import argparse
import sys
from pathlib import Path

from PIL import Image, ImageDraw, ImageFont

ROOT = Path(__file__).resolve().parent.parent
LIBRARY = [ROOT / "third_party" / "pixelify", *sorted((ROOT / "third_party" / "fonts").glob("*"))]
SAMPLE = "Hamburgefonstiv 0123 AÑÇÀ"


def chars():
    """The 256 characters of cp1252 (undefined codes and controls as '?' and ' ')."""
    for code in range(256):
        try:
            ch = bytes([code]).decode("cp1252")
        except UnicodeDecodeError:
            ch = "?"
        yield code, " " if code < 0x20 else ch


def library() -> dict[str, Path]:
    found = {}
    for d in LIBRARY:
        for f in sorted(d.glob("*.[ot]tf")):
            found[f.stem.lower().replace("-regular", "").replace("[wght]", "")] = f
    return found


def grid_px(path: str) -> float | None:
    """A pixel font drawn on a grid: its square's size in font units divides every point of its outlines, and the
    em over that size is the pixel size at which one square is one pixel (fractional for some fonts)."""
    try:
        from math import gcd

        from fontTools.pens.recordingPen import DecomposingRecordingPen
        from fontTools.ttLib import TTFont
    except ImportError:
        return None
    font = TTFont(path)
    cmap, glyphs, unit = font.getBestCmap(), font.getGlyphSet(), 0
    for ch in SAMPLE:
        if ord(ch) in cmap:
            pen = DecomposingRecordingPen(glyphs)
            glyphs[cmap[ord(ch)]].draw(pen)
            for _, points in pen.value:
                for point in points:
                    for v in point:
                        unit = gcd(unit, int(round(v)))
    px = font["head"].unitsPerEm / unit if unit else 0
    return px if 4 <= px <= 40 else None


def native_px(path: str) -> float:
    """The size at which a pixel font's squares land on whole pixels: from its grid, else the smallest size at which
    almost nothing comes out grey, else 16."""
    px = grid_px(path)
    if px:
        return px
    for px in range(5, 49):
        font = ImageFont.truetype(path, px)
        img = Image.new("L", (px * len(SAMPLE), px * 4), 0)
        ImageDraw.Draw(img).text((0, px * 2), SAMPLE, font=font, fill=255, anchor="ls")
        hist = img.histogram()
        ink = sum(hist[1:])
        if ink and sum(hist[32:224]) / ink < 0.03:
            return px
    return 16


def from_ttf(ttf: str, px: float, weight: int | None, spacing: int):
    font = ImageFont.truetype(ttf, px)
    pixelify = "Pixelify" in ttf  # its C and G nearly close at small sizes; other fonts are left alone
    if weight is not None:
        font.set_variation_by_axes([weight])
    ascent, descent = font.getmetrics()
    h = ascent + descent
    glyphs, advs = [], []
    for code, ch in chars():
        img = Image.new("L", (int(px * 2) + 2, h + 2), 0)
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
    return glyphs, advs, ascent


def from_bdf(path: str, spacing: int):
    """STARTCHAR blocks: ENCODING (Unicode or Latin-1), DWIDTH, BBX w h xoff yoff, BITMAP rows in hex."""
    ascent = descent = 0
    found, cur, rows = {}, None, None
    for line in Path(path).read_text(encoding="latin-1").splitlines():
        key, _, rest = line.partition(" ")
        if key == "FONT_ASCENT":
            ascent = int(rest)
        elif key == "FONT_DESCENT":
            descent = int(rest)
        elif key == "STARTCHAR":
            cur, rows = {"enc": -1, "adv": 0, "bbx": (0, 0, 0, 0)}, None
        elif cur is not None and key == "ENCODING":
            cur["enc"] = int(rest.split()[0])
        elif cur is not None and key == "DWIDTH":
            cur["adv"] = int(rest.split()[0])
        elif cur is not None and key == "BBX":
            cur["bbx"] = tuple(int(v) for v in rest.split()[:4])
        elif cur is not None and key == "BITMAP":
            rows = []
        elif cur is not None and key == "ENDCHAR":
            cur["rows"] = rows or []
            found[cur["enc"]] = cur
            cur, rows = None, None
        elif rows is not None and line.strip():
            rows.append(int(line.strip(), 16))
    if not found:
        sys.exit(f"{path}: no glyphs (not a BDF font?)")
    h = ascent + descent or max(c["bbx"][1] for c in found.values())
    wide = max(max(c["bbx"][0] + max(c["bbx"][2], 0) for c in found.values()), max(c["adv"] for c in found.values()))
    glyphs, advs = [], []
    for code, ch in chars():
        g = Image.new("L", (wide + 1, h + 2), 0)
        c = found.get(ord(ch))
        if c:
            w, gh, xo, yo = c["bbx"]
            nbytes = (w + 7) // 8
            for j, bits in enumerate(c["rows"][:gh]):
                for i in range(w):
                    if bits & (1 << (nbytes * 8 - 1 - i)):
                        x, y = xo + i, ascent - yo - gh + j
                        if 0 <= x < g.width and 0 <= y < g.height:
                            g.putpixel((x, y), 255)
        glyphs.append(g)
        advs.append((c["adv"] if c else wide // 2) + spacing)
    return glyphs, advs, ascent


def from_png(path: str, cell: tuple[int, int] | None, first: int, spacing: int):
    sheet = Image.open(path).convert("RGBA")
    cw, ch = cell or (sheet.width // 16, sheet.width // 16)
    bg = sheet.getpixel((0, 0))
    glyphs, advs = [], []
    for code, _ in chars():
        k = code - first
        g = Image.new("L", (cw + 1, ch + 2), 0)
        if k < 0 or (k // 16 + 1) * ch > sheet.height:
            glyphs.append(g)
            advs.append(cw // 2 + spacing)
            continue
        box = sheet.crop((k % 16 * cw, k // 16 * ch, k % 16 * cw + cw, k // 16 * ch + ch))
        px = box.load()
        stop = cw  # a magenta column ends the glyph (GB Studio's variable width)
        for x in range(cw):
            if any(px[x, y][:3] == (255, 0, 255) and px[x, y][3] for y in range(ch)):
                stop = x
                break
        ink = [(x, y) for y in range(ch) for x in range(stop)
               if px[x, y][3] >= 128 and px[x, y] != bg and px[x, y][:3] != (255, 0, 255)]
        for x, y in ink:
            g.putpixel((x, y), 255)
        if stop < cw:
            adv = stop
        else:
            adv = (max(x for x, _ in ink) + 2) if ink else cw // 2
        glyphs.append(g)
        advs.append(adv + spacing)
    return glyphs, advs, ch


def pack(glyphs, advs, ascent: int, scale: int, out: str) -> None:
    """Rows nobody uses trimmed, each pixel scale x scale, written as FNT1."""
    w = max(max(a for a in advs), max((g.getbbox() or (0, 0, 0, 0))[2] for g in glyphs))
    boxes = [g.getbbox() for g in glyphs if g.getbbox()]
    if not boxes:
        sys.exit("no ink in any glyph")
    top, bottom = min(b[1] for b in boxes), max(b[3] for b in boxes)  # trim unused rows: tighter lines
    glyphs = [g.crop((0, top, g.width, bottom)) for g in glyphs]
    h, ascent = bottom - top, ascent - top
    cw, ch_ = w * scale, h * scale
    if cw > 255 or ch_ > 255:
        sys.exit(f"glyphs of {cw}x{ch_} pixels: the format keeps them under 256 (a smaller --scale or --px)")
    if cw > 64 or ch_ > 64:
        print(f"note: {cw}x{ch_} pixel glyphs; text() styles (outline, shadow, scale) need 64x64 or less", file=sys.stderr)
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
        f.write(b"FNT1" + bytes([cw, ch_, max(0, ascent) * scale, 0]) +
                bytes(max(0, min(255, a * scale)) for a in advs) + bytes(bits))


def build(src: str, out: str, px: float | None = None, scale: int = 2, weight: int | None = None, spacing: int = 0,
          cell: tuple[int, int] | None = None, first: int = 32) -> None:
    lib = library()
    if not Path(src).exists() and src.lower() in lib:
        src = str(lib[src.lower()])
    ext = Path(src).suffix.lower()
    if ext in (".ttf", ".otf"):
        glyphs, advs, ascent = from_ttf(src, px or native_px(src), weight, spacing)
    elif ext == ".bdf":
        glyphs, advs, ascent = from_bdf(src, spacing)
    elif ext == ".png":
        glyphs, advs, ascent = from_png(src, cell, first, spacing)
    else:
        sys.exit(f"{src}: not a font file (.ttf .otf .bdf .png) nor a font in --list")
    pack(glyphs, advs, ascent, scale, out)


def main() -> None:
    ap = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    ap.add_argument("src", nargs="?")
    ap.add_argument("out", nargs="?")
    ap.add_argument("--list", action="store_true")
    ap.add_argument("--px", type=float)
    ap.add_argument("--scale", type=int, default=2)
    ap.add_argument("--weight", type=int)
    ap.add_argument("--spacing", type=int, default=0)
    ap.add_argument("--cell", help="WxH, a PNG sheet's glyph cell")
    ap.add_argument("--first", type=int, default=32)
    a = ap.parse_args()
    if a.list:
        for name, path in library().items():
            print(f"{name:24} {native_px(str(path)):6.2f} px   {path.relative_to(ROOT)}")
        return
    if not a.src or not a.out:
        ap.error("SOURCE and out.fnt, or --list")
    cell = tuple(int(v) for v in a.cell.lower().split("x")) if a.cell else None
    build(a.src, a.out, a.px, a.scale, a.weight, a.spacing, cell, a.first)


if __name__ == "__main__":
    main()
