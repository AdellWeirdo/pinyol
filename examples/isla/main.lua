-- Isla: una isla en perspectiva isométrica, a la manera de los juegos de la Game Boy Advance que la pintaban con un fondo y sprites.
-- El suelo es un fondo de tiles; las columnas, las cajas, las palmeras, las gemas y el héroe son sprites, y cada frame se les dan los
-- números por profundidad (el más cercano, el 0), así el héroe pasa por detrás de una torre y por delante de otra. Cinco gemas: unas se
-- alcanzan andando y saltando, otras empujando una caja contra un pilar o al agua, para cruzar.
--   La cruceta por la cuadrícula, A saltar, C las cajas otra vez, START el título.
local scene = require("scene")

function _init()
  sound("STEP", {wave = "noise", freq = 2400, decay = 0.03, volume = 0.08})
  sound("JUMP", {wave = "square", freq = 330, slide = 440, decay = 0.14, volume = 0.18})
  sound("PUSH", {wave = "noise", freq = 500, decay = 0.2, volume = 0.18})
  sound("SPLASH", {wave = "noise", freq = 1200, slide = -900, decay = 0.4, volume = 0.25})
  sound("GEM", {wave = "triangle", freq = 660, slide = 660, decay = 0.4, volume = 0.3})
  sound("WIN", {wave = "square", freq = 440, slide = 880, decay = 0.8, volume = 0.3})
  scene.go(require("title"), nil, {clean = true})
end

function _update() scene.update() end
function _draw() scene.draw() end
