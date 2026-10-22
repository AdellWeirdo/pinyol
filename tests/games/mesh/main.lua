-- mesh() against the same cube drawn by hand in Lua with quad() (tests/ps1cube's maths): they must give the same picture.
-- Globals for tests/mesh.script: mode ("mesh" or "lua"), the pose, and what the last mesh() returned.
mode, vx, vy, vz, shown = "mesh", 0, 0, 0, 0
local S, DEG = 320 / 240, 360 / 4096
local V = {{-100,-100,-100},{100,-100,-100},{-100,100,-100},{100,100,-100},{100,-100,100},{-100,-100,100},{100,100,100},{-100,100,100}}
local F = {{1,2,4,3},{5,6,8,7},{6,5,2,1},{7,8,3,4},{1,3,8,6},{4,2,5,7}} -- quad()'s corner order
local N = {{0,0,-1},{0,0,1},{0,-1,0},{0,1,0},{-1,0,0},{1,0,0}}
local LIGHT = {dir = {-0.5, -0.5, -0.5}, ambient = 63 * 16 / 4096, gain = 0.75}
cube = nil -- the mesh's number (global: the script builds others)

function _init()
  show(0)
  cube = mesh_new(V, F)
end

local function by_hand() -- as tests/games/ps1cube/main.lua
  local a, b, c = vx * math.pi / 2048, vy * math.pi / 2048, vz * math.pi / 2048
  local sx, cx, sy, cy, sz, cz = math.sin(a), math.cos(a), math.sin(b), math.cos(b), math.sin(c), math.cos(c)
  local X = {{1,0,0},{0,cx,-sx},{0,sx,cx}}
  local Y = {{cy,0,sy},{0,1,0},{-sy,0,cy}}
  local Z = {{cz,-sz,0},{sz,cz,0},{0,0,1}}
  local function mul(p, q) local m = {} for i = 1, 3 do m[i] = {} for j = 1, 3 do m[i][j] = p[i][1]*q[1][j] + p[i][2]*q[2][j] + p[i][3]*q[3][j] end end return m end
  local M = mul(mul(X, Y), Z)
  local function apply(v) return M[1][1]*v[1] + M[1][2]*v[2] + M[1][3]*v[3], M[2][1]*v[1] + M[2][2]*v[2] + M[2][3]*v[3], M[3][1]*v[1] + M[3][2]*v[2] + M[3][3]*v[3] end
  local P = {}
  for i, v in ipairs(V) do local x, y, z = apply(v); z = z + 400; P[i] = {240 + x * 160 / z * S, 160 + y * 160 / z * S} end
  for f = 1, 6 do
    local p1, p2, p3, p4 = P[F[f][1]], P[F[f][2]], P[F[f][3]], P[F[f][4]]
    if (p2[1]-p1[1]) * (p3[2]-p1[2]) - (p2[2]-p1[2]) * (p3[1]-p1[1]) > 0 then
      local nx, ny, nz = apply(N[f])
      local k = math.max(0, -0.5 * (nx + ny + nz))
      local byte = math.min(255, math.floor((LIGHT.ambient + LIGHT.gain * k) * 256))
      quad("TEX_CUBE", p1[1], p1[2], p2[1], p2[2], p3[1], p3[2], p4[1], p4[2], {light = byte << 16 | byte << 8 | byte, dither = true})
    end
  end
end

function _draw()
  rect(0, 0, 480, 320, 0x3F007F)
  if mode == "lua" then by_hand()
  elseif mode == "mesh" then
    shown = mesh(cube, "TEX_CUBE", {pos = {0, 0, 400}, rot = {vx * DEG, vy * DEG, vz * DEG}, focal = 160 * S, light = LIGHT})
  end
end

-- a ball of segments x rings quads (the front half shows): a bigger model for the tests
function ball(segments, rings)
  local verts, faces = {}, {}
  for r = 0, rings do
    for sgm = 0, segments - 1 do
      local lat, lon = math.pi * (r / rings - 0.5), 2 * math.pi * sgm / segments
      verts[#verts + 1] = {100 * math.cos(lat) * math.cos(lon), 100 * math.sin(lat), 100 * math.cos(lat) * math.sin(lon)}
    end
  end
  for r = 0, rings - 1 do
    for sgm = 0, segments - 1 do
      local a, b = r * segments + sgm + 1, r * segments + (sgm + 1) % segments + 1
      faces[#faces + 1] = {a, b, b + segments, a + segments}
    end
  end
  return mesh_new(verts, faces)
end
