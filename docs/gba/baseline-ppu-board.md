# `ppu_render` on the board

The real renderer (`src/ppu.c`), not the simplified kernels of `firmware/main/bench.c`, on the Cirera console
(ESP32-S3 at 240 MHz, content in PSRAM, the 240×160 frame in internal RAM), measured on 2026-10-19 with
`firmware/main/bench_ppu.c`. One core, both line halves in turn (as `hal_parallel` does while the second core is not
started). Median of 300 frames, in CPU cycles; 4.0 M cycles = one core for a 60 fps frame. The scenes are those of the
host harness, so a frame hash of the first 120 frames can be compared: **all 15 scenes give the same hash on the
board and on a Mac** (same pixels from the same code; the content internal-RAM pass does not fit: 75 KB free).

```sh
cd firmware && idf.py -DBP_BENCH=ppu build flash        # lines start with "BENCH ppu"; then -DBP_BENCH=OFF for the console
```

| Scene | before | after | change | ms | share of a core at 60 fps |
|---|---|---|---|---|---|
| clear only | 331 k | 378 k | +14.2 % | 1.57 | 9 % |
| 1 layer | 1,247 k | 1,283 k | +2.8 % | 5.34 | 32 % |
| 4 layers | 3,376 k | 3,386 k | +0.3 % | 14.11 | 85 % |
| 128 sprites 16x16 | 1,554 k | 914 k | -41.2 % | 3.81 | 23 % |
| 1 affine layer | 1,702 k | 1,746 k | +2.6 % | 7.28 | 44 % |
| light: 2L+32 spr | 2,335 k | 2,188 k | -6.3 % | 9.12 | 55 % |
| GBA mode 0: 4L+128 spr | 4,759 k | 4,081 k | -14.2 % | 17.00 | 102 % |
| Mode 7: aff+1L+64 spr | 3,472 k | 3,162 k | -8.9 % | 13.18 | 79 % |
| Max: aff+3L+128 spr | 5,643 k | 4,974 k | -11.9 % | 20.72 | 124 % |
| FX: 4L+alpha+window | 6,286 k | 5,946 k | -5.4 % | 24.77 | 149 % |
| FX: 128 spr half OBJ_BLEND | 2,723 k | 2,078 k | -23.7 % | 8.66 | 52 % |
| x: 4L+alpha only | 6,138 k | 6,166 k | +0.4 % | 25.69 | 154 % |
| x: 4L+window only | 3,902 k | 4,203 k | +7.7 % | 17.51 | 105 % |
| x: 4L+128 spr half OBJ_BLEND | 6,043 k | 5,387 k | -10.9 % | 22.45 | 135 % |
| x: 128 sprites off-screen | 1,201 k | 383 k | -68.1 % | 1.59 | 10 % |

"before" is `src/ppu.c` at the commit before the per-line sprite masks; "after" has them (`prepare` marks, per line, the
sprites whose box crosses it, and off-screen sprites are dropped). The frames are identical.

## What it says

- **The real renderer costs about twice what `bench.c`'s kernels suggested.** 4 layers: 3.39 M cycles (85 % of a core)
  where the kernel said 1.56 M (39 %); GBA mode 0 (4 layers + 128 sprites): 4.08 M (102 %) against 2.07 M (52 %).
  One core cannot hold 60 fps in those scenes; the two cores, each drawing half the lines, can (about half a core each).
- **A line with nothing on it is not free:** clearing alone is 0.33 M cycles (about 8 cycles per pixel for the fill
  and the conversion to RGB565), 8 % of a core.
- **Tile layers cost about 0.85 M cycles each** (about 22 cycles per pixel), alpha adds 2.8 M to four layers.
- **Layout noise:** moving a few lines of `ppu.c` changed scenes that run the same code by up to ±7 % (instruction
  placement in IRAM), so a change under about 8 % on one scene is not a result. Judge by the scenes the change is for.
- **Compiler flags for `ppu.c` do not pay** (same board, same scenes, hashes unchanged). `-O3`: 4 layers +7 %, mode 0
  +6 %, only the OBJ_BLEND-sprites scene gains (−17 %). `-funroll-loops` on `-O2`: clear −14 %, but 4 layers +10 %,
  mode 0 +8 %. The default `-O2` is the best overall; do not revisit without a new kernel.

