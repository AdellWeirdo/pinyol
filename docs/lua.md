# Making a game in Lua (pinyol@2)

An pinyol@2 game is a folder with a `game.json`, a `main.lua` and its assets. The engine gives it a virtual console
modelled on the Game Boy Advance: a 240×160 picture built from four background layers and 128 sprites, palettes,
transparency, windows and per-line effects, with text and panels drawn on top at the screen's full 480×320. It runs
the same on the Cirera console, the desktop simulator and the browser.

```
games/mygame/
  game.json      {"id": "mygame", "title": "My Game", "engine": "pinyol@2", "main": "main.lua"}
  main.lua       _init(), _update(), _draw()
  *.lua          more code, loaded with require("name")
  assets/        indexed tiles, maps, palettes and sprites (tools/png2asset.py)
  audio/         WAV (PCM 16-bit mono at 22,050 Hz) and tracker music (.mod)
  fonts/         FONT_MAIN.fnt, FONT_BOLD.fnt, FONT_MAIN_L.fnt, FONT_BOLD_L.fnt (copy them from an example),
                 and any of the game's own: fonts/<name>.fnt, used as text(..., {font = "<name>"})
```

The examples are the best way in: `examples/plataformas` (a platformer), `naves` (a shoot-'em-up), `carreras`
(Mode 7 racing), `puzle` (a touch puzzle with synthesised music), `aldea` (a top-down adventure made in Tiled,
with dialogue), `estilos` (a game's own look: fonts, text styles, frames, turned pictures) and `inventos` (toys of
no genre, drawn with nothing but code: painting, land that breaks, generative trails, 3D, a split screen). Each has an
`art.py` that draws its art by code and converts it, so you can start from its PNGs in `art/`.

## The loop

```lua
function _init() end      -- once, when the game starts, after its careta (and again on "new game" in tests)
function _update() end    -- 60 times a second: input, movement, rules
function _draw() end      -- before each frame: scroll, sprites, text
```

The picture processor keeps its state between frames: a sprite stays where you put it until you move or remove
it. Text and shapes (the overlay) are drawn again every frame: call them in `_draw()`.

A Lua error stops the game and shows the message on screen; `pinyol_headless --validate` reports it too.

## The careta (POWERED BY PINYOL)

Every game made with pinyol opens with a careta that says **POWERED BY PINYOL**, the way a film opens with its
studio's logo. `_init` runs after it. The engine has its own: pinyol's logo builds itself on the night sky (3 s). A game
can have its own instead, in its own style, with its pictures, its music and anything else the API draws or plays:
`splash.lua` in the game folder (or another file, named by game.json `"splash"`). It returns a table:

```lua
-- splash.lua
local careta = {}
function careta.update(t)         -- t: ticks since the careta began (1, 2, 3...)
  if t == 20 then tone(0, "G4") end
  return t >= 150                 -- true: it is over
end
function careta.draw(t)
  rect(0, 0, 480, 320, 0x1A0F2E)
  text("MY GAME", 240, 100, {font = "bold", scale = 3, align = "center"})
  local w, h = powered_by()       -- the seal's size
  powered_by((480 - w) // 2, 200) -- where it goes this frame (its top-left corner)
end
return careta
```

Whatever a careta draws, **the engine draws the seal "POWERED BY PINYOL" over it**, on every frame: where
`powered_by(x, y)` put it that frame (kept whole on the screen), or centred near the bottom. The careta cannot be
skipped (no button reaches it) and lasts 2 to 6 seconds: earlier than 2 s, its last frame stays; at 6 s it ends. It
runs after `main.lua` (so it can use the game's modules and pictures), and when it is over the picture processor
starts again as new for `_init`. A mistake in `splash.lua` fails `--validate`; an error while it plays shows the
engine's careta instead. See `examples/careta`.

The careta plays on the console, the desktop, the web player and in RetroArch. To make a game without seeing it every
time: `pinyol_sim --no-splash`, and saving a file (hot reload) goes straight back to the game. `pinyol_headless` and
test scripts start without it (their ticks count from `_init`); `--splash` plays it first.

## Coordinates and colours

- The world is 240×160 (`W`, `H`). Backgrounds and sprites use world pixels.
- The overlay (text, panels) uses screen pixels, 480×320 (`SCREEN_W`, `SCREEN_H`): world pixel x is screen 2x.
- Colours are `0xRRGGBB` numbers; `rgb(r, g, b)` makes one. They are stored as RGB565 (5-6-5 bits).
- Numbers can have fractions: positions are rounded down when drawn.

## Input

| Call | Returns |
|---|---|
| `btn(name)` | true while held. Names: `"up" "down" "left" "right" "a" "b" "c" "start" "menu"`. There are no L and R: the console has no shoulder buttons, and a name that only a computer's keyboard had would make games the console cannot play. A game after a GBA one gives what L and R did to C, or to the touch screen |
| `btnp(name)` | true on the tick it was pressed. `btnp(name, hold, every)` also repeats while held: again after `hold` ticks, then every `every` ticks (a menu that scrolls on its own) |
| `btnr(name)` | true on the tick it was let go (a charged shot fires on release) |
| `btnt(name)` | ticks it has been held, 0 when it is not (a long press, how charged) |
| `btnb(name, window)` | true if it was pressed in the last `window` ticks (6 if left out) and not used yet; true once, then used. A jump pressed just before landing still jumps |
| `touch()` | `x, y, down, tapped, released`, in world pixels (240x160) |
| `pen()` | the same finger in the screen's own 480x320 pixels, the space `text()` and shapes draw in: `x, y, down, tapped, released`. `released` is true on the tick the finger lifts, where it was lifted. For taps, drags, flicks and drawn shapes see the `"pointer"` library |
| `touches()` | every finger down, `{{x, y}, ...}`, in `pen()`'s pixels, the first being `pen()`'s: the console's panel takes up to 5. Two fingers make a pinch or a two-finger drag (`"pointer"`'s `pinch`). In the simulator, Alt and a click put a second finger mirrored round the screen's middle; a phone in the browser gives its own fingers |
| `screen(n)` | for a game with `"screens": 2` in game.json: the top (1) or the bottom (2, the touch one) screen is drawn on from now on, by the picture calls (`bg`, `spr`, `scroll`, `pal`, `line_*`...) and by the text and shapes, from its own corner and cut at its edge. Each `_update` and `_draw` starts on screen 1. Each screen is 240x160 (`SCREEN_W`, `SCREEN_H` say so), the two side by side in the middle of the 480x320 frame; `touch()` and `pen()` are the bottom screen's own pixels and a touch off it is none. Not yet: the careta of a game with its own `splash.lua`, the console's panel (see [ds-dual-screen-design.md](ds-dual-screen-design.md)) |
| `t()` | seconds since the game started |
| `ticks()` | ticks since the game started (60 a second) |
| `clock()` | the date and the time where the player is: `{year, month, day, hour, min, sec, wday, yday, days, offset}` (`wday` 1 Monday to 7 Sunday; `days` since 1970-01-01, for the time between two sessions; `offset` the minutes from UTC), or `nil` when the machine does not know the date. A computer and a browser always do; the console has no clock of its own and is given the computer's whenever a game is sent over the cable (the editor or `tools/send_game.py`), and keeps it while asleep, not once its battery runs out. A game that grows its berries by the day keeps the last `days` it saw in `store` and is ready for `nil` |

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
| `SILHOUETTE` | drawn as usual, and where a background of a nearer priority covers it, its silhouette shows through: a flat colour mixed over the background (a hero behind a house, a cat under the table). `silhouette(colour [, strength])` sets the colour and how much of it (0.5): the same for every such sprite |
| `DOUBLE` | with `spr_mat`: the drawing area is twice the size, so the turned sprite is not cut. A turned sprite is drawn only where its pixels fall, so the larger area costs next to nothing |
| `MOSAIC` | blocky with `mosaic()` |

Sheets are indexed (`png2asset.py --indexed`) or a direct-colour runtime asset (`png2asset.py`). Frames are up to
255×255 pixels.

## Effects

| Call | Does |
|---|---|
| `blend(first, second, a, b)` | where a layer in `first` is over one in `second`: `(top·a + under·b) / 16` |
| `fade("light" or "dark", layers, amount)` | brighten or darken those layers by amount/16 |
| `palcycle(lo, hi, phase [, "obj" or {obj, blend}])` | entries `lo..hi` of the palette cycle, as Mark Ferrari's living worlds do (a waterfall, lava, rain from a handful of entries): entry i shows what entry `lo + (i - lo + phase) mod n` held, and a fraction of `phase` mixes two neighbours so the cycle glides (`blend = false` steps). The entries' own colours are kept from the first call for that range (eight ranges at most); `palcycle(lo, hi)` puts a range back; `palcycle()` forgets them all (after loading another palette). Costs nothing: it writes a few palette entries |
| `shock(x, y, r [, width [, amp]])` | the world's picture bent after it is drawn: a ring of radius `r` about `(x, y)` (the picture's own pixels, 240x160), `width` wide (8), pushes what it passes outwards by up to `amp` pixels (6): an explosion, a drum hit, a portal. Four a frame. On the world (the layers and the sprites), not on what `img`, the shapes and `text` draw at full resolution over it |
| `haze(y0, y1 [, amp [, phase [, period]]])` | the picture's rows `y0..y1` moved sideways by `amp * sin(y / period + phase)` (2 pixels, a period of 12 lines): heat over sand, a fire, a portal's edge; move `phase` each frame. On the world too, not on what is drawn at full resolution over it; the copy it works from covers only the rows asked for |
| `distort(x, y, w, h [, {kind, amp, phase, period, speed}])` | a rectangle of the world's picture that sways or wobbles, for this frame, in the picture's own pixels: `kind = "heat"` (the default) moves each row sideways by `amp * sin(y / period + phase)`, `kind = "water"` also lifts each column up and down by half that, as light bends through a pool; `speed` (cycles a second) animates it by itself, or move `phase` each frame. Up to four a frame, which must not overlap; on the console a heat zone costs well under a millisecond and a water zone about 5 ms for 120 rows of the full width (measured, docs/measurements.md); `haze` is `distort` across the whole width. Not on what `img` and the text draw over the world |
| `crt([{scan, persist}])`, `crt(false)` | the glass of a cathode-ray tube, from now on until turned off: `scan` (0 to 1, 0.25) dims every second row of the screen (the 320 real rows of the 480x320 picture), over everything the game drew, `img` pictures and text included, under the console's own menu; `persist` (0 to 0.95, 0) keeps that part of the world's last frame where the new one is darker (a streak behind what moves; it works on the 240x160 world only, keeps one more copy of it, 77 KB of the slow memory, and costs 3 to 9 ms a frame on the console). Scanlines alone cost CPU in the strips (measured in docs/measurements.md) |
| `fx_off()` | no blending or fade |
| `window(k, x1, y1, x2, y2, inside)` | window 0 or 1: inside it only the `inside` layers show |
| `window_out(layers)` | what shows outside every window |
| `objwindow(inside)` | the shapes of `WINDOW` sprites as a window; `objwindow(nil)` turns it off |
| `window_off(k)` | |
| `mosaic(bg_w, bg_h [, obj_w, obj_h])` | block size for layers and sprites with the mosaic option, 1 = off |
| `show(layers)` | which of `BG0`-`BG3` and `OBJ` are drawn (all at the start): hide a layer without losing its setup, `show(ALL & ~BG1)` |

Layer sets are added with `|`: `BG0 BG1 BG2 BG3 OBJ BACK` (the backdrop), and `FX` in a window's set lets effects
happen inside it. `ALL` is every layer.

## Per-line effects

Each of the 160 lines can have its own values: wavy water, parallax bands, gradients, a spotlight.

