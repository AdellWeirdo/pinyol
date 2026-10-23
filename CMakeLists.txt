cmake_minimum_required(VERSION 3.13...3.21) # 3.13: RetroPie's image (Debian 10) builds the libretro core
project(pinyol C)

set(CMAKE_C_STANDARD 11)
set(CMAKE_C_STANDARD_REQUIRED ON)
if(NOT CMAKE_BUILD_TYPE)
  set(CMAKE_BUILD_TYPE Debug)
endif()
if(EMSCRIPTEN)
  set(SAN "")
else()
  set(SAN $<$<CONFIG:Debug>:-fsanitize=address,undefined;-fno-omit-frame-pointer>)
endif()
if(CMAKE_C_COMPILER_ID STREQUAL "GNU") # GCC warns at every snprintf that may cut; the engine's cut on purpose
  add_compile_options(-Wno-format-truncation)
endif()
# A game's repo can build the engine as a subproject: set GAME_DIR, then add_subdirectory(<pinyol> pinyol).
set(GAME_DIR ${CMAKE_CURRENT_SOURCE_DIR}/examples/hola CACHE PATH "Game folder the simulator opens and the web player packs")

if(WIN32)
  link_libraries(ws2_32) # the link's UDP (platform/link_udp.c): Winsock
  enable_language(RC)    # the desktop app's icon and manifest (platform/desktop/cirera.rc)
endif()
option(PINYOL_APP "pinyol_sim as the Cirera desktop app: named Cirera, and on Windows with no console window" OFF)

add_library(cjson STATIC third_party/cjson/cJSON.c)
target_include_directories(cjson PUBLIC ${CMAKE_CURRENT_SOURCE_DIR}/third_party/cjson)
target_compile_options(cjson PRIVATE -Wno-deprecated-declarations ${SAN})

