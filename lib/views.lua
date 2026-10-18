-- views: project one logical ground position (x across, z along a route, h above ground) through fixed,
-- lateral and rear cameras. The game keeps its actor in world coordinates when the shot changes.
--
--   sx, sy, scale, order = views.project(camera, x, z, h)
--   id = views.pick(zones, x, z, fallback) -- half-open rectangles; the first matching zone wins
-- `order` sorts far to near in ascending order. A point behind a rear camera returns nil.
local M = {}

local function finite(n)
  return type(n) == "number" and n == n and n ~= math.huge and n ~= -math.huge
end

local function number(n, fallback, name)
  if n == nil then return fallback end
  assert(finite(n), "views: " .. name .. " must be a finite number")
  return n
end

function M.project(view, x, z, h)
  assert(type(view) == "table", "views.project: camera must be a table")
  assert(finite(x) and finite(z), "views.project: x and z must be finite numbers")
  h = number(h, 0, "height")
  local kind = view.kind
  local ox, oy = number(view.ox, 0, "ox"), number(view.oy, 0, "oy")
  local dx, dz = x - number(view.cx, 0, "cx"), z - number(view.cz, 0, "cz")
  if kind == "side" then
    local sx = ox + dz * number(view.forward, 1, "forward")
    local sy = oy + dx * number(view.depth, 0, "depth") - h * number(view.height_scale, 1, "height_scale")
    return sx, sy, 1, x
  end
  if kind == "fixed" then
    local b = view.basis or {1, 0, 0, 1}
    assert(type(b) == "table" and finite(b[1]) and finite(b[2]) and finite(b[3]) and finite(b[4]),
           "views.project: fixed basis needs four finite numbers")
    local scale = math.max(0.25, math.min(4, number(view.scale, 1, "scale") + dz * number(view.grow, 0, "grow")))
    return ox + dx * b[1] + dz * b[2], oy + dx * b[3] + dz * b[4] - h * scale, scale, z
  end
  if kind == "rear" then
    if dz <= 0 then return nil end
    local focal, offset = number(view.focal, 80, "focal"), number(view.offset, 40, "offset")
    assert(focal > 0 and offset >= 0, "views.project: rear focal must be positive and offset nonnegative")
    local scale = math.min(number(view.max_scale, 4, "max_scale"), focal / (dz + offset))
    return ox + dx * scale, number(view.horizon, oy, "horizon") + (number(view.eye, 120, "eye") - h) * scale,
           scale, -z
  end
  error("views.project: unknown camera kind " .. tostring(kind), 2)
end

function M.pick(zones, x, z, fallback)
  assert(type(zones) == "table" and finite(x) and finite(z), "views.pick: zones, x and z required")
  for _, v in ipairs(zones) do
    if x >= (v.x0 or -math.huge) and x < (v.x1 or math.huge)
       and z >= (v.z0 or -math.huge) and z < (v.z1 or math.huge) then return v.id end
  end
  return fallback
end

return M
