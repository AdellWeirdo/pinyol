-- proj: what enemies throw: spores, stingers, clods of earth, rocks. It flies, may arc, hurts the hero once, and stops on
-- a wall (or is blocked by the pala when `parry`: a clod can be knocked back).
local C = require("core.const")
local U = require("core.util")
local W = require("core.world")
local S = require("core.spr")
local E = require("core.ents")
local FX = require("core.fx")
local Hero = require("core.hero")
local Proj = {}

-- o: x, y (the sprite's top-left), vx, vy, sheet, frames {names}, speed (ticks a frame), dmg, life, gravity (an arc),
--    size (hitbox side), through (flies over walls), on_land(self) (what a lobbed one does when it lands)
function Proj.new(o)
  local p = {kind = "proj", team = "enemy_proj", x = o.x, y = o.y, vx = o.vx or 0, vy = o.vy or 0, t = 0, dmg = o.dmg or 1,
             sheet = o.sheet or "MON", frames = o.frames, fspeed = o.speed or 6, life = o.life or 120, grav = o.gravity or 0,
             size = o.size or 6, through = o.through, on_land = o.on_land, sort = 20, z = o.z or 0, vz = o.vz or 0}
  function p.update(self)
    self.t = self.t + 1
    self.x, self.y = self.x + self.vx, self.y + self.vy
    if self.grav ~= 0 then -- lobbed: z is the height above the ground, the ground point keeps moving
      self.z = self.z + self.vz
      self.vz = self.vz - self.grav
      if self.z <= 0 and self.t > 2 then
        if self.on_land then self.on_land(self) end
        self.dead = true
        return
      end
    end
    if not self.through then
      local gx, gy = math.floor((self.x + 4) / C.T), math.floor((self.y + 4) / C.T)
      local f = W.cell_flags(gx, gy)
      if not f or f.solid then
        FX.spark(self.x + 4, self.y + 4)
        self.dead = true
        return
      end
    end
    local h = E.hero
    if h and h.state ~= "dead" and (self.grav == 0 or self.z < 6) and
       U.overlap(self.x, self.y - (self.z or 0) * 0, self.size, self.size, h.x + 4, h.y + 5, 8, 10) then
      if Hero.hurt(h, self.dmg, self.x + 4, self.y + 4) then self.dead = true end
    end
    if self.t >= self.life then self.dead = true end
  end
  function p.draw(self)
    local sx, sy = W.to_screen(self.x, self.y - (self.z or 0))
    S.draw(self.sheet, self.frames[(self.t // self.fspeed) % #self.frames + 1], sx, sy)
  end
  return E.add(p)
end

return Proj
