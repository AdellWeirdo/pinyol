"""gbart: the Game Boy art kit of Cerezo. Pictures are written as text in four tones and become the engine's assets.

A picture is a list of strings, one per row. Each character is one pixel:

    0 1 2 3     the four tones, 0 the lightest (the paper) to 3 the darkest (the ink)
    .           nothing: see-through (sprites, and the front layer of the map)

Everything an artist needs lives here: `pic()` checks and parses rows, `flip_h` / `flip_v` / `shift` / `overlay`
build one picture from another, `Tileset` cuts 16x16 metatiles into the 8x8 tiles a map is made of (one copy of
each, as the console's video memory held them), `Layer` is a map of those tiles, and the `write_*` functions write
what the engine reads (`.tiles`, `.map`, `.idx`, `.pal` and their `.meta.json`). `preview*` draw PNGs to look at.

Tone indices in the files are 1 to 4 (0 is see-through), and a palette *bank* adds 16 to each of them: the same
picture takes the colours of any bank, as a Game Boy Color's attributes did. A bank is four colours, so a game in four
greens has the same four in every bank and a game in colour has a bank for the grass, another for the water...
"""
from __future__ import annotations

import json
from pathlib import Path

from PIL import Image

HERE = Path(__file__).resolve().parent.parent  # examples/cerezo
ASSETS, ART_DIR = HERE / "assets", HERE / "art"

# the first palette, lightest to darkest: the Game Boy's own greens (docs/art.md: a game draws in tones, not colours)
DMG = [(155, 188, 15), (139, 172, 15), (48, 98, 48), (15, 56, 15)]

Pic = list[list[int]]  # rows of tones 0..3, -1 where see-through


# ------------------------------------------------------------------ parsing and editing text pictures

def pic(rows: list[str] | str, w: int | None = None, h: int | None = None) -> Pic:
    """Rows of text to a picture; `w` and `h`, if given, are checked (a row of the wrong length is the commonest bug)."""
    if isinstance(rows, str):
        rows = [r for r in rows.strip("\n").split("\n")]
    out: Pic = []
    for y, r in enumerate(rows):
        if w is not None and len(r) != w:
            raise ValueError(f"row {y} has {len(r)} pixels, not {w}: {r!r}")
        row = []
        for ch in r:
            if ch in "0123":
                row.append(int(ch))
            elif ch in ". ":
                row.append(-1)
            else:
                raise ValueError(f"row {y}: {ch!r} is not a tone (0-3) or . (see-through)")
        out.append(row)
    if h is not None and len(out) != h:
        raise ValueError(f"{len(out)} rows, not {h}")
    return out


def as_pic(v, w: int | None = None, h: int | None = None) -> Pic:
    """Text rows or a picture already parsed, checked to be w x h."""
    if isinstance(v, str) or (isinstance(v, list) and v and isinstance(v[0], str)):
        return pic(v, w, h)
    if h is not None and len(v) != h or w is not None and len(v[0]) != w:
        raise ValueError(f"a {len(v[0])}x{len(v)} picture where {w}x{h} is needed")
    return v


def text_of(p: Pic) -> list[str]:
    return ["".join("." if v < 0 else str(v) for v in row) for row in p]


def flip_h(p: Pic) -> Pic:
    return [row[::-1] for row in p]


def flip_v(p: Pic) -> Pic:
    return [row[:] for row in p[::-1]]


def blank(w: int, h: int, v: int = -1) -> Pic:
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
            if v >= 0 and 0 <= y + dy < len(out) and 0 <= x + dx < len(out[0]):
                out[y + dy][x + dx] = v
    return out


def crop(p: Pic, x: int, y: int, w: int, h: int) -> Pic:
    return [row[x:x + w] for row in p[y:y + h]]


def paste_rows(*parts: Pic) -> Pic:
    """Pictures of one width stacked top to bottom."""
    out: Pic = []
    for p in parts:
        out.extend(row[:] for row in p)
    return out


