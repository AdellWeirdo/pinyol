-- hearing: what she hears, the board's microphone as loudness only and never recorded, D-31
-- (a port of audreygotchi/core/hearing.py).
--
-- The platform turns the microphone's level into three kinds of sound and hands them in: "voz" (someone talking
-- near her), "ruido" (a sudden loud noise) and "musica" (sound that goes on). The owner's yes, 2026-10-05:
-- - a voice: she turns her ears to you, and someone is there, as if a button had been pressed;
-- - a loud noise: a fright (stress up a little); a skittish or stressed one hides from it;
-- - music: she sways along;
-- - hiding, she answers your voice from her room, and the seek bar marks it for a moment;
-- - asleep at night nothing wakes her (the night rule); by day a loud noise does, a voice not.
-- Ajustes > Micro switches all of it off. Each kind has a cooldown, so a conversation is not a stream of
-- reactions.
local util = require("core.util")
local M = {}

local function due(s, kind, now_ms)
  local till = util.int(util.get(s._heard_until, kind, 0))
  local cooldown = s.HEAR_COOLDOWN_MS[kind]
  -- set on another tick base (a reboot, a wrap): forget it
  return now_ms >= till or till - now_ms > cooldown
end

-- A loud noise frightens her: stress up a little; a skittish or stressed one hides.
function M.fright(s, now_ms)
  s.stress = s:_clamp_stat(s.stress + s.FRIGHT_STRESS)
  local skittish = util.contains(s.quirks, "Huidiza") or s.stress >= 70.0
  local unwell = s.sick or s.in_critical
  if skittish and not unwell and s:_may_hide(now_ms) then
    s:_hide(now_ms) -- she runs and hides
    s._hide_cd_until_ms = util.int(now_ms) + 12000
  else
    s:_emit_sound("susto")
  end
  s:mark_dirty()
end

local DEAF_MODES = {"farewell", "birth", "sancho_intro", "grow"}

function M.hear(s, kind, now_ms)
  if s.HEAR_COOLDOWN_MS[kind] == nil or not s.mic_on then
    return
  end
  if s.powered_off or s.deep_sleep or util.contains(DEAF_MODES, s.mode) then
    return
  end
  if util.int(s.sitter_until) ~= 0 then -- with Sancho: nobody home to hear
    return
  end
  s._frame_ms = util.int(now_ms) -- the platform's tick, as update() keeps it
  if not due(s, kind, now_ms) then
    return
  end
  s._heard_until[kind] = util.int(now_ms) + s.HEAR_COOLDOWN_MS[kind]
  if s.sleeping then
    if kind == "ruido" and not s:is_night() then -- woken by a noise, as by B: she judges it
      s.sleeping = false
      s:_emit_sound("despierta")
      s:_log_event("La despertó un ruido")
      s:compute_mood()
      s:mark_dirty()
    end
    return
  end
  if kind == "voz" and not s._was_away then
    s._input_pending_ts = s.clock:now() -- someone is here (no greeting from it)
  end
  if s.hidden then
    if kind == "voz" then -- she answers from her room
      s.seek_hint_until = util.int(now_ms) + s.SEEK_HINT_MS
      s:_emit_sound("responde")
    end
    return
  end
  if s.mode ~= "main" then
    return -- in a menu or a game: heard, not shown
  end
  if kind == "voz" then
    s:_emit_sound("te_oye")
  elseif kind == "ruido" then
    M.fright(s, now_ms)
  elseif kind == "musica" then
    s.excitement = s:_clamp_stat(s.excitement + 3.0)
    s:_emit_sound("musica")
  end
  s:mark_dirty()
end

return M
