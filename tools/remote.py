# /// script
# requires-python = ">=3.11"
# dependencies = ["pyserial", "pillow"]
# ///
"""Drive a -DBP_REMOTE=ON console over its USB cable (firmware/main/remote.c) and keep its log.

    uv run tools/remote.py [--port P] [--log FILE] STEP...

Steps, in order:
    tap:X,Y          a finger at (X, Y) on the 480x320 screen
    key:NAME[,N]     A, B, C, UP, DOWN, LEFT, RIGHT, START or MENU, held N polls (a few by default)
    lua:CODE         pinyol@2: runs CODE in the game; print() answers in the log (until: can wait for it)
    wait:SECONDS     let it run
    until:TEXT[,S]   wait for a log line containing TEXT (at most S seconds, 60 by default); fails if it never comes
    shot:FILE.png    the frame on the panel

The port is opened without resetting the board. Log lines are printed as they come; exit status 1 if an until fails.
"""

import argparse
import base64
import sys
import time

import serial
from PIL import Image


class Console:
    def __init__(self, port: str, log_path: str | None):
        self.s = serial.Serial(port, 115200, timeout=0.2)
        self.log = open(log_path, "a", encoding="utf-8") if log_path else None
        self.buf = b""
        self.seen: list[str] = []  # every line since the last until matched, so a fast reply is not missed

    def lines(self, seconds: float):
        """Yields the log lines that arrive within the given time."""
        end = time.time() + seconds
        while time.time() < end:
            self.buf += self.s.read(65536)
            while b"\n" in self.buf:
                raw, self.buf = self.buf.split(b"\n", 1)
                yield raw.decode(errors="replace").rstrip("\r")

    def note(self, line: str):
        self.seen.append(line)
        if line.startswith("audio ") and "missing" in line:
            return  # the flash copy's silent music, once per track
        print(line, flush=True)
        if self.log:
            self.log.write(line + "\n")
            self.log.flush()

    def send(self, cmd: str):
        self.s.write((cmd + "\n").encode())

    def wait(self, seconds: float, text: str | None = None) -> bool:
        if text and any(text in line for line in self.seen):
            self.seen.clear()
            return True
        for line in self.lines(seconds):
            self.note(line)
            if text and text in line:
                self.seen.clear()
                return True
        return text is None

    def shot(self, path: str) -> bool:
        self.send("shot")
        rows, size = [], None
        for line in self.lines(30):
            if line.startswith("SHOT END"):
                break
            if line.startswith("SHOT "):
                size = tuple(int(v) for v in line.split()[1:3])
            elif size and len(rows) < size[1] and len(line) > 100:
                try:
                    rows.append(base64.b64decode(line, validate=True))
                except ValueError:
                    print(f"shot: bad row {len(rows)} ({len(line)} chars): {line[:60]}...{line[-60:]}", file=sys.stderr)
                    return False
            else:
                self.note(line)
        if not size or len(rows) != size[1]:
            print(f"shot: incomplete ({len(rows)} rows)", file=sys.stderr)
            return False
        w, h = size
        img = Image.new("RGB", (w, h))
        px = img.load()
        for y, row in enumerate(rows):
            for x in range(w):
                c = row[2 * x] | row[2 * x + 1] << 8
                px[x, y] = ((c >> 11) * 255 // 31, ((c >> 5) & 63) * 255 // 63, (c & 31) * 255 // 31)
        img.save(path)
        print(f"shot: {path}", flush=True)
        return True


def main() -> int:
    ap = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    ap.add_argument("--port", default="/dev/cu.usbmodem1101")
    ap.add_argument("--log")
    ap.add_argument("steps", nargs="+")
    a = ap.parse_args()
    con = Console(a.port, a.log)
    for step in a.steps:
        kind, _, arg = step.partition(":")
        if kind == "tap":
            x, y = arg.split(",")
            con.send(f"tap {int(x)} {int(y)}")
            con.wait(0.5)
        elif kind == "key":
            name, _, n = arg.partition(",")
            con.send(f"key {name.upper()} {n}".rstrip())
            con.wait(0.5)
        elif kind == "lua":
            con.send(f"lua {arg}")
            con.wait(0.2)
        elif kind == "wait":
            con.wait(float(arg))
        elif kind == "until":
            text, _, secs = arg.partition(",")
            if not con.wait(float(secs or 60), text):
                print(f"until: no '{text}'", file=sys.stderr)
                return 1
        elif kind == "shot":
            if not con.shot(arg):
                return 1
        else:
            print(f"unknown step {step}", file=sys.stderr)
            return 2
    return 0


if __name__ == "__main__":
    sys.exit(main())