| Call | Does |
|---|---|
| `line_scroll(n, y, x [, y_offset])` | layer n's scroll on line y |
| `line_backdrop(y, colour)` | the backdrop on line y (a sky gradient) |
| `line_affine(n, y, x, y_map, pa [, pc])` | on line y, layer n (in affine mode) starts at map point `(x, y_map)` and steps by `(pa, pc)` a screen pixel: what `mode7` works out for a floor, line by line, for anything else (a floor with hills, a wall seen at an angle, a tower turning, a flag waving: `lib/road.lua` draws an OutRun road with it). The first use in a frame starts every line from the layer's own matrix |
| `line_scroll_ramp(n, y0, y1, x0, x1 [, curve])` | layer n's scroll goes from `x0` on line `y0` to `x1` on line `y1`, straight or along `k ^ curve`: parallax bands, a floor sliding faster the nearer it is, in one call instead of a `line_scroll` a line |
| `line_pal(y, index, colour [, colour ...])`, `line_pal_obj(...)` | on line y, entry `index` of the backgrounds' palette (and the next ones, one for each further colour) has that colour, as a console that writes its palette in each HBlank does: a sky that deepens, water that shimmers, a sail painted by the sunset; `line_pal_obj` is the same for the sprites' palette. Up to 16 entries a line in each; they last until `line_off()`. Entry 0 is the backdrop (`line_backdrop` wins on a line that has both). The renderer pays about a thousand cycles on each line that replaces entries (a real scene: 0.1 ms in 5), and nothing when none does; the cost to mind is the game's own, a call into C for each line and each colour: do the colours with numbers, not tables made for each line, and since the tables stay until `line_off()` write only the lines whose colours changed |
| `line_ramp(y0, y1, index, from, to [, curve] [, "obj"])` | entry `index` of the palette (the sprites' with `"obj"`) goes from colour `from` on line `y0` to `to` on line `y1`, straight or along `k ^ curve` (1.5: a sky that pales fast near the horizon); `y1` above `y0` runs it upwards. One call for what would be a `line_pal` on each line: a sky, a sea's depth, a glow. It shares the lines' sixteen entries with `line_pal` |
| `line_window(k, y, x1, x2)` | window k's span on line y (a circle, a cone of light) |
| `line_fx(y, amount)` | 0..16 on line y: the amount of the `fade`, or how much of a `blend`'s first target shows (the second gets 16 − amount). Fog thickening toward the horizon of a `mode7` floor: `fade("light", BG2, 0)` once, then `line_fx` for each line. While it is on, every fade and blend of the game takes its amount from it, so a screen-wide fade needs `line_off()` first |
| `line_off()` | back to the layers' own values (a `mode7` floor stays) |

## Levels from Tiled

[Tiled](https://www.mapeditor.org) is a free map editor. Draw a level there with any tile size, then import it:

```
python3 tools/tiled2asset.py maps/level1.tmx games/mygame LEVEL1
```

Each visible tile layer becomes a background, `LEVEL1_<LAYER>` (`bg(1, {map = "LEVEL1_GROUND"})`), and the rest
goes into `level1.lua` in the game folder:

```lua
local level = require("level1")
level.width, level.height, level.tile_w, level.tile_h  -- the map in tiles, and its tile size in pixels
level.layers.ground.data[ty * level.width + tx + 1]   -- the tile id in a cell (0: empty)
level.tiles[id].solid                                 -- the tile's custom properties in Tiled
level.objects                                         -- {name, type, x, y, w, h, props} from object layers
level.props                                           -- the map's own properties
```

Collisions come from tile properties (`solid` on the wall tiles, say) or from a layer drawn only for them. Maps are
`.tmx` or Tiled's JSON, tilesets embedded or separate; infinite maps and image-collection tilesets are not supported.

## Text and shapes at full resolution

Drawn over the world, in screen pixels (480×320), every frame in `_draw()`.

| Call | Does |
|---|---|
| `text(str, x, y [, colour [, font [, align [, width [, chars]]]]])` | returns its width and height. Fonts: `"main" "bold" "large" "large_bold"` or one of the game's own; align `"left" "center" "right"`; `width` wraps it into lines that fit; `chars` shows only the first ones (dialogue typed out letter by letter) |
| `text(str, x, y, {options})` | the same with a style: see below |
| `textw(str [, font or {options}])` | width and height |
| `rect(x, y, w, h, colour)`, `box(x, y, w, h, colour)` | filled, outline |
| `shade(x, y, w, h)` | darken what is under it |
| `panel(x, y, w, h)`, `plate(x, y, w, h, colour)` | a card and a small sign, in the game's theme (`game.json` "theme") |
| `img(id, x, y [, frame [, scale]])` | a direct-colour runtime asset, scale 1 or 2 |
| `img(id, x, y, {frame, scale, scale_x, scale_y, flip_x, flip_y, angle, pal, tint, dim, mul, alpha, add, sub, quarter, outline, outline_width})` | the same turned (degrees, about its centre), scaled by any amount (negative flips) or flipped; `(x, y)` is where its top-left corner would be unturned. A packed picture (below) can also be drawn with another one's colours, `pal = "SPR_RAN_B"` (a second player, an enemy's stronger kind), or all of one colour, `tint = 0xFFFFFF` (the flash of a hit, a shadow), or darker, `dim = 0.4` (a night) or each channel by its own, `mul = 0x6070C0` (0xFF as it is): its palette is multiplied once, so a whole picture costs nothing more; not turned; `alpha = 0.5` mixes it with what is under it (a ghost, a moonbeam, afterimages), `add = true` adds its light (a glow, a fireball), `sub = true` takes it away from what is under it (a shadow, a dark vapour), `quarter = true` adds a quarter of it (a faint glow), `outline = 0xRRGGBB` draws a ring of that colour round the picture's shape, `outline_width = 1..4` pixels thick (the picture is drawn five times: for a few sprites, a selected one, a hit one): the PlayStation's four ways to meet the picture beneath, each held to its range (`alpha` scales the picture's light in `add`, `sub` and `quarter`); all with any of the rest, turned or not |
| `frame(id, x, y, w, h [, scale [, frame]])` | a box of any size cut from a picture of the game: its thirds are the corners (drawn once), the edges and the middle (repeated). A 24×24 picture gives 8×8 corners; `scale` makes each pixel bigger |

Text is UTF-8 limited to the characters of Windows-1252 (Spanish, French, German... yes; emoji no).

**Pictures as big as a Neo Geo's.** Converted with `png2asset.py --packed`, a picture keeps its own palette and only
its visible pixels ([the format](game-format.md#packed-pictures)): fighters 192 pixels tall, backgrounds wider than
the screen, all drawn at 60 fps on the console. `examples/duelo` is a fighting game made this way: two layers of
stage, two fighters of eleven frames each, mirrored, flashing white when hit. Mirrored (`flip_x`) a packed picture
costs the same as plain; scaled, the same per pixel drawn.

A game's pictures share 4 MB of memory. Past it, those not drawn in the frame being made are let go, the least
recently drawn first, and come back from the card by themselves the next time they are drawn (a moment's load: a
level's pictures are best drawn once when it starts). So a game's art can be far bigger than the console's memory,
as long as what one frame draws fits. Pictures used by the 240x160 world (sprite sheets, bitmap layers) and canvases
always stay.

On the console the pictures' 4 MB is what the heap leaves (about 3 MB for a game with a script of a megabyte),
and a picture needs one block of that, not its sum. When a picture finds no block big enough, the ones not drawn in this frame go one at a time, the
least recently drawn first, until it fits. If it still finds none it is not lost: a one-pixel stand-in is drawn, `imgsize`
tells the size it will have, and a third of a second later (twenty frames) it is asked for again; the log says so
once (`no memory for N bytes`). A game that draws a fight's sheets of 600 KB each, both fighters', should preload them
behind a still screen and leave out what it will not use soon (a SUPER's background loads in its own flash).
Better still, cut the sheet into pieces of a few frames (`python3 tools/pk_split.py assets/SPR_HERO.pk --frames 10
--remove` writes `SPR_HERO_C0`, `_C1`...; the game draws frame `f` as frame `f % 10` of `"SPR_HERO_C" .. f // 10`):
pieces of 60-230 KB find their block when a whole sheet does not, and only the pieces in use stay in memory. A
`canvas` needs one block too, and gets it the same way: pictures not drawn in this frame go for it, oldest first.

### A game's own look

Every game starts with the same four fonts and the same panels. What makes one look like itself:

- **Its own fonts.** Any number, `fonts/<name>.fnt`, loaded the first time `text` or `textw` asks for them (16 at
  most). `tools/font2fnt.py` makes them from a TTF or OTF (a pixel font is drawn at its own pixel size, found for
  you), a BDF, a PNG sheet of glyphs (16 a row, as GB Studio's), or one of the fonts that come with pinyol
  (`font2fnt.py --list`: Press Start 2P, Silkscreen, VT323, Jersey, Micro 5, Jacquard, Bytesized, DotGothic16...,
  all SIL Open Font License, in `third_party/fonts`). Replacing the four `FONT_*.fnt` changes the game's
  everyday text too.
- **Text styles**, as `text`'s fourth argument:

  | Option | Default | |
  |---|---|---|
  | `color` | `0xFFFFFF` | |
  | `font`, `align`, `width`, `chars` | | as the arguments above |
  | `outline` | none | a colour: a ring around each letter |
  | `shadow`, `shadow_x`, `shadow_y` | none, 1, 1 | a colour, and its offset in font pixels (-2..2) |
  | `gradient` | none | the colour at the foot of the letters; `color` is the top |
  | `scale` | 1 | each pixel of the font 1..8 screen pixels: a small pixel font as a title |
  | `spacing` | 0 | font pixels added after each letter |
  | `wave`, `shake` | 0 | pixels: the letters move along a sine, or jitter |

  ```lua
  text("GAME OVER", 240, 120, {font = "arcade", scale = 3, align = "center", color = 0xFFE070,
                               gradient = 0xFF5020, outline = 0x301010, shadow = 0x000000})
  ```

  A styled text costs more to draw than a plain one (each letter is worked out with its ring and shadow): fine for
  titles, labels and dialogue, not for hundreds of them a frame. Styles need fonts up to 64×64 pixels a glyph.
- **Frames from its own art**, with `frame()`: a wooden sign, a neon screen, a parchment, each a 24×24 PNG.
- **Pictures that turn and scale** with `img(..., {angle = a, scale = s})`, at the screen's full resolution.

## Drawing anything

For games no template has thought of: free drawing at the screen's full resolution, and canvases, pictures the game
makes and changes while it runs. Colours are `0xRRGGBB`; `CLEAR` is see-through (it erases, on a canvas).

| Call | Does |
|---|---|
| `pset(x, y [, colour])` | one pixel |
| `line(x0, y0, x1, y1 [, colour])` | a line |
| `circ(x, y, r [, colour [, filled]])` | a circle, filled unless `filled` is `false` |
| `tri(x0, y0, x1, y1, x2, y2 [, colour [, filled]])` | a triangle: the piece of 3D, of shapes, of light cones |
| `poly({x0, y0, x1, y1, ...} [, colour [, filled]])` | a polygon of up to 64 corners (one that crosses itself has holes) |
| `cls([colour])` | clears: the screen to black, a canvas to see-through (or to the colour) |
| `camera([x, y])` | everything drawn after it moves by -x, -y: a world bigger than the screen; `camera()` back |
| `clip([x, y, w, h])` | only that rectangle is drawn on: split screens, windows, masks; `clip()` everywhere again |
| `canvas(id, w, h)` | a canvas, up to 1024×1024, see-through; again with the same size, cleared |
| `canvas(id, picture)` | a canvas that starts as a copy of a picture of the game (land drawn by hand, to be broken) |
| `target(id)`, `target()` | from now on draw on that canvas, at once; then on the screen again. Each target starts with no camera and no clip, and every `_draw` starts on the screen |
| `pget(x, y [, picture])` | the colour of a pixel of a canvas (the target, or the one named) or any picture; `nil` where it is see-through or outside: collisions with anything drawn |
| `grad(x, y, w, h, c1, c2 [, {across, dither, alpha, add, sub, quarter}])` | a box shaded from `c1` at its top to `c2` at its bottom (`across = true`: left to right): a sky, a vignette, a shaft of light (`add`), a shadow (`sub`). `dither = true` breaks the bands of a slow ramp into the PlayStation's fine 4x4 pattern |
| `quad(id, x1, y1, x2, y2, x3, y3, x4, y4 [, {frame, alpha, add, sub, quarter, light, lights, dither, mesh, uv, persp}])` | a frame of the picture on any four corners, in the picture's order (top-left, top-right, bottom-right, bottom-left): a Saturn distorted sprite, a PlayStation textured quad (a floor going away, a sign swinging, a boss bending). Corners may be fractions of a pixel and glide; two triangles with the picture spread evenly across each (no depth correction, as the PlayStation drew them, so a strong tilt shows the diagonal: `persp = true` fixes that, taking the four corners as the picture seen in perspective (the projective map that puts its square on them) and cutting it into as many cells as the quad's far and near edges differ, or `persp = 8` into 8 by 8: a floor going away, a wall seen at an angle, a sign turned; on the console it costs about twice and a half the flat quad, so a floor that fills the screen still belongs on `mode7()`). `alpha`, `add`, `sub`, `quarter` as in `img`. `light = 0xRRGGBB` lights it by that colour (`0x808080` as it is, `0x000000` black, `0xFFFFFF` twice as bright); `lights = {c1, c2, c3, c4}` one colour a corner, blending across (a shaded face, a sunset on a wall); `dither = true` spreads the lit colours' rounding in the PlayStation's 4x4 pattern instead of bands. `mesh = true` uses Saturn VDP1 mesh transparency: only pixels where screen X+Y is even are drawn; the others show what is below, including masked, lit and perspective quads. The picture is kept unpacked in memory (width x height x frames x 2 bytes, once) so each pixel can be looked up: mind that for big sheets. On the console a plain quad costs about 150 ns a pixel and a lit one 400 (a 100x100 sign is 1.5 or 4 ms of a 16.7 ms frame): quads are for signs, props and bosses; a floor over the whole screen goes on `mode7()` |
| `mesh_new(verts, faces)` | a 3D model kept once, its number (up to 48 a game): `verts = {{x, y, z}, ...}` (512 at most), `faces = {{a, b, c, d}, ...}` (256 at most) with vertex numbers from 1, in the order `quad` takes corners (top-left, top-right, bottom-right, bottom-left, going clockwise on the screen when seen from outside; a triangle gives three numbers). Each face may carry `uv = {u1, v1, ..., u4, v4}` in texels (six numbers for a triangle), on every face or on none (then the whole picture is on each face). For `mesh()` |
| `mesh(mesh, id, {pos, rot, scale, focal, cx, cy, near, light, fade, snap, cull, dither, frame})` | the model turned, projected, culled, lit and sorted **in C**, and drawn far to near with the picture `id` on every face; returns how many faces show. `pos = {x, y, z}` is where its origin is from the camera (z away, y down, default `{0, 0, 400}`), `rot = {rx, ry, rz}` degrees applied as Rx·Ry·Rz, `scale` (1). The screen is `cx + x * focal / z` (focal 160, cx 240, cy 160). A face with a corner nearer than `near` (1) is left out, not cut. `cull` (true) leaves out the faces turned away. `light = true` or `{dir = {x, y, z}, ambient = 0.25, gain = 0.75}` lights each face flat by `ambient + gain * (dir · normal)`, `dir` pointing toward the lamp in camera space (as a PlayStation's GTE did; 0x80 as it is, up to twice as bright), dithered unless `dither = false`. `fade = {near, far}` darkens with distance: full at `near`, black at `far`. `snap = true` rounds every corner to a whole pixel, the PlayStation's wobble. The faces of a call are **one command**, so they do not use the 128 slots of `quad`: a frame holds 384 faces from all its `mesh` calls (the nearest of each are kept past that) and 2048 commands. Faces are ordered by their average depth in 256 steps, as a PlayStation's ordering table was: a model that folds into itself can show a wrong face. The cost is the pixels filled, as for `quad` (about 300 ns a lit one on the console); what `mesh` takes off is the maths in Lua |
| `light(x, y, r, colour [, {intensity, sub, cone}])` | a soft round glow of that colour reaching `r` pixels, added to what is under it (a candle, a lamp, a window's light); `sub = true` takes light away instead (a pool of shadow); `intensity` 0 to 2; `cone = {angle = degrees (0 right, 90 down), width = degrees across}` makes it a beam (a flashlight, a guard's sight), full in two thirds of it and half at the rim. It reads no picture: only the pixels it reaches cost (about 200 ns each on the console: a lamp of radius 60 is 2 ms, of 100 about 6; a beam a third of that). Dim a baked background through its palette first (`img(..., {dim = 0.4})` or `{mul = 0x6070C0}`, a colour a channel, 0xFF as it is: free for a packed picture) and add the lights on it |
| `warp(id, x, y, {rows, cols, wrap, frame})` | a picture with each row `j` moved right by `rows[j]` pixels and then each column `i` of the result moved down by `cols[i]` (a table, or a function asked for each from 0): water that ripples, heat over a road, a flag, a panorama going round (`wrap = true`); the Saturn's line and column scroll, at the screen's own 480x320. It reads the picture's pixels one by one: about 110 ns a pixel on the console (the whole screen is 17 ms, a frame), so for a part of it (a lake, a banner), not all of it |
| `linetint(x, y, w, h, colours [, {add, sub, alpha, lay}])` | each row of the box in a colour of its own (a table of `0xRRGGBB`, or a function asked for each row from 0), added to what is there (the default), taken from it (`sub = true`), mixed (`alpha = 0.5`) or laid as it is (`lay = true`): a sunset down a wall, a flash up a floor, the Saturn's colour offset for each line |
| `preload({images = {ids}, sounds = {ids}})` | reads those pictures and sounds from the card now, so the first time they are drawn or played nothing waits (a room's, behind the curtain that closes); returns how many of the pictures there are |
| `imgsize(picture)` | its width, height and frames, or `nil` |

`quad(..., {uv = {u1,v1, u2,v2, u3,v3, u4,v4}})` selects texture coordinates in texels for each corner. Defaults to the whole picture; useful for a cropped or near-clipped 3D face. Custom UV currently skips mip selection, so keep its source picture small.

Everything else draws on a canvas too: `text`, `rect`, `img`, `frame`, `shade`... A canvas is shown like any
picture, with `img`, `frame`, or as a background layer (`bg(n, {image = "CANVAS"})`); what it holds when the frame
is drawn is what is seen. A game's canvases share 3 MB (a 480×320 one takes 300 KB). Drawing `0xFF00FF` on a canvas
gives a colour one step from it: that exact colour is how a canvas keeps its see-through pixels.

```lua
canvas("LAND", 240, 160)            -- in _init
target("LAND")
circ(x, y, 14, CLEAR)               -- a bomb: a hole in the land
target()
if pget(px, py + 4, "LAND") then    -- standing on something
```

`noise(x [, y [, z]])` gives smooth noise between about -1 and 1 (Perlin's), the same everywhere: hills along `x`,
clouds over `x, y`, the same clouds moving with time as `z`.

## Video

Video, played on a canvas a frame at a time from the card: the news on a TV studio's monitors, a tape that rewinds,
a cutscene, a window onto somewhere else. `tools/clip2npv.py` makes one from a video (with ffmpeg), an animated GIF or
a folder of PNGs:

```
python3 tools/clip2npv.py news.mp4 mygame NEWS --width 240 --height 160 --fps 15
```

It fits the picture inside the size given (240×160 by default: drawn at scale 2 it fills the screen), cuts the clip into
scenes where the picture changes (`--cut`, 0 to 1) and gives each scene its own palette of up to 256 colours (`--colours`;
`--one-palette` for one for all), as the 32-bit consoles' cutscenes did; `--ordered` spreads the colours' rounding in the
PlayStation's 4x4 pattern, which stays in place from frame to frame and so costs little (`--dither` is finer but its noise
moves, and the file grows many times). Each frame is kept as what changed since the one before, with a whole frame at each
scene's start and every two seconds within it (`--key N` frames).
The sound, if the video has any, goes to `audio/<id>.wav`.

| Call | Does |
|---|---|
| `video(id [, {canvas, loop, speed, play}])` | plays `video/<id>.npv` on the canvas `id` (or `canvas`), made the clip's size; returns the clip. `loop` false, `speed` 1, `play` true by default |
| `c:play()`, `c:pause()`, `c:playing()` | |
| `c:seek(frame)` | that frame now (0 is the first) |
| `c:frame()`, `c:frames()`, `c:fps()` | the frame shown, how many, how many a second |
| `c.speed = 2` | faster; `0.5` slower; `-1` backwards (each frame back is worked out from the whole frame before it: a clip made with `--key 1` rewinds cheaply) |
| `c:close()` | its file closed; 8 clips can be open at once |

```lua
tv = video("NEWS", {loop = true})          -- in _init
music("NEWS")                            -- its sound, started with it
img("NEWS", 300, 40, {scale = 0.5})      -- in _draw: a monitor in the corner
```

A clip moves on by itself with the ticks (one frame every 4 ticks at 15 fps), in step with music started with it.
A 240×160 clip at 15 fps takes about 50-100 KB a second of card: fine on the microSD, big for a game in the
console's flash.

## First person

`raycast(canvas, view)` draws a map of walls seen from inside it onto a canvas, a column at a time, as Wolfenstein 3D
did: walls textured and darker far away, the floor darker towards the horizon, sprites standing in the maze hidden by
the walls in front. The game shows the canvas as it likes: `img("VIEW", 0, 0, {scale = 2})` fills the screen from a
240×160 view. `examples/laberinto` is a whole game.

```lua
canvas("VIEW", 240, 160)                                   -- in _init
local dist, wall = raycast("VIEW", {
  map = {"#####", "#...#", "#.#.D", "#####"},             -- a character a square; space or . is open
  walls = {["#"] = "TEX_STONE", D = 0x40A060},             -- a wall's picture (frame 0 wraps a square) or colour
  x = 1.5, y = 1.5, angle = 0, fov = 66,                   -- in squares; degrees, 0 east, 90 south
  fog = 12, ceiling = 0x303040, floor = 0x505050,          -- squares to black (0: none)
  sprites = {{x = 3.5, y = 1.5, picture = "GHOST", frame = 0, scale = 1}},
})
```

It returns the distance to the wall in the middle of the view (along the view, in squares) and that wall's
character: what a shot straight ahead would hit, and how far. Walking, colliding and the ghosts' thinking are the
game's, in Lua, on the same map. Wall and sprite pictures are plain ones (not `--packed`); a whole view of 240×160
is about 38,000 pixels.

`voxels(canvas, {height, colour, x, y, angle, z, horizon, distance, fov, scale, sky, fog})` draws a landscape from a height
map and a colour map the way Comanche (1992) did, a column at a time, nearest first: `height` a canvas or plain picture
whose brightness is the ground's height (0..255), `colour` one with its colours (both wrap; `colour` left out: the
height map's own), the camera at `x, y` on the map, `angle` in degrees (0 east, 90 south), `z` its height, `horizon`
the screen row of the far horizon, `distance` how far it looks (map pixels, 300), `scale` how tall the hills stand,
`sky` the colour above, `fog` the distance from which the ground fades to it (0: none). A 240×160 view out to 300 is
about 60,000 samples. `tests/games/looks` has one.

## Swarms

Bullets, sparks, rain, stars, a crowd: many things that move the same simple way. Moved and drawn from Lua, each one
costs some microseconds on the console to move and as many to draw, so a few hundred take a whole frame. A swarm
moves, culls, tests and draws them in C: 300 orbs and more at 60 frames a second.

| Call | Does |
|---|---|
| `s = swarm(cap [, {x0, y0, x1, y1}])` | room for `cap` (up to 4096); those that leave the area go (default: the screen and 32 pixels around it) |
| `s:add(x, y [, vx, vy [, life]])` | one more, moving by vx, vy a tick, for `life` ticks (none: until it leaves); `false` when full |
| `s:step()` | each moves; those out of the area or out of life go |
| `s:draw(picture [, frame])` | each drawn centred on its point: one command for them all (the camera applies) |
| `s:hit(x, y, w, h [, keep])` | how many are in that box; they go, unless `keep` |
| `#s`, `s:get(i)`, `s:set(i, x, y [, vx, vy])`, `s:remove(i)`, `s:clear()` | how many; one of them, 1 to `#s` (x, y, vx, vy, life); move one; take one out; all out |

```lua
orbs = swarm(1500)
orbs:add(boss_x, boss_y, math.cos(a) * 2, math.sin(a) * 2)   -- in _update: a ring, one by one
orbs:step()
if orbs:hit(ship_x - 6, ship_y - 5, 12, 10) > 0 then hurt() end
orbs:draw("SPR_ORB")                                          -- in _draw
```

Which one is where changes as they go (the last takes the place of one that leaves): keep anything a single one needs
in Lua tables instead. `examples/nubes` fires its shots and the battleship's orbs this way.

## Grids

A game's thinking on a grid of cells, done in C: where to walk round the furniture, how far a unit can move this turn,
where a crowd heads, a smell or a noise spreading through the rooms. Cells count from 0, as `mget`'s.

| Call | Does |
|---|---|
| `g = grid(w, h [, cost])` | a grid of up to 256×256 cells, each costing `cost` (1) to enter; 0 is a wall, up to 255 (mud, stairs, a guarded door) |
| `g:set(x, y, cost)`, `g:get(x, y)`, `g:size()` | |
| `g:path(x0, y0, x1, y1 [, {diagonal = true}])` | the cheapest way there (A*): a list of `{x, y}` steps, the first after the start, the last the goal, and its cost; `nil` if there is none. Diagonal steps cost 1.4 and never cut a wall's corner |
| `g:reach(x, y, budget [, {diagonal}])` | every cell it can get to for that much: a list of `{x, y, cost}` (a tactics unit's moves) |
| `g:distances(x, y [, {diagonal}])` or `g:distances({{x, y}, ...})` | a layer: each cell's cost to the nearest target (`nil` where none can be reached). Many walkers each take `f:descend(x, y)`: one search for all of them |
| `l = g:layer([value])` | a number on every cell: a smell, a noise, heat, danger |
| `l:get(x, y)`, `l:set(x, y, v)`, `l:add(x, y, v)`, `l:fill(v)` | |
| `l:spread(rate [, fade])` | once: each open cell moves `rate` (0 to 1) of the way to its open neighbours' mean, then all fade by `fade` (0 to 1). Walls hold nothing |
| `l:scale(k)`, `l:mix(other [, w])` | every cell times `k`; `other`'s cells added, times `w`: several wants (food, danger, the hero) into one map |
| `g:rescan(layer [, {diagonal}])` | a layer: each cell's value made no more than the cheapest neighbour's plus the step, from the layer's own values (Brogue's Dijkstra maps): a distance field scaled by -1.2 and rescanned leads away from the hero and into corners to hide, not straight into a wall |
| `g:fov(x, y, radius [, layer])` | what is seen from that cell (shadowcasting, as roguelikes do it): a layer with 1 on every cell in view within the radius, walls seen included, 0 elsewhere; a layer of the grid given is filled instead of making one. Fog of war, a lantern, a guard's eyes (walls are the cells of cost 0) |
| `g:sees(x0, y0, x1, y1)` | `true` when no wall stands on the straight line between the two cells (the ends may be walls): does the guard see the hero |
| `l:climb(x, y)`, `l:descend(x, y)` | `dx, dy`: to the open neighbour with the most (follow a smell) or the least (walk down a distance field, flee a noise); `0, 0` when none is better |

```lua
local g = grid(30, 20)                       -- the house, from the level: walls 0, rugs 1, the cat flap 3
local path = g:path(cat.x, cat.y, bowl.x, bowl.y)
local smell = g:layer()
smell:add(fish.x, fish.y, 50)                -- each tick: the fish smells, it spreads and fades
smell:spread(0.4, 0.02)
local dx, dy = smell:climb(cat.x, cat.y)     -- the cat follows its nose
```

On the console a path right across a 64×64 grid full of obstacles takes about 5 ms (it looks at most of the cells;
across a room of 30×20, about a millisecond), a distance field over 64×64 about 10 ms and a spread 2.5 ms: work out
paths when something decides to go somewhere, not every tick for everyone, and for a crowd heading the same way use
one `distances` for all of them.

## Playing together (link)

Consoles near each other running the same game can send each other messages: no router, no internet. On the
console they go by ESP-NOW, radio to radio (tens of metres); in the desktop simulator, between simulators on the
same computer or network; in the browser player, between tabs of the same browser. Only consoles running the same
game (the same `id` in game.json) hear each other.

| Call | Returns |
|---|---|
| `link.send(value [, to])` | `true`, or `false` when this console has used up its share of the air for now (20 messages a second). `value` is a number, string, boolean or a table of them, as `store`, up to 220 bytes as JSON; `to` is one console's id, or everyone |
| `link.recv()` | `from, value` of the oldest message waiting, or `nil`: `for from, m in link.recv do ... end` |
| `link.peers()` | the ids of the consoles playing this game nearby (heard in the last 3 seconds), smallest first: every console sees the same order, so they can agree who is player 1 or who sits next to whom. Up to 16 at once; an id is a large number, not 0, 1, 2: take a console's place in this list, not its id |
| `link.id()` | this console's id (0 where there is no radio) |

The radio comes on the first time a game uses `link` and goes off when it ends. Messages can be lost on the way
and can come late: send what the state is, often (where you are, what you drew this moment), rather than one
change once. What comes from another console may be anything: check its shape before using it
(`type(m) == "table" and type(m.x) == "number"`). `examples/juntos` is a shared whiteboard and a ball passed from
screen to screen. Its test plays the other consoles with `link_from <id> <json>` and checks what was sent with
`expect_link_sent <text>`.

A game runs the same on every console: Lua's numbers are 32-bit everywhere and `pairs()` walks a table in the same
order, so consoles that get the same messages can compute the same thing.

## Sound

| Call | Does |
|---|---|
| `sfx(id [, gain [, {pitch, loop, pan, reverb, attack, decay, sustain, release, loop_start, loop_end, delay, pitch_var, gain_var, max, cooldown}]])` | plays `audio/<id>.wav` (or a sound made with `sound`) once, or looping; `pitch` 1 as recorded, 2 an octave up, 0.5 down; `pan` -1 (left ear) to 1 (right), 0 the middle: the far ear fades to nothing as it goes, the near one stays full, so an unpanned sound is as it always was. Platforms with one speaker hear it at half. `attack`, `decay` (seconds), `sustain` (0 to 1, the level it settles at) and `release` (seconds) shape its volume like a PlayStation voice: it climbs, falls to the sustain level, and when you `sfx_stop` it, lets go over the release instead of cutting (any of the four makes an envelope; the others default to no attack, no decay, full sustain, no release). `loop_start` and `loop_end` (seconds into the clip, with `loop = true`) loop only that part: a held organ note, an engine's steady hum after its start-up. `reverb` (0 to 1) sends that much of it into the room set by `reverb()`. Returns a handle; `delay` (seconds, up to 10) starts it that long after the next block of sound, to the sample, so hits asked for in one frame keep their exact spacing; `pitch_var` (semitones each way) and `gain_var` (0..1 each way) vary each play a little, so a footstep or a hit is never twice the same (a cue the player must know, a coin, stays exact); `max` plays it only while fewer than that many of it sound (0 is given back); `cooldown` (seconds) not again within that of its last play |
| `audio/<id>.vag` | a sound kept as the PlayStation's ADPCM (4 bits a sample, a third of PCM16 in memory, decoded as it plays): `uv run tools/wav2vag.py in.wav GAME ID [--loop START END]` makes it from any WAV; `sfx("ID")` plays it like a WAV (a `.vag` of the same name wins), and with `loop = true` loops the part the file was given (or `loop_start`/`loop_end`, rounded down to 28 samples). Not for studio tracks, which take WAVs |
| `sfx_set(handle, {gain, pitch, pan})` | changes a sound while it plays: an engine that follows the speed, a theremin, a car crossing the screen |
| `sfx_stop(handle)`, `sfx_on(handle)` | stops it (a sound with a `release` fades over it); is it still playing? |
| `instrument{sample, root, loop, adsr, gain, reverb}` | a recording that plays any note (below). Returns the instrument |
| `i:play(note [, velocity [, {reverb, delay}]])` | plays a note (a name like `"E4"` or a frequency in Hz) at the pitch it needs; `velocity` 0 to 1. Returns a handle, which `sfx_set`, `sfx_stop` and `sfx_on` take as well |
| `i:release(handle)` | lets the note go: its envelope's release, then it ends. An instrument with no envelope stops |
| `reverb(room [, wet [, {music, ambient}]])` | a room of the PlayStation's for the game's sounds, the one its sound chip's own reverb is: `"room"`, `"studio_small"`, `"studio_medium"`, `"studio_large"`, `"hall"`, `"half_echo"`, `"space_echo"`, `"delay"`. `wet` (0 to 1, default 0.5) is how much of the room comes back; a sound goes into it with `sfx`'s `reverb`, the music and the ambience with `music` and `ambient` (default 0). `reverb()` lets it ring out and goes. Each room keeps a few to 60 KB of memory while it is on |
| `volume(v)` | everything the game sounds (effects, music, tones, the studio), from 0 (silent) to 1; each game starts at 1 |
| `sound(id, recipe [, seed])` | makes a sound from a recipe: `"coin"`, `"laser"`, `"explosion"`, `"powerup"`, `"hit"`, `"jump"`, `"blip"` or `"random"`; each seed gives another. Returns its numbers |
| `sound(id, {numbers})` | makes a sound from its numbers (below), played with `sfx(id)`. Returns them, completed |
| `music(id)` / `music()` | loops `audio/<id>.mod` (a ProTracker module), `.xm` or `.s3m` (FastTracker II and Scream Tracker 3: instruments with envelopes; their samples are kept as 16-bit in the console's slow memory, so an XM of 8-bit samples takes twice its size there), `audio/<id>.spum` (ADPCM, read from the card as it plays: a third of the WAV's size, `uv run tools/wav2vag.py song.wav GAME ID --stream --loop SAMPLE`, whose channels are its layers and whose loop comes from the file) or else `audio/<id>.wav`; no id stops it |
| `music(id, fade_ms, {bar, beats, loop_at, layers, at})` with a WAV or SPUM | `bar`: a bar's length in seconds, so changes of layers (`music_layer`) and of songs land on bar lines; `beats` a bar (4), for `music_beat()`; `loop_at`: where the song goes back to (seconds); `layers`: each channel's gain at the start (`{1, 0, 0}`: the first stem only, the others brought in with `music_layer`); a WAV's own markers serve when `bar` or `loop_at` is not given: the loop from its `smpl` chunk (the loop region a DAW or Audacity writes), the bar from the distance between its first two cue points (`cue ` chunk); `at = "bar"`: the song starts on the next bar line of the one playing, as iMUSE's transitions did (the new one is opened now and waits; `music_queued()` says so), else now. A module (`.mod`) takes `at = "bar"` too, no `bar` needed: its bar is sixteen lines (four beats of four, as most are written); and `music(nil, fade_ms, {at = "bar"})` lets the module play to its bar line and fades it there, as a theme ends on a button |
| `music_beat()` | `bar, beat, fraction`: where the song is, as the player hears it (bars and beats from 1, the fraction of the beat gone); `nil` with no song or no `bar` given (a module counts its own lines: sixteen a bar, four a beat). A dancer in step, a note landing on the beat, a change readied for the bar |
| `music(id, fade_ms, {bank, loop, volume})` with `audio/<id>.mid` | a song as notes, as the PlayStation's SEQ and VAB: a Standard MIDI File played by a bank of samples, `audio/<bank>.bank` (default `"BANK"`). The notes take their own 16 voices, never a sound effect's; they have each instrument's envelope, the channel's volume, pan, expression, sustain pedal, reverb send (with `reverb()`) and pitch bend; channel 10 is the drum kit. A marker `loopStart` (or controller 111) and `loopEnd` set the loop, else the whole song goes round. Make a bank with `uv run tools/mkbank.py kit.json GAME BANK` (your WAVs, the keys each serves, its root note, loop and envelope) or from any General MIDI SoundFont: `uv run tools/mkbank.py --sf2 font.sf2 GAME BANK --programs 0,33,48 --drums --kb 1500`. Samples are ADPCM, a third of PCM16; a bank lives in memory (up to 8 MB, mind the PSRAM) |
| `bus(name [, {gain, lowpass, fade}])` | what a group of sounds goes through, set at once for all of them: `"music"` and `"ambient"` take a gain (0..1) and a lowpass (Hz; 0 open), `"sfx"` (the game's sounds) a gain; `fade` in seconds (0.3). `bus("music", {gain = 0.5, lowpass = 600})` muffles the song (a WAV, a module) for a pause or under water; `bus("music")` opens it again. The console's own volume (`settings().volume`) is over all of them |
| `duck([{to, attack, hold, release}])` | the music dips to `to` (0.3) over `attack` (0.05 s), stays `hold` (0.5 s) and comes back over `release` (0.6 s): a voice line, a big hit, a pickup that must be heard |
| `music_pan(pan [, fade_ms])` | the song placed between the ears, -1 (left) to 1 (right), moving there over the fade (a speaker with one ear hears it at half, as a sound's pan) |
| `ambient(id [, fade_ms [, {pan}]])` / `ambient()` | a bed of sound under the game (a room's murmur, rain, a crowd) from `audio/<id>.wav` or `.spum`, looping, crossfading with the one before it (up to three at once); `ambient()` fades it out. With the world's lowpass (`listen`) and `pan` -1 to 1 |
| `music_layer(stem, gain [, fade_ms])` | a WAV's channels are layers (drums, bass, melody... up to 3): each comes in or goes out, so the music follows the game |
| `music_time()` | seconds into the song `music()` started, as the player hears it now, going on across its loops; `nil` when none plays. For notes on the beat |
| `tone(voice, pitch [, options])` | plays a synthesised note on voice 0-3, replacing what it played |
| `tone(voice)` | lets the voice's note go (it fades with its release) |
| `tone_set(voice, {vol, bend})` | changes a note while it sounds: its volume (0 to 1), its bend in semitones (a slide up to the next note, a dive-bomb) |
| `note(name)` | the frequency of a note: `note("A4")` is 440, also `"C#3"`, `"Eb5"` |

Recordings are not the only way: like the GBA's sound channels, four voices make notes from waveforms, for music
and effects written in Lua. `pitch` is a frequency in Hz or a note name. The options, all optional:

| Option | Default | |
|---|---|---|
| `wave` | `"square"` | `"square"`, `"triangle"`, `"saw"`, `"sine"`, `"noise"` or `"fm"` (two operators: a sine bent by another `fm_ratio` times higher, `fm_index` deep (1: a cycle of phase), the depth following the envelope: a bell with `fm_ratio = 3.5`, an electric piano with 1 and a short decay); or a table of 32 numbers from 0 to 15, one period of any shape you draw (the GBA's wave channel) |
| `vol` | 0.5 | 0 to 1 |
| `lfsr` | 15 | noise only: `7` makes the shorter, pitched noise (metallic hiss, a hi-hat, a tone-like buzz) |
| `vibrato` | none | `{depth = 25, speed = 5.5, delay = 0}`: the pitch wobbles that many cents each way, that many times a second, after `delay` seconds |
| `bend` | 0 | semitones above the note (`tone_set` moves it while the note sounds) |
| `duty` | 0.5 | square only: the high part of each period (0.125 and 0.25 sound thinner) |
| `attack` | 0.005 | seconds to reach full volume |
| `decay` | 0.25 | seconds (time constant) to fall towards `sustain` |
| `sustain` | 0 | the level held after the decay; 0 makes a plucked note that ends by itself |
| `len` | 0 | seconds until the note is let go; 0 waits for `tone(voice)` (or for the pluck to end) |
| `release` | 0.03 | seconds to fade once let go |
| `slide` | 0 | Hz per second added to the pitch: negative for a drop, positive for a rising zap |

```lua
tone(0, "C5", {wave = "square", duty = 0.25, decay = 0.08})           -- a blip
tone(1, 900, {wave = "noise", decay = 0.2})                            -- a hit
tone(2, 1200, {wave = "saw", sustain = 1, len = 0.15, slide = -6000})  -- a laser
tone(1, "C2", {wave = {8,10,12,14,15,14,12,10,8,6,4,2,0,2,4,6,8,10,12,14,15,14,12,10,8,6,4,2,0,2,4,6}, sustain = 1})  -- a bass
tone(0, "A4", {sustain = 1, vibrato = {depth = 20, speed = 6, delay = 0.2}})                                    -- a held note that sings
```

Music made in a tracker (MilkyTracker, OpenMPT, ProTracker...) saved as a ProTracker `.mod`, up to 32 channels and
4 MB, plays with `music(id)` like a WAV, in far less space; on the console it takes about 3 % of a core.

A tune is notes played from `_update` on a beat: keep a step counter and call `tone` when it changes. The `puzle`
example does its music this way.

**On the beat.** A rhythm game reads `music_time()` every tick: it follows the samples the speaker plays, not the
game's ticks, so notes stay on the song however long it lasts. What is queued for the speaker is already taken off
(about 70 ms on the console, more in a browser); the player's ears and screen add the rest, so a rhythm game lets
them tune it once, tapping along:

```lua
local bpm, offset = 120, stored("offset", 0)        -- offset: the player's own, in seconds
local beat = (music_time() - offset) * bpm / 60      -- 3.0 is the fourth beat, right now
-- tuning: taps on a steady beat; each tap's distance to the nearest beat, averaged, is the offset to store
local d = ((music_time() * bpm / 60 + 0.5) % 1 - 0.5) * 60 / bpm
```

Buttons are read once a tick (every 17 ms): judge a hit within about 50 ms of its beat, and do not ask for less.

### Sounds made from numbers

`sound` makes a sound the way sfxr did (and every jam game since): a wave whose pitch slides, wobbles or jumps,
shaped by an envelope and filters. A game can make a hundred of them with no files, a different one for each enemy,
or a new one each level (`sound("ZAP", "laser", level)`). The numbers, all optional:

| Number | Default | |
|---|---|---|
| `wave` | `"square"` | `"square"`, `"triangle"`, `"saw"`, `"sine"`, `"noise"` or `"fm"` (with `fm_ratio` (2) and `fm_index` (1), the depth falling over the sound) |
| `freq`, `freq_min` | 440, 0 | Hz at the start; a falling sound ends when it gets below `freq_min` |
| `slide`, `slide_accel` | 0, 0 | Hz per second the pitch moves (negative falls), and how that changes per second |
| `vibrato`, `vibrato_speed` | 0, 6 | a wobble, 0 to 1 deep, Hz fast |
| `arp`, `arp_time` | 1, 0 | after `arp_time` seconds the pitch is multiplied by `arp` (a coin's jump) |
| `duty`, `duty_sweep` | 0.5, 0 | square: the high part of each period, and how it moves per second |
| `attack`, `sustain`, `decay` | 0, 0.1, 0.2 | seconds: rising, holding, falling (4 s in all at most) |
| `punch` | 0 | 0 to 1: louder at the start of the sustain |
| `lowpass`, `lowpass_sweep`, `resonance` | 1, 0, 0 | 0 to 1 (1 lets everything through), its move per second, how it rings |
| `highpass`, `highpass_sweep` | 0, 0 | 0 to 1 (0 lets everything through), its move per second |
| `again` | 0 | seconds after which it starts over (an alarm, a climbing power-up) |
| `volume`, `seed` | 0.5, 1 | how loud; the noise's seed |

```lua
local zap = sound("ZAP", "laser", 7)      -- a laser, the seventh of its kind
zap.slide = zap.slide * 2                 -- falls twice as fast
sound("ZAP2", zap)
sound("HUM", {wave = "sine", freq = 220, sustain = 1, decay = 0})   -- whole cycles in a second: it loops cleanly
local h = sfx("HUM", 0.5, {loop = true})
sfx_set(h, {pitch = 1 + speed / 10})      -- in _update
```

### Instruments

An instrument turns one recording into any note, as the GBA's sound driver did with its small samples: it is played faster or
slower to reach the note, it loops a part of itself while the key is held, and an envelope shapes the start and the end.

```lua
sound("PAD", {wave = "saw", freq = 220, sustain = 1, decay = 0})
local pad = instrument{
  sample = "PAD", root = "A3",           -- the note the recording is at ("C4" if left out)
  loop = {from = 0.1, to = 0.8},         -- seconds: plays on to 0.8, then round from 0.1 while held; true: the whole sound
  adsr = {a = 0.02, d = 0.15, s = 0.6, r = 0.4},   -- seconds, and the sustain's level (0 to 1)
  gain = 0.8, reverb = 0.3,               -- reverb: how much goes through the game's reverb(room)
}
local h = pad:play("E4", 0.9)            -- in _update, when the key goes down
pad:release(h)                           -- when it comes up: it fades over `r`, then ends
```

Without `adsr` the envelope is a short one (3 ms in, 80 ms out) so a note never clicks; `adsr = false` plays the recording
as it is. It is the engine's `sfx` voice with an envelope (the attack climbs evenly; the decay and the release fall by a constant
factor a sample, as the PlayStation's sound chip's do) and a loop region, so what `sfx` says about voices holds: a new sound takes
the one nearest its end when they are all busy. Times are turned into whole samples once, when a note is played.

A sound that stops dead (`decay = 0`) is meant to loop; one that decays fades its last moment so it never clicks.
Making a sound takes a moment (a long one, some hundredths of a second on the console): make them in `_init` or
between levels, not every frame. A game's made sounds share 1 MB (about 24 seconds).

### The studio: steps on the sample

A drum machine, a tracker's pattern, a rhythm game's own beat: tracks of sounds on steps, played by a sequencer that
runs where the sound is mixed. Each step starts on its exact sample at any tempo (steps played from `_update` move by
up to 17 ms, and only tempos of 900/n BPM fall on whole ticks), and keeps time while a frame is slow.

| Call | Does |
|---|---|
| `studio.tempo(bpm [, swing])` | 30 to 300 BPM, a step is a 16th; swing 50 (straight) to 75 %, as an MPC's: the odd steps come later (66 is a triplet's feel) |
| `studio.length(steps)` | steps in the pattern, 1 to 64 (16 at the start: a bar) |
| `studio.track(i, {sound, gain, pitch, choke})` | track 1 to 16 plays `audio/<sound>.wav` or a sound made with `sound`; `gain` 0 to 1, `pitch` as `sfx`'s, `choke` 1 to 15: a hit cuts the tracks of its group still sounding (an 808's closed hat cuts its open one), 0 none. What is left out stays as it was. `true` if the sound is there |
| `studio.steps(i, {v, v, ...} [, next_bar])` | each step's velocity, 0 (silent) to 1; `true` and `false` are 1 and 0. Change them while it plays; with `next_bar` true they take over when the sequence next comes round to its first step, on its sample: a song's next section, its bar line exact however late the game asks |
| `studio.play([step])`, `studio.stop()`, `studio.playing()` | from that step (1, the first, if left out) |
| `studio.pos()` | `step, fraction`: the step the player hears now (1 to the length) and how far into it, past what is queued for the speaker (as `music_time`); `nil` when stopped |
| `studio.hit(i [, velocity])` | the track's sound now, as a pad: what a player plays by hand, recorded on the step `studio.pos()` is nearest to |

```lua
studio.track(1, {sound = "KICK"})
studio.track(2, {sound = "HAT", choke = 1})
studio.track(3, {sound = "HAT_OPEN", choke = 1})
studio.steps(1, {1, 0, 0, 0, 1, 0, 0, 0, 1, 0, 0, 0, 1, 0, 0, 0})
studio.steps(2, {0, 0, 1, 0, 0, 0, 1, 0, 0, 0, 1, 0, 0, 0, 0.5, 0})
studio.tempo(96, 58)
studio.play()
local step, f = studio.pos()          -- in _update: light the step's key, nod on the beat
```

**Synth tracks.** A track can play notes on a synth voice instead of a sound: an acid bass as a TB-303 plays it,
one note at a time. Its oscillator is band-limited (no harsh folding at 22 kHz), a soft drive feeds a resonant
lowpass that an envelope opens on each note, an accented note opens it further and plays louder, and a note that
slides glides into the next without starting again. A knob turned while it plays glides there, with no zipper.

| Call | Does |
|---|---|
| `studio.synth(i, {wave, cutoff, res, env, decay, accent, glide, drive, volume, tune})` | track i plays notes: `wave` `"saw"` or `"square"`; `cutoff`, `res` (how it rings), `env` (how far each note opens the filter), `accent`, `drive`, `volume` 0 to 1; `decay` and `glide` in seconds (the filter's fall, a slide's time); `tune` in semitones. What is left out stays as it was |
| `studio.notes(i, {...} [, next_bar])` | a note per step (`next_bar` as in `studio.steps`): MIDI (60 is C4), a name (`"A1"`, `"F#2"`, `"Bb3"`), or `{note, accent = true, slide = true}`; `0`, `false` or nothing is a rest. A slide holds the note into the next step and glides to it |
| `studio.note(i [, note [, accent]])` | a note played by hand, held a little over half a step; no note lets one go |

```lua
studio.synth(2, {wave = "saw", cutoff = 0.25, res = 0.8, env = 0.6, decay = 0.2})
studio.notes(2, {"A1", 0, {"A2", accent = true}, 0, {"A1", slide = true}, "C2", 0, "E1",
                 "A1", 0, "G1", 0, {"A1", accent = true, slide = true}, "A2", 0, 0})
studio.synth(2, {cutoff = 0.6})         -- turned while it plays: the acid sweep
```

**Effects.** Each track sends some of itself to an echo and a reverb (`delay` and `reverb`, 0 to 1, in
`studio.track` and `studio.synth`), and the whole game's sound can go through Lo-fi GBA.

| Call | Does |
|---|---|
| `studio.fx({delay, feedback, tone, reverb, size, damp, gate, lofi})` | the echo's time in steps (3 is a dotted 8th; it follows the tempo, gliding as a tape would), its repeats (`feedback` 0 to 0.95) and `tone` (0 dark as a tape echo's, 1 bright); `reverb` `"plate"` or `"gba"`: the two echoes, ~100 and ~117 ms apart, that Nintendo's GBA sound driver fed back into its mix, `size` and `damp` 0 to 1; `gate = true` cuts the plate's wet tail about 200 ms after its send falls silent (no effect on GBA); `lofi = true` holds everything the game plays at 13,379 Hz and cuts it to 8 bits with no dither, as that driver mixed. What is left out stays as it was |

```lua
studio.track(2, {sound = "SNARE", reverb = 0.4, delay = 0.2})
studio.synth(9, {cutoff = 0.3, delay = 0.35})
studio.fx({delay = 3, feedback = 0.45, tone = 0.3, reverb = "gba", size = 0.6, lofi = true})
```

A track plays the first of a sound's variants every time (a pattern sounds the same each time round), and its sound
stays in memory while a track holds it. Twelve sounds play at once, with `sfx` too: the one-shot closest to its end gives way.

## The microphone

The console hears: blowing on a candle, singing a note that opens a door, a clap on the beat, a cat's miaow made by
the player. The browser asks the player first; the simulator uses the computer's microphone.

| Call | Does |
|---|---|
| `mic()` | `level, pitch, hit, recording, kind`, or `nil` where there is no microphone (or the player said no). The first call starts listening |
| `mic(false)` | stops listening |
| `mic_record(id, seconds)` | what it hears for up to 10 seconds becomes the sound `id`, played with `sfx(id)` like any other; `true` if it started |
| `mic_record()` | ends the recording sooner |

- `level` goes from 0 (silence) to 1 (a shout close to the console), worked out every tick.
- `pitch` is the note heard in Hz (a voice, a whistle, a recorder: 70 to 1000 Hz), or 0 when there is no clear one
  (noise, a breath, silence). `note("A4")` gives the Hz of a note to compare with.
- `hit` is true on the one tick a sudden sound starts: a clap, a knock on the table, a shout.
- `recording` is true while `mic_record` is still listening.
- `kind` is what the sound is, or `nil` (silence, or a sound that is none of these):
  `"blow"` someone blowing on the console (wind on the microphone: low, without a note, held a moment: a candle, dust,
  a sail), `"voice"` a voice, sung or shouted (it has a pitch; how loud is `level`), `"whistle"` a whistle or any clean
  high note (500 Hz and up), `"clap"` a clap or a knock (a `hit` without a note). Plain noise, a fan, the street, is
  none of them.

```lua
local level, pitch, hit, _, kind = mic()
if not level then                         -- no microphone: a button does it instead
  blowing = btn("a")
else
  blowing = kind == "blow"
  shouting = kind == "voice" and level > 0.7
  singing = math.abs(pitch - note("C5")) < 15
  if kind == "clap" then clap() end
end
```

Listening costs the game some time every tick on the console: `mic(false)` when it is not needed.

The microphone also hears the console's own speaker: a game that listens for the player plays its music softly
meanwhile, or not at all. Made sounds and recordings share the same 1 MB.

## The console itself

Games that reach out of the screen: a TV studio's red tally light that comes on when the camera is live, a warning
that the cat's console is running out, a story that knows the player is charging it.

| Call | Does |
|---|---|
| `led(0xRRGGBB)` | the console's pilot LED in that colour. It has red and green only: red, green, yellow, orange (no blue). In a browser, a light in the corner of the screen |
| `led()` | the LED back to the console's own (charging, battery); it is also given back when the game ends. A battery about to die blinks it red whatever the game asked |
| `battery()` | `level, charging`: 0 (empty) to 1 (full) and whether it is charging; `nil` where it cannot be told (a desktop with no battery, browsers without the Battery API). On the console the level is a guess from the voltage, and says little while the cable is in |
| `console_games()` | `list, last, cold`: the console's games, each `{id, title, subtitle, flash, music}`; the index of the one played last (`nil`: none); `true` the first time since the console woke. The console's menu is a pinyol game itself (`firmware/cirera`): these are for it. On a desktop, the game folders in `$PINYOL_GAMES` |
| `console_cover(id, canvas)` | the game's cover (its `cover.rgb565`, 240x160; an adventure's title picture otherwise) on that canvas, and its average colour; `nil` if it has none |
| `console_launch(id)` | ends this game and starts that one |
| `console_off()`, `console_version()` | switches the console off; the firmware's version |
| `tilt()` | `x, y, z`: the way gravity pulls on the console, -1..1 each, relative to the neutral position `tilt_zero()` set (the player holds the console as they like and presses A, as Kirby Tilt 'n' Tumble did; `tilt_zero(false)` forgets it); `nil` on a console without a sensor (the Cirera has none yet: [docs/hardware-rev2.md](hardware-rev2.md); the desktop and the browser say `nil`). A marble that rolls downhill, a cocktail shaken |
| `rumble(ms [, strength])` | a vibration of that many milliseconds (strength 0..1); nothing where there is no motor |
| `console_played()` | the console's record of its games: `{id = {plays, seconds, last (the clock's, when known), seq (the order played in), fav, done = {achievement ids}}}`; the menu shows it and sorts by it |
| `console_favourite(id [, bool])` | whether that game is a favourite; with a value, sets it |
| `achieve(id)` | an achievement of the game earned: `true` the first time. The game lists them in `game.json`, `"achievements": [{"id": "first", "name": "Primer paso", "description": "..."}, ...]`; they are kept by the console with the game's record, whatever happens to the game's saves, and the menu counts them |
| `achievements()` | the list, each `{id, name, description, done}`: a shelf screen, a toast with `hud.toast` when `achieve` says true |

### The console's menu, over every game

A tap of MENU pauses any Lua game and opens the console's menu over it: **Seguir**, the game's own items, **Reiniciar**
(the game from its start, as a fresh run), **Ajustes** and, on the console, **Salir a la lista**; B closes it. A game
that reads MENU itself (`btn("menu")`, `btnp("menu")`...) keeps its taps: for it, MENU held one second opens the menu.
MENU held two seconds goes to the console's list, as always. While the menu is up the game is frozen (no `_update`, no
`_draw`, the sound paused), and `ticks()` does not move.

| Call | Does |
|---|---|
| `menuitem(label, fn)` | an item of the game's own in that menu, three at most (a label of 32 characters): `fn` runs when the player chooses it, with the menu already closed (`menuitem("Nivel 1", function() scene.go(level1) end)`). The same label again changes its function; `menuitem(label)` takes it away, `menuitem()` all of them. A new game (Reiniciar) starts with none: set them in `_init` |
| `_pause()`, `_resume()` | if the game has them, called when the menu opens and when it closes |
| `settings()` | the console's settings, the same for every game, as the player set them in Ajustes: `volume` (0-100, over the game's own `volume()`), `reduce_flashing` (true: the player wants less flashing; `juice.flash` then does nothing, and a game with its own flashes should look at it), `colour` (`"normal"`, `"protan"`, `"deutan"` or `"tritan"`: the world's colours are shifted for that player by the engine, 1.8 ms a frame on the console; the text and shapes over it are not), `speed` (100, 75 or 50: the share of ticks the game gets; its music keeps its pace), `lang` (`"es"`, `"ca"`, `"en"`: the menu's language, for a game that wants to follow it), `swap_ab` (A and B the other way round, done by the engine before the game sees them), `buttons` (what the console's A, B and C do, as three letters: `"ABC"` as they are, `"BAC"` with A and B swapped, done by the engine too), `sticky` (true: a press of A, B or C holds it until the next press, for a player who cannot keep a button down; the engine does it) |

A game that stops on an error shows the **crash screen**: the whole error and its stack, UP and DOWN to read it, A to
start the game again, B back to the list. The same text goes to `crash.txt` in the game's saves folder, to send with a
bug report; and the screen shows it as a QR code too, for a phone to read off the console and paste into the report.

## Libraries built in

Lua code every game can `require`, so a game does not start from nothing. They come inside the engine (the
console, the simulator and the browser have them); a game with a file of the same name uses its own instead, so a
library can be copied into a game and changed. Each file in `lib/` says how to use it at its top.

| `require` | For |
|---|---|
| `"juice"` | what makes a game feel alive: `juice.tween(obj, {x = 100}, 0.5, "out_back")` moves fields with an ease (`linear`, `in_quad`, `out_quad`, `in_out_quad`, `in_cubic`, `out_cubic`, `in_out_cubic`, `in_back`, `out_back`, `out_elastic`, `out_bounce`, `in_bounce`), and chains: `:delay(s)`, `:loops(n)` (-1 for ever), `:yoyo()`, `:on_done(fn)`, `:after(obj, to, secs, ease)` (the next one). Time: `juice.after(secs, fn)`, `juice.every(secs, fn, times)`, `juice.script(fn)` (a function that waits: `juice.wait(secs)`, `juice.wait_until(test)`, `juice.wait_for(tween)`), `juice.cancel(handle or obj)`. `juice.shake(px)`, `juice.freeze(ticks)`, `juice.flash(colour, ticks)`; `juice.update()` in `_update` (true while frozen), `camera(juice.offset())` and `juice.draw()` in `_draw`; `juice.trauma(0.5)` shakes by the square of the hits taken, from smooth noise (`juice.offset()` gives a third value, an angle); `juice.kick(dx, dy)` a push that eases back; `s = juice.spring(f, z, r)` a second-order follower (`s:update(target)` a tick: overshoot, anticipation); `juice.squash(obj, 0.3)` sets `obj.sx, obj.sy` squeezed and springing back |
| `"particles"` | sparks, smoke, dust, confetti, embers, fire: `fx = particles.new()`, `fx:burst(x, y, n, {speed, angle, spread, gravity, wind, drag, life, size, size_end, colours, shape})`, `fx:update()`, `fx:draw()`. `shape` is `"circle"`, `"square"`, `"pixel"`, `"glow"` (a soft light added to what is under it: a spark, a flame), `"shadow"` (the same taken away: smoke) or `"sprite"` (`image`, `frame`, `blend` = `"add"`, `"sub"`, `"quarter"`, `"alpha"`, `fade`). `e = fx:emit({x, y, rate, ticks, follow, ox, oy, ...the same})` keeps making them (`rate` a tick, 0.25: one in four) until `e:stop()` or `ticks`; `e:move(x, y)`. Glows and shadows are lights: a group draws the 64 youngest in a frame, the 48 youngest scaled sprites (the drawing slots are 128 a frame for every light, gradient, quad and scaled picture) |
| `"rig"` | a character as pieces hung on each other, moved by keyframes (cut-out animation, as the Saturn's big 2D characters): `hero = rig.new({parts = {{id, image, pivot, parent, at, z}, ...}, anims = {walk = {len, loop, next, events, tracks = {head = {rot = {{0, 0}, {30, 5, "smooth"}}}}}}})`; tracks change `rot` (degrees, clockwise), `x`, `y`, `sx`, `sy` and `frame`; `hero:play("walk", {fade, restart, speed})` blends from the pose it was in, `hero:on("step", fn)` for events, `hero:update()`, `hero:draw(x, y, {flip, scale, light, lights, dither})` (each piece a `quad`), `hero:point("arm", 0, 18)` where a point of a piece is on the screen (a hand, a weapon's tip). Each piece uses one of the frame's 128 drawing slots |
| `"transition"` | the way from one screen to the next: `transition.go("iris", 0.8, {cx, cy, color, hold, on_mid = function() load_room() end, on_done})` closes, calls `on_mid` once with the screen covered, holds and opens; `transition.update()` each tick and `transition.draw()` last in `_draw`; `transition.active()`, `transition.covered()`. Kinds: `"fade"` (smooth, the dearest: a mixed full-screen box), `"wipe"` (`dir` = `"right"`, `"left"`, `"up"`, `"down"`), `"curtain"` (two halves closing; `dir = "vertical"`), `"blinds"` (`bars`, `dir`), `"iris"` (a circle closing on `cx`, `cy`), `"blocks"` (`size`: square blocks in the 4x4 pattern's order, the PlayStation's tile dissolve). `transition.draw_kind(kind, k, opts)` draws one still frame (k 0 to 1). `scene.go(scene, args, {fade = 0.4, transition = "iris", cx, cy})` uses one for the change |
| `"physics"` | things that fall, bounce, slide, tip over, roll, float and hit: `w = physics.world({gravity})`, `w:circle(x, y, r, {bounce, friction, static, mass, turns})`, `w:box(x, y, w, h, {...})`, `w:poly(x, y, {x0, y0, x1, y1, ...}, {...})` (a convex shape: rocks, ramps, hulls), `w:rope(a, b, length, {stick})`, `w:water(x, y, w, h, {lift, drag, flow_x, flow_y})` (it floats, slows down and drifts with the current: a river, a raft), `w:drive(body, angle [, px, py])` (a static polygon the game turns about a point, a flipper or a door: what it meets is hit by its moving surface), `w:step()`, `w:hits()`, `w:at(x, y)`, `w:corners(body)`, `w:remove(body)`. With `turns = true` a box tips over and a circle rolls; draw it with `img(id, b.x, b.y, {angle = b.angle})` (or `poly(w:corners(b))`). Each step is worked out in C (a world holds up to 256 bodies); bodies that do not turn move exactly as they did when the library was Lua |
| `"kit"` | a whole game from data and events, as the [editor](../README.md#without-code-the-editor) makes them: `kit.setup(data)` with levels (each a map of tiles and objects, played in order: `kit.next_level()`, `kit.goto_level(id)`; a `cover` before them, an `ending` after), objects and their kinds (`"platformer"`, `"topdown"`, `"grid"`, `"patrol"`, `"chase"`, `"shot"`, `"push"`, `"still"`); `kit.on("touch", "heroe", "moneda", function(este, otro) ... end)` and `"start"`, `"level"`, `"out"`, `"tick"`, `"press"`, `"hold"`, `"tile"`, `"every"`, `"tap"`; `kit.spawn`, `kit.destroy`, `kit.count_on(kind, tile)`, `kit.retry()`, `kit.music(id)` (each level and the cover may have their own), `kit.label(key, text, where [, style])` (`"shadow"`, `"wave"`, `"big"`, `"gradient"`), `kit.sound`, `kit.win`, `kit.lose`; conversations (`kit.say`, `kit.ask`, `"answer"`), the microphone (`"clap"`, `"blow"`), videos (`kit.video`, `"video_end"`); named animations (a kind's `anims = {idle = {frames = {0}}, walk = {frames = {1, 2, 3}, fps = 10}, hit = {frames = {4}, loop = false}}`, as `"anim"` names them: `fps` left out is the kind's own `animate` pause, `loop = false` stops on the last frame, `{first, last}` as before still works; a kind's `pivot = {x, y}` is the point it turns round when it looks the other way; with `idle_side`, `walk_side`, `idle_up`, `walk_up` for its side and back views and `act1`..`act6` for actions (the last frame stays while a conversation waits); `kit.play(o, "hit")`, `kit.play(o, "act1")`, `kit.face(o, other)`; they go on while a conversation waits); lives shown as hearts (`kit.set_lives`, `kit.add_lives`, `kit.lives()`, `"no_lives"`) and a countdown (`kit.countdown`, `kit.add_time`, `kit.time_left()`, `kit.stop_countdown`, `"time_up"`); `data.tile` (16 or 8), `data.style` (the colours of its texts, hearts and conversation box), `data.transition` (blinds between levels) and `data.words` (its own sentences, in the game's language); `kit.init()`, `kit.update()`, `kit.draw()` in the three callbacks; up to three pictures behind the map, repeated, each moving with the camera by its parallax (`backdrops`). All of it at the top of [lib/kit.lua](../lib/kit.lua) |
| `"keyboard"` | writing with the d-pad or a finger: `kb = keyboard.new({title, text, max, colours})`, `kb:update()` returns `"ok"` or `"cancel"` when done, `kb:draw()`, `kb.text` |
| `"story"` | conversations and stories that branch, written as plain text: [below](#stories) |
| `"pointer"` | a finger or stylus as the DS's games used it: `pointer.update()` in `_update` (a second call in the same tick does nothing), then `pointer.began` (it went down), `.tapped`, `.long` (30 ticks held still), `.released`, `.dragging`, `.dx`, `.dy`, `.flick` (`{dx, dy, dir}` on lift), `.stroke` (the points of the one going on), `.fingers` and `.pinch` (while two fingers are down: `{scale, angle, cx, cy, dx, dy}`, their distance and turn since the second landed, their middle and its move this tick; a stroke with two fingers is no tap and no flick) and `.last` (the one just lifted); `pointer.pressed(item)` (that `{x, y, w, h}` was tapped); `pointer.pick(items, x, y)` (the `{x, y, w, h}` nearest the touch, each hit as if at least 40 px); `pointer.simplify(points, eps)`; `pointer.recognize(points)` returns `"line"`, `"circle"`, `"triangle"`, `"square"` or `"zigzag"` and a 0..1 score (`nil` below 0.7). Digits as Brain Age took them: `pointer.written` is the strokes of a figure once the pen has rested 30 ticks (`WRITE_PAUSE`), and `pointer.digit(strokes)` reads 0..9 from them without turning (a 6 is not a 9), with a score (`nil` below 0.75; a 4 or a 5 may be two strokes). The numbers to tune are at its top: [lib/pointer.lua](../lib/pointer.lua) |
| `"widgets"` | buttons, sliders and scrolling lists that a finger and the d-pad both work, with one focus: `ui = widgets.new({colours, font})`, `ui:button({x, y, w, h, label, on})`, `ui:slider({x, y, w, h, min, max, step, value, on})`, `ui:list({x, y, w, h, items, row_h, on})`; `ui:update()` after `pointer.update()`, `ui:draw()`. A tap presses or picks, a slider follows the finger, a list scrolls as it is dragged; the d-pad moves the focus (up and down), A presses, left and right move a slider; the focus ring shows only after the d-pad was used. [lib/widgets.lua](../lib/widgets.lua) |
| `"input"` | the game's own actions, so code says `"jump"` and not `"b"`: `input.map({jump = {"b"}, fire = {"a", "c"}})`, `input.down`, `input.pressed(name, hold, every)`, `input.released`, `input.held`, `input.buffered(name, window)`; `input.dir()` (-1, 0 or 1 each, diagonals too; with left and right both held, the last pressed). A name that is not an action is a button |
| `"move"` | a platformer's bodies as Celeste moves them: `a = move.actor(x, y, w, h, {solid = fn(x, y, w, h), oneway = fn})` moves a whole pixel at a time against the level (`a:move_x(dx, on_hit)`, `a:move_y(dy, on_hit)`, the fractions kept; `a:on_ground()`); `s = move.solid(x, y, w, h)` is never inside an actor: `s:move(dx, dy)` carries the ones riding it and pushes the ones in its way (`s.on = false` lets them through); `pl = move.platformer(a, {speed, accel, jump, gravity, max_fall, coyote = 6, buffer = 6, apex = 0.5, corner = 4, cut = 0.4})` then `pl:update(dir, jump_pressed, jump_held)` each tick: coyote time, a jump buffered before landing, a short jump when the button is let go, half gravity at the apex, a head nudged round a block's corner, one-way platforms; `pl.state` (`"ground"`, `"jump"`, `"fall"`), `pl.jumped`, `pl.landed` for a tick |
| `"brain"` | what a creature does next, by scores (utility AI): `b = brain.new({flee = {score = fn(e), enter, update, exit}, attack = {score = 0.8, curve = "quad"}, ...}, {every = 6, stick = 0.1})`, `b:update(e)` each tick (it thinks every `every` ticks, keeps its action unless another beats it by `stick`, runs enter/update/exit), `b.current`, `b.since`, `b:think(e)`, `b:force(name, e)` |
| `"rng"` | random numbers a game can count on, a stream per thing (Squirrel noise): `r = rng.new(seed)`, `r:int(a, b)`, `r:float([a, b])`, `r:chance(p)`, `r:pick(t)`, `r:shuffle(t)`, `r:sign()`, `r:gauss()`; `rng.hash(i [, seed])` the i-th number of a seed without a stream; `rng.fbm(x, y [, octaves, lacunarity, gain])` noise stacked |
| `"gen"` | levels made by code, as maps `{w, h, get, set, count, find, is_solid}` of 1 (solid) and 0: `gen.caves(w, h, {fill, steps, seed})`, `gen.bsp(w, h, {min, seed})` (rooms joined by corridors, `m.rooms`), `gen.walk(w, h, {steps, seed})`, `gen.spelunky(cols, rows, {seed})` (a grid of room kinds with a walkable path top to bottom), `gen.connected(m)` keeps the biggest open region, `gen.fill_border(m)` |
| `"chain"` | creatures made of a line of joints that follow a head: `w = chain.new(n, len, {bend, x, y})`, `w:follow(x, y)`, `w.points[i].x, .y, .angle`; legs that step: `leg = chain.leg({hip = w.points[3], len, side, stride, lift})`, `leg:update()`, `leg.foot`, `leg.knee`; the solvers: `chain.fabrik(points, lens, tx, ty [, iters])`, `ex, ey = chain.two_bone(ax, ay, l1, l2, tx, ty [, flip])` |
| `"steer"` | Reynolds's steering and boids: `steer.apply(e, steer.seek(e, tx, ty))` (any table with `x, y, vx, vy, max_speed, max_force`), `flee`, `arrive(e, tx, ty, slow)`, `wander(e)`, `pursue(e, other)`, `separate(e, others, radius)`, `flock(e, others, {align, cohere, separate, radius})`, `combine({fx, fy, w}, ...)`; `h = steer.hash(size)`, `h:rebuild(list)`, `h:near(e, radius)` for crowds |
| `"stack"` | a thing seen from above as a stack of slices (sprite stacking, as NIUM): `car = stack.new("CAR", {slices = 8, w = 16, h = 24, spacing = 1, scale = 2, steps = 32})` takes a picture whose frames are the object's horizontal slices, bottom first; `car:draw(x, y, angle)` draws them one over the other, each a little higher, all turned by `angle`; each angle (snapped to one of `steps`) is made once on a canvas and kept, so a still object costs one `img` a frame; `stack.clear()` frees the canvases |
| `"water"` | a surface that ripples (Hoffman's springs): `pond = water.new({x, y, w, springs = 48, colour, deep, alpha, depth})`, `pond:splash(x, speed)` when something falls in, `pond:update()` a tick, `pond:draw()` (polygons from the surface down), `pond:height(x)` to float things |
| `"road"` | a road going away into the distance, as OutRun drew it, on an affine layer whose map is the road's cross-section (grass, kerb, road, line) in two rows, one per band: `r = road.new({layer, row, map_w, horizon, width, camera_h, fov, segment, stripe_pal = {{entry, colour_a, colour_b}, ...}})`, `r:add(length, curve)` for each segment, `r:update(speed)`, `r:draw(steer)` in `_draw` (a `line_affine` and the bands' `line_pal` a line), `x, y, scale, visible = r:project(z_ahead, x_on_road)` for what stands on it |
| `"autotile"` | the right tile at every edge and corner, from the neighbours, for levels made by code or dug into: `autotile.blob(layer, w, h, is_solid, tile_of)` (47 tiles by the 8-neighbour mask, `tile_of(mask)` or a table; `autotile.blob_index(mask)` 0..46 in cr31's order) or `autotile.dual(layer, w, h, is_solid, tiles)` (the dual grid: 16 tiles, `tiles[NW + NE * 2 + SW * 4 + SE * 8]`, drawn half a tile off the data); `autotile.fix(..., tx, ty [, dual])` after one cell changes; `autotile.mask(is_solid, w, h, tx, ty)` |
| `"rollback"` | two consoles playing one game over `link` without waiting for each other, as GGPO does it: each runs ahead guessing the other keeps pressing what it pressed last, and when the truth arrives and differs the game is put back to that tick's saved state and run again from there within the same tick. The game gives `save()` (its state as a new table), `load(s)` and `run(inputs, tick)` (one deterministic tick): `rb = rollback.new({step = 3, delay = 1, history = 12, save, load, run})`, `rb:start(link.peers())`, `rb:update(rollback.buttons())` each tick; `rb.rollbacks`, `rb.rolled` (ticks run again the last time), `rb.tick`. The transport is lockstep's (frames of `step` ticks, the last `history` repeated) |
| `"lockstep"` | two or more consoles playing one game in step over `link`, as the fighting games did before rollback: only buttons are sent, every console runs the same game with the same inputs. `ls = lockstep.new({step = 3, delay = 2, history = 4})`, `ls:start(link.peers())` (the players in id order, the same on every console), then in `_update` `inputs = ls:update(lockstep.buttons())`: `nil` while a player's buttons are missing (the game waits), else `inputs[id]` the bits of each player for this tick, `delay` frames of `step` ticks after they were pressed (100 ms at the defaults, felt by all alike); `lockstep.down(bits, "a")`; `ls.players`, `ls.me`, `ls.tick`, `ls.waiting`, `ls.lag`. Each message carries the last `history` frames again, so a lost one costs nothing; a console waiting for the other samples no further than a frame past the one it is at and sends its last frames again every few ticks, so one that starts later (a menu on each side, pressed seconds apart) gets them and catches up |
| `"lang"` | the game's words in the console's language from one CSV of the game (`strings.csv`: `key,es,ca,en`): `lang.load()` (the language of `settings()`, or `lang.load("ca")`), `lang.tr("hello", {name = n})` fills `{name}` (a text missing in a language falls back to the first column; a missing key is the key), `lang.plural("coins", n)` (`coins` for one, `coins_n` for several), `lang.set(code)`, `lang.code`. `tools/strings_check.py GAME` says which letters the fonts lack and which keys a language misses, and `--pseudo` writes longer, accented texts to find what overflows |
| `"anim"` | animations with names, like Aseprite's tags: `a = anim.new({run = {frames = {1, 2, 3, 4}, fps = 10}, shoot = {frames = {5, 6}, ms = {60, 120}, loop = false, next = "idle", events = {[2] = "fire"}}, bob = {frames = {0, 1, 2}, mode = "pingpong"}})`, `a:play("run")` (playing it already: it goes on), `a:update()` each tick, `a.frame` to draw, `a:on("fire", fn)` on that frame, `a.done` when one that does not loop is over |
| `"cam"` | a camera that follows: `c = cam.new({bounds = {0, 0, 3840, 320}, deadzone = {80, 60}, lerp = 0.15, lead = 40, forward_only})`, `c:follow(hero)`, `c:update()` each tick, `c:apply()` in `_draw` (with juice's shake), `c:snap()`, `c:look(x, y)` for a while, `c:visible(x, y, w, h)`. `c.x, c.y` is the top-left corner seen. Zoom and turn, for a scene drawn with rect, img, quad and light: `c:draw(function() ... end)` (or `c:begin()` ... `c:finish()`), `c:zoom_to(2)`, `c:rotate_to(15)`, `c:zoom_now`, `c:rotate_now`, `c:punch(0.08, 12)` (a hit zooms in and eases back); the scene goes through a canvas and a quad, so it is for a moment, not a level (80 ms a frame at the whole screen, 31 with `cam.new({w = 240, h = 160})`; not zoomed it is free) |
| `"scene"` | a game as scenes on a stack (the title, a level, the pause): tables with `enter(args)`, `leave()`, `pause()`, `resume(result)`, `update()`, `draw()`; `scene.go(s, args, {fade = 0.4})` (the scenes leaving lose their sprites and juice's tweens, timers and scripts; the picture's effects stay: with `{clean = true}`, or `scene.clean()` by hand, the fade, blend, windows and their per-line spans, mosaic, per-line tables, hidden layers, synthesised voices and the LED are put back too), `scene.push(s, args)`, `scene.pop(result)`, `scene.top()`, `scene.depth()`; a scene with `overlay = true` is drawn over the one under it, which waits. `scene.update()` and `scene.draw()` in the callbacks |
| `"rooms"` | a game as places you walk between: `rooms.define({id, w, h, layers, front, solids, spawns, exits, things, variant, variants, assets, enter, leave, update})`, `rooms.go("bar", "door")` (the curtain closes, the next room's pictures and sounds are read behind it with `preload`, it opens), `rooms.update()`, `rooms.draw(function() draw_player() end, player.y + player.h)`; `rooms.move(player, dx, dy)` (walls and the room's edge, one axis at a time), `rooms.exit_at(e)` and `rooms.take(exit)`, `rooms.thing_near(e, reach)`, `rooms.remove(id)`, `rooms.flag(room, key [, value])`, `rooms.visits(room)`; a room scrolls with a camera that follows `rooms.player`, wider than the screen if it says so; `variant()` picks a look (a crisis) and `rooms.refresh()` applies it; `store("rooms", rooms.save())` and `rooms.load(...)` keep what you did in each. `occluders` (the pieces of a pre-rendered background that stand in front of what is behind them: a counter, a stool, a pillar), each with a depth `z` and ordered among the things and the player by his feet's line, so he walks behind the counter and in front of the stool; `uv run tools/depthcut.py BG.png MAP.png GAME BG_BAR --z FF0000=280,...` cuts them from a map painted in flat colours, one for each piece. All of it at the top of [lib/rooms.lua](../lib/rooms.lua) |
| `"views"` | project one actor's ground position through several staged cameras: `sx, sy, scale, order = views.project({kind = "side" or "fixed" or "rear", ...}, x, z, height)`. Side maps route distance `z` across the screen; fixed uses `basis = {xx, zx, xy, zy}` and optional depth scaling; rear projects distance from a camera at `cz`, returning `nil` behind it. For many actors in a rear view, create `project = views.projector(camera)` once and call `project(x, z, height)`: lens settings are validated and captured once, while `camera.cx` and `camera.cz` remain live for following. `order` sorts far to near. `views.pick({{id, x0, x1, z0, z1}, ...}, x, z, fallback)` chooses a half-open camera zone; it does not change the actor's world position. See [examples/psx_views](../examples/psx_views), which cuts from lateral to fixed to rear with `transition` and keeps state. |
| `"inventory"` | what a character carries: `inv = inventory.new({slots = 3, items = {llave = {name, icon}}, uses = {llave = {botellero = function() return true end}}})`, `inv:add(id)` (false and `"full"`, `"have"` or `"unknown"`), `inv:remove`, `inv:has`, `inv:select(i)`, `inv:next()`, `inv:use_on(target)`, `inv:draw(x, y)` (a strip of slots), `inv:save()` and `inv:load(t)` |
| `"hud"` | what a screen keeps in a corner: `m = hud.meter({x, y, w, h, label, segments, color, danger, danger_color})` that eases to `m:set(0.35)`, `hud.hearts(x, y, n, max)`, `hud.counter(x, y, icon, n)`, `hud.portrait(x, y, pic)`, `hud.objective(x, y, w, title, lines, {done})`, `hud.toast("text")` with `hud.update()` and `hud.draw_toasts(x, y)`; its sizes follow the font |
| `"lights"` | the lamps of a scene as a list: `lights.ambient(0.35, 0.4, 0.55)` (the room's own light), `lamp = lights.add({x, y, r = 80, color = 0xFFC060, flicker = 0.15})`, `torch = lights.add({follow = player, r = 110, cone = {angle = 0, width = 60}, aim = true})`, `lights.update()`, `img("BG", 0, 0, {mul = lights.mul()})` and `lights.draw()`; `lamp.on = false` |
| `"light"` | a palette lit by a lamp: pixel art drawn with a palette whose entries mean surfaces (the "normal map palettes" of the GBA/DS era) turns towards a torch that moves: `lamp = light.new({bank = 2, obj = true, base = {[1] = 0xD04030, ...}, normals = {[1] = {0, -1, 0.3}, ...}, ambient = 0.25})`, `lamp:set(dx, dy, dz)` (the lamp's direction from the thing; `nil`: flat light) writes the bank's entries; `light.shade(normal, dir, ambient)` is one surface's lighting, 0..1 |
| `"voice"` | a character's voice from one short sound, as Animal Crossing's villagers and Undertale's blips: `v = voice.new({sound = "BLIP", pitch = 0.8, spread = 2, every = 2, gain = 0.5})`, `v:say(letter)` each letter typed (a blip every `every` letters, its pitch from the letter, vowels higher, `spread` semitones around the voice's own; spaces and marks are silent), `v:reset()` at a new line, `v:blip()` a function for `rich`'s `blip` option (and so a story's) |
| `"rich"` | text with marks, for any text and for [stories](#stories): `rich.draw(str, x, y, opts)` at once, or `r = rich.new(str, opts)` typed out (`r:update()`, `r:draw(x, y)`, `r:skip()`, `r.done`); options `font`, `color`, `width` (wraps), `speed`, `line`, `outline`, `shadow`, `blip`. `rich.plain(str)` without the marks |
| `"slices"` | a wide picture kept as columns so only the ones on screen are in memory: cut it with `uv run tools/slice_pic.py art/far.png games/g FAR --lua games/g/far_slices.lua`, then `slices.draw(require("far_slices"), x, y [, {flip_x, ...img options}])` draws only the columns that touch the screen and returns how many; `slices.preload(def, x)` reads the ones about to come in |
| `"sheets"` | a strip of more than 64 frames, which `png2asset.py` writes in pieces (`HERO`, `HERO_2`, `HERO_3`, 64 frames each): `sheets.spr(slot, "HERO", 130, x, y, flags)`, `sheets.img("SPR_HERO", x, y, 130, {opts})`, `sheets.piece(id, frame)` gives the piece and its frame |

`views.draw3d(camera, items)` draws textured 3D quads and actors through a `side`, `fixed` or `rear` camera. A face is `{id = "WALL", corners = {{x=..., z=..., h=..., u=..., v=...}, ...}, opts = {light = ...}}`: four corners in picture order, UV in texels. Optional `pose = {x, z, h, angle, scale}` places local corners in the world; angle turns around the height axis in degrees and scale must be positive. `cull = true` skips faces whose projected corners run counterclockwise on the screen; use convex faces with consistent winding. An actor is `{x=..., z=..., h=..., draw=function(sx, sy, scale) ... end}`; its callback can draw a sprite at the projected position. Items are sorted far to near with stable ties, so actors can pass behind and in front of faces. A rear view clips faces at `camera.cz + camera.near` (default near `0.01`), interpolating position and UV; faces crossing that plane become triangles. Actors behind that plane are hidden. `snap = true` on the camera rounds every projected point to a whole pixel, as a PlayStation did: a turning model's vertices then wobble, which is much of that console's look (off by default, the points keep their fractions). Clipped faces do not accept per-corner `lights` yet; a uniform `light` works. Use small pictures and a modest number of faces: rasterized area, not polygon count, dominates Cirera's frame time.

### Stories

Who says what, the choices the player makes, what they change and what comes back later: written in a text file
of the game, in any language (one file each: `story/es.txt`, `story/ca.txt`), not in code.

```
// story/es.txt
[var confianza = 0]

== inicio
Abuela: Buenas noches, {nombre}.
El suelo cruje bajo los pies.
-> preguntas

== preguntas
[if confianza >= 2] Abuela (seria): Ya sabes demasiado.
* Preguntar por la Raíz -> raiz
* Preguntar por el pueblo
    Abuela: Este pueblo está encima de otro.
    [do confianza = confianza + 1]
    -> preguntas
+ [if llave] Abrir la trampilla -> trampilla
+ Irse -> END

== raiz
[do sfx("RAIZ")]
Abuela: La Raíz guarda lo que el pueblo olvida.
-> preguntas
```

| Line | Is |
|---|---|
| `== name` | a knot: a place in the story to go to. Running into the next knot ends the story |
| `Name: text` | a line said, with who says it (30 letters at most before the `: `); `Name (mood): text` also gives a mood, for a portrait |
| `text` | a line nobody says |
| `{expr}` | inside a text: the value of a variable or expression |
| `* text -> knot` | a choice, once: taken, it is not offered again. `+` is offered always. The lines indented under it happen when it is taken; then the story goes on after the choices, or to `knot` |
| `-> knot`, `-> END` | go to that knot; the end |
| `[if expr] line` | that line (or choice) only when `expr` is true |
| `[do code]` | Lua: the story's variables are its globals, and the game's functions are there too (`sfx`, `music`, its own) |
| `[var name = expr]` | a variable and its first value, unless a saved story has it already |
| `{a\|b\|c}`, `{&a\|b}`, `{~a\|b}`, `{!a\|b}` | inside a text, a sequence: the next each time the line is read, then the last for ever; `&` round and round; `~` one at random; `!` once each, then nothing. What has been shown is kept with the story's variables (`seq`) |
| `visits("knot")` | in an expression: how many times the story has entered that knot (`seen.knot` is the same) |
| `// text` | a comment |

Inside any line, marks: `[color=FF8040]` or `[c=FF8040]` ... `[/c]` a colour, `[wave]` ... `[/wave]` letters that
float, `[shake]` ... `[/shake]` letters that tremble (`[wave=3]` how much), `[wait=30]` a pause of 30 ticks while the
letters come, `[speed=0.5]` letters a tick from there, `[sfx=ID]` a sound when the letters reach it, `[img=ID]` a
small picture among the words, `[[` a `[`. They are [rich](#libraries-built-in)'s, which a game can use for any text.

```lua
local story = require("story")
local lang = stored("lang", "es")
s = story.new(file("story/" .. lang .. ".txt"), {name = lang .. ".txt", vars = stored("story")})
s:go("inicio")                               -- in _update: s:update() returns "done" at the end; in _draw: s:draw()
store("story", s.vars)                       -- the story's variables, knots seen and choices taken
```

`s:update()` and `s:draw()` are a box at the foot of the screen: the letters come one by one, A (or a tap) shows the
line whole and then goes on, up and down pick a choice, A or a tap on it takes it. `story.new`'s `ui` option changes
it: `font`, `color`, `name_color`, `choice_color`, `pick_color`, `speed` (letters a tick), `x`, `y`, `w`, `h`, `pad`,
`box` and `border` (colours), `frame` (a picture of the game, as `frame()` draws it), `panel = true` (the theme's),
`portraits` (`{Abuela = "FACE_ABUELA", Abuela_seria = "FACE_ABUELA_2"}`, drawn standing on the box's left) and
`blip` (a sound every `blip_every` letters). A game that draws its own: `s:line()` is `{who, mood, text}` or nil,
`s:choices()` the texts offered or nil, `s:next()`, `s:choose(i)`, `s:running()`. `s.vars.seen.raiz` counts the
visits to a knot. A mistake in the text stops the game with its file and line.

## Saving

`store(key, value)` keeps a value in the game's saves folder: a number, string, boolean, or a table of them (a list,
or string keys), nested; `store(key, nil)` forgets it. `stored(key [, default])` reads it back. For high scores,
options and progress (`store("save", {room = 3, items = {"key", "map"}})`), up to 64 KB in all. On a computer each
`store` writes the file at once; on the console the value is kept at once and the file written a second after the
last `store` (several in a row are one write), which costs the picture about a fifth of a second: call it at moments
like a level's end, not every frame.

## Other

`log(...)` (and `print`) writes to the log. `quit()` goes back to the console's game list (holding MENU for two
seconds does too). `perf()` returns the milliseconds the last `_update`, `_draw` and picture took, and the script's
memory in KB, to see where a frame goes. `perf(true)` shows a meter over the game: the frames a second, the last 60
frames as bars (red past the 16.7 ms of 60 fps), those times and the memory of the script and the pictures;
`perf(false)` hides it; two more lines say how full the frame's lists are (`commands 120/2048`, `slots 40/128`: the 128 are
shared by every quad, light, gradient, warp and scaled picture) and which kinds of drawing cost most in the strips (CPU
milliseconds, both cores added). `perf("ops")` gives the same to the game: `ops, commands, slots = perf("ops")`, `ops.quad.n` and
`ops.quad.ms` for each kind (`text`, `rect`, `shade`, `panel`, `plate`, `box`, `img`, `frame`, `line`, `circ`, `poly`, `points`, `quad`,
`grad`, `light`, `warp`, `linetint`) of the last whole frame; the first call starts measuring, so it answers after a frame has gone by.
Measuring times each command in each strip, so it costs a little while it is on. `perf("lua")` says where the Lua time goes, by
function: `rows, ms = perf("lua")` gives `rows[i].name` (`"reach (dungeon.lua:93)"`; the engine's calls by their names,
`_update`, `_draw`), `rows[i].self` (milliseconds with that function on top: its own code, and the C calls it made, as
`mset` or a path) and `rows[i].total` (with it anywhere on the stack), dearest own time first, and `ms`, all the Lua time
counted since the first call (that one starts it and answers empty). It samples every thousand instructions, which slows
the script by about a third while it is on; `perf("lua", false)` stops it and forgets. With it on, the meter has a line
for the two dearest. `pinyol_headless --profile out.folded` profiles a whole test run: the dearest functions on the
terminal, and every stack in `out.folded` for a flame graph (drop it on [speedscope.app](https://www.speedscope.app) or
give it to `flamegraph.pl`). MENU and C together show or hide the meter on the console, F3 in the simulator. `require("name")`
loads `name.lua` from the game folder (`"ui.menu"` is `ui/menu.lua`). `file("story/es.txt")` returns the text of any
file of the game (1 MB at most), or nil: stories, levels written by hand, a metro's stations as CSV.

## Limits (the sandbox)

A game downloaded from the community cannot harm the console:

- Lua 5.4 with 32-bit integers and floats on every platform (the same results everywhere).
- 4 MB of memory for the script (`"lua_memory_kb"` in game.json, up to 6144); past it, "not enough memory".
- The garbage collector runs in Lua's generational mode: tables made and dropped in the same frame (a list of sprites
  to sort, a vector) are collected young and cheaply, not left to pile up into a pause that costs a frame.
- A call (`_init`, `_update`, `_draw`) that makes 20 million jumps, loop turns or calls without returning is stopped: an
  endless loop becomes an error, not a frozen console.
- No `io`, `os`, `debug` or `package`; `load` takes source text only, never bytecode; `require` only reads `.lua`
  files inside the game folder.
- `math.random` starts from the same seed every run, so a game and its tests repeat exactly; `math.randomseed(n)` sets another. A game that wants
  a new world each time seeds it with `ticks()` when the player first presses a button (a person never presses on the same tick twice, a
  test always does: `examples/sima`), or with `clock().days` for one world a day for everyone. `math.randomseed()` with nothing seeds
  from the machine's time, which the tests cannot repeat.

## Testing

A test script plays the game with real input (see `tests/plataformas.script`):

```
new                              # start (runs _init)
press A                          # a button for one tick; hold RIGHT 30 holds it for 30
tap 240 160                      # a finger down and up at that screen pixel (480x320)
touch 240 160 60                 # a finger held there 60 ticks, then lifted (a long press)
drag 40 200 440 200 30           # a finger along a line in 30 ticks (a knob turned, a fader, steps painted)
swipe 400 100 400 20             # the same, quick (8 ticks)
pinch 240 160 100 200 20         # two fingers round (240, 160), 100 apart going to 200 (a spread), in 20 ticks
drag2 100 100 200 100 120 0 30   # two fingers moved together by (120, 0) in 30 ticks
tick 20                          # let 20 ticks pass
expect_lua state == "play"       # a Lua expression that must be true
lua P.x = 100                    # run Lua in the game (set up a situation)
expect_lua_error spin()          # code that must fail
expect_ok                        # the game has not stopped on an error (a script also fails by itself on the tick it does)
shot name                        # save the screen to the saves folder (name.ppm)
mic 0.5 440                      # the microphone hears a tone that loud (no Hz: noise; mic 0: silence; mic none: no microphone)
battery 0.2 charging             # battery() says so (battery none: no battery; battery real: the platform's)
settings speed 50                # the console's settings (speed 100/75/50, flash less/normal, colour protan/deutan/tritan/normal, swap_ab, buttons BAC, hold toggle/press, lang, volume)
expect_menu open                 # the console's menu is up (or closed): press MENU taps it open
allow_crash                      # the game may stop on an error from here on: the ticks do not fail for it (its crash screen is up)
expect_crashed                   # and it has
in 30 RIGHT+A 240 160            # exactly that input for 30 ticks: those buttons (- for none) and a finger at that point (up to five points)
hotswap ui/menu.lua ui.menu      # the file run again over the module the game required, its state kept (what the simulator does when that file is saved)
expect_led ff0000                # the LED is that colour (expect_led off: the console's own)
tilt 0.5 -0.2 0.8                # tilt() reads so (tilt none: no sensor; tilt real: the platform's)
expect_rumble 120                # the game asked for a vibration that long since the last look (0: none)
```

`#` after a space starts a comment in these scripts, so avoid Lua's `#` length operator there.

**A file saved while the game runs.** The simulator restarts the game when one of its files is saved, except a `.lua`
the game has `require`d (not `main.lua`): that file is run again and what it returns is copied over the table the
game already holds (as rxi's lume.hotswap does), so a number tuned or a function fixed shows at once with the game
where it was. A file that fails to load leaves the module as it was and says so in the log.

**A play recorded as a script.** `pinyol_sim --game DIR --record out.script` (or F8 while playing, again to stop:
`saves/partida-N.script`) writes every tick's buttons and fingers as `in` lines, from the game's own first tick. Played
back with `pinyol_headless --game DIR --fresh --script out.script` it gives the same frames (a game is deterministic given
its input: the same seed, the same ticks), so one file is a bug report, a regression test and a replay. `--crc` on both
runs shows it. What a script changes with `lua` is not input and is not recorded.

**Flashing that can hurt.** `pinyol_headless ... --check-flashes` watches every frame for more than three flashes a
second over more than a quarter of the screen (WCAG 2.3.1: a flash is a change of 10 % or more in relative luminance
each way, the darker side under 80 %), and ends with code 4 and the frame it found it around. The Library's robot plays
every game with it. The simulator also takes **F6** a screenshot (`saves/pantalla-N.png`), **F7** the game's cover from
the screen (`cover.rgb565`, as `tools/cover.py` makes it), **F9** the last eight seconds as a GIF (`saves/clip-N.gif`).

The headless player runs `_draw` only for a `shot`: what a game works out while drawing (the sprites' order, say) is
there to check after one, not after `tick`.

Run it with `pinyol_headless --game DIR --fresh --script FILE --check-strips`, or name it `tests/<game>.script` next
to `examples/<game>` and `ctest` runs it.

## Making it on the console

`pinyol_sim` restarts a game each time one of its files is saved. To see it on the console the same way, keep it on the
cable while you work:

```
uv run --with pyserial tools/watch_game.py games/mygame
```

It sends the game whole once; then each file you save goes into the game on the console, which starts again with it
a moment later, and what the game logs (`log`, `print`) and its errors show in the terminal.

## Sharing a game

```
python3 tools/pack_game.py games/mygame -o dist/      # -> dist/mygame.zip
```

The zip holds the folder `mygame/` with what the console reads (add `--sources` to include `art/` and `art.py`).
Unzipped into the card's `games/` folder it shows in the console's list. The web player (`player.html`, built with
Emscripten, see the README) plays it in a browser: `player.html?game=dist/mygame.zip`, or drop the zip on the page.
Saves made in the browser stay in that browser.
