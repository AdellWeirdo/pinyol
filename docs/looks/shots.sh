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
printf 'tick 5\nlua require("core.title").leave() require("core.game").reset() G.state = "play" require("core.hud").init() require("core.pal").fade("dark", 0)\nlua require("core.play").enter("overworld", 24, 16, "up")\ntick 40\nshot gameboy\n' | shot gameboy cerezo
printf 'tick 20\npress A\ntick 2\npress A\nhold RIGHT 24\ntick 30\nshot spectrum\n' | shot spectrum cinta
printf 'tick 10\npress A\ntick 20\nhold RIGHT 100\npress A\ntick 8\nshot gba\n' | shot gba plataformas
printf 'tick 10\npress A\nhold RIGHT 75\nshot 16bits\n' | shot 16bits veloz
printf 'tick 30\npress A\ntick 100\nhold RIGHT 70\nhold A 1\ntick 7\nshot neogeo\n' | shot neogeo duelo
printf 'tick 30\npress A\ntick 100\nhold RIGHT 50\npress B\ntick 8\nshot cps2\n' | shot cps2 torneo
printf 'tick 20\npress A\ntick 2\npress A\nhold RIGHT 6\ntick 40\nshot pico8\n' | shot pico8 ladrillos
printf 'tick 20\npress A\nhold RIGHT 2\ntick 150\nshot lcd\n' | shot lcd huevos
printf 'tick 20\npress A\ntick 5\nlua G.begin_level(7)\ntick 200\nhold LEFT 20\npress A\ntick 8\nshot vector\n' | shot vector pozo
printf 'tick 20\npress A\nhold A 150\nshot vertical\n' | shot vertical tormenta
printf 'tick 10\npress A\nlua P.x, P.y, P.a = 3.2, 13.5, 0 ghosts[1].x, ghosts[1].y = 10.5, 13.5\ntick 2\nshot firstperson\n' | shot firstperson laberinto
printf 'tick 500\nshot loading\n' | shot loading cinta
printf 'tick 10\npress A\nhold RIGHT 40\nlua ghost.x = L.x + 150\nhold B 1\ntick 3\nshot 32bits\n' | shot 32bits gotico
printf 'tick 10\npress A\nlua L.x, L.hurt, cam = 1790, 0, 1680\ntick 78\nshot 32bits_boss\n' | shot 32bits_boss gotico
rm -rf "$tmp"
