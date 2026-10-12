# The portable engine and cJSON, compiled as they are for the desktop (no SDL/ESP headers in src/).
set(ROOT ${CMAKE_CURRENT_LIST_DIR}/../../..)
file(GLOB CORE_SRC ${ROOT}/src/*.c)
file(GLOB LUA_SRC ${ROOT}/third_party/lua/*.c)
idf_component_register(SRCS ${CORE_SRC} ${ROOT}/third_party/cjson/cJSON.c ${LUA_SRC}
                       INCLUDE_DIRS ${ROOT}/src ${ROOT}/third_party/cjson ${ROOT}/third_party/lua
                       PRIV_INCLUDE_DIRS ${ROOT}/third_party/pocketmod
                       LDFRAGMENTS linker.lf)
target_compile_definitions(${COMPONENT_LIB} PUBLIC LUA_32BITS=1) # as on the desktop: games behave the same
# gcc 14 flags bounded snprintf truncation, which src/ uses on purpose (clang on the desktop does not)
target_compile_options(${COMPONENT_LIB} PRIVATE -Wall -Wextra -Werror -Wno-format-truncation)
set_source_files_properties(${ROOT}/third_party/cjson/cJSON.c ${LUA_SRC} PROPERTIES COMPILE_OPTIONS "-Wno-error")
