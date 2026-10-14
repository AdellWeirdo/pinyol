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
