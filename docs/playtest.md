# Playtest: bots that play a finished game

```sh
uv run tools/playtest.py games/mygame                    # 50 perfect + 50 imperfect games -> ~/pinyol-playtests/mygame/report.md
uv run tools/playtest.py examples/pozo --perfect 10 --imperfect 10 --workers 2
```

It plays the game in `pinyol_headless` (fast: a game takes a second or two) with
- **perfect** players: they know the game. They tell you if the game can be finished and how fast.
- **imperfect** players: 80 % human-like with a skill from 0.1 to 0.9 (a reaction delay of 5 to 30 ticks, late or let-go presses, stray presses, a moment looking away, giving up) and 20 % monkeys that mash buttons (to find crashes with odd input).

and writes `report.md` (win/lose/timeout/stuck/crash per kind of player and per skill band, where the games end badly, crashes with file:line, stuck games, NaN or negative numbers, flashing, whether a repeated seed repeats), `results.csv` (every game, with its seed) and `logs/`. At most `--workers` (4) games run at once; the output is outside the repo.

## The adapter

The bots work without help, but the report is only useful about difficulty if the game says how it is scored and played. Put `tests/playtest.lua` in the game (`tests/playtest/<id>.lua` for the engine's examples). It sets `PLAYTEST`, every field optional:

| field | what |
|---|---|
| `playing()` | true while the game is being played (not a title or a menu: the bot presses A and START there) |
| `progress()` | a number, higher is further (level, room, score). No progress for a minute = `stuck` |
| `done()` | `"win"`, `"lose"` or nil: the game's end |
| `perfect(pt)` | what a perfect player holds now: `{left = true, a = true}` (`pt.t` is the tick). Without it the "perfect" player is a random explorer |
| `where()` | a short word for where the player is (`level_3`, `room_12`): the report counts where games end badly |
| `probe()` | numbers to watch: NaN is always flagged, names starting `n_` also when negative |
| `deaths()`, `stuck_ticks` | how many times it died; how long without progress is "stuck" (default 3600) |

See `tests/playtest/malabar.lua` (a perfect player in ten lines) and `pozo.lua`. The bot replaces `btn`/`btnp`; a game that reads its input some other way (its own layer, touch) installs the bot's `held` table there from the adapter.

## Reading it

The skill bands should win more as the skill rises; if they do not, something else decides. One place with more than 40 % of the bad endings is a spike (or a softlock if the games are `stuck`). A perfect player that does not win is a game bug (an unwinnable or unreachable part) or an adapter that is not perfect: replay the seed (`--only P03`) and look. The bots are a model of people: take the difficulty as relative.
