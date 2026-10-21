#!/bin/sh
# Builds tests/pie and runs it in Espressif's QEMU (ESP-IDF 5.4 exported; QEMU from `idf_tools.py install qemu-xtensa`, or
# QEMU=path/to/qemu-system-xtensa). Exit 0 when the vector code gives the C code's pixels.
set -e
cd "$(dirname "$0")"
idf.py build >/dev/null
(cd build && esptool.py --chip esp32s3 merge_bin --fill-flash-size 4MB -o flash.bin @flash_args >/dev/null)
QEMU=${QEMU:-qemu-system-xtensa}
out=$(timeout 60 "$QEMU" -nographic -machine esp32s3 -drive file=build/flash.bin,if=mtd,format=raw 2>&1 | sed '/PIE_DONE/q' || true)
echo "$out" | grep -E '^(PIE|diff)'
echo "$out" | grep -q '^PIE ok'