def side_by_side(*parts: Pic) -> Pic:
    h = len(parts[0])
    return [sum((p[y] for p in parts), []) for y in range(h)]


def recolour(p: Pic, table: dict[int, int]) -> Pic:
    """Tones changed by a table ({1: 2, 2: 3}): a stronger kind of an enemy, the same tree in autumn."""
    return [[table.get(v, v) for v in row] for row in p]


def split_frames(rows: list[str] | str, fw: int, fh: int) -> list[Pic]:
    """A strip of frames drawn side by side, separated by `|` or not, cut into pictures of fw x fh."""
    if isinstance(rows, str):
        rows = rows.strip("\n").split("\n")
    rows = [r.replace("|", "") for r in rows]
    full = pic(rows)
    if len(full) % fh:
        raise ValueError(f"{len(full)} rows do not split into frames {fh} tall")
    out = []
    for by in range(0, len(full), fh):
        for bx in range(0, len(full[0]), fw):
            out.append(crop(full, bx, by, fw, fh))
    return out


# ------------------------------------------------------------------ painting with materials

class Mat:
    """A material for `paint`: a letter in the rows stands for it. `base` is its tone; with `shade`, where it is at
    least two pixels thick its top and left edge take `hi` and its bottom and right edge `lo` (light from the top
    left, as the whole game is lit), which gives a round bush or a hat its volume without drawing every pixel."""

    def __init__(self, base: int, hi: int | None = None, lo: int | None = None, shade: bool = True):
        self.base, self.hi, self.lo, self.shade = base, hi, lo, shade


def paint(rows: list[str] | str, mats: dict[str, Mat], outline: int | None = 3) -> Pic:
    """Rows where a digit is a tone and any letter a material, painted: materials shaded at their edges, and (with
    `outline`) a one-pixel line of that tone round everything that is drawn, so the picture grows by a pixel each way
    (draw it with a margin). Digits are never changed: eyes, highlights and details stay as written."""
    if isinstance(rows, str):
        rows = rows.strip("\n").split("\n")
    h, w = len(rows), len(rows[0])
    grid = [[rows[y][x] for x in range(w)] for y in range(h)]

    def at(x, y):
        return grid[y][x] if 0 <= x < w and 0 <= y < h else "."

    out = blank(w, h)
    for y in range(h):
        for x in range(w):
            ch = grid[y][x]
            if ch in "0123":
                out[y][x] = int(ch)
            elif ch in ". ":
                continue
            else:
                m = mats[ch]
                v = m.base
                if m.shade:
                    top, left, bottom, right = at(x, y - 1) != ch, at(x - 1, y) != ch, at(x, y + 1) != ch, at(x + 1, y) != ch
                    if m.lo is not None and (bottom and not top or right and not left):
                        v = m.lo
                    elif m.hi is not None and (top and not bottom or left and not right):
                        v = m.hi
                out[y][x] = v
    if outline is not None:
        edge = []
        for y in range(h):
            for x in range(w):
                if out[y][x] < 0 and any(0 <= x + dx < w and 0 <= y + dy < h and out[y + dy][x + dx] >= 0
                                         for dx, dy in ((1, 0), (-1, 0), (0, 1), (0, -1))):
                    edge.append((x, y))
        for x, y in edge:
            out[y][x] = outline
    return out


def outline(p: Pic, tone: int = 3) -> Pic:
    """A one-pixel line of `tone` round what is drawn (the picture needs a margin for it)."""
    return paint(text_of(p), {}, tone)


def dither(w: int, h: int, a: int, b: int, phase: int = 0) -> Pic:
    """A checkerboard of two tones: the Game Boy's way of making a fifth tone."""
    return [[a if (x + y + phase) % 2 == 0 else b for x in range(w)] for y in range(h)]


# ------------------------------------------------------------------ what a game's art is made of

