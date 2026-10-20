-- world: the castle as rooms on a grid of screens (15 x 10 tiles of 16), read from the Tiled imports (room_<id>.lua). What a cell is,
-- in a room or anywhere in the castle; which room holds a place; and a solver that says where a hero with some abilities can get to,
-- so the tests can prove the castle is finished in the order it was meant to be. No drawing and nothing kept but the broken walls.
local M = {}

M.T, M.SW, M.SH = 16, 15, 10 -- a tile's pixels; a screen in tiles
M.EMPTY, M.WALL, M.PLATFORM, M.CRACKED = 0, 1, 2, 3
M.JUMP_CELLS, M.DOUBLE_CELLS, M.REACH_CELLS = 3, 5, 3 -- what the hero's jumps climb (exactly: hero.lua's 54 px and 94 px), and a
-- careful reach across (the hero gets some 6 tiles, so 3 is what it surely does)

M.rooms, M.order = {}, {}
for _, id in ipairs(require("rooms_list")) do
  local r = require("room_" .. id)
  local room = {id = id, mx = r.props.mx, my = r.props.my, w = r.width, h = r.height, asset = r.layers.suelo.asset, things = {}}
  room.cells = {}
  for i, v in ipairs(r.layers.suelo.data) do
    local p = r.tiles[v] or {}
    room.cells[i] = p.cracked and M.CRACKED or p.solid and M.WALL or p.platform and M.PLATFORM or M.EMPTY
  end
  for _, o in ipairs(r.objects) do -- Tiled's points are where feet stand, in the middle of a tile
    room.things[#room.things + 1] = {kind = o.type, tx = o.x // M.T, ty = o.y // M.T - 1}
  end
  M.rooms[id], M.order[#M.order + 1] = room, id
end

M.screens = {} -- [sy * 100 + sx] = the room that holds that screen of the castle
for _, id in ipairs(M.order) do
  local r = M.rooms[id]
  for sy = r.my, r.my + r.h // M.SH - 1 do
    for sx = r.mx, r.mx + r.w // M.SW - 1 do M.screens[sy * 100 + sx] = r end
  end
end

M.broken = {} -- cracked walls the dash broke: [room id] = {[cell index] = true}

-- the cell at tile (tx, ty) of a room; outside it, a wall
function M.cell(room, tx, ty)
  if tx < 0 or ty < 0 or tx >= room.w or ty >= room.h then return M.WALL end
  local i = ty * room.w + tx + 1
  local c = room.cells[i]
  if c == M.CRACKED and M.broken[room.id] and M.broken[room.id][i] then return M.EMPTY end
  return c
end

function M.break_wall(room, tx, ty)
  if M.cell(room, tx, ty) ~= M.CRACKED then return false end
  M.broken[room.id] = M.broken[room.id] or {}
  M.broken[room.id][ty * room.w + tx + 1] = true
  return true
end

-- the room that holds castle tile (wx, wy), and that tile in it
function M.room_at(wx, wy)
  if wx < 0 or wy < 0 then return nil end
  local r = M.screens[(wy // M.SH) * 100 + wx // M.SW]
  if r then return r, wx - r.mx * M.SW, wy - r.my * M.SH end
end

-- the castle's tile: what it is wherever it lies (outside every room, a wall)
function M.wcell(wx, wy)
  local r, tx, ty = M.room_at(wx, wy)
  if not r then return M.WALL end
  return M.cell(r, tx, ty)
end

function M.thing(kind)
  for _, id in ipairs(M.order) do
    for _, t in ipairs(M.rooms[id].things) do
      if t.kind == kind then return M.rooms[id], t end
    end
  end
end

-- ------------------------------------------------------------------ the solver
-- Where a hero can stand: an open tile with a wall, a cracked wall or a platform under it. From one, it walks to a neighbour, falls
-- down a column, or jumps: up to `climb` tiles (3, or 5 with the wings) and `REACH` across, through open tiles (a platform lets it up
-- through, and holds it from above). With the gust a cracked wall is open: the dash goes through it. A floor that is cracked still holds.
local function open(c, gust) return c == M.EMPTY or c == M.PLATFORM or (gust and c == M.CRACKED) end
local function holds(c) return c == M.WALL or c == M.CRACKED or c == M.PLATFORM end

function M.reach(start_wx, start_wy, abilities, across_max)
  across_max = across_max or M.REACH_CELLS -- (the tests also ask with a longer one: what the hero may get to, not only what it surely does)
  local climb = abilities.wings and M.DOUBLE_CELLS or M.JUMP_CELLS
  local gust = abilities.gust
  local function free(x, y) return open(M.wcell(x, y), gust) end
  local function stand(x, y) return free(x, y) and holds(M.wcell(x, y + 1)) end
  local seen, queue, head, from = {}, {}, 1, nil
  local back = {} -- back[k] = the tiles it can be got to from (the moves reversed: the tests ask where the hero can return from)
  local function push(x, y)
    local k = y * 1000 + x
    if from then
      back[k] = back[k] or {}
      back[k][from] = true
    end
    if not seen[k] then seen[k] = true queue[#queue + 1] = {x, y} end
  end
  local function land(x, y) -- falling from (x, y): the tile it comes to rest on, if any
    for yy = y, y + 60 do
      if not free(x, yy) then return nil end
      if stand(x, yy) then return yy end
    end
  end
  push(start_wx, start_wy)
  while head <= #queue do
    local x, y = queue[head][1], queue[head][2]
    head = head + 1
    from = y * 1000 + x
    for _, dx in ipairs({-1, 1}) do -- a step, or off the edge and down
      if free(x + dx, y) then
        local ly = land(x + dx, y)
        if ly then push(x + dx, ly) end
      end
    end
    for up = 1, climb do -- a jump: straight up while it is open, then across at that height, then down onto what holds
      if not free(x, y - up) then break end
      for _, dir in ipairs({-1, 1}) do
        for across = 0, across_max do
          local nx = x + dir * across
          if not free(nx, y - up) then break end
          local ly = land(nx, y - up)
          if ly then push(nx, ly) end
        end
      end
    end
  end
  return seen, back
end

function M.can_reach(seen, wx, wy) return seen[wy * 1000 + wx] == true end

-- a thing's castle tile
function M.world_tile(room, tx, ty) return room.mx * M.SW + tx, room.my * M.SH + ty end

return M
