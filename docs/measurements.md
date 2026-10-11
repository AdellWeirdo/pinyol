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
