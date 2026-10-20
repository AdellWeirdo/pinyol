-- rules: Tablero's numbers and moves, with no drawing and nothing kept between calls. A `state` is {terrain, units, turn, side}; every
-- function that changes something returns a new state, so the scenes, the AI and the tests use them alike. The movement, the paths
-- and the danger map are the engine's `grid` (the C code behind g:reach, g:path, g:distances and layers).
local M = {}

M.TERRAIN = { -- by the number data.lua gives each cell: cost to enter (0: a wall), defence it adds
  [0] = {name = "Llano", cost = 1, def = 0},
  [1] = {name = "Bosque", cost = 2, def = 1},
  [2] = {name = "Montaña", cost = 3, def = 2},
  [3] = {name = "Agua", cost = 0, def = 0},
  [4] = {name = "Camino", cost = 1, def = 0},
  [5] = {name = "Puente", cost = 1, def = 0},
}
M.KINDS = { -- 0 sword, 1 bow, 2 rider: life, attack, defence, cells it moves, and the range it hits at
  [0] = {name = "Espada", hp = 20, atk = 7, def = 2, move = 4, min = 1, max = 1},
  [1] = {name = "Arco", hp = 14, atk = 6, def = 1, move = 3, min = 2, max = 2},
  [2] = {name = "Jinete", hp = 18, atk = 8, def = 1, move = 6, min = 1, max = 1},
}

local function copy(t)
  local c = {}
  for k, v in pairs(t) do c[k] = v end
  return c
end

