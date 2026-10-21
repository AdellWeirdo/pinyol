/* Flashing that can hurt (flashcheck.c): the headless player looks at every frame (--check-flashes) for more than
 * three flashes a second over a quarter of the screen, the limit of WCAG 2.3.1 and the games' accessibility guidelines
 * (a flash: a pair of opposing changes of 10 % or more in relative luminance, the darker side below 80 %). */
#pragma once
#include <stdbool.h>
#include <stdint.h>

void flash_reset(void);
/* A frame (480x320 RGB565). Returns the share of the screen (0..100) flashing more than three times in the last
 * second, 0 when within the limit; the caller fails the run past 25. */
int flash_frame(const uint16_t *fb);
