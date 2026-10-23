-- view: the picture. Everything is a mesh() through the fixed camera of cam.lua; the dark is the picture's own: faces far from the light get
-- a dim light, and a glow added over the screen is the lamp's and the torch's.
local Models, Cam, Level = require("models"), require("cam"), require("level")
local M = {}

M.snap, M.dither, M.fog = true, true, true

local models = {}
M.models = models

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

local OPTS, POS, LIGHT = {pos = {0, 0, 0}, focal = Cam.FOCAL, cx = Cam.CX, cy = Cam.CY, near = 12}, {0, 0, 0}, {dir = {0, 0, 0}, ambient = 0.2, gain = 0.16}
local MOON = {-0.3, 0.8, -0.4} -- toward the moon, in the world (y up)
local light_for = -1           -- the camera the moon's direction was worked out for (it only changes at a cut)

-- one mesh() call: a model at a world point, turned `heading`, lit by `ambient` (0..1) with the moon's light on its faces, or with no light at all
function M.call(model, tex, x, y, z, heading, ambient, unlit)
  if light_for ~= Cam.version then
    local mx, my, mz = Cam.dir_to_cam(MOON[1], MOON[2], MOON[3])
    LIGHT.dir[1], LIGHT.dir[2], LIGHT.dir[3] = -mx, -my, -mz
    light_for = Cam.version
  end
  local px, py, pz = Cam.to_cam(x, y, z)
  local o = OPTS
  o.pos = POS
  POS[1], POS[2], POS[3] = px, py, pz
  o.rot = Cam.model_rot(heading or 0)
  LIGHT.ambient = ambient or 0.2
  o.light = not unlit and LIGHT or false
  o.snap, o.dither = M.snap, M.dither
  return mesh(model, tex, o)
end

-- What is worked out once a frame (a light is asked for in a dozen places, and a square root costs on the console): the lamps near the player, where
-- the torch points.
local near_lamps, nl = {}, 0
local px, pz, bx, bz, cosmin, range, flick = 0, 0, 0, 1, 0, 78, 1

function M.frame_begin(W)
  local p = W.p
  px, pz = p.x, p.z
  local r = math.rad(p.h)
  bx, bz = math.sin(r), math.cos(r)
  cosmin, range, flick = math.cos(math.rad(W.CONE + 8)), W.RANGE, W.flick
  nl = 0
  for _, l in ipairs(Level.lamps) do
    local dx, dz = l.x - px, l.z - pz
    if dx * dx + dz * dz < 44100 then nl = nl + 1; near_lamps[nl] = l end
  end
end

-- how much light there is at (x, z): a little everywhere, the lamps' pools, the player's halo, the torch's beam. With the fog off, plenty everywhere.
function M.ambient(x, z)
  if not M.fog then return 0.55 end
  local a = 0.08
  local dx, dz = x - px, z - pz
  local d2 = dx * dx + dz * dz
  local d
  if d2 < 2116 then d = math.sqrt(d2); a = a + 0.34 * (1 - d / 46) end
  for i = 1, nl do
    local l = near_lamps[i]
    local lx, lz = x - l.x, z - l.z
    local e2 = lx * lx + lz * lz
    if e2 < 6400 then
      local k = 1 - math.sqrt(e2) / 80
      a = a + (l.flicker and flick or 1) * 0.6 * k * k
    end
  end
  if d2 < range * range and d2 > 1 then -- the beam: a face in the cone is lit
    d = d or math.sqrt(d2)
    if (dx * bx + dz * bz) / d > cosmin then a = a + 0.5 * (1 - d / range) end
  end
  return a < 0.95 and a or 0.95
end

local FAR_FOG, FAR_CLEAR = 125, 320 -- things farther than this from the player are not drawn: the fog hides where it stops (with it off, the cut shows)

local items, nitems = {}, 0

