-- slices: a wide picture kept as columns, so only the ones on the screen are in memory (on the console a picture needs one block of the
-- heap, and a 960 px background does not find it once the heap is fragmented). Cut the picture with tools/slice_pic.py, which writes the
-- pieces as assets and a small Lua table that says where each one goes.
--
--   local slices = require("slices")
--   local far = require("far_slices")                 -- written by: uv run tools/slice_pic.py art/far.png games/g FAR --lua games/g/far_slices.lua
--   slices.draw(far, -cam_x * 0.3, 0)                 -- draws only the columns that touch the screen (480 wide); returns how many it drew
--   slices.draw(far, x, y, {flip_x = true, dim = 0.6})-- the picture mirrored as a whole (its columns swap sides), with any img option
--   slices.preload(far, cam_x, 480)                   -- reads the columns about to come in (behind a still screen), so none waits when it appears
local M = {}

local look = {}

-- draws the columns of `def` that show: def = {w, h, slices = {{id, x, w}...}}; (x, y) is where the picture's top-left goes
function M.draw(def, x, y, opts, view_w)
  view_w = view_w or 480
  for k in pairs(look) do look[k] = nil end
  if opts then for k, v in pairs(opts) do look[k] = v end end
  local flip, drawn = look.flip_x, 0
  for _, s in ipairs(def.slices) do
    local dx = flip and (x + def.w - s.x - s.w) or (x + s.x)
    if dx < view_w and dx + s.w > 0 then
      img(s.id, dx, y or 0, look)
      drawn = drawn + 1
    end
  end
  return drawn
end

-- reads the pictures of the columns that show from `x` (the picture's left edge on the screen) across `view_w`
function M.preload(def, x, view_w)
  view_w = view_w or 480
  local ids = {}
  for _, s in ipairs(def.slices) do
    if x + s.x < view_w and x + s.x + s.w > 0 then ids[#ids + 1] = s.id end
  end
  return preload({images = ids})
end

return M
