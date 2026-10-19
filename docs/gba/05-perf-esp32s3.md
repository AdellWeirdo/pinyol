# 05 - Making the PPU fast on the ESP32-S3

A research digest for `src/ppu.c` (the software GBA-style scanline renderer) on the Cirera console: ESP32-S3R8,
240 MHz dual core, 8 MB octal PSRAM at 80 MHz, ST77922 over QSPI at 80 MHz, ESP-IDF. Written 2026-10-19.

How to read the marks:

- **[V]** verified in the code in this repo, in `docs/measurements.md`, or in a page I fetched (source in section 9).
- **[E]** my estimate. No measurement behind it. Treat gains as order of magnitude, and re-measure.
- **[U]** unverified: from memory, from a forum post, or inferred. Check before building on it.

Nothing outside `docs/gba/` was edited. No GPL code was read or copied. mGBA (MPL-2.0) was read only as a
description of technique; nothing was copied.

---

## 1. What the renderer does today (specific to this code)

All of this is read from `src/ppu.c`, `ppu.h`, `lua_game.c`, `firmware/main/{main,display,bench}.c` [V].

- **Tiles**: 8x8, 8 bits per pixel, 64 index bytes per tile, row after row. Index 0 is transparent. The palette entry is
  `(index + 16 * bank) & 255`. Tile data and maps come from `load_bytes()` (a `malloc`, so PSRAM for anything big,
  because `CONFIG_SPIRAM_MALLOC_ALWAYSINTERNAL=256`).
- **`rows` skip table**: one `uint16_t` per tile. Bit `y` = row `y` is empty, bit `8+y` = row `y` is fully opaque
  (`ppu_tile_rows`). `bg_tiles_x` uses it to skip empty rows and to take the no-test copy path for opaque rows.
- **Line composition**: each line is drawn back to front into two `uint32_t[240]` buffers, `top` and `under`. A pixel is
  `colour | layer_id << 16` (`PX`). `under` is filled only when `F.track` (alpha FX, or any `OBJ_BLEND` sprite) is on for
  the whole frame. After the layers, `line()` either copies `top` to the output as RGB565 or runs the FX pass
  (alpha, fade through per-channel LUTs, windows).
- **Specialisation**: `layers_x` is `always_inline` and instantiated four ways: windows on/off x track on/off. Tile runs
  add a second axis (opaque row or not, hflip or not).
- **Sprites**: up to 128, each tested against every line it might touch. `prepare()` builds `F.order[prio][]` (back to
  front) once per frame and drops only `!on` sprites. Then `obj_line_x` runs for every sprite in the list on every line
  and rejects by `y` itself (`ppu.c` 318-321). Plain indexed sprites with no affine and no mosaic take a fast path;
  everything else, including **all RGB565 sprites** (`o->rgb`), goes through the per-pixel `obj_pixel()`.
- **Bitmap layers**: `bitmap_row` steps the column and copies or skips mask bytes 8 pixels at a time, but still calls
  `put()` per pixel into the 32-bit buffer.
- **Two cores**: `hal_parallel(render_part)`: core 0 draws even lines, core 1 odd lines, each with its own `LB[part]`.
  The measured speed-up is 1.6-1.9x, not 2x.
- **Memory placement**: the PPU's code is in IRAM and its `.bss`/`.rodata` in internal RAM (`linker.lf`, scheme
  `ppu_inside`). Data cache 64 KB with 64-byte lines, instruction cache 32 KB (`sdkconfig.defaults`). `G.world`
  (240x160 RGB565, 76.8 KB) is internal.
- **Output**: `ppu_render(G.world)` -> `gfx_upscale2x` writes each source pixel as two aligned 32-bit words in two panel
  columns, byte-swapped, into a 20 KB internal strip; 15 strips, ring of 2 DMA buffers, `queue_size = 2`.

### 1.1 The frame budget is serial, so PPU time is not hidden [V by reading, model is mine]

`draw()` in `main.c` is: `game_draw_world()` (Lua `_draw`, then `ppu_render`) -> `display_wait_scan()` ->
`display_present_strips()` (blocks until the last strip is out). The next tick's Lua `_update` only starts after that.
So per frame, on the 60 fps path:

```
update + draw + ppu + (wait for TE) + strips (>= 8.10 ms on the wire) <= 16.67 ms
```

The wire alone is 480x320x16 bits / (4 lines x 80 MHz) = 7.68 ms; measured 8.10 ms [V]. Plataformas (picture 5.3 ms,
`_draw` ~1 ms, `_update` up to 1.9 ms) lands at roughly 15-16 ms: right at the limit, which matches its measured 61 fps
and the 53 fps dips with a bomb flash. This means:

1. Every ms saved in `ppu_render` is a ms of frame-rate headroom, 1:1, until the CPU side is below ~8 ms.
2. Overlapping CPU work with the DMA (section 4.12) is worth as much as the biggest PPU optimisation, because the CPU
   is idle for about 5-6 ms of every frame while the strips drain [E: 8.1 ms wire minus ~2.4 ms strip CPU].
3. The strip CPU work (2.4 ms, `gfx_upscale2x` + overlay) is hidden under the DMA. Optimising it gains nothing in fps.
   Do not spend effort there (the exception is the first strip, which cannot be hidden).

### 1.2 `bench.c` does not measure `ppu.c` [V]

`firmware/main/bench.c` has its own kernels: 4 bpp tiles, indexed 8-bit output, `put_row4`, a 25-cycle SWAR blend,
`strip_indexed`. It never calls `ppu_render`. So the headline numbers (4 layers + 128 sprites = 2,074k cycles) describe a
**simplified baseline**, not the shipping renderer. `ppu.c` differs in ways that cost cycles: 8 bpp bytes, a palette
lookup per pixel, 32-bit `PX` stores, optional `under` stores, window tests, a final pass. The real renderer's cost has
only been seen indirectly, through the `perf` line of the Lua games (`picture X ms`). **Step 0 of everything below is to
measure `ppu_render` itself** (section 3).