class Sheet:
    """A sprite sheet in the making: `add(name, picture)` gives each frame a name and the frames follow one another
    in the file; the game says `frames.HERO.walk_down_1` and never counts."""

    def __init__(self, sid: str, w: int, h: int, bank: int = 0, ms: int = 0):
        self.id, self.w, self.h, self.bank, self.ms = sid, w, h, bank, ms
        self.frames: list[tuple[str, Pic]] = []
        self.banks: dict[str, int] = {}

    def add(self, name: str, p: Pic | list[str] | str, bank: int | None = None) -> Pic:
        p = as_pic(p, self.w, self.h)
        if any(n == name for n, _ in self.frames):
            raise ValueError(f"{self.id}.{name} twice")
        self.frames.append((name, p))
        if bank is not None:
            self.banks[name] = bank
        return p

    def get(self, name: str) -> Pic:
        return next(p for n, p in self.frames if n == name)


class Metatile:
    def __init__(self, name: str, ground: Pic, front: Pic | None, flags: tuple, bank: int, front_bank: int | None):
        self.name, self.ground, self.front, self.flags, self.bank, self.front_bank = name, ground, front, flags, bank, front_bank


class Registry:
    """Everything the art modules define: sheets, metatiles of each tileset, animations, the palettes."""

    def __init__(self):
        self.sheets: dict[str, Sheet] = {}
        self.metas: dict[str, dict[str, Metatile]] = {}  # tileset -> name -> metatile, in the order made
        self.anims: dict[str, dict] = {}                  # name -> {"frames": [metatile names], "ticks": n}
        self.tiles8: dict[str, dict[str, tuple[Pic, int]]] = {}  # tileset -> name -> (8x8 picture, bank): letters, icons

    def sheet(self, sid: str, w: int, h: int, bank: int = 0, ms: int = 0) -> Sheet:
        if sid in self.sheets:
            raise ValueError(f"sheet {sid} twice")
        self.sheets[sid] = Sheet(sid, w, h, bank, ms)
        return self.sheets[sid]

    def meta(self, tileset: str, name: str, ground: list[str] | str | Pic, front: list[str] | str | Pic | None = None,
             flags: tuple = (), bank: int = 0, front_bank: int | None = None) -> Metatile:
        """A 16x16 metatile of a tileset. `ground` is drawn on the ground layer; `front`, if any, on the layer drawn
        over the sprites (a tree's top, a roof's edge: the hero walks behind it). `flags` is what the game does with
        it: "solid" (blocks), "water" (deep: blocks, drowns what falls in), "pit", "cut" (the pala cuts it), "dig",
        "door", "stairs"... the engine's list is in data/tiles.lua when it is built."""
        d = self.metas.setdefault(tileset, {})
        if name in d:
            raise ValueError(f"metatile {tileset}.{name} twice")

        def to_pic(v):
            return None if v is None else as_pic(v, 16, 16)
        m = Metatile(name, to_pic(ground), to_pic(front), tuple(flags), bank, front_bank if front_bank is not None else bank)
        d[name] = m
        return m

    def tile8(self, tileset: str, name: str, rows: list[str] | str, bank: int = 0) -> None:
        self.tiles8.setdefault(tileset, {})[name] = (as_pic(rows, 8, 8), bank)

    def animate(self, name: str, frames: list[str], ticks: int = 30) -> None:
        """Metatiles that take turns (water, a flame): the game swaps them on the map every `ticks`."""
        self.anims[name] = {"frames": frames, "ticks": ticks}


ART = Registry()


# ------------------------------------------------------------------ tiles and maps

def _tile_key(p: Pic) -> bytes:
    return bytes(0 if v < 0 else v + 1 for row in p for v in row)


