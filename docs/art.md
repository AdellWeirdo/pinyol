# Art for a game: generated images to the engine's assets

A game's art can be drawn by code (the template's `art.py` does it) or drawn by hand, but most of the examples'
art was generated with an image model and then fitted to the game: `duelo`, `calle`, `asalto`, `nubes`, `futbol`,
`moto` and `control`. This page is how, step by step, with the numbers they use. It is written so a coding agent
(Codex, Claude Code...) can follow it too.

```
raw/  big generated PNGs (keep them outside the game, with the prompts that made them)
  │   art/make_art.py: remove the background, cut the frames, fit scale and feet, crop, quantize
  ▼
art/  PNGs at the game's size, one per asset (kept in the game: small, and what you would retouch by hand)
  │   art.py: tools/png2asset.py for each one
  ▼
assets/  what the engine reads (.pk / .tiles / .map / .pal + .meta.json)
```

`examples/duelo/art/make_art.py` is the shortest whole example of the middle step: read it next to this page.

## 0. Choose a look

A game looks like the console it is made for. Pick one with whoever the game is for (ask, if they have not said),
then make every picture by that look's rules and start from its example. The engine moves all of them.

Not every look needs an image model. The small ones (Game Boy, Spectrum, 16-bit, PICO-8, LCD, vector, first person)
are best **drawn by code** in the game's `art.py`, from pictures written as text and simple shapes, as their examples
do: no quota, and pixels exactly where they should be. A game can even draw everything while it runs, with no
pictures at all (`examples/inventos`, `rocas`, `ladrillos`, `huevos`, `tormenta`).
Generate images (sections 2 to 4 below) for the big, detailed looks: Neo Geo and CPS2.

### Game Boy: `examples/bolsillo`

- The whole world, 240×160, as a modern Game Boy would show it: a status bar across the top and the level under it.
  No console case drawn around a 160×144 screen (it wastes a third of the screen) unless the user asks for one: then
  the level sits in the world's middle and the case is a picture at full resolution, drawn last.
- **Four tones**, lightest to darkest. `art.py` writes `WORLD.pal` and `OBJ.pal` with them *before* converting, so each
  tone keeps its index (1-4) and `pal()` changes the whole game's colours at once (as a Game Boy Color did).
- 8×8 tiles in one background layer, 16×16 sprites, a status bar, two square voices and a noise.
- Art by code. Style line, if generating: *Game Boy pixel art, four shades of green, 8x8 tiles, no anti-aliasing*.

### ZX Spectrum (and Amstrad CPC): `examples/cinta`

- The world, a 224×144 screen inside a border of one colour.
- **Two colours per 8×8 block**, an ink and a paper, from fifteen (eight, and seven bright). Blocks are drawn in two
  key colours (`WORLD.pal` 1 and 2) and coloured by a palette bank per block (`mset(n, x, y, tile | bank << 12)`),
  as the attributes did. Sprites are ink only and take the bank of the block they are in: the colour clash. A
  flashing block is a bank whose two colours swap.
- The loading screen: any picture through `art/make_art.py` (the best two colours per block, a dither between them),
  shown as the tape loaded it: striped border, the bitmap in the Spectrum's order, then the colours.
- One square voice (the beeper). Amstrad CPC: the same, with pixels twice as wide (mode 0) and 16 colours of 27.
- Art by code; the loading screen from any illustration.

### Game Boy Advance: `plataformas`, `naves`, `carreras`, `puzle`, `aldea`

- The world, 240×160. Characters 16 to 32 pixels tall, 8 to 16 colours; 8×8 tiles (`--tiles`), shared palettes
  (`--palette`); sprites that turn and scale (`spr_mat`), Mode 7, per-line effects, blending, mosaic, windows.
- Style line: *16-bit handheld pixel art, 4 to 8 colours per sprite, hard pixel edges, no anti-aliasing*.

### SNES and Mega Drive: `examples/veloz`

- The world, 240×160. Sprites up to 32×32 (bigger in a few), 15 colours each or fewer.
- Mega Drive: far layers moved at a different speed on each line (`line_scroll`: a sea, clouds), strong saturated
  colours, a checkered earth. SNES: a sky that changes colour line by line (`line_backdrop`), water and glass seen
  through (`blend`), a mosaic between scenes, Mode 7 floors.
