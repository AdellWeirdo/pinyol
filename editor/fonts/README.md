# The editor's fonts

- `PixelifySans.ttf`: the editor's cover preview of a game with the engine's own letters (`FONT_*.fnt` here).
- `<id>/`: the letters a game can choose (project.js `FONTS`, set by a look): the four `FONT_*.fnt` the game carries,
  made by `tools/font2fnt.py` from `third_party/fonts` (SIL Open Font License 1.1), and `font.woff2` for the preview.
  `pressstart2p/` is shown as **Arcade 8**: Press Start 2P's licence reserves its name, so what is made from it
  (these `.fnt`, and `font.woff2`, renamed inside with fontTools) goes by another.

```sh
# scale 2 (world pixels) for the 8-pixel fonts, 1 for Jersey 15; the large ones a step bigger
uv run tools/font2fnt.py silkscreen      editor/fonts/silkscreen/FONT_MAIN.fnt   --scale 2   # FONT_BOLD: silkscreen-bold
uv run tools/font2fnt.py micro5          editor/fonts/micro5/FONT_MAIN.fnt       --scale 2
uv run tools/font2fnt.py pressstart2p    editor/fonts/pressstart2p/FONT_MAIN.fnt --scale 2
uv run tools/font2fnt.py jersey15        editor/fonts/jersey15/FONT_MAIN.fnt     --scale 1
# FONT_MAIN_L / FONT_BOLD_L: --scale 3 (Jersey 15: 2); FONT_BOLD is FONT_MAIN where the font has no bold
```
