-- game_init: a fresh game's every field (a port of audreygotchi/core/game_init.py).
local util = require("core.util")
local memory = require("core.memory")
local v2_gameplay = require("core.v2_gameplay")
local M = {}

function M.init_fresh(s)
  -- the first row cares for her, each button under the top bar's bar it fills; the second is her world, then
  -- what you look up, Ajustes last (the owner, 2026-10-08)
  s.menu_items = {"Feed", "Play", "Cuddle", "Bath", "Sleep", "Sitter", "Album", "Status", "Settings"}
  s.selected_index = 0
  s._menu_seen = nil -- the list the cursor index refers to

  -- modes: "main" | "status" | "settings" | "action_heal" | "action_feed" | "action_play" | "action_minigame" |
  -- "farewell" | "tech" | "system"
  s.mode = "main"
  s.status_page = 0
  s.status_focus = nil -- "H" | "F" | "E" | "S" | nil
  s.tech_page = 0
  s.settings_index = 0
  s.system_index = 0
  s.qa_mode = false
  s.brightness_level = 2
  s.sound_mode = 0 -- 0 on, 1 off, 2 night
  s.volume = 1     -- 0 bajo, 1 medio, 2 alto
  s.guide_seen = false
  s.ui_style = 0
  s.screen_off_idx = 0
  s.mic_on = true
  s.friends_on = true
  s.language = "es"
  s.qa_balance_preset = "equilibrada"

  -- action screens
  s.heal_choice = 0
  s.feed_choice = 0
  s.play_choice = 0
  s.minigame_action = nil
  s.minigame_cursor = 0.0
  s.minigame_dir = 1
  s.minigame_speed = 60.0
  s.minigame_target_center = 50.0
  s.minigame_target_half = 12.0
  s._minigame_last_ms = 0

  -- identity
  s.name = "Audrey"
  s.cycle = 1
  s.day = 1
  s.age_days = 0
  s.birth_timestamp = s.clock:now()

  -- stats (0..100)
  s.hunger = 80.0
  s.affection = 70.0
  s.energy = 80.0
  s.health = 90.0
  s.dirt = 10.0
  s.weight_kg = 3.0
  s.height_cm = 27.0

  s.phase = "Cachorro"
  s.sick = false
  s.in_critical = false
  s.sleeping = false
  s.deep_sleep = false
  s.powered_off = false
  s.light_on = true

  -- the five rooms
  s.scenarios = {"Salón", "Cocina", "Rascador", "Estudio", "WC"}
  s.current_scene = 0
  s.hidden_scene = -1
  s.hidden = false
  s.seek_misses = 0
  s.seek_searched = 0
  s.seek_found = 0
  s.seek_first_try = 0
  s.seek_play = false
  s.feather_level = 0
  s.feather_streak = 0
  s.knot_level = 0
  s.knot_streak = 0
  for _, game in ipairs({"boxes", "simon", "laser", "brush"}) do
    s[game .. "_level"] = 0
    s[game .. "_streak"] = 0
  end
  s.sitter_until = 0
  s.sitter_day = 0
  s.sitter_yes = false
  s.sancho_intro_at = 0
  s.ask, s.ask_yes, s.ask_until = nil, true, 0
  s.bed_at = 0
  s.tucked_at = 0
  s.nickname = ""
  s.intro_step = 0
  s.grow_from = ""
  s.grow_to = ""
  s._grow_start_ms = 0
  s._grow_revealed = false
  s._grow_calls = 0
  s._grow_call_ms = 0
  s.bird_until = 0
  s.bird_room = 0
  s._intro_next_ms = 0
  s._sim_ts = 0
  s.wants_play = false

  -- personality (v11: 2-3 quirks a cycle)
  s.quirks = util.sample(s.QUIRKS, util.choice({2, 3}))
  s.personality = s:_generate_personality()
  s.memory = memory.fresh()
  s.trust_bond = 52.0
  s.stress = 24.0
  s.excitement = 46.0
  s.confidence = 50.0
  s._last_interaction_action = "init"
  s._last_interaction_ok = true
  s._interactions_total = 0
  s._rejections_total = 0
  s._action_ok_counts = {}
  s._action_reject_counts = {}
  s._phase_seconds = {}
  for _, p in ipairs(s.PHASE_ORDER) do s._phase_seconds[p] = 0 end

  s.last_events = {}
  s.overlay_text = nil
  s.overlay_until = 0

  s.mood = "calm"
  s.mood_icon = ""
  s._mood_since = 0
  s._complain_cd_until_ms = 0
  s._reject_cd_until_ms = 0
  s._purr_cd_until_ms = 0
  s._hug_cd_until_ms = 0
  s._feed_cd_until_ms = 0
  s._play_cd_until_ms = 0
  s._bath_cd_until_ms = 0
  s._hug_log = {}

  s.growth_points = 0.0
  s.critical_seconds = 0
  s._evo_overlay_cd_until_ms = 0
  s._critical_streak_sec = 0
  s._auto_vet_cd_sec = 0
  s.vet_softlock_until_ts = 0
  s._low_health_streak_sec = 0
  s._light_off_minutes = 0
  s._hide_cd_until_ms = 0
  s._last_wake_ts = 0
  -- simulated seconds (not now_ms: a catch-up simulates hours with one now_ms)
  s._awake_sec = s.AUTO_SLEEP_GRACE_SEC -- no grace pending: she may doze already
  s._nap_sec = 0
  s.last_input_ts = s.clock:now()
  s.morning_wake_ts = 0
  s._input_pending_ts = 0
  s._frame_ms = 0
  s._away = false
  s._was_away = false
  s._need_called = nil
  s.game_result, s.game_result_seq = nil, 0
  s.new_sticker, s.new_sticker_seq = nil, 0
  s.litter, s._litter_sec, s.bath_choice = 0, 0, 0
  s._sim_second_accum = 0
  s._sec_non_critical = 0
  s._sec_health_h = 0
  s._sec_health_e = 0
  s._sec_health_d = 0
  s._sec_health_f = 0

  s._last_tick_ts = s.clock:now()

  s.care_points_total = 0.0
  s.care_minutes_total = 0
  s.name_preset_idx = 0

  s.life_deadline_day = s.LIFE_MIN_DAYS
  s.farewell_started = false
  s.farewell_step = 0
  s.farewell_next_ms = 0
  s.birth_step = 0
  s.birth_next_ms = 0
  s.farewell_done = false
  s.farewell_choice = 0
  s.farewell_memories = false
  s.farewell_scheduled_day = 0
  s.daily_metrics = {}

  s._dirty = true

  s.favorite_food = ""
  s.disliked_food = ""
  s.sick_type = nil
  s.sick_cause = ""
  s.sick_since_ms = 0
  s.indigestion_until_ms = 0
  s._med_doses = 0
  s._snack_streak = 0
  s._ev_min = 0
  s._ev_ring = {}
  s._ev_prev = nil
  s._later = {}            -- {{frame ms, sound}}: what she does a moment later
  s._looking_until = 0
  s._heard_until = {}
  s.seek_hint_until = 0
  s.friend_visit, s.friend_until = nil, 0
  s._friend_visit_ts, s._friend_candidates = nil, {}
  s.visitor, s.visitor_until = nil, 0
  s.visitor_next = 0
  s._ev_last_big = -1000000
  s._ev_ready = {}
  s.events_once = {}
  s.legacy = {}
  s.stars = 0
  s.weather = nil

  v2_gameplay.init_v2_state(s)
end

return M
