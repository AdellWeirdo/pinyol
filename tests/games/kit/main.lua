-- A game as the editor makes it: data, then the blocks' events (tests/kit.script plays it).
kit = require("kit") -- global: tests and the editor reach it
puntos = 0
kit.setup(require("data"))

kit.on("start", function() puntos = 0 kit.label("p", "Monedas: 0") end)
kit.on("touch", "heroe", "moneda", function(este, otro)
  kit.destroy(otro)
  puntos = puntos + 1
  kit.sound("moneda")
  kit.burst(otro.x, otro.y, 0xFFE070)
  kit.label("p", "Monedas: " .. puntos)
  if kit.count("moneda") == 0 then kit.win("¡Todas!") end
end)
kit.on("touch", "heroe", "malo", function() kit.shake(6) kit.lose("¡Ay!") end)
kit.on("tile", "heroe", "pincho", function() kit.lose("Pinchos") end)

local function picture(id, w, h, frames, colour) -- the editor writes these as files; here, drawn
  canvas(id, w * frames, h)
  target(id)
  for f = 0, frames - 1 do rect(f * w + 1, 1, w - 2, h - 2, colour + f * 0x101010) end
  target()
end

function _init()
  picture("SPR_heroe", 12, 16, 1, 0xE8443A)
  picture("SPR_suelo", 16, 16, 1, 0x6B4A2E)
  picture("SPR_moneda", 8, 8, 1, 0xF2B233)
  picture("SPR_malo", 14, 12, 1, 0x3A3466)
  picture("SPR_pincho", 16, 16, 1, 0xC0C0C0)
  kit.init()
end
function _update() kit.update() end
function _draw() kit.draw() end
