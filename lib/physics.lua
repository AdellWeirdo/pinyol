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
-- and arcade games of up to about 60 bodies on the console, fewer if they turn (about 25).
local M = {}
local World = {}
World.__index = World

local SUBSTEPS = 2
local ITERATIONS = 6 -- passes over the contacts of turning bodies each substep: stacks settle
local BOUNCE_MIN = 1  -- px a tick: slower than this, turning bodies meet without bouncing
local PUSH_BACK, SLOP = 0.2, 0.1 -- the part of an overlap undone each substep, and what is let be
local DEG, RAD = 180 / math.pi, math.pi / 180
local sqrt, cos, sin, abs = math.sqrt, math.cos, math.sin, math.abs

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
  if b._stamp == stamp and stamp then return b._v end
  local cx, cy = centre(b)
  local pts = b.pts
  if not pts then
    local hw, hh = b.w / 2, b.h / 2
    pts = {-hw, -hh, hw, -hh, hw, hh, -hw, hh}
  end
  local a = (b.angle or 0) * RAD
  local c, s = cos(a), sin(a)
  local v = b._v or {}
  for i = 1, #pts - 1, 2 do
    local x, y = pts[i], pts[i + 1]
    v[i], v[i + 1] = cx + x * c - y * s, cy + x * s + y * c
  end
  b._v, b._stamp = v, stamp
  return v
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

function World:corners(b) return corners(b) end

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
local function outward(v, i, cx, cy) -- edge i of corners v: its outward normal and first corner
  local j = i + 2 > #v and 1 or i + 2
  local x1, y1 = v[i], v[i + 1]
  local ex, ey = v[j] - x1, v[j + 1] - y1
  local l = sqrt(ex * ex + ey * ey)
  if l < 1e-9 then return nil end
  local nx, ny = ey / l, -ex / l
  if (x1 - cx) * nx + (y1 - cy) * ny < 0 then nx, ny = -nx, -ny end
  return nx, ny, x1, y1
end

local function inside(v, cx, cy, px, py)
  for i = 1, #v - 1, 2 do
    local nx, ny, x1, y1 = outward(v, i, cx, cy)
    if nx and (px - x1) * nx + (py - y1) * ny > 0.01 then return false end
  end
  return true
end

-- the least push to part two polygons along one of a's edges' normals, and that edge (nil if one separates them)
local function least(va, ax, ay, vb)
  local best, bnx, bny, bi = math.huge, 0, 0, 1
  for i = 1, #va - 1, 2 do
    local nx, ny, x1, y1 = outward(va, i, ax, ay)
    if nx then
      local m = math.huge
      for k = 1, #vb - 1, 2 do
        local d = (vb[k] - x1) * nx + (vb[k + 1] - y1) * ny
        if d < m then m = d end
      end
      if m > 0 then return nil end
      if -m < best then best, bnx, bny, bi = -m, nx, ny, i end
    end
  end
  return best, bnx, bny, bi
end

local function edge(v, i)
  local j = i + 2 > #v and 1 or i + 2
  return v[i], v[i + 1], v[j], v[j + 1]
end

-- the part of the segment p-q on the side of o where (x - o).s >= 0 (nil if none)
local function clip(px, py, qx, qy, ox, oy, sx, sy)
  local dp, dq = (px - ox) * sx + (py - oy) * sy, (qx - ox) * sx + (qy - oy) * sy
  if dp < 0 and dq < 0 then return nil end
  if dp < 0 then
    local t = dp / (dp - dq)
    px, py = px + (qx - px) * t, py + (qy - py) * t
  elseif dq < 0 then
    local t = dp / (dp - dq)
    qx, qy = px + (qx - px) * t, py + (qy - py) * t
  end
  return px, py, qx, qy
end

