-- ui: the one window the game draws its menus and sheets in: dark blue with a light edge, so the white and yellow letters read on it
-- (the theme's own panel is parchment, where they do not).
local M = {}

M.FILL, M.EDGE, M.INK, M.SEL, M.DIM, M.SUB = 0x101830, 0xE8D8B0, 0xFFFFFF, 0xFFE070, 0x8890A8, 0xA8B8D0

function M.box(x, y, w, h)
  rect(x, y, w, h, M.FILL)
  box(x, y, w, h, M.EDGE)
  box(x + 2, y + 2, w - 4, h - 4, 0x3A4A78)
end

return M
