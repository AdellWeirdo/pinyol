#pragma once
#include <stdbool.h>
#include <stddef.h>
#include <stdint.h>

#include "hal.h"

/* A game sent over the console's USB cable by pinyol's editor (Chrome's Web Serial): cable.c. */
void cable_init(void);          /* the cable listens from boot */
void cable_poll(hal_input *in); /* in every input poll: what came over the cable (test builds: remote.c's input too) */
bool cable_wanted(void);        /* a game is on its way: the game or the list gives way to cable_receive */
/* Receives it, a progress screen on `frame` meanwhile; written to the card (or the flash), the old copy replaced
 * (its saves kept). True and its id once it is all there; false, and nothing changed, otherwise. */
bool cable_receive(uint16_t *frame, char *id, size_t id_size);
