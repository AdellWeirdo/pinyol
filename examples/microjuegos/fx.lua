-- fx: a round window on the picture: only the circle about (cx, cy) shows (window 0 with a span on each line), the rest is black.
local M = {}

function M.circle(cx, cy, r)
  window(0, 0, 0, SCREEN_W // 2, SCREEN_H // 2, ALL)
  window_out(0)
  for y = 0, SCREEN_H // 2 - 1 do
    local dy = y - cy
    if r > 0 and math.abs(dy) < r then
      local half = math.sqrt(r * r - dy * dy)
      line_window(0, y, math.max(0, math.floor(cx - half)), math.min(SCREEN_W // 2, math.ceil(cx + half)))
    else
      line_window(0, y, 0, 0)
    end
  end
end

return M