Useful derived numbers from the bench [V arithmetic, E interpretation]:

| From bench | Cycles per pixel |
|---|---|
| 4 layers 1,561k / (4 x 38,400) | 10.2 |
| 1 layer 471k / 38,400 | 12.3 |
| affine layer 801k / 38,400 | 20.9 |
| alpha blend 967k / 38,400 | 25 |
| 128 sprites 538k / (128 x 16 x 16 = 32,768 sprite pixels) | 16.4, including the per-line visit of every sprite |

---

## 2. Hardware facts that matter (and which are verified)

| Fact | Status |
|---|---|
| S3 has **no PPA and no 2D-DMA/DMA2D**. The ESP-IDF PPA page exists for ESP32-P4 and returns 404 for the S3 tree; LVGL's DMA2D/PPA integration names only the P4. | [V] |
| S3 GDMA can reach PSRAM, but ESP-IDF says "DMA bandwidth to external RAM is low, and drops when the CPU uses it", and descriptors must be in internal RAM. | [V] |
| SPI master DMA wants internal `MALLOC_CAP_DMA` buffers, 32-bit aligned. Per-transaction overhead is ~20 us + 8n/Fspi for interrupt-driven; a linked-list setup costs ~2 us. Max transfer 4092 B by default (the driver chains descriptors; this repo uses 20 KB). | [V] |
| The 8.10 ms vs 7.68 ms gap over 15 strips is ~28 us per strip of per-transaction overhead. At most ~0.4 ms can be recovered, and only with bigger strips (RAM). | [E] |
| PIE (S3 "TIE"): 8 x 128-bit Q registers (q0-q7); instructions with the `ee.` prefix: `ee.vld.128.ip`, `ee.vst.128.ip`, `ee.vst.l.64.ip`, `ee.movi.32.q`, `ee.zero.q`, `ee.src.q` + `wur.sar_byte` (realign), `ee.vmulas.*`, `ee.vmax.*`. Used from **assembly** (inline `asm volatile` or `.S`); the Espressif blog shows no C intrinsics. Clang builtins exist (`__builtin_xtensa_ee_vld_128_ip`) in the Espressif LLVM fork, not in the GCC toolchain ESP-IDF uses. | [V] for the list, [U] for GCC intrinsics |
| PIE has **no vector gather/table lookup** that I found. A palette lookup cannot be vectorised; it stays scalar `l16ui`. | [U] (absence of evidence in what I read; check the TRM PIE chapter) |
| Espressif's own LVGL SIMD blend (`esp_lvgl_port`, `lv_color_blend_to_rgb565_esp32s3.S`) uses PIE for solid fills and blends, handles 4-byte and 2-byte aligned heads/tails, and its comment says it is "not worth" using PIE below 16 pixels of width. It uses the zero-overhead `loopnez`. | [V] |
| PIE loads/stores are 16-byte-alignment sensitive. A user on the Espressif forum hit a `LoadStoreError` on `ee.vld.128.ip` for an address that worked with `l32i` (cause not established in what I could read). | [V] that it was reported, [U] on the cause |
| PIE register state is switched lazily (coprocessor-disabled exception on first use by a task). A forum estimate: ~210 cycles of handler + ~40-50 to save/restore. Best when only one task per core uses PIE. There are no callee-saved Q registers by ABI. | [U] (forum, informal) |
| `dsps_memcpy_aes3` IRAM->IRAM measured by a forum user at ~1.4 GB/s; PSRAM-bound copies see almost no PIE gain (PIE 58.1 vs `memcpy` 56.7 MB/s). PIE helps only where the bus is not the limit, i.e. internal RAM. | [U] (one forum thread) |
| Xtensa zero-overhead loops (`loop`, `loopnez`) exist on the S3 (not on the S2). GCC uses them for simple counted loops; inline `asm` in the loop body disables them. Check the disassembly. | [V] for existence, [U] for what GCC does to `ppu.c` |
| Data and instruction caches are shared by both cores [U, I believe so from the TRM]. External RAM shares the cache region with flash. Large PSRAM working sets (>32 KB) evict cached flash code. | [V] last two, [U] first |
| Misaligned 16/32-bit loads and stores on Xtensa LX trap unless an unaligned option is configured. The 32-bit tricks need aligned bases. | [U] (strong prior, verify on the board) |
| Cache autoload / hardware prefetch registers exist on the S3 (`EXTMEM_DCACHE_AUTOLOAD_*`, `DCACHE_PRELOAD_CTRL` appear in a simulator model of the peripheral), and ROM has `Cache_Start_DCache_Preload`. Whether they are on by default and whether they help a 64-byte line fill from octal PSRAM is not documented in what I read. | [U] |
| ESP-IDF has `xtensa_perfmon` (docs: "Performance Monitor") that programs the LX7 counters through `xtensa_perfmon_init/start/stop/value`. Which event IDs give D-cache miss, interlock and branch-penalty counts I did not find. | [V] API exists, [U] events |
| ST77922: `x_start`/`x_end` must be divisible by 4 when refreshing (Espressif driver readme). Matters for any partial-window update. COLMOD 0x3A supports 16/18/24 bpp per that readme; a 12-bit (RGB444) mode was not found. | [V] / [U] |
| 120 MHz octal PSRAM is not available without experimental IDF features (ESPHome docs; IDF says restrictions). Do not plan on it. | [V] |
| `CONFIG_SPIRAM_XIP_FROM_PSRAM` "can improve performance" (IDF PSRAM guide). This would speed the Lua VM and engine code (flash-resident, 32 KB icache), not the PPU. | [V] claim, [U] gain here |

No GBA emulator for the ESP32-S3 turned up in my searches. What exists is the NES/Game Boy class (Espressif's
`esp32-nesemu`, gnuboy ports) on the original ESP32, which feed SPI by DMA from the second core: the same shape this
firmware already has.

---

## 3. Measure first (do this before changing any pixel code)

