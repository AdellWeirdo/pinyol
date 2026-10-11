# The portable engine and cJSON, compiled as they are for the desktop (no SDL/ESP headers in src/).
set(ROOT ${CMAKE_CURRENT_LIST_DIR}/../../..)
file(GLOB CORE_SRC ${ROOT}/src/*.c)
idf_component_register(SRCS ${CORE_SRC} ${ROOT}/third_party/cjson/cJSON.c
                       INCLUDE_DIRS ${ROOT}/src ${ROOT}/third_party/cjson
                       LDFRAGMENTS linker.lf)
# gcc 14 flags bounded snprintf truncation, which src/ uses on purpose (clang on the desktop does not)
target_compile_options(${COMPONENT_LIB} PRIVATE -Wall -Wextra -Werror -Wno-format-truncation)
set_source_files_properties(${ROOT}/third_party/cjson/cJSON.c PROPERTIES COMPILE_OPTIONS "-Wno-error")
