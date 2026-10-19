-- kit.lua turning a kind round its pivot (tests/kitflip_test.py): each picture blue, its column 1 red (the pivot's).
kit = require("kit")
kit.setup(require("data"))
function _init()
  for _, id in ipairs({"SPR_giro", "SPR_caja"}) do
    canvas(id, 8, 8) target(id) rect(0, 0, 8, 8, 0x0000FF) rect(1, 0, 1, 8, 0xFF0000) target()
  end
  kit.init()
end
function _update()
  kit.update()
  for _, o in ipairs({kit.first("giro"), kit.first("caja")}) do if o then o.flip = flipped end end
end
function _draw() kit.draw() end
