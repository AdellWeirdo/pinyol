# The portable engine and cJSON, compiled as they are for the desktop (no SDL/ESP headers in src/).
set(ROOT ${CMAKE_CURRENT_LIST_DIR}/../../..)
file(GLOB CORE_SRC ${ROOT}/src/*.c)
file(GLOB LUA_SRC ${ROOT}/third_party/lua/*.c)
include(${ROOT}/cmake/embed_lib.cmake)
pinyol_embed_lib(${CMAKE_CURRENT_BINARY_DIR}/pinyol_lib.c ${ROOT}/lib)
pinyol_splash_pics(SPLASH_PICS ${ROOT})
pinyol_embed_pics(${CMAKE_CURRENT_BINARY_DIR}/pinyol_splash.c ${SPLASH_PICS})
idf_component_register(SRCS ${CORE_SRC} ${ROOT}/third_party/cjson/cJSON.c ${ROOT}/third_party/qrcodegen/qrcodegen.c ${ROOT}/third_party/ibxm/ibxm.c ${LUA_SRC} ${CMAKE_CURRENT_BINARY_DIR}/pinyol_lib.c
                            ${CMAKE_CURRENT_BINARY_DIR}/pinyol_splash.c
                       INCLUDE_DIRS ${ROOT}/src ${ROOT}/third_party/cjson ${ROOT}/third_party/lua
                       PRIV_INCLUDE_DIRS ${ROOT}/third_party/pocketmod ${ROOT}/third_party/ibxm ${ROOT}/third_party/qrcodegen
                       LDFRAGMENTS linker.lf)
target_compile_definitions(${COMPONENT_LIB} PUBLIC LUA_32BITS=1) # as on the desktop: games behave the same
# gcc 14 flags bounded snprintf truncation, which src/ uses on purpose (clang on the desktop does not)
target_compile_options(${COMPONENT_LIB} PRIVATE -Wall -Wextra -Werror -Wno-format-truncation)
set_source_files_properties(${ROOT}/third_party/cjson/cJSON.c ${LUA_SRC} PROPERTIES COMPILE_OPTIONS "-Wno-error")
# physics as the Lua code did it and as the desktop does it: no fused multiply-adds (linked consoles agree)
set_source_files_properties(${ROOT}/src/lua_physics.c PROPERTIES COMPILE_OPTIONS "-ffp-contract=off")
# the S3's vector unit (PIE) for runs of mixed pixels; checked against the C code in QEMU by tests/pie/run.sh
set_source_files_properties(${ROOT}/src/gfx_span.c PROPERTIES COMPILE_DEFINITIONS "PINYOL_PIE=1")
set_source_files_properties(${ROOT}/third_party/ibxm/ibxm.c PROPERTIES COMPILE_DEFINITIONS "PINYOL_SLOW_ALLOC" COMPILE_OPTIONS "-Wno-sign-compare;-Wno-unused-parameter;-Wno-implicit-fallthrough")
# the same string hashes every run, as on the desktop (pairs() in the same order: tests repeat, linked consoles agree)
set_source_files_properties(${LUA_SRC} PROPERTIES COMPILE_DEFINITIONS "luai_makeseed=0x6e703264u+0*sizeof;LUA_PINYOL_BUDGET")
