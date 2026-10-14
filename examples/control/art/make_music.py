"""The newscast's theme, made here: a 16-second loop at 120 bpm in D minor (two bars each of Dm, Bb, F, C), a clock
ticking every sixteenth, a timpani hit on each bar, a brass-like pad and a bass. Mono PCM16 at 22050 Hz, as pinyol
plays it with music(); the game's cues fall on its beats (music_time()).

    python3 examples/control/art/make_music.py      -> examples/control/audio/MUS_NEWS.wav
"""
import math
import random
import struct
import wave
from pathlib import Path

HZ, BPM, BARS = 22050, 120, 8
BEAT = 60 / BPM
N = int(HZ * BEAT * 4 * BARS)
OUT = Path(__file__).resolve().parents[1] / "audio" / "MUS_NEWS.wav"
CHORDS = [(50, 53, 57), (46, 50, 53), (53, 57, 60), (48, 52, 55)]  # MIDI: Dm, Bb, F, C, two bars each
BASS = [0, 0, 12, 0, 7, 0, 10, 12]                                  # eighths over the root, each bar


def hz(m):
    return 440 * 2 ** ((m - 69) / 12)


mix = [0.0] * N
rng = random.Random(3)


def add(start, length, fn):
    for i in range(max(0, start), min(N, start + length)):
        mix[i] += fn(i - start)


for bar in range(BARS):
    chord = CHORDS[bar // 2]
    b0 = int(bar * 4 * BEAT * HZ)
    # timpani: a low thump falling in pitch, and a little noise
    add(b0, int(0.6 * HZ), lambda i: 0.55 * math.exp(-i / (0.18 * HZ)) *
        (math.sin(2 * math.pi * hz(chord[0] - 12) * (1 + 0.3 * math.exp(-i / 800)) * i / HZ) + 0.2 * (rng.random() - 0.5)))
    # the pad: three saw-like voices, slow in, held for the bar
    for m in chord:
        f = hz(m)
        add(b0, int(4 * BEAT * HZ), lambda i, f=f: 0.06 * min(1, i / (0.25 * HZ)) * min(1, (4 * BEAT * HZ - i) / 2000) *
            sum(math.sin(2 * math.pi * f * k * i / HZ) / k for k in (1, 2, 3, 4)))
    # the bass, in eighths
    for e, step in enumerate(BASS):
        f = hz(chord[0] - 24 + step)
        add(b0 + int(e * BEAT / 2 * HZ), int(BEAT / 2 * HZ * 0.9), lambda i, f=f: 0.22 * math.exp(-i / (0.12 * HZ)) *
            (1 if math.sin(2 * math.pi * f * i / HZ) > 0 else -1) * 0.6)
    # the clock: a tick every sixteenth, louder on the beats
    for s in range(16):
        accent = 0.16 if s % 4 == 0 else 0.07
        add(b0 + int(s * BEAT / 4 * HZ), 300, lambda i, a=accent: a * math.exp(-i / 60) * math.sin(2 * math.pi * 2200 * i / HZ))

peak = max(abs(v) for v in mix)
k = 0.7 * 32767 / peak
OUT.parent.mkdir(parents=True, exist_ok=True)
with wave.open(str(OUT), "wb") as w:
    w.setnchannels(1)
    w.setsampwidth(2)
    w.setframerate(HZ)
    w.writeframes(struct.pack(f"<{N}h", *(int(v * k) for v in mix)))
print(OUT, f"{N / HZ:.1f} s")
