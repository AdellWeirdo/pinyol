# /// script
# requires-python = ">=3.10"
# ///
"""The one recording of this example, made here: MUS_CAPAS, music in three layers, one per channel of the WAV
(drums, bass, melody), which music_layer() brings in and out. Everything else it plays is made by sound() in
main.lua.

    python3 examples/sonidos/art.py
"""
from __future__ import annotations

import math
import random
import struct
import wave
from pathlib import Path

HERE = Path(__file__).resolve().parent
HZ, BPM, BARS = 22050, 112, 4
BEAT = HZ * 60 // BPM


def note(midi: int) -> float:
    return 440 * 2 ** ((midi - 69) / 12)


def main() -> None:
    n = BEAT * 4 * BARS
    drums, bass, melody = [0.0] * n, [0.0] * n, [0.0] * n
    rnd = random.Random(7)
    for b in range(4 * BARS):  # kick on 1 and 3, a snare on 2 and 4, hats between
        start = b * BEAT
        for i in range(BEAT // 2):
            t = i / HZ
            if b % 2 == 0:
                drums[start + i] += 0.7 * math.sin(2 * math.pi * (110 - 70 * min(1, t * 20)) * t) * math.exp(-t * 18)
            else:
                drums[start + i] += 0.35 * (rnd.random() * 2 - 1) * math.exp(-t * 25)
        for i in range(BEAT // 8):
            drums[start + BEAT // 2 + i] += 0.12 * (rnd.random() * 2 - 1) * math.exp(-i / HZ * 60)
    roots = [45, 41, 43, 40]  # A F G E: one chord a bar
    for bar, root in enumerate(roots):
        for b in range(8):  # bass in eighths
            start = bar * 4 * BEAT + b * BEAT // 2
            f = note(root - (0 if b % 2 == 0 else -12))
            for i in range(BEAT // 2):
                t = i / HZ
                bass[start + i] += 0.35 * (2 * ((f * t) % 1) - 1) * math.exp(-t * 6)
        tune = [root + 24 + k for k in (0, 7, 12, 7, 3, 7, 12, 15)]
        for b, m in enumerate(tune):  # an arpeggio on top
            start = bar * 4 * BEAT + b * BEAT // 2
            f = note(m)
            for i in range(BEAT // 2):
                t = i / HZ
                melody[start + i] += 0.25 * (1 if (f * t) % 1 < 0.3 else -1) * math.exp(-t * 5)
    (HERE / "audio").mkdir(exist_ok=True)
    with wave.open(str(HERE / "audio" / "MUS_CAPAS.wav"), "wb") as w:
        w.setnchannels(3)
        w.setsampwidth(2)
        w.setframerate(HZ)
        frames = bytearray()
        for i in range(n):
            for ch in (drums, bass, melody):
                frames += struct.pack("<h", int(max(-1, min(1, ch[i])) * 26000))
        w.writeframes(bytes(frames))


if __name__ == "__main__":
    main()
