cmake_minimum_required(VERSION 3.22.1)
project(siir_ecqt LANGUAGES C)

set(ECQT_DIR ${CMAKE_CURRENT_SOURCE_DIR}/../../../../../native/ecqt)
add_library(shirr_ecqt SHARED ${ECQT_DIR}/shirr_ecqt.c ${ECQT_DIR}/pffft/pffft.c)
target_compile_options(shirr_ecqt PRIVATE -O3)
target_link_libraries(shirr_ecqt m)
