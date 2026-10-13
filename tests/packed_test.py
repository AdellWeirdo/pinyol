"""Packed pictures (tools/png2asset.py --packed) against the same pictures as RGB565: tests/neo.script played with
each gives the same frames, every one (strips checked too). Then broken .pk files: refused, never read past.

    python3 tests/packed_test.py BP_HEADLESS OUT_DIR
"""
import filecmp
import random
import shutil
import subprocess
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
headless, out = sys.argv[1], Path(sys.argv[2])
shutil.rmtree(out, ignore_errors=True)
out.mkdir(parents=True)


def make(name, *opts):
    subprocess.run([sys.executable, str(ROOT / "tests" / "make_neo_game.py"), str(out / name), *opts], check=True,
                   stdout=subprocess.DEVNULL)


def play(name, *opts):
    crc = out / f"{name}{len(opts)}.crc"
    subprocess.run([headless, "--game", str(out / name), "--saves", str(out / f"{name}_saves"), "--fresh", "--script",
                    str(ROOT / "tests" / "neo.script"), "--crc", str(crc), "--check-strips", *opts], check=True,
                   stdout=subprocess.DEVNULL)
    return crc


make("plain")
make("packed", "--packed")
assert filecmp.cmp(play("plain"), play("packed"), shallow=False), "packed pictures drew differently"
# a budget smaller than the pictures: they are let go and come back from the card, and draw the same
assert filecmp.cmp(play("packed"), play("packed", "--pictures", "300"), shallow=False), "pictures let go drew differently"
assert filecmp.cmp(play("plain"), play("plain", "--pictures", "300"), shallow=False), "pictures let go drew differently"
sizes = {n: sum(f.stat().st_size for f in (out / n / "assets").iterdir()) for n in ("plain", "packed")}
print(f"packed: the same frames in {sizes['packed'] // 1024} KB instead of {sizes['plain'] // 1024} KB")

rng = random.Random(7)  # broken files: cut short, bytes changed; the game still runs (a checkerboard where they were)
pk = out / "packed" / "assets" / "SPR_F1.pk"
good = pk.read_bytes()
for trial in range(40):
    bad = bytearray(good)
    if trial % 2:
        bad = bad[:rng.randrange(len(bad))]
    else:
        for _ in range(1 + trial):
            bad[rng.randrange(len(bad))] = rng.randrange(256)
    pk.write_bytes(bytes(bad))
    r = subprocess.run([headless, "--game", str(out / "packed"), "--saves", str(out / "fuzz_saves"), "--fresh", "--script",
                        str(ROOT / "tests" / "neo.script")], capture_output=True, text=True)
    assert r.returncode == 0, f"a broken .pk (trial {trial}) broke the game:\n{r.stdout[-800:]}{r.stderr[-800:]}"

def crafted(w, h, frames):  # files that are well formed but for one thing, each must be refused by name
    import struct
    head = b"NP2K" + bytes([1, 8]) + struct.pack("<HHHHH", 1, w, h, frames, 0) + struct.pack("<H", 0) + b"\0\0"
    col = struct.pack("<HHH", 1, 0, 1) + b"\0"
    table = len(head) + 4 * w * frames
    yield "a column outside the file", head + struct.pack(f"<{w * frames}I", *([0xFFFFFFFE] + [table] * (w * frames - 1))) + col
    head4 = b"NP2K" + bytes([1, 4]) + struct.pack("<HHHHH", 2, w, h, frames, 0) + struct.pack("<HH", 0, 0xFFFF)
    yield "a colour outside the palette", head4 + struct.pack(f"<{w * frames}I", *[len(head4) + 4 * w * frames] * (w * frames)) + \
        struct.pack("<HHH", 1, 0, 1) + bytes([0xF0])


w, h, frames = (int.from_bytes(good[i:i + 2], "little") for i in (8, 10, 12))
for why, bad in crafted(w, h, frames):
    pk.write_bytes(bad)
    r = subprocess.run([headless, "--game", str(out / "packed"), "--saves", str(out / "fuzz_saves"), "--fresh", "--script",
                        str(ROOT / "tests" / "neo.script")], capture_output=True, text=True)
    assert r.returncode == 0 and why in r.stdout + r.stderr, f"{why}: not refused\n{r.stdout[-800:]}{r.stderr[-800:]}"
pk.write_bytes(good)
print("packed: 40 broken files and 2 made to fool the checks refused")
