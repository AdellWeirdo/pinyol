-- action_runtime: a bath and a cuddle, done (a port of audreygotchi/core/action_runtime.py).
local util = require("core.util")
local M = {}

function M.act_bath(s, now_ms)
  if now_ms < s._bath_cd_until_ms then
    return -- still shaking herself dry: the press is dropped (2026-10-09)
  end

  if s.in_critical then
    s.overlay_text = "Baño no, estoy malita"
    s.overlay_until = now_ms + 900
    s:_log_event("Baño bloqueado (crítico)")
    s:_register_interaction("Baño", false)
    return
  end

  if s.dirt <= 10 then
    s.overlay_text = "¡Pero si ya brillo!"
    s.overlay_until = now_ms + 900
    s:_log_event("Baño innecesario")
    s:_register_interaction("Baño", false)
    return
  end

  -- v9 §7.4
  s.dirt = math.max(0.0, s.dirt - 40.0)
  s.affection = math.min(100.0, s.affection + 2.0)
  s._bath_cd_until_ms = now_ms + util.int(s.BATH_COOLDOWN_SEC * 1000) -- transient (ms: reset on load)
  s:_emit_sound("bano") -- heard on the board, and the platform reacts to it

  if s.sleeping then
    s.sleeping = false
    s:_log_event("Se despertó para baño")
  end

  s.overlay_text = "¡Splash! Brrr..."
  s.overlay_until = now_ms + 900
  s:_log_event("Baño")
  s:_register_interaction("Baño", true)
end

function M.act_hug(s, now_ms)
  if now_ms < s._hug_cd_until_ms then
    return -- her purr still playing: the press is dropped (2026-10-09)
  end
  local many, window = s.HUG_MASH[1], s.HUG_MASH[2]
  local recent = {}
  for _, t in ipairs(s._hug_log) do
    local ago = now_ms - t
    if 0 <= ago and ago < window then recent[#recent + 1] = t end
  end
  s._hug_log = recent -- transient (not saved)
  if #s._hug_log >= many then -- cuddled and cuddled: very much a cat, she has had enough
    s._hug_log = {}
    s.stress = s:_clamp_stat(s.stress + 5.0)
    s:_emit_sound("enfado")
    s._hug_cd_until_ms = now_ms + util.int(s.PET_COOLDOWN_SEC * 1000)
    s.overlay_text, s.overlay_until = "¡Ya vale, humana!", now_ms + 900
    s:_log_event("Harta de mimos")
    s:_register_interaction("Mimos", false)
    return
  end
  s._hug_log[#s._hug_log + 1] = now_ms

  local gain = s.affection > 85.0 and 2.0 or 10.0 -- v9 §7.3: diminishing returns
  s.affection = math.min(100.0, s.affection + gain)
  s.stress = s:_clamp_stat(s.stress - 8.0) -- D-12

  s._hug_cd_until_ms = now_ms + util.int(s.PET_COOLDOWN_SEC * 1000) -- transient (ms: reset on load)
  s:_emit_sound("mimos")
  s.overlay_text = "Prrrr..."
  s.overlay_until = now_ms + 900
  s:_log_event("Mimos")
  s:_register_interaction("Mimos", true)
end

return M
