#pragma once
#include <stdbool.h>
#include <stdint.h>

#include "driver/i2c_master.h"

/* Codec, I2S and the mixing task on core 1; false (logged) if the codec does not answer. */
bool audio_out_init(i2c_master_bus_handle_t bus);
void audio_out_off(void); /* before deep sleep: the mixer stops for good, then the amplifier, held off */
extern volatile int64_t audio_out_mix_us; /* diagnostics: time in audio_mix(), summed */
extern volatile int audio_out_blocks, audio_out_underruns;
extern volatile int32_t audio_out_mix_min_us, audio_out_mix_max_us; /* per block: the quickest, the slowest */
