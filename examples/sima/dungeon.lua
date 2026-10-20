-- dungeon: one floor of the chasm, made from the run's seed and the floor's number, so the same run always meets the same floors (and a
-- test can ask for any). Rooms are placed where they fit, apart from each other, and joined in a chain by corridors (an L each), with a
-- couple more joins for loops; the hero starts in the first room and the stairs down are in the last (on the last floor, the amulet).
-- Nothing drawn here.
local M = {}

M.W, M.H = 48, 32
M.FLOOR, M.WALL, M.STAIRS, M.AMULET = 0, 1, 2, 3
M.FLOORS = 5
local ROOMS, TRIES = 9, 300

local function key(x, y) return y * M.W + x + 1 end
M.key = key

function M.at(d, x, y)
  if x < 0 or y < 0 or x >= M.W or y >= M.H then return M.WALL end
  return d.cells[key(x, y)]
end

function M.open(d, x, y) return M.at(d, x, y) ~= M.WALL end

local function overlaps(rooms, x, y, w, h)
  for _, r in ipairs(rooms) do
    if x - 1 <= r.x + r.w and r.x - 1 <= x + w and y - 1 <= r.y + r.h and r.y - 1 <= y + h then return true end
  end
  return false
end

local function carve(d, x0, y0, x1, y1)
  for y = math.min(y0, y1), math.max(y0, y1) do
    for x = math.min(x0, x1), math.max(x0, x1) do d.cells[key(x, y)] = M.FLOOR end
  end
end

local function centre(r) return r.x + r.w // 2, r.y + r.h // 2 end

local function join(d, a, b)
  local ax, ay = centre(a)
  local bx, by = centre(b)
  if math.random(2) == 1 then carve(d, ax, ay, bx, ay) carve(d, bx, ay, bx, by)
  else carve(d, ax, ay, ax, by) carve(d, ax, by, bx, by) end
end

-- a free floor cell of a room, none of those already taken
local function spot(d, r, taken)
  for _ = 1, 40 do
    local x, y = math.random(r.x, r.x + r.w - 1), math.random(r.y, r.y + r.h - 1)
    if d.cells[key(x, y)] == M.FLOOR and not taken[key(x, y)] then taken[key(x, y)] = true return x, y end
  end
end

local KINDS_BY_FLOOR = {{"rata"}, {"rata", "murcielago"}, {"rata", "murcielago", "esqueleto"}, {"murcielago", "esqueleto"},
                        {"murcielago", "esqueleto", "esqueleto"}}

function M.generate(seed, floor)
  math.randomseed(seed * 97 + floor)
  local d
  repeat
    d = {cells = {}, rooms = {}, monsters = {}, items = {}, floor = floor}
    for i = 1, M.W * M.H do d.cells[i] = M.WALL end
    for _ = 1, TRIES do
      if #d.rooms >= ROOMS then break end
      local w, h = math.random(4, 9), math.random(3, 6)
      local x, y = math.random(1, M.W - w - 1), math.random(1, M.H - h - 1)
      if not overlaps(d.rooms, x, y, w, h) then d.rooms[#d.rooms + 1] = {x = x, y = y, w = w, h = h} end
    end
  until #d.rooms >= 5
  table.sort(d.rooms, function(a, b) return a.x + a.y < b.x + b.y end) -- the chain goes across the floor, from one corner
  for _, r in ipairs(d.rooms) do carve(d, r.x, r.y, r.x + r.w - 1, r.y + r.h - 1) end
  for i = 2, #d.rooms do join(d, d.rooms[i - 1], d.rooms[i]) end
  for _ = 1, 2 do join(d, d.rooms[math.random(#d.rooms)], d.rooms[math.random(#d.rooms)]) end
  local taken = {}
  local sx, sy = centre(d.rooms[1])
  d.start = {sx, sy}
  taken[key(sx, sy)] = true
  local ex, ey = centre(d.rooms[#d.rooms])
  d.exit = {ex, ey}
  d.cells[key(ex, ey)] = floor == M.FLOORS and M.AMULET or M.STAIRS
  taken[key(ex, ey)] = true
  local kinds = KINDS_BY_FLOOR[floor]
  for _ = 1, 3 + floor do
    local x, y = spot(d, d.rooms[math.random(2, #d.rooms)], taken)
    if x then d.monsters[#d.monsters + 1] = {kind = kinds[math.random(#kinds)], x = x, y = y} end
  end
  for _ = 1, math.random(3, 5) do
    local x, y = spot(d, d.rooms[math.random(#d.rooms)], taken)
    if x then d.items[#d.items + 1] = {kind = math.random(3) == 1 and "pocion" or "oro", x = x, y = y} end
  end
  return d
end

-- every open cell reached from (x, y) walking: the tests check a floor is all one piece
function M.reach(d, x, y)
  local seen, queue, head = {[key(x, y)] = true}, {{x, y}}, 1
  while head <= #queue do
    local cx, cy = queue[head][1], queue[head][2]
    head = head + 1
    for _, s in ipairs({{1, 0}, {-1, 0}, {0, 1}, {0, -1}}) do
      local nx, ny = cx + s[1], cy + s[2]
      if M.open(d, nx, ny) and not seen[key(nx, ny)] then seen[key(nx, ny)] = true queue[#queue + 1] = {nx, ny} end
    end
  end
  return seen
end

return M
