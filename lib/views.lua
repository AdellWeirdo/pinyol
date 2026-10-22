-- views: project one logical ground position (x across, z along a route, h above ground) through fixed,
-- lateral and rear cameras. The game keeps its actor in world coordinates when the shot changes.
--
--   sx, sy, scale, order = views.project(camera, x, z, h)
--   views.draw3d(camera, items) -- face: {id, corners = {{x,z,h,u,v} x4}, opts?}; actor: {x,z,h,draw}
--     camera.snap = true rounds every projected point to a whole pixel, as a PlayStation did (its vertices wobble)
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
    local max_scale = number(view.max_scale, 4, "max_scale")
    assert(focal > 0 and offset >= 0 and max_scale > 0, "views.project: rear focal and max_scale must be positive, offset nonnegative")
    local scale = math.min(max_scale, focal / (dz + offset))
    return ox + dx * scale, number(view.horizon, oy, "horizon") + (number(view.eye, 120, "eye") - h) * scale,
           scale, -z
  end
  error("views.project: unknown camera kind " .. tostring(kind), 2)
end

-- Reuse a rear camera's validated lens for many actors. cx/cz remain live for a following camera.
function M.projector(view)
  assert(type(view) == "table", "views.projector: camera must be a table")
  if view.kind ~= "rear" then
    M.project(view, 0, 1, 0)
    return function(x, z, h) return M.project(view, x, z, h) end
  end
  local ox = number(view.ox, 0, "ox")
  local horizon = number(view.horizon, number(view.oy, 0, "oy"), "horizon")
  local eye = number(view.eye, 120, "eye")
  local focal = number(view.focal, 80, "focal")
  local offset = number(view.offset, 40, "offset")
  local max_scale = number(view.max_scale, 4, "max_scale")
  assert(focal > 0 and offset >= 0 and max_scale > 0, "views.project: rear focal and max_scale must be positive, offset nonnegative")
  return function(x, z, h)
    assert(finite(x) and finite(z), "views.project: x and z must be finite numbers")
    h = number(h, 0, "height")
    local dx = x - number(view.cx, 0, "cx")
    local dz = z - number(view.cz, 0, "cz")
    if dz <= 0 then return nil end
    local scale = math.min(max_scale, focal / (dz + offset))
    return ox + dx * scale, horizon + (eye - h) * scale, scale, -z
  end
end

