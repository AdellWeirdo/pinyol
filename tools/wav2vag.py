#!/usr/bin/env python3
"""Turns a WAV into a sound pinyol keeps as the PlayStation sound chip's ADPCM: GAME/audio/<id>.vag, about a third and a
half of the memory of the same sound as PCM16, and a loop of its own if you give one.

  wav2vag.py SOURCE.wav GAME ID [--loop START END] [--seconds]
  wav2vag.py SOURCE.wav GAME ID --stream [--loop START] [--seconds]      music and beds: audio/ID.spum, played from the card

SOURCE is any PCM WAV (8, 16 or 24 bit; stereo is averaged; other rates are resampled to 22050 Hz, which the mixer
plays). --loop START END are the loop's first and last sample (with --seconds: in seconds): the loop starts on a block
(28 samples) boundary, rounded down, and its first block is made without prediction so the jump back is clean.
sfx("ID", 1, {loop = true}) then loops it, or {loop_start, loop_end} choose another part.

--stream makes, instead of a sound kept in memory, a stream read from the card as it plays (sfx() cannot play it; music() and
ambient() can): every channel of the WAV is a stem (up to 3), and the blocks of the stems alternate so one read of the card
brings them all, in step. --loop START is the sample the song goes back to at its end (rounded down to a block), 0 for the
whole of it; the stems keep their bar-quantised layer changes (music_layer) as they do from a WAV, at a third of its size.
  "SPUM", u32 samples, u32 loop sample, u8 stems, 3 spare bytes, then for each 28 samples a block of each stem in turn.

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


def read_wav_channels(path):
    """Every channel of the WAV as its own list of floats, resampled to RATE: the stems of a song."""
    with wave.open(path, "rb") as w:
        ch, width, rate, n = w.getnchannels(), w.getsampwidth(), w.getframerate(), w.getnframes()
        raw = w.readframes(n)
    if width not in (1, 2, 3):
        sys.exit(f"{path}: {width * 8}-bit samples are not supported (8, 16 or 24)")
    chans = [[] for _ in range(ch)]
    for i in range(0, len(raw), width * ch):
        for c in range(ch):
            b = raw[i + c * width:i + (c + 1) * width]
            chans[c].append((b[0] - 128) * 256 if width == 1 else int.from_bytes(b, "little", signed=True) / (256.0 if width == 3 else 1.0))
    if rate != RATE and chans[0]:
        m = max(1, int(len(chans[0]) * RATE / rate))
        for c in range(ch):
            src, out = chans[c], []
            for i in range(m):
                p = i * rate / RATE
                a = int(p)
                out.append(src[a] + (src[min(a + 1, len(src) - 1)] - src[a]) * (p - a))
            chans[c] = out
    return chans


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
    ap.add_argument("--loop", nargs="+", type=float, metavar="START [END]")
    ap.add_argument("--seconds", action="store_true", help="--loop is in seconds, not samples")
    ap.add_argument("--stream", action="store_true", help="a stream for music() and ambient(), each channel a stem")
    a = ap.parse_args()
    if not a.id.replace("_", "").isalnum():
        sys.exit("id: letters, digits and _ only")
    if a.stream:
        chans = read_wav_channels(a.source)
        if not 1 <= len(chans) <= 3 or not chans[0]:
            sys.exit(f"{a.source}: a stream has 1 to 3 channels (the stems of a song) and some samples")
        n, k = len(chans[0]), RATE if a.seconds else 1
        start = int(a.loop[0] * k) // BLOCK * BLOCK if a.loop else 0
        if not 0 <= start < n:
            sys.exit(f"--loop: START must be inside the song (it has {n} samples)")
        per = [encode(c, (start, n) if a.loop else None) for c in chans]
        nb = len(per[0]) // 16
        body = b"".join(per[c][b * 16:(b + 1) * 16] for b in range(nb) for c in range(len(chans)))
        path = os.path.join(a.game, "audio")
        os.makedirs(path, exist_ok=True)
        path = os.path.join(path, a.id + ".spum")
        with open(path, "wb") as f:
            f.write(b"SPUM" + struct.pack("<II", n, start) + bytes([len(chans), 0, 0, 0]) + body)
        print("%s: %d samples, %d stem(s), %d bytes (PCM16: %d)" % (path, n, len(chans), 16 + len(body), 2 * n * len(chans)))
        return
    samples = read_wav(a.source)
    if not samples:
        sys.exit("%s: no samples" % a.source)
    loop = None
    if a.loop:
        if len(a.loop) != 2:
            sys.exit("--loop START END")
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
