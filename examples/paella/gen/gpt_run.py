"""Runs the image-model jobs of gen/gpt_jobs.py (the codex bridge) with tools/sheet_jobs.py: raw pictures in the game's raw/, nothing asked twice, a missing reference reported.

    python3 gen/gpt_run.py --plan                  # what would be asked (and what it costs)
    python3 gen/gpt_run.py --only grandma tractor  # just those (their reference comes with them)
    python3 gen/gpt_run.py --redo grandma_free.png # ask one again (the old one goes to raw/old/)
Needs the bridge and a style reference picture raw/style_ref.png (a crop of one of the backgrounds)."""
from __future__ import annotations

import os
import sys
from pathlib import Path

HERE = Path(__file__).resolve().parent
sys.path.insert(0, str(HERE))
sys.path.insert(0, str(HERE.parents[2] / "tools"))
import gpt_jobs as J  # noqa: E402
import sheet_jobs as SJ  # noqa: E402

RAW = Path(os.environ["PAELLA_RAW"]) if os.environ.get("PAELLA_RAW") else SJ.raw_dir(HERE.parent)


def style_ref() -> None:
    """The style reference (a crop of a background) if raw/ has none."""
    src = HERE.parent / "art/near_calle_a.png"
    if not (RAW / "style_ref.png").exists() and src.exists():
        from PIL import Image
        Image.open(src).convert("RGB").crop((0, 20, 480, 300)).save(RAW / "style_ref.png")


def jobs() -> list[SJ.Job]:
    style_ref()
    out = []
    style = RAW / "style_ref.png"
    for chef, c in J.CHEFS.items():
        if c["ref"]:
            out.append(SJ.Job(J.ref_prompt(chef), RAW / f"{chef}_ref.png", style))
        for sheet in J.SHEETS:
            out.append(SJ.Job(SJ.sheet(J.sheet_prompt(chef, sheet)), RAW / f"{chef}_{sheet}.png", RAW / f"{chef}_ref.png"))
    for eid, e in list(J.ENEMIES.items()) + [("tractor", J.TRACTOR)]:
        if e["ref"]:
            out.append(SJ.Job(e["ref"] if e["ref"].rstrip().endswith(J.FLAT) else e["ref"] + J.STYLE + " " + J.FLAT, RAW / f"{eid}_ref.png", style))
        tail = J.LEFT if e["faces"] == "left" else J.SHEET
        for sh in e["sheets"]:
            out.append(SJ.Job(SJ.sheet(f"{sh[1]} frames of this character: {sh[2]}. " + J.STYLE + " " + tail), RAW / f"{eid}_{sh[0]}.png", RAW / f"{eid}_ref.png"))
    for oid, o in J.OBJECTS.items():
        for sh in o["sheets"]:
            out.append(SJ.Job(f"{sh[2]}. " + J.STYLE + " " + J.OBJ, RAW / f"{oid}_{sh[0]}.png", RAW / "soldier_ref.png"))
    return out


if __name__ == "__main__":
    SJ.main(jobs(), int(os.environ.get("GPT_WORKERS", 5)))
