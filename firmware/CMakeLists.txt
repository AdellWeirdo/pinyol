# ConsolaS3 firmware (Freenove FNK0104N, ESP32-S3R8): a game list and the np2d engine (../src, built unchanged as
# the bp_core component) playing any game folder on the card; main/ is this console's platform (pins: docs/hardware.md).
cmake_minimum_required(VERSION 3.16)
include($ENV{IDF_PATH}/tools/cmake/project.cmake)
project(np2d_console)

# One game, minus its music and ambience beds (they need the card) and local saves, as a FAT image in the "game"
# partition, so the console runs without a microSD. Re-run `idf.py reconfigure` after changing the game's files.
#   idf.py -DFLASH_GAME=/path/to/games/mygame build
set(FLASH_GAME ${CMAKE_SOURCE_DIR}/../examples/hola CACHE PATH "Game folder baked into the flash")
string(REGEX REPLACE "/+$" "" FLASH_GAME "${FLASH_GAME}") # "games/mygame/" would otherwise give an empty id
get_filename_component(GAME_ID ${FLASH_GAME} NAME)
set(GAME_IMG ${CMAKE_BINARY_DIR}/game_image)
file(REMOVE_RECURSE ${GAME_IMG})
file(COPY ${FLASH_GAME}/ DESTINATION ${GAME_IMG}/games/${GAME_ID} PATTERN audio EXCLUDE PATTERN saves EXCLUDE)
# of the audio, what fits: interaction effects, listening clips and voices; music, ambience beds and random
# ambience events (SFX_AMB_*) stay on the card
if(EXISTS ${FLASH_GAME}/audio)
  file(COPY ${FLASH_GAME}/audio/ DESTINATION ${GAME_IMG}/games/${GAME_ID}/audio
       FILES_MATCHING PATTERN "SFX_*.wav" PATTERN "L*.wav" PATTERN "VO_*.wav")
  file(GLOB AMB_EVENTS ${GAME_IMG}/games/${GAME_ID}/audio/SFX_AMB_*.wav)
  file(REMOVE ${AMB_EVENTS})
endif()
# -DBP_AUTOTEST=ON: the console plays the listed end-to-end scripts on boot (/autotest/<game>/, without their
# shots), then shows its list; -DBP_SOAK=ON: the same again and again while all pass (/autotest/loop), heap logged.
#   -DBP_TESTS="mygame=/abs/mygame/tests/e2e.script;other=..." (the game folders must be on the card or in the flash);
#   with the example in the flash and no BP_TESTS, its own test runs
set(BP_TESTS "" CACHE STRING "game=script pairs for autotest builds")
if(BP_AUTOTEST OR BP_SOAK)
  set(TESTS ${BP_TESTS})
  if(NOT TESTS AND GAME_ID STREQUAL "hola")
    set(TESTS hola=${CMAKE_SOURCE_DIR}/../tests/hola.script)
  endif()
  foreach(t ${TESTS})
    string(REPLACE "=" ";" kv ${t})
    list(GET kv 0 game)
    list(GET kv 1 script)
    file(READ ${script} TEXT) # as text: a ';' in a comment would split a list
    string(REGEX REPLACE "\nshot [^\n]*" "" TEXT "${TEXT}")
    get_filename_component(name ${script} NAME)
    file(WRITE ${GAME_IMG}/autotest/${game}/${name} "${TEXT}")
  endforeach()
  if(BP_SOAK)
    file(TOUCH ${GAME_IMG}/autotest/loop)
  endif()
endif()
if(BP_OTA_TEST) # -DBP_OTA_TEST=<firmware.bin>: installed from the flash image on boot, as from a card (ota.c)
  file(COPY_FILE ${BP_OTA_TEST} ${GAME_IMG}/firmware.bin)
endif()
fatfs_create_spiflash_image(game ${GAME_IMG} FLASH_IN_PROJECT)
