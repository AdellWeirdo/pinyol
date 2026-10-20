# Two screens: a design (step 1 built: layout C in the simulator; the Cirera has one screen, so the rest is dropped)

Phase 2 of the DS touch work ([ds-touch-research.md](ds-touch-research.md)). Step 1 of "Order of work" is built (see below); the rest is not. It is written from a read of `src/ppu.h`, `src/ppu.c`, `src/game.c`, `src/lua_game.c` and `docs/hardware.md`; what was not read is under "To check before building".

## What a game would write

```lua
-- game.json: "screens": 2        (opt in; a game without it is exactly as today)
function _draw()
  screen(1)            -- the top screen: every call after this is for it
  bg(0, ...) ; spr(...) ; text("Mapa", 10, 10)
  screen(2)            -- the bottom, the touch one
  bg(0, ...) ; spr(...)
end
local x, y, down, tapped, released = pen()   -- always the bottom screen's own pixels
```

`screen(n)` picks which screen the PPU calls (`bg`, `spr`, `scroll`, `pal`, `line_*`...) and the drawing calls (`text`, `rect`, `line`...) act on. `SCREEN_W` and `SCREEN_H` are those of one screen. `touch()` and `pen()` are the bottom screen's.

> **Decision (2026-10-20):** the Cirera has one touch screen. Two screens stay an opt-in of the simulator and the web player (`"screens": 2`), for games that want to be made DS-style; layouts A and B, the panel's strips and the firmware (steps 2 and 5 below) are not going to be built. Touch games for the console use `pen()` and `lib/pointer.lua` on its one screen.

## The size of a screen, and the panel

The Cirera's panel is **320x480, portrait**; today the firmware turns it into 480x320 in software (`docs/hardware.md`: the ST77922 has no MV bit). Held upright it fits two screens with no turning:

| Layout | Each screen | Pixel shape | Note |
|---|---|---|---|
| **A. Stacked, 4/3 (recommended)** | the 240x160 world drawn 320x213 (x4/3), 54 rows spare for a gap | one source pixel in four is drawn twice | uses the whole panel width, like the DS's two equal screens |
| B. Stacked, 1x | 240x160 at 1:1, centred | exact | 40 px of border each side: small |
| C. Side by side in today's landscape | 240x160 at 1:1 | exact | no platform change at all, but each is 36 mm wide |

A is the one that feels like a DS; C is the cheap first step that proves the model. The rest of this page assumes A, with the world still 240x160 (`PPU_W`/`PPU_H` stay: they are in every line buffer of `src/ppu.c`). Text and shapes of each screen are drawn straight at 320x213, not at 480x320 and shrunk.

## How it is built

