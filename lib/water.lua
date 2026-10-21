-- water: a surface that ripples when something falls in, as Michael Hoffman's springs (Tuts+, "Make a splash with
-- dynamic 2D water effects"): the surface is a row of springs, each pulled back to its rest height and dragged by its
-- neighbours, so a splash runs out in waves to both sides and dies down.
--
--   local water = require("water")
--   pond = water.new({x = 0, y = 200, w = 480, springs = 48, colour = 0x2060C0, deep = 0x103060, alpha = 0.6})
--   pond:splash(x, speed)         -- something hits the surface at x going down at that speed (pixels a tick)
--   pond:update()                 -- once a tick
--   pond:draw()                   -- the water from its surface down to y + depth (120), as polygons
--   pond:height(x)                -- the surface's height at x, to float things on it
--
-- k: the pull back to rest (0.025); damp: how fast a wave dies (0.025); spread: how much neighbours drag each other
-- (0.25, over 8 passes); depth: pixels of water drawn below the rest line (120).
local M = {}
local W = {}
W.__index = W

function M.new(opts)
  opts = opts or {}
  local w = setmetatable({x = opts.x or 0, y = opts.y or 160, w = opts.w or 480, n = opts.springs or 48,
                          k = opts.k or 0.025, damp = opts.damp or 0.025, spread = opts.spread or 0.25,
                          depth = opts.depth or 120, colour = opts.colour or 0x2060C0, deep = opts.deep,
                          alpha = opts.alpha, h = {}, v = {}, ld = {}, rd = {}}, W)
  for i = 1, w.n do w.h[i], w.v[i] = 0, 0 end
  return w
end

function W:splash(x, speed)
  local i = math.floor((x - self.x) / self.w * (self.n - 1) + 0.5) + 1
  if i < 1 or i > self.n then return end
  self.v[i] = self.v[i] + (speed or 4)
end

function W:update()
  local h, v = self.h, self.v
  for i = 1, self.n do
    v[i] = v[i] - self.k * h[i] - self.damp * v[i]
    h[i] = h[i] + v[i]
  end
  local ld, rd = self.ld, self.rd
  for _ = 1, 8 do
    for i = 1, self.n do
      ld[i] = i > 1 and self.spread * (h[i] - h[i - 1]) or 0
      rd[i] = i < self.n and self.spread * (h[i] - h[i + 1]) or 0
    end
    for i = 1, self.n do
      if i > 1 then v[i - 1] = v[i - 1] + ld[i] h[i - 1] = h[i - 1] + ld[i] end
      if i < self.n then v[i + 1] = v[i + 1] + rd[i] h[i + 1] = h[i + 1] + rd[i] end
    end
  end
end

function W:height(x) -- the surface at x (between two springs)
  local t = (x - self.x) / self.w * (self.n - 1)
  local i = math.floor(t)
  if i < 0 then return self.y + self.h[1] end
  if i >= self.n - 1 then return self.y + self.h[self.n] end
  local f = t - i
  return self.y + self.h[i + 1] * (1 - f) + self.h[i + 2] * f
end

function W:draw()
  local step = self.w / (self.n - 1)
  local opts = self.alpha and {alpha = self.alpha} or nil
  for i = 1, self.n - 1 do
    local x0, x1 = self.x + (i - 1) * step, self.x + i * step
    local y0, y1 = self.y + self.h[i], self.y + self.h[i + 1]
    local bottom = self.y + self.depth
    if opts then
      poly({x0, y0, x1, y1, x1, bottom, x0, bottom}, self.colour, true, opts)
    else
      poly({x0, y0, x1, y1, x1, bottom, x0, bottom}, self.colour, true)
    end
  end
  if self.deep then
    for i = 1, self.n - 1 do
      local x0, x1 = self.x + (i - 1) * step, self.x + i * step
      line(x0, self.y + self.h[i], x1, self.y + self.h[i + 1], self.deep)
    end
  end
end

return M
