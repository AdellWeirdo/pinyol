-- physics: things that fall, bounce, slide, turn and hit each other; ropes and sticks between them; water.
-- Bodies are circles, boxes or convex polygons, moving or static (floors, walls, platforms, rocks). Each step adds
-- gravity, moves them, pushes overlapping ones apart with their bounce and friction, and pulls ropes taut.
-- Boxes and circles keep their angle unless made with {turns = true}; polygons always turn (unless static).
--
--   local physics = require("physics")
--   local w = physics.world({gravity = 0.25})
--   local ball = w:circle(100, 40, 12, {bounce = 0.7})       -- x, y: the centre
--   w:box(0, 300, 480, 20, {static = true})                  -- x, y: the top-left corner
--   w:rope(ball, w:circle(200, 40, 8), 80)                   -- at most 80 apart; {stick = true}: exactly
--   in _update: w:step()     then draw from ball.x, ball.y (and b.w, b.h for a box, b.r for a circle)
--   w:hits() -> {{a, b, speed}, ...}: what hit what in the last step, and how hard (sounds, sparks, damage)
--   w:at(x, y) -> the body there (to drag it with a finger); w:remove(body); body.data: anything of the game's
--   w:box(x, y, w, h, {turns = true}): it tips over and spins; draw it with img(id, b.x, b.y, {angle = b.angle})
--   w:circle(x, y, r, {turns = true}): it rolls (b.angle turns with it)
--   w:poly(x, y, {x0, y0, x1, y1, ...}, {...}): a convex shape around (x, y), its corners relative to it; b.x, b.y
--     become its centre of mass; w:corners(b) -> its corners on the screen now (to draw it with poly())
--   w:water(x, y, w, h, {lift, drag, flow_x, flow_y}): bodies in it float (lift 2: half under), slow down and
--     drift with the current; what floats tips back level
--
-- Options of a body: bounce (0..1, 0.3), friction (0..1, 0.4), static, mass (the area by default), turns, angle
-- (degrees), spin (degrees a tick). It is simple on purpose (no stacking of hundreds): enough for toys, puzzles
-- and arcade games of up to about 60 bodies on the console. Where something that turns touches anything is worked
-- out in C (physics_turning, src/lua_physics.c): in Lua it took the console 32 ms a tick for ten boxes.
local M = {}
local World = {}
World.__index = World

local SUBSTEPS = 2
local ITERATIONS = 4 -- passes over the contacts of turning bodies each substep: stacks settle
local BOUNCE_MIN = 1  -- px a tick: slower than this, turning bodies meet without bouncing
local PUSH_BACK, SLOP = 0.2, 0.1 -- the part of an overlap undone each substep, and what is let be
local DEG, RAD = 180 / math.pi, math.pi / 180
local sqrt, cos, sin, abs = math.sqrt, math.cos, math.sin, math.abs
local MAX_CORNERS = 16

function M.world(o)
  o = o or {}
  return setmetatable({gravity = o.gravity or 0.25, bodies = {}, ropes = {}, waters = {}, last_hits = {}, stamp = 0},
                      World)
end

