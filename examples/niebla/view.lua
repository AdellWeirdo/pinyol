-- view: the picture. Everything is a mesh() through the fixed camera of cam.lua; the dark is the picture's own: faces far from the light get
-- a dim light, and a glow added over the screen is the lamp's and the torch's.
local Models, Cam, Level = require("models"), require("cam"), require("level")
local M = {}

M.snap, M.dither, M.fog = true, true, true

local models = {}
M.models = models
local OPTS, POS, LIGHT = {pos = {0, 0, 0}, focal = Cam.FOCAL, cx = Cam.CX, cy = Cam.CY, near = 12}, {0, 0, 0}, {dir = {0, 0, 0}, ambient = 0.2, gain = 0.3}
local MOON = {-0.3, 0.8, -0.4} -- toward the moon, in the world (y up)

function M.init()
  local s
  s = Models.solid(); s:floor(-40, 40, 0, 40, 0); models.slab = s:build()
  s = Models.solid(); s:box(1.8, 50, 1.8, 0, 25, 0); s:box(8, 3, 8, 0, 50, 0); models.lamp_post = s:build()
  s = Models.solid(); s:box(4.6, 1.2, 4.6, 0, 52.6, 0); models.lamp_glass = s:build()
  s = Models.solid(); s:box(17, 8, 44, 0, 4, 0); s:box(15, 7, 22, 0, 12, -2); models.car = s:build()
  s = Models.solid(); s:box(34, 6, 34, 0, 3, 0); s:box(26, 5, 26, 0, 8.5, 0); s:box(5, 20, 5, 0, 19, 0); models.fountain = s:build()
  s = Models.solid(); s:box(8, 3, 24, 0, 8, 0); s:box(2, 8, 22, -3, 4, 0); s:box(2, 8, 22, 3, 4, 0); models.bench = s:build()
  s = Models.solid(); s:box(14, 14, 14, 0, 7, 0); models.crate = s:build()
  s = Models.solid(); s:box(3.4, 1.2, 1.2, 0, 0, 0); models.key = s:build()
  s = Models.solid(); s:box(16, 30, 2, 0, 15, 0); s:box(4, 30, 4, -10, 15, 0); s:box(4, 30, 4, 10, 15, 0); s:box(24, 4, 4, 0, 32, 0); models.door = s:build()
  s = Models.solid(); s:box(26, 110, 26, 0, 55, 0); models.tower = s:build()
end

function M.call(model, tex, x, y, z, heading, ambient, scale)
  local px, py, pz = Cam.to_cam(x, y, z)
  local o = OPTS
  o.pos = POS
  POS[1], POS[2], POS[3] = px, py, pz
  o.rot = Cam.model_rot(heading or 0)
  local mx, my, mz = Cam.dir_to_cam(MOON[1], MOON[2], MOON[3])
  LIGHT.dir[1], LIGHT.dir[2], LIGHT.dir[3] = -mx, -my, -mz
  LIGHT.ambient, LIGHT.gain = ambient or 0.2, 0.16
  o.light, o.scale = LIGHT, scale
  o.snap, o.dither = M.snap, M.dither
  return mesh(model, tex, o)
end


local function dist(ax, az, bx, bz) return math.sqrt((ax - bx) ^ 2 + (az - bz) ^ 2) end

-- how much light there is at (x, z): a little everywhere, the lamps' pools, the player's halo, the torch's beam. With the fog off, plenty everywhere.
function M.ambient(W, x, z, floor_)
  if not M.fog then return 0.55 end
  local p = W.p
  local a = 0.08
  a = a + 0.34 * math.max(0, 1 - dist(x, z, p.x, p.z) / 46)
  for _, l in ipairs(Level.lamps) do
    local d = dist(x, z, l.x, l.z)
    if d < 80 then a = a + (l.flicker and W.flick or 1) * 0.5 * (1 - d / 80) ^ 1.4 end
  end
  -- the beam: a face in the cone is lit
  local d = dist(x, z, p.x, p.z)
  if d < W.RANGE and d > 1 then
    local ang = math.deg(math.atan(x - p.x, z - p.z)) - p.h
    ang = (ang + 180) % 360 - 180
    if math.abs(ang) < W.CONE + 8 then a = a + 0.5 * (1 - d / W.RANGE) end
  end
  return math.min(0.95, a)
end

local FAR_FOG, FAR_CLEAR = 125, 320 -- things farther than this from the player are not drawn: the fog hides where it stops (with it off, the cut shows)

