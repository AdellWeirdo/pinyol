-- checks: what the tests prove about the castle, kept with it so that a room changed in Tiled is checked by the same code (tests/cripta.script).
local W = require("world")

local M = {}

local function count(t) local n = 0 for _ in pairs(t) do n = n + 1 end return n end

-- every open tile on a room's edge has an open tile of another room beyond it: a list of the ones that do not ("room tx,ty")
function M.bad_edges()
  local bad = {}
  for _, id in ipairs(W.order) do
    local r = W.rooms[id]
    for ty = 0, r.h - 1 do
      for tx = 0, r.w - 1 do
        local edge = tx == 0 or ty == 0 or tx == r.w - 1 or ty == r.h - 1
        if edge and W.cell(r, tx, ty) ~= W.WALL then
          local wx, wy = W.world_tile(r, tx, ty)
          local outs = {}
          if tx == 0 then outs[#outs + 1] = {wx - 1, wy} end
          if tx == r.w - 1 then outs[#outs + 1] = {wx + 1, wy} end
          if ty == 0 then outs[#outs + 1] = {wx, wy - 1} end
          if ty == r.h - 1 then outs[#outs + 1] = {wx, wy + 1} end
          for _, o in ipairs(outs) do
            local nr = W.room_at(o[1], o[2])
            if not nr or nr == r or W.wcell(o[1], o[2]) == W.WALL then bad[#bad + 1] = id .. " " .. tx .. "," .. ty end
          end
        end
      end
    end
  end
  return bad
end

-- the tiles the hero can get to from (x, y) with these abilities, from which it cannot get back to (x, y): a trap. One search forward, and one
-- backward over the same moves from (x, y).
function M.traps(x, y, ab)
  local seen, back = W.reach(x, y, ab, W.REACH_CELLS)
  local home, queue, head = {[y * 1000 + x] = true}, {y * 1000 + x}, 1
  while head <= #queue do
    local k = queue[head]
    head = head + 1
    for f in pairs(back[k] or {}) do
      if not home[f] then home[f] = true queue[#queue + 1] = f end
    end
  end
  local n = 0
  for k in pairs(seen) do if not home[k] then n = n + 1 end end
  return n
end

M.count = count
return M
