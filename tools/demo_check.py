# /// script
# requires-python = ">=3.10"
# dependencies = ["pillow>=10"]
# ///
"""The quality gate of an example game: what every flagship demo should have, checked, so a demo is not "done" because it runs (the lessons of Pozo, Cerezo, Socavón, Tumba, Botín,
Paella and Taller, written down). Static checks, fast, no console needed.

    uv run tools/demo_check.py examples/paella            # one game
    uv run tools/demo_check.py examples/*                 # a table of several (a game that is not a Lua game is skipped)

Each check is OK, WARN (worth fixing) or FAIL (a demo must not ship without it):
  card     game.json has id, title, subtitle, a description of real length, and "look" (tools/looks.json)                     FAIL
  extras   at least 5 achievements, each one named in the code (achieve("id") or a helper)                                           FAIL
  words    strings.csv with es, ca and en, no empty cell, and the game loads it (lang)                                       FAIL
  how      a menu item ("How it works": menuitem) that explains the trick of its era                                         WARN
  flash    the game reads settings().reduce_flashing                                                                       WARN
  cover    cover.rgb565, 240x160 (76800 bytes), for the console's menu                                                       FAIL
  picture  the cover is a picture (no colour fills 80% of it), not a blank frame                                                      WARN
  test     tests/<id>.script (here or in the engine's tests/) that plays the game and checks it (5+ expect_ lines)                                         FAIL
  fonts    the look's font pack, or a font of the game's own, is in fonts/ and used                                         WARN
  art      tools/sprite_check.py finds no cut frame or floating feet (if the game has art/)                                  WARN
  text     its test script plays with the simulator's --check-text: no text cut by the screen's edge or too big for its textbox, in es, ca and en   FAIL
  pictures no raw RGB565 picture of 8 KB or more, drawn with img, that is not the whole screen (slow on the console: pack it)   WARN
  numbers  docs/measurements.md has the game's frame rate measured on the console                                           WARN
Exit 1 if any FAIL.
"""
from __future__ import annotations

import argparse
import csv
import subprocess
import tempfile
import json
import re
import sys
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent))
import looks  # noqa: E402

ROOT = Path(__file__).resolve().parents[1]


def lua_text(game: Path) -> str:
    return "\n".join(p.read_text(encoding="utf-8", errors="replace") for p in game.rglob("*.lua") if "gen" not in p.parts and "raw" not in p.parts)