class Tileset:
    """The 8x8 tiles of a set of 16x16 metatiles, one copy of each (tile 0 is the empty one, so a map's 0 is nothing).

    `add(name, rows, ...)` registers a metatile and returns its four map entries (top-left, top-right, bottom-left,
    bottom-right): each is the tile's number, with `bank << 12` for the palette bank it is to be drawn in. A tile
    that is the mirror of one already there is the same tile with a flip bit when `flips` (the Game Boy Color could,
    the first Game Boy could not)."""

    def __init__(self, flips: bool = False):
        self.flips = flips
        self.tiles: list[bytes] = [bytes(64)]
        self.index: dict[bytes, int] = {bytes(64): 0}
        self.meta: dict[str, list[int]] = {}

    def tile(self, p: Pic, bank: int = 0) -> int:
        key = _tile_key(p)
        if key in self.index:
            return self.index[key] | bank << 12
        if self.flips:
            for flags, variant in ((0x400, flip_h(p)), (0x800, flip_v(p)), (0xC00, flip_v(flip_h(p)))):
                k = _tile_key(variant)
                if k in self.index:
                    return self.index[k] | flags | bank << 12
        if len(self.tiles) >= 1024:
            raise ValueError("more than 1024 different tiles: a map holds tile numbers up to 1023")
        self.index[key] = len(self.tiles)
        self.tiles.append(key)
        return self.index[key] | bank << 12

    def add(self, name: str, rows: list[str] | str, bank: int = 0) -> list[int]:
        p = as_pic(rows, 16, 16)
        entries = [self.tile(crop(p, x, y, 8, 8), bank) for y in (0, 8) for x in (0, 8)]
        if name in self.meta:
            raise ValueError(f"metatile {name!r} twice")
        self.meta[name] = entries
        return entries

    def add_tile(self, name: str, rows: list[str] | str, bank: int = 0) -> int:
        """One 8x8 tile of its own (a letter, a heart, a frame's corner)."""
        e = self.tile(as_pic(rows, 8, 8), bank)
        self.meta[name] = [e]
        return e


