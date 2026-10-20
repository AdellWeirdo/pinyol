-- title: a new game, or the one saved at the last statue.
local scene = require("scene")
local ui = require("ui")

local T = {}
local choice, saved

function T.enter()
  bg(0) bg(1) bg(2)
  palette("WORLD")
  bg(3, {map = "FAR", prio = 3})
  backdrop(0)
  saved = stored("save")
  choice = saved and 2 or 1
end

function T.update()
  if saved and (btnp("up") or btnp("down")) then choice = choice % 2 + 1 end
  if btnp("a") or btnp("start") then scene.go(require("play"), {saved = choice == 2 and saved or nil}, {clean = true, fade = 0.5}) end
end

function T.draw()
  shade(60, 50, 360, 200)
  text("CRIPTA", 240, 70, {font = "large_bold", scale = 2, align = "center", color = ui.SEL})
  text("un castillo, dos poderes y una gárgola", 240, 120, {font = "main", align = "center", color = ui.INK})
  text((choice == 1 and "> " or "  ") .. "Nueva partida", 240, 160, {font = "bold", align = "center", color = choice == 1 and ui.SEL or ui.INK})
  if saved then text((choice == 2 and "> " or "  ") .. "Continuar", 240, 186, {font = "bold", align = "center", color = choice == 2 and ui.SEL or ui.INK}) end
  text("A saltar   B espada   C ráfaga   START mapa", 240, 292, {font = "main", align = "center", color = ui.SUB})
end

return T
