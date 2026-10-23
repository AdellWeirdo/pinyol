-- cam: the fixed cameras. mesh() has no camera of its own (it looks along +z with the horizon at `cy`), so the camera is done here: a point of the
-- world is moved into the camera's space (turned about y by the camera's heading, then tilted about x by its pitch, as mesh() tilts a model), and
-- a model's own heading is taken from the camera's. Units are tenths of a metre; the world is y up, mesh() y down.
local M = {}

M.FOCAL, M.CX, M.CY = 200, 240, 150

local cams = {}      -- {pos = {x, y, z}, target = {x, y, z}, zone = {x0, x1, z0, z1}}
local cur, yaw, pitch, cy_, sy_, cp, sp, yaw_d, pitch_d = 1, 0, 0, 1, 0, 1, 0, 0, 0
M.version = 0 -- one more each time the camera changes: what was worked out for it is worked out again
M.rot = {0, 0, 0}

function M.define(list) cams = list end

function M.use(i)
  cur = i
  local c = cams[i]
  local dx, dy, dz = c.target[1] - c.pos[1], c.target[2] - c.pos[2], c.target[3] - c.pos[3]
  yaw = math.atan(dx, dz)
  pitch = math.atan(-dy, math.sqrt(dx * dx + dz * dz)) -- looking down is positive
  cy_, sy_, cp, sp = math.cos(yaw), math.sin(yaw), math.cos(pitch), math.sin(pitch)
  yaw_d, pitch_d = math.deg(yaw), math.deg(pitch)
  M.version = M.version + 1
end

function M.current() return cur end
function M.yaw_deg() return math.deg(yaw) end
function M.pitch_deg() return math.deg(pitch) end

-- the camera that watches (x, z): the current one while it still does (a margin both ways), else the first whose zone has it
function M.pick(x, z)
  local function inside(c, m) local zn = c.zone return x >= zn[1] - m and x <= zn[2] + m and z >= zn[3] - m and z <= zn[4] + m end
  if inside(cams[cur], 14) then return cur end
  for i, c in ipairs(cams) do if inside(c, 0) then return i end end
  return cur
end

-- a world point in the camera's space (mesh()'s: x right, y down, z away)
function M.to_cam(x, y, z)
  local c = cams[cur]
  local dx, vy, dz = x - c.pos[1], -(y - c.pos[2]), z - c.pos[3]
  local x1, z1 = cy_ * dx - sy_ * dz, sy_ * dx + cy_ * dz
  return x1, cp * vy - sp * z1, sp * vy + cp * z1
end

-- a world direction (no move) in the camera's space
function M.dir_to_cam(dx, dy, dz)
  local x1, z1 = cy_ * dx - sy_ * dz, sy_ * dx + cy_ * dz
  local vy = -dy
  return x1, cp * vy - sp * z1, sp * vy + cp * z1
end

-- mesh()'s `rot` for a model turned `heading` degrees in the world (forward = (sin h, cos h))
function M.model_rot(heading)
  local r = M.rot
  r[1], r[2], r[3] = pitch_d, heading - yaw_d, 0
  return r
end

-- a world point on the screen: x, y, size (1 at one unit away... the pixels of a unit there), or nil behind the camera
function M.project(x, y, z)
  local px, py, pz = M.to_cam(x, y, z)
  if pz < 12 then return nil end
  local k = M.FOCAL / pz
  return M.CX + px * k, M.CY + py * k, k, pz
end

return M
