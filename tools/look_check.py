# /// script
# requires-python = ">=3.10"
# ///
"""Checks a game against the look it is made for (tools/looks.json "limits"): colours in each palette bank, colours and bits of packed
sprite sheets, the biggest sprite frame, pictures in a look that has none, forbidden code, and the font pack. With --play, the game's test script is played (sampled every 15 ticks) and
the layers, the sprites on the screen, the most sprites on one line and the blend and window use are checked against the look's "play" limits.

    uv run tools/look_check.py examples/cerezo                 # the look is read from game.json ("look")
    uv run tools/look_check.py games/mygame --look gameboy     # or named
    uv run tools/look_check.py examples/cerezo --play          # also plays tests/<id>.script and checks what the picture processor does
Exit 1 if there is an error. Warnings (WARN) are things to look at, not to fail on.
"""
from __future__ import annotations

import argparse
import json
import re
import struct
import subprocess
import sys
import tempfile
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent))
import looks  # noqa: E402
import sprite_check  # noqa: E402

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
    art = game / "art"
    if art.is_dir():  # the strips the game's art scripts make: frames cut by their cell, feet off the ground line, sizes that jump (tools/sprite_check.py)
        bad = [e for f in sorted(art.glob("*.json")) for e in sprite_check.audit(f)[0]]
        if bad:
            warns.append(f"art: {len(bad)} sprite problems, first: {bad[0]} (uv run tools/sprite_check.py {art})")
    fonts = [p.name for p in (game / "fonts").glob("*.fnt")] if (game / "fonts").is_dir() else []
    if fonts and not any(f.startswith(look["font_pack"]) for f in fonts):
        warns.append(f"fonts: none from the '{look['font_pack']}' pack (uv run tools/font2fnt.py --pack {look['font_pack']} {game})")
    return errs, warns


PRELUDE = ("lua __M = {l = 0, s = 0, n = 0, b = false, w = false} function __u() local u = ppu_usage() "
           "if u.layers > __M.l then __M.l = u.layers end if u.sprites > __M.s then __M.s = u.sprites end "
           "if u.line_sprites > __M.n then __M.n = u.line_sprites end __M.b = __M.b or u.blend __M.w = __M.w or u.window end")
PRELUDE_AGAIN = PRELUDE.replace("lua __M = {l = 0, s = 0, n = 0, b = false, w = false} function", "lua __M = __M or {l = 0, s = 0, n = 0, b = false, w = false} function")
SAMPLE = 15  # ticks between samples


def instrument(script: str) -> str:
    """The game's script with the picture processor sampled between its commands (a long `tick N` is cut in pieces of 15)."""
    out = [PRELUDE]
    for line in script.splitlines():
        words = line.split()
        if words and words[0] == "new":  # a new game forgets the sampler: put it back (keeping what it saw)
            out += [line, PRELUDE_AGAIN]
            continue
        if words and words[0] == "tick" and len(words) > 1 and words[1].isdigit():
            n = int(words[1])
            while n > 0:
                out += [f"tick {min(SAMPLE, n)}", "lua __u()"]
                n -= SAMPLE
        else:
            out.append(line)
            if words and words[0] in ("hold", "press", "release", "wait"):
                out.append("lua __u()")
    out.append('lua print("LOOKUSE", __M.l, __M.s, __M.n, tostring(__M.b), tostring(__M.w))')
    return "\n".join(out) + "\n"


def play(game: Path, look: dict, headless: Path, script: Path | None) -> tuple[list[str], str]:
    """Plays the test script and checks look["play"]; returns (errors, a line with the maxima seen)."""
    if not script:
        mine, engines = game / "tests" / f"{game.name}.script", Path(__file__).resolve().parents[1] / "tests" / f"{game.name}.script"
        script = mine if mine.exists() else engines  # (the engine's examples keep theirs in its tests/)
    if not script.exists():
        return [f"--play: no script {script}"], ""
    lim = look.get("play", {})
    with tempfile.TemporaryDirectory() as tmp:
        sc = Path(tmp) / "play.script"
        sc.write_text(instrument(script.read_text(encoding="utf-8")), encoding="utf-8")
        r = subprocess.run([str(headless), "--game", str(game), "--saves", str(Path(tmp) / "saves"), "--fresh", "--script", str(sc), "--check-strips"],
                           capture_output=True, text=True)
    text = r.stdout + r.stderr
    m = re.search(r"LOOKUSE (\d+) (\d+) (\d+) (\w+) (\w+)", text)
    if not m:
        return [f"--play: the script did not finish ({text.strip().splitlines()[-1:] or ['no output']})"], ""
    layers, sprites, line, blend, window = int(m[1]), int(m[2]), int(m[3]), m[4] == "true", m[5] == "true"
    errs = []
    for key, got, what in (("layers", layers, "background layers"), ("sprites", sprites, "sprites on the screen"), ("line_sprites", line, "sprites on one line")):
        if key in lim and got > lim[key]:
            errs.append(f"play: {got} {what}, {look['name']} allows {lim[key]}")
    if lim.get("blend") is False and blend:
        errs.append(f"play: a blend is used, {look['name']} has none")
    if lim.get("window") is False and window:
        errs.append(f"play: a window is used, {look['name']} has none")
    return errs, f"play: up to {layers} layers, {sprites} sprites ({line} on one line), blend {'yes' if blend else 'no'}, window {'yes' if window else 'no'}"


def main() -> None:
    p = argparse.ArgumentParser(description=__doc__.split("\n\n")[0])
    p.add_argument("game", type=Path)
    p.add_argument("--look", help="a look id or a phrase (default: game.json's \"look\")")
    p.add_argument("--play", nargs="?", const="", metavar="SCRIPT", help="also play tests/<id>.script (or SCRIPT) and check layers and sprites")
    p.add_argument("--headless", type=Path, default=Path(__file__).resolve().parents[1] / "build" / "pinyol_headless")
    a = p.parse_args()
    look_id = a.look
    if not look_id:
        look_id = json.loads((a.game / "game.json").read_text(encoding="utf-8")).get("look")
    if not look_id:
        sys.exit("no look: pass --look or put \"look\": \"<id>\" in game.json")
    ids, _ = looks.resolve(look_id)
    if len(ids) != 1:
        sys.exit(f"{look_id!r} is not one look: {ids or 'none'}")
    look = looks.get(ids[0])
    errs, warns = check(a.game, look)
    if a.play is not None:
        e, seen = play(a.game, look, a.headless, Path(a.play) if a.play else None)
        errs += e
        print(seen) if seen else None
    for w in warns:
        print("WARN", w)
    for e in errs:
        print("ERROR", e)
    print(f"{a.game.name} as {ids[0]}: {len(errs)} errors, {len(warns)} warnings")
    sys.exit(1 if errs else 0)


if __name__ == "__main__":
    main()
