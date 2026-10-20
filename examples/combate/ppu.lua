-- ppu: every effect a scene can leave on the screen, put back. A scene that uses windows, a mosaic, a fade or per-line tables calls
-- this when it begins, so what the one before it was doing never shows in it.
local M = {}

function M.reset()
  line_off()
  fx_off()
  window_off(0)
  window_off(1)
  objwindow(nil)
  mosaic(1, 1, 1, 1)
  show(ALL)
  clip()
  camera()
end

-- A circle of the picture about (cx, cy), radius r: window 0 with a span on each line, and nothing shows outside it.
-- r <= 0 shows nothing, r large shows all (iris_off ends it).
function M.iris(cx, cy, r)
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

function M.iris_off()
  window_off(0)
  line_off()
end

return M
