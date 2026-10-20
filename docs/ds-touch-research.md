# Nintendo DS touch: what it did, and what pinyol takes from it

Research for touch games on pinyol (2026-10-20). Each fact has its source; what could not be read is under "Still to check".

## The hardware

- Touch controller: a TI TSC2046 on the ARM7's SPI port; a 12-bit ADC; the DS wires an external 3.3 V reference. X is read with command `0xD4`, Y with `0x94`, cross-panel pressure with `0xB4` / `0xC4` (Z1, Z2); each reading is three SPI transfers. [DS Touch Screen Information](https://retroisle.com/others/nintendods/Technical/Firmware/touch%20screen.php)
- Calibration: the firmware stores two points (a raw ADC value and the pixel it means); each axis is a straight line through them: `x = (raw - CAL_X1) * W / dADC + X1`. The screen is 256x192. Same source.
- libnds hands games `touchPosition {rawx, rawy, px, py, z1, z2}`, `touchPenDown()` and `touchApplyCalibration()`: the raw value, the calibrated pixel and the pressure readings all reach the game. [libnds](https://libnds.devkitpro.org/structtouchPosition.html)
- Two independent 2D engines (main and sub), each with 4 backgrounds and 128 sprites, sharing VRAM by banks. [BlocksDS manual](https://blocksds.skylyrac.net/manual/backgrounds.html)
- Value ranges (GBATEK, "DS Touch Screen Controller (TSC)"): Y reads roughly 0x0B0 to 0xF20 and X roughly 0x100 to 0xED0 (12 bit); a released panel reads Y = 0xFFF and X = 0. Pen-down is the controller's /PENIRQ pin (low while touched): read the controller only then, and treat any invalid reading as "not pressed" even if /PENIRQ was low, because the pen may lift before the read. Read at least twice and ignore both positions if either is invalid; spots near the screen's edges may be unreachable; with two points pressed the reading falls between them. [GBATEK](https://problemkaputt.de/gbatek.htm)
- Pressure (same section; not on the DSi): `Rtouch = Rx_plate * Xpos * (Z2/Z1 - 1) / 4096`, or with Rx_plate set to 4096 a unitless `Xpos * (Z2/Z1 - 1)`.
- Calibration in libnds (`touchInit`, `touchApplyCalibration`): a scale per axis `(px2 - px1) << 19 / (raw2 - raw1)` and an offset from the two points' middles, then the result is clamped to 0..255 and 0..191. [libnds/BlocksDS touch.c](https://github.com/blocksds/libnds/blob/master/source/arm7/touch.c)
- Sampling and noise in libnds: each read takes **five samples** of each of Z1, Z2, X and Y with the ADC held on, and **skips the first sample** (`tscTouchReadData`, [tsc.c](https://github.com/blocksds/libnds/blob/master/source/arm7/tsc.c)). The filter (`libnds_touchMeasurementFilter`, [touchFilter.c](https://github.com/blocksds/libnds/blob/master/source/arm7/touchFilter.c)) sorts the five, takes the three closest to each other (preferring the middle ones), and returns their average weighted `(5, 6, 5) / 16`; a value of 0 is kept for "invalid", and a read with no valid X is reported as not touched. The comments cite TI's application notes on median and average filters.

## How Nintendo designed for it

- Zelda: Phantom Hourglass (Aonuma, GDC 2007): the first prototype put a touch-driven map on the bottom screen and "felt unintuitive"; the 3D world moved to the touch screen and the player touches Link directly. Tap locks on and attacks, a drawn line is the boomerang's path, notes are written on the map. [NWR](https://nintendoworldreport.com/feature/13088). The stylus-only scheme was only decided late, once the team trusted it: [Nintendo interview](https://www.nintendo.co.uk/News/2007/Interview-Zelda-Phantom-Hourglass-249679.html).
- Patent US7785199, touch-sensitive gaming system with dual displays: the touch screen shows a 2D plan of the field; a flick sends the nearest athlete in a line, a held trace makes one follow a path, a drawn line moves a defensive line; the athlete chosen is the one **nearest where the touch began**; commands go on after the touch ends; **buttons take priority** over a touch order, so both inputs live together. [Google Patents](https://patents.google.com/patent/US7785199)
- Patent US7860315, touch input program: a stroke is the list of points from touch-on to touch-off; recognition runs on the stroke after it is turned upright (`x' = xmax - x`); a left-handed mode turns the question round for the other hand. [Google Patents](https://patents.google.com/patent/US7860315)
- Handwriting: Nintendo licensed Zi Corporation's Decuma for DS developers. [NWR](https://www.nintendoworldreport.com/news/10894/nintendo-licenses-ds-handwriting-technology)
- Griptonite's 20 DS games: plan for touch from the first day; how responsive it feels matters as much as the scheme; touch features took five to ten times as long to iterate as to build; touch prototypes mislead. [Game Developer](https://www.gamedeveloper.com/production/five-years-20-lessons-20-ds-games)
- Origin: Iwata and Miyamoto decided on the touch panel together with the two screens. [Iwata Asks](https://iwataasks.nintendo.com/interviews/3ds/how-nintendo-3ds-made/1/0/)

## What pinyol took (`lib/pointer.lua`, `pen()`)

| DS idea | In pinyol |
|---|---|
| Games read the calibrated pixel at full panel resolution | `pen()`: 480x320, the space `text()` draws in (`touch()` halves it to the 240x160 world), with `released` |
| Tap, drag, draw the path | `pointer.tapped`, `.dragging`, `.stroke`, `.last` |
| Flick sends a unit | `pointer.flick` `{dx, dy, dir}` on lift |
| The target nearest where the touch began | `pointer.pick(items, x, y)` |
| A stroke is a point list, recognised after normalising | `pointer.simplify` (Ramer-Douglas-Peucker) and `pointer.recognize`: the $1 recogniser, five shapes |
| Touch orders yield to buttons | not in the library: a game checks `btn()` first, as the patent does |

Left out on purpose: the DS's five-sample filter (it works on a burst of readings within one tick; the engine reads one point a tick, so the same idea would cost ticks of delay: not worth it until the board's noise is measured), the left-handed flip, pressure (the engine's input has none), and a second screen.

## Still to check

- The DS panel's measured latency, and the Cirera's own noise, jitter and accuracy: only a finger on the board will say.
- Nintendo's 2006 multi-touch patent application, and US8306330 (handwriting input): claims not read.

## Next steps (not built)

1. Widgets: touch button, slider, scroll list, on `lib/keyboard.lua`'s hit tests, with one focus for the D-pad and the finger.
2. A second screen: designed in [ds-dual-screen-design.md](ds-dual-screen-design.md), not built.
