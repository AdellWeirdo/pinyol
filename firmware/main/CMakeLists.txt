idf_component_register(SRCS main.c display.c sd.c input.c audio_out.c power.c launcher.c ota.c cable.c remote.c bench.c link_radio.c
                       INCLUDE_DIRS .
                       REQUIRES bp_core esp_timer esp_psram esp_driver_spi esp_driver_ledc esp_driver_gpio
                                esp_driver_sdmmc esp_driver_i2c esp_driver_i2s esp_adc fatfs sdmmc vfs wear_levelling app_update
                                esp_driver_usb_serial_jtag mbedtls esp_wifi esp_event)
target_compile_options(${COMPONENT_LIB} PRIVATE -Wall -Wextra -Werror -Wno-format-truncation) # bounded snprintf, as in bp_core
# the engine (bp_core) calls the radio's hal_link_* (link_radio.c), which nothing in main does: link it in anyway
target_link_libraries(${COMPONENT_LIB} INTERFACE "-u hal_link_open")
if(BP_REMOTE) # -DBP_REMOTE=ON: taps, keys and screenshots over the USB cable (remote.c, tools/remote.py)
  target_compile_definitions(${COMPONENT_LIB} PRIVATE BP_REMOTE)
endif()
if(BP_FRAME_TICKS) # -DBP_FRAME_TICKS=1: draw every tick (60 fps) instead of every other one
  target_compile_definitions(${COMPONENT_LIB} PRIVATE TICKS_PER_FRAME=${BP_FRAME_TICKS})
endif()
if(BP_BENCH) # -DBP_BENCH=ON: renderer measurements instead of the game list (bench.c)
  target_compile_definitions(${COMPONENT_LIB} PRIVATE BP_BENCH)
  if(BP_BENCH STREQUAL "play")
    target_compile_definitions(${COMPONENT_LIB} PRIVATE BP_BENCH_PLAY)
  endif()
  if(BP_BENCH STREQUAL "v1")
    target_compile_definitions(${COMPONENT_LIB} PRIVATE BP_BENCH_V1)
  endif()
endif()
if(BP_OTA_NEVER_GOOD)
  target_compile_definitions(${COMPONENT_LIB} PRIVATE BP_OTA_NEVER_GOOD)
endif()
if(BP_OTA_TEST)
  target_compile_definitions(${COMPONENT_LIB} PRIVATE BP_OTA_FILE="/flash/firmware.bin")
endif()
# test builds run unattended, often at night: mixed and timed, never heard; -DBP_LOUD=ON: heard (the microphone
# tests listen to the speaker)
if((BP_AUTOTEST OR BP_SOAK OR BP_REMOTE) AND NOT BP_LOUD)
  target_compile_definitions(${COMPONENT_LIB} PRIVATE BP_QUIET)
endif()
if(BP_AUTOTEST OR BP_SOAK)
  target_compile_definitions(${COMPONENT_LIB} PRIVATE PERF_WINDOW_US=1000000)
endif()
