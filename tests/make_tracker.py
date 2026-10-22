#!/usr/bin/env python3
"""The small modules and WAVs the tests play (tests/games/music/audio): a ProTracker LOOP.mod, a FastTracker LOOPX.xm
and a Scream Tracker LOOPS.s3m, each one pattern of 64 rows with a square-wave sample struck on the first line of
each bar of sixteen, at speed 1 (a line every 20 ms at 125 BPM, a bar 320 ms), so a script can count their bars; and
MARKED.wav, a second of a tone with its own markers (a loop from 0.25 s in a smpl chunk, cue points at 0 and 0.5 s).
    python3 tests/make_tracker.py            # writes the four files
"""
import struct
from pathlib import Path

OUT = Path(__file__).resolve().parent / "games/music/audio"
SQUARE = bytes([100] * 32 + [156] * 32)  # +100 then -100 (signed 8-bit): a square wave, 64 samples
HITS = (0, 16, 32, 48)


def mod() -> bytes:
    hdr = b"LOOP".ljust(20, b"\0")
    hdr += b"SQUARE".ljust(22, b"\0") + struct.pack(">HBBHH", 32, 0, 64, 0, 32)  # 32 words, loops whole
    hdr += (b"\0" * 22 + struct.pack(">HBBHH", 0, 0, 0, 0, 1)) * 30
    hdr += bytes([1, 127]) + bytes(128) + b"M.K."
    pat = bytearray(64 * 4 * 4)

    def put(row, period, smp, fx=0, param=0):
        i = row * 16
        pat[i] = ((smp >> 4) << 4) | (period >> 8)
        pat[i + 1] = period & 255
        pat[i + 2] = ((smp & 15) << 4) | fx
        pat[i + 3] = param

    put(0, 428, 1, 0xF, 1)  # C-2, sample 1, F01: speed 1
    for row in HITS[1:]:
        put(row, 428, 1)
    return hdr + bytes(pat) + SQUARE


def xm() -> bytes:
    """FastTracker II 1.04: one pattern, one instrument with one looping sample and a volume envelope."""
    orders = bytes([0]) + bytes(255)
    header = struct.pack("<IHHHHHHHH", 276, 1, 0, 4, 1, 1, 0, 1, 125) + orders  # size, len, restart, chans, pats, insts, flags, speed, bpm
    # the pattern: rows of four channels, each cell packed (0x80 | bits: note 1, instrument 2, volume 4, effect 8, param 16)
    cells = bytearray()
    for row in range(64):
        for ch in range(4):
            if ch == 0 and row in HITS:
                if row == 0:
                    cells += bytes([0x80 | 1 | 2 | 8 | 16, 37, 1, 0xF, 1])  # C-3, instrument 1, F01: speed 1
                else:
                    cells += bytes([0x80 | 1 | 2, 37, 1])
            else:
                cells += bytes([0x80])
    pattern = struct.pack("<IBHH", 9, 0, 64, len(cells)) + bytes(cells)
    vol_env = struct.pack("<" + "HH" * 12, 0, 48, 10, 64, 40, 40, *([0] * 18))  # three points, up then down; sustain on the second
    pan_env = bytes(48)
    inst = struct.pack("<I", 263) + b"SQUARE".ljust(22, b"\0") + bytes([0]) + struct.pack("<H", 1)
    inst += struct.pack("<I", 40) + bytes(96) + vol_env + pan_env
    inst += bytes([3, 0, 1, 0, 0, 0, 0, 0])  # points (vol, pan), vol sustain at point 1, no loops, pan sustain and loops
    inst += bytes([1, 0]) + bytes([0, 0, 0, 0]) + struct.pack("<H", 0) + bytes(22)  # vol env on, pan env off; vibrato; fadeout; reserved
    assert len(inst) == 263
    sample = struct.pack("<IIIBbBBbB", 64, 0, 64, 64, 0, 1, 128, 0, 0) + b"SQUARE".ljust(22, b"\0")  # loops forward, 8-bit
    deltas = bytearray()
    prev = 0
    for b in SQUARE:  # XM stores 8-bit samples as deltas
        v = b - 256 if b > 127 else b
        deltas.append((v - prev) & 255)
        prev = v
    body = b"Extended Module: " + b"LOOP".ljust(20, b"\0") + bytes([0x1A]) + b"pinyol tests".ljust(20, b"\0") + struct.pack("<H", 0x0104)
    return body + header + pattern + inst + sample + bytes(deltas)