function M.draw3d(view, faces)
  assert(type(view) == "table" and (view.kind == "rear" or view.kind == "side" or view.kind == "fixed"),
         "views.draw3d: rear, side or fixed camera required")
  assert(type(faces) == "table", "views.draw3d: faces must be a table")
  local rear = view.kind == "rear"
  local near = rear and number(view.near, 0.01, "near") or 0
  assert(not rear or near > 0, "views.draw3d: near must be positive")
  local cz = number(view.cz, 0, "cz")
  assert(not rear or (finite(cz + near) and cz + near > cz), "views.draw3d: near plane must be representable")
  local project = rear and M.projector(view) or function(x, z, h) return M.project(view, x, z, h) end
  -- Validate the lens even when the face list is empty or every face is hidden.
  project(0, rear and cz + near or 1, 0)
  if view.snap then -- the PlayStation's GPU drew whole pixels, so a turning model's vertices wobble
    local exact = project
    project = function(x, z, h)
      local sx, sy, scale, order = exact(x, z, h)
      if sx == nil then return nil end
      return math.floor(sx + 0.5), math.floor(sy + 0.5), scale, order
    end
  end
  local visible = {}
  for index, face in ipairs(faces) do
    assert(type(face) == "table", "views.draw3d: each item must be a table")
    if face.draw ~= nil then
      assert(type(face.draw) == "function" and finite(face.x) and finite(face.z)
             and (face.h == nil or finite(face.h)),
             "views.draw3d: sprite needs draw function and finite x, z, h")
      if not rear or face.z - cz >= near then
        local sx, sy, scale = project(face.x, face.z, face.h)
        assert(finite(sx) and finite(sy) and finite(scale), "views.draw3d: sprite projection must be finite")
        visible[#visible + 1] = {draw = face.draw, sx = sx, sy = sy, scale = scale,
          depth = view.kind == "side" and face.x or rear and -face.z or face.z, index = index}
      end
    else
      assert(type(face.id) == "string" and type(face.corners) == "table"
             and #face.corners == 4 and (face.opts == nil or type(face.opts) == "table")
             and (face.pose == nil or type(face.pose) == "table")
             and (face.cull == nil or type(face.cull) == "boolean"),
             "views.draw3d: face needs an id, four corners and optional opts")
      local pose = face.pose
      local px, pz, ph, cs, sn, size = 0, 0, 0, 1, 0, 1
      if pose then
        px, pz, ph = number(pose.x, 0, "pose.x"), number(pose.z, 0, "pose.z"), number(pose.h, 0, "pose.h")
        local angle = number(pose.angle, 0, "pose.angle")
        size = number(pose.scale, 1, "pose.scale")
        assert(size > 0, "views.draw3d: pose.scale must be positive")
        cs, sn = math.cos(math.rad(angle)), math.sin(math.rad(angle))
      end
      local corners = {}
      for i = 1, 4 do
        local v = face.corners[i]
        assert(type(v) == "table" and finite(v.x) and finite(v.z) and finite(v.h)
               and finite(v.u) and finite(v.v), "views.draw3d: corner needs finite x, z, h, u, v")
        corners[i] = pose and {x = px + (v.x * cs - v.z * sn) * size,
          z = pz + (v.x * sn + v.z * cs) * size, h = ph + v.h * size, u = v.u, v = v.v} or v
        assert(finite(corners[i].x) and finite(corners[i].z) and finite(corners[i].h),
               "views.draw3d: transformed corner must be finite")
      end
      local clipped = {}
      local cut = false
      if rear then
        local previous = corners[4]
        for i = 1, 4 do
          local current = corners[i]
          local a, b = previous.z - cz >= near, current.z - cz >= near
          if a ~= b then
            cut = true
            local t = (cz + near - previous.z) / (current.z - previous.z)
            clipped[#clipped + 1] = {x = previous.x + t * (current.x - previous.x), z = cz + near,
              h = previous.h + t * (current.h - previous.h), u = previous.u + t * (current.u - previous.u),
              v = previous.v + t * (current.v - previous.v)}
          end
          if b then clipped[#clipped + 1] = current end
          previous = current
        end
      else
        clipped = corners
      end
      if #clipped >= 3 then
        assert(not (cut and face.opts and face.opts.lights),
               "views.draw3d: clipped faces do not support corner lights")
        local depth, area, projected = 0, 0, {}
        for i, v in ipairs(clipped) do
          local sx, sy = project(v.x, v.z, v.h)
          assert(finite(sx) and finite(sy), "views.draw3d: projected corner must be finite")
          projected[i] = {x = sx, y = sy, u = v.u, v = v.v}
          depth = depth + (view.kind == "side" and v.x or rear and -v.z or v.z) / #clipped
        end
        assert(finite(depth), "views.draw3d: face depth must be finite")
        if face.cull then
          for i, a in ipairs(projected) do
            local b = projected[i % #projected + 1]
            area = area + a.x * b.y - b.x * a.y
          end
          assert(finite(area), "views.draw3d: projected area must be finite")
        end
        if not face.cull or area > 0 then
          visible[#visible + 1] = {face = face, vertices = projected, depth = depth, index = index, cut = cut}
        end
      end
    end
  end
  table.sort(visible, function(a, b)
    if a.depth == b.depth then return a.index < b.index end
    return a.depth < b.depth
  end)
  for _, entry in ipairs(visible) do
    if entry.draw then
      entry.draw(entry.sx, entry.sy, entry.scale)
    else
      local face, vertices = entry.face, entry.vertices
      local function draw(a, b, c, d)
        local coords, uv = {}, {}
        for _, v in ipairs({a, b, c, d}) do
          coords[#coords + 1], coords[#coords + 2] = v.x, v.y
          uv[#uv + 1], uv[#uv + 2] = v.u, v.v
        end
        local opts = {}
        for key, value in pairs(face.opts or {}) do opts[key] = value end
        opts.uv = uv
        quad(face.id, coords[1], coords[2], coords[3], coords[4], coords[5], coords[6],
             coords[7], coords[8], opts)
      end
      if not entry.cut then
        draw(vertices[1], vertices[2], vertices[3], vertices[4])
      else
        for i = 2, #vertices - 1 do draw(vertices[1], vertices[i], vertices[i + 1], vertices[i + 1]) end
      end
    end
  end
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
