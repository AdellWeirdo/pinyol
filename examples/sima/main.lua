-- Sima: un roguelike por turnos, a la manera de los Mystery Dungeon de la Game Boy Advance. Cada piso se hace con la semilla de la
-- bajada: una nueva cada vez (los ticks hasta pulsar A) o la misma para todos ese día (clock()). El piso se escribe en BG1 celda a celda
-- con mset y la niebla en BG0, por encima de los sprites; los monstruos persiguen al héroe por un único campo de distancias (grid).
--   La cruceta anda y golpea, A espera un turno, B bebe una poción, START abandona.
local scene = require("scene")

function _init()
  sound("STEP", {wave = "noise", freq = 1800, decay = 0.03, volume = 0.07})
  sound("HIT", {wave = "noise", freq = 900, slide = -400, decay = 0.12, volume = 0.25})
  sound("HURT", {wave = "saw", freq = 220, slide = -140, decay = 0.18, volume = 0.28})
  sound("DRINK", {wave = "triangle", freq = 400, slide = 300, decay = 0.3, volume = 0.25})
  sound("DOWN", {wave = "square", freq = 330, slide = -220, decay = 0.5, volume = 0.22})
  sound("DEATH", {wave = "saw", freq = 260, slide = -220, decay = 0.8, volume = 0.3})
  sound("WIN", {wave = "square", freq = 440, slide = 880, decay = 0.9, volume = 0.3})
  scene.go(require("title"), nil, {clean = true})
end

function _update() scene.update() end
function _draw() scene.draw() end
