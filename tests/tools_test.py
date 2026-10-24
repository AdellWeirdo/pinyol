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
# the words lang.lua reads (strings.csv at the game's top) go in the zip, for the web player, the card and the Library;
# the pseudo-translation the checker wrote does not
sys.path.insert(0, str(ROOT / "tools"))
import pack_game
import zipfile
names = zipfile.ZipFile(pack_game.pack(game, out / "zips", False)).namelist()
assert "toolsgame/strings.csv" in names and "toolsgame/strings.pseudo.csv" not in names, names
print("tools_test: ok")

# a FamiStudio text export as a module: four channels, the speed from the note length, a volume envelope followed
FS_TEXT = """Project Version="4.1.0" TempoMode="FamiStudio" Name="Prueba" Author="pinyol"
	Instrument Name="Lead"
		Envelope Type="Volume" Length="4" Values="15,12,8,4"
		Envelope Type="DutyCycle" Length="1" Values="1"
	Instrument Name="Bass"
		Envelope Type="Volume" Length="1" Values="15"
	Song Name="Cancion" Length="2" LoopPoint="1" PatternLength="16" BeatLength="4" NoteLength="6" Groove="6"
		Channel Type="Square1"
			Pattern Name="A"
				Note Time="0" Value="C4" Instrument="Lead"
				Note Time="4" Value="E4" Instrument="Lead"
				Note Time="8" Value="G4" Instrument="Lead" Duration="12"
				Note Time="12" Value="Stop"
			PatternInstance Time="0" Pattern="A"
			PatternInstance Time="1" Pattern="A"
		Channel Type="Square2"
		Channel Type="Triangle"
			Pattern Name="B"
				Note Time="0" Value="C3" Instrument="Bass"
				Note Time="8" Value="G2" Instrument="Bass"
			PatternInstance Time="0" Pattern="B"
		Channel Type="Noise"
			Pattern Name="N"
				Note Time="0" Value="C4" Instrument="Bass"
				Note Time="2" Value="Stop"
			PatternInstance Time="1" Pattern="N"
"""
fs = out / "cancion.txt"
fs.write_text(FS_TEXT, encoding="utf-8")
fsgame = out / "fsgame"
(fsgame / "audio").mkdir(parents=True)
shutil.copytree(ROOT / "tests/games/device/fonts", fsgame / "fonts")
(fsgame / "game.json").write_text(json.dumps({"id": "fsgame", "title": "fs", "engine": "pinyol@2", "main": "main.lua"}))
(fsgame / "main.lua").write_text("function _init() music('FS') end function _update() end function _draw() cls(0) end\n")
subprocess.run([sys.executable, str(ROOT / "tools/famistudio2mod.py"), str(fs), str(fsgame / "audio/FS.mod"), "--song", "Cancion"], check=True)
mod = (fsgame / "audio/FS.mod").read_bytes()
assert mod[1080:1084] == b"M.K." and mod[950] == 2 and mod[951] == 1, (mod[950], mod[951])  # two positions, the loop at the second
names = [mod[20 + i * 30:20 + i * 30 + 22].rstrip(b"\0") for i in range(31)]
assert b"square1" in names and b"triangle" in names and b"noise" in names, names[:4]
pat0 = mod[1084:1084 + 1024]
assert pat0[2 * 4 + 2] & 15 == 0xF and pat0[2 * 4 + 3] == 150 and pat0[3 * 4 + 2] & 15 == 0xF and pat0[3 * 4 + 3] == 6, "the tempo and the speed"
assert pat0[0] & 15 == 428 >> 8 and pat0[1] == 428 & 255, "C4 is period 428"
assert pat0[4 * 16 + 2] & 15 == 0xC and pat0[4 * 16 + 3] == 64, "the envelope: full at the note"  # E4 at row 4: volume 15 -> 64
assert pat0[1 * 16 + 2] & 15 == 0xC and pat0[1 * 16 + 3] < 64, "and falling a row later"
assert pat0[12 * 16 + 3] == 0, "the stop"
assert pat0[15 * 16 + 3 * 4 + 2] & 15 == 0xD, "a pattern of 16 notes breaks at its end"
script = out / "fs.script"
script.write_text("tick 5\nexpect_lua music_beat() ~= nil\ntick 60\nexpect_lua music_beat() ~= nil\nexpect_ok\n")
r = subprocess.run([str(Path(sys.argv[1]) / "pinyol_headless"), "--game", str(fsgame), "--fresh", "--script", str(script)], capture_output=True, text=True)
assert "PASS" in r.stdout + r.stderr, (r.stdout + r.stderr)[-400:]
print("famistudio2mod: ok")


