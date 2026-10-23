"""gbakit: the Game Boy Advance art kit of Botín. Pictures are written as text with sixteen-colour palettes, as GBA art was made.

A picture is a list of strings, one per row, one character per pixel:

    .           see-through (index 0 of every palette bank)
    1 2 .. 9    colour slots 1 to 9 of the picture's palette bank
    a b .. f    colour slots 10 to 15

A bank is fifteen colours (slot 0 is always see-through). A picture is drawn with one bank; the same picture takes the colours of any
other bank (an enemy's stronger kind, a hero burning, the same tree in autumn): that is what GBA games did with palette banks.
Colours are 15-bit (5 bits a channel): the kit rounds the RGB you give.

What an artist uses:
    ART.palette(set, bank, [15 colours "#rrggbb" or (r,g,b)])   a bank of a palette set. Set "obj" is the sprites' palette; any other set
                                                                 name ("selva", "cristal"...) is the world palette of a level (its tile
                                                                 layers and scenery share it): at most 16 banks per set
    ART.sheet(sid, w, h, bank)                                   a sprite sheet of frames w x h, drawn with that bank of set "obj"
    sheet.add(name, picture [, bank])                            a frame (text rows); `bank` overrides the sheet's for that frame
    ART.meta(set, name, rows16, bank, front=None, front_bank=None, flags=())
                                                                 a 16x16 metatile of a level set: `rows16` is the ground layer (what the hero
                                                                 stands on and is behind), `front` an optional layer over the hero
    ART.scenery(name, rows, set, bank)                           a big picture (a width and height multiple of 8) for a background layer:
                                                                 the build cuts it into 8x8 tiles (one copy of each) and a tile map
    pic(), flip_h(), flip_v(), shift(), overlay(), crop(), side_by_side(), paste_rows(), recolour(), split_frames(), outline()
    preview_*()                                                  PNGs in art/ to look at
"""
from __future__ import annotations

import json
from pathlib import Path

from PIL import Image

HERE = Path(__file__).resolve().parent.parent  # examples/botin
ASSETS, ART_DIR, DATA = HERE / "assets", HERE / "art", HERE / "data"

Pic = list[list[int]]  # rows of colour slots 0..15 (0 see-through)
HEX = "0123456789abcdef"


# ------------------------------------------------------------------ parsing and editing text pictures

def pic(rows: list[str] | str, w: int | None = None, h: int | None = None) -> Pic:
    """Rows of text to a picture; `w` and `h`, if given, are checked (a row of the wrong length is the commonest bug)."""
    if isinstance(rows, str):
        rows = [r.rstrip() if False else r for r in rows.strip("\n").split("\n")]
    out: Pic = []
    for y, r in enumerate(rows):
        if w is not None and len(r) != w:
            raise ValueError(f"row {y} has {len(r)} pixels, not {w}: {r!r}")
        row = []
        for ch in r:
            if ch in ". ":
                row.append(0)
            elif ch in HEX[1:]:
                row.append(HEX.index(ch))
            else:
                raise ValueError(f"row {y}: {ch!r} is not a colour slot (1-9, a-f) or . (see-through)")
        out.append(row)
    if h is not None and len(out) != h:
        raise ValueError(f"{len(out)} rows, not {h}")
    return out


def as_pic(v, w: int | None = None, h: int | None = None) -> Pic:
    if isinstance(v, str) or (isinstance(v, list) and v and isinstance(v[0], str)):
        return pic(v, w, h)
    if h is not None and len(v) != h or w is not None and len(v[0]) != w:
        raise ValueError(f"a {len(v[0])}x{len(v)} picture where {w}x{h} is needed")
    return v


def text_of(p: Pic) -> list[str]:
    return ["".join("." if v == 0 else HEX[v] for v in row) for row in p]


def flip_h(p: Pic) -> Pic:
    return [row[::-1] for row in p]


def flip_v(p: Pic) -> Pic:
    return [row[:] for row in p[::-1]]


