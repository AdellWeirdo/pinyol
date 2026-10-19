-- save: a game to a table for pinyol's store() and back. The fields kept are the board game's payload
-- (audreygotchi/core/payload_codec.py, schema 17); everything else starts fresh on load, as it did there: a
-- moment's cooldowns, what she was about to do, a game's board, a visit on screen. Then the same fix-ups.
local util = require("core.util")
local State = require("core.state")
local Clock = require("core.clock")
local v2_gameplay = require("core.v2_gameplay")
local M = {}

M.VERSION = 1
M.KEYS = {
  "name", "cycle", "birth_timestamp", "age_days", "name_preset_idx", "brightness_level", "sound_mode", "volume",
  "guide_seen", "ui_style", "screen_off_idx", "mic_on", "friends_on", "language", "selected_index", "mode",
  "status_page", "status_focus", "tech_page", "settings_index", "qa_mode", "qa_balance_preset", "heal_choice",
  "litter", "_litter_sec", "feed_choice", "play_choice", "minigame_action", "minigame_cursor", "minigame_dir",
  "minigame_speed", "minigame_target_center", "minigame_target_half", "phase", "sick", "sleeping",
  "deep_sleep", "powered_off", "in_critical", "light_on", "hidden", "hidden_scene", "current_scene", "seek_misses",
  "seek_searched", "seek_found", "seek_first_try", "seek_play", "events_once", "memory", "legacy", "stars",
  "weather", "mood", "_mood_since", "feather_level", "feather_streak", "knot_level", "knot_streak",
  "boxes_level", "boxes_streak", "simon_level", "simon_streak", "laser_level", "laser_streak", "brush_level",
  "brush_streak", "sitter_until", "sitter_day", "sancho_intro_at", "grow_from", "grow_to", "bed_at", "tucked_at",
  "nickname", "hunger", "affection", "energy", "health", "dirt", "weight_kg", "height_cm", "quirks", "personality",
  "trust_bond", "stress", "excitement", "confidence", "_last_interaction_action", "_last_interaction_ok",
  "_interactions_total", "_rejections_total", "_action_ok_counts", "_action_reject_counts", "_phase_seconds",
  "last_events", "growth_points", "critical_seconds", "_last_tick_ts", "care_points_total", "care_minutes_total",
  "daily_metrics", "life_deadline_day", "farewell_started", "farewell_scheduled_day", "farewell_step",
  "farewell_done", "vet_softlock_until_ts", "_critical_streak_sec", "_auto_vet_cd_sec",
  "_low_health_streak_sec", "_light_off_minutes", "_last_wake_ts", "sick_type", "sick_cause", "_snack_streak",
  "last_input_ts", "morning_wake_ts", "visitor_next", "save_counter",
}
-- frame ticks (ms) start again at 0 each session: a saved one would wait for a moment that never comes
M.FRAME_MS = {"_minigame_last_ms", "farewell_next_ms", "_hide_cd_until_ms"}

function M.dump(s)
  s.save_counter = (s.save_counter or 0) + 1
  local fields = {}
  for _, k in ipairs(M.KEYS) do fields[k] = util.deepcopy(s[k]) end
  return {v = M.VERSION, base = s.clock.base, now = s.clock:now(), s = fields}
end

function M.load(data, now_ms) -- a game, or nil when data is not one
  if type(data) ~= "table" or data.v ~= M.VERSION or type(data.s) ~= "table" or type(data.base) ~= "table" then
    return nil
  end
  local clock = Clock.new(data.base, math.floor(tonumber(data.now) or 0))
  local s = State.new(clock)
  for _, k in ipairs(M.KEYS) do
    local v = data.s[k]
    if v ~= nil then s[k] = util.deepcopy(v) end
  end
  for _, k in ipairs(M.FRAME_MS) do s[k] = 0 end
  s._frame_ms = now_ms or 0

  -- the board's fix-ups after a load (payload_codec.apply_payload)
  if s.powered_off then s.deep_sleep, s.sleeping = false, false end
  if s.mode == "birth" or s.mode == "sancho_intro" or s.mode == "grow" then s.mode = "main" end
  if s.mode == "action_minigame" or (s.mode or ""):sub(1, 7) == "action_" or s.mode == "ask" then
    s.mode = "main" -- a game's board, a screen's cursor and a question are never saved
    s.minigame_action = nil
  end
  if s.sick_type == "" then s.sick_type = nil end
  v2_gameplay.restore_v2_state_after_load(s)
  s._menu_seen = s:active_menu_items()
  s.selected_index = util.clamp(s.selected_index, 0, #s._menu_seen - 1)
  s.hunger = util.clamp(s.hunger, 0.0, 100.0)
  s.affection = util.clamp(s.affection, 0.0, 100.0)
  s.energy = util.clamp(s.energy, 0.0, 100.0)
  s.health = util.clamp(s.health, 0.0, 100.0)
  s.dirt = util.clamp(s.dirt, 0.0, 100.0)
  s.weight_kg = util.clamp(s.weight_kg, 1.8, 9.5)
  local target_h = s.PHASE_HEIGHT_CM[s.phase] or 33.0
  s.height_cm = util.clamp(s.height_cm + (target_h - s.height_cm) * 0.0025, 24.0, 36.0)
  s.trust_bond = s:_clamp_stat(s.trust_bond)
  s.stress = s:_clamp_stat(s.stress)
  s.excitement = s:_clamp_stat(s.excitement)
  s.confidence = s:_clamp_stat(s.confidence)
  s.volume = util.clamp(s.volume, 0, 2)
  s.sound_mode = util.clamp(s.sound_mode, 0, 2)
  s:_prune_daily_metrics(s:_current_day_key())
  if s.cycle <= 1 then s.name = "Audrey" end
  -- on load (state.py load_blob)
  s.overlay_text = "¡Hola otra vez!"
  s.overlay_until = s._frame_ms + 900
  s:compute_mood()
  s._dirty = false
  return s
end

return M
