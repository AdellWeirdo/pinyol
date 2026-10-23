-- pickups: what lies on the ground to be picked up: a heart, a cherry, a bundle of pinyoles. They bob, last a while,
-- blink before they go, and are taken by touch.
local W = require("core.world")
local S = require("core.spr")
local E = require("core.ents")
local U = require("core.util")
local Game = require("core.game")
local Sound = require("core.sound")
local P = {}

local KINDS = {
  heart = {frame = "heart_pickup", take = function() Game.heal(2) end, sfx = "heart"},
  cherry = {frame = "cherry_pickup", take = function() Game.add_cherries(1) end, sfx = "cherry"},
  cherries = {frame = "cherry_pickup", take = function() Game.add_cherries(5) end, sfx = "cherry"},
  pinyoles = {frame = "pinyol_pickup", take = function() Game.add_pinyoles(5) end, sfx = "cherry"},
}

-- a pickup of `what` whose middle is at x, y; `still` ones do not expire (the ones a chest or a quest gives)
function P.drop(what, x, y, still)
  local k = KINDS[what]
  if not k then return nil end
  local p = {kind = "pickup", what = what, x = x - 4, y = y - 4, t = 0, life = still and 99999 or 480, hx = 0, hy = 0, hw = 8, hh = 8, sort = 6,
             vy = -1.6, z = 0}
  function p.update(self)
    self.t = self.t + 1
    if self.vy then
      self.z = self.z - self.vy
      self.vy = self.vy + 0.18
      if self.z <= 0 then self.z, self.vy = 0, nil end
    end
    if self.t >= self.life then self.dead = true return end
    local h = E.hero
    if h and h.state ~= "dead" and U.overlap(self.x, self.y, 8, 8, h.x + 3, h.y + 5, 10, 10) then
      k.take()
      Sound.play(k.sfx)
      self.dead = true
    end
  end
  function p.draw(self)
    if self.life - self.t < 90 and (self.t // 3) % 2 == 0 then return end
    local sx, sy = W.to_screen(self.x, self.y - self.z)
    S.draw("UI8", k.frame, sx, sy + (self.vy == nil and math.floor(math.sin(self.t / 8) + 0.5) or 0))
  end
  return E.add(p)
end

-- what a thing that breaks or an enemy leaves, by chance: {{what, weight}, ...} with nothing the rest of the way to 100
function P.roll(table_, x, y)
  local r = math.random(100)
  local acc = 0
  for _, d in ipairs(table_) do
    acc = acc + d[2]
    if r <= acc then return P.drop(d[1], x, y) end
  end
  return nil
end

return P
