-- The PSn00bSDK examples/graphics/gte cube redone with quad(): same vertices, rotation order (Rx*Ry*Rz, 4096 = a turn), camera
-- (z 400, H 160, centre 160,120), backface cull, ambient 63*16/4096 + one light (-0.5,-0.5,-0.5) at 0.75, same texture, dither.
-- vx, vy, vz are globals so tests/ps1cube.script can pose it. The PS1 frame is 320x240, here drawn at 4/3 in the middle of 480x320.
vx, vy, vz = 0, 0, 0
local S, CX, CY = 320 / 240, 240, 160
local V = {{-100,-100,-100},{100,-100,-100},{-100,100,-100},{100,100,-100},{100,-100,100},{-100,-100,100},{100,100,100},{-100,100,100}}
local N = {{0,0,-1},{0,0,1},{0,-1,0},{0,1,0},{-1,0,0},{1,0,0}}
local F = {{1,2,3,4},{5,6,7,8},{6,5,1,2},{7,8,4,3},{1,3,6,8},{4,2,7,5}} -- the PS1's order: top-left, top-right, bottom-left, bottom-right
local LIGHT, AMBIENT, GAIN = {-0.5, -0.5, -0.5}, 63 * 16 / 4096, 0.75

local function rotation(ax, ay, az)
  local function ang(a) a = a * math.pi * 2 / 4096 return math.sin(a), math.cos(a) end
  local sx, cx = ang(ax); local sy, cy = ang(ay); local sz, cz = ang(az)
  local X = {{1,0,0},{0,cx,-sx},{0,sx,cx}}
  local Y = {{cy,0,sy},{0,1,0},{-sy,0,cy}}
  local Z = {{cz,-sz,0},{sz,cz,0},{0,0,1}}
  local function mul(a, b) local m = {} for i = 1, 3 do m[i] = {} for j = 1, 3 do m[i][j] = a[i][1]*b[1][j] + a[i][2]*b[2][j] + a[i][3]*b[3][j] end end return m end
  return mul(mul(X, Y), Z)
end
local function apply(m, v) return m[1][1]*v[1] + m[1][2]*v[2] + m[1][3]*v[3], m[2][1]*v[1] + m[2][2]*v[2] + m[2][3]*v[3], m[3][1]*v[1] + m[3][2]*v[2] + m[3][3]*v[3] end

function _init() show(0) end

function _draw()
  rect(0, 0, 480, 320, 0x3F007F) -- the clear colour (63, 0, 127)
  local M = rotation(vx, vy, vz)
  local P = {}
  for i, v in ipairs(V) do
    local x, y, z = apply(M, v); z = z + 400
    P[i] = {CX + (x * 160 / z) * S, CY + (y * 160 / z) * S}
  end
  for f = 1, 6 do
    local a, b, c, d = F[f][1], F[f][2], F[f][3], F[f][4]
    local cull = (P[b][1]-P[a][1]) * (P[c][2]-P[a][2]) - (P[b][2]-P[a][2]) * (P[c][1]-P[a][1])
    if cull > 0 then -- (the sign is the GTE's nclip's, checked against the PS1 frames)
      local nx, ny, nz = apply(M, N[f])
      local k = math.max(0, LIGHT[1]*nx + LIGHT[2]*ny + LIGHT[3]*nz)
      local byte = math.min(255, math.floor((AMBIENT + GAIN * k) * 256))
      local col = byte << 16 | byte << 8 | byte
      quad("TEX_CUBE", P[a][1], P[a][2], P[b][1], P[b][2], P[d][1], P[d][2], P[c][1], P[c][2], {light = col, dither = true})
    end
  end
end
