# pinyol: notes for coding agents

pinyol is a 2D engine for the Cirera handheld (ESP32-S3, 480x320). Games are Lua folders that run the same in the
desktop simulator, the browser and the console. If you were asked to make a game, make it in `games/<id>/` and leave
`src/`, `lib/` and `examples/` alone.

## The API is pinyol's own

It is not LÖVE, PICO-8 or TIC-80. Before writing code, read [docs/lua.md](docs/lua.md) (the whole API) and the
`main.lua` of the closest example in `examples/` (README.md has a table: platformer, shmup, Mode 7 racing, puzzle,
top-down adventure, beat'em up, fighting, sports...). If a function is not in docs/lua.md, it does not exist: grep
before using it. The sandbox has no `io`, `os`, `debug` or `package`.

## Build once

```sh
brew install cmake sdl2 uv          # macOS; Linux: cmake, libsdl2-dev, uv
cmake -B build && cmake --build build
```

If `cmake`, SDL2 or `uv` are missing, install them yourself with that `brew` line: it needs the network and writes
outside this folder, so ask the user to approve it. Homebrew itself (https://brew.sh) needs the user's password: if
`brew` is missing, ask them to install it.

## Ask before you make it

When the user asks for a game, ask only what changes the work and cannot be assumed: at most five questions, all in one go (the agent's question tool, the recommended option first), and only the ones the request does not answer. Never ask when the user says "decide yourself" or "don't ask": assume the defaults below and say so in one line.

Ask (each one decides a different pipeline):

1. **Graphics**: from the image model (`gen/` + `tools/sprite_kit.py`, one reference picture for the style, 1% of a window a call; ask for a reference if they have one), or drawn by code (the small looks: Game Boy, ZX, PICO-8, LCD, vector)? Recommend by look: the big looks (CPS2, Neo Geo, PlayStation, 16-bit) the image model, the small ones code.
2. **Logo**: from the image model (two variants, they choose) or by code? Recommend the image model for a flagship.
3. **Universe**: its own (recommended; the demos never borrow a franchise) or an existing one (then ask which and where its references are).
4. **Cover** (the picture of the game's card on the web and in the console's menu, 240x160 at `cover.rgb565`): the title screen at the right moment (the default, `tools/cover.py`), a picture from the image model made for it (key art, in the logo's style; recommend it for a flagship, one or two variants), or a moment of play they choose (`--at`, `--keys`)? Never leave the tool's first guess: it takes the screen at 1.5 s, which can be a loading screen or the careta. Look at the cover before saying it is done.
5. **Where it will live**: the console's flash (small: no raw big pictures, the flash is nearly full), the card, or the web demo (needs es/ca/en, a cover and a test)? It sets the size budget and the gate.

Assume without asking (change only if the user says so): the look's font pack, and a second font only for the logo or titles; es, ca and en; touch or buttons by the genre (a puzzle: touch with buttons as support); music and sound synthesised by code in the look's own sound; five levels or about three minutes of play; five or more achievements; a "how it works" menu item; `reduce_flashing`; a test script that plays it; everything the quality gate (`tools/demo_check.py`) asks. Write the answers and the assumptions in `brief.md` of the game (one line each) so the next session does not ask again.

## Make a game

```sh
uv run tools/new_game.py games/<id> --lua --title "Title"   # a small working game to change
./build/pinyol_sim --game games/<id>                        # play it (a window; restarts on every save)
```

`_init()` once, `_update()` 60 times a second, `_draw()` each frame. The world is 240x160 (layers, sprites);
`text()` and shapes draw over it at 480x320. [docs/tutorial.md](docs/tutorial.md) walks the template step by step.

## Check your work (do this after every change)

You cannot see the `pinyol_sim` window, so play the game headless with a test script in `games/<id>/tests/<id>.script`
(syntax in docs/lua.md, "Testing"; `tests/*.script` are real ones):

```sh
./build/pinyol_headless --game games/<id> --fresh --script games/<id>/tests/<id>.script --check-strips --strict-assets
```

It prints `PASS` or `FAIL` with the Lua error and line. `--strict-assets` also fails when requested art is missing
or corrupt. End scripts with `expect_ok`. To look at the screen, put
`shot name` in the script: it writes `games/<id>/saves/name.ppm`; `sips -s format png X.ppm --out X.png` (macOS)
turns it into a PNG you can open. Look at it: a game that passes but draws nothing is not done. Take a shot of every
screen with text (title, messages, game over, the end) and look at each text: inside its box with a margin, never
over the box's border or past the screen's edge, readable on what is under it.

## Playtest it when it is finished

`uv run tools/playtest.py games/<id>` plays it with 50 perfect and 50 imperfect bots (human-like and monkeys) and writes a report of
crashes, softlocks, flashing, where players die and how hard it is (docs/playtest.md). Give the game a `tests/playtest.lua` adapter
(progress, end, `where`, a perfect player) so the numbers mean something; the bots run in the background, a few at a time.

## Art and sound

- The look: a game is made to look like a console (Game Boy, ZX Spectrum, PICO-8, a pocket LCD game, a vector
  arcade, Game Boy Advance, SNES / Mega Drive, PlayStation / Saturn 2D, Neo Geo, CPS2, a vertical arcade screen, or
  first person). When the user says "a game like <console or game>", turn their words into a look with
  `uv run tools/looks.py "<their words>"` (one id: go on; several or none, or no output after uv's first run: ask, or run it again once, before making any art), then
  `uv run tools/new_game.py games/<id> --lua --look <id>` (it writes the look's rules to `look.md`, the font pack and `"look"`
  in game.json), follow that look's rules in [docs/art.md](docs/art.md) ("Choose a look"), start from its example, and
  check the art with `uv run tools/look_check.py games/<id>` (palette banks, colours, sprite sizes, forbidden code).
  The table of looks and their limits is `tools/looks.json`. The small looks are drawn by code
  (`art.py`): they need no image generation.
- Generated sprites: fit them with `tools/sprite_kit.py` (one scale per sheet from an upright frame, soles on the ground row, feet centred, never cut, objects and effects at their own size) ask the image model through `tools/sheet_jobs.py` (raw pictures in the game's `raw/`, `--plan` first: a call is about 1% of the plan), check them with `uv run tools/sprite_check.py games/<id>/art --regen --fresh`, and measure with `uv run tools/board_perf.py games/<id> --tour`: docs/art.md, "Sprites that fit".
- Text must fit the first time: size a panel from `textw(str, {font, width})` or draw the text in `textbox` / `lib/box.lua`; a test script of a flagship game runs with `--check-text` (no line cut by the screen's edge, no text too big for its box; `slide = true` for a scroll), registered in CMake's `TEXT_CHECKED`.
- A finished example game passes `uv run tools/demo_check.py games/<id>`: a card with its look, 5+ achievements, es/ca/en words, a "how it works" menu item, `reduce_flashing` read if it flashes, a cover, a test script, its look's fonts, sprites that fit and a measured frame rate.
- Pictures: generated images (backgrounds removed, frames cut, scale and feet fitted) are in
  [docs/art.md](docs/art.md): read it before making art. Or draw them by code in the game's `art.py`, as the
  template does.
- Letters: pick the look's font pack in [docs/fonts.md](docs/fonts.md) and make it with
  `uv run tools/font2fnt.py --pack <pack> games/<id>` (fonts/<pack>_title.fnt, _body, _small, for `text(..., {font = ...})`).
- Sounds: `tone()` and the sound factory in docs/lua.md need no files; WAV must be PCM 16-bit mono 22,050 Hz;
  music can be a `.mod`.

## Share it

`python3 tools/pack_game.py games/<id> -o dist/` makes `dist/<id>.zip`: unzipped into the microSD's `games/` it
plays on the console; the web player (README.md) plays it in a browser.