1. **One PPU per screen, by name.** `ppu_state PPU` is a global (`src/ppu.h`); `src/ppu.c` says `PPU.` in every line. Make it `ppu_state ppu_ctx[2]; ppu_state *ppu_cur;` with `#define PPU (*ppu_cur)`: `ppu.c` and the 50 uses in `lua_game.c` then need no edit, and `screen(n)` is `ppu_cur = &ppu_ctx[n - 1]`. Single-screen games never switch it.
2. **State that lives beside the PPU must follow it.** `lua_game.c` keeps per-frame tables the PPU points into (`line_scroll_tab`, `line_affine_tab`, `line_win_tab`, `line_back_tab`, `line_pal_tab`, `line_ev_tab`, lines 174-179), `layer[n].mx7_on`, `blank` and `backdrop`, and `G.world`. Each becomes a two-element array, or goes into one struct that is switched with the PPU.
3. **One overlay list per screen.** `_draw`'s drawing calls are recorded and replayed by `v2_draw` (`draw_overlay`); there is one list. Two lists, chosen by `screen()`.
4. **Render.** `v2_draw_world` calls `ppu_render` for each screen into its own `G.world`; `v2_draw` upscales each (x4/3 in place of `gfx_upscale2x`), replays its overlay, and puts both into the panel's buffer.
5. **Output size.** `game_render(uint16_t *native)` fills 480x320. A dual game fills 320x480; the platform needs `game_screen_size(&w, &h)`. SDL, the web player and libretro take it as a window or a core geometry; the null platform's frame and `--script`'s `shot` follow it.
6. **Touch.** The bottom screen's rectangle is a known offset; a touch there becomes screen-local (`(x - ox) * 3 / 4`, scaled to the overlay's pixels); a touch on the top screen is dropped (the DS's top screen was not a touch screen). `hal_input` is untouched: the mapping is in `game_tick`, where `G.in.px/py` are set today (`src/game.c:195-199`).
7. **Firmware last.** The board draws in strips into a turned panel (`platform/null/main.c:71` mimics it); a dual game would draw into an unturned one, which should be simpler, but cannot be tried without the board.

## Order of work

1. **Built (`screens` in game.json, `screen(n)`, `tests/dual.script`).** Layout C on SDL and headless: `screens` in `game.json`, `screen(n)`, the PPU context, two world buffers, `shot` of both. Proves 1-4 with no platform change.
2. Layout A and the size query, in SDL, web and libretro.
3. Touch mapping and `pen()` in screen-local pixels, with `tests/*.script` (`tap`, `drag` already exist) on the bottom screen and a tap on the top one that does nothing.
4. **Built:** `examples/dos_pantallas` (a close view above, the touch map and `lib/pointer.lua` below).
5. Firmware, with the board in hand.

## What it costs

- Memory: a second `G.world` is 240x160x2 = 77 KB and a second `ppu_state` a few tens of KB; the board has 8 MB of PSRAM. The 3 MB of canvases stays shared.
- Time: the PPU runs twice a frame. `docs/measurements.md` and `firmware/main/bench_ppu.c` give today's per-frame cost; if one world takes more than half the 16.6 ms, a dual game cannot hold 60 fps and the design needs a 30 fps mode.

## To check before building

- `ppu_blank`/`blank` and the `draw_covers_screen()` shortcut in `v2_draw` are per world: read their callers.
- Every `SCREEN_W` / `SCREEN_H` in `src/` (33 uses in `ui.c`, 19 in `arena.c`...) belongs to the built-in adventure runtime (`v2` is Lua games): a dual game should not run it; confirm it is `G.v2`-only.
- `lib/kit.lua`, `lib/views.lua` and `lib/hud.lua` assume 480x320 or 240x160; they would draw on one screen only.
- The splash (the engine's careta) and the error overlay draw at 480x320: in dual mode they go on the bottom screen.
- Whether `ppu_render` is called from anywhere besides `lua_game.c` that would see the wrong `PPU` (`firmware/main/bench_ppu.c` calls it directly).
- The 4/3 scaler's cost on the ESP32-S3 against `gfx_upscale2x`'s fast path (`src/game.c:region_cut` keeps even edges for it).

## What step 1 did differently from the plan above

- The overlay is not two lists: `screen(n)` sets the existing camera and clip to that screen's rectangle (`draw_set_view` in `lua_draw.c`), so text and shapes of a screen are drawn from its corner and cut at its edge. `camera()`, `clip()` and `target()` keep to it.
- What the plan called "parked state" is `parked_screen` in `lua_game.c`: the layers' maps and the per-line tables, copied in and out by `screen()` (about 31 KB each way); the PPU itself is `ppu_ctx[2]`.
- The bottom world is allocated only for a two-screen game (`world2`), so one-screen games cost nothing. `PPU` is now `(*ppu_cur)`: one pointer load more in `ppu.c`; not measured on the board.
- Touch is mapped in `game_tick`; `touch()` in a two-screen game does not halve.
- Not done: the engine's careta of a game with its own `splash.lua`, the adventure runtime (v1), the panel's turned strips (only `gfx_copy1x` is generic; the firmware has not been built), layouts A and B.
