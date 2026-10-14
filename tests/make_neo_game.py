"""Makes the game tests/neo.script plays, and the console's benchmark of it: a fighting-game scene at the screen's full
480x320, as a Neo Geo game draws it, with examples/duelo's pictures: the stage's two layers and two fighters of
eleven 192x184 frames, converted with tools/png2asset.py and the options given (plain pictures, or packed ones).

    python3 tests/make_neo_game.py OUT_DIR [png2asset options, e.g. --packed]
"""
import json
import shutil
import subprocess
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
ART = ROOT / "examples" / "duelo" / "art"
out = Path(sys.argv[1])
extra = sys.argv[2:]
shutil.rmtree(out, ignore_errors=True)
(out / "assets").mkdir(parents=True)
shutil.copytree(ROOT / "examples" / "naves" / "fonts", out / "fonts")

for png, aid, *opts in (("stage_far", "BG_FAR", "--type", "background"), ("stage_near", "BG_NEAR", "--type", "background"),
                        ("kai", "SPR_F1", "--frames", "11"), ("ran", "SPR_F2", "--frames", "11")):
    subprocess.run([sys.executable, str(ROOT / "tools" / "png2asset.py"), str(ART / f"{png}.png"), str(out / "assets"),
                    aid, *opts, *extra], check=True, stdout=subprocess.DEVNULL)

(out / "game.json").write_text(json.dumps({"id": "neo", "title": "Neo", "engine": "pinyol@2", "main": "main.lua"}))
shutil.copy(ROOT / "tests" / "games" / "neo.lua", out / "main.lua")
print("neo game in", out)
