set(EMBED "")
if(BP_BENCH STREQUAL "play") # the end-to-end tests the play bench runs (main.c, bench_play)
  set(EMBED EMBED_TXTFILES ${CMAKE_CURRENT_LIST_DIR}/../../../Bajopueblo-ESP/tests/scripts/e2e_full.script
                           ${CMAKE_CURRENT_LIST_DIR}/../../../Geumgye-ESP/tests/scripts/e2e_lectura.script)
endif()
idf_component_register(SRCS main.c display.c sd.c input.c audio_out.c power.c launcher.c ota.c remote.c bench.c INCLUDE_DIRS .
                       REQUIRES bp_core esp_timer esp_psram esp_driver_spi esp_driver_ledc esp_driver_gpio
                                esp_driver_sdmmc esp_driver_i2c esp_driver_i2s esp_adc fatfs sdmmc vfs wear_levelling app_update
                                esp_driver_usb_serial_jtag mbedtls
                       ${EMBED})
target_compile_options(${COMPONENT_LIB} PRIVATE -Wall -Wextra -Werror -Wno-format-truncation) # bounded snprintf, as in bp_core
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
if(BP_AUTOTEST OR BP_SOAK OR BP_REMOTE) # test builds run unattended, often at night: mixed and timed, never heard
  target_compile_definitions(${COMPONENT_LIB} PRIVATE BP_QUIET)
endif()
