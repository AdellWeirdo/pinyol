#!/usr/bin/env python3
"""Playtest a finished game with bots: N perfect and N imperfect (human-like skill 0.1..0.9, and monkeys) games in the headless simulator,
and a report of crashes, softlocks, flashing, odd numbers, where players die and how hard the game is. See docs/playtest.md.

    uv run tools/playtest.py games/mygame                       # 50 perfect + 50 imperfect (40 human-like, 10 monkeys)
    uv run tools/playtest.py examples/pozo --perfect 10 --imperfect 10 --workers 2

The game may bring an adapter (games/<id>/tests/playtest.lua, or tests/playtest/<id>.lua for the examples) that tells the bot how the game
scores, ends and, best of all, how a perfect player plays. Without one the "perfect" player is a random explorer: it still finds crashes and
softlocks. Output (default ~/pinyol-playtests/<id>/): report.md, results.csv, logs/. Stdlib only. At most --workers (default 4) games run at once."""
import argparse, collections, concurrent.futures as cf, csv, os, re, statistics, subprocess, sys, time
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
HEADLESS = Path(os.environ.get("PINYOL_HEADLESS") or ROOT / "build" / "pinyol_headless")
BOT = ROOT / "tools" / "playtest_bot.lua"
BANDS = [(0.0, 0.3), (0.3, 0.5), (0.5, 0.7), (0.7, 1.01)]
RESULT = re.compile(r"PT_RESULT (.*)")


def adapter_for(game: Path):
    for p in (game / "tests" / "playtest.lua", ROOT / "tests" / "playtest" / f"{game.name}.lua"):
        if p.exists():
            return p
    return None


def make_jobs(n_perfect, n_imperfect, base_seed):
    jobs = [dict(id=f"P{i:02d}", mode="perfect", skill=1.0, seed=base_seed + i) for i in range(n_perfect)]
    n_monkey = n_imperfect // 5
    n_human = n_imperfect - n_monkey
    for i in range(n_human):
        jobs.append(dict(id=f"H{i:02d}", mode="human", skill=round(0.1 + 0.8 * i / max(1, n_human - 1), 3), seed=base_seed + 1000 + i))
    for i in range(n_monkey):
        jobs.append(dict(id=f"M{i:02d}", mode="monkey", skill=0.0, seed=base_seed + 2000 + i))
    return jobs


