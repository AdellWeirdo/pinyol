"""Runs the image-model jobs of gen/gpt_jobs.py (the codex bridge) with tools/sheet_jobs.py: raw pictures in the game's raw/, nothing asked twice, a missing reference reported.

    python3 gen/gpt_run.py --plan                 # what would be asked (and what it costs)
    python3 gen/gpt_run.py                        # ask what is missing (the references first)
    python3 gen/gpt_run.py --only vera            # only Vera's pictures
    python3 gen/gpt_run.py --redo caldero_die.png # ask one again (the old one goes to raw/old/)
Needs the bridge ~/.claude/skills/gpt-image-bridge/bin/gpt-image-2 and a style reference picture raw/style_ref.png (a CPS2 sprite)."""
from __future__ import annotations

import os
import sys
from pathlib import Path

HERE = Path(__file__).resolve().parent
sys.path.insert(0, str(HERE))
sys.path.insert(0, str(HERE.parents[2] / "tools"))
import gpt_jobs as J  # noqa: E402
import sheet_jobs as SJ  # noqa: E402

RAW = Path(os.environ["TALLER_RAW"]) if os.environ.get("TALLER_RAW") else SJ.raw_dir(HERE.parent)


def style_ref() -> None:
    """The style reference (a CPS2 sprite, from the old fighting game torneo) if raw/ has none."""
    src = HERE.parents[2] / "tests/games/torneo/art/alba.png"
    if not (RAW / "style_ref.png").exists() and src.exists():
        from PIL import Image
        f = Image.open(src).convert("RGBA").crop((0, 0, 240, 176))
        bg = Image.new("RGBA", f.size, (150, 150, 160, 255))
        bg.alpha_composite(f)
        bg.resize((480, 352), Image.NEAREST).convert("RGB").save(RAW / "style_ref.png")


def jobs() -> list[SJ.Job]:
    style_ref()
    out = []
    for cid, c in J.CHARS.items():
        out.append(SJ.Job(c["ref"], RAW / f"{cid}_ref.png", RAW / "style_ref.png"))
        for name, n, desc, _, _ in c["sheets"]:
            out.append(SJ.Job(SJ.sheet(f"{n} frames of this character: {desc}. " + J.STYLE + " " + J.SHEET), RAW / f"{cid}_{name}.png", RAW / f"{cid}_ref.png"))
    for oid, o in J.OBJECTS.items():
        for name, n, desc, _ in o["sheets"]:
            out.append(SJ.Job(f"{desc}. " + J.STYLE + " " + J.OBJ, RAW / f"{oid}_{name}.png", RAW / "style_ref.png"))
    return out


if __name__ == "__main__":
    SJ.main(jobs(), int(os.environ.get("GPT_WORKERS", 5)))
