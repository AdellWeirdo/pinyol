-- physics: things that fall, bounce, slide and hit each other; ropes and sticks between them.
-- Bodies are circles or boxes (boxes do not turn), moving or static (floors, walls, platforms). Each step adds
-- gravity, moves them, pushes overlapping ones apart with their bounce and friction, and pulls ropes taut.
--
--   local physics = require("physics")
--   local w = physics.world({gravity = 0.25})
--   local ball = w:circle(100, 40, 12, {bounce = 0.7})       -- x, y: the centre
--   w:box(0, 300, 480, 20, {static = true})                  -- x, y: the top-left corner
--   w:rope(ball, w:circle(200, 40, 8), 80)                   -- at most 80 apart; {stick = true}: exactly
--   in _update: w:step()     then draw from ball.x, ball.y (and b.w, b.h for a box, b.r for a circle)
--   w:hits() -> {{a, b, speed}, ...}: what hit what in the last step, and how hard (sounds, sparks, damage)
--   w:at(x, y) -> the body there (to drag it with a finger); w:remove(body); body.data: anything of the game's
--
-- Options of a body: bounce (0..1, 0.3), friction (0..1, 0.4), static, mass (the area by default).
-- It is simple on purpose (no turning, no stacking of hundreds): enough for toys, puzzles and arcade games of up
-- to about 60 bodies on the console.
local M = {}
local World = {}
World.__index = World

local SUBSTEPS = 2

function M.world(o)
  o = o or {}
  return setmetatable({gravity = o.gravity or 0.25, bodies = {}, ropes = {}, last_hits = {}}, World)
end

