-- title: the island seen from a camera going slowly round it, the name and the best walk so far.
local scene = require("scene")
local iso = require("iso")
local V = require("view")
local G = require("index")
local ui = require("ui")

local T = {}
local t

function T.enter()
  V.init(iso.new(require("level")))
  t = 0
end

function T.update()
  t = t + 1
  if btnp("a") or btnp("start") then scene.go(require("play"), nil, {fade = 0.4}) end
end

function T.draw()
  V.water(t)
  local a = t / 300
  V.draw({}, (G.w - 240) / 2 + math.cos(a) * 60, (G.h - 160) / 2 + math.sin(a) * 30)
  text("ISLA", 240, 54, {font = "large_bold", scale = 2, align = "center", color = ui.SEL, outline = 0x101830, shadow = 0x000000})
  text("cinco gemas, dos cajas y el mar", 240, 106, {font = "bold", align = "center", color = ui.INK, shadow = 0x000000})
  local best = stored("best")
  if best then text("el mejor paseo: " .. best .. " pasos", 240, 134, {font = "main", align = "center", color = ui.INK, shadow = 0x000000}) end
  if (t // 30) % 2 == 0 then text("A para empezar", 240, 250, {font = "bold", align = "center", color = ui.SEL, shadow = 0x000000}) end
  text("la cruceta va en diagonal, por la cuadrícula", 240, 292, {font = "main", align = "center", color = ui.INK, shadow = 0x000000})
end

return T
