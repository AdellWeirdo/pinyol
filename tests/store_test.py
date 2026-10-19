"""store(): the saves are two files written in turn, each with a generation and a checksum.

A save that is cut, torn or altered is not believed; the one before it is. A save that fails leaves the last good one alone.

    python3 tests/store_test.py build/pinyol_headless
"""
import re
import subprocess
import sys
import tempfile
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
HEADLESS = Path(sys.argv[1]).resolve()
GAME = ROOT / "tests" / "games" / "storetest"


def run(saves, *lines):
    """The engine on the game, with these script lines; its saves folder is kept between runs."""
    script = saves / "run.script"
    script.write_text("new\n" + "\n".join(lines) + "\nexpect_ok\n", encoding="utf-8")
    r = subprocess.run([str(HEADLESS), "--game", str(GAME), "--saves", str(saves), "--script", str(script)],
                       capture_output=True, text=True, timeout=120)
    out = r.stdout + r.stderr
    return r.returncode == 0 and "PASS" in out, out


def must(ok_out, what):
    ok, out = ok_out
    assert ok, f"{what}:\n{out}"


def fresh(t):
    d = Path(tempfile.mkdtemp(dir=t))
    must(run(d, 'lua store("v", 1) store("v", 2) store("v", 3)'), "three saves")
    return d


with tempfile.TemporaryDirectory() as t:
    t = Path(t)
    a, b = None, None

    # three saves: generations 1 (.b), 2 (the first file), 3 (.b): the newest is v2.json.b with 3, v2.json has 2
    d = fresh(t)
    first, second = d / "v2.json", d / "v2.json.b"
    assert first.exists() and second.exists()
    must(run(d, "expect_lua stored('v') == 3"), "the newest save is read")
    tail = re.search(rb"\n#gen (\d+)( crc ([0-9a-f]{8}))?\n", second.read_bytes())
    assert tail and tail.group(1) == b"3" and tail.group(3), "the file ends with its generation and its checksum"

    # a torn file: one character changed inside the JSON, the length and the tail as they were: not believed, the save before is
    d = fresh(t)
    raw = (d / "v2.json.b").read_bytes()
    (d / "v2.json.b").write_bytes(raw.replace(b'{"v":3}', b'{"v":9}', 1))
    must(run(d, "expect_lua stored('v') == 2"), "an altered save is not believed")

    # a save with no checksum (written by an older engine) is believed as it was
    d = fresh(t)
    raw = (d / "v2.json.b").read_bytes()
    (d / "v2.json.b").write_bytes(re.sub(rb" crc [0-9a-f]{8}", b"", raw, count=1))
    must(run(d, "expect_lua stored('v') == 3"), "a save with no checksum is still read")

    # both files unreadable: the saves are empty, the game starts anew (and can save again)
    d = fresh(t)
    for f in (d / "v2.json", d / "v2.json.b"):
        f.write_bytes(b"{not json")
    must(run(d, "expect_lua stored('v') == nil", 'lua store("v", 7)', "expect_lua stored('v') == 7"), "both lost")

    # a save that cannot be written leaves the last good one alone: the next save goes to the same place, not to the good file
    d = fresh(t)
    good = (d / "v2.json.b").read_bytes()
    target = d / "v2.json"            # the older: where the next save goes
    target.unlink()
    target.mkdir()                    # nothing can be written there
    must(run(d, "expect_lua not pcall(store, 'v', 4)", "expect_lua not pcall(store, 'v', 5)"), "saves that fail raise an error")
    assert (d / "v2.json.b").read_bytes() == good, "a failed save did not touch the last good file"
    target.rmdir()
    must(run(d, "expect_lua stored('v') == 3", 'lua store("v", 6)', "expect_lua stored('v') == 6"), "saving again works")
    must(run(d, "expect_lua stored('v') == 6"), "and it stays")

print("store: ok")
