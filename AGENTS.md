# pinyol: notes for coding agents

pinyol is a 2D engine for the RetroGo handheld (ESP32-S3, 480x320). Games are Lua folders that run the same in the
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
./build/pinyol_headless --game games/<id> --fresh --script games/<id>/tests/<id>.script --check-strips
```

It prints `PASS` or `FAIL` with the Lua error and line. End scripts with `expect_ok`. To look at the screen, put
`shot name` in the script: it writes `games/<id>/saves/name.ppm`; `sips -s format png X.ppm --out X.png` (macOS)
turns it into a PNG you can open. Look at it: a game that passes but draws nothing is not done.

## Art and sound

- Pictures: generated images (backgrounds removed, frames cut, scale and feet fitted) are in
  [docs/art.md](docs/art.md): read it before making art. Or draw them by code in the game's `art.py`, as the
  template does.
- Sounds: `tone()` and the sound factory in docs/lua.md need no files; WAV must be PCM 16-bit mono 22,050 Hz;
  music can be a `.mod`.

## Share it

`python3 tools/pack_game.py games/<id> -o dist/` makes `dist/<id>.zip`: unzipped into the microSD's `games/` it
plays on the console; the web player (README.md) plays it in a browser.
