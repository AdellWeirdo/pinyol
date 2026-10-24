#!/bin/sh
# Draw CROMOTA's art by code, then convert it for pinyol.   sh examples/cromota/gen/build.sh   (from the repo root)
# Every picture of the sprite kind is packed (a raw sprite sheet is 5x slower on the console, measured); FONDO covers the
# whole screen and stays raw. No text is baked into any of them: the words are drawn with text() (strings.csv).
set -e
cd "$(dirname "$0")/../../.."
G=examples/cromota
A=$G/assets
mkdir -p $A $G/art $G/fonts
uv run --quiet --with pillow --with numpy python3 $G/gen/art.py
conv() { uv run --quiet tools/png2asset.py "$@"; }
conv $G/art/fondo.png $A FONDO --type background
conv $G/art/gotas.png $A GOTAS --frames 13 --packed
conv $G/art/gotas_s.png $A GOTAS_S --frames 13 --packed
conv $G/art/brocha.png $A BROCHA --frames 11 --packed
conv $G/art/logo.png $A LOGO --type ui --packed   # the title logo: art/logo_b.png from the image model, 312 px wide (not drawn by art.py)
rm -f $A/OBRA_*
for o in noche ola nenufares; do
  conv $G/art/obra_${o}_gris.png $A OBRA_${o}_GRIS --packed
  for i in 1 2 3 4 5 6; do conv $G/art/obra_${o}_$i.png $A OBRA_${o}_$i --packed; done
done
[ -f $G/fonts/snes_title.fnt ] || uv run --quiet tools/font2fnt.py --pack snes $G
echo built
