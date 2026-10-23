# /// script
# requires-python = ">=3.10"
# dependencies = ["pyserial>=3"]
# ///
"""Measures a game on the console: a silent copy of it (the sound off, so the numbers are the picture's) is sent over USB, left running for
a while, and the console's own perf lines are summed up: frames a second, the time each frame takes, the free memory, and any error.

    uv run tools/board_perf.py examples/cerezo                       # 40 s of the game as it starts (its demo, if it has one)
    uv run tools/board_perf.py examples/paella --seconds 90 --drive tour.lua   # the Lua in tour.lua is appended: a bot, a tour of the levels
    uv run tools/board_perf.py games/mygame --port /dev/cu.usbmodem101

--drive FILE.lua: code added at the end of the game's main.lua (it can wrap _update, as the examples' tours do, to start a level and press
buttons; the test hooks of the game are available). The game's own folder is not touched. Check first that nothing else uses the port.
"""
from __future__ import annotations

import argparse
import re
import shutil
import statistics
import subprocess
import sys
import tempfile
from pathlib import Path

HERE = Path(__file__).resolve().parent
SILENT = "\n-- board_perf.py: silent\ndo local __update = _update function _update(...) volume(0) return __update(...) end end\n"
SKIP = shutil.ignore_patterns("art", "saves", "tests", "gen", "docs", ".git", "__pycache__", "*.script", "preview_*")


def silent_copy(game: Path, out: Path, drive: Path | None) -> None:
    shutil.copytree(game, out, ignore=SKIP)
    main = out / "main.lua"
    if not main.exists():
        sys.exit(f"{game}: no main.lua (board_perf is for Lua games, pinyol@2)")
    extra = "\n-- board_perf.py: drive\n" + drive.read_text(encoding="utf-8") + "\n" if drive else ""
    main.write_text(main.read_text(encoding="utf-8") + SILENT + extra, encoding="utf-8")


def summarize(text: str) -> tuple[str, bool]:
    perf = re.findall(r"perf: tick ([\d.]+) ms, render ([\d.]+) ms, present [\d.]+ ms, ([\d.]+) fps.*?free internal (\d+) KB, PSRAM (\d+) KB \(largest block (\d+) KB",
                      text)
    if not perf:
        return "no perf lines: the console did not answer (is the port free? is it in the game list?)\n" + "\n".join(text.splitlines()[-5:]), False
    fps = [float(p[2]) for p in perf]
    lines = [f"{len(perf)} samples (10 s each is the console's pace): fps min {min(fps):.1f}, mean {statistics.mean(fps):.1f}, max {max(fps):.1f}",
             f"render ms: mean {statistics.mean(float(p[1]) for p in perf):.1f}, worst {max(float(p[1]) for p in perf):.1f}; "
             f"free internal RAM at least {min(int(p[3]) for p in perf)} KB; PSRAM free at least {min(int(p[4]) for p in perf)} KB "
             f"(largest block at least {min(int(p[5]) for p in perf)} KB)"]
    lua = re.findall(r"lua: _update ([\d.]+) ms, _draw ([\d.]+) ms, picture ([\d.]+) ms", text)
    if lua:
        lines.append(f"lua: _update mean {statistics.mean(float(l[0]) for l in lua):.2f} ms, _draw {statistics.mean(float(l[1]) for l in lua):.2f} ms, "
                     f"picture {statistics.mean(float(l[2]) for l in lua):.2f} ms")
    bad = [l for l in text.splitlines() if re.search(r"no memory|error|failed|abort|panic|underrun [1-9]|[1-9]\d* underruns", l, re.I) and "0 underruns" not in l]
    ok = not bad
    lines += [f"PROBLEM: {l.strip()[:160]}" for l in bad[:6]] or ["no error or memory message in the log"]
    return "\n".join(lines), ok


def main() -> None:
    p = argparse.ArgumentParser(description=__doc__.split("\n\n")[0])
    p.add_argument("game", type=Path)
    p.add_argument("--seconds", type=int, default=40, help="how long to watch (default 40)")
    p.add_argument("--drive", type=Path, help="Lua appended to main.lua: a bot or a tour")
    p.add_argument("--port", default="/dev/cu.usbmodem2101")
    p.add_argument("--keep", type=Path, help="leave the silent copy here (to look at, or to resend with send_game.py --only)")
    a = p.parse_args()
    if not Path(a.port).exists():
        sys.exit(f"{a.port} is not there: the console is unplugged, asleep, or on another port (ls /dev/cu.usb*)")
    busy = subprocess.run(["lsof", a.port], capture_output=True, text=True).stdout.strip()
    if busy:
        sys.exit(f"{a.port} is in use:\n{busy}")
    with tempfile.TemporaryDirectory() as tmp:
        copy = a.keep or Path(tmp) / a.game.name
        if a.keep and copy.exists():
            shutil.rmtree(copy)
        silent_copy(a.game, copy, a.drive)
        r = subprocess.run([sys.executable, str(HERE / "send_game.py"), str(copy), "--port", a.port, "--log", str(a.seconds)], capture_output=True, text=True)
    text = r.stdout + r.stderr
    report, ok = summarize(text)
    print(f"{a.game.name} on the console:\n{report}")
    sys.exit(0 if ok else 1)


if __name__ == "__main__":
    main()