def script_for(job, game: Path, adapter, cap, work: Path):
    cfg = work / f"{job['id']}_cfg.lua"
    cfg.write_text('PT_CFG = {mode = "%s", seed = %d, skill = %s, cap = %d}\n' % (job["mode"], job["seed"], job["skill"], cap))
    empty = work / "empty.lua"
    empty.write_text("PLAYTEST = nil\n")
    lines = ["new", f"lua math.randomseed({job['seed']})", f"luafile {cfg}", f"luafile {adapter or empty}", f"luafile {BOT}"]
    for _ in range(cap // 600 + 2):
        lines += ["tick 600", "expect_lua not PT.done"]  # the bot says it is done: this "fails" on purpose and ends the run early
    sp = work / f"{job['id']}.script"
    sp.write_text("\n".join(lines) + "\n")
    return sp


def run_one(job, game, adapter, cap, out: Path, flash):
    work, logs = out / "work", out / "logs"
    saves = out / "saves" / job["id"]
    saves.mkdir(parents=True, exist_ok=True)
    sp = script_for(job, game, adapter, cap, work)
    cmd = [str(HEADLESS), "--game", str(game), "--fresh", "--saves", str(saves), "--script", str(sp)]
    if flash:
        cmd += ["--check-flashes", "--check-strips"]
    t0 = time.time()
    try:
        r = subprocess.run(cmd, cwd=ROOT, capture_output=True, text=True, timeout=max(120, cap / 60))
        text, code = r.stdout + r.stderr, r.returncode
    except subprocess.TimeoutExpired as e:
        text, code = (e.stdout or b"").decode(errors="replace") if isinstance(e.stdout, bytes) else (e.stdout or ""), -9
    (logs / f"{job['id']}.log").write_text(text)
    row = dict(job, flash=flash, exit=code, wall_s=round(time.time() - t0, 1), outcome="", ticks="", progress="", deaths="", where="", anomalies="", error="", flashes="")
    m = RESULT.search(text)
    if m:
        row.update(dict(kv.split("=", 1) for kv in m.group(1).split()))
    else:
        fail = next((l for l in text.splitlines() if l.startswith("FAIL")), "")
        row["outcome"] = "crash" if "expect_lua not PT.done" not in fail else "nodata"
        row["error"] = re.sub(r"^FAIL \S+:\d+: ", "", fail)[:300]
    if flash:
        row["flashes"] = "FLASH" if code == 4 else ("ok" if row["outcome"] != "crash" else "n/a")
    shutil_rm(saves)
    return row


def shutil_rm(p: Path):
    import shutil
    shutil.rmtree(p, ignore_errors=True)


def med(xs):
    xs = [float(x) for x in xs if str(x) not in ("", "-")]
    return int(statistics.median(xs)) if xs else "-"


def pct(a, b):
    return f"{a}/{b} ({100 * a // b}%)" if b else "-"


def report(rows, game, adapter, repeat_ok, cap):
    L = [f"# Playtest: {game.name}", "",
         f"{len(rows)} games, cap {cap} ticks ({cap // 3600} min of play). Adapter: {adapter if adapter else 'none (the perfect player is a random explorer, so its numbers say little about difficulty)'}.", ""]
    L += ["## By player", "", "| player | games | win | lose | timeout | stuck | giveup | crash | median ticks | median progress |", "|---|---|---|---|---|---|---|---|---|---|"]
    for mode in ("perfect", "human", "monkey"):
        rs = [r for r in rows if r["mode"] == mode]
        if not rs:
            continue
        c = collections.Counter(r["outcome"] for r in rs)
        L.append(f"| {mode} | {len(rs)} | {c['win']} | {c['lose']} | {c['timeout']} | {c['stuck']} | {c['giveup']} | {c['crash']} | {med(r['ticks'] for r in rs)} | {med(r['progress'] for r in rs)} |")
    hs = [r for r in rows if r["mode"] == "human"]
    if hs:
        L += ["", "## Human-like players by skill", "", "| skill | games | win | lose | timeout/giveup/stuck | median progress | median ticks |", "|---|---|---|---|---|---|---|"]
        for lo, hi in BANDS:
            rs = [r for r in hs if lo <= float(r["skill"]) < hi]
            if rs:
                c = collections.Counter(r["outcome"] for r in rs)
                L.append(f"| {lo:.1f}-{min(hi, 1):.1f} | {len(rs)} | {pct(c['win'], len(rs))} | {c['lose']} | {c['timeout'] + c['giveup'] + c['stuck']} | {med(r['progress'] for r in rs)} | {med(r['ticks'] for r in rs)} |")
        wr = [sum(r["outcome"] == "win" for r in hs if lo <= float(r["skill"]) < hi) / max(1, sum(lo <= float(r["skill"]) < hi for r in hs)) for lo, hi in BANDS]
        if any(b < a - 0.15 for a, b in zip(wr, wr[1:])):
            L.append("\nThe win rate does not rise with skill: something other than skill decides (luck, a spike, a bot limit).")
    L += ["", "## Where the games end badly", ""]
    bad = collections.Counter(r["where"] for r in rows if r["outcome"] in ("lose", "stuck", "giveup") and r["where"] not in ("", "-"))
    if bad:
        total = sum(bad.values())
        L += ["| where | games | share |", "|---|---|---|"] + [f"| {w} | {n} | {100 * n // total}% |" for w, n in bad.most_common(10)]
        w, n = bad.most_common(1)[0]
        if total >= 5 and n / total > 0.4:
            L.append(f"\n**{w}** takes {100 * n // total}% of the bad endings: a difficulty spike (or a softlock if they are `stuck`).")
    else:
        L.append("Nothing recorded (the adapter has no `where()`, or no game ended badly).")
    perfect = [r for r in rows if r["mode"] == "perfect"]
    if adapter and perfect:
        nw = sum(r["outcome"] in ("win", "timeout") for r in perfect)
        L += ["", "## Can a perfect player finish?", "", f"{pct(nw, len(perfect))} of the perfect games won or survived to the cap."]
        if nw < len(perfect):
            L.append("The rest `lose`, get `stuck` or crash: a game bug (unwinnable, unreachable, a hole), or the adapter's perfect player is not perfect. Check the logs and replay the seed.")
    L += ["", "## Problems", ""]
    crashes = collections.defaultdict(list)
    for r in rows:
        if r["outcome"] == "crash":
            crashes[r["error"]].append(r["id"])
    for e, ids in crashes.items():
        L.append(f"- **crash** ({len(ids)}x, e.g. {ids[0]}, seed {next(r['seed'] for r in rows if r['id'] == ids[0])}): `{e}`")
    stuck = [r for r in rows if r["outcome"] == "stuck"]
    if stuck:
        L.append(f"- **stuck** {len(stuck)}x (no progress for a minute): " + ", ".join(f"{r['id']} (seed {r['seed']}, {r['where']})" for r in stuck[:8]))
    an = collections.defaultdict(list)
    for r in rows:
        for a in r["anomalies"].split(","):
            if a not in ("", "-"):
                an[a.split("@")[0]].append(r["id"])
    for a, ids in an.items():
        L.append(f"- **anomaly** `{a}` in {len(ids)} games (e.g. {ids[0]})")
    fl = [r for r in rows if r["flashes"] == "FLASH"]
    chk = [r for r in rows if r["flashes"] in ("FLASH", "ok")]
    if fl:
        L.append(f"- **flashing** (more than 3 flashes a second over a quarter of the screen) in {len(fl)}/{len(chk)} checked games: " + ", ".join(f"{r['id']} (seed {r['seed']})" for r in fl[:8]))
    elif chk:
        L.append(f"- flashing: none in {len(chk)} checked games.")
    nodata = [r for r in rows if r["outcome"] == "nodata"]
    if nodata:
        L.append(f"- **no result** in {len(nodata)} games ({nodata[0]['id']}): the bot did not take over; the game may read its input some other way (see docs/playtest.md, `install`).")
    if not (crashes or stuck or an or fl or nodata):
        L.append("None found.")
    L += ["", f"Determinism: {'the same seed gave the same result in every repeated game' if repeat_ok else 'REPEATED GAMES DIFFERED: the game is not deterministic from its seed and input'}.", "",
          "Repeat a game: `uv run tools/playtest.py GAME --only ID` (the seeds are in results.csv). The bots are models: read the difficulty as relative, not as what people will feel."]
    return "\n".join(L) + "\n"


def main():
    ap = argparse.ArgumentParser(description=__doc__.split("\n\n")[0])
    ap.add_argument("game")
    ap.add_argument("--perfect", type=int, default=50)
    ap.add_argument("--imperfect", type=int, default=50)
    ap.add_argument("--workers", type=int, default=4)
    ap.add_argument("--cap", type=int, default=54000, help="ticks per game (60 a second)")
    ap.add_argument("--seed", type=int, default=100)
    ap.add_argument("--out", help="output folder (default ~/pinyol-playtests/<game>)")
    ap.add_argument("--only", help="run just this id (P03, H12, M01)")
    ap.add_argument("--flash-every", type=int, default=10, help="every Nth game also runs with --check-flashes (0: none)")
    a = ap.parse_args()
    game = Path(a.game).resolve()
    if not (game / "main.lua").exists():
        sys.exit(f"{game}: no main.lua")
    if not HEADLESS.exists():
        sys.exit(f"{HEADLESS} not built: cmake -B build && cmake --build build")
    out = Path(a.out).expanduser() if a.out else Path.home() / "pinyol-playtests" / game.name
    for d in ("work", "logs", "saves"):
        (out / d).mkdir(parents=True, exist_ok=True)
    adapter = adapter_for(game)
    jobs = make_jobs(a.perfect, a.imperfect, a.seed)
    if a.only:
        jobs = [j for j in jobs if j["id"] == a.only]
    for k, j in enumerate(jobs):
        j["flash"] = bool(a.flash_every) and k % a.flash_every == 0
    workers = max(1, min(a.workers, os.cpu_count() or 2))
    rows, t0 = [], time.time()
    with cf.ThreadPoolExecutor(max_workers=workers) as ex:
        futs = [ex.submit(run_one, j, game, adapter, a.cap, out, j["flash"]) for j in jobs]
        for k, f in enumerate(cf.as_completed(futs), 1):
            r = f.result()
            rows.append(r)
            print(f"[{k:3d}/{len(jobs)}] {r['id']} {r['mode']:7s} skill={r['skill']} -> {r['outcome']} ticks={r['ticks']} progress={r['progress']} ({r['wall_s']}s)", flush=True)
    rows.sort(key=lambda r: r["id"])
    # determinism: three games again, same seed, same result
    repeat_ok = True
    first = {r["id"]: r for r in rows}
    for j in [j for j in jobs if j["id"] in ([rows[0]["id"], rows[len(rows) // 2]["id"], rows[-1]["id"]] if rows else [])]:
        again = run_one(j, game, adapter, a.cap, out, False)
        if (again["outcome"], again["ticks"], again["progress"]) != (first[j["id"]]["outcome"], first[j["id"]]["ticks"], first[j["id"]]["progress"]):
            repeat_ok = False
    with open(out / "results.csv", "w", newline="") as f:
        w = csv.DictWriter(f, fieldnames=list(rows[0].keys()))
        w.writeheader()
        w.writerows(rows)
    (out / "report.md").write_text(report(rows, game, adapter, repeat_ok, a.cap))
    shutil_rm(out / "saves")
    print(f"done in {time.time() - t0:.0f}s: {out}/report.md")


if __name__ == "__main__":
    main()
