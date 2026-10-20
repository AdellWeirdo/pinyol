-- iso: the island as heights on a grid, and the moves the hero can make on it. Nothing drawn here, so the tests can play it.
-- A cell's ground is its height in blocks (0 the ground, 1-4 a column), WATER or PALM; a crate on it adds one, and a crate pushed
-- into the water fills it (ground 0 from then on). The hero walks onto what is no higher than where it stands (down any drop), jumps
-- onto what is one block higher at most, and pushes a crate at its own level along if what is beyond is no higher than the crate's foot.
local M = {}

M.WATER, M.PALM = -1, 99
M.DIRS = {up = {0, -1}, right = {1, 0}, down = {0, 1}, left = {-1, 0}}

local function key(x, y) return y * 100 + x end
M.key = key

function M.new(level)
  local s = {w = #level.rows[1], h = #level.rows, cells = {}, crates = {}, filled = {}, gems = {}, gems_left = 0, level = level}
  for y = 0, s.h - 1 do
    local row = level.rows[y + 1]
    for x = 0, s.w - 1 do
      local c = row:sub(x + 1, x + 1)
      s.cells[key(x, y)] = c == "~" and M.WATER or c == "t" and M.PALM or tonumber(c) or 0
    end
  end
  for _, g in ipairs(level.gems) do s.gems[key(g[1], g[2])] = true; s.gems_left = s.gems_left + 1 end
  M.reset(s)
  return s
end

-- the crates back where they were and the hero at the start; the gems taken stay taken
function M.reset(s)
  s.crates, s.filled = {}, {}
  for _, c in ipairs(s.level.crates) do s.crates[key(c[1], c[2])] = true end
  s.hx, s.hy = s.level.start[1], s.level.start[2]
end

function M.ground(s, x, y)
  if x < 0 or y < 0 or x >= s.w or y >= s.h then return M.WATER end
  local k = key(x, y)
  if s.filled[k] then return 0 end
  return s.cells[k]
end

-- what stands at a cell: its ground, and one more with a crate on it
function M.surface(s, x, y)
  local g = M.ground(s, x, y)
  if s.crates[key(x, y)] then return g + 1 end
  return g
end

-- The move the hero would make in that direction (jumping or not): {kind = "walk" | "jump" | "push" | "splash", tx, ty, z0, z1,
-- and for a push the crate's cx, cy, cz0, cz1 and whether it sinks}, or nil when the way is shut.
function M.try(s, dir, jump)
  local d = M.DIRS[dir]
  local z0 = M.surface(s, s.hx, s.hy)
  local tx, ty = s.hx + d[1], s.hy + d[2]
  local g = M.ground(s, tx, ty)
  if g == M.PALM then return nil end
  if g == M.WATER then return {kind = "splash", tx = tx, ty = ty, z0 = z0, z1 = -1} end
  local tk = key(tx, ty)
  if s.crates[tk] and not jump and g == z0 then -- a crate is pushed at its foot, from the same level (from higher, stepped down onto)
    local cx, cy = tx + d[1], ty + d[2]
    local cg, ck = M.ground(s, cx, cy), key(cx, cy)
    if cg == M.PALM or s.crates[ck] or s.gems[ck] or cg > g then return nil end
    return {kind = "push", tx = tx, ty = ty, z0 = z0, z1 = z0, cx = cx, cy = cy, cz0 = g, cz1 = cg == M.WATER and -1 or cg,
            sinks = cg == M.WATER}
  end
  local z1 = M.surface(s, tx, ty)
  if jump then
    if z1 <= z0 + 1 then return {kind = "jump", tx = tx, ty = ty, z0 = z0, z1 = z1} end
  elseif z1 <= z0 then
    return {kind = "walk", tx = tx, ty = ty, z0 = z0, z1 = z1}
  end
  return nil
end

-- The move done: the hero where it went (back where it was from the water), the crate pushed or sunk. Returns true when a gem was taken.
function M.apply(s, mv)
  if mv.kind == "splash" then return false end
  if mv.kind == "push" then
    s.crates[key(mv.tx, mv.ty)] = nil
    if mv.sinks then s.filled[key(mv.cx, mv.cy)] = true else s.crates[key(mv.cx, mv.cy)] = true end
  end
  s.hx, s.hy = mv.tx, mv.ty
  local k = key(s.hx, s.hy)
  if s.gems[k] then
    s.gems[k] = nil
    s.gems_left = s.gems_left - 1
    return true
  end
  return false
end

-- Every cell the hero can get to with the crates where they are, never pushing one (the tests: what needs a crate moved first).
function M.reach(s)
  local seen, queue, head = {[key(s.hx, s.hy)] = true}, {{s.hx, s.hy}}, 1
  local hx, hy = s.hx, s.hy
  while head <= #queue do
    s.hx, s.hy = queue[head][1], queue[head][2]
    head = head + 1
    for dir in pairs(M.DIRS) do
      for _, jump in ipairs({false, true}) do
        local mv = M.try(s, dir, jump)
        if mv and mv.kind ~= "splash" and mv.kind ~= "push" and not seen[key(mv.tx, mv.ty)] then
          seen[key(mv.tx, mv.ty)] = true
          queue[#queue + 1] = {mv.tx, mv.ty}
        end
      end
    end
  end
  s.hx, s.hy = hx, hy
  return seen
end

return M
