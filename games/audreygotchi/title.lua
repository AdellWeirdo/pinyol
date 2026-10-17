-- title: the title screen and, for a new game, the date and the hour, asked as Pokémon Gold asked them: pinyol has
-- no clock that survives the console being off, so the game keeps its own from here.
local ui = require("ui")
local T = ui.T
local M = {}

local MONTHS = {"ENE", "FEB", "MAR", "ABR", "MAY", "JUN", "JUL", "AGO", "SEP", "OCT", "NOV", "DIC"}
local DAYS_IN = {31, 28, 31, 30, 31, 30, 31, 31, 30, 31, 30, 31}

local function days_in(y, m)
  if m == 2 and ((y % 4 == 0 and y % 100 ~= 0) or y % 400 == 0) then return 29 end
  return DAYS_IN[m]
end

-- ------------------------------------------------------------------ title

local title = {t = 0, menu = nil}
M.title = title

function title.enter(o)
  title.t, title.has_save = 0, o and o.has_save
  title.menu = title.has_save and ui.menu({"CONTINUAR", "NUEVA PARTIDA"}, {x = 128, y = 214, w = 224}) or nil
end

-- returns "continue", "new" or nil
function title.update()
  title.t = title.t + 1
  if title.menu then
    local r = title.menu:update()
    if r == 1 then return "continue" end
    if r == 2 then return "new" end
    return nil
  end
  if btnp("start") or btnp("a") then ui.ok() return "new" end
end

function title.draw()
  cls(T[1])
  local w, h = imgsize("TITLE_LOGO")
  local bob = (title.t // 30) % 2 == 0 and 0 or 2
  img("TITLE_LOGO", 240 - w, 18 + bob, {scale = 2})
  local id = "A_CACHORRO"
  local aw, ah = imgsize(id)
  if aw then img(id, 240 - aw, 196 - ah * 2, {scale = 2}) end
  if title.menu then
    title.menu:draw()
  elseif (title.t // 30) % 2 == 0 then
    ui.text("PULSA START", 240, 236, T[4], "center")
  end
end

-- ------------------------------------------------------------------ the date and the hour

local setup = {}
M.setup = setup

function setup.enter()
  setup.v = {15, 10, 2026, 10, 0} -- day, month, year, hour, minute
  setup.field, setup.page, setup.t = 1, 1, 0
end

local function bump(k, d)
  local v = setup.v
  if k == 1 then v[1] = (v[1] - 1 + d) % days_in(v[3], v[2]) + 1
  elseif k == 2 then v[2] = (v[2] - 1 + d) % 12 + 1
  elseif k == 3 then v[3] = math.max(2000, math.min(2099, v[3] + d))
  elseif k == 4 then v[4] = (v[4] + d) % 24
  else v[5] = (v[5] + d) % 60 end
  v[1] = math.min(v[1], days_in(v[3], v[2]))
end

-- returns {year, month, day, hour, minute} when done, "back", or nil
function setup.update()
  setup.t = setup.t + 1
  local first, last = setup.page == 1 and 1 or 4, setup.page == 1 and 3 or 5
  if btnp("left", 14, 5) and setup.field > first then setup.field = setup.field - 1 ui.blip() end
  if btnp("right", 14, 5) and setup.field < last then setup.field = setup.field + 1 ui.blip() end
  if btnp("up", 12, 3) then bump(setup.field, 1) ui.blip() end
  if btnp("down", 12, 3) then bump(setup.field, -1) ui.blip() end
  if btnp("a") or btnp("start") then
    ui.ok()
    if setup.page == 1 then setup.page, setup.field = 2, 4 return nil end
    local v = setup.v
    return {v[3], v[2], v[1], v[4], v[5]}
  end
  if btnp("b") then
    ui.blip()
    if setup.page == 2 then setup.page, setup.field = 1, 1 return nil end
    return "back"
  end
end

local function field(txt, x, y, on)
  if on and (setup.t // 16) % 2 == 0 then
    tri(x + 8, y - 12, x + 24, y - 12, x + 16, y - 20, T[4])
    tri(x + 8, y + 26, x + 24, y + 26, x + 16, y + 34, T[4])
  end
  ui.text(txt, x, y, T[4])
end

function setup.draw()
  cls(T[1])
  ui.box(32, 40, 416, 64)
  ui.text(setup.page == 1 and "¿Qué día es hoy?" or "¿Qué hora es?", 240, 64, T[4], "center")
  ui.box(96, 136, 288, 80)
  local v = setup.v
  if setup.page == 1 then
    field(string.format("%02d", v[1]), 128, 168, setup.field == 1)
    field(MONTHS[v[2]], 200, 168, setup.field == 2)
    field(tostring(v[3]), 288, 168, setup.field == 3)
  else
    field(string.format("%02d", v[4]), 184, 168, setup.field == 4)
    ui.text(":", 232, 168, T[4])
    field(string.format("%02d", v[5]), 256, 168, setup.field == 5)
  end
  ui.text("Cruceta: cambiar   A: vale", 240, 260, T[3], "center")
  ui.text("Su reloj corre mientras juegas", 240, 288, T[3], "center")
end

return M
