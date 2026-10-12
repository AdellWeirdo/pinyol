# Making a game in Lua (np2d@2)

An np2d@2 game is a folder with a `game.json`, a `main.lua` and its assets. The engine gives it a virtual console
modelled on the Game Boy Advance: a 240×160 picture built from four background layers and 128 sprites, palettes,
transparency, windows and per-line effects, with text and panels drawn on top at the screen's full 480×320. It runs
the same on the RetroGo console, the desktop simulator and the browser.

```
games/mygame/
  game.json      {"id": "mygame", "title": "My Game", "engine": "np2d@2", "main": "main.lua"}
  main.lua       _init(), _update(), _draw()
  *.lua          more code, loaded with require("name")
  assets/        indexed tiles, maps, palettes and sprites (tools/png2asset.py)
  audio/         WAV, PCM 16-bit mono at 22,050 Hz
  fonts/         FONT_MAIN.fnt, FONT_BOLD.fnt, FONT_MAIN_L.fnt, FONT_BOLD_L.fnt (copy them from an example)
```

The examples are the best way in: `examples/plataformas` (a platformer), and the others next to it. Each has an
`art.py` that draws its art by code and converts it, so you can start from its PNGs in `art/`.

## The loop

```lua
function _init() end      -- once, when the game starts (and again on "new game" in tests)
function _update() end    -- 60 times a second: input, movement, rules
function _draw() end      -- before each frame: scroll, sprites, text
```

The picture processor keeps its state between frames: a sprite stays where you put it until you move or remove
it. Text and shapes (the overlay) are drawn again every frame: call them in `_draw()`.

A Lua error stops the game and shows the message on screen; `bp_headless --validate` reports it too.

## Coordinates and colours

- The world is 240×160 (`W`, `H`). Backgrounds and sprites use world pixels.
- The overlay (text, panels) uses screen pixels, 480×320 (`SCREEN_W`, `SCREEN_H`): world pixel x is screen 2x.
- Colours are `0xRRGGBB` numbers; `rgb(r, g, b)` makes one. They are stored as RGB565 (5-6-5 bits).
- Numbers can have fractions: positions are rounded down when drawn.

## Input

| Call | Returns |
|---|---|
| `btn(name)` | true while held. Names: `"up" "down" "left" "right" "a" "b" "c" "start" "menu"` |
| `btnp(name)` | true on the tick it was pressed |
| `touch()` | `x, y, down, tapped`, in world pixels |
| `t()` | seconds since the game started |
| `ticks()` | ticks since the game started (60 a second) |

## Palettes

Indexed pixels look their colour up in a palette: 256 entries for backgrounds and 256 for sprites. Entry 0 of a
palette is transparent; background entry 0 is also the backdrop colour.

| Call | Does |
|---|---|
| `pal(i, colour [, obj])` | sets entry i of the background palette (or the sprite palette when obj is true) |
| `palette(id [, obj [, offset]])` | loads `assets/<id>.pal` into the palette, from entry `offset` |
| `backdrop(colour)` | the colour behind everything |

A tilemap brings its palette with it: `bg()` loads it. Sprite palettes are loaded with `palette("OBJ", true)`.
Palette banks: a sprite drawn with `bank(b)` uses entries `index + 16 * b`, so one 16-colour graphic can be
recoloured.

## Backgrounds

Four layers, 0 to 3. Each is tiles, affine (rotated, scaled, Mode 7) or a bitmap.

```lua
bg(1, {map = "LEVEL", prio = 1, wrap = false})          -- tiles from assets/LEVEL.tiles + .map
bg(2, {map = "TRACK", mode = "affine"})                  -- the same, turned and scaled
bg(3, {image = "BG_TITLE"})                              -- a bitmap: a direct-colour runtime asset
bg(0)                                                    -- off
```

Options: `prio` 0 (front) to 3 (back), default the layer's number; `wrap` (default true) repeats the map;
`mosaic` makes it blocky with `mosaic()`; `x`, `y` start scroll; `pal = false` keeps the current palette.

| Call | Does |
|---|---|
| `scroll(n, x, y)` | the map pixel at the screen's top-left |
| `affine(n, pa, pb, pc, pd, x0, y0)` | screen (x, y) shows map (x0 + pa·x + pb·y, y0 + pc·x + pd·y) |
| `rot(n, degrees, zoom, map_x, map_y, screen_x, screen_y)` | turn and zoom so that map point appears at that screen point |
| `mode7(n, cam_x, cam_y, degrees, height, horizon, fov)` | a perspective floor seen from a camera; lines above the horizon are empty |
| `project(n, map_x, map_y)` | where a point on that floor appears: `x, y, scale, visible` (for its sprites) |
| `mget(n, tx, ty)` / `mset(n, tx, ty, v)` | read or change a map entry: tile number, `0x400` flips across, `0x800` flips up, `bank << 12` |
| `mapsize(n)` | the map's width and height in tiles |

## Sprites

```lua
local hero = sheet("HERO")                  -- a sprite sheet: handle, w, h, frames
spr(0, hero, frame, x, y, prio(1) | FLIP_X) -- sprite 0 shows frame `frame` at x, y
spr_off(0)                                  -- hide it
spr_clear()                                 -- hide all 128
```

Sprite 0 is drawn over sprite 1, and so on. A sprite is drawn over backgrounds of the same priority. Flags, added
with `|`:

