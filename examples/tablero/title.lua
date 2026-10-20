-- title: a new battle, the one saved at the last end of turn, or a demonstration (both armies led by the computer).
local scene = require("scene")
local R = require("rules")
local ui = require("ui")
local DATA = require("data")

local T = {}
local choice, items, saved

function T.enter()
  require("ppu").reset()
  palette("WORLD")
  palette("OBJ", true)
  bg(0)
  bg(1)
  bg(3)
  bg(2, {map = "FIELD", prio = 3, wrap = false})
  backdrop(0)
  saved = stored("save")
  items = {{"Nueva batalla", "new"}}
  if saved then items[#items + 1] = {string.format("Continuar (turno %d)", saved.turn or 1), "continue"} end
  items[#items + 1] = {"Demostración", "demo"}
  choice = saved and 2 or 1
end

local function restored()
  local st = R.new_game(DATA)
  local units = {}
  for _, u in ipairs(saved.units) do units[#units + 1] = {id = u.id, team = u.team, kind = u.kind, x = u.x, y = u.y, hp = u.hp, acted = false} end
  st.units, st.turn, st.side = units, saved.turn, saved.side
  return st
end

function T.update()
  if btnp("down") then choice = choice % #items + 1 elseif btnp("up") then choice = (choice - 2) % #items + 1 end
  if btnp("a") or btnp("start") then
    local what = items[choice][2]
    scene.go(require("play"), {state = what == "continue" and restored() or nil, auto = what == "demo"}, {fade = 0.4})
  end
end

function T.draw()
  shade(80, 50, 320, 190)
  text("TABLERO", 240, 70, {font = "large_bold", scale = 2, align = "center", color = ui.SEL})
  text("tácticas por turnos", 240, 118, {font = "main", align = "center", color = ui.INK})
  for i, it in ipairs(items) do
    text((i == choice and "> " or "  ") .. it[1], 240, 156 + (i - 1) * 26, {font = "bold", align = "center", color = i == choice and ui.SEL or ui.INK})
  end
  text("A: elegir", 240, 296, {font = "main", align = "center", color = ui.SUB})
end

return T
