#!/bin/sh
# Record a script run as a video with its sound (needs ffmpeg and a built bp_headless):
#   tools/record.sh GAME_DIR SCRIPT OUT.mp4 [SAVES_DIR]
# The script's "shot" captures land in SAVES_DIR (default: a temporary folder that is removed).
set -e
tmp=$(mktemp -d)
saves=${4:-$tmp}
./build/bp_headless --game "$1" --saves "$saves" --fresh --script "$2" \
    --video "$tmp/video.mp4" --audio "$tmp/audio.pcm"
ffmpeg -loglevel error -y -i "$tmp/video.mp4" -f s16le -ar 22050 -ac 1 -i "$tmp/audio.pcm" \
    -c:v copy -c:a aac -b:a 160k -shortest "$3"
rm -rf "${tmp:?}"
echo "$2"
