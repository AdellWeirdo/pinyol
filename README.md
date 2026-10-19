# pinyol

[![tests](https://github.com/ipaud/pinyol/actions/workflows/ci.yml/badge.svg)](https://github.com/ipaud/pinyol/actions/workflows/ci.yml)

English · [Español](README.es.md) · [Català](README.ca.md)

**[Play every example in your browser](https://pinyol.ipaud.dev/)**, with the engine's measures on the console.

<p align="center"><img src="docs/media/logo.webp" alt="pinyol" width="480"></p>

A small C engine for 2D games on the **Cirera** console, an open-source handheld built on an ESP32-S3 (480×320 touch screen, buttons, speaker, microSD).

<p align="center"><img src="docs/media/console.webp" alt="The console, a Freenove FNK0104N board, starting up: pinyol's intro, Cirera's menu with its games and some of them running" width="480"></p>

A game is **a folder**: copy it to the console's microSD under `games/<id>/` and it appears in the game list. The same folder runs in a desktop simulator and in the browser. There are two kinds:

- **Lua games** (`"engine": "pinyol@2"`), any genre. The engine gives them a virtual console modelled on the Game Boy Advance: four background layers (tiles, rotated and scaled, Mode 7), 128 sprites, palettes, transparency, windows, mosaic and per-line effects, with text drawn on top at full resolution. They hold 60 fps on the console. Beyond the screen and the buttons: the microphone (level, pitch, claps, recordings), stories written as plain text, a song's clock for rhythm games, bodies that tip over, roll and float, video clips on canvases, the console's LED and battery, and consoles playing together. The API: [docs/lua.md](docs/lua.md).
- **Adventures made of data** (`"engine": "pinyol@1"`): JSON for zones, dialogues, items, puzzles and events, no code. The engine's first games were made this way: [docs/game-format.md](docs/game-format.md).

A game looks like the console it is made for, and the engine moves them all: pick a look and follow its recipe in
[docs/art.md](docs/art.md#0-choose-a-look). Each picture is a moment of play in that look's example (`docs/looks/shots.sh`
takes them again).

| | |
|---|---|
| ![A Game Boy platformer in four tones of green, on the whole screen](docs/looks/gameboy.png) | ![A ZX Spectrum room: blocks of two colours, a miner and a guardian](docs/looks/spectrum.png) |
| **Game Boy**: [bolsillo](examples/bolsillo), all its art drawn by code | **ZX Spectrum**: [cinta](examples/cinta), from the tape loading |
| ![A Game Boy Advance platformer with parallax mountains and water](docs/looks/gba.png) | ![A 16-bit speed platformer: checkered earth, a sea moved line by line](docs/looks/16bits.png) |
| **Game Boy Advance**: [plataformas](examples/plataformas) | **SNES / Mega Drive**: [veloz](examples/veloz), all its art drawn by code |
| ![A Neo Geo fighting game: two big fighters on a pier at sunset](docs/looks/neogeo.png) | ![A CPS2 fighting game: fighters in 15 colours on a floor in perspective](docs/looks/cps2.png) |
| **Neo Geo**: [duelo](examples/duelo) | **CPS2**: [torneo](examples/torneo) |
| ![A PICO-8 brick breaker: 128x128 in sixteen colours](docs/looks/pico8.png) | ![A pocket LCD game: a cook catching eggs, figures on or off](docs/looks/lcd.png) |
| **PICO-8**: [ladrillos](examples/ladrillos), no pictures | **Pocket LCD**: [huevos](examples/huevos), all polygons |
| ![A vector arcade game: glowing lines on black](docs/looks/vector.png) | ![A vertical shoot-'em-up, shown turned: hold the console on its side](docs/looks/vertical.png) |
| **Vector arcade**: [rocas](examples/rocas), no pictures | **Vertical screen**: [tormenta](examples/tormenta), the console on its side |
| ![A first-person maze: stone corridors and a ghost, Wolfenstein-style](docs/looks/firstperson.png) | ![A ZX Spectrum loading screen: a miner in a crystal cave, two colours a block](docs/looks/loading.png) |
| **First person**: [laberinto](examples/laberinto), `raycast()` | **ZX Spectrum**: [cinta](examples/cinta)'s tape loading |
| ![A gothic castle hall: candle glows, a half-seen ghost and a huntress with a whip](docs/looks/32bits.png) | ![The skull boss turning and swelling, its fireballs glowing](docs/looks/32bits_boss.png) |
| **PlayStation / Saturn 2D**: [gotico](examples/gotico) | **PlayStation / Saturn 2D**: its boss |

## Quick start

macOS: `brew install cmake sdl2 uv`. On Linux, install the same three with your package manager (`libsdl2-dev`).

```sh
cmake -B build && cmake --build build
./build/pinyol_sim --game examples/plataformas   # or naves, carreras, hola
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
| Restart the game (the simulator also restarts it when you save one of its files) | F5 | |

## Make your own game

### With a coding agent

On a Mac, install [Homebrew](https://brew.sh) (it brings git and Apple's compiler with it) and an agent, for example
Codex: `brew install codex`, then `codex login` with a ChatGPT account. Clone this repository, open the agent in its
folder (`codex`) and ask for the game you want, in any language. It reads [AGENTS.md](AGENTS.md), installs what is
missing (approve it when it asks: installing runs outside its sandbox), builds the engine, makes the game in
`games/<id>/` and plays it with a test to check it. `./build/pinyol_sim --game games/<id>` plays it on your screen.
The site's [ladder](https://pinyol.ipaud.dev/crear/#codex) shows five games Codex made this way, from a paddle game to a
Mega Drive speed platformer, each with its request, its time and tokens, and its frame rate on the console.

### Without code: the editor

<p align="center"><a href="https://pinyol.ipaud.dev/video/linea0.mp4"><img src="docs/media/editor.webp" alt="LÍNEA 0 being made in the editor: drawings, maps, rules and play" width="640"></a><br>
<sub>LÍNEA 0, a Game Boy Advance game made entirely with the editor, live, here sped up: <a href="https://pinyol.ipaud.dev/video/linea0.mp4">the whole video</a>.</sub></p>

`editor/` is a web page for making a game without programming: draw the pictures pixel by pixel (with frames for
animation) or bring them in from image files (PNG with transparency, JPG, a row of frames; dropped or pasted), in
any of the console's colours; paint the levels' maps with them and put the objects on them (a player who walks and
jumps, enemies that patrol or chase, coins), with up to three pictures behind each that move slower than the camera,
and a cover before the first; make the sounds from recipes (coin, laser, explosion, jump...) or bring them in from
files (WAV, MP3, OGG...: effects, and music for each level and the cover, cut and made louder or softer), or compose a
song on a grid (melody, bass and drums, in a scale where every note fits); write the rules
with blocks ("when the hero touches a coin: remove the other, play coin, add 1 to points"; "when the hero touches
the flag: go on to the next level"), and with the blocks of Diálogos (characters who speak and ask, the game waiting
for the answer), Micrófono (when you clap, when you blow, how loud) and Vídeo (a video brought in from a file or a GIF,
over the whole screen or in a window), and Guardar (a record or progress kept in the console); music can also come as a
tracker's `.mod`. The cover is also the game's picture in the console's menu, with a line, an author and what it is about.
**Jugar** plays it right there; **Pasar a la consola** sends it over the USB
cable (Chrome and Edge, with Web Serial) or gives the zip for the card. A short guide walks a first-time user through
it (again with **?**); everything works from the keyboard too, and on a phone or a tablet. A game takes a **look**
(Game Boy, PICO-8, ZX Spectrum, 16 bits, or free): its console's colours for every drawing, its tiles (8 or 16
pixels), its letters and the colours of its texts; and a language for the sentences the engine says. Objects can have
named animations (still, walking, hit), and the Lives and time blocks put hearts and a countdown on the screen.
**Nuevo** starts from one of six games to change, each with its own drawings, levels and rules: a platformer, an
adventure seen from above (keys and doors), a space shooter, a box-pushing puzzle and **Abella**, a whole Game Boy
game in three levels (made live in the editor, and the first game in the site's Library), and **LÍNEA 0**, a
Game Boy Advance game in five levels of five genres about a metro that does not obey its own rules (made live too: its
video is on the site). The interface is in
Spanish, Catalan or English (chosen in the header, **Idioma**). It needs the web player beside it (see [below](#share-a-game-play-it-in-the-browser) to build it):

```sh
python3 tools/make_editor.py dist/editor --player build-web
python3 -m http.server -d dist/editor    # open http://localhost:8000
```

The editor keeps the project in the browser (IndexedDB) as it changes; **Guardar archivo** saves it to a file (`.pinyol.json`) and
**Abrir** opens it again. The game it makes is ordinary Lua on the `kit` library ([lib/kit.lua](lib/kit.lua)), so it
can be carried on by hand; it carries its own copy of kit, so it plays the same on a console with older firmware.

### In Lua

```sh
uv run tools/new_game.py games/mygame --lua --title "My Game"
./build/pinyol_sim --game games/mygame
```

You get a small game to change: a room bigger than the screen, a character to walk around it, gems to pick up, sounds and a best time saved. `main.lua` is the game, `room.lua` the room as text, and `art.py` draws the art and converts it (replace its PNGs with your own and run it again). **[docs/tutorial.md](docs/tutorial.md) takes it from there step by step**, to a game on the console and in the browser. Levels can be drawn in [Tiled](https://www.mapeditor.org) and imported with `tools/tiled2asset.py`. Art made with an image model (backgrounds removed, frames cut, scale and feet fitted): [docs/art.md](docs/art.md). Everything else is in [docs/lua.md](docs/lua.md), and the examples show more:

| Example | What it shows |
|---|---|
| [plataformas](examples/plataformas) | a platformer: parallax layers, see-through water with a wavy per-line scroll, mosaic transitions |
| [naves](examples/naves) | a shoot-'em-up: a star field with a speed per line, a turning planet, blended explosions, a flash |
| [carreras](examples/carreras) | a kart race in Mode 7: a perspective floor, rivals as scaled sprites, laps and positions |
| [puzle](examples/puzle) | a sliding puzzle for the touch screen: a ghost hint by blending, a mosaic reveal, music made of notes |
| [aldea](examples/aldea) | a top-down adventure: a village drawn in Tiled, people with typed-out dialogue, tree tops you walk behind |
| [estilos](examples/estilos) | a game's own look: fonts from the library, outlined and wavy text, frames cut from a picture, turned pictures |
| [inventos](examples/inventos) | toys of no genre, from code alone: painting, land that breaks, generative trails, 3D triangles, a split screen |
| [juntos](examples/juntos) | consoles playing together over the air (ESP-NOW, no router): a shared whiteboard, a ball passed from screen to screen |
| [asalto](examples/asalto) | a run and gun: a heroine with a machine gun, scrap robots that explode, a walking tank at the end of a long street |
| [nubes](examples/nubes) | a horizontal shoot-em-up over a sea of clouds: drones in formation, a battleship that fills the sky with orbs (swarms) |
| [calle](examples/calle) | a beat-em-up on a neon street at night: depth, groups of thugs, the camera stopping at each fight |
| [futbol](examples/futbol) | five a side on a pitch twice the screen's width: four kits that are one picture in four palettes |
| [moto](examples/moto) | a motorbike race: the road on the world's Mode 7 floor, the coast, the roadside and the rivals at full resolution over it |
| [duelo](examples/duelo) | a fighting game as a Neo Geo's: every pixel at 480x320, a stage in two layers, fighters in 192x184 frames as packed pictures, hit flashes and sparks, a rival played by the console |
| [torneo](examples/torneo) | a fighting game as a CPS2's: fighters in 15 colours and thirty frames, never zoomed, a floor in perspective drawn in bands of rows, pillars in front, the same fighter twice in other colours |
| [mazmorra](examples/mazmorra) | a beat-em-up in a dungeon as a CPS2's: goblins and skeletons in groups, torches that flicker, pillars that pass in front of everyone |
| [bolsillo](examples/bolsillo) | a platformer as a Game Boy's, on the whole screen: four tones, C changes them; all its art drawn by code |
| [cinta](examples/cinta) | a game as a ZX Spectrum's, from the tape loading (striped border, the screen in its own order): blocks of two colours, sprites that clash, a flashing key, air running out |
| [veloz](examples/veloz) | a speed platformer as the 16-bit consoles': a sea moved line by line, a sky in a gradient, pools seen through, a Mode 7 title; a pangolin that rolls into a ball |
| [ladrillos](examples/ladrillos) | a brick breaker as a PICO-8 cartridge: a 128x128 screen in its sixteen colours, drawn again every frame; no pictures |
| [huevos](examples/huevos) | a pocket LCD game: figures on or off (their ghosts still show) over a printed picture, a step and a beep at a time |
| [rocas](examples/rocas) | a vector arcade game: bright lines with a glow, even the letters; no pictures |
| [tormenta](examples/tormenta) | a vertical shoot-'em-up played with the console on its side: a standing canvas shown turned, hundreds of bullets |
| [laberinto](examples/laberinto) | first person as Wolfenstein 3D drew it: raycast() draws the maze from inside, textured and fogged, ghosts and gems standing in it |
| [gotico](examples/gotico) | a castle hall at night as the 32-bit consoles drew it: candle light added, a ghost and a dash's afterimages half seen through, a skull boss that turns and swells |
| [psx_views](examples/psx_views) | one actor and three staged PS1-style cameras: lateral, fixed with foreground occlusion, and a corridor seen from behind; the same position and state survive every cut |
| [sonidos](examples/sonidos) | sounds made from numbers (a factory of coins, lasers, explosions), a theremin, an engine that follows the speed, music in layers, a keyboard that plays one recording as any note |
| [control](examples/control) | directing a 1994 newscast from the control room: cuts, tape and captions on the beat of the theme, the producer's lines written as a story in Catalan and Spanish, the console's LED as the tally light, a video clip on a monitor; then a camera that does not exist looks at you, hears you and knows your battery |
| [raton_de_biblioteca](examples/raton_de_biblioteca) | made by Codex from one sentence on a fresh clone: a Game Boy-look mouse in a library, cheese and cats (then put on the whole screen by hand) |
| [oxigeno](examples/oxigeno) | made by Codex from one sentence: a ZX Spectrum-look astronaut after oxygen bottles, with its tape loading screen |
| [museo_nocturno](examples/museo_nocturno) | made by Codex from one sentence: a first-person museum at night, five stolen paintings and guards |
| [paletes](examples/paletes) | made by Codex from one sentence: paddles and a ball against the console, in vectors, to 7 points |
| [pinball](examples/pinball) | a whole table on the screen, three balls, four bumpers and two flippers that turn about their ends (`physics` and its `w:drive`), a spring you pull with DOWN, a ball saver |
| [costa_relampago](examples/costa_relampago) | made by Codex in three requests (the game, its generated art, 60 fps on the console): a Mega Drive-look squirrel on a coast, layers at their own speeds and a sea moved line by line |

### As an adventure made of data

```sh
uv run tools/new_game.py games/mygame --title "My Game"
./build/pinyol_sim --game games/mygame
./build/pinyol_headless --game games/mygame --validate     # every ID exists, every text fits
```

`new_game.py` writes a tiny but complete game: two zones, a player, a friend with a dialogue choice, a key, a locked door, a chest and the end screen. All its art is placeholder drawn by code. Then make it yours:

- **Text and logic** are JSON. The full reference is [docs/game-format.md](docs/game-format.md).
- **Art**: draw a PNG and convert it under the same ID. Character sheets are horizontal strips in direction order N, E, S, W.
  ```sh
  uv run tools/png2asset.py street.png games/mygame/assets BG_Z01 --type background
  uv run tools/png2asset.py hero_walk.png games/mygame/assets PJ_WALK --frames 16 --ms 125 --anchor 12,29
  uv run tools/png2asset.py fighter.png games/mygame/assets SPR_KAI --frames 11 --packed   # big art: its own palette, a quarter of the memory
  ```
- **Sound**: WAV, PCM 16-bit mono at 22,050 Hz.
- **Fonts**: `tools/font2fnt.py` turns a TTF, OTF, BDF or PNG sheet into the engine's FNT format; twelve free pixel
  fonts come with it (`third_party/fonts`), so each game can have its own letters.
- **Tests**: a script plays the game with real input and checks flags, zones and screens. See [tests/hola.script](tests/hola.script); run it with `./build/pinyol_headless --game DIR --fresh --script FILE`, and `tools/record.sh DIR FILE out.mp4` records the run as a video.

## A game in its own repo

A bigger game can live in its own repository and build pinyol as a subproject, with its own tests:

```cmake
cmake_minimum_required(VERSION 3.21)
project(mygame C)
set(GAME_DIR ${CMAKE_SOURCE_DIR}/games/mygame)  # what pinyol_sim and pinyol_headless open by default
add_subdirectory(../pinyol pinyol)              # pinyol_core, pinyol_headless, pinyol_sim
enable_testing()
add_test(NAME validate COMMAND pinyol_headless --game ${GAME_DIR} --validate)
```

The data adventures pinyol started with are built this way.

The engine's checkout is found by the game's scripts through `PINYOL_ENGINE` (a path; `ENGINE` in some) and, failing that, a
sibling folder: `export PINYOL_ENGINE=~/Desktop/DEV/pinyol/pinyol-engine/pinyol` works wherever the game's repo lives.

## Share a game, play it in the browser

```sh
python3 tools/pack_game.py games/mygame -o dist/      # -> dist/mygame.zip, a folder mygame/ inside
```

Unzipped into the card's `games/` folder, the game is installed. The same zip plays in a browser: the simulator builds with [Emscripten](https://emscripten.org) into `player.html`, which plays any game's zip, given as `player.html?game=URL` or dropped on the page, with on-screen buttons on phones, a gamepad over USB or Bluetooth (standard layout: the bottom button is A), and saves kept in the browser. `?lang=ca` or `?lang=en` puts its words in Catalan or English.

```sh
emcmake cmake -B build-web -DCMAKE_BUILD_TYPE=Release
cmake --build build-web --target pinyol_player
cp dist/mygame.zip build-web/
python3 -m http.server -d build-web     # open http://localhost:8000/player.html?game=mygame.zip
```

The `pinyol_web` target makes `index.html` instead, with one game (`-DGAME_DIR=...`) packed inside.

A whole shelf of games, each playable and downloadable, with a picture of its title screen:

```sh
python3 tools/make_gallery.py gallery/ --player build-web --headless build/pinyol_headless examples/*
python3 -m http.server -d gallery       # open http://localhost:8000
```

A finished game can go in the site's [Library](https://pinyol.ipaud.dev/biblioteca/), to be played there and downloaded for the console: [send it with a form](https://github.com/ipaud/pinyol/issues/new?template=biblioteca.yml), a robot opens it, plays it for ten seconds and, once we review it, it shows up there.

<p align="center"><a href="https://pinyol.ipaud.dev/video/subir.mp4"><img src="docs/media/library.webp" alt="From the editor's .zip to the Library: the form, the robot's check, the approval and the game playing on the site" width="640"></a><br>
<sub>From your game to the Library, sped up: <a href="https://pinyol.ipaud.dev/video/subir.mp4">the whole tutorial</a>.</sub></p>

## Run it on the console

The quickest way: the site [installs the latest release](https://pinyol.ipaud.dev/consola/#consola) on a board over
USB, from Chrome or Edge, with fifteen games in its flash.

The firmware in [firmware/](firmware/) is the console's platform: screen, touch, buttons, audio, microSD, battery and updates over the card. It needs [ESP-IDF 5.4](https://docs.espressif.com/projects/esp-idf/en/v5.4.2/esp32s3/get-started/).

```sh
. $IDF_PATH/export.sh
cd firmware
idf.py build
idf.py -p /dev/cu.usbmodem1101 flash        # your board's port
```

A game can also go over the USB cable, straight from the editor (Chrome or Edge) or from a terminal: the console
writes it to the card (or, with none, its flash) and starts it.

```sh
uv run --with pyserial tools/send_game.py games/mygame     # a game folder, or a game's .zip
```

The firmware also bakes games into the flash, so the console works without a card: `examples/hola` by default, or a list, `idf.py -DFLASH_GAME="/abs/a;/abs/b" build` (then flash `build/game.bin` too, at 0x420000). Every other game goes on the microSD (FAT32) as `games/<id>/`. Holding MENU for two seconds leaves a Lua game for the list. To update the firmware later, copy `build/pinyol_console.bin` to the card as `firmware.bin`.

The console starts in **Cirera**'s menu, which is itself a pinyol game ([firmware/cirera](firmware/cirera)) baked
into the flash with the firmware: an animated intro, then every game as a card with its cover, to pick with the
d-pad and A (B asks before turning the console off). A game's cover is its `cover.rgb565`, a 240×160 picture that
`tools/cover.py` takes from a moment of play; without one, its title screen (`assets/BG_TITLE`) or a card with its name.

Pins and peripherals, each with its source: [docs/hardware.md](docs/hardware.md).

## Cirera on your computer: Mac, Windows and Linux

The console as an app: its menu, the examples inside, and any game's .zip dropped on its window, installed. Download it
from the [release "cirera"](https://github.com/ipaud/pinyol/releases/tag/cirera) or the [site](https://pinyol.ipaud.dev/consola/#escritorio), which says how to open it the first time (Apple
and Microsoft have not signed it yet). Its games and saves go to `~/Library/Application Support/pinyol/Cirera` on a
Mac, `%APPDATA%\pinyol\Cirera` on Windows, `~/.local/share/pinyol/Cirera` on Linux (x86_64 or aarch64, glibc 2.35 and
up; a dropped game is unpacked with unzip).

It is `pinyol_sim` built as the app, and `tools/make_app.py` packs it:

```sh
cmake -B build-app -DCMAKE_BUILD_TYPE=Release -DPINYOL_APP=ON
cmake --build build-app --target pinyol_sim             # -> build-app/Cirera (Cirera.exe on Windows)
python3 tools/make_app.py build-app/Cirera -o dist/     # -> dist/Cirera-mac.zip (Cirera-linux-*.tar.gz on Linux)
```

The Windows app is built from a Mac or Linux with MinGW-w64 (`cmake/mingw-w64-x86_64.cmake`).
[.github/workflows/desktop.yml](.github/workflows/desktop.yml) builds them all with SDL inside, so they need nothing
installed, and opens each one on its own system before publishing it. The simulator plays the console too:
`pinyol_sim --console examples --menu firmware/cirera`.

## Play it in RetroArch: RetroPie, Batocera, Lakka

The engine is also a [libretro](https://www.libretro.com) core, which plays a game's zip in RetroArch and in
everything built on it, a Raspberry Pi with RetroPie among them:

```sh
cmake -B build-release -DCMAKE_BUILD_TYPE=Release
cmake --build build-release --target pinyol_libretro    # -> build-release/pinyol_libretro.so
```

How to install it, the controls and what it does not do yet: [docs/libretro.md](docs/libretro.md).

## How it is built

```
src/             the engine, portable C11: no SDL or ESP-IDF headers (hal.h is the whole platform contract)
  ppu.c          the virtual picture processor (layers, sprites, effects) that Lua games draw with
  lua_game.c     pinyol@2: the Lua sandbox and its API
platform/sdl/    desktop simulator, the Cirera app (-DPINYOL_APP=ON), and the web players when built with Emscripten
platform/desktop/ the app's icons
platform/null/   pinyol_headless: validator and test runner without a window
platform/libretro/ the libretro core, for RetroArch and RetroPie
platform/web/    the web pages around the players
site/            the site (https://pinyol.ipaud.dev/), built by site/build.py in Spanish, Catalan and English
firmware/        the console: ESP-IDF project, builds src/ unchanged; cirera/ is its menu, a pinyol game
examples/        games as they go on the microSD: thirty-two in Lua, hola as data
templates/lua/   the game new_game.py --lua starts from
tests/           test scripts for the examples, and the PPU's own tests
tools/           new_game.py, png2asset.py, tiled2asset.py, pack_game.py, make_gallery.py, font2fnt.py, clip2npv.py, ...
lib/             Lua libraries built into the engine, require()d by any game: juice, particles, physics, keyboard, kit, story
editor/          the web editor (plain HTML and JavaScript, no build step) and Blockly in vendor/
third_party/     cJSON, Lua 5.4, pocketmod, puff (unzip), libretro.h, the Pixelify Sans font and a library of pixel fonts (fonts/)
```

The world is 240×160 logical pixels drawn at 2× into a 480×320 frame; text and UI use the full resolution. Logic runs at 60 ticks per second on every platform. On the console the frame goes to the panel in 32-row strips drawn straight from the game while the previous strip is sent, in step with the panel's refresh; a Lua game's picture is drawn by both cores. How it got fast enough, measured: [docs/measurements.md](docs/measurements.md).

<p align="center"><img src="docs/media/strips.gif" alt="Animation: the screen split into 15 strips; each fills from the top, half by core 0 and half by core 1, then appears on the panel while the next is drawn" width="480"><br>
<sub>In slow motion: a real frame takes 16.6 ms; here, 2.4 seconds. Red, core 0; yellow, core 1.</sub></p>

## Status

pinyol was first written for two data adventures, and then opened up with Lua for any genre. What to know:

- The Lua API (`pinyol@2`) is new and may still change; the data format (`pinyol@1`) is stable.
- The built-in interface text of data adventures (menus, pause, bag) is in Spanish.
- Some pinyol@1 defaults come from the first game: without a `"player"` in `game.json` the player is `KLAUS` with sprite prefix `KL`, and the start zone defaults to `Z01`. Set them in your `game.json`.
- What was done and measured, step by step: [docs/progress.md](docs/progress.md).
- pinyol was first called np2d: games whose `game.json` says `"engine": "np2d@1"` or `"np2d@2"` still run, and a game's repo can still use the targets `bp_core`, `bp_headless` and `bp_sim`.

## License

pinyol is MIT licensed ([LICENSE](LICENSE)). It includes [cJSON](third_party/cjson/LICENSE) (MIT), [Lua 5.4](third_party/lua/LICENSE) (MIT), [pocketmod](third_party/pocketmod/LICENSE) (MIT), [puff](third_party/puff/puff.h) (zlib), libretro's [libretro.h](third_party/libretro/libretro.h) (MIT), the [Pixelify Sans](third_party/pixelify/OFL.txt) font and the pixel fonts in [third_party/fonts](third_party/fonts/README.md) (all SIL Open Font License 1.1). The editor includes [Blockly](editor/vendor/blockly/LICENSE) (Apache 2.0). The site serves [ESP Web Tools](site/vendor/esp-web-tools/LICENSE) (Apache 2.0) to install the firmware, and [GoatCounter](site/vendor/goatcounter/README.pinyol)'s count.js (ISC) to count visits; the firmware is built with [ESP-IDF](https://github.com/espressif/esp-idf) (Apache 2.0, with parts under MIT and BSD licences) and the web player with Emscripten and SDL2. The desktop app carries SDL2 (zlib) and, on Windows, MinGW-w64's runtime ([ZPL 2.1 and MIT](third_party/mingw-w64/COPYING)). Every notice they ask for is in [THIRD_PARTY_NOTICES.md](THIRD_PARTY_NOTICES.md), which also goes with each release.

The pictures, sounds, music and video of the examples, the template and the tests were made for pinyol, generated
with an image model or drawn and synthesised by code (each game's `art.py` and `art/`): they are dedicated to the
public domain ([CC0 1.0](https://creativecommons.org/publicdomain/zero/1.0/)), to use in your own games as you like.

Game Boy, Game Boy Advance, PlayStation, Saturn, Mega Drive, Super Nintendo, Neo Geo, CPS2, PICO-8, ZX Spectrum,
Wolfenstein 3D and the other consoles and games named here are trademarks of their owners. pinyol and Cirera are not
affiliated with them or endorsed by them: the names only say which look a game takes after.
