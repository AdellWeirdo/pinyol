"""Damaged games must not crash the engine: copies a game, damages 1-3 of its files (bytes changed, or cut short),
plays it for two seconds, and reports any AddressSanitizer or UBSan finding. Use a Debug build (sanitizers on).

    python3 tests/fuzz_assets.py examples/naves /tmp/fuzzwork build/pinyol_headless 60

Not part of ctest (a minute per game). Last run 2026-10-12: naves, plataformas, puzle, hola, 60 each, no findings;
2026-10-17: the games midi_test, vag_test and clip_scenes_test leave in the build (a MIDI song and its bank, one from a
SoundFont, a looped VAG, an SPU-ADPCM stream and an ambience bed, two NPV2 clips), 80 each, no findings.
"""
import random
import shutil
import subprocess
import sys
from pathlib import Path

src, work, binp, n = Path(sys.argv[1]), Path(sys.argv[2]), sys.argv[3], int(sys.argv[4])
work.parent.mkdir(parents=True, exist_ok=True)
script = work.parent / "af.script"
script.write_text("new\ntick 2\npress A\ntick 120\n")
r = random.Random(7)
bad = 0
for k in range(n):
    shutil.rmtree(work, ignore_errors=True)
    shutil.copytree(src, work, ignore=shutil.ignore_patterns("saves", "art", "art.py"))
    files = [p for p in work.rglob("*") if p.is_file() and p.suffix != ".lua"]
    for _ in range(r.randint(1, 3)):
        f = r.choice(files)
        b = bytearray(f.read_bytes())
        if not b:
            continue
        if r.random() < 0.3:
            b = b[: r.randrange(len(b))]
        else:
            for _ in range(r.randint(1, 16)):
                b[r.randrange(len(b))] = r.randrange(256)
        f.write_bytes(bytes(b))
    out = subprocess.run([binp, "--game", str(work), "--saves", str(work.parent / "af-sv"), "--fresh", "--script",
                          str(script), "--check-strips"], capture_output=True, text=True, errors="replace")
    if "ERROR: AddressSanitizer" in out.stderr or "runtime error" in out.stderr or out.returncode < 0:
        bad += 1
        print("REPORT", k, out.returncode)
        print("\n".join(l for l in out.stderr.splitlines() if "ERROR" in l or "runtime error" in l or "#0 " in l or "#1 " in l or "#2 " in l)[:1500])
        shutil.copytree(work, work.parent / f"af-crash-{k}")
print("runs", n, "reports", bad)
