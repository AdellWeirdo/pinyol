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
| HBlank gradient (backdrop) | Sky gradients | `line_backdrop` (5 examples), `line_pal` / `line_pal_obj` (`horizonte`) | Per-line mosaic size: not exposed |
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
23. **Arcade classics**: fixed screens, canvases (have: pozo, ladrillos, paletes); maze-chase AI on a grid (`grid`,
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
| 1 | Mascot platformer | plataformas (GBA look), raton_de_biblioteca (Game Boy look; bolsillo in tests/games), cinta, oxigeno (ZX look, single screen) | COVERED | plataformas is the GBA reference |
| 2 | Speed platformer | veloz (16-bit), costa_relampago (Mega Drive look: ramps, loop, springs) | COVERED | |
| 3 | Metroidvania | cripta (eight rooms from Tiled, two abilities, map, statues, a boss); gotico (one hall + skull boss) | PARTIAL | eight rooms, not thirty: the picture cache and memory across many areas are not tried |
| 4 | Run and gun | asalto | COVERED | Mega Man Zero-style dash/wall-cling/rank not shown |
| 5 | Beat-em-up | calle, mazmorra | COVERED | |
| 6 | Fighting | duelo, torneo | COVERED | |
| 7 | Shmup | naves (GBA look), nubes (H, battleship), tormenta (vertical, rotated canvas) | COVERED | |
| 8 | Mode 7 racing | carreras, moto | COVERED | fog / distance fade absent |
| 9 | Other racing | none | MISSING | top-down or OutRun-style scanline road; low priority |
| 10 | FPS / software 3D | laberinto, museo_nocturno (raycast), inventos (3D toy) | COVERED | |
| 11 | Top-down action-adventure | aldea (talk, chest), hola (data adventure) | PARTIAL | no combat, dungeon, keys/items loop, boss, or cave lighting |
| 12 | JRPG | combate (meadow, encounters, fight by turns, party saved); aldea (dialogue) | PARTIAL | no shops, equipment, status effects, story or link trade; one spell each |
| 13 | Tactics | tablero | PARTIAL | one 15 x 10 field, no side-view battle scene, fog, army palettes or link arena |
| 14 | Real-time grid battler | none | MISSING | |
| 15 | Roguelike | sima (five generated floors, fog, a chasing crowd on one distance field, the day's seed) | PARTIAL | no inventory beyond potions, no hunger, traps or allies, no saved run |
| 16 | Puzzle | puzle (sliding), ladrillos (breakout) | PARTIAL | falling blocks, match-3, rotating-stick maze missing |
| 17 | Pinball | pinball | PARTIAL | one table: no scrolling, bonus fields or multi-ball; flippers use `w:drive` |
| 18 | Rhythm | control (cuts on the beat of a theme), sonidos | PARTIAL | no rhythm game proper; `studio.*` unused by examples |
| 19 | Microgame / party | microjuegos | PARTIAL | eight games, speed ramp, boss; no touch, microphone or tilt games, no assets loaded per game from the card |
| 20 | Life sim / pet | none | MISSING | |
| 21 | Card / board | none | MISSING | |
| 22 | Sports | futbol (5-a-side), paletes (pong) | PARTIAL | golf, tennis, skate missing |
| 23 | Arcade classics | pozo, ladrillos, paletes, huevos (LCD) | COVERED | maze-chase (Pac-Man) missing |
| 24 | Sensor / peripheral | control (mic, battery, LED, video) | PARTIAL | no IMU/tilt, light sensor or RTC to build on |
| 25 | Isometric / 2.5D | isla (a grid island: heights, crates, depth-sorted sprites) | PARTIAL | no isometric tactics or skate, no map with more standing things than 128 sprites |
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

## 7. What building the JRPG showed (`examples/combate`)

The ranked list expected per-line effects, `scene` and the 480 x 320 menus to be where a JRPG would find gaps. What it found:

- **`line_window`, `window`/`window_out`, `line_scroll`, `mosaic`, `fade`, `spr_mat` all work together** (a flash, a ripple, a blocky screen and an iris
  closing on the hero, then a fight). Nothing in the engine had to change. On the console the meadow is 60 fps, the swirl's second 47-52,
  the fight 59.5-59.8.
- **`DOUBLE` cost four times the pixels**: three enemies of 64 x 64 drawn in a 128 x 128 area took the fight from 59.6 to about 40 fps
  (render 15.4 to 23 ms), and the game turned it on only while an enemy spins away. Since then the renderer works out, for each line, the span where a
  turned sprite's source falls inside it, and steps its coordinates by additions: on a computer 16 turned 64 x 64 sprites went from 607 to 67 us a frame
  with the double area (204 to 64 without), the same pixels (`g.obj-affine-turns`, a golden of 24 sprites turned, scaled, sheared and mirrored every way).
  On the console the 15 reference scenes did not move (+0.02 %); 128 turned sprites in their double area are 4.26 M cycles a frame.
- **`scene.go` leaves no effect behind**: `tests/combate.script` compares the meadow's frame before a fight and after it (same party on the screen) and
  they are the same bytes; the game still resets the PPU's effects when each scene begins (`ppu.lua`), and a mutant that does not is caught by that comparison.
- **Bugs in the game, found by playing whole fights with an autopilot** (not the engine's): the last enemy falling in the middle of a turn skipped the victory
  check and sent the player back to a menu with nothing to hit; the menu's down arrow moved one entry instead of the other row; the theme's panel is
  parchment, where white letters do not read (the game draws its own dark box, `ui.lua`).
- **For script tests**: `#` starts a comment anywhere in a line of a `.script` (not only at its start), so `#t` in an `expect_lua` is cut off; use
  `t[3] ~= nil` or `select`. A script line is also limited in length.

## 8. What building the tactics game showed (`examples/tablero`)

`grid` had only a script test; this is its first game. What it found:

- **`grid` is enough for the genre as it stands** and nothing in the engine changed: `g:reach` for a unit's moves, `g:path` for the walk it
  animates, `g:distances` (one search from all the enemies) for the AI's "nearest", and a `g:layer()` filled by `l:add` as the danger map.
  On the console 25 s of the AI playing itself (four units deciding each turn, a danger map after each blow) had no slow tick but the two
  scene loads, at 60 fps with `_update` at 0.3-0.8 ms on average.
- **Units that block** are the one thing `grid` does not know: the enemy is a wall for a unit's move, its own side is not (but cannot be stood on).
  The game builds a grid for the unit's move with the enemy's cells set to 0 (`rules.cost_grid`), 150 `g:set` calls on this field. On a 64 x 64 one
  that would be 4096 a call: a temporary wall (`g:block(x, y)` and back) or a copy of a grid is what a big map would want. Not measured.
- **Highlights on a second layer** work and are cheap: `mset(1, tx, ty, tile)` four tiles a cell, only the cells painted last time cleared,
  blended over the ground with `blend(BG1, BG2, 7, 9)`. The picture that makes the layer carries the swatches in its top row and the game
  reads their tile numbers with `mget` and empties the layer when it begins.
- **For script tests** `#` is a comment anywhere in a line (the same as `combate` found): a counting helper (`cnt`) in the script's first line
  does what `#t` cannot.

## 9. What building the microgames showed (`examples/microjuegos`)

The list expected `scene.go` hygiene, the full reset of the picture between games and the load time of each game to be the problems. What it found:

- **`scene.go` did not reset the picture's effects**, only the sprites and juice's tweens. A game that leaves a fade, a window with its per-line
  spans, a mosaic, a hidden layer, a note of the synthesiser or the LED leaves them to the next. Two examples (`combate`, `tablero`) had each copied the
  same reset by hand. Now it is `scene.clean()` in `lib/scene.lua`, and `scene.go(s, args, {clean = true})` calls it; `docs/lua.md` says so. The game
  keeps eight microgames that each leave one of those on purpose, and `tests/microjuegos.script` draws a plain scene after each and compares its frame
  with one drawn from nothing: the same bytes. Mutants of `clean` (without `fx_off`, `mosaic`, `show(ALL)`, `line_off`, `led`, or `go` ignoring the option) are caught.
- **What cannot leak is not worth cleaning**: `camera` and `clip` are one drawing's state (the engine resets them each frame), and `window_off(0)` after
  `line_off()` is invisible (the window then covers the whole picture). The reset leaves them out, or keeps the redundant call, as the case is.
- **Load time is not a problem on the console**: thirteen games in a run, each with its backdrop and its sheet loaded as it begins, 59.4-60 fps and no slow tick
  after the first scene's 55 ms.
- **The bots were the bug**: a demonstration played by each game's own `bot` lost on the console what it won on the host, because one bot ran into the
  rocks and only some random numbers showed it. A sweep of the first verdict of each game under several seeds (`math.randomseed`) found it, a bot that moves
  to the nearest free gap instead of away from the nearest rock fixed it, and the test keeps the sweep (5 seeds a game). A game played by a bot should be tested under
  many seeds, not the one a run happens to have.
- **For script tests**: `#` is a comment anywhere in a line (a third time): `bad[#bad + 1]` was cut to `bad[` and the check that used it passed; write `bad[k] = true`.
  The generic `script_<name>` test runs every script with `--check-strips`, which is several times slower than the plain run: a script of 27 000 ticks took 75 s
  there, and one of 17 000 took 26 s.

## 10. What building the per-line palette showed (`line_pal`, `examples/horizonte`)

- **The engine had to change here, and the cost of changing it was the story.** The renderer read the palettes at five places, all at the registers' own
  (constant) addresses. Reading them through a per-line pointer cost 2 to 7 % on the console on every scene, used or not: a pointer held in a register in the
  inner pixel loops of an in-order core with 16 registers is not free. What keeps the common path at +0.3 % (15 scenes, same frame hashes) is building the layer
  and sprite functions twice and choosing per line: the registers' palettes as before, or the line's (`ppu.c`, `layers_*` and `layers_*_lp`).
- **Using it costs about a thousand cycles a line** (a copy of the palettes each core makes once a frame, then a patch and a restore of the entries a line changes),
  mostly the line tables being in PSRAM: 160 lines with both palettes, 8 + 8 entries, over 4 layers and 128 sprites, are 4.39 M cycles against 4.08 M without.
  Whether that is memory latency was not settled (the measurement that would have told, with the tables in internal RAM, was not run).
  On a real scene it does not matter: `horizonte` with the animation paused draws its frame in 5.25 ms of the renderer's "world" with a palette on
  every line against 5.15 ms flat, 60 fps either way.
- **The game's own colour code was the cost, not the engine's**: the first `horizonte` ran at 14 fps on the console, with `_draw` at 52 ms, because each of the
  160 lines made tables of Lua for its colours (`mix` returned a table) and called `math.floor` and `math.min` seven times a colour; on the console each call into C and each
  table made is paid for. Written with numbers in tables made once, `rgb` taking the fractions, and the line tables repainted only when the colours move
  (they stay until `line_off`) and a part of the sky each frame, it runs at 55 fps with everything on (the sea's shimmer, sixty lines of colour a frame, is the part
  that remains), 59 without it and 60 flat. A game that writes a palette per line should do the same.
  Since then `line_ramp(y0, y1, index, from, to [, curve])` does a gradient in one call: `horizonte` paints its sky, clouds, hills, sail and sun
  with eight of them a frame (about 300 calls into C a frame before, 70 now: the sea's shimmer is a wave, not a ramp, and stays a call a line).
  `tests/ramp.script` and the `line_ramp` CMake test hold it to the picture of the same arithmetic done with `line_pal`. On the console (`tests/games/ramp`
  sent over the cable: three gradients down all 160 lines, redone every frame): `_draw` 0.58 ms with `line_ramp`, 4.97 with `line_pal` on every line,
  the picture 0.91 ms either way, 60 fps both.
- **Backdrop gradients with `line_backdrop` do not need it**; a tile art that is made of a few palette entries does: the sky of `horizonte` is one colour in
  the art and a hundred on the screen, the sea three, the boat's sail and the sun a gradient each, and a flat comparison (A) shows what is lost.
- **A property test, not only goldens**: `tests/ppu_linepal_test.c` checks every pixel of lines that replace entries in each reader of the palette (tiles,
  mosaic tiles, a turned layer, a bank, the backdrop, sprites, a turned sprite), the patch and restore of lines after one another, and the registers' palette
  changing between two frames. A dozen mutants of the renderer are caught.
- **For script tests** a comparison of two shots has to be of the picture alone: the HUD's text ("per-line palette: yes/no") made "on differs from off" true whatever
  the engine did, and a mutant that never cleared the tables survived until the shots were taken with the HUD hidden and compared with a frame drawn before the
  function was ever used.

## 11. What building the metroidvania showed (`examples/cripta`)

- **The multi-room Tiled workflow works as it is**: each room is its own `.tmx` (a tile layer and an object layer), `tools/tiled2asset.py` imports each into
  `assets/ROOM_<ID>_SUELO` and `room_<id>.lua`, and where a room is in the castle is two map properties (`mx`, `my`, in screens). Nothing in the tool or
  the engine changed. A room changed in Tiled is checked by the same code the tests run (`checks.lua`).
- **Changing rooms costs nothing on the console**: the hero walks the castle in castle pixels and the game only puts the next room's map on BG1
  (`bg(1, {map = ...})`); walking through all eight rooms gave 57.6-58.8 fps and no slow tick at a room change. `rooms.lua` (a picture backdrop and a
  curtain) is for adventures, not for this: a tile room needs none of it.
- **A save stalled the picture, and it was the save task's priority**: touching a statue logged a 60-80 ms write to the card and, next to it, a frame
  as long. The write is not on the game's thread: the console hands `store()` to a task of its own (`saver_task`, `firmware/main/main.c`). That task
  ran at priority 2 with no core of its own, above the game loop (priority 1, core 0), and while the card wrote it held core 0. Measured on the board,
  three times each, a save standing still and a save while rooms kept loading: unpinned at priority 2, a 46-79 ms frame in 5 of 6 and a 69 ms tick in one;
  pinned to core 1 at priority 1 (under the picture's half, the display and the mixer there), none in 6, the write itself 84-110 ms in the background.
  The other guesses were wrong: not the card's file lock (it stalled standing still, reading nothing), not a flash write (the saves are on the card).
  (A first version of this paragraph said the write was on the game's thread; it was not.)
- **The design is proved, not only played**: `world.lua`'s solver (where a hero that climbs 3 tiles, or 5 with the wings, and dashes through cracked
  walls can stand) checks the order (nothing gets the wings; the wings get the gust; both get the gargoyle and the heart), with a careful reach across
  (3 tiles: what surely can be done) and a long one (7: what may be done), and that nothing reachable is a trap (one search forward, one back over the same
  moves). The solver found two mistakes in the first plans: the heart and the gargoyle could be had without the gust, by jumping over cracked walls that
  did not reach the ceiling. The physics is held to the solver's numbers by the test (one jump climbs 54 px, two 92: more than 3 and 5 tiles, less than 4
  and 6); the first double jump climbed 99 px, six tiles, and was lowered.
- **Not proved**: that the gargoyle can be beaten by hand with three hearts (the test beats it with hearts that do not run out), and the whole castle played
  through with the buttons (the test moves the hero between the places it checks).

## 12. What building the isometric island showed (`examples/isla`)

- **Depth order is a sort of the sprite numbers, and the engine needs nothing more**: the ground is one tiled background (61 different tiles for a
  400 x 240 picture of a 12 x 12 island: the 2:1 diamonds repeat), and every column, crate, palm, gem, the hero and its shadow are sprites. Each frame
  `view.lua` sorts them by the depth of their cell (`x + y`, then a layer: a sunk crate, a block, a shadow, what stands on top) and gives the nearest
  sprite 0, as a GBA game re-sorting OAM had to. A thing between two cells counts as the one it is mostly in; with that, a hero walking past a tower
  is never drawn over the column in front of it. `tests/isla.script` and the `isla_depth` CMake test prove it with pictures: behind the four-block
  tower the frame is the same as the one without the hero; in front of it, it is not. A sort turned the wrong way fails both.
- **The cost on the console is small, and what it found was the garbage collector's**: playing the island on the board, `_update` 0.6 ms, `_draw`
  2.5 ms (the sort and the `spr` calls for about 20 things), the picture 3.3. Yet the play ran at 58 fps with 96 frames of 32 ms a minute: the
  tables made each frame for the sort, left to Lua's incremental collector, grew into cycles whose steps took a scan. Switched to Lua's generational
  mode (`collectgarbage("generational")` sent to the running game), the same play gave 7 slow frames in 40 s and 59.2-59.8 fps with the same
  memory (80-160 KB). The engine now starts every game in generational mode (`src/lua_game.c`, `v2_load`; `tests/sandbox.script` checks it), so
  every game that makes tables in its frame gets it. Flashed and played again for a minute: 59.4-59.6 fps, 17 frames over 20 ms (111 before).
  Another game gained too: Castells' heaviest scene (4 de 9 F standing) went from 56.5-58.5 to 58.8-59.0 fps, `_draw` 3.6 to 3.3 ms,
  no audio underruns.
- **A shadow under a GBA sprite cannot be blended with another sprite under it** (the object layer holds only the top sprite's pixel; a blended one
  mixes with the backgrounds), so the hero's shadow is a checker of a dark colour, the old dither, which reads over a column top as over the grass.
- **The design is proved, not only played**: `iso.reach` (where the hero can get without pushing a crate) shows that only the first two gems can be had
  that way, and the test plays the whole island with the keys in 34 moves, both crates pushed (one against the low pillar, one into the channel).
- **For tests**: the headless player runs `_draw` only for a `shot`, so what a game works out while drawing (here the sprites' order) is read after
  one (`docs/lua.md`, Testing). The first version of the test read it after `tick` and found an empty list.
- **Not tried**: a map with more standing things than the 128 sprites (a bigger island would need culling by the camera, which `view.lua` does, and
  columns merged into the ground picture where nothing can pass behind them), and the occluding parts of the ground on a second background layer, the
  other way GBA isometric games split a scene.

## 13. What building the roguelike showed (`examples/sima`)

- **Seeding needs no engine call, only a habit, now written down** (`docs/lua.md`, Limits): the run's seed is the `ticks()` at which A was
  pressed on the title, the old trick of GBA games that counted frames until START. A person never presses on the same tick twice; a test
  always does, so its runs repeat. The day's chasm is seeded with `clock().days` (offered only when `clock()` knows the date), and each floor
  with the run's seed and its number, so a floor is the same whenever it is made. `math.randomseed()` with nothing would seed from the time
  and break the tests' repeats.
- **The fog of war is a second background, no primitive**: BG0 over the sprites (`prio = 0`), its map all dark, a checker of dark over what
  was seen (the items under it show dimmed) and clear where the hero sees. For each floor both maps are loaded again (`bg()` copies the
  asset's map: all rock and all dark at once, in C) and only what is not plain rock, and the cells the hero sees, are written with `mset`;
  after a turn, only the fog's cells that came into sight or left it. The tests read the map back with `mget` after every turn of a whole
  run and find it the same as the run's own sight; a fog that was not updated, or only half of it, fails it.
- **Which tiles a kind of cell is**: `png2asset --tiles` numbers tiles as it first meets them, flipped copies folded in (an entry may be
  `5 | 0x400`), so `art.py` draws one cell of each kind in the map's first row and reads their four entries back from the `.map` it made,
  into `index.lua`. A game that writes a map by `mset` needs that; a tool that printed them would save the step.
- **One distance field moves the whole crowd**: each turn `grid:distances` from the hero over the floor, and every awake monster takes
  `descend`; the bats half the time go anywhere instead. Sight is a circle of six cells cut by walls (Bresenham to each), in Lua, once a turn.
- **The design is checked, not only played**: twenty runs of five floors are each one piece (every open cell reached from the start, the
  stairs among them), the same seed makes the same floor, and a bot walking to the stairs along `grid:path` plays a whole run in 263 turns,
  to the amulet, with the best floor and the wins kept.
- **On the console the cost was all the game's Lua, and three habits fixed it** (measured by putting each piece in `_update` for a
  window and reading the perf line's mean): sight with Bresenham worked out every turn, 8 ms a look, and it was looked twice a turn;
  rays worked out once and walked, 2.1 ms, once. The fog over a 17 x 17 square, 2.4 ms; by the difference of two sights, 0.35. One
  `grid:distances` over 48 x 32, 1.4 ms. With the turn still in one tick, almost every step was a 24-27 ms frame (about 290 in a run);
  with the hero's half and the monsters' half a tick apart (the step slides for four), 34 over 20 ms in a whole run of 261 turns, 59.8 fps.
  A floor's arrival held a tick 166 ms (every cell of both maps written, the grid set cell by cell); with the maps loaded again, only
  what is open written, the grid made all wall and only the open cells set, 50-53 ms, behind a "Piso 2 de 5" card on black, as the
  Mystery Dungeons put between floors, where a long tick is not seen. Each Lua call there is microseconds (6,144 `mget`+`mset` pairs,
  about 40 ms): a game counts its calls per frame on the console, not its lines. Half of that was the engine's, and is gone (section 14):
  with it, a floor's arrival is under 40 ms and the run 24 frames over 20 ms instead of 34.

## 14. The Lua VM ran at half its speed on the console, and why

What `isla` and `sima` showed (a Lua call costing microseconds) was measured with a game of nothing but loops (`_update` running one
operation 2,000 times a tick; the perf line's mean less the empty one's), on the board:

| 2,000 of | before | no hook at all | budget in the VM (now) |
|---|---|---|---|
| empty `for` turns | 0.70 ms | 0.33 | 0.41 |
| `s = s + i` | 1.37 | 0.67 | 0.76 |
| a table write | 3.29 | 1.57 | 1.64 |
| a global table's field | 2.77 | 1.75 | 1.84 |
| a Lua function call | 4.97 | 1.94 | 2.07 |
| a C function call (`math.abs`) | 4.13 | 2.38 | 2.54 |
| `mget` | 6.69 | 4.26 | 4.40 |
| 200 tables made | 3.48 | 3.29 | 3.33 |

The cause was the sandbox's guard against a call that never returns: a count hook every 1,000 instructions. With any count hook set,
Lua 5.4's VM calls `luaG_traceexec` before every instruction (it only decrements the count and returns): on a computer a quarter slower
(the same loops, 128 ms against 102), on the console half. The budget is now counted by the VM itself (`luai_budget` in
`third_party/lua/lvm.c`, five lines: every jump, numeric and generic `for` turn, call and tail call, so no endless loop escapes it), and
only when it is spent is the count hook set, to raise the error where the VM has saved its place, as before. It stays deterministic (the
tests repeat), and every kind of endless loop is in `tests/sandbox.script` (`while`, `repeat`, `goto`, numeric and generic `for`, a tail
call, `pcall` and coroutines in a loop); with the count taken out of the jumps they hang. On the console an endless loop still ends in
"the script ran too long". Games: `isla`'s `_draw` 2.48 to 2.09 ms; `sima`'s `_update` 0.58 to 0.46.

What is left is the VM's own cost here (about 50 cycles a `for` turn, its stack and tables living in PSRAM, and 17 µs to make a table): a frame of a few
thousand Lua operations is a few milliseconds.

