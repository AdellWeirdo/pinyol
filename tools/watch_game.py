#!/usr/bin/env python3
"""Plays a game on the console while you make it: each time you save one of its files it goes over the USB cable
into the game there, which starts again with it; what the game logs (log, print) and its errors show here.

    uv run --with pyserial tools/watch_game.py games/mygame              # sends it whole once, then what changes
    uv run --with pyserial tools/watch_game.py games/mygame --no-first   # it is on the console already
    uv run --with pyserial tools/watch_game.py games/mygame --all-log    # the console's whole log, not only the game's

Ctrl-C to stop. The simulator does the same on the desktop by itself (bp_sim reloads a game when a file is saved).
"""
import argparse
import glob
import sys
import time
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent))
from send_game import Cable, files_of, send  # noqa: E402

GAME_LINES = ("lua", "script", "error", "Lua", "panic", "Guru")  # what a game's maker wants to see of the log


def stamps(folder: Path) -> dict[str, float]:
    _, files = files_of(folder)
    return {rel: (folder / rel).stat().st_mtime for rel in files}


def pump(c: Cable, all_log: bool) -> None:
    """Prints the console's log lines that came in (its answers are for send())."""
    c.buf += c.s.read(c.s.in_waiting or 0)
    while b"\n" in c.buf:
        raw, c.buf = c.buf.split(b"\n", 1)
        text = raw.decode(errors="replace").rstrip()
        if text and not text.startswith("@np2d") and (all_log or text.startswith(GAME_LINES)):
            print(f"  {text}", flush=True)


def main() -> None:
    ap = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    ap.add_argument("game", type=Path, help="the game's folder")
    ap.add_argument("--port", help="the console's serial port (default: the first /dev/cu.usbmodem*)")
    ap.add_argument("--no-first", action="store_true", help="do not send it whole first: it is on the console")
    ap.add_argument("--all-log", action="store_true", help="show the console's whole log")
    ap.add_argument("--every", type=float, default=0.4, help="seconds between looks at the folder")
    a = ap.parse_args()
    if not (a.game / "game.json").exists():
        raise SystemExit(f"{a.game}: not a game folder (no game.json)")
    port = a.port or next(iter(sorted(glob.glob("/dev/cu.usbmodem*") + glob.glob("/dev/ttyACM*"))), None)
    if not port:
        raise SystemExit("no console on a USB port: plug it in, or give --port")
    c = Cable(port)
    print(f"{port}: {c.ask('hello')}")
    gid, files = files_of(a.game)
    if not a.no_first:
        t = time.time()
        send(c, gid, files, patch=False)
        print(f"\r{gid}: sent whole ({sum(map(len, files.values())) // 1024} KB) in {time.time() - t:.1f} s")
    seen = stamps(a.game)
    print(f"watching {a.game}: save a file and it is on the console a moment later (Ctrl-C to stop)", flush=True)
    try:
        while True:
            pump(c, a.all_log)
            time.sleep(a.every)
            now = stamps(a.game)
            changed = sorted(r for r, m in now.items() if seen.get(r) != m)
            if not changed:
                continue
            time.sleep(0.15)  # an editor may still be writing it
            _, files = files_of(a.game)
            t = time.time()
            send(c, gid, {r: files[r] for r in changed if r in files}, patch=True, quiet=True)
            print(f"{time.strftime('%H:%M:%S')} {', '.join(changed)} -> the console ({time.time() - t:.1f} s)", flush=True)
            seen = stamps(a.game)
    except KeyboardInterrupt:
        print()


if __name__ == "__main__":
    main()
