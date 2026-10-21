-- move: how a platformer's bodies move, the way Celeste and TowerFall do it (Maddy Thorson, "Celeste and TowerFall
-- physics", "Celeste and forgiveness"): actors (the hero, enemies, things that fall) move a whole pixel at a time
-- against solids, keeping the fraction for later; solids (walls, floors, moving platforms) are never inside an actor:
-- a solid that moves carries the actors riding it and pushes the ones in its way. On top, a platformer with the
-- forgiveness players never notice and always feel: coyote time (a jump a few ticks after leaving a ledge), a jump
-- buffered before landing, a variable jump (let go early: a short one), half gravity at the top of the jump while
-- the button is held, corners nudged round (a head that clips a block's edge slides past), one-way platforms.
--
--   local move = require("move")
--   local function solid(x, y, w, h) return any solid tile under the box x, y, w, h end   -- the level's walls
--   hero = move.actor(32, 100, 8, 14, {solid = solid, oneway = oneway})     -- a box; oneway(x, y, w, h): platforms to stand on
--   hero:move_x(dx, on_hit) hero:move_y(dy, on_hit)   -- by pixels (fractions kept); on_hit() when it stops on a solid
--   hero.ground = hero:on_ground()
--   lift = move.solid(100, 150, 48, 8)                -- a moving platform
--   lift:move(dx, dy)                                 -- carries whoever stands on it, pushes whoever is in the way
--   pl = move.platformer(hero, {speed = 2, accel = 0.3, jump = 4.2, gravity = 0.25, max_fall = 5, coyote = 6, buffer = 6,
--                              apex = 0.5, corner = 4})
--   in _update: pl:update(input.dir(), btnp("a"), btn("a"))   -- the direction held (-1, 0, 1), jump pressed, jump held
--   hero.x, hero.y are whole pixels; pl.state is "ground", "jump", "fall"; pl.jumped, pl.landed are true for a tick.
local M = {}

local Actor = {}
Actor.__index = Actor
local Solid = {}
Solid.__index = Solid
local actors, solids = {}, {}

local function overlaps(ax, ay, aw, ah, bx, by, bw, bh)
  return ax < bx + bw and bx < ax + aw and ay < by + bh and by < ay + ah
end

-- actor(x, y, w, h, {solid, oneway}): solid(x, y, w, h) says if a box touches the level's walls; oneway(x, y, w, h) if
-- it touches a platform that can be jumped through from below (only its top stops a fall)
function M.actor(x, y, w, h, opts)
  local a = setmetatable({x = math.floor(x), y = math.floor(y), w = w, h = h, rx = 0, ry = 0,
                          solid = opts and opts.solid, oneway = opts and opts.oneway}, Actor)
  actors[#actors + 1] = a
  return a
end

function Actor:remove()
  for i = #actors, 1, -1 do if actors[i] == self then table.remove(actors, i) end end
end

-- is the box at (x, y) blocked? by the level, or by a solid body; moving down, by a one-way platform whose top is
-- at or below the feet's last place
function Actor:blocked(x, y, dy)
  if self.solid and self.solid(x, y, self.w, self.h) then return true end
  for _, s in ipairs(solids) do
    if s.on and overlaps(x, y, self.w, self.h, s.x, s.y, s.w, s.h) then return true end
  end
  if dy and dy > 0 and self.oneway and self.oneway(x, y + self.h - 1, self.w, 1) and not self.oneway(x, y + self.h - 2, self.w, 1) then
    return true -- the feet cross a platform's top this pixel
  end
  return false
end

function Actor:move_x(dx, on_hit)
  self.rx = self.rx + dx
  local n = math.floor(self.rx + 0.5)
  if n == 0 then return true end
  self.rx = self.rx - n
  local step = n > 0 and 1 or -1
  while n ~= 0 do
    if self:blocked(self.x + step, self.y) then
      self.rx = 0
      if on_hit then on_hit(self, step, 0) end
      return false
    end
    self.x, n = self.x + step, n - step
  end
  return true
end

function Actor:move_y(dy, on_hit)
  self.ry = self.ry + dy
  local n = math.floor(self.ry + 0.5)
  if n == 0 then return true end
  self.ry = self.ry - n
  local step = n > 0 and 1 or -1
  while n ~= 0 do
    if self:blocked(self.x, self.y + step, step) then
      self.ry = 0
      if on_hit then on_hit(self, 0, step) end
      return false
    end
    self.y, n = self.y + step, n - step
  end
  return true
end

function Actor:on_ground() return self:blocked(self.x, self.y + 1, 1) end

function Actor:riding(s) -- standing on that solid
  return self.x < s.x + s.w and s.x < self.x + self.w and self.y + self.h == s.y
end

-- solid(x, y, w, h): a body actors never overlap; s.on = false lets them through (a door opened)
function M.solid(x, y, w, h)
  local s = setmetatable({x = math.floor(x), y = math.floor(y), w = w, h = h, rx = 0, ry = 0, on = true}, Solid)
  solids[#solids + 1] = s
  return s
end

function Solid:remove()
  for i = #solids, 1, -1 do if solids[i] == self then table.remove(solids, i) end end
end

-- move(dx, dy): carries the actors riding it, pushes the ones it runs into (they are squashed if pushed into a wall:
-- on_squash(actor) if given, else they are left overlapping)
function Solid:move(dx, dy, on_squash)
  self.rx, self.ry = self.rx + dx, self.ry + dy
  local mx, my = math.floor(self.rx + 0.5), math.floor(self.ry + 0.5)
  if mx == 0 and my == 0 then return end
  self.rx, self.ry = self.rx - mx, self.ry - my
  local riders = {}
  for _, a in ipairs(actors) do if a:riding(self) then riders[a] = true end end
  self.on = false -- out of the way while they are moved, so a carried actor does not collide with its carrier
  local ox, oy = self.x, self.y
  self.x, self.y = self.x + mx, self.y + my
  for _, a in ipairs(actors) do
    if riders[a] then
      a:move_x(mx) a:move_y(my)
    elseif overlaps(a.x, a.y, a.w, a.h, self.x, self.y, self.w, self.h) then -- in the way: pushed out
      if mx ~= 0 then
        local push = mx > 0 and (self.x + self.w - a.x) or (self.x - (a.x + a.w))
        if not a:move_x(push) and on_squash then on_squash(a) end
      end
      if my ~= 0 then
        local push = my > 0 and (self.y + self.h - a.y) or (self.y - (a.y + a.h))
        if not a:move_y(push) and on_squash then on_squash(a) end
      end
    end
  end
  self.on = true
  local _ = ox + oy
end

-- platformer(actor, opts): the hero's run and jump with every forgiveness
local Platformer = {}
Platformer.__index = Platformer

function M.platformer(actor, opts)
  opts = opts or {}
  return setmetatable({
    a = actor, vx = 0, vy = 0, state = "fall", coyote = 0, buffer = 0, holding = false, jumped = false, landed = false,
    speed = opts.speed or 2, accel = opts.accel or 0.3, decel = opts.decel or opts.accel or 0.4, air_accel = opts.air_accel,
    jump = opts.jump or 4.2, gravity = opts.gravity or 0.25, max_fall = opts.max_fall or 5,
    coyote_ticks = opts.coyote or 6, buffer_ticks = opts.buffer or 6, apex = opts.apex or 0.5, apex_speed = opts.apex_speed or 0.6,
    corner = opts.corner or 4, cut = opts.cut or 0.4,
  }, Platformer)
end

-- a head about to hit a block's edge is nudged sideways round it (up to `corner` pixels), the jump kept
function Platformer:nudge_corner()
  local a = self.a
  for d = 1, self.corner do
    for _, side in ipairs({d, -d}) do
      if not a:blocked(a.x + side, a.y - 1) and not a:blocked(a.x + side, a.y) then
        a.x = a.x + side
        return true
      end
    end
  end
  return false
end

function Platformer:update(dir, jump_pressed, jump_held)
  local a = self.a
  self.jumped, self.landed = false, false
  local on_ground = a:on_ground()
  if on_ground then self.coyote = self.coyote_ticks elseif self.coyote > 0 then self.coyote = self.coyote - 1 end
  if jump_pressed then self.buffer = self.buffer_ticks elseif self.buffer > 0 then self.buffer = self.buffer - 1 end
  -- run: towards dir, with its own acceleration (and less in the air), braking faster than it starts
  local target = (dir or 0) * self.speed
  local accel = on_ground and self.accel or (self.air_accel or self.accel)
  if target == 0 or (target > 0) ~= (self.vx > 0) then accel = on_ground and self.decel or accel end
  if self.vx < target then self.vx = math.min(self.vx + accel, target)
  elseif self.vx > target then self.vx = math.max(self.vx - accel, target) end
  -- jump: from the ground or just off it, pressed now or a moment before landing
  if self.buffer > 0 and self.coyote > 0 then
    self.vy, self.coyote, self.buffer, self.holding, self.jumped = -self.jump, 0, 0, true, true
    self.state = "jump"
    on_ground = false
  end
  if not jump_held then self.holding = false end
  -- gravity: half at the top of a held jump (a floaty apex), and the jump cut short when the button is let go
  local g = self.gravity
  if self.vy < 0 and not self.holding then self.vy = self.vy * self.cut; self.holding = nil end
  if self.vy ~= 0 and math.abs(self.vy) < self.apex_speed and jump_held then g = g * self.apex end
  if not on_ground then self.vy = math.min(self.vy + g, self.max_fall) else if self.vy > 0 then self.vy = 0 end end
  -- the move, a pixel at a time
  a:move_x(self.vx, function() self.vx = 0 end)
  local was_falling = self.vy > 0
  a:move_y(self.vy, function(_, _, step)
    if step < 0 and self:nudge_corner() then return end -- round the corner, the jump goes on
    if step > 0 then self.landed = not on_ground end
    self.vy = 0
  end)
  if self.vy == 0 and was_falling and a:on_ground() then self.landed = true end
  local ground_now = a:on_ground()
  self.state = ground_now and "ground" or (self.vy < 0 and "jump" or "fall")
  if ground_now and self.vy > 0 then self.vy = 0 end
end

function M.reset() actors, solids = {}, {} end
function M.actors() return actors end
function M.solids() return solids end

return M
