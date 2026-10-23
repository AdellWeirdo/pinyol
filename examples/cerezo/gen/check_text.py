"""The words of Cerezo checked: every language has every knot of the Spanish story, every letter the stories use is in the
game's font, and no choice is wider than the dialogue window can show.

    python3 examples/cerezo/gen/check_text.py        # exit code 1 when something is wrong
"""
from __future__ import annotations

import re
import sys
from pathlib import Path

HERE = Path(__file__).resolve().parent.parent
FONT = HERE / "fonts" / "ps.fnt"
GLYPH_W = 8   # world pixels a letter takes in the font (it is monospaced)
CHOICE_MAX = 22  # letters a choice may have: the window's inner width less the cursor


def font_coverage(path: Path) -> set[int]:
    d = path.read_bytes()
    return {i for i in range(256) if d[8 + i] != 0}


def knots(text: str) -> dict[str, list[str]]:
    out, cur = {}, None
    for line in text.splitlines():
        m = re.match(r"^== (\w+)\s*$", line)
        if m:
            cur = m.group(1)
            out[cur] = []
        elif cur and line.strip() and not line.lstrip().startswith("//"):
            out[cur].append(line)
    return out


def spoken(line: str) -> str:
    """The words of a line of the story, without its markup ([if ...], [do ...], the choice mark, the target)."""
    line = re.sub(r"\[(if|do|var)[^\]]*\]", "", line)
    line = re.sub(r"->\s*\w+\s*$", "", line)
    line = re.sub(r"^\s*[*+]\s*", "", line)
    return line.strip()


def main() -> int:
    have = font_coverage(FONT)
    problems = 0
    stories = {p.stem: knots(p.read_text(encoding="utf-8")) for p in sorted((HERE / "story").glob("*.txt"))}
    base = stories.get("es", {})
    for lang, ks in stories.items():
        missing = sorted(set(base) - set(ks))
        extra = sorted(set(ks) - set(base))
        if missing:
            problems += 1
            print(f"{lang}: lacks knots {', '.join(missing[:12])}{' ...' if len(missing) > 12 else ''}")
        if extra and lang != "es":
            print(f"{lang}: knots not in es: {', '.join(extra)}")
        lacking = set()
        for name, lines in ks.items():
            for line in lines:
                words = spoken(line)
                for ch in words:
                    try:
                        code = ch.encode("cp1252")[0]
                    except UnicodeEncodeError:
                        lacking.add(ch)
                        continue
                    if code not in have and ch not in "{}|&~!\n":
                        lacking.add(ch)
                if re.match(r"^\s*[*+]", line) and len(words) > CHOICE_MAX:
                    problems += 1
                    print(f"{lang}:{name}: a choice of {len(words)} letters (max {CHOICE_MAX}): {words}")
        if lacking:
            problems += 1
            print(f"{lang}: the font lacks {' '.join(sorted(lacking))}")
    if not problems:
        print(f"stories {', '.join(stories)}: {len(base)} knots, every letter in the font, choices fit")
    return 1 if problems else 0


if __name__ == "__main__":
    sys.exit(main())
