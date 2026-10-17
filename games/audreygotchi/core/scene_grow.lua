-- scene_grow: her growing up, shown (a port of audreygotchi/core/scene_grow.py).
-- (the owner, 2026-10-09: it was a 2 s celebration nobody saw.) A new stage calls you (the owner, 2026-10-11: not
-- on its own, unannounced): while she is awake at home it chimes, "crece_aviso", every CALL_FIRST_MS a few times
-- then every CALL_LATER_MS, and the snapshot's grow_due lights the case's LED and the screen's hint. Its scene plays
-- only when you press B (start). Then GROW_MS, drawn by the platform by time: she glows, her silhouette flickers
-- between the stage she leaves and the one she reaches, faster and faster, a flash, and at REVEAL_MS she is
-- revealed, celebrating ("crece", its fanfare). The buttons wait meanwhile. Stages grown while nobody looked show
-- as one, from the first to the last. After the puppy's, Sancho comes to meet her, a moment after it ends.
local util = require("core.util")
local scene_sancho = require("core.scene_sancho")
local M = {}

M.GROW_MS = 8000  -- the whole scene: she glows to GLOW_MS, her silhouette flickers between
M.GLOW_MS = 1600  -- her two stages to FLASH_MS, a flash, and her new self from REVEAL_MS
M.FLASH_MS = 5000
M.REVEAL_MS = 5600
M.FLICKER_FIRST_MS, M.FLICKER_SHRINK, M.FLICKER_MIN_MS = 380, 82, 45 -- each switch 82 % of the last
M.CALL_FIRST_MS, M.CALL_FIRST_TIMES, M.CALL_LATER_MS = 60000, 5, 600000 -- her call: a minute apart, 5
                                                                        -- times, then every 10 minutes

-- When her silhouette switches stage, ms into the scene: faster and faster to the flash. The platform draws by it
-- and its music (speaker "evoluciona") keeps time with it.
function M.flicker_times()
  local out, t, step = {}, M.GLOW_MS, M.FLICKER_FIRST_MS
  while t + step < M.FLASH_MS do
    t = t + step
    out[#out + 1] = t
    step = math.max(M.FLICKER_MIN_MS, step * M.FLICKER_SHRINK // 100)
  end
  return out
end

-- A stage grown: its scene waits to be seen (from the first stage not yet shown).
function M.due(s, old, new)
  if s.grow_to == nil or s.grow_to == "" then
    s.grow_from = tostring(old)
  end
  s.grow_to = tostring(new)
  s:mark_dirty()
end

local function _end(s)
  s.mode, s.grow_from, s.grow_to = "main", "", ""
  if util.int(s.sancho_intro_at) ~= 0 then -- his introduction a moment after it
    local later = util.int(s.clock:now()) + scene_sancho.INTRO_AFTER_SEC
    s.sancho_intro_at = math.max(util.int(s.sancho_intro_at), later)
  end
  s:mark_dirty()
end

-- Each frame: call you while it is due and she can show it; play the scene out.
function M.update(s, now_ms)
  if s.mode == "grow" then
    local t = util.int(now_ms) - util.int(s._grow_start_ms)
    if t < 0 or t > 2 * M.GROW_MS then -- set on another tick base (a reboot, a wrap)
      s._grow_start_ms, t = util.int(now_ms), 0
    end
    if t >= M.REVEAL_MS and not s._grow_revealed then
      s._grow_revealed = true
      s:_emit_sound("crece")
      s:mark_dirty()
    end
    if t >= M.GROW_MS then
      _end(s)
    end
    return
  end
  if not M.can_show(s) then
    s._grow_calls = 0 -- once she can again, the call starts afresh
    return
  end
  local since = util.int(now_ms) - util.int(s._grow_call_ms)
  local gap = M.CALL_LATER_MS
  if s._grow_calls < M.CALL_FIRST_TIMES then gap = M.CALL_FIRST_MS end
  if s._grow_calls == 0 or since >= gap or since < 0 or since > 2 * M.CALL_LATER_MS then
    s._grow_calls = s._grow_calls + 1
    s._grow_call_ms = util.int(now_ms)
    s:_emit_sound("crece_aviso")
    s:mark_dirty()
  end
end

-- A stage grown and not yet shown, and she can show it now: awake at home, on the main screen, well.
function M.can_show(s)
  return (s.grow_to ~= nil and s.grow_to ~= "") and s.mode == "main" and not (
    s.sleeping or s.deep_sleep or s.powered_off or s.hidden or s.sick
    or s.in_critical or scene_sancho.away(s))
end

-- B while it calls: her scene.
function M.start(s, now_ms)
  s.mode = "grow"
  s._grow_start_ms, s._grow_revealed = util.int(now_ms), false
  s.overlay_text, s.overlay_until = nil, 0
  s:_emit_sound("evoluciona") -- her own music, in time with the scene
  s:mark_dirty()
end

-- {ms into the scene, its length}: the platform draws it by time.
function M.timing(s)
  if s.mode ~= "grow" then
    return {0, M.GROW_MS}
  end
  return {math.max(0, math.min(M.GROW_MS, util.int(s._frame_ms) - util.int(s._grow_start_ms))), M.GROW_MS}
end

return M
