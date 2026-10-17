"""ADPCM sounds (tools/wav2vag.py, src/audio.c): the tool's blocks decode to the sound within a few percent of noise
and a third of the memory; the engine plays exactly what the decoder says, once and looped between two points (a
jump back that is clean); a damaged file plays nothing and breaks nothing.

    python3 tests/vag_test.py BP_HEADLESS OUT_DIR
"""
import importlib.util
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
spec = importlib.util.spec_from_file_location("wav2vag", ROOT / "tools" / "wav2vag.py")
w2v = importlib.util.module_from_spec(spec)
spec.loader.exec_module(w2v)

failures = 0


def check(cond, what):
    global failures
    if not cond:
        failures += 1
        print("FAIL:", what)


# a tone with some grit in it, 0.5 s, starting off zero so the first sample is heard
N = 11025
seed = 12345
samples = []
for i in range(N):
    seed = (seed * 1103515245 + 12345) & 0x7FFFFFFF
    samples.append(int(12000 * math.sin(0.3 + 2 * math.pi * 440 * i / 22050) + ((seed >> 16) % 600) - 300))
wav = out / "tone.wav"
with wave.open(str(wav), "wb") as w:
    w.setnchannels(1), w.setsampwidth(2), w.setframerate(22050)
    w.writeframes(b"".join(struct.pack("<h", s) for s in samples))


def game(name, vag_args):
    g = out / name
    shutil.copytree(ROOT / "tests" / "games" / "turned" / "fonts", g / "fonts")
    (g / "game.json").write_text('{"id": "%s", "title": "ADPCM", "engine": "pinyol@2", "main": "main.lua"}' % name)
    (g / "main.lua").write_text('n = 0\nfunction _init() show(0) end\nfunction _update() n = n + 1 if n == 1 then sfx("TONE", 1, {loop = %s}) end end\nfunction _draw() end\n' %
                                ("true" if "--loop" in vag_args else "false"))
    r = subprocess.run([sys.executable, str(ROOT / "tools" / "wav2vag.py"), str(wav), str(g), "TONE", *vag_args],
                       check=True, capture_output=True, text=True)
    return g, r.stdout


