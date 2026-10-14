#!/usr/bin/env python3
"""Sends a game to the console over its USB cable: it is written to the card (or the flash) and starts at once.

    uv run --with pyserial tools/send_game.py games/mygame            # a game folder
    uv run --with pyserial tools/send_game.py dist/mygame.zip         # or the editor's zip
    uv run --with pyserial tools/send_game.py games/mygame --port /dev/cu.usbmodem101
    uv run --with pyserial tools/send_game.py games/mygame --only 'assets/*_HD.*'   # some files, into the game there

The console's side is firmware/main/cable.c (the protocol is described there); pinyol's editor does the same from the
browser. Saves, art sources and dot files are not sent.
"""
from __future__ import annotations

import argparse
import fnmatch
import base64
import glob
import io
import json
import sys
import time
import zipfile
from pathlib import Path

CHUNK = 768
SKIP = ("saves", "art")


def files_of(src: Path) -> tuple[str, dict[str, bytes]]:
    """The game's id and its files by path inside it."""
    out: dict[str, bytes] = {}
    if src.suffix == ".zip":
        z = zipfile.ZipFile(io.BytesIO(src.read_bytes()))
        names = [n for n in z.namelist() if not n.endswith("/")]
        tops = {n.split("/")[0] for n in names}
        if len(tops) != 1:
            raise SystemExit(f"{src}: a game's zip has one folder inside")
        top = tops.pop()
        for n in names:
            out[n[len(top) + 1:]] = z.read(n)
    else:
        top = src.resolve().name
        for p in sorted(src.rglob("*")):
            rel = p.relative_to(src).as_posix()
            if p.is_file() and not any(part.startswith(".") for part in rel.split("/")) and rel.split("/")[0] not in SKIP \
                    and p.name != "art.py":
                out[rel] = p.read_bytes()
    if "game.json" not in out:
        raise SystemExit(f"{src}: no game.json, not a game")
    gid = json.loads(out["game.json"]).get("id") or top
    return gid, out


class Cable:
    def __init__(self, port: str):
        import serial  # pyserial

        self.s = serial.Serial()
        self.s.port, self.s.baudrate, self.s.timeout = port, 115200, 0.2
        self.s.dtr = self.s.rts = False  # opening must not reset the console
        self.s.open()
        self.buf = b""

    def answer(self, timeout: float) -> str:
        """The console's next answer ("@pinyol ..."), skipping its log."""
        end = time.time() + timeout
        while time.time() < end:
            while b"\n" in self.buf:
                raw, self.buf = self.buf.split(b"\n", 1)
                text = raw.decode(errors="replace").strip()
                for tag in ("@pinyol ", "@np2d "):  # np2d: firmware from before the engine's rename
                    if text.startswith(tag):
                        return text[len(tag):]
            self.buf += self.s.read(self.s.in_waiting or 1)  # what is there, or a byte: never the whole timeout
        raise SystemExit("the console does not answer (is it on, with firmware that has the cable?)")

    def ask(self, line: str, timeout: float = 5) -> str:
        self.s.write(line.encode() + b"\n")
        a = self.answer(timeout)
        if a.startswith("err"):
            raise SystemExit(f"the console says: {a[4:]}")
        return a


def main() -> None:
    ap = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    ap.add_argument("game", type=Path, help="a game folder or a game's zip")
    ap.add_argument("--port", help="the console's serial port (default: the first /dev/cu.usbmodem*)")
    ap.add_argument("--only", nargs="+", metavar="GLOB",
                    help="send only these files ('assets/*_HD.*'), added to the game already on the console")
    a = ap.parse_args()
    gid, files = files_of(a.game)
    if a.only:
        files = {r: b for r, b in files.items() if any(fnmatch.fnmatch(r, g) for g in a.only)}
        if not files:
            raise SystemExit("--only: no file of the game matches")
    port = a.port or next(iter(sorted(glob.glob("/dev/cu.usbmodem*") + glob.glob("/dev/ttyACM*"))), None)
    if not port:
        raise SystemExit("no console on a USB port: plug it in, or give --port")
    total = sum(len(b) for b in files.values())
    c = Cable(port)
    print(f"{port}: {c.ask('hello')}")
    t0 = time.time()
    send(c, gid, files, patch=bool(a.only))
    print(f"\r{gid}: {len(files)} files, {total // 1024} KB in {time.time() - t0:.1f} s; it is starting on the console")


def send(c: Cable, gid: str, files: dict[str, bytes], patch: bool, quiet: bool = False) -> None:
    """The files over the cable: all of the game (begin), or some into the game already there (patch)."""
    total = sum(len(b) for b in files.values())
    c.ask(f"{'patch' if patch else 'begin'} {gid} {total}", timeout=15)  # the game playing stops first
    sent = 0
    for rel, data in files.items():
        c.ask(f"file {rel} {len(data)}")
        for i in range(0, len(data), CHUNK):
            c.ask("data " + base64.b64encode(data[i:i + CHUNK]).decode())
            sent += len(data[i:i + CHUNK])
            if i % (CHUNK * 32) == 0 and not quiet:
                print(f"\r{gid}: {sent * 100 // total} %", end="", file=sys.stderr)
    c.ask("end", timeout=30)


if __name__ == "__main__":
    main()
