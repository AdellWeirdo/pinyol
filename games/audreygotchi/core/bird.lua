-- bird: a sparrow at the window (a port of audreygotchi/core/bird.py; the owner's friend, 2026-10-10: the real
-- Audrey cannot stand birds). Now and then, by day and dry, one lands outside the window of the room she is in
-- (events "pajaro": only the rooms with one, WINDOW_ROOMS). She glares at it, stressed. B shoos it, and that press
-- does nothing else: she is glad of you. Left alone, it goes after BIRD_MS; it is gone too once she is in another
-- room. Not saved: a moment, not a state.
local util = require("core.util")
local M = {}

M.WINDOW_ROOMS = {"bg_living.png", "bg_studio.png"}
M.BIRD_MS = 25000
M.STRESS_IN, M.STRESS_SHOO, M.LOVE_SHOO = 4.0, 5.0, 3.0

local function set(v) return v ~= nil and v ~= 0 end -- Python's bool() of a number field

function M.window_here(s)
  local files = s.BG_FILES
  return util.contains(M.WINDOW_ROOMS, files[util.int(s.current_scene) % #files + 1])
end

-- A bird at the window she can see.
function M.here(s)
  return set(s.bird_until) and util.int(s.bird_room) == util.int(s.current_scene)
end

function M.land(s, now_ms)
  s.bird_until, s.bird_room = util.int(now_ms) + M.BIRD_MS, util.int(s.current_scene) -- transient (not saved)
  s.stress = s:_clamp_stat(s.stress + M.STRESS_IN)
  s:mark_dirty()
end

-- B while it is there: off it goes, and she is glad of you.
function M.shoo(s, now_ms)
  s.bird_until = 0
  s.stress = s:_clamp_stat(s.stress - M.STRESS_SHOO)
  s.affection = math.min(100.0, s.affection + M.LOVE_SHOO)
  s.overlay_text, s.overlay_until = "¡Y no vuelvas!", util.int(now_ms) + 900
  s:_emit_sound("pajaro_vuela")
  s:compute_mood()
  s:mark_dirty()
end

-- Each frame: gone with her out of its room; flown off on its own after BIRD_MS.
function M.update(s, now_ms)
  if not set(s.bird_until) then
    return
  end
  local left = util.int(s.bird_until) - util.int(now_ms)
  if util.int(s.bird_room) ~= util.int(s.current_scene) or left > 2 * M.BIRD_MS then -- (a wrapped tick)
    s.bird_until = 0
    s:mark_dirty()
  elseif left <= 0 then
    s.bird_until = 0
    s:_emit_sound("pajaro_vuela")
    s:mark_dirty()
  end
end

return M
