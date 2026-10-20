-- ending: the gargoyle has fallen.
local scene = require("scene")
local ui = require("ui")

local E = {}
function E.enter() E.t = 0 store("save", nil) store("cleared", (stored("cleared", 0) or 0) + 1) end
function E.update() E.t = E.t + 1 if E.t > 90 and (btnp("a") or btnp("start")) then scene.go(require("title"), nil, {clean = true, fade = 0.5}) end end
function E.draw()
  cls(0)
  text("LA GÁRGOLA HA CAÍDO", 240, 110, {font = "large_bold", align = "center", color = ui.SEL})
  local seen = 0
  for _ in pairs(game.visited) do seen = seen + 1 end
  text(string.format("salas %d   corazones %d   muertes %d", seen, game.max_hearts, game.deaths), 240, 160, {font = "main", align = "center", color = ui.INK})
  if E.t > 90 then text("A: al título", 240, 200, {font = "main", align = "center", color = ui.SUB}) end
end
return E
