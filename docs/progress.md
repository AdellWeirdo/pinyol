# Progress log

What was done, measured and left, step by step. Newest at the bottom. The plan is the research report's
(GBA-like virtual hardware, then Lua, then tools); measurements are in measurements.md.

## 2026-10-12 · Step 2: the slow screens

Measured on the board, CPU per frame for the world plus all 15 panel strips (the DMA of the strips overlaps it):

| Screen | Adventure A | Adventure B |
|---|---|---|
| Walking | 5.3 ms | 6.4 ms |
| Dialogue | 8.2-8.8 ms | 8.6 ms |
| Bag | 14.7 ms | 13.9 ms |
| Puzzles | 7.7 / 10.9 ms | 11.1 / 8.1 ms |
| Bag with a dialogue over it | 20.2 ms | |

What it took, all pixel-identical (48 scripts, CRC per frame, strips checked against whole frames):

- Cut-corner cards (adventure B's theme) drawn column by column, each pixel once: shadow only where it shows, ink on
  the border, paper inside, and only the columns inside the window. Before: three full-area passes, and the corner
  rows became one-pixel runs on a turned strip.
- Masked blits copy or skip 8 pixels per mask byte on plain buffers: adventure A's world went from ~4.5 to ~2 ms.
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
slower: adventure A's bag (about 15 ms of drawing) and an item's close-up over the bag (about 35 ms a frame).

**Board note (night of 2026-10-12):** after many flash/reset cycles the board's USB stopped answering (esptool: "No
serial data received"); it needs the cable unplugged and plugged back in. Until then the console runs the play bench
(`-DBP_BENCH=play`), not the game list. To put the normal firmware back:
`cd firmware && idf.py -DBP_BENCH=OFF build && esptool.py --chip esp32s3 -p /dev/cu.usbmodem101 -b 921600 write_flash 0x20000 build/pinyol_console.bin`
(commit 25661b4 or later). Pau reconnected the cable the same night and the console got the normal firmware back
(25661b4: game list, 60 fps on TE). Board flashing kept to a minimum from here.

## 2026-10-12 · Phases 2 and 3: the virtual hardware and Lua

- **PPU** (`src/ppu.c`, 459a1e4): the GBA's model in software. Four layers (tiles, affine, bitmap), 128 sprites
  (indexed or direct colour, turned and scaled by 32 matrices), palettes with banks, alpha blending and fades, two
  windows and an object window, mosaic, and per-line tables (scroll, affine, windows, backdrop, blend). The frame is
  240×160, scaled 2× into the panel strips with text and panels drawn on top at 480×320.
- **pinyol@2, games in Lua** (e68b9b2): Lua 5.4 with 32-bit numbers on every platform, in a sandbox (memory quota,
  instruction budget per call, no io/os/debug, source-only `load`, `require` inside the game folder). The API is in
  [lua.md](lua.md). v1 games (the data adventures) run as before, unchanged to the pixel.
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
  end screen with a full-screen fade: 51-54 fps). The two adventures' play bench after the IRAM and cache
  changes: no regression (55-61 fps in play, adventure B a steady 60-61; adventure A's bag with a dialogue over it is
  still ~32 ms a frame, as before).

## 2026-10-12 · A fifth genre, safety, and the slow screens again

- **aldea**, a top-down adventure: a village drawn as a Tiled map (three layers: ground, what stands on it, tree tops
  in front of the characters), people with dialogue typed out in a box, a key and a chest, a waltz in notes. 60 fps on
  the console. The five Lua examples now cover platformer, shoot-'em-up, Mode 7 racing, touch puzzle and adventure.
- **Saved games:** `store()` keeps tables (inventories, progress), written through a temporary file so a power cut
  never leaves half a save. Games installed in the flash save on the card when there is one (a flash write stalled
  the console ~0.3 s).
- **Safety:** an API fuzzer (every Lua function with NaN, infinities, huge numbers, wrong types and bad names, under
  ASan/UBSan), a damaged-assets fuzzer (`tests/fuzz_assets.py`) and a damaged-modules fuzzer, plus a code review of
  the night's work, found and fixed: float and integer overflows at the API boundary, asset sizes that wrapped on
  32-bit targets, an instruction limit that `pcall` in a loop could escape, two over-reads in pocketmod, a zip bomb
  in the web player, names that could reach outside the game folder. Known limit: a game can still stall itself
  inside one C call (a pathological Lua string pattern); on the console the watchdog restarts it.
