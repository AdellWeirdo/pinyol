# PlayStation reference for `quad()`

`ps1_pose0..3.png` (320x240) are what a PlayStation GPU/GTE drew: PSn00bSDK's `examples/graphics/gte` cube (textured, one light, dithered),
frozen at four poses, captured from `pcsx_rearmed` (RetroArch, HLE BIOS). `posecube_main.c` is that example with the pose fixed by
`-DPOSE_VX/VY/VZ` (poses: 0 0 0, 256 0 256, 600 0 600, 300 500 700); `texture.png` is its `texture.tim`. PSn00bSDK's examples are MPL 2.0
and may be copied and changed (Lameguy64 / Meido-Tek, https://github.com/Lameguy64/PSn00bSDK).

`tests/games/ps1cube` draws the same cube with `quad()`; `tests/ps1cube.script` poses it and `tests/ps1cube_check.py` compares
(silhouette >= 0.97, box within 2 px, mean colour within 8 levels). Measured 2026-10-23: 0.98-0.99, 1 px, 1-5 levels.

To make the references again: build the SDK with a `mipsel-none-elf` GCC (14.2 builds on macOS; 12.2 does not, and the bundled zlib needs
`--with-system-zlib`), build `posecube_main.c` with the example's `CMakeLists.txt` and `texture.tim`, put the `.exe` on a CD image with
`mkpsxiso` (`SYSTEM.CNF`: `BOOT=cdrom:\POSECUBE.EXE;1`), and run `retroarch -L pcsx_rearmed_libretro --max-frames 700 --max-frames-ss
--max-frames-ss-path out.png --appendconfig cfg game.cue` with `pause_nonactive = "false"` in the cfg.
