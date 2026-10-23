"""A composed tomb room to judge the art in context: art/p8_preview.png (1x and 4x side by side)."""
from __future__ import annotations

from PIL import Image

from p8kit import ART, ART_DIR, color, contact

ROOM = """
################
#S....#....g..*#
#.##..#.##.##..#
#.#g.....#...g.#
#...a.##.#.mm..#
###.#.##...mm.##
#g..#....c..#..#
#.###.##.#..#.k#
#.....#g.#..R..#
#.#.#.#..##D####
#.#g#..........#
#...#.###.#.#.b#
##..*.#g..#.#..#
#..####...#...E#
#g......U.#.g..#
################
"""
TILE_OF = {"g": "coin_0", "*": "spike_0", "m": "mud_0", "a": "tele_a_0", "b": "tele_b_0", "k": "key_0", "D": "door",
           "E": "exit_open_0", "c": "crack_0", "S": "start", "U": "gate_u", "V": "gate_d", "L": "gate_l", "R": "gate_r"}
HERO_AT = (1, 1)
DECOR = {(4, 0): "deco_torch_0", (11, 0): "deco_torch_1", (7, 14): "deco_skull"}
FLOORS = ["floor_a"] * 4 + ["floor_b"] + ["floor_a"] * 3 + ["floor_c"] + ["floor_a"] * 3 + ["floor_d"]


def cells() -> list[str]:
    rows = [r for r in ROOM.strip("\n").split("\n")]
    return [r.ljust(16, "#")[:16] for r in rows]


def tile_for(m: list[str], x: int, y: int) -> str:
    def wall(cx, cy):
        return not (0 <= cx < 16 and 0 <= cy < 16) or m[cy][cx] == "#"
    c = m[y][x]
    if (x, y) in DECOR:
        return DECOR[(x, y)]
    if c == "#":
        mask = (0 if wall(x, y - 1) else 1) | (0 if wall(x + 1, y) else 2) | (0 if wall(x, y + 1) else 4) | (0 if wall(x - 1, y) else 8)
        return f"wall_m{mask}"
    if c in TILE_OF:
        return TILE_OF[c]
    h = (x * 73 + y * 151 + x * y * 7) % len(FLOORS)
    if wall(x, y - 1):
        return "floor_shade_b" if h == 4 else "floor_shade_a"
    return FLOORS[h]


def paint(img: Image.Image, rows: list[str], ox: int, oy: int) -> None:
    for y, r in enumerate(rows):
        for x, ch in enumerate(r):
            if ch != ".":
                img.putpixel((ox + x, oy + y), color(ch))


def render(hero: str = "idle_0") -> Image.Image:
    m = cells()
    img = Image.new("RGB", (128, 128), (0, 0, 0))
    for y in range(16):
        for x in range(16):
            name = tile_for(m, x, y)
            if name in ART.tiles:
                paint(img, ART.tiles[name], x * 8, y * 8)
    frames = dict(ART.sheets.get("HERO", {}).get("frames", []))
    if hero in frames:
        paint(img, frames[hero], HERO_AT[0] * 8, HERO_AT[1] * 8)
    return img


def save() -> None:
    one = render()
    big = one.resize((512, 512), Image.NEAREST)
    out = Image.new("RGB", (128 + 8 + 512, 512), (0, 0, 0))
    out.paste(one, (0, 0))
    out.paste(big, (136, 0))
    out.save(ART_DIR / "p8_preview.png")


def save_sheets(tag: str = "") -> None:
    """Contact sheets at 6x (the build writes them too; this lets --preview skip the asset conversion)."""
    contact(list(ART.tiles.values()), 16, 6).save(ART_DIR / f"tiles_sheet{tag}.png")
    for sid, s in ART.sheets.items():
        contact([r for _, r in s["frames"]], 13, 8).save(ART_DIR / f"sheet_{sid.lower()}{tag}.png")


def save_logo() -> None:
    img = Image.new("RGB", (120, 32))
    for r in range(4):
        for c in range(15):
            paint(img, ART.tiles[f"logo_{r}_{c}"], c * 8, r * 8)
    img.resize((480, 128), Image.NEAREST).save(ART_DIR / "logo_preview.png")


def save_screen() -> None:
    """The room in a screen: the TUMBA logo above, hieroglyph columns at both sides (art/p8_screen.png, 1x and 3x)."""
    w, h = 160, 32 + 8 + 128
    img = Image.new("RGB", (w, h))
    for r in range(4):
        for c in range(15):
            paint(img, ART.tiles[f"logo_{r}_{c}"], 20 + c * 8, r * 8)
    img.paste(render(), (16, 40))
    order = ["border_a", "border_b", "border_c", "border_d"]
    for i in range(16):
        for x in (2, 150):
            paint(img, ART.tiles[order[i % 4]], x, 40 + i * 8)
    out = Image.new("RGB", (w + 8 + w * 3, h * 3))
    out.paste(img, (0, 0))
    out.paste(img.resize((w * 3, h * 3), Image.NEAREST), (w + 8, 0))
    out.save(ART_DIR / "p8_screen.png")
