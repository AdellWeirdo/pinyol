#pragma once
#include <stdint.h>

/* A new firmware copied to the card as firmware.bin goes into the other OTA slot, the file is renamed (.instalado,
 * or .fallido) and the console restarts into it. Returns only when there is nothing to install or it failed. */
void ota_from_card(uint16_t *frame);
/* The running firmware found its games and started its screen and sound: keep it. Until then, a restart rolls
 * back to the previous one. */
void ota_mark_good(void);
