"""tools/depthcut.py: a background cut into the pieces that pass in front of the characters, each at its depth, and rooms
drawing the character among them (tests/games/adv does the ordering with pictures made in code; this one with real files).

    python3 tests/depthcut_test.py BP_HEADLESS OUT_DIR
"""
import re
import shutil
import subprocess
import sys
from pathlib import Path

from PIL import Image, ImageDraw

ROOT = Path(__file__).resolve().parents[1]
headless, out = sys.argv[1], Path(sys.argv[2])
shutil.rmtree(out, ignore_errors=True)
out.mkdir(parents=True)
failures = 0


def check(cond, what):
    global failures
    if not cond:
        failures += 1
        print("FAIL:", what)


def tool(*args, game):
    return subprocess.run([sys.executable, str(ROOT / "tools" / "depthcut.py"), *map(str, args)], capture_output=True, text=True)


# a background with a striped counter and a stool, and the map that names them
bg = Image.new("RGB", (480, 320), (40, 50, 90))
d = ImageDraw.Draw(bg)
d.rectangle((100, 200, 219, 259), fill=(120, 70, 30))
d.rectangle((300, 220, 319, 249), fill=(150, 150, 150))
bg.save(out / "bg.png")
mp = Image.new("RGB", (480, 320), (0, 0, 0))
d = ImageDraw.Draw(mp)
d.rectangle((100, 200, 219, 259), fill=(255, 0, 0))
d.rectangle((300, 220, 319, 249), fill=(0, 255, 0))
mp.save(out / "map.png")

game = out / "game"
r = tool(out / "bg.png", out / "map.png", game, "BG_TEST", "--z", "FF0000=280,00FF00=262", game=game)
check(r.returncode == 0, "the tool runs: " + r.stderr[-300:])
lua = (game / "bg_test_depth.lua").read_text()
rows = re.findall(r'pic = "(\w+)", x = (\d+), y = (\d+), z = (\d+)', lua)
check(rows == [("BG_TEST_1", "300", "220", "262"), ("BG_TEST_2", "100", "200", "280")], f"pieces ordered by depth: {rows}")
check((game / "assets" / "BG_TEST.pk").exists() and (game / "assets" / "BG_TEST_1.pk").exists(), "the pictures are written")
check('"w": 20' in (game / "assets" / "BG_TEST_1.meta.json").read_text(), "a piece is cut to its box (20 wide)")

r = tool(out / "bg.png", out / "map.png", out / "game2", "BG_TEST", "--z-from-bottom", game=game)
rows = re.findall(r'z = (\d+)', (out / "game2" / "bg_test_depth.lua").read_text())
check(rows == ["250", "260"], f"--z-from-bottom takes the lowest row: {rows}")
r = tool(out / "bg.png", out / "map.png", out / "game3", "BG_TEST", "--z", "FF0000=280", game=game)
check(r.returncode != 0 and "no depth" in r.stderr, "a colour with no depth is refused")
r = tool(out / "bg.png", out / "map.png", out / "game3", "BG_TEST", game=game)
check(r.returncode != 0, "without --z or --z-from-bottom is refused")

# the engine: the pieces and the background load, a piece keeps the background's pixels, rooms orders the player among them
shutil.copytree(ROOT / "tests" / "games" / "turned" / "fonts", game / "fonts")
(game / "game.json").write_text('{"id": "depth", "title": "Depth", "engine": "pinyol@2", "main": "main.lua"}')
(game / "main.lua").write_text("""rooms = require("rooms")
player = {x = 0, y = 0, w = 16, h = 40}
function _init()
  show(0)
  rooms.define({id = "bar", layers = {{pic = "BG_TEST"}}, occluders = require("bg_test_depth"),
                spawns = {default = {x = 130, y = 150}}})
  rooms.player = player
  rooms.go("bar")
end
function _update() rooms.update() end
function _draw() rooms.draw(function() rect(player.x, player.y, player.w, player.h, 0xE04040) end, player.y + player.h) end
function pos(l, n) for i, v in ipairs(l) do if v == n then return i end end end
function near(c, r, g, b) return c and math.abs((c >> 16) - r) < 12 and math.abs((c >> 8 & 255) - g) < 12 and math.abs((c & 255) - b) < 12 end
""")
script = out / "depth.script"
script.write_text("""new
tick 3
expect_lua rooms.id() == "bar"
expect_lua near(pget(5, 5, "BG_TEST_2"), 120, 70, 30) and near(pget(5, 5, "BG_TEST_1"), 150, 150, 150)
expect_lua pget(0, 0, "BG_TEST") ~= nil and imgsize("BG_TEST_2") == 120
lua player.y = 180 behind = rooms.order(function() end, player.y + player.h)
lua player.y = 250 front = rooms.order(function() end, player.y + player.h)
expect_lua pos(behind, "player") < pos(behind, "BG_TEST_2") and pos(front, "player") > pos(front, "BG_TEST_2")
# dim and mul darken a packed picture through its palette: half, and a colour at a time (red whole, green half, blue none)
lua canvas("D", 40, 40) target("D") img("BG_TEST", 0, 0, {dim = 0.5}) target() canvas("M", 40, 40) target("M") img("BG_TEST", 0, 0, {mul = 0xFF8000}) target() base = pget(5, 5, "BG_TEST")
expect_lua near(pget(5, 5, "D"), (base >> 16) // 2, (base >> 8 & 255) // 2, (base & 255) // 2)
expect_lua near(pget(5, 5, "M"), base >> 16, (base >> 8 & 255) // 2, 0)
lua player.x, player.y = 120, 190
tick 2
shot depth
expect_ok
""")
r = subprocess.run([headless, "--game", str(game), "--saves", str(out / "saves"), "--fresh", "--script", str(script), "--check-strips"],
                   capture_output=True, text=True)
check(r.returncode == 0, "the engine draws it: " + r.stdout[-400:] + r.stderr[-300:])
print("depthcut: %s" % ("ok" if not failures else "%d failed" % failures))
sys.exit(1 if failures else 0)
