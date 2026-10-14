#!/bin/sh
# The README's pictures of each look: a moment of play in each look's example, taken by the headless player.
#   sh docs/looks/shots.sh      (after cmake --build build; needs uv for the PNGs)
set -e
cd "$(dirname "$0")/../.."
tmp=$(mktemp -d)
shot() { # shot NAME GAME, the script's lines on stdin; it ends with "shot NAME"
  cat > "$tmp/$1.script"
  ./build/pinyol_headless --game "examples/$2" --saves "$tmp/$1" --fresh --script "$tmp/$1.script" >/dev/null
  uv run --quiet --with pillow python3 -c "from PIL import Image; Image.open('$tmp/$1/$1.ppm').save('docs/looks/$1.png', optimize=True)"
}
printf 'tick 20\npress A\nhold RIGHT 80\npress A\ntick 10\nshot gameboy\n' | shot gameboy bolsillo
printf 'tick 20\npress A\ntick 2\npress A\nhold RIGHT 24\ntick 30\nshot spectrum\n' | shot spectrum cinta
printf 'tick 10\npress A\ntick 20\nhold RIGHT 100\npress A\ntick 8\nshot gba\n' | shot gba plataformas
printf 'tick 10\npress A\nhold RIGHT 75\nshot 16bits\n' | shot 16bits veloz
printf 'tick 30\npress A\ntick 100\nhold RIGHT 70\nhold A 1\ntick 7\nshot neogeo\n' | shot neogeo duelo
printf 'tick 30\npress A\ntick 100\nhold RIGHT 50\npress B\ntick 8\nshot cps2\n' | shot cps2 torneo
rm -rf "$tmp"
