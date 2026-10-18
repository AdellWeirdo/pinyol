"""A texture page keeps small pictures together and gives each its own UV rectangle."""
import json
import re
import shutil
import subprocess
import sys
import tempfile
from pathlib import Path

from PIL import Image

ROOT = Path(__file__).resolve().parents[1]


def run(game, *args):
    return subprocess.run([sys.executable, str(ROOT / "tools" / "make_atlas.py"), str(game), *args],
                          capture_output=True, text=True)


with tempfile.TemporaryDirectory() as temp:
    game = Path(temp)
    built, assets = game / "art" / ".built", game / "assets"
    built.mkdir(parents=True)
    assets.mkdir()
    for aid, size, color in (("A", (10, 6), (250, 20, 20, 255)), ("B", (9, 8), (20, 240, 20, 255))):
        Image.new("RGBA", size, color).save(built / f"{aid}.png")
        (assets / f"{aid}.meta.json").write_text(json.dumps({"frames": 1, "w": size[0], "h": size[1]}))
    result = run(game, "PAGE", "A", "B")
    assert result.returncode == 0, result.stderr
    meta = json.loads((assets / "PAGE.meta.json").read_text())
    assert meta["atlas_sources"] == ["A", "B"] and meta["w"] == meta["h"] == 128
    assert (assets / "PAGE.pk").exists()
    lua = (game / "page_atlas.lua").read_text()
    page = Image.open(built / "PAGE.png").convert("RGBA")
    for aid, color in (("A", (250, 20, 20, 255)), ("B", (20, 240, 20, 255))):
        values = re.search(rf'\["{aid}"\] = {{id = "PAGE", uv = {{(.*?)}}}}', lua)
        assert values, lua
        u1, v1, u2, _, _, v2, _, _ = map(int, values.group(1).split(", "))
        assert page.getpixel((u1, v1)) == color
        assert page.getpixel((u2, v2 - 1)) == color
        assert page.getpixel((u1 - 1, v1)) == color  # one-pixel extruded gutter
    assert run(game, "PAGE", "A", "B").returncode == 0  # repeatable output
    assert run(game, "PAGE", "../escape").returncode != 0
    assert run(game, "A", "B").returncode != 0  # never replace an ordinary asset
    assert not (game / "escape.pk").exists()
    (game / "blocked_atlas.lua").write_text("return {user = true}\n")
    assert run(game, "BLOCKED", "A").returncode != 0
    assert (game / "blocked_atlas.lua").read_text() == "return {user = true}\n"
    Image.new("RGBA", (127, 127)).save(built / "BIG.png")
    (assets / "BIG.meta.json").write_text(json.dumps({"frames": 1, "w": 127, "h": 127}))
    assert run(game, "TOOBIG", "BIG").returncode != 0
    for aid in ("C", "D"):
        Image.new("RGBA", (100, 100), (30, 40, 50, 255)).save(built / f"{aid}.png")
        (assets / f"{aid}.meta.json").write_text(json.dumps({"frames": 1, "w": 100, "h": 100}))
    assert run(game, "OVERFULL", "C", "D").returncode != 0
    assert not (assets / "OVERFULL.pk").exists()
    (assets / "A.meta.json").write_text(json.dumps({"frames": 2, "w": 10, "h": 6}))
    assert run(game, "ANIM", "A").returncode != 0

    shutil.copytree(ROOT / "tests" / "games" / "turned" / "fonts", game / "fonts")
    (game / "game.json").write_text(json.dumps({"id": "atlas_test", "title": "Atlas", "engine": "pinyol@2", "main": "main.lua"}))
    (game / "main.lua").write_text('''
local a = require("page_atlas")
function _init() canvas("OUT", 32, 16) end
function _draw()
  target("OUT")
  cls(0x0000FF)
  quad(a.A.id, 0, 0, 10, 0, 10, 6, 0, 6, {uv = a.A.uv})
  quad(a.B.id, 12, 0, 21, 0, 21, 8, 12, 8, {uv = a.B.uv})
  target()
end
function atlas_ok()
  return pget(5, 3, "OUT") == pget(a.A.uv[1] + 5, a.A.uv[2] + 3, "PAGE")
     and pget(15, 3, "OUT") == pget(a.B.uv[1] + 3, a.B.uv[2] + 3, "PAGE")
     and pget(11, 3, "OUT") == 0x0000FF
end
''')
    script = game / "atlas.script"
    script.write_text("new\ntick 2\nexpect_lua atlas_ok()\nexpect_ok\n")
    rendered = subprocess.run([sys.argv[1], "--game", str(game), "--saves", str(game / "saves"),
                               "--fresh", "--script", str(script), "--check-strips"], capture_output=True, text=True)
    assert rendered.returncode == 0, rendered.stdout + rendered.stderr

print("atlas: PASS")
