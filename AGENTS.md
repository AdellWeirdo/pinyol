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

## Art and sound

- The look: a game is made to look like a console (Game Boy, ZX Spectrum, PICO-8, a pocket LCD game, a vector
  arcade, Game Boy Advance, SNES / Mega Drive, PlayStation / Saturn 2D, Neo Geo, CPS2, a vertical arcade screen, or
  first person). When the user says "a game like <console or game>", turn their words into a look with
  `uv run tools/looks.py "<their words>"` (one id: go on; several or none: ask which, before making any art), then
  `uv run tools/new_game.py games/<id> --lua --look <id>` (it writes the look's rules to `look.md`, the font pack and `"look"`
  in game.json), follow that look's rules in [docs/art.md](docs/art.md) ("Choose a look"), start from its example, and
  check the art with `uv run tools/look_check.py games/<id>` (palette banks, colours, sprite sizes, forbidden code).
  The table of looks and their limits is `tools/looks.json`. The small looks are drawn by code
  (`art.py`): they need no image generation.
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
