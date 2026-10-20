# Studying the GBA to improve pinyol: where it stands (2026-10-19)

Digests of what the real hardware did, audits of np2d against it, measurements, and what was changed.

## Files

| File | What |
|---|---|
| `01-ppu.md`, `02-system.md`, `03-audio.md`, `04-genres.md`, `05-perf-esp32s3.md` | research digests (hardware, system, sound, genres, making a software renderer fast on the ESP32-S3) |
| `audit-01-ppu.md`, `audit-02-system.md`, `audit-03-audio.md` | np2d against each digest: a row per behaviour, ranked fixes |
| `baseline-ppu-host.md`, `baseline-ppu-board.md`, `baseline-audio-board.md` | what `ppu_render` and the sound really cost (host ratios; the board's cycles and percentages, with the frame hashes that match the Mac's) |
| `listen/` | WAVs of the Teclado toy's sounds and `numbers.txt` (click analysis): to listen to |

## What changed, and how far it is checked

| Change | Where | Host | Board |
|---|---|---|---|
| Whole-frame golden test, 30 scenes | `tests/ppu_golden_test.c`, `ppu_golden.txt` | yes | the 15 bench scenes: **15 of 15 hashes equal the host's**, with the fidelity fixes in |
| Sprites per line (mask of the sprites each line crosses; off-screen ones dropped) | `src/ppu.c` | goldens unchanged | mode 0 -14 %, 128 sprites -41 % (before the fixes below) |
| PPU fidelity: blending sprite over a sprite, empty object window, blend sprite in a window that bars effects | `src/ppu.c`, `tests/ppu_test.c` | pixel checks fail on the old code | hashes match; the scenes that blend are 7-17 % faster |
| `line_fx(y, amount)` (a fade or blend amount per line) | `src/lua_game.c`, `docs/lua.md` | yes (CRC test) | the PPU side runs (`fx_ev`); no Lua game on the board yet |
| `sfx(.., {delay})`; `instrument{...}` with loop region and ADSR (on this branch's own voice engine; on `gba-engine`'s: a gain ramp and `echo` too, dropped in the merge, see below) | `src/audio.c`, `bp.h`, `lua_sound.c` | `tests/audio_voice_test.c`, 5 mutants caught | CPU measured ([baseline-audio-board.md](baseline-audio-board.md)) |
| PSG: wave table, 7-bit noise, vibrato, bend, `tone_set` | `src/psg.c`, `lua_sound.c` | `tests/psg_test.c`, 3 mutants caught | CPU measured: 2.0-2.4 % of a core a tone |
| `store`: a CRC in each file, the generation moves on only after a good write; the console retries a failed save 3 times | `src/lua_game.c`, `firmware/main/main.c`, `tests/store_test.py` | yes, 2 mutants caught | firmware compiles; **not run** |
| Teclado toy | `examples/sonidos` | script + screenshots | n/a |
| TRECE: distance haze on the pitch | `TRECE/trece/campo.lua` (its own repo) | screenshots, 4 scripts | n/a |
| MAQUETA: the tunnel comes down the floor from the horizon | `MAQUETA/maqueta/cine.lua` (its own repo) | screenshots, 18 scripts | n/a |
| Docs: 20 M instruction budget (it said 50 M), `math.randomseed`, up to 16 link peers and large ids | `docs/lua.md` | n/a | n/a |

## Checked on the board (2026-10-19)

