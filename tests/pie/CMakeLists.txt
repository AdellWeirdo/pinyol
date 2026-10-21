# The ESP32-S3's vector code (src/gfx_span.c with PINYOL_PIE) against its C twin, run in Espressif's QEMU: tests/pie/run.sh
cmake_minimum_required(VERSION 3.16)
include($ENV{IDF_PATH}/tools/cmake/project.cmake)
project(pie_test)
