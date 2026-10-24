"""tools/playtest.py plays malabar with its adapter: the perfect player survives to the cap, nobody crashes, the report is written.
Run: python3 tests/playtest_test.py (needs build/pinyol_headless)"""
import subprocess, sys, tempfile
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
with tempfile.TemporaryDirectory() as out:
    r = subprocess.run([sys.executable, str(ROOT / "tools" / "playtest.py"), "examples/malabar", "--perfect", "3", "--imperfect", "5", "--cap", "6000", "--workers", "2", "--out", out],
                       cwd=ROOT, capture_output=True, text=True)
    assert r.returncode == 0, r.stdout + r.stderr
    rep = (Path(out) / "report.md").read_text()
    assert "| perfect | 3 | 0 | 0 | 3 |" in rep, rep  # 3 games, all timeout (survived the cap)
    assert "crash** " not in rep and "REPEATED GAMES DIFFERED" not in rep, rep
print("playtest ok")
