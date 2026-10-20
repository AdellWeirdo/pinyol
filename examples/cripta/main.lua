-- Cripta: un castillo en ocho salas, a la manera de los metroidvania de la Game Boy Advance. Las alas dan un segundo salto, la ráfaga rompe
-- las paredes agrietadas, y cada poder abre el camino al siguiente. Las salas son mapas de Tiled (art/*.tmx), uno por sala, importados con
-- tools/tiled2asset.py; dónde está cada una en el castillo son dos propiedades del mapa. Las estatuas guardan la partida.
--   A saltar (en el aire, con las alas, otra vez), B espada, C ráfaga, START el mapa.
local scene = require("scene")

function _init()
  sound("JUMP", {wave = "square", freq = 330, slide = 500, decay = 0.12, volume = 0.18})
  sound("JUMP2", {wave = "square", freq = 500, slide = 700, decay = 0.12, volume = 0.18})
  sound("DASH", {wave = "noise", freq = 900, slide = -500, decay = 0.18, volume = 0.22})
  sound("SWING", {wave = "noise", freq = 1400, decay = 0.06, volume = 0.15})
  sound("HIT", {wave = "square", freq = 220, slide = -120, decay = 0.1, volume = 0.25})
  sound("HURT", {wave = "saw", freq = 200, slide = -150, decay = 0.2, volume = 0.3})
  sound("BREAK", {wave = "noise", freq = 300, decay = 0.35, volume = 0.3})
  sound("ITEM", {wave = "triangle", freq = 523, slide = 523, decay = 0.5, volume = 0.3})
  sound("SAVE", {wave = "triangle", freq = 392, slide = 196, decay = 0.4, volume = 0.25})
  sound("DEATH", {wave = "saw", freq = 300, slide = -250, decay = 0.6, volume = 0.3})
  sound("WIN", {wave = "square", freq = 440, slide = 880, decay = 0.8, volume = 0.3})
  scene.go(require("title"), nil, {clean = true})
end

function _update() scene.update() end
function _draw() scene.draw() end