# pk_split: a sheet of seven frames made by png2asset --packed, split into pieces of three: every piece's columns are the
# original's, the pieces' metas are right, and the engine loads them (a game drawing a pixel of each, through the headless)
sys.path.insert(0, str(ROOT / "tools"))
import pk_split  # noqa: E402

sheet = out / "sheet"
(sheet / "assets").mkdir(parents=True)
shutil.copytree(ROOT / "tests/games/device/fonts", sheet / "fonts")
frames = []
for k in range(7):  # a diagonal of an opaque bar per frame: runs of different lengths, some columns empty
    im = Image.new("RGBA", (12, 9), (0, 0, 0, 0))
    for x in range(12):
        for y in range(9):
            if (x + y + k) % 5 < 2 and x > k % 3:
                im.putpixel((x, y), (40 * k % 256, 200 - 20 * k, 90 + 10 * y, 255))
    frames.append(im)
strip = Image.new("RGBA", (12 * 7, 9))
for k, f in enumerate(frames):
    strip.paste(f, (12 * k, 0))
strip.save(out / "sheet_src.png")
subprocess.run([sys.executable, str(ROOT / "tools/png2asset.py"), str(out / "sheet_src.png"), str(sheet / "assets"), "SHEET",
                "--packed", "--frames", "7", "--ms", "50"], check=True)
whole = (sheet / "assets/SHEET.pk").read_bytes()
written = pk_split.split_file(sheet / "assets/SHEET.pk", 3, remove=False)
assert [p.name for p in written] == ["SHEET_C0.pk", "SHEET_C1.pk", "SHEET_C2.pk"], written
metas = [json.loads(p.with_suffix(".meta.json").read_text()) for p in written]
assert [m["frames"] for m in metas] == [3, 3, 1] and metas[1]["asset"] == "SHEET_C1", metas
assert metas[2]["frame_ms"] == [50] and metas[0]["w"] == 12 and metas[0]["h"] == 9 and metas[2]["order"] == [0]
for (f0, f1, piece), p in zip(pk_split.split(whole, 3), written):
    assert piece == p.read_bytes() and pk_split.same_frames(whole, f0, piece)
(sheet / "game.json").write_text(json.dumps({"id": "sheet", "title": "sheet", "engine": "pinyol@2", "main": "main.lua"}))
(sheet / "main.lua").write_text("function _init() show(0) end function _update() end function _draw() cls(0) "
                                "img('SHEET_C0', 0, 0) img('SHEET_C1', 20, 0, {frame = 2}) img('SHEET_C2', 40, 0) end\n")
script = out / "sheet.script"
script.write_text("tick 2\nexpect_lua imgsize('SHEET_C1') == 12\nexpect_lua select(3, imgsize('SHEET_C0')) == 3\n"
                  "expect_lua select(3, imgsize('SHEET_C2')) == 1\nshot sheet\nexpect_ok\n")
r = subprocess.run([str(Path(sys.argv[1]) / "pinyol_headless"), "--game", str(sheet), "--saves", str(out / "sheet_saves"), "--fresh",
                    "--script", str(script)], capture_output=True, text=True)
assert "PASS" in r.stdout + r.stderr, (r.stdout + r.stderr)[-400:]
print("pk_split: ok")

# looks: the phrase table, the checker catching a breach, new_game --look
sys.path.insert(0, str(ROOT / "tools"))
import looks  # noqa: E402
import look_check  # noqa: E402

for phrase, want in (("un juego de Metal Slug", ["neogeo"]), ("Game Boy Advance", ["gba"]), ("a game boy game", ["gameboy"]), ("pico-8", ["pico8"]),
                     ("juego de lucha estilo Street Fighter", ["cps2"]), ("algo retro", []), ("un juego de la NES", ["gameboy"])):
    got = looks.resolve(phrase)[0]
    assert got == want, (phrase, got)
