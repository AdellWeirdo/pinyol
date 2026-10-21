-- chain: creatures made of a line of joints that follow a head (the worm, the snake, the dragon of the procedural
-- animation demos: each joint keeps its distance from the one before it and the bend between joints is held to an
-- angle, so the body curls and never folds), legs that step (a foot stays planted until it is too far behind, then
-- strides ahead), and the two solvers behind arms and legs: FABRIK (Aristidou and Lasenby, 2011) for any chain
-- reaching a point, and the two-bone solver for an arm or a leg with one elbow.
--
--   local chain = require("chain")
--   worm = chain.new(12, 8, {bend = 25})           -- 12 joints, 8 pixels apart, at most 25 degrees between links
--   worm:follow(x, y)                              -- the head goes there; the body follows
--   worm.points[i].x, .y, .angle                   -- each joint, to draw a circle, a segment of a sprite, a leg's hip
--   leg = chain.leg({hip = worm.points[3], len = 14, side = 1, stride = 20})
--   leg:update() leg.foot.x, leg.foot.y, leg.knee.x, leg.knee.y    -- the foot steps when the hip gets too far from it
--   chain.fabrik(points, lens, tx, ty [, iters])   -- points[1] stays; the chain bends to put its end at (tx, ty)
--   ex, ey = chain.two_bone(ax, ay, l1, l2, tx, ty [, flip])     -- the elbow of an arm from (ax, ay) to (tx, ty)
local M = {}
local C = {}
C.__index = C

function M.new(n, len, opts)
  opts = opts or {}
  local c = setmetatable({len = len, bend = (opts.bend or 180) * math.pi / 180, points = {}}, C)
  for i = 1, n do c.points[i] = {x = (opts.x or 0) - (i - 1) * len, y = opts.y or 0, angle = 0} end
  return c
end

local function wrap(a) return (a + math.pi) % (2 * math.pi) - math.pi end

function C:follow(x, y)
  local p = self.points
  p[1].x, p[1].y = x, y
  for i = 2, #p do
    local a, b = p[i - 1], p[i]
    local ang = math.atan(b.y - a.y, b.x - a.x)
    if i > 2 then -- the bend held: this link's direction within `bend` of the one before
      local prev = math.atan(a.y - p[i - 2].y, a.x - p[i - 2].x)
      local d = wrap(ang - prev)
      if d > self.bend then ang = prev + self.bend elseif d < -self.bend then ang = prev - self.bend end
    end
    b.x, b.y = a.x + math.cos(ang) * self.len, a.y + math.sin(ang) * self.len
    a.angle = ang
  end
  if #p > 1 then p[#p].angle = p[#p - 1].angle end
end

function M.two_bone(ax, ay, l1, l2, tx, ty, flip)
  local dx, dy = tx - ax, ty - ay
  local d = math.sqrt(dx * dx + dy * dy)
  d = math.max(math.abs(l1 - l2) + 0.001, math.min(l1 + l2 - 0.001, d))
  local a = math.acos(math.max(-1, math.min(1, (l1 * l1 + d * d - l2 * l2) / (2 * l1 * d))))
  local base = math.atan(dy, dx)
  local ang = base + (flip and -a or a)
  return ax + math.cos(ang) * l1, ay + math.sin(ang) * l1
end

function M.fabrik(points, lens, tx, ty, iters)
  local n = #points
  local total = 0
  for i = 1, n - 1 do total = total + lens[i] end
  local rx, ry = points[1].x, points[1].y
  local dx, dy = tx - rx, ty - ry
  if math.sqrt(dx * dx + dy * dy) >= total then -- out of reach: the chain straight at it
    local ang = math.atan(dy, dx)
    for i = 2, n do points[i].x, points[i].y = points[i - 1].x + math.cos(ang) * lens[i - 1], points[i - 1].y + math.sin(ang) * lens[i - 1] end
    return false
  end
  for _ = 1, iters or 8 do
    points[n].x, points[n].y = tx, ty -- backward: from the end to the root
    for i = n - 1, 1, -1 do
      local a, b = points[i], points[i + 1]
      local ddx, ddy = a.x - b.x, a.y - b.y
      local d = math.sqrt(ddx * ddx + ddy * ddy)
      if d > 0 then a.x, a.y = b.x + ddx / d * lens[i], b.y + ddy / d * lens[i] end
    end
    points[1].x, points[1].y = rx, ry -- forward: from the root to the end
    for i = 2, n do
      local a, b = points[i - 1], points[i]
      local ddx, ddy = b.x - a.x, b.y - a.y
      local d = math.sqrt(ddx * ddx + ddy * ddy)
      if d > 0 then b.x, b.y = a.x + ddx / d * lens[i - 1], a.y + ddy / d * lens[i - 1] end
    end
  end
  return true
end

-- leg({hip, len, side, stride, lift}): the foot stays planted while the hip's ideal foot place is within stride of it, then
-- steps there in a few ticks (lifting by `lift`); hip is a point {x, y, angle} (a chain joint); side 1 or -1, which side
-- of the body the foot sits on
local Leg = {}
Leg.__index = Leg
function M.leg(opts)
  local l = setmetatable({hip = opts.hip, len = opts.len or 12, side = opts.side or 1, stride = opts.stride or 16,
                          lift = opts.lift or 6, foot = {x = opts.hip.x, y = opts.hip.y + (opts.len or 12)}, knee = {x = 0, y = 0},
                          from = nil, t = 0, steps = 0}, Leg)
  return l
end
function Leg:target() -- where the foot would like to be: beside the hip, a little ahead
  local a = self.hip.angle or 0
  local side = a + self.side * math.pi / 2
  return self.hip.x + math.cos(side) * self.len * 0.8 + math.cos(a) * self.len * 0.3,
         self.hip.y + math.sin(side) * self.len * 0.8 + math.sin(a) * self.len * 0.3
end
function Leg:update()
  local tx, ty = self:target()
  local dx, dy = tx - self.foot.x, ty - self.foot.y
  if not self.from and dx * dx + dy * dy > self.stride * self.stride then -- too far behind: a step begins
    self.from, self.to, self.t = {x = self.foot.x, y = self.foot.y}, {x = tx, y = ty}, 0
    self.steps = self.steps + 1
  end
  if self.from then
    self.t = self.t + 0.25
    local k = math.min(1, self.t)
    self.foot.x = self.from.x + (self.to.x - self.from.x) * k
    self.foot.y = self.from.y + (self.to.y - self.from.y) * k - math.sin(k * math.pi) * self.lift
    if k >= 1 then self.from = nil end
  end
  self.knee.x, self.knee.y = M.two_bone(self.hip.x, self.hip.y, self.len * 0.55, self.len * 0.55, self.foot.x, self.foot.y, self.side < 0)
end

return M
