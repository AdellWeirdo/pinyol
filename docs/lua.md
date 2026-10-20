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
| `DOUBLE` | with `spr_mat`: the drawing area is twice the size, so the turned sprite is not cut. It costs four times the pixels (on the console three 64 x 64 sprites in 128 x 128 areas took a fight from 60 to 40 fps): use it only while the sprite turns past its own edges |
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
| `line_pal(y, index, colour [, colour ...])`, `line_pal_obj(...)` | on line y, entry `index` of the backgrounds' palette (and the next ones, one for each further colour) has that colour, as a console that writes its palette in each HBlank does: a sky that deepens, water that shimmers, a sail painted by the sunset; `line_pal_obj` is the same for the sprites' palette. Up to 16 entries a line in each; they last until `line_off()`. Entry 0 is the backdrop (`line_backdrop` wins on a line that has both). The renderer pays about a thousand cycles on each line that replaces entries (a real scene: 0.1 ms in 5), and nothing when none does; the cost to mind is the game's own, a call into C for each line and each colour: do the colours with numbers, not tables made for each line, and since the tables stay until `line_off()` write only the lines whose colours changed |
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
| `img(id, x, y, {frame, scale, scale_x, scale_y, flip_x, flip_y, angle, pal, tint, dim, mul, alpha, add, sub, quarter})` | the same turned (degrees, about its centre), scaled by any amount (negative flips) or flipped; `(x, y)` is where its top-left corner would be unturned. A packed picture (below) can also be drawn with another one's colours, `pal = "SPR_RAN_B"` (a second player, an enemy's stronger kind), or all of one colour, `tint = 0xFFFFFF` (the flash of a hit, a shadow), or darker, `dim = 0.4` (a night) or each channel by its own, `mul = 0x6070C0` (0xFF as it is): its palette is multiplied once, so a whole picture costs nothing more; not turned; `alpha = 0.5` mixes it with what is under it (a ghost, a moonbeam, afterimages), `add = true` adds its light (a glow, a fireball), `sub = true` takes it away from what is under it (a shadow, a dark vapour), `quarter = true` adds a quarter of it (a faint glow): the PlayStation's four ways to meet the picture beneath, each held to its range (`alpha` scales the picture's light in `add`, `sub` and `quarter`); all with any of the rest, turned or not |
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
| `grad(x, y, w, h, c1, c2 [, {across, dither, alpha, add, sub, quarter}])` | a box shaded from `c1` at its top to `c2` at its bottom (`across = true`: left to right): a sky, a vignette, a shaft of light (`add`), a shadow (`sub`). `dither = true` breaks the bands of a slow ramp into the PlayStation's fine 4x4 pattern |
| `quad(id, x1, y1, x2, y2, x3, y3, x4, y4 [, {frame, alpha, add, sub, quarter, light, lights, dither, mesh, uv, persp}])` | a frame of the picture on any four corners, in the picture's order (top-left, top-right, bottom-right, bottom-left): a Saturn distorted sprite, a PlayStation textured quad (a floor going away, a sign swinging, a boss bending). Corners may be fractions of a pixel and glide; two triangles with the picture spread evenly across each (no depth correction, as the PlayStation drew them, so a strong tilt shows the diagonal: `persp = true` fixes that, taking the four corners as the picture seen in perspective (the projective map that puts its square on them) and cutting it into as many cells as the quad's far and near edges differ, or `persp = 8` into 8 by 8: a floor going away, a wall seen at an angle, a sign turned; on the console it costs about twice and a half the flat quad, so a floor that fills the screen still belongs on `mode7()`). `alpha`, `add`, `sub`, `quarter` as in `img`. `light = 0xRRGGBB` lights it by that colour (`0x808080` as it is, `0x000000` black, `0xFFFFFF` twice as bright); `lights = {c1, c2, c3, c4}` one colour a corner, blending across (a shaded face, a sunset on a wall); `dither = true` spreads the lit colours' rounding in the PlayStation's 4x4 pattern instead of bands. `mesh = true` uses Saturn VDP1 mesh transparency: only pixels where screen X+Y is even are drawn; the others show what is below, including masked, lit and perspective quads. The picture is kept unpacked in memory (width x height x frames x 2 bytes, once) so each pixel can be looked up: mind that for big sheets. On the console a plain quad costs about 150 ns a pixel and a lit one 400 (a 100x100 sign is 1.5 or 4 ms of a 16.7 ms frame): quads are for signs, props and bosses; a floor over the whole screen goes on `mode7()` |
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
| `sfx(id [, gain [, {pitch, loop, pan, reverb, attack, decay, sustain, release, loop_start, loop_end, delay}]])` | plays `audio/<id>.wav` (or a sound made with `sound`) once, or looping; `pitch` 1 as recorded, 2 an octave up, 0.5 down; `pan` -1 (left ear) to 1 (right), 0 the middle: the far ear fades to nothing as it goes, the near one stays full, so an unpanned sound is as it always was. Platforms with one speaker hear it at half. `attack`, `decay` (seconds), `sustain` (0 to 1, the level it settles at) and `release` (seconds) shape its volume like a PlayStation voice: it climbs, falls to the sustain level, and when you `sfx_stop` it, lets go over the release instead of cutting (any of the four makes an envelope; the others default to no attack, no decay, full sustain, no release). `loop_start` and `loop_end` (seconds into the clip, with `loop = true`) loop only that part: a held organ note, an engine's steady hum after its start-up. `reverb` (0 to 1) sends that much of it into the room set by `reverb()`. Returns a handle; `delay` (seconds, up to 10) starts it that long after the next block of sound, to the sample, so hits asked for in one frame keep their exact spacing |
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
| `music(id)` / `music()` | loops `audio/<id>.mod` (a tracker module), `audio/<id>.spum` (ADPCM, read from the card as it plays: a third of the WAV's size, `uv run tools/wav2vag.py song.wav GAME ID --stream --loop SAMPLE`, whose channels are its layers and whose loop comes from the file) or else `audio/<id>.wav`; no id stops it |
| `music(id, fade_ms, {bank, loop, volume})` with `audio/<id>.mid` | a song as notes, as the PlayStation's SEQ and VAB: a Standard MIDI File played by a bank of samples, `audio/<bank>.bank` (default `"BANK"`). The notes take their own 16 voices, never a sound effect's; they have each instrument's envelope, the channel's volume, pan, expression, sustain pedal, reverb send (with `reverb()`) and pitch bend; channel 10 is the drum kit. A marker `loopStart` (or controller 111) and `loopEnd` set the loop, else the whole song goes round. Make a bank with `uv run tools/mkbank.py kit.json GAME BANK` (your WAVs, the keys each serves, its root note, loop and envelope) or from any General MIDI SoundFont: `uv run tools/mkbank.py --sf2 font.sf2 GAME BANK --programs 0,33,48 --drums --kb 1500`. Samples are ADPCM, a third of PCM16; a bank lives in memory (up to 8 MB, mind the PSRAM) |
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
| `wave` | `"square"` | `"square"`, `"triangle"`, `"saw"`, `"sine"` or `"noise"`; or a table of 32 numbers from 0 to 15, one period of any shape you draw (the GBA's wave channel) |
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

## Libraries built in

Lua code every game can `require`, so a game does not start from nothing. They come inside the engine (the
console, the simulator and the browser have them); a game with a file of the same name uses its own instead, so a
library can be copied into a game and changed. Each file in `lib/` says how to use it at its top.

| `require` | For |
|---|---|
| `"juice"` | what makes a game feel alive: `juice.tween(obj, {x = 100}, 0.5, "out_back")` moves fields with an ease (`linear`, `in_quad`, `out_quad`, `in_out_quad`, `in_cubic`, `out_cubic`, `in_out_cubic`, `in_back`, `out_back`, `out_elastic`, `out_bounce`, `in_bounce`), and chains: `:delay(s)`, `:loops(n)` (-1 for ever), `:yoyo()`, `:on_done(fn)`, `:after(obj, to, secs, ease)` (the next one). Time: `juice.after(secs, fn)`, `juice.every(secs, fn, times)`, `juice.script(fn)` (a function that waits: `juice.wait(secs)`, `juice.wait_until(test)`, `juice.wait_for(tween)`), `juice.cancel(handle or obj)`. `juice.shake(px)`, `juice.freeze(ticks)`, `juice.flash(colour, ticks)`; `juice.update()` in `_update` (true while frozen), `camera(juice.offset())` and `juice.draw()` in `_draw` |
| `"particles"` | sparks, smoke, dust, confetti, embers, fire: `fx = particles.new()`, `fx:burst(x, y, n, {speed, angle, spread, gravity, wind, drag, life, size, size_end, colours, shape})`, `fx:update()`, `fx:draw()`. `shape` is `"circle"`, `"square"`, `"pixel"`, `"glow"` (a soft light added to what is under it: a spark, a flame), `"shadow"` (the same taken away: smoke) or `"sprite"` (`image`, `frame`, `blend` = `"add"`, `"sub"`, `"quarter"`, `"alpha"`, `fade`). `e = fx:emit({x, y, rate, ticks, follow, ox, oy, ...the same})` keeps making them (`rate` a tick, 0.25: one in four) until `e:stop()` or `ticks`; `e:move(x, y)`. Glows and shadows are lights: a group draws the 64 youngest in a frame, the 48 youngest scaled sprites (the drawing slots are 128 a frame for every light, gradient, quad and scaled picture) |
| `"rig"` | a character as pieces hung on each other, moved by keyframes (cut-out animation, as the Saturn's big 2D characters): `hero = rig.new({parts = {{id, image, pivot, parent, at, z}, ...}, anims = {walk = {len, loop, next, events, tracks = {head = {rot = {{0, 0}, {30, 5, "smooth"}}}}}}})`; tracks change `rot` (degrees, clockwise), `x`, `y`, `sx`, `sy` and `frame`; `hero:play("walk", {fade, restart, speed})` blends from the pose it was in, `hero:on("step", fn)` for events, `hero:update()`, `hero:draw(x, y, {flip, scale, light, lights, dither})` (each piece a `quad`), `hero:point("arm", 0, 18)` where a point of a piece is on the screen (a hand, a weapon's tip). Each piece uses one of the frame's 128 drawing slots |
| `"transition"` | the way from one screen to the next: `transition.go("iris", 0.8, {cx, cy, color, hold, on_mid = function() load_room() end, on_done})` closes, calls `on_mid` once with the screen covered, holds and opens; `transition.update()` each tick and `transition.draw()` last in `_draw`; `transition.active()`, `transition.covered()`. Kinds: `"fade"` (smooth, the dearest: a mixed full-screen box), `"wipe"` (`dir` = `"right"`, `"left"`, `"up"`, `"down"`), `"curtain"` (two halves closing; `dir = "vertical"`), `"blinds"` (`bars`, `dir`), `"iris"` (a circle closing on `cx`, `cy`), `"blocks"` (`size`: square blocks in the 4x4 pattern's order, the PlayStation's tile dissolve). `transition.draw_kind(kind, k, opts)` draws one still frame (k 0 to 1). `scene.go(scene, args, {fade = 0.4, transition = "iris", cx, cy})` uses one for the change |
| `"physics"` | things that fall, bounce, slide, tip over, roll, float and hit: `w = physics.world({gravity})`, `w:circle(x, y, r, {bounce, friction, static, mass, turns})`, `w:box(x, y, w, h, {...})`, `w:poly(x, y, {x0, y0, x1, y1, ...}, {...})` (a convex shape: rocks, ramps, hulls), `w:rope(a, b, length, {stick})`, `w:water(x, y, w, h, {lift, drag, flow_x, flow_y})` (it floats, slows down and drifts with the current: a river, a raft), `w:drive(body, angle [, px, py])` (a static polygon the game turns about a point, a flipper or a door: what it meets is hit by its moving surface), `w:step()`, `w:hits()`, `w:at(x, y)`, `w:corners(body)`, `w:remove(body)`. With `turns = true` a box tips over and a circle rolls; draw it with `img(id, b.x, b.y, {angle = b.angle})` (or `poly(w:corners(b))`). Each step is worked out in C (a world holds up to 256 bodies); bodies that do not turn move exactly as they did when the library was Lua |
| `"kit"` | a whole game from data and events, as the [editor](../README.md#without-code-the-editor) makes them: `kit.setup(data)` with levels (each a map of tiles and objects, played in order: `kit.next_level()`, `kit.goto_level(id)`; a `cover` before them, an `ending` after), objects and their kinds (`"platformer"`, `"topdown"`, `"grid"`, `"patrol"`, `"chase"`, `"shot"`, `"push"`, `"still"`); `kit.on("touch", "heroe", "moneda", function(este, otro) ... end)` and `"start"`, `"level"`, `"out"`, `"tick"`, `"press"`, `"hold"`, `"tile"`, `"every"`, `"tap"`; `kit.spawn`, `kit.destroy`, `kit.count_on(kind, tile)`, `kit.retry()`, `kit.music(id)` (each level and the cover may have their own), `kit.label(key, text, where [, style])` (`"shadow"`, `"wave"`, `"big"`, `"gradient"`), `kit.sound`, `kit.win`, `kit.lose`; conversations (`kit.say`, `kit.ask`, `"answer"`), the microphone (`"clap"`, `"blow"`), videos (`kit.video`, `"video_end"`); named animations (a kind's `anims = {idle = {frames = {0}}, walk = {frames = {1, 2, 3}, fps = 10}, hit = {frames = {4}, loop = false}}`, as `"anim"` names them: `fps` left out is the kind's own `animate` pause, `loop = false` stops on the last frame, `{first, last}` as before still works; a kind's `pivot = {x, y}` is the point it turns round when it looks the other way; with `idle_side`, `walk_side`, `idle_up`, `walk_up` for its side and back views and `act1`..`act6` for actions (the last frame stays while a conversation waits); `kit.play(o, "hit")`, `kit.play(o, "act1")`, `kit.face(o, other)`; they go on while a conversation waits); lives shown as hearts (`kit.set_lives`, `kit.add_lives`, `kit.lives()`, `"no_lives"`) and a countdown (`kit.countdown`, `kit.add_time`, `kit.time_left()`, `kit.stop_countdown`, `"time_up"`); `data.tile` (16 or 8), `data.style` (the colours of its texts, hearts and conversation box), `data.transition` (blinds between levels) and `data.words` (its own sentences, in the game's language); `kit.init()`, `kit.update()`, `kit.draw()` in the three callbacks; up to three pictures behind the map, repeated, each moving with the camera by its parallax (`backdrops`). All of it at the top of [lib/kit.lua](../lib/kit.lua) |
| `"keyboard"` | writing with the d-pad or a finger: `kb = keyboard.new({title, text, max, colours})`, `kb:update()` returns `"ok"` or `"cancel"` when done, `kb:draw()`, `kb.text` |
| `"story"` | conversations and stories that branch, written as plain text: [below](#stories) |
| `"input"` | the game's own actions, so code says `"jump"` and not `"b"`: `input.map({jump = {"b"}, fire = {"a", "c"}})`, `input.down`, `input.pressed(name, hold, every)`, `input.released`, `input.held`, `input.buffered(name, window)`; `input.dir()` (-1, 0 or 1 each, diagonals too; with left and right both held, the last pressed). A name that is not an action is a button |
| `"anim"` | animations with names, like Aseprite's tags: `a = anim.new({run = {frames = {1, 2, 3, 4}, fps = 10}, shoot = {frames = {5, 6}, ms = {60, 120}, loop = false, next = "idle", events = {[2] = "fire"}}, bob = {frames = {0, 1, 2}, mode = "pingpong"}})`, `a:play("run")` (playing it already: it goes on), `a:update()` each tick, `a.frame` to draw, `a:on("fire", fn)` on that frame, `a.done` when one that does not loop is over |
| `"cam"` | a camera that follows: `c = cam.new({bounds = {0, 0, 3840, 320}, deadzone = {80, 60}, lerp = 0.15, lead = 40, forward_only})`, `c:follow(hero)`, `c:update()` each tick, `c:apply()` in `_draw` (with juice's shake), `c:snap()`, `c:look(x, y)` for a while, `c:visible(x, y, w, h)`. `c.x, c.y` is the top-left corner seen. Zoom and turn, for a scene drawn with rect, img, quad and light: `c:draw(function() ... end)` (or `c:begin()` ... `c:finish()`), `c:zoom_to(2)`, `c:rotate_to(15)`, `c:zoom_now`, `c:rotate_now`, `c:punch(0.08, 12)` (a hit zooms in and eases back); the scene goes through a canvas and a quad, so it is for a moment, not a level (80 ms a frame at the whole screen, 31 with `cam.new({w = 240, h = 160})`; not zoomed it is free) |
| `"scene"` | a game as scenes on a stack (the title, a level, the pause): tables with `enter(args)`, `leave()`, `pause()`, `resume(result)`, `update()`, `draw()`; `scene.go(s, args, {fade = 0.4})` (the scenes leaving lose their sprites and juice's tweens, timers and scripts; the picture's effects stay: with `{clean = true}`, or `scene.clean()` by hand, the fade, blend, windows and their per-line spans, mosaic, per-line tables, hidden layers, synthesised voices and the LED are put back too), `scene.push(s, args)`, `scene.pop(result)`, `scene.top()`, `scene.depth()`; a scene with `overlay = true` is drawn over the one under it, which waits. `scene.update()` and `scene.draw()` in the callbacks |
| `"rooms"` | a game as places you walk between: `rooms.define({id, w, h, layers, front, solids, spawns, exits, things, variant, variants, assets, enter, leave, update})`, `rooms.go("bar", "door")` (the curtain closes, the next room's pictures and sounds are read behind it with `preload`, it opens), `rooms.update()`, `rooms.draw(function() draw_player() end, player.y + player.h)`; `rooms.move(player, dx, dy)` (walls and the room's edge, one axis at a time), `rooms.exit_at(e)` and `rooms.take(exit)`, `rooms.thing_near(e, reach)`, `rooms.remove(id)`, `rooms.flag(room, key [, value])`, `rooms.visits(room)`; a room scrolls with a camera that follows `rooms.player`, wider than the screen if it says so; `variant()` picks a look (a crisis) and `rooms.refresh()` applies it; `store("rooms", rooms.save())` and `rooms.load(...)` keep what you did in each. `occluders` (the pieces of a pre-rendered background that stand in front of what is behind them: a counter, a stool, a pillar), each with a depth `z` and ordered among the things and the player by his feet's line, so he walks behind the counter and in front of the stool; `uv run tools/depthcut.py BG.png MAP.png GAME BG_BAR --z FF0000=280,...` cuts them from a map painted in flat colours, one for each piece. All of it at the top of [lib/rooms.lua](../lib/rooms.lua) |
| `"views"` | project one actor's ground position through several staged cameras: `sx, sy, scale, order = views.project({kind = "side" or "fixed" or "rear", ...}, x, z, height)`. Side maps route distance `z` across the screen; fixed uses `basis = {xx, zx, xy, zy}` and optional depth scaling; rear projects distance from a camera at `cz`, returning `nil` behind it. For many actors in a rear view, create `project = views.projector(camera)` once and call `project(x, z, height)`: lens settings are validated and captured once, while `camera.cx` and `camera.cz` remain live for following. `order` sorts far to near. `views.pick({{id, x0, x1, z0, z1}, ...}, x, z, fallback)` chooses a half-open camera zone; it does not change the actor's world position. See [examples/psx_views](../examples/psx_views), which cuts from lateral to fixed to rear with `transition` and keeps state. |
| `"inventory"` | what a character carries: `inv = inventory.new({slots = 3, items = {llave = {name, icon}}, uses = {llave = {botellero = function() return true end}}})`, `inv:add(id)` (false and `"full"`, `"have"` or `"unknown"`), `inv:remove`, `inv:has`, `inv:select(i)`, `inv:next()`, `inv:use_on(target)`, `inv:draw(x, y)` (a strip of slots), `inv:save()` and `inv:load(t)` |
| `"hud"` | what a screen keeps in a corner: `m = hud.meter({x, y, w, h, label, segments, color, danger, danger_color})` that eases to `m:set(0.35)`, `hud.hearts(x, y, n, max)`, `hud.counter(x, y, icon, n)`, `hud.portrait(x, y, pic)`, `hud.objective(x, y, w, title, lines, {done})`, `hud.toast("text")` with `hud.update()` and `hud.draw_toasts(x, y)`; its sizes follow the font |
| `"lights"` | the lamps of a scene as a list: `lights.ambient(0.35, 0.4, 0.55)` (the room's own light), `lamp = lights.add({x, y, r = 80, color = 0xFFC060, flicker = 0.15})`, `torch = lights.add({follow = player, r = 110, cone = {angle = 0, width = 60}, aim = true})`, `lights.update()`, `img("BG", 0, 0, {mul = lights.mul()})` and `lights.draw()`; `lamp.on = false` |
| `"rich"` | text with marks, for any text and for [stories](#stories): `rich.draw(str, x, y, opts)` at once, or `r = rich.new(str, opts)` typed out (`r:update()`, `r:draw(x, y)`, `r:skip()`, `r.done`); options `font`, `color`, `width` (wraps), `speed`, `line`, `outline`, `shadow`, `blip`. `rich.plain(str)` without the marks |

`views.draw3d(camera, items)` draws textured 3D quads and actors through a `side`, `fixed` or `rear` camera. A face is `{id = "WALL", corners = {{x=..., z=..., h=..., u=..., v=...}, ...}, opts = {light = ...}}`: four corners in picture order, UV in texels. Optional `pose = {x, z, h, angle, scale}` places local corners in the world; angle turns around the height axis in degrees and scale must be positive. `cull = true` skips faces whose projected corners run counterclockwise on the screen; use convex faces with consistent winding. An actor is `{x=..., z=..., h=..., draw=function(sx, sy, scale) ... end}`; its callback can draw a sprite at the projected position. Items are sorted far to near with stable ties, so actors can pass behind and in front of faces. A rear view clips faces at `camera.cz + camera.near` (default near `0.01`), interpolating position and UV; faces crossing that plane become triangles. Actors behind that plane are hidden. Clipped faces do not accept per-corner `lights` yet; a uniform `light` works. Use small pictures and a modest number of faces: rasterized area, not polygon count, dominates Cirera's frame time.

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
Measuring times each command in each strip, so it costs a little while it is on. MENU and C together show or hide the meter on the console, F3 in the simulator. `require("name")`
loads `name.lua` from the game folder (`"ui.menu"` is `ui/menu.lua`). `file("story/es.txt")` returns the text of any
file of the game (1 MB at most), or nil: stories, levels written by hand, a metro's stations as CSV.

## Limits (the sandbox)

A game downloaded from the community cannot harm the console:

- Lua 5.4 with 32-bit integers and floats on every platform (the same results everywhere).
- 4 MB of memory for the script (`"lua_memory_kb"` in game.json, up to 6144); past it, "not enough memory".
- A call (`_init`, `_update`, `_draw`) that runs 20 million VM instructions without returning is stopped: an
  endless loop becomes an error, not a frozen console.
- No `io`, `os`, `debug` or `package`; `load` takes source text only, never bytecode; `require` only reads `.lua`
  files inside the game folder.
- `math.random` starts from the same seed every run, so a game and its tests repeat exactly; `math.randomseed(n)` sets another.

## Testing

A test script plays the game with real input (see `tests/plataformas.script`):

```
new                              # start (runs _init)
press A                          # a button for one tick; hold RIGHT 30 holds it for 30
tap 240 160                      # a finger down and up at that screen pixel (480x320)
touch 240 160 60                 # a finger held there 60 ticks, then lifted (a long press)
drag 40 200 440 200 30           # a finger along a line in 30 ticks (a knob turned, a fader, steps painted)
swipe 400 100 400 20             # the same, quick (8 ticks)
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
