-- interact: A in front of something. Anything with an `interact(self, hero)` function and a box can be spoken to, read
-- or opened; the nearest one to the point he looks at answers.
local U = require("core.util")
local W = require("core.world")
local E = require("core.ents")
local I = {}

function I.try(h)
  local d = U.DIRS[h.face]
  local fx, fy = h.x + 8 + d[1] * 10, h.y + 11 + d[2] * 10
  local best, bd
  for _, e in ipairs(E.list) do
    if e.interact and not e.dead then
      local bx, by = e.ix or (e.x + (e.hx or 0)), e.iy or (e.y + (e.hy or 0))
      local bw, bh = e.iw or e.hw or 16, e.ih or e.hh or 16
      if U.overlap(fx - 6, fy - 6, 12, 12, bx, by, bw, bh) then
        local dd = U.dist(fx, fy, bx + bw / 2, by + bh / 2)
        if not bd or dd < bd then best, bd = e, dd end
      end
    end
  end
  if best then
    best:interact(h)
    return true
  end
  return false
end

-- after a dig: what was buried there, if anything, comes out
function I.dug(gx, gy)
  local Rewards = require("core.rewards")
  for _, def in ipairs(W.area.things) do
    if def.kind == "buried" and def.cx == gx and def.cy == gy then
      Rewards.buried(def, gx * 16 + 8, gy * 16 + 8)
    end
  end
end

return I
