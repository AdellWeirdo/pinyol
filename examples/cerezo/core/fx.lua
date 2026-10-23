-- fx: what makes a hit feel like one: a screen that shakes, a game that stops for a moment, a puff of dust, a spark.
-- Particles are sprites of the UI8 sheet that live a few ticks; the cap keeps them well inside the console's sprites.
local W = require("core.world")
local S = require("core.spr")
local E = require("core.ents")
local FX = {}

FX.freeze_t = 0     -- ticks the world stands still (hit stop)
local shake_t, shake_amp = 0, 0
local MAX_PARTS = 24
local parts = 0

function FX.freeze(n) if n > FX.freeze_t then FX.freeze_t = n end end

function FX.shake(amp, ticks)
  if settings().reduce_flashing then amp = math.min(amp, 1) end -- less movement for whoever asked for less flashing
  shake_amp, shake_t = amp, ticks
end

function FX.update()
  if shake_t > 0 then
    shake_t = shake_t - 1
    local a = shake_amp * shake_t / math.max(1, shake_t + 1)
    W.shake_x = (ticks() % 2 == 0 and 1 or -1) * math.floor(a + 0.5)
    W.shake_y = shake_t % 3 == 0 and 1 or 0
    if shake_t == 0 then W.shake_x, W.shake_y = 0, 0 end
  end
end

-- a particle: a sprite of UI8 (or another sheet) that plays `frames` in order, drifting; gone at the end
-- opts: x, y (area px, the sprite's top-left), vx, vy, frames {"dust_0", ...}, speed (ticks a frame), sheet, grav, life
function FX.particle(o)
  if parts >= MAX_PARTS then return end
  parts = parts + 1
  local p = {kind = "fx", x = o.x, y = o.y, vx = o.vx or 0, vy = o.vy or 0, frames = o.frames, speed = o.speed or 4,
             sheet = o.sheet or "UI8", grav = o.grav or 0, t = 0, life = o.life or (#o.frames * (o.speed or 4)), sort = o.sort or 40,
             hy = 0}
  function p.update(self)
    self.t = self.t + 1
    self.x, self.y = self.x + self.vx, self.y + self.vy
    self.vy = self.vy + self.grav
    if self.t >= self.life then self.dead = true parts = parts - 1 end
  end
  function p.draw(self)
    local sx, sy = W.to_screen(self.x, self.y)
    S.draw(self.sheet, self.frames[math.min(#self.frames, self.t // self.speed + 1)], sx, sy, {prio = 1})
  end
  return E.add(p)
end

function FX.clear() parts = 0 end

-- the usual bursts
function FX.dust(x, y) FX.particle({x = x - 4, y = y - 4, vy = -0.2, frames = {"dust_0", "dust_1", "dust_2"}, speed = 4}) end
function FX.poof(x, y) FX.particle({x = x - 4, y = y - 4, frames = {"poof_0", "poof_1", "poof_2", "poof_3"}, speed = 3}) end
function FX.spark(x, y) FX.particle({x = x - 4, y = y - 4, frames = {"spark_0", "spark_1", "spark_2"}, speed = 3}) end
function FX.splash(x, y) FX.particle({x = x - 4, y = y - 4, frames = {"splash_0", "splash_1", "splash_2"}, speed = 4}) end
function FX.leaves(x, y, n)
  for i = 1, n or 3 do
    FX.particle({x = x - 4 + (i - 2) * 3, y = y - 4, vx = (i - 2) * 0.5, vy = -1.2, grav = 0.12, frames = {"leaf_0", "leaf_1"}, speed = 5,
                 life = 18})
  end
end

return FX
