# Measurements on the board

What the pieces of a GBA-like software renderer cost on the RetroGo console (ESP32-S3R8 at 240 MHz, octal PSRAM at
80 MHz, ST77922 over QSPI at 80 MHz). Measured on 2026-10-11 with `firmware/main/bench.c`:

```sh
cd firmware && idf.py -DBP_BENCH=ON build flash monitor     # lines start with "BENCH"
```

The kernels are plain C on synthetic content: 240×160 logical frame of 8-bit palette indices, 8×8 tiles at 4 bpp,
64×64-tile maps, 16×16 sprites at 4 bpp, an 8 bpp affine map with a per-line perspective table. Cycles are the best
of five runs. One core has 4.0 M cycles per frame at 60 fps.

## Rendering one logical frame (one core)

| Scene | Cycles | ms | Share of a core at 60 fps |
|---|---|---|---|
| Clear only | 25 k | 0.10 | 0.6 % |
| 1 regular layer | 471 k | 1.96 | 11.8 % |
| 4 regular layers | 1,561 k | 6.50 | 39.0 % |
| 4 regular layers, tiles and maps in PSRAM (160 KB) | 1,719 k | 7.16 | 43.0 % |
| same, cold cache | 1,765 k | 7.35 | 44.1 % |
| 128 sprites 16×16 | 538 k | 2.24 | 13.5 % |
| 1 affine layer, full screen | 801 k | 3.34 | 20.0 % |
| Light: 2 layers + 32 sprites | 966 k | 4.03 | 24.2 % |
| GBA mode 0: 4 layers + 128 sprites | 2,074 k | 8.64 | 51.9 % |
| Mode 7: affine + 1 layer + 64 sprites | 1,507 k | 6.28 | 37.7 % |
| Max: affine + 4 layers + 128 sprites | 2,850 k | 11.88 | 71.3 % |
| Alpha blend of two RGB565 frames | 967 k | 4.03 | 24.2 % |

## Getting it to the panel

| What | Result |
|---|---|
| SPI clock asked / set | 80,000 / 80,000 kHz |
| Panel refresh (TE, one pulse per frame) | 61.5 Hz; the init's TE mode also pulses every line (29.4 kHz) |
| v1: 480×320 RGB565 frame in PSRAM → panel | 9.45 ms |
| Output stage alone: 240×160 indexed → palette, 2×, transpose, byte swap into 15 strips | 1.81 ms of CPU |
| v2: 240×160 indexed in internal RAM → panel | 8.10 ms (the wire alone is 7.68 ms) |

Two cores, core 1 drawing frame N+1 while core 0 sends frame N, no TE sync (frames as fast as they come):

| Scene | fps | Core 0 CPU on the output stage |
|---|---|---|
| GBA mode 0: 4 layers + 128 sprites | 113.6 | 1.91 ms a frame |
| Mode 7: affine + 1 layer + 64 sprites | 123.1 | 1.86 ms |
| Max: affine + 4 layers + 128 sprites | 83.2 | 1.88 ms |

## Memory and storage

| What | Result |
|---|---|
| memcpy internal → internal | 381 MB/s |
| memcpy internal → PSRAM (1 MB) | 48.5 MB/s |
| memcpy PSRAM → internal (1 MB) | 84.7 MB/s |
| memcpy PSRAM → PSRAM (1 MB) | 31.9 MB/s |
| Free internal RAM at boot (largest block) | 274 KB (180 KB) |
| Free internal RAM after the test content and two logical frames | 89 KB |
| microSD reads, 64 KB / 8 KB / 512 B chunks | 11.3 / 11.2 / 9.9 MB/s |

## What this settles

- **60 fps fits with room to spare.** The heaviest scene takes 71 % of one core; core 0 spends under 2 ms of CPU a
  frame on the output stage and is otherwise free for game logic and audio while the DMA runs.
- **Tiles and maps can live in PSRAM.** Reading them from there costs 10-13 % more than from internal RAM, so no
  hot-tile cache is needed; internal RAM stays for the two logical frames, the strips and the system.
- **Sending a frame is bound by the wire** (8.1 ms for 7.7 ms of bits) and fits inside the panel's 16.3 ms refresh,
  so presents can start on the TE frame pulse for tear-free output (TE must be switched to frame-only mode).
- **Alpha blending is the expensive effect** (a quarter of a core for the whole screen): keep it to marked layers.
- The v1 engine's 30 fps comes from drawing 480×320 frames in PSRAM (writes at 48.5 MB/s), not from the panel.

Not measured yet: audio mixing and Lua running at the same time, TE-synced presents, real game content.

## Phase 1: drawing straight into the panel strips (2026-10-11)

The v1 engine drew a 480×320 frame in PSRAM and sent it, drawing every other tick (30 fps). Drawing every tick only
reached 46-60 fps, because one core writing that frame and the other reading it to send fought over PSRAM.

Now there is no 480×320 frame on the console. Each 32-row panel strip (32 frame columns) is drawn straight from the
game into internal RAM, already turned and byte-swapped (`gfx_turned`), while the previous strip goes out by DMA; the
zone is drawn into `G.world` once a frame. Every pixel is the same as drawing the whole frame: all 48 test scripts of
Bajo Pueblo and Geumgye give the same CRC as the previous engine on all 72,600 frames, and with `--check-strips` every
frame is also drawn as strips (both orientations, both byte orders) and compared.