# Lua 5.4 (third_party/lua/README.pinyol), with 32-bit integers and floats on every platform so a game behaves the same.
file(GLOB LUA_SRC CONFIGURE_DEPENDS third_party/lua/*.c)
add_library(lua STATIC ${LUA_SRC})
target_include_directories(lua PUBLIC ${CMAKE_CURRENT_SOURCE_DIR}/third_party/lua)
target_compile_definitions(lua PUBLIC LUA_32BITS=1)
# The same string hashes every run and on every platform, so pairs() walks a table in the same order: tests repeat,
# and consoles playing together over link compute the same thing
target_compile_definitions(lua PRIVATE "luai_makeseed=0x6e703264u+0*sizeof") # used as luai_makeseed(L)
target_compile_definitions(lua PRIVATE LUA_PINYOL_BUDGET) # lvm.c counts the engine's budget (third_party/lua/README.pinyol)
target_compile_options(lua PRIVATE ${SAN})

# Portable engine core: no SDL/ESP headers allowed in src/.
file(GLOB CORE_SRC CONFIGURE_DEPENDS src/*.c)
include(cmake/embed_lib.cmake)
pinyol_embed_lib(${CMAKE_BINARY_DIR}/pinyol_lib.c ${CMAKE_CURRENT_SOURCE_DIR}/lib)
pinyol_splash_pics(SPLASH_PICS ${CMAKE_CURRENT_SOURCE_DIR})
pinyol_embed_pics(${CMAKE_BINARY_DIR}/pinyol_splash.c ${SPLASH_PICS})
add_library(pinyol_core STATIC ${CORE_SRC} third_party/qrcodegen/qrcodegen.c third_party/ibxm/ibxm.c ${CMAKE_BINARY_DIR}/pinyol_lib.c ${CMAKE_BINARY_DIR}/pinyol_splash.c)
# IBXM (XM and S3M modules) keeps its own style; its memory goes to the console's slow memory (src/modplay.c)
set_source_files_properties(third_party/ibxm/ibxm.c PROPERTIES COMPILE_DEFINITIONS PINYOL_SLOW_ALLOC COMPILE_OPTIONS "-Wno-sign-compare;-Wno-unused-parameter;-Wno-implicit-fallthrough;-fno-sanitize=shift") # (it shifts negative values, as trackers always did)
# physics as the Lua code did it, operation for operation: no fused multiply-adds, the same on every platform
set_source_files_properties(src/lua_physics.c PROPERTIES COMPILE_OPTIONS -ffp-contract=off)
target_include_directories(pinyol_core PUBLIC ${CMAKE_CURRENT_SOURCE_DIR}/src)
target_include_directories(pinyol_core PRIVATE ${CMAKE_CURRENT_SOURCE_DIR}/third_party/pocketmod ${CMAKE_CURRENT_SOURCE_DIR}/third_party/ibxm ${CMAKE_CURRENT_SOURCE_DIR}/third_party/qrcodegen) # (the trackers, the crash screen's QR)
target_compile_options(pinyol_core PRIVATE -Wall -Wextra -Werror ${SAN})
target_link_libraries(pinyol_core PUBLIC cjson lua m)
target_link_options(pinyol_core PUBLIC ${SAN})
# The targets were called bp_core, bp_headless and bp_sim before the engine was pinyol: a game's repo that still says
# so keeps building, and its scripts can still run build/bp_headless. ponytail: drop once the games say pinyol_*
add_library(bp_core ALIAS pinyol_core)
function(old_name target old)
  add_executable(${old} ALIAS ${target})
  add_custom_command(TARGET ${target} POST_BUILD WORKING_DIRECTORY $<TARGET_FILE_DIR:${target}>
                     COMMAND ${CMAKE_COMMAND} -E rm -f ${old} COMMAND ${CMAKE_COMMAND} -E create_symlink ${target} ${old})
endfunction()

# Web builds: emcmake cmake -B build-web -DCMAKE_BUILD_TYPE=Release && cmake --build build-web
# -> build-web/index.html + .js + .wasm + .data: GAME_DIR packed in, at /game.
# -> build-web/player.html + .js + .wasm: any game, from a .zip (tools/pack_game.py) given as ?game=URL or dropped on
#    the page. Serve the folder over http.
if(EMSCRIPTEN)
  add_executable(pinyol_player platform/sdl/main.c)
  set_target_properties(pinyol_player PROPERTIES OUTPUT_NAME player SUFFIX .html)
  target_compile_options(pinyol_player PRIVATE -Wall -Wextra -sUSE_SDL=2)
  target_link_libraries(pinyol_player pinyol_core)
  target_link_options(pinyol_player PRIVATE -sUSE_SDL=2 -sALLOW_MEMORY_GROWTH=1 -sINITIAL_MEMORY=64MB -sINVOKE_RUN=0
                      -sFORCE_FILESYSTEM=1 -sEXPORTED_RUNTIME_METHODS=FS,callMain,UTF8ToString -lidbfs.js
                      --shell-file ${CMAKE_CURRENT_SOURCE_DIR}/platform/web/player.html)
  set_property(TARGET pinyol_player APPEND PROPERTY LINK_DEPENDS ${CMAKE_CURRENT_SOURCE_DIR}/platform/web/player.html)

  add_executable(pinyol_web platform/sdl/main.c)
  set_target_properties(pinyol_web PROPERTIES OUTPUT_NAME index SUFFIX .html)
  target_compile_options(pinyol_web PRIVATE -Wall -Wextra -sUSE_SDL=2)
  target_link_libraries(pinyol_web pinyol_core)
  target_link_options(pinyol_web PRIVATE -sUSE_SDL=2 -sALLOW_MEMORY_GROWTH=1 -sINITIAL_MEMORY=64MB
                      --shell-file ${CMAKE_CURRENT_SOURCE_DIR}/platform/web/shell.html
                      --preload-file ${GAME_DIR}@/game --exclude-file ${GAME_DIR}/saves)
  set_property(TARGET pinyol_web APPEND PROPERTY LINK_DEPENDS ${CMAKE_CURRENT_SOURCE_DIR}/platform/web/shell.html)
  return()
endif()

add_executable(pinyol_headless platform/null/main.c platform/null/hal_null.c platform/link_udp.c)
target_compile_options(pinyol_headless PRIVATE -Wall -Wextra -Werror ${SAN})
target_compile_definitions(pinyol_headless PRIVATE PINYOL_GAME="${GAME_DIR}") # the game it opens without --game
target_link_libraries(pinyol_headless pinyol_core)
old_name(pinyol_headless bp_headless)

find_package(SDL2 CONFIG QUIET)
if(SDL2_FOUND)
  add_executable(pinyol_sim platform/sdl/main.c platform/sdl/desktop.c platform/sdl/capture.c platform/link_udp.c)
  target_compile_options(pinyol_sim PRIVATE -Wall -Wextra ${SAN})
  target_include_directories(pinyol_sim PRIVATE third_party/msf_gif) # the GIF of the last eight seconds (F9)
  set_source_files_properties(platform/sdl/capture.c PROPERTIES COMPILE_OPTIONS "-Wno-missing-field-initializers;-Wno-unused-parameter") # (msf_gif's)
  # the captures on a made-up screen, and PIL reads the files back
  add_executable(capture_test tests/capture_test.c platform/sdl/capture.c platform/null/hal_null.c platform/link_udp.c)
  target_include_directories(capture_test PRIVATE third_party/msf_gif platform/sdl)
  set_source_files_properties(tests/capture_test.c PROPERTIES COMPILE_OPTIONS "-Wall;-Wextra;-Werror")
  target_link_libraries(capture_test pinyol_core)

  target_compile_definitions(pinyol_sim PRIVATE PINYOL_GAME="${GAME_DIR}")
  # the app links SDL statically where SDL was built so (SDL2::SDL2-static): one file, nothing to install beside it
  if(PINYOL_APP AND TARGET SDL2::SDL2-static)
    set(PINYOL_SDL SDL2::SDL2-static)
  else()
    set(PINYOL_SDL SDL2::SDL2)
  endif()
  if(WIN32)
    target_link_libraries(pinyol_sim pinyol_core SDL2::SDL2main ${PINYOL_SDL}) # SDL2main (WinMain, then main) first
    target_link_options(pinyol_sim PRIVATE -static) # MinGW's own runtime inside: only SDL2.dll goes beside it
  else()
    target_link_libraries(pinyol_sim pinyol_core ${PINYOL_SDL})
  endif()
  if(PINYOL_APP)
    set_target_properties(pinyol_sim PROPERTIES OUTPUT_NAME Cirera WIN32_EXECUTABLE ON)
    if(WIN32)
      target_sources(pinyol_sim PRIVATE platform/desktop/cirera.rc) # its icon, and UTF-8 paths (the manifest)
      target_link_options(pinyol_sim PRIVATE -s) # no debug symbols in what people download
    endif()
    target_compile_definitions(pinyol_sim PRIVATE PINYOL_APP=1)
  endif()
  old_name(pinyol_sim bp_sim)
else()
  message(STATUS "SDL2 not found: pinyol_sim skipped (brew install sdl2)")
endif()

# The libretro core, for RetroArch and what is built on it (RetroPie, Batocera, Recalbox, Lakka...): docs/libretro.md.
# -> pinyol_libretro.so (.dylib on a Mac). It exports only retro_*, so the engine's names never meet the frontend's.
set_target_properties(pinyol_core lua cjson PROPERTIES POSITION_INDEPENDENT_CODE ON)
add_library(pinyol_libretro SHARED platform/libretro/libretro.c platform/link_udp.c third_party/puff/puff.c)
set_target_properties(pinyol_libretro PROPERTIES PREFIX "")
target_include_directories(pinyol_libretro PRIVATE third_party/libretro third_party/puff)
target_compile_options(pinyol_libretro PRIVATE -Wall -Wextra -Werror ${SAN})
execute_process(COMMAND git rev-parse --short HEAD WORKING_DIRECTORY ${CMAKE_CURRENT_SOURCE_DIR}
                OUTPUT_VARIABLE PINYOL_REV OUTPUT_STRIP_TRAILING_WHITESPACE ERROR_QUIET)
if(PINYOL_REV) # the version RetroArch shows (as of the last configure)
  target_compile_definitions(pinyol_libretro PRIVATE PINYOL_VERSION="${PINYOL_REV}")
endif()
target_link_libraries(pinyol_libretro PRIVATE pinyol_core)
if(APPLE)
  target_link_options(pinyol_libretro PRIVATE "LINKER:-exported_symbol,_retro_*")
else()
  target_link_options(pinyol_libretro PRIVATE "LINKER:--version-script=${CMAKE_CURRENT_SOURCE_DIR}/platform/libretro/link.T"
                      "LINKER:--no-undefined")
endif()

if(NOT CMAKE_SOURCE_DIR STREQUAL CMAKE_CURRENT_SOURCE_DIR) # a game's repo registers its own tests
  return()
endif()
enable_testing()
add_executable(ppu_test tests/ppu_test.c platform/null/hal_null.c platform/link_udp.c)
target_compile_options(ppu_test PRIVATE -Wall -Wextra -Werror ${SAN})
target_link_libraries(ppu_test pinyol_core)
add_test(NAME ppu COMMAND ppu_test)
add_executable(grad_test tests/grad_test.c platform/null/hal_null.c platform/link_udp.c)
target_compile_options(grad_test PRIVATE -Wall -Wextra -Werror ${SAN})
target_link_libraries(grad_test pinyol_core)
add_test(NAME grad_table COMMAND grad_test) # a dithered gradient from its ramp worked out ahead is the one that works it out itself
add_executable(ppu_golden_test tests/ppu_golden_test.c platform/null/hal_null.c platform/link_udp.c)
target_compile_options(ppu_golden_test PRIVATE -Wall -Wextra -Werror ${SAN})
target_link_libraries(ppu_golden_test pinyol_core)
add_test(NAME ppu_golden COMMAND ppu_golden_test ${CMAKE_CURRENT_SOURCE_DIR}/tests/ppu_golden.txt)
add_executable(psg_test tests/psg_test.c platform/null/hal_null.c platform/link_udp.c)
target_compile_options(psg_test PRIVATE -Wall -Wextra -Werror ${SAN})
target_link_libraries(psg_test pinyol_core)
add_test(NAME psg COMMAND psg_test)
add_executable(mod_test tests/mod_test.c platform/null/hal_null.c platform/link_udp.c)
target_compile_options(mod_test PRIVATE -Wall -Wextra -Werror ${SAN})
target_link_libraries(mod_test pinyol_core)
add_test(NAME mod COMMAND mod_test)
add_executable(span_test tests/span_test.c platform/null/hal_null.c platform/link_udp.c)
target_compile_options(span_test PRIVATE -Wall -Wextra -Werror ${SAN})
target_link_libraries(span_test pinyol_core)
add_test(NAME span COMMAND span_test) # one colour mixed into a run: the same pixels as the general mixing
add_executable(mesh_test tests/mesh_test.c src/mesh.c)
target_include_directories(mesh_test PRIVATE src)
target_compile_options(mesh_test PRIVATE -Wall -Wextra -Werror ${SAN})
target_link_libraries(mesh_test m)
target_link_options(mesh_test PRIVATE ${SAN})
add_test(NAME mesh COMMAND mesh_test) # mesh(): faces that show, snap, lamp, fade, ordering table, limits
add_executable(conf_test tests/conf_test.c platform/null/hal_null.c platform/link_udp.c)
target_compile_options(conf_test PRIVATE -Wall -Wextra -Werror ${SAN})
target_link_libraries(conf_test pinyol_core)
add_test(NAME conf COMMAND conf_test) # the console's settings: parsing, and the colour filter's table
add_executable(qr_test tests/qr_test.c third_party/qrcodegen/qrcodegen.c)
target_include_directories(qr_test PRIVATE third_party/qrcodegen)
target_compile_options(qr_test PRIVATE -Wall -Wextra -Werror ${SAN})
target_link_options(qr_test PRIVATE ${SAN})
add_test(NAME qr COMMAND qr_test) # the crash screen's QR code: a short text and a long one, their finder patterns
# flashing that can hurt: a game that flashes the whole screen every tick fails --check-flashes (4), a quiet one passes
add_test(NAME flashes_caught COMMAND sh -c "$<TARGET_FILE:pinyol_headless> --game ${CMAKE_CURRENT_SOURCE_DIR}/tests/games/flash \
  --saves ${CMAKE_BINARY_DIR}/saves_flash --fresh --script ${CMAKE_CURRENT_SOURCE_DIR}/tests/flash.script --check-flashes; test $? -eq 4")
add_test(NAME flashes_quiet COMMAND pinyol_headless --game ${CMAKE_CURRENT_SOURCE_DIR}/tests/games/sysmenu
  --saves ${CMAKE_BINARY_DIR}/saves_flash_quiet --fresh --script ${CMAKE_CURRENT_SOURCE_DIR}/tests/sysmenu.script --check-flashes)
# a play recorded as a script plays back frame for frame: plataformas' test through the recorder, then the recording, the same CRCs
add_test(NAME record_replay COMMAND sh -c "$<TARGET_FILE:pinyol_headless> --game ${CMAKE_CURRENT_SOURCE_DIR}/tests/games/plataformas \
  --saves ${CMAKE_BINARY_DIR}/saves_rec1 --fresh --script ${CMAKE_CURRENT_SOURCE_DIR}/tests/record/plataformas_input.script --crc ${CMAKE_BINARY_DIR}/rec1.crc \
  --record ${CMAKE_BINARY_DIR}/rec.script >/dev/null && $<TARGET_FILE:pinyol_headless> --game ${CMAKE_CURRENT_SOURCE_DIR}/tests/games/plataformas \
  --saves ${CMAKE_BINARY_DIR}/saves_rec2 --fresh --script ${CMAKE_BINARY_DIR}/rec.script --crc ${CMAKE_BINARY_DIR}/rec2.crc >/dev/null && \
  cmp ${CMAKE_BINARY_DIR}/rec1.crc ${CMAKE_BINARY_DIR}/rec2.crc")
add_executable(synth_test tests/synth_test.c platform/null/hal_null.c platform/link_udp.c)
target_compile_options(synth_test PRIVATE -Wall -Wextra -Werror ${SAN})
target_link_libraries(synth_test pinyol_core)
add_test(NAME synth COMMAND synth_test)
add_executable(lua_mem_test tests/lua_mem_test.c platform/null/hal_null.c platform/link_udp.c)
target_compile_options(lua_mem_test PRIVATE -Wall -Wextra -Werror ${SAN})
target_link_libraries(lua_mem_test pinyol_core)
add_test(NAME lua_mem COMMAND lua_mem_test) # Lua's memory: random blocks across the small/big border, contents and alignment checked, chunks back at the reset
add_executable(audio_voice_test tests/audio_voice_test.c platform/null/hal_null.c platform/link_udp.c)
target_compile_options(audio_voice_test PRIVATE -Wall -Wextra -Werror ${SAN})
target_link_libraries(audio_voice_test pinyol_core)
add_test(NAME audio_voice COMMAND audio_voice_test)
add_executable(ppu_linepal_test tests/ppu_linepal_test.c platform/null/hal_null.c platform/link_udp.c)
target_compile_options(ppu_linepal_test PRIVATE -Wall -Wextra -Werror ${SAN})
target_link_libraries(ppu_linepal_test pinyol_core)
add_test(NAME ppu_linepal COMMAND ppu_linepal_test)
add_executable(post_fx_test tests/post_fx_test.c platform/null/hal_null.c platform/link_udp.c)
target_compile_options(post_fx_test PRIVATE -Wall -Wextra -Werror ${SAN})
target_link_libraries(post_fx_test pinyol_core)
add_test(NAME post_fx COMMAND post_fx_test)
add_executable(audio_ambient_test tests/audio_ambient_test.c platform/null/hal_null.c platform/link_udp.c)
target_compile_options(audio_ambient_test PRIVATE -Wall -Wextra -Werror ${SAN})
target_link_libraries(audio_ambient_test pinyol_core)
add_test(NAME audio_ambient COMMAND audio_ambient_test)
add_executable(studio_test tests/studio_test.c platform/null/hal_null.c platform/link_udp.c)
target_compile_options(studio_test PRIVATE -Wall -Wextra -Werror ${SAN})
target_link_libraries(studio_test pinyol_core)
add_test(NAME studio COMMAND studio_test)
add_executable(audio_test tests/audio_test.c platform/null/hal_null.c platform/link_udp.c)
target_compile_options(audio_test PRIVATE -Wall -Wextra -Werror ${SAN})
target_link_libraries(audio_test pinyol_core)
add_test(NAME audio COMMAND audio_test)
add_executable(audio_bench EXCLUDE_FROM_ALL tests/audio_bench.c platform/null/hal_null.c platform/link_udp.c) # not a test: make audio_bench
target_link_libraries(audio_bench pinyol_core)
add_executable(files_test tests/files_test.c platform/null/hal_null.c platform/link_udp.c)
target_compile_options(files_test PRIVATE -Wall -Wextra -Werror ${SAN})
target_link_libraries(files_test pinyol_core)
add_test(NAME files COMMAND files_test)
# Every example opens and validates; tests/<name>.script plays examples/<name> (with its strips checked).
file(GLOB EXAMPLES LIST_DIRECTORIES true CONFIGURE_DEPENDS examples/*)
foreach(dir ${EXAMPLES})
  if(IS_DIRECTORY ${dir})
    get_filename_component(n ${dir} NAME)
    add_test(NAME validate_${n} COMMAND pinyol_headless --game ${dir} --validate)
  endif()
endforeach()
# Games made by the tools, when Python 3 has Pillow: tests/template_lua.script plays one just made by
# tools/new_game.py --lua, tests/tiled.script one with levels from Tiled (tests/make_tiled_game.py).
find_package(Python3 COMPONENTS Interpreter QUIET)
if(Python3_FOUND) # the site's numbers: the minutes played, the ranking, the cover of the week (tools/stats.py)
  add_test(NAME stats COMMAND ${Python3_EXECUTABLE} ${CMAKE_CURRENT_SOURCE_DIR}/tools/stats.py --test)
  add_test(NAME midi_songs COMMAND ${Python3_EXECUTABLE} ${CMAKE_CURRENT_SOURCE_DIR}/tests/midi_test.py
           $<TARGET_FILE:pinyol_headless> ${CMAKE_BINARY_DIR}/midi) # a MIDI file played by a bank of samples, and one from a SoundFont
  add_test(NAME vag_sounds COMMAND ${Python3_EXECUTABLE} ${CMAKE_CURRENT_SOURCE_DIR}/tests/vag_test.py
           $<TARGET_FILE:pinyol_headless> ${CMAKE_BINARY_DIR}/vag)
  add_test(NAME strict_assets COMMAND ${Python3_EXECUTABLE} ${CMAKE_CURRENT_SOURCE_DIR}/tests/strict_assets_test.py
           $<TARGET_FILE:pinyol_headless>)
endif()
# The desktop app's install of a dropped .zip (platform/sdl/desktop.c: the system's tar on macOS and Windows, unzip on
# Linux)
if(SDL2_FOUND AND Python3_FOUND)
  add_executable(desktop_test tests/desktop_test.c platform/sdl/desktop.c)
  target_compile_options(desktop_test PRIVATE -Wall -Wextra -Werror)
  target_include_directories(desktop_test PRIVATE src platform/sdl)
  target_link_libraries(desktop_test ${PINYOL_SDL})
  if(WIN32) # as the app: one file, UTF-8 paths (the manifest)
    target_sources(desktop_test PRIVATE platform/desktop/cirera.rc)
    target_link_options(desktop_test PRIVATE -static)
  endif()
  add_test(NAME desktop_install COMMAND ${Python3_EXECUTABLE} ${CMAKE_CURRENT_SOURCE_DIR}/tests/desktop_test.py
           $<TARGET_FILE:desktop_test>)
endif()
set(NO_PIL 1)
if(Python3_FOUND)
  execute_process(COMMAND ${Python3_EXECUTABLE} -c "import PIL" RESULT_VARIABLE NO_PIL OUTPUT_QUIET ERROR_QUIET)
endif()
if(NOT NO_PIL) # the importers (ase2asset, ldtk2asset), strings_check and pack_game --budget, on files made by the test
  add_test(NAME tools COMMAND ${Python3_EXECUTABLE} ${CMAKE_CURRENT_SOURCE_DIR}/tests/tools_test.py ${CMAKE_BINARY_DIR})
endif()
if(TARGET capture_test AND NOT NO_PIL) # the simulator's captures (PNG, cover, GIF), read back with PIL
  add_test(NAME capture COMMAND sh -c "rm -rf ${CMAKE_BINARY_DIR}/capture && mkdir -p ${CMAKE_BINARY_DIR}/capture && \
    $<TARGET_FILE:capture_test> ${CMAKE_BINARY_DIR}/capture && ${Python3_EXECUTABLE} ${CMAKE_CURRENT_SOURCE_DIR}/tests/capture_check.py ${CMAKE_BINARY_DIR}/capture")
endif()
if(NOT NO_PIL)
  add_test(NAME new_lua_game COMMAND ${Python3_EXECUTABLE} -c
           "import shutil, subprocess, sys; shutil.rmtree(sys.argv[1], True); subprocess.run([sys.executable, sys.argv[2], sys.argv[1], '--lua'], check=True)"
           ${CMAKE_BINARY_DIR}/template_lua ${CMAKE_CURRENT_SOURCE_DIR}/tools/new_game.py)
  set_tests_properties(new_lua_game PROPERTIES FIXTURES_SETUP lua_template)
  add_test(NAME make_tiled_game COMMAND ${Python3_EXECUTABLE} ${CMAKE_CURRENT_SOURCE_DIR}/tests/make_tiled_game.py
           ${CMAKE_BINARY_DIR}/tiled)
  set_tests_properties(make_tiled_game PROPERTIES FIXTURES_SETUP tiled_game)
  add_test(NAME make_neo_game COMMAND ${Python3_EXECUTABLE} ${CMAKE_CURRENT_SOURCE_DIR}/tests/make_neo_game.py
           ${CMAKE_BINARY_DIR}/neo --packed)
  set_tests_properties(make_neo_game PROPERTIES FIXTURES_SETUP neo_game)
  add_test(NAME make_clip_game COMMAND ${Python3_EXECUTABLE} ${CMAKE_CURRENT_SOURCE_DIR}/tests/make_clip_game.py
           ${CMAKE_BINARY_DIR}/clip)
  set_tests_properties(make_clip_game PROPERTIES FIXTURES_SETUP clip_game)
  add_test(NAME packed_pictures COMMAND ${Python3_EXECUTABLE} ${CMAKE_CURRENT_SOURCE_DIR}/tests/packed_test.py
           $<TARGET_FILE:pinyol_headless> ${CMAKE_BINARY_DIR}/packed)
  add_test(NAME font_packs COMMAND ${Python3_EXECUTABLE} ${CMAKE_CURRENT_SOURCE_DIR}/tests/fonts_test.py
           $<TARGET_FILE:pinyol_headless> ${CMAKE_BINARY_DIR}/fontpacks) # the catalog, every pack, the engine drawing each
  add_test(NAME depthcut COMMAND ${Python3_EXECUTABLE} ${CMAKE_CURRENT_SOURCE_DIR}/tests/depthcut_test.py
           $<TARGET_FILE:pinyol_headless> ${CMAKE_BINARY_DIR}/depthcut) # a background cut into pieces at their depth
  add_test(NAME build_art COMMAND ${Python3_EXECUTABLE} ${CMAKE_CURRENT_SOURCE_DIR}/tests/build_art_test.py
           $<TARGET_FILE:pinyol_headless> ${CMAKE_BINARY_DIR}/build_art) # raw art to assets from art.json, only what changed
  add_test(NAME atlas COMMAND ${Python3_EXECUTABLE} ${CMAKE_CURRENT_SOURCE_DIR}/tests/atlas_test.py
           $<TARGET_FILE:pinyol_headless>)
  add_test(NAME clip_scenes COMMAND ${Python3_EXECUTABLE} ${CMAKE_CURRENT_SOURCE_DIR}/tests/clip_scenes_test.py
           $<TARGET_FILE:pinyol_headless> ${CMAKE_BINARY_DIR}/clip_scenes) # a palette a scene, the ordered dither
  add_test(NAME library COMMAND ${Python3_EXECUTABLE} ${CMAKE_CURRENT_SOURCE_DIR}/tests/library_test.py
           $<TARGET_FILE:pinyol_headless>) # what tools/library.py takes and refuses from the Library's form
endif()
# The libretro core as a frontend sees it: a game from its folder, its game.json and its zip plays the same, and a
  add_test(NAME kit_pivot_flip COMMAND ${Python3_EXECUTABLE} ${CMAKE_CURRENT_SOURCE_DIR}/tests/kitflip_test.py
           $<TARGET_FILE:pinyol_headless>) # a kind turns round its pivot, one without round its box's middle
  add_test(NAME store_atomic COMMAND ${Python3_EXECUTABLE} ${CMAKE_CURRENT_SOURCE_DIR}/tests/store_test.py
           $<TARGET_FILE:pinyol_headless>) # the saves: two files in turn, a checksum, a failed save leaves the last good one
# damaged zip or one reaching outside its folder is refused (tests/libretro_test.c is the frontend)
add_executable(libretro_test tests/libretro_test.c)
target_include_directories(libretro_test PRIVATE third_party/libretro)
target_compile_options(libretro_test PRIVATE -Wall -Wextra -Werror ${SAN})
target_link_options(libretro_test PRIVATE ${SAN})
target_link_libraries(libretro_test ${CMAKE_DL_LIBS})
if(Python3_FOUND)
  add_test(NAME libretro COMMAND ${Python3_EXECUTABLE} ${CMAKE_CURRENT_SOURCE_DIR}/tests/libretro_test.py
           $<TARGET_FILE:libretro_test> $<TARGET_FILE:pinyol_libretro> ${CMAKE_CURRENT_SOURCE_DIR}/examples/naves
           ${CMAKE_BINARY_DIR}/libretro)
endif()
find_program(NODE node) # the web editor's templates, built as the browser builds them, for script_editor_*
if(NODE)
  add_test(NAME make_editor_game COMMAND ${NODE} ${CMAKE_CURRENT_SOURCE_DIR}/editor/test/build_game.mjs
           ${CMAKE_BINARY_DIR}/editor)
  set_tests_properties(make_editor_game PROPERTIES FIXTURES_SETUP editor_game)
  add_test(NAME editor_cable COMMAND ${NODE} ${CMAKE_CURRENT_SOURCE_DIR}/editor/test/cable_test.mjs)
  add_test(NAME editor_packed COMMAND ${NODE} ${CMAKE_CURRENT_SOURCE_DIR}/editor/test/packed_test.mjs)
  add_test(NAME editor_i18n COMMAND ${NODE} ${CMAKE_CURRENT_SOURCE_DIR}/editor/test/i18n_test.mjs) # Catalan, English
  add_test(NAME editor_anims COMMAND ${NODE} ${CMAKE_CURRENT_SOURCE_DIR}/editor/test/anims_test.mjs) # speed, loop, pivot, sheets
endif()
file(GLOB SCRIPTS CONFIGURE_DEPENDS tests/*.script)
foreach(s ${SCRIPTS})
  get_filename_component(n ${s} NAME_WE)
  set(game ${CMAKE_CURRENT_SOURCE_DIR}/examples/${n})
  if(n STREQUAL "template_lua" OR n STREQUAL "tiled" OR n STREQUAL "neo" OR n STREQUAL "clip")
    if(NO_PIL)
      continue()
    endif()
    set(game ${CMAKE_BINARY_DIR}/${n})
  elseif(n MATCHES "^editor_(.+)")
    if(NOT NODE)
      continue()
    endif()
    set(game ${CMAKE_BINARY_DIR}/editor/${CMAKE_MATCH_1}) # a template of the editor, built by make_editor_game
  elseif(n STREQUAL "cirera")
    set(game ${CMAKE_CURRENT_SOURCE_DIR}/firmware/cirera) # the console's menu
  elseif(n STREQUAL "careta_aventura")
    set(game ${CMAKE_CURRENT_SOURCE_DIR}/examples/hola) # the engine's careta before an adventure's title
  elseif(NOT IS_DIRECTORY ${game})
    set(game ${CMAKE_CURRENT_SOURCE_DIR}/tests/games/${n}) # games that only exist to be tested
  endif()
  set(splash "")
  if(n MATCHES "^careta") # the careta plays first (the others start at _init, their ticks counted from there)
    set(splash --splash)
  endif()
  add_test(NAME script_${n} COMMAND pinyol_headless --game ${game}
           --saves ${CMAKE_BINARY_DIR}/saves_${n} --fresh --script ${s} --check-strips ${splash})
endforeach()
if(Python3_FOUND)
  add_test(NAME quad_mesh_screen COMMAND ${Python3_EXECUTABLE} ${CMAKE_CURRENT_SOURCE_DIR}/tests/quad_mesh_screen.py
           ${CMAKE_BINARY_DIR}/saves_quad/quad.ppm)
  set_tests_properties(script_quad PROPERTIES FIXTURES_SETUP quad_mesh)
  set_tests_properties(quad_mesh_screen PROPERTIES FIXTURES_REQUIRED quad_mesh)
  if(NOT NO_PIL) # the new looks' shots read back: palcycle, shock, haze, line_scroll_ramp, line_affine
    add_test(NAME looks_pixels COMMAND ${Python3_EXECUTABLE} ${CMAKE_CURRENT_SOURCE_DIR}/tests/looks_check.py ${CMAKE_BINARY_DIR}/saves_looks)
    set_tests_properties(script_looks PROPERTIES FIXTURES_SETUP looks_shots)
    set_tests_properties(looks_pixels PROPERTIES FIXTURES_REQUIRED looks_shots)
    # mesh() against the same cube drawn by hand with quad(): the same picture
    add_test(NAME mesh_pixels COMMAND ${Python3_EXECUTABLE} ${CMAKE_CURRENT_SOURCE_DIR}/tests/mesh_check.py ${CMAKE_BINARY_DIR}/saves_mesh)
    set_tests_properties(script_mesh PROPERTIES FIXTURES_SETUP mesh_shots)
    set_tests_properties(mesh_pixels PROPERTIES FIXTURES_REQUIRED mesh_shots)
  endif()
    # quad() against what a real PlayStation drew (tests/ps1cube_ref): silhouette, box and colour of a lit, textured cube
    add_test(NAME ps1cube_pixels COMMAND ${Python3_EXECUTABLE} ${CMAKE_CURRENT_SOURCE_DIR}/tests/ps1cube_check.py ${CMAKE_BINARY_DIR}/saves_ps1cube)
    set_tests_properties(script_ps1cube PROPERTIES FIXTURES_SETUP ps1cube_shots)
    set_tests_properties(ps1cube_pixels PROPERTIES FIXTURES_REQUIRED ps1cube_shots)
endif()
# the console's menu (a game too) lists the examples as the console lists its games
set_tests_properties(script_cirera PROPERTIES ENVIRONMENT "PINYOL_GAMES=${CMAKE_CURRENT_SOURCE_DIR}/examples")
# the console's record (played.json) lives in PINYOL_HOME for this test, fresh each run
set_tests_properties(script_trophies PROPERTIES ENVIRONMENT "PINYOL_HOME=${CMAKE_BINARY_DIR}/home_trophies")
add_test(NAME trophies_fresh COMMAND ${CMAKE_COMMAND} -E rm -rf ${CMAKE_BINARY_DIR}/home_trophies)
set_tests_properties(trophies_fresh PROPERTIES FIXTURES_SETUP trophies_home)
set_tests_properties(script_trophies PROPERTIES FIXTURES_REQUIRED trophies_home)
# a canvas shown turned, changed every frame, must look different from one frame to the next (not a kept copy)
add_test(NAME turned_canvas COMMAND sh -c "$<TARGET_FILE:pinyol_headless> --game ${CMAKE_CURRENT_SOURCE_DIR}/tests/games/turned \
  --saves ${CMAKE_BINARY_DIR}/saves_turned_crc --fresh --script ${CMAKE_CURRENT_SOURCE_DIR}/tests/turned.script \
  --crc ${CMAKE_BINARY_DIR}/turned.crc >/dev/null && test $(tail -n 4 ${CMAKE_BINARY_DIR}/turned.crc | sort -u | wc -l) -ge 2")
if(NOT NO_PIL)
  set_tests_properties(script_template_lua PROPERTIES FIXTURES_REQUIRED lua_template)
  set_tests_properties(script_tiled PROPERTIES FIXTURES_REQUIRED tiled_game)
  set_tests_properties(script_neo PROPERTIES FIXTURES_REQUIRED neo_game)
  set_tests_properties(script_clip PROPERTIES FIXTURES_REQUIRED clip_game)
endif()
# line_fx: a fade whose amount grows down the screen, then line_off: two pictures, no more, no fewer
add_test(NAME physics_drive COMMAND $<TARGET_FILE:pinyol_headless> --game ${CMAKE_CURRENT_SOURCE_DIR}/tests/games/drive
  --saves ${CMAKE_BINARY_DIR}/saves_drive_x --fresh --script ${CMAKE_CURRENT_SOURCE_DIR}/tests/drive.script)
add_test(NAME pinball COMMAND $<TARGET_FILE:pinyol_headless> --game ${CMAKE_CURRENT_SOURCE_DIR}/examples/pinball
  --saves ${CMAKE_BINARY_DIR}/saves_pinball_x --fresh --script ${CMAKE_CURRENT_SOURCE_DIR}/tests/pinball.script)
add_test(NAME combate COMMAND sh -c "rm -rf ${CMAKE_BINARY_DIR}/saves_combate_x && $<TARGET_FILE:pinyol_headless> --game ${CMAKE_CURRENT_SOURCE_DIR}/examples/combate \
  --saves ${CMAKE_BINARY_DIR}/saves_combate_x --fresh --script ${CMAKE_CURRENT_SOURCE_DIR}/tests/combate.script >/dev/null && \
  cmp ${CMAKE_BINARY_DIR}/saves_combate_x/leak_a.ppm ${CMAKE_BINARY_DIR}/saves_combate_x/leak_b.ppm")
add_test(NAME tablero COMMAND $<TARGET_FILE:pinyol_headless> --game ${CMAKE_CURRENT_SOURCE_DIR}/examples/tablero
  --saves ${CMAKE_BINARY_DIR}/saves_tablero_x --fresh --script ${CMAKE_CURRENT_SOURCE_DIR}/tests/tablero.script)
add_test(NAME microjuegos COMMAND sh -c "rm -rf ${CMAKE_BINARY_DIR}/saves_microjuegos_x && $<TARGET_FILE:pinyol_headless> --game ${CMAKE_CURRENT_SOURCE_DIR}/examples/microjuegos \
  --saves ${CMAKE_BINARY_DIR}/saves_microjuegos_x --fresh --script ${CMAKE_CURRENT_SOURCE_DIR}/tests/microjuegos.script >/dev/null && \
  for i in 1 2 3 4 5 6 7 8; do cmp ${CMAKE_BINARY_DIR}/saves_microjuegos_x/leak_0.ppm ${CMAKE_BINARY_DIR}/saves_microjuegos_x/leak_$i.ppm || exit 1; done")
add_test(NAME isla_depth COMMAND sh -c "rm -rf ${CMAKE_BINARY_DIR}/saves_isla_x && $<TARGET_FILE:pinyol_headless> --game ${CMAKE_CURRENT_SOURCE_DIR}/examples/isla \
  --saves ${CMAKE_BINARY_DIR}/saves_isla_x --fresh --script ${CMAKE_CURRENT_SOURCE_DIR}/tests/isla.script >/dev/null && \
  cmp ${CMAKE_BINARY_DIR}/saves_isla_x/isla_behind.ppm ${CMAKE_BINARY_DIR}/saves_isla_x/isla_behind_none.ppm && \
  ! cmp -s ${CMAKE_BINARY_DIR}/saves_isla_x/isla_front.ppm ${CMAKE_BINARY_DIR}/saves_isla_x/isla_front_none.ppm")
add_test(NAME horizonte_linepal COMMAND sh -c "rm -rf ${CMAKE_BINARY_DIR}/saves_horizonte_x && $<TARGET_FILE:pinyol_headless> --game ${CMAKE_CURRENT_SOURCE_DIR}/examples/horizonte \
  --saves ${CMAKE_BINARY_DIR}/saves_horizonte_x --fresh --script ${CMAKE_CURRENT_SOURCE_DIR}/tests/horizonte.script >/dev/null && \
  cmp ${CMAKE_BINARY_DIR}/saves_horizonte_x/hz_on.ppm ${CMAKE_BINARY_DIR}/saves_horizonte_x/hz_on2.ppm && \
  cmp ${CMAKE_BINARY_DIR}/saves_horizonte_x/hz_off0.ppm ${CMAKE_BINARY_DIR}/saves_horizonte_x/hz_off.ppm && \
  ! cmp -s ${CMAKE_BINARY_DIR}/saves_horizonte_x/hz_on.ppm ${CMAKE_BINARY_DIR}/saves_horizonte_x/hz_off.ppm")
add_test(NAME script_fails_on_game_error COMMAND sh -c "$<TARGET_FILE:pinyol_headless> --game ${CMAKE_CURRENT_SOURCE_DIR}/tests/games/sandbox \
  --saves ${CMAKE_BINARY_DIR}/saves_game_error_x --fresh --script ${CMAKE_CURRENT_SOURCE_DIR}/tests/fail/game_error.script 2>&1 | \
  grep -q 'game_error.script:6: tick 3 -> the game stopped on an error: _update: .*boom'") # (tests/fail: scripts that must fail)
add_test(NAME line_ramp COMMAND sh -c "rm -rf ${CMAKE_BINARY_DIR}/saves_ramp_x && $<TARGET_FILE:pinyol_headless> --game ${CMAKE_CURRENT_SOURCE_DIR}/tests/games/ramp \
  --saves ${CMAKE_BINARY_DIR}/saves_ramp_x --fresh --script ${CMAKE_CURRENT_SOURCE_DIR}/tests/ramp.script >/dev/null && \
  cmp ${CMAKE_BINARY_DIR}/saves_ramp_x/ramp_r.ppm ${CMAKE_BINARY_DIR}/saves_ramp_x/ramp_p.ppm")
add_test(NAME linefx_crc COMMAND sh -c "$<TARGET_FILE:pinyol_headless> --game ${CMAKE_CURRENT_SOURCE_DIR}/tests/games/linefx \
  --saves ${CMAKE_BINARY_DIR}/saves_linefx_crc --fresh --script ${CMAKE_CURRENT_SOURCE_DIR}/tests/linefx.script \
  --crc ${CMAKE_BINARY_DIR}/linefx.crc >/dev/null && test $(sort -u ${CMAKE_BINARY_DIR}/linefx.crc | wc -l) -eq 2")
if(NODE)
  foreach(s ${SCRIPTS})
    get_filename_component(n ${s} NAME_WE)
    if(n MATCHES "^editor_")
      set_tests_properties(script_${n} PROPERTIES FIXTURES_REQUIRED editor_game)
    endif()
  endforeach()
endif()
