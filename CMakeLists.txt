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

# Portable engine core: no SDL/ESP headers allowed in src/.
file(GLOB CORE_SRC CONFIGURE_DEPENDS src/*.c)
add_library(bp_core STATIC ${CORE_SRC})
target_include_directories(bp_core PUBLIC ${CMAKE_CURRENT_SOURCE_DIR}/src)
target_compile_options(bp_core PRIVATE -Wall -Wextra -Werror ${SAN})
target_link_libraries(bp_core PUBLIC cjson m)
target_link_options(bp_core PUBLIC ${SAN})

# Web player: emcmake cmake -B build-web -DCMAKE_BUILD_TYPE=Release && cmake --build build-web
# -> build-web/index.html + .js + .wasm + .data (GAME_DIR packed at /game). Serve the folder over http.
if(EMSCRIPTEN)
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
add_executable(ppu_test tests/ppu_test.c)
target_compile_options(ppu_test PRIVATE -Wall -Wextra -Werror ${SAN})
target_link_libraries(ppu_test bp_core)
add_test(NAME ppu COMMAND ppu_test)
add_test(NAME validate COMMAND bp_headless --game ${GAME_DIR} --validate)
file(GLOB SCRIPTS CONFIGURE_DEPENDS tests/*.script) # written for examples/hola
foreach(s ${SCRIPTS})
  get_filename_component(n ${s} NAME_WE)
  add_test(NAME script_${n}
           COMMAND bp_headless --game ${GAME_DIR} --saves ${CMAKE_BINARY_DIR}/saves_${n} --fresh --script ${s})
endforeach()
