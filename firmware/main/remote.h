#pragma once
#include "hal.h"

/* -DBP_REMOTE=ON test builds: input and screenshots over the USB cable (remote.c, tools/remote.py). */
void remote_init(void);
void remote_poll(hal_input *in); /* adds what the cable asked for to this poll's input */
