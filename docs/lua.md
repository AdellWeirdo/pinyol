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
function _init() end      -- once, when the game starts (and again on "new game" in tests)
function _update() end    -- 60 times a second: input, movement, rules
function _draw() end      -- before each frame: scroll, sprites, text
```

The picture processor keeps its state between frames: a sprite stays where you put it until you move or remove
it. Text and shapes (the overlay) are drawn again every frame: call them in `_draw()`.

A Lua error stops the game and shows the message on screen; `pinyol_headless --validate` reports it too.

## Coordinates and colours

- The world is 240×160 (`W`, `H`). Backgrounds and sprites use world pixels.
- The overlay (text, panels) uses screen pixels, 480×320 (`SCREEN_W`, `SCREEN_H`): world pixel x is screen 2x.
- Colours are `0xRRGGBB` numbers; `rgb(r, g, b)` makes one. They are stored as RGB565 (5-6-5 bits).
- Numbers can have fractions: positions are rounded down when drawn.

## Input

| Call | Returns |
|---|---|
| `btn(name)` | true while held. Names: `"up" "down" "left" "right" "a" "b" "c" "start" "menu"` |
| `btnp(name)` | true on the tick it was pressed. `btnp(name, hold, every)` also repeats while held: again after `hold` ticks, then every `every` ticks (a menu that scrolls on its own) |
| `btnr(name)` | true on the tick it was let go (a charged shot fires on release) |
| `btnt(name)` | ticks it has been held, 0 when it is not (a long press, how charged) |
| `btnb(name, window)` | true if it was pressed in the last `window` ticks (6 if left out) and not used yet; true once, then used. A jump pressed just before landing still jumps |
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
| `show(layers)` | which of `BG0`-`BG3` and `OBJ` are drawn (all at the start): hide a layer without losing its setup, `show(ALL & ~BG1)` |

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
| `img(id, x, y, {frame, scale, scale_x, scale_y, flip_x, flip_y, angle, pal, tint, alpha, add})` | the same turned (degrees, about its centre), scaled by any amount (negative flips) or flipped; `(x, y)` is where its top-left corner would be unturned. A packed picture (below) can also be drawn with another one's colours, `pal = "SPR_RAN_B"` (a second player, an enemy's stronger kind), or all of one colour, `tint = 0xFFFFFF` (the flash of a hit, a shadow); not turned; `alpha = 0.5` mixes it with what is under it (a ghost, a moonbeam, afterimages), `add = true` adds its light (a glow, a fireball), as the 32-bit consoles did; both with any of the rest, turned or not |
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
| `imgsize(picture)` | its width, height and frames, or `nil` |

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

It fits the picture inside the size given (240×160 by default: drawn at scale 2 it fills the screen), gives the
whole clip one palette of up to 256 colours (`--colours`, `--dither` for smoother gradients in a bigger file) and
keeps each frame as what changed since the one before, with a whole frame every two seconds (`--key N` frames).
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
| `link.peers()` | the ids of the consoles playing this game nearby (heard in the last 3 seconds), smallest first: every console sees the same order, so they can agree who is player 1 or who sits next to whom |
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
| `sfx(id [, gain [, {pitch, loop}]])` | plays `audio/<id>.wav` (or a sound made with `sound`) once, or looping; `pitch` 1 as recorded, 2 an octave up, 0.5 down. Returns a handle |
| `sfx_set(handle, {gain, pitch})` | changes a sound while it plays: an engine that follows the speed, a theremin |
| `sfx_stop(handle)`, `sfx_on(handle)` | stops it; is it still playing? |
| `sound(id, recipe [, seed])` | makes a sound from a recipe: `"coin"`, `"laser"`, `"explosion"`, `"powerup"`, `"hit"`, `"jump"`, `"blip"` or `"random"`; each seed gives another. Returns its numbers |
| `sound(id, {numbers})` | makes a sound from its numbers (below), played with `sfx(id)`. Returns them, completed |
| `music(id)` / `music()` | loops `audio/<id>.mod` (a tracker module) or else `audio/<id>.wav`; no id stops it |
| `music_layer(stem, gain [, fade_ms])` | a WAV's channels are layers (drums, bass, melody... up to 3): each comes in or goes out, so the music follows the game |
| `music_time()` | seconds into the song `music()` started, as the player hears it now, going on across its loops; `nil` when none plays. For notes on the beat |
| `tone(voice, pitch [, options])` | plays a synthesised note on voice 0-3, replacing what it played |
| `tone(voice)` | lets the voice's note go (it fades with its release) |
| `note(name)` | the frequency of a note: `note("A4")` is 440, also `"C#3"`, `"Eb5"` |

Recordings are not the only way: like the GBA's sound channels, four voices make notes from waveforms, for music
and effects written in Lua. `pitch` is a frequency in Hz or a note name. The options, all optional:

| Option | Default | |
|---|---|---|
| `wave` | `"square"` | `"square"`, `"triangle"`, `"saw"`, `"sine"` or `"noise"` |
| `vol` | 0.5 | 0 to 1 |
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
| `wave` | `"square"` | `"square"`, `"triangle"`, `"saw"`, `"sine"` or `"noise"` |
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

A sound that stops dead (`decay = 0`) is meant to loop; one that decays fades its last moment so it never clicks.
Making a sound takes a moment (a long one, some hundredths of a second on the console): make them in `_init` or
between levels, not every frame. A game's made sounds share 1 MB (about 24 seconds).

## The microphone

The console hears: blowing on a candle, singing a note that opens a door, a clap on the beat, a cat's miaow made by
the player. The browser asks the player first; the simulator uses the computer's microphone.

| Call | Does |
|---|---|
| `mic()` | `level, pitch, hit, recording`, or `nil` where there is no microphone (or the player said no). The first call starts listening |
| `mic(false)` | stops listening |
| `mic_record(id, seconds)` | what it hears for up to 10 seconds becomes the sound `id`, played with `sfx(id)` like any other; `true` if it started |
| `mic_record()` | ends the recording sooner |

- `level` goes from 0 (silence) to 1 (a shout close to the console), worked out every tick.
- `pitch` is the note heard in Hz (a voice, a whistle, a recorder: 70 to 1000 Hz), or 0 when there is no clear one
  (noise, a breath, silence). `note("A4")` gives the Hz of a note to compare with.
- `hit` is true on the one tick a sudden sound starts: a clap, a knock on the table, a shout.
- `recording` is true while `mic_record` is still listening.

```lua
local level, pitch, hit = mic()
if not level then                         -- no microphone: a button does it instead
  blowing = btn("a")
