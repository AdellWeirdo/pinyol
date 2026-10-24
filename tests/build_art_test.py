"""tools/build_art.py: a game's raw art (a sheet of a character on white, drawn at another size, a background, its depth map, an
icon) made into its assets from art.json; built again only when something changed; the engine loads and draws them.

    python3 tests/build_art_test.py BP_HEADLESS OUT_DIR
"""
import json
import shutil
import subprocess
import sys
from pathlib import Path

from PIL import Image, ImageDraw

ROOT = Path(__file__).resolve().parents[1]
headless, out = sys.argv[1], Path(sys.argv[2])
shutil.rmtree(out, ignore_errors=True)
game = out / "game"
(game / "raw").mkdir(parents=True)
failures = 0


def check(cond, what):
    global failures
    if not cond:
        failures += 1
        print("FAIL:", what)


# a walk of 4 frames on white, each a 120 px tall green figure (an image model's size), a little apart and moving up and down
sheet = Image.new("RGB", (4 * 200, 200), (255, 255, 255))
d = ImageDraw.Draw(sheet)
for i in range(4):
    x, bob = 40 + i * 200, (i % 2) * 6
    d.ellipse((x, 30 + bob, x + 70, 150 + bob), fill=(90, 200, 120), outline=(20, 40, 20), width=3)
    d.rectangle((x + 20, 150 + bob, x + 30, 170), fill=(20, 40, 20))  # legs down to the floor at 170
    d.rectangle((x + 40, 150 + bob, x + 50, 170), fill=(20, 40, 20))
sheet.save(game / "raw" / "walk.png")
bg = Image.new("RGB", (960, 640), (40, 30, 50))
ImageDraw.Draw(bg).rectangle((200, 400, 639, 519), fill=(120, 70, 30))  # a counter
bg.save(game / "raw" / "bar.png")
mp = Image.new("RGB", (960, 640), (0, 0, 0))
ImageDraw.Draw(mp).rectangle((200, 400, 639, 519), fill=(255, 0, 0))
mp.save(game / "raw" / "bar_depth.png")
icon = Image.new("RGBA", (16, 16), (0, 0, 0, 0))
ImageDraw.Draw(icon).ellipse((2, 2, 13, 13), fill=(240, 200, 60, 255))
icon.save(game / "raw" / "key.png")
(game / "art.json").write_text(json.dumps({
    "defaults": {"colours": 64},
    "pictures": [
        {"id": "SPR_WALK", "src": "raw/walk.png", "split": 4, "frame": [48, 64], "height": 50, "key_bg": True, "ms": 120},
        {"id": "BG_BAR", "src": "raw/bar.png", "size": [480, 320], "depth": {"map": "raw/bar_depth.png", "z_from_bottom": True}},
        {"id": "ICO_KEY", "src": "raw/key.png", "copy": True, "colours": 16},
        {"id": "SPR_FEET", "src": "raw/walk.png", "split": 4, "frame": [64, 80], "height": 50, "key_bg": True, "fit": "feet"},
    ]}))


def build(*extra):
    return subprocess.run([sys.executable, str(ROOT / "tools" / "build_art.py"), str(game), *extra], capture_output=True, text=True)


