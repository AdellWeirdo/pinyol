#!/usr/bin/env python3
"""A FamiStudio song (File > Export > FamiStudio Text) as a ProTracker module the console plays with music():
    python3 tools/famistudio2mod.py song.txt games/mygame/audio/SONG.mod [--song "Song 1"]
The NES's four tracker channels go to the module's four: Square1, Square2, Triangle and Noise (DPCM is left out). A
square instrument becomes a one-period sample of its duty (12.5, 25, 50 or 75 %), the triangle a 32-step one, the
noise a burst of noise; a note of the song is a row, so the speed is the song's NoteLength (frames a note) at a tempo
of 150 (a tick a frame, 60 a second), and the volume envelope is followed row by row with volume commands. Arpeggio
and pitch envelopes are left out (ponytail: add them as 0xy and 1xx/2xx when a song needs them). Stop and Release
notes cut the sound; Duration too. The loop point is the module's restart.
"""
from __future__ import annotations

import argparse
import re
import struct
import sys
from pathlib import Path

NOTE_INDEX = {"C": 0, "C#": 1, "D": 2, "D#": 3, "E": 4, "F": 5, "F#": 6, "G": 7, "G#": 8, "A": 9, "A#": 10, "B": 11}
# ProTracker periods, C-1 to B-3; the samples are tuned so that C-2 (period 428) sounds the NES's C4
PERIODS = [856, 808, 762, 720, 678, 640, 604, 570, 538, 508, 480, 453, 428, 404, 381, 360, 339, 320, 302, 285, 269, 254,
           240, 226, 214, 202, 190, 180, 170, 160, 151, 143, 135, 127, 120, 113]
CHANNELS = ["Square1", "Square2", "Triangle", "Noise"]
DUTIES = [0.125, 0.25, 0.5, 0.75]


def parse(text: str) -> list[tuple[int, str, dict[str, str]]]:
    out = []
    for line in text.splitlines():
        if not line.strip():
            continue
        indent = len(line) - len(line.lstrip("\t "))
        body = line.strip()
        tag = body.split(" ", 1)[0]
        attrs = dict(re.findall(r'(\w+)="([^"]*)"', body))
        out.append((indent, tag, attrs))
    return out


def period_of(value: str) -> int | None:
    m = re.fullmatch(r"([A-G]#?)(-?\d)", value)
    if not m:
        return None
    semis = NOTE_INDEX[m.group(1)] + 12 * (int(m.group(2)) - 4) + 12  # C4 -> index 12 (period 428)
    semis = max(0, min(len(PERIODS) - 1, semis))
    return PERIODS[semis]


def sample_square(duty: float) -> bytes:
    return bytes([100 if i / 32 < duty else 156 for i in range(32)])  # +100 / -100 (signed 8-bit)


def sample_triangle() -> bytes:
    return bytes([(i * 8 if i < 16 else (31 - i) * 8) - 64 & 255 for i in range(32)])


def sample_noise(seed: int = 7) -> bytes:
    x, out = seed, bytearray()
    for _ in range(512):
        x = (x * 1103515245 + 12345) & 0x7FFFFFFF
        out.append(((x >> 16) & 255) - 128 & 255)
    return bytes(out)


