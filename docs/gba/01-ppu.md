# GBA video hardware (PPU) reference digest

Purpose: know exactly how the real Game Boy Advance PPU behaves, so `src/ppu.c` / `src/ppu.h` (np2d's software model) can be audited and improved later.
Written from public sources only (GBATEK, Tonc, mGBA / NanoBoyAdvance source read for understanding, test ROM sources). No Nintendo SDK or AGB manual material was used, and no emulator code was copied (NanoBoyAdvance is GPL, np2d is MIT: facts and behaviours are restated in our own words).

## 0. How to read this file

Confidence tags:

| Tag | Meaning |
|---|---|
| (G) | GBATEK states it. Widely trusted, but GBATEK is sometimes wrong or vague on edge cases. |
| (T) | Tonc states it (author tested on hardware for many items). |
| (mGBA) / (NBA) | The behaviour is implemented by that emulator. Both projects are hardware-tested, but "implemented" is not "proven". |
| (both) | mGBA and NBA agree, independently written: treat as likely hardware truth. |
| unverified | Single weak source, an emulator TODO, or two sources disagree. Test on hardware or with a test ROM before relying on it. |

Source tooling note: coranac.com did not resolve from the research sandbox; Tonc was read from its mirror at gbadev.net/tonc (same chapters).

Primary sources (full list repeated at the end of each section as needed):

- GBATEK: https://problemkaputt.de/gbatek.htm (anchors `#gbalcdvideocontroller`, `#lcdiodisplaycontrol`, ... `#lcddimensionsandtimings`, `#gbamemorymap`, `#gbaunpredictablethings`)
- Tonc: https://gbadev.net/tonc/ (video, regbg, affbg, regobj, affobj, gfx, dma, mode7, mode7ex)
- mGBA renderer: https://github.com/mgba-emu/mgba/tree/master/src/gba/renderers (video-software.c, software-obj.c, software-bg.c, software-mode0.c, software-private.h, common.c) and include/mgba/internal/gba/video.h
- mGBA test ROMs: https://github.com/mgba-emu/suite/blob/master/src/video.c
- NanoBoyAdvance: https://github.com/nba-emu/NanoBoyAdvance (src/nba/src/hw/ppu/*.cc, *.inl, *.hh, and CHANGELOG)
- jsmolka/gba-tests: https://github.com/jsmolka/gba-tests (ppu/ folder)

---

## 1. Timing and display

| Item | Value | Src |
|---|---|---|
| System clock | 16.777216 MHz (16*1024*1024), 1 cycle ~59.59 ns | (G) |
| Dot | 4 CPU cycles | (G)(T) |
| Visible line | 240 dots = 960 cycles | (G) |
| HBlank | 68 dots = 272 cycles | (G) |
| Scanline total | 308 dots = 1232 cycles (~13.62 kHz) | (G) |
| Visible lines | 160 lines = 197,120 cycles | (G) |
| VBlank | 68 lines = 83,776 cycles | (G) |
| Frame | 228 lines = 280,896 cycles = 59.7275 Hz | (G)(T) |
| VCOUNT | 0..227, increments at line start; 160..227 are "hidden" lines | (G) |

DISPSTAT (0400:0004) and VCOUNT (0400:0006):

| Bit | Meaning |
|---|---|
| 0 | VBlank flag, set on lines 160..226 (clear on 227) (G) |
| 1 | HBlank flag, toggles on all 228 lines, including VBlank lines (G) |
| 2 | VCount-match flag (R) |
| 3 / 4 / 5 | VBlank IRQ / HBlank IRQ / VCount IRQ enable |
| 8-15 | LYC (VCount setting) |

- The HBlank flag is 0 for about 1006 cycles, not 960: the line's "draw" part ends later than the 240 visible dots (G). Emulators schedule the flag at cycle 1006 (NBA code, 1007 after +1) or 1008 (mGBA `VIDEO_HDRAW_LENGTH`, with an IRQ fudge of -6). The exact cycle is unverified; 1006..1008 is the range.
- HBlank DMA triggers only on visible lines 0..159 (Tonc: "HDMA fires only on visible-scanline HBlanks"; NBA requests it only in the visible-line path). HBlank IRQ in VBlank lines: GBATEK contradicts itself (DISPSTAT text: HBlank conditions are generated on every line "including the hidden scanlines"; LCD timing text: "no H-Blank interrupts are generated within V-Blank"). NBA raises the HBlank IRQ on VBlank lines too. Unverified.
- NBA delays the HBlank IRQ by 4 cycles after the flag (changelog) and sets the VCount flag 1 cycle after the line starts.
- The first rendered pixel appears some cycles into the line (NBA: BG fetch starts about cycle 32 for affine/bitmap, ~36 for text; merge output starts at cycle 46; changelog "delay scanline rendering by 32 cycles"). Unverified as exact hardware numbers; relevant only for mid-line register writes.
- Reset values measured on a 3DS in GBA mode (via NBA): VCOUNT=225, DISPSTAT=3 (VBlank+HBlank) (NBA comment).
- Forced blank (DISPCNT bit 7): LCD shows white lines; VRAM/palette/OAM become freely accessible (G). When cleared during the visible period, "the display begins after two vertical lines" (G, wording unclear). mGBA forum notes a one-frame blank is not emulated after enabling rendering (Pokemon Pinball artefact): unverified.
- Upper ~8 lines of the real LCD are shadowed on a lit-from-front AGB-001; irrelevant to a software model (G).

Sources: https://problemkaputt.de/gbatek.htm#lcddimensionsandtimings , #lcdiointerruptsandstatus ; https://gbadev.net/tonc/video.html ; NBA ppu.cc / merge.cc ; mGBA video.h (`VIDEO_HDRAW_LENGTH`).

---

## 2. Registers (video)

### DISPCNT 0400:0000 (R/W)

| Bit | Meaning |
|---|---|
| 0-2 | BG mode 0-5 (6,7 prohibited; NBA draws no BGs for 6/7) |
| 3 | CGB mode flag (BIOS only) |
| 4 | Frame select (modes 4 and 5 only): frame 0 at 0600:0000, frame 1 at 0600:A000 |
| 5 | HBlank interval free: OAM accessible during HBlank, at the price of fewer sprite cycles (954 instead of 1210) |
| 6 | OBJ tile mapping: 0 = 2D (32x32 tile matrix), 1 = 1D |
| 7 | Forced blank |
| 8-11 | BG0..BG3 enable |
| 12 | OBJ enable |
| 13 / 14 / 15 | WIN0 / WIN1 / OBJ-window enable |

Undocumented 0400:0002 bit 0 "green swap": swaps the green channel of each horizontal pixel pair (x even/odd) in the final output (G; NBA implements it). Irrelevant for np2d except as a curiosity.

### BG control, BGxCNT 0400:0008 + 2x

| Bit | Meaning |
|---|---|
| 0-1 | Priority 0 (front) .. 3 |
| 2-3 | Character base block, 16 KB units (0..3) |
| 6 | Mosaic enable |
| 7 | Palette mode: 0 = 4bpp 16x16, 1 = 8bpp 256x1 |
| 8-12 | Screen base block, 2 KB units (0..31) |
| 13 | BG2/BG3 only: area overflow, 0 = transparent outside, 1 = wrap. Unused on BG0/1 |
| 14-15 | Screen size 0..3 |

### Other video registers

| Reg | Address | Notes |
|---|---|---|
| BGxHOFS/VOFS | 0400:0010 + 4x (+2) | Write-only, 9 bits (0..511). Text BGs only |
| BG2/3 PA PB PC PD | 0400:0020..26, 0400:0030..36 | s16, 8.8 fixed point. Write-only |
| BG2/3 X, Y | 0400:0028/2C, 0400:0038/3C | 28-bit signed (19-bit integer + sign, 8-bit fraction), write-only; bits 28-31 ignored |
| WIN0H/WIN1H | 0400:0040/42 | low byte X2 (exclusive right), high byte X1 |
| WIN0V/WIN1V | 0400:0044/46 | low byte Y2 (exclusive bottom), high byte Y1 |
| WININ | 0400:0048 | bits 0-3 WIN0 BGs, 4 OBJ, 5 effects; bits 8-13 same for WIN1 |
| WINOUT | 0400:004A | bits 0-5 outside; bits 8-13 inside the OBJ window |
| MOSAIC | 0400:004C | write-only; 4 nibbles: BG H, BG V, OBJ H, OBJ V, each = size-1 (0..15) |
| BLDCNT | 0400:0050 | bits 0-5 first targets (BG0-3, OBJ, BD), 6-7 effect (0 none, 1 alpha, 2 brighten, 3 darken), 8-13 second targets |
| BLDALPHA | 0400:0052 | EVA bits 0-4, EVB bits 8-12; 0..16 meaningful, 17..31 act as 16 |
| BLDY | 0400:0054 | EVY bits 0-4, write-only; 17..31 act as 16 |

Sources: https://problemkaputt.de/gbatek.htm#lcdiodisplaycontrol .. #lcdiocolorspecialeffects ; https://gbadev.net/tonc/regbg.html ; https://gbadev.net/tonc/gfx.html

---

## 3. Display modes 0-5

| Mode | BG0 | BG1 | BG2 | BG3 | Notes |
|---|---|---|---|---|---|
| 0 | text | text | text | text | 4 text layers |
| 1 | text | text | affine | - | BG3 unavailable |
| 2 | - | - | affine | affine | BG0/BG1 unavailable |
| 3 | - | - | bitmap 240x160, 15-bit direct colour | - | 1 frame, 480 bytes/line, 0600:0000..0601:2BFF (75 KB used of 80) |
| 4 | - | - | bitmap 240x160, 8-bit palette index | - | 2 frames, 240 bytes/line, 0x9600 bytes each: frame 0 at 0600:0000, frame 1 at 0600:A000 |
| 5 | - | - | bitmap 160x128, 15-bit direct colour | - | 2 frames, 320 bytes/line, 0xA000 bytes each (0600:0000 and 0600:A000) |

Mode facts:

- OBJ layer exists in all modes. Sprite tile VRAM: 0601:0000..0601:7FFF (32 KB) in modes 0-2, only 0601:4000..0601:7FFF (16 KB) in modes 3-5; there sprite tile numbers 0..511 are not drawn (G)(T)(both).
- Bitmap modes are BG2 with the BG2 affine matrix (PA..PD, X, Y) applied, so they can be scaled/rotated (G "Rot/Scal: Yes"). Out-of-bitmap is always transparent: the BGxCNT overflow bit is ignored in modes 3-5 (G). BG2CNT priority and mosaic bits do apply.
- Mode 3 and Mode 5: every in-bounds pixel is opaque (no transparent colour). Mode 4: palette index 0 is transparent, so sprites/backdrop show through (G).
- Mode 5 outside the 160x128 rectangle shows the backdrop (or lower layers).
- Page flip: DISPCNT bit 4 selects frame (modes 4 and 5). The change is effective from the next fetch; games flip in VBlank. Mode 3 has no second page.
- Mode 4 frame 1 base is 0600:A000 (not 0600:9600).
- BG enable bits for BGs not present in the mode have no effect (NBA: `k_min_max_bg`).
- Mid-frame mode changes: "tend to take effect on the very next scanline" (mGBA blog, Rayman 3 changes mode between scanlines). Tonc's Mode 7 demo switches DISPCNT mode at the horizon line (mode 0 sky, mode 1 floor).
- Invalid modes 6/7: NBA renders nothing from BGs (handles them explicitly). Unverified on hardware beyond that.

Sources: https://problemkaputt.de/gbatek.htm#lcdiodisplaycontrol , #lcdvramoverview , #lcdvrambitmapbgmodes ; https://gbadev.net/tonc/mode7.html ; https://mgba.io/2017/05/29/holy-grail-bugs/ ; NBA background.cc / background.inl (`RenderMode3BG..5BG`, bounds checks).

---

## 4. Memory layout and access rules

### Layout

| Region | Address | Size | Notes |
|---|---|---|---|
| Palette RAM | 0500:0000 | 1 KB | BG palette 0500:0000..01FF (256 colours), OBJ palette 0500:0200..03FF |
| VRAM | 0600:0000 | 96 KB (0..0x17FFF) | Repeats every 128 KB: 0x18000..0x1FFFF mirrors 0x10000..0x17FFF (G) |
| OAM | 0700:0000 | 1 KB | 128 x 8-byte slots: 3 attribute halfwords + 1 affine-parameter halfword |

- Palette colour: 16 bits, `0bbbbbgggggrrrrr` (bit 15 unused). Index 0 of every 16-colour bank and of the 256-colour palette is transparent for tiles/sprites; BG palette entry 0 is the backdrop colour (G).
- Modes 0-2 VRAM: 0..0xFFFF shared by BG tiles (charblocks 0-3, 16 KB each) and BG maps (screenblocks 0-31, 2 KB each: screenblock n overlaps charblock n/8); 0x10000..0x17FFF sprite tiles (G)(T).
- Tile sizes: 4bpp = 32 bytes, 8bpp = 64 bytes. BG tile numbers step in tile units of that size; sprite tile numbers always step in 32-byte units, so an 8bpp sprite uses every second number (T)(G).

### CPU access rules

- VRAM/palette/OAM accessible freely only in VBlank, in HBlank (OAM only if DISPCNT bit 5 is set), or in forced blank (G). At any other time the CPU is not blocked: one wait cycle is added if the PPU used that memory in the same cycle, and data is not lost (G; NBA models it per-fetch with `DidAccess*` stalls).
- Bus: palette/VRAM 16-bit (32-bit access = 2 cycles), OAM 32-bit bus (1 cycle). +1 cycle on collision with the PPU (G).
- 8-bit writes (STRB) (G "Unpredictable Things", NBA):
  - Palette RAM and BG-area VRAM: the byte is written to both halves of the aligned halfword (`value * 0x0101`).
  - OBJ-area VRAM (0601:0000.. in modes 0-2, 0601:4000.. in modes 3-5) and OAM: the write is ignored.
  - The BG/OBJ VRAM boundary used for this depends on the current BG mode (0x10000 vs 0x14000) (NBA `GetSpriteVRAMBoundary`).
- 8-bit reads work normally.
- VRAM mirroring: 0x18000..0x1FFFF mirrors 0x10000..0x17FFF. NBA changelog: in bitmap modes the mirror at 0600:18000 is disabled for the part that would alias the bitmap area (accesses that would land below 0x14000 are ignored/return 0).
- Invalid text-BG tile numbers (tile data address beyond the 64 KB BG area): BG fetches past the BG boundary return the last data the PPU latched, which is the map entry just fetched, so the tile displays "as if its character data were the 16-bit map entry value" (vertical stripes) (G). With several BGs enabled the result mixes data from other layers (G: "much more complicated"). NBA models this with `vram_bg_latch`. On NDS-in-GBA-mode it is all zeros instead.
- Sprite tile fetches that point below the OBJ boundary in bitmap modes read 0 in NBA (tiles 0-511 not displayed) (G says "ignored (not displayed)").
- OAM contents at power-on are undefined. A zeroed OAM entry is NOT invisible: it is an 8x8 sprite at (0,0) with tile 0 (T). Hide unused entries with attr0 bit 9 set (regular, non-affine).

Sources: https://problemkaputt.de/gbatek.htm#gbamemorymap , #gbaunpredictablethings , #lcdvramoverview , #lcdcolorpalettes ; https://gbadev.net/tonc/regobj.html ; NBA ppu.hh (`WritePRAM`, `WriteVRAM`, `FetchVRAM_BG`, `ReadVRAM_OBJ`).

---

## 5. Text backgrounds (modes 0 and 1: BG0/BG1; mode 0: also BG2/BG3)

Screen entry (16-bit, in the map):

| Bits | Meaning |
|---|---|
| 0-9 | tile number (0..1023) |
| 10 | horizontal flip |
| 11 | vertical flip |
| 12-15 | palette bank (4bpp only; ignored in 8bpp) |

Map sizes (BGxCNT bits 14-15):

| Size | Pixels | Tiles | Layout of 32x32 screenblocks (SC at base + n*0x800) |
|---|---|---|---|
| 0 | 256x256 | 32x32 | SC0 |
| 1 | 512x256 | 64x32 | SC0 SC1 side by side |
| 2 | 256x512 | 32x64 | SC0 over SC1 |
| 3 | 512x512 | 64x64 | SC0 SC1 / SC2 SC3 |

- Always wraps; scroll values are 9 bits (0..511) and the effective offset wraps modulo the map size (T).
- Scroll register semantics: HOFS/VOFS give the map coordinate shown at the screen's top-left (q = p - offset), so increasing scrolls the picture left/up (T).
- 4bpp tile data: each byte = 2 pixels, low nibble = LEFT pixel, high nibble = right (G). 8bpp: one byte per pixel.
- 4bpp: colour = palette[bank*16 + index], index 0 transparent. 8bpp: palette[index], 0 transparent.
- Flip: H flip reverses the 8 pixels of the tile; V flip reverses its rows. For 4bpp H flip also swaps the nibbles (NBA does this in its fetch pipeline).
- Maximum addressable tiles are limited by VRAM: 4bpp up to 1024, 8bpp 1024 numbers but only ~1023 minus map space (G).
- Text BG scrolling registers are ignored in modes 3-5 and for affine layers; those use the reference-point registers (G).
- Priority among BGs: lower BGxCNT priority number is in front. Same priority: lower BG number (BG0) in front (G).
- BG tile data cannot be fetched from the OBJ VRAM region on hardware, even if the numbers point there (T; see invalid tile numbers above).

Sources: https://problemkaputt.de/gbatek.htm#lcdiobgcontrol , #lcdvrambgscreendataformatbgmap , #lcdvramcharacterdata ; https://gbadev.net/tonc/regbg.html ; NBA background.inl (`RenderMode0BG`).

---

## 6. Affine backgrounds (BG2 in modes 1/2, BG3 in mode 2) and bitmap transform

Sizes (BGxCNT bits 14-15; one flat map, 1 byte per entry, tile number 0..255, no flip, no palette bank, 8bpp tiles only):

| Size | Pixels | Tiles | Map bytes |
|---|---|---|---|
| 0 | 128x128 | 16x16 | 0x100 |
| 1 | 256x256 | 32x32 | 0x400 |
| 2 | 512x512 | 64x64 | 0x1000 |
| 3 | 1024x1024 | 128x128 | 0x4000 |

Per-pixel rule (8.8 fixed point, floor shift):

```
screen (x, y), line start point (X_y, Y_y) = internal reference registers
tex_x = (X_y + PA*x) >> 8        tex_y = (Y_y + PC*x) >> 8
next line:  X_{y+1} = X_y + PB     Y_{y+1} = Y_y + PD
```

- Out of range [0, size): BGxCNT bit 13 = 1 wraps (coordinates AND (size-1)); 0 = transparent (G)(T)(both). Bit 13 is ignored in bitmap modes (always transparent outside).
- Tiles are 8bpp from the BG's character base; maps are read byte-wise (NBA `RenderMode2BG`).
- Registers are 20.8-ish: 28-bit signed. PA..PD are s16 8.8.

Reference point latching (important for per-line tricks):

- The internal X/Y registers are reloaded from BGxX/BGxY at the start of the frame (line 0), and after every line they increase by PB/PD (G).
- Writing BGxX/BGxY outside VBlank copies the value into the internal register immediately (G); in practice the new value becomes the origin of the NEXT line when written in HBlank. NBA models it as: a write sets a "written" flag and the internal register is reloaded at the start of the next scanline (changelog: "latch BGX/Y writes at the beginning of each scanline"). Tonc: an HBlank ISR writing BGxY treats the next line as the origin line; the vertical offset (+h) is then NOT automatically added, so compensate (y_s = y_s0 - h) (T).
- After such a write, lines continue accumulating PB/PD from the new value.
- The internal X/Y do not advance while the BG is disabled in the latched DISPCNT; NBA says this "was confirmed on real hardware" (NBA code comment).
- Affine mosaic: the vertical advance is applied per mosaic row, see section 11.
- Switching modes mid-frame latches the internal registers specially (NBA changelog: "latch internal affine registers on mode switch"). Unverified details.
- Madden NFL 06/07 writes scaling parameters right before drawing and gets a vertically infinite stretch on hardware; cause unknown, suspected undocumented write block (mGBA blog). Unverified.

Bitmap modes (3, 4, 5) use the same machinery with the bitmap as the "map" (PA = 0x100, PD = 0x100 gives 1:1).

Sources: https://problemkaputt.de/gbatek.htm#lcdiobgrotationscaling ; https://gbadev.net/tonc/affbg.html ; https://gbadev.net/tonc/mode7.html ; NBA background.cc / background.inl ; mGBA software-bg.c / software-private.h.

---

## 7. Sprites (OBJ)

### OAM slot (8 bytes), 128 slots

| Attr | Bits | Meaning |
|---|---|---|
| 0 | 0-7 | Y (0..255); sprite covers lines Y..Y+h-1 modulo 256 |
| 0 | 8 | Affine flag |
| 0 | 9 | affine=0: disable (hidden); affine=1: double-size |
| 0 | 10-11 | Mode: 0 normal, 1 semi-transparent, 2 OBJ window, 3 prohibited |
| 0 | 12 | Mosaic |
| 0 | 13 | 0 = 4bpp, 1 = 8bpp |
| 0 | 14-15 | Shape: 0 square, 1 wide, 2 tall, 3 prohibited |
| 1 | 0-8 | X, 9-bit signed (-256..255) |
| 1 | 9-13 | affine: matrix index 0..31 |
| 1 | 12 / 13 | not affine: H flip / V flip |
| 1 | 14-15 | Size |
| 2 | 0-9 | Tile number (top-left tile) |
| 2 | 10-11 | Priority vs BG (0 = front) |
| 2 | 12-15 | Palette bank (4bpp only) |
| 3 | - | Not an attribute: the 4 affine halfwords of group n live in the "attr3" slots: PA at 0x06+0x20n, PB at 0x0E, PC at 0x16, PD at 0x1E (offset 0x20*n + 0x06 + 8*k) |

- 32 affine groups, shared by any number of sprites. Writing attr3 of an affine-using sprite corrupts the matrix (T).
- Affine parameters are s16 8.8.
- Not-affine + bit 9 set = hidden: not rendered and cheap (T,G). Affine + bit 9 = double size.
- Attribute 0 bits 8-9 "10" (hidden) / "11" (affine double-size) per Tonc's table; mode value 3 and shape value 3 are "prohibited". How hardware renders mode 3 / shape 3 is unverified (NBA skips mode 3, treats shape 3 as 8x8).

### Shape / size table (width x height in pixels)

| Shape \ Size | 0 | 1 | 2 | 3 |
|---|---|---|---|---|
| Square (0) | 8x8 | 16x16 | 32x32 | 64x64 |
| Wide (1) | 16x8 | 32x8 | 32x16 | 64x32 |
| Tall (2) | 8x16 | 8x32 | 16x32 | 32x64 |

Double-size affine: bounding box = 2x in both directions (16x16 .. 128x128), centred on the same point.

### Regular vs affine vs double-size

- Regular: pixels copied, H/V flip via attr1 bits 12-13. Box = w x h. Reference point = top-left (X, Y).
- Affine: box = w x h; the sprite is transformed around its centre; texture pixels mapped outside the box are clipped (the "clipping artifact"). Per screen pixel (ix, iy measured from the box centre): `tex = P * (ix, iy) + (w/2, h/2)` in 8.8, floor shift, then bounds-checked against the sprite size (outside = transparent) (T)(both). The pivot is a whole texel (the centre pixel, rounded up), not the geometric centre, which gives a half-pixel/1-pixel wobble (T).
- Double-size: box = 2w x 2h, same formula with (ix, iy) running over the doubled box and the centre at (w, h) screen offset. Rotated corners stay visible (a 90-degree rotation of an 8x32 still clips) (G)(T).
- No flips for affine sprites; flipping = negative matrix entries (T).
- Degenerate matrices: an all-zero matrix gives a uniform colour (every screen pixel samples the same texel: the centre) (T; mGBA suite has "Degenerate OBJ transforms"). Unverified beyond that.

### Position wrap and clipping

- X: 9-bit signed, -256..255, wraps. Sprites at X >= 240 are off the right edge or, with X-512 + width > 0, wrap in from the left.
- Y: 8 bits, covers Y..Y+h-1 mod 256. A sprite with Y > 255-h+1 wraps onto the top lines (T). Exception (G, "negative precedence"): a 128-pixel-tall double-size sprite (a 64-tall one with the double flag, bounding 128) whose Y + 128 > 256 is treated as Y-256, so it shows at the top and NOT again at the bottom (T agrees, "VBA uses positive precedence, which is incorrect"). mGBA: `if (y + height > 256) y -= 256`.
- Hardware clips the left edge in pairs of pixels for regular sprites (NBA: clip & ~1 for non-affine): unverified detail, mostly a timing matter.

### Tile mapping

- 2D mapping (DISPCNT bit 6 = 0): the OBJ tile area is a 32x32 tile matrix (256x256 px; for 8bpp tiles it counts as 16 wide in 64-byte tiles). Row stride is +0x20 in tile numbers. A 16x16 4bpp sprite at tile 04: row 0 = tiles 04,05; row 1 = tiles 24,25 (G). 8bpp: 04,06 / 24,26 (the low tile-number bit is ignored in 2D 8bpp mode).
- Tile numbers wrap independently within the row (column & 0x1F) and within the matrix (row & 0x1F): a 16x8 sprite at tile 63 takes its right half from tile 32, not 64 (mGBA issue #2443, NBA changelog "2D OBJs should wraparound horizontally") (both).
- 1D mapping (bit 6 = 1): tiles consecutive; row stride = width/8 tiles (4bpp) or width/4 tile numbers (8bpp). Tile number arithmetic wraps at 1024 (NBA `& 0x3FF`).
- 8bpp sprites: only even tile numbers meaningful; in 2D mode bit 0 is ignored, in 1D mode mGBA does not mask it (mGBA `align`), NBA likewise does not (unverified for 1D odd numbers).
- Bitmap modes: sprite tile numbers < 512 not displayed.

### OBJ window sprites

- Mode 2 sprites are not drawn; their non-transparent pixels define the OBJ-window mask. Colour, palette, priority of such sprites are ignored for drawing (G). Needs DISPCNT bits 12 AND 15 (G). They still use sprite cycles. Per NBA, transparent pixels of OBJ-window sprites still update the pixel's priority/mosaic attributes (priority hijack, section 8).
- Mosaic does not apply to OBJ-window sprites (NBA: `mosaic = flag && mode != OBJ_WINDOW`). Unverified on hardware.

Sources: https://problemkaputt.de/gbatek.htm#lcdobjoverview , #lcdobjoamattributes , #lcdobjoamrotationscalingparameters , #lcdobjvramcharactertilemapping ; https://gbadev.net/tonc/regobj.html , https://gbadev.net/tonc/affobj.html ; NBA sprite.cc (`DrawSpriteFetchOAM`, `DrawSpriteFetchVRAM`); mGBA software-obj.c, common.c; mGBA issue https://mgba.io/i/2443 (tile 63 wrap); https://github.com/mgba-emu/suite/blob/master/src/video.c

---

## 8. Sprite evaluation, the per-scanline cycle budget, and ordering

### Timeline

- Sprites for line N are evaluated and drawn during line N-1 ("one scanline ahead", NBA changelog "render sprites one scanline ahead"). Line 0 sprites are prepared during line 227. The engine does not run during VBlank lines 160..226 (NBA). Consequence: OAM changes need to land before line N-1, and mGBA's suite has an "OAM Update Delay" test for exactly this.
- DISPCNT bit 12 is checked per fetch cycle (NBA `// @todo: research how real HW handles the OBJ layer enable bit`); unverified.

### Budget (G, confirmed in spirit by both emulators)

Available OBJ cycles per line:

| DISPCNT bit 5 (HBlank free) | GBATEK | mGBA constant | NBA limit |
|---|---|---|---|
| 0 | 1210 (= 304*4 - 6) | 1210 | 1232 cycles |
| 1 | 954 (= 240*4 - 6) | 954 | 964 cycles |

Cost per sprite (GBATEK; n = box width in pixels):

| Sprite | Cycles |
|---|---|
| Regular | n (8..64) |
| Affine, 8..64 box | 10 + 2n |
| Affine double-size (box 16..128) | 10 + 2n where n is the doubled width |

Finer model (mGBA `CleanOAM` + `PreprocessSpriteLayer`; NBA sprite.cc is consistent):

- Every OAM slot the evaluator steps over costs 2 cycles, even disabled ones, so 128 slots cost at least 256 cycles of the 1210 (mGBA subtracts `2 * (index - lastIndex)`; NBA's fetch is one OAM step per 2 cycles).
- A sprite that is on the line adds: regular `width - 2` (so slot + body = `width`), affine `8 + 2*boxWidth` (so with the 2 for the slot, 10 + 2n). Matches GBATEK.
- Sprites that are partly off the left edge cost less (mGBA: regular `cycles += x >> 1` for negative x; affine `cycles += x`). Sprites completely off the left, and (mGBA) sprites completely off the right (X >= 240 with X + width < 512), cost only their 2-cycle slot step. This partly contradicts GBATEK's caution that offscreen sprites "consume budget"; the caution is about the on-line, visible-Y case. Unverified in detail.
- Sprites not on this line cost only the 2-cycle slot step (mGBA, NBA). GBATEK asks "does the above also apply to vertically offscreen sprites?": answer from both emulators: no, only the slot step.
- Typical numbers (mGBA model): 128 regular 8x8 sprites = 1024 cycles, all drawn with HBlank-free off; with HBlank-free on (954) not all fit. Roughly 19 contiguous 64-wide regular sprites fit (19*64 = 1216 but the check is "remaining > 0 before starting a sprite"). Affine 64x64 double-size (128 box) costs 266.

### What is dropped when exceeded

- Sprites are processed in OAM order (index 0 first). When the budget runs out, all higher-index sprites on that line are not drawn.
- Granularity differs: mGBA stops BEFORE starting a sprite that finds the budget <= 0 (the sprite that crosses the limit is still drawn whole). NBA runs the limit at cycle granularity and can truncate a sprite part-way (the draw loop stops at the cycle limit). The hardware behaviour is unverified; NBA's changelog notes it once applied the limit "only on OAM boundaries for now".
- Hidden sprite order matters: put visible sprites first in OAM, or make hidden ones cheap (8x8, non-affine) (G).

### Sprite-vs-sprite priority

- Per screen pixel: the sprite with the lowest priority value (attr2 bits 10-11) wins; ties resolved by lowest OAM index (G)(T). Implemented by drawing in OAM order and replacing only when the new priority is strictly lower (both).
- Only the topmost OBJ pixel takes part in blending: no OBJ-to-OBJ alpha (G).

### OBJ priority hijacking (both emulators; NBA changelog "handle OBJ priority hijacking")

- While building the OBJ line buffer, even a TRANSPARENT pixel of a sprite with a lower priority value than the pixel currently stored overwrites the stored priority (and mosaic flag), while the stored colour stays. Example: sprite A (OAM 0, priority 2, opaque) then sprite B (OAM 5, priority 1, transparent here): the pixel keeps A's colour but is now compared against BGs as priority 1. Same applies to transparent pixels of OBJ-window sprites. The semi-transparent flag stays with the sprite that supplied the colour (NBA `Plot`).

### Sprite-vs-BG priority

- OBJ priority value <= BG priority value puts the OBJ in front (ties go to the sprite) (G)(both). Order front to back: for p in 0..3: sprites of priority p (OAM order), then BG0..BG3 of priority p; then backdrop.
- BGs among themselves: lower priority number, then lower BG index.
- GBATEK's warning: do not give OBJ 0 a lower BG-priority than OBJ 1-127 (garbage) - this is the hijack effect.

Sources: https://problemkaputt.de/gbatek.htm#lcdobjoverview ; mGBA common.c (`GBAVideoRendererCleanOAM`), video-software.c (`PreprocessSpriteLayer`), video.h (`OBJ_LENGTH`, `OBJ_HBLANK_FREE_LENGTH`); NBA sprite.cc (`InitSprite`, `DrawSpriteImpl`, `Plot`), CHANGELOG ("Handle OBJ priority hijacking", "Respect per-scanline cycle limit"); https://devkitpro.org/viewtopic.php?p=16492 (forum quoting GBATEK on budget).

---

## 9. Layer compositing and windows

### Final pixel pipeline (both emulators, matches GBATEK)

1. Per pixel, determine the window region (if any window enabled), giving a 6-bit enable mask (BG0-3, OBJ, effects).
2. Collect candidate layers that are enabled by DISPCNT and by the window mask and non-transparent there. Sort by priority (above). Top = first pixel, next = second pixel (needed for blending); a layer disabled by the window does not count as a second target.
3. Apply the effect (section 10) if the pixel's region has the effects bit set.
4. Output 15-bit colour.

### Windows

| Rule | Detail | Src |
|---|---|---|
| Enable | DISPCNT 13/14/15. If NONE of the three is set, windowing is off and all layers/effects show everywhere. If any is set, "outside" (WINOUT low byte) applies to pixels in no window | (G) |
| Priority | WIN0 > WIN1 > OBJ window > outside | (G)(T)(both) |
| Layer enables | A layer shows only if both DISPCNT and the region's mask enable it | (G) |
| OBJ window | requires OBJ enable (bit 12) and bit 15; region = opaque pixels of mode-2 sprites; uses WINOUT high byte | (G)(NBA) |
| Effects bit | bit 5 of the region's mask enables colour effects (blend/fade) in that region | (G) |
| Semi-transparent OBJ | forced alpha blend ignores the window's effects bit (mGBA, NBA both) when a second target exists; if it has no second target it falls back to the window rules (NBA changelog "respect WININ/WINOUT if Alpha OBJ does not have a blend source") | (both) |
| Windows are not mosaicked | window masks are screen-space | (NBA structure) |

Window rectangle semantics (edge cases, sources disagree - unverified):

- Normal: X in [X1, X2), Y in [Y1, Y2). X2/Y2 are exclusive.
- GBATEK: garbage "X2 > 240 or X1 > X2" is read as X2 = 240; same for Y with 160.
- Tonc (hardware-tested): if X2 < X1 the window wraps (covers [0, X2) and [X1, 240)); if both horizontal and vertical wrap, a cross shape. mGBA splits wrapped windows into two spans this way; NBA also lets it wrap. So GBATEK's "X2 = 240" statement looks wrong for X1 > X2 (conflict: verify with a test ROM).
- Horizontal: NBA models it per dot with a flag that sets at x == X1 and clears at x == X2 (no clamping), and the flag is not reset at line start (unverified). Consequence: X2 > 240 never clears the flag and it leaks into the next line from x = 0.
- Vertical: NBA/mGBA model Y with a latch: set on the line where VCOUNT == Y1, cleared on the line where VCOUNT == Y2, evaluated per line including VBlank lines (so values 160..227 act in the hidden lines).
- Tonc hardware notes (T): if Y1 is in 227..255 (i.e. -29..0) the window is not rendered; if Y2 is in that range the window covers the full screen height (given Y1 < Y2); a window whose bottom moves from 161 to 160 can cover the whole width for about one frame. mGBA test "Window offscreen reset" (WIN0V = 0x50E3, WIN1V = 0x50E4 with an off-screen Y2 must equal Y2 = 0xA0) and mGBA code (`win->on = false` if Y2 in [160, 228); `win->on = true` if Y1 in [160, 228) and Y1 > Y2) encode this.
- Initial state after reset: NBA changelog "properly initialise WIN0/1 state after reset" - hardware state at reset unverified.
- WININ/WINOUT bits 6-7 and 14-15 unused.

Sources: https://problemkaputt.de/gbatek.htm#lcdiowindowfeature ; https://gbadev.net/tonc/gfx.html ; mGBA video-software.c (`_breakWindow`, `StepWindow`, `PrepareWindow`); NBA window.cc, merge.cc; https://github.com/mgba-emu/suite/blob/master/src/video.c

---

## 10. Colour effects: alpha, brighten, darken

BLDCNT first target = pixel that is topmost; second target = next-lower non-transparent pixel (backdrop counts as a layer, as BD). Effect types:

| Effect | Formula per channel (0..31) | Notes |
|---|---|---|
| Alpha | `min(31, I1*EVA/16 + I2*EVB/16)` (G) | Applies only if the top pixel is a first target AND the second pixel is a second target; otherwise only the top pixel shows unchanged |
| Brighten | `I + (31 - I) * EVY/16` (G) | first target only |
| Darken | `I - I * EVY/16` (G) | first target only |

- EVA, EVB, EVY are clamped individually to 16 (17..31 behave as 16). EVA + EVB may exceed 16, so results saturate at 31 (no wrap) (G).
- Blend only mixes the OBJ pixel as a first target if that pixel is the topmost; a non-second-target pixel between first and second targets blocks the blend (G).
- All six layers can be selected as both first and second target; then topmost = first, next = second (G).
- Windowed: the effects bit of the region (WININ/WINOUT bit 5) must be set (G, T).

Semi-transparent sprites (OBJ mode 1):

- Always treated as first target, always use alpha mode, regardless of BLDCNT bit 4 and effect bits 6-7 (G).
- If it overlaps a valid second-target pixel, the alpha blend wins and the brighten/darken effect is not applied to either (G). If no second target, behaviour falls back to normal rules including BLDCNT's brighten/darken applied to the OBJ if OBJ is a first target (NBA implements this, G text is consistent).
- Alpha blend works OBJ over BG and BG over OBJ, never OBJ over OBJ (G).
- Mosaic'd and blended: nothing special known.

Rounding and precision - emulators DISAGREE:

| Item | GBATEK/mGBA | NBA (since 1.7) |
|---|---|---|
| Alpha | floor: `(a*EVA + b*EVB) >> 4` | round to nearest: `(a*EVA + b*EVB + 8) >> 4`, using a 6-bit green (bit 15 of the colour word acts as green LSB) |
| Brighten | `I + ((31-I)*EVY) / 16` (mGBA integer division) | `I + (((31-I)*EVY + 8) >> 4)` |
| Darken | `I - (I*EVY)/16` | `I - ((I*EVY + 7) >> 4)` |

- NBA 1.7 changelog: "use the 6-th green channel bit during blending", "round the blending result to the nearest integer". Not described in GBATEK. Verify with a hardware capture before changing np2d's exactness. Differences are at most 1 LSB per channel.

Brightness special cases seen in games:

- Kirby and the Amazing Mirror flash: sprites (Dark Meta Knight and the mirror) ARE brightened together with the scene (mGBA issue; hardware tester agreed) - i.e. brighten/darken applies to sprite pixels that are first targets as expected, including through the window effects bit.
- pokeemerald uses BLDY per line for fade gradients and BLDALPHA 12/7 style blends for the orb effect.

Sources: https://problemkaputt.de/gbatek.htm#lcdiocolorspecialeffects ; https://gbadev.net/tonc/gfx.html ; mGBA video-software.c / software-private.h (`_brighten`, `_compositeBlend*`, `PreprocessSprite` flags) ; NBA merge.cc (`Blend`, `Brighten`, `Darken`), CHANGELOG (v1.7) ; https://mgba.io/i/532 ; https://github.com/pret/pokeemerald/blob/master/src/field_screen_effect.c

---

## 11. Mosaic

Register: MOSAIC (write-only): BG H size, BG V size, OBJ H size, OBJ V size, each field = size-1 (0..15); all zero = effectively off (G).

Which layers: BGs with BGxCNT bit 6; sprites with attr0 bit 12 (not OBJ-window sprites, NBA).

Quirks (mGBA and NBA agree on the grid, written independently):

- The cell grid is anchored to the SCREEN, not to the BG map or the sprite: horizontally to x = 0 (cells at x = 0, S, 2S, ...), vertically to a line counter that starts at line 0 of the frame. The cell's colour is the layer's pixel at the cell's top-left (G "upperleft covered pixel"); to get the centre pixel, offset the layer (G).
- BG, text: every pixel in the cell shows the BG buffer pixel at the cell's left screen column, and the BG row is `line - (line mod Sv)`. If the top-left sample is transparent, the whole cell is transparent for that BG (it does not look for an opaque pixel inside the cell).
- BG, affine: the same, horizontal hold plus the vertical reference point only advances once per mosaic row (the internal X/Y step by Sv*PB / Sv*PD when the line counter wraps) (NBA `AdvanceBGXY`).
- BG vertical counter: increments each line 0..158, compares to the current size and wraps to 0, reset to 0 at the end of line 159, so it restarts every frame. Changing MOSAIC mid-frame therefore gives cells that are not size-aligned (NBA changelog: "more accurate handling of mid-frame vertical mosaic reconfiguration").
- OBJ vertical: sprite row = `max(0, (Y_line - Y_sprite) - counter_y)` where counter_y is the OBJ line counter (same scheme, own size) (NBA); mGBA clamps `mosaicY = y - y % Sv` to the sprite's first/last row. Visible effect: the first mosaic row of a sprite that starts mid-cell is shorter (clamped to the sprite top).
- OBJ horizontal: applied at merge time on the final OBJ-layer pixels, screen-anchored, with a per-line horizontal counter. A held sprite pixel is kept across the cell unless the current pixel has no mosaic flag, the held pixel has no mosaic flag, a pixel with a lower priority value arrives, or the cell restarts (NBA `sprite_pixel_latch`). Affine sprites: mGBA treats mosaic by holding the sampled texel across the cell horizontally.
- Mosaic is applied BEFORE windowing and blending: the held colour is what windows/effects then see (NBA merge order).
- OBJ mosaic V counter has its own register field and own line counter (NBA `obj._counter_y`).
- Emulator history (Tonc, mGBA forum): VBA has mosaic bugs; no$gba disables vertical mosaic; "mosaic on transformed sprites" and "OBJWIN in different BG modes" were long-unimplemented combos in mGBA (older post). Test on hardware.
- pokeemerald battle transition animates MOSAIC with `(counter & 15) * 17` (both H and V nibbles of BG and OBJ) after setting bit 6 on BG1-BG3.

Sources: https://problemkaputt.de/gbatek.htm#lcdiomosaicfunction ; https://gbadev.net/tonc/gfx.html ; NBA background.cc (counter), merge.cc (`mosaic_x`, sprite latch), sprite.cc (`mosaic_y`) ; mGBA software-private.h (`BACKGROUND_BITMAP_INIT`), software-mode0.c, software-obj.c (`SPRITE_MOSAIC_LOOP`) ; https://github.com/pret/pokeemerald/blob/master/src/battle_transition.c

---

## 12. Colour and the LCD

- Stored colour: 15-bit BGR555, 5 bits per channel, bit 15 unused (G). 32,768 colours. There is no 8-bit conversion in hardware; emulators expand 5 to 8 bits as `(c << 3) | (c >> 2)` (NBA `RGB555`).
- The panel (AGB-001, not backlit; SP/Micro/AGS-101 are lit) is very dark and low-contrast: intensities 0..14 look almost black, 15..31 medium to bright (G). Games' palettes are brightened/saturated accordingly. A software model should treat GBA colour as "needs correction": typical emulator correction is gamma ~3-4 into a linear space plus a primaries matrix, then re-gamma (libretro forum, "Real GBA colors"; byuu/higan-style, details unverified - decide a look, do not claim hardware accuracy).
- Slow LCD response: ghosting; some games alternate frames for pseudo-transparency (G mentions that the panel dims alternate scanlines per frame, "interlace"; unverified, depends on model).
- np2d note (from `ppu.h` only): np2d stores RGB565. GBA green has 5 bits, so green gets 1 extra bit when converting (x31 -> x63 by replication or a plain shift). Blend/fade results on 5-bit channels differ by up to 1 LSB from doing the maths on 6-bit green. Not necessarily a problem, but know it is an approximation.

Sources: https://problemkaputt.de/gbatek.htm#lcdcolorpalettes , #lcddimensionsandtimings ; https://forums.libretro.com/t/real-gba-and-ds-phat-colors/1540 ; NBA merge.cc.

---

## 13. Mid-frame register behaviour and per-line (HBlank DMA / IRQ) tricks

### What the hardware does at line boundaries

- Registers are effectively sampled as the PPU fetches: BG scroll/control in text mode when each tile is fetched, affine X/Y at the line start (latched), PA/PC each pixel, BLD*/window per pixel. A write during HBlank (cycle >= ~1006) therefore applies from the next line start; that is how every HBlank effect works.
- BG/OBJ enable bits and forced blank are latched with a delay: enabling a BG takes about three scanlines to appear, disabling takes effect (nearly) immediately. NBA models effective-enable = DISPCNT_now AND DISPCNT_latched_3_lines_ago for BG/OBJ, and forced blank as current OR latched. mGBA models it with `enabled` counters (ENABLED_MAX = 4; 1-2 line start delay; disable has a 2-line tail). mGBA's suite has "Layer toggle 2" for it; Lady Sia re-enables a BG ~3 lines late and flickers in emulators that lack the latch (mGBA blog). Tonc's Mode 7 notes "about three scanlines of garbage" when switching a BG between sky and floor without a mode switch.
- HBlank DMA (DMA timing mode "HBlank") triggers once per visible line (lines 0..159) at the start of HBlank, not in VBlank. Its first transfer happens after line 0 is drawn, so a per-line table is indexed from line+1 and line 0's value must be set manually (pokeemerald and Tonc both do this; Tonc's table keeps one extra entry = entry 0 copied to the end) (T).
- DMA stalls the CPU; interrupt timing can slip (T).
- DMA special timing mode 3 on DMA3 ("video capture") runs on lines 2..161 (NBA); rarely used.
- With HBlank IRQ instead of DMA the ISR must be short and often lives in IWRAM; Mode 7 routines run once per scanline in IWRAM for timing (mGBA blog, Tonc).

### Effects and which registers they write per line

| Trick | Per-line registers | Notes / examples |
|---|---|---|
| Mode 7 floor / perspective plane | BG2PA, BG2PC, BG2X, BG2Y (PB/PD not needed once X/Y are written each line) | Per line zoom lambda = a_y / h, matrix = scale * rotation; write X/Y for the NEXT line; compensate the latch (see section 6). HBlank IRQ in Tonc, HBlank DMA in other games. Horizon: mode switch (DISPCNT mode 0 sky, mode 1 or 2 floor) or BG2CNT swap at the horizon line (Tonc `mode7`, `mode7ex`). Games usually cited: F-Zero Maximum Velocity, Mario Kart Super Circuit (unverified, general knowledge); Mega Man Battle Network 4 runs mode 7 routines in IWRAM (mGBA blog) |
| Distance fog on the floor | BLDALPHA (EVA/EVB) per line (also BLDCNT) | Tonc: value capped at 16 or the register wraps |
| Wavy / water ripple | BGxHOFS (horizontal wave) or BGxVOFS (vertical wave) per line, sine table, moved per frame | pokeemerald title screen and intro: `ScanlineEffect_InitWave` on BG1HOFS / BG1VOFS; battle transition "pattern weave" on BG0HOFS |
| Window shapes: circle, spotlight, flashlight, iris wipes, diamond | WIN0H (x1/x2) per line (WIN0V fixed to the whole height), sometimes WIN1H | Tonc `dma_demo` circular window; pokeemerald battle transitions (`VBlankCB_CircularMask`) and Flash cave effect: `REG_WIN0H` with HBlank DMA, 16-bit halfwords. Cave darkness = outside the window darkened (BLDY / blend) |
| Brightness gradients, fade wipes | BLDY per line (with BLDCNT effect 2/3) | pokeemerald battle transitions write `REG_BLDY` per line |
| Backdrop / palette gradients (sky, sunsets, "raster bars") | palette RAM entry 0 (backdrop) or any palette entry, per line | Needs palette writes in HBlank (allowed). Widely used pattern, not source-verified here (unverified for specific GBA titles) |
| Parallax bands (several scroll speeds in one layer) | BGxHOFS / BGxVOFS per line or per band | Common; same registers as waves |
| Split screens (status bar, split-screen two-player) | BGxCNT, BGxHOFS/VOFS, DISPCNT mode and enables, sometimes whole VRAM bases, at a VCOUNT IRQ or HBlank | Switch mode mid-frame: "takes effect on the next scanline" (Rayman 3 in mGBA blog) |
| Per-line affine for pseudo-3D roads | BG2/BG3 PA..PD and X/Y | Same as Mode 7 |
| Mosaic transitions | MOSAIC (per frame, sometimes per line for wipes) | Frame-level in pokeemerald |
| Sprite multiplexing (more than 128 sprites per frame) | rewrite OAM mid-frame at VCOUNT/HBlank (needs HBlank-free bit or timing in VBlank) | Plausible, no source here (unverified) |
| Per-line affine sprites | OAM affine groups rewritten between lines | Rare; same limitations (OAM only writable in HBlank with bit 5) |

pokeemerald implementation detail (shows how real games structure it): double-buffered per-line table (`gScanlineEffectRegBuffers[2][0x3C0]`), DMA channel 0 in HBlank/repeat mode with destination-reload (or fixed destination), 16- or 32-bit units, source starting at entry 1, line 0 written by hand at VBlank, DMA stopped before reconfiguring.

Sources: https://gbadev.net/tonc/dma.html , https://gbadev.net/tonc/mode7.html , https://gbadev.net/tonc/mode7ex.html ; https://github.com/pret/pokeemerald/blob/master/src/scanline_effect.c , battle_transition.c , field_screen_effect.c , title_screen.c , intro.c ; https://mgba.io/2017/05/29/holy-grail-bugs/ ; NBA ppu.cc (`BeginHBlankVDraw`, `LatchDISPCNT`).

---

## 14. Behaviours games relied on, and what tests cover

Games / test evidence:

| Behaviour | Evidence |
|---|---|
| BG enable bit latch (~3 lines delay on enable) | Lady Sia flicker, Tonc "garbage while switching" (mGBA blog, Tonc mode7ex), mGBA suite "Layer toggle 2" |
| Mid-frame BG mode switch effective next line | Rayman 3, Tonc Mode 7 horizon (mGBA blog) |
| Window Y2 beyond 160 acts as full height to bottom | mGBA suite "Window offscreen reset", Tonc gfx notes |
| Affine sprite with zero matrix shows uniform colour | mGBA suite "Degenerate OBJ transforms", Tonc |
| OAM update delay (sprites are one line ahead) | mGBA suite "OAM Update Delay" |
| 2D sprite tile wrap | mGBA issue #2443 (16x8 sprite at tile 63; right half comes from tile 32) |
| Games that deliberately overflow the sprite cycle limit and rely on later sprites being discarded | Gunstar Super Heroes / Future Heroes status bar: weapon icons drawn beyond the budget must vanish (mGBA issue #1279, fleroviux: "massively exceeding the scanline cycle limit ... expects OBJs beyond that limit to get discarded"; also needs OAM order 0 first) |
| Sprites brightened with the scene | Kirby and the Amazing Mirror flash (mGBA issue #532) |
| OBJ priority hijack | NBA #99, mGBA behaviour |
| Cycle limit per line | NBA #98, GBATEK, Gunstar Super Heroes (above) |
| BGxX/Y latch on write (Mode 7 timing) | NBA #176, Tonc |
| HBlank IRQ timing | NBA #89/#175 |

Test ROMs in the sources:

- mGBA suite video tests (mgba-emu/suite src/video.c): "Basic Mode 3", "Basic Mode 4", "Degenerate OBJ transforms", "Layer toggle", "Layer toggle 2" (BG enable timing), "OAM Update Delay", "Window offscreen reset" (hardware-captured expected images). Also timing/io suites (not video proper).
- jsmolka/gba-tests ppu/ folder: only visual smoke tests (`hello` text in a bitmap-style BG, `shades` 4bpp palette, `stripes` BG0 tiles); useful as sanity checks, not hardware edge cases.
- Tonc demo ROMs (sbb_reg, obj_aff, dma_demo, m7_demo) are practical references; mGBA and NBA issue trackers hold per-game regressions.

Sources: https://github.com/mgba-emu/suite/blob/master/src/video.c ; https://github.com/jsmolka/gba-tests/tree/master/ppu ; https://github.com/nba-emu/NanoBoyAdvance (CHANGELOG) ; https://mgba.io/i/532 (Kirby), https://mgba.io/i/1279 (Gunstar, cycle limit), https://mgba.io/i/2443 (2D wrap).

---

## 15. Things a software PPU commonly gets wrong

Checklist for auditing `src/ppu.c`. Items marked (np2d?) are particularly worth a look against the model's header; none have been audited against the code.

Layer / priority

1. Sprite vs BG priority ties: a sprite with priority p is IN FRONT of BGs with priority p. Front-to-back order per priority level: sprites (OAM 0 first), then BG0..BG3. (np2d's header describes back-to-front drawing "for priority 3 down to 0: backgrounds of that priority, then sprites, sprite 127 under sprite 0", which is the correct order: just confirm `ppu.c` does it that way in every path, including the windowed and blended ones.)
2. Sprite-vs-sprite: lowest priority value first, then lowest OAM index. Not "last drawn wins by index".
3. OBJ priority hijacking: transparent pixels of a higher-priority-value-lower sprite change the stored priority of an opaque pixel below them (both emulators). Most engines skip this.
4. Only the topmost OBJ pixel takes part in blending; OBJ-to-OBJ alpha does not exist.
5. BG2/BG3 priority ties: lower BG number wins.

Sprites

6. Per-line budget: slots cost 2 cycles each even if hidden; affine costs 10 + 2n; partial left-edge reduction; HBlank-free = 954. Sprites in the budget are dropped by OAM order, not by priority.
7. Sprites are evaluated a line ahead; OAM edits during HDraw are not visible until two lines later (only matters if the model exposes mid-frame OAM).
8. 2D tile mapping wraps within the 32-wide row; 8bpp sprites use tile numbers in steps of 2 and ignore bit 0 in 2D mode; 1D 8bpp row stride is width/4.
9. Affine sprites: pivot at a whole texel (centre pixel rounded up), `tex = P*(ix,iy) + (w/2,h/2)`; the screen pixel area is the box (w x h) or double box; no flips; texels outside [0,w) x [0,h) are transparent (no wrap). (np2d? the header says the affine maps "around the sprite's centre (x + w/2, y + h/2)" and "draws within 2w x 2h" - check the half-pixel convention and the vertical-wrap rule below.)
10. Y wrap: a sprite whose Y + height crosses 256 appears at the top; the 128-high double-size special case is "negative precedence" (does NOT also show at the bottom).
11. Sprite size cap: hardware boxes go up to 64x64 (128x128 double). np2d's header allows source size up to 128x128 per sprite, which is a deliberate superset; keep the budget comparison in mind.
12. Sprite tile numbers < 512 in bitmap modes are not drawn; 8-bit writes to OBJ VRAM are ignored (matters only for bit-exact memory emulation).
13. Mosaic + sprites: grid anchored to the screen; OBJ-window sprites are never mosaicked.

Affine BG

14. Sampling is floor of `(ref + PA*x) >> 8` with a per-line reference that advances by PB/PD; out-of-range is transparent unless wrap is set; wrap size is the BG size (power of two), not the screen.
15. The BGxX/BGxY write-in-HBlank latch behaviour (next line takes the new value, no automatic `+h`): a model that re-derives the origin from a per-frame register plus `y*PB` cannot express Mode 7; per-line tables should supply the origin directly, which np2d's `ppu_line_affine` does by taking per-line x/y/pa/pc (good). Remember that real Mode 7 per-line origin is "start of THIS line", and writing in HBlank targets the next line.
16. Bitmap modes are affine BG2: they honour PA..PD/X/Y, outside is transparent, mode 3/5 have no transparent colour, mode 4 index 0 is transparent.
17. Affine BG internal X/Y only advance while the BG is enabled.

Text BG

18. Map layout for 64x64 maps is 4 separate 2 KB screenblocks (SC0 SC1 / SC2 SC3), not a flat 64-wide matrix (a flat `map_w x map_h` array in the model needs a conversion at import only).
19. Scroll registers are 9 bits; scrolling wraps at the map size, always.
20. 4bpp H flip swaps nibble order; the left pixel is the low nibble.
21. Tile index 0 / palette index 0 transparent in every bank; the backdrop is BG palette entry 0 only.

Windows

22. Window priority WIN0 > WIN1 > OBJ window > outside; windows disabled in DISPCNT leave all layers visible; layer-enable bit AND DISPCNT bit; effects bit 5 gates blending.
23. Horizontal wrap when X2 < X1 (Tonc/mGBA/NBA) versus GBATEK's "clamp to 240": decide and document. Vertical: the Y range behaves as a latch per line, with off-screen Y2 (>= 160, < 228) meaning "to the bottom" and Y1 in the hidden range meaning "not drawn".
24. Windows are screen-aligned and unaffected by mosaic. The OBJ window needs both DISPCNT bit 12 and 15. (np2d? header models `rect` [x1,x2) x [y1,y2) and per-line spans; check the wrap/garbage cases.)
25. A semi-transparent OBJ ignores the window's effects bit when a second target exists. Layers disabled by the window region do not count as the "second target" for blending.

Blending

26. EVA/EVB/EVY clamp at 16 individually and the sum saturates at 31; BLDALPHA's EVA + EVB may exceed 16.
27. Alpha needs top = first target AND the immediate next pixel = second target; a non-target pixel in between blocks it. A semi-transparent sprite does not combine with brighten/darken when it blends.
28. Fades apply to a first-target layer even if the sprite is semi-transparent but without a valid second target.
29. Rounding: GBATEK/mGBA floor versus NBA round-to-nearest with 6-bit green: unverified; pick one and keep it consistent. (np2d? header says `alpha = (first * eva + second * evb) / 16`; fades by `evy / 16` and `evb = 16 - eva` for per-line `fx_ev`, which is a simplified (G) model; real hardware has independent EVA/EVB.)

Mosaic

30. Grid anchored at screen (0,0), not at the layer's origin and not scrolling with the layer; it samples the top-left pixel of the cell, including transparency.
31. Vertical counter runs free per frame and compares against the CURRENT size.
32. BG mosaic and OBJ mosaic have separate H/V sizes and separate counters. (np2d? header has `mosaic.bg_w/bg_h/obj_w/obj_h` = 1..16, good; check the anchoring.)

Timing / per-line

33. HBlank DMA tables are offset by one line (effect applies to line+1); line 0 is set before the frame; 160 entries (+1 trailing copy).
34. BG enable latency (~3 lines) and mode-switch behaviour (next line) are hardware effects that a "settings per line" model reproduces automatically only if the per-line table captures them.
35. Per-line effects the model offers (np2d `line.*`): scroll, affine, window span, backdrop, blend alpha. Missing relative to hardware: per-line BLDY (fade gradients, widely used in pokeemerald), per-line mosaic size, per-line palette entries other than the backdrop, per-line layer enables and BG priority/bank changes. (np2d? based on the header only.)

Memory / colour

36. 8-bit VRAM/palette writes duplicate into both bytes of a BG-area halfword; OBJ-area and OAM ignore them.
37. VRAM is 96 KB mirrored in 128 KB; palette bit 15 is unused (but NBA uses it as green LSB in blends: unverified).
38. 5-bit channel maths versus RGB565: expect <= 1 LSB differences and decide the conversion once (replication vs shift). Do not alpha-blend in 8-bit then truncate unless you accept drift.
39. Forced blank outputs white; sprites still evaluate in NBA; a frame after leaving forced blank may be blank on hardware (unverified).
40. Colour correction: the raw GBA palette on a modern LCD looks different from the console; if np2d wants authenticity it is a post-process, never part of the PPU maths.

Sources for this section: all above; the numbered points consolidate GBATEK, Tonc, mGBA and NBA behaviours. Treat anything tagged unverified in earlier sections as unverified here.
