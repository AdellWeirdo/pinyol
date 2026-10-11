idf_component_register(SRCS main.c display.c sd.c input.c audio_out.c power.c launcher.c ota.c remote.c bench.c INCLUDE_DIRS .
                       REQUIRES bp_core esp_timer esp_psram esp_driver_spi esp_driver_ledc esp_driver_gpio
                                esp_driver_sdmmc esp_driver_i2c esp_driver_i2s esp_adc fatfs sdmmc vfs wear_levelling app_update
                                esp_driver_usb_serial_jtag mbedtls)
target_compile_options(${COMPONENT_LIB} PRIVATE -Wall -Wextra -Werror -Wno-format-truncation) # bounded snprintf, as in bp_core
if(BP_REMOTE) # -DBP_REMOTE=ON: taps, keys and screenshots over the USB cable (remote.c, tools/remote.py)
  target_compile_definitions(${COMPONENT_LIB} PRIVATE BP_REMOTE)
endif()
if(BP_BENCH) # -DBP_BENCH=ON: renderer measurements instead of the game list (bench.c)
  target_compile_definitions(${COMPONENT_LIB} PRIVATE BP_BENCH)
endif()
if(BP_OTA_NEVER_GOOD)
  target_compile_definitions(${COMPONENT_LIB} PRIVATE BP_OTA_NEVER_GOOD)
endif()
if(BP_OTA_TEST)
  target_compile_definitions(${COMPONENT_LIB} PRIVATE BP_OTA_FILE="/flash/firmware.bin")
endif()
if(BP_AUTOTEST OR BP_SOAK OR BP_REMOTE) # test builds run unattended, often at night: mixed and timed, never heard
  target_compile_definitions(${COMPONENT_LIB} PRIVATE BP_QUIET)
endif()
