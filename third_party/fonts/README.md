# Fonts that come with pinyol

**98 fonts and 73 ready-made packs, one for each console's look: see [docs/fonts.md](../../docs/fonts.md)**
(`uv run tools/font2fnt.py --pack snes games/mygame`). `catalog.json` here says which font is which pack's title, body
and small letters; the table below is the first dozen, the rest are listed in docs/fonts.md.

Pixel fonts a game can use as its own: `uv run tools/font2fnt.py <name> games/mygame/fonts/<name>.fnt`
(`font2fnt.py --list` shows them with their pixel size). Each is under the SIL Open Font License 1.1 (its `OFL.txt`
next to it): free to use, change and share, also in games that are sold, as long as the font itself is not sold on
its own. All come from [Google Fonts](https://github.com/google/fonts) (`ofl/`); DotGothic16 is cut to the
characters the engine draws (Windows-1252), the rest are as published.

| Folder | Font | Pixel size | Feel |
|---|---|---|---|
| `pressstart2p` | Press Start 2P | 8 | 80s arcade, capitals and small letters the same height |
| `silkscreen` | Silkscreen, Silkscreen Bold | 8 | small capitals, clean labels |
| `vt323` | VT323 | 16 | a computer terminal |
| `jersey10`, `jersey15`, `jersey20` | Jersey 10, 15, 20 | 18.7, 27, 34 | sport, scoreboards, titles |
| `micro5` | Micro 5 | 11 | tiny, still readable |
| `jacquard12` | Jacquard 12 | 21 | blackletter: medieval, Gothic |
| `jacquardabastarda9` | Jacquarda Bastarda 9 | 13 | a gentler blackletter |
| `bytesized` | Bytesized | 8 | the smallest |
| `dotgothic16` | DotGothic16 | 16 (`--px 16`) | Japanese dot-matrix |

Pixelify Sans, the engine's own (`third_party/pixelify`), is there too as `pixelifysans`.

Press Start 2P is published with the Reserved Font Name "Press Start 2P": the TTF here is the original, unchanged, but
what is made from it (a game's `.fnt`, the editor's `font.woff2`) may not be called by that name. The editor calls it
**Arcade 8**, and so should a game that names its letters.
