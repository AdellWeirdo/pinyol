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
