"""Makes the game tests/clip.script plays: a clip made by tools/clip2npv.py from frames drawn here (each with its
number as the colour of its top-left corner, and a square moving across, so a test can tell which frame is on the
canvas and that the frames between keyframes came out right), and broken copies of it, which must only fail to open
or play, never crash (under ASan in Debug).

    python3 tests/make_clip_game.py OUT_DIR
"""
import json
import random
import shutil
import struct
import subprocess
import sys
import tempfile
from pathlib import Path

from PIL import Image, ImageDraw

ROOT = Path(__file__).resolve().parents[1]
out = Path(sys.argv[1])
shutil.rmtree(out, ignore_errors=True)
out.mkdir(parents=True)
shutil.copytree(ROOT / "tests" / "games" / "libs" / "fonts", out / "fonts")
# colours a 16-bit screen shows exactly: what the test reads back with pget is what was drawn
MARKS = [(255, 0, 0), (0, 255, 0), (0, 0, 255), (255, 255, 0), (0, 255, 255), (255, 0, 255), (255, 255, 255),
         (132, 0, 0)]
BACK, SQUARE = (0, 0, 132), (255, 134, 0)
with tempfile.TemporaryDirectory() as tmp:
    for k in range(40):
        im = Image.new("RGB", (64, 48), BACK)
        d = ImageDraw.Draw(im)
        d.rectangle((0, 0, 7, 7), fill=MARKS[k % len(MARKS)])
        d.rectangle((k, 20, k + 9, 29), fill=SQUARE)
        im.save(f"{tmp}/f{k:03d}.png")
    subprocess.run([sys.executable, str(ROOT / "tools" / "clip2npv.py"), tmp, str(out), "demo", "--fps", "15",
                    "--width", "64", "--height", "48", "--colours", "16", "--key", "8"], check=True,
                   stdout=subprocess.DEVNULL)

good = (out / "video" / "demo.npv").read_bytes()
w, h, fps, ncol, frames, key = struct.unpack_from("<HHHHII", good, 4)
index_at = 20 + 2 * ncol
rng = random.Random(7)
bad = {
    "cut_head": good[:12],
    "cut_index": good[:index_at + 8],
    "cut_frames": good[:len(good) // 2],
    "magic": b"NPV2" + good[4:],
    "huge": good[:4] + struct.pack("<HH", 4000, 4000) + good[8:],
    "no_fps": good[:8] + struct.pack("<H", 0) + good[10:],
    "frames": good[:12] + struct.pack("<I", 0xFFFFFFF0) + good[16:],
    "index_back": good[:index_at + 4] + struct.pack("<I", 3) + good[index_at + 8:],
    "index_past": good[:index_at + 4 * frames] + struct.pack("<I", len(good) + 999) + good[index_at + 4 * frames + 4:],
    "colours": good[:10] + struct.pack("<H", 2) + good[12:],  # indices past the palette in the frames
}
for n in range(12):  # noise over the frames' ops
    b = bytearray(good)
    for _ in range(40):
        b[rng.randrange(index_at + 4 * (frames + 1), len(b))] = rng.randrange(256)
    bad[f"noise{n}"] = bytes(b)
for name, data in bad.items():
    (out / "video" / f"{name}.npv").write_bytes(data)
(out / "bad.txt").write_text("\n".join(bad))
(out / "game.json").write_text(json.dumps({"id": "clip", "title": "Clip", "engine": "np2d@2", "main": "main.lua"}))
(out / "main.lua").write_text('''-- Clips (src/lua_clip.c), checked by tests/clip.script
MARKS = {0xFF0000, 0x00FF00, 0x0000FF, 0xFFFF00, 0x00FFFF, 0xFF00FF, 0xFFFFFF, 0x840000}
function _init() show(0) end
function _update() end
function _draw()
  cls(0x101010)
  if tv then img(tv_canvas or "demo", 16, 16, {scale = 4}) end
end
function mark(k) return MARKS[k % 8 + 1] end
function on(k, c) -- is frame k on canvas c: its mark, and the square where frame k has it
  c = c or "demo"
  return pget(2, 2, c) == mark(k) and pget(k + 1, 25, c) == 0xFF8600 and pget(k + 11, 25, c) == 0x000084
end
function try_bad()
  local opened, failed = 0, 0
  for name in file("bad.txt"):gmatch("[^\\n]+") do
    local ok, c = pcall(video, name, {canvas = "BAD", loop = true, speed = 3})
    if ok then
      opened = opened + 1
      for _ = 1, 20 do pcall(c.seek, c, math.random(-5, 50)) end
      if last then last:close() end
      last = c -- the last one opened plays on
    else
      failed = failed + 1
      log(c)
    end
  end
  return opened, failed
end
''')
print("clip game in", out)
