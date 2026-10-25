"""The quality gate: a game whose adapter says `-- playtest-gate: win` (or `survive`) in its first lines must be finished (or survived to the cap) by its perfect player.
A game that cannot be finished passes every other test as long as the tests teleport or set flags: four of the engine's examples were like that.
Run: python3 tests/playtest_gate.py [build dir]   (ctest runs it). Env PINYOL_HEADLESS names another pinyol_headless."""
import csv, os, re, subprocess, sys, tempfile
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
build = Path(sys.argv[1]) if len(sys.argv) > 1 else ROOT / "build"
env = dict(os.environ, PINYOL_HEADLESS=os.environ.get("PINYOL_HEADLESS") or str(build / "pinyol_headless"))
CAP = {"win": 54000, "survive": 12000}
bad, ran = [], 0
for adapter in sorted((ROOT / "tests" / "playtest").glob("*.lua")):
    m = re.search(r"playtest-gate:\s*(win|survive)", "".join(adapter.read_text().splitlines(True)[:5]))
    if not m:
        continue
    game = next((g for g in (ROOT / "examples" / adapter.stem, ROOT / "tests" / "games" / adapter.stem) if (g / "main.lua").exists()), None)
    if not game:
        bad.append(f"{adapter.name}: no game {adapter.stem}")
        continue
    want = m.group(1)
    with tempfile.TemporaryDirectory() as out:
        r = subprocess.run([sys.executable, str(ROOT / "tools" / "playtest.py"), str(game), "--perfect", "1", "--imperfect", "0", "--cap", str(CAP[want]), "--flash-every", "0", "--out", out],
                           cwd=ROOT, env=env, capture_output=True, text=True)
        rows = list(csv.DictReader(open(Path(out, "results.csv")))) if Path(out, "results.csv").exists() else []
        outcome = rows[0]["outcome"] if rows else "no result"
        if not rows:
            print(r.stdout + r.stderr)
    ok = outcome == "win" if want == "win" else outcome in ("win", "timeout")
    ran += 1
    print(f"{adapter.stem}: perfect player {outcome} (wanted {want}) {'ok' if ok else 'FAIL'}")
    if not ok:
        bad.append(f"{adapter.stem}: the perfect player ended with {outcome}, wanted {want}")
if bad:
    sys.exit("playtest gate failed:\n  " + "\n  ".join(bad))
print(f"playtest gate ok ({ran} games)")
