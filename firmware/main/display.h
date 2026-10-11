#pragma once
#include <stdbool.h>
#include <stdint.h>

/* ST77922 panel (docs/hardware.md). spi_hz: QSPI clock; flip: turn the picture 180 degrees (the board sits
 * either way round in the case). */
void display_init(int spi_hz, bool flip);
void display_present(const uint16_t *native); /* 480x320 RGB565 frame, as game_render() writes it */
/* Presenting on core 1 while the next frame is drawn: submit returns once the previous frame is out, so the
 * caller can draw into the other of two buffers. present_us: time the panel took, summed (diagnostics). */
void display_start_task(void);
void display_submit(const uint16_t *native);
const uint16_t *display_last(void); /* the frame last submitted: remote screenshots (remote.c) */
extern volatile int64_t display_present_us;
void display_backlight(int percent);
void display_sleep(void); /* panel off and asleep, after the frame in flight (power off) */
