#!/bin/sh
# Record a script run as a video with its sound (needs ffmpeg and a built bp_headless):
#   tools/record.sh tests/scripts/e2e_full.script e2e.mp4 [SAVES_DIR]
# The script's "shot" captures land in SAVES_DIR (default: a temporary folder that is removed).
set -e
tmp=$(mktemp -d)
saves=${3:-$tmp}
./build/bp_headless --game sd/games/bajopueblo --saves "$saves" --fresh --script "$1" \
    --video "$tmp/video.mp4" --audio "$tmp/audio.pcm"
ffmpeg -loglevel error -y -i "$tmp/video.mp4" -f s16le -ar 22050 -ac 1 -i "$tmp/audio.pcm" \
    -c:v copy -c:a aac -b:a 160k -shortest "$2"
rm -rf "${tmp:?}"
echo "$2"