def convert(text: str, song_name: str | None = None) -> bytes:
    rows = parse(text)
    instruments: dict[str, dict] = {}
    songs: list[dict] = []
    cur_inst = cur_song = cur_chan = cur_pat = None
    for indent, tag, a in rows:
        if tag == "Instrument":
            cur_inst = {"name": a.get("Name", ""), "volume": [15], "duty": 2}
            instruments[cur_inst["name"]] = cur_inst
        elif tag == "Envelope" and cur_inst is not None:
            vals = [int(v) for v in a.get("Values", "").split(",") if v.strip()]
            if a.get("Type") == "Volume" and vals:
                cur_inst["volume"] = vals
            elif a.get("Type") == "DutyCycle" and vals:
                cur_inst["duty"] = max(0, min(3, vals[0]))
        elif tag == "Song":
            cur_song = {"name": a.get("Name", ""), "length": int(a.get("Length", "1")), "loop": int(a.get("LoopPoint", "0")),
                        "pattern_length": int(a.get("PatternLength", "16")), "note_length": int(a.get("NoteLength", "10")),
                        "channels": {}}
            songs.append(cur_song)
            cur_inst = None
        elif tag == "Channel" and cur_song is not None:
            cur_chan = {"patterns": {}, "instances": {}}
            cur_song["channels"][a.get("Type", "")] = cur_chan
        elif tag == "Pattern" and cur_chan is not None:
            cur_pat = []
            cur_chan["patterns"][a.get("Name", "")] = cur_pat
        elif tag == "Note" and cur_pat is not None:
            cur_pat.append(a)
        elif tag == "PatternInstance" and cur_chan is not None:
            cur_chan["instances"][int(a.get("Time", "0"))] = a.get("Pattern", "")
    if not songs:
        raise SystemExit("famistudio2mod: no Song in the text")
    song = next((s for s in songs if s["name"] == song_name), songs[0]) if song_name else songs[0]
    plen, nlen = song["pattern_length"], max(1, min(31, song["note_length"]))
    if plen > 64:
        raise SystemExit(f"famistudio2mod: a pattern of {plen} notes does not fit a module's 64 rows")

    # the samples: one per duty used, the triangle, the noise
    samples: list[tuple[str, bytes, bool]] = []  # name, data, looped
    sample_of: dict[str, int] = {}

    def sample_index(key: str, make) -> int:
        if key not in sample_of:
            samples.append((key, *make()))
            sample_of[key] = len(samples)
        return sample_of[key]

    # the module's patterns: one per song position, 64 rows x 4 channels
    patterns: list[bytearray] = []
    for pos in range(song["length"]):
        pat = bytearray(64 * 4 * 4)
        for ch, ch_name in enumerate(CHANNELS):
            chan = song["channels"].get(ch_name)
            if not chan:
                continue
            notes = chan["patterns"].get(chan["instances"].get(pos, ""), [])
            held: dict | None = None  # the instrument sounding, and the row it began on, for its envelope
            events: dict[int, tuple] = {}
            for n in notes:
                t = int(n.get("Time", "0"))
                if t >= plen:
                    continue
                value = n.get("Value", "")
                if value in ("Stop", "Release"):
                    events[t] = ("stop",)
                    continue
                period = period_of(value)
                if period is None:
                    continue
                inst = instruments.get(n.get("Instrument", ""), {"volume": [15], "duty": 2})
                if ch_name == "Triangle":
                    smp = sample_index("triangle", lambda: (sample_triangle(), True))
                elif ch_name == "Noise":
                    smp = sample_index("noise", lambda: (sample_noise(), True))
                else:
                    duty = inst["duty"]
                    smp = sample_index(f"square{duty}", lambda d=duty: (sample_square(DUTIES[d]), True))
                dur = n.get("Duration")
                events[t] = ("note", period, smp, inst, int(dur) if dur else None)
            for row in range(plen):
                cell = row * 16 + ch * 4
                ev = events.get(row)
                vol = None
                if ev and ev[0] == "note":
                    _, period, smp, inst, dur = ev
                    held = {"inst": inst, "start": row, "end": row + max(1, dur // nlen) if dur else None}
                    vol = inst["volume"][0]
                    pat[cell] = ((smp >> 4) << 4) | (period >> 8)
                    pat[cell + 1] = period & 255
                    pat[cell + 2] = (smp & 15) << 4
                elif ev and ev[0] == "stop":
                    held = None
                    vol = 0
                elif held is not None:
                    if held["end"] is not None and row >= held["end"]:
                        held = None
                        vol = 0
                    else:
                        env = held["inst"]["volume"]
                        k = (row - held["start"]) * nlen
                        vol = env[min(len(env) - 1, k)]  # the envelope's value, a frame a step, at this row's first frame
                if vol is not None:
                    pat[cell + 2] |= 0xC
                    pat[cell + 3] = max(0, min(64, vol * 4 + (4 if vol == 15 else 0)))
            if plen < 64 and ch == 3:  # the pattern ends where the song's does
                cell = (plen - 1) * 16 + ch * 4
                if pat[cell + 2] & 15 == 0:
                    pat[cell + 2] |= 0xD
                    pat[cell + 3] = 0
        if pos == 0:  # the tempo (a tick a frame) on the triangle's first cell, the speed (the note length) on the noise's: a
            # volume there on the first row gives way (the samples start at full volume anyway)
            for ch, param in ((2, 150), (3, nlen)):
                cell = ch * 4
                pat[cell + 2] = (pat[cell + 2] & 0xF0) | 0xF
                pat[cell + 3] = param
        patterns.append(pat)
    if not samples:
        samples.append(("square2", sample_square(0.5), True))

    header = song["name"].encode("latin-1", "replace")[:20].ljust(20, b"\0")
    for i in range(31):
        if i < len(samples):
            name, data, looped = samples[i]
            words = len(data) // 2
            header += name.encode("ascii", "replace")[:22].ljust(22, b"\0") + struct.pack(">HBBHH", words, 0, 64, 0, words if looped else 1)
        else:
            header += bytes(22) + struct.pack(">HBBHH", 0, 0, 0, 0, 1)
    length = len(patterns)
    order = bytes(range(length)) + bytes(128 - length)
    header += bytes([length, max(0, min(length - 1, song["loop"]))]) + order + b"M.K."
    body = b"".join(bytes(p) for p in patterns) + b"".join(data for _, data, _ in samples)
    return header + body


def main() -> None:
    ap = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    ap.add_argument("text", type=Path, help="the FamiStudio text export")
    ap.add_argument("out", type=Path, help="the module to write (games/<game>/audio/<ID>.mod)")
    ap.add_argument("--song", help="which song of the project (the first by default)")
    a = ap.parse_args()
    data = convert(a.text.read_text(encoding="utf-8"), a.song)
    a.out.write_bytes(data)
    print(f"{a.out}: {len(data)} bytes")


if __name__ == "__main__":
    main()