-- the street seen from the current camera: floor, lamps, solids, the key, the lighthouse, the people far to near. Returns the faces drawn.
function M.scene(W, draw_people)
  local p = W.p
  local FAR = M.fog and FAR_FOG or FAR_CLEAR
  local far2 = FAR * FAR
  M.frame_begin(W)
  local n = 0
  nitems = 0
  local function add(x, z, fn) -- (depth in the camera's space, to sort by)
    local _, _, d = Cam.to_cam(x, 0, z)
    nitems = nitems + 1
    items[nitems] = {d = d, fn = fn}
  end
  local function near(x, z) return (x - px) * (x - px) + (z - pz) * (z - pz) < far2 end
  -- the floor, a slab at a time, under everything and with no light of its own: its brightness is a step of four, chosen by the light there
  for z0 = math.floor((p.z - FAR) / 40) * 40, p.z + FAR, 40 do
    if z0 >= -80 and z0 < 580 then
      local zc = z0 + 20
      local a = M.ambient(0, zc)
      local b = M.ambient(0, z0)
      if b > a then a = b end
      b = M.ambient(0, z0 + 40)
      if b > a then a = b end
      if a > 0.1 or not M.fog then
        local step = (not M.fog or a > 0.62) and 4 or a > 0.4 and 3 or a > 0.22 and 2 or 1
        n = n + M.call(models.slab, Level.floor_at(zc) .. "_" .. step, 0, 0, z0, 0, 0, true)
      end
    end
  end
  for _, l in ipairs(Level.lamps) do
    if near(l.x, l.z) then
      add(l.x, l.z, function()
        local c = M.call(models.lamp_post, "TEX_METAL", l.x, 0, l.z, 0, M.ambient(l.x, l.z))
        local on = not l.flicker or W.flick > 0.5
        return c + M.call(models.lamp_glass, "TEX_LAMP", l.x, 0, l.z, 0, on and 1.0 or 0.12)
      end)
    end
  end
  for _, s in ipairs(Level.solids) do
    if near(s.x, s.z) then
      add(s.x, s.z, function()
        local m = s.k == "car" and models.car or s.k == "fountain" and models.fountain or s.k == "bench" and models.bench or models.crate
        local tex = s.k == "car" and "TEX_METAL" or s.k == "fountain" and "TEX_STONE" or s.k == "bench" and "TEX_WOOD" or "TEX_RUST"
        return M.call(m, tex, s.x, 0, s.z, s.yaw, M.ambient(s.x, s.z))
      end)
    end
  end
  if not W.key_taken and near(Level.KEY.x, Level.KEY.z) then
    add(Level.KEY.x, Level.KEY.z, function()
      return M.call(models.key, "TEX_GOLD", Level.KEY.x, Level.KEY.y + math.sin(W.t / 14) * 0.6, Level.KEY.z, W.t * 2, 1.0)
    end)
  end
  local d = Level.DOOR
  if (d.x - px) ^ 2 + (d.z - pz) ^ 2 < (FAR + 40) ^ 2 then
    add(d.x, d.z, function()
      local k = M.ambient(d.x, d.z - 4)
      return M.call(models.door, "TEX_DOOR", d.x, 0, d.z, 0, k) + M.call(models.tower, "TEX_LIGHTHOUSE", d.x, 0, d.z + 14, 0, k)
    end)
  end
  if draw_people then add(p.x, p.z, function() return draw_people("player") end) end
  if draw_people and W.f.state ~= "away" then add(W.f.x, W.f.z, function() return draw_people("figure") end) end
  for i = nitems + 1, #items do items[i] = nil end
  table.sort(items, function(a, b) return a.d > b.d end)
  for i = 1, nitems do n = n + items[i].fn() end
  return n
end

-- the lamps' and the torch's light, added over the picture. A glow costs by its area on the console (about 200 ns a pixel): small ones, the floor's
-- own light does the rest, and the torch's cone is held to a size.
function M.glows(W)
  local p = W.p
  for i = 1, nl do
    local l = near_lamps[i]
    local on = not l.flicker or W.flick > 0.5
    if on then
      local sx, sy, k = Cam.project(l.x, 52, l.z)
      if sx and sx > -80 and sx < 560 then light(sx, sy + 8 * k, math.min(58, 52 * k), 0xE8B870, {intensity = 0.55}) end
    end
  end
  -- the torch: from the player's hand along the ground where it looks
  local hx, hy, k = Cam.project(p.x, 11, p.z)
  if hx then
    local r = math.rad(p.h)
    local tx, ty = Cam.project(p.x + math.sin(r) * 30, 1, p.z + math.cos(r) * 30)
    if tx then
      local rad = 150
      for _, reach in ipairs({1, 0.75, 0.5, 0.35}) do
        local fx, fy = Cam.project(p.x + math.sin(r) * W.RANGE * reach, 0, p.z + math.cos(r) * W.RANGE * reach)
        if fx then rad = math.min(150, math.sqrt((fx - hx) ^ 2 + (fy - hy) ^ 2) / reach) break end
      end
      local ang = math.deg(math.atan(ty - hy, tx - hx))
      light(hx, hy, math.max(30, rad), 0xEAF0FF, {intensity = 0.85, cone = {angle = ang, width = 2 * W.CONE + 8}})
    end
    light(hx, hy + 14 * k, 20 * k, 0x7A8CA8, {intensity = 0.5})
  end
end

return M
