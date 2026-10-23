"""The title wordmark TUMBA, 120x32 px on black, cut into logo_<row>_<col> tiles (4 rows x 15 columns).

Letters are built from rectangles (20x24 each), then shaded like a PICO-8 title: a yellow-to-orange face (checker dither between),
a lit top edge, a brown extrusion below for the 3D bevel and a dark purple drop shadow. The A's crossbar is a blue gem.
"""
from __future__ import annotations

W, H = 120, 32
LW, LH = 20, 24
GAP = 3
X0, Y0 = 4, 2

# rectangles (x0, y0, x1, y1), end exclusive, in a 20x24 letter box
GLYPHS = {
    "T": [(0, 0, 20, 6), (7, 0, 13, 24)],
    "U": [(0, 0, 6, 24), (14, 0, 20, 24), (0, 18, 20, 24)],
    "M": [(0, 0, 6, 24), (14, 0, 20, 24)] + [(4 + y * 4 // 13, y, 8 + y * 4 // 13, y + 1) for y in range(15)]
         + [(12 - y * 4 // 13, y, 16 - y * 4 // 13, y + 1) for y in range(15)],
    "B": [(0, 0, 6, 24), (0, 0, 16, 5), (14, 2, 19, 10), (0, 10, 17, 14), (14, 12, 20, 22), (0, 19, 17, 24)],
    "A": [(0, 5, 6, 24), (14, 5, 20, 24), (2, 0, 18, 6)],
}
# corners cut off for a chunky carved look: (x, y) of the corner pixel and the direction the cut grows into
CHAMFER = {
    "T": [(0, 5, 1, -1), (19, 5, -1, -1)],
    "U": [(0, 23, 1, -1), (19, 23, -1, -1)],
    "M": [],
    "B": [(15, 0, -1, 1), (18, 2, -1, 1), (18, 9, -1, -1), (16, 13, -1, 1), (19, 12, -1, 1), (19, 21, -1, -1), (16, 23, -1, -1)],
    "A": [(2, 0, 1, 1), (17, 0, -1, 1), (0, 5, 1, 1), (19, 5, -1, 1)],
}
GEM = [  # the A's crossbar, set between the stems at (5, 10) in the A's box
    ".1cccc1.",
    "1c77ccc1",
    "c7cccccd",
    "1cccccd1",
    ".1ccdd1.",
    "..1cd1..",
    "...11...",
]


def letter_mask(ch: str) -> set[tuple[int, int]]:
    px = set()
    for x0, y0, x1, y1 in GLYPHS[ch]:
        px |= {(x, y) for x in range(x0, x1) for y in range(y0, y1)}
    for cx, cy, dx, dy in CHAMFER[ch]:
        for k in range(2):
            for j in range(2 - k):
                px.discard((cx + dx * j, cy + dy * k))
    return px


def compose() -> list[str]:
    img = [["0"] * W for _ in range(H)]
    mask: set[tuple[int, int]] = set()
    gem_at = None
    for i, ch in enumerate("TUMBA"):
        ox = X0 + i * (LW + GAP)
        mask |= {(x + ox, y + Y0) for x, y in letter_mask(ch)}
        if ch == "A":
            gem_at = (ox + 5, Y0 + 10)

    def setp(x, y, c):
        if 0 <= x < W and 0 <= y < H:
            img[y][x] = c

    for x, y in mask:                       # drop shadow, down-right
        for dx, dy in ((2, 4), (1, 4), (2, 3)):
            setp(x + dx, y + dy, "2")
    for x, y in mask:                       # the extrusion: 3 px of brown under the face
        for d in (1, 2, 3):
            setp(x, y + d, "4" if d < 3 else "2")
    for x, y in mask:                       # the face
        ly = y - Y0
        if ly < 9:
            c = "a"
        elif ly < 13:
            c = "a" if (x + y) % 2 else "9"
        else:
            c = "9"
        if (x, y - 1) not in mask:
            c = "7" if ly < 2 else "f"      # lit top edge (white on the outer top, peach inside the holes)
        elif (x - 1, y) not in mask:
            c = "f" if ly < 13 else "a"     # lit left edge
        elif (x + 1, y) not in mask:
            c = "9" if ly < 13 else "4"     # shaded right edge
        setp(x, y, c)
    if gem_at:
        gx, gy = gem_at
        for y, row in enumerate(GEM):
            for x, c in enumerate(row):
                if c != ".":
                    setp(gx + x, gy + y, c)
    return ["".join(r) for r in img]


def register(ART) -> None:
    pic = compose()
    for r in range(4):
        for c in range(15):
            ART.tile(f"logo_{r}_{c}", [row[c * 8:(c + 1) * 8] for row in pic[r * 8:(r + 1) * 8]])
