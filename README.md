# np2d

A small C engine for 2D games on the **RetroGo** console, an open-source handheld built on an ESP32-S3 (480×320 touch screen, buttons, speaker, microSD).

A game is **a folder**: copy it to the console's microSD under `games/<id>/` and it appears in the game list. The same folder runs in a desktop simulator and in the browser. There are two kinds:

- **Lua games** (`"engine": "np2d@2"`), any genre. The engine gives them a virtual console modelled on the Game Boy Advance: four background layers (tiles, rotated and scaled, Mode 7), 128 sprites, palettes, transparency, windows, mosaic and per-line effects, with text drawn on top at full resolution. They hold 60 fps on the console. The API: [docs/lua.md](docs/lua.md).
- **Adventures made of data** (`"engine": "np2d@1"`): JSON for zones, dialogues, items, puzzles and events, no code. Bajo Pueblo and Geumgye are made this way: [docs/game-format.md](docs/game-format.md).

![Four Lua games: a platformer, a shoot-'em-up, a Mode 7 kart race and the starting template](docs/examples.png)

## Quick start

macOS: `brew install cmake sdl2 uv`. On Linux, install the same three with your package manager (`libsdl2-dev`).

```sh
cmake -B build && cmake --build build
./build/bp_sim --game examples/plataformas   # or naves, carreras, hola
ctest --test-dir build                       # validates every example and plays its test script
```

| Action | Keyboard | Console |
|---|---|---|
| Move | Arrows / WASD | D-pad |
| A: interact, advance, jump, fire | Enter, E, Space, Z | A |
| B: back | Esc, Backspace, X | B |
| Cycle target, puzzle help | Tab, C | C |
| Bag | I | MENU |
| Pause | P | START |
| Touch | Mouse | Screen |

## Make your own game

### In Lua

```sh
uv run tools/new_game.py games/mygame --lua --title "My Game"
./build/bp_sim --game games/mygame
```

You get a small game to change: a room bigger than the screen, a character to walk around it, gems to pick up, sounds and a best time saved. `main.lua` is the game, `room.lua` the room as text, and `art.py` draws the art and converts it (replace its PNGs with your own and run it again). Everything else is in [docs/lua.md](docs/lua.md), and the examples show more:

| Example | What it shows |
|---|---|
| [plataformas](examples/plataformas) | a platformer: parallax layers, see-through water with a wavy per-line scroll, mosaic transitions |
| [naves](examples/naves) | a shoot-'em-up: a star field with a speed per line, a turning planet, blended explosions, a flash |
| [carreras](examples/carreras) | a kart race in Mode 7: a perspective floor, rivals as scaled sprites, laps and positions |
| [puzle](examples/puzle) | a sliding puzzle for the touch screen: a ghost hint by blending, a mosaic reveal, music made of notes |

### As an adventure made of data

```sh
uv run tools/new_game.py games/mygame --title "My Game"
./build/bp_sim --game games/mygame
./build/bp_headless --game games/mygame --validate     # every ID exists, every text fits
```

`new_game.py` writes a tiny but complete game: two zones, a player, a friend with a dialogue choice, a key, a locked door, a chest and the end screen. All its art is placeholder drawn by code. Then make it yours:

- **Text and logic** are JSON. The full reference is [docs/game-format.md](docs/game-format.md).
- **Art**: draw a PNG and convert it under the same ID. Character sheets are horizontal strips in direction order N, E, S, W.
  ```sh
  uv run tools/png2asset.py street.png games/mygame/assets BG_Z01 --type background
  uv run tools/png2asset.py hero_walk.png games/mygame/assets PJ_WALK --frames 16 --ms 125 --anchor 12,29
  ```
- **Sound**: WAV, PCM 16-bit mono at 22,050 Hz.
- **Fonts**: `tools/ttf2fnt.py` turns a pixel TTF into the engine's FNT format.
- **Tests**: a script plays the game with real input and checks flags, zones and screens. See [tests/hola.script](tests/hola.script); run it with `./build/bp_headless --game DIR --fresh --script FILE`, and `tools/record.sh` records the run as a video.

## A game in its own repo

A bigger game can live in its own repository and build np2d as a subproject, with its own tests:

```cmake
cmake_minimum_required(VERSION 3.21)
project(mygame C)
set(GAME_DIR ${CMAKE_SOURCE_DIR}/games/mygame)  # what bp_sim and bp_headless open by default
add_subdirectory(../np2d np2d)                  # bp_core, bp_headless, bp_sim
enable_testing()
add_test(NAME validate COMMAND bp_headless --game ${GAME_DIR} --validate)
```

Bajo Pueblo and Geumgye are built this way.

## Share a game, play it in the browser

```sh
python3 tools/pack_game.py games/mygame -o dist/      # -> dist/mygame.zip, a folder mygame/ inside
```

Unzipped into the card's `games/` folder, the game is installed. The same zip plays in a browser: the simulator builds with [Emscripten](https://emscripten.org) into `player.html`, which plays any game's zip, given as `player.html?game=URL` or dropped on the page, with on-screen buttons on phones and saves kept in the browser.

```sh
emcmake cmake -B build-web -DCMAKE_BUILD_TYPE=Release
cmake --build build-web --target np2d_player
cp dist/mygame.zip build-web/
python3 -m http.server -d build-web     # open http://localhost:8000/player.html?game=mygame.zip
```

The `np2d_web` target makes `index.html` instead, with one game (`-DGAME_DIR=...`) packed inside.

## Run it on the console

The firmware in [firmware/](firmware/) is the console's platform: screen, touch, buttons, audio, microSD, a game list, battery and updates over the card. It needs [ESP-IDF 5.4](https://docs.espressif.com/projects/esp-idf/en/v5.4.2/esp32s3/get-started/).

```sh
. $IDF_PATH/export.sh
cd firmware
idf.py build
idf.py -p /dev/cu.usbmodem1101 flash        # your board's port
```

The firmware also bakes games into the flash, so the console works without a card: `examples/hola` by default, or a list, `idf.py -DFLASH_GAME="/abs/a;/abs/b" build` (then flash `build/game.bin` too, at 0x420000). Every other game goes on the microSD (FAT32) as `games/<id>/`. Holding MENU for two seconds leaves a Lua game for the list. To update the firmware later, copy `build/np2d_console.bin` to the card as `firmware.bin`.

Pins and peripherals, each with its source: [docs/hardware.md](docs/hardware.md).

## How it is built

```
src/             the engine, portable C11: no SDL or ESP-IDF headers (hal.h is the whole platform contract)
  ppu.c          the virtual picture processor (layers, sprites, effects) that Lua games draw with
  lua_game.c     np2d@2: the Lua sandbox and its API
platform/sdl/    desktop simulator, and the web players when built with Emscripten
platform/null/   bp_headless: validator and test runner without a window
platform/web/    the web pages around the players
firmware/        the console: ESP-IDF project, builds src/ unchanged
examples/        games as they go on the microSD: four in Lua, hola as data
templates/lua/   the game new_game.py --lua starts from
tests/           test scripts for the examples, and the PPU's own tests
tools/           new_game.py, png2asset.py, pack_game.py, ttf2fnt.py, record.sh, remote.py
third_party/     cJSON, Lua 5.4, the Pixelify Sans font
```

The world is 240×160 logical pixels drawn at 2× into a 480×320 frame; text and UI use the full resolution. Logic runs at 60 ticks per second on every platform. On the console the frame goes to the panel in 32-row strips drawn straight from the game while the previous strip is sent, in step with the panel's refresh; a Lua game's picture is drawn by both cores. How it got fast enough, measured: [docs/measurements.md](docs/measurements.md).

## Status

np2d was written for two games, *Bajo Pueblo* and *Geumgye*, and then opened up with Lua for any genre. What to know:

- The Lua API (`np2d@2`) is new and may still change; the data format (`np2d@1`) is stable.
- The built-in interface text of data adventures (menus, pause, bag) is in Spanish.
- Some np2d@1 defaults come from the first game: without a `"player"` in `game.json` the player is `KLAUS` with sprite prefix `KL`, and the start zone defaults to `Z01`. Set them in your `game.json`.
- What was done and measured, step by step: [docs/progress.md](docs/progress.md).

## License

np2d is MIT licensed ([LICENSE](LICENSE)). It includes [cJSON](third_party/cjson/LICENSE) (MIT), [Lua 5.4](third_party/lua/LICENSE) (MIT) and the [Pixelify Sans](third_party/pixelify/OFL.txt) font (SIL Open Font License 1.1).
