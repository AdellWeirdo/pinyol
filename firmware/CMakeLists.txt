# ConsolaS3 firmware (Freenove FNK0104N, ESP32-S3R8): a game list and the pinyol engine (../src, built unchanged as
# the pinyol_core component) playing any game folder on the card; main/ is this console's platform (pins: docs/hardware.md).
cmake_minimum_required(VERSION 3.16)
include($ENV{IDF_PATH}/tools/cmake/project.cmake)
project(pinyol_console)

# Games in the flash (FLASH_GAME, a ;-list of folders), so the console has something to play without a microSD.
# A game's music and ambience beds stay on the card when its audio is big; saves and art sources never go.
# Re-run `idf.py reconfigure` after changing a game's files.
#   idf.py -DFLASH_GAME="/abs/games/a;/abs/games/b" build
set(FLASH_GAME ${CMAKE_SOURCE_DIR}/../examples/hola CACHE STRING "Game folders baked into the flash (a ;-list)")
set(GAME_IMG ${CMAKE_BINARY_DIR}/game_image)
set(FLASH_IDS "")
file(REMOVE_RECURSE ${GAME_IMG})
foreach(game ${FLASH_GAME})
  string(REGEX REPLACE "/+$" "" game "${game}") # "games/mygame/" would otherwise give an empty id
  get_filename_component(GAME_ID ${game} NAME)
  list(APPEND FLASH_IDS ${GAME_ID})
  file(COPY ${game}/ DESTINATION ${GAME_IMG}/games/${GAME_ID}
       PATTERN audio EXCLUDE PATTERN saves EXCLUDE PATTERN art EXCLUDE PATTERN art.py EXCLUDE)
  if(EXISTS ${game}/audio)
    file(GLOB WAVS ${game}/audio/*.wav)
    set(audio_bytes 0)
    foreach(w ${WAVS})
      file(SIZE ${w} n)
      math(EXPR audio_bytes "${audio_bytes} + ${n}")
    endforeach()
    if(audio_bytes LESS 2000000) # small: all of it
      file(COPY ${game}/audio/ DESTINATION ${GAME_IMG}/games/${GAME_ID}/audio)
    else() # of a big game's audio, what fits: effects, listening clips and voices, not random ambience events
      file(COPY ${game}/audio/ DESTINATION ${GAME_IMG}/games/${GAME_ID}/audio
           FILES_MATCHING PATTERN "SFX_*.wav" PATTERN "L*.wav" PATTERN "VO_*.wav")
      file(GLOB AMB_EVENTS ${GAME_IMG}/games/${GAME_ID}/audio/SFX_AMB_*.wav)
      file(REMOVE ${AMB_EVENTS})
    endif()
  endif()
endforeach()
# -DBP_AUTOTEST=ON: the console plays the listed end-to-end scripts on boot (/autotest/<game>/, without their
# shots), then shows its list; -DBP_SOAK=ON: the same again and again while all pass (/autotest/loop), heap logged.
#   -DBP_TESTS="mygame=/abs/mygame/tests/e2e.script;other=..." (the game folders must be on the card or in the flash);
#   without BP_TESTS, every game in the flash with a tests/<id>.script in pinyol runs it
set(BP_TESTS "" CACHE STRING "game=script pairs for autotest builds")
if(BP_AUTOTEST OR BP_SOAK)
  set(TESTS ${BP_TESTS})
  if(NOT TESTS)
    foreach(id ${FLASH_IDS})
      if(EXISTS ${CMAKE_SOURCE_DIR}/../tests/${id}.script)
        list(APPEND TESTS ${id}=${CMAKE_SOURCE_DIR}/../tests/${id}.script)
      endif()
    endforeach()
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
