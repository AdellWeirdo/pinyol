-- needs: what she needs most right now, as the menu item that answers it, and her call for it
-- (a port of audreygotchi/core/needs.py).
--
-- The owner, 2026-10-08, from how a Tamagotchi asks for care: a need lights the action that answers it (the
-- platform marks its icon and shows her thinking of it) and she calls once when it comes, so the owner sees
-- what to do without reading. Asleep she needs nothing (let a sleeping pet sleep), unless she is unwell.
local util = require("core.util")
local smells = require("core.litter").smells
local M = {}

M.HUNGER_BELOW = 25.0
M.DIRT_ABOVE = 75.0
M.ENERGY_BELOW = 20.0
M.AFFECTION_BELOW = 25.0

-- The menu item for her most pressing need ("Heal", "Feed", "Bath", "Sleep", "Cuddle", "Play"), or nil.
function M.need(s)
  if s.powered_off or util.int(s.sitter_until) ~= 0 or s.hidden or s.mode == "farewell" then
    return nil
  end
  local unwell = s.sick or s.in_critical
  if (s.sleeping or s.deep_sleep) and not unwell then
    return nil
  end
  local want
  if unwell then
    want = "Heal"
  elseif s.hunger < M.HUNGER_BELOW then
    want = "Feed"
  elseif s.dirt > M.DIRT_ABOVE or smells(s) then -- her coat, or her litter box
    want = "Bath"
  elseif s.energy < M.ENERGY_BELOW and not s.sleeping then
    want = "Sleep"
  elseif s.affection < M.AFFECTION_BELOW then
    want = "Cuddle"
  elseif s.wants_play then
    want = "Play"
  else
    return nil
  end
  if util.contains(s:active_menu_items(), want) then return want end
  return nil
end

-- Each simulated minute: a need new since the last one she called for, she calls (once); asleep, there is
-- nothing to call for.
function M.call_minute(s)
  local want = M.need(s)
  if want and want ~= s._need_called and not (s.sleeping or s.deep_sleep) then
    s:_emit_sound("llama")
    s:_log_event("Te llama")
  end
  s._need_called = want
end

return M
