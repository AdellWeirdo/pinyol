#pragma once
#include <stdbool.h>
#include <stdint.h>

/* ST77922 panel (docs/hardware.md). spi_hz: QSPI clock; flip: turn the picture 180 degrees (the board sits
 * either way round in the case). */
void display_init(int spi_hz, bool flip);
void display_present(const uint16_t *native); /* 480x320 RGB565 frame, as game_render() writes it */
/* The same transfer with the strips built by the caller: build(p0, out, ctx) fills panel rows p0..p0+31 (frame
 * columns), 32 x 320 pixels, byte-swapped for the bus. Strips go out by DMA while the next one is built. */
typedef void (*display_strip_fn)(int p0, uint16_t *out, void *ctx);
void display_present_strips(display_strip_fn build, void *ctx);
bool display_flipped(void);
void display_wait(void); /* until the presenting task is done with its frame: then the caller may send strips itself */
/* TE (GPIO 42): one pulse per frame (vblank only) or also one per line (the init's setting). */
void display_te_vblank_only(bool vblank_only);
int display_spi_khz(void); /* the clock the SPI driver really set, which can differ from the one asked for */
/* Presenting on core 1 while the next frame is drawn: submit returns once the previous frame is out, so the
 * caller can draw into the other of two buffers. present_us: time the panel took, summed (diagnostics). */
void display_start_task(void);
void display_submit(const uint16_t *native);
const uint16_t *display_last(void); /* the frame last submitted: remote screenshots (remote.c) */
extern volatile int64_t display_present_us;
void display_backlight(int percent);
void display_sleep(void); /* panel off and asleep, after the frame in flight (power off) */
