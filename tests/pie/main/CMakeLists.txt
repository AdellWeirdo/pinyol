set(ROOT ${CMAKE_CURRENT_LIST_DIR}/../../..)
idf_component_register(SRCS "pie_test.c" ${ROOT}/src/gfx_span.c
                       INCLUDE_DIRS ${ROOT}/src ${ROOT}/third_party/cjson)
set_source_files_properties(${ROOT}/src/gfx_span.c PROPERTIES COMPILE_DEFINITIONS "PINYOL_PIE=1")
target_compile_options(${COMPONENT_LIB} PRIVATE -Wall -Wextra -Werror)
