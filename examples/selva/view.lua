-- view: the picture of the game, all of it made of mesh() calls and a few quads. y up in the game, y down for mesh(); the camera sits behind
-- and above the fox and looks along +z (mesh() has no camera turn: the horizon is where `cy` is).
local Models = require("models")
local M = {}

M.FOCAL, M.CX, M.CY = 213, 240, 112
M.CAM_H, M.CAM_BACK = 58, 112
M.snap, M.dither, M.fog = true, true, true -- the tricks "Cómo funciona" lets the player switch

local LIGHT = {dir = {-0.45, -0.75, -0.5}, ambient = 0.27, gain = 0.42} -- (128 is a texture as it is; 255, twice as bright)
local models = {}

local function ground_y() return M.CAM_H end -- the ground is this far below the camera, in mesh() terms

function M.init()
  local s
  -- the path: slabs of 40, getting longer toward the horizon (one picture each: far ones stretch, as a PlayStation's did)
  s = Models.solid()
  local z = 0
  for _, len in ipairs({40, 40, 40, 40, 40, 80, 160, 320, 640}) do s:floor(-46, 46, z, z + len, 0) z = z + len end
  models.path = s:build()
  -- a row of three trees, spaced 110 apart, one side (the left; the right is the same mirrored by x)
  s = Models.solid()
  local H, W, J = {44, 58, 38}, {40, 52, 34}, {0, 6, -5} -- each tree its own height, width and place across
  for i = 0, 2 do s:box(9, H[i + 1], 9, J[i + 1], H[i + 1] / 2, i * 110 + J[i + 1]) end
  models.trunks = s:build()
  s = Models.solid()
  for i = 0, 2 do s:pyramid(W[i + 1], W[i + 1], H[i + 1] + 4, J[i + 1], H[i + 1] - 8, i * 110 + J[i + 1]) end
  models.leaves = s:build()
  s = Models.solid(); s:box(18, 18, 18, 0, 9, 0); models.crate = s:build()
  s = Models.solid(); s:floor(-46, 46, 0, 40, 0.5); models.pit = s:build()
  s = Models.solid(); s:floor(-14, 14, 0, 14, 0.5); models.spike = s:build()
end

local function call(model, tex, x, y, z, rot, opts)
  local o = {pos = {x, y, z}, rot = rot, focal = M.FOCAL, cx = M.CX, cy = M.CY, near = 20, light = LIGHT, snap = M.snap, dither = M.dither}
  if M.fog then o.fade = {260, 980} end
  if opts then for k, v in pairs(opts) do o[k] = v end end
  return mesh(model, tex, o)
end
M.call = call

-- a point of the game (x, y up, z) on the screen, its size (1 at 100 away), or nil behind the camera
function M.project(x, y, z, cam)
  local rz = z - cam.z
  if rz < 24 then return nil end
  local k = M.FOCAL / rz
  return M.CX + (x - cam.x) * k, M.CY + (M.CAM_H - y) * k, k
end

function M.sky(t)
  local hy = M.CY
  grad(0, 0, 480, hy - 96, 0x0E1C34, 0x4A3468, {dither = M.dither})
  grad(0, hy - 96, 480, 96, 0x4A3468, 0xF4934C, {dither = M.dither})
  -- the sun, low, behind the far hills: a ring of a deeper orange and its disc
  circ(330, hy - 34, 46, 0xF2763A, true)
  circ(330, hy - 34, 36, 0xFFC468, true)
  circ(330, hy - 34, 26, 0xFFE59A, true)
  -- distant hills: three dark teal ridges, nearer ones darker
  for layer = 1, 3 do
    local c = ({0x2E4A5A, 0x203A48, 0x142A36})[layer]
    local base = hy + 2 * layer + 4
    local pts = {0, base}
    for x = 0, 480, 40 do pts[#pts + 1] = x; pts[#pts + 1] = base - 14 - layer * 6 - ((x * (7 + layer * 3) + layer * 53) % 17) end
    pts[#pts + 1] = 480; pts[#pts + 1] = base + 1
    pts[#pts + 1] = 0; pts[#pts + 1] = base + 1
    poly(pts, c, true)
  end
  -- the ground beside the way: bands of a mossy dark, lighter toward the horizon
  local bands = {0x1E3C3C, 0x183238, 0x142A36, 0x102230}
  local y0 = hy + 4
  for i, c in ipairs(bands) do
    local y1 = i == #bands and 320 or y0 + math.floor((320 - hy - 4) * ({0.12, 0.3, 0.6})[i])
    rect(0, y0, 480, y1 - y0, c)
    y0 = y1
  end
end

function M.haze() -- a warm band on the horizon, over the far ground and under what is near
  if M.fog then grad(0, M.CY - 18, 480, 46, 0x000000, 0x5A2A12, {add = true, alpha = 0.5, dither = M.dither}) end
end

-- the world seen from `cam` ({x, z}): the rolling path and the two rows of trees
function M.path(cam)
  return call(models.path, "TEX_PATH", -cam.x, ground_y(), -(cam.z % 40) + 40, {0, 0, 0}, {fade = M.fog and {300, 1400} or nil})
end

function M.trees(cam)
  local gz = ground_y()
  local toff = cam.z % 110
  local n = 0
  for _, side in ipairs({-1, 1}) do
    local x = side * 78 - cam.x
    n = n + call(models.trunks, "TEX_BARK", x, gz, -toff + 40, {0, 0, 0})
    n = n + call(models.leaves, "TEX_LEAF", x, gz, -toff + 40, {0, 0, 0})
  end
  return n
end

-- the things on the path, far to near: a crate, a pit, a spike trap, a fruit (a sprite that turns)
function M.thing(it, cam, t)
  if it.z - cam.z < 24 or it.z - cam.z > 520 then return 0 end
  if it.k == "crate" then return call(models.crate, "TEX_CRATE", it.x - cam.x, ground_y(), it.z - cam.z, {0, 0, 0}) end
  if it.k == "pit" then return call(models.pit, "TEX_PIT", -cam.x, ground_y(), it.z - cam.z - 0, {0, 0, 0}, {light = false, fade = M.fog and {300, 1400} or nil}) end
  if it.k == "spike" then return call(models.spike, "TEX_SPIKE", it.x - cam.x - 0, ground_y(), it.z - cam.z, {0, 0, 0}) end
  if it.k == "fruit" then
    local sx, sy, k = M.project(it.x, it.y + 6, it.z, cam)
    if not sx then return 0 end
    local bob = math.sin(t / 9 + it.z) * 2
    local w = math.max(0.15, 0.52 * k * (1 + 0.12 * math.sin(t / 7 + it.z)))
    img("SPR_FRUIT", sx - 8 * w, sy - 8 * w + bob, {scale_x = w, scale_y = w})
    return 0
  end
  return 0
end

-- a soft dark patch under the fox, smaller the higher it is
function M.shadow(fox, cam)
  local x0, x1 = fox.x - 7 + (fox.y * 0.0), fox.x + 7
  local s = math.max(0.45, 1 - fox.y / 70)
  local w = 9 * s
  local a, b, c, d = {M.project(fox.x - w, 0, fox.z - w * 1.3, cam)}, {M.project(fox.x + w, 0, fox.z - w * 1.3, cam)},
                     {M.project(fox.x + w, 0, fox.z + w * 1.3, cam)}, {M.project(fox.x - w, 0, fox.z + w * 1.3, cam)}
  if a[1] and c[1] then quad("TEX_FOXD", a[1], a[2], b[1], b[2], c[1], c[2], d[1], d[2], {alpha = 0.5}) end
end

return M
