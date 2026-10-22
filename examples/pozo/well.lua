-- well: the pozo itself, a tube seen from its mouth. The mouth (the rim) is a shape of N corners, the far end the same
-- shape small at the middle of the screen; a lane is the strip between two corners, running from the rim (depth 0)
-- to the far end (depth 1). A point at depth d is the rim's point drawn nearer the middle by a perspective scale.
local V = require("vec")
local M = {}

local CX, CY, R = 240, 176, 116  -- the vanishing point, and how far the rim reaches
local K = 0.13                   -- the far end's size, as a part of the rim's

local function around(n, a0, f) -- n corners on a closed curve: f(angle) -> x, y
  local v = {}
  for i = 0, n - 1 do
    local x, y = f(a0 + i * 2 * math.pi / n)
    v[#v + 1] = {x, y}
  end
  return v
end

local function perimeter(corners, per_side) -- per_side corners along each side of a polygon
  local v = {}
  for s = 1, #corners do
    local a, b = corners[s], corners[s % #corners + 1]
    for k = 0, per_side - 1 do
      local t = k / per_side
      v[#v + 1] = {a[1] + (b[1] - a[1]) * t, a[2] + (b[2] - a[2]) * t}
    end
  end
  return v
end

local function line_of(n, f) -- an open line of n + 1 corners
  local v = {}
  for i = 0, n do local x, y = f(i / n) v[#v + 1] = {x, y} end
  return v
end

local SHAPES = {
  {name = "circulo", closed = true, v = around(16, -math.pi / 2, function(a) return math.cos(a), math.sin(a) end)},
  {name = "cuadrado", closed = true, v = perimeter({{-1, -1}, {1, -1}, {1, 1}, {-1, 1}}, 4)},
  {name = "cruz", closed = true, v = {{-1, -0.33}, {-0.33, -0.33}, {-0.33, -1}, {0.33, -1}, {0.33, -0.33}, {1, -0.33},
                                      {1, 0.33}, {0.33, 0.33}, {0.33, 1}, {-0.33, 1}, {-0.33, 0.33}, {-1, 0.33}}},
  {name = "triangulo", closed = true, v = perimeter({{0, -1.1}, {0.97, 0.55}, {-0.97, 0.55}}, 4)},
  {name = "plano", closed = false, dy = -52, v = line_of(12, function(t) return -1.55 + 3.1 * t, 1.18 end)},
  {name = "uve", closed = false, v = line_of(14, function(t) return -1.1 + 2.2 * t, -0.7 + 1.5 * (1 - math.abs(2 * t - 1)) end)},
  {name = "estrella", closed = true, v = around(10, -math.pi / 2, function(a)
    local k = (math.floor((a + math.pi / 2) / (math.pi / 5) + 0.5) % 2 == 0) and 1 or 0.55
    return math.cos(a) * k, math.sin(a) * k
  end)},
  {name = "ovalo", closed = true, v = around(16, -math.pi / 2, function(a) return math.cos(a) * 1.18, math.sin(a) * 0.82 end)},
}
-- lane colour, rim colour: the well changes colour every level, the way the machines did
local PALS = { -- lane colour, rim colour, the claw's colour (not the well's)
  {0x2860FF, 0x70B0FF, 0xFFE040}, {0xFF3030, 0xFF9070, 0xFFE040}, {0xFFD020, 0xFFF090, 0x50F0FF}, {0x20E0E0, 0xA0FFFF, 0xFFE040},
  {0x30F050, 0xA0FFA0, 0xFFE040}, {0xC040FF, 0xE8A0FF, 0xFFE040}, {0xE0E0E0, 0xFFFFFF, 0xFFE040}, {0xFF8020, 0xFFC888, 0x50F0FF},
}

M.n, M.closed, M.zoom, M.rot = 16, true, 1, 0
M.cx, M.cy = CX, CY
M.pal = PALS[1]
local shape, cr, sr = SHAPES[1], 1, 0

function M.set(level) -- the well of a level
  shape = SHAPES[(level - 1) % #SHAPES + 1]
  M.n, M.closed = shape.closed and #shape.v or #shape.v - 1, shape.closed
  M.pal = PALS[(level - 1) % #PALS + 1]
  M.zoom, M.rot = 1, 0
  cr, sr = 1, 0
end

function M.vanish() return CX, CY + (shape.dy or 0) end

function M.turn(a) M.rot = a cr, sr = math.cos(a), math.sin(a) end

local function sc(d) return 1 / (1 + d * (1 / K - 1)) end
M.scale = sc

local function plain(i, d) -- corner i (it wraps on a closed shape) at depth d
  local n = #shape.v
  local p = shape.v[M.closed and (i - 1) % n + 1 or math.max(1, math.min(n, i))]
  local s = sc(d) * M.zoom * R
  return CX + (p[1] * cr - p[2] * sr) * s, CY + (shape.dy or 0) + (p[1] * sr + p[2] * cr) * s
end
M.corner = plain

function M.at(j, u, d) -- lane j (1..n), u (0..1) across it, depth d
  local x0, y0 = plain(j, d)
  local x1, y1 = plain(j + 1, d)
  return x0 + (x1 - x0) * u, y0 + (y1 - y0) * u
end

function M.qat(q, d) -- a point by lane position q (lane j spans j to j + 1: a fraction is across it), at depth d
  local n = M.n
  local j = math.floor(q)
  local u = q - j
  if M.closed then j = (j - 1) % n + 1 else
    if j < 1 then j, u = 1, 0 elseif j > n then j, u = n, 1 end
  end
  return M.at(j, u, d)
end

function M.rim_at(p) -- a point of the rim by position p (1 is corner 1; fractions are along the lane)
  local j = math.floor(p)
  local x, y = M.at(j, p - j, 0)
  local x1, y1 = M.at(j, (p - j) + 0.05, 0)
  local dx, dy = x1 - x, y1 - y
  local len = math.sqrt(dx * dx + dy * dy)
  return x, y, dx / len, dy / len
end

function M.lane_of(p) -- the lane position p belongs to, 1..n
  if M.closed then return (math.floor(p + 0.5) - 1) % M.n + 1 end
  return math.max(1, math.min(M.n, math.floor(p + 0.5)))
end

-- The well's own lines do not move while a level lasts, so their ends are worked out once (again when the title turns it),
-- and each ring is ONE outline: one call to draw it (an open well's outline goes along the line and back).
local cache = {shape = nil, zoom = nil, rot = nil}
local RIM, RING1, RING2, FAR, LANEPATH, LANELINES = {}, {}, {}, {}, {}, {}

local function ring_pts(d) -- the shape at depth d as an outline
  local pts, k, n = {}, 0, #shape.v
  for i = 1, n do
    local x, y = plain(i, d)
    pts[k + 1], pts[k + 2] = x, y
    k = k + 2
  end
  if not M.closed then
    for i = n - 1, 2, -1 do
      local x, y = plain(i, d)
      pts[k + 1], pts[k + 2] = x, y
      k = k + 2
    end
  end
  return pts
end

local function build()
  cache.shape, cache.zoom, cache.rot = shape, M.zoom, M.rot
  RIM, RING1, RING2, FAR = ring_pts(0), ring_pts(0.34), ring_pts(0.67), ring_pts(1)
  local n = #shape.v
  if M.closed then -- every lane in one path: rim, far, far, rim, then the next two lanes (every other side of both rings comes with it)
    local p, k = {}, 0
    for i = 1, n, 2 do
      local rx, ry = plain(i, 0)
      local fx, fy = plain(i, 1)
      local gx, gy = plain(i + 1, 1)
      local sx, sy = plain(i + 1, 0)
      p[k + 1], p[k + 2], p[k + 3], p[k + 4], p[k + 5], p[k + 6], p[k + 7], p[k + 8] = rx, ry, fx, fy, gx, gy, sx, sy
      k = k + 8
    end
    LANEPATH = p
  else -- an open well: a line for each lane
    LANELINES = {}
    for i = 1, n do
      local x0, y0 = plain(i, 0)
      local x1, y1 = plain(i, 1)
      local k = (i - 1) * 4
      LANELINES[k + 1], LANELINES[k + 2], LANELINES[k + 3], LANELINES[k + 4] = x0, y0, x1, y1
    end
  end
end

function M.ring(d, colour) -- the shape at depth d, thin (the rings that rush by as the claw dives)
  V.hair(ring_pts(d), colour)
end

function M.draw(hot, bright)
  if cache.shape ~= shape or cache.zoom ~= M.zoom or cache.rot ~= M.rot then build() end
  local lane, rim = M.pal[1], M.pal[2]
  bright = bright or 1
  V.hair(RING1, V.dim(lane, 0.5 * bright))
  V.hair(RING2, V.dim(lane, 0.36 * bright))
  V.hair(FAR, V.dim(lane, 0.3 * bright))
  local c_lane = V.dim(lane, 0.85 * bright)
  if M.closed then V.hair(LANEPATH, c_lane)
  else for k = 0, #LANELINES - 4, 4 do V.line(LANELINES[k + 1], LANELINES[k + 2], LANELINES[k + 3], LANELINES[k + 4], c_lane, 1) end end
  V.shape(RIM, V.dim(rim, bright), 3)
  if hot then -- the lane the claw is in, lit along its two edges
    for _, i in ipairs({hot, hot + 1}) do
      local x0, y0 = plain(i, 0)
      local x1, y1 = plain(i, 1)
      V.line(x0, y0, x1, y1, 0xFFFFFF, 2)
    end
  end
end

return M
