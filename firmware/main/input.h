#pragma once
#include "driver/i2c_master.h"
#include "hal.h"

void input_init(void);   /* I2C bus, buttons, touch; logs what it found on the bus */
hal_input input_poll(void);
i2c_master_bus_handle_t input_bus(void); /* the shared bus, for the codec (F4) */
