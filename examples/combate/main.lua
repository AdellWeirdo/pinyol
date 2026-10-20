-- Hierba Alta: a small RPG with a fight by turns, in the Game Boy Advance's style. You walk a meadow; the tall grass hides
-- enemies; a fight begins with the screen's own effects (flash, ripple, mosaic, an iris) and is a menu of turns. Made to
-- try what a JRPG asks of the engine: scenes that come and go (scene.lua), per-line windows and scrolls, mosaic, sprites turned
-- by a matrix, menus at the full 480 x 320, a party in `store`.
--   Field: arrows walk, START the party's sheet.   Fight: arrows and A choose, B goes back.
local scene = require("scene")
local R = require("rules")

game = {party = R.new_party(), potions = 3, wins = 0, x = 224, y = 136, dir = 2} -- (a global: the scenes and the tests read it)

function _init()
  sound("SWIRL", {wave = "saw", freq = 180, slide = 1400, decay = 0.9, volume = 0.25})
  sound("APPEAR", {wave = "square", freq = 330, slide = 330, decay = 0.25, volume = 0.25})
  sound("HIT", {wave = "noise", freq = 700, slide = -300, decay = 0.1, volume = 0.3})
  sound("MAGIC", {wave = "square", freq = 440, slide = 900, decay = 0.3, volume = 0.25})
  sound("HURT", {wave = "saw", freq = 260, slide = -200, decay = 0.15, volume = 0.3})
  sound("HEAL", {wave = "triangle", freq = 520, slide = 520, decay = 0.35, volume = 0.3})
  sound("NO", {wave = "square", freq = 150, decay = 0.1, volume = 0.2})
  sound("DRAIN", {wave = "saw", freq = 330, slide = -260, decay = 0.6, volume = 0.3})
  scene.go(require("title"))
end

function _update() scene.update() end
function _draw() scene.draw() end