class Layer:
    """A map of tile entries, `w` x `h` tiles."""

    def __init__(self, w: int, h: int):
        self.w, self.h = w, h
        self.entries = [0] * (w * h)

    def put(self, tx: int, ty: int, entry: int) -> None:
        if 0 <= tx < self.w and 0 <= ty < self.h:
            self.entries[ty * self.w + tx] = entry

    def put_meta(self, mx: int, my: int, entries: list[int]) -> None:
        """A metatile at metatile cell mx, my (16x16 pixels)."""
        for i, e in enumerate(entries):
            self.put(mx * 2 + i % 2, my * 2 + i // 2, e)


def write_tilemap(aid: str, ts: Tileset, layer: Layer, palette: str = "WORLD") -> None:
    ASSETS.mkdir(parents=True, exist_ok=True)
    (ASSETS / f"{aid}.tiles").write_bytes(b"".join(ts.tiles))
    (ASSETS / f"{aid}.map").write_bytes(b"".join(e.to_bytes(2, "little") for e in layer.entries))
    meta = {"asset": aid, "type": "tilemap", "tiles": len(ts.tiles), "map_w": layer.w, "map_h": layer.h, "palette": palette}
    (ASSETS / f"{aid}.meta.json").write_text(json.dumps(meta, indent=2) + "\n")


def write_sheet(aid: str, frames: list[Pic], palette: str = "OBJ", ms: int = 0) -> None:
    """A sprite sheet of equal frames (the engine's .idx: one byte a pixel, 0 see-through, tones 1 to 4)."""
    w, h = len(frames[0][0]), len(frames[0])
    for i, f in enumerate(frames):
        if len(f) != h or len(f[0]) != w:
            raise ValueError(f"{aid}: frame {i} is {len(f[0])}x{len(f)}, not {w}x{h}")
    ASSETS.mkdir(parents=True, exist_ok=True)
    (ASSETS / f"{aid}.idx").write_bytes(b"".join(_tile_key(f) for f in frames))
    meta = {"asset": aid, "type": "sprite", "format": "idx8", "w": w, "h": h, "frames": len(frames),
            "frame_ms": [ms] * len(frames), "palette": palette}
    (ASSETS / f"{aid}.meta.json").write_text(json.dumps(meta, indent=2) + "\n")


def rgb565(c: tuple[int, int, int]) -> int:
    r, g, b = c
    return (r >> 3) << 11 | (g >> 2) << 5 | b >> 3


def write_palette(name: str, banks: list[list[tuple[int, int, int]]]) -> None:
    """A palette of banks of four tones: entry 16 * bank + tone + 1; entry 0 stays see-through."""
    entries = [0] * (16 * len(banks))
    for b, tones in enumerate(banks):
        for i, c in enumerate(tones):
            entries[16 * b + 1 + i] = rgb565(c)
    ASSETS.mkdir(parents=True, exist_ok=True)
    (ASSETS / f"{name}.pal").write_bytes(b"".join(e.to_bytes(2, "little") for e in entries))


# ------------------------------------------------------------------ pictures to look at

def to_image(p: Pic, tones=DMG, scale: int = 1, back=None) -> Image.Image:
    h, w = len(p), len(p[0])
    img = Image.new("RGBA", (w, h), (0, 0, 0, 0) if back is None else back + (255,))
    px = img.load()
    for y in range(h):
        for x in range(w):
            if p[y][x] >= 0:
                px[x, y] = tones[p[y][x]] + (255,)
    return img.resize((w * scale, h * scale), Image.NEAREST) if scale != 1 else img


def contact_sheet(pics: list[Pic], cols: int = 8, scale: int = 4, gap: int = 4, tones=DMG,
                  back=(200, 200, 200)) -> Image.Image:
    """Pictures in a grid, on a neutral grey so what is see-through shows."""
    cw = max(len(p[0]) for p in pics)
    ch = max(len(p) for p in pics)
    rows = (len(pics) + cols - 1) // cols
    sheet = Image.new("RGB", (cols * (cw * scale + gap) + gap, rows * (ch * scale + gap) + gap), back)
    for i, p in enumerate(pics):
        sheet.paste(to_image(p, tones, scale, back), (gap + (i % cols) * (cw * scale + gap), gap + (i // cols) * (ch * scale + gap)))
    return sheet


def layer_image(ts: Tileset, layer: Layer, tones=DMG, back=DMG[0]) -> Image.Image:
    """A map drawn from its tiles, as the engine will (flips included): to check what the numbers say."""
    img = Image.new("RGB", (layer.w * 8, layer.h * 8), back)
    for ty in range(layer.h):
        for tx in range(layer.w):
            e = layer.entries[ty * layer.w + tx]
            n = e & 0x3FF
            if n == 0:
                continue
            raw = ts.tiles[n]
            t = Image.new("RGBA", (8, 8))
            px = t.load()
            for y in range(8):
                for x in range(8):
                    v = raw[y * 8 + x]
                    if v:
                        px[x, y] = tones[v - 1] + (255,)
            if e & 0x400:
                t = t.transpose(Image.FLIP_LEFT_RIGHT)
            if e & 0x800:
                t = t.transpose(Image.FLIP_TOP_BOTTOM)
            img.paste(t, (tx * 8, ty * 8), t)
    return img


# ------------------------------------------------------------------ terrain that borders itself (autotiling)

def edge_piece(fam: str, n: bool, e: bool, s: bool, w: bool, ne: bool, se: bool, sw: bool, nw: bool) -> str | None:
    """Which piece of a terrain family a cell takes, given whether each of its eight neighbours is the same family.

    A family is drawn over a background (grass over which dirt lies, sand over which water lies). Its pieces:
      <fam>_n  _e  _s  _w        the border runs along that side (the neighbour there is not the family)
      <fam>_ne _se _sw _nw       two borders meet: an OUTER corner, the family's corner is rounded off
      <fam>_in_ne ... _in_nw     the four sides are the family but the diagonal neighbour is not: an INNER corner,
                                 a small notch of background in that corner of the tile
    and `None` for a cell inside the family (it takes one of the family's plain variants). Areas must be at least two
    cells wide: a one-cell strip has no piece (its two borders would be asked of one tile)."""
    if not n and not e:
        return f"{fam}_ne"
    if not n and not w:
        return f"{fam}_nw"
    if not s and not e:
        return f"{fam}_se"
    if not s and not w:
        return f"{fam}_sw"
    if not n:
        return f"{fam}_n"
    if not s:
        return f"{fam}_s"
    if not e:
        return f"{fam}_e"
    if not w:
        return f"{fam}_w"
    if not ne:
        return f"{fam}_in_ne"
    if not se:
        return f"{fam}_in_se"
    if not sw:
        return f"{fam}_in_sw"
    if not nw:
        return f"{fam}_in_nw"
    return None


def autotile(grid: list[str], families: dict[str, str], variants: dict[str, list[str]], fallback: dict[str, list[str]],
             seed: int = 1, joins: dict[str, str] | None = None, warn=None) -> list[list[str]]:
    """A map of metatile names from a map of terrain characters.

    `grid` rows of characters; `families` {char: family name} for those that border themselves (the cells of other
    characters are not that family); `variants` {family: [plain pieces]} for a cell inside a family; `fallback`
    {char: [names]} for every other character (grass, a bush...): one name of the list is chosen by a fixed hash of
    the cell, so the same map always draws the same. Outside the map counts as the same family (a shore runs off the
    edge of the screen). `joins` {char: chars} says which other characters count as the same body for that family's
    edges (the sand does not draw a border against the water whose own pieces carry the shore). `warn(x, y, ch, why)`
    is called for a strip one cell wide, which no piece can draw."""
    h, w = len(grid), len(grid[0])
    joins = joins or {}

    def same(x, y, ch):
        return not (0 <= x < w and 0 <= y < h) or grid[y][x] == ch or grid[y][x] in joins.get(ch, "")

    def pick(names, x, y):
        return names[((x * 73856093) ^ (y * 19349663) ^ (seed * 83492791)) % len(names)]
    out = []
    for y in range(h):
        row = []
        for x in range(w):
            ch = grid[y][x]
            if ch in families:
                fam = families[ch]
                n, e, s_, w_ = same(x, y - 1, ch), same(x + 1, y, ch), same(x, y + 1, ch), same(x - 1, y, ch)
                if warn and ((not n and not s_) or (not e and not w_)):
                    warn(x, y, ch, "a strip one cell wide")
                piece = edge_piece(fam, n, e, s_, w_,
                                   same(x + 1, y - 1, ch), same(x + 1, y + 1, ch), same(x - 1, y + 1, ch), same(x - 1, y - 1, ch))
                row.append(piece or pick(variants[fam], x, y))
            else:
                row.append(pick(fallback[ch], x, y))
        out.append(row)
    return out


def scene_image(names: list[list[str]], metas: dict[str, "Metatile"], tones=DMG, scale: int = 1, hero: tuple | None = None) -> Image.Image:
    """A map of metatile names drawn: the ground, then (optionally) a picture at pixel hero = (pic, x, y), then the
    front layer over it: what the engine will show. For looking at transitions and compositions."""
    h, w = len(names), len(names[0])
    base = Image.new("RGBA", (w * 16, h * 16), tones[0] + (255,))
    front = Image.new("RGBA", (w * 16, h * 16), (0, 0, 0, 0))
    for y, row in enumerate(names):
        for x, n in enumerate(row):
            m = metas[n]
            base.alpha_composite(to_image(m.ground, tones), (x * 16, y * 16))
            if m.front is not None:
                front.alpha_composite(to_image(m.front, tones), (x * 16, y * 16))
    if hero is not None:
        base.alpha_composite(to_image(hero[0], tones), (hero[1], hero[2]))
    base.alpha_composite(front)
    img = base.convert("RGB")
    return img.resize((img.width * scale, img.height * scale), Image.NEAREST) if scale != 1 else img