- Art by code or generated at the sprite's size. Style line: *16-bit console pixel art, 15 colours per sprite,
  bold outlines, saturated colours, no anti-aliasing*.

### Neo Geo: `duelo`, `calle`, `asalto`, `nubes`, `futbol`, `moto`

- Pictures at 480×320 (`img`, `--packed`). Characters 150 to 180 pixels tall, 64 colours or more; wide layers;
  zoom (`img(..., {scale})`, a camera that zooms in); big frames, flashes (`tint`).
- Generated art. Style line: *mid-1990s Neo Geo sprite art, 3 to 4 tones per material, hard pixel edges, no
  anti-aliasing*.

### PlayStation and Saturn 2D: `examples/gotico`

- Pictures at 480×320. Characters about 90 pixels tall in **up to 256 colours** (8 bits packed), many frames.
- **Light and transparency**: candle glows and fire added to what is under them (`img(..., {add = true})`), ghosts,
  the afterimages of a dash half seen through (`{alpha = 0.5}`); glows drawn by code. On the console a mixed
  pixel costs about three drawn plainly: keep them to what moves (light that moves with a background goes into the
  background, as `gotico`'s moonbeams).
- Sprites that **turn and swell** (`angle`, `scale`): a boss that sways and breathes.
- Generated art. Style line: *late-1990s 32-bit console 2D sprite art, gothic action game: richly detailed
  hand-pixelled sprite with up to 256 colours, smooth careful shading, crisp pixel edges*.

### CPS2: `torneo`, `mazmorra`

- Pictures at 480×320. Characters 125 to 140 pixels tall in **15 colours and see-through** (`--colours 16`, four bits
  a pixel). **No zoom**: everyone keeps the size they were drawn at; the camera only pans. A floor in perspective drawn
  in bands of rows (`torneo`), pillars in front of everyone, the same character in other colours (`pal`), many frames
  per move.
- Generated art. Style line: *mid-1990s 2D arcade fighting game sprite, hand-pixelled, bold dark outline, cel
  shading with 3 or 4 tones per material, about 15 colours in total, anime-influenced proportions*.

### PICO-8: `examples/ladrillos`

- A 128×128 canvas, cleared and drawn again every frame with `cls`, `rect`, `circ`, `line` and `pset` (as PICO-8
  code is written), shown twice as big in the middle: `img("P8", 112, 32, {scale = 2})`.
- PICO-8's **sixteen colours** and no others; letters four of its pixels wide (Press Start 2P at 8 pixels).
- No pictures at all; little square-wave blips.

### Pocket LCD games: `examples/huevos`

- Every figure is a fixed shape, either **on** (black) or **off** (a faint ghost that still shows), over a picture
  printed in colour behind the glass. Draw the glass, the printed picture and every figure's ghost once on a canvas;
  each frame show it and draw only what is on.
- Things move a step at a time with a beep, faster as the score grows; the score in seven-segment digits.
- All polygons (`poly`, `circ`, `rect`): no pictures.

### Vector arcade: `examples/rocas`

- Nothing but bright lines on black, at the screen's full resolution, each with a soft glow (a dim copy one pixel to
  each side, then the line); letters made of strokes too.
- No pictures at all.

### First person: `examples/laberinto`

- `raycast()` (docs/lua.md, "First person") draws the maze seen from inside onto a 240×160 canvas, shown twice as
  big under a status bar; walls are 32×32 textures, sprites 32×32 pictures standing in the maze.
- Art by code (stone, brick, wood, a door; a ghost, a gem, a lamp) or generated at 32 or 64 pixels.

### A vertical screen: `examples/tormenta`

- The game drawn on a **320×480 canvas standing up**, shown turned a quarter round (`img(..., {angle = 90})`): the
  console is held on its side, its left edge down. Read the arrows turned the same way.
- Hundreds of bullets as swarms (they draw on the canvas too).

Name the look, never a company's game or characters: the art must be the game's own.

## 1. Decide the sizes first

Two kinds of picture, and a game can mix them:

| | Drawn with | Size | Look |
|---|---|---|---|
| **World** (the PPU) | `bg()`, `spr()` | the world is 240×160, shown twice as big | GBA: big chunky pixels, tiles, palettes, Mode 7 |
| **Pictures** | `img()` | screen pixels, 480×320 | Neo Geo: every pixel at full resolution |

