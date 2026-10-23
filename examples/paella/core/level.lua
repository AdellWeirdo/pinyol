-- level: the mission, as data. Three zones of three chunks (the harbour at dawn, the main street at noon, the beach at sunset) and then the boss's arena. Things are put
-- when the camera's right edge reaches `at`: waves of gulls, people to free, props. Positions are world pixels; in a wave, "r" is the right of the screen, "l" the left,
-- "air" a flyer coming from the right, a number an absolute x.
local C = require("core.const")
local L = {}

L.ZONES = {
  {id = "puerto", far = "far_puerto", near = {"near_puerto_a", "near_puerto_b", "near_puerto_a"}, music = "puerto", name = {es = "LONJA DEL PUERTO", ca = "LLOTJA DEL PORT", en = "HARBOUR MARKET"}},
  {id = "calle", far = "far_calle", near = {"near_calle_a", "near_calle_b", "near_calle_a"}, music = "calle", name = {es = "CALLE MAYOR", ca = "CARRER MAJOR", en = "MAIN STREET"}},
  {id = "playa", far = "far_playa", near = {"near_playa_a", "near_playa_b", "near_playa_a"}, music = "playa", name = {es = "PLAYA Y CHIRINGUITO", ca = "PLATJA I XIRINGUITO", en = "BEACH AND BAR"}},
}

function L.zone_at(x) return math.min(C.ZONES, math.floor(x / C.ZONE_W) + 1) end

-- waves and things, sorted by `at`. kinds: soldier bazooka drone kamikaze crab
L.EVENTS = {
  {at = 300, props = {{"barrel", 520}, {"crate", 760}}},
  {at = 480, wave = {{"soldier", "r", 40}, {"soldier", "r", 140}}},
  {at = 640, pow = {"grandma", 900, "a"}},
  {at = 900, wave = {{"drone", "air", 120}}, props = {{"buoy", 1180}}},
  {at = 1250, wave = {{"soldier", "r", 40}, {"soldier", "r", 130}, {"soldier", "l", 80}}, props = {{"barrel", 1420}}},
  {at = 1650, wave = {{"bazooka", 1960, 0}, {"soldier", "r", 90}}, food = {{"sardine", 1500}, {"bread", 1560}}},
  {at = 2000, wave = {{"drone", "air", 80}, {"drone", "air", 220}}, pow = {"fisherman", 2250, "b"}},
  {at = 2450, wave = {{"kamikaze", "air", 60}, {"kamikaze", "air", 200}, {"soldier", "l", 100}}, props = {{"crate", 2600}}},
  {at = 2800, wave = {{"soldier", "r", 60}, {"soldier", "r", 160}, {"soldier", "r", 260}}},
  -- the main street: the tractor waits at its start
  {at = 3000, tractor = 3360, props = {{"barrel", 3100}}, pow = {"grandma", 3140, "c"}},
  {at = 3400, wave = {{"soldier", "r", 40}, {"soldier", "r", 140}, {"soldier", "l", 90}}},
  {at = 3750, wave = {{"crab", "r", 120}}, food = {{"jamon", 3850}, {"cheese", 3910}}},
  {at = 4200, wave = {{"drone", "air", 100}, {"drone", "air", 240}, {"soldier", "r", 60}}, pow = {"fisherman", 4300, "a"}},
  {at = 4600, wave = {{"bazooka", 4880, 0}, {"bazooka", 5040, 0}, {"soldier", "r", 80}}, props = {{"barrel", 4760}, {"crate", 4960}}},
  {at = 5000, wave = {{"kamikaze", "air", 60}, {"kamikaze", "air", 160}, {"kamikaze", "air", 260}}},
  {at = 5350, wave = {{"crab", "r", 100}, {"soldier", "r", 240}, {"soldier", "l", 80}}, food = {{"paella", 5500}}},
  -- the beach
  {at = 5900, wave = {{"soldier", "r", 40}, {"soldier", "r", 130}, {"soldier", "r", 230}}, props = {{"buoy", 6000}}},
  {at = 6250, wave = {{"drone", "air", 60}, {"drone", "air", 180}, {"drone", "air", 300}}, pow = {"grandma", 6400, "b"}},
  {at = 6650, wave = {{"bazooka", 6960, 0}, {"soldier", "r", 60}, {"soldier", "l", 100}}, food = {{"churro", 6800}, {"orange", 6860}}},
  {at = 7050, wave = {{"crab", "r", 100}, {"kamikaze", "air", 120}, {"kamikaze", "air", 240}}},
  {at = 7450, wave = {{"soldier", "r", 40}, {"soldier", "r", 120}, {"soldier", "r", 200}, {"soldier", "l", 90}}, pow = {"fisherman", 7560, "c"}, props = {{"barrel", 7700}}},
  {at = 7850, wave = {{"drone", "air", 80}, {"drone", "air", 200}, {"bazooka", 8180, 0}}, food = {{"ensaimada", 8000}, {"melon", 8060}}},
}

L.BOSS_X = C.LEVEL_W

return L
