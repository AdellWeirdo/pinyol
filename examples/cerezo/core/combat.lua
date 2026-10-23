-- combat: who hits whom. A hit is a rectangle in the area's pixels; enemies are entities with team = "enemy" and a
-- `hit(self, dmg, from_dir, source)` function; the hero is hurt through hero.hurt.
local U = require("core.util")
local E = require("core.ents")
local C = {}

-- the box of an entity that can be hurt: hurtbox if it has one, else its sprite's square
function C.box(e)
  return e.x + (e.bx or 0), e.y + (e.by or 0), e.bw or 16, e.bh or 16
end

-- every enemy inside the rectangle gets hit once per swing (`seen` is the swing's own list)
function C.strike(x, y, w, h, dmg, dir, seen, source)
  local any = false
  for _, e in ipairs(E.list) do
    local only_shots = e.ranged_only and not (source and source.kind == "shot")
    if e.team == "enemy" and e.hit and not e.dead and not only_shots and not (seen and seen[e]) then
      local bx, by, bw, bh = C.box(e)
      if U.overlap(x, y, w, h, bx, by, bw, bh) then
        if seen then seen[e] = true end
        e:hit(dmg, dir, source)
        any = true
      end
    end
  end
  return any
end

-- does an enemy touch the hero's body? (his hurtbox is a little smaller than his sprite)
function C.touches_hero(e, hero)
  local ex, ey, ew, eh = C.box(e)
  return U.overlap(ex, ey, ew, eh, hero.x + 4, hero.y + 4, 8, 11)
end

return C
