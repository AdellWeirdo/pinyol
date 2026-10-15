"""stats.json: each game's numbers for the site, the ranking and the cover of the week. Run once a day by
.github/workflows/stats.yml, which publishes it on the branch "stats"; the site reads it from there (site/src/games.js).

    GITHUB_TOKEN=... [GOATCOUNTER_TOKEN=...] python3 tools/stats.py stats.json --previous old.json
    python3 tools/stats.py --test

- likes and comments: the GitHub Discussion giscus keeps for each game (category "Juegos", titled with its id): its
  reactions but 👎 and 😕, and its comments with their replies.
- visits, plays and minutes played, when there is a GoatCounter token: the visitors of the game's page in the three
  languages, its "partida/<id>" events (a game started in the web player) and its "tiempo/<id>/<m>" ones (play passed m
  minutes). GoatCounter counts people, so the minutes come as milestones: the time is what each step adds, times the
  people who got there, a little under the real time.
- the cover of the week, chosen the first time the job runs in a new week (ISO, Monday): the most voted that week (the
  likes added since the week before), or else the one most commented, or else one at random (seeded by the week) of
  those not shown in the last 8 weeks.
"""
from __future__ import annotations

import argparse
import datetime as dt
import json
import os
import random
import sys
import urllib.parse
import urllib.request
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
REPO = os.environ.get("GITHUB_REPOSITORY", "ipaud/pinyol")
CATEGORY = "Juegos"
COUNTER = "https://pinyol.goatcounter.com"
SITE_PATH = "/pinyol/"
MILESTONES = [1, 2, 3, 5, 10, 15, 20, 30, 45, 60, 90, 120]  # platform/web/player.html sends the same
NOT_LIKES = {"THUMBS_DOWN", "CONFUSED"}
FRESH = 8  # weeks a game waits before it can be the random cover again


def game_ids() -> list[str]:
    ids = sorted(p.parent.name for p in (ROOT / "examples").glob("*/game.json"))
    ids += [g["id"] for g in json.loads((ROOT / "library/library.json").read_text(encoding="utf-8"))]
    return ids


def _get(url: str, token: str, body: dict | None = None) -> dict:
    req = urllib.request.Request(url, data=json.dumps(body).encode() if body else None,
                                 headers={"Authorization": f"Bearer {token}", "Content-Type": "application/json",
                                          "User-Agent": "pinyol-stats"})
    with urllib.request.urlopen(req, timeout=60) as r:
        return json.load(r)


def discussions(token: str) -> dict[str, dict]:
    """{game id: {likes, reactions, comments, url}} from the category's Discussions (none if it does not exist yet)."""
    owner, name = REPO.split("/")
    query = """query($owner: String!, $name: String!, $after: String) { repository(owner: $owner, name: $name) {
      discussions(first: 100, after: $after) { pageInfo { hasNextPage endCursor } nodes {
        title url category { name } comments(first: 100) { totalCount nodes { replies { totalCount } } }
        reactionGroups { content reactors { totalCount } } } } } }"""
    out, after = {}, None
    while True:
        data = _get("https://api.github.com/graphql", token,
                    {"query": query, "variables": {"owner": owner, "name": name, "after": after}})
        if data.get("errors"):
            raise SystemExit(f"GitHub: {data['errors']}")
        repo = data["data"]["repository"]
        for d in repo["discussions"]["nodes"]:
            if d["category"]["name"] != CATEGORY:
                continue
            reactions = {g["content"]: g["reactors"]["totalCount"] for g in d["reactionGroups"] if g["reactors"]["totalCount"]}
            # (the replies of a thread's first 100 comments: past that, a few go uncounted)
            comments = d["comments"]["totalCount"] + sum(c["replies"]["totalCount"] for c in d["comments"]["nodes"])
            likes = sum(n for k, n in reactions.items() if k not in NOT_LIKES)
            was = out.get(d["title"].strip())  # two Discussions with one title (anyone may start one): both count
            if was:
                reactions = {k: reactions.get(k, 0) + was["reactions"].get(k, 0) for k in {*reactions, *was["reactions"]}}
                likes, comments = likes + was["likes"], comments + was["comments"]
            out[d["title"].strip()] = {"likes": likes, "reactions": reactions, "comments": comments,
                                       "url": was["url"] if was else d["url"]}
        page = repo["discussions"]["pageInfo"]
        if not page["hasNextPage"]:
            return out
        after = page["endCursor"]