| Flag | Effect |
|---|---|
| `FLIP_X`, `FLIP_Y` | mirror |
| `prio(p)` | priority 0..3 |
| `bank(b)` | palette bank (indexed sheets) |
| `BLEND` | always blended over what is under it (see `blend`) |
| `WINDOW` | not drawn: its shape becomes the object window |
| `spr_mat(m)` | turned and scaled by matrix m, set with `mat(m, degrees, scale_x [, scale_y])` |
| `DOUBLE` | with `spr_mat`: the drawing area is twice the size, so the turned sprite is not cut |
| `MOSAIC` | blocky with `mosaic()` |

Sheets are indexed (`png2asset.py --indexed`) or a direct-colour runtime asset (`png2asset.py`). Frames are up to
255×255 pixels.

## Effects

| Call | Does |
|---|---|
| `blend(first, second, a, b)` | where a layer in `first` is over one in `second`: `(top·a + under·b) / 16` |
| `fade("light" or "dark", layers, amount)` | brighten or darken those layers by amount/16 |
| `fx_off()` | no blending or fade |
| `window(k, x1, y1, x2, y2, inside)` | window 0 or 1: inside it only the `inside` layers show |
| `window_out(layers)` | what shows outside every window |
| `objwindow(inside)` | the shapes of `WINDOW` sprites as a window; `objwindow(nil)` turns it off |
| `window_off(k)` | |
| `mosaic(bg_w, bg_h [, obj_w, obj_h])` | block size for layers and sprites with the mosaic option, 1 = off |

Layer sets are added with `|`: `BG0 BG1 BG2 BG3 OBJ BACK` (the backdrop), and `FX` in a window's set lets effects
happen inside it. `ALL` is every layer.

## Per-line effects

Each of the 160 lines can have its own values: wavy water, parallax bands, gradients, a spotlight.

| Call | Does |
|---|---|
| `line_scroll(n, y, x [, y_offset])` | layer n's scroll on line y |
| `line_backdrop(y, colour)` | the backdrop on line y (a sky gradient) |
| `line_window(k, y, x1, x2)` | window k's span on line y (a circle, a cone of light) |
| `line_off()` | back to the layers' own values (a `mode7` floor stays) |

## Text and shapes at full resolution

Drawn over the world, in screen pixels (480×320), every frame in `_draw()`.

| Call | Does |
|---|---|
| `text(str, x, y [, colour [, font [, align]]])` | returns its width. Fonts: `"main" "bold" "large" "large_bold"`; align `"left" "center" "right"` |
| `textw(str [, font])` | width and height |
| `rect(x, y, w, h, colour)`, `box(x, y, w, h, colour)` | filled, outline |
| `shade(x, y, w, h)` | darken what is under it |
| `panel(x, y, w, h)`, `plate(x, y, w, h, colour)` | a card and a small sign, in the game's theme (`game.json` "theme") |
| `img(id, x, y [, frame [, scale]])` | a direct-colour runtime asset, scale 1 or 2 |

Text is UTF-8 limited to the characters of Windows-1252 (Spanish, French, German... yes; emoji no).

## Sound

| Call | Does |
|---|---|
| `sfx(id [, gain])` | plays `audio/<id>.wav` once |
| `music(id)` / `music()` | loops `audio/<id>.wav`; no id stops it |

## Saving

`store(key, value)` keeps a number, string or boolean in the game's saves folder; `stored(key [, default])` reads it.
For high scores, options and progress.

## Other

`log(...)` (and `print`) writes to the log. `quit()` goes back to the console's game list (holding MENU for two
seconds does too). `perf()` returns the milliseconds the last `_update`, `_draw` and picture took, and the script's
memory in KB, to see where a frame goes. `require("name")`
loads `name.lua` from the game folder (`"ui.menu"` is `ui/menu.lua`).

## Limits (the sandbox)

A game downloaded from the community cannot harm the console:

- Lua 5.4 with 32-bit integers and floats on every platform (the same results everywhere).
- 4 MB of memory for the script (`"lua_memory_kb"` in game.json, up to 6144); past it, "not enough memory".
- A call (`_init`, `_update`, `_draw`) that runs 50 million VM instructions without returning is stopped: an
  endless loop becomes an error, not a frozen console.
- No `io`, `os`, `debug` or `package`; `load` takes source text only, never bytecode; `require` only reads `.lua`
  files inside the game folder.
- `math.random` starts from the same seed every run, so a game and its tests repeat exactly.

## Testing

A test script plays the game with real input (see `tests/plataformas.script`):

```
new                              # start (runs _init)
press A                          # a button for one tick; hold RIGHT 30 holds it for 30
tick 20                          # let 20 ticks pass
expect_lua state == "play"       # a Lua expression that must be true
lua P.x = 100                    # run Lua in the game (set up a situation)
expect_lua_error spin()          # code that must fail
expect_ok                        # the game has not stopped on an error
shot name                        # save the screen to the saves folder (name.ppm)
```

`#` after a space starts a comment in these scripts, so avoid Lua's `#` length operator there.

Run it with `bp_headless --game DIR --fresh --script FILE --check-strips`, or name it `tests/<game>.script` next
to `examples/<game>` and `ctest` runs it.

## Sharing a game

```
python3 tools/pack_game.py games/mygame -o dist/      # -> dist/mygame.zip
```

The zip holds the folder `mygame/` with what the console reads (add `--sources` to include `art/` and `art.py`).
Unzipped into the card's `games/` folder it shows in the console's list. The web player (`player.html`, built with
Emscripten, see the README) plays it in a browser: `player.html?game=dist/mygame.zip`, or drop the zip on the page.
Saves made in the browser stay in that browser.
