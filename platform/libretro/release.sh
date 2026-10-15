#!/bin/bash
# The libretro core for one kind of Linux machine, as the release "libretro" carries it (.github/workflows/libretro.yml).
# Built in Debian 10, RetroPie's image, so it runs there and on anything newer:
#   docker run --rm --platform linux/arm/v7 -v "$PWD":/src -w /src debian:buster bash platform/libretro/release.sh armhf
# (armhf: 32-bit ARMv7 and up; arm64; x86_64) -> dist/pinyol_libretro-linux-<arch>.zip: the core, its .info, LICENSE
# and THIRD_PARTY_NOTICES.md.
set -euo pipefail
arch="$1"
# Debian 10 has left the mirrors (and archive.debian.org lacks armhf): its last packages, from the snapshot
cat > /etc/apt/sources.list <<'EOF'
deb [check-valid-until=no] http://snapshot.debian.org/archive/debian/20240612T000000Z buster main
deb [check-valid-until=no] http://snapshot.debian.org/archive/debian-security/20240612T000000Z buster/updates main
deb [check-valid-until=no] http://snapshot.debian.org/archive/debian/20240612T000000Z buster-updates main
EOF
apt-get update -qq
apt-get install -y -qq --no-install-recommends cmake gcc make libc6-dev git zip >/dev/null
git -C / config --global --add safe.directory "$PWD" # (the core's version: the commit's hash)
out=$(mktemp -d)
cmake -S . -B "$out/build" -DCMAKE_BUILD_TYPE=Release >/dev/null
cmake --build "$out/build" --target pinyol_libretro -- -j"$(nproc)"
mkdir -p "$out/zip" dist
cp "$out/build/pinyol_libretro.so" platform/libretro/pinyol_libretro.info LICENSE THIRD_PARTY_NOTICES.md "$out/zip/"
strip "$out/zip/pinyol_libretro.so"
rm -f "dist/pinyol_libretro-linux-$arch.zip"
(cd "$out/zip" && zip -q -9 "$OLDPWD/dist/pinyol_libretro-linux-$arch.zip" ./*)
echo "dist/pinyol_libretro-linux-$arch.zip"
