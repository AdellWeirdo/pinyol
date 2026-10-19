# GBA genres and the techniques each relied on: reference digest for pinyol

Purpose: which kinds of games the Game Boy Advance had, what screen/tile/sprite set-up and hardware tricks each used,
what a pinyol@2 engine needs to host that genre, what the examples already cover, and which genre example to build
next so that it finds engine gaps. Written 2026-10-19. No Nintendo SDK or AGB manual material was used.

**Evidence marks.** A fact with no mark was read in a source listed at the end (fetched during this research).
`unverified` = general knowledge or inference that no fetched source confirmed; treat as a lead, not a fact.
Per-game rendering internals are mostly `unverified`: the public write-ups for most commercial GBA games are thin
(searches for Advance Wars, Golden Sun, Doom and Duke Nukem Advance internals returned nothing citable).

**pinyol baseline** (from `docs/lua.md`, `src/ppu.h`, and a grep of `examples/*/main.lua`): 4 BG layers (tiles /
affine / bitmap), 128 sprites, 32 affine matrices, palettes + banks, alpha/fade, 2 windows + object window, mosaic,
per-line tables (`line_scroll`, `line_backdrop`, `line_window`, Mode 7 via `mode7`), 4 tone voices + `.mod` +
`studio`, `raycast`, `physics`, `swarm`, `grid`, `link`, `mic`, `battery`, `led`, `video`, `store` (64 KB).

---

## 1. Hardware facts that shaped GBA genres