bad = out / "badlook"
(bad / "assets").mkdir(parents=True)
(bad / "main.lua").write_text("c = canvas(480, 320)\n")
(bad / "assets/HERO.meta.json").write_text(json.dumps({"asset": "HERO", "type": "sprite", "format": "idx8", "w": 48, "h": 48}))
(bad / "assets/WORLD.pal").write_bytes(struct.pack("<16H", 0, *range(1, 6), *([0] * 10)))  # one bank with five colours
errs, _ = look_check.check(bad, looks.get("gameboy"))
assert len(errs) == 2 and "5 colours" in errs[0] and "48x48" in errs[1], errs
errs, _ = look_check.check(bad, looks.get("lcd"))
assert len(errs) == 1 and "canvas" in errs[0], errs
r = subprocess.run([sys.executable, str(ROOT / "tools/new_game.py"), str(out / "lookgame"), "--lua", "--look", "metal slug"], capture_output=True, text=True)
assert r.returncode == 0 and "look neogeo" in r.stdout, r.stdout + r.stderr
assert json.loads((out / "lookgame/game.json").read_text())["look"] == "neogeo" and (out / "lookgame/look.md").exists()
assert look_check.check(out / "lookgame", looks.get("neogeo"))[0] == []
assert (out / "lookgame/tests/lookgame.script").exists() and "placeholders" in (out / "lookgame/look.md").read_text()
r = subprocess.run([sys.executable, str(ROOT / "tools/new_game.py"), str(out / "nolook"), "--lua", "--look", "algo retro"], capture_output=True, text=True)
assert r.returncode != 0 and not (out / "nolook").exists(), r.stderr
print("looks: ok")

# slice_pic + lib/slices: a 400x40 picture cut in 160-px columns, only the ones on screen drawn
import slice_pic  # noqa: E402
import numpy as np  # noqa: E402

sl = out / "slices"
shutil.copytree(ROOT / "tests/games/device/fonts", sl / "fonts")
(sl / "assets").mkdir(parents=True, exist_ok=True)
Image.new("RGBA", (400, 40), (200, 60, 60, 255)).save(out / "wide.png")
d = slice_pic.slice_picture(out / "wide.png", sl, "WIDE", 160, [])
assert [(s["x"], s["w"]) for s in d["slices"]] == [(0, 160), (160, 160), (320, 80)] and (d["w"], d["h"]) == (400, 40), d
assert all((sl / f"assets/WIDE_{i}.pk").exists() for i in range(3))
(sl / "wide_slices.lua").write_text(slice_pic.lua_table(d))
(sl / "game.json").write_text(json.dumps({"id": "slices", "title": "slices", "engine": "pinyol@2", "main": "main.lua"}))
(sl / "main.lua").write_text('local slices = require("slices")\nlocal def = require("wide_slices")\nn1, n2, n3 = 0, 0, 0\nfunction _init() show(0) end function _update() end\n'
                             'function _draw() cls(0) n1 = slices.draw(def, 0, 0) n2 = slices.draw(def, -200, 0) n3 = slices.draw(def, 300, 0, {flip_x = true}, 480) end\n')
script = out / "slices.script"
script.write_text("tick 2\nshot slices\nexpect_lua n1 == 3\nexpect_lua n2 == 2\nexpect_lua n3 == 2\nexpect_ok\n")
r = subprocess.run([str(Path(sys.argv[1]) / "pinyol_headless"), "--game", str(sl), "--saves", str(out / "slices_saves"), "--fresh", "--script", str(script)],
                   capture_output=True, text=True)
assert "PASS" in r.stdout + r.stderr, (r.stdout + r.stderr)[-400:]
print("slices: ok")

# a strip of 70 frames is written in two pieces and found by lib/sheets.lua
big = out / "bigsheet"
shutil.copytree(ROOT / "tests/games/device/fonts", big / "fonts")
(big / "assets").mkdir(parents=True)
strip = Image.new("RGBA", (8 * 70, 8))
for k in range(70):
    strip.paste((k * 3 % 256, 40, 200, 255), (8 * k, 0, 8 * k + 8, 8))
strip.save(out / "s70.png")
subprocess.run([sys.executable, str(ROOT / "tools/png2asset.py"), str(out / "s70.png"), str(big / "assets"), "SPR_BIG", "--packed", "--frames", "70"], check=True,
               capture_output=True)
m1, m2 = (json.loads((big / f"assets/{n}.meta.json").read_text()) for n in ("SPR_BIG", "SPR_BIG_2"))
assert m1["frames"] == 64 and m2["frames"] == 6, (m1["frames"], m2["frames"])
(big / "game.json").write_text(json.dumps({"id": "bigsheet", "title": "bigsheet", "engine": "pinyol@2", "main": "main.lua"}))
(big / "main.lua").write_text('local sheets = require("sheets")\nfunction _init() show(0) end function _update() end\n'
                              'function _draw() cls(0) sheets.img("SPR_BIG", 0, 0, 3) sheets.img("SPR_BIG", 20, 0, 69) end\n'
                              'p_id, p_f = sheets.piece("SPR_BIG", 130)\n')
