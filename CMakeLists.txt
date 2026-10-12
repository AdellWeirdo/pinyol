cmake_minimum_required(VERSION 3.21)
project(np2d C)

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
# A game's repo can build the engine as a subproject: set GAME_DIR, then add_subdirectory(<np2d> np2d).
set(GAME_DIR ${CMAKE_CURRENT_SOURCE_DIR}/examples/hola CACHE PATH "Game folder the simulator opens and the web player packs")

add_library(cjson STATIC third_party/cjson/cJSON.c)
target_include_directories(cjson PUBLIC ${CMAKE_CURRENT_SOURCE_DIR}/third_party/cjson)
target_compile_options(cjson PRIVATE -Wno-deprecated-declarations ${SAN})

# Lua 5.4 (third_party/lua/README.np2d), with 32-bit integers and floats on every platform so a game behaves the same.
file(GLOB LUA_SRC CONFIGURE_DEPENDS third_party/lua/*.c)
add_library(lua STATIC ${LUA_SRC})
target_include_directories(lua PUBLIC ${CMAKE_CURRENT_SOURCE_DIR}/third_party/lua)
target_compile_definitions(lua PUBLIC LUA_32BITS=1)
target_compile_options(lua PRIVATE ${SAN})

# Portable engine core: no SDL/ESP headers allowed in src/.
file(GLOB CORE_SRC CONFIGURE_DEPENDS src/*.c)
add_library(bp_core STATIC ${CORE_SRC})
target_include_directories(bp_core PUBLIC ${CMAKE_CURRENT_SOURCE_DIR}/src)
target_compile_options(bp_core PRIVATE -Wall -Wextra -Werror ${SAN})
target_link_libraries(bp_core PUBLIC cjson lua m)
target_link_options(bp_core PUBLIC ${SAN})

# Web builds: emcmake cmake -B build-web -DCMAKE_BUILD_TYPE=Release && cmake --build build-web
# -> build-web/index.html + .js + .wasm + .data: GAME_DIR packed in, at /game.
# -> build-web/player.html + .js + .wasm: any game, from a .zip (tools/pack_game.py) given as ?game=URL or dropped on
#    the page. Serve the folder over http.
if(EMSCRIPTEN)
  add_executable(np2d_player platform/sdl/main.c)
  set_target_properties(np2d_player PROPERTIES OUTPUT_NAME player SUFFIX .html)
  target_compile_options(np2d_player PRIVATE -Wall -Wextra -sUSE_SDL=2)
  target_link_libraries(np2d_player bp_core)
  target_link_options(np2d_player PRIVATE -sUSE_SDL=2 -sALLOW_MEMORY_GROWTH=1 -sINITIAL_MEMORY=64MB -sINVOKE_RUN=0
                      -sFORCE_FILESYSTEM=1 -sEXPORTED_RUNTIME_METHODS=FS,callMain -lidbfs.js
                      --shell-file ${CMAKE_CURRENT_SOURCE_DIR}/platform/web/player.html)
  set_property(TARGET np2d_player APPEND PROPERTY LINK_DEPENDS ${CMAKE_CURRENT_SOURCE_DIR}/platform/web/player.html)

  add_executable(np2d_web platform/sdl/main.c)
  set_target_properties(np2d_web PROPERTIES OUTPUT_NAME index SUFFIX .html)
  target_compile_options(np2d_web PRIVATE -Wall -Wextra -sUSE_SDL=2)
  target_link_libraries(np2d_web bp_core)
  target_link_options(np2d_web PRIVATE -sUSE_SDL=2 -sALLOW_MEMORY_GROWTH=1 -sINITIAL_MEMORY=64MB
                      --shell-file ${CMAKE_CURRENT_SOURCE_DIR}/platform/web/shell.html
                      --preload-file ${GAME_DIR}@/game --exclude-file ${GAME_DIR}/saves)
  set_property(TARGET np2d_web APPEND PROPERTY LINK_DEPENDS ${CMAKE_CURRENT_SOURCE_DIR}/platform/web/shell.html)
  return()
endif()

add_executable(bp_headless platform/null/main.c platform/null/hal_null.c)
target_compile_options(bp_headless PRIVATE -Wall -Wextra -Werror ${SAN})
target_compile_definitions(bp_headless PRIVATE NP2D_GAME="${GAME_DIR}") # the game it opens without --game
target_link_libraries(bp_headless bp_core)

find_package(SDL2 CONFIG QUIET)
if(SDL2_FOUND)
  add_executable(bp_sim platform/sdl/main.c)
  target_compile_options(bp_sim PRIVATE -Wall -Wextra ${SAN})
  target_compile_definitions(bp_sim PRIVATE NP2D_GAME="${GAME_DIR}")
  target_link_libraries(bp_sim bp_core SDL2::SDL2)
else()
  message(STATUS "SDL2 not found: bp_sim skipped (brew install sdl2)")
endif()

if(NOT PROJECT_IS_TOP_LEVEL) # a game's repo registers its own tests
  return()
endif()
enable_testing()
add_executable(ppu_test tests/ppu_test.c platform/null/hal_null.c)
target_compile_options(ppu_test PRIVATE -Wall -Wextra -Werror ${SAN})
target_link_libraries(ppu_test bp_core)
add_test(NAME ppu COMMAND ppu_test)
add_executable(psg_test tests/psg_test.c platform/null/hal_null.c)
target_compile_options(psg_test PRIVATE -Wall -Wextra -Werror ${SAN})
target_link_libraries(psg_test bp_core)
add_test(NAME psg COMMAND psg_test)
# Every example opens and validates; tests/<name>.script plays examples/<name> (with its strips checked).
file(GLOB EXAMPLES LIST_DIRECTORIES true CONFIGURE_DEPENDS examples/*)
foreach(dir ${EXAMPLES})
  if(IS_DIRECTORY ${dir})
    get_filename_component(n ${dir} NAME)
    add_test(NAME validate_${n} COMMAND bp_headless --game ${dir} --validate)
  endif()
endforeach()
# tests/template_lua.script plays a game just made by tools/new_game.py --lua (when Python 3 has Pillow).
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
endif()
file(GLOB SCRIPTS CONFIGURE_DEPENDS tests/*.script)
foreach(s ${SCRIPTS})
  get_filename_component(n ${s} NAME_WE)
  set(game ${CMAKE_CURRENT_SOURCE_DIR}/examples/${n})
  if(n STREQUAL "template_lua")
    if(NO_PIL)
      continue()
    endif()
    set(game ${CMAKE_BINARY_DIR}/template_lua)
  elseif(NOT IS_DIRECTORY ${game})
    set(game ${CMAKE_CURRENT_SOURCE_DIR}/tests/games/${n}) # games that only exist to be tested
  endif()
  add_test(NAME script_${n} COMMAND bp_headless --game ${game}
           --saves ${CMAKE_BINARY_DIR}/saves_${n} --fresh --script ${s} --check-strips)
endforeach()
if(NOT NO_PIL)
  set_tests_properties(script_template_lua PROPERTIES FIXTURES_REQUIRED lua_template)
endif()
