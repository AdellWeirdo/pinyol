"""Clips with scenes (tools/clip2npv.py, src/lua_clip.c NPV2): each scene its own palette, so a red scene and a blue one each
keep their gradients; jumping into a scene and back brings its colours; the ordered dither stays put from frame to frame.

    python3 tests/clip_scenes_test.py BP_HEADLESS OUT_DIR
"""
import shutil
import struct
import subprocess
import sys
from pathlib import Path

from PIL import Image

ROOT = Path(__file__).resolve().parents[1]
headless, out = sys.argv[1], Path(sys.argv[2])
shutil.rmtree(out, ignore_errors=True)
(out / "frames").mkdir(parents=True)
failures = 0


def check(cond, what):
    global failures
    if not cond:
        failures += 1
        print("FAIL:", what)


W, H = 64, 48
src = []
for k in range(30):  # 15 frames of a red ramp, then 15 of a blue one, each moving a little
    im = Image.new("RGB", (W, H))
    px = im.load()
    for y in range(H):
        for x in range(W):
            v = (x * 4 + k) % 256
            px[x, y] = (v, v // 4, 0) if k < 15 else (0, v // 3, v)
    im.save(out / "frames" / f"f{k:03d}.png")
    src.append(im)


def make(game, *opts):
    r = subprocess.run([sys.executable, str(ROOT / "tools" / "clip2npv.py"), str(out / "frames"), str(game), "demo", "--fps", "15",
                        "--width", str(W), "--height", str(H), "--colours", "16", "--no-sound", *opts], capture_output=True, text=True)
    check(r.returncode == 0, "clip2npv runs: " + r.stderr[-300:])
    return (game / "video" / "demo.npv").read_bytes(), r.stdout


def play(game, frames):
    """The frames given, as the engine shows them on the clip's canvas: {frame: [(r, g, b) row by row]}"""
    shutil.copytree(ROOT / "tests" / "games" / "turned" / "fonts", game / "fonts", dirs_exist_ok=True)
    (game / "game.json").write_text('{"id": "sc", "title": "Scenes", "engine": "pinyol@2", "main": "main.lua"}')
    (game / "main.lua").write_text("function _init() show(0) tv = video(\"demo\", {play = false}) end\nfunction _draw() end\n"
                                   "function dump(k) tv:seek(k) local t = {} for y = 0, %d do for x = 0, %d do t[#t + 1] = pget(x, y, \"demo\") end end print(\"F\" .. k .. \":\" .. table.concat(t, \",\")) end\n" % (H - 1, W - 1))
    script = game / "s.script"
    script.write_text("new\ntick 2\n" + "".join(f"lua dump({k})\n" for k in frames) + "expect_ok\n")
    r = subprocess.run([headless, "--game", str(game), "--saves", str(game / "sv"), "--fresh", "--script", str(script)], capture_output=True, text=True)
    check(r.returncode == 0, "the engine plays it: " + r.stdout[-300:])
    shown = {}
    for line in (r.stdout + r.stderr).splitlines():
        if "F" in line and ":" in line:
            tag, _, vals = line[line.index("F"):].partition(":")
            if tag[1:].isdigit() and vals:
                shown[int(tag[1:])] = [(int(v) >> 16 & 255, int(v) >> 8 & 255, int(v) & 255) for v in vals.split(",")]
    return shown


def error(shown, k):
    s = [src[k].getpixel((x, y)) for y in range(H) for x in range(W)]
    return sum(abs(a - b) for p, q in zip(shown, s) for a, b in zip(p, q)) / (len(s) * 3)


one, said1 = make(out / "one", "--one-palette")
two, said2 = make(out / "two")
check(one[:4] == b"NPV2" and two[:4] == b"NPV2", "the new kind")
check("1 scene" in said1 and "2 scene" in said2, "two scenes found: " + said2)
frames = struct.unpack_from("<I", two, 12)[0]
ncol = struct.unpack_from("<H", two, 10)[0]
idx = [struct.unpack_from("<I", two, 20 + 2 * ncol + 4 * i)[0] for i in range(frames)]
keys = [i for i, v in enumerate(idx) if v >> 31]
check(keys[:2] == [0, 15], f"a scene starts whole: keyframes at {keys}")
# seeking into the blue scene and back (each from its keyframe, with its palette): the colours are each scene's
a = play(out / "two", [20, 3, 25])
b = play(out / "one", [20, 3, 25])
for k in (20, 3, 25):
    check(k in a and k in b, f"frame {k} shown")
if all(k in a and k in b for k in (20, 3, 25)):
    e2 = [error(a[k], k) for k in (20, 3, 25)]
    e1 = [error(b[k], k) for k in (20, 3, 25)]
    check(max(e2) < 5, f"with a palette a scene, close to the source: {e2}")
    check(sum(e2) < sum(e1) * 0.7, f"closer than one palette for both: {e2} against {e1}")
    print("error with a palette a scene %.2f, with one %.2f" % (sum(e2) / 3, sum(e1) / 3))
    check(all(p[2] == 0 for p in a[3]) and all(p[0] == 0 for p in a[20]), "the red scene has no blue, the blue none of the red")
# ordered dither: on a clip whose picture barely moves, it stays put, so the deltas stay small (Floyd-Steinberg's noise moves)
still = Image.new("RGB", (W, H))
pxs = still.load()
for y in range(H):
    for x in range(W):
        pxs[x, y] = (x * 4, y * 5, 128)
for k in range(30):
    im = still.copy()
    im.paste((255, 255, 255), (k, 2, k + 3, 5))  # a dot crossing
    im.save(out / "frames" / f"f{k:03d}.png")
ordd, _ = make(out / "ord", "--ordered", "--key", "100")
fs, _ = make(out / "fs", "--dither", "--key", "100")
print("ordered %d bytes, Floyd-Steinberg %d" % (len(ordd), len(fs)))
check(len(ordd) < len(fs) * 0.6, f"ordered dither is far smaller in a delta: {len(ordd)} against {len(fs)} bytes")
print("clip scenes: %s" % ("ok" if not failures else "%d failed" % failures))
sys.exit(1 if failures else 0)
