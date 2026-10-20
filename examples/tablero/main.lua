-- Tablero: tácticas por turnos sobre una cuadrícula, a la manera de Advance Wars. Dos ejércitos de cuatro unidades en un campo de
-- 15 x 10 casillas con bosque, montaña, un río y dos puentes. Es una prueba de lo que la táctica pide al motor: `grid` (alcance, caminos,
-- distancias y mapa de peligro), una capa del PPU cuyas casillas se cambian con mset y se mezcla con el campo, y una IA que
-- decide con lo mismo que usa el jugador.
--   Elegir: flechas y A. B vuelve atrás. START termina el turno. C enseña dónde puede golpear el rojo.
local scene = require("scene")

function _init()
  sound("PICK", {wave = "square", freq = 700, decay = 0.05, volume = 0.2})
  sound("STEP", {wave = "noise", freq = 500, decay = 0.03, volume = 0.1})
  sound("HIT", {wave = "noise", freq = 650, slide = -300, decay = 0.1, volume = 0.3})
  sound("NO", {wave = "square", freq = 150, decay = 0.08, volume = 0.2})
  sound("TURN", {wave = "triangle", freq = 330, slide = 330, decay = 0.2, volume = 0.25})
  sound("WIN", {wave = "square", freq = 440, slide = 880, decay = 0.6, volume = 0.3})
  sound("LOSE", {wave = "saw", freq = 330, slide = -280, decay = 0.7, volume = 0.3})
  scene.go(require("title"))
end

function _update() scene.update() end
function _draw() scene.draw() end