script = out / "bigsheet.script"
script.write_text("tick 2\nexpect_lua p_id == 'SPR_BIG_3' and p_f == 2\nexpect_lua select(3, imgsize('SPR_BIG_2')) == 6\nshot bigsheet\nexpect_ok\n")
r = subprocess.run([str(Path(sys.argv[1]) / "pinyol_headless"), "--game", str(big), "--saves", str(out / "big_saves"), "--fresh", "--script", str(script)],
                   capture_output=True, text=True)
assert "PASS" in r.stdout + r.stderr, (r.stdout + r.stderr)[-400:]
print("sheets: ok")

# look_check --play: the picture processor sampled while the game's script plays
pl = out / "playgame"
r = subprocess.run([sys.executable, str(ROOT / "tools/new_game.py"), str(pl), "--lua", "--look", "game boy"], capture_output=True, text=True)
assert r.returncode == 0, r.stderr
headless = Path(sys.argv[1]) / "pinyol_headless"
errs, seen = look_check.play(pl, looks.get("gameboy"), headless, None)
assert errs == [] and "sprites" in seen, (errs, seen)
(pl / "main.lua").write_text((pl / "main.lua").read_text() + '\nlocal base_draw = _draw\nfunction _draw()\n  base_draw()\n  local h = sheet("HERO")\n'
                             '  for i = 60, 105 do spr(i, h, 0, 10 + (i % 3), 20) end\nend\n')
errs, seen = look_check.play(pl, looks.get("gameboy"), headless, None)
assert any("sprites on the screen" in e for e in errs) and any("on one line" in e for e in errs), (errs, seen)
print("look_check --play: ok")

# sprite_kit + sprite_check: a sheet of three poses of one body, drawn at different sizes and places, comes out at one size, soles on the anchor's row, feet on its column
import sprite_check  # noqa: E402
import sprite_kit as K  # noqa: E402

def pose(w, h, body_h, dx=0, arm=0):
    im = Image.new("RGBA", (w, h), (0, 0, 0, 0))
    px = im.load()
    for y in range(h - body_h - 5, h - 5):          # a body 20 wide, standing 5 px above the cell's bottom
        for x in range(w // 2 - 10 + dx, w // 2 + 10 + dx):
            px[x, y] = (200, 60, 60, 255)
    for x in range(w // 2 + 10 + dx, w // 2 + 10 + dx + arm):  # an arm reaching out
        for y in range(h - body_h, h - body_h + 8):
            px[x, y] = (60, 60, 200, 255)
    return im

sheet = Image.new("RGBA", (300, 120), (0, 0, 0, 0))
for i, (bh, dx, arm) in enumerate(((80, 0, 0), (60, 5, 0), (90, -8, 30))):  # three poses of "the same" character, each drawn differently
    sheet.alpha_composite(pose(100, 120, bh, dx, arm), (i * 100, 0))
fitted = K.fit_sheet(K.key_background(sheet), 3, (160, 160), (80, 150), 0, 100)
for f in fitted:
    ys, xs = np.where(np.array(f.getchannel("A")) >= 128)
    assert ys.max() + 1 == 150, ys.max() + 1                       # the soles on the anchor's row
    body = np.array(f.getchannel("A"))[ys.max() - 10:ys.max() + 1] >= 128
    cx = (np.where(body.any(axis=0))[0].min() + np.where(body.any(axis=0))[0].max()) / 2
    assert abs(cx - 80) <= 1.5, cx                                 # the feet's middle on the anchor's column, not dragged by the arm
    assert xs.min() >= 0 and xs.max() < 160 and ys.min() >= 0       # inside its cell
strip, meta = K.build_character([(sheet, 3, ["a_0", "a_1", "a_2"], 0)], 100)
K.write_strip(out / "kit_art", "hero", strip, meta, alt=True)
errs, warns, _ = sprite_check.audit(out / "kit_art/hero.json")
assert errs == [], errs
assert (out / "kit_art/hero_b.png").exists() and meta["w"] % 8 == 0 and meta["h"] % 8 == 0 and 0 < meta["anchor"][1] < meta["h"], meta
# a frame cut by its cell is caught
cut = Image.new("RGBA", (200, 100), (0, 0, 0, 0))
cut.alpha_composite(pose(100, 100, 100, 40), (0, 0)); cut.alpha_composite(pose(100, 100, 60), (100, 0))
(out / "kit_art/bad.png").parent.mkdir(exist_ok=True)
cut.save(out / "kit_art/bad.png")
(out / "kit_art/bad.json").write_text(json.dumps({"w": 100, "h": 100, "anchor": [50, 95], "frames": ["idle_0", "idle_1"]}))
errs, _, _ = sprite_check.audit(out / "kit_art/bad.json")
assert any("clipped" in e for e in errs), errs
print("sprite_kit: ok")
