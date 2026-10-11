#pragma once
#include <stdbool.h>

#include "hal.h"

void power_init(void);     /* LED, battery and USB sensing; the power-on glow; a task keeps the LED current */
float power_volts(void);   /* smoothed battery voltage (on USB: the charger's output, the cell is cut off) */
bool power_usb(void);
bool power_critical(void); /* on battery under 3.4 V: the game should save and call power_off() */
void power_off(void);     /* green fade, screen and amplifier off, deep sleep until BOOT; does not return */
