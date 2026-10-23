-- fox: a small low-poly animal of ten boxes, its own (a head, a body, a long tail, four legs), moved part by part with mesh(): the legs swing
-- about their hips, the tail wags, the body leans into a turn. Parts are placed in the fox's space (y up, z forward) and turned about y when it spins.
local Models, View = require("models"), require("view")
local M = {}
local parts = {}

function M.init()
  local s = Models.solid(); s:box(14, 11, 22, 0, 0, 0); parts.torso = s:build()
  s = Models.solid()
  s:box(10, 9, 10, 0, 0, 0); s:box(5, 4, 6, 0, -1.5, 7); s:box(3, 5, 2, 3.6, 6.5, -1); s:box(3, 5, 2, -3.6, 6.5, -1)
  parts.head = s:build()
  s = Models.solid(); s:box(5, 5, 14, 0, 0, -7); parts.tail = s:build()
  s = Models.solid(); s:box(5.4, 5.4, 6, 0, 0, -3); parts.tip = s:build()
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
    local x, z = ox * ca + oz * sa, -ox * sa + oz * ca
    return View.call(parts[model], tex, gx + x, gy - oy + bob * -1, gz + z, rot)
  end
  local air = fox.y > 0.5
  local swing = air and 22 or math.sin(ph) * 42
  n = n + place(0, 15, 0, "torso", "TEX_FOX", {0, yaw, lean})
  n = n + place(0, 21.5, 12, "head", "TEX_FOX", {math.sin(ph * 2) * 2, yaw, lean * 0.5})
  local wag = math.sin(ph * 0.5) * 18
  local tail_rot = {-14 - (air and 14 or 0), yaw + 26 + wag, lean}
  n = n + place(1.5, 16, -11, "tail", "TEX_FOX", tail_rot)
  local tip = rotate({0, 0, -14}, tail_rot) -- the tip sits where the tail ends
  n = n + View.call(parts.tip, "TEX_FOXW", gx + tip[1] * ca + tip[3] * sa + 1.5 * ca, gy - 16 + tip[2] - bob, gz - tip[1] * sa + tip[3] * ca - 11 * ca, tail_rot)
  if (fox.spin or 0) == 0 then
    -- (the front legs are behind the body seen from where the camera is: not drawn)
    n = n + place(4.5, 9.5, -7, "leg", "TEX_FOXD", {-swing, 0, 0})
    n = n + place(-4.5, 9.5, -7, "leg", "TEX_FOXD", {swing, 0, 0})
  end
  return n
end

return M
