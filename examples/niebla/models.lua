-- models: the solids of the game as mesh() wants them, built once. Written y up and z forward (mesh() has y down: flipped here). A limb is a
-- box hanging from a pivot and turned about x by a baked angle: mesh() turns about x, y, z in that order, so a limb swinging about the
-- body's own x while the body is turned about y cannot be asked of it; the poses are separate models instead.
local M = {}

local CUBE_V = {{-1,-1,-1},{1,-1,-1},{-1,1,-1},{1,1,-1},{1,-1,1},{-1,-1,1},{1,1,1},{-1,1,1}}
local CUBE_F = {{1,2,4,3},{5,6,8,7},{6,5,2,1},{7,8,3,4},{1,3,8,6},{4,2,5,7}}

local function sub(a, b) return {a[1] - b[1], a[2] - b[2], a[3] - b[3]} end
local function cross(a, b) return {a[2] * b[3] - a[3] * b[2], a[3] * b[1] - a[1] * b[3], a[1] * b[2] - a[2] * b[1]} end
local function dot(a, b) return a[1] * b[1] + a[2] * b[2] + a[3] * b[3] end

local Solid = {}
Solid.__index = Solid
function M.solid() return setmetatable({v = {}, f = {}, parts = {}}, Solid) end

-- a box w x h x d (y up) centred at (x, y, z)
function Solid:box(w, h, d, x, y, z)
  return self:limb(w, h, d, x, y + h / 2, z, 0)
end

-- a box hanging from a pivot (px, py, pz) (its top middle), turned about x by `pitch` degrees: a leg, an arm
function Solid:limb(w, h, d, px, py, pz, pitch)
  local base = #self.v
  local k = math.rad(pitch or 0)
  local c, s = math.cos(k), math.sin(k)
  local cx, cy, cz = 0, 0, 0
  for _, corner in ipairs(CUBE_V) do
    local x, y, z = corner[1] * w / 2, -corner[2] * h / 2 - h / 2, corner[3] * d / 2 -- y up, the box below the pivot
    local ry, rz = y * c - z * s, y * s + z * c -- turned about x (y up)
    self.v[#self.v + 1] = {px + x, -(py + ry), pz + rz}
    cx, cy, cz = cx + x / 8, cy + ry / 8, cz + rz / 8
  end
  for _, f in ipairs(CUBE_F) do self.f[#self.f + 1] = {base + f[1], base + f[2], base + f[3], base + f[4]} end
  self.parts[#self.parts + 1] = {first = #self.f - 5, last = #self.f, centre = {px + cx, -(py + cy), pz + cz}}
  return self
end

-- a flat quad on the ground (y up = y), x0..x1 by z0..z1, seen from above
function Solid:floor(x0, x1, z0, z1, y)
  local base = #self.v
  self.v[#self.v + 1] = {x0, -y, z0}; self.v[#self.v + 1] = {x1, -y, z0}
  self.v[#self.v + 1] = {x1, -y, z1}; self.v[#self.v + 1] = {x0, -y, z1}
  self.f[#self.f + 1] = {base + 4, base + 3, base + 2, base + 1}
  self.parts[#self.parts + 1] = {first = #self.f, last = #self.f, centre = {(x0 + x1) / 2, -y + 1, (z0 + z1) / 2}}
  return self
end

local function orient(v, f, centre)
  local n = #f
  local a, b, c = v[f[1]], v[f[2]], v[f[3]]
  local mid = {0, 0, 0}
  for i = 1, n do for k = 1, 3 do mid[k] = mid[k] + v[f[i]][k] / n end end
  if dot(cross(sub(b, a), sub(c, a)), sub(mid, centre)) > 0 then -- clockwise from outside: the cross product points into the solid
    if n == 4 then f[2], f[4] = f[4], f[2] else f[2], f[3] = f[3], f[2] end
  end
end

function Solid:build()
  for _, p in ipairs(self.parts) do
    for i = p.first, p.last do orient(self.v, self.f[i], p.centre) end
  end
  return mesh_new(self.v, self.f)
end

return M
