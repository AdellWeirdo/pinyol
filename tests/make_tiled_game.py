"""Makes the game tests/tiled.script plays: two small Tiled maps (.tmx with CSV data, an external .tsx, flipped tiles,
objects and properties; .json with zlib base64 data) imported with tools/tiled2asset.py.

    python3 tests/make_tiled_game.py OUT_DIR
"""
import base64
import json
import shutil
import struct
import subprocess
import sys
import zlib
from pathlib import Path

from PIL import Image, ImageDraw

ROOT = Path(__file__).resolve().parents[1]
out = Path(sys.argv[1])
shutil.rmtree(out, ignore_errors=True)
(out / "maps").mkdir(parents=True)
shutil.copytree(ROOT / "examples" / "naves" / "fonts", out / "fonts")

# a 32x32 tileset of four 16x16 tiles: red, green, blue, and a white triangle (to see flips)
ts = Image.new("RGBA", (32, 32))
d = ImageDraw.Draw(ts)
d.rectangle((0, 0, 15, 15), fill=(255, 0, 0, 255))
d.rectangle((16, 0, 31, 15), fill=(0, 255, 0, 255))
d.rectangle((0, 16, 15, 31), fill=(0, 0, 255, 255))
d.polygon([(16, 16), (31, 16), (16, 31)], fill=(255, 255, 255, 255))
ts.save(out / "maps" / "tiles.png")
(out / "maps" / "tiles.tsx").write_text("""<?xml version="1.0" encoding="UTF-8"?>
<tileset name="tiles" tilewidth="16" tileheight="16" tilecount="4" columns="2">
 <image source="tiles.png" width="32" height="32"/>
 <tile id="1"><properties><property name="solid" type="bool" value="true"/></properties></tile>
</tileset>
""")
H = 0x80000000
(out / "maps" / "level1.tmx").write_text(f"""<?xml version="1.0" encoding="UTF-8"?>
<map version="1.10" orientation="orthogonal" width="4" height="3" tilewidth="16" tileheight="16" infinite="0">
 <properties><property name="music" value="MUS_1"/></properties>
 <tileset firstgid="1" source="tiles.tsx"/>
 <layer id="1" name="ground" width="4" height="3">
  <data encoding="csv">
1,2,0,{4 | H},
0,0,0,0,
3,3,2,2
</data>
 </layer>
 <objectgroup id="2" name="things">
  <object id="1" name="start" type="spawn" x="20" y="18"/>
  <object id="2" name="door" type="exit" x="48" y="32" width="16" height="16">
   <properties><property name="to" value="level2"/><property name="locked" type="bool" value="true"/></properties>
  </object>
 </objectgroup>
</map>
""")
cells = [2, 2, 2, 2, 1, 0, 0, 1]
(out / "maps" / "level2.json").write_text(json.dumps({
    "width": 4, "height": 2, "tilewidth": 16, "tileheight": 16, "infinite": False,
    "tilesets": [{"firstgid": 1, "source": "tiles.tsx"}],
    "layers": [{"type": "tilelayer", "name": "Back Wall", "width": 4, "height": 2, "visible": True,
                "encoding": "base64", "compression": "zlib",
                "data": base64.b64encode(zlib.compress(struct.pack("<8I", *cells))).decode()},
               {"type": "objectgroup", "name": "o", "objects": [{"name": "coin", "class": "pickup", "x": 8, "y": 8,
                                                                  "width": 0, "height": 0}]}]}))
t2a = [sys.executable, str(ROOT / "tools" / "tiled2asset.py")]
subprocess.run(t2a + [str(out / "maps" / "level1.tmx"), str(out), "LEVEL1"], check=True)
subprocess.run(t2a + [str(out / "maps" / "level2.json"), str(out), "LEVEL2"], check=True)
(out / "game.json").write_text(json.dumps({"id": "tiled", "title": "Tiled", "engine": "np2d@2", "main": "main.lua"}))
(out / "main.lua").write_text("""L1, L2 = require("level1"), require("level2")
function _init()
  bg(1, {map = "LEVEL1_GROUND"})
  bg(2, {map = "LEVEL2_BACK_WALL", prio = 2})
end
function _update() end
function _draw() end
""")
