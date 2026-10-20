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

return M
