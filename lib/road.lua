-- road: a road going away into the distance, as OutRun, Space Harrier and Road Rash drew it (Louis Gorenfeld's
-- "Lou's Pseudo 3d Page"): each screen line below the horizon is a slice of the road at its own distance, drawn from
-- one row of a tiled background (grass, kerb, road, line) scaled by the distance with line_affine, slid sideways for
-- the curves (the curve's bend adds up line by line) and coloured in bands by line_pal, so stripes come towards you.
-- Hills raise and lower the horizon of each segment. Things on the road (cars, signs) are placed with road:project.
--
--   local road = require("road")
--   r = road.new({layer = 2, row = 0, rows = 2, map_w = 256, horizon = 48, width = 2000, camera_h = 300, fov = 240,
--                 segment = 200, stripe_pal = {{2, 0x3C9C3C, 0x2C7C2C}, {3, 0xFFFFFF, 0xC01010}}})
--   r:add(400, 0, 0) r:add(200, 1.5, 0) r:add(300, 0, -40) ...   -- segments: length, curve (bend per segment), hill (y change)
--   r:update(speed)                -- the car moves ahead that many units a tick; r.z is where it is
--   r:draw(steer)                  -- the lines of this frame (in _draw, before sprites); steer: the car's x on the road, -1..1
--   x, y, scale, visible = r:project(z, x_on_road)   -- where something at distance z (ahead of the car) and road x (-1..1) shows
--
-- The background `layer` must be in affine mode with a map whose rows `row` and `row + 1` (two stripes of the road's
-- cross-section, one per band: the kerb red then white, the grass light then dark) are the road across `map_w`
-- pixels: the road's left kerb at map x 0, its right at map_w. stripe_pal gives, per palette entry, the two colours
-- that alternate by band (so the same tiles serve both bands). Nothing of this is in pixels of the console; the units
-- are the road's (width 2000 is the road's width in them).
local M = {}
local R = {}
R.__index = R

function M.new(opts)
  opts = opts or {}
  local r = setmetatable({layer = opts.layer or 2, row = opts.row or 0, rows = opts.rows or 2, map_w = opts.map_w or 256,
                          horizon = opts.horizon or 48, width = opts.width or 2000, camera_h = opts.camera_h or 300,
                          fov = opts.fov or 240, segment = opts.segment or 200, stripe_pal = opts.stripe_pal or {},
                          segments = {}, length = 0, z = 0, band_px = opts.band_px or 8}, R)
  return r
end

function R:add(length, curve, hill)
  local seg = {z0 = self.length, length = length, curve = curve or 0, hill = hill or 0}
  self.segments[#self.segments + 1] = seg
  self.length = self.length + length
  return seg
end

function R:segment_at(z) -- the segment holding z (the road loops)
  z = z % math.max(self.length, 1)
  for _, s in ipairs(self.segments) do
    if z >= s.z0 and z < s.z0 + s.length then return s, z - s.z0 end
  end
  return self.segments[#self.segments], 0
end

function R:update(speed)
  self.z = (self.z + (speed or 0)) % math.max(self.length, 1)
end

-- the lines of this frame: for each screen line below the horizon, the distance it looks at, the road's centre there
-- (the curves adding up), its width on screen, and the band's colours
function R:draw(steer)
  local H, hor, layer = 160, self.horizon, self.layer
  local x_cam = (steer or 0) * self.width / 2 -- the camera's x on the road
  local dx, cum = 0, 0 -- the curve's bend per line, and the road's centre offset so far (in road units)
  for y = hor + 1, H - 1 do
    local d = self.camera_h * self.fov / (y - hor) -- distance to the line, in road units
    local z = self.z + d
    local s = self:segment_at(z)
    dx = dx + s.curve * 0.01
    cum = cum + dx
    local scale = self.fov / d                                -- screen pixels per road unit
    local center = 120 + (cum - x_cam) * scale                -- the road's centre on screen
    local map_per_px = self.map_w / (self.width * scale)      -- map pixels per screen pixel
    local band = math.floor(z / self.segment) % 2
    local map_x0 = self.map_w / 2 - center * map_per_px       -- the map x seen at screen x 0
    line_affine(layer, y, map_x0, (self.row + band % self.rows) * self.band_px + self.band_px / 2, map_per_px, 0)
    for _, p in ipairs(self.stripe_pal) do line_pal(y, p[1], band == 0 and p[2] or p[3]) end
  end
  self.cum_last = cum
end

function R:project(z_ahead, x_on_road)
  if z_ahead <= 1 then return 0, 0, 0, false end
  local scale = self.fov / z_ahead
  local y = self.horizon + self.camera_h * scale
  local x = 120 + (x_on_road or 0) * self.width / 2 * scale
  return x, y, scale, y < 160
end

return M
