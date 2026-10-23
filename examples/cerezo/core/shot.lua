-- shot: a pinyol fired from the tirachinas. It flies straight, stops on a wall, and hurts the first enemy it meets.
local C = require("core.const")
local W = require("core.world")
local S = require("core.spr")
local E = require("core.ents")
local Combat = require("core.combat")
local FX = require("core.fx")
local Sound = require("core.sound")
local U = require("core.util")
local Shot = {}

function Shot.new(x, y, vx, vy)
  local s = {kind = "shot", x = x, y = y, vx = vx, vy = vy, t = 0, sort = 12}
  s.dir = U.dir_of(vx, vy)
  function s.update(self)
    self.t = self.t + 1
    self.x, self.y = self.x + self.vx, self.y + self.vy
    local gx, gy = math.floor((self.x + 4) / C.T), math.floor((self.y + 4) / C.T)
    local f = W.cell_flags(gx, gy)
    if not f or f.solid then
      if f and f.switch then require("core.switches").hit(gx, gy) end
      FX.spark(self.x + 4, self.y + 4)
      self.dead = true
      return
    end
    if Combat.strike(self.x, self.y, 8, 8, 1, self.dir, nil, self) then
      FX.spark(self.x + 4, self.y + 4)
      self.dead = true
      return
    end
    if self.t > 80 then self.dead = true end
  end
  function s.draw(self)
    local sx, sy = W.to_screen(self.x, self.y)
    S.draw("UI8", "shot_pinyol", sx, sy, {flip = self.dir == "left"})
  end
  return E.add(s)
end

return Shot