local function add(w, b, o)
  o = o or {}
  b.vx, b.vy = o.vx or 0, o.vy or 0
  b.bounce, b.friction, b.static = o.bounce or 0.3, o.friction or 0.4, o.static or false
  local mass = o.mass or b.area or (b.r and math.pi * b.r * b.r or b.w * b.h)
  b.inv = b.static and 0 or 1 / math.max(mass, 0.001)
  if b.kind == "poly" or o.turns then -- it turns: its angle and spin, and how hard it is to turn (its inertia)
    b.turns, b.angle, b.spin = true, o.angle or 0, o.spin or 0
    local inertia = b.inertia or (b.r and mass * b.r * b.r / 2 or mass * (b.w * b.w + b.h * b.h) / 12)
    if b.inertia then inertia = b.inertia * mass / b.area end
    b.iinv = b.static and 0 or 1 / math.max(inertia, 0.001)
  else
    b.iinv = 0
  end
  w.bodies[#w.bodies + 1] = b
  return b
end

function World:circle(x, y, r, o) return add(self, {kind = "circle", x = x, y = y, r = math.max(1, r)}, o) end
function World:box(x, y, w, h, o) return add(self, {kind = "box", x = x, y = y, w = math.max(1, w), h = math.max(1, h)}, o) end

-- A convex polygon: the hull of the points given (relative to x, y), moved so that x, y is its centre of mass.
function World:poly(x, y, pts, o)
  local p = {}
  for i = 1, #pts - 1, 2 do p[#p + 1] = {pts[i], pts[i + 1]} end
  if #p < 3 then error("physics poly: three corners at least", 2) end
  table.sort(p, function(a, b) return a[1] < b[1] or (a[1] == b[1] and a[2] < b[2]) end)
  local hull = {} -- the convex hull, Andrew's monotone chain
  local function turn(o_, a, b) return (a[1] - o_[1]) * (b[2] - o_[2]) - (a[2] - o_[2]) * (b[1] - o_[1]) end
  for _, pass in ipairs({1, -1}) do
    local start = #hull
    for i = pass == 1 and 1 or #p, pass == 1 and #p or 1, pass do
      while #hull >= start + 2 and turn(hull[#hull - 1], hull[#hull], p[i]) <= 0 do hull[#hull] = nil end
      hull[#hull + 1] = p[i]
    end
    hull[#hull] = nil
  end
  if #hull < 3 then error("physics poly: its corners are on a line", 2) end
  if #hull > MAX_CORNERS then error("physics poly: " .. MAX_CORNERS .. " corners at most", 2) end
  local area, cx, cy, inertia = 0, 0, 0, 0
  for i = 1, #hull do
    local a, b = hull[i], hull[i % #hull + 1]
    local c = a[1] * b[2] - b[1] * a[2]
    area, cx, cy = area + c, cx + (a[1] + b[1]) * c, cy + (a[2] + b[2]) * c
  end
  cx, cy = cx / (3 * area), cy / (3 * area)
  local pts_ = {}
  for i = 1, #hull do pts_[#pts_ + 1] = hull[i][1] - cx; pts_[#pts_ + 1] = hull[i][2] - cy end
  for i = 1, #pts_ - 1, 2 do -- second moment about the centre, per unit of area density
    local j = i + 2 > #pts_ and 1 or i + 2
    local ax, ay, bx, by = pts_[i], pts_[i + 1], pts_[j], pts_[j + 1]
    local c = abs(ax * by - bx * ay)
    inertia = inertia + c * (ax * ax + ax * bx + bx * bx + ay * ay + ay * by + by * by) / 12
  end
  return add(self, {kind = "poly", x = x + cx, y = y + cy, pts = pts_, area = abs(area) / 2, inertia = inertia}, o)
end

-- Water: what is in it floats (lift: how strongly, 2 floats half under), slows down (drag, 0..1 a tick) and drifts
-- with its current (flow_x, flow_y: the speed it is carried at).
function World:water(x, y, w, h, o)
  o = o or {}
  local z = {x = x, y = y, w = w, h = h, lift = o.lift or 2, drag = o.drag or 0.05, flow_x = o.flow_x or 0,
             flow_y = o.flow_y or 0}
  self.waters[#self.waters + 1] = z
  return z
end

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
  for i = #self.waters, 1, -1 do if self.waters[i] == body then table.remove(self.waters, i) end end
end

local function centre(b)
  if b.kind ~= "box" then return b.x, b.y end
  return b.x + b.w / 2, b.y + b.h / 2
end

-- The corners of a box or polygon on the screen, for this substep (stamp): turned by its angle about its centre.
local function corners(b, stamp)
  if b._stamp == stamp and stamp then return b._v, b._n end
  local cx, cy = centre(b)
  local pts = b.pts
  if not pts then
    local hw, hh = b.w / 2, b.h / 2
    pts = {-hw, -hh, hw, -hh, hw, hh, -hw, hh}
  end
  local a = (b.angle or 0) * RAD
  local c, s = cos(a), sin(a)
  local v, nrm = b._v or {}, b._n or {}
  local n = #pts
  for i = 1, n - 1, 2 do
    local x, y = pts[i], pts[i + 1]
    v[i], v[i + 1] = cx + x * c - y * s, cy + x * s + y * c
  end
  for i = 1, n - 1, 2 do -- each edge's outward normal (from corner i to the next)
    local j = i + 2 > n and 1 or i + 2
    local ex, ey = v[j] - v[i], v[j + 1] - v[i + 1]
    local l = sqrt(ex * ex + ey * ey)
    local nx, ny = ey / l, -ex / l
    if (v[i] - cx) * nx + (v[i + 1] - cy) * ny < 0 then nx, ny = -nx, -ny end
    nrm[i], nrm[i + 1] = nx, ny
  end
  b._v, b._n, b._stamp = v, nrm, stamp
  return v, nrm
end

local function bounds(b, stamp)
  if b.kind == "circle" then return b.x - b.r, b.y - b.r, b.x + b.r, b.y + b.r end
  if not b.turns then return b.x, b.y, b.x + b.w, b.y + b.h end
  local v = corners(b, stamp)
  local x0, y0, x1, y1 = v[1], v[2], v[1], v[2]
  for i = 3, #v - 1, 2 do
    if v[i] < x0 then x0 = v[i] elseif v[i] > x1 then x1 = v[i] end
    if v[i + 1] < y0 then y0 = v[i + 1] elseif v[i + 1] > y1 then y1 = v[i + 1] end
  end
  return x0, y0, x1, y1
end

function World:corners(b) return (corners(b)) end

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

-- Bodies that turn: where two touch, the push between them, and the points it acts at.
local function inside(v, nrm, px, py)
  for i = 1, #v - 1, 2 do
    if (px - v[i]) * nrm[i] + (py - v[i + 1]) * nrm[i + 1] > 0.01 then return false end
  end
  return true
end

local function float(w, b, stamp) -- what water does to a body in it
  local x0, y0, x1, y1 = bounds(b, stamp)
  for _, z in ipairs(w.waters) do
    if x1 > z.x and x0 < z.x + z.w and y1 > z.y and y0 < z.y + z.h then
      local h = y1 - y0
      local under = math.min(1, (y1 - math.max(y0, z.y)) / math.max(h, 1e-6))
      local lift, drag = w.gravity * z.lift * under / SUBSTEPS, z.drag * under / SUBSTEPS
      b.vy = b.vy - lift
      b.vx, b.vy = b.vx + (z.flow_x - b.vx) * drag, b.vy + (z.flow_y - b.vy) * drag
      if b.turns and b.kind ~= "circle" then -- pushed up where it is under: it tips back level
        local v, sx, n = corners(b, stamp), 0, 0 -- the corners under the surface, the deeper the more
        for i = 1, #v - 1, 2 do
          local d = v[i + 1] - z.y
          if d > 0 then sx, n = sx + v[i] * d, n + d end
        end
        if n > 0 then
          local cx = centre(b)
          b.spin = b.spin - (sx / n - cx) * lift / b.inv * b.iinv * DEG
        end
      end
      if b.turns then b.spin = b.spin * (1 - drag) end
    end
  end
end

function World:step()
  self.hits_now = {}
  local bodies = self.bodies
  for _ = 1, SUBSTEPS do
    self.stamp = self.stamp + 1
    local stamp = self.stamp
    for _, b in ipairs(bodies) do -- (what turns moves after its contacts are worked out: below)
      if b.inv > 0 then
        b.vy = b.vy + self.gravity / SUBSTEPS
        if not b.turns then b.x, b.y = b.x + b.vx / SUBSTEPS, b.y + b.vy / SUBSTEPS end
      end
    end
    if #self.waters > 0 then
      for _, b in ipairs(bodies) do if b.inv > 0 then float(self, b, stamp) end end
    end
    local box, turns = {}, false
    for i, b in ipairs(bodies) do
      if b.turns then turns = true else box[i] = {bounds(b, stamp)} end
    end
    for i = 1, #bodies do
      local a, ba = bodies[i], box[i]
      for j = ba and i + 1 or #bodies + 1, #bodies do
        local b, bb = bodies[j], box[j]
        if bb and (a.inv > 0 or b.inv > 0) and ba[1] < bb[3] and bb[1] < ba[3] and ba[2] < bb[4] and bb[2] < ba[4] then
          resolve(self, a, b)
        end
      end
    end
    if turns then -- where something that turns touches anything, and how it moves: in C (src/lua_physics.c)
      for _, h in ipairs(physics_turning(bodies, ITERATIONS, BOUNCE_MIN, PUSH_BACK, SLOP, SUBSTEPS)) do
        self.hits_now[#self.hits_now + 1] = h
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
    elseif b.turns then
      local v, nrm = corners(b)
      if inside(v, nrm, x, y) then return b end
    elseif x >= b.x and x < b.x + b.w and y >= b.y and y < b.y + b.h then
      return b
    end
  end
end

return M
