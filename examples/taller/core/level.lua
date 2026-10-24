-- level: the three stages as data. Each is 2880 pixels long (three painted chunks of 960 with a pillar in front of each seam); the camera stops where an event says `lock` and only
-- goes on when its wave is beaten. A wave entry is {kind, side ("l" or "r" of the screen), ticks until it comes in}; props are {kind, x}.
local L = {}

local function w(kind, side, delay) return {kind, side, delay or 0} end

L.END_CAM = 2400

L.STAGES = {
  {id = "calle", near = {"near_calle_a", "near_calle_b", "near_calle_c"}, music = "calle", pillar = "calle",
   name = {es = "CALLE DE LOS RELOJEROS", ca = "CARRER DELS RELLOTGERS", en = "CLOCKMAKERS' STREET"},
   events = {
     {at = 0, props = {{"barrel", 380}, {"crate", 520}, {"lamp", 760}}},
     {at = 300, lock = true, wave = {w("rodete", "r"), w("rodete", "r", 50)}},
     {at = 760, props = {{"clocks", 1150}, {"mailbox", 1300}, {"barrel", 1420}}},
     {at = 1000, lock = true, wave = {w("rodete", "r"), w("rodete", "l", 30), w("rodete", "r", 90)}},
     {at = 1500, lock = true, wave = {w("rodete", "r"), w("resorte", "l", 20), w("rodete", "r", 80), w("resorte", "r", 120)}, props = {{"crate", 1880}, {"pipes", 2020}}},
     {at = 2100, lock = true, wave = {w("caldero", "r"), w("rodete", "l", 150)}},
   }},
  {id = "fabrica", near = {"near_fabrica_a", "near_fabrica_b", "near_fabrica_c"}, music = "fabrica", pillar = "fabrica",
   name = {es = "LA FÁBRICA", ca = "LA FÀBRICA", en = "THE FACTORY"},
   events = {
     {at = 0, props = {{"pipes", 380}, {"crate", 560}, {"barrel", 740}}},
     {at = 280, lock = true, wave = {w("resorte", "r"), w("resorte", "l", 40), w("rodete", "r", 100)}},
     {at = 800, props = {{"clocks", 1180}, {"barrel", 1320}}},
     {at = 960, lock = true, wave = {w("rodete", "r"), w("rodete", "l"), w("resorte", "r", 60), w("rodete", "r", 110)}},
     {at = 1500, lock = true, wave = {w("caldero", "l"), w("resorte", "r", 60), w("resorte", "r", 100)}, props = {{"crate", 1900}, {"mailbox", 2040}}},
     {at = 2100, lock = true, wave = {w("rodete", "r"), w("rodete", "l", 20), w("resorte", "r", 70), w("caldero", "r", 120)}},
   }},
  {id = "torre", near = {"near_torre_a", "near_torre_b", "near_torre_c"}, music = "torre", pillar = "torre",
   name = {es = "LA TORRE DEL RELOJ", ca = "LA TORRE DEL RELLOTGE", en = "THE CLOCK TOWER"},
   events = {
     {at = 0, props = {{"clocks", 400}, {"lamp", 620}, {"barrel", 800}}},
     {at = 280, lock = true, wave = {w("rodete", "r"), w("rodete", "l"), w("resorte", "r", 60), w("resorte", "l", 90)}},
     {at = 900, props = {{"crate", 1200}, {"pipes", 1340}}},
     {at = 1000, lock = true, wave = {w("caldero", "r"), w("rodete", "l", 40), w("rodete", "r", 100), w("resorte", "l", 140)}},
     {at = 1650, lock = true, wave = {w("resorte", "r"), w("resorte", "l", 30), w("rodete", "r", 70), w("rodete", "l", 100), w("caldero", "l", 160)}, props = {{"barrel", 2050}}},
   }},
}

return L