local function add(w, b, o)
  o = o or {}
  b.vx, b.vy = o.vx or 0, o.vy or 0
  b.bounce, b.friction, b.static = o.bounce or 0.3, o.friction or 0.4, o.static or false
  local mass = o.mass or (b.r and math.pi * b.r * b.r or b.w * b.h)
  b.inv = b.static and 0 or 1 / math.max(mass, 0.001)
  w.bodies[#w.bodies + 1] = b
  return b
end

function World:circle(x, y, r, o) return add(self, {kind = "circle", x = x, y = y, r = math.max(1, r)}, o) end
function World:box(x, y, w, h, o) return add(self, {kind = "box", x = x, y = y, w = math.max(1, w), h = math.max(1, h)}, o) end

function World:rope(a, b, len, o)
  o = o or {}
  local r = {a = a, b = b, len = len, stick = o.stick or false, stiff = o.stiff or 0.8}
  self.ropes[#self.ropes + 1] = r
  return r
end

function World:remove(body)
  for i = #self.bodies, 1, -1 do if self.bodies[i] == body then table.remove(self.bodies, i) end end
  for i = #self.ropes, 1, -1 do
    if self.ropes[i].a == body or self.ropes[i].b == body or self.ropes[i] == body then table.remove(self.ropes, i) end
  end
end

local function centre(b)
  if b.kind == "circle" then return b.x, b.y end
  return b.x + b.w / 2, b.y + b.h / 2
end

local function bounds(b)
  if b.kind == "circle" then return b.x - b.r, b.y - b.r, b.x + b.r, b.y + b.r end
  return b.x, b.y, b.x + b.w, b.y + b.h
end

-- how a overlaps b: the direction to push b away from a (nx, ny) and how deep; nil if they do not touch
local function contact(a, b)
  if a.kind == "box" and b.kind == "circle" then
    local nx, ny, d = contact(b, a)
    if nx then return -nx, -ny, d end
    return nil
  end
  if a.kind == "circle" and b.kind == "circle" then
    local dx, dy = b.x - a.x, b.y - a.y
    local dist, sum = math.sqrt(dx * dx + dy * dy), a.r + b.r
    if dist >= sum then return nil end
    if dist < 1e-6 then return 0, -1, sum end
    return dx / dist, dy / dist, sum - dist
  end
  if a.kind == "circle" then -- a circle against a box: from the box's nearest point
    local px = math.max(b.x, math.min(a.x, b.x + b.w))
    local py = math.max(b.y, math.min(a.y, b.y + b.h))
    local dx, dy = px - a.x, py - a.y
    local d2 = dx * dx + dy * dy
    if d2 >= a.r * a.r then return nil end
    if d2 > 1e-9 then
      local dist = math.sqrt(d2)
      return dx / dist, dy / dist, a.r - dist
    end
    -- the centre is inside the box: out by the nearest side
    local left, right, top, bottom = a.x - b.x, b.x + b.w - a.x, a.y - b.y, b.y + b.h - a.y
    local m = math.min(left, right, top, bottom)
    if m == top then return 0, 1, top + a.r end
    if m == bottom then return 0, -1, bottom + a.r end
    if m == left then return 1, 0, left + a.r end
    return -1, 0, right + a.r
  end
  -- two boxes: by the axis they overlap least on
  local ox = math.min(a.x + a.w, b.x + b.w) - math.max(a.x, b.x)
  local oy = math.min(a.y + a.h, b.y + b.h) - math.max(a.y, b.y)
  if ox <= 0 or oy <= 0 then return nil end
  local ax, ay = centre(a)
  local bx, by = centre(b)
  if ox < oy then return bx >= ax and 1 or -1, 0, ox end
  return 0, by >= ay and 1 or -1, oy
end

local function resolve(w, a, b)
  local nx, ny, depth = contact(a, b)
  if not nx then return end
  local im = a.inv + b.inv
  if im == 0 then return end
  local push = math.max(depth - 0.01, 0) / im * 0.9 -- apart, by how light each is
  a.x, a.y = a.x - nx * push * a.inv, a.y - ny * push * a.inv
  b.x, b.y = b.x + nx * push * b.inv, b.y + ny * push * b.inv
  local rvx, rvy = b.vx - a.vx, b.vy - a.vy
  local vn = rvx * nx + rvy * ny
  if vn >= 0 then return end -- already parting
  local e = math.min(a.bounce, b.bounce)
  if -vn < 0.4 then e = 0 end -- resting: no endless tiny bounces
  local j = -(1 + e) * vn / im
  a.vx, a.vy = a.vx - j * nx * a.inv, a.vy - j * ny * a.inv
  b.vx, b.vy = b.vx + j * nx * b.inv, b.vy + j * ny * b.inv
  local tx, ty = rvx - vn * nx, rvy - vn * ny -- friction, along the surface
  local tl = math.sqrt(tx * tx + ty * ty)
  if tl > 1e-6 then
    tx, ty = tx / tl, ty / tl
    local jt = math.max(-j * math.sqrt(a.friction * b.friction), math.min(j * math.sqrt(a.friction * b.friction),
                        -(rvx * tx + rvy * ty) / im))
    a.vx, a.vy = a.vx - jt * tx * a.inv, a.vy - jt * ty * a.inv
    b.vx, b.vy = b.vx + jt * tx * b.inv, b.vy + jt * ty * b.inv
  end
  if -vn > 0.5 then w.hits_now[#w.hits_now + 1] = {a, b, -vn} end
end

local function pull(r) -- a rope: never further than its length (a stick: always exactly)
  local a, b = r.a, r.b
  local ax, ay = centre(a)
  local bx, by = centre(b)
  local dx, dy = bx - ax, by - ay
  local d = math.sqrt(dx * dx + dy * dy)
  local im = a.inv + b.inv
  if d < 1e-6 or im == 0 or (not r.stick and d <= r.len) then return end
  local nx, ny, off = dx / d, dy / d, (d - r.len) * r.stiff / im
  a.x, a.y = a.x + nx * off * a.inv, a.y + ny * off * a.inv
  b.x, b.y = b.x - nx * off * b.inv, b.y - ny * off * b.inv
  local vn = (b.vx - a.vx) * nx + (b.vy - a.vy) * ny -- and their speeds along it agree
  if r.stick or vn > 0 then
    local j = vn / im
    a.vx, a.vy = a.vx + j * nx * a.inv, a.vy + j * ny * a.inv
    b.vx, b.vy = b.vx - j * nx * b.inv, b.vy - j * ny * b.inv
  end
end

function World:step()
  self.hits_now = {}
  local bodies = self.bodies
  for _ = 1, SUBSTEPS do
    for _, b in ipairs(bodies) do
      if b.inv > 0 then
        b.vy = b.vy + self.gravity / SUBSTEPS
        b.x, b.y = b.x + b.vx / SUBSTEPS, b.y + b.vy / SUBSTEPS
      end
    end
    local box = {}
    for i, b in ipairs(bodies) do box[i] = {bounds(b)} end
    for i = 1, #bodies do
      local a, ba = bodies[i], box[i]
      for j = i + 1, #bodies do
        local b, bb = bodies[j], box[j]
        if (a.inv > 0 or b.inv > 0) and ba[1] < bb[3] and bb[1] < ba[3] and ba[2] < bb[4] and bb[2] < ba[4] then
          resolve(self, a, b)
        end
      end
    end
    for _, r in ipairs(self.ropes) do pull(r) end
  end
  self.last_hits = self.hits_now
end

function World:hits() return self.last_hits end

function World:at(x, y)
  for i = #self.bodies, 1, -1 do
    local b = self.bodies[i]
    if b.kind == "circle" then
      if (x - b.x) ^ 2 + (y - b.y) ^ 2 <= b.r * b.r then return b end
    elseif x >= b.x and x < b.x + b.w and y >= b.y and y < b.y + b.h then
      return b
    end
  end
end

return M