else
  blowing = level > 0.5 and pitch == 0    -- loud and without a note: a breath
  singing = math.abs(pitch - note("C5")) < 15
  if hit then clap() end
end
```

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

## Libraries built in

Lua code every game can `require`, so a game does not start from nothing. They come inside the engine (the
console, the simulator and the browser have them); a game with a file of the same name uses its own instead, so a
library can be copied into a game and changed. Each file in `lib/` says how to use it at its top.

| `require` | For |
|---|---|
| `"juice"` | what makes a game feel alive: `juice.tween(obj, {x = 100}, 0.5, "out_back")` moves fields with an ease (`linear`, `in_quad`, `out_quad`, `in_out_quad`, `in_cubic`, `out_cubic`, `in_out_cubic`, `in_back`, `out_back`, `out_elastic`, `out_bounce`, `in_bounce`), and chains: `:delay(s)`, `:loops(n)` (-1 for ever), `:yoyo()`, `:on_done(fn)`, `:after(obj, to, secs, ease)` (the next one). Time: `juice.after(secs, fn)`, `juice.every(secs, fn, times)`, `juice.script(fn)` (a function that waits: `juice.wait(secs)`, `juice.wait_until(test)`, `juice.wait_for(tween)`), `juice.cancel(handle or obj)`. `juice.shake(px)`, `juice.freeze(ticks)`, `juice.flash(colour, ticks)`; `juice.update()` in `_update` (true while frozen), `camera(juice.offset())` and `juice.draw()` in `_draw` |
| `"particles"` | sparks, smoke, dust, confetti: `fx = particles.new()`, `fx:burst(x, y, n, {speed, angle, spread, gravity, drag, life, size, colours, shape})`, `fx:update()`, `fx:draw()` |
| `"physics"` | things that fall, bounce, slide, tip over, roll, float and hit: `w = physics.world({gravity})`, `w:circle(x, y, r, {bounce, friction, static, mass, turns})`, `w:box(x, y, w, h, {...})`, `w:poly(x, y, {x0, y0, x1, y1, ...}, {...})` (a convex shape: rocks, ramps, hulls), `w:rope(a, b, length, {stick})`, `w:water(x, y, w, h, {lift, drag, flow_x, flow_y})` (it floats, slows down and drifts with the current: a river, a raft), `w:step()`, `w:hits()`, `w:at(x, y)`, `w:corners(body)`, `w:remove(body)`. With `turns = true` a box tips over and a circle rolls; draw it with `img(id, b.x, b.y, {angle = b.angle})` (or `poly(w:corners(b))`). Each step is worked out in C (a world holds up to 256 bodies); bodies that do not turn move exactly as they did when the library was Lua |
| `"kit"` | a whole game from data and events, as the [editor](../README.md#without-code-the-editor) makes them: `kit.setup(data)` with levels (each a map of tiles and objects, played in order: `kit.next_level()`, `kit.goto_level(id)`; a `cover` before them, an `ending` after), objects and their kinds (`"platformer"`, `"topdown"`, `"grid"`, `"patrol"`, `"chase"`, `"shot"`, `"push"`, `"still"`); `kit.on("touch", "heroe", "moneda", function(este, otro) ... end)` and `"start"`, `"level"`, `"out"`, `"tick"`, `"press"`, `"hold"`, `"tile"`, `"every"`, `"tap"`; `kit.spawn`, `kit.destroy`, `kit.count_on(kind, tile)`, `kit.retry()`, `kit.music(id)` (each level and the cover may have their own), `kit.label(key, text, where [, style])` (`"shadow"`, `"wave"`, `"big"`, `"gradient"`), `kit.sound`, `kit.win`, `kit.lose`; conversations (`kit.say`, `kit.ask`, `"answer"`), the microphone (`"clap"`, `"blow"`), videos (`kit.video`, `"video_end"`); named animations (a kind's `anims = {idle, walk, hit}` frame ranges, with `idle_side`, `walk_side`, `idle_up`, `walk_up` for its side and back views and `act1`..`act6` for actions (the last frame stays while a conversation waits); `kit.play(o, "hit")`, `kit.play(o, "act1")`, `kit.face(o, other)`; they go on while a conversation waits); lives shown as hearts (`kit.set_lives`, `kit.add_lives`, `kit.lives()`, `"no_lives"`) and a countdown (`kit.countdown`, `kit.add_time`, `kit.time_left()`, `kit.stop_countdown`, `"time_up"`); `data.tile` (16 or 8), `data.style` (the colours of its texts, hearts and conversation box), `data.transition` (blinds between levels) and `data.words` (its own sentences, in the game's language); `kit.init()`, `kit.update()`, `kit.draw()` in the three callbacks; up to three pictures behind the map, repeated, each moving with the camera by its parallax (`backdrops`). All of it at the top of [lib/kit.lua](../lib/kit.lua) |
| `"keyboard"` | writing with the d-pad or a finger: `kb = keyboard.new({title, text, max, colours})`, `kb:update()` returns `"ok"` or `"cancel"` when done, `kb:draw()`, `kb.text` |
| `"story"` | conversations and stories that branch, written as plain text: [below](#stories) |
| `"input"` | the game's own actions, so code says `"jump"` and not `"b"`: `input.map({jump = {"b"}, fire = {"a", "c"}})`, `input.down`, `input.pressed(name, hold, every)`, `input.released`, `input.held`, `input.buffered(name, window)`; `input.dir()` (-1, 0 or 1 each, diagonals too; with left and right both held, the last pressed). A name that is not an action is a button |
| `"anim"` | animations with names, like Aseprite's tags: `a = anim.new({run = {frames = {1, 2, 3, 4}, fps = 10}, shoot = {frames = {5, 6}, ms = {60, 120}, loop = false, next = "idle", events = {[2] = "fire"}}, bob = {frames = {0, 1, 2}, mode = "pingpong"}})`, `a:play("run")` (playing it already: it goes on), `a:update()` each tick, `a.frame` to draw, `a:on("fire", fn)` on that frame, `a.done` when one that does not loop is over |
| `"cam"` | a camera that follows: `c = cam.new({bounds = {0, 0, 3840, 320}, deadzone = {80, 60}, lerp = 0.15, lead = 40, forward_only})`, `c:follow(hero)`, `c:update()` each tick, `c:apply()` in `_draw` (with juice's shake), `c:snap()`, `c:look(x, y)` for a while, `c:visible(x, y, w, h)`. `c.x, c.y` is the top-left corner seen |
| `"scene"` | a game as scenes on a stack (the title, a level, the pause): tables with `enter(args)`, `leave()`, `pause()`, `resume(result)`, `update()`, `draw()`; `scene.go(s, args, {fade = 0.4})` (the scenes leaving lose their sprites and juice's tweens, timers and scripts), `scene.push(s, args)`, `scene.pop(result)`, `scene.top()`, `scene.depth()`; a scene with `overlay = true` is drawn over the one under it, which waits. `scene.update()` and `scene.draw()` in the callbacks |
| `"rich"` | text with marks, for any text and for [stories](#stories): `rich.draw(str, x, y, opts)` at once, or `r = rich.new(str, opts)` typed out (`r:update()`, `r:draw(x, y)`, `r:skip()`, `r.done`); options `font`, `color`, `width` (wraps), `speed`, `line`, `outline`, `shadow`, `blip`. `rich.plain(str)` without the marks |

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
options and progress (`store("save", {room = 3, items = {"key", "map"}})`), up to 64 KB in all. Each `store`
writes the file at once: call it at moments like a level's end, not every frame.

## Other

`log(...)` (and `print`) writes to the log. `quit()` goes back to the console's game list (holding MENU for two
seconds does too). `perf()` returns the milliseconds the last `_update`, `_draw` and picture took, and the script's
memory in KB, to see where a frame goes. `perf(true)` shows a meter over the game: the frames a second, the last 60
frames as bars (red past the 16.7 ms of 60 fps), those times and the memory of the script and the pictures;
`perf(false)` hides it. MENU and C together show or hide it on the console, F3 in the simulator. `require("name")`
loads `name.lua` from the game folder (`"ui.menu"` is `ui/menu.lua`). `file("story/es.txt")` returns the text of any
file of the game (1 MB at most), or nil: stories, levels written by hand, a metro's stations as CSV.

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
tap 240 160                      # a finger down and up at that screen pixel (480x320)
tick 20                          # let 20 ticks pass
expect_lua state == "play"       # a Lua expression that must be true
lua P.x = 100                    # run Lua in the game (set up a situation)
expect_lua_error spin()          # code that must fail
expect_ok                        # the game has not stopped on an error
shot name                        # save the screen to the saves folder (name.ppm)
mic 0.5 440                      # the microphone hears a tone that loud (no Hz: noise; mic 0: silence; mic none: no microphone)
battery 0.2 charging             # battery() says so (battery none: no battery; battery real: the platform's)
expect_led ff0000                # the LED is that colour (expect_led off: the console's own)
```

`#` after a space starts a comment in these scripts, so avoid Lua's `#` length operator there.

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