local function replace(units, id, changes)
  local out = {}
  for i, u in ipairs(units) do
    if u.id == id then
      local n = copy(u)
      for k, v in pairs(changes) do n[k] = v end
      out[#out + 1] = n
    else
      out[#out + 1] = u
    end
  end
  return out
end

function M.new_game(data)
  local units, id = {}, 0
  for _, army in ipairs({{"blue", data.blue}, {"red", data.red}}) do
    for _, p in ipairs(army[2]) do
      id = id + 1
      local k = M.KINDS[p[3]]
      units[#units + 1] = {id = id, team = army[1], kind = p[3], x = p[1], y = p[2], hp = k.hp, acted = false}
    end
  end
  return {terrain = data.grid, w = data.w, h = data.h, units = units, turn = 1, side = "blue"}
end

function M.terrain_at(state, x, y) return M.TERRAIN[state.terrain[y + 1][x + 1]] end

function M.unit_at(state, x, y)
  for _, u in ipairs(state.units) do if u.x == x and u.y == y then return u end end
end

function M.unit(state, id)
  for _, u in ipairs(state.units) do if u.id == id then return u end end
end

function M.alive(state, side)
  local out = {}
  for _, u in ipairs(state.units) do if not side or u.team == side then out[#out + 1] = u end end
  return out
end

-- the terrain as the engine's grid; cells in `blocked` ({[y * 100 + x] = true}) are walls too
function M.cost_grid(state, blocked)
  local g = grid(state.w, state.h)
  for y = 0, state.h - 1 do
    for x = 0, state.w - 1 do
      g:set(x, y, (blocked and blocked[y * 100 + x]) and 0 or M.TERRAIN[state.terrain[y + 1][x + 1]].cost)
    end
  end
  return g
end

local function cell_key(x, y) return y * 100 + x end

-- where a unit can end its move: what its move buys over the terrain, round the enemy (who blocks) and through its own side (who does
-- not, but cannot be stood on). {x, y, cost}, its own cell first.
function M.reach(state, u)
  local blocked, occupied = {}, {}
  for _, o in ipairs(state.units) do
    if o.id ~= u.id then
      if o.team ~= u.team then blocked[cell_key(o.x, o.y)] = true else occupied[cell_key(o.x, o.y)] = true end
    end
  end
  local g = M.cost_grid(state, blocked)
  local out = {{x = u.x, y = u.y, cost = 0}}
  for _, c in ipairs(g:reach(u.x, u.y, M.KINDS[u.kind].move)) do
    if not (c[1] == u.x and c[2] == u.y) and not occupied[cell_key(c[1], c[2])] then
      out[#out + 1] = {x = c[1], y = c[2], cost = c[3]}
    end
  end
  return out, g
end

-- the cells an attack from (x, y) with this range could hit, inside the field
function M.cells_in_range(state, x, y, min, max)
  local out = {}
  for dy = -max, max do
    for dx = -max, max do
      local d = math.abs(dx) + math.abs(dy)
      local cx, cy = x + dx, y + dy
      if d >= min and d <= max and cx >= 0 and cy >= 0 and cx < state.w and cy < state.h then out[#out + 1] = {cx, cy} end
    end
  end
  return out
end

-- the enemies a unit standing at (x, y) could hit
function M.targets(state, u, x, y)
  local k, out = M.KINDS[u.kind], {}
  for _, c in ipairs(M.cells_in_range(state, x, y, k.min, k.max)) do
    local o = M.unit_at(state, c[1], c[2])
    if o and o.team ~= u.team then out[#out + 1] = o end
  end
  return out
end

function M.damage(att, def, def_terrain)
  return math.max(1, M.KINDS[att.kind].atk - M.KINDS[def.kind].def - def_terrain)
end

local function inside(state, att, def)
  local k = M.KINDS[att.kind]
  local d = math.abs(att.x - def.x) + math.abs(att.y - def.y)
  return d >= k.min and d <= k.max
end

-- a blow, and the answer if the one hit is still standing and the other is within its range. Returns the new state and the events
-- ({kind = "hit"|"counter"|"fall", id, dmg}).
function M.strike(state, att_id, def_id)
  local att, def = M.unit(state, att_id), M.unit(state, def_id)
  local events = {}
  local dmg = M.damage(att, def, M.terrain_at(state, def.x, def.y).def)
  local units = replace(state.units, def_id, {hp = math.max(0, def.hp - dmg)})
  events[#events + 1] = {kind = "hit", id = def_id, dmg = dmg}
  def = M.unit({units = units}, def_id)
  if def.hp > 0 and inside(state, def, att) then
    local back = M.damage(def, att, M.terrain_at(state, att.x, att.y).def)
    units = replace(units, att_id, {hp = math.max(0, att.hp - back)})
    events[#events + 1] = {kind = "counter", id = att_id, dmg = back}
  end
  local alive = {}
  for _, u in ipairs(units) do
    if u.hp > 0 then alive[#alive + 1] = u else events[#events + 1] = {kind = "fall", id = u.id} end
  end
  local out = copy(state)
  out.units = alive
  return out, events
end

function M.move(state, id, x, y)
  local out = copy(state)
  out.units = replace(state.units, id, {x = x, y = y})
  return out
end

function M.finish(state, id)
  local out = copy(state)
  out.units = replace(state.units, id, {acted = true})
  return out
end

function M.end_turn(state)
  local out = copy(state)
  out.side = state.side == "blue" and "red" or "blue"
  if out.side == "blue" then out.turn = state.turn + 1 end
  out.units = {}
  for _, u in ipairs(state.units) do
    local n = copy(u)
    n.acted = false
    out.units[#out.units + 1] = n
  end
  return out
end

function M.winner(state)
  local blue, red = #M.alive(state, "blue"), #M.alive(state, "red")
  if red == 0 then return "blue" end
  if blue == 0 then return "red" end
end

-- where `side` could hit next turn: a layer with, in each cell, how many of its units reach it. The player's map of danger.
function M.danger(state, side)
  local layer = M.cost_grid(state):layer(0)
  for _, u in ipairs(M.alive(state, side)) do
    local k = M.KINDS[u.kind]
    local seen = {}
    for _, c in ipairs(M.reach(state, u)) do
      for _, t in ipairs(M.cells_in_range(state, c.x, c.y, k.min, k.max)) do
        local key = cell_key(t[1], t[2])
        if not seen[key] then seen[key] = true layer:add(t[1], t[2], 1) end
      end
    end
  end
  return layer
end

return M
