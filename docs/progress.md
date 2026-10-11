# Progress log

What was done, measured and left, step by step. Newest at the bottom. The plan is the research report's
(GBA-like virtual hardware, then Lua, then tools); measurements are in measurements.md.

## 2026-10-12 · Step 2: the slow screens

Measured on the board, CPU per frame for the world plus all 15 panel strips (the DMA of the strips overlaps it):

| Screen | Bajo Pueblo | Geumgye |
|---|---|---|
| Walking | 5.3 ms | 6.4 ms |
| Dialogue | 8.2-8.8 ms | 8.6 ms |
| Bag | 14.7 ms | 13.9 ms |
| Puzzles | 7.7 / 10.9 ms | 11.1 / 8.1 ms |
| Bag with a dialogue over it | 20.2 ms | |

What it took, all pixel-identical (48 scripts, CRC per frame, strips checked against whole frames):

- Cut-corner cards (Geumgye's theme) drawn column by column, each pixel once: shadow only where it shows, ink on
  the border, paper inside, and only the columns inside the window. Before: three full-area passes, and the corner
  rows became one-pixel runs on a turned strip.
- Masked blits copy or skip 8 pixels per mask byte on plain buffers: Bajo Pueblo's world went from ~4.5 to ~2 ms.
- gfx_blit2x on windows walks columns with a stepping pointer.
- Dialogue choices count their wrapped lines once (cached until the choices or the font change): a 4-choice menu
  wrapped text ~20 times per strip, 300 times a frame.

Real play (end-to-end tests, frames as fast as they come): 54-89 fps in 5 s windows, most above 75.
