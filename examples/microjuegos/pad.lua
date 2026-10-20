-- pad: the buttons a microgame reads, from the real ones or, in the demonstration, from the game's own bot. A game asks pad.btn / pad.btnp and
-- does not know which; its `bot` function (made for the demonstration and the tests) says which buttons it presses this tick.
local M = {}
local pressed, before = {}, {}

function M.bot_input(set)
  before, pressed = pressed, set or {}
end

M.bot = false

function M.btn(n) if M.bot then return pressed[n] == true end return btn(n) end
function M.btnp(n) if M.bot then return pressed[n] == true and before[n] ~= true end return btnp(n) end
function M.any()
  for _, n in ipairs({"a", "b", "c", "up", "down", "left", "right"}) do if M.btn(n) then return true end end
  return false
end

return M