## After the fidelity fixes, on the board (2026-10-19)

The 15 scenes again with the current `src/ppu.c` (sprites per line, the three fidelity fixes, the split final loop): **15 of 15
frame hashes equal the table above**, the two changed on purpose included. Median cycles per frame, one core:

| Scene | before the sprite masks | with them | now | now vs before | share of a core at 60 fps |
|---|---|---|---|---|---|
| clear only | 331 k | 378 k | 376 k | +13.7 % | 9 % |
| 1 layer | 1,247 k | 1,283 k | 1,281 k | +2.7 % | 32 % |
| 4 layers | 3,376 k | 3,386 k | 3,383 k | +0.2 % | 85 % |
| 128 sprites 16x16 | 1,554 k | 914 k | 913 k | -41.3 % | 23 % |
| 1 affine layer | 1,702 k | 1,746 k | 1,744 k | +2.5 % | 44 % |
| light: 2L+32 spr | 2,335 k | 2,188 k | 2,187 k | -6.3 % | 55 % |
| GBA mode 0: 4L+128 spr | 4,759 k | 4,081 k | 4,078 k | -14.3 % | 102 % |
| Mode 7: aff+1L+64 spr | 3,472 k | 3,162 k | 3,161 k | -9.0 % | 79 % |
| Max: aff+3L+128 spr | 5,643 k | 4,974 k | 4,970 k | -11.9 % | 124 % |
| FX: 4L+alpha+window | 6,286 k | 5,946 k | 5,943 k | -5.5 % | 149 % |
| FX: 128 spr half OBJ_BLEND | 2,723 k | 2,078 k | 1,725 k | -36.7 % | 43 % |
| x: 4L+alpha only | 6,138 k | 6,166 k | 5,451 k | -11.2 % | 136 % |
| x: 4L+window only | 3,902 k | 4,203 k | 4,200 k | +7.6 % | 105 % |
| x: 4L+128 spr half OBJ_BLEND | 6,043 k | 5,387 k | 5,029 k | -16.8 % | 126 % |
| x: 128 sprites off-screen | 1,201 k | 383 k | 381 k | -68.3 % | 10 % |

The fixes did not cost anything: the sprite scenes are where they were (-0.1 %), and the scenes that blend gained, because the
final loop was split into the common case with no window and the one with windows (alpha only -11.6 % against the masks alone, a
blending-sprite scene -17 %, the host had predicted -7 % for the first). Layout noise is still about 0.5 % between runs here.

## Expected frame hashes (current `src/ppu.c`)

FNV-1a 64 of frames 0..119 of each scene, as `bench_ppu.c` prints them (`hash=`) and as the host harness gave them on 2026-10-19.
Measured on the board before the PPU fidelity fixes, 15 of 15 matched the host. Two scenes changed on purpose with those
fixes (a blending sprite over a sprite now blends with the background): `FX: 128 spr half OBJ_BLEND` and
`x: 4L+128 spr half OBJ_BLEND`; check the board against this table.

| Scene | hash |
|---|---|
| clear only | `684ff1e0e683e325` |
| 1 layer | `0fa13df27bdbf3eb` |
| 4 layers | `3a0cfb1b4bc78fd0` |
| 128 sprites 16x16 | `8d03b241d7aa83d0` |
| 1 affine layer | `3e8631b8a5c9ce74` |
| light: 2L+32 spr | `88108c8a845b4c95` |
| GBA mode 0: 4L+128 spr | `285505286fa5065a` |
| Mode 7: aff+1L+64 spr | `141e51d55cdf3226` |
| Max: aff+3L+128 spr | `956505d3eb678c99` |
| FX: 4L+alpha+window | `7678940a038438d4` |
| FX: 128 spr half OBJ_BLEND | `e2ec559e0a268aa7` |
| x: 4L+alpha only | `1a44cc151ab180e4` |
| x: 4L+window only | `15d3f7e0226ca2e9` |
| x: 4L+128 spr half OBJ_BLEND | `5df19b538750a824` |
| x: 128 sprites off-screen | `684ff1e0e683e325` |
