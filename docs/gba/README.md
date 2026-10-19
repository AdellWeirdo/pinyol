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
3. **The board runs the engine of branch `font-catalog` (`np2d-psx`), not this one.** Its slot 0 held `np2d-psx/firmware/build/pinyol_console.bin`
   (the first MB of my backup is byte-identical to it) and the Cirera menu on the card (`games/cirera`, from that branch) calls
   `load_pictures`, which this branch does not have. A firmware built from this branch therefore boots to an error screen
   ("main.lua:33 attempt to call a nil value (upvalue 'load_pictures')"), not to the list. An earlier version of this file
   said the board "boots to the game list at 59.9 fps" with such a build: that was read from the log's perf line, which an
   erroring menu also prints; nobody had looked at the screen. The original firmware is back in slot 0 (checked) and the menu works.

Still open, and **blocked by that**: a Lua game using `line_fx` on the board (TRECE and MAQUETA are not in the console's list anyway:
the original firmware lists 32 games and leaves the rest out; TRECE's folder was sent over the cable and is on the card now), an
instrument sounding next to a running game, and the saves' retry with a card that fails. To do them, this work has to run on the
console's engine: `git merge gba-engine` into `font-catalog` conflicts in `CMakeLists.txt`, `README.md`, `docs/lua.md`, `src/audio.c`
and `src/lua_sound.c` (tried in a scratch worktree, aborted). `src/audio.c` and `lua_sound.c` are the ones that need care.

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
- Not done on purpose: window wrap (x2 < x1: sources disagree), the sprite priority hijack by transparent pixels (a hardware bug), per-line palette and mosaic, an affine bitmap layer, GBA-faithful sprite cycle budget.

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