r = build("--sheet", str(out / "sheet.png"))
check(r.returncode == 0, "it builds: " + r.stdout[-500:] + r.stderr[-500:])
meta = json.loads((game / "assets" / "SPR_WALK.meta.json").read_text())
check(meta["w"] == 48 and meta["h"] == 64 and meta["frames"] == 4 and meta["frame_ms"] == [120] * 4, f"the walk: 4 frames of 48x64 ({meta['w']}x{meta['h']}, {meta['frames']})")
built = Image.open(game / "art" / ".built" / "SPR_WALK.png").convert("RGBA")
f0 = built.crop((0, 0, 48, 64))
box = f0.getchannel("A").point(lambda a: 255 if a >= 128 else 0).getbbox()
check(box is not None and abs((box[3] - box[1]) - 50) <= 4 and box[3] in (62, 63), f"its body is 50 tall and stands on the foot: {box}")
check(f0.getpixel((0, 0))[3] == 0, "the white background is gone")
# the "feet" fit (tools/sprite_kit.py): every frame's soles on the foot row (80 - 1 - 1 = 78 + 1), the middle of the feet on the middle column, inside its cell
fm = json.loads((game / "assets" / "SPR_FEET.meta.json").read_text())
check(fm["w"] == 64 and fm["h"] == 80 and fm["frames"] == 4, f"the feet fit: 4 frames of 64x80 ({fm['w']}x{fm['h']})")
fb = Image.open(game / "art" / ".built" / "SPR_FEET.png").convert("RGBA")
for i in range(4):
    a = fb.crop((i * 64, 0, (i + 1) * 64, 80)).getchannel("A").point(lambda v: 255 if v >= 128 else 0)
    bb = a.getbbox()
    check(bb is not None and bb[3] == 78 and 0 <= bb[0] and bb[2] <= 64, f"feet fit frame {i}: soles on the anchor row (78), inside the cell: {bb}")
bgm = json.loads((game / "assets" / "BG_BAR.meta.json").read_text())
check(bgm["w"] == 480 and bgm["h"] == 320, "the background covers 480x320")
dl = (game / "bg_bar_depth.lua").read_text()
check('pic = "BG_BAR_1", x = 100, y = 200, z = 260' in dl, "its counter cut at half the size: " + dl)
check(json.loads((game / "assets" / "ICO_KEY.meta.json").read_text())["w"] == 16, "the icon as it is")
check((out / "sheet.png").exists(), "the sheet to look at")
r2 = build()
check(r2.stdout.count("unchanged") == 4 and "built" not in r2.stdout, "a second run builds nothing: " + r2.stdout)
ImageDraw.Draw(icon).rectangle((6, 6, 9, 9), fill=(200, 40, 40, 255))  # (a change to its pixels)
icon.save(game / "raw" / "key.png")
r3 = build()
check("ICO_KEY" in r3.stdout and r3.stdout.count("unchanged") == 3 and r3.stdout.count(" built") == 1, "a changed source is built again: " + r3.stdout)
(game / "art.json").write_text(json.dumps({"pictures": [{"id": "X", "src": "raw/key.png", "colour": 3}]}))
check(build().returncode != 0, "an unknown key is refused (a typo is not silently ignored)")

shutil.copytree(ROOT / "tests" / "games" / "turned" / "fonts", game / "fonts")
(game / "game.json").write_text('{"id": "artb", "title": "Art", "engine": "pinyol@2", "main": "main.lua"}')
(game / "main.lua").write_text("""rooms = require("rooms")
player = {x = 0, y = 0, w = 20, h = 50}
function _init()
  show(0)
  rooms.define({id = "bar", layers = {{pic = "BG_BAR"}}, occluders = require("bg_bar_depth"), spawns = {default = {x = 180, y = 160}}})
  rooms.player = player
  rooms.go("bar")
end
t = 0
function _update() t = t + 1 rooms.update() end
function _draw() rooms.draw(function() img("SPR_WALK", player.x, player.y, {frame = t // 8 % 4}) end, player.y + player.h) img("ICO_KEY", 10, 10) end
""")
(out / "s.script").write_text("new\ntick 20\nexpect_lua imgsize(\"SPR_WALK\") == 48 and select(3, imgsize(\"SPR_WALK\")) == 4\nshot art\nexpect_ok\n")
r = subprocess.run([headless, "--game", str(game), "--saves", str(out / "sv"), "--fresh", "--script", str(out / "s.script"), "--check-strips"],
                   capture_output=True, text=True)
check(r.returncode == 0, "the engine draws them: " + r.stdout[-300:] + r.stderr[-300:])
print("build_art: %s" % ("ok" if not failures else "%d failed" % failures))
sys.exit(1 if failures else 0)
