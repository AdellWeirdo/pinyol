-- Microjuegos: una colección de juegos de cinco segundos, a la manera de WarioWare. Un juego se explica en una palabra, dura unos
-- segundos, y el siguiente empieza al momento; cada cuatro, todo va más rápido; el último es el jefe. Cada microjuego deja a propósito
-- algo en la imagen o en el sonido (un fundido, una ventana, un mosaico, una nota, el LED): el marco los limpia al cambiar de escena.
--   Flechas y A, según el juego: la palabra lo dice. START y A en el título.
local scene = require("scene")
local run = require("run")

function _init()
  sound("WIN", {wave = "square", freq = 523, slide = 523, decay = 0.35, volume = 0.3})
  sound("LOSE", {wave = "saw", freq = 300, slide = -220, decay = 0.4, volume = 0.3})
  sound("TICK", {wave = "square", freq = 880, decay = 0.04, volume = 0.15})
  scene.go(run.title, nil, {clean = true})
end

function _update() scene.update() end
function _draw() scene.draw() end
