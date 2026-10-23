-- view: the level on the screen. The 16x16 cells are tiles of the background layer (PICO-8's map()), placed in the middle of a 32x18 map so that the
-- carved margins of the tomb fill the 56 pixels at each side; animated cells (gems, spikes, the exit, mud, teleporters, keys) change tile every few ticks.
local Rules = require("core.rules")
local Tilepos = require("data.tilepos")
local V = {}

V.OX, V.OY = 8, 1        -- the level's cell (0, 0) in the map
V.PX, V.PY = 56, 16      -- and its pixel on the screen (the 128x128 cart screen is at 56, 16 of the 240x160 world)
local TILE = {}

function V.init()
  bg(1, {map = "ROOM", prio = 1, wrap = false})
  for name, p in pairs(Tilepos) do TILE[name] = mget(1, p[1], p[2]) & 0xFFF end -- before the first level overwrites the atlas
  scroll(1, V.OX * 8 - V.PX, V.OY * 8 - V.PY)
end

function V.tile(name) return TILE[name] end

local function put(mx, my, name)
  local e = TILE[name]
  if not e then error("no tile " .. tostring(name), 2) end
  mset(1, mx, my, e)
end
V.put = put

-- the carved columns left and right, and black over and under: the margins
function V.margins()
  for my = 0, 17 do
    for mx = 0, 31 do
      local inside = mx >= V.OX and mx < V.OX + 16 and my >= V.OY and my < V.OY + 16
      if not inside then
        local name = "floor_a"
        if my >= 1 and my <= 16 then
          if mx == V.OX - 1 or mx == V.OX + 16 then name = "border_" .. ({"a", "b", "c", "d"})[(my % 4) + 1] end
        end
        put(mx, my, name)
      end
    end
  end
end

local function hash(x, y) return ((x * 73856093) ~ (y * 19349663)) & 0xFFFF end

local function solid(lv, st, x, y)
  if x < 0 or y < 0 or x >= 16 or y >= 16 then return true end
  local c = lv.g[y + 1][x + 1]
  if c == "#" then return true end
  if c == "c" or c == "D" then return Rules.now(lv, st, x, y) ~= "." end
  return false
end

-- the tile name of a cell, for the animation frame t
function V.name(lv, st, x, y, t)
  local c = lv.g[y + 1][x + 1]
  local now = Rules.now(lv, st, x, y)
  local fr = t // 6
  if c == "#" then
    local m = 0
    if not solid(lv, st, x, y - 1) then m = m | 1 end
    if not solid(lv, st, x + 1, y) then m = m | 2 end
    if not solid(lv, st, x, y + 1) then m = m | 4 end
    if not solid(lv, st, x - 1, y) then m = m | 8 end
    return "wall_m" .. m
  end
  if c == "c" then return now == "c" and "crack_0" or "rubble" end
  if c == "D" then return now == "D" and "door" or "door_open" end
  if c == "^" then return "spike_" .. (fr // 3) % 2 end
  if c == "E" then
    if Rules.all_gems(lv, st) then return "exit_open_" .. fr % 3 end
    return "exit_closed"
  end
  if c == "m" then return "mud_" .. (fr // 2) % 2 end
  if c == "1" then return "tele_a_" .. fr % 3 end
  if c == "2" then return "tele_b_" .. fr % 3 end
  if c == "u" or c == "d" or c == "l" or c == "r" then return "gate_" .. c end
  if now == "o" then return "coin_" .. (fr + x + y) % 4 end
  if now == "k" then return "key_" .. (fr // 2) % 2 end
  if c == "S" then return "start" end
  -- floor (also where a gem or a key was)
  local up_solid = solid(lv, st, x, y - 1)
  local h = hash(x, y)
  if up_solid then return "floor_shade_" .. ({"a", "b"})[h % 2 + 1] end
  local r = h % 10
  return "floor_" .. (r < 6 and "a" or r < 8 and "b" or r < 9 and "c" or "d")
end

-- the start cell shows its sigil too: the generator writes it as a floor and the level knows `start`
function V.draw_all(lv, st, t)
  for y = 0, 15 do
    for x = 0, 15 do
      local name = V.name(lv, st, x, y, t)
      if lv.start and lv.start[1] == x and lv.start[2] == y and Rules.now(lv, st, x, y) == "." then name = "start" end
      put(V.OX + x, V.OY + y, name)
    end
  end
end

local ANIM = {o = true, k = true, ["^"] = true, E = true, m = true, ["1"] = true, ["2"] = true}
function V.animate(lv, st, t)
  for y = 0, 15 do
    for x = 0, 15 do
      if ANIM[lv.g[y + 1][x + 1]] then put(V.OX + x, V.OY + y, V.name(lv, st, x, y, t)) end
    end
  end
end

function V.cell(lv, st, x, y, t)
  put(V.OX + x, V.OY + y, V.name(lv, st, x, y, t))
  -- a change can alter the walls and shadows around it
  for _, d in ipairs({{0, -1}, {1, 0}, {0, 1}, {-1, 0}}) do
    local nx, ny = x + d[1], y + d[2]
    if nx >= 0 and nx < 16 and ny >= 0 and ny < 16 then
      local name = V.name(lv, st, nx, ny, t)
      if lv.start and lv.start[1] == nx and lv.start[2] == ny and Rules.now(lv, st, nx, ny) == "." then name = "start" end
      put(V.OX + nx, V.OY + ny, name)
    end
  end
end

return V