def goatcounter(token: str, since: str) -> dict[str, int] | None:
    """{path or event name: visitors} since the day given; None if GoatCounter can't be read today (the rest goes on)."""
    try:
        return _goatcounter(token, since)
    except (OSError, ValueError, KeyError) as e:  # (urllib's errors are OSErrors)
        print(f"GoatCounter: {e}; visits, plays and time left out today", file=sys.stderr)
        return None


def _goatcounter(token: str, since: str) -> dict[str, int]:
    out, exclude = {}, []
    while True:
        q = urllib.parse.urlencode({"start": f"{since}T00:00:00Z", "limit": 100,  # (the API's most)
                                    **({"exclude_paths": ",".join(exclude)} if exclude else {})})
        data = _get(f"{COUNTER}/api/v0/stats/hits?{q}", token)
        for h in data.get("hits", []):
            out[h["path"]] = out.get(h["path"], 0) + h["count"]
            exclude.append(str(h["path_id"]))
        if not data.get("more"):
            return out


def minutes(reached: dict[int, int]) -> int:
    """Minutes played from how many people reached each milestone: each step's minutes times who got that far."""
    total, before = 0, 0
    for m in MILESTONES:
        total += reached.get(m, 0) * (m - before)
        before = m
    return total


def counts(hits: dict[str, int], gid: str) -> dict:
    visits = sum(hits.get(f"{SITE_PATH}{lang}juegos/{gid}/", 0) for lang in ("", "ca/", "en/"))
    reached = {m: hits.get(f"tiempo/{gid}/{m}", 0) for m in MILESTONES}
    return {"visits": visits, "plays": hits.get(f"partida/{gid}", 0), "minutes": minutes(reached)}


def week_of(day: dt.date) -> str:
    y, w, _ = day.isocalendar()
    return f"{y}-W{w:02d}"


def choose(ids: list[str], games: dict, prev: dict, week: str) -> tuple[dict, dict, list]:
    """The cover of the week, the week's starting numbers and the covers so far; kept as they were within a week."""
    if prev.get("featured", {}).get("week") == week and prev["featured"].get("id") in ids:
        return prev["featured"], prev.get("week_start", {}), prev.get("history", [])
    start = prev.get("week_start", {})
    gained = lambda gid, k: games[gid][k] - start.get(gid, {}).get(k, 0)
    plays = lambda gid: games[gid].get("plays") or 0
    best = lambda k: max(ids, key=lambda gid: (gained(gid, k), plays(gid), gid))
    if gained(best("likes"), "likes") > 0:
        gid, reason = best("likes"), "votes"
    elif gained(best("comments"), "comments") > 0:
        gid, reason = best("comments"), "comments"
    else:
        recent = {h["id"] for h in prev.get("history", [])[-FRESH:]}
        gid, reason = random.Random(week).choice([i for i in ids if i not in recent] or ids), "random"
    featured = {"id": gid, "reason": reason, "week": week}
    snapshot = {i: {"likes": games[i]["likes"], "comments": games[i]["comments"]} for i in ids}
    return featured, snapshot, (prev.get("history", []) + [featured])[-52:]