Everything below is gated by a baseline. The aim is to find where `ppu.c` really spends its cycles.

### 3.1 Bench `ppu_render` itself, in `firmware/main/bench.c`

`bench_run()` runs before `part1_task` exists, so `hal_parallel` runs part 0 then part 1 **serially on the calling
core** [V, `main.c`]. A cycle count around `ppu_render()` is therefore the whole-frame, one-core number, directly
comparable with the table in `docs/measurements.md`. Add scenes that call `ppu_reset()`, fill `PPU.bg[]` / `PPU.obj[]`
with synthetic content like the existing kernels, and time `ppu_render(buf)` best-of-5 with `esp_cpu_get_cycle_count()`:

1. One `BG_TILES` layer: (a) all opaque, `rows` set; (b) ~1/3 transparent tiles (like `make_content`), `rows` set;
   (c) same with `rows == NULL`; (d) scroll_x % 8 == 0 and != 0; (e) with hflip entries; (f) tiles+maps in PSRAM, 160 KB.
2. Four layers + 128 indexed 16x16 sprites (the "GBA mode 0" scene, now through the real code), and the same with 128
   sprites entirely off screen, and with 8 sprites of 64x64.
3. 128 **RGB565** sprites (`rgb` set, with and without `mask`) and 128 with `affine >= 0`.
4. `BG_BITMAP` 240-wide, wrapping and not, mask NULL and mask present, bitmap in PSRAM.
5. FX: alpha with one first-target layer; alpha with a `OBJ_BLEND` sprite; fade (`FX_DARKEN`, ey = 8); fade with
   `evy = 0`; per-line `fx_ev`.
6. Windows: one rectangle; two; an object window.
7. Affine: pow2 map wrap, non-wrap, with and without the per-line table; `pc == 0` (no rotation) and `pc != 0`.
8. Calibration: the synthetic `bench.c` kernel scene "4 layers + 128 sprites" vs the same scene through `ppu_render`. The
   ratio tells you how much the real renderer costs over the simplified one.
9. Core scaling: time `render_part(0, ...)` alone vs both parts after `part1_task` is running (the `BP_BENCH=play`
   build), to learn whether the 1.6-1.9x loss is imbalance, barrier, or contention.

### 3.2 Counters to add to `ppu.c` (behind `#ifdef PPU_PROFILE`, compiled out otherwise)

Cycle counters, per core (`LB[part]`), accumulated per frame and printed with `perf_report`:

- backdrop init, `windows()`, `layers` split by BG type (tiles / affine / bitmap) and by sprites, final pass (copy / fade
  / alpha), plus the barrier wait in `hal_parallel` on core 0.

