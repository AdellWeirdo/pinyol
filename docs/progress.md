# Progress log

What was done, measured and left, step by step. Newest at the bottom. The plan is the research report's
(GBA-like virtual hardware, then Lua, then tools); measurements are in measurements.md.

## 2026-10-12 · Step 2: the slow screens

Measured on the board, CPU per frame for the world plus all 15 panel strips (the DMA of the strips overlaps it):

| Screen | Bajo Pueblo | Geumgye |
|---|---|---|
| Walking | 5.3 ms | 6.4 ms |
| Dialogue | 8.2-8.8 ms | 8.6 ms |
| Bag | 14.7 ms | 13.9 ms |
| Puzzles | 7.7 / 10.9 ms | 11.1 / 8.1 ms |
| Bag with a dialogue over it | 20.2 ms | |

What it took, all pixel-identical (48 scripts, CRC per frame, strips checked against whole frames):

- Cut-corner cards (Geumgye's theme) drawn column by column, each pixel once: shadow only where it shows, ink on
  the border, paper inside, and only the columns inside the window. Before: three full-area passes, and the corner
  rows became one-pixel runs on a turned strip.
- Masked blits copy or skip 8 pixels per mask byte on plain buffers: Bajo Pueblo's world went from ~4.5 to ~2 ms.
- gfx_blit2x on windows walks columns with a stepping pointer.
- Dialogue choices count their wrapped lines once (cached until the choices or the font change): a 4-choice menu
  wrapped text ~20 times per strip, 300 times a frame.

Real play (end-to-end tests, frames as fast as they come): 54-89 fps in 5 s windows, most above 75.

## 2026-10-12 · Step 2: frames in step with the panel

The panel's TE line now pulses once per frame (it pulsed every line too) and the firmware starts sending a frame on
that pulse, so the strips (8 ms) always run ahead of the panel's scan (16.3 ms): no frame shows half old, half new.
The zone is drawn before waiting (`game_draw_world`), so only the fast strip composition runs after the pulse; if
the pulse came less than 3 ms ago the frame goes straight out instead of waiting a whole refresh.

Real play: steady 60-61 fps (the panel refreshes at 61.5 Hz), about 5 ms a frame left waiting for the scan. Still
slower: Bajo Pueblo's bag (about 15 ms of drawing) and an item's close-up over the bag (about 35 ms a frame).

**Board note (night of 2026-10-12):** after many flash/reset cycles the board's USB stopped answering (esptool: "No
serial data received"); it needs the cable unplugged and plugged back in. Until then the console runs the play bench
(`-DBP_BENCH=play`), not the game list. To put the normal firmware back:
`cd firmware && idf.py -DBP_BENCH=OFF build && esptool.py --chip esp32s3 -p /dev/cu.usbmodem101 -b 921600 write_flash 0x20000 build/np2d_console.bin`
(commit 25661b4 or later). Pau reconnected the cable the same night and the console got the normal firmware back
(25661b4: game list, 60 fps on TE). Board flashing kept to a minimum from here.

## 2026-10-12 · Phases 2 and 3: the virtual hardware and Lua

- **PPU** (`src/ppu.c`, 459a1e4): the GBA's model in software. Four layers (tiles, affine, bitmap), 128 sprites
  (indexed or direct colour, turned and scaled by 32 matrices), palettes with banks, alpha blending and fades, two
  windows and an object window, mosaic, and per-line tables (scroll, affine, windows, backdrop, blend). The frame is
  240×160, scaled 2× into the panel strips with text and panels drawn on top at 480×320.
- **np2d@2, games in Lua** (e68b9b2): Lua 5.4 with 32-bit numbers on every platform, in a sandbox (memory quota,
  instruction budget per call, no io/os/debug, source-only `load`, `require` inside the game folder). The API is in
  [lua.md](lua.md). v1 games (Bajo Pueblo, Geumgye) run as before, unchanged to the pixel.
- **Three genres as examples** (48f0194, a8cff5a): `plataformas` (platformer: parallax, see-through water with a wavy
  line scroll, mosaic transitions), `naves` (shoot-'em-up: per-line star parallax, a turning affine planet,
  blended explosions, a bomb flash), `carreras` (Mode 7 kart race: perspective floor, rivals as scaled sprites
  placed with `project`). Each has its art drawn by `art.py` and a test script.
- **On the console** (this commit): the examples first ran at 26-30 fps; now all three hold 60 fps. The steps are in
  [measurements.md](measurements.md#lua-games-on-the-ppu-2026-10-12). The firmware also gained: Lua in the core
  component, a scrolling game list (up to 32 games), games in the flash listed with those on the card, holding MENU
  for two seconds leaves a Lua game, and `-DFLASH_GAME` taking a list of folders (their tests run in autotest builds).

## 2026-10-12 · Making games: tools, sound, a fourth example, the browser

- **Start a game:** `tools/new_game.py games/mygame --lua` copies `templates/lua` (a room to walk with gems, a camera,
  sounds, a best time) and draws its art; ctest makes one from scratch and plays it.
- **Levels from Tiled:** `tools/tiled2asset.py` turns a `.tmx` or JSON map into PPU layers and a Lua module with the
  cells, the tiles' properties and the objects.
- **Sound:** four synthesised voices like the GBA's (`tone`, `note`: square, triangle, saw, sine, noise, with envelope
  and slide), and tracker music (`music("SONG")` plays `audio/SONG.mod`, through pocketmod). On the console a module
  takes 3 % of a core, the voices 4-5 %. Fuzzing pocketmod with 20,000 damaged modules under ASan/UBSan found two
  bugs, both fixed.
- **puzle**, a sliding puzzle for the touch screen: pieces as sprites, a ghost hint by blending, a mosaic reveal,
  music made of notes; its picture was generated with an image model. 61 fps on the console.
- **API:** `show(layers)` (the GBA's display control), `text()` wraps and types out, `perf()`; `textw()` without a
  font no longer fails. Test scripts can `tap X Y`.
- **Share and play in the browser:** `tools/pack_game.py` makes `<id>.zip`; `player.html` plays any game zip from a
  URL or dropped on the page, with on-screen buttons on phones and saves in the browser.
- **Checks on the console:** all five Lua examples pass their tests on the board at 60 fps in play (plataformas'
  end screen with a full-screen fade: 51-54 fps). Bajo Pueblo and Geumgye's play bench after the IRAM and cache
  changes: no regression (55-61 fps in play, Geumgye a steady 60-61; Bajo Pueblo's bag with a dialogue over it is
  still ~32 ms a frame, as before).