Real play on the board, end-to-end tests, frames drawn as fast as they come (`-DBP_BENCH=play`):

| | Drawing every tick, v1 | Strips |
|---|---|---|
| Bajo Pueblo, 5 s windows | 25-60 fps | 43-73 fps (the low ones: bag and dialogue screens) |
| Geumgye, 5 s windows | 46-56 fps | 57-74 fps |
| The bag open | 31 ms a frame | 20 ms |
| Bag and dialogue | 48 ms | 45 ms |

What made the strips fast enough, measured per frame: the 2× upscale written as 32-bit pairs down each panel column
(8.9 → 2.0 ms), fills and shades the same way (a shade on swapped bytes is a mask and a one-bit rotation), cut-corner
panels filled as one rectangle between the corners, and the current objective looked up once a frame instead of once
per strip. Still over 16.7 ms: dialogue, bag and puzzle screens (about 20 ms); the zone itself takes up to 4.5 ms in
Bajo Pueblo.

## Lua games on the PPU (2026-10-12)

The three Lua examples on the board, autotest builds (`-DBP_AUTOTEST=ON`, a perf line every second). "Picture" is
`ppu_render`, the 240×160 frame from layers and sprites; the strips and their DMA (~8 ms, overlapped) come after it.

| | Picture, first try | Now | Frame rate now |
|---|---|---|---|
| Carreras (Mode 7 floor, horizon layer, 4 scaled sprites) | 10.3 ms | 3.3 ms | 60-61 fps |
| Naves (star parallax per line, turning planet, blended explosions) | 15 ms | 2.8 ms | 60-61 fps (53 with a bomb flash) |
| Plataformas (4 layers, see-through water) | 25 ms | 5.3 ms | 61 fps |

Plataformas with its layers taken away one by one (a bench script): blending 0.5 ms, BG3 0.6-0.8, BG2 0.7-1.0,
BG1 0.6, BG0 0.3, sprites 0.1-0.2, the rest (backdrop and copying out) 0.7. Lua itself: `_update` 0.1-1.9 ms,
`_draw` about 1 ms.

What it took, in order of what it gave:

1. The PPU's code in IRAM and its data in internal RAM (`linker.lf`, scheme `ppu_inside`), and 32 KB of instruction
   cache instead of 16: from flash, the PPU, the Lua VM and the drawing code kept evicting each other. About 2×
   on everything, Lua included.
2. Both cores: even lines on core 0, odd lines on core 1 (`hal_parallel`). 1.6-1.9×.
3. No `memmove` in the inner loops: GCC turned the 8-pixel "top goes under" copy of blended frames into a call to
   ROM `memmove` per tile row, 10,000 calls a frame, 4 ms. `-fno-tree-loop-distribute-patterns` for ppu.c.
4. The layer loops in four copies (windows or not, blending or not) so the inner loops carry no tests they do not
   need; tile rows known empty skipped, rows known opaque copied without tests (`ppu_tile_rows`); colour and layer
   packed in one word per pixel.
5. Affine layers that do not wrap only walk the span of each line inside the map; mosaic samples once per block;
   fades through per-channel tables; lines with nothing for the blend to touch are copied straight out.

All of it pixel-identical: the 48 Bajo Pueblo and Geumgye scripts and the four Lua scripts give the same CRC on every
frame, and `tests/ppu_test.c` checks the shortcuts against the plain path and the clipped affine path against the
formula on 200 random matrices.

## The bag screens (2026-10-12)

Bajo Pueblo and Geumgye's bag and notebook are opaque panels over 87% of the screen. Drawing the zone (scaled 2×),
the layers below and the shade only in the four bands around the panel's middle (`game_draw`, `gfx_clip`), per
screen with the strips (`-DBP_BENCH=v1`):

| Screen | Before | After |
|---|---|---|
| Bajo Pueblo, the bag | 14.7 ms | 10.4 ms |
| Bajo Pueblo, the bag with a dialogue | 20.2 ms | 14.2 ms |
| Geumgye, the bag | 13.9 ms | 9.9 ms |

Then the same for the whole layer stack (each layer says which opaque panels it leaves; the zone and the shades are
drawn only where they show, the panel layers whole) and a 2× blit that writes whole blocks on the strips:

| Screen | Before tonight | Now |
|---|---|---|
| A dialogue | 7.9 ms | 7.6 ms |
| An item's close-up | 14.8 ms | 11.6 ms |
| A close-up over the bag | 27.2 ms | 18.5 ms (still ~30 fps) |

Pixel-identical on the 48 scripts. The close-up over the bag would need the bag drawn only around the card, which
costs more than it saves while the bag lays its text out again for every piece.

## A game made with the editor (2026-10-13)

The editor's platformer template (a `kit` game: the map is one canvas drawn as a bitmap layer, objects are sprites,
the labels and messages are styled text), built by `editor/test/build_game.mjs` and played on the board by an
autotest script: walking with the camera, jumping, a coin's sparks, the lose and win messages.

| Part | Frame rate | Strips |
|---|---|---|
| Walking, jumping, a coin | 60-61 fps | 2.4 ms |
| The lose and win messages over the game | 58-61 fps | 4.4-6.5 ms |