Event counters (host and board both can run them; they cost nothing in the host build and answer "which path does my
game actually use"):

- tile runs by class: empty-skipped, opaque, mixed; runs shorter than 8 (the two edge runs of each line) vs full runs.
- pixels written per layer; pixels hidden by `put()` windows; `under` stores (the `track` cost).
- sprites visited (every `obj_line_x` call), rejected by `y`, off-screen in `x`, drawn; split by fast path / `obj_pixel`
  path / affine / mosaic. RGB-sprite pixels drawn through `obj_pixel`.
- bitmap pixels and mask-byte classes (0x00 / 0xFF / mixed).
- final pass lines by class: straight copy, fade-only, full FX; blend pixels.
- lines skipped by `PPU_LINE_OFF`, affine pixels clipped by `clip_span`.

### 3.3 Real content, not synthetic

- Run each Lua game's perf script (autotest builds, `docs/measurements.md` method) and record `picture` average and
  longest. Pick the 5 heaviest as the standing optimisation set: synthetic scenes mislead (blend, windows and RGB sprites
  barely show in `bench.c`).
- Log a per-frame timeline to confirm the serial model of 1.1: `_update`, `_draw`, `ppu`, `strip_us.wait`, strips CPU,
  and when the last DMA completes. `strip_us.world/wait/first/rest` already exist in `main.c` [V].

### 3.4 Tooling checks

- Disassemble `ppu.c`'s object with `xtensa-esp32s3-elf-objdump -d`: count `loopnez`/`loop`, look for calls to
  `__divsi3`/`__modsi3`/`memmove`/`memcpy` in the hot functions, and look at the code of one 8-pixel tile run to count
  instructions per pixel. The existing history (a `memmove` per tile row, `docs/measurements.md`) shows this pays off.
  `x % mw` in `obj_line_x` is a hardware divide per sprite pixel on the generic path (the S3 has a 32-bit hardware
  divide, per the repo's own notes).
- `xtensa_perfmon` for D-cache misses, interlocks and branch penalties on the PPU region only [U events]. Use it to decide
  whether the tile kernel is load-use bound (then unroll and hoist loads) or miss bound (then align and shrink data).
- Print `free internal` in the same line: section 4 (#4, #13) spends RAM (10 KB for tables, 77 KB for a world buffer).

### 3.5 Acceptance gate for every change

All the changes below keep the output pixel-identical, so reuse the existing gate: `tests/ppu_test.c` plus the 48 CRC
scripts and the Lua scripts on the host. Give each new fast path a plain-path twin that tests can switch to at run time
(the existing `rows == NULL` path is the model, `tile_row_shortcuts` the test pattern), so equality is checked pixel by
pixel on random scenes, not just by CRC.

---

## 4. Ranked optimisations for this renderer

Ranked by (expected gain x confidence) / effort. Gains are **[E]** and relative to the scene named; "mode 0" is the
4 layers + 128 sprites scene (2,074k cycles in the bench). Difficulty: S small (hours), M (a day or two), L (a week+).
"Host" = whether the logic can be tested without the board (all pixel-exact changes can; none of them can be timed there).

| # | Optimisation | Gain [E] | Effort | Risk | Host-testable |
|---|---|---|---|---|---|
| 1 | Measure `ppu_render` itself (section 3) | enabler | S-M | none | counters yes, cycles no |
| 2 | Per-file flags for `ppu.c`: `-O3`, `-funroll-loops` (try each alone) | 0-10% | S | low (IRAM grows) | CRC yes |
| 3 | Return early from `display_present_strips` | ~1 ms/frame of budget | S | low-med | no |
| 4 | Inner kernel diet: doubled palette, no `&255`, pre-ORed id tables, unrolled full-tile runs | 15-30% of BG cost | M | low | yes |
| 5 | Track `under` only for layers that can blend | 5-10% on FX frames | S | low | yes |
| 6 | Sprites: cull, per-line bitmask, row extents, RGB fast path | 5-12% (128 sprites); 3-4x on RGB sprites | M | low | yes |
| 7 | Dynamic line distribution between cores | 3-8% wall when audio is busy | S | low | yes |
| 8 | Direct RGB565 line for frames with no FX; bitmap rows as copies | 5-9% (no FX); 3-5x on bitmap layers | M | med (IRAM) | yes |
| 9 | Blend: 50% special case, SWAR when `eva + evb <= 16` | blend cost -50 to -80% | S | low | yes |
| 10 | Opaque occlusion: start from the topmost layer that covers the line | 0-60% by scene | M | med | yes |
| 11 | Window segments instead of a per-pixel test | window scenes: 10-25% | M | med | yes |
| 12 | Skip `ppu_render` when nothing changed | 100% on static frames | S-M | med (missed dirty path) | yes |
| 13 | Frame pipelining: ring depth, then a second world buffer | up to ~5 ms/frame headroom | M-L | high | no |
| 14 | 4 bpp tiles | 0 internal, ~3-10% PSRAM | L (format) | med | yes |
| 15 | Affine: hoist when `pc == 0`, fewer ops per pixel | affine -20 to -35% | M | low | yes |
| 16 | PIE for long spans only | situational | M-L | high | no |
| 17 | Fades by recomputed palette | fade-only passes -100% for indexed layers | M | med | yes |

### 4.1 Per-file compiler flags for `ppu.c` (#2)

ESP-IDF is built `-O2` (`CONFIG_COMPILER_OPTIMIZATION_PERF`) [V]. `ppu.c` already has the pragma
`no-tree-loop-distribute-patterns` [V]. Try, in `components/pinyol_core/CMakeLists.txt`, `set_source_files_properties(
ppu.c ... COMPILE_OPTIONS -O3)` and separately `-funroll-loops`, plus `-fno-tree-vectorize` (no vector unit in scalar
code, avoids surprises). Unrolling is the usual win on Xtensa for the 8-pixel runs, where the loop counter and the
branch are a visible share of an 8-instruction body. The cost is IRAM (12 KB today; every KB comes out of internal RAM)
and icache layout. Gain [E] 0-10%. Measure with the section 3 scenes; read the disassembly for `loopnez`.

### 4.2 Return early from `display_present_strips` (#3)

`display_present_strips` ends with `while (inflight--) spi_device_get_trans_result(...)`, so the caller blocks until the
last two strips (about 2 x 0.51 ms of wire [E]) are out, and only then does the next tick start. Make `inflight` static,
queue the last strips and return, and drain `inflight` at the start of the next present (and before `write_reg`,
`display_sleep`, `display_wait`). The strip buffers are not touched by the next frame's `_update`, `_draw` or
`ppu_render`, since those do not write `strip_buf`. Gain [E] ~1 ms per frame. Risk: every other SPI user must drain first;
`display_start_task`'s launcher path already uses its own idle semaphore. Firmware-only change.

### 4.3 Inner kernel diet (#4)

Today an opaque tile pixel is `pal[(tp[...] + bank) & 255] | id`, stored to `top[k]`, plus `under[k] = top[k]` when
tracking (`tile_run`, `ppu.c` 101-117). On an in-order Xtensa that is roughly: byte extract, add bank, mask, scale
index, load colour, OR id, store (and load+store for `under`) per pixel, plus loop control [E, check the disassembly].
Three cheap changes, each exact:

1. **A doubled palette.** `prepare()` copies `PPU.bg_pal` and `PPU.obj_pal` into 512-entry tables (`pal2[i + 256] = pal[i]`,
   512 B x 2, copy cost ~1k cycles per frame [E]). Then `(i + bank) & 255` becomes `pal2[i + bank]`, and better, a base
   pointer `pb = pal2 + bank` hoisted per tile run so the loop body is `pb[tp[k]]`. Index plus `16 * bank` is at most
   255 + 240 = 495 < 512. Rebuild every frame: `PPU.bg_pal` is written directly by `l_pal`/`palette_load`/`l_backdrop` in
   `lua_game.c` (lines 438-507), so a per-frame copy is the safe way to avoid a dirty flag. For sprites, `bank` is a
   `uint8_t`; use `(bank & 15) * 16`, which is identical modulo 256.
2. **Pre-ORed id tables on the tracked path.** When `F.track` is on, build `pal32[layer][512]` = `colour | layer << 16`
   (4 BG layers + OBJ, 5 x 2 KB = 10 KB, ~3k cycles per frame to build [E]). That removes the OR per pixel. Costs 10 KB of
   internal RAM: check `free internal` first.
3. **An unrolled kernel for full 8-pixel runs.** For an unaligned `scroll_x` only the first and last run of a line are
   partial; the 29 or 30 middle runs are full 8-pixel runs with `fx == 0`. Specialise that case: two aligned 32-bit loads
   of the tile row (tile base alignment must be guaranteed, see #14 and the alignment note in section 2), then 8 fully
   unrolled extract-lookup-store steps with the `rev` case as a separate instantiation, no counter, no per-pixel branch.
   Also handle the `bank == 0` case (the common one) without the base add.

Expected: per opaque pixel from ~8-9 to ~5-6 operations, so 25-35% of tile-kernel cycles [E]. BG tiles are ~75% of the
mode 0 scene, so ~15-25% of that scene [E]. Not gained for transparent pixels beyond the unroll, where the zero test is
a real branch. A further trick for the untracked, no-window path is to write two pixels per 32-bit store (alignment of
`x` parity complicates it: only worth it after #8).

### 4.4 Track `under` only for layers that can blend (#5)

`F.track` is frame-wide, so with an alpha effect on one layer (Plataformas: the water) all four layers and all sprites
pay two extra operations per pixel for `under[k] = top[k]`. The `under` value is read in `line()` only when the final top
pixel is a first target (`first & tb`) or an `OBJ_BLEND` sprite. A write by a layer that is not a first target can never
leave a useful `under`: either a later first-target layer overwrites it with `under = top`, or the layer's own pixel stays
on top and is not a first target, so no blend reads it. So pass `track && (first >> n & 1)` for BG `n`, and per sprite
`mode == OBJ_BLEND || (fx.mode == FX_ALPHA && first & PPU_OBJ)`. The backdrop `under` fill (240 stores per line) is still
needed. No new instantiations: the existing `(win, track)` pairs cover it. This should be bit-exact; prove it with the
CRC suite and a random-scene differential test against the current path. Gain [E] 5-10% of FX frames; in Plataformas
the layers are 0.3-1.0 ms each, so this is plausibly 0.2-0.4 ms.

### 4.5 Sprites (#6)

Costs in the current code [E from reading, not measured]:

- **The per-line visit of every sprite.** 128 sprites x 160 lines = 20,480 calls of the inlined `obj_line_x` front: load
  `affine`, `dbl`, `y`, `h`, compare. At ~8-12 cycles that is 160-250k cycles, 8-12% of the mode 0 scene, paid even when
  every sprite is off screen (only `!on` is culled by `prepare()`).
- **Off-screen sprites** are never rejected in `prepare()`. Reject any box fully outside `[0,240) x [0,160)`.
- **Per-line lists.** In `prepare()`, for each kept sprite, set bit `i` in a per-line `uint32_t[4]` mask for every line
  its box covers (sum of heights, ~2k writes for 128 16x16 sprites). Then per line and priority: `mask[y] & prio_mask[p]`
  and walk set bits high to low (index 127 is the back, drawn first). Memory: 160 x 16 B = 2.5 KB. This replaces the
  linear scan and keeps exactly the current draw order.
- **Row extents.** Compute per sprite row `[first_opaque, last_opaque]` once when a sheet is loaded (like
  `ppu_tile_rows` does for tiles; ~2 bytes per row). Trim the loop and skip empty rows. 10-25% fewer pixel visits for
  roundish sprites [E]. Sheets are `s->idx` frames of up to 255x255 (`sheet_get`); store the extents in the sheet.
- **An RGB565 fast path.** For `o->rgb`, `affine < 0`, no mosaic, there is no row fast path today: each pixel goes through
  `obj_pixel` (affine test, flip tests, `idx` test, `rgb` test, a mask bit test, plus `x - x % mw`, a divide, even for
  `mw == 1`). Copy the opaque run straight from `rgb + v * w`, with the mask read a byte at a time as `bitmap_row` does.
  [E] 3-4x on those sprites. Whether games hit this depends on whether they use runtime-asset sprites (editor "kit" games
  do, per `ppu.h`); the section 3 counter answers it.
- The `x % mw` for `mw == 1` can be removed in the general path too (`mw == 1` and `mh == 1` branch).

### 4.6 Dynamic line distribution (#7)

`render_part` gives core 0 the even lines and core 1 the odd lines. Core 1 also runs the audio mixer (priority 6, below
`part1` at 7 but still stealing time) and the idle presenter, so when music is busy `part1` finishes later and core 0
waits at `ulTaskNotifyTake`. Replace the fixed parity with a shared atomic line counter handed out in chunks of 2-4 lines
(a `fetch_add` per chunk, trivial next to ~13k cycles per line). Each core keeps its own `LB[part]`. Lines are
independent (every line is computed from `y` and the registers), so the output is bit-identical, and the host's serial
`hal_parallel` still works (core 0 just takes every line). Gain [E] a few percent of the picture time while audio runs,
zero otherwise. It also self-balances scenes whose cost varies by line (Mode 7 sky vs floor).

### 4.7 Direct RGB565 path for frames without FX (#8)

When `PPU.fx.mode == FX_NONE` and no `OBJ_BLEND` sprite exists, the layer id is never read: `line()` ends in the
"copy `top` to `out`" loop. Instantiate the layer functions once more with a `uint16_t *` line (no `id`, no `under`, no
final pass): draw straight into the output line and fill the backdrop as 32-bit pairs. Windows stay (they do not need ids).
Saves the 32-bit backdrop fill, the final 240-pixel pass and the width of every store. The Lua-game table says
"the rest (backdrop and copying out)" was 0.7 ms of Plataformas' 5.3 ms; some of that is this [E: 0.3-0.5 ms]. The larger
win is bitmap layers (the editor's games draw their map and pictures as bitmap layers): an opaque unmasked bitmap row
becomes a plain RGB565 copy, 240 pixels = 480 bytes, with no per-pixel `put`, and a masked row copies 0xFF mask bytes
8 pixels at a time. The ceiling is the PSRAM read of 76.8 KB per layer per frame: at the measured 84.7 MB/s (PSRAM ->
internal) that is ~0.9 ms per layer [E]; today a photo layer costs ~1 ms of cycles in the per-pixel `put` plus the read.
Costs more IRAM (a second set of instantiations, ~8-10 KB [E]). It does not help frames with alpha (the water in
Plataformas), which is why #5 comes first.

### 4.8 Blend (#9)

`blend()` in `ppu.c` unpacks three channels and multiplies each (6 multiplies, 3 clamps). The bench's own SWAR kernel
(`(c | c << 16) & 0x07E0F81F`, two multiplies) measured 25 cycles per pixel, so the generic path is probably worse
[E]. Two exact fast paths:

- `eva == evb == 8`, a common 50% (water, shadows): no multiply needed. Note `blend50` in `gfx_px.h`
  (`((a & 0xF7DE) >> 1) + ((b & 0xF7DE) >> 1)`) is **not** bit-identical to `(a * 8 + b * 8) >> 4`: it rounds each
  halved term down, so two odd channels lose 1. The exact form is `(a & b) + (((a ^ b) & 0xF7DE) >> 1)` (floor of the
  average per channel, no carry between fields): ~6 operations. Verify against `blend()` over all channel pairs in a host
  test before switching.
- `eva + evb <= 16`: no channel can exceed its maximum, so drop the clamps and use the SWAR form. The field layout of the
  mask has room for a 5-bit multiplier on each field (b 0-9, r 11-20, g 21-31), and the shift by 4 followed by the mask
  restores each channel exactly. Keep the current code for `eva + evb > 16`.

Gain [E]: blend work -50% to -80% (Plataformas: 0.5 ms -> 0.15-0.25 ms). Big alpha scenes, which the bench puts at a
quarter of a core for a full screen, move the most.

### 4.9 Opaque occlusion (#10)

Layers are painted back to front, so a layer hidden by an opaque layer above it is drawn for nothing; so are the backdrop
fill and lower sprites. `rows` already says per tile row whether it is opaque. A cheap probe on a line (31 map entries and
31 `rows[t] >> ty & 0x100` tests, ~200 cycles [E]) against a layer line of ~2,900 cycles [bench] pays when it hits.
Rules for exactness: no windows (or the line is wholly inside one window that shows the layer), no FX that reads `under`
or `drew` of lower layers (track off, or the lower layers are not second targets), and sprites of the same priority are
still drawn after the BG. Candidates: unmasked bitmap layers (known opaque without a probe, if they cover the line), full
opaque tile rows (panels, bag and notebook screens: 87% of the screen is opaque per `docs/measurements.md`), Mode 7 floors
(opaque below the horizon; `PPU_LINE_OFF` already handles the sky). Adaptive: probe a layer only if it was opaque on the
previous line, and a layer's opacity usually changes in runs. Gain [E] none on scrolling platformers, up to 50-60% on UI
or opaque-ground frames.

### 4.10 Windows as segments (#11)

With windows `put()` tests `L->show[x] & bit` for every pixel of every layer. Windows split the line into at most five
segments of constant `show`; draw each layer per segment with the segment's mask known at compile time per segment
(layer visible / hidden), as mGBA's window segments do (described, not copied). Hidden layers cost nothing, visible ones
lose the test. [E] 10-25% on window scenes. Needs care at the segment edges for tile runs; the existing differential test
(`ppu_test`) is the safety net.

### 4.11 Skip `ppu_render` when nothing changed (#12)

`G.world` persists between frames and `ppu_render` is a pure function of the PPU registers, the palettes, the sprite
table, the per-line tables and the tile/map/bitmap memory. If `memcmp(&PPU, &prev_PPU, sizeof PPU)` (~7 KB, ~10 us [E])
is equal and a generation counter of "data written" is unchanged, return without rendering. Pause screens, dialogue boxes
over a still scene and puzzle idle states are free. The risk is a missed write path: maps and tile data are
written through Lua APIs (`layer[i].map` is a per-layer copy), so every such API must bump the counter, and per-line
table pointers point into arrays Lua can edit. mGBA does the finer-grained version (per-line register snapshots with a
dirty bit set by VRAM, OAM and palette writes) [V from reading its description]; here the whole-frame check captures most
of the value for far less. Gain: 100% of the picture time on static frames, 0 otherwise.

### 4.12 Overlap CPU work with the DMA (#13)

Three steps, each valid alone:

- **P1 = #3** (about 1 ms).
- **P2: a deeper strip ring.** The CPU builds strips faster than the wire takes them (2.4 ms vs 8.1 ms) and then waits
  in `spi_device_get_trans_result`. Each 20 KB buffer is 0.51 ms of wire. A ring of N buffers lets the CPU finish
  `N - 2` strips earlier, so the same trick as P1 hides `(N - 2) x 0.51 ms` of the next frame's CPU work under the wire.
  RAM-bound: 4 buffers = 80 KB, about all the internal RAM left after the test content (89 KB [V from bench]). Smaller
  strips (16 columns = 10 KB) give the same depth in time per KB. [E] ~1 ms more.
- **P3: a second world buffer.** Strips read `G.world` and the recorded overlay list; if `ppu_render` for frame N+1 wrote
  a second 76.8 KB buffer during frame N's DMA, the picture time would leave the critical path (up to ~5 ms/frame
  of headroom [E]). `_draw` also resets the overlay command list (`draw_frame_begin`), so that list needs two copies too.
  Internal RAM is the constraint; PSRAM for the world costs 76.8 KB x write at ~48 MB/s (1.6 ms of write bandwidth) and
  the docs already record two cores fighting over PSRAM (Phase 1 of `docs/measurements.md`). Only worth it if games
  routinely exceed the ~11 ms CPU budget left by the serial model. Not before #1-#9.
- **Tick during the wait.** Lua `_update` (0.1-1.9 ms) does not write the PPU's recorded state; running the next tick
  inside the strip wait would hide it. [U] whether `_update` may call drawing APIs that touch the recorded list; check
  `lua_game.c` first.

TE and tear-free output: the strip scheme already is the double buffering. The panel scans at 16.3 ms per frame and
the strips arrive in 8.1 ms, so as long as the DMA starts inside the slack after the TE pulse the write head stays
ahead of the scan (`SCAN_START_US = 3000` in `display.c`). I computed that a start 3 ms after TE has the write behind the
scan at first and passing it ~6 ms in; the repo's comment says it is tear-free, which depends on the panel's porch and
scan start after the TE edge [U]. Worth checking on the board with a high-speed camera before relying on starting late.

### 4.13 4 bpp tiles (#14)

Tiles at 4 bpp halve the data (64 KB per 1024 tiles -> 32 KB) and the cache footprint; in PSRAM that is the 10-13% the
docs measured between internal and PSRAM, at most. The ALU cost is the same: Xtensa `extui` extracts a nibble in one
instruction just like a byte. The catch is the asset format: `tiles` is 8 bpp index data (`docs/game-format.md`), games
with more than 16 colours per tile would not fit, and `bank` semantics (`+ 16 * bank`) is already the GBA 4 bpp idiom, so
a per-tilemap `bpp` flag is the clean way. Format change plus tools (`tiled2asset.py`, `png2asset.py`). Low priority
unless PSRAM-resident tile sets show cache misses in `xtensa_perfmon`.

### 4.14 Affine (#15)

20.9 cycles per pixel in the bench; `ppu.c` does a mask, shift, two index computations and a map lookup per pixel
(the pow2 path, 195-212). When `pc == 0` (a horizontal scale/scroll with no rotation, per line in a Mode 7 table with a
fixed camera angle) `v` is constant along the line: hoist the map row pointer and the tile row offset out of the loop and
the body drops to `u`, `map[u >> 3]`, tile load, palette: ~35% fewer operations [E]. Not a general win (Mode 7 with a
rotating camera has `pc != 0`). For far lines, render every other pixel and duplicate: changes the output, so only as an
opt-in quality setting [E: -45% on those lines].

### 4.15 PIE (#16): only for long spans

PIE has no gather, a lazy-context cost, and 16-byte alignment rules, and Espressif's own blend code does not use it below
16 pixels. In this renderer the candidates are the unmasked long copies after #8: opaque bitmap rows and 64+ pixel wide
sprite rows, solid fills (the backdrop and `memset`-like `show` setup), `blend50` over a full line, and the
output-stage 2x (which is DMA-hidden, so no gain). Reuse the technique of `esp_lvgl_port`'s SIMD blend (aligned vector
loop, scalar head and tail by bit tests, `loopnez`) rather than designing one; read it, do not link it blindly: it is
written for LVGL's strides. Gain: internal-to-internal line copies at several times the scalar rate, but the bulk of
this renderer's time (8-px runs with a palette lookup) is out of reach. Do it last, and only after profiling says copies
dominate.

### 4.16 Fades by recomputed palette (#17)

mGBA keeps pre-brightened and pre-darkened palettes so a fade is a palette rebuild, not a per-pixel pass. Here the
fade-only pass is `fade(&L->fade, c)` per first-target pixel (~6 cycles [E], ~230k per frame). A fade of palette-indexed
layers could instead change `pal2` (512 entries) once per frame. It does not apply to `rgb` sprites and bitmap layers
(direct colour), so a hybrid is needed. A fade is a transition effect, not steady state; skip unless profiling shows fades
dominate a game.

---

## 5. What to leave alone (verified or reasoned)

- **PPA / 2D-DMA / DMA2D**: not on the S3 [V]. Nothing to use.
- **LCD_CAM i80/RGB**: the panel here is wired QSPI on SPI2; the peripheral is irrelevant.
- **Faster output stage**: DMA-bound (wire 7.68 ms). Its CPU (1.81 ms in the bench, ~2.4 ms measured with overlay) hides
  under the wire except for the first strip.
- **PIE for 8-pixel tile runs or palette lookups**: no gather, setup and lazy context costs exceed the work; see 4.15.
- **Hand-written assembly for the tile loops**: GCC with `always_inline` specialisation already gets 10 cycles/pixel;
  unrolled C gets most of what is on offer, and assembly kills the portable host build that gates every change.
- **Pre-baked RGB565 tile cache (mGBA-style)**: 128 B per tile per palette variant against ~89 KB of free internal RAM.
  Palette animation would invalidate it. Skip.
- **Cache prefetch tuning (`Cache_Start_DCache_Preload`, autoload)**: undocumented to me [U]; the whole PSRAM penalty
  measured is 10-13%, which bounds the gain.
- **Aligning tile data to 64 bytes**: one tile = one cache line, so a base misaligned by 4 B makes tiles straddle two
  lines. A real but small effect (a few % on PSRAM-resident sets [E]); do it only as a by-product (a
  `heap_caps_aligned_alloc` in `load_bytes` for tiles also fixes the 32-bit load alignment for #4).
- **Bigger SPI strips to save 0.2-0.4 ms**: costs 20+ KB of RAM per buffer. Not worth it.
- **RGB444 to cut wire time**: the wire is not the CPU bottleneck unless P3 pipelining exists, and the ST77922 12-bit
  mode is not confirmed [U]. Dirty-strip skipping needs a hash per strip and only helps static scenes (and the panel
  window x must be a multiple of 4).
- **Full-frame double buffers in PSRAM**: tried and measured as slower in this repo (two cores fighting over PSRAM).
- **Splitting the picture top/bottom between cores**: even/odd lines balance better; #7 balances further.
- **120 MHz octal PSRAM**: not available without experimental IDF options [V].
- **NanoBoyAdvance-style per-layer line buffers plus a compose pass**: an extra pass over 240 pixels per layer per line,
  and it does not fit this code's `top`/`under` scheme. (I could not fetch its source to describe it; this is from
  memory [U].)
- **`esp_async_memcpy` / GDMA to prefetch tiles**: random 8-byte tile-row reads, IDF documents low PSRAM DMA bandwidth,
  and a forum thread reports GDMA async copy problems with PSRAM [U].

Outside the PPU but cheap to try: `CONFIG_SPIRAM_XIP_FROM_PSRAM` (IDF says it can improve performance) could speed the
Lua VM and engine code that runs from flash through a 32 KB icache [U gain]; and adding the hot `gfx_upscale2x` /
`shade_run` code to the same `ppu_inside` IRAM scheme in `linker.lf` helps the first strip only.

---

## 6. Techniques in other renderers (what applies here)

- **mGBA software renderer** (read-only, described): a 32-bit word per pixel with colour and flag bits (the same shape as
  `PX`); window segments; a sprite list built when OAM changes, culled by Y per line; pre-brightened/darkened
  palettes for fades; a per-line cache of the registers with a dirty flag so an unchanged line is reused; an
  "unwritten" flag so already-final pixels are skipped. Applicable: window segments (#11), per-line sprite lists (#6),
  palette-based fades (#17), the frame-level form of line reuse (#12). Not found in what I read: a whole-layer
  occlusion test, so #10 is ours to design.
- **ESP32 NES/Game Boy emulators** (`esp32-nesemu`, gnuboy ports on the original ESP32): render a line at a time into
  a small buffer with a palette, push to the SPI display by DMA from the other core. The same split as this firmware's
  strips, so nothing new; the lesson is to keep the DMA fed without the CPU waiting, which is #3 and #13.
- **LVGL on ESP32-S3**: its S3 SIMD blend lives in `esp_lvgl_port` (not in LVGL core), for fills and RGB565
  blends with scalar heads and tails. That is the model for #16.
- I found no public GBA-class renderer running on the S3 to compare against. Numbers for "how fast can it be" would have
  to come from the board.

---

## 7. Suggested order

1. #1 measurement (bench scenes on the real `ppu_render` + counters + a baseline table on the 5 heaviest games).
2. #2 flags and #3 early return (hours, independent, immediate numbers).
3. #4 kernel diet and #5 per-layer tracking (the BG and FX frames), #9 blend fast paths.
4. #6 sprites, #7 dynamic lines.
5. #8 direct path, then #10, #11, #12 depending on what the games turn out to need.
6. #13 pipelining only if frames still miss 16.6 ms after the above.

Each step: run `ppu_test` and the CRC scripts, bench the section 3 scenes, record before/after in
`docs/measurements.md`.

## 8. Open questions (all unverified here)

1. How does `ppu_render` compare with the synthetic bench kernel? (3.1 #8.)
2. Does `_update` write anything the strips read, so a tick can run during the DMA wait?
3. Do the games hit the RGB-sprite `obj_pixel` path or the indexed fast path? (3.2 counters.)
4. Does GCC emit `loopnez` for the tile loops, and what is the real instruction count per pixel?
5. S3 cache autoload/preload: on by default? any gain on tile misses? (`xtensa_perfmon` event IDs.)
6. Tear-free margin of `SCAN_START_US = 3000` against the ST77922 scan start after the TE edge.
7. Does the LX7 trap on misaligned 32-bit loads here, and what alignment does `read_file` give the tile data?
8. Is there a vector table-lookup instruction in PIE that would change the palette-lookup cost? (TRM PIE chapter.)

## 9. Sources

Fetched or searched in this session (2026-10-19). Forum threads are informal; several esp32.com pages answered with a
bot-check page and were used only through search snippets.

- Espressif, PIE introduction (P4-focused, same design): https://developer.espressif.com/blog/2024/12/pie-introduction/
- Espressif esp-bsp, `esp_lvgl_port` SIMD sources for ESP32-S3:
  https://github.com/espressif/esp-bsp/tree/master/components/esp_lvgl_port/src/lvgl9/simd
- Espressif esp-dsp, `dsps_memcpy_aes3.S` / `dsps_memset_aes3.S`:
  https://github.com/espressif/esp-dsp/tree/master/modules/support/mem/esp32s3
- ESP-IDF, Support for External RAM (S3): https://docs.espressif.com/projects/esp-idf/en/v5.5/esp32s3/api-guides/external-ram.html
- ESP-IDF, SPI Master driver (S3): https://docs.espressif.com/projects/esp-idf/en/v5.5/esp32s3/api-reference/peripherals/spi_master.html
- ESP-IDF, Memory Types (S3): https://docs.espressif.com/projects/esp-idf/en/v5.5/esp32s3/api-guides/memory-types.html
- ESP-IDF, PPA (ESP32-P4 only; the S3 page is 404): https://docs.espressif.com/projects/esp-idf/en/v5.5/esp32p4/api-reference/peripherals/ppa.html
- LVGL, DMA2D support (names ESP32-P4): https://lvgl.io/docs/open/integration/chip_vendors/espressif/hardware_accelerator_dma2d
- ESP-IDF, Performance Monitor (S3): https://docs.espressif.com/projects/esp-idf/en/v5.1/esp32s3/api-reference/system/perfmon.html
- ESP-IDF, Memory Synchronization (cache coherence for DMA): https://docs.espressif.com/projects/esp-idf/en/v5.5/esp32s3/api-reference/system/mm_sync.html
- Hackaday, PIE max-pool/conv kernels on the S3 (instruction names, 16-byte layout): https://hackaday.io/project/196067/logs
- Forum, `ee.vld.128.ip` trap: https://esp32.com/viewtopic.php?p=104226
- Forum, Q registers across context switches (lazy PIE switching): https://esp32.com/viewtopic.php?p=148868
- Forum, S3 PSRAM copy bandwidth, cache line size query: https://esp32.com/viewtopic.php?p=123419
- Forum, zero-overhead loops and inline asm on the S3: https://esp32.com/viewtopic.php?p=141735
- Espressif `esp_lcd_st77922` readme (x multiple of 4, 3Ah pixel formats):
  https://components.espressif.com/components/espressif/esp_lcd_st77922/versions/2.1.1/readme
- ST77922 SPEC V0.1: https://dl.espressif.com/AE/esp-iot-solution/ST77922_SPEC_V0.1.pdf (title seen; command table not read)
- mGBA software renderer, read only for technique: https://github.com/mgba-emu/mgba/blob/master/src/gba/renderers/video-software.c
- Espressif NES emulator for ESP32: https://github.com/espressif/esp32-nesemu
- Repo files read: `src/ppu.c`, `src/ppu.h`, `src/lua_game.c`, `src/gfx.c`, `src/gfx_px.h`, `src/hal.h`,
  `firmware/main/{main,display,bench}.c`, `firmware/sdkconfig.defaults`, `firmware/components/pinyol_core/linker.lf`,
  `docs/measurements.md`, `docs/hardware.md`, `tests/ppu_test.c`.