-- Two polygons: the face of one they press on (the reference), the other's face against it (the incident),
-- clipped to the reference face's width: the one or two points they touch at, as Box2D does it.
local function poly_poly(a, b, stamp)
  local va, vb = corners(a, stamp), corners(b, stamp)
  local ax, ay = centre(a)
  local bx, by = centre(b)
  local da, anx, any, ai = least(va, ax, ay, vb)
  if not da then return nil end
  local db, bnx, bny, bi = least(vb, bx, by, va)
  if not db then return nil end
  local rv, nx, ny, ri, iv, icx, icy, flip = va, anx, any, ai, vb, bx, by, false
  if db < da * 0.95 - 0.01 then rv, nx, ny, ri, iv, icx, icy, flip = vb, bnx, bny, bi, va, ax, ay, true end
  local most, ii = math.huge, 1
  for i = 1, #iv - 1, 2 do
    local ex, ey = outward(iv, i, icx, icy)
    if ex and ex * nx + ey * ny < most then most, ii = ex * nx + ey * ny, i end
  end
  local p1x, p1y, p2x, p2y = edge(iv, ii)
  local r1x, r1y, r2x, r2y = edge(rv, ri)
  local tx, ty = r2x - r1x, r2y - r1y
  local tl = sqrt(tx * tx + ty * ty)
  tx, ty = tx / tl, ty / tl
  p1x, p1y, p2x, p2y = clip(p1x, p1y, p2x, p2y, r1x, r1y, tx, ty)
  if p1x then p1x, p1y, p2x, p2y = clip(p1x, p1y, p2x, p2y, r2x, r2y, -tx, -ty) end
  local pts, depth = {}, 0
  if p1x then
    for _, q in ipairs({{p1x, p1y}, {p2x, p2y}}) do
      local sep = (q[1] - r1x) * nx + (q[2] - r1y) * ny
      if sep <= 0.01 then
        pts[#pts + 1] = q
        if -sep > depth then depth = -sep end
      end
    end
  end
  if #pts == 0 then pts[1], depth = {(ax + bx) / 2, (ay + by) / 2}, math.min(da, db) end
  if flip then nx, ny = -nx, -ny end
  return nx, ny, depth, pts
end

-- a circle c against a polygon: the direction from the circle to the polygon, how deep, where
local function circle_poly(c, b, stamp)
  local v = corners(b, stamp)
  local bx, by = centre(b)
  local best, qx, qy = math.huge, 0, 0
  for i = 1, #v - 1, 2 do
    local j = i + 2 > #v and 1 or i + 2
    local x1, y1, ex, ey = v[i], v[i + 1], v[j] - v[i], v[j + 1] - v[i + 1]
    local l2 = ex * ex + ey * ey
    local t = l2 > 0 and math.max(0, math.min(1, ((c.x - x1) * ex + (c.y - y1) * ey) / l2)) or 0
    local px, py = x1 + ex * t, y1 + ey * t
    local d = (px - c.x) ^ 2 + (py - c.y) ^ 2
    if d < best then best, qx, qy = d, px, py end
  end
  local dist = sqrt(best)
  if inside(v, bx, by, c.x, c.y) then
    if dist < 1e-6 then return 0, 1, c.r, {{c.x, c.y}} end
    return (c.x - qx) / dist, (c.y - qy) / dist, c.r + dist, {{qx, qy}}
  end
  if dist >= c.r or dist < 1e-9 then return nil end
  return (qx - c.x) / dist, (qy - c.y) / dist, c.r - dist, {{qx, qy}}
end

local function turning_contact(a, b, stamp)
  if a.kind == "circle" and b.kind == "circle" then
    local nx, ny, d = contact(a, b)
    if nx then return nx, ny, d, {{a.x + nx * a.r, a.y + ny * a.r}} end
    return nil
  end
  if a.kind == "circle" then return circle_poly(a, b, stamp) end
  if b.kind == "circle" then
    local nx, ny, d, pts = circle_poly(b, a, stamp)
    if nx then return -nx, -ny, d, pts end
    return nil
  end
  return poly_poly(a, b, stamp)
end

local function cross(ax, ay, bx, by) return ax * by - ay * bx end

local function impulse(c, p, jx, jy) -- applied at point p: a pushed back, b forwards; both turn by it
  local a, b = c.a, c.b
  a.vx, a.vy = a.vx - jx * a.inv, a.vy - jy * a.inv
  b.vx, b.vy = b.vx + jx * b.inv, b.vy + jy * b.inv
  if a.iinv > 0 then a.spin = a.spin - cross(p.rax, p.ray, jx, jy) * a.iinv * DEG end
  if b.iinv > 0 then b.spin = b.spin + cross(p.rbx, p.rby, jx, jy) * b.iinv * DEG end
end

-- One pass over a contact's points (Box2D's sequential impulses): each point's push adds up over the passes and
-- never pulls; friction at most mu times it; a bounce only for what came in fast.
local function solve(c)
  local a, b, nx, ny = c.a, c.b, c.nx, c.ny
  local mu = sqrt(a.friction * b.friction)
  for _, p in ipairs(c.pts) do
    local wa, wb = (a.spin or 0) * RAD, (b.spin or 0) * RAD
    local rvx = (b.vx - wb * p.rby) - (a.vx - wa * p.ray)
    local rvy = (b.vy + wb * p.rbx) - (a.vy + wa * p.rax)
    local vn = rvx * nx + rvy * ny
    local pn = math.max(p.pn - (vn - p.bias) / p.kn, 0)
    local dn = pn - p.pn
    p.pn = pn
    impulse(c, p, dn * nx, dn * ny)
    wa, wb = (a.spin or 0) * RAD, (b.spin or 0) * RAD
    rvx = (b.vx - wb * p.rby) - (a.vx - wa * p.ray)
    rvy = (b.vy + wb * p.rbx) - (a.vy + wa * p.rax)
    local tx, ty = -ny, nx
    local pt = math.max(-mu * p.pn, math.min(mu * p.pn, p.pt - (rvx * tx + rvy * ty) / p.kt))
    local dt = pt - p.pt
    p.pt = pt
    impulse(c, p, dt * tx, dt * ty)
  end
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
    local box, turning, warm = {}, {}, self.warm or {}
    for i, b in ipairs(bodies) do box[i] = {bounds(b, stamp)} end
    for i = 1, #bodies do
      local a, ba = bodies[i], box[i]
      for j = i + 1, #bodies do
        local b, bb = bodies[j], box[j]
        if (a.inv > 0 or b.inv > 0) and ba[1] < bb[3] and bb[1] < ba[3] and ba[2] < bb[4] and bb[2] < ba[4] then
          if a.turns or b.turns then
            local nx, ny, depth, pts = turning_contact(a, b, stamp)
            if nx then turning[#turning + 1] = {a = a, b = b, nx = nx, ny = ny, depth = depth, pts = pts} end
          else
            resolve(self, a, b)
          end
        end
      end
    end
    for _, c in ipairs(turning) do -- the points, how hard each resists a push (mass and inertia), what bounces
      local a, b = c.a, c.b
      local ax, ay = centre(a)
      local bx, by = centre(b)
      local wa, wb = (a.spin or 0) * RAD, (b.spin or 0) * RAD
      local e = math.min(a.bounce, b.bounce)
      local before = warm[a] and warm[a][b] -- the same contact a moment ago: its pushes, to start from
      for k, q in ipairs(c.pts) do
        local p = {x = q[1], y = q[2], rax = q[1] - ax, ray = q[2] - ay, rbx = q[1] - bx, rby = q[2] - by, pn = 0,
                   pt = 0, bias = 0}
        for _, o in ipairs(before or {}) do
          if (o.x - p.x) ^ 2 + (o.y - p.y) ^ 2 < 4 then p.pn, p.pt = o.pn, o.pt end
        end
        p.kn = a.inv + b.inv + cross(p.rax, p.ray, c.nx, c.ny) ^ 2 * a.iinv + cross(p.rbx, p.rby, c.nx, c.ny) ^ 2 * b.iinv
        p.kt = a.inv + b.inv + cross(p.rax, p.ray, -c.ny, c.nx) ^ 2 * a.iinv + cross(p.rbx, p.rby, -c.ny, c.nx) ^ 2 * b.iinv
        local vn = ((b.vx - wb * p.rby) - (a.vx - wa * p.ray)) * c.nx + ((b.vy + wb * p.rbx) - (a.vy + wa * p.rax)) * c.ny
        if vn < -BOUNCE_MIN then p.bias = -e * vn end -- resting, rocking: no endless tiny bounces
        p.bias = math.max(p.bias, PUSH_BACK * math.max(c.depth - SLOP, 0) * SUBSTEPS) -- and out of each other
        if vn < -0.5 and not c.hit then c.hit = true; self.hits_now[#self.hits_now + 1] = {a, b, -vn} end
        c.pts[k] = p
        impulse(c, p, p.pn * c.nx - p.pt * c.ny, p.pn * c.ny + p.pt * c.nx)
      end
    end
    for _ = 1, ITERATIONS do
      for _, c in ipairs(turning) do solve(c) end
    end
    self.warm = {}
    for _, c in ipairs(turning) do
      self.warm[c.a] = self.warm[c.a] or {}
      self.warm[c.a][c.b] = c.pts
    end
    for _, b in ipairs(bodies) do
      if b.inv > 0 and b.turns then
        b.x, b.y = b.x + b.vx / SUBSTEPS, b.y + b.vy / SUBSTEPS
        b.angle = (b.angle + b.spin / SUBSTEPS) % 360
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
      local cx, cy = centre(b)
      if inside(corners(b), cx, cy, x, y) then return b end
    elseif x >= b.x and x < b.x + b.w and y >= b.y and y < b.y + b.h then
      return b
    end
  end
end

return M