1. `-DBP_BENCH=ppu`: 15 of 15 hashes equal the table in `baseline-ppu-board.md`; no regression (+-0.5 %).
2. `-DBP_BENCH=audio`: the mixer's cost per voice, tone and reverb ([baseline-audio-board.md](baseline-audio-board.md)); no underruns.
3. **The board runs `main`** (the merge of `gba-engine` and `font-catalog`, then the editor's animations), built with
   `-DBP_REMOTE=ON -DFLASH_GAME=examples/hola`. Looked at on the screen, not read from the log: the Cirera menu lists the
   **48 games** on the card at 59.8 fps (the original firmware listed 32), TRECE's pitch fades into haze with `line_fx` at 58-59 fps
   (what it ran at without the haze), and MAQUETA's train scene with the tunnel coming down the floor runs at 55-60 fps.
   Do not take a screenshot and read the perf line in the same run: each capture freezes the game for seconds, and MAQUETA read
   5.8 fps that way. (An earlier build from a branch without `load_pictures` printed a perf line over an erroring menu and was
   reported as "boots to the game list": a screen has to be looked at.)
4. `-DBP_BENCH=audio` again on `main`, after the mixer's changes (below, "Commits after the merge"): idle 1.84 -> 1.10 %, four PSG
   tones 9.72 -> 5.72 %, everything at once 19.72 -> 15.45 % of a core; the table is in [baseline-audio-board.md](baseline-audio-board.md).

5. **An instrument and PSG tones beside a running game** (TRECE): 57-59 fps with 8 notes and 4 tones sounding, audio at 27 % of a core,
   no underruns ([baseline-audio-board.md](baseline-audio-board.md)). The 38.6 fps window seen once before the mixer's changes did not come back.
6. **`examples/pinball` on the console** (sent over the cable, `w:drive` flippers): 59-60 fps, tick 1.7 ms, audio 4-5 %; the flippers answer the
   keys and the ball is shot from the spring. (A hint that ran past the panel's edge on the console was cut in two lines.)

Still open: the saves' retry with a card that fails (compiled and read, never run: it needs the card taken out while the game saves,
and the firmware does not remount a card put back).

## Commits (branch `gba-engine`, from `cards`'s tip; nothing pushed)

1. `cd951ee` ppu: sprites per line, fidelity fixes, `line_fx`, the golden test, `linefx` game and CRC test.
2. `6b8f2da` store: the CRC, the generation after a good write, the console's retry, `store_test.py`.
3. `e1f8b9f` audio: instruments, sends and delay on `sfx`, the PSG options, the Teclado toy and its tests.
4. `cf7b20c` firmware: `-DBP_BENCH=ppu`.
5. `4996ef5` docs: this folder, `progress.md`, three corrections in `docs/lua.md`.
6. `b3b11dc` firmware: `-DBP_BENCH=audio` and the per-block minimum/maximum.
7. `adc6354` docs: what the board showed (the PPU after the fixes, the sound's cost).
8. fix: the audio bench did not reset the audio, so it saw 6.7 % at idle that was its own (commit 7's message says it was the engine's: it was not).

Commits 1 to 4 were each built and tested alone in their own worktree (120, 121, 122 and 122 tests pass). `TRECE` and `MAQUETA` are their own
repos: their one-file changes are left for their owners to commit. `games/` in this folder was untracked before this work and is not
part of it. The WAVs in `listen/` are not committed (860 KB of binaries that only a scratch harness makes); `numbers.txt` and
`LEEME.txt` are.

## Known limits

- Layout noise on the board is about +-7 % between builds that run the same code (instruction placement in IRAM): a change under ~8 % on one scene is not a result.
- A per-line fade costs ~7 us a frame on the host in the worst case (a new amount on every line); not measured on the board.
- Not done on purpose: window wrap (x2 < x1: sources disagree), the sprite priority hijack by transparent pixels (a hardware bug), per-line mosaic (per-line palette is `line_pal`), an affine bitmap layer, GBA-faithful sprite cycle budget.

## `gba-on-catalog`: this work on the engine the console runs

`font-catalog` already had a voice engine with envelopes, loop points, pan, a game reverb and a MIDI sequencer. The merge keeps
its `audio.c` whole and rebuilds on top of it what this work added: `sfx(..., {delay})` (a `wait` in `sfx_opts`), and
`instrument{}` as an `sfx` voice with its envelope and loop region. **Dropped on purpose:** the gain ramp (their engine steps the
gain; the `synth` test is theirs again), `sfx`'s `echo`, and `reverb` as a send to the studio's reverb (`reverb` is their game
reverb now). The PPU, `line_fx`, `store`, the PSG options and the Teclado toy merged as they were.

### On the board, with this branch's firmware (2026-10-19)

Built from `gba-on-catalog` (`-DBP_REMOTE=ON`, as the console's own build is): the Cirera menu works (screenshot checked), TRECE
sent over the cable runs on the panel at 58-60 fps with the distance haze visible. Measured with `tools/remote.py`:

- **`line_fx` (TRECE's haze) costs about 0.6 ms of PPU** (the `picture` figure 4.25 ms with it, 3.63 ms after `line_off()`); the fps
  is 58-59 either way, so something else is the limit in that scene (tick 1.4 ms, render 14.8 ms).
- **Eight instrument notes next to a running TRECE: no underrun, but one 5 s window fell to 38.6 fps** (render 22.6 ms, the mixer at
  24 % of a core); the windows around it were 59.6 and 55.6 fps. The mixer shares core 1 with the second half of each frame. One
  voice here costs about 1.6-1.8 % of a core (8 notes: +12-14 % over the 6 % idle), three times what the `gba-engine` voice cost
  (0.6 %): this branch's voice has per-sample envelope, pan and reverb send work. **Keep instruments to a few voices at once next to
  a heavy game** until the voice is made cheaper.
- The saves' retry and a card that fails: still not tried.

The firmware that was on the board (np2d-psx's build) is back in slot 0, checked by screenshot. The merged build is kept in the
scratchpad only (`gba_on_catalog_firmware.bin`); TRECE's folder is on the card (`games/trece`, 3.4 MB).

## `unified`: every branch in one (2026-10-19)

`unified` is `gba-on-catalog` plus the three things it lacked, merged one at a time with the suite run after: local `main` (the console
lists up to 64 games), `origin/main` (IL·LUSTRES, a new version) and `audreygotchi-gb` (the Audreygotchi Game Boy port: a
work-in-progress backup of `games/audreygotchi`, 1266 files, 49 MB with its screenshots). No conflict in any of the three.
Every local branch and `origin/main` is now an ancestor of `unified`. What `unified` holds:

| Line of work | Branches | Came in through |
|---|---|---|
| The engine the console ran, with the PlayStation/Saturn look | `psx-saturn-engine` -> `font-catalog` | `gba-on-catalog` |
| This GBA study | `gba-engine` | `gba-on-catalog` |
| The site: comments, footer, library updates, the phone player | `giscus`, `footer`, `library-update`, `mobile-player`, `cards` | `gba-engine` (they were its base) and `origin/main` |
| 64-game list, the faster screen pipeline | `launcher-max-64`, `perf-turned-blit-overlap`, `cirera-empty-b` | `main` |
| Older work already in `main` | `fases`, `gb-talk`, `mic`, `studio`, `libretro-dev`, `npc-foot`, `os-logos`, `engine-section`, `library-ilustres` | `main` |
| Audreygotchi | `audreygotchi-gb` | direct |

Not source and not merged: `origin/gh-pages` (the deployed site) and `origin/stats` (data). Local `main` and `origin/main` had each
6 commits the other lacked; `unified` has both sets. Neither was moved, and nothing was pushed.
