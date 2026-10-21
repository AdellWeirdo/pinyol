-- gen: levels made by code, the roguelike classics: caves from cellular automata, rooms and corridors from a BSP
-- tree, tunnels from a drunkard's walk, and Spelunky's trick (Derek Yu, as Darius Kazemi took it apart): a grid of
-- rooms with a path from the top to the bottom that is always walkable, each room on it picked from templates
-- that open on the sides the path needs. Every map is a table {w, h, get(x, y), set(x, y, v)} of 1 (solid) and 0
-- (open); draw it with autotile, walk it with grid. Give each a seed (rng.new) and the same level comes back.
--
--   local gen = require("gen")
--   m = gen.caves(60, 40, {fill = 0.45, steps = 5, seed = 7})        -- rounded caves
--   m = gen.bsp(60, 40, {min = 6, seed = 7})                           -- rooms joined by corridors; m.rooms = {{x, y, w, h}...}
--   m = gen.walk(60, 40, {steps = 1200, seed = 7})                     -- a drunkard's tunnels
--   rooms = gen.spelunky(4, 4, {seed = 7})                             -- rooms[row][col]: 0 side room, 1 open left-right,
--                                                                      -- 2 also open down, 3 also open up (the path's)
--   gen.connected(m)                                                   -- keeps only the biggest open region (the rest filled)
--   gen.fill_border(m)  m:count(0)  m:find(0, r)                       -- a border of walls; how many of v; a random open cell
local M = {}
local rng = require("rng")
local Map = {}
Map.__index = Map

function M.map(w, h, v)
  local m = setmetatable({w = w, h = h, cells = {}}, Map)
  for i = 0, w * h - 1 do m.cells[i] = v or 0 end
  return m
end
function Map:get(x, y)
  if x < 0 or y < 0 or x >= self.w or y >= self.h then return 1 end
  return self.cells[y * self.w + x]
end
function Map:set(x, y, v)
  if x >= 0 and y >= 0 and x < self.w and y < self.h then self.cells[y * self.w + x] = v end
end
function Map:count(v)
  local n = 0
  for i = 0, self.w * self.h - 1 do if self.cells[i] == v then n = n + 1 end end
  return n
end
function Map:find(v, r) -- a random cell with that value (r: an rng), or nil
  for _ = 1, 1000 do
    local x, y = r:int(0, self.w - 1), r:int(0, self.h - 1)
    if self:get(x, y) == v then return x, y end
  end
  return nil
end
function Map:is_solid(x, y) return self:get(x, y) == 1 end -- for autotile

function M.fill_border(m)
  for x = 0, m.w - 1 do m:set(x, 0, 1) m:set(x, m.h - 1, 1) end
  for y = 0, m.h - 1 do m:set(0, y, 1) m:set(m.w - 1, y, 1) end
  return m
end

function M.caves(w, h, opts)
  opts = opts or {}
  local r = rng.new(opts.seed or 0)
  local m = M.map(w, h)
  for y = 0, h - 1 do for x = 0, w - 1 do m:set(x, y, r:chance(opts.fill or 0.45) and 1 or 0) end end
  M.fill_border(m)
  for _ = 1, opts.steps or 5 do
    local next = {}
    for y = 0, h - 1 do
      for x = 0, w - 1 do
        local n = 0
        for dy = -1, 1 do for dx = -1, 1 do if (dx ~= 0 or dy ~= 0) and m:get(x + dx, y + dy) == 1 then n = n + 1 end end end
        next[y * w + x] = (n >= (opts.birth or 5) or (m:get(x, y) == 1 and n >= (opts.survive or 4))) and 1 or 0
      end
    end
    m.cells = next
    M.fill_border(m)
  end
  return m
end

function M.walk(w, h, opts)
  opts = opts or {}
  local r = rng.new(opts.seed or 0)
  local m = M.map(w, h, 1)
  local x, y = opts.x or w // 2, opts.y or h // 2
  for _ = 1, opts.steps or w * h // 2 do
    m:set(x, y, 0)
    local d = r:int(4)
    if d == 1 then x = x + 1 elseif d == 2 then x = x - 1 elseif d == 3 then y = y + 1 else y = y - 1 end
    x, y = math.max(1, math.min(w - 2, x)), math.max(1, math.min(h - 2, y))
  end
  return m
end

local function carve(m, x0, y0, x1, y1)
  for y = math.min(y0, y1), math.max(y0, y1) do for x = math.min(x0, x1), math.max(x0, x1) do m:set(x, y, 0) end end
end

function M.bsp(w, h, opts)
  opts = opts or {}
  local r = rng.new(opts.seed or 0)
  local min = opts.min or 6
  local m = M.map(w, h, 1)
  local rooms = {}
  local function split(x, y, bw, bh, depth)
    if depth > (opts.depth or 5) or (bw < min * 2 and bh < min * 2) or r:chance(depth > 2 and 0.2 or 0) then
      local rw, rh = r:int(math.max(3, min // 2), math.max(3, bw - 2)), r:int(math.max(3, min // 2), math.max(3, bh - 2))
      local rx, ry = x + r:int(1, math.max(1, bw - rw - 1)), y + r:int(1, math.max(1, bh - rh - 1))
      local room = {x = rx, y = ry, w = rw, h = rh, cx = rx + rw // 2, cy = ry + rh // 2}
      carve(m, rx, ry, rx + rw - 1, ry + rh - 1)
      rooms[#rooms + 1] = room
      return room
    end
    local a, b
    if bw >= bh then
      local cut = r:int(min, bw - min)
      a, b = split(x, y, cut, bh, depth + 1), split(x + cut, y, bw - cut, bh, depth + 1)
    else
      local cut = r:int(min, bh - min)
      a, b = split(x, y, bw, cut, depth + 1), split(x, y + cut, bw, bh - cut, depth + 1)
    end
    if a and b then -- a corridor between the two halves' rooms, an L
      if r:chance(0.5) then carve(m, a.cx, a.cy, b.cx, a.cy) carve(m, b.cx, a.cy, b.cx, b.cy)
      else carve(m, a.cx, a.cy, a.cx, b.cy) carve(m, a.cx, b.cy, b.cx, b.cy) end
    end
    return a or b
  end
  split(1, 1, w - 2, h - 2, 0)
  M.fill_border(m)
  m.rooms = rooms
  return m
end

-- Spelunky's rooms: a cols x rows grid, a path from a random top room down to the bottom going left or right, dropping
-- when it runs into the side or by chance; the path's rooms are 1 (open left and right), 2 (open below too), 3 (open
-- above, where the drop lands; also left and right); the others 0. rooms[row][col], rows and cols from 1.
function M.spelunky(cols, rows, opts)
  opts = opts or {}
  local r = rng.new(opts.seed or 0)
  local rooms = {}
  for y = 1, rows do rooms[y] = {} for x = 1, cols do rooms[y][x] = 0 end end
  local x, y = r:int(cols), 1
  local dir = r:sign()
  rooms[y][x] = 1
  while y <= rows do
    local roll = r:int(5)
    if roll <= 3 and x + dir >= 1 and x + dir <= cols then -- go on sideways (three times in five)
      x = x + dir
      if rooms[y][x] == 0 then rooms[y][x] = 1 end
    else -- drop
      if y == rows then break end
      rooms[y][x] = 2
      y = y + 1
      rooms[y][x] = 3
      dir = r:sign()
    end
  end
  return rooms
end

function M.connected(m) -- the biggest open region kept, the others filled
  local seen, best, best_n = {}, nil, 0
  local w = m.w
  for y = 0, m.h - 1 do
    for x = 0, w - 1 do
      if m:get(x, y) == 0 and not seen[y * w + x] then
        local region, stack = {}, {y * w + x}
        seen[y * w + x] = true
        while #stack > 0 do
          local i = table.remove(stack)
          region[#region + 1] = i
          local cx, cy = i % w, i // w
          for _, d in ipairs({{1, 0}, {-1, 0}, {0, 1}, {0, -1}}) do
            local nx, ny = cx + d[1], cy + d[2]
            local j = ny * w + nx
            if m:get(nx, ny) == 0 and not seen[j] then seen[j] = true stack[#stack + 1] = j end
          end
        end
        if #region > best_n then best, best_n = region, #region end
      end
    end
  end
  if not best then return m end
  local keep = {}
  for _, i in ipairs(best) do keep[i] = true end
  for i = 0, w * m.h - 1 do if m.cells[i] == 0 and not keep[i] then m.cells[i] = 1 end end
  return m
end

return M
