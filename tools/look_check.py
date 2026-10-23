# /// script
# requires-python = ">=3.10"
# ///
"""Checks a game against the look it is made for (tools/looks.json "limits"): colours in each palette bank, colours and bits of packed
sprite sheets, the biggest sprite frame, pictures in a look that has none, forbidden code, and the font pack.

    uv run tools/look_check.py examples/cerezo                 # the look is read from game.json ("look")
    uv run tools/look_check.py games/mygame --look gameboy     # or named
Exit 1 if there is an error. Warnings (WARN) are things to look at, not to fail on.
"""
from __future__ import annotations

import argparse
import json
import re
import struct
import sys
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent))
import looks  # noqa: E402

BANK = 16  # entries of one palette bank in a .pal (RGB565, little endian); entry 0 is see-through


def pal_colours(path: Path) -> list[int]:
    """Distinct non-zero colours of each 16-entry bank that has any."""
    raw = path.read_bytes()
    vals = struct.unpack(f"<{len(raw) // 2}H", raw[: len(raw) // 2 * 2])
    return [len({v for v in vals[i + 1:i + BANK] if v}) for i in range(0, len(vals), BANK)]


def check(game: Path, look: dict) -> tuple[list[str], list[str]]:
    lim, errs, warns = look["limits"], [], []
    assets = game / "assets"
    max_bank = lim.get("pal_bank_colours")
    if max_bank is not None:
        for pal in sorted(assets.glob("*.pal")):
            for b, n in enumerate(pal_colours(pal)):
                if n > max_bank:
                    errs.append(f"{pal.name} bank {b}: {n} colours, {look['name']} allows {max_bank}")
    pictures = 0
    for meta_path in sorted(assets.glob("*.meta.json")):
        m = json.loads(meta_path.read_text(encoding="utf-8"))
        pictures += m.get("type") in ("sprite", "background")
        if "sprite" in lim and m.get("type") == "sprite":
            mw, mh = lim["sprite"]
            if m.get("w", 0) > mw or m.get("h", 0) > mh:
                errs.append(f"{m['asset']}: a {m['w']}x{m['h']} frame, {look['name']} sprites are at most {mw}x{mh}")
        if m.get("format") == "packed" and m.get("type") == "sprite":
            if m.get("bpp", 0) > lim.get("image_bpp", 99) or m.get("colours", 0) > lim.get("image_colours", 1 << 30):
                errs.append(f"{m['asset']}: {m.get('colours')} colours / {m.get('bpp')} bits, {look['name']} pictures are at most "
                            f"{lim.get('image_colours')} colours / {lim.get('image_bpp')} bits")
    if lim.get("pictures") is False and pictures:
        errs.append(f"{pictures} picture assets, but a {look['name']} game draws only lines (poly/line)")
    for src in sorted(game.rglob("*.lua")):
        text = src.read_text(encoding="utf-8", errors="replace")
        for pat in lim.get("forbid_lua", []):
            if re.search(pat, text):
                errs.append(f"{src.relative_to(game)}: matches /{pat}/, which {look['name']} must not do (see its 'avoid' in tools/looks.json)")
    fonts = [p.name for p in (game / "fonts").glob("*.fnt")] if (game / "fonts").is_dir() else []
    if fonts and not any(f.startswith(look["font_pack"]) for f in fonts):
        warns.append(f"fonts: none from the '{look['font_pack']}' pack (uv run tools/font2fnt.py --pack {look['font_pack']} {game})")
    return errs, warns


def main() -> None:
    p = argparse.ArgumentParser(description=__doc__.split("\n\n")[0])
    p.add_argument("game", type=Path)
    p.add_argument("--look", help="a look id or a phrase (default: game.json's \"look\")")
    a = p.parse_args()
    look_id = a.look
    if not look_id:
        look_id = json.loads((a.game / "game.json").read_text(encoding="utf-8")).get("look")
    if not look_id:
        sys.exit("no look: pass --look or put \"look\": \"<id>\" in game.json")
    ids, _ = looks.resolve(look_id)
    if len(ids) != 1:
        sys.exit(f"{look_id!r} is not one look: {ids or 'none'}")
    errs, warns = check(a.game, looks.get(ids[0]))
    for w in warns:
        print("WARN", w)
    for e in errs:
        print("ERROR", e)
    print(f"{a.game.name} as {ids[0]}: {len(errs)} errors, {len(warns)} warnings")
    sys.exit(1 if errs else 0)


if __name__ == "__main__":
    main()
