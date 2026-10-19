# Studying the GBA to improve pinyol: where it stands (2026-10-19)

Digests of what the real hardware did, audits of np2d against it, measurements, and what was changed.

## Files

| File | What |
|---|---|
| `01-ppu.md`, `02-system.md`, `03-audio.md`, `04-genres.md`, `05-perf-esp32s3.md` | research digests (hardware, system, sound, genres, making a software renderer fast on the ESP32-S3) |
| `audit-01-ppu.md`, `audit-02-system.md`, `audit-03-audio.md` | np2d against each digest: a row per behaviour, ranked fixes |
| `baseline-ppu-host.md`, `baseline-ppu-board.md` | what `ppu_render` really costs (host ratios; the board's cycles, with the frame hashes that match the Mac's) |
| `listen/` | WAVs of the Teclado toy's sounds and `numbers.txt` (click analysis): to listen to |

## What changed, and how far it is checked

| Change | Where | Host | Board |
|---|---|---|---|
| Whole-frame golden test, 30 scenes | `tests/ppu_golden_test.c`, `ppu_golden.txt` | yes | the 15 bench scenes give the same hashes |
| Sprites per line (mask of the sprites each line crosses; off-screen ones dropped) | `src/ppu.c` | goldens unchanged | mode 0 -14 %, 128 sprites -41 % (before the fixes below) |
| PPU fidelity: blending sprite over a sprite, empty object window, blend sprite in a window that bars effects | `src/ppu.c`, `tests/ppu_test.c` | pixel checks fail on the old code | **not run** |
| `line_fx(y, amount)` (a fade or blend amount per line) | `src/lua_game.c`, `docs/lua.md` | yes (CRC test) | **not run** |
| A gain change eases over the block; `sfx(.., {reverb, echo, delay})`; `instrument{...}` with loop region and ADSR | `src/audio.c`, `bp.h`, `lua_sound.c` | `tests/audio_voice_test.c`, 5 mutants caught | **not run, never listened to** |
| PSG: wave table, 7-bit noise, vibrato, bend, `tone_set` | `src/psg.c`, `lua_sound.c` | `tests/psg_test.c`, 3 mutants caught | **not run, never listened to** |
| `store`: a CRC in each file, the generation moves on only after a good write; the console retries a failed save 3 times | `src/lua_game.c`, `firmware/main/main.c`, `tests/store_test.py` | yes, 2 mutants caught | firmware compiles; **not run** |
| Teclado toy | `examples/sonidos` | script + screenshots | n/a |
| TRECE: distance haze on the pitch | `TRECE/trece/campo.lua` (its own repo) | screenshots, 4 scripts | n/a |
| MAQUETA: the tunnel comes down the floor from the horizon | `MAQUETA/maqueta/cine.lua` (its own repo) | screenshots, 18 scripts | n/a |
| Docs: 20 M instruction budget (it said 50 M), `math.randomseed`, up to 16 link peers and large ids | `docs/lua.md` | n/a | n/a |

## To do when the board is back

1. `cd firmware && idf.py -DBP_BENCH=ppu build flash`; the `BENCH ppu SCENE` lines' `hash=` must equal the table at the end of `baseline-ppu-board.md` (15 scenes; two of them changed on purpose with the fidelity fixes).
2. Read `audio_out_mix_us` (printed in the `perf:` line) with an `instrument` note and a modulated `tone` sounding. No audio CPU figure exists yet.
3. Put the normal firmware back (`-DBP_BENCH=OFF`). The board's slot 0 had a truncated backup written to it once and was repaired with a full build; the slot-1 firmware was never touched.
4. Listen to `listen/*.wav` and to `pinyol_sim --game sonidos` (C: Teclado).

## Commits (branch `gba-engine`, from `cards`'s tip; nothing pushed)

1. `cd951ee` ppu: sprites per line, fidelity fixes, `line_fx`, the golden test, `linefx` game and CRC test.
2. `6b8f2da` store: the CRC, the generation after a good write, the console's retry, `store_test.py`.
3. `e1f8b9f` audio: instruments, sends and delay on `sfx`, the PSG options, the Teclado toy and its tests.
4. `cf7b20c` firmware: `-DBP_BENCH=ppu`.
5. docs: this folder, `progress.md`, three corrections in `docs/lua.md`.

Each commit was built and tested alone in its own worktree (120, 121, 122 and 122 tests pass). `TRECE` and `MAQUETA` are their own
repos: their one-file changes are left for their owners to commit. `games/` in this folder was untracked before this work and is not
part of it. The WAVs in `listen/` are not committed (860 KB of binaries that only a scratch harness makes); `numbers.txt` and
`LEEME.txt` are.

## Known limits

- Layout noise on the board is about +-7 % between builds that run the same code (instruction placement in IRAM): a change under ~8 % on one scene is not a result.
- A per-line fade costs ~7 us a frame on the host in the worst case (a new amount on every line); not measured on the board.
- Not done on purpose: window wrap (x2 < x1: sources disagree), the sprite priority hijack by transparent pixels (a hardware bug), per-line palette and mosaic, an affine bitmap layer, GBA-faithful sprite cycle budget.
