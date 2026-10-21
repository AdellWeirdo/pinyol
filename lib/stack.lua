-- stack: a thing seen from above as a stack of slices (sprite stacking, as NIUM and the PICO-8 demos do it): a picture
-- whose frames are the horizontal slices of an object, bottom first, drawn one over the other, each a little higher
-- and all turned by the same angle, so a car or a tower turns in 3D from a dozen small drawings. Each angle the stack
-- is drawn at is made once on a canvas and kept, so a still or slowly turning object costs one img() a frame.
--
--   local stack = require("stack")
--   car = stack.new("CAR", {slices = 8, w = 16, h = 24, spacing = 1, scale = 2, steps = 32})   -- or stack.new({"S0", "S1", ...}, {w, h, ...})
--   car:draw(x, y, angle)        -- its bottom slice's centre at (x, y), turned by angle (degrees; snapped to one of steps)
--
-- slices: how many frames the picture has (the stack's height); w, h: a frame's size; spacing: pixels between slices
-- (1); scale: the whole thing scaled (1); steps: angles kept (32). stack.clear() frees every canvas made.
local M = {}
local S = {}
S.__index = S
local made = {}

-- new(id, opts): the slices are the frames of picture id (opts.slices of them), or id is a list of pictures, one a slice
function M.new(id, opts)
  opts = opts or {}
  local ids = type(id) == "table" and id or nil
  local slices = ids and #ids or opts.slices
  assert(slices and opts.w and opts.h, "stack.new: slices, w and h are needed")
  local diag = math.ceil(math.sqrt(opts.w * opts.w + opts.h * opts.h))
  local s = setmetatable({id = ids and ids[1] or id, ids = ids, slices = slices, w = opts.w, h = opts.h, spacing = opts.spacing or 1,
                          scale = opts.scale or 1, steps = opts.steps or 32, diag = diag}, S)
  s.cw = math.ceil(diag * s.scale) + 2
  s.ch = math.ceil((diag + (s.slices - 1) * s.spacing) * s.scale) + 2
  return s
end

function S:canvas_for(k) -- the canvas of angle step k, made on first use
  local name = self.id .. "_stack" .. k
  if made[name] then return name end
  canvas(name, self.cw, self.ch)
  target(name)
  local angle = k * 360 / self.steps
  local cx, base = self.cw / 2, self.ch - 1 - self.diag * self.scale / 2
  for i = 0, self.slices - 1 do
    local y = base - i * self.spacing * self.scale
    local pic, frame = self.id, i
    if self.ids then pic, frame = self.ids[i + 1], 0 end
    img(pic, cx - self.w * self.scale / 2, y - self.h * self.scale / 2, {frame = frame, angle = angle, scale = self.scale})
  end
  target()
  made[name] = true
  return name
end

function S:draw(x, y, angle, opts)
  local k = math.floor((angle or 0) / 360 * self.steps + 0.5) % self.steps
  local name = self:canvas_for(k)
  local base = self.ch - 1 - self.diag * self.scale / 2
  img(name, x - self.cw / 2, y - base, opts)
end

function M.clear()
  for name in pairs(made) do canvas(name, 1, 1) end
  made = {}
end

return M
