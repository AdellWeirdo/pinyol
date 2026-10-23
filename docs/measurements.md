# Measurements on the board

What the pieces of a GBA-like software renderer cost on the Cirera console (ESP32-S3R8 at 240 MHz, octal PSRAM at
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
| Panel refresh (TE, one pulse per frame) | 61.5 Hz then (61.14 Hz at RTN 1A0h on 2026-10-20); now calibrated to 60.00 at the start (`display.c`). The init's TE mode also pulses every line (29.4 kHz) |
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
two pinyol@1 adventures (A and B, games of their own) give the same CRC as the previous engine on all 72,600 frames, and with `--check-strips` every
frame is also drawn as strips (both orientations, both byte orders) and compared.

Real play on the board, end-to-end tests, frames drawn as fast as they come (`-DBP_BENCH=play`; each test is on the card,
`/sdcard/pinyol_bench/<game id>.script`, played on `/sdcard/games/<game id>`):

| | Drawing every tick, v1 | Strips |
|---|---|---|
| Adventure A, 5 s windows | 25-60 fps | 43-73 fps (the low ones: bag and dialogue screens) |
| Adventure B, 5 s windows | 46-56 fps | 57-74 fps |
| The bag open | 31 ms a frame | 20 ms |
| Bag and dialogue | 48 ms | 45 ms |

What made the strips fast enough, measured per frame: the 2× upscale written as 32-bit pairs down each panel column
(8.9 → 2.0 ms), fills and shades the same way (a shade on swapped bytes is a mask and a one-bit rotation), cut-corner
panels filled as one rectangle between the corners, and the current objective looked up once a frame instead of once
per strip. Still over 16.7 ms: dialogue, bag and puzzle screens (about 20 ms); the zone itself takes up to 4.5 ms in
adventure A.

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

All of it pixel-identical: the 48 scripts of adventures A and B and the four Lua scripts give the same CRC on every
frame, and `tests/ppu_test.c` checks the shortcuts against the plain path and the clipped affine path against the
formula on 200 random matrices.

## The bag screens (2026-10-12)

The adventures' bag and notebook are opaque panels over 87% of the screen. Drawing the zone (scaled 2×),
the layers below and the shade only in the four bands around the panel's middle (`game_draw`, `gfx_clip`), per
screen with the strips (`-DBP_BENCH=v1`; the screens are listed on the card, `/sdcard/pinyol_bench/<game id>.v1`,
format in `firmware/main/bench.c`):

| Screen | Before | After |
|---|---|---|
| Adventure A, the bag | 14.7 ms | 10.4 ms |
| Adventure A, the bag with a dialogue | 20.2 ms | 14.2 ms |
| Adventure B, the bag | 13.9 ms | 9.9 ms |

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

Then the editor gained pictures behind the map (bitmap layers that repeat, moving slower than the camera), and the
first measure was bad: each such layer cost about 4 ms of picture, the template with its hills fell to 40 fps and
a game with a photo behind the hills to 30. A repeating bitmap layer worked its column out per pixel with a
division, and tested its mask bit by bit. Now the column steps and wraps at the bitmap's edge, and the mask skips
or copies eight pixels a byte at a time (`bitmap_row` in ppu.c; pixel-identical on every script, and
`tests/ppu_test.c` checks it against the formula on 120 random bitmaps):

| Game | Picture before | Picture now | Frame rate now |
|---|---|---|---|
| The template: map, hills behind it | 7.6-8.2 ms | 2.4-2.6 ms | 60-61 fps |
| An imported photo behind the hills and the map | 12.2 ms | 3.4-3.6 ms | 59-61 fps |

The map itself is a bitmap layer, so it gained too: the template's picture was 4.2 ms before it had hills.

The editor's four templates and a game with music from files, each played on the board by its test script
(autotest, tests/editor_*.script): all pass, 0 audio underruns.

| Game | Frame rate playing | Picture |
|---|---|---|
| Plataformas (two levels, hills behind) | 60-61 fps | 1.9-2.3 ms |
| Aventura desde arriba (20 x 12 maps, chasing ghosts) | 60-61 fps | 2.2-2.6 ms |
| Naves (two star fields drifting, saucers, comets) | 60-61 fps | 2.2-2.5 ms |
| Puzle de cajas | 60-61 fps | 1.9-2.2 ms |

Starting a game takes 0.3-0.5 s (its pictures, fonts and made sounds); starting a level, one frame of about 45 ms
(its map painted into the map canvas) while its name shows.

## A Neo Geo scene (2026-10-13)

Can the console draw what a Neo Geo fighting game draws, every pixel at 480x320? `tests/games/neo.lua` is that
scene: a sky, two layers wider than the screen moving at their own speeds, two big fighters walking and striking,
one mirrored; the benchmark adds a camera zoomed to 1.25 and six fighters. Its first pictures were drawn by code
(layers 960 pixels wide, fighters of 128x192 in eight frames). Every step below draws the same frames (packed and
plain pictures give the same CRC on every frame):

| Step | Frame rate | Strips |
|---|---|---|
| Plain pictures (RGB565 and a mask) | 20 fps | 38-47 ms |
| Packed pictures: a palette each, columns of opaque runs | 30 fps | 23.6-28 ms |
| The palette copied to internal memory per picture, 4-bit pixels two at a time, each strip drawn in two halves, one on each core | 60-61 fps | 10.4-12.9 ms |

The plain pictures were limited by PSRAM: about 40 MB/s read through a 64 KB cache, and a full-screen scene in two
layers reads more than that at 60 fps.

Then the scene took `examples/duelo`'s art: a sky and city 640 pixels wide, a pier and crowd in front, fighters of
192x184 in eleven frames. Packed, its pictures take 528 KB instead of 2.2 MB.

Zoomed (`scale = 1.25`), the fighters first went through the cache of turned pictures, each frame scaled once and
kept: eleven frames of two fighters at 240x230 did not fit its 1.5 MB, so it made them again every frame (40-45 fps,
frames of 28 and 52 ms). A packed picture scaled but not turned is now drawn straight from its runs, each run
landing on the screen rows worked out from its ends (`gfx_blit_scaled`), the same pixels as before:

| Scene (the art of examples/duelo) | Frame rate | Strips |
|---|---|---|
| The stage alone | 61 fps | 7.4 ms |
| Two fighters | 61 fps | 6.7 ms |
| Two fighters at 1.25 | 61 fps | 8.9 ms |
| Six fighters | 61 fps | 8.3 ms |
| `examples/duelo`: the title (styled text, both fighters) | 60-61 fps | 8.8 ms |
| `examples/duelo`: a fight (sparks, hit flashes, the HUD) | 61 fps | 7.3 ms |

The strips take about half of each frame's 16.6 ms: room for a third layer, more fighters, or effects.

## The Neo Geo's genres (2026-10-13)

Of the Neo Geo's 156 games, by genre: fighting 55, sports 23, shoot-em-ups 15, puzzle 14, run and gun 10, quiz and
mahjong 10, beat-em-ups 8, platform 7, first person 4, racing 4, maze 3, other 3. One example for each genre that asks
a lot of the console, with original generated art, all at 480x320 from packed pictures, each measured on the board
by a script that plays it and loads it on purpose (`examples/<id>`, the scripts in the session's notes):

| Game | Scene | Frame rate | Lua (tick + draw) | Strips |
|---|---|---|---|---|
| asalto (run and gun) | running and firing | 61 fps | 1.4-2.0 ms | 6.0 ms |
| | 20 robots on screen, all firing | 61 fps | 3.4 ms | 7.7 ms |
| | the walking tank, robots, shells | 61 fps | 3.5 ms | 7.2 ms |
| nubes (shoot-em-up) | waves of drones | 60-61 fps | 2.9 ms | 5.7 ms |
| | the battleship's rings and spirals | 56-61 fps | 3.6 ms | 6.8 ms |
| | 300 orbs more (a swarm) | 61 fps | 2.3 ms | 8.5 ms |
| calle (beat-em-up) | Kai and six thugs, everyone at 0.8 | 60 fps | 2.3 ms | 9.7 ms |
| futbol (sports) | five a side | 61 fps | 3.8 ms | 5.1 ms |
| | eleven a side | 60-61 fps | 5.3 ms | 4.8 ms |
| moto (racing) | a race: Mode 7 road (2.8 ms) and full-resolution coast, roadside, rivals | 53-60 fps | 4.3 ms | 5.3 ms |
| | the four rivals all on the player's own place | 44-55 fps | 4.5 ms | 6.3 ms |

What it took, each step measured on the same scenes:

- **Pictures past a budget are let go** and come back from the card (4 MB, least recently drawn first): a game's
  art may be bigger than the console's memory.
- **No world when none shows.** With `show(0)` the 240x160 world was still worked out (0.7 ms) and doubled into every
  strip; now it is one colour, filled (0.8 ms a frame saved in every full-resolution game).
- **Strips skip what is not theirs.** Each drawing command notes the 32-column bands it may touch; with 450 commands,
  the strips went from 12.4 to 9.3 ms.
- **Swarms.** 300 orbs moved and drawn from Lua cost 9 ms (some 10 us each to move and as many to draw); as a swarm
  (`swarm()`, moved, tested and drawn in C), 2.3 ms: 30 fps became 61.
- **`img` reads its options in one walk** over the table instead of nine lookups.
- **Scaled pictures divide in 32 bits.** Each run of each column of a scaled packed picture worked out its rows with
  two 64-bit divisions, which the console does in software: in 32 bits it divides in hardware.
- **The two cores split each strip into its left and right columns**, not its top and bottom: a game's work is rarely
  even between the sky and the ground, nearly always between two neighbouring bands. Six thugs went from 43-55 fps
  to 60, eleven a side from 46-49 to 61.

Lua is what is left: on the console, each thing moved and drawn from a script costs some 50 us, so about 60-70 of
them a frame, besides any number in swarms. The strips take 5 to 10 ms of the 16.6.

## The looks on the console (2026-10-14)

Each look's example played on the board by its own perf script (autotest builds, a perf line a second). First the
numbers as written, then after what the board showed was fixed.

| Example (look) | First | Now | What it took |
|---|---|---|---|
| torneo (CPS2: a floor drawn in 36 bands of rows) | 60-61 | 60-61 | nothing: the bands are a plain picture's rows |
| mazmorra (CPS2), rocas (vector), bolsillo (Game Boy), huevos (LCD) | 60-61 | 60-61 | nothing |
| cinta (Spectrum) | 49-61 | 49-61 | (the tape's colour phase dips to 42 a moment) |
| ladrillos (PICO-8) | 46-55 | 56-60 | the bricks on a canvas of their own, drawn again when one breaks, not 120 rectangles a frame |
| veloz (16-bit) | 40-59 | 40-59 | its far layers as tiles, not bitmaps; the sea's per-line scroll and the blended pools are what is left |
| gotico (32-bit) | 31 | 59-61 | a shared buffer raced between the two cores (a heap assertion: fixed); mixing in the packed blit itself, one multiply a pixel; the moonbeams mixed into the background by make_art.py |
| laberinto (first person) | 20-31 | 38-60 | raycast() draws in bands of 16 columns in internal memory, copied to the canvas a row at a time (the canvas is in PSRAM: a pixel per row was most of it); a 240×144 view |
| tormenta (vertical) | 20 | 60-61 | a 160×240 canvas shown twice as big (clearing a 320×480 one was 18 ms a frame); a right-angle turn's row worked out once a line. Then the turn's inner loops split by direction, with the picture's row, its mask row and the byte swap taken out of the per-pixel work (strips 20.4 → 11.8 ms), and two consecutive lines that read the same picture row done in one pass when the picture is shown twice as big (→ 6.4 ms; `gfx_blit_ex`, pixel-identical on every script) |

Costs worth knowing when making a game: a pixel mixed with what is under it (img's alpha or add) costs about three
drawn plainly, so a few big see-through pictures fill a frame; writing a whole canvas in PSRAM costs about 1 ms per
10,000 pixels written one at a time; a 240×160 canvas shown twice as big is cheap (15.5 ms a frame including
everything else, at 60).

## The next frame while the last strips go out (2026-10-17)

`display_present_strips` used to wait for the last strip to leave before returning, so the next frame's tick and
picture started only after the 8 ms of wire. A frame of 9.5 ms of work and 7.4 ms of strips (veloz) came to 16.9 ms,
a little over the panel's 16.26 ms, and missed one scan in two. It now returns once the last strip is queued: that
strip and the one before it still go out by DMA, from the two strip buffers, which nothing in the game feeds any more,
and the next present (or any register write) collects them. About 1 ms of the wire now overlaps the next frame's work.
Same board, autotest builds, the frame rate in each 5 s window of the test, the lowest ones:

| Game | Before | After |
|---|---|---|
| veloz (playing) | 39.5-45.8 | 49.7-56.2 |
| plataformas | 27.6, 37.9 | 38.6, 41.4 |
| laberinto | 37.9-49.3 | 39.5-55.6 |
| cinta (the tape's colour phase) | 39.3, 47.7 | 41.9, 49.7 |
| gotico | 52.9 | 56.9 |
| moto, duelo | 59-61 | 59-61 |

veloz is not at 60 yet: its tick (1.2 ms) and picture (5.9 ms, of which the PPU is most) plus 7.4 ms of strips still
come to about 17 ms. A third strip buffer would give another half millisecond, but internal RAM has 44 KB free.

## PlayStation / Saturn features on the board (2026-10-17)

On a Cirera, firmware from `psx-saturn-engine`, one scene at a time (`tools/send_game.py game --log 8` prints the perf lines;
a scene is a black screen plus the one thing). "Strips" is the CPU time to draw the whole 480x320 frame (an empty frame is
1.5 ms; 60 fps wants the sum under about 12).

| Scene | Pixels | Strips |
|---|---|---|
| a gradient, 480x118, dithered | 56k | 3.6 ms (about 37 ns a pixel) |
| a gradient, 480x202, dithered | 97k | 5.3 ms |
| the same two before their loops had no division (`grad`) | | 11.2 and 18.0 ms |
| six quads, a carpet in perspective, plain | 44k | 6-7 ms (about 150 ns a pixel) |
| the same, lit by a colour a corner | 77k | 33 ms (about 400 ns) |
| the same, lit and dithered | 77k | 35 ms |
| the same, see-through (alpha) or added | 77k | 29 / 34 ms |
| a sign (lit, dithered) and a banner | 8k | 2.7 ms |
| three glows scaled 2x, added, taken away, a quarter | | 4.4 ms |

What the table says: a plain quad is about 21 instructions a pixel on the LX7 and no more can be taken out; lighting each pixel
(three multiplies, the dither and the clamps) is about 250 ns more. A quad is for what is not the whole screen: signs, props,
a carpet, a boss that bends. A floor that fills the screen belongs on the PPU's affine layer (`mode7()`, `examples/carreras`),
which does it at 60 fps. Two things were found only here: `grad` had a 64-bit division a pixel (software, dozens of cycles:
now a table of the ramp's colours, 3x faster), and a quad's columns are short in bands, so the work a column takes to set
up (now stepped with integers, no divisions) counted as much as its pixels.

Sound, eight to twelve looping ADPCM voices (a clip kept as blocks, decoded as it plays) with an envelope and a pan each, the
rest of the frame an empty one at 60 fps and no new underruns:

| | Share of one core |
|---|---|
| nothing playing | 3 % |
| 8 voices, no reverb | 17 % |
| 8 voices through the Hall reverb | 24 % |
| 8 voices through Space Echo (the biggest ring, 63 KB in PSRAM) | 24 % |
| 12 voices through Space Echo | 31 % |

A voice costs about 1.8 %, the reverb about 7 % whatever the room.

## Lights, line effects, perspective, clips (2026-10-17)

The same way (one thing on a black screen; 1.5 ms of strips is the empty frame):

| Scene | Strips |
|---|---|
| `light` radius 60 | 3.6 ms (about 200 ns a pixel it reaches) |
| `light` radius 100 | 7.7 ms |
| the same as a beam 60° wide | 4.4 ms |
| the same taking light away (`sub`) | 7.8 ms |
| four lights of radius 60 | 10.6 ms |
| a packed background 480x320 | 5.0 ms |
| the same with `dim = 0.4` or `mul = 0x8090FF` | 5.0 ms: free |
| `warp` of that background, every row moved | 18.9 ms (about 110 ns a pixel), and 4 ms of Lua for the 320 rows' function |
| `linetint` over the whole screen, added | 34.5 ms before it made each row's colour ready once (`gfx_lines`), then 12.3 ms |
| a quad 480 wide, a floor going away, flat | 8.2 ms |
| the same with `persp = true` (6 bands) | 17.4 ms with affine cells; 10.8 ms now, perspective-correct (U/w, V/w, 1/w, one division every 16 pixels) |
| a clip 240x160 scrolling every pixel, drawn at scale 2 | 5.1 ms, 60 fps |

What this says: a light, a warp and a perspective quad are for a part of the screen; a background is darkened through its palette
for nothing; a clip at 240x160 drawn twice as big plays at 60 fps even when every pixel changes.

`examples/psx_demo` (a full-screen sky, a carpet in perspective, a lit sign and banner, two lights, text): 24.5 fps at the start of this
section's work, 30.5 fps after (strips 30.2 -> 25.5 ms). Where the 25.5 go: the carpet about 7, the sky and ground grads about 6, the
sign 2.4, haze 1.7, banner 1.6. A mixed pixel is paid only on a canvas for its see-through colour check (`surface.canvas`): testing
every pixel for it took full-screen `linetint` from 12.3 to 22 ms.

`lib/particles.lua`, a camp fire of about 110 particles (flames and embers as added `light()`s, smoke as shadows): 2.5 ms of tick, 2.9 of
world (the Lua drawing), 8 ms of strips; 34 fps at the frame's edge (a tick + world + strips of more than ~13.5 ms misses a 60 Hz
frame). Each particle is about 50 us of Lua a frame; one options table a `light()` call cost 1.3 ms more at that size (now shared).
`transition`: iris at 0.5, 5.5 ms of strips; blocks 1.8; a smooth fade 12.3 (a mixed full-screen box).

`lib/rig.lua`, three characters of 10 pieces (30 quads of 40x80, every one overlapping the others, lit and dithered): 4.8 ms of Lua
for placing and drawing the 30 (it was 9.4 before one sort a frame, a table and a closure a piece went), 46 ms of strips: about
480 ns a pixel lit with dither against ~150 unlit. So a character of 10 pieces and ~10 thousand pixels is about 1.5 ms plain and 5 ms
lit; light the ones that need it, and keep the pieces to the size of what they draw.

The same quad (400x280 pixels, flat) with a picture of 32x32, 128x128 and 256x256: 7.2, 9.1 and 47 ms of strips (51, 68 and 400 ns a
pixel). A picture over about 128x128 (32 KB) stops fitting the memory cache and every pixel waits for the external RAM: keep the
pictures a quad draws to 128x128 or less (cut a big floor into tiles, or draw it from a smaller one: the quad scales it).
A picture drawn at less than half its size is now sampled from a smaller copy (a mip level, `gfx_quad_mip`): six quads of 100x100 with a
256x256 picture, 5.9 ms of strips; the same six with a canvas of that size (not mipped), 22.8 ms: 3.9 times. Loaded pictures only.
The clamps of a quad's texture coordinates are skipped when a column's ends are inside the picture (affine 7.8 -> 6.7 ms).

`perf("ops")` on `examples/psx_demo` (CPU ms of the strips, both cores added, so about twice the time on the clock): quads 22.2 (5), grads 16.1
(3), lights 4.8 (2), picture 2.7, the rest nothing; the strips take 25 ms on the clock. A dithered full-height gradient costs 1.4 ms of
the clock more than a plain one: every strip rebuilt its four dither phases of the ramp. Now the ramp is worked out once, when the command
is recorded (`gfx_grad_table`, into the frame's `ov_pts`; a box too tall for what is left of it works it out as it draws): the same three
gradients 16.1 -> 10.4 ms of CPU, a full-sky dithered gradient 3.5 -> 2.5 ms of the clock (a plain one is 2.1), psx_demo's strips 26.8 -> 23.7 ms.

`lib/cam.lua` zoomed and turned (the world drawn on a canvas, then a quad of it): not zoomed, 60 fps and no cost; a 480x320 canvas at zoom 1.3
turned 10 degrees, 79 ms a frame (36 filling the canvas in the external memory, 33 of the strips); a 240x160 canvas, 31 ms (30 fps). It
is for a moment (a hit, a reveal), not a whole level.

A lit quad laid opaque whose column ends are inside the picture and the light's range skips every clamp (coordinates, lights, colours
before their dither): a lit quad bench 35.1 -> 29.0 ms of strips, psx_demo's strips 23.7 -> 22.6 ms. A quad mixed with what is under it (add,
alpha) is still the slow, general loop (a mixed quad bench 36.9 ms).

`examples/psx_views`, the staged-camera prototype for Micromiserias: one logical actor passes through lateral, fixed and rear views
without losing position or state. On Cirera, lateral drew at 59.9 fps (8.4 ms of strips). A large filled floor polygon in the fixed
view and a full road polygon in the rear view brought both to about 30.6 fps (roughly 15–19 ms of strips). Replacing those with a
rectangle and twelve-pixel horizontal bands: fixed 59.6–60 fps (4.3–4.6 ms of strips), rear 59.8–60 fps (4.3–6.3 ms). These are
short samples of shape-only art; they do not establish the budget for packed sprites, prerendered scenery and music together.

## Phase 0: connected board, read-only snapshot (2026-10-18)

Cirera answered `hello 1 card 14964864` on `/dev/cu.usbmodem2101`. Without changing its current game, USB log reported firmware `0f98162-dirty`, menu `54.4 fps`, `tick 2.07 ms`, `render 14.20 ms`, strips `4.11 ms`, audio `10%` of a core and `0 underruns`; free internal RAM was `28 KB`. This is a launcher snapshot, **not** a baseline for `psx_views` or textured 3D. Automatic approval review rejected `send_game.py`: it interpreted the transfer as a possible write to the game partition under the earlier app-only flash instruction. The command was not run. Scene measurement needs explicit authorization for an SD-card transfer or an already installed reference scene.

`psx_demo` was already installed, so opened through the launcher with the test firmware's USB controls, without transferring files. It measured `30.6 fps`, `tick 0.18 ms`, `render 30.79 ms`, strips `28.61 ms`, audio `33%` of a core and `0 underruns`. This is a baseline for that installed game under firmware `0f98162-dirty`; its Lua and assets may differ from the repository copy. At 60 fps this scene needs a major reduction in filled/mixed pixels, not only faster geometry setup.

After building and flashing **only the app** at `0x20000` with `BP_REMOTE=ON`, the installed `psx_demo` still ran at `30.6 fps`, with `render 30.80 ms`, audio `28%` of a core and `0 underruns`. A temporary in-memory `_draw` wrapper drew a textured face crossing the rear camera's near plane through `views.draw3d`; the face appeared in the captured board frame, and the game reported `30.5 fps` with `0 underruns`. No game files were transferred. These runs establish that the new renderer works on Cirera, but do not isolate its cost: the scene already misses 60 fps and frame content differed between samples.

## Rear-camera geometry cost (2026-10-18)

Cirera was identified by `hello 1 card 14964864` and MAC `7c:e8:b1:b2:89:48`. Only the app at `0x20000` was flashed. The already installed `psx_demo` supplied its 96×48 sign texture; temporary Lua changed `_draw` in RAM to render one, four or eight copies of the same 80×80 projected face. Each case ran for 11 seconds; the last performance report was used, since earlier reports lagged one scene. The sign rendered correctly on the panel. No SD files changed.

| Scene | Before: `_draw` / strips / fps | Reused rear projector: `_draw` / strips / fps |
|---|---:|---:|
| Empty | 0.02 / 1.13 / 59.9 | 0.02 / 1.13 / 60.1 |
| 1 face | 2.52 / 1.97 / 60.1 | 2.14 / 1.97 / 60.1 |
| 4 faces | 7.92 / 4.10 / 46.1 | 6.19 / 4.10 / 54.5 |
| 8 faces | 15.06 / 6.92 / 30.6 | 11.56 / 6.92 / 30.6 |

Times are milliseconds. `views.draw3d` now validates the rear lens once per call and uses `views.projector` for actors and vertices. CPU `_draw` improved 15–23% in these scenes; raster cost did not change. The eight-face case stayed at 30.6 fps because display timing and other frame work still crossed the next presentation interval. Identical overlapping faces stress overdraw; a real scene with distinct geometry needs a separate measurement.

## A lit, textured 3D cube against the real PlayStation (2026-10-23)

The PSn00bSDK `examples/graphics/gte` cube (6 faces, 128x128 texture, ambient plus one light, dithered) built for a PS1, run in
an emulator at four fixed poses, and the same cube drawn here with `quad(..., {light, dither})` from the same vertices, rotation,
camera and light: the silhouette matches at 98-99 % (IoU) with the bounding box within 1 px, and the mean colour within 1-5 levels
(this engine reads about 3 levels greener, not chased). Looks, geometry and lighting need no change. Cost on the Cirera (firmware
d1f8178, game sent to the card, volume 0, `perf` lines of the last second): each cube drawn at 4/3 scale covers about 18.5k pixels
(three faces after the backface cull).

| Cubes | Pixels lit | Strips (CPU, both cores) | fps |
|---:|---:|---:|---:|
| 1 | 18.5k | about 7 ms | 59.8 |
| 2 | 37k | 12.7 ms | 59.1 |
| 4 | 74k | 23.9 ms | 30.0 |
| 7 | 130k | 38.2 ms | 20.0 |

About 300 ns a lit, dithered pixel (strips 23.9 ms / 74k, 38.2 ms / 130k), as in the quad tables above. With the frame at 16.7 ms
the budget is roughly 12 ms of strips, **about 37k lit pixels a frame, a quarter of the screen**: two cubes this size, or a room
seen through a few small faces, not a screenful of lit polygons. Two cubes (37k pixels, strips 12.7 ms) hold 59.1 fps with 0.9 ms
to spare, so that is the edge. The cube itself costs little in Lua: `_draw` 1.2 ms for one, 2.5 ms for four, 3.7 ms for seven. Sources: a scratch game,
not in the repo.

## The same mixer on a desktop

Measured on a desktop (an optimized build, `make audio_bench`): the order and the ratios, not the console's milliseconds (the
board's own are above). Milliseconds of mixing for one second of
sound, twelve voices of one looping clip:

| Scene | ms per second |
|---|---|
| nothing playing | 0.15 |
| 12 plain voices | 0.13 |
| 12 voices at pitch 1.3 (between two samples) | 1.37 |
| 12 voices with pan, envelope and a reverb send, no room | 1.07 |
| 12 plain voices through the Room reverb | 0.55 |
| 12 voices with pan, envelope and sends through Hall | 1.26 |
| the same through Space Echo | 1.17 |

The reverb costs about 0.4 ms a second whatever the room (its work is the same turn for each sample; only the memory it
touches differs: from 10 KB for Room to 63 KB for Space Echo), about as much as three voices at a pitch. A voice with an
envelope or an ADPCM clip takes the between-two-samples path, the dearest. 

## 2026-10-20 · Internal RAM and the radio

The radio (link, ESP-NOW) had stopped starting on the console: `esp_wifi_init` gave `ESP_ERR_NO_MEM` with 22 KB free
and a largest block of 12 KB. Measured on the board:

- The radio takes **27 KB** of internal RAM (a probe at boot: 78 KB free -> 51 KB with ESP-NOW on).
- Between boot and a game's start, tasks, the card and the game take ~50 KB: a game started with 19 KB free.
- The PPU's code in IRAM had grown 18.5 KB since 2026-10-17 (the line-palette builds, the blend's tracking). Its two
  line-palette builds now run from flash (`linker.lf`): +9 KB; horizonte's picture 4.19 -> 4.49 ms, 59.8 fps both.
- Task stacks, the least ever unused (logged with `perf:` as `stacks unused`, MAQUETA's title the deepest seen): main
  8.4 KB of 16, audio 4.9 of 6, display 3.1 of 4, power 2.2 of 3. Audio 6 -> 4 KB, display 4 -> 2.5, power 3 -> 2.
- Now a game starts with 32 KB free; with the radio on, 6 KB are left (juntos plays, 59 fps). That is little: what
  grows internal RAM again stops the radio first. `.github/workflows/firmware.yml` fails when the statics leave less
  than 70000 bytes; the main task's 16 KB stack (8 KB seen used) is the next margin, if one is needed.

## 2026-10-21 · The system's code out of internal RAM

What the statics leave of D/IRAM (`esp_idf_size` on the map, the same build with one change each, `BP_BENCH=OFF`):

| Build | D/IRAM left |
|---|---|
| Before | 73170 B |
| FreeRTOS and ringbuf non-ISR code in flash | 84330 B (+11.2 KB) |
| + the ROM's flash driver (`SPI_FLASH_ROM_IMPL`) | **92938 B (+19.8 KB)**, taken; **undone 2026-10-22: it corrupted the heap on every flash erase, see the end of this file** |
| FreeRTOS, ringbuf, heap in flash (no ROM driver) | 97586 B (+24.4 KB), not taken: it needs the panel's SPI interrupt out of IRAM |

The ROM's driver lacks only `SPI_FLASH_AUTO_SUSPEND` (off here). Not yet run on the board: check a save to the flash,
a game sent over the cable, an OTA and `examples/juntos` with the radio, and the frame time of a strip-heavy game
(FreeRTOS's queue and semaphore calls now run from flash). A checkout with its own `firmware/sdkconfig` keeps the old
values until it is made again (`rm sdkconfig`, or `idf.py reconfigure` after deleting the lines). CI's floor is now 90000.

## 2026-10-21 · The vector unit for runs of one colour mixed in

A box of one colour seen through, added or taken away (a fade, a flash, a dialogue's backing: `gfx_grad` with one colour and
no dither) now mixes its runs with `span_mix_const` (src/gfx_span.c): in C everywhere, and on the console with the S3's
128-bit vector unit (PIE, `ee.*`), eight pixels an iteration, following Jet's constant blend (MIT). Both give the pixels of
the general mixing: `span_test` checks the C one against `mix565`/`blend_held` for every pixel under, and `tests/pie/run.sh`
runs the vector one against the C one in Espressif's QEMU (4000 random runs, every alignment, length, mode and byte order:
the same). **Not measured on the board yet**: Jet reports its RGB565 constant blend several times faster than C on an S3;
the smooth `transition` fade (a mixed full-screen box, 12.3 ms of strips) is the scene to time. ESP-IDF saves the vector
registers lazily per task (`_xt_coproc_sa_offset`), so both cores' strip tasks may use them.

## 2026-10-21 · The round's changes on the board, and the variants

Firmware `a3ae4d5` (the seven phases of docs/roadmap.md) flashed app and otadata only, on the board with the card
(18 games on it). Compared with `602f119-dirty`, which was on it: the menu starts with **51 KB** of internal RAM free
instead of 32; `examples/juntos` turns the radio on with 51 KB and keeps **24 KB** (it was 32 and 6). A game's own
`game_init` takes what it took (the ROM's flash driver reads the flash no slower: cirera 257-268 ms; the 511 ms of the
first boot after a flash is the first boot's). The mixed full-screen box of `transition`'s fade (now `span_mix_const`
with the vector unit): **3.4 ms of strips** against the 12.3 measured on 2026-10-17.

Then four builds, each flashed and the same nine games played the same way over the cable (`tools/remote.py`, a
`-DBP_REMOTE=ON` build: the game launched from the menu, A three times, RIGHT held, the last two `perf:` lines):

| Build | Internal RAM, menu / in a game | duelo world / strips | torneo | castells | trece | maqueta |
|---|---|---|---|---|---|---|
| 64 KB data cache, from flash (as it was) | 50 / 38-49 KB | 1.4 / 7.3-7.8 ms | 1.9-2.0 / 8.6-9.6 | 1.5-2.0 / 5.7-7.8 | 2.3-4.4 / 2.4-7.0 | 6.2 / 3.3 (56.9 fps) |
| 32 KB data cache | 81 / 70-73 KB | 1.5 / 7.4-8.0 | 2.1 / 8.8-9.6 | 1.6-2.2 / 5.8-7.4 | 2.3-2.4 / 2.4 | 6.2-2.8 / 3.2-3.5 |
| XIP from PSRAM (code and rodata in PSRAM) | 48 / 37-40 KB | 1.0 / 7.1-7.6 | 1.5-1.6 / 8.5-8.9 | 1.1-1.5 / 5.6-7.0 | 2.1-2.3 / 2.2 | 6.0 / 3.2 |
| **both (taken)** | **80 / 68-71 KB** | 1.06 / 7.2-7.8 | 1.6-1.7 / 8.6-9.3 | 1.2-1.5 / 5.7-7.2 | 2.2-2.3 / 2.2 | 6.1 / 3.2 |

World is the firmware's `world` (Lua and the picture processor, one core), strips the two cores' CPU for the whole
frame. Every game stays at 59-60 fps in every build (maqueta's scene at 56.9 in all four: its own `_draw`, 6 ms). The
32 KB data cache costs nothing these games can show and gives 31 KB of internal RAM; XIP takes 10-30 % off the world
(the instruction cache refills from octal PSRAM, not quad flash) for 1.7 MB of PSRAM (6.3 -> 4.6 MB free at the menu).
Both are now in `sdkconfig.defaults`. paleta's heaviest scene (strips 9.7-11.5 ms, 49-56 fps) varied between runs more
than between builds. control 59-60, paleta 58-60, horizonte 59.9, veloz 59.6-60 in play.

What `tools/remote.py`'s `shot` costs: a frame over the cable (400 KB) stalls the console for about six seconds, so
the `perf:` lines next to a shot read 10-27 fps: those are the shots, not the game.

An adventure (Bajo Pueblo, np2d@1, sent without its 123 MB of audio), the same stages on the two builds:

| Stage | 64 KB cache, from flash | 32 KB cache and XIP |
|---|---|---|
| the title (a 480x320 picture every frame) | 16.8 ms of strips, 38-50 fps | 17.7 ms, 38-49 fps |
| the first dialogue | 7.0-7.8 ms, 52-58 fps | 6.6-7.5 ms, 52-58 fps |
| a choice, then walking | 6.6-6.9 ms, 60 fps | 6.3-6.7 ms, 60 fps |

The title's 17 ms are the adventure's own (the picture drawn whole each frame: it was 11-12 ms with the world before
the first shot, the rest is the shot); nothing else moved more than the run-to-run noise. Internal RAM in the game: 43
KB on the old build, 42 on the new (an adventure allocates its own buffers; the 30 KB show in Lua games, 70 KB).

IL·LUSTRES (np2d@2, a Neo Geo-like fighter, 44 MB of pictures on the card, sent over the cable in eleven minutes)
on the final build: `game_init` 755 ms; the fights at 57.6-59.8 fps (world 1.1-1.6 ms, strips 6-10 ms), the round's
intro at 53 fps (world 4.2 ms), one 44 fps sample while pictures were loading (world 6.8 ms); PSRAM free went from 3.7
to 2.0 MB as its fighters came in, so XIP's 1.7 MB still leaves it room. Internal RAM 56-59 KB in play.

The console's menu and settings seen on the panel over horizonte (shots over the cable): the colour filter costs
**1.8 ms a frame** (horizonte's picture 4.4 -> 6.3 ms, 59 -> 56 fps at its heaviest scene; the 240x160 world through
a 32768-entry table in PSRAM), gone again when it is turned off. Found on the way: the strips are drawn on both cores
at once, so nothing in the drawing path may call into the game's Lua state (the menu read its items there and the
console aborted in luaD_throw: fixed, the labels are copied on the tick).

`music(..., {at = "bar"})` on the console's mixer (tests/games/music sent to the card, driven over the cable): with a
bar of two seconds the queued song waits (`music_queued()` true while the first is at 0.90 s) and comes in on the
line (the next sample, 1.1 s later: the new one at 0.32 s). The console's `lua:` round trip over the cable is about
half a second, so finer timing needs a longer bar, as here.

Geumgye (np2d@1, the same engine as Bajo Pueblo, sent without its 76 MB of audio): its title at 59.8 fps with 13.2 ms
of strips (its picture, as Bajo Pueblo's), 42 KB of internal RAM free.

## 2026-10-21 · A real game on the round: CONTROL

CONTROL (`juegos/CONTROL`, Lua, 1300 lines) took the round's libraries: `lib/voice` for its two speakers (a blip every
two letters, from a `sound()` of each one's wave and pitch), `duck()` under the producer's intercom, `sfx` variation
options on the desk's clicks, `music(nil, 200, {at = "bar"})` for the theme's end, four achievements, `reduce_flashing`
and `juice.tween` on its cards. Its own bench (`bench.txt`: the autopilot directs the show in a loop, silent, `perf()`
logged each second; 76 s) on the console, before and after, on the same firmware (main 9bb4905 + remote, cache 32 +
XIP):

| | Lua `_update` | Lua `_draw` | fps (median / min) | internal free | underruns |
|---|---|---|---|---|---|
| before | 0.74 ms (max 0.98) | 4.51 ms (max 7.65) | 59.8 / 56.9 | 77 KB | 0 |
| after, same firmware | 0.80 ms (max 1.08) | 4.45 ms (max 8.32) | 59.8 / 56.9 | 76 KB | 0 |
| after, tonight's firmware (modules through the bus, voices with accents) | 0.79 ms (max 1.06) | 4.61 ms (max 9.06) | 59.8 / 56.6 | 76 KB | 0 (audio 14 % of a core) |

The 0.06 ms are the voice's letters, `juice.update()` and a `settings()` read a second. `game_init` 255 ms both.

The profiler, repaired on the way (it had been stopped by `v2_free` since 479ba09, and its count hook started over at
each call, so a tick under 1000 instructions was never sampled): `--profile` over CONTROL's directed test, two whole
shows, 554 ms of Lua on the desktop (about 14 us a tick); by own time `score.tick` 54 ms, `score.pending` 48,
`pilot` 47 (the tests' director), `audio.babble` 33 (the new voices), `switcher.tape` 30, `prog.incident` 27; loading
(`third_below`, `letters`) 14 ms once. Nothing worth a change: the console's 0.8 ms a tick is spread thin.

Modules through the music bus (`audio.c`): the module renders into its own chunk buffer and is added to `mus[]` with
the bus's gain, then takes the duck and the lowpass with the WAVs; one `memset` and one multiply-add per sample more
(a 256-sample chunk: a few microseconds on the console).
The firmware with all of it: 90222 B of D/IRAM left (the CI floor is 90000; it was 91558 before the round's last build), the
two spare module contexts asked for in slow memory.

## 2026-10-21 · TRECE on the round, and the post pass's copy

TRECE (Mode 7 petanque; its own bench: `bench.txt` "auto", games played by itself in silence, the console's perf
lines every few seconds and the game's own "worst frame" every 600 frames) on the console, 75 s each:

| | tick (Lua) | render avg / max | fps median / min | worst frames (ms) | internal free |
|---|---|---|---|---|---|
| before | 1.40 ms | 15.45 / 16.32 ms | 58.5 / 52.4 | 13-17 | 74 KB |
| after, post copying the whole picture | 1.43 ms | 16.76 / 20.50 ms | 55.5 / 43.3 | 16-24 | 73 KB |
| after, post copying the rows it reads | 1.47 ms | 15.62 / 16.41 ms | 58.0 / 52.1 | 15-19 | 73 KB |

The heat haze is on every frame on the square and the beach (22 rows), the rings only after a blow: with the whole
240x160 picture copied first (76 KB, PSRAM to PSRAM) the render lost 1.3 ms a frame and the worst frames went past
20 ms; copying the rows the effects read (the haze's own, each ring's reach) gives nearly all of it back. The 0.07 ms
of tick are the rival's scores, the voices and `juice.update()`. Firmware D/IRAM left: 90222 B, as before.

## 2026-10-22 · PALETA on the round, the crash's QR and the button map

PALETA (the drops puzzle) on the console, its autopilot playing from level 5 for 50 s (driven over the cable:
`lua:autopiloto = true; ir(5)`; a port opened after a game is sent resets the console into the menu, so the game is
launched again first), old and new versions, the same levels won (5 to 10):

| | tick (Lua) | `_update` / `_draw` | render | fps median / min | internal free |
|---|---|---|---|---|---|
| before | 3.05 ms | 3.00 / 1.60 ms | 15.47 ms | 51.6 / 49.8 | 69 KB |
| after (juice, achievements, calm) | 3.24 ms | 3.20 / 1.64 ms | 15.34 ms | 51.5 / 50.3 | 68 KB |

The 3 ms a tick are the autopilot's (it tries 24 placements of each pair, resolving a copy of the board for each);
a player's hand costs 0.3 ms. The round's additions: 0.2 ms.

The crash screen's QR (version ≤ 10, 2 px modules): a shot of the panel over the cable decodes with OpenCV
(`cv2.QRCodeDetector` on the shot scaled 2x): "pinyol control: _update: script:1: prueba del QR..." The firmware's
D/IRAM left stays at 90222 B (the QR's 407-byte buffer and the map live with the menu's state; the encoder's code is
in flash).

## 2026-10-22 · XM and S3M modules on the console (IBXM)

The music test game sent to the card with three modules, played over the cable (`lua:music("STRESS")`...), the
firmware's audio line (share of a core the mixer takes, every few seconds):

| playing | audio, % of a core | underruns | internal free | PSRAM free |
|---|---|---|---|---|
| nothing | 2 | 0 | 77 KB | 4827 KB |
| STRESS.xm: 8 channels, a note on half the cells, two instruments with envelopes and vibrato, speed 6 at 125 BPM | 9 | 0 | 77 KB | 4784 KB |
| LOOPX.xm (4 channels, queued at the bar line of the XM playing) | 7 | 0 | 77 KB | 4751 KB |
| LOOPS.s3m (4 channels) | 5 | 0 | 77 KB | 4792 KB |

IBXM renders a tick at a time (a line's share at the song's speed) into a buffer in slow memory and the mixer takes
it out by frames: about 7 % of a core for eight channels at 22050 Hz with linear interpolation off, nothing in
internal RAM (D/IRAM left 90222 B, as before IBXM), the module's samples (as 16-bit), patterns and replay in PSRAM
(43 KB for the dense one). `music_beat()` on the XM after 25 s said bar 14, beat 1 (a line every 120 ms, a bar
every 1.92 s); the queued XM came in at the bar line (`music_queued()` true until then).

## 2026-10-22 · The batch: markers, blue noise, FM, voxels, light, rollback, FamiStudio

The voxel landscape on the console, first cut (the looks test game's view: 240x160, distance 120, a 64x64 map):
`_draw` 21-28 ms, 20-24 fps. Its cost was in the inner loop: two floorf, four modulos and the brightness of the
height map worked out again for every sample. Rewritten (the height map kept as bytes while the same picture is
asked for, masks for power-of-two maps, a cast with an offset instead of floorf, the buffers in slow memory):
`_draw` 14.6 ms, 30 fps (the frame no longer fits in 16.7 ms, so the panel's scan halves it). The rest is the
canvas's pixels in PSRAM written a column at a time: a view of 120x80 shown twice as big has a quarter of them.
On the desktop the same view draws in 0.57 ms (headless, `perf()` over twenty frames). The silhouette sprite over
the picture (the same test game): `_draw` 0.18 ms, 59.8 fps, nothing to see against the plain picture.
The firmware flashed at the end: D/IRAM left 91802 B. Found on the way: the launcher listed 64 games at most
(LAUNCHER_MAX, and console_games()'s MAX_GAMES), and this card holds 70, so a game past the 64th could not be
launched over the cable; both are 128 now (the list lives in PSRAM: 16 KB more there, none internal), the console
lists 70 and launches the last.

Internal RAM: ppu.c lives in IRAM (linker.lf, `ppu_inside`) with its line buffers, so code added to the line drawers
costs IRAM six times over (the layers_x variants): the silhouette's hooks took 1.3 KB until they were moved to the
frame's preparation (sil_map, once a frame on the game's thread) and to flash (sil_apply, line). The per-line palette
copies (2 KB, a game that replaces entries on a line) went to slow memory. D/IRAM left: 91838 B (90222 before the
batch; the floor in CI is 90000).

## 2026-10-22 · CPS2: un escenario de ILUSTRES en el overlay o en el mundo

`juegos/ILUSTRES-ESP/tests/cps2bench` (Cadaqués: BG_FAR de 640×320 y BG_NEAR de 720 de ancho, dos luchadores de
312×272, la cámara barriendo el escenario), diez segundos por modo, `perf("ops")` y `perf()` una vez por segundo en la
consola:

| Modo | Strips (ms de CPU por frame, los dos núcleos sumados) | Capas del mundo (ms) | Total |
|---|---|---|---|
| Todo en el overlay con `img` (como dibuja ILUSTRES) | 12,6 (`img`) | 0 | 12,6 |
| Capa lejana en el mundo (canvas de 320×160, el PPU la dobla), el resto en el overlay | 5,6 | 2,1 | 7,7 |
| Lejana y cercana en el mundo, solo los luchadores en el overlay | 1,9 | 3,0 | 4,9 |

Las líneas `perf:` del firmware dan 60 fps y «render 16.15 ms» en los tres modos: con TE lock, render es el periodo
del panel, no el coste; para comparar hay que mirar `perf("ops")`. Una imagen de 480×320 por `img` cuesta unos 7 ms
de CPU (los dos núcleos); la misma como capa del mundo a mitad de resolución, unos 2. ILUSTRES (combates a 57,6-59,8
fps, intro de asalto a 53) ganaría ~5 ms de CPU por frame pasando la capa lejana al mundo, ~7,7 con las dos; la
cercana a mitad de resolución pierde el detalle del público y la terraza, la lejana (cielo y ciudad al fondo) apenas
se nota.

Aplicado a ILUSTRES (`stage.lua`, 0719f0c) y medido en el combate real: la misma demo fija (Dalí contra Gaudí, 45
segundos, `perf("ops")` cada segundo desde una copia del juego con la sonda), con los Lua antiguos y los nuevos sobre el
mismo firmware:

| Escenario | Strips (ms de CPU por frame) | de ellas `img` | Capas | Total |
|---|---|---|---|---|
| Lejana por `img` (antes) | 16,5 (máx. 23,0) | 14,5 | 0 | 16,5 |
| Lejana en el mundo (ahora) | 9,5 (máx. 19,3) | 7,5 | 2,1 | 11,6 |

Cinco ms de CPU por frame menos (−30 %) con la misma imagen en pantalla; los fps no cambian (59,1 de mediana en los
dos, el tope del panel): el margen queda para lo que venga. Las bajadas que quedan (33 fps un segundo) son cargas de
imágenes entre pantallas, no el dibujo.

## 2026-10-22 · PSRAM in pieces: why a fighter went missing, and what gave the memory back

Playing IL·LUSTRES on the board a fighter was not drawn (Dalí against Rodoreda, in VERSUS and in the arcade): the log said
`asset SPR_RODOREDA: not a packed picture`, `imgsize` gave nil, and the hits still counted. The same fight worked on the
firmware of `95efeb7` (where the 2 MB of margin was measured) and failed on today's, with the game as it was before today
as well. The firmware's per-second line now ends with `(largest block N KB; U blocks used, F free)` of PSRAM:

| Where | Free PSRAM | Largest block | Blocks used |
|---|---|---|---|
| a fight, before | 1.0-1.6 MB | 320-624 KB | 11 500-14 300 |
| the same, Lua's memory in chunks | 0.7-1.7 MB | 256-752 KB | 530-640 |

So it was not the sum but the pieces: Lua's small objects, twelve thousand blocks of the heap, scattered between the
pictures, and a sheet of 609 KB (a fighter's first strip; the VS screen's portraits are 825 KB) found no block. A failed load
left the picture a one-pixel placeholder for the whole game. What changed, in the order it was found:

1. **`src/lua_mem.c`**: Lua's objects up to 256 bytes are cut from 32 KB chunks taken whole from the heap (a freed one waits on
   its size's list; every chunk goes back when the game ends). Blocks used 12 000 -> 500; `game_init` of IL·LUSTRES 791 ms
   -> 700 ms (the heap is asked less often). `tests/lua_mem_test.c`: 400 000 random operations across the small/big border
   with each block's contents checked, alignment, and the chunks' count.
2. **300 KB of PSRAM that nothing used**: `script.c` kept the screenshot's frame in a static in every firmware (the 480x320
   buffer of the `shot` command, `fb` in the link map). It is made when a shot is taken. Free PSRAM at the game's start
   4054 -> 4345 KB. (The map: 709 KB of PSRAM statics, 720 KB of read-only data and 1 MB of code run from PSRAM, the XIP.)
3. **Eviction**: when a picture found no block, every picture not drawn in that frame went at once and it asked once. A fight's
   preload (one picture every 4 ticks behind the VS screen) took its own earlier loads with it. Now the pictures go one at a
   time, the least recently drawn first, asking again after each (`pic_malloc`): the pair Cerdà and Llull (730 + 791 KB the
   first strips, 41 failed loads in the log) loaded with none.
4. **A load that fails is tried again** (a third of a second later) instead of being a placeholder for good: a one-pixel
   stand-in, `imgsize` tells the size it will have, the log says it once. `tests/picmem.script` (`fail_loads N` makes the
   next N loads find no memory).
5. **The game** (IL·LUSTRES, `main.lua`'s preload): a SUPER's background (155 KB each) and the effects of fighters not in the
   fight are no longer loaded behind the VS screen: about 460 KB less in the fight's 2.8 MB. A SUPER loads its own in the
   flash, when the picture stands still (seen on the board: Cerdà's L'EIXAMPLE).

The same eleven games on the board before and after (the firmware of `111be0b` against the one with all of the above; each
launched from the menu, three presses of A, a walk to the right, medians of the log's lines; the panel caps the frames at 60):

| Game | fps | Lua draw ms | world ms | script KB | game_init ms |
|---|---|---|---|---|---|
| trece | 59.2 -> 59.3 | 0.72 -> 0.68 | 2.50 -> 2.43 | 296 -> 298 | 479 -> 425 |
| duelo | 59.9 -> 59.8 | 0.99 -> 0.89 | 1.04 -> 0.93 | 77 -> 80 | 217 -> 207 |
| torneo | 59.8 -> 59.8 | 1.60 -> 1.56 | 1.65 -> 1.60 | 86 -> 84 | 232 -> 231 |
| castells | 58.5 -> 58.6 | 1.64 -> 1.53 | 1.69 -> 1.57 | 280 -> 280 | 473 -> 446 |
| maqueta | 56.7 -> 59.4 | 4.00 -> 3.22 | 6.14 -> 5.36 | 814 -> 836 | 1082 -> 984 |
| control | 58.3 -> 58.5 | 4.82 -> 4.11 | 5.30 -> 4.41 | 248 -> 241 | 289 -> 270 |
| paleta | 59.7 -> 59.7 | 1.80 -> 1.54 | 5.26 -> 5.02 | 116 -> 120 | 331 -> 318 |
| horizonte | 59.8 -> 59.8 | 1.48 -> 1.42 | 5.66 -> 5.59 | 37 -> 36 | 220 -> 221 |
| veloz | 58.7 -> 58.8 (three runs each) | 1.72 -> 1.60 | 7.1 -> 6.9 | 51 -> 50 | 228 -> 214 |
| isla | 59.5 -> 59.5 | 1.92 -> 1.64 | 5.08 -> 4.83 | 90 -> 93 | 240 -> 234 |
| sima | 58.0 -> 58.0 | 0.79 -> 0.69 | 4.96 -> 4.88 | 154 -> 158 | 235 -> 229 |

Lua's drawing is 5-20 % cheaper, the script's memory 1-3 % more (the chunks), blocks of PSRAM used 74-442 instead of
thousands, and no game is slower.

6. **Sheets in pieces** (`tools/pk_split.py`). Everything above left the whole sheets as the unit: with the heap as it is after
   a fight or two, the largest block is 300-700 KB and a sheet of 600 KB still finds none with 1-3 MB free. Four heavy pairs
   through the real VERSUS path on the board (Cerdà-Llull, Tió-Llull, Caballé-Cerdà, Llull-Tió): with whole sheets and XIP
   off (6082 KB free at the game's start instead of 4345) a fighter was still invisible in all four: more room, the same
   pieces of it. The game's 46 fighter sheets are now 184 pieces of 60-235 KB (10 frames each) and `PORTRAITS_L` (825 KB) 6 of 151
   KB; `gfx.fighter` draws frame `f` from piece `f // 10`, the preload asks for the pieces. The same four pairs on the
   XIP-on firmware (the production one): both fighters and both portraits in all four, no failed load. A SUPER in Cerdà-Llull
   shows its background and both fighters; its start is one frame of 200 ms (the background loads then).
7. **A canvas had no eviction.** The stage's far layer is a canvas of 320x160 (100 KB) made when a round starts, with plain
   `malloc`; at the VS screen's end the heap of a heavy pair had 86 KB as its largest block and the game stopped with
   `canvas "FAR": out of memory`. `gfx_canvas` now asks for its block as a picture does (`pic_malloc`: pictures not drawn
   in this frame go one at a time, the oldest first). `tests/picmem.script` (`fail_mallocs N`: the next N first tries at a
   block find none): a picture not drawn goes for the canvas, a drawn one stays, and with none to let go the canvas is the
   error. Free PSRAM at the lowest point of a heavy pair: 170-490 KB, the largest block 50-110 KB, and nothing fails.

Tried and left: **XIP off** (`CONFIG_SPIRAM_XIP_FROM_PSRAM` unset, which gives 1.7 MB back: 6.1 MB at the game's start). With
the ROM's flash driver on (see the next section) it panicked with `Cache disabled but cached memory region accessed` inside
`tlsf_malloc`, probably the same corruption as the update's (it was not chased then); with that driver off it boots and
runs. It does not fix the fighters (point 6), so the production firmware keeps XIP on. The secret fighter Tió (1 MB and 0.6 MB of sheets) is one of the
four pairs above.

## 2026-10-22 · The ROM's flash driver corrupted the heap on every erase (and the update from the card with it)

A firmware update from the card (`firmware.bin` on the card's root) ended on the console's screen with «La actualización no
vale». The log of the boot, read with the update's file moved into a game folder the cable can write (a scratch firmware that
looks for it in `games/otatest/`):

```
E bootloader_mmap: spi_flash_mmap failed: 0x101
E esp_image: bootloader_mmap(0x2e0020, 0xfa56c) failed
ota: ... not installed: ESP_ERR_OTA_VALIDATE_FAILED
Guru Meditation Error: Core 0 panic'ed (StoreProhibited)   <- in tlsf_malloc, from fseek, 0x0863086f: pixels where a heap block's list was
```

`0x101` is `ESP_ERR_NO_MEM` from the small internal blocks the mapping asks for: the heap was already corrupt. With
`heap_caps_check_integrity_all()` between the steps of the update:

| Step | Heap |
|---|---|
| start, file opened and renamed, partition found | ok |
| `esp_partition_erase_range(ota_1, 0, 1.9 MB)` returns `ESP_OK` | **corrupt** |
| every later step | corrupt; the verification read `invalid segment length 0x11111111` |

The same firmware with `CONFIG_SPI_FLASH_ROM_IMPL` unset (nothing else changed) keeps the heap ok through all of it, writes the
1 889 456 bytes, restarts and says `firmware 4b182ce in ota_1`, `ota: this firmware is kept`. So the ROM's flash driver,
taken on 2026-10-21 for 9.6 KB of D/IRAM ("not yet run on the board: check a save to the flash, a game sent over the cable, an
OTA", the note said), corrupts memory on a flash erase, together with the code run from PSRAM (XIP) and the data cache at 32 KB
this firmware has. What it touched: every erase of the flash: an update from the card, a game sent over the cable to a console
with no card, saves to the flash. (The panic of the XIP-off build above, in `tlsf_malloc`, may be the same fault.)

D/IRAM left by the statics: 93 138 B with it, **83 534 B** without; the CI floor goes from 90 000 to 80 000. A console running
a build of main from 2026-10-21 (0ff5136, where the ROM's driver came in) or 2026-10-22 (until da2b717) cannot update itself
from the card (its own driver does the erase): flash it once by the cable
(`esptool write_flash 0xf000 ota_data_initial.bin 0x20000 pinyol_console.bin`), then the card works. The released firmwares are
not affected: 0.3.0, published on 2026-10-20, was built without that driver (the sdkconfig of its tag has
`CONFIG_SPI_FLASH_ROM_IMPL` unset, no XIP and the 64 KB cache).

## 2026-10-22 · Vector drawing: the call is what costs, not the pixels

Pozo (the vector look's example) first drew every ring and lane of its well as a filled `poly` quad, then as lines, then
with a glow on a canvas under the lines. Each step was found out with `perf("ops")` (what each kind of drawing command
costs in the strips) and `perf("lua")` (which function of the game spends the Lua time) on the board. A filled `poly` cost
about 140 us in the strips, a `line` about 20, and each call from Lua to C some 15 us on top.

| What the frame draws (Pozo in its demo, some 100 strokes a frame) | `_draw` | fps on the console |
|---|---|---|
| a filled quad for every ring and lane (105 to 180 `poly` a frame: 11.5 to 20.5 ms in the strips) | 8.3-9.1 ms | 30 |
| every side a `line`, the glow on a canvas under them (a `shade` of it each frame) | 11.9 ms | 30 |
| the same, the canvas cleared each frame instead | 9.3-9.9 ms | 30 |
| the well's line ends worked out once, only the last frame's glow erased | 9.9-10 ms | 30-32 |
| one outline per ring, `poly(points, colour, false)`, the glow canvas at half size | 8.0-8.3 ms | 34-38 |
| the same with the glow canvas turned off | 3.5-4.2 ms | 59.3-59.6 |
| **outlines, the glow as a dimmer copy one pixel over (two for the heaviest), every glow first and then every core** | 3.1-4.5 ms | **59.3-59.9** |

What the table says: the glow canvas cost 4 to 5 ms a frame whichever way it was filled (a bitmap layer of 240×160 in
PSRAM is 1.2 to 1.35 ms before anything is drawn on it, and a `shade` of it 2.5 ms; what is drawn into it runs in `_draw`);
an outline of any number of corners is ONE call, so a whole well (a ring, a few lanes in one path, the far ring) is five
or six calls, not a hundred; and the two passes keep one stroke's glow from covering another stroke's bright core.
`explain.lua` (the menu's "Cómo funciona") keeps working because the frame's strokes are in a list (`vec.snapshot()`),
not only on the screen.

## 2026-10-23 · Game Boy adventure (Cerezo) on the console

Cerezo's frame is a tile world: the ground, a front layer and the window layer are tile maps the console scrolls, so the
cost is in the strips (`picture` 4.1-4.4 ms) and not in the game's Lua (`_update` 0.30-0.35 ms, `_draw` about 0.5 ms).
A silent copy (`volume(0)`, as the other perf builds) was sent with a driver that teleports the hero to 18 places and
leaves him 5 s in each: the nine screens of the island, Yaya's house and the shop, and seven rooms of the cave (the
dark room with its circles of light, the beetle's room, the boss arena).

| What was measured | Result |
|---|---|
| fps in the 18 places | 58.1 to 59.6 (the one frame of loading showed 49.5) |
| `render` (the whole frame) | 15.1-16.2 ms |
| audio, the songs off | 7-12% of a core, 0 underruns |
| free internal RAM / free PSRAM | 55 KB / about 2.95 MB |
| script memory | 0.8-1.0 MB |

What it does not cover: the hero stood still and the pests were in their first state, so a fight with several of them
and the sword's effects on the screen at once were not measured. The numbers are of the draw and the world.

## 2026-10-23 · ZX Spectrum mine (Socavón) on the console

Socavón's room is one tile layer of 28×16 blocks plus a handful of sprites, so the strips cost 2.3-2.5 ms and the game's Lua
about 1.2-1.4 ms a frame (`_update` and `_draw`: the miner's physics, the guardians, the colour banks). A silent copy
(`volume(0)`) was sent with a driver that loads each of the eight rooms in turn and leaves it 6 s, the miner standing at his
start and the guardians moving.

| What was measured | Result |
|---|---|
| fps in the eight rooms | 58.0 to 59.6 (the 58.0 is the frame that loads a room) |
| `render` (the whole frame) | 15.1-16.0 ms |
| audio, music off | 4-11% of a core, 0 underruns |
| free internal RAM / free PSRAM | 64-75 KB / 4.7-4.9 MB |
| script memory | 235-280 KB |

Not measured: the miner walking and jumping (the floor-crumbling and belt rooms change blocks with `mset` as he goes, a few at
a time), and the tape loading (which draws full-screen images and clips; its striped border strobes only when "less flashing"
is off).

## 2026-10-23 · PICO-8 sliding puzzle (Tumba) on the console

Tumba's screen is the 16x16 map of the level on the background layer plus one sprite, so the strips cost 2.4-2.5 ms and the
game's Lua 0.8-1.0 ms of `_update` and 1.6-1.7 ms of `_draw` (the margins' text, the particles as 2x2 rectangles). A silent
copy (`volume(0)`) was sent with the title's demo running, which plays each level's solved moves with the real rules: slides,
particles, screen shake and the gems and cracks changing tiles.

| What was measured | Result |
|---|---|
| fps playing the demo | 58.9 to 59.9 (the first sample, 55.6, is the load) |
| `render` (the whole frame) | 15.8 ms |
| audio, the four voices of the tunes off | 9-10% of a core, 0 underruns |
| free internal RAM / free PSRAM | 64-75 KB / 4.75-4.78 MB |
| script memory | 322 KB |

Not measured: the explainer's pages (the map page draws 256 letters, once, into a canvas) and the level select.

## 2026-10-23 · Pocket LCD (Malabarista) on the console, and a full-screen canvas

A game that keeps its whole 480×320 screen (the glass of a handheld, with the picture printed behind it) in a canvas and shows it with
`img("LCD", 0, 0)` ran at **9.2 fps** on the console running firmware 3aff58e: `perf("ops")` gave the `img` 172-193 ms (both cores added)
for the frame, and the audio thread was at 75% of a core with hundreds of underruns. The old example `huevos`, which does exactly that,
measured the same, 9.2 fps, though it had been at 60-61 on 14 October. A test game then showed each way of putting a full-screen picture
on the screen:

| How the 480×320 picture is kept and shown | fps |
|---|---|
| a picture of the game (`png2asset --type background`), `img("PIC", 0, 0)` | 60 |
| a 480×320 canvas, `img("C480", 0, 0)` | 10 (19 the first seconds) |
| a 240×160 canvas, `img("C240", 0, 0, {scale = 2})` | 60 |
| a plain `rect` | 60 |

So Malabarista draws its glass once, in the headless player (`gen/make_glass.py`), and keeps it as a picture; each frame it draws only what
is on. With the miner holding both hands and the balls going: 57.7 to 60.0 fps, `render` 16.1-16.6 ms, the game's Lua 0.2-0.6 ms of
`_update` and 0.9-1.7 ms of `_draw`, audio 11% of a core with no underruns, 63-75 KB of internal RAM and 4.75-4.98 MB of PSRAM free, script
memory 62 KB. The cause of the canvas cost was not looked for; the data cache was made 32 KB and the code run from PSRAM on 22 October
(95efeb7), after the 14 October measurements.

