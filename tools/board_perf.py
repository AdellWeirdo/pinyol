# /// script
# requires-python = ">=3.10"
# dependencies = ["pyserial>=3"]
# ///
"""Measures a game on the console: a silent copy of it (the sound off, so the numbers are the picture's) is sent over USB, left running for
a while, and the console's own perf lines are summed up: frames a second, the time each frame takes, the free memory, and any error.

    uv run tools/board_perf.py examples/cerezo                       # 40 s of the game as it starts (its demo, if it has one)
    uv run tools/board_perf.py examples/paella --seconds 90 --drive tour.lua   # the Lua in tour.lua is appended: a bot, a tour of the levels
    uv run tools/board_perf.py games/mygame --tour                  # the route in games/mygame/tour.lua, a line of figures for each step
    uv run tools/board_perf.py games/mygame --port /dev/cu.usbmodem101

--tour [FILE.lua]: a route through the game, one measurement per step. The game keeps it in `tour.lua` (or FILE): `return {{10, 'dbg_play("vera", 1, 300) dbg_god() dbg_bot()'}, {10, "dbg_boss()"}}`,
each step the seconds to stay in it and the Lua to run when it starts (the game's own test hooks: dbg_play, dbg_bot...). The sound is off; the log is cut by step.

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
SKIP = shutil.ignore_patterns("art", "raw", "saves", "tests", "gen", "docs", ".git", "__pycache__", "*.script", "preview_*")


def silent_copy(game: Path, out: Path, drive: Path | None) -> None:
    shutil.copytree(game, out, ignore=SKIP)
    main = out / "main.lua"
    if not main.exists():
        sys.exit(f"{game}: no main.lua (board_perf is for Lua games, pinyol@2)")
    extra = "\n-- board_perf.py: drive\n" + drive.read_text(encoding="utf-8") + "\n" if drive else ""
    main.write_text(main.read_text(encoding="utf-8") + SILENT + extra, encoding="utf-8")


TOUR_DRIVER = """
-- board_perf.py: the tour (tour.lua): each step runs its code when it starts and lasts its seconds
do
  local __tour, __i, __left, __upd = require("tour"), 0, 0, _update
  function _update(...)
    volume(0)
    if __left <= 0 and __tour[__i + 1] then
      __i = __i + 1
      __left = __tour[__i][1] * 60
      print("TOUR", __i, __tour[__i][2])
      local f = load(__tour[__i][2])
      if f then f() end
    end
    __left = __left - 1
    return __upd(...)
  end
end
"""


def by_step(text: str) -> list[tuple[str, list[float]]]:
    """The fps samples after each `TOUR n code` line of the log, until the next one: [(label, [fps...])]."""
    steps: list[tuple[str, list[float]]] = []
    for line in text.splitlines():
        m = re.search(r"lua: TOUR (\d+) (.*)", line)
        if m:
            steps.append((f"{m[1]} {m[2][:48]}", []))
            continue
        m = re.search(r"perf: .*?, ([\d.]+) fps", line)
        if m and steps:
            steps[-1][1].append(float(m[1]))
    return steps


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
    steps = by_step(text)
    if steps:
        lines.append("by step:")
        lines += [f"  {lab:50} fps min {min(f):5.1f} mean {statistics.mean(f):5.1f} ({len(f)} samples)" for lab, f in steps if f]
    return "\n".join(lines), ok


def eval_steps(path: Path) -> list[tuple[float, str]]:
    """The steps of a tour file (`return {{seconds, "code"}, ...}`), read without running a Lua: only to add up the seconds."""
    text = path.read_text(encoding="utf-8")
    return [(float(m[1]), m[3]) for m in re.finditer(r"\{\s*([\d.]+)\s*,\s*(['\"])(.*?)\2\s*\}", text)]


def main() -> None:
    p = argparse.ArgumentParser(description=__doc__.split("\n\n")[0])
    p.add_argument("game", type=Path)
    p.add_argument("--seconds", type=int, default=40, help="how long to watch (default 40)")
    p.add_argument("--drive", type=Path, help="Lua appended to main.lua: a bot or a tour")
    p.add_argument("--tour", nargs="?", const="tour.lua", metavar="FILE", help="a route through the game, measured step by step (tour.lua of the game by default)")
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
        drive = a.drive
        if a.tour:
            src = a.game / a.tour if (a.game / a.tour).exists() else Path(a.tour)
            if not src.exists():
                sys.exit(f"{a.tour}: no tour (a Lua file that returns {{{{seconds, code}}, ...}})")
            tour = eval_steps(src)
            a.seconds = a.seconds if a.seconds != 40 else int(sum(t[0] for t in tour)) + 8
            drive = None
        silent_copy(a.game, copy, drive)
        if a.tour:
            shutil.copy(src, copy / "tour.lua")
            main_lua = copy / "main.lua"
            main_lua.write_text(main_lua.read_text(encoding="utf-8") + TOUR_DRIVER, encoding="utf-8")
        r = subprocess.run([sys.executable, str(HERE / "send_game.py"), str(copy), "--port", a.port, "--log", str(a.seconds)], capture_output=True, text=True)
    text = r.stdout + r.stderr
    report, ok = summarize(text)
    print(f"{a.game.name} on the console:\n{report}")
    sys.exit(0 if ok else 1)


if __name__ == "__main__":
    main()