def blank(w: int, h: int, v: int = 0) -> Pic:
    return [[v] * w for _ in range(h)]


def shift(p: Pic, dx: int, dy: int) -> Pic:
    """The picture moved by dx, dy; what leaves is cut and what comes in is see-through."""
    h, w = len(p), len(p[0])
    out = blank(w, h)
    for y in range(h):
        for x in range(w):
            sx, sy = x - dx, y - dy
            if 0 <= sx < w and 0 <= sy < h:
                out[y][x] = p[sy][sx]
    return out


def overlay(base: Pic, top: Pic, dx: int = 0, dy: int = 0) -> Pic:
    """`top` laid over `base` at dx, dy: where `top` is see-through, `base` shows."""
    out = [row[:] for row in base]
    for y, row in enumerate(top):
        for x, v in enumerate(row):
            if v and 0 <= y + dy < len(out) and 0 <= x + dx < len(out[0]):
                out[y + dy][x + dx] = v
    return out


def crop(p: Pic, x: int, y: int, w: int, h: int) -> Pic:
    return [row[x:x + w] for row in p[y:y + h]]


def paste_rows(*parts: Pic) -> Pic:
    out: Pic = []
    for p in parts:
        out.extend(row[:] for row in p)
    return out


def side_by_side(*parts: Pic) -> Pic:
    h = len(parts[0])
    return [sum((p[y] for p in parts), []) for y in range(h)]


def recolour(p: Pic, table: dict[int, int]) -> Pic:
    """Slots changed by a table ({3: 4, 4: 5})."""
    return [[table.get(v, v) for v in row] for row in p]


def split_frames(rows: list[str] | str, fw: int, fh: int) -> list[Pic]:
    """A strip of frames drawn side by side (separated by `|` or not), cut into pictures of fw x fh; strips stacked are read row by row."""
    if isinstance(rows, str):
        rows = rows.strip("\n").split("\n")
    full = pic([r.replace("|", "") for r in rows])
    if len(full) % fh or len(full[0]) % fw:
        raise ValueError(f"a {len(full[0])}x{len(full)} strip does not split into frames {fw}x{fh}")
    return [crop(full, bx, by, fw, fh) for by in range(0, len(full), fh) for bx in range(0, len(full[0]), fw)]


def outline(p: Pic, slot: int) -> Pic:
    """A one-pixel line of `slot` round what is drawn (the picture needs a margin for it)."""
    h, w = len(p), len(p[0])
    out = [row[:] for row in p]
    for y in range(h):
        for x in range(w):
            if p[y][x] == 0 and any(0 <= x + dx < w and 0 <= y + dy < h and p[y + dy][x + dx] for dx, dy in ((1, 0), (-1, 0), (0, 1), (0, -1))):
                out[y][x] = slot
    return out


# ------------------------------------------------------------------ colours