def s3m() -> bytes:
    """Scream Tracker 3.20: one pattern, one PCM instrument (unsigned 8-bit), 4 channels."""
    sample_para = 0x60 // 16 + 0  # placeholders; the offsets below are worked out
    orders = bytes([0, 255])  # the song, then the end marker (and an even count)
    hdr_len = 96 + len(orders) + 2 + 2  # header, orders, one instrument parapointer, one pattern parapointer
    inst_off = (hdr_len + 15) // 16 * 16
    pat_off = inst_off + 80
    # the pattern: packed rows; a cell: byte (channel | 32 note+inst | 64 volume | 128 command), note, inst, [vol], [cmd, info]
    rows = bytearray()
    for row in range(64):
        if row in HITS:
            if row == 0:
                rows += bytes([0 | 32 | 128, 0x30, 1, 0x01, 1])  # C-3 (octave 3, note 0), instrument 1, A01: speed 1
            else:
                rows += bytes([0 | 32, 0x30, 1])
        rows.append(0)  # end of row
    pattern = struct.pack("<H", len(rows) + 2) + bytes(rows)
    pat_len = (len(pattern) + 15) // 16 * 16
    smp_off = pat_off + pat_len
    inst = bytes([1]) + b"SQUARE.RAW".ljust(12, b"\0") + bytes([(smp_off >> 20) & 255, (smp_off >> 4) & 255, (smp_off >> 12) & 255])
    inst += struct.pack("<IIIBBBB", 64, 0, 64, 64, 0, 0, 1)  # length, loop begin, loop end, volume, dsk, pack, flags: looping
    inst += struct.pack("<I", 8363) + bytes(12) + b"SQUARE".ljust(28, b"\0") + b"SCRS"
    assert len(inst) == 80
    header = b"LOOP".ljust(28, b"\0") + bytes([0x1A, 16, 0, 0]) + struct.pack("<HHHHHH", len(orders), 1, 1, 0, 0x1320, 2) + b"SCRM"
    header += bytes([64, 1, 125, 48, 0, 0]) + bytes(8) + struct.pack("<H", 0)  # global vol, speed, tempo, master vol, uc, dp
    chans = bytes([0, 8, 1, 9] + [255] * 28)  # L, R, L, R
    header += chans
    assert len(header) == 96
    body = bytearray(header + orders + struct.pack("<H", inst_off // 16) + struct.pack("<H", pat_off // 16))
    body += bytes(inst_off - len(body)) + inst
    body += bytes(pat_off - len(body)) + pattern
    body += bytes(smp_off - len(body)) + bytes((b + 128) & 255 for b in (x - 256 if x > 127 else x for x in SQUARE))  # unsigned
    return bytes(body)


def marked() -> bytes:
    """A second of a 440 Hz tone, 22050 Hz mono PCM16, with a smpl loop starting at 0.25 s and two cue points, at 0 and 0.5 s,
    written after the data chunk as DAWs do."""
    import math
    rate = 22050
    pcm = b"".join(struct.pack("<h", int(12000 * math.sin(2 * math.pi * 440 * i / rate))) for i in range(rate))
    fmt = struct.pack("<HHIIHH", 1, 1, rate, rate * 2, 2, 16)
    smpl = struct.pack("<IIIIIIIII", 0, 0, 1000000000 // rate, 60, 0, 0, 0, 1, 0) + struct.pack("<IIIIII", 0, 0, rate // 4, rate - 1, 0, 0)
    cue = struct.pack("<I", 2) + struct.pack("<IIIIII", 1, 0, 0x61746164, 0, 0, 0) + struct.pack("<IIIIII", 2, rate // 2, 0x61746164, 0, 0, rate // 2)
    chunks = b"fmt " + struct.pack("<I", len(fmt)) + fmt + b"data" + struct.pack("<I", len(pcm)) + pcm
    chunks += b"smpl" + struct.pack("<I", len(smpl)) + smpl + b"cue " + struct.pack("<I", len(cue)) + cue
    return b"RIFF" + struct.pack("<I", 4 + len(chunks)) + b"WAVE" + chunks


if __name__ == "__main__":
    OUT.mkdir(parents=True, exist_ok=True)
    for name, make in (("LOOP.mod", mod), ("LOOPX.xm", xm), ("LOOPS.s3m", s3m), ("MARKED.wav", marked)):
        data = make()
        (OUT / name).write_bytes(data)
        print(f"{name}: {len(data)} bytes")