| Fact | Value | Why it matters to genre |
|---|---|---|
| CPU / RAM | ARM7TDMI 16.78 MHz; 32 KB IWRAM + 256 KB EWRAM (EWRAM on a 16-bit bus); VRAM 96 KB; OAM 1 KB; palette 1 KB | Software 3D (Doom, Quake) lives or dies on what fits in 32 KB IWRAM |
| Screen | 240x160, 15-bit colour; up to 511 colours at once in tile modes (256 BG + 256 OBJ, minus transparency) | Everything is palette art; recolouring by palette bank is the norm |
| Modes | 0: four text BGs. 1: BG0/BG1 text + BG2 affine. 2: BG2/BG3 affine. 3: 240x160 16 bpp bitmap. 4: 240x160 8 bpp, 2 pages. 5: 160x128 16 bpp, 2 pages | Tile games = mode 0/1. Mode 7 floors and rotating worlds = mode 1/2. 3D = mode 4/5 (page flip) |
| Text BG | 256x256 to 512x512 px (32x32 .. 64x64 tiles), 10-bit tile index (1024 tiles), H/V flip, 4-bit palette bank (4 bpp) | Big maps scroll as a ring buffer: only the new row/column is rewritten |
| Affine BG | 128..1024 px square (16..128 tiles), 1-byte map entries, **256-colour tiles only, max 256 tiles**, wrap flag; BG2 affine in modes 1-2, BG3 in mode 2 | Why affine worlds look chunkier than tile worlds |
| Sprites | 128 OBJ; shapes 8x8..64x64 (square, wide, tall); 32 affine parameter groups shared with OAM; double-size flag stops rotation clipping; 32 KB OBJ VRAM (1024 4bpp tiles; only 512..1023 usable in bitmap modes) | Big bosses are many sprites glued, or one affine sprite; 128 is a real budget |
| Per-line sprite budget | 1210 cycles (954 with H-Blank Interval Free); a normal OBJ costs about 1 cycle per pixel wide, an affine one 10 + 2 per pixel (the latter quoted from GBATEK via a forum post: unverified at source) | Sprite flicker/limits show up on crowded lines; off-screen sprites also eat budget |
| Effects | 2 rect windows + object window; alpha blend (16 levels: eva/evb), fade to white/black (evy); mosaic 1..16 px, per-BG and per-OBJ; sprites can be alpha, window-mask | Spotlights, fades, battle wipes, transparent water |
| Timing | 1232 cycles/line: 960 visible + 272 HBlank; 228 lines: 160 visible + 68 VBlank | HBlank DMA gets one halfword per line into a register |
| HBlank DMA recipe | Repeat DMA, destination fixed (e.g. WIN0H), source one entry per scanline, set up in VBlank; first line needs a pre-load; DMA halts the CPU | The mechanism behind every "per-line" trick below |
| Sound | 4 legacy PSG channels (2 square, wave, noise) + 2 Direct Sound 8-bit PCM channels fed by DMA/timers; commercial games used software mixers (Sonic Advance decomp ships an `m4a` library) | Chiptune + sampled voices + MIDI-like sequences |
| Link | Game Link Cable 512 kbit/s, up to 4 devices; Wireless Adapter supported by fewer than 20 games; multiboot (one cart boots other GBAs, e.g. Sonic Advance's Collect Rings) | Link play is a genre feature (trading, versus, co-op) |
| Cartridge extras | Solar sensor (Boktai); rumble (Drill Dozer); gyro (WarioWare: Twisted!); tilt (Yoshi's Universal Gravitation); real-time clock (Pokemon Ruby/Sapphire/Emerald: berries, tides, lottery measured in elapsed days) | Peripherals defined whole games |
| Scale | About 81.5 M units sold; 1,538 licensed games listed on Wikipedia | Genre list below is of the "major" ones, not exhaustive |
| Best sellers (top 20) | 3 Pokemon RPGs on top (16.2 M, 12.0 M, 6.8 M), Mario Kart: Super Circuit 5.91 M, Super Mario Advance 1/2/4 about 5.5-5.7 M each, Namco Museum 2.96 M, Pac-Man Collection 2.94 M, LttP + Four Swords 2.82 M, Pokemon Mystery Dungeon: Red 2.36 M, Wario Land 4 2.2 M, Mario & Luigi 2.15 M, Kirby: Nightmare in Dream Land 2.1 M, Minish Cap 1.76 M, Yu-Gi-Oh! Eternal Duelist Soul 1.71 M | RPG, platformer, racing, arcade compilations, action-adventure, card game are the volume genres |

How a real engine fed these registers (pret/pokeemerald, read-only): a 64-entry sprite pool (`MAX_SPRITES 64`,
`gOamLimit` 64) with per-sprite `callback` and `data[8]`, tag-based tile-sheet and palette allocation (16 OBJ palette
slots), a 32-matrix OAM affine allocator, insertion sort by priority/Y into an OAM buffer copied in VBlank; a task
list (`NUM_TASKS 16`, `NUM_TASK_DATA 16`, priority-sorted function pointers); an overworld drawn as a 32x32 BG tilemap
**ring buffer** redrawn one metatile row/column at a time as the camera crosses 16 px steps (15x10 metatile view),
3 BG layers per map (BG1 top, BG2 middle, BG3 bottom; metatile layer types NORMAL / COVERED / SPLIT choose where
tiles go so sprites pass in front of or behind them), 512 primary + 512 secondary tiles, 6 + 7 palettes; scanline
effects as two 960-byte staging/live buffers (6 bytes per line) fed by repeating DMA0 or an HBlank interrupt.

---

## 2. Technique glossary: GBA trick -> pinyol call

| Trick | Used for (sourced examples) | pinyol today | Gap? |
|---|---|---|---|
| Affine sprite (+ double-size) | Rotating/scaling bosses and trainers (Pokemon mugshot transitions use `ST_OAM_AFFINE_DOUBLE`); rotating stick in Kuru Kuru Kururin (technique unverified) | `spr_mat(m)`, `mat(m, deg, sx, sy)`, `DOUBLE`; matrix index masked to 32; used only by `carreras` | Rotation-heavy use never exercised |
| Affine BG | Rotating/zooming worlds, Mode 7 floors | `bg(n,{mode="affine"})`, `rot`, `affine`, `mode7`, `project` | `affine()` raw call unused by any example |
| Mode 7 per-line affine (HBlank) | F-Zero: Maximum Velocity (scaling/rotation of bitmap graphics, double layer), Mario Kart: Super Circuit, Banjo-Pilot ("Mode 7-style engine"; voxel tried and dropped) | `mode7` (carreras, moto, veloz title) | See "per-line fog" below |
| Mode 7 fog / horizon | Tonc ch. 21: fog strength reuses the per-line scale, capped at 16, as the blend weight toward the backdrop; horizon switches mode 1 -> 0 in HBlank to show the backdrop | `PPU_LINE_OFF` hides lines above the horizon | **Per-line blend weight exists in the PPU (`PPU.line.fx_ev`, `ppu.c:461`) but no Lua call sets it (`lua_game.c:660` only clears it)**: no distance fog, no per-line fade |
| HBlank gradient (backdrop) | Sky gradients | `line_backdrop` (5 examples) | Per-line palette entries other than the backdrop: not exposed (unverified that games did it a lot) |
| HBlank scroll | Wavy water, parallax bands, battle ripples/swirls (Pokemon SWIRL/SHUFFLE/RIPPLE use sine offsets on BG scroll) | `line_scroll` (naves, plataformas, veloz) | OK |
| HBlank window | Circular spotlight (Pokemon cave Flash darkness via WIN0H DMA), clockwise wipe, wave, shred-split, black hole | `window`, `line_window`, `window_out` | **No example uses any window call** |
| Object window | Shape-defined masks (silhouettes, lights) | `WINDOW` sprite flag, `objwindow` | **Unused by any example** |
| Mosaic | Pokemon BLUR transition; level reveals | `mosaic` (puzle, plataformas, veloz) | OK; per-line mosaic not exposed (hardware has none either) |
| Alpha / fade | Water, ghosts, brightness fades (Pokemon mugshot BLDY DMA fade) | `blend`, `fade`, `BLEND` | Per-line fade (BLDY per line) needs the `fx_ev` binding |
| BG priority layering | Walk behind tree tops/roofs (3-layer metatiles) | `prio`, per-layer `bg()` (aldea) | OK |
| Tile streaming / ring buffer | Big overworld maps in 32x32 BG | Maps up to 1024x1024 tiles resident (`lua_game.c:129`), `mget`/`mset` | Streaming not needed on this engine; huge multi-room worlds are untested |
| Palette banks | One 16-colour sprite, many recolours (trainers, kits) | `bank(b)`, `pal=` for runtime pictures | OK |
| Bitmap modes + page flip | 3D (Doom, Duke Nukem Advance, Quake prototype), FMV | `raycast` + canvases + `video`; `inventos` 3D toy | Sector/BSP style 3D has no helper (a raycaster is enough for Wolf-style) |
| Software mixer / PSG | Music + SFX | `sfx`, `tone`, `.mod`, `studio` | `studio.*` used by no example |
| Link cable | Trading, versus, co-op, card duels, arenas | `link.*` over ESP-NOW (20 msg/s, 220 B JSON) (juntos) | Only toys use it |
| Cart sensors | Solar, rumble, gyro, tilt, RTC | `mic`, `battery`, `led` as analogues | **No IMU/tilt, no light sensor, no wall-clock** (`os` is sandboxed out; `t()` is seconds since start; `docs/hardware.md` lists no IMU/RTC) |

---

## 3. Genre table: landmarks, typical set-up, key tricks

Set-up column = typical screen/tile/sprite arrangement. Items marked `unverified` are inferences from how the
hardware worked, not confirmed rendering internals of that title.

| # | Genre | Landmarks (3-5) | Typical set-up | Key hardware tricks |
|---|---|---|---|---|
| 1 | Mascot platformer | Super Mario Advance 1/2/4 (5.4-5.7 M each); Yoshi's Island: SMA3 (2.83 M); Kirby: Nightmare in Dream Land (copy abilities, 41 levels, 4-player co-op); Wario Land 4; Donkey Kong Country | Mode 0: BG0-1 level (8x8 tiles, 16x16 metatiles), BG2-3 parallax; 16x16-32x32 hero sprites, 128 OBJ budget for enemies; sprite sheets by palette bank | Parallax by BG speed ratios; priority layering (front foliage); palette swaps for enemy variants; alpha for water (unverified per title); sprite flicker avoided by OBJ ordering |
| 2 | Speed platformer | Sonic Advance (Dimps, 6 zones x 2 acts, spin dash, rail grinding, Tiny Chao Garden, 4-player link/GCN cable); Sonic Advance 2 (decompiled, shows Dimps' C engine + `m4a` sound); Klonoa: Empire of Dreams (decomp in progress) | Mode 0 with large scrolling level; 32x32 hero; loops/slopes by per-column height tiles and layer swap (unverified) | Fast camera with look-ahead; per-line scroll for water/background bands (unverified per title); rotating sprites via affine for the spin/ball (unverified) |
| 3 | Metroidvania | Metroid Fusion (large connected world, regions joined by elevators, rooms by doors, ability gating, navigation rooms); Castlevania: Aria of Sorrow (areas gated by abilities, 4 soul types, souls tradable over link); Harmony of Dissonance (shares AoS's engine); Metroid: Zero Mission (unverified) | Mode 0: BG0 foreground, BG1 collision/tiles, BG2-3 parallax; room = tilemap swap on door, small map screen; 32x48 hero, 64x64+ bosses as OBJ groups | Room streaming via tilemap rewrite during door transition (unverified); affine/scaled boss parts (unverified); alpha for ghosts/water; palette fades; save rooms; link soul trade |
| 4 | Run and gun / action-platformer | Mega Man Zero (Mega Man X formula: dash, wall-cling, mission grade, cyber-elves); Gunstar Super Heroes (Treasure; three weapons, supercharge); Astro Boy: Omega Factor (Treasure + Hitmaker; beat-em-up/shooter hybrid, 47 Tezuka cameos, slowdown the main complaint); Contra/Metal Slug ports (unverified) | Mode 0, 2-3 BGs, 32-64 px bosses as multi-OBJ; heavy sprite counts | OBJ budget management; screen flash via fade; boss scale/rotate via affine (unverified); parallax; mission rank bookkeeping |
| 5 | Beat-em-up | Final Fight One; Double Dragon Advance; River City-like brawlers (all unverified at source, listed from general knowledge) | Mode 0, wide stage tiles, 3-4 enemies of 32x48; depth lane (Y-sort) | Y-priority sort via OAM order; BG pillars in front by priority; camera lock per wave; palette-bank enemy variants |
| 6 | Fighting | Super Street Fighter II Turbo Revival; Street Fighter Alpha 3 Upper; Dragon Ball Z: Supersonic Warriors (unverified) | Mode 0, one BG stage + parallax; two 64x64 fighters built from multiple OBJs (tile streaming of frames into OBJ VRAM, unverified) | Per-frame OBJ tile upload; palette-bank second player; alpha for hit sparks (unverified); link versus |
| 7 | Shoot-em-up | R-Type III; Gradius Galaxies; Iridion II (all unverified at source) | Mode 0/1: BG0 stars (per-line scroll), BG1-2 terrain; ship/bullets as OBJ; 128-sprite ceiling shapes bullet counts | Per-line scroll star fields; affine BG planets; bomb flashes (fade); sprite-count tuning; alpha explosions |
| 8 | Pseudo-3D racing (Mode 7) | Mario Kart: Super Circuit (5.91 M; "Mode 7"-style scaling + parallax; track rotation reported updated at 30 fps while scroll runs at 60); F-Zero: Maximum Velocity (scaling + rotation of bitmap graphics, double layer, 5 laps, boost, 2-4 link, single-cart = one course); Banjo-Pilot (Rare, flying kart racer, 16 tracks) | Mode 1 or 2: floor on BG2 affine, sky/horizon BG on a text layer, karts as scaled/rotated affine OBJs sorted by depth | HBlank-DMA/IRQ per-scanline affine matrix (zoom lambda = a_y / line, fixed-point precision: 12 bits better than 8); horizon by switching mode in HBlank; fog = per-line blend; rotation frames chosen from an angle table, mirrored by negating pa (Tonc); depth sort of sprites |
| 9 | Other racing | Rock n' Roll Racing, Need for Speed Underground, Moto Racer Advance (all unverified) | Top-down or scanline-scrolled pseudo road | Per-line scroll road (OutRun style, unverified); sprite scaling by pre-rendered frames |
| 10 | First-person / software 3D | Doom and Doom II (David A. Palmer Productions; aggressive texture mip-mapping, double-width pixel mode on Nightmare!); Duke Nukem Advance (Torus Games, own engine; rendering method unverified); Randy Linden's Quake GBA prototype (polygon scanline renderer, 10,000+ lines of ARM assembly) | Bitmap mode 4/5 with page flip; reduced resolution/double-wide pixels | Renderer in 32 KB IWRAM; self-modifying code; ROM lookup tables; palette tricks for lighting; HUD on OBJ |
| 11 | Top-down action-adventure | Zelda: The Minish Cap (1.76 M; decompiled); Zelda: A Link to the Past + Four Swords (2.82 M; up to 4 via link); Boktai (solar sensor, stealth); Sword of Mana (unverified); Grand Theft Auto Advance (top-down open world; text-only cutscenes) | Mode 0: BG0 foreground tops, BG1 objects, BG2 ground, (BG3 UI); 16x16 metatiles; OBJ for characters/enemies; room/screen scroll | BG priority walk-behind; palette cycling for water; window iris/spotlight on cave entry (unverified for Zelda, verified idiom for Pokemon); alpha lighting/night tint; link co-op |
| 12 | JRPG | Pokemon Ruby/Sapphire/Emerald, FireRed/LeafGreen (the top sellers); Golden Sun (Psynergy overworld puzzles; battle characters/backgrounds rotate for a pseudo-3D look); Mario & Luigi: Superstar Saga (timed action commands); Mother 3 (rhythm combo up to 16 hits, rolling HP); Final Fantasy I&II/IV Advance (unverified) | Overworld = tile BGs (3 layers) + sprite NPCs; battle = separate screen (BG backdrop + sprites + text window on a BG); menus as BG text boxes with window clipping | HBlank-DMA battle transitions (swirl, ripple, window wipes, mosaic blur, black hole); affine battle sprites; palette flashes; ring-buffer map; link trade/battle; RTC events (Pokemon RSE) |
| 13 | Turn-based tactics | Advance Wars (Intelligent Systems, 2001; animated battles, can be skipped); Fire Emblem: The Sacred Stones (grid, weapon triangle, permadeath, world map, 4-player Link Arena; fe7/fe8 disassembly projects exist); Final Fantasy Tactics Advance (isometric grid, Law system, jobs, clan missions, link trades); Tactics Ogre: Knight of Lodis (unverified) | Map = tile BG 16x16; cursor + unit sprites (map sprites) as OBJ; range overlays by alpha tiles; battle = side-view scene with larger animated sprites | Tile BG for terrain, OBJ for units; blend for move/attack range overlay (unverified); palette bank per army (unverified); battle-scene swap; link arena |
| 14 | Real-time grid battler | Mega Man Battle Network (18-tile 3x6 field, Custom screen: 5 chips per turn from a 30-chip folder, elements, link trade/battle) | Overworld + 3x6 field BG, sprites for navis/viruses | Hit-flash palettes; panel state by tile swap; link versus |
| 15 | Roguelike | Pokemon Mystery Dungeon: Red Rescue Team (random dungeons, hunger, turn-based; Blue is the DS version) | Tile BG per floor, sprites per creature, text log on BG | Procedural floor gen; fog of war (unverified method); tile redraw per turn |
| 16 | Puzzle | Kuru Kuru Kururin (steer a rotating stick through mazes; 200+ courses made, 4-player ghost races); Tetris Worlds, Puyo Pop, Zoo Keeper (unverified); Mario vs. Donkey Kong (unverified) | Mode 0, board as BG tilemap or sprites; one affine sprite for Kururin's stick (unverified) | Tilemap writes per drop; affine sprite rotation with collision against walls; mosaic/alpha result reveals |
| 17 | Pinball | Pokemon Pinball: Ruby & Sapphire (2 tables; Catch 'Em: reveal a silhouette with bumpers, hit it 3 times; Egg, Evolution, Travel, bonus fields; Ball Saver) | Tall scrolling BG table, sprite ball/flippers, bonus fields as separate screens | Fixed-point ball physics at 60 fps; camera scroll; BG tile swaps for lit targets (unverified); silhouette reveal (object window is the natural tool: unverified) |
| 18 | Rhythm / music | Rhythm Tengoku (2006, Japan only; 8 sets x 6 games, audio-first cues; OK/Superb ranks; remix stages); Mother 3 battle combos; Bit Generations series (unverified) | Simple scenes, 1-3 BGs, big expressive sprites; mixing runs on the same timer as the beat | Beat clock from the sound mixer, input judged against samples; per-beat animation; screen pulses by fade/mosaic (unverified) |
| 19 | Microgame / party | WarioWare, Inc.: Mega Microgame$! (over 210 microgames in 9 stages; 4 lives; speed ramp; boss games with no time limit; each coded by a different programmer); WarioWare: Twisted! (gyro: rotate the whole console, rumble feedback, recalibrates after each microgame); Mario Party Advance, Yoshi Topsy-Turvy (unverified) | One tiny scene at a time, each with its own art/sound; instant switch | Fast scene reset, asset swap, tempo ramp, transition effects; gyro as input |
| 20 | Life sim / pet / management | Harvest Moon: Friends of Mineral Town (farm, shipping, relationships, GameCube link); Pokemon RSE berries/tides (RTC-driven); Sim City 2000, Tamagotchi-likes (unverified) | Top-down tile map + large inventory UI + calendar | Long-term save state; RTC; text/menu UI |
| 21 | Card / board | Yu-Gi-Oh! The Eternal Duelist Soul (800+ cards, calendar events, password cards, head-to-head mode); Mario Party Advance, Monopoly (unverified) | UI-heavy scenes: card art as OBJ/BG tiles; text boxes | Many card images with palette banks; link duels |
| 22 | Sports | Mario Golf: Advance Tour; Mario Tennis: Power Tour; Tony Hawk's Pro Skater 2/3/4; FIFA-style football (all unverified at source) | Court/course as tile BG or affine; characters as sprites with pre-drawn rotations | Shadow sprites; scaled ball by distance (unverified); camera follow |
| 23 | Arcade / classic compilations | Namco Museum (2.96 M); Pac-Man Collection (2.94 M); Classic NES Series: Super Mario Bros. (2.27 M); Atari Anniversary Advance (unverified) | Fixed-screen tile playfields; letterboxed original resolutions | Palette-faithful art; scaled/centred 8-bit screens |
| 24 | Sensor / peripheral games | Boktai (photometric light sensor; time zone entered by player so the game simulates sun position; sunlight charges the weapon, outdoors changes the world); Drill Dozer (rumble built into a custom cart; two shoulder buttons spin the drill); WarioWare: Twisted! (gyro); Yoshi's Universal Gravitation (tilt) | Normal tile games with a new input | Input outside the d-pad; time-of-day tint by blend/fade |
| 25 | Isometric / 2.5D | Final Fantasy Tactics Advance (overhead isometric); Tony Hawk (GBA); Crash Bandicoot XS; Max Payne GBA (all but FFTA unverified) | Diamond tile maps, sprites sorted by Y+Z | Depth sort within 128 OBJ; BG tile priority for occlusion |
| 26 | Link multiplayer (cross-cutting) | Four Swords (4p); Sonic Advance (4p race/Chao search); Kirby: Nightmare in Dream Land (4p co-op); F-Zero MV (2-4p, single-cart limited to one course); Fire Emblem Link Arena; FFTA trades and co-op missions; Aria of Sorrow soul trade; Mega Man Battle Network chip trade | Same single-player engine plus link state | Cable sync (512 kbit/s, 4 devices); multiboot for single-cart play |

---

## 4. Minimum engine features per genre

`have` = pinyol provides it today (name the call). `gap` = not provided or untested; `check` = provided but no
example exercises it, so correctness/perf on the console is unproven.

1. **Mascot platformer**: tile BG scroll with `wrap=false` (have); parallax via `scroll` per layer (have); one-way/slope
   collision from Tiled tile props (have: `tiled2asset`); input buffering `btnb` (have); sprite palette banks (have);
   transparency water (have); mosaic level transitions (have); enemy swarms >128 sprites not needed.
2. **Speed platformer**: velocity/slope physics in Lua (have); camera lead/forward-only (`cam`, have); per-line scroll
   water/background (have); rotated hero sprite (`spr_mat`, check); loop/layer swap = `prio` change at runtime (check).
3. **Metroidvania**: multi-room world with per-room maps imported from Tiled (check: `tiled2asset` handles one map per
   call; a room graph and 20-50 maps is untested); fast tilemap swap on door (`bg()` swap or `mset` rewrite, check on
   device); persistent flags/map-explored state in `store` (have, 64 KB cap); ability gating (game logic); minimap
   (canvas or tiles, have); big bosses (packed pictures or `spr_mat` + `DOUBLE`, check); boss HP bars/text (have).
4. **Run and gun / action-platformer**: bullet swarms (`swarm`, have); screen flash/shake (`juice`, have); sprite
   budget for many enemies (128 OBJ + `img` overlay, have); rank/mission screen with `store` (have).
5. **Beat-em-up**: Y-sorted depth lanes (have: calle, mazmorra); camera lock per wave (have); hit-stop (`juice.freeze`).
6. **Fighting**: packed pictures, mirrored frames, palette swap (have: duelo, torneo); frame-data/hitbox logic (Lua).
7. **Shmup**: per-line scroll stars (have); swarms (have); bomb fade/flash (have); boss patterns (Lua).
8. **Mode 7 racing**: `mode7`, `project`, scaled sprites (have); per-line fog = per-line blend weight (**gap**, `fx_ev`
   not bound); horizon sky (have via `PPU_LINE_OFF`); sprite depth sort (Lua); link versus (check).
9. **Other racing**: top-down road as tile BG (have); OutRun scanline road via `line_scroll` (check); pre-rotated
   car sprites by angle (have via `spr_mat` or `img` angle).
10. **FPS / 3D**: `raycast` (have: laberinto, museo_nocturno); wall heights/doors/secret walls beyond uniform walls
    (check); sector or BSP style rooms with floors at varied height (gap; not needed for Wolf-style).
11. **Top-down action-adventure**: tile BG layers with priority (have); NPC dialogue/story (have: `story`, `rich`);
    enemy AI on a grid (`grid`, check); push blocks, keys, doors, items (kit "push"/"grid" kinds exist; no example);
    spotlight/cave dark via `window` + `line_window` (check: unused); day/night tint via `blend`/`fade`/`line_backdrop`
    (have); wall-clock time (gap: no RTC; `os` is sandboxed).
12. **JRPG**: overworld (have: aldea); encounter trigger and a battle scene (scene stack `scene`, check: unused by examples);
    battle transitions needing `line_window` spans per line, `line_scroll` sine, `mosaic`, `fade` (check; per-line
    fade = gap); menus/text boxes (`panel`, `plate`, `frame`, `rich`, have); party/inventory/flags in `store` (have,
    64 KB total: sizing check); typed dialogue (have); affine battle sprites (check); music swap (have); link trade
    (check, 220 B message cap); RTC events (gap).
13. **Tactics**: `grid` with `path`/`reach`/`distances` (have in C; **no example**, only `tests/grid.script`); cursor,
    range overlays with `blend` or `shade` (have); unit sprites by army palette bank (have); battle scene with big
    sprites (have: packed pictures); AI with distance fields (`layer:climb`/`descend`, have); permadeath/save in
    `store` (have); link arena (check).
14. **Real-time grid battler**: 3x6 grid tile swaps (`mset`, have); chip UI (have); hit flashes (`tint`, have).
15. **Roguelike**: procedural map in Lua + `grid`; deterministic RNG: `math.random` starts from the same seed every run
    (documented), so the game must seed itself, e.g. from the tick count at the first press (check); fog of war via
    `window`/`objwindow` or shade overlay (check); `store` for permadeath/hall of fame; text log (have).
16. **Puzzle**: tilemap writes per drop `mset` (have); line-clear flash via `fade`/`mosaic` (have); rotating stick with
    pixel-accurate collisions: `spr_mat` + `pget` on a canvas or line/polygon tests (check; 8.8 matrix precision);
    touch/d-pad both (have).
17. **Pinball**: `physics` world (have; **no example uses it**; only `tests/games/*`); flippers need a driven (kinematic)
    rotating body (unverified whether `physics` has one: the documented options are `static`, `mass`, `bounce`,
    `friction`, `turns`); anti-tunnelling for a fast ball at 60 Hz (check); tall camera scroll (have); multi-ball (256
    body cap, have); silhouette reveal with `objwindow`/`WINDOW` (check, unused); rumble analogue = `led`.
18. **Rhythm**: `music_time`, `studio.pos`, `.mod` playback with a clock across loops (have); judging window about
    50 ms vs a 17 ms input tick (have, documented); offset calibration via `store` (have); sprite/beat sync, `anim`
    events (have: `anim` lib; used only in puzle); on-beat screen pulses `blend`/`fade`/`mosaic` (have).
19. **Microgame**: `scene` stack with `scene.go` clean-up of sprites/tweens (have; no example); fast asset load/unload
    (4 MB picture cache lets go least-recently-drawn; "a moment's load" the first time: check against a 3-5 s
    microgame budget); full PPU state reset between scenes (`spr_clear`, `line_off`, `fx_off`, `window_off`,
    `mosaic(1,1)`, `show(ALL)`: check there is no leak from a previous microgame); `sound()` generation cost (have, "some
    hundredths of a second" per long sound); tilt/gyro input (gap: no IMU; substitute touch drag, mic blow, d-pad).
20. **Life sim**: calendar/clock (gap: no wall clock; tick-based game days work); large save (`store` 64 KB cap: check
    against farm + inventory + relationships); inventory UI (have); tile map with many objects (have).
21. **Card / board**: card art as `img` with `pal`/`tint` (have); text-heavy UI (`rich`, `text` styles, have); rules
    engine in Lua; link duels with state sync (have: `link`, check at 20 msg/s); card collection in `store` (check size).
22. **Sports (golf/tennis/skate)**: aim/power meters (have: `btnt`, `btnr`); ball + shadow sprites with scale by height
    (have); isometric or 3D-ish court by `mode7` or sprites (have).
23. **Arcade classics**: fixed screens, canvases (have: rocas, ladrillos, paletes); maze-chase AI on a grid (`grid`,
    `distances`; unused example).
24. **Sensor / peripheral games**: `mic`, `battery`, `led` (have: control); IMU/tilt, light sensor, rumble (gap).
25. **Isometric**: depth sort across up to 128 OBJ (Lua sort + `spr` order, check); diamond tile maps as sprites or a
    canvas (no native isometric BG).
26. **Link multiplayer**: reliable-enough state sync under packet loss (documented approach: send state often);
    consistent player order from `link.peers()` (have); a real game on top (gap in examples).

---

## 5. Coverage vs pinyol (`examples/`)

Status: COVERED, PARTIAL (a slice of the genre), MISSING (nothing in `examples/`). Audited by reading each
`main.lua` header and grepping API use; `games/micromiserias` (a Spanish digestion-puzzle scene) and the editor
`kit` games were not counted. Sibling projects under `~/Desktop/DEV/pinyol/` (audreygotchi, Castells, etc.) were not
examined.

| # | Genre | Example(s) | Status | Note |
|---|---|---|---|---|
| 1 | Mascot platformer | plataformas (GBA look), bolsillo, raton_de_biblioteca (Game Boy look), cinta, oxigeno (ZX look, single screen) | COVERED | plataformas is the GBA reference |
| 2 | Speed platformer | veloz (16-bit), costa_relampago (Mega Drive look: ramps, loop, springs) | COVERED | |
| 3 | Metroidvania | gotico (one hall + skull boss, 32-bit look) | PARTIAL | no room graph, map screen, or ability gating |
| 4 | Run and gun | asalto | COVERED | Mega Man Zero-style dash/wall-cling/rank not shown |
| 5 | Beat-em-up | calle, mazmorra | COVERED | |
| 6 | Fighting | duelo, torneo | COVERED | |
| 7 | Shmup | naves (GBA look), nubes (H, battleship), tormenta (vertical, rotated canvas) | COVERED | |
| 8 | Mode 7 racing | carreras, moto | COVERED | fog / distance fade absent |
| 9 | Other racing | none | MISSING | top-down or OutRun-style scanline road; low priority |
| 10 | FPS / software 3D | laberinto, museo_nocturno (raycast), inventos (3D toy) | COVERED | |
| 11 | Top-down action-adventure | aldea (talk, chest), hola (data adventure) | PARTIAL | no combat, dungeon, keys/items loop, boss, or cave lighting |
| 12 | JRPG | aldea (overworld/dialogue only); control (story lib) | MISSING | battle scene, encounters, menus, party data, transitions |
| 13 | Tactics | none (`grid` has only `tests/grid.script`) | MISSING | |
| 14 | Real-time grid battler | none | MISSING | |
| 15 | Roguelike | none | MISSING | |
| 16 | Puzzle | puzle (sliding), ladrillos (breakout) | PARTIAL | falling blocks, match-3, rotating-stick maze missing |
| 17 | Pinball | pinball | PARTIAL | one table: no scrolling, bonus fields or multi-ball; flippers use `w:drive` |
| 18 | Rhythm | control (cuts on the beat of a theme), sonidos | PARTIAL | no rhythm game proper; `studio.*` unused by examples |
| 19 | Microgame / party | none | MISSING | |
| 20 | Life sim / pet | none | MISSING | |
| 21 | Card / board | none | MISSING | |
| 22 | Sports | futbol (5-a-side), paletes (pong) | PARTIAL | golf, tennis, skate missing |
| 23 | Arcade classics | rocas, ladrillos, paletes, huevos (LCD) | COVERED | maze-chase (Pac-Man) missing |
| 24 | Sensor / peripheral | control (mic, battery, LED, video) | PARTIAL | no IMU/tilt, light sensor or RTC to build on |
| 25 | Isometric / 2.5D | none | MISSING | |
| 26 | Link multiplayer | juntos (whiteboard, ball passed between screens) | PARTIAL | no competitive/co-op game |

Engine surface that **no example exercises** (grep of `examples/*/main.lua` and sibling `.lua`): `window`,
`window_out`, `window_off`, `line_window`, `objwindow` / `WINDOW`, raw `affine()`, `grid`, `physics`, `scene`, `cam`,
`rich`, `keyboard`, `input`, `anim` (puzle only), `kit`, `studio.*`, `btnr`/`btnt`. `spr_mat`/`DOUBLE` is used only by
carreras, `rot` only by naves, `fade` only by naves and plataformas, `swarm` only by nubes/tormenta. (Several of
these have `tests/` coverage; that proves they run, not that a real game feels right on the console.)

Doc mismatch spotted: `src/ppu.h` says an object's source size is "up to 128 x 128"; `docs/lua.md` says "Frames are up
to 255x255 pixels". Check which is true (the fields are `uint8_t`).

---

## 6. Missing genre examples worth building next (ranked, max 10)

Ranking = how common the genre was on the GBA (sales/landmarks above) x how much currently unexercised engine
surface it forces open. Each entry lists the stress it applies and the gaps it is likely to reveal.

1. **JRPG with a Pokemon-style battle (overworld, encounter, transition, battle, menus).**
   Stress: `line_window` per-line spans (clockwise wipe, circle, wave), `line_scroll` sine ripple/swirl, `mosaic` blur,
   `fade`; `scene` stack (overworld -> battle -> overworld); `spr_mat` + `DOUBLE` on battle sprites; `panel/plate/rich`
   menus; party + inventory in `store` (64 KB cap); `story`; music swap; link trade (220 B cap). Likely gaps: per-line
   blend/fade (`fx_ev` unbound), cost of rewriting 160-line tables every frame on the ESP32-S3, scene-change memory.
2. **Turn-based tactics (Advance Wars / Fire Emblem).**
   Stress: `grid` (`path`, `reach`, `distances`, `layer` smell/danger maps) in a real game with the documented
   5 ms/64x64 path budget; range overlays with `blend` or `shade`; cursor/unit sprites and army palette banks; side-view
   battle scene with packed pictures; AI on distance fields; mid-battle save; link arena. Likely gaps: AI turn cost spikes
   in `_update`, UI for 30-unit maps, `store` size of a mid-battle state.
3. **Metroidvania (Fusion / Aria of Sorrow).**
   Stress: many rooms from `tiled2asset` (one call per map), door transitions swapping BG maps in under a frame, an
   explored-map screen on a canvas, ability gating and flags in `store`, affine/packed bosses, parallax + per-line water,
   `cam` bounds per room, the 4 MB picture cache across areas. Likely gaps: multi-room import workflow, memory
   with 30+ maps, room-swap hitch, sprite budget in big boss fights.
4. **Pinball (Pokemon Pinball).**
   Stress: `physics` in anger (convex polys, bumpers, ramps, multi-ball under the 256-body cap), fast-ball tunnelling at
   60 Hz, tall scrolling table via `cam`, bonus fields as separate screens, `objwindow`/`WINDOW` for the silhouette
   reveal, `led` as rumble. Likely gaps: no kinematic/driven body for flippers (verify), no continuous collision
   detection, `w:hits()` granularity. Cheapest of the ten to build and the only way to test `physics` on a real game.
5. **Microgame collection (WarioWare).**
   Stress: `scene.go` hygiene across 10-20 tiny games, full PPU/sprite/window/mosaic reset between games, speed ramp,
   asset load latency under the 4 MB cache, `sound()` generation time, transitions, touch/mic/d-pad inputs in place of the
   gyro. Likely gaps: state leaking across scenes, first-draw load hitches, `_init` cost, no IMU.
6. **Top-down action-adventure with combat and dungeons (Minish Cap / Boktai).**
   Stress: BG priority walk-behind, enemy AI with `grid` distances, push blocks/keys/doors (the `kit` kinds), cave
   spotlight via `window` + `line_window`, object-window light cones, day/night tint via `blend`/`line_backdrop`, boss with
   affine sprite, link co-op. Likely gaps: wall-clock time of day (no RTC), window spotlight cost, `kit` vs hand-written Lua
   ergonomics.
7. **Rhythm game (Rhythm Tengoku).**
   Stress: `music_time`/`studio.pos` against a chart, 50 ms judgement with 17 ms input ticks, offset calibration in `store`,
   per-beat animation via `anim` events, beat pulses by `fade`/`mosaic`, tempo-change songs, `.mod` clock across loops.
   Likely gaps: audio-visual latency on the console speaker vs display, `studio.*` untested in a real game.
8. **Roguelike (Mystery Dungeon).**
   Stress: procedural generation with `noise`/`grid`, deterministic RNG (seed problem: `math.random` is fixed at start),
   fog of war by windows or shade overlay, `layer:spread` for noise/smell, turn-based log UI, permadeath in `store`.
   Likely gaps: seeding, fog-of-war primitive, long-run memory growth.
9. **Puzzle pair: Kuru Kuru Kururin-style rotating stick maze (and/or falling-block puzzle).**
   Stress: `spr_mat` + `mat` precision (8.8 matrices), rotated-polygon vs wall collision (`poly`, `pget`, `mget`), 32-matrix
   limit with several sprites, `mset` writes and line-clear effects for the falling-block half, 4-player ghost races over
   `link`. Likely gaps: sub-degree rotation smoothness, no helper for pixel collision of a rotated sprite.
10. **Life sim with a calendar (Harvest Moon / Pokemon RSE berries).**
    Stress: `store` near its 64 KB cap (crops, inventory, relationships), long-running day/season clock (the engine has
    no wall clock: ticks only), inventory UI, big tile maps, tool/stamina systems. Likely gaps: the missing RTC (decide
    whether to add `date()`), save size, save-flush behaviour (written a second after the last `store`).

**Honourable mentions** (not ranked): golf/tennis (aim meters, scaled ball + shadow), card duel game (UI-heavy, link
duels), isometric tactics/skate (Y+Z depth sort), Pac-Man maze-chase (`grid` + `distances`), co-op/versus link game
(Four Swords style; stresses `link` far beyond `juntos`).

## 7. Concrete engine gaps surfaced while mapping (verify, then decide)

1. `PPU.line.fx_ev` (per-line blend weight, `src/ppu.c:461`) is implemented but unreachable from Lua: needed for Mode 7
   fog (Tonc ch. 21), per-line brightness fades (Pokemon mugshot BLDY DMA).
2. No `object window` / `window` example, so spotlights, silhouette reveals and battle wipes are untested on device.
3. No wall-clock (`os` removed, `t()` = seconds since start): Pokemon RSE (RTC), Boktai (time of day), life sims.
4. No tilt/gyro/light sensors in `docs/hardware.md` (WarioWare: Twisted!, Yoshi tilt, Boktai have no pinyol analogue; `mic`
   and touch are the substitutes).
5. `math.random` is fixed-seed by design: procedural games need a documented way to seed (e.g. from `ticks()` at first input).
6. ~~`physics` documents no driven/kinematic body~~: it had none (a static body was never moved by the step and what it hit felt a wall that jumps). `w:drive(body, angle, px, py)` is one now (`src/lua_physics.c`: the pose goes to its target a substep at a time, with the speed of its surface; `tests/drive.script`). Found by building `examples/pinball`, which also needed a ball that falls back to the spring to be shot again, a saver that counts once a ball, and a ball parked at the game's end: all three were soft-locks the autopilot in `tests/pinball.script` found.
7. `store` caps at 64 KB total: RPG parties, card collections and life-sim state may need budgeting guidance.
8. Check `ppu.h` (128x128) vs `lua.md` (255x255) sprite size statement.

---

## Sources

Hardware: GBATEK (https://problemkaputt.de/gbatek.htm: modes, OBJ limits, timing, 1210/954 cycle budgets); Tonc via the
gbadev.net mirror (coranac.com did not resolve): `affbg`, `dma`, `bitmaps`, `regobj`, `affobj`, `regbg`, `gfx`
(windows/blend/mosaic), `mode7`, `mode7ex`, `sndsqr`.
Architecture: pret/pokeemerald (`src/battle_transition.c`, `src/task.c`, `src/sprite.c`, `src/field_camera.c`,
`include/fieldmap.h`, `include/sprite.h`, `include/task.h`, wiki "Scanline Effects", "Triple layer metatiles");
SAT-R/sa2 README; zeldaret/tmc README; FireEmblemUniverse/fireemblem8u README (none of these three READMEs describe
engine internals).
Games (Wikipedia unless noted): List of Game Boy Advance games; List of best-selling Game Boy Advance video games;
Game Boy Advance; Mario Kart: Super Circuit (search snippet); F-Zero: Maximum Velocity; Banjo-Pilot; Kuru Kuru
Kururin; Drill Dozer; Rhythm Tengoku; Metroid Fusion; Castlevania: Aria of Sorrow; Fire Emblem: The Sacred Stones;
Final Fantasy Tactics Advance; Pokemon Pinball: Ruby & Sapphire; WarioWare: Twisted!; WarioWare, Inc.: Mega
Microgame$!; Astro Boy: Omega Factor; Gunstar Super Heroes; Mega Man Zero; Mother 3; Mario & Luigi: Superstar Saga;
Mega Man Battle Network; Pokemon Mystery Dungeon: Red/Blue Rescue Team; Golden Sun; Harvest Moon: Friends of Mineral
Town; Sonic Advance; Kirby: Nightmare in Dream Land; Yu-Gi-Oh! The Eternal Duelist Soul; Grand Theft Auto Advance;
Boktai: The Sun Is in Your Hand. Doom GBA: DoomWiki and Nintendo World Report snippets (search). Quake GBA:
https://www.xda-developers.com/how-quake-ported-game-boy-advance/. Pokemon RTC: PokeBase / Bulbagarden forum threads
(search).
pinyol: `docs/lua.md`, `src/ppu.h`, `src/ppu.c`, `src/lua_game.c`, `docs/hardware.md`, `README.md`, each
`examples/*/main.lua` header, `tests/` listing.
