"""kit.lua: a kind with a pivot turns round it (its pivot's column stays put), one without turns round the middle of its
box, as it always did. The game draws each picture blue with its column 1 red; this reads where the red lands.

    python3 tests/kitflip_test.py build/pinyol_headless
"""
import subprocess
import sys
import tempfile
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
headless = Path(sys.argv[1]).resolve()


def red_columns(ppm: Path, top: int, bottom: int) -> tuple[int, int]:
    d = ppm.read_bytes()
    _, w, h, _ = d.split(None, 4)[:4]
    w, h = int(w), int(h)
    px = d[len(d) - w * h * 3:]
    xs = [x for y in range(top, bottom) for x in range(w) if px[(y * w + x) * 3] > 200 and px[(y * w + x) * 3 + 2] < 60]
    assert xs, f"no red in rows {top}..{bottom} of {ppm.name}"
    return min(xs), max(xs)


with tempfile.TemporaryDirectory() as t:
    t = Path(t)
    script = t / "flip.script"
    script.write_text("new\ntick 5\nshot plain\nlua flipped = true\ntick 5\nshot flipped\nexpect_ok\n", encoding="utf-8")
    r = subprocess.run([str(headless), "--game", str(ROOT / "tests/games/kitflip"), "--saves", str(t), "--fresh",
                        "--script", str(script)], capture_output=True, text=True, timeout=120)
    assert r.returncode == 0, r.stdout + r.stderr
    rows = {"giro": (40, 56), "caja": (120, 136)}  # (y 20 and 60 in the world, drawn twice as big)
    before = {k: red_columns(t / "plain.ppm", *v) for k, v in rows.items()}
    after = {k: red_columns(t / "flipped.ppm", *v) for k, v in rows.items()}
    assert after["giro"] == before["giro"], (before, after)            # round its pivot: the red column stays
    assert after["caja"] == (before["caja"][0] + 10, before["caja"][1] + 10), (before, after)  # round the box: 6 - 1 = 5 px away, twice
print("kitflip: a pivot stays put when it turns; without one it turns as before")
