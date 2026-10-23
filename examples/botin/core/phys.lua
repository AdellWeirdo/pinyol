-- phys: moving a box through the level's cells. A box is {x, y, w, h} (top-left corner); move_x and move_y carry it as far as it can go and say what stopped it.
local W = require("core.world")
local P = {}

local SOLID, HURT = W.SOLID, W.HURT
P.platforms = {} -- things that hold from above like a one-way floor: {x, y, w} (a fist of the boss that has slammed down)

-- the first solid cell the box overlaps, as cx, cy, char (or nil)
function P.hits_solid(x, y, w, h)
  local x0, x1 = math.floor(x) // 16, math.floor(x + w - 0.01) // 16
  local y0, y1 = math.floor(y) // 16, math.floor(y + h - 0.01) // 16
  for cy = y0, y1 do
    for cx = x0, x1 do
      local c = W.cell(cx, cy)
      if SOLID[c] then return cx, cy, c end
    end
  end
  return nil
end

-- the first cell of any of the characters in `set` (a table [char] = true) that the box overlaps
function P.touches(x, y, w, h, set)
  local x0, x1 = math.floor(x) // 16, math.floor(x + w - 0.01) // 16
  local y0, y1 = math.floor(y) // 16, math.floor(y + h - 0.01) // 16
  for cy = y0, y1 do
    for cx = x0, x1 do
      local c = W.cell(cx, cy)
      if set[c] then return cx, cy, c end
    end
  end
  return nil
end

-- moves e.x by dx; stops against a solid cell. Returns cx, cy, char of the cell that stopped it, or nil.
function P.move_x(e, dx)
  if dx == 0 then return nil end
  local nx = e.x + dx
  local cx, cy, c = P.hits_solid(nx, e.y, e.w, e.h)
  if not cx then e.x = nx return nil end
  if dx > 0 then e.x = cx * 16 - e.w else e.x = (cx + 1) * 16 end
  return cx, cy, c
end

-- moves e.y by dy. Going down it also lands on one-way platforms ('=') when the box's feet were above them (and e.drop is not set).
-- Returns cx, cy, char of the cell that stopped it, or nil.
function P.move_y(e, dy)
  if dy == 0 then return nil end
  local ny = e.y + dy
  if dy > 0 then
    local feet0, feet1 = e.y + e.h, ny + e.h
    local x0, x1 = math.floor(e.x) // 16, math.floor(e.x + e.w - 0.01) // 16
    local best
    for cy = math.floor(feet0 - 0.01) // 16, math.floor(feet1 - 0.01) // 16 do
      for cx = x0, x1 do
        local c = W.cell(cx, cy)
        if SOLID[c] or (c == "=" and not (e.drop and e.drop > 0) and feet0 <= cy * 16 + 0.01) then
          if not best or cy < best[2] then best = {cx, cy, c} end
        end
      end
    end
    local pl_y
    for _, pl in ipairs(P.platforms) do
      if (e.drop or 0) <= 0 and feet0 <= pl.y + 0.01 and feet1 >= pl.y and e.x + e.w > pl.x and e.x < pl.x + pl.w and (not pl_y or pl.y < pl_y) then pl_y = pl.y end
    end
    if pl_y and (not best or pl_y < best[2] * 16) then
      e.y = pl_y - e.h
      return -1, -1, "="
    end
    if best then
      e.y = best[2] * 16 - e.h
      return best[1], best[2], best[3]
    end
    e.y = ny
    return nil
  end
  local cx, cy, c = P.hits_solid(e.x, ny, e.w, e.h)
  if not cx then e.y = ny return nil end
  e.y = (cy + 1) * 16
  return cx, cy, c
end

-- is there ground under the box's feet (within `d` pixels)?
function P.grounded(e, d)
  d = d or 1
  local x0, x1 = math.floor(e.x) // 16, math.floor(e.x + e.w - 0.01) // 16
  local fy = math.floor(e.y + e.h + d - 0.01)
  for cx = x0, x1 do
    local c = W.cell(cx, fy // 16)
    if SOLID[c] then return true, c end
    if c == "=" and (e.drop or 0) <= 0 and e.y + e.h <= (fy // 16) * 16 + 0.01 then return true, c end
  end
  for _, pl in ipairs(P.platforms) do
    if (e.drop or 0) <= 0 and e.x + e.w > pl.x and e.x < pl.x + pl.w and e.y + e.h <= pl.y + 0.01 and e.y + e.h + d >= pl.y then return true, "=" end
  end
  return false
end

function P.overlap(ax, ay, aw, ah, bx, by, bw, bh)
  return ax < bx + bw and bx < ax + aw and ay < by + bh and by < ay + ah
end

return P
