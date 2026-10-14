cmake_minimum_required(VERSION 3.21)
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
# A game's repo can build the engine as a subproject: set GAME_DIR, then add_subdirectory(<pinyol> pinyol).
set(GAME_DIR ${CMAKE_CURRENT_SOURCE_DIR}/examples/hola CACHE PATH "Game folder the simulator opens and the web player packs")

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
target_compile_options(lua PRIVATE ${SAN})

# Portable engine core: no SDL/ESP headers allowed in src/.
file(GLOB CORE_SRC CONFIGURE_DEPENDS src/*.c)
include(cmake/embed_lib.cmake)
pinyol_embed_lib(${CMAKE_BINARY_DIR}/pinyol_lib.c ${CMAKE_CURRENT_SOURCE_DIR}/lib)
add_library(pinyol_core STATIC ${CORE_SRC} ${CMAKE_BINARY_DIR}/pinyol_lib.c)
# physics as the Lua code did it, operation for operation: no fused multiply-adds, the same on every platform
set_source_files_properties(src/lua_physics.c PROPERTIES COMPILE_OPTIONS -ffp-contract=off)
target_include_directories(pinyol_core PUBLIC ${CMAKE_CURRENT_SOURCE_DIR}/src)
target_include_directories(pinyol_core PRIVATE ${CMAKE_CURRENT_SOURCE_DIR}/third_party/pocketmod)
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
                      -sFORCE_FILESYSTEM=1 -sEXPORTED_RUNTIME_METHODS=FS,callMain -lidbfs.js
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
  add_executable(pinyol_sim platform/sdl/main.c platform/link_udp.c)
  target_compile_options(pinyol_sim PRIVATE -Wall -Wextra ${SAN})
  target_compile_definitions(pinyol_sim PRIVATE PINYOL_GAME="${GAME_DIR}")
  target_link_libraries(pinyol_sim pinyol_core SDL2::SDL2)
  old_name(pinyol_sim bp_sim)
else()
  message(STATUS "SDL2 not found: pinyol_sim skipped (brew install sdl2)")
endif()

if(NOT PROJECT_IS_TOP_LEVEL) # a game's repo registers its own tests
  return()
endif()
enable_testing()
add_executable(ppu_test tests/ppu_test.c platform/null/hal_null.c platform/link_udp.c)
target_compile_options(ppu_test PRIVATE -Wall -Wextra -Werror ${SAN})
target_link_libraries(ppu_test pinyol_core)
add_test(NAME ppu COMMAND ppu_test)
add_executable(psg_test tests/psg_test.c platform/null/hal_null.c platform/link_udp.c)
target_compile_options(psg_test PRIVATE -Wall -Wextra -Werror ${SAN})
target_link_libraries(psg_test pinyol_core)
add_test(NAME psg COMMAND psg_test)
add_executable(mod_test tests/mod_test.c platform/null/hal_null.c platform/link_udp.c)
target_compile_options(mod_test PRIVATE -Wall -Wextra -Werror ${SAN})
target_link_libraries(mod_test pinyol_core)
add_test(NAME mod COMMAND mod_test)
add_executable(synth_test tests/synth_test.c platform/null/hal_null.c platform/link_udp.c)
target_compile_options(synth_test PRIVATE -Wall -Wextra -Werror ${SAN})
target_link_libraries(synth_test pinyol_core)
add_test(NAME synth COMMAND synth_test)
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
set(NO_PIL 1)
if(Python3_FOUND)
  execute_process(COMMAND ${Python3_EXECUTABLE} -c "import PIL" RESULT_VARIABLE NO_PIL OUTPUT_QUIET ERROR_QUIET)
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
endif()
find_program(NODE node) # the web editor's templates, built as the browser builds them, for script_editor_*
if(NODE)
  add_test(NAME make_editor_game COMMAND ${NODE} ${CMAKE_CURRENT_SOURCE_DIR}/editor/test/build_game.mjs
           ${CMAKE_BINARY_DIR}/editor)
  set_tests_properties(make_editor_game PROPERTIES FIXTURES_SETUP editor_game)
  add_test(NAME editor_cable COMMAND ${NODE} ${CMAKE_CURRENT_SOURCE_DIR}/editor/test/cable_test.mjs)
  add_test(NAME editor_packed COMMAND ${NODE} ${CMAKE_CURRENT_SOURCE_DIR}/editor/test/packed_test.mjs)
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
  elseif(NOT IS_DIRECTORY ${game})
    set(game ${CMAKE_CURRENT_SOURCE_DIR}/tests/games/${n}) # games that only exist to be tested
  endif()
  add_test(NAME script_${n} COMMAND pinyol_headless --game ${game}
           --saves ${CMAKE_BINARY_DIR}/saves_${n} --fresh --script ${s} --check-strips)
endforeach()
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
if(NODE)
  foreach(s ${SCRIPTS})
    get_filename_component(n ${s} NAME_WE)
    if(n MATCHES "^editor_")
      set_tests_properties(script_${n} PROPERTIES FIXTURES_REQUIRED editor_game)
    endif()
  endforeach()
endif()
