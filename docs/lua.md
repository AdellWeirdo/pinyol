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
| `img(id, x, y, {frame, scale, scale_x, scale_y, flip_x, flip_y, angle, pal, tint})` | the same turned (degrees, about its centre), scaled by any amount (negative flips) or flipped; `(x, y)` is where its top-left corner would be unturned. A packed picture (below) can also be drawn with another one's colours, `pal = "SPR_RAN_B"` (a second player, an enemy's stronger kind), or all of one colour, `tint = 0xFFFFFF` (the flash of a hit, a shadow); not turned |
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
  you), a BDF, a PNG sheet of glyphs (16 a row, as GB Studio's), or one of the fonts that come with np2d
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

## Libraries built in

Lua code every game can `require`, so a game does not start from nothing. They come inside the engine (the
console, the simulator and the browser have them); a game with a file of the same name uses its own instead, so a
library can be copied into a game and changed. Each file in `lib/` says how to use it at its top.

| `require` | For |
|---|---|
| `"juice"` | what makes a game feel alive: `juice.tween(obj, {x = 100}, 0.5, "out_back")` moves fields with an ease (`linear`, `in_quad`, `out_quad`, `in_out_quad`, `in_cubic`, `out_cubic`, `in_out_cubic`, `in_back`, `out_back`, `out_elastic`, `out_bounce`, `in_bounce`); `juice.shake(px)`, `juice.freeze(ticks)`, `juice.flash(colour, ticks)`; `juice.update()` in `_update` (true while frozen), `camera(juice.offset())` and `juice.draw()` in `_draw` |
| `"particles"` | sparks, smoke, dust, confetti: `fx = particles.new()`, `fx:burst(x, y, n, {speed, angle, spread, gravity, drag, life, size, colours, shape})`, `fx:update()`, `fx:draw()` |
| `"physics"` | things that fall, bounce, slide and hit: `w = physics.world({gravity})`, `w:circle(x, y, r, {bounce, friction, static, mass})`, `w:box(x, y, w, h, {...})`, `w:rope(a, b, length, {stick})`, `w:step()`, `w:hits()`, `w:at(x, y)`, `w:remove(body)`. Circles and boxes that do not turn: toys, puzzles, arcade games, up to about 60 bodies on the console |
| `"kit"` | a whole game from data and events, as the [editor](../README.md#without-code-the-editor) makes them: `kit.setup(data)` with levels (each a map of tiles and objects, played in order: `kit.next_level()`, `kit.goto_level(id)`; a `cover` before them, an `ending` after), objects and their kinds (`"platformer"`, `"topdown"`, `"grid"`, `"patrol"`, `"chase"`, `"shot"`, `"push"`, `"still"`); `kit.on("touch", "heroe", "moneda", function(este, otro) ... end)` and `"start"`, `"level"`, `"out"`, `"tick"`, `"press"`, `"hold"`, `"tile"`, `"every"`, `"tap"`; `kit.spawn`, `kit.destroy`, `kit.count_on(kind, tile)`, `kit.retry()`, `kit.music(id)` (each level and the cover may have their own), `kit.label`, `kit.sound`, `kit.win`, `kit.lose`; `kit.init()`, `kit.update()`, `kit.draw()` in the three callbacks; up to three pictures behind the map, repeated, each moving with the camera by its parallax (`backdrops`). All of it at the top of [lib/kit.lua](../lib/kit.lua) |
| `"keyboard"` | writing with the d-pad or a finger: `kb = keyboard.new({title, text, max, colours})`, `kb:update()` returns `"ok"` or `"cancel"` when done, `kb:draw()`, `kb.text` |

## Saving

`store(key, value)` keeps a value in the game's saves folder: a number, string, boolean, or a table of them (a list,
or string keys), nested; `store(key, nil)` forgets it. `stored(key [, default])` reads it back. For high scores,
options and progress (`store("save", {room = 3, items = {"key", "map"}})`), up to 64 KB in all. Each `store`
writes the file at once: call it at moments like a level's end, not every frame.

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
tap 240 160                      # a finger down and up at that screen pixel (480x320)
tick 20                          # let 20 ticks pass
expect_lua state == "play"       # a Lua expression that must be true
lua P.x = 100                    # run Lua in the game (set up a situation)
expect_lua_error spin()          # code that must fail
expect_ok                        # the game has not stopped on an error
shot name                        # save the screen to the saves folder (name.ppm)
mic 0.5 440                      # the microphone hears a tone that loud (no Hz: noise; mic 0: silence; mic none: no microphone)
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
