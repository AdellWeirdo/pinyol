-- models: the solids of the game as mesh() wants them (vertices and quads), built once. Written y up and z forward; mesh() has y down, so
-- every y is flipped here. A face is turned the way mesh() expects (clockwise from outside) by orient(), whatever order it was made in.
local M = {}

local CUBE_V = {{-1,-1,-1},{1,-1,-1},{-1,1,-1},{1,1,-1},{1,-1,1},{-1,-1,1},{1,1,1},{-1,1,1}}
local CUBE_F = {{1,2,4,3},{5,6,8,7},{6,5,2,1},{7,8,3,4},{1,3,8,6},{4,2,5,7}}

local function sub(a, b) return {a[1] - b[1], a[2] - b[2], a[3] - b[3]} end
local function cross(a, b) return {a[2] * b[3] - a[3] * b[2], a[3] * b[1] - a[1] * b[3], a[1] * b[2] - a[2] * b[1]} end
local function dot(a, b) return a[1] * b[1] + a[2] * b[2] + a[3] * b[3] end

-- a solid under construction: add boxes and pyramids, then build() gives the mesh number
local Solid = {}
Solid.__index = Solid

function M.solid() return setmetatable({v = {}, f = {}, parts = {}}, Solid) end

-- a box w x h x d (y up) centred at (x, y, z), its faces' uv the whole picture
function Solid:box(w, h, d, x, y, z)
  local base = #self.v
  for _, c in ipairs(CUBE_V) do self.v[#self.v + 1] = {x + c[1] * w / 2, -(y + -c[2] * h / 2), z + c[3] * d / 2} end
  for _, f in ipairs(CUBE_F) do self.f[#self.f + 1] = {base + f[1], base + f[2], base + f[3], base + f[4]} end
  self.parts[#self.parts + 1] = {first = #self.f - 5, last = #self.f, centre = {x, -y, z}}
  return self
end

-- a four-sided pyramid: a base w x d at height y, an apex `h` above it
function Solid:pyramid(w, d, h, x, y, z)
  local base = #self.v
  local hw, hd = w / 2, d / 2
  for _, c in ipairs({{-hw, -hd}, {hw, -hd}, {hw, hd}, {-hw, hd}}) do self.v[#self.v + 1] = {x + c[1], -y, z + c[2]} end
  self.v[#self.v + 1] = {x, -(y + h), z}
  for i = 1, 4 do self.f[#self.f + 1] = {base + 5, base + i % 4 + 1, base + i} end -- (turned by orient)
  self.parts[#self.parts + 1] = {first = #self.f - 3, last = #self.f, centre = {x, -(y + h / 3), z}}
  return self
end

-- a flat quad on the ground (y up = y), x0..x1 by z0..z1, seen from above
function Solid:floor(x0, x1, z0, z1, y)
  local base = #self.v
  self.v[#self.v + 1] = {x0, -y, z0}; self.v[#self.v + 1] = {x1, -y, z0}
  self.v[#self.v + 1] = {x1, -y, z1}; self.v[#self.v + 1] = {x0, -y, z1}
  self.f[#self.f + 1] = {base + 4, base + 3, base + 2, base + 1}
  self.parts[#self.parts + 1] = {first = #self.f, last = #self.f, centre = {(x0 + x1) / 2, -y + 1, (z0 + z1) / 2}} -- (outward: up)
  return self
end

local function orient(v, f, centre)
  local n = #f
  local a, b, c = v[f[1]], v[f[2]], v[f[3]]
  local mid = {0, 0, 0}
  for i = 1, n do for k = 1, 3 do mid[k] = mid[k] + v[f[i]][k] / n end end
  -- clockwise from outside means the cross product points INTO the solid
  if dot(cross(sub(b, a), sub(c, a)), sub(mid, centre)) > 0 then
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
