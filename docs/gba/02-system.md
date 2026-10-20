# GBA system hardware (non-video, non-audio): reference digest for pinyol

Purpose: what the rest of the GBA did around the PPU, so we can decide what pinyol should model or offer to Lua games.
Written from GBATEK, Tonc, pret/pokeemerald (read only, for how a real game used the hardware), mGBA's save-type
list and jsmolka/gba-tests (names only). No code was copied; no Nintendo SDK / AGB manual material was used.
"unverified" = not confirmed in a primary source during this research (usually: general knowledge).

**pinyol baseline** (from `docs/lua.md`, to judge "already modelled?"): `_init/_update/_draw` at 60 Hz; PPU in
software with per-line effects (`line_scroll`, `line_backdrop`, `line_window`), windows, blend, mosaic; input
`btn/btnp/btnr/btnt/btnb` + touch; `store/stored` (64 KB, JSON-like, flushed 1 s after last write); `link.*` over
ESP-NOW (20 msgs/s, 220 B JSON); `perf()`, `battery()`, `led()`; sandbox 4 MB Lua heap.

Legend for the "pinyol" column: **have** = already there; **add** = worth an API; **maybe** = only if a game asks;
**skip** = hardware artefact, no value.

Sources (whole doc):
- GBATEK, https://problemkaputt.de/gbatek.htm (sections cited by name below)
- Tonc, https://gbadev.net/tonc/ (mirror; coranac.com did not resolve from this machine): `hardware`, `dma`, `timers`, `interrupts`, `swi`, `asm`, `bitmaps`
- pret/pokeemerald, https://github.com/pret/pokeemerald (`src/main.c`, `dma3_manager.c`, `scanline_effect.c`, `save.c`, `rtc.c`, `link.c`)
- mGBA savedata, https://github.com/mgba-emu/mgba/blob/master/src/gba/savedata.c ; tests, https://github.com/jsmolka/gba-tests

---

## 1. CPU and the performance envelope

| Fact | Value | Source |
|---|---|---|
| CPU | ARM7TDMI, 16.78 MHz (2^24 Hz), 59.59 ns/cycle, no cache, no FPU, no integer divide | GBATEK "GBA Memory Map"; Tonc `hardware` |
| Frame | 228 lines x 1232 cycles = **280,896 cycles** (59.73 Hz); 160 visible + 68 VBlank lines (~83.8k cycles in VBlank); HBlank 272 cycles = 16.2 us | Tonc `timers`; GBATEK DMA ("HBlank time 16.212us"); VBlank cycle figure derived (68 x 1232) |
| Instruction sets | ARM (32-bit) and Thumb (16-bit); switch with `BX`; no mixing within an instruction | GBATEK; Tonc `hardware` |
| Guidance | Thumb for code in ROM (16-bit bus); ARM only for hot code copied to IWRAM (32-bit bus) | Tonc `hardware`; GBATEK "GBA Memory Map" |

Wait-state arithmetic (access time = 1 cycle + waitstates; N = first/non-sequential, S = sequential):

| Region | Bus | 8/16/32-bit access cycles | Notes |
|---|---|---|---|
| IWRAM 32 KB | 32 | 1/1/1 | fastest; hot code, stack, IRQ handler, DMA queues |
| EWRAM 256 KB | 16 | 3/3/6 | 2 waitstates by default (reg 0x4000800 can lower it, undocumented) |
| BIOS ROM 16 KB | 32 | 1/1/1 | read-protected except while executing in it |
| Palette / VRAM | 16 | 1/1/2 (+1 if video is reading at the same time) | 8-bit writes not allowed (16/32 only) |
| OAM | 32 | 1/1/1 (+1 on video clash) | 16/32-bit writes only |
| Game Pak ROM | 16 | default 5/5/8; commercial games set WAITCNT 0x4317: N=4, S=2 (3,1 waitstates) | 32-bit = 2 halfword fetches, second always sequential |
| SRAM/Flash | 8 | 5 (8 waitstates recommended) | byte access only |

- WAITCNT (0x4000204): SRAM wait (bits 0-1), WS0/1/2 first and second access, **prefetch enable (bit 14)**. Startup
  value 0000h (N=5,S=3, prefetch off); typical games set 3,1 waitstates + prefetch (pokeemerald:
  `PREFETCH_ENABLE | WS0_S_1 | WS0_N_3`). 128 KB-block boundaries in ROM force non-sequential timing.
- Prefetch buffer: up to eight 16-bit values fetched from ROM while the CPU is busy on internal cycles; only helps
  opcode fetches from ROM, not data reads. With prefetch off there is a quirk: ROM opcodes with internal cycles
  fetch at N instead of S.
- Derived rules of thumb (arithmetic from the table above, so mostly sound but unverified against hardware):
  Thumb from ROM at 3,1 is ~2 cycles/instruction; ARM from ROM ~4; anything in IWRAM ~1. Hence the standard
  split: ROM = Thumb, hot loops = ARM in IWRAM, big data in EWRAM at 16-bit width.
