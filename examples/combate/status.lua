-- status: the party's sheet, over the meadow (which stays drawn under it). START or B closes it.
local scene = require("scene")
local ui = require("ui")
local R = require("rules")

local S = {overlay = true}

function S.update()
  if btnp("start") or btnp("b") then scene.pop() end
end

function S.draw()
  shade(0, 0, SCREEN_W, SCREEN_H)
  ui.box(60, 16, 360, 288)
  text("EL GRUPO", 240, 28, {font = "bold", align = "center", color = ui.SEL})
  for i, m in ipairs(game.party) do
    local y = 62 + (i - 1) * 94
    text(string.format("%s   Nv %d", m.name, m.lv), 84, y, {font = "bold", color = ui.INK})
    text(string.format("PV %d/%d    PM %d/%d", m.hp, m.maxhp, m.mp, m.maxmp), 84, y + 26, {font = "main", color = ui.SUB})
    text(string.format("Ataque %d   Defensa %d   Veloc. %d", m.atk, m.def, m.spd), 84, y + 46, {font = "main", color = ui.SUB})
    text(string.format("Experiencia %d/%d", m.xp, R.xp_needed(m.lv)), 84, y + 66, {font = "main", color = ui.DIM})
  end
  text(string.format("Pociones %d   ·   Victorias %d", game.potions, game.wins), 240, 252, {font = "main", align = "center", color = ui.INK})
  text("START: cerrar", 240, 276, {font = "main", align = "center", color = ui.DIM})
end

return S
