"""Small helpers for Socavón's text pictures: frames side by side, shifts, flips, and a checked parse.

Pictures stay `X`/`.` rows (zxkit's format). `strip(text, w, h)` reads several frames written next to each other,
separated by `|`, so an animation can be drawn and compared in one block of text.
"""
from __future__ import annotations


def parse(text: str, w: int, h: int, what: str) -> list[str]:
    rows = [r.strip() for r in text.strip("\n").split("\n")]
    bad = [(i, len(r)) for i, r in enumerate(rows) if len(r) != w]
    if len(rows) != h or bad:
        raise ValueError(f"{what}: needs {h} rows of {w}, has {len(rows)} rows, bad rows (index, length) {bad}")
    odd = {c for r in rows for c in r} - set("X.")
    if odd:
        raise ValueError(f"{what}: characters other than X and .: {sorted(odd)}")
    return rows


def strip(text: str, names: list[str], w: int = 16, h: int = 16) -> dict[str, list[str]]:
    """Frames drawn side by side, `|` between them: returns {name: rows}."""
    lines = [l.strip() for l in text.strip("\n").split("\n")]
    cols = [l.split("|") for l in lines]
    if any(len(c) != len(names) for c in cols):
        raise ValueError(f"strip {names}: rows with a wrong number of frames: "
                         f"{[(i, len(c)) for i, c in enumerate(cols) if len(c) != len(names)]}")
    return {n: parse("\n".join(c[i] for c in cols), w, h, n) for i, n in enumerate(names)}


def shift_h(rows: list[str], dx: int, wrap: bool = True) -> list[str]:
    """Move a picture dx pixels right (wrapping, or filling with paper)."""
    if not rows:
        return []
    w = len(rows[0])
    if wrap:
        return [r[-dx % w:] + r[:-dx % w] if dx % w else r for r in rows]
    if dx >= 0:
        return [("." * dx + r)[:w] for r in rows]
    return [(r[-dx:] + "." * -dx) for r in rows]


def shift_v(rows: list[str], dy: int) -> list[str]:
    """Move a picture dy pixels down, filling with paper."""
    w, h = len(rows[0]), len(rows)
    blank = ["." * w] * abs(dy)
    return (blank + rows)[:h] if dy >= 0 else (rows[-dy:] + blank)


def flip_h(rows: list[str]) -> list[str]:
    return [r[::-1] for r in rows]


def flip_v(rows: list[str]) -> list[str]:
    return list(reversed(rows))


def overlay(a: list[str], b: list[str]) -> list[str]:
    """Ink of both pictures."""
    return ["".join("X" if "X" in (x, y) else "." for x, y in zip(ra, rb)) for ra, rb in zip(a, b)]


def cut(big: list[str], x: int, y: int, w: int = 8, h: int = 8) -> list[str]:
    return [r[x:x + w] for r in big[y:y + h]]


def transpose(rows: list[str]) -> list[str]:
    """Rows become columns (a square picture turned on its diagonal)."""
    return ["".join(r[i] for r in rows) for i in range(len(rows[0]))]
