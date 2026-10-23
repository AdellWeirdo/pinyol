"""Runs the image-model jobs of gen/gpt_jobs.py in parallel (the codex bridge), skipping what already exists.

    python3 gen/gpt_run.py refs
    python3 gen/gpt_run.py sheets chef [chef_id ...]
Needs the bridge ~/.claude/skills/gpt-image-bridge/bin/gpt-image-2 and a style reference picture RAW/style_ref.png."""
from __future__ import annotations

import os
import subprocess
import sys
import time
from concurrent.futures import ThreadPoolExecutor
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent))
import gpt_jobs as J  # noqa: E402

RAW = Path(os.environ.get("PAELLA_RAW", "/private/tmp/claude-501/-Users-pauavila-Desktop-DEV-pinyol/0c2c8ddb-2909-4ab2-9a6a-d16056eabb26/scratchpad/paella/gpt"))
BRIDGE = Path.home() / ".claude/skills/gpt-image-bridge/bin/gpt-image-2"
WORKERS = int(os.environ.get('GPT_WORKERS', 5))


def ask(prompt: str, out: Path, ref: Path) -> bool:
    if out.exists() and out.stat().st_size > 10_000:
        return True
    for attempt in range(2):
        r = subprocess.run([str(BRIDGE), prompt, str(out), "--ref", str(ref)], capture_output=True, text=True, timeout=1500)
        if out.exists() and out.stat().st_size > 10_000:
            print("ok", out.name, flush=True)
            return True
        print("FAILED", out.name, r.stderr[-300:], flush=True)
        time.sleep(5)
    return False


def enemy_sheet_prompt(eid: str, sheet) -> str:
    _, n, what, _, _ = sheet
    e = J.ENEMIES.get(eid) or J.TRACTOR
    tail = J.LEFT if e["faces"] == "left" else J.SHEET
    return f"{n} frames of this character: {what}. " + J.STYLE + " " + tail


def object_sheet_prompt(sheet) -> str:
    _, n, what, _ = sheet
    return f"{what}. " + J.STYLE + " " + J.OBJ


def main() -> None:
    what = sys.argv[1]
    jobs = []
    if what == "refs":
        kind = sys.argv[2] if len(sys.argv) > 2 else "chef"
        if kind == "chef":
            for chef in J.CHEFS:
                if J.CHEFS[chef]["ref"]:
                    jobs.append((J.ref_prompt(chef), RAW / f"{chef}_ref.png", RAW / "style_ref.png"))
        else:
            for eid, e in list(J.ENEMIES.items()) + [("tractor", J.TRACTOR)]:
                if e["ref"]:
                    jobs.append((e["ref"] if e["ref"].rstrip().endswith(J.FLAT) else e["ref"] + J.STYLE + " " + J.FLAT, RAW / f"{eid}_ref.png", RAW / "style_ref.png"))
    elif what == "sheets":
        kind = sys.argv[2]
        ids = sys.argv[3:]
        if kind == "chef":
            for chef in ids or list(J.CHEFS):
                for sheet in J.SHEETS:
                    jobs.append((J.sheet_prompt(chef, sheet), RAW / f"{chef}_{sheet}.png", RAW / f"{chef}_ref.png"))
        elif kind == "enemy":
            for eid in ids or list(J.ENEMIES):
                for sh in J.ENEMIES[eid]["sheets"]:
                    jobs.append((enemy_sheet_prompt(eid, sh), RAW / f"{eid}_{sh[0]}.png", RAW / f"{eid}_ref.png"))
        elif kind == "tractor":
            for sh in J.TRACTOR["sheets"]:
                jobs.append((enemy_sheet_prompt("tractor", sh), RAW / f"tractor_{sh[0]}.png", RAW / "tractor_ref.png"))
        elif kind == "obj":
            for oid in ids or list(J.OBJECTS):
                for sh in J.OBJECTS[oid]["sheets"]:
                    jobs.append((object_sheet_prompt(sh), RAW / f"{oid}_{sh[0]}.png", RAW / "soldier_ref.png"))
    with ThreadPoolExecutor(WORKERS) as ex:
        results = list(ex.map(lambda j: ask(*j), jobs))
    print(f"{sum(results)}/{len(results)} done")


if __name__ == "__main__":
    main()
