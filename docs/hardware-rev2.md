# Cirera rev2: what to add to the board, and what the engine already offers for it

The FNK0104N has no GPIO left (docs/hardware.md: 0–21, 26–37 flash and PSRAM, 38–48 all taken), so every add-on
hangs off the shared I2C bus (SDA 38, SCL 39, 400 kHz, 10 kΩ pull-ups) beside the touch panel (0x55), the codec (0x18)
and the buttons' PCF8574 (0x20). Reading an IMU at 100 Hz adds little to that bus. Research of 2026-10-21
(docs/roadmap.md); none of this is built yet.

| Add-on | Part | I2C address | What it opens | Engine side |
|---|---|---|---|---|
| Tilt, twist, shake | LSM6DS3TR-C or BMI270 (BMI270 wants a config blob at start; avoid MPU6050 clones) | 0x6A/0x6B, 0x68/0x69 | marble mazes, Kirby Tilt 'n' Tumble (its patent US6375572, with a neutral position set by the player, expired 2020-02-24), WarioWare Twisted turns, a cocktail shaken | `tilt()`, `tilt_zero()` (below); `hal_imu` for the firmware |
| Rumble | DRV2605L with an ERM or LRA motor (100+ built-in effects, ~100 mA) | 0x5A | hits felt, an engine's purr, a heartbeat | `rumble(ms, strength)`; `hal_rumble` |
| A crank | AS5600 magnetic angle sensor (12 bits; AS5600L at 0x40); the magnet centred, DIR tied off | 0x36 | Playdate-style cranks: fishing reels, winches, a film projector | (read as an angle: a later `crank()`) |
| A clock that survives the switch | PCF8563 or RV-3028 with a coin cell (the power switch cuts the battery, so the chip's own clock dies) | 0x51, 0x52 | real-time games, a day's seed for everyone (`clock()` already serves it when the computer sets the time over the cable) | `hal_clock` already |
| Figures on the console | PN532 reader with NTAG215 stickers in pinyol's own format (not amiibo's) | 0x24 | a toy that brings its character; poll only when a game asks (100+ mA with the field on) | (a later `tag()`) |
| L and R | a second PCF8574 | 0x21 | shoulder buttons | the input bits, two more names |

Not worth it: infrared (needs a pin with RMT: IO40's WS2812 or IO0 would have to go; ESP-NOW does what IR did),
the ESP32-P4 as the next chip (no radio, and ESP-NOW is not supported through its C6 coprocessor), PSRAM at 120 MHz
(experimental, temperature calibration, random hangs).

## Already in the engine, for games written before the board exists

- `tilt()` gives the console's tilt as `x, y, z` (-1..1 each, the direction gravity pulls, relative to the neutral
  position `tilt_zero()` sets: the player holds the console as they like and presses A), or `nil` on a console
  without a sensor. The desktop and the browser answer `nil`; a test script says `tilt X Y Z` (and `tilt none`).
- `rumble(ms [, strength])` asks for a vibration (strength 0..1); nothing happens where there is no motor. A test
  script checks `expect_rumble MS`.
- The firmware adds a driver per part behind `hal_imu` and `hal_rumble` (src/hal.h), on the I2C bus already open
  for the touch panel and the codec; no other code changes.

## Patents to keep clear of (active)

- Warner's Nemesis system (US11192028, to about 2035).
- Nintendo's StreetPass-with-steps family (US9687733B2, to 2031-08-20): no passive exchange tied to a pedometer or
  sleep-mode processing in that way.
- Nintendo's summon-and-fight and throw-to-capture families (under reexamination at the time of writing).

Expired, free to use: Namco's loading-screen minigames (US5718632, 2015), Sega's Crazy Taxi arrow and dodging
pedestrians (US6200138, 2018), Konami's DDR pad (US6410835) and keysounds, Nintendo's tilt with a neutral position
(US6375572, 2020), LucasArts' iMUSE (US5315057, 2011: already in `music(..., {at = "bar"})`).
