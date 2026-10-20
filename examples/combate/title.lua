-- title: the first screen. A new game, or the one saved after the last victory.
local scene = require("scene")
local R = require("rules")
local ppu = require("ppu")

local T = {}
local choice, saved

function T.enter()
  ppu.reset()
  palette("WORLD")
  bg(0)
  bg(1)
  bg(2)
  bg(3, {map = "BACKDROP", prio = 3, wrap = false})
  backdrop(0)
  saved = stored("save")
  choice = saved and 2 or 1
end

local function start(continue)
  game = {party = R.new_party(), potions = 3, wins = 0, x = 224, y = 136, dir = 2}
  if continue and saved then
    for k, v in pairs(saved) do game[k] = v end
  end
  scene.go(require("field"), nil, {fade = 0.5})
end

function T.update()
  if saved and (btnp("up") or btnp("down")) then choice = choice % 2 + 1 end
  if btnp("a") or btnp("start") then start(choice == 2) end
end

function T.draw()
  shade(60, 40, 360, 120)
  text("HIERBA ALTA", 240, 70, {font = "large_bold", scale = 2, align = "center", color = 0xFFE070})
  text("combates por turnos, a la manera de la GBA", 240, 130, {font = "main", align = "center", color = 0xFFFFFF})
  text((choice == 1 and "> " or "  ") .. "Nueva partida", 240, 176, {font = "bold", align = "center", color = choice == 1 and 0xFFE070 or 0xFFFFFF})
  if saved then
    text((choice == 2 and "> " or "  ") .. string.format("Continuar (%d combates ganados)", saved.wins or 0), 240, 200,
         {font = "bold", align = "center", color = choice == 2 and 0xFFE070 or 0xFFFFFF})
  end
  text("A: elegir    START en el campo: el grupo", 240, 290, {font = "main", align = "center", color = 0x9CB0C8})
end

return T
