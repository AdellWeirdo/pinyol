"""The importers and checkers in tools/, on files made here: an .aseprite written by hand (two frames, a tag, a slice),
an LDtk simplified export, and a strings.csv against the device test game's fonts. Usage: tools_test.py BUILD_DIR"""
import json
import struct
import subprocess
import sys
import zlib
from pathlib import Path

from PIL import Image

ROOT = Path(__file__).resolve().parent.parent
out = Path(sys.argv[1]) / "tools_test"
if out.exists():
    import shutil
    shutil.rmtree(out)
out.mkdir(parents=True)


def chunk(ctype, body):
    return struct.pack("<IH", 6 + len(body), ctype) + body


def ase_file():
    """A 4x3 RGBA sprite: frame 0 red (100 ms), frame 1 blue (200 ms), a layer 'Body', a tag 'run' over both, a slice."""
    w, h = 4, 3
    frames = []
    layer = chunk(0x2004, struct.pack("<HHHHHHHHB", 3, 0, 0, 0, 0, 0, 0, 0, 255) + b"\0\0\0" + struct.pack("<H", 4) + b"Body")
    tags = chunk(0x2018, struct.pack("<H", 1) + b"\0" * 8 + struct.pack("<HHBH", 0, 1, 2, 0) + b"\0" * 6 + b"\0\0\0\0" + b"\0" + struct.pack("<H", 3) + b"run")
    slices = chunk(0x2022, struct.pack("<III", 1, 2, 0) + struct.pack("<H", 6) + b"hitbox" + struct.pack("<IiiII", 0, 1, 0, 2, 3) + struct.pack("<ii", 1, 2))
    for i, (col, ms) in enumerate((((255, 0, 0, 255), 100), ((0, 0, 255, 255), 200))):
        px = bytes(col) * (w * h)
        cel = chunk(0x2005, struct.pack("<HhhBHh", 0, 0, 0, 255, 2, 0) + b"\0" * 5 + struct.pack("<HH", w, h) + zlib.compress(px))
        chunks = (layer + tags + slices + cel) if i == 0 else cel
        n = chunks.count(b"") and 0
        nchunks = 4 if i == 0 else 1
        frames.append(struct.pack("<IHHHHI", 16 + len(chunks), 0xF1FA, nchunks, ms, 0, nchunks) + chunks)
    body = b"".join(frames)
    header = struct.pack("<IHHHHHIHIIB", 128 + len(body), 0xA5E0, len(frames), w, h, 32, 1, 100, 0, 0, 0) + b"\0" * 3 + struct.pack("<HBBhhHH", 256, 1, 1, 0, 0, w, h) + b"\0" * 84
    assert len(header) == 128, len(header)
    return header + body


game = out / "game"
(game / "assets").mkdir(parents=True)
(game / "hero.aseprite").write_bytes(ase_file())
subprocess.run([sys.executable, str(ROOT / "tools/ase2asset.py"), str(game / "hero.aseprite"), str(game), "HERO"], check=True)
meta = json.loads((game / "assets/HERO.meta.json").read_text())
assert meta["frames"] == 2 and meta["w"] == 4 and meta["h"] == 3 and meta["frame_ms"] == [100, 200], meta
px = (game / "assets/HERO.rgb565").read_bytes()
assert struct.unpack("<H", px[:2])[0] == 0xF800 and struct.unpack("<H", px[4 * 3 * 2:4 * 3 * 2 + 2])[0] == 0x001F
anims = (game / "hero_anims.lua").read_text()
assert "run = {frames = {1, 2}, ms = {100, 200}, mode = \"pingpong\"}" in anims, anims
assert "hitbox = {x = 1, y = 0, w = 2, h = 3, pivot = {1, 2}}" in anims, anims

# LDtk: a 16x8 level, an IntGrid of 8 px cells, one entity
level = out / "Level_0"
level.mkdir()
Image.new("RGBA", (16, 8), (10, 200, 30, 255)).save(level / "_composite.png")
(level / "Walls.csv").write_text("1,1,\n0,1,\n")
(level / "data.json").write_text(json.dumps({"width": 16, "height": 8, "bgColor": "#112233", "neighbourLevels": [{"levelIid": "abc", "dir": "e"}],
    "entities": {"Door": [{"id": "Door", "iid": "x", "layer": "Entities", "x": 8, "y": 0, "width": 8, "height": 8, "color": "#fff",
                           "customFields": {"locked": True, "key": "gold"}}]}}))
subprocess.run([sys.executable, str(ROOT / "tools/ldtk2asset.py"), str(level), str(game), "LEVEL0"], check=True)
lua = (game / "level0.lua").read_text()
assert "grids" in lua and "Walls" in lua and "data = {1, 1, 0, 1}" in lua and "size = 8" in lua, lua
assert 'name = "Door"' in lua and "locked = true" in lua and 'key = "gold"' in lua and 'dir = "e"' in lua, lua
meta = json.loads((game / "assets/LEVEL0.meta.json").read_text())
assert meta["w"] == 16 and meta["type"] == "background"
subprocess.run([sys.executable, str(ROOT / "tools/ldtk2asset.py"), str(level), str(game), "LEVEL0T", "--tiles"], check=True)
assert (game / "assets/LEVEL0T.tiles").exists() and (game / "assets/LEVEL0T.pal").exists()

# strings: the device game's fonts cover plain letters; a key missing in one language and a letter no font has are reported
import shutil
shutil.copytree(ROOT / "tests/games/device/fonts", game / "fonts")
(game / "strings.csv").write_text("key,es,en\nhello,Hola,Hello\nfull,Lleno,\n")
r = subprocess.run([sys.executable, str(ROOT / "tools/strings_check.py"), str(game), "--pseudo"], capture_output=True, text=True)
assert r.returncode == 1 and "en: 1 keys without a text: full" in r.stdout, r.stdout
assert (game / "strings.pseudo.csv").exists()
(game / "strings.csv").write_text("key,es,en\nhello,Hola,Hello\n")
r = subprocess.run([sys.executable, str(ROOT / "tools/strings_check.py"), str(game)], capture_output=True, text=True)
assert r.returncode == 0, r.stdout
(game / "strings.csv").write_text("key,es,en\nhello,Hola ☃,Hello\n")
r = subprocess.run([sys.executable, str(ROOT / "tools/strings_check.py"), str(game)], capture_output=True, text=True)
assert r.returncode == 1 and "lacks ☃" in r.stdout, r.stdout

# pack_game --budget lists the files and kinds
(game / "game.json").write_text('{"id": "toolsgame", "title": "T", "engine": "pinyol@2"}')
r = subprocess.run([sys.executable, str(ROOT / "tools/pack_game.py"), str(game), "--budget"], capture_output=True, text=True, check=True)
assert "assets/HERO.rgb565" in r.stdout and "kind" in r.stdout, r.stdout
print("tools_test: ok")
