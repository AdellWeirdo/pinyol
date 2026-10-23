-- stage: the set. The wall, two sliding ridges and the curtains are the PPU's layers (drawn for next to nothing); the lane, the notes, the bubbles and the
-- judgements are drawn over them.
local M = {}

local scroll_x = 0

function M.init()
  bg(3, {image = "BG_WALL"})
  bg(2, {image = "BG_HILLS2"})
  bg(1, {image = "BG_HILLS"})
  bg(0, {image = "BG_FG"})
end

-- the ridges slide on the beat: the further, the slower
function M.update(speed)
  scroll_x = scroll_x + speed
  scroll(2, scroll_x * 0.5, 0)
  scroll(1, scroll_x, 0)
end

local BUTTON = {a = {0xE05848, "A"}, b = {0x4890E0, "B"}, left = {0x58B060, "L"}, right = {0xE0B040, "R"}}
M.BUTTON = BUTTON

-- a button's mark: a paper disc with its colour and a letter (or an arrow)
function M.mark(button, x, y, r, alpha_state)
  local b = BUTTON[button]
  circ(x, y, r + 2, 0xFFFFFF, true)
  circ(x, y, r, alpha_state == "dim" and 0x8C8C8C or b[1], true)
  if button == "left" then tri(x + r // 2, y - r // 2, x + r // 2, y + r // 2, x - r // 2, y, 0xFFFFFF, true)
  elseif button == "right" then tri(x - r // 2, y - r // 2, x - r // 2, y + r // 2, x + r // 2, y, 0xFFFFFF, true)
  else text(b[2], x, y - 6, {font = "arcade", align = "center", color = 0xFFFFFF}) end
end

return M
