-- fox: a small low-poly animal of ten boxes, its own (a head, a body, a long tail, four legs), moved part by part with mesh(): the legs swing
-- about their hips, the tail wags, the body leans into a turn. Parts are placed in the fox's space (y up, z forward) and turned about y when it spins.
local Models, View = require("models"), require("view")
local M = {}
local parts = {}
local S = 1.25 -- how big it is drawn, against how big it is for the rules (the camera is a way back)

function M.init()
  local s = Models.solid(); s:box(14, 11, 22, 0, 0, 0); parts.torso = s:build()
  s = Models.solid(); s:box(12, 10, 11, 0, 0, 0); s:box(5.5, 4.5, 6.5, 0, -2, 8); parts.head = s:build()
  s = Models.solid(); s:box(3.6, 6.5, 2.4, 3.9, 0, 0); s:box(3.6, 6.5, 2.4, -3.9, 0, 0); parts.ears = s:build() -- dark, to read against the orange
  s = Models.solid(); s:box(6.5, 6.5, 14, 0, 0, -7); parts.tail = s:build()
  s = Models.solid(); s:box(5.6, 5.6, 6, 0, 0, -3); parts.tip = s:build()
  s = Models.solid(); s:box(4.4, 9, 4.4, 0, -4.5, 0); parts.leg = s:build()
end

local function rotate(v, rot) -- as mesh() turns: Rx * Ry * Rz, degrees, y down
  local k = math.pi / 180
  local sx, cx, sy, cy, sz, cz = math.sin(rot[1] * k), math.cos(rot[1] * k), math.sin(rot[2] * k), math.cos(rot[2] * k), math.sin(rot[3] * k), math.cos(rot[3] * k)
  local x, y, z = v[1] * cz - v[2] * sz, v[1] * sz + v[2] * cz, v[3]
  x, z = x * cy + z * sy, -x * sy + z * cy
  y, z = y * cx - z * sx, y * sx + z * cx
  return {x, y, z}
end

-- fox: {x, y, z, spin (degrees), phase (the stride), lean (degrees), blink}; cam: {x, z}. Returns the faces drawn.
function M.draw(fox, cam)
  if fox.blink and fox.blink > 0 and (fox.blink // 3) % 2 == 0 then return 0 end -- hurt: it flickers
  local n = 0
  local gx, gy, gz = fox.x - cam.x, View.CAM_H - fox.y, fox.z - cam.z
  local yaw = fox.spin or 0
  local ca, sa = math.cos(math.rad(yaw)), math.sin(math.rad(yaw))
  local lean, ph = fox.lean or 0, fox.phase or 0
  local bob = fox.y <= 0.5 and math.abs(math.sin(ph)) * 1.4 or 0
  local function place(ox, oy, oz, model, tex, rot) -- (ox, oy, oz): the part's origin in the fox's space, y up
    local x, z = (ox * ca + oz * sa) * S, (-ox * sa + oz * ca) * S
    return View.call(parts[model], tex, gx + x, gy - oy * S - bob, gz + z, rot, {scale = S})
  end
  local air = fox.y > 0.5
  local swing = air and 22 or math.sin(ph) * 42
  n = n + place(0, 15, 0, "torso", "TEX_FOX", {0, yaw, lean})
  n = n + place(0, 22, 11, "head", "TEX_FOX", {math.sin(ph * 2) * 2, yaw, lean * 0.5})
  n = n + place(0, 30.5, 9.5, "ears", "TEX_FOXD", {math.sin(ph * 2) * 2, yaw, lean * 0.5})
  local wag = math.sin(ph * 0.5) * 18
  local tail_rot = {-6 - (air and 22 or 0), yaw + 14 + wag, lean}
  n = n + place(1.5, 16, -11, "tail", "TEX_FOX", tail_rot)
  local tip = rotate({0, 0, -14 * S}, tail_rot) -- the tip sits where the tail ends
  local bx, bz = (1.5 * ca + -11 * sa) * S, (-1.5 * sa + -11 * ca) * S -- the tail's base
  n = n + View.call(parts.tip, "TEX_FOXW", gx + bx + tip[1] * ca + tip[3] * sa, gy - 16 * S + tip[2] - bob, gz + bz - tip[1] * sa + tip[3] * ca, tail_rot, {scale = S})
  if (fox.spin or 0) == 0 then
    -- (the front legs are behind the body seen from where the camera is: not drawn)
    n = n + place(4.5, 9.5, -7, "leg", "TEX_FOXD", {-swing, 0, 0})
    n = n + place(-4.5, 9.5, -7, "leg", "TEX_FOXD", {swing, 0, 0})
  end
  return n
end

return M
