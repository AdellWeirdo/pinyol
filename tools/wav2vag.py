#!/usr/bin/env python3
"""Turns a WAV into a sound pinyol keeps as the PlayStation sound chip's ADPCM: GAME/audio/<id>.vag, about a third and a
half of the memory of the same sound as PCM16, and a loop of its own if you give one.

  wav2vag.py SOURCE.wav GAME ID [--loop START END] [--seconds]

SOURCE is any PCM WAV (8, 16 or 24 bit; stereo is averaged; other rates are resampled to 22050 Hz, which the mixer
plays). --loop START END are the loop's first and last sample (with --seconds: in seconds): the loop starts on a block
(28 samples) boundary, rounded down, and its first block is made without prediction so the jump back is clean.
sfx("ID", 1, {loop = true}) then loops it, or {loop_start, loop_end} choose another part.

The format (little endian), as src/audio.c reads it:
  "SPUV", u32 samples, u32 loop first, u32 loop last (both 0: no loop), then blocks of 16 bytes: filter (high nibble,
  0-4) and shift (low nibble, 0-12), a flags byte (1: last block, 2: loops back, 4: loop start), and 28 4-bit samples,
  low nibble first. A sample is its nibble times 2^(12 - shift), plus (older x k0 + old x k1 + 32) >> 6 from the two
  samples before it, with (k0, k1) the filter's: (0, 0), (60, 0), (115, -52), (98, -55), (122, -60). A block is tried
  at each filter and shift; the one that reproduces the sound best is kept.
"""
import argparse
import math
import os
import struct
import sys
import wave

RATE = 22050
K0 = (0, 60, 115, 98, 122)
K1 = (0, 0, -52, -55, -60)
BLOCK = 28


def read_wav(path):
    """The WAV as floats in -32768..32767, mono, resampled (linearly) to RATE."""
    with wave.open(path, "rb") as w:
        ch, width, rate, n = w.getnchannels(), w.getsampwidth(), w.getframerate(), w.getnframes()
        raw = w.readframes(n)
    if width not in (1, 2, 3):
        sys.exit("%s: %d-bit samples are not supported (8, 16 or 24)" % (path, width * 8))
    vals = []
    for i in range(0, len(raw), width * ch):
        t = 0.0
        for c in range(ch):
            b = raw[i + c * width:i + (c + 1) * width]
            if width == 1:
                v = (b[0] - 128) * 256
            elif width == 2:
                v = int.from_bytes(b, "little", signed=True)
            else:
                v = int.from_bytes(b, "little", signed=True) / 256.0
            t += v
        vals.append(t / ch)
    if rate != RATE and vals:
        m = max(1, int(len(vals) * RATE / rate))
        out = []
        for i in range(m):
            p = i * rate / RATE
            a = int(p)
            b = min(a + 1, len(vals) - 1)
            out.append(vals[a] + (vals[b] - vals[a]) * (p - a))
        vals = out
    return vals


def clamp16(v):
    return -32768 if v < -32768 else 32767 if v > 32767 else v


def encode_block(samples, old, older, filters):
    """The best (filter, shift) for these 28 samples after old/older: the bytes, and the decoder's state after them."""
    best = None
    for f in filters:
        for shift in range(13):
            step = 1 << (12 - shift)
            o, oo, err, nibs = old, older, 0, []
            for s in samples:
                pred = (o * K0[f] + oo * K1[f] + 32) >> 6
                q = round((s - pred) / step)
                q = -8 if q < -8 else 7 if q > 7 else q
                v = clamp16(q * step + pred)
                err += (s - v) ** 2
                nibs.append(q & 15)
                oo, o = o, v
            if best is None or err < best[0]:
                best = (err, f, shift, nibs, o, oo)
    _, f, shift, nibs, o, oo = best
    data = bytearray([f << 4 | shift, 0])
    for i in range(0, BLOCK, 2):
        data.append(nibs[i] | nibs[i + 1] << 4)
    return data, o, oo


def encode(samples, loop=None):
    n = len(samples)
    nb = (n + BLOCK - 1) // BLOCK
    samples = list(samples) + [0.0] * (nb * BLOCK - n)
    loop_block = loop[0] // BLOCK if loop else None
    out = bytearray()
    old = older = 0
    for b in range(nb):
        if b == loop_block:
            old = older = 0  # the jump back starts a block from nothing: no prediction in it
        data, old, older = encode_block(samples[b * BLOCK:(b + 1) * BLOCK], old, older, (0,) if b == loop_block else range(5))
        if loop and b == loop_block:
            data[1] |= 4
        if b == nb - 1:
            data[1] |= 1 | (2 if loop else 0)
        out += data
    return bytes(out)


def decode(blocks, n):
    """What the engine plays: the samples back from the blocks (used by the tests, and by --check)."""
    old = older = 0
    out = []
    for b in range(0, len(blocks), 16):
        f, shift = blocks[b] >> 4, min(blocks[b] & 15, 12)
        f = min(f, 4)
        for i in range(BLOCK):
            nib = (blocks[b + 2 + i // 2] >> (4 * (i & 1))) & 15
            d = ((nib << 12) - 65536 if nib >= 8 else nib << 12) >> shift
            v = clamp16(d + ((old * K0[f] + older * K1[f] + 32) >> 6))
            older, old = old, v
            out.append(v)
    return out[:n]


def main():
    ap = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    ap.add_argument("source")
    ap.add_argument("game")
    ap.add_argument("id")
    ap.add_argument("--loop", nargs=2, type=float, metavar=("START", "END"))
    ap.add_argument("--seconds", action="store_true", help="--loop is in seconds, not samples")
    a = ap.parse_args()
    if not a.id.replace("_", "").isalnum():
        sys.exit("id: letters, digits and _ only")
    samples = read_wav(a.source)
    if not samples:
        sys.exit("%s: no samples" % a.source)
    loop = None
    if a.loop:
        k = RATE if a.seconds else 1
        start, end = int(a.loop[0] * k), int(a.loop[1] * k)
        if not 0 <= start < end <= len(samples):
            sys.exit("--loop: START and END must be inside the sound, in order (it has %d samples)" % len(samples))
        loop = (start // BLOCK * BLOCK, end)
    blocks = encode(samples, loop)
    path = os.path.join(a.game, "audio")
    os.makedirs(path, exist_ok=True)
    path = os.path.join(path, a.id + ".vag")
    with open(path, "wb") as f:
        f.write(b"SPUV" + struct.pack("<III", len(samples), *(loop or (0, 0))) + blocks)
    back = decode(blocks, len(samples))
    sig = sum(s * s for s in samples) or 1.0
    noise = sum((s - b) ** 2 for s, b in zip(samples, back)) or 1.0
    print("%s: %d samples, %d bytes (PCM16: %d), %.1f dB signal to noise" %
          (path, len(samples), len(blocks) + 16, 2 * len(samples), 10 * math.log10(sig / noise)))


if __name__ == "__main__":
    main()