def rgb(c) -> tuple[int, int, int]:
    """'#rrggbb' or (r, g, b), rounded to 15-bit colour (5 bits a channel)."""
    if isinstance(c, str):
        c = tuple(int(c[i:i + 2], 16) for i in (1, 3, 5))
    r, g, b = (min(31, max(0, round(v * 31 / 255))) for v in c)
    return (r * 255 // 31, g * 255 // 31, b * 255 // 31)


def rgb565(c: tuple[int, int, int]) -> int:
    r, g, b = c
    return (r >> 3) << 11 | (g >> 2) << 5 | b >> 3


# ------------------------------------------------------------------ the registry

class Sheet:
    def __init__(self, sid: str, w: int, h: int, bank: str):
        self.id, self.w, self.h, self.bank = sid, w, h, bank
        self.frames: list[tuple[str, Pic]] = []
        self.banks: dict[str, str] = {}

    def add(self, name: str, p, bank: str | None = None) -> Pic:
        p = as_pic(p, self.w, self.h)
        if any(n == name for n, _ in self.frames):
            raise ValueError(f"{self.id}.{name} twice")
        self.frames.append((name, p))
        if bank:
            self.banks[name] = bank
        return p

    def get(self, name: str) -> Pic:
        return next(p for n, p in self.frames if n == name)


class Metatile:
    def __init__(self, name, ground, front, flags, bank, front_bank):
        self.name, self.ground, self.front, self.flags, self.bank, self.front_bank = name, ground, front, tuple(flags), bank, front_bank


class Registry:
    def __init__(self):
        self.palettes: dict[str, dict[str, list[tuple[int, int, int]]]] = {}
        self.sheets: dict[str, Sheet] = {}
        self.metas: dict[str, dict[str, Metatile]] = {}
        self.sceneries: dict[str, tuple[Pic, str, str]] = {}

    def palette(self, set_: str, bank: str, colours) -> None:
        cols = [rgb(c) for c in colours]
        if len(cols) > 15:
            raise ValueError(f"palette {set_}.{bank}: {len(cols)} colours, a bank holds 15 (slot 0 is see-through)")
        banks = self.palettes.setdefault(set_, {})
        if bank in banks:
            raise ValueError(f"palette {set_}.{bank} twice")
        if len(banks) >= 16:
            raise ValueError(f"palette set {set_} has 16 banks already")
        banks[bank] = cols + [(0, 0, 0)] * (15 - len(cols))

    def bank_index(self, set_: str, bank: str) -> int:
        return list(self.palettes[set_]).index(bank)

    def sheet(self, sid: str, w: int, h: int, bank: str) -> Sheet:
        if sid in self.sheets:
            raise ValueError(f"sheet {sid} twice")
        self.sheets[sid] = Sheet(sid, w, h, bank)
        return self.sheets[sid]

    def meta(self, set_: str, name: str, ground, bank: str, front=None, front_bank: str | None = None, flags=()) -> None:
        d = self.metas.setdefault(set_, {})
        if name in d:
            raise ValueError(f"metatile {set_}.{name} twice")
        d[name] = Metatile(name, as_pic(ground, 16, 16), None if front is None else as_pic(front, 16, 16), flags, bank, front_bank or bank)

    def scenery(self, name: str, rows, set_: str, bank: str) -> None:
        p = as_pic(rows)
        if len(p) % 8 or len(p[0]) % 8:
            raise ValueError(f"scenery {name} is {len(p[0])}x{len(p)}: both must be multiples of 8")
        if name in self.sceneries:
            raise ValueError(f"scenery {name} twice")
        self.sceneries[name] = (p, set_, bank)


ART = Registry()


# ------------------------------------------------------------------ tiles and maps (what the engine reads)

def _key(p: Pic) -> bytes:
    return bytes(v for row in p for v in row)


class Tileset:
    """The 8x8 tiles of a layer, one copy of each (tile 0 is the empty one), flips folded (a mirrored tile is the same tile with a flip bit).
    `tile(p, bank)` returns the map entry: the tile's number, flips and `bank << 12`."""

    def __init__(self):
        self.tiles: list[bytes] = [bytes(64)]
        self.index: dict[bytes, int] = {bytes(64): 0}

    def tile(self, p: Pic, bank: int = 0) -> int:
        key = _key(p)
        if key in self.index:
            return self.index[key] | bank << 12
        for flags, variant in ((0x400, flip_h(p)), (0x800, flip_v(p)), (0xC00, flip_v(flip_h(p)))):
            k = _key(variant)
            if k in self.index:
                return self.index[k] | flags | bank << 12
        if len(self.tiles) >= 1024:
            raise ValueError("more than 1024 different tiles: a map holds tile numbers up to 1023")
        self.index[key] = len(self.tiles)
        self.tiles.append(key)
        return self.index[key] | bank << 12

    def meta(self, p: Pic, bank: int) -> list[int]:
        """A 16x16 picture as its four map entries (top-left, top-right, bottom-left, bottom-right)."""
        return [self.tile(crop(p, x, y, 8, 8), bank) for y in (0, 8) for x in (0, 8)]


class Layer:
    def __init__(self, w: int, h: int):
        self.w, self.h = w, h
        self.entries = [0] * (w * h)

    def put(self, tx: int, ty: int, entry: int) -> None:
        if 0 <= tx < self.w and 0 <= ty < self.h:
            self.entries[ty * self.w + tx] = entry

    def put_meta(self, mx: int, my: int, entries: list[int]) -> None:
        for i, e in enumerate(entries):
            self.put(mx * 2 + i % 2, my * 2 + i // 2, e)


def write_tilemap(aid: str, ts: Tileset, layer: Layer, palette: str) -> None:
    ASSETS.mkdir(parents=True, exist_ok=True)
    (ASSETS / f"{aid}.tiles").write_bytes(b"".join(ts.tiles))
    (ASSETS / f"{aid}.map").write_bytes(b"".join(e.to_bytes(2, "little") for e in layer.entries))
    meta = {"asset": aid, "type": "tilemap", "tiles": len(ts.tiles), "map_w": layer.w, "map_h": layer.h, "palette": palette}
    (ASSETS / f"{aid}.meta.json").write_text(json.dumps(meta, indent=2) + "\n")


def write_sheet(aid: str, frames: list[Pic], palette: str = "OBJ", ms: int = 0) -> None:
    """A sprite sheet of equal frames (the engine's .idx: one byte a pixel, 0 see-through, slots 1 to 15 + 16 * bank at draw time)."""
    w, h = len(frames[0][0]), len(frames[0])
    for i, f in enumerate(frames):
        if len(f) != h or len(f[0]) != w:
            raise ValueError(f"{aid}: frame {i} is {len(f[0])}x{len(f)}, not {w}x{h}")
    ASSETS.mkdir(parents=True, exist_ok=True)
    (ASSETS / f"{aid}.idx").write_bytes(b"".join(_key(f) for f in frames))
    meta = {"asset": aid, "type": "sprite", "format": "idx8", "w": w, "h": h, "frames": len(frames), "frame_ms": [ms] * len(frames), "palette": palette}
    (ASSETS / f"{aid}.meta.json").write_text(json.dumps(meta, indent=2) + "\n")


def write_palette(name: str, banks: list[list[tuple[int, int, int]]]) -> None:
    """A palette of banks of fifteen colours: entry 16 * bank + slot; entry 16 * bank stays see-through."""
    entries = [0] * (16 * len(banks))
    for b, cols in enumerate(banks):
        for i, c in enumerate(cols):
            entries[16 * b + 1 + i] = rgb565(c)
    ASSETS.mkdir(parents=True, exist_ok=True)
    (ASSETS / f"{name}.pal").write_bytes(b"".join(e.to_bytes(2, "little") for e in entries))


# ------------------------------------------------------------------ pictures to look at

def to_image(p: Pic, colours, scale: int = 1, back=(40, 40, 48)) -> Image.Image:
    img = Image.new("RGB", (len(p[0]) * scale, len(p) * scale), back)
    px = img.load()
    for y, row in enumerate(p):
        for x, v in enumerate(row):
            if v:
                c = colours[v - 1]
                for dy in range(scale):
                    for dx in range(scale):
                        px[x * scale + dx, y * scale + dy] = c
    return img


def contact_sheet(pics: list[tuple[Pic, list]], cols: int = 8, scale: int = 4, gap: int = 4, back=(40, 40, 48)) -> Image.Image:
    """Pictures each with its own bank's colours, side by side."""
    w, h = max(len(p[0]) for p, _ in pics), max(len(p) for p, _ in pics)
    rows = (len(pics) + cols - 1) // cols
    sheet = Image.new("RGB", (cols * (w * scale + gap) + gap, rows * (h * scale + gap) + gap), (24, 24, 30))
    for i, (p, c) in enumerate(pics):
        sheet.paste(to_image(p, c, scale, back), (gap + (i % cols) * (w * scale + gap), gap + (i // cols) * (h * scale + gap)))
    return sheet


def preview_sheet(sid: str, cols: int = 8, scale: int = 4) -> Path:
    s = ART.sheets[sid]
    items = [(p, ART.palettes["obj"][s.banks.get(n, s.bank)]) for n, p in s.frames]
    ART_DIR.mkdir(exist_ok=True)
    out = ART_DIR / f"sheet_{sid.lower()}.png"
    contact_sheet(items, cols, scale).save(out)
    return out


def preview_metas(set_: str, cols: int = 8, scale: int = 3) -> Path:
    items = []
    for m in ART.metas[set_].values():
        items.append((m.ground, ART.palettes[set_][m.bank]))
        if m.front is not None:
            items.append((m.front, ART.palettes[set_][m.front_bank]))
    ART_DIR.mkdir(exist_ok=True)
    out = ART_DIR / f"metas_{set_}.png"
    contact_sheet(items, cols, scale).save(out)
    return out


def preview_scenery(name: str, scale: int = 2) -> Path:
    p, set_, bank = ART.sceneries[name]
    ART_DIR.mkdir(exist_ok=True)
    out = ART_DIR / f"scenery_{name}.png"
    to_image(p, ART.palettes[set_][bank], scale).save(out)
    return out


# ------------------------------------------------------------------ the build

def lua_table(v, indent=0) -> str:
    pad = "  " * indent
    if isinstance(v, dict):
        items = [f'{pad}  {k if str(k).isidentifier() else "[" + repr(str(k)) + "]"} = {lua_table(x, indent + 1)}' for k, x in v.items()]
        return "{\n" + ",\n".join(items) + f"\n{pad}}}"
    if isinstance(v, (list, tuple)):
        return "{" + ", ".join(lua_table(x) for x in v) + "}"
    if isinstance(v, bool):
        return "true" if v else "false"
    if isinstance(v, str):
        return '"' + v.replace('"', '\\"') + '"'
    return str(v)


def build_common() -> dict:
    """Palettes, sprite sheets and scenery; writes data/banks.lua and data/frames.lua. Returns the bank numbers."""
    DATA.mkdir(exist_ok=True)
    banks: dict[str, dict[str, int]] = {}
    for set_, bs in ART.palettes.items():
        write_palette("OBJ" if set_ == "obj" else set_.upper(), list(bs.values()))
        banks[set_] = {name: i for i, name in enumerate(bs)}
    frames = {}
    for sid, s in ART.sheets.items():
        pics = [p for _, p in s.frames]
        for part in range(0, len(pics), 64):  # a picture holds up to 64 frames: longer sheets are written in pieces HERO, HERO_2...
            write_sheet(sid if part == 0 else f"{sid}_{part // 64 + 1}", pics[part:part + 64])
        d = {"w": s.w, "h": s.h, "n": len(s.frames), "bank": banks["obj"][s.bank], "parts": (len(s.frames) + 63) // 64}
        sb = {}
        for i, (name, _) in enumerate(s.frames):
            d[name] = i
            if name in s.banks:
                sb[name] = banks["obj"][s.banks[name]]
        if sb:
            d["banks"] = sb
        frames[sid] = d
    for name, (p, set_, bank) in ART.sceneries.items():
        ts, layer = Tileset(), Layer(len(p[0]) // 8, len(p) // 8)
        b = banks[set_][bank]
        for ty in range(layer.h):
            for tx in range(layer.w):
                layer.put(tx, ty, ts.tile(crop(p, tx * 8, ty * 8, 8, 8), b))
        write_tilemap(name.upper(), ts, layer, set_.upper())
    (DATA / "banks.lua").write_text("-- made by gen/build.py: palette bank numbers by set and name\nreturn " + lua_table(banks) + "\n")
    (DATA / "frames.lua").write_text("-- made by gen/build.py: sprite sheets and their frame numbers\nreturn " + lua_table(frames) + "\n")
    return banks
