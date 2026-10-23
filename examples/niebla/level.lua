-- level: where everything is (tenths of a metre; z runs along the street), what blocks the way, and the cameras. One street, four stretches:
-- the mouth with a wrecked car, a plaza with a fountain and a bench, an alley, the pier to the lighthouse.
local M = {}

M.START = {x = -6, z = 0, heading = 0}
M.DOOR = {x = 0, z = 548, w = 16}      -- the lighthouse's door, at the end of the pier
M.KEY = {x = 24, z = 184, y = 9}      -- on the bench in the plaza
M.HALF = 38                            -- the street's half width for the player

-- lamps: {x, z, flicker (1: it stutters)}
M.lamps = {}
for k = 0, 7 do M.lamps[#M.lamps + 1] = {x = (k % 2 == 0) and -36 or 36, z = 16 + k * 72, flicker = (k == 3 or k == 6)} end

-- solid things: {kind, x, z, w, d, yaw}: boxes the player and the Figure cannot walk through (x, z their middle)
M.solids = {
  {k = "car", x = -22, z = 64, w = 17, d = 44, yaw = 0},
  {k = "fountain", x = 0, z = 196, w = 34, d = 34, yaw = 0},
  {k = "bench", x = 26, z = 180, w = 8, d = 24, yaw = 0},
  {k = "crates", x = -26, z = 318, w = 14, d = 14, yaw = 0},
  {k = "crates", x = 22, z = 352, w = 14, d = 14, yaw = 0},
}

-- the stretches: a camera for each, alternating from behind-left and from the front looking back (cuts like a fixed-camera horror game)
local SEGMENTS = {-62}
for z = -10, 540, 52 do SEGMENTS[#SEGMENTS + 1] = z end
SEGMENTS[#SEGMENTS + 1] = 580
M.cameras = {}
for i = 1, #SEGMENTS - 1 do
  local z0, z1 = SEGMENTS[i], SEGMENTS[i + 1]
  local mid = (z0 + z1) / 2
  local cam
  if i % 2 == 1 then cam = {pos = {-30, 40, mid - 48}, target = {0, 6, mid + 6}}
  else cam = {pos = {30, 40, mid + 52}, target = {0, 6, mid - 6}} end
  cam.zone = {-60, 60, z0, z1}
  M.cameras[i] = cam
end

function M.floor_at(z)
  if z < 130 then return "TEX_ASPHALT" elseif z < 262 then return "TEX_PAVING" elseif z < 404 then return "TEX_ASPHALT" else return "TEX_PLANK" end
end

return M
