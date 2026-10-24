"""Runs the image-model jobs of gen/gpt_jobs.py in parallel (the codex bridge), skipping what already exists.

    python3 gen/gpt_run.py refs [id ..]
    python3 gen/gpt_run.py sheets char [id ..]
    python3 gen/gpt_run.py sheets obj [id ..]
Needs the bridge ~/.claude/skills/gpt-image-bridge/bin/gpt-image-2 and a style reference RAW/style_ref.png (a CPS2 sprite)."""
from __future__ import annotations

import os
import subprocess
import sys
import time
from concurrent.futures import ThreadPoolExecutor
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent))
import gpt_jobs as J  # noqa: E402

RAW = Path(os.environ.get("TALLER_RAW", "/private/tmp/claude-501/-Users-pauavila-Desktop-DEV-pinyol/0c2c8ddb-2909-4ab2-9a6a-d16056eabb26/scratchpad/taller/gpt"))
BRIDGE = Path.home() / ".claude/skills/gpt-image-bridge/bin/gpt-image-2"
WORKERS = int(os.environ.get("GPT_WORKERS", 5))


def ask(prompt: str, out: Path, ref: Path) -> bool:
    if out.exists() and out.stat().st_size > 10_000:
        return True
    for _ in range(2):
        r = subprocess.run([str(BRIDGE), prompt, str(out), "--ref", str(ref)], capture_output=True, text=True, timeout=1500)
        if out.exists() and out.stat().st_size > 10_000:
            print("ok", out.name, flush=True)
            return True
        print("FAILED", out.name, r.stderr[-300:], flush=True)
        time.sleep(5)
    return False


def main() -> None:
    what, jobs = sys.argv[1], []
    if what == "refs":
        for cid in sys.argv[2:] or list(J.CHARS):
            jobs.append((J.CHARS[cid]["ref"], RAW / f"{cid}_ref.png", RAW / "style_ref.png"))
    elif what == "sheets" and sys.argv[2] == "char":
        for cid in sys.argv[3:] or list(J.CHARS):
            for name, n, desc, _, _ in J.CHARS[cid]["sheets"]:
                jobs.append((f"{n} frames of this character: {desc}. " + J.STYLE + " " + J.SHEET, RAW / f"{cid}_{name}.png", RAW / f"{cid}_ref.png"))
    elif what == "sheets" and sys.argv[2] == "obj":
        for oid in sys.argv[3:] or list(J.OBJECTS):
            for name, n, desc, _ in J.OBJECTS[oid]["sheets"]:
                jobs.append((f"{desc}. " + J.STYLE + " " + J.OBJ, RAW / f"{oid}_{name}.png", RAW / "style_ref.png"))
    with ThreadPoolExecutor(WORKERS) as ex:
        results = list(ex.map(lambda j: ask(*j), jobs))
    print(f"{sum(results)}/{len(results)} done")


if __name__ == "__main__":
    main()