-- the street seen from the current camera: floor, lamps, solids, the key, the lighthouse, the people far to near. Returns the faces drawn.
function M.scene(W, draw_people)
  local p = W.p
  local FAR = M.fog and FAR_FOG or FAR_CLEAR
  local n = 0
  local items = {}
  local function add(x, z, fn) -- (depth in the camera's space, to sort by)
    local _, _, d = Cam.to_cam(x, 0, z)
    items[#items + 1] = {d = d, fn = fn}
  end
  -- the floor, a slab at a time: it is drawn first, under everything
  for z0 = math.floor((p.z - FAR) / 40) * 40, p.z + FAR, 40 do
    if z0 >= -80 and z0 < 580 then
      local zc = z0 + 20
      -- (a slab that no light reaches is black anyway: not drawn, and the floor is most of the pixels)
      local a = math.max(M.ambient(W, 0, z0), M.ambient(W, 0, zc), M.ambient(W, 0, z0 + 40), M.ambient(W, 30, zc), M.ambient(W, -30, zc))
      if a > 0.11 or not M.fog then n = n + M.call(models.slab, Level.floor_at(zc), 0, 0, z0, 0, M.ambient(W, 0, zc)) end
    end
  end
  for _, l in ipairs(Level.lamps) do
    if dist(l.x, l.z, p.x, p.z) < FAR then
      add(l.x, l.z, function()
        local k = M.ambient(W, l.x, l.z)
        local c = M.call(models.lamp_post, "TEX_METAL", l.x, 0, l.z, 0, k)
        local on = not l.flicker or W.flick > 0.5
        return c + M.call(models.lamp_glass, "TEX_LAMP", l.x, 0, l.z, 0, on and 1.0 or 0.12)
      end)
    end
  end
  for _, s in ipairs(Level.solids) do
    if dist(s.x, s.z, p.x, p.z) < FAR then
      add(s.x, s.z, function()
        local m = s.k == "car" and models.car or s.k == "fountain" and models.fountain or s.k == "bench" and models.bench or models.crate
        local tex = s.k == "car" and "TEX_METAL" or s.k == "fountain" and "TEX_STONE" or s.k == "bench" and "TEX_WOOD" or "TEX_RUST"
        return M.call(m, tex, s.x, 0, s.z, s.yaw, M.ambient(W, s.x, s.z))
      end)
    end
  end
  if not W.key_taken and dist(Level.KEY.x, Level.KEY.z, p.x, p.z) < FAR then
    add(Level.KEY.x, Level.KEY.z, function()
      return M.call(models.key, "TEX_GOLD", Level.KEY.x, Level.KEY.y + math.sin(W.t / 14) * 0.6, Level.KEY.z, W.t * 2, 1.0)
    end)
  end
  local d = Level.DOOR
  if dist(d.x, d.z, p.x, p.z) < FAR + 40 then
    add(d.x, d.z, function()
      local k = M.ambient(W, d.x, d.z - 4)
      return M.call(models.door, "TEX_DOOR", d.x, 0, d.z, 0, k) + M.call(models.tower, "TEX_LIGHTHOUSE", d.x, 0, d.z + 14, 0, k)
    end)
  end
  if draw_people then add(p.x, p.z, function() return draw_people("player") end) end
  if draw_people and W.f.state ~= "away" then add(W.f.x, W.f.z, function() return draw_people("figure") end) end
  table.sort(items, function(a, b) return a.d > b.d end)
  for _, it in ipairs(items) do n = n + it.fn() end
  return n
end

-- the lamps' and the torch's light, added over the picture
function M.glows(W)
  local p = W.p
  local FAR = FAR_FOG
  for _, l in ipairs(Level.lamps) do
    if dist(l.x, l.z, p.x, p.z) < FAR then
      local sx, sy, k = Cam.project(l.x, 52, l.z)
      local on = not l.flicker or W.flick > 0.5
      if sx and on and sx > -80 and sx < 560 then light(sx, sy + 8 * k, math.min(58, 52 * k), 0xE8B870, {intensity = 0.55}) end -- (a glow costs by its area: a small one, the floor's own light does the rest)
    end
  end
  -- the torch: from the player's hand along the ground where it looks
  local hx, hy, k = Cam.project(p.x, 11, p.z)
  if hx then
    local r = math.rad(p.h)
    local tx, ty = Cam.project(p.x + math.sin(r) * 30, 1, p.z + math.cos(r) * 30)
    if tx then
      -- how far the beam reaches on the screen: its far end, or as far as can be seen when it points at the camera and leaves the picture
      local rad = 210
      for _, reach in ipairs({1, 0.75, 0.5, 0.35}) do
        local fx, fy = Cam.project(p.x + math.sin(r) * W.RANGE * reach, 0, p.z + math.cos(r) * W.RANGE * reach)
        if fx then rad = math.min(260, math.sqrt((fx - hx) ^ 2 + (fy - hy) ^ 2) / reach) break end
      end
      local ang = math.deg(math.atan(ty - hy, tx - hx))
      light(hx, hy, math.max(30, rad), 0xEAF0FF, {intensity = 0.85, cone = {angle = ang, width = 2 * W.CONE + 8}})
    end
    light(hx, hy + 14 * k, 20 * k, 0x7A8CA8, {intensity = 0.5})
  end
end

return M