- Multiply is multi-cycle, no divide: games use BIOS `Div` or lookup tables (see section 5).
- The GBA budget a game lived in: roughly **280k cycles per frame minus waits**, i.e. a few hundred simple
  instructions per scanline. Every effect had to be table-driven or hardware-assisted (DMA, affine, windows).

**pinyol:** the ESP32-S3 runs Lua at 240 MHz with PSRAM, so a cycle-accurate CPU is out of scope. **skip** CPU/wait
state modelling. **Useful idea:** the GBA's *budget* (HBlank-sized work per line, VBlank-sized upload per frame) is
a good design constraint for the software PPU's per-line effect API, and `perf()` already measures the equivalent.

Sources: GBATEK "GBA Memory Map", "GBA System Control" (WAITCNT, GamePak Prefetch), "GBA Cartridge ROM";
Tonc `hardware`, `asm` (cycle tables), `timers` (280,896 cycles); pokeemerald `src/main.c`.

---

## 2. Memory map and sizes

| Range | What | Size | Mirrors / limits |
|---|---|---|---|
| 0000_0000 | BIOS | 16 KB | |
| 0200_0000 | EWRAM | 256 KB | multiboot code lands here |
| 0300_0000 | IWRAM | 32 KB | top 256 B reserved (IRQ stack, BIOS stack, IRQ vector at 0300_7FFC, BIOS IRQ flag at 0300_7FF8) |
| 0400_0000 | I/O regs | ~1 KB | |
| 0500_0000 | Palette | 1 KB (256 BG + 256 OBJ colours, 15-bit) | |
| 0600_0000 | VRAM | 96 KB | |
| 0700_0000 | OAM | 1 KB (128 sprites) | |
| 0800_0000 / 0A.. / 0C.. | Game Pak ROM (WS0/1/2) | max 32 MB | same ROM mirrored three times with different wait settings |
| 0E00_0000 | Save RAM/Flash | max 64 KB visible (128 KB flash via bank switch) | 8-bit bus |

Total RAM a game can touch: 32 KB + 256 KB work RAM + 96 KB VRAM. Typical ROMs: 4-32 MB (F-Zero and Super Mario
Advance 4 MB, Zelda 8 MB per GBATEK; 32 MB max).

Pokemon Emerald as a worked example of the budget: `EWRAM_SIZE 0x40000`, `IWRAM_SIZE 0x8000`; save blocks, heap
and decompression buffers live in EWRAM; IRQ handler (`IntrMain`) is DMA-copied into an IWRAM buffer at boot so it
runs at 1 cycle/fetch.

**pinyol:** **skip** the memory map as such (Lua games see tables and canvases). **Take the numbers as defaults for
budgets:** 32 KB hot + 256 KB cold + 96 KB tile VRAM is the envelope GBA art was built for; useful when sizing
tile/palette limits in docs ("a GBA game fit in this").

Sources: GBATEK "GBA Memory Map", "GBA Interrupt Control" (default 3007Fxx usage); Tonc `hardware`; pokeemerald
`include/gba/defines.h`, `src/main.c`.

---

## 3. DMA

Four channels; priority 0 (highest) to 3; CPU is halted while a DMA runs (it only runs during the gaps of
VBlank/HBlank/sound DMAs). Cost for n units: `2N + 2(n-1)S + xI` (internal 2I, or 4I if both ends are in ROM).

| Ch | Source | Dest | Max count | Special start mode | Typical use |
|---|---|---|---|---|---|
| 0 | internal memory only | internal only | 16 K units | not allowed | HBlank effects (highest priority, timing-critical) |
| 1 | any | internal | 16 K | sound FIFO A/B | PCM audio |
| 2 | any | internal | 16 K | sound FIFO A/B | PCM audio |
| 3 | any (only channel that can read ROM) | any (also EEPROM save) | 64 K | video capture (lines 2..162) | general copies/fills, EEPROM bit-stream |

