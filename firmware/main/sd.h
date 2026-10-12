#pragma once
#include <stdbool.h>

/* Mounts the microSD at /sdcard and the "game" flash partition at /flash (games without their music, and the test
 * scripts of autotest builds); false if neither is usable. */
bool storage_mount(void);
bool storage_card(void); /* the microSD card is mounted at /sdcard */