def play(g, ticks):
    script = out / "play.script"
    script.write_text("new\ntick %d\nexpect_ok\n" % ticks)
    pcm = out / (g.name + ".pcm")
    subprocess.run([headless, "--game", str(g), "--saves", str(out / (g.name + "_saves")), "--fresh", "--script",
                    str(script), "--audio", str(pcm)], check=True, stdout=subprocess.DEVNULL)
    data = pcm.read_bytes()
    return list(struct.unpack("<%dh" % (len(data) // 2), data))


def first_sound(d):
    return next((i for i, v in enumerate(d) if v), None)


# 1. the tool: size and fidelity
g, said = game("once", [])
blob = (g / "audio" / "TONE.vag").read_bytes()
check(blob[:4] == b"SPUV" and struct.unpack("<III", blob[4:16]) == (N, 0, 0), "header")
check(len(blob) - 16 == (N + 27) // 28 * 16, "one 16-byte block for each 28 samples")
check(len(blob) < 0.3 * 2 * N, "under a third of PCM16 (%d bytes of %d)" % (len(blob), 2 * N))
ref = w2v.decode(blob[16:], N)
sig = sum(s * s for s in samples)
noise = sum((s - r) ** 2 for s, r in zip(samples, ref))
check(10 * math.log10(sig / noise) > 20, "signal to noise over 20 dB: " + said.strip())

# 2. the engine plays what the decoder says, sample for sample
d = play(g, 60)  # a second of ticks
at = first_sound(d)
check(at is not None and d[at:at + N] == ref, "the engine's samples are the decoder's, once")
check(all(v == 0 for v in d[at + N:]), "and silence after (no loop)")

# 3. looped between two points: the head once, then the loop for ever, on the decoder's samples
g, _ = game("loop", ["--loop", "4000", "8000"])
blob = (g / "audio" / "TONE.vag").read_bytes()
check(struct.unpack("<III", blob[4:16]) == (N, 3976, 8000), "loop points rounded down to a block: %s" % (struct.unpack("<III", blob[4:16]),))
ref = w2v.decode(blob[16:], N)
d = play(g, 90)  # 1.5 s: past the clip's end several times over
at = first_sound(d)
expect = [ref[p] if p < 8000 else ref[3976 + (p - 8000) % (8000 - 3976)] for p in range(30000)]
check(at is not None and d[at:at + 30000] == expect, "the loop is the decoder's samples between its points, no click")

# 4. damaged files: a header that promises more than the file has, and not an ADPCM file at all
g, _ = game("short", [])
f = g / "audio" / "TONE.vag"
f.write_bytes(f.read_bytes()[:200])
check(first_sound(play(g, 20)) is None, "a short file plays nothing")
f.write_bytes(b"RIFFnotavagfile" * 10)
check(first_sound(play(g, 20)) is None, "a file that is not ADPCM plays nothing")

# 5. streams: a two-stem song and a mono bed kept as ADPCM and read from the card as they play (.spum): the engine plays what the
# decoder says, stem by stem and summed, loops from its block, takes a pan, and a bed plays too
N2 = 8000
stems = []
for tone in (330, 495):
    stems.append([int(9000 * math.sin(0.4 + 2 * math.pi * tone * i / 22050)) for i in range(N2)])
wav2 = out / "song.wav"
with wave.open(str(wav2), "wb") as w:
    w.setnchannels(2), w.setsampwidth(2), w.setframerate(22050)
    w.writeframes(b"".join(struct.pack("<hh", a, b) for a, b in zip(*stems)))
gs = out / "stream"
shutil.copytree(ROOT / "tests" / "games" / "turned" / "fonts", gs / "fonts")
(gs / "game.json").write_text('{"id": "stream", "title": "Stream", "engine": "pinyol@2", "main": "main.lua"}')
(gs / "main.lua").write_text("n = 0\nfunction _init() show(0) end\nfunction _draw() end\nfunction _update()\n  n = n + 1\n  if n == 1 then music(\"SONG\", 1) end\n  if n == 40 then music_pan(1, 1) end\nend\n")
r = subprocess.run([sys.executable, str(ROOT / "tools" / "wav2vag.py"), str(wav2), str(gs), "SONG", "--stream", "--loop", "2800"], capture_output=True, text=True)
check(r.returncode == 0, "the stream tool runs: " + r.stderr[-300:])
blob = (gs / "audio" / "SONG.spum").read_bytes()
check(blob[:4] == b"SPUM" and struct.unpack("<II", blob[4:12]) == (N2, 2800) and blob[12] == 2, "stream header")
check(len(blob) == 16 + (N2 + 27) // 28 * 2 * 16, "a block of each stem for each 28 samples")
dec = [w2v.decode(bytes(blob[16 + 16 * c + 32 * b: 16 + 16 * c + 32 * b + 16] for b in range(0)) if False else b"".join(blob[16 + 32 * b + 16 * c:16 + 32 * b + 16 * c + 16] for b in range((N2 + 27) // 28)), N2) for c in range(2)]
d = play(gs, 60)
at = first_sound(d)
expect = [dec[0][p] + dec[1][p] if p < N2 else dec[0][2800 + (p - N2) % (N2 - 2800)] + dec[1][2800 + (p - N2) % (N2 - 2800)] for p in range(30000)]
# (the first 40 ticks: no pan: both stems summed, the first of the song, then its loop from its block)
head = 38 * 367
check(at is not None and d[at + 100:at + head] == expect[100:head], "the stream's samples are the decoder's, the stems summed, then its loop (its fade-in done)")
# music_pan(1): hard right on a mono platform is half (the average of the ears): after the pan the level is half of the song's
rest = d[at + head + 1000:at + head + 5000]
want = [expect[head + 1000 + i] for i in range(len(rest))]
close = sum(1 for a2, b2 in zip(rest, want) if abs(a2 - b2 / 2) <= 2)
check(close > 0.95 * len(rest), "a pan of 1 takes the song to half on a speaker (%d of %d samples)" % (close, len(rest)))
# a mono bed
bed = [int(7000 * math.sin(0.3 + 2 * math.pi * 220 * i / 22050)) for i in range(6000)]
wavb = out / "bed.wav"
with wave.open(str(wavb), "wb") as w:
    w.setnchannels(1), w.setsampwidth(2), w.setframerate(22050)
    w.writeframes(b"".join(struct.pack("<h", x) for x in bed))
gb = out / "bed"
shutil.copytree(ROOT / "tests" / "games" / "turned" / "fonts", gb / "fonts")
(gb / "game.json").write_text('{"id": "bed", "title": "Bed", "engine": "pinyol@2", "main": "main.lua"}')
(gb / "main.lua").write_text("n = 0\nfunction _init() show(0) end\nfunction _draw() end\nfunction _update()\n  n = n + 1\n  if n == 1 then ambient(\"BED\", 1) end\nend\n")
subprocess.run([sys.executable, str(ROOT / "tools" / "wav2vag.py"), str(wavb), str(gb), "BED", "--stream", "--loop", "0"], check=True, capture_output=True)
bb = (gb / "audio" / "BED.spum").read_bytes()
bdec = w2v.decode(bb[16:], 6000)
db = play(gb, 60)
ab = first_sound(db)
exp_b = [bdec[p % 6000] for p in range(18000)]
check(ab is not None and db[ab + 300:ab + 18000] == exp_b[300:18000], "an ambient bed from the card plays the decoder's samples, looped")

print("vag: %s" % ("ok" if not failures else "%d failed" % failures))
sys.exit(1 if failures else 0)