Control (DMAxCNT_H): dest control (inc/dec/fixed/**inc+reload**), source control (inc/dec/fixed), repeat, 16/32-bit,
start timing (**immediate / VBlank / HBlank / special**), IRQ at end, enable. Rules worth knowing:
- Start timing 2 (HBlank) with **repeat** re-arms each scanline, transferring `count` units *each* HBlank; there is no
  HBlank DMA during VBlank. The first transfer happens after line 0 is drawn, so effects set line 0 by hand
  (pokeemerald does exactly this).
- Fill = fixed source address (the *address* of a value, not the value; Tonc warns of the `volatile` bug).
- OAM or OBJ VRAM writes during HBlank need DISPCNT "H-Blank interval free".
- Sound FIFO mode: repeat required, dest = FIFO A/B (0x40000A0/A4), each request moves 4 x 32-bit; count/size ignored;
  higher-priority DMA must not run longer than ~0.25 ms at 64 kHz or audio starves.
- Source/dest registers are not updated by hardware; internal copies are reloaded on enable/repeat.

How games used it:
- **Per-scanline effects (HDMA):** DMA0, HBlank, repeat, one 16/32-bit value per line from a 160-entry table into a
  fixed register: wavy water (BGxHOFS), parallax bands, sky gradients (backdrop colour or palette entry), circular
  windows (WIN0H), spotlights, Mode-7 style per-line affine parameters (BGxPA..PD). Tonc's `dma` demo does a circular
  window this way. pokeemerald's `scanline_effect.c` double-buffers the table (`gScanlineEffectRegBuffers[2][0x3C0]`)
  so the game can rewrite it while DMA reads the other half, and swaps buffers each frame.
- **VBlank upload queue:** pokeemerald's `dma3_manager.c` queues up to 128 copy/fill requests during the frame and
  drains them in the VBlank handler, stopping at **40 KiB per frame** or when VCOUNT > 224 ("about to leave VBlank").
  This is the canonical "stream tiles/palettes safely" pattern.
- **Sound:** DMA1/2 + Timer 0/1 feed FIFO A/B (section 4).
- **General copies:** DMA3 for tiles/maps/palettes into VRAM; Tonc notes CpuFastSet is within ~10% of DMA for copies
  and DMA stalls the CPU (IRQ latency risk).
- **EEPROM saves** use DMA3 as the only way to talk to the chip (section 9).

**pinyol:** per-line effects are **have** (`line_scroll`, `line_backdrop`, `line_window`). Open questions: (a) **add**
per-line writes for more targets that GBA HDMA covered but pinyol may not: layer offsets Y, palette entry, mosaic,
blend coefficient, affine parameters (check `mode7`); (b) a "register table per frame" model like pokeemerald's
double buffer is already implied by the immediate-mode `line_*` calls. DMA itself (channels, priorities, FIFO)
is **skip**: no game-visible semantics beyond "copy during VBlank".

Sources: GBATEK "GBA DMA Transfers"; Tonc `dma`; pokeemerald `src/dma3_manager.c`, `src/scanline_effect.c`.

---

## 4. Timers

Four 16-bit up-counters, clocked at F/1, F/64, F/256, F/1024 (16.78 MHz / 262 kHz / 65.5 kHz / 16.4 kHz); overflow
reloads from the reload value; optional IRQ on overflow; **cascade (count-up) mode** increments a timer when the
previous one overflows (not available for timer 0).

| Use | How |
|---|---|
| Sound sample rate | Timer 0 or 1 overflow clocks the FIFO A/B sample output (reload = 65536 - 16.78M/rate); a cascaded timer can IRQ after N samples to refill buffers |
| Long timers / clock | e.g. Tonc's clock demo: timer 2 at F/1024 with reload -0x4000 overflows exactly once a second, cascaded timer 3 counts seconds |
| RNG seed | pokeemerald starts Timer 1 free-running at boot and reads `REG_TM1CNT_L` when the player presses a button to seed the RNG and trainer ID (`StartTimer1`, `SeedRngAndSetTrainerId`) |
| Link cable pacing | Emerald loads Timer 3 with -197 at F/64 (~0.75 ms) to schedule serial transfers (inference: timing between multi-play transfers; unverified) |
| Profiling | cycle-count code with a free-running timer pair (common practice, unverified here) |

Quirks: writing the data register sets the *reload*, not the current count; start bit 0 to 1 copies reload into counter.

**pinyol:** timers as hardware are **skip**; pinyol has `t()` and `ticks()` (60 Hz). Possible small **add**: none needed.
Note the RNG-from-timer idiom: GBA games seeded RNG from human timing; pinyol's `math.random` is deterministic
per run (good for tests), so a `seed_from_time()` is **maybe** if games want varied runs.

Sources: GBATEK "GBA Timers"; Tonc `timers`; pokeemerald `src/main.c`, `src/link.c`.

---

## 5. Interrupts and the BIOS calls games leaned on

### Interrupts
Registers: IME (master), IE (enable mask), IF (flags; ack by writing 1), plus CPSR I-bit. 14 sources:
VBlank, HBlank, VCount match, Timer 0-3, Serial, DMA 0-3, Keypad, Game Pak. Hardware vectors to BIOS, which saves
r0-r3/r12/lr and jumps through the user pointer at 0300_7FFC (ARM-mode handler; no priority built in, the game
decides). pokeemerald builds an interrupt table of 14 function pointers and its `IntrMain` dispatches by IF bit.
- VBlank handler (pokeemerald `VBlankIntr`) is the game's real synchronisation point: link update, buffered GPU
  register copy (`CopyBufferedValuesToGpuRegs`), DMA request queue, audio mixer (`m4aSoundMain`), RNG tick, and
  setting the BIOS flag at 0300_7FF8 (`INTR_CHECK`).
- VCount interrupt: pokeemerald enables VCount at line 150 (for audio mixing timing: `m4aSoundVSync`).
- HBlank IRQ: used for CPU-driven raster effects when HDMA is not enough (Tonc's gradient demo).
- Keypad IRQ: meant for waking from Stop mode, not for normal input (GBATEK); Game Pak IRQ: cartridge removal
  (GBATEK recommends hanging the machine when it fires with SRAM carts) and cart hardware.

### BIOS calls (SWI) games used
| SWI | Name | What | Notes |
|---|---|---|---|
| 02h / 03h | Halt / Stop | CPU sleep until (IE and IF) | Stop = screensaver-like low power |
| 04h / 05h | IntrWait / **VBlankIntrWait** | halt until the chosen IRQ; requires the handler to OR the flag into 0300_7FF8 | standard frame wait; saves battery vs polling VCOUNT (Tonc) |
| 06h / 07h | Div / DivArm | signed divide: quotient, remainder, abs(quotient) | no hardware divide; do not divide by zero |
| 08h | Sqrt | 32-bit to 16-bit integer root | shift input by 2N for fractional bits |
| 09h / 0Ah | ArcTan / **ArcTan2** | angle 0-FFFFh = 0..2pi from 1.14 fixed-point x,y | ArcTan poor outside +-pi/4; use ArcTan2 |
| 0Bh / 0Ch | **CpuSet / CpuFastSet** | memcpy/memfill in 16/32-bit units / 32-byte blocks | fill takes an address; FastSet rounds up to 8 words; refuse BIOS-area source |
| 0Eh / 0Fh | **BgAffineSet / ObjAffineSet** | build PA..PD matrices from scale + angle (angle 0-FFFFh, only top 8 bits used) | the "sin/cos" of GBA games; Tonc reads cos/sin back out of the result |
| 10h | BitUnPack | expand 1/2/4-bit to 4/8/16/32-bit | 1bpp fonts to 4bpp tiles |
| 11h / 12h | **LZ77UnComp** WRAM / VRAM | LZ77 (header 0x10, 12-bit disp, len 3-18) | VRAM variant writes 16-bit units, cannot use disp 0 |
| 13h | HuffUnComp | Huffman, 4 or 8-bit symbols | used for text/maps |
| 14h / 15h | **RLUnComp** WRAM / VRAM | run-length | good for flat tilemaps |
| 16h-18h | Diff8/16 unfilter | delta decoding | pairs with LZ/Huffman for audio and gradients |
| 19h-1Dh, 28h, 29h | SoundBias, SoundDriver* | Nintendo's sound driver (m4a/MusicPlayer is built on it) | out of scope here |
| 25h | MultiBoot | upload a program to slave GBAs with no cartridge | single-cart multiplayer |
| 00h, 01h, 26h | SoftReset, RegisterRamReset, HardReset | reset and clear RAM | the A+B+Start+Select soft reset is a game-implemented convention (pokeemerald `DoSoftReset`) |

- There is **no sin/cos SWI on the GBA** (that exists on the NDS only). Games ship their own 256- or 512-entry
  sine lookup table (Tonc appendix B) or take it from ObjAffineSet. (Tonc swi chapter; GBATEK lists no GBA sine call)
- BIOS calls cost at least ~60 cycles overhead and are "designed for space, not speed" (Tonc `swi`).
- Compressed asset formats: pokeemerald stores graphics as `.4bpp.lz`, `.gbapal.lz`, tilemaps `.bin.lz`; they are
  decompressed with `LZ77UnCompWram` into a shared EWRAM buffer or straight to VRAM (`LZ77UnCompVram`) at load.
  Common pipeline in devkitARM tools (grit, gbafix) is the same (unverified detail).

**pinyol:**
| Item | Verdict |
|---|---|
| VBlank/HBlank IRQ model | **skip**; `_update/_draw` split plus `line_*` calls replace it |
| VBlankIntrWait | **have** (implicit frame loop) |
| ArcTan2 / Sqrt / Div | **have** (Lua `math.atan(y,x)`, `math.sqrt`, `//`); skip fixed-point variants |
| BgAffineSet / ObjAffineSet | check `mode7` / sprite rotate API: if games must build matrices from scale+angle, a helper `affine(sx, sy, angle)` is **maybe** |
| CpuSet / CpuFastSet / DMA copies | **skip** (Lua has no raw memory) |
| LZ77 / RLE / Huffman asset formats | **maybe** (on the ESP32 flash/SD, a decompress-on-load step for tilesets could cut game size; but `docs/game-format.md` assets are probably PNG/rgb565 already; a quick size comparison of LZ77 vs current format would decide) |
| BitUnPack | **skip** |
| Sound driver SWIs | **skip** |

Sources: GBATEK "GBA Interrupt Control", "BIOS Function Summary", "BIOS Arithmetic Functions", "BIOS Rotation/Scaling
Functions", "BIOS Decompression Functions", "BIOS Memory Copy", "BIOS Halt Functions"; Tonc `interrupts`, `swi`;
pokeemerald `src/main.c`, `src/decompress.c`, `src/graphics.c`.

---

## 6. Keypad

- 10 buttons: A, B, Select, Start, Right, Left, Up, Down, R, L; `KEYINPUT` (0x4000130) is **active low** (0 =
  pressed), bits 0-9. GBATEK: read once per frame and store (also avoids contact bounce).
- `KEYCNT` (0x4000132): per-key mask + OR/AND condition + IRQ enable; for waking from Stop, not for input.
- No analog, no repeat in hardware: games implement it. pokeemerald `ReadKeys`: `newKeys`, `heldKeys`,
  `newAndRepeatedKeys` (start delay 40 frames, repeat every 5), L=A remap option, and A+B+Start+Select soft reset.
- GBA SP backlight button and Game Boy Player rumble are outside the keypad register.

**pinyol:** **have**, and richer (`btnp(name, hold, every)`, `btnr`, `btnt`, `btnb` buffering). Nothing to add.
The GBA had no input buffering built in either, but Emerald's repeat delays (40/5 frames) are good defaults to
mention in docs. pinyol has C and MENU extra; GBA has L/R shoulders: how a GBA-ported game maps L/R is a
documentation question, not hardware. Decided: no `"l"`/`"r"` names (the console has no such buttons; they would only exist on a
keyboard); `docs/lua.md` says to give them to C or the touch screen.

Sources: GBATEK "GBA Keypad Input"; pokeemerald `src/main.c`.

---

## 7. Save types

Game Pak backup is detected by ID strings inside the ROM (no header field): `EEPROM_Vnnn`, `SRAM_Vnnn`,
`FLASH_Vnnn` / `FLASH512_Vnnn`, `FLASH1M_Vnnn` (GBATEK "GBA Cart Backup IDs"). mGBA autodetects the same set and also
has SRAM512 and EEPROM512 types.

| Type | Size | Access | Endurance | Used by |
|---|---|---|---|---|
| SRAM (battery) | 32 KB (up to 64 KB visible window) | 8-bit read/write at 0E00_0000, 8 waitstates, read from WRAM-run code | battery life | F-Zero (GBATEK) and many |
| FRAM | 32 KB | identical software interface to SRAM, no battery | ~10^10 write cycles per bit | WarioWare Twisted (GBATEK) |
| EEPROM 4 Kbit | 512 B (64 x 8-byte blocks) | **bit-serial via DMA3** (2-bit command + 6-bit address, 64-bit data), 8 waitstates; write takes ~6.5 ms | 100k writes | Super Mario Advance (GBATEK) |
| EEPROM 64 Kbit | 8 KB (1024 blocks, 14-bit address) | same, 14-bit addressing; chip size is not detectable by software | 100k | Boktai (GBATEK) |
| Flash 512 Kbit | 64 KB, 16 x 4 KB sectors | command sequences (AA/55 unlock), erase sector/chip before write, poll until 0xFF; 8-bit access, run from WRAM | 10k per sector | Sonic Advance (GBATEK) |
| Flash 1 Mbit | 128 KB, 2 banks of 64 KB | same + bank switch | n/a | Pokemon Emerald, many large games |

- Atmel flash differs (128-byte sectors, erase+write in one command; interrupts must be off during the write).
- Real games add integrity logic on top: pokeemerald uses **128 KB flash = 32 sectors of 4096 B**
  (`SECTOR_DATA_SIZE 3968` + 128-byte footer with signature, sector id, checksum, save counter), **two rotating save
  slots** (counter picks the newest valid one, 14 sectors per slot), plus a few special sectors (Hall of Fame, Trainer
  Hill, recorded battle). That is power-loss-safe wear levelling in ~32 sectors.
- Removing the cart while powered can corrupt SRAM (no write protect): GBATEK recommends handling the Game Pak IRQ.
- Save size on the GBA is tiny: most games used 0.5-128 KB.

**pinyol:** **have** (`store/stored`, 64 KB, JSON-like, delayed write). Ideas: (a) the **"two slots + counter +
checksum"** pattern is worth recommending in docs/library for the ESP32's flash/SD (power loss while `store` flushes
is the same failure the GBA games guarded against); is the existing write atomic (write temp then rename)? Worth
checking; (b) nothing else: erase/write timings and bus protocols are **skip**.

Sources: GBATEK "GBA Cart Backup IDs / SRAM-FRAM / EEPROM / Flash ROM"; mGBA `src/gba/savedata.c`;
pokeemerald `include/save.h`, `src/save.c`; jsmolka/gba-tests `save/` (flash/SRAM/EEPROM behaviour tests).

---

## 8. Link cable (SIO)

Serial port with six pins (SC, SD, SI, SO, VCC, GND); modes selected by RCNT bit 15 / SIOCNT bits 12-13:

| Mode | What | Key facts |
|---|---|---|
| Normal (8 or 32-bit) | two units, master/slave shift register, full duplex | 256 kHz (stable) or 2 MHz (only for direct expansions); also one-way fast broadcast; MultiBoot can use it |
| **Multi-player** | up to **4 GBAs**, one parent (the end with the small plug, SI low) and up to 3 children | 16-bit per unit per transfer; baud 9600/38400/57600/115200; all units end with the same SIOMULTI0-3 contents; IDs 0-3 assigned after first transfer; error bit and ready (SD) bit; IRQ on completion. Duration: 18 + 18*(n-1) bits plus delays and timeout |
| UART | RS-232-like, 7/8 data bits, parity, 4-deep FIFO, CTS | baud 9600-115200; used by some adapters and devkits |
| JoyBus | GBA as slave to a GameCube | not for game-to-game |
| General purpose | SI/SO/SC/SD as 4 bits of GPIO | used by e.g. adapters and IR peripherals (not as shipped hardware) |
| Wireless adapter (RFU) | separate 2004 accessory over the same port | pokeemerald `link_rfu` is a whole stack (up to 5 players) |

Typical multiplayer game patterns:
- **Parent-starts-transfer, per-frame exchange:** parent starts a multi-play transfer from its VBlank handler; all
  units send their latest packet and receive everyone's in the same transfer. Pokemon Emerald: 115200 baud, 4
  players max (`MAX_LINK_PLAYERS 4`), command packets of **8 x u16** (`CMD_LENGTH 8`), send/receive queues,
  block transfers of 0x100 bytes cut into packets (`INIT_BLOCK`/`CONT_BLOCK` commands), handshake before play,
  lag counters when no serial IRQ arrives within ~10 VBlanks, Timer 3 used for pacing.
- **Lockstep input exchange:** each unit sends its keypad state; every unit simulates the same frame (needs
  determinism). Used in racers and puzzle games (unverified: general knowledge of GBA multiplayer; Emerald's
  `LINKCMD_*` includes key exchange for the Pokemon Blender, e.g. `LINKCMD_BLENDER_SEND_KEYS`).
- **Single-cart multiplayer:** the BIOS multiboot (SWI 25h) uploads one game's slave program to EWRAM in the other
  GBAs; the slave program is capped to ~256 KB. Nintendo used it widely.
- **Cable detection:** the parent role is decided by the connector end; software reads SIOCNT bit 2 (SI) and bit 3
  (SD) to know role and readiness.

**pinyol:** **have**, and a different (better for hobby use) shape: `link.send/recv/peers/id` over ESP-NOW with JSON,
20 msgs/s, loss and lateness allowed. Hardware-derived lessons worth documenting for game authors rather than
modelling: send *state*, not events (already said in lua.md); a deterministic lockstep helper (shared tick number +
input exchange) is a **maybe** library if games want GBA-style 2-4 player lockstep; a fixed player cap of 4
(IDs 0-3) matches both the GBA and `link.peers()` order. Everything else (SIO registers, baud rates, UART) is **skip**.

Sources: GBATEK "GBA Communication Ports", "SIO Normal / Multi-Player / UART / JOY BUS Mode", BIOS "MultiBoot";
pokeemerald `src/link.c`, `include/link.h`, `src/main.c`.

---

## 9. Game Pak peripherals

Most carts have only ROM + backup. Extras are mapped into the ROM address space through a **4-bit GPIO port in the
ROM chip** at 0800_00C4 (data), 0800_00C6 (direction), 0800_00C8 (control: read/write enable), or into the SRAM window.

| Peripheral | Interface | Games (confirmed in sources) | Notes |
|---|---|---|---|
| **RTC** (Seiko S-3511A, 3-wire serial over GPIO bits 0-2) | read/write 7-byte date-time (BCD), control reg with 12/24 h flag and a **"power failure, time lost" flag**; alarm/IRQ possible | Boktai series, P-Letter, Rockman EXE 4.5 (GBATEK); **Pokemon Ruby/Sapphire/Emerald** (pokeemerald `src/rtc.c` + `RtcInit` in `main.c`; berries, tides, time-of-day events) | the Pokemon games compute day counts and "minutes since" to drive time-based events; also used (`RtcGetMinuteCount`) to seed the RNG in the bugfix path |
| **Solar sensor** | photodiode, 8-bit ramp A/D conversion clocked via GPIO (slow clock ~666 Hz in Boktai, bit 3 = comparator) | Boktai 1-3 (GBATEK; Boktai 3 Japan-only per a retailer list) | sunlight level 0x00 (bright) to ~0xE8 (dark); needs a calibration step in-game |
| **Tilt sensor** (X/Y accelerometer, Yoshi-type) | memory-mapped in the SRAM window at 0E00_8000..8500; write 55h/AAh to start sampling, 12-bit X and Y | **Yoshi Topsy-Turvy / Universal Gravitation**, Koro Koro Puzzle (GBATEK) | needs SRAM wait=8 and PHI=4 MHz; sampled once per frame in VBlank |
| **Gyro sensor** (Z-axis rotation) | serial ADC over GPIO bits 0-2, 12-bit sample | **WarioWare Twisted** (GBATEK) | range 0x354..0x9E3, 0x6C0 at rest (cart-specific) |
| **Rumble** | one motor via GPIO bit 3 (on/off level), no PWM | WarioWare Twisted; **Drill Dozer** (rumble only) (GBATEK, retailer list); also works via GameCube pads on Game Boy Player | Drill Dozer's strength varies with what you drill (forum info, unverified) |
| e-Reader | dot-code scanner + extra flash | Pokemon, Mario cards | skip |
| Others (IR, Wireless Adapter, Play-Yan MP3 etc.) | | | skip |

**pinyol (ESP32-S3 console):**
| Peripheral | Verdict |
|---|---|
| RTC / wall-clock date | **done**: `clock()` (a table of the local date and time, or `nil` as the S-3511A's power-failure flag says: no date). The console has no RTC chip; the computer sets its clock over the cable (`hello 2`, then `time <unix> <offset>`) and the ESP32-S3's RTC timer keeps it through sleep and restarts, not through a flat battery. Seconds since 1970 are not given: the console's Lua has 32-bit integers, which 2038 would overflow; `days` and the time of day do the same work |
| Solar sensor | **skip** (could be faked with an ambient-light sensor if the board had one; no evidence it does) |
| Tilt / gyro | **maybe** (only if the board has an IMU: not listed in `docs/hardware.md`; the browser player has DeviceOrientation, so a nil-able `tilt()` is feasible) |
| Rumble | **maybe** (nil-able `rumble(strength, ms)`; no motor on the board; the pilot LED or a speaker thump could substitute) |

Sources: GBATEK "GBA Cart I/O Port (GPIO)", "Real-Time Clock", "Solar Sensor", "Tilt Sensor", "Gyro Sensor", "Rumble",
"Cart e-Reader"; pokeemerald `src/rtc.c`, `src/main.c`; retailer/forum list for Boktai/Drill Dozer/Yoshi/Wario
(web search result: https://shop.insidegadgets.com/product/gba-16mb-64k-eeprom-solar-rtc-flash-cart/ and
https://shmups.system11.org/viewtopic.php?p=1068323 - lower reliability).

---

## 10. Typical frame loop and double-buffering patterns

**Frame loop (pokeemerald `AgbMain`, reduced):**
1. Boot: reset RAM, set WAITCNT, init keys, interrupt table, sound, RTC, flash probe, heap.
2. `for (;;)` { `ReadKeys()`; reset combo check; link update; call game callbacks (`callback1` world-update,
   `callback2` current screen); play-time and music tick; `WaitForVBlank()` }.
3. `WaitForVBlank()` = clear the VBlank flag, then `VBlankIntrWait` (halt the CPU until VBlank IRQ).
4. VBlank IRQ does the time-critical hardware writes only: copy buffered GPU/PPU registers, copy OAM from a RAM
   shadow (sprite buffer), drain the DMA3 queue, mix audio, advance counters.

**Core idioms:**
| Pattern | Why | Source |
|---|---|---|
| Shadow OAM in RAM, copy to OAM in VBlank | OAM is only safely writable in VBlank (or HBlank with a flag) | Tonc; pokeemerald (sprite copy requests; `ClearSpriteCopyRequests`) |
| Shadow/buffer PPU registers, commit in VBlank | avoid mid-frame tearing, scroll glitches | pokeemerald `gpu_regs.c` (`sGpuRegBuffer`, waiting list, lock flag) |
| Deferred DMA request queue with a per-frame byte cap | spread VRAM uploads; never run past VBlank | pokeemerald `dma3_manager.c` (40 KiB cap, VCOUNT > 224 stop) |
| Double-buffered per-line tables | rewrite effect data while the previous frame's table is still read by HDMA | pokeemerald `scanline_effect.c` |
| Page flip in bitmap modes 4/5 | two frame buffers (mode 4: 2 x 0x9600 B at 0600_0000 / 0600_A000; mode 5: 2 x 0xA000 B); flip by toggling DISPCNT bit 4 in VBlank; kills tearing | Tonc `bitmaps` |
| Tile modes need no page flip | tilemaps are small; the PPU re-reads state every frame | Tonc `bitmaps` ("90% or more of GBA games used tile modes") |
| Task/callback state machines (`SetMainCallback2`, `Task_*`) | cooperative multitasking without an OS | pokeemerald `main.c`, `task.c` (not read in detail) |
| Soft-reset combo A+B+Start+Select | no reset button | pokeemerald `main.c` |

**pinyol:** frame loop is **have** (`_update/_draw`, 60 Hz, state persists in the PPU like a shadow-OAM/register
model). Bitmap modes/page flip: **skip** (software PPU; double buffer is internal). The **DMA byte-cap per frame**
idea matters for the ESP32: any streamed asset (tileset swaps, big canvases to PSRAM/LCD over QSPI) should be
budgeted per frame; `perf()` could report "bytes uploaded this frame" (**maybe**). Soft-reset combo = pinyol's
MENU-hold quit (**have**).

---

## 11. Memory-budget techniques GBA games used

| Technique | What / numbers | Evidence | pinyol |
|---|---|---|---|
| **Tile-based VRAM budget** | 96 KB VRAM = 64 KB BG tiles/maps (4 x 16 KB charblocks, 2 KB screenblocks, 32x32 map) + 32 KB sprite tiles (16 KB in bitmap modes); 4bpp tile 32 B (up to 512 per 16 KB), 8bpp tile 64 B | Tonc `bitmaps`/`regbg` (video detail owned by the video digest; unverified here beyond Tonc's framing) | **have** (PPU is a model of this); keep limits documented |
| **16-colour palette banks** | 4bpp tiles select one of 16 sub-palettes of 16 colours per tile (BG and OBJ palettes: 256 colours each); halves tile memory vs 8bpp and allows recolour variants (day/night, damage flash, team colours) by swapping palette entries only | Tonc / GBATEK palette; common practice | **have** (`Palettes` section): promote recolour-by-palette as the way to make variants |
| **Tile streaming** | keep only the tiles needed *now* in VRAM; load sprite-sheet frames on demand (Pokemon loads/unloads sprite sheets via a tag system, compressed), animate by swapping tile data or the tile index, scroll maps by writing a new column/row into the circular 32x32 screenblock as the camera moves | pokeemerald `dma3_manager.c` (queued copies), `decompress.c`, `graphics.c`; scrolling map streaming is common practice (unverified here) | **maybe**: if canvases/tilesets live in PSRAM, expose a "tileset slot" swap and a per-frame upload budget |
| **VRAM tile reuse / flip** | h/v flip bits per tile and per sprite give 2-4x reuse; shared tiles for walls/floors; identical metatiles | GBA tilemap entries have flip bits (GBATEK video; not in this digest's scope) | **have**/check flip is exposed in sprite+tile API |
| **Compressed assets in ROM** | LZ77 (BIOS SWI 11h/12h) for tiles/palettes/maps, RLE for flat maps, Huffman for text; decompress to a shared EWRAM scratch buffer or straight to VRAM at load; typical 2-4x for pixel art (ratio unverified) | pokeemerald `.4bpp.lz`, `.gbapal.lz`; `decompress.c` | **maybe** (see section 5) |
| **Working RAM split** | IWRAM = stack + IRQ + hot ARM routines + per-frame tables; EWRAM = heap, save buffers, decompression scratch, big arrays; ROM = Thumb code + read-only data | pokeemerald `EWRAM_DATA` / `COMMON_DATA` split; Tonc `hardware` | **skip** |
| **Fixed-size pools** | task slots, sprite slots (128 OAM), DMA queue (128), no malloc in the frame loop; pokeemerald does allocate a heap at boot (`InitHeap`) but fixed-size | pokeemerald `main.c`, `dma3_manager.c` | **have** (`swarms`, grids): documenting "pools not malloc" matches the 4 MB Lua heap limit |
| **Mosaic/line tricks instead of art** | per-line scroll (water), HBlank gradients, windows (spotlights), mosaic fades replace bigger or more frames | Tonc `dma`; pokeemerald `scanline_effect.c` | **have** |
| **Save in RAM-sized structs** | save blocks (a few KB) kept in RAM, written in sector chunks with checksum | pokeemerald `save.c` | **have** (`store`) |

---

## 12. Summary: what is worth taking

| Priority | Item | Why |
|---|---|---|
| High | More per-line (HDMA-equivalent) targets beyond scroll/backdrop/window: affine params, palette entry, blend, mosaic | HBlank DMA was the GBA's signature trick; costs little in a software PPU |
| High | Document/offer the **two-slot save with counter + checksum** (and verify `store` is atomic against power loss) | Real GBA games all had to survive removal/power loss; ESP32 flash/SD has the same risk |
| Medium | nil-able **wall-clock** (`date()`/`now()`) for time-of-day games | Pokemon, Boktai, P-Letter used the cart RTC |
| Medium | Per-frame **upload budget** concept (VBlank-style) and "bytes uploaded" in `perf()` | Emerald caps 40 KiB/VBlank; a QSPI LCD will have a similar wall |
| Low/maybe | `affine(scale, angle)` helper; LZ77/RLE asset option; deterministic lockstep helper for link; nil-able `tilt()`/`rumble()` | only if a game asks |
| Skip | CPU/wait-states, DMA channels, timers, SIO registers, memory map, SWIs, flash/EEPROM protocols | no game-visible value in pinyol's Lua model |

## Unverified / gaps
- coranac.com was unreachable; Tonc was read through its gbadev.net mirror (same content, updated format).
- GBATEK lists no cycle-timing table for ARM vs Thumb instruction costs in the sections read; the "2 vs 4 cycles per
  instruction" rule is derived from the waitstate table, not measured.
- Which GBA games used the Game Pak IRQ, the Game Boy Player rumble, or the JoyBus mode was not researched.
- Compression ratios and the exact asset toolchain of other pret decomps (pokefirered, etc.) not checked.
- The purpose of Emerald's Timer 3 pacing value (-197 at F/64) is inferred.
- jsmolka/gba-tests was only inspected by directory names (arm, thumb, bios, memory, ppu, save, nes, unsafe); no test source was read.
