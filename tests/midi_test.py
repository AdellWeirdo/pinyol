"""Songs as notes (src/midi.c, tools/mkbank.py): a Standard MIDI File played by a bank of ADPCM samples. A bank is made from a looped
sine and a click; a song plays the sine at A4 for a while, then an octave up, with a click of drum between and a pitch bend;
what the engine sends to the speaker is listened to for its pitch, its silences and its length.

    python3 tests/midi_test.py BP_HEADLESS OUT_DIR
"""
import json
import math
import shutil
import struct
import subprocess
import sys
import wave
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
headless, out = sys.argv[1], Path(sys.argv[2])
shutil.rmtree(out, ignore_errors=True)
out.mkdir(parents=True)
failures = 0
RATE = 22050


def check(cond, what):
    global failures
    if not cond:
        failures += 1
        print("FAIL:", what)


def write_wav(path, samples):
    with wave.open(str(path), "wb") as w:
        w.setnchannels(1), w.setsampwidth(2), w.setframerate(RATE)
        w.writeframes(b"".join(struct.pack("<h", int(max(-32768, min(32767, s)))) for s in samples))


# a sine of exactly 50 samples a period (441 Hz) so a loop is seamless, recorded at MIDI note 69 (A4, 440 Hz in tune)
sine = [int(12000 * math.sin(2 * math.pi * i / 50)) for i in range(8000)]
write_wav(out / "sine.wav", sine)
click = [int(16000 * math.exp(-i / 200.0) * math.sin(i * 0.9)) for i in range(2000)]
write_wav(out / "click.wav", click)
(out / "kit.json").write_text(json.dumps({
    "samples": {"SINE": {"file": "sine.wav", "loop": [2800, 6800]}, "CLICK": {"file": "click.wav"}},
    "programs": {"0": [{"sample": "SINE", "root": 69, "keys": [0, 127], "attack": 0.005, "sustain": 1.0, "release": 0.05}]},
    "drums": [{"sample": "CLICK", "root": 36, "keys": [36, 36], "release": 0.05}],
}))
game = out / "game"
r = subprocess.run([sys.executable, str(ROOT / "tools" / "mkbank.py"), str(out / "kit.json"), str(game), "KIT"], capture_output=True, text=True)
check(r.returncode == 0, "mkbank runs: " + r.stderr[-300:])
bank = (game / "audio" / "KIT.bank").read_bytes()
check(bank[:4] == b"SBNK" and struct.unpack("<HHH", bank[4:10]) == (1, 2, 2), "bank header")
check(len(bank) < 12 + 129 * 4 + 2 * 16 + 2 * 24 + (8000 + 2000 + 56) // 28 * 16 + 100, "its samples are ADPCM (%d bytes)" % len(bank))


def vlq(n):
    out_ = [n & 0x7F]
    n >>= 7
    while n:
        out_.append(0x80 | (n & 0x7F))
        n >>= 7
    return bytes(reversed(out_))


# 120 beats a minute, 480 ticks a beat: a tick is 1/960 s
events = [
    (0, b"\xFF\x51\x03" + (500000).to_bytes(3, "big")),
    (96, bytes([0x90, 69, 100])), (384, bytes([0x80, 69, 0])),         # 0.1 s to 0.4 s: A4, 440 Hz
    (576, bytes([0x90, 81, 100])), (864, bytes([0x80, 81, 0])),        # 0.6 s to 0.9 s: A5, 880 Hz
    (480, bytes([0x99, 36, 120])), (528, bytes([0x89, 36, 0])),        # 0.5 s: the drum's click
    (960, b"\xFF\x2F\x00"),
]
events.sort(key=lambda e: e[0])
track = b""
last = 0
for tick, data in events:
    track += vlq(tick - last) + data
    last = tick
smf = b"MThd" + struct.pack(">IHHH", 6, 0, 1, 480) + b"MTrk" + struct.pack(">I", len(track)) + track
(game / "audio" / "SONG.mid").write_bytes(smf)
shutil.copytree(ROOT / "tests" / "games" / "turned" / "fonts", game / "fonts")
(game / "game.json").write_text('{"id": "midi", "title": "MIDI", "engine": "pinyol@2", "main": "main.lua"}')
(game / "main.lua").write_text('n = 0\nfunction _init() show(0) end\nfunction _draw() end\nfunction _update()\n  n = n + 1\n  if n == 1 then music("SONG", 1, {bank = "KIT", loop = false}) end\nend\n')
script = out / "play.script"
script.write_text("new\ntick 90\nexpect_ok\n")
pcm = out / "midi.pcm"
r = subprocess.run([headless, "--game", str(game), "--saves", str(out / "saves"), "--fresh", "--script", str(script), "--audio", str(pcm)], capture_output=True, text=True)
check(r.returncode == 0, "the engine plays it: " + r.stdout[-300:] + r.stderr[-300:])
data = pcm.read_bytes()
d = list(struct.unpack("<%dh" % (len(data) // 2), data))


def window(t0, t1):
    return d[int(t0 * RATE):int(t1 * RATE)]


def rms(x):
    return math.sqrt(sum(v * v for v in x) / max(1, len(x)))


def freq(x):  # from the zero crossings
    zc = sum(1 for a, b in zip(x, x[1:]) if a < 0 <= b)
    return zc * RATE / max(1, len(x))


check(rms(window(0.0, 0.08)) < 50, "silence before the first note")
check(rms(window(0.15, 0.35)) > 1500, "the first note sounds (rms %.0f)" % rms(window(0.15, 0.35)))
f1 = freq(window(0.15, 0.35))
check(abs(f1 - 441) < 6, "it is A4: %.1f Hz" % f1)
check(rms(window(0.44, 0.48)) < 200, "it lets go after its note off (rms %.0f)" % rms(window(0.44, 0.48)))
check(rms(window(0.5, 0.53)) > 300, "the drum's click at 0.5 s (rms %.0f)" % rms(window(0.5, 0.53)))
check(rms(window(0.65, 0.85)) > 1500, "the second note sounds")
f2 = freq(window(0.65, 0.85))
check(abs(f2 - 882) < 10, "an octave up: %.1f Hz" % f2)
check(rms(window(0.97, 1.05)) < 200, "silent after its off")
# the same song from a SoundFont: a minimal .sf2 made here (one preset, one instrument, a looped sine at 44100 Hz) and taken by --sf2
def sf2(path):
    def chunk(tag, body):
        return tag + struct.pack("<I", len(body)) + body + (b"\0" if len(body) & 1 else b"")

    def lst(kind, *chunks):
        body = kind + b"".join(chunks)
        return chunk(b"LIST", body)

    rate = 44100
    pcm = [int(12000 * math.sin(2 * math.pi * i / 100)) for i in range(16000)] + [0] * 46  # 441 Hz at 44100
    smpl = b"".join(struct.pack("<h", v) for v in pcm)
    name = lambda n: n.encode().ljust(20, b"\0")  # noqa: E731
    phdr = struct.pack("<20sHHHIII", name("Sine"), 0, 0, 0, 0, 0, 0) + struct.pack("<20sHHHIII", name("EOP"), 0, 0, 1, 0, 0, 0)
    pbag = struct.pack("<HH", 0, 0) + struct.pack("<HH", 1, 0)
    pmod = b"\0" * 10
    pgen = struct.pack("<HH", 41, 0) + struct.pack("<HH", 0, 0)
    inst = struct.pack("<20sH", name("SineInst"), 0) + struct.pack("<20sH", name("EOI"), 1)
    ibag = struct.pack("<HH", 0, 0) + struct.pack("<HH", 6, 0)
    imod = b"\0" * 10
    igen = b"".join(struct.pack("<Hh", op, v) for op, v in (
        (43, 0x7F00), (34, -7973), (38, -4000), (54, 1), (58, 69), (53, 0))) + struct.pack("<HH", 0, 0)  # key range 0-127, attack ~10 ms, release ~0.1 s, loops
    igen = igen.replace(struct.pack("<Hh", 43, 0x7F00), struct.pack("<HBB", 43, 0, 127))
    shdr = struct.pack("<20sIIIIIBbHH", name("sine"), 0, 16000, 2800 * 2, 2800 * 2 + 100 * 80, rate, 69, 0, 0, 1) + struct.pack("<20sIIIIIBbHH", name("EOS"), 0, 0, 0, 0, 0, 0, 0, 0, 0)
    pdta = lst(b"pdta", chunk(b"phdr", phdr), chunk(b"pbag", pbag), chunk(b"pmod", pmod), chunk(b"pgen", pgen), chunk(b"inst", inst),
               chunk(b"ibag", ibag), chunk(b"imod", imod), chunk(b"igen", igen), chunk(b"shdr", shdr))
    info = lst(b"INFO", chunk(b"ifil", struct.pack("<HH", 2, 1)), chunk(b"isng", b"EMU8000\0"), chunk(b"INAM", b"test\0\0"))
    body = b"sfbk" + info + lst(b"sdta", chunk(b"smpl", smpl)) + pdta
    path.write_bytes(b"RIFF" + struct.pack("<I", len(body)) + body)


sf2(out / "sine.sf2")
game2 = out / "game2"
r = subprocess.run([sys.executable, str(ROOT / "tools" / "mkbank.py"), "--sf2", str(out / "sine.sf2"), str(game2), "SF", "--programs", "0"], capture_output=True, text=True)
check(r.returncode == 0, "mkbank --sf2 runs: " + r.stderr[-400:])
shutil.copytree(game / "fonts", game2 / "fonts")
shutil.copy(game / "audio" / "SONG.mid", game2 / "audio" / "SONG.mid")
(game2 / "game.json").write_text('{"id": "midi2", "title": "MIDI 2", "engine": "pinyol@2", "main": "main.lua"}')
(game2 / "main.lua").write_text('n = 0\nfunction _init() show(0) end\nfunction _draw() end\nfunction _update()\n  n = n + 1\n  if n == 1 then music("SONG", 1, {bank = "SF", loop = false}) end\nend\n')
pcm2 = out / "midi2.pcm"
r = subprocess.run([headless, "--game", str(game2), "--saves", str(out / "saves2"), "--fresh", "--script", str(script), "--audio", str(pcm2)], capture_output=True, text=True)
check(r.returncode == 0, "the engine plays the SoundFont's bank")
data2 = pcm2.read_bytes()
d2 = list(struct.unpack("<%dh" % (len(data2) // 2), data2))
w2 = d2[int(0.15 * RATE):int(0.35 * RATE)]
check(rms(w2) > 1000 and abs(freq(w2) - 441) < 8, "a 44100 Hz sample from a SoundFont plays at 441 Hz: rms %.0f, %.1f Hz" % (rms(w2), freq(w2)))
check(rms(d2[int(0.0 * RATE):int(0.08 * RATE)]) < 50, "and is silent before it")

# damaged songs and banks (a game from the internet is not to be trusted): each plays or is refused, never a crash. Under a Debug
# build (ASan) this also catches reading past what was read.
import random  # noqa: E402

rng = random.Random(7)
mid, kit = (game / "audio" / "SONG.mid").read_bytes(), (game / "audio" / "KIT.bank").read_bytes()
fz = out / "fuzz"
shutil.copytree(game, fz)
short = out / "short.script"
short.write_text("new\ntick 20\n")
crashes = 0
for i in range(60):
    m, b = bytearray(mid), bytearray(kit)
    for blob in (m, b) if i % 3 == 0 else ((m,) if i % 3 == 1 else (b,)):
        for _ in range(rng.randint(1, 12)):
            blob[rng.randrange(len(blob))] = rng.randrange(256)
        if rng.random() < 0.3:
            del blob[rng.randrange(len(blob)):]
    (fz / "audio" / "SONG.mid").write_bytes(m)
    (fz / "audio" / "KIT.bank").write_bytes(b)
    r = subprocess.run([headless, "--game", str(fz), "--saves", str(fz / "sv"), "--fresh", "--script", str(short)], capture_output=True, text=True, timeout=60)
    if r.returncode not in (0, 1) or "Sanitizer" in r.stderr or "runtime error" in r.stderr:
        crashes += 1
check(crashes == 0, "damaged songs and banks never crash (%d did)" % crashes)

print("midi: %s" % ("ok" if not failures else "%d failed" % failures))
sys.exit(1 if failures else 0)
