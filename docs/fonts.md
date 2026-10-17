<!-- made by `tools/font2fnt.py --markdown docs/fonts.md`: edit third_party/fonts/catalog.json, not this -->
# Fonts for every look

Each console's games had their own letters, and those are not ours to ship (Nintendo's, Sony's and Sega's fonts are theirs). What pinyol carries instead are free fonts, all under the SIL Open Font License, that give the same *feel*, grouped into **packs**: a `title`, a `body` and a `small` font for each look. Pick the pack of the console your game is made for (docs/art.md, "Choose a look") and make its fonts into your game:

```sh
uv run tools/font2fnt.py --pack snes games/mygame     # fonts/snes_title.fnt, snes_body.fnt, snes_small.fnt
```

```lua
text("PUSH START", 240, 60, {font = "snes_title", align = "center", color = 0xFFFFFF})
text("Hamburgefonstiv", 20, 140, {font = "snes_body"})
```

`uv run tools/font2fnt.py --catalog` lists the packs, `--sheet out.png [pack]` draws them. A game can have 16 fonts of its own besides the four every game has, so mix packs freely (`--prefix` renames a pack's files). Letters are the 256 of Windows-1252: Spanish, Catalan, French, German, Portuguese, Italian and the Nordic languages, not Japanese or Cyrillic. Fonts with an `*` keep a Reserved Font Name: what is made from them (your `.fnt`) must not be called by it, so the packs name their files by pack (`snes_title`), never by font.

![Every pack](media/fonts.png)

## Packs

| Pack | Look | Title | Body | Small |
|---|---|---|---|---|
| `nes` | **NES / Famicom**: chunky 8x8 caps, few colours | Press Start 2P* | Press Start 2P* | Silkscreen |
| `master_system` | **Master System / Game Gear**: squarish 8-bit text | Silkscreen Bold | Silkscreen | Tiny5 |
| `game_boy` | **Game Boy**: round plain 8 px text on four greens | Jersey 10 | Pixelify Sans | Tiny5 |
| `game_boy_color` | **Game Boy Color**: the Game Boy's text, a little livelier | Jersey 15 | Pixelify Sans | Micro 5 |
| `gba` | **Game Boy Advance**: clear 16 px handheld text, a bold title | Jersey 15 | Pixelify Sans | Tiny5 |
| `snes` | **Super Nintendo**: a bold rounded RPG and platform feel | Jersey 20 | Pixelify Sans | Silkscreen |
| `mega_drive` | **Mega Drive / Genesis**: sporty heavy titles and tight body text | Jersey 25 | Jersey 10 | Tiny5 |
| `pc_engine` | **PC Engine / TurboGrafx**: dotted Japanese-style text | Doto | DotGothic16 | Micro 5 |
| `neo_geo` | **Neo Geo**: arcade fighting: heavy slanted-looking titles | Bangers | Jersey 15 | Silkscreen |
| `cps2` | **CPS2 arcade**: stencil title cards, tidy body | Black Ops One | Jersey 15 | Micro 5 |
| `arcade_80s` | **80s arcade**: square caps for a high score table | Press Start 2P* | Press Start 2P* | Bytesized |
| `atari_2600` | **Atari 2600**: very blocky | Sixtyfour | Bytesized | Bytesized |
| `atari_st` | **Atari ST**: a crisp monospace desktop | Workbench | IBM Plex Mono* | Tiny5 |
| `amiga` | **Amiga**: the Workbench look | Workbench | Workbench | Tiny5 |
| `commodore_64` | **Commodore 64**: wide blocky home computer | Sixtyfour | Sixtyfour | Tiny5 |
| `zx_spectrum` | **ZX Spectrum**: narrow thin tape-loading text | Workbench | Tiny5 | Tiny5 |
| `msx` | **MSX**: a plain 8-bit computer face | Sixtyfour | Tiny5 | Tiny5 |
| `apple_ii` | **Apple II**: green terminal text | VT323 | VT323 | VT323 |
| `dos_vga` | **DOS / VGA**: the 80x25 text screen | IBM Plex Mono Bold* | VT323 | Micro 5 |
| `pico8` | **PICO-8**: tiny 4x6 text in sixteen colours | Bytesized | Micro 5 | Bytesized |
| `tic80` | **TIC-80**: tiny readable pixels | Tiny5 | Tiny5 | Bytesized |
| `pocket_lcd` | **Pocket LCD / Game & Watch**: dots with gaps, segment-display feel | Bitcount Grid Single | Doto | Handjet |
| `vector_arcade` | **Vector arcade**: thin outlined strokes | Major Mono Display | Share Tech Mono* | Geo* |
| `playstation` | **PlayStation (menus and RPGs)**: clean angular sans, Roman title capitals | Cinzel Decorative Bold* | Chakra Petch | Chakra Petch |
| `playstation_scifi` | **PlayStation (racing, sci-fi)**: geometric techno | Orbitron* | Chakra Petch | Geo* |
| `saturn` | **Sega Saturn (arcade ports)**: wide techno and bold labels | Audiowide* | Russo One* | Chakra Petch |
| `gothic` | **Gothic action (SotN-style)**: blackletter titles, fantasy body | Jacquard 24 | Metamorphous* | Jacquarda Bastarda 9 |
| `n64` | **Nintendo 64**: chunky signage titles, soft body | Bungee | Righteous* | Chakra Petch |
| `dreamcast` | **Dreamcast**: wide techno titles, bold sans | Audiowide* | Russo One* | Chakra Petch |
| `ds_psp` | **Nintendo DS / PSP**: tidy handheld sans | Jersey 20 | Pixelify Sans | Tiny5 |
| `jrpg` | **Japanese-style RPG**: dot-matrix body, Roman title | Cinzel | DotGothic16 | Micro 5 |
| `fantasy` | **Medieval fantasy**: blackletter and hand-cut text | UnifrakturCook* | MedievalSharp* | Silkscreen |
| `horror` | **Horror**: dripping titles, rough text | Creepster* | New Rocker* | Micro 5 |
| `comic_beatemup` | **Comic / beat'em up**: shouted comic caps | Bangers | Righteous* | Tiny5 |
| `sports` | **Sports / scoreboard**: bold jerseys and digits | Jersey 25 | Jersey 15 | Jersey 10 |
| `terminal` | **Hacker terminal**: a green monitor | Major Mono Display | VT323 | Courier Prime |
| `typewriter` | **Typewriter / detective**: typed pages and case files | Courier Prime Bold | Courier Prime | Courier Prime |

## The fonts

| Font | Feel | Folder |
|---|---|---|
| Press Start 2P* | 80s arcade and NES-era caps and small letters, 8 px | `third_party/fonts/pressstart2p` |
| Silkscreen | small clean capitals for labels, 8 px | `third_party/fonts/silkscreen` |
| Silkscreen Bold | the same, heavier | `third_party/fonts/silkscreen` |
| Tiny5 | tiny 5 px pixel text that still reads: PICO-8, ZX Spectrum, small HUDs | `third_party/fonts/tiny5` |
| Micro 5 | tiny, a little rounder | `third_party/fonts/micro5` |
| Bytesized | the smallest, numbers and credits | `third_party/fonts/bytesized` |
| Pixelify Sans | round friendly pixel sans: Game Boy, GBA, handheld RPGs | `third_party/fonts/..` |
| Jersey 10 | sport and scoreboard, 16-bit | `third_party/fonts/jersey10` |
| Jersey 15 | sport, a size up | `third_party/fonts/jersey15` |
| Jersey 20 | bold 16-bit titles | `third_party/fonts/jersey20` |
| Jersey 25 | big bold arcade titles | `third_party/fonts/jersey25` |
| Sixtyfour | wide blocky 8-bit home computer (C64, MSX, Atari) | `third_party/fonts/sixtyfour` |
| Workbench | an Amiga Workbench-style bitmap face with serifed bits | `third_party/fonts/workbench` |
| Handjet | LED and dot-matrix printer | `third_party/fonts/handjet` |
| Doto | a dot-matrix display, round dots | `third_party/fonts/doto` |
| Bitcount Single | a bitmap text face with a tidy computer feel | `third_party/fonts/bitcountsingle` |
| Bitcount Grid Single | pixels with a grid between them: pocket LCD games, game and watch | `third_party/fonts/bitcountgridsingle` |
| DotGothic16 | Japanese dot-matrix, 16 px: JRPG body text | `third_party/fonts/dotgothic16` |
| VT323 | a computer terminal: DOS, Apple II, hacker screens | `third_party/fonts/vt323` |
| Jacquard 12 | blackletter pixels: gothic action games | `third_party/fonts/jacquard12` |
| Jacquard 24 | blackletter pixels, bigger, for titles | `third_party/fonts/jacquard24` |
| Jacquarda Bastarda 9 | a gentler blackletter | `third_party/fonts/jacquardabastarda9` |
| Orbitron* | geometric sci-fi: PlayStation racers, Dreamcast | `third_party/fonts/orbitron` |
| Oxanium | squared sci-fi, mecha | `third_party/fonts/oxanium` |
| Geo* | a narrow technical face | `third_party/fonts/geo` |
| Major Mono Display | outlined strokes: vector arcade, Tron | `third_party/fonts/majormonodisplay` |
| Share Tech Mono* | a technical monospace: vector arcade, a cockpit | `third_party/fonts/sharetechmono` |
| Audiowide* | wide rounded techno titles: Dreamcast, Saturn arcade | `third_party/fonts/audiowide` |
| Russo One* | bold squared sans for readable menus | `third_party/fonts/russoone` |
| Black Ops One | stencil military arcade titles | `third_party/fonts/blackopsone` |
| Chakra Petch | clean angular sans: PS1/PS2 menus, sci-fi HUDs | `third_party/fonts/chakrapetch` |
| Chakra Petch Bold | the same, bold | `third_party/fonts/chakrapetch` |
| Zen Dots | wide futuristic titles | `third_party/fonts/zendots` |
| Wallpoet* | stencilled wall lettering | `third_party/fonts/wallpoet` |
| Cinzel | Roman capitals: JRPG and fantasy titles | `third_party/fonts/cinzel` |
| Cinzel Decorative Bold* | fancy Roman capitals for titles | `third_party/fonts/cinzeldecorative` |
| MedievalSharp* | a hand-cut medieval face for text | `third_party/fonts/medievalsharp` |
| Metamorphous* | fantasy book text | `third_party/fonts/metamorphous` |
| UnifrakturCook* | bold blackletter titles | `third_party/fonts/unifrakturcook` |
| UnifrakturMaguntia* | classic blackletter | `third_party/fonts/unifrakturmaguntia` |
| New Rocker* | Celtic heavy metal | `third_party/fonts/newrocker` |
| Creepster* | horror titles: dripping letters | `third_party/fonts/creepster` |
| Bungee | chunky signage capitals: N64 titles, arcade signs | `third_party/fonts/bungee` |
| Bangers | comic book shout: beat'em ups, fighters | `third_party/fonts/bangers` |
| Righteous* | rounded retro-futuristic text | `third_party/fonts/righteous` |
| Courier Prime | typewriter | `third_party/fonts/courierprime` |
| Courier Prime Bold | typewriter, bold | `third_party/fonts/courierprime` |
| Cutive Mono | a light typewriter | `third_party/fonts/cutivemono` |
| IBM Plex Mono* | a clear monospace: DOS and terminals | `third_party/fonts/ibmplexmono` |
| IBM Plex Mono Bold* | the same, bold | `third_party/fonts/ibmplexmono` |

Each folder holds the font's `OFL.txt`. The fonts are free to use, change and share, also in games that are sold, as long as the font is not sold on its own; `THIRD_PARTY_NOTICES.md` carries their notices.