For each character, write down four numbers before generating anything, and put them at the top of `make_art.py`:
the frame's size, the body's height, the row of its feet and the column of its centre. Then one number for the
stage: the screen row where feet stand (`FLOOR`).

| Example | Frame | Body | Feet (anchor) | Floor |
|---|---|---|---|---|
| duelo, calle: fighters | 192×184 | 168 | 70,181 | 292 |
| calle: a thug | | | 122,181 | 292 |
| asalto: heroine, robot, walking tank | | 88, 72, 150 | 50,94 / 52,78 / 150,158 | 292 |
| futbol: a player | | | 30,70 | |
| moto: the bike | | | 64,127 | |

Heights decide how characters look next to each other: choose them together, in one table, not one sheet at a time.

## 2. Generate

**The tool.** Codex has an image tool built in (it uses your ChatGPT plan's quota: about 1% of the five-hour window
per image, three times that if it retries, so ask once and fix the result in code instead of regenerating). Any
other image model works the same way.

**One reference per character.** Generate the character first, alone: full body, standing, facing right, on a
transparent background. Look at it; when it is right it becomes the character's reference, and *every* later sheet
of that character is generated with that one image attached. Without it the style and the face drift from sheet to
sheet; with more than one reference each request costs more. The result tends to copy the reference's size and
background.

**Sheets of frames.** One request, one row of five frames (a fifth of the cost of five requests):

> One horizontal row of exactly five animation frames of this same character (attached): a walk cycle. Facing
> right, three-quarter view, the feet of every frame on one baseline, wide empty gaps between frames, the same
> size in every frame. Transparent background. No text, no grid, no ground, no shadow.

For many frames, two rows of five at 1536×1024 halve the requests again (cut the rows apart at the emptiest row).

**One style line for every prompt**, so the whole game matches. `asalto`'s:

> mid-1990s Neo Geo sprite art, 3 to 4 tones per material, hard pixel edges, no anti-aliasing

**Backgrounds** at 1536×1024, in separate layers:

- far: the whole scene, *"nothing in the lower foreground"* (the fighters will stand there);
- near: *"behind it nothing but transparent, a wide flat floor where the fighters stand"*;
- a layer that repeats sideways: *"the left and right edges continue seamlessly"*, or mirror every other copy in
  the game (below).

Keep a `prompts.txt` (`name|prompt`, one per line) beside the raw images, so any of them can be made again.

Never real people, brands or logos.

## 3. Remove the background

Generated images often come back without real transparency: on white, or on a grey checkerboard *painted into the
picture*. `tools/fit_sprite.py --key-bg` removes light grey and white connected to the border:

```sh
uv run tools/fit_sprite.py raw/hero_walk.png art/walk --like art/idle.png --split 5 --key-bg
```

What to check afterwards (look at the frames over a strong colour such as magenta):

- **pockets**: background enclosed by the character (between an arm and the body) does not touch the border and stays;
- **white clothes** that touch the background get eaten;
- asking the model for a magenta background to key out is not reliable (asalto asked and got transparency instead).

When one of these happens, fix that image in `make_art.py` (fill the pocket, protect a region) rather than
regenerating it.

