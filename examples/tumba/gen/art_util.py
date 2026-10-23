"""Small helpers for Tumba's code art: pictures as lists of 8-char strings of hex colours ('.' = see-through)."""
from __future__ import annotations


def grid(text: str) -> list[str]:
    """A picture written as a block of text (blank lines and indentation ignored)."""
    return [r.strip() for r in text.strip("\n").split("\n") if r.strip()]


def check(rows: list[str], w: int = 8, h: int = 8, name: str = "?") -> list[str]:
    if len(rows) != h or any(len(r) != w for r in rows):
        raise ValueError(f"{name}: needs {h} rows of {w}, got {[len(r) for r in rows]}")
    return rows


def over(base: list[str], top: list[str]) -> list[str]:
    """Lay `top` (with '.' holes) over `base`."""
    return ["".join(t if t != "." else b for b, t in zip(br, tr)) for br, tr in zip(base, top)]


def put(rows: list[str], pts: dict[tuple[int, int], str]) -> list[str]:
    """A copy of `rows` with pixels {(x, y): colour} set."""
    out = [list(r) for r in rows]
    for (x, y), c in pts.items():
        if 0 <= y < len(out) and 0 <= x < len(out[0]):
            out[y][x] = c
    return ["".join(r) for r in out]


def flip_x(rows: list[str]) -> list[str]:
    return [r[::-1] for r in rows]


def flip_y(rows: list[str]) -> list[str]:
    return rows[::-1]


def rot90(rows: list[str]) -> list[str]:
    """Clockwise."""
    h = len(rows)
    return ["".join(rows[h - 1 - y][x] for y in range(h)) for x in range(len(rows[0]))]


def recolor(rows: list[str], mapping: dict[str, str]) -> list[str]:
    return ["".join(mapping.get(c, c) for c in r) for r in rows]


def shift(rows: list[str], dx: int = 0, dy: int = 0, fill: str = ".") -> list[str]:
    h, w = len(rows), len(rows[0])
    out = []
    for y in range(h):
        sy = y - dy
        out.append("".join(rows[sy][x - dx] if 0 <= sy < h and 0 <= x - dx < w else fill for x in range(w)))
    return out
