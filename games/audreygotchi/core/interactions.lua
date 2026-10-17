-- interactions: what an interaction leaves in her, the vet, and B held (a port of
-- audreygotchi/core/interactions.py).
local util = require("core.util")
local asks = require("core.asks")
local v2_gameplay = require("core.v2_gameplay")
local memory = require("core.memory")
local lifecycle = require("core.lifecycle")
local M = {}

local function bucket_of(action) -- str(action).split(":", 1)[0].strip() or "Unknown"
  local a = tostring(action)
  local colon = string.find(a, ":", 1, true)
  local head = colon and a:sub(1, colon - 1) or a
  head = head:match("^%s*(.-)%s*$")
  if head == "" then return "Unknown" end
  return head
end

function M.register_interaction(s, action, ok)
  memory.interaction(s, action, ok)
  s._last_interaction_action = tostring(action)
  s._last_interaction_ok = not not ok
  s._interactions_total = s._interactions_total + 1
  local bucket = bucket_of(action)
  if ok then
    s._action_ok_counts[bucket] = util.get(s._action_ok_counts, bucket, 0) + 1
  end
  if not ok then
    s._rejections_total = s._rejections_total + 1
    s._action_reject_counts[bucket] = util.get(s._action_reject_counts, bucket, 0) + 1
  end

  -- Immediate emotional memory per interaction (stress goes apart, per action: D-12).
  if ok then
    s.trust_bond = s:_clamp_stat(s.trust_bond + 0.6 + 0.5 * s:_pf("sociability"))
    s.excitement = s:_clamp_stat(s.excitement + 1.0 + 1.8 * s:_pf("activity"))
    s.confidence = s:_clamp_stat(s.confidence + 0.45 + 0.3 * (1.0 - s:_pf("sociability")))
  else
    s.trust_bond = s:_clamp_stat(s.trust_bond - (0.8 + 0.6 * s:_pf("sensitivity")))
    s.excitement = s:_clamp_stat(s.excitement - (0.7 + 0.6 * (1.0 - s:_pf("sociability"))))
    s.confidence = s:_clamp_stat(s.confidence - (0.5 + 0.3 * s:_pf("sensitivity")))
  end
end

function M.apply_veterinary_care(s, now_ms, automatic)
  -- v9 §7.6: arriving in critical earns 2 min of rest, unless nobody was there to see it
  local severe = s:critical_now() and not s._away
  s:_record_vet_visit()
  memory.first(s, "vet")
  s:_emit_sound("curar")
  v2_gameplay.cure_illness(s, now_ms, "veterinario")
  s.health = 65.0
  s.stress = 40.0
  s.energy = math.min(100.0, s.energy + 10.0)
  s.affection = math.max(0.0, s.affection - 5.0)
  s.in_critical = s:critical_now()
  s._critical_streak_sec = 0
  s._low_health_streak_sec = 0

  if severe then
    s:_set_vet_softlock()
  end

  if automatic then
    s._auto_vet_cd_sec = s.AUTO_VET_COOLDOWN_SEC
    if s.mode == "main" then
      s.overlay_text = "Fui sola al veterinario"
      s.overlay_until = now_ms + 1200
    end
    s:_log_event("Veterinario automático")
  else
    s:_log_event("Veterinario")
  end
end

-- B held (on the platform): cancel, go back.
function M.cancel_action(s, now_ms)
  if s.mode == "ask" then -- back is a No
    asks.answer(s, false, now_ms)
    return
  end
  if s.mode == "guide" then -- the buttons' guide, put away
    s.guide_seen, s.mode = true, "main"
    s:mark_dirty()
    return
  end
  if s.mode == "sitter_confirm" then -- no Sancho today after all
    s.mode = "main"
    s:mark_dirty()
    return
  end
  if s.mode == "status" then
    s:exit_status(now_ms)
    s:compute_mood()
    s:mark_dirty()
    return
  end
  if s.mode == "settings" then
    s:exit_settings(now_ms)
    s:compute_mood()
    s:mark_dirty()
    return
  end
  if s.mode == "system" then -- B held 2 s confirms, destructive options included (D-11)
    s:system_choose(now_ms, true)
    s:compute_mood()
    return
  end
  if s.mode == "tech" then
    s:exit_tech_mode(now_ms)
    s:compute_mood()
    s:mark_dirty()
    return
  end
  if s.mode == "action_bath" then -- Baño's choice, put away
    s.mode = "main"
    s:mark_dirty()
    return
  end
  if s.mode == "action_heal" then
    s:exit_action_heal(now_ms, "Vale, otro rato")
    s:compute_mood()
    s:mark_dirty()
    return
  end
  if s.mode == "action_feed" then
    s:exit_action_feed(now_ms, "Vale, otro rato")
    s:compute_mood()
    s:mark_dirty()
    return
  end
  if s.mode == "action_play" then
    s:exit_action_play(now_ms, "Vale, otro rato")
    s:compute_mood()
    s:mark_dirty()
    return
  end
  if s.mode == "action_minigame" then
    s:exit_action_minigame(now_ms, "Vale, otro rato")
    s:compute_mood()
    s:mark_dirty()
    return
  end
  if s.mode == "birth" then
    lifecycle.skip_birth(s) -- from her second life on, B held skips it
    return
  end
  if s.mode == "farewell" or s.mode == "sancho_intro" or s.mode == "grow" then
    s:mark_dirty()
    return
  end

  s.overlay_text = nil
  s.overlay_until = 0
  s:mark_dirty()
end

return M