**Transparency is all or nothing** in the engine. Resize first, with `Image.LANCZOS`, then make every pixel either
opaque or clear at alpha 128 (`solid()` in duelo's `make_art.py`). A faint halo means the resize happened after the
threshold, or the image was resized without premultiplied alpha.

## 4. Animation frames

1. **The first frame (idle) from the reference**: crop it to what is visible, scale it so the body is `BODY` tall,
   paste it on a transparent `W`×`H` frame with the feet on row `FEET` and the centre on column `BACK` (`idle()` in
   duelo's `make_art.py`).
2. **Every sheet fitted to that frame**: `fit_sprite.py` cuts the sheet at its empty columns and gives every frame
   the idle frame's size, body height and baseline, with one scale and one vertical offset for the whole sheet, so a
   jump inside the sheet stays a jump:

   ```sh
   uv run tools/fit_sprite.py raw/kai_walk.png tmp/walk --like tmp/idle.png --split 5
   uv run tools/fit_sprite.py raw/kai_punch.png tmp/punch --like tmp/idle.png --split 5 --anchor left --keep-main
   ```

   - `--anchor left`: frames line up by their leading edge, for moves that grow forward (a punch, a kick) while the
     body stays; `right` for a character facing left.
   - `--keep-main` drops what does not touch the body: motion lines, dust.
   - `--scale-frame K` takes the scale from frame K, when frame 0 is a crouch.
   - `--height N` instead of the idle frame's height.
3. **One strip, one palette**: paste the frames side by side and quantize the whole strip together (duelo: 64
   colours for a fighter), so every frame has the same colours.
4. **Into the engine**:

   ```sh
   uv run tools/png2asset.py art/kai.png assets SPR_KAI --frames 11 --anchor 70,181 --packed
   ```

   A picture holds 64 frames at most, each up to 1024×1024: past that, two pictures (`SPR_X` and `SPR_X2`).
5. **Timing is in Lua**: `frame = (t // 6) % 5` is a walk at 10 frames a second.

Even with the reference, the model draws each sheet at its own scale. `--like` corrects the height by the body,
but check by eye: the idle frame and a punch side by side, the feet on the same row.

## 5. Placing them on the screen

`img()` draws from the picture's top-left corner, so subtract the feet. For a frame `W` wide with its feet at
`AX,AY`:

```lua
img("SPR_KAI", x - AX, FLOOR - AY, {frame = f})                      -- facing right
img("SPR_KAI", x - (W - 1 - AX), FLOOR - AY, {frame = f, flip_x = true}) -- facing left
```

(duelo: `x - 70` and `x - 121` for its 192-wide frames, `FLOOR - 181`.) Mirroring costs nothing; scaling at
runtime (`scale =`) costs per pixel drawn, so bake the size in `make_art.py` when it does not change.

In the world, the same: `spr()` places a sheet's frame by its top-left, at world pixels (240×160).

## 6. Backgrounds

**As pictures** (full resolution, `--packed`):

- the far layer wider than the screen, scrolling at half the camera's speed: duelo crops its 1536×1024 to the rows
  it needs and resizes to 640×320; 256 colours;
- the near layer only the floor strip, with transparency: duelo's is 572×175, 255 colours plus clear;
- crop away what the game never shows: it is memory, and time to draw;
- a repeating layer drawn mirrored every other copy (`flip_x`) needs no seamless edges. A vertical flip is slow: make
  a flipped copy in `make_art.py` instead;
- another colour of the same picture (a second player, the other team's kit, a stronger enemy): one picture,
  drawn with another's palette, `img(id, x, y, {pal = "SPR_KAI_B"})`; `futbol`'s four kits are one picture;
- `--colours 16` makes a picture 4 bits a pixel, half the memory; up to 256 colours it is 8.

A game's pictures share 4 MB; past it, those not drawn in a frame are let go and come back from the card when
drawn again. What one frame draws must fit. `pinyol_headless --pictures KB` plays a test with less memory to check it.

**In the world** (tiles):

```sh
uv run tools/png2asset.py art/level.png assets LEVEL --tiles --palette WORLD         # bg(1, {map = "LEVEL"})
uv run tools/png2asset.py art/track.png assets TRACK --tiles --affine --palette WORLD # turned, Mode 7
uv run tools/png2asset.py art/hero.png assets HERO --indexed --frames 4 --palette OBJ  # spr()
```

The picture is cut into 8×8 tiles; repeated tiles (also mirrored ones) are stored once. A map holds 1024 different
tiles at most (256 for `--affine`, without mirroring): a generated picture with no repeats rarely fits, so tiles
suit drawn or simplified art. `--palette` shares one palette between assets, as the PPU does.

## 7. Tiles and levels

- **Levels as text**: the template's `room.lua` is a level written as characters (`#` wall, `~` water...); its
  `art.py` draws each character's tile and builds the map.
- **Tiled**: draw the level in [Tiled](https://www.mapeditor.org) and import it with `tools/tiled2asset.py`
  (`examples/aldea`, 16×16 tiles). See [lua.md](lua.md#levels-from-tiled).

## 8. Check

- `pinyol_headless --game DIR --validate`, then a test script with `shot` on the screens that matter: look at them.
- Every frame over magenta, in one contact sheet: holes, halos, feet off the row.
- On the console, `perf(true)` (or MENU and C) shows the frame time: big pictures are where it goes.
- Each file in a folder makes opening the others slower on the card: keep `assets/` to what the game uses.
