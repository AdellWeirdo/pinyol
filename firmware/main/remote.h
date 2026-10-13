#pragma once
#include "hal.h"

/* -DBP_REMOTE=ON test builds: input and screenshots over the USB cable (remote.c, tools/remote.py). */
void remote_init(void);
void remote_line(const char *cmd);  /* a line from the cable that cable.c does not take */
void remote_input(hal_input *in);   /* adds what the cable asked for to this poll's input */
const uint16_t *remote_picture(void); /* main.c: the frame on the panel, for shots */
