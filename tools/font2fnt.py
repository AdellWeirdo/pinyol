# /// script
# requires-python = ">=3.10"
# dependencies = ["pillow>=10.1", "fonttools>=4"]
# ///
"""Any font to the engine's FNT1 format (docs/game-format.md, 256 cp1252 glyphs, 1 bit): a game's own letters.

    uv run tools/font2fnt.py SOURCE out.fnt [--px N] [--scale K] [--spacing S] [--weight W] [--cell WxH] [--first C]
    uv run tools/font2fnt.py --list                     the fonts that come with pinyol (third_party/fonts)
    uv run tools/font2fnt.py --catalog                  the packs: a title, body and small font for each console's look
    uv run tools/font2fnt.py --pack NAME GAME           NAME's three fonts made into GAME/fonts/NAME_title.fnt, _body, _small
    uv run tools/font2fnt.py --sheet out.png [NAME]     a picture of every pack (or one), to choose from

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
import json
import re
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
            found[re.sub(r"\[.*\]", "", f.stem).lower().replace("-regular", "")] = f
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


def from_ttf(ttf: str, px: float, weight: int | None, spacing: int, axes: list[float] | None = None):
    font = ImageFont.truetype(ttf, px)
    pixelify = "Pixelify" in ttf  # its C and G nearly close at small sizes; other fonts are left alone
    if axes is not None:  # a variable font with several axes: a value for each, in the order the font lists them
        font.set_variation_by_axes(axes)
    elif weight is not None:
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
    advs[32] = max(advs[32], round(px * 0.3))  # some display faces set the word space too tight at small sizes
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
          cell: tuple[int, int] | None = None, first: int = 32, axes: list[float] | None = None) -> None:
    lib = library()
    if not Path(src).exists() and src.lower() in lib:
        src = str(lib[src.lower()])
    ext = Path(src).suffix.lower()
    if ext in (".ttf", ".otf"):
        glyphs, advs, ascent = from_ttf(src, px or native_px(src), weight, spacing, axes)
    elif ext == ".bdf":
        glyphs, advs, ascent = from_bdf(src, spacing)
    elif ext == ".png":
        glyphs, advs, ascent = from_png(src, cell, first, spacing)
    else:
        sys.exit(f"{src}: not a font file (.ttf .otf .bdf .png) nor a font in --list")
    pack(glyphs, advs, ascent, scale, out)


CATALOG = ROOT / "third_party" / "fonts" / "catalog.json"
ROLES = ("title", "body", "small")


def catalog() -> dict:
    """third_party/fonts/catalog.json: "fonts" (id: file, name, feel) and "packs" (id: name, feel, roles), each role a
    font id with optional px, scale, weight, axes, spacing."""
    return json.loads(CATALOG.read_text(encoding="utf-8"))


def role_font(cat: dict, spec: dict) -> tuple[str, dict]:
    """The font file and the build options of one role of a pack."""
    f = cat["fonts"][spec["font"]]
    path = CATALOG.parent / f["file"]
    return str(path), {"px": spec.get("px"), "scale": spec.get("scale", 2), "weight": spec.get("weight"),
                       "spacing": spec.get("spacing", 0), "axes": spec.get("axes")}


def make_pack(name: str, game: str, prefix: str | None = None) -> list[str]:
    """Pack `name`'s title, body and small fonts, made into game/fonts/<prefix>_<role>.fnt (the file names are the pack's,
    not the fonts': several of the fonts keep their names reserved under the licence, and what is made from them may not
    carry those names). Returns the names to give text()'s font."""
    cat = catalog()
    if name not in cat["packs"]:
        sys.exit(f"no pack \"{name}\": --catalog lists them")
    out = Path(game) / "fonts"
    out.mkdir(parents=True, exist_ok=True)
    made = []
    for role in ROLES:
        path, o = role_font(cat, cat["packs"][name]["roles"][role])
        fnt = f"{prefix or name}_{role}"
        build(path, str(out / (fnt + ".fnt")), o["px"], o["scale"], o["weight"], o["spacing"], None, 32, o["axes"])
        made.append(fnt)
    return made


def reserved_name(font_file: str) -> str | None:
    """The Reserved Font Name in the OFL.txt beside a font file, if its copyright line has one."""
    ofl = (CATALOG.parent / font_file).parent / "OFL.txt"
    if not ofl.exists():
        return None
    head = ofl.read_text(encoding="utf-8", errors="replace").split("This Font Software is licensed")[0]
    m = re.search(r"Reserved Font Names?:?\s*(.+?)(?:\)|\.|\n\n|$)", " ".join(head.split()), re.I)
    return m.group(1).strip(" \"'.,") if m else None