def build(ids: list[str], talk: dict, hits: dict | None, prev: dict, today: dt.date, now: str) -> dict:
    games = {}
    for gid in ids:
        t = talk.get(gid, {})
        games[gid] = {"likes": t.get("likes", 0), "comments": t.get("comments", 0), "reactions": t.get("reactions", {}),
                      "url": t.get("url"), **(counts(hits, gid) if hits is not None else
                                             {"visits": None, "plays": None, "minutes": None})}
    ranking = sorted(ids, key=lambda g: (-games[g]["likes"], -games[g]["comments"], -(games[g]["plays"] or 0), g))
    featured, start, history = choose(ids, games, prev, week_of(today))
    return {"updated": now, "week": week_of(today), "featured": featured, "history": history, "week_start": start,
            "ranking": ranking, "games": games}


def test() -> None:
    assert minutes({1: 10, 2: 6, 3: 5, 5: 2}) == 10 * 1 + 6 * 1 + 5 * 1 + 2 * 2
    assert minutes({}) == 0
    hits = {"/pinyol/juegos/a/": 3, "/pinyol/ca/juegos/a/": 2, "partida/a": 4, "tiempo/a/1": 4, "tiempo/a/2": 1}
    assert counts(hits, "a") == {"visits": 5, "plays": 4, "minutes": 5}
    ids = ["a", "b", "c"]
    day = dt.date(2026, 10, 19)  # a Monday: week 43
    first = build(ids, {}, None, {}, day, "now")
    assert first["featured"]["reason"] == "random" and first["featured"]["week"] == "2026-W43"
    assert first["games"]["a"]["visits"] is None and first["ranking"] == ["a", "b", "c"]
    talk = {"b": {"likes": 3, "comments": 1, "reactions": {"HEART": 2, "THUMBS_UP": 1}}, "c": {"likes": 1, "comments": 5}}
    same_week = build(ids, talk, None, first, day + dt.timedelta(days=3), "now")
    assert same_week["featured"] == first["featured"]                  # chosen once a week
    assert same_week["ranking"][:2] == ["b", "c"]
    next_week = build(ids, talk, None, same_week, day + dt.timedelta(days=7), "now")
    assert next_week["featured"]["id"] == "b" and next_week["featured"]["reason"] == "votes"
    quiet = build(ids, talk, None, next_week, day + dt.timedelta(days=14), "now")  # nothing new: at random, b skipped
    assert quiet["featured"]["reason"] == "random" and quiet["featured"]["id"] != "b"
    talk2 = {**talk, "a": {"likes": 0, "comments": 2}}
    talked = build(ids, talk2, None, quiet, day + dt.timedelta(days=21), "now")
    assert talked["featured"] == {"id": "a", "reason": "comments", "week": "2026-W46"}
    print("stats: ok")


def main() -> None:
    ap = argparse.ArgumentParser(description=__doc__.split("\n")[0])
    ap.add_argument("out", type=Path, nargs="?")
    ap.add_argument("--previous", type=Path, help="yesterday's stats.json (the cover of the week and its week's start)")
    ap.add_argument("--since", default="2026-10-01", help="GoatCounter's first day")
    ap.add_argument("--test", action="store_true")
    a = ap.parse_args()
    if a.test:
        return test()
    if not a.out:
        ap.error("the output file is needed")
    token = os.environ.get("GITHUB_TOKEN") or sys.exit("GITHUB_TOKEN is needed to read the Discussions")
    prev = {}
    if a.previous and a.previous.exists() and a.previous.stat().st_size:
        prev = json.loads(a.previous.read_text(encoding="utf-8"))
    gc = os.environ.get("GOATCOUNTER_TOKEN")
    now = dt.datetime.now(dt.timezone.utc)
    hits = goatcounter(gc, a.since) if gc else None
    stats = build(game_ids(), discussions(token), hits, prev, now.date(), now.isoformat(timespec="seconds"))
    a.out.write_text(json.dumps(stats, ensure_ascii=False, indent=1) + "\n", encoding="utf-8")
    top = [g for g in stats["ranking"] if stats["games"][g]["likes"] or stats["games"][g]["comments"]][:3]
    print(f"{a.out}: {len(stats['games'])} games, top {top}, cover {stats['featured']}, visits {'yes' if hits is not None else 'no'}")


if __name__ == "__main__":
    main()
