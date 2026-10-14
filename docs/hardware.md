# Hardware: the Cirera console (Freenove FNK0104N, ESP32-S3)

Pins and peripherals for the firmware (Freenove FNK0104N = LCDWIKI ES3C35P), each with its source.

**Sources** (Freenove's documentation for the FNK0104N: schematic, LCDWIKI spec, user manual, tutorial; plus the ST77922 datasheet; unless noted otherwise):
- **SCH:** schematics. If sources disagree, the schematic wins.
- **SPEC:** LCDWIKI specification V1.0.
- **UM:** user manual.
- **TUT:** Freenove tutorial.
- **DS:** ST77922 datasheet.
- **VEND:** Freenove repository `Freenove/Freenove_ESP32_S3_Display`, with the patched TFT_eSPI.
- **WIRING:** the console's own wiring notes (not yet published), for the console's custom wiring.

⚠ marks a contradiction between sources.

> The sibling 2.8" board (FNK0104A/B) uses **different pins** for I2S, SD, I2C and battery. In Freenove's sketches, this board is the `#ifdef FNK0104N_3P5_320x480_ST77922` branch and the 2.8" board is the `#else`.

## MCU
- **Chip:** ESP32-S3R8, with 8 MB of integrated octal PSRAM (SCH, UM p.15).
- **Flash:** 16 MB QSPI (SPEC §3.1).
- **Pins used by flash and PSRAM:** IO26 to IO37. Do not touch.
- **USB:** native on IO19 and IO20, no CH340 (SCH). The debug console goes over **USB-Serial-JTAG**, because UART0 is taken by IO43 and IO44 (see Console).

## Display · ST77922, QSPI, 320×480 portrait
| Signal | GPIO | Source |
|---|---|---|
| CS | 10 | SPEC p.9, SCH, VEND |
| SCK | 12 | SPEC p.9, SCH, VEND |
| D0 / D1 / D2 / D3 | 11 / 13 / 14 / 9 | SPEC p.9, SCH, VEND |
| TE | 42 | SCH only. ⚠ SPEC omits it |
| Backlight | 41 | Active high, PWM capable, 120 mA (UM p.21) |
| RST | CHIP_PU | It is the ESP reset; no GPIO |

- **Interface mode:** IM = 011, QSPI with no DC line.
- **Protocol** (UM pp.6–7, VEND):
  - Register write: `0x02` followed by the 24-bit address `00 cmd 00`.
  - Pixel write: `0x32`, with command `0x3C` or `0x2C`.
- **Initialization:** about 60 commands, in `st77922_lcd_init[]` in VEND (`ST77922.cpp`). Ends with `3A=01` (RGB565), `36=00` and `35=01` (TE on).
- **Byte order:** big-endian (byte swap).
- **Rotation:** **MADCTL has no MV bit** (DS p.188), so there is no hardware landscape. The firmware transposes in software. VEND does the same.
- **Clock:** VEND uses 80 MHz. ⚠ The DS gives a minimum cycle of 16 ns, about 62.5 MHz.

## Touch · integrated in the ST77922 (TDDI)
- **Bus:** I2C at **0x55**, 16-bit registers, up to 5 points (SPEC §3.2, VEND `ST77922_Touch`). ⚠ UM says FT6336G, but that is copied from the 2.8" model.
- **INT:** 47, active low.
- **RST:** 48, active low. ⚠ The XLSX sheet swaps 47 and 48.
- **Protocol:** `ST77922 TDDI Interface Protocol V01.00.pdf`, in the VEND zip.

## microSD · 4-bit SDMMC
| CLK | CMD | D0 | D1 | D2 | D3 |
|---|---|---|---|---|---|
| 5 | 4 | 6 | 7 | 2 | 3 |

- 10 kΩ pull-ups on all lines, no card detect (SPEC p.9, SCH).
- IO3 is a strapping pin (JTAG source select). With the pull-up it is fine.

## Audio
- **Codec:** ES8311 on I2C **0x18** (UM p.24, SCH).
- **I2S:**
  | MCLK | BCLK | WS | DOUT (ESP→codec) | DIN (codec→ESP) |
  |---|---|---|---|---|
  | 17 | 18 | 21 | 15 | 16 |
- **Amplifier:** class 8002, BTL. ⚠ SCH says SC8002B and UM says FM8002E; they are pin-compatible.
  - Enable on **IO1, active low**. A pull-up keeps it off by default.
  - Powered from the +5 rail, which becomes the battery voltage when there is no USB.
- **Sample rate:** VEND supports 22,050 Hz with MCLK at 5.6448 MHz (256·fs), which is the game's `AUDIO_HZ`.
- **Speaker:** JP3, PH1.25, 8 Ω, 1.5 W.

## Shared I2C bus (SDA 38, SCL 39, 10 kΩ pull-ups)
| Device | Address |
|---|---|
| ST77922 touch | 0x55 |
| ES8311 codec | 0x18 |
| Console button PCF8574 | 0x20 |

No address clashes. The bus supports 400 kHz (DS p.118).

## Buttons (WIRING)
- **PCF8574 at 0x20, polled:** P0–P3 are the D-pad (up, down, left, right) and P4–P7 are A, B, MENU and START. Its INT is left unconnected.
- **C:** on **IO44** (RXD of the UART connector), with the internal pull-up.

## Console, LED and power (WIRING + SCH)
- **IO43:** detects USB through a VBUS divider (10k/15k).
- **ROM:** writes to IO43 at boot; with the divider it does no harm.
- **Bicolor LED:** red on IO45 and green on IO46, each with 1 kΩ, PWM.
- **IO45 and IO46 are strapping pins:** IO45 must be low at reset (sets VDD_SPI), and the LED to GND guarantees that. **Do not add pull-ups on IO45 or IO46.**
- **Battery:**
  - Measured on **IO8** (ADC1_CH7) through a 100k/100k divider, so multiply by 2. ⚠ TUT says IO9, which is the 2.8" board.
  - The charger is a TP4054 at about 300 mA. **Its CHRG does not reach the MCU:** "charging" or "charged" can only be inferred from USB present and the voltage.
- **Switch:** SS12D00 on the battery lead. **Never feed 5 V into the 5V pin of the UART connector with the battery connected.**
- **Other:** IO0 is the BOOT button (usable as an input after boot) and IO40 is an on-board WS2812B.
