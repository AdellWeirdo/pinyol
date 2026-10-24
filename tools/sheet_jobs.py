# /// script
# requires-python = ">=3.10"
# dependencies = []
# ///
"""Running the image model's jobs for a game's sheets without losing or wasting them (the lessons of Paella and Taller). A library for a game's gen/gpt_run.py:

    import sheet_jobs as SJ
    jobs = [SJ.Job(prompt, raw / "vera_ref.png", style_ref), SJ.Job(sheet_prompt, raw / "vera_idle.png", raw / "vera_ref.png"), ...]
    SJ.main(jobs)            # --plan: what would be asked and what it costs; no flag: ask it; --only vera_: just those; --redo vera_air.png: ask that one again

  * **Raw pictures live in the game's `raw/`** (`raw_dir(game)`: made, and ignored by git), never in /tmp: the art can be fitted again whenever its rules change, without asking
    the image model again. Nothing is asked for twice: a picture that exists is kept.
  * **A reference first, and only if missing.** A sheet's reference is the canonical picture of its character; a job whose reference is neither there nor made by another job of
    the list is reported, not asked (it would come out with the style and the face drifted).
  * **`ONLY`**: every prompt for a sheet ends with the same sentence: only the character, every frame the same size, no smoke, dust, motion lines or sparks round it: effects are
    other pictures, drawn on purpose. `sheet(prompt)` adds it.
  * **One call is about 1% of a ChatGPT plan's five-hour window**: `--plan` says how many it would make.
"""
from __future__ import annotations

import argparse
import subprocess
import sys
import time
from concurrent.futures import ThreadPoolExecutor
from dataclasses import dataclass
from pathlib import Path

BRIDGE = Path.home() / ".claude/skills/gpt-image-bridge/bin/gpt-image-2"
MIN_BYTES = 10_000  # a smaller file is an error, not a picture
ONLY = (" Draw ONLY the character, every frame at exactly the SAME size and scale as the reference, standing on the same ground line; NO smoke or steam clouds, NO dust, "
        "NO motion lines, NO swoosh, NO shock rings, NO sparks or stars around it.")


@dataclass(frozen=True)
class Job:
    prompt: str
    out: Path
    ref: Path | None = None


def sheet(prompt: str) -> str:
    """A sheet's prompt with the sentence that keeps effects out of it."""
    return prompt.rstrip() + ONLY


def raw_dir(game: Path) -> Path:
    """GAME/raw, made, and listed in GAME/.gitignore so the (big) pictures stay out of the repository."""
    raw = game / "raw"
    raw.mkdir(parents=True, exist_ok=True)
    ign = game / ".gitignore"
    have = ign.read_text().splitlines() if ign.exists() else []
    if "raw/" not in have:
        ign.write_text("\n".join(have + ["raw/"]) + "\n")
    return raw


def done(p: Path) -> bool:
    return p.exists() and p.stat().st_size > MIN_BYTES


def plan(jobs: list[Job]) -> tuple[list[Job], list[Job]]:
    """(the jobs to ask, the jobs that cannot be: their reference is not there and nothing in the list makes it)."""
    made = {j.out for j in jobs}
    todo, blocked = [], []
    for j in jobs:
        if done(j.out):
            continue
        if j.ref is not None and not done(j.ref) and j.ref not in made:
            blocked.append(j)
        else:
            todo.append(j)
    return todo, blocked


def ask(job: Job, tries: int = 2) -> bool:
    if done(job.out):
        return True
    job.out.parent.mkdir(parents=True, exist_ok=True)
    for _ in range(tries):
        cmd = [str(BRIDGE), job.prompt, str(job.out)] + (["--ref", str(job.ref)] if job.ref else [])
        r = subprocess.run(cmd, capture_output=True, text=True, timeout=1500)
        if done(job.out):
            print("ok", job.out.name, flush=True)
            return True
        print("FAILED", job.out.name, r.stderr[-200:], flush=True)
        time.sleep(5)
    return False


def run(jobs: list[Job], workers: int = 5) -> int:
    """Asks what is missing: first the references that other jobs need, then the rest, `workers` at a time. Returns how many failed."""
    todo, blocked = plan(jobs)
    for j in blocked:
        print(f"SKIPPED {j.out.name}: its reference {j.ref} is missing and nothing makes it", file=sys.stderr)
    refs = {j.ref for j in jobs if j.ref}
    first = [j for j in todo if j.out in refs]
    rest = [j for j in todo if j.out not in refs]
    bad = 0
    with ThreadPoolExecutor(workers) as ex:
        for batch in (first, rest):
            bad += sum(not ok for ok in ex.map(ask, batch))
    print(f"{len(todo) - bad}/{len(todo)} made, {len(blocked)} skipped")
    return bad


def main(jobs: list[Job], workers: int = 5, argv: list[str] | None = None) -> None:
    ap = argparse.ArgumentParser(description=__doc__.split("\n\n")[0])
    ap.add_argument("--plan", action="store_true", help="say what would be asked and how much it costs; ask nothing")
    ap.add_argument("--only", nargs="+", metavar="TEXT", help="only jobs whose picture's name contains one of these")
    ap.add_argument("--redo", nargs="+", metavar="FILE", help="ask these pictures again (their file names): the old ones are moved to raw/old/")
    a = ap.parse_args(argv)
    if a.redo:
        for name in a.redo:
            for j in jobs:
                if j.out.name == name and j.out.exists():
                    old = j.out.parent / "old"
                    old.mkdir(exist_ok=True)
                    j.out.rename(old / f"{int(time.time())}_{name}")
    if a.only:
        wanted = [j for j in jobs if any(t in j.out.name for t in a.only)]
        needed = {j.ref for j in wanted if j.ref}  # a reference that the chosen ones need comes with them
        jobs = wanted + [j for j in jobs if j.out in needed and j not in wanted]
    todo, blocked = plan(jobs)
    if a.plan:
        for j in todo:
            print("ask    ", j.out.name)
        for j in blocked:
            print("blocked", j.out.name, "(reference missing:", j.ref.name + ")")
        print(f"{len(todo)} calls (about {len(todo)}% of a five-hour window), {len(blocked)} blocked, {sum(done(j.out) for j in jobs)} already there")
        return
    sys.exit(1 if run(jobs, workers) else 0)