def markdown(path: str) -> None:
    """docs/fonts.md: the packs and the fonts, from catalog.json and the OFL.txt files."""
    cat = catalog()
    out = ["<!-- made by `tools/font2fnt.py --markdown docs/fonts.md`: edit third_party/fonts/catalog.json, not this -->",
           "# Fonts for every look", "",
           "Each console's games had their own letters, and those are not ours to ship (Nintendo's, Sony's and Sega's fonts "
           "are theirs). What pinyol carries instead are free fonts, all under the SIL Open Font License, that give the "
           "same *feel*, grouped into **packs**: a `title`, a `body` and a `small` font for each look. Pick the pack of "
           "the console your game is made for (docs/art.md, \"Choose a look\") and make its fonts into your game:", "",
           "```sh", "uv run tools/font2fnt.py --pack snes games/mygame     # fonts/snes_title.fnt, snes_body.fnt, snes_small.fnt",
           "```", "",
           "```lua", 'text("PUSH START", 240, 60, {font = "snes_title", align = "center", color = 0xFFFFFF})',
           'text("Hamburgefonstiv", 20, 140, {font = "snes_body"})', "```", "",
           "`uv run tools/font2fnt.py --catalog` lists the packs, `--sheet out.png [pack]` draws them. A game can have 16 fonts "
           "of its own besides the four every game has, so mix packs freely (`--prefix` renames a pack's files). Letters are "
           "the 256 of Windows-1252: Spanish, Catalan, French, German, Portuguese, Italian and the Nordic languages, not "
           "Japanese or Cyrillic. Fonts with an `*` keep a Reserved Font Name: what is made from them (your `.fnt`) must not "
           "be called by it, so the packs name their files by pack (`snes_title`), never by font.", "",
           "![Every pack](media/fonts.png)", "", "## Packs", "",
           "| Pack | Look | Title | Body | Small |", "|---|---|---|---|---|"]
    def nm(role_spec):
        f = cat["fonts"][role_spec["font"]]
        return f["name"] + ("*" if reserved_name(f["file"]) else "")
    for k, pk in cat["packs"].items():
        out.append(f"| `{k}` | **{pk['name']}**: {pk['feel']} | " + " | ".join(nm(pk["roles"][r]) for r in ROLES) + " |")
    out += ["", "## The fonts", "", "| Font | Feel | Folder |", "|---|---|---|"]
    for k, f in cat["fonts"].items():
        out.append(f"| {f['name']}{'*' if reserved_name(f['file']) else ''} | {f['feel']} | `third_party/fonts/{f['file'].split('/')[0]}` |")
    out += ["", "Each folder holds the font's `OFL.txt`. The fonts are free to use, change and share, also in games that are "
            "sold, as long as the font is not sold on its own; `THIRD_PARTY_NOTICES.md` carries their notices.", ""]
    Path(path).write_text("\n".join(out), encoding="utf-8")


def sheet(path: str, only: str | None) -> None:
    """A picture of the packs: each role's sample text drawn from the very glyphs the .fnt would hold, at the size they
    have on the 480x320 screen, beside the pack's name."""
    cat = catalog()
    names = [only] if only else list(cat["packs"])
    lines = []
    for n in names:
        pk = cat["packs"][n]
        row = []
        for role in ROLES:
            fpath, o = role_font(cat, pk["roles"][role])
            px = o["px"] or native_px(fpath)
            glyphs, advs, _ = from_ttf(fpath, px, o["weight"], o["spacing"], o["axes"])
            text = {"title": "Hamburg 0123", "body": "Hamburgefonstiv ñ¿", "small": "small text 0123 ñ¿"}[role]
            codes = {ch: i for i, (c, ch) in enumerate(chars())}
            k = o["scale"]
            w = sum(advs[codes[c]] for c in text) * k + 4
            h = max(g.height for g in glyphs) * k + 2
            img = Image.new("RGB", (w, h), (24, 22, 34))
            x = 0
            for c in text:
                g = glyphs[codes[c]].resize((glyphs[codes[c]].width * k, glyphs[codes[c]].height * k), Image.NEAREST)
                img.paste((240, 224, 168), (x, 0), g)
                x += advs[codes[c]] * k
            row.append(img)
        lines.append((pk["name"], pk["feel"], row))
    label_w, gap = 230, 14
    width = max(label_w + sum(i.width + gap for i in row) for _, _, row in lines) + 8
    height = sum(max(i.height for i in row) + 16 for _, _, row in lines) + 8
    pic = Image.new("RGB", (width, height), (24, 22, 34))
    d = ImageDraw.Draw(pic)
    y = 4
    for title, feel, row in lines:
        d.text((6, y + 2), title, fill=(150, 200, 255))
        d.text((6, y + 14), feel[:38], fill=(110, 120, 150))
        x = label_w
        for img in row:
            pic.paste(img, (x, y))
            x += img.width + gap
        y += max(i.height for i in row) + 16
    pic.save(path)


def main() -> None:
    ap = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    ap.add_argument("src", nargs="?")
    ap.add_argument("out", nargs="?")
    ap.add_argument("--list", action="store_true")
    ap.add_argument("--catalog", action="store_true", help="the packs and the fonts in each")
    ap.add_argument("--pack", metavar="NAME", help="make NAME's three fonts into SRC/fonts (SRC is the game's folder)")
    ap.add_argument("--prefix", help="--pack: the fonts' file names (default: the pack's)")
    ap.add_argument("--sheet", metavar="FILE.png", help="draw a picture of the packs (SRC: one pack)")
    ap.add_argument("--markdown", metavar="FILE.md", help="write the catalog as docs/fonts.md")
    ap.add_argument("--axes", help="a variable font's axes, comma separated, in the order it lists them")
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
    if a.catalog:
        cat = catalog()
        for n, pk in cat["packs"].items():
            fonts = ", ".join(cat["fonts"][pk["roles"][r]["font"]]["name"] for r in ROLES)
            print(f"{n:18} {pk['name']:34} {fonts}")
        return
    if a.sheet:
        sheet(a.sheet, a.src)
        return
    if a.markdown:
        markdown(a.markdown)
        return
    if a.pack:
        if not a.src:
            ap.error("--pack NAME GAME")
        print("made", ", ".join(make_pack(a.pack, a.src, a.prefix)), "in", Path(a.src) / "fonts")
        return
    if not a.src or not a.out:
        ap.error("SOURCE and out.fnt, or --list, --catalog, --pack, --sheet")
    cell = tuple(int(v) for v in a.cell.lower().split("x")) if a.cell else None
    axes = [float(v) for v in a.axes.split(",")] if a.axes else None
    build(a.src, a.out, a.px, a.scale, a.weight, a.spacing, cell, a.first, axes)


if __name__ == "__main__":
    main()