- **The web:** `tools/make_gallery.py` builds a shelf of games (each playable and downloadable) for the site.
- **The adventures' bag:** what lies under the bag and the notebook is drawn only where it shows. Per
  screen on the console: adventure A's bag 14.7 → 10.4 ms, bag with a dialogue 20.2 → 14.2 ms, adventure B's bag
  13.9 → 9.9 ms. Then occlusion for the whole stack and a faster 2× blit: an item's close-up 14.8 → 11.6 ms (60 fps),
  over the bag 27.2 → 18.5 ms (still ~30 fps there).

## 2026-10-13 · What creative games need: hearing, stories, rhythm, turning, video, the console itself

Pau's own game ideas (a buried village that remembers, ritual mechas, a cat's life, raising a child, live 90s TV that
turns on the player, castells, a festa's dances, rafts on rivers, a metro that should not exist) were the yardstick.
Six things pinyol lacked, added on branch `fases` (local commits, all tests green after each):

- **The microphone:** `mic()` gives level, pitch (McLeod's NSDF, 69-1000 Hz) and a hit on the tick a sudden sound
  starts; `mic_record(id, s)` turns what it hears into a sound. Console: the ES8311's ADC on the same I2S stream as
  the sound (full duplex, +6 KB of DMA). Browser: verified in Chromium with a fake microphone playing 440 Hz (level
  0.889 against 0.894 worked out; pitch 440.1 Hz), without the browser's auto gain and noise suppression.
  **Not tried on the console yet** (`MIC_GAIN`, `MIC_PGA` in audio_out.c are guesses to tune; is there a microphone
  on the board at all?).
- **Stories:** `lib/story.lua`, conversations written as plain text (knots, who says what and with which mood,
  choices once or always with indented bodies, `[if]`, `[do]`, `[var]`, `{expr}`), saved with `store()`.
  `file(name)` reads any text file of a game.
- **The song's clock:** `music_time()`, the samples of the song the speaker has played, for rhythm games; it takes
  off what is queued (the console's DMA queue, 70 ms, a guess not yet checked against the microphone).
- **Bodies that turn:** boxes and circles with `turns = true`, convex polygons, water with lift, drag and current.
  First in Lua: on the console 10 turning boxes took **32 ms** a tick, 25 took 85 ms (measured on the board).
  Then in C (`src/lua_physics.c`), about 20 times faster on a desktop: 25 turning boxes 0.83 → 0.04 ms (not measured
  on the board again). Bodies that do not turn keep the old Lua path, bit for bit (checked).
- **Video:** `tools/clip2npv.py` and `video(id)`: a palette clip of changed runs, played on a canvas, seek, loop,
  speed and backwards. 6 s of 213x160 at 15 fps: 451 KB. 22 broken clips fail or play, never crash (ASan).
- **The console itself:** `led(0xRRGGBB)` lights the pilot LED (red and green) and `battery()` gives level and
  charging; in the browser a light on the player's page and the Battery API.

Found on the way, not fixed: the API fuzzer with a different random sequence finds strips that differ from the whole
frame (455 pixels on main itself) on odd PPU settings; the fuzzer keeps its old sequence and the new functions get a
storm of their own.
2026-10-17: not seen again: 92 other sequences of the fuzzer, every strip the same as the whole frame. The fuzzer now
also storms the PlayStation and Saturn functions (quad, grad, light, warp, linetint, img's new mixes, reverb, the
sounds' pan and envelope) with arguments in their shape, so most of them draw and the strips are compared; 25
sequences of that under ASan and UBSan, no findings.
2026-10-18: 50 explicit `math.randomseed` values (1–50), 120 ticks each, with `--check-strips`: no mismatch. The original
failing sequence was not recorded, so the 455-pixel mismatch remains unproven as fixed.

Measured on the console afterwards (autotest builds with the speaker on, `-DBP_LOUD=ON`):

| What | Result |
|---|---|
| Physics, 10 / 25 / 40 boxes that turn | 2.4 / 5.3 / 8.7 ms a tick (in Lua it was 32 ms for 10, 85 ms for 25) |
| Physics, 25 that turn + 30 plain circles | 23.9 ms: the plain bodies' Lua path is now what limits a big pile |
| Microphone | there is one and it works: at the full gain (42 dB) the speaker's 880 Hz square reads level 0.76 with its note found every tick; silence reads 0 |
| A click from the speaker, heard | 6-7 ticks later (~100-115 ms round trip: the 70 ms queued for the speaker, the microphone's block, the tick) |
| Video, 213x160 at 15 fps at scale 2, with its sound, from the flash | 61 fps, a tick 0.5 ms on average with the decoding |

Not checked by eye yet: the LED's colours.
