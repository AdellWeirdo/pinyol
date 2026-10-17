#!/bin/bash
# Generate each job of a jobs file that has no picture yet, four at a time: run_jobs.sh jobs1.tsv
D=$(cd "$(dirname "$0")" && pwd)
B=~/.claude/skills/gpt-image-bridge/bin/gpt-image-2
A=/Users/pauavila/Desktop/DEV/pinyol/AUDREYGOTCHI-main/audreygotchi/assets/backgrounds
mkdir -p "$D/gen"
PAL="Strictly four colours only: lightest #E0F8D0, light #88C070, dark #346856, darkest #081820. Real low-resolution Game Boy pixel art: every pixel a crisp square block of the same size, 1-pixel darkest outline, flat shading, no anti-aliasing, no gradients, no dithering noise, no text, no frame borders."
one() {
  IFS=$'\t' read -r id kind what <<< "$1"
  out="$D/gen/$id.png"
  [ -s "$out" ] && return 0
  case $kind in
    adult) prompt="Game Boy DMG pixel-art sprite sheet of THIS exact cat from the reference sprite (Audrey, a grumpy ginger Persian: very fluffy round body, flat face, half-closed judging eyes, cream face and chest, huge fluffy tail), drawn in exactly the same pixel-art style, at the same size and with the same chunky pixel size as the reference. $what. Side by side in one horizontal row with wide empty gaps between them, all at the same scale on one shared baseline. $PAL Transparent background."
           ref=(--ref "$D/refs/gb_adult.png") ;;
    scale) prompt="Game Boy DMG pixel-art sprite sheet. $what. Side by side in one horizontal row with wide empty gaps, same scale, one baseline, same pixel-art style and chunky pixel size as the reference. $PAL Transparent background."
           ref=(--ref "$D/refs/gb_scale.png") ;;
    room)  name=${id#room_}
           prompt="Game Boy DMG pixel-art background of $what, redrawn from the first reference picture (keep its layout and furniture) in exactly the style of the second reference (a Game Boy living room): a 240 by 160 pixel room in a 3:2 frame built from 8x8 tiles, clean straight lines, simple repeating patterns, a floor along the bottom third where a character stands, mostly the two lightest greens, the darkest only for outlines. $PAL Full frame, no border."
           ref=(--ref "$D/refs/src_$name.png" --ref "$D/refs/gb_living.png") ;;
  esac
  if $B "$prompt" "$out" "${ref[@]}" ${kind:+$( [ "$kind" = room ] && echo --size 1536x1024 )} > "$D/gen/$id.log" 2>&1; then echo "ok $id"; else echo "FAIL $id"; fi
}
export -f one; export D B PAL A
for r in kitchen rasca studio wc; do
  [ -s "$D/refs/src_$r.png" ] || uv run -q --with pillow python -I -c "
from PIL import Image
bg = Image.open('$A/bg_$r.png').convert('RGB').resize((768,768), Image.LANCZOS)
bg.crop((0, 256, 768, 768)).save('$D/refs/src_$r.png')"
done
JOBS=$(cd "$(dirname "$1")" && pwd)/$(basename "$1"); export JOBS
n=$(grep -c . "$JOBS")
seq 1 "$n" | xargs -P 4 -I{} bash -c 'one "$(grep -v "^\s*$" "$JOBS" | sed -n {}p)"' 