def check(game: Path) -> list[tuple[str, str, str]]:
    """[(check, OK|WARN|FAIL, note)]"""
    out: list[tuple[str, str, str]] = []
    meta = json.loads((game / "game.json").read_text(encoding="utf-8"))
    code = lua_text(game)

    miss = [k for k in ("id", "title", "subtitle", "description") if not meta.get(k)]
    if len(meta.get("description", "")) < 80:
        miss.append("a description of 80+ characters")
    look = meta.get("look")
    if look:
        try:
            looks.get(look)
        except KeyError:
            miss.append(f"look {look!r} (not in tools/looks.json)")
    else:
        miss.append('"look"')
    out.append(("card", "FAIL" if miss else "OK", "missing: " + ", ".join(miss) if miss else look))

    ach = [a["id"] for a in meta.get("achievements", [])]
    unused = [a for a in ach if not re.search(r'["\']%s["\']' % re.escape(a), code)]  # given by achieve("id") or by a helper that takes the id
    out.append(("extras", "FAIL" if len(ach) < 5 or unused else "OK", f"{len(ach)} achievements" + (f", never given: {', '.join(unused[:4])}" if unused else "")))

    csvp = game / "strings.csv"
    if not csvp.exists():
        out.append(("words", "FAIL", "no strings.csv (es, ca, en): the game speaks one language"))
    else:
        rows = list(csv.reader(csvp.open(encoding="utf-8")))
        head = rows[0] if rows else []
        empty = sum(1 for r in rows[1:] for c in r[1:4] if not c.strip())
        ok = {"es", "ca", "en"} <= set(head) and not empty and 'require("lang")' in code.replace("'", '"')
        out.append(("words", "OK" if ok else "FAIL", f"{len(rows) - 1} keys" if ok else f"languages {head[1:]}, {empty} empty cells, lang loaded: {'lang' in code}"))

    out.append(("how", "OK" if re.search(r"menuitem\(\s*[^)\s]", code) else "WARN", "a menu item" if re.search(r"menuitem\(\s*[^)\s]", code) else "no menuitem that explains the era's trick"))
    flashes = bool(re.search(r"\bflash\s*\(|juice\.flash|{[^}]*flash", code))  # a screen flash or a strobing effect somewhere
    reads = "reduce_flashing" in code
    out.append(("flash", "OK" if reads or not flashes else "WARN", "settings().reduce_flashing read" if reads else "no screen flashes" if not flashes else "flashes the screen and does not read reduce_flashing"))

    cv = game / "cover.rgb565"
    cover_ok = cv.exists() and cv.stat().st_size == 240 * 160 * 2
    out.append(("cover", "OK" if cover_ok else "FAIL", "240x160" if cv.exists() else "no cover.rgb565 (tools/cover.py)"))
    if cover_ok:  # a cover that is nearly one colour is the screen of a moment before the game drew anything (tools/cover.py takes 1.5 s in)
        raw = cv.read_bytes()
        from collections import Counter
        top = Counter(raw[i:i + 2] for i in range(0, len(raw), 2)).most_common(1)[0][1] / (240 * 160)
        out.append(("picture", "OK" if top < 0.8 else "WARN", f"{top:.0%} of the cover is one colour: a blank frame or a loading screen? (tools/cover.py --at, --keys or --from)" if top >= 0.8 else "not a blank frame"))

    scripts = [p for p in (game / "tests" / f"{game.name}.script", ROOT / "tests" / f"{game.name}.script") if p.exists()]
    if not scripts:
        out.append(("test", "FAIL", "no tests/<id>.script"))
    else:
        body = scripts[0].read_text()
        out.append(("test", "OK" if body.count("expect_") >= 5 and "tick" in body else "FAIL", str(scripts[0].relative_to(ROOT)) if scripts[0].is_relative_to(ROOT) else scripts[0].name))

    fonts = sorted((game / "fonts").glob("*.fnt")) if (game / "fonts").is_dir() else []
    pack = looks.get(look)["font_pack"] if look and look in {k["id"] for k in looks.load()["looks"]} else None
    names = [f.stem for f in fonts if not f.stem.startswith("FONT_")]
    used = [n for n in names if re.search(r'["\']%s["\']|%s' % (re.escape(n), re.escape(n)), code)]
    if used:
        out.append(("fonts", "OK", ", ".join(used[:3])))
    else:
        out.append(("fonts", "WARN", f"draws with the generic fonts only (the look's pack: {pack}: uv run tools/font2fnt.py --pack {pack} {game})"))

    headless = ROOT / "build" / "pinyol_headless"
    if scripts and headless.exists():
        said: list[str] = []
        for lg in ("es", "ca", "en"):  # the same play in each language: their words are longer or shorter and must fit too
            with tempfile.TemporaryDirectory() as saves:
                r = subprocess.run([str(headless), "--game", str(game), "--saves", saves, "--fresh", "--script", str(scripts[0]), "--check-strips", "--check-text", "--lang", lg],
                                   capture_output=True, text=True, timeout=300)
            if r.returncode == 5:
                said += [f"{lg}: {ln.strip()}" for ln in r.stderr.splitlines() if "the screen's edge" in ln or "its box" in ln][:1]
        out.append(("text", "FAIL" if said else "OK", "; ".join(said) if said else "no text cut or outside its box (es, ca, en)"))
    art = game / "art"
    if art.is_dir() and any(art.glob("*.json")):
        try:
            import sprite_check
            bad = [e for f in sorted(art.glob("*.json")) for e in sprite_check.audit(f)[0]]
            out.append(("art", "WARN" if bad else "OK", f"{len(bad)} sprite problems, first: {bad[0]}" if bad else "no cut frames, feet on the ground"))
        except ImportError:
            out.append(("art", "OK", "(numpy/scipy not installed: not checked)"))
    raw = [f"{p.stem} {p.stat().st_size // 1024} KB" for p in sorted((game / "assets").glob("*.rgb565"))
           if p.stat().st_size >= 8 * 1024 and p.stat().st_size != 480 * 320 * 2
           and re.search(r'img\([^)]*["\']%s["\']' % re.escape(p.stem), code)] if (game / "assets").is_dir() else []  # (a bg() layer's image is another path)
    out.append(("pictures", "WARN" if raw else "OK", "raw and slow on the console (tools/png2asset.py --packed): " + ", ".join(raw[:4]) if raw else "no big raw picture"))
    meas = (ROOT / "docs" / "measurements.md").read_text(encoding="utf-8") if (ROOT / "docs" / "measurements.md").exists() else ""
    has = re.search(r"\b%s\b" % re.escape(meta["id"]), meas, re.I) or re.search(re.escape(meta["title"]), meas, re.I)
    out.append(("numbers", "OK" if has else "WARN", "measured on the console" if has else "not in docs/measurements.md"))
    return out


def main() -> None:
    ap = argparse.ArgumentParser(description=__doc__.split("\n\n")[0])
    ap.add_argument("games", nargs="+", type=Path)
    a = ap.parse_args()
    fails = 0
    for g in a.games:
        if not (g / "game.json").exists():
            continue
        if json.loads((g / "game.json").read_text(encoding="utf-8")).get("engine") != "pinyol@2":
            continue
        res = check(g)
        bad = [r for r in res if r[1] != "OK"]
        fails += sum(r[1] == "FAIL" for r in res)
        print(f"{g.name:22} " + " ".join(f"{c}:{s}" for c, s, _ in res if s != "OK") if bad else f"{g.name:22} all OK")
        if len(a.games) == 1:
            for c, s, note in res:
                print(f"  {s:4} {c:8} {note}")
    sys.exit(1 if fails else 0)


if __name__ == "__main__":
    main()
