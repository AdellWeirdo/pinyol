"""Missing art fails headless checks only when strict asset checking is requested."""
import json
import shutil
import subprocess
import sys
import tempfile
from pathlib import Path

headless = Path(sys.argv[1])
source = Path(__file__).resolve().parent.parent / "examples" / "psx_views" / "fonts"

with tempfile.TemporaryDirectory() as tmp:
    game = Path(tmp) / "game"
    game.mkdir()
    shutil.copytree(source, game / "fonts")
    (game / "game.json").write_text(json.dumps({"id": "strict_art", "title": "Strict art",
                                                  "engine": "pinyol@2", "main": "main.lua"}))
    script = Path(tmp) / "play.script"
    script.write_text("tick 2\nexpect_ok\n")

    def check(lua, args, expected, message=""):
        (game / "main.lua").write_text(lua)
        run = subprocess.run([str(headless), "--game", str(game), "--saves", str(Path(tmp) / "saves"),
                              *args], capture_output=True, text=True)
        output = run.stdout + run.stderr
        assert (run.returncode == 0) == expected, output
        if not expected:
            assert "asset check: required picture" in output, output
        if message:
            assert message in output, output

    check("function _init() end\nfunction _draw() cls(0) end\n", ["--strict-assets", "--validate"], True)
    check("function _init() img('GONE_INIT', 10, 10) end\nfunction _draw() end\n",
          ["--strict-assets", "--validate"], False, "GONE_INIT")
    check("function _init() end\nfunction _draw() img('GONE_DRAW', 10, 10) end\n",
          ["--validate"], True)
    check("function _init() end\nfunction _draw() img('GONE_DRAW', 10, 10) end\n",
          ["--strict-assets", "--validate"], False, "GONE_DRAW")
    check("n = 0\nfunction _init() end\nfunction _update() n = n + 1 end\n"
          "function _draw() if n > 1 then img('GONE_SCRIPT', 10, 10) end end\n",
          ["--strict-assets", "--script", str(script)], False, "GONE_SCRIPT")
    assets = game / "assets"
    assets.mkdir()
    (assets / "BROKEN.meta.json").write_text('{"w":2,"h":2,"frames":1}')
    (assets / "BROKEN.rgb565").write_bytes(b"bad")
    check("function _init() end\nfunction _draw() img('BROKEN', 10, 10) end\n",
          ["--strict-assets", "--validate"], False, "BROKEN")
    (assets / "BAD_MASK.meta.json").write_text('{"w":2,"h":2,"frames":1}')
    (assets / "BAD_MASK.rgb565").write_bytes(b"\x00" * 8)
    (assets / "BAD_MASK.mask").write_bytes(b"bad")
    check("function _init() end\nfunction _draw() img('BAD_MASK', 10, 10) end\n",
          ["--strict-assets", "--validate"], False, "BAD_MASK")
    # a picture gfx.c refuses (65 frames: 64 at most) fails --validate even when nothing draws it yet, saying why;
    # a PPU tilemap's meta, another loader's, is not read as a picture
    (assets / "TOO_MANY.meta.json").write_text('{"w":2,"h":2,"frames":65,"format":"packed"}')
    (game / "main.lua").write_text("function _init() end\nfunction _draw() end\n")
    run = subprocess.run([str(headless), "--game", str(game), "--saves", str(Path(tmp) / "saves"), "--validate"],
                         capture_output=True, text=True)
    assert run.returncode != 0 and "TOO_MANY.meta.json: 2x2, 65 frame(s)" in run.stdout + run.stderr, run.stdout + run.stderr
    (assets / "TOO_MANY.meta.json").unlink()
    (assets / "MAP.meta.json").write_text('{"type":"tilemap","tiles":4,"map_w":30,"map_h":20,"palette":"WORLD"}')
    check("function _init() end\nfunction _draw() end\n", ["--validate"], True)
    (assets / "MAP.meta.json").unlink()
    script.write_text("tick 1\nexpect_ok\n")
    check("draws = 0\nfunction _init() end\nfunction _draw() draws = draws + 1; "
          "if draws > 1 then error('drawn twice') end end\n",
          ["--strict-assets", "--script", str(script)], True)
    legacy = Path(tmp) / "legacy"
    shutil.copytree(source.parent.parent / "hola", legacy, ignore=shutil.ignore_patterns("saves"))
    (legacy / "assets" / "LOGO.meta.json").unlink()  # title falls back to text
    run = subprocess.run([str(headless), "--game", str(legacy), "--saves", str(Path(tmp) / "saves"),
                          "--strict-assets", "--validate"], capture_output=True, text=True)
    assert run.returncode == 0, run.stdout + run.stderr
