-- tests for group E: core/state_screens.lua, core/settings_system.lua, core/ui_viewmodel.lua
-- (asserts ported from tests/test_rules_v11.py, test_v2_gameplay.py and the board's rules they check)
local util = require("core.util")
local rules = require("core.rules")
local Clock = require("core.clock")

local calls = {} -- what the stubbed modules were asked, by name
local function note(name, ...) calls[#calls + 1] = {name, ...} end
local function called(name)
  for _, c in ipairs(calls) do if c[1] == name then return c end end
  return nil
end

-- the modules these call, stubbed with the Python names they export ------------------------------------------
local medicine = {applied = true, cured = true, message = "¡Adiós, mocos!"}
local stub_returns = {} -- the snapshot's optional values, set per test
LOADED["core.actions"] = {
  heal_left = function(s) note("heal_left") end,
  heal_right = function(s) note("heal_right") end,
  feed_left = function(s) note("feed_left") end,
  feed_right = function(s) note("feed_right") end,
  first_open = function(s, options, choice) note("first_open", options, choice) return 4 end,
  selected_food_name = function(s) return s.FOOD_OPTIONS[s.feed_choice % #s.FOOD_OPTIONS + 1] end,
  selected_feed_type = function(s) return "Comida" end,
  fiesta_item = function(s) return stub_returns.fiesta_item end,
  new_games = function(s) return {"Cepillarla"} end,
  unlocks = function(s) return {Pienso = "Juvenil"} end,
}
LOADED["core.interactions"] = {
  apply_veterinary_care = function(s, now_ms, automatic) note("vet", now_ms, automatic) s.health = 65.0 end,
}
LOADED["core.minigames"] = {
  minigame_profile = function(s, action) return {} end,
  minigame_label = function(s, action) return action and ("label " .. action) or "" end,
  enter_action_minigame = function(s, now_ms, action) s.mode = "action_minigame" end,
  exit_action_minigame = function(s, now_ms, msg) s.mode = "main" end,
  update_minigame = function(s, now_ms) end,
  minigame_apply = function(s, now_ms, action, score) end,
  minigame_confirm = function(s, now_ms) end,
  game_view = function(s) return {} end,
  minigame_left = function(s, now_ms) note("minigame_left", now_ms) end,
  minigame_right = function(s, now_ms) note("minigame_right", now_ms) end,
}
LOADED["core.navigation"] = {
  status_page_left = function(s) s.status_page = (s.status_page - 1) % #s.STATUS_PAGES end,
  status_page_right = function(s) s.status_page = (s.status_page + 1) % #s.STATUS_PAGES end,
  active_menu_items = function(s) return util.copy(s.menu_items) end,
  sync_menu_cursor = function(s) end,
  active_menu_icons = function(s)
    local out = {}
    for _ in ipairs(s.menu_items) do out[#out + 1] = "*" end
    return out
  end,
}
LOADED["core.v2_gameplay"] = {
  apply_medicine = function(s, now_ms)
    if not s.sick then return {applied = false, cured = false, message = "¡Estoy como una rosa!"} end
    if medicine.cured then s.sick = false end
    return medicine
  end,
}
LOADED["core.save_policy"] = {request_now = function(s) note("request_now", s._frame_ms) end}
LOADED["core.lifecycle"] = {
  LEGACY_SHOWN = 6,
  FAREWELL_CHOICES = {"nueva_vida", "recuerdos"},
  start_birth = function(s, now_ms) s.mode = "birth" end,
  heirloom = function(s) return stub_returns.heirloom end,
  birth_timing = function(s) return {300, 3000} end,       -- a tuple as an array (core/lifecycle.lua)
  farewell_timing = function(s) return {10, 20} end,
}
LOADED["core.bird"] = {here = function(s) return false end}
LOADED["core.scene_grow"] = {
  timing = function(s) return 0, 9000 end,                 -- a tuple as two values: read the same
  can_show = function(s) return false end,
}
LOADED["core.scene_sancho"] = {
  why_not = function(s) return stub_returns.sitter_no end,
  intro_step_name = function(s) return "llega" end,
  left_min = function(s) return 0 end,
}
LOADED["core.litter"] = {BATH_OPTIONS = {"Bañarla", "Arenero"}}
LOADED["core.needs"] = {need = function(s) return stub_returns.need end}
LOADED["core.events"] = {stage = function(s) return {0.8, 1.0, {}} end}
LOADED["core.weather"] = {
  kind = function(s) return stub_returns.kind end,
  dark = function(s) return false end,
  dusk = function(s) return false end,
  now = function(s) return stub_returns.weather_now end,
  season = function(s) return stub_returns.season end,
  holiday = function(s) return stub_returns.holiday end,
}
LOADED["core.friends"] = {
  names = function(s) return {} end,
  visiting = function(s) return stub_returns.friend end,
}
LOADED["core.visitors"] = {
  gift = function(s) return stub_returns.visitor_gift end,
  gifts = function(s) return {} end,
  met = function(s) return {} end,
  visiting = function(s) return stub_returns.visitor end,
}
LOADED["core.memory"] = {
  dream = function(s) return stub_returns.dream end,
  fav_game = function(s) return stub_returns.fav_game end,
  fav_room = function(s) return stub_returns.fav_room end,
  fav_time = function(s) return stub_returns.fav_time end,
}
LOADED["core.personality"] = {about = function(s) return stub_returns.about end}

local screens = require("core.state_screens")
local settings = require("core.settings_system")
local vm = require("core.ui_viewmodel")

-- a fake GameState: state_screens' methods, state.py's few the modules call, then the rules -------------------
local T0 = 12 * 3600 -- noon of the clock's first day

local function fresh_fields(s)
  s.menu_items = {"Feed", "Play", "Cuddle", "Bath", "Sleep", "Sitter", "Album", "Status", "Settings"}
  s.selected_index, s.mode, s.status_page, s.status_focus, s.tech_page = 0, "main", 0, nil, 0
  s.settings_index, s.system_index, s.qa_mode, s.brightness_level = 0, 0, false, 2
  s.sound_mode, s.volume, s.ui_style, s.screen_off_idx, s.mic_on, s.friends_on = 0, 1, 0, 0, true, true
  s.language, s.qa_balance_preset = "es", "equilibrada"
  s.heal_choice, s.feed_choice, s.play_choice = 0, 0, 0
  s.minigame_action, s.minigame_cursor, s.minigame_target_center, s.minigame_target_half = nil, 0.0, 50.0, 12.0
  s.name, s.cycle, s.day, s.age_days, s.birth_timestamp, s.name_preset_idx = "Audrey", 1, 1, 0, s.clock:now(), 0
  s.hunger, s.affection, s.energy, s.health, s.dirt = 80.0, 70.0, 80.0, 90.0, 10.0
  s.weight_kg, s.height_cm, s.phase = 3.0, 27.0, "Cachorro"
  s.sick, s.in_critical, s.sleeping, s.deep_sleep, s.powered_off, s.light_on = false, false, false, false, false, true
  s.scenarios = {"Salón", "Cocina", "Rascador", "Estudio", "WC"}
  s.current_scene, s.hidden_scene, s.hidden = 0, -1, false
  s.seek_misses, s.seek_searched, s.seek_found, s.seek_first_try = 0, 0, 0, 0
  s.sitter_until, s.sitter_yes, s.ask, s.ask_yes = 0, false, nil, true
  s.nickname, s.grow_from, s.grow_to, s.wants_play = "", "", "", false
  s.quirks, s.personality = {"Curiosa", "Glotona"}, {activity = 0.5}
  s.memory = {first = {}, stars = {}, stickers = {}, games = {}, rooms = {}, friends = {}, animals = {}}
  s.trust_bond, s.stress, s.excitement, s.confidence = 52.0, 24.0, 46.0, 50.0
  s._last_interaction_action, s._last_interaction_ok = "init", true
  s._interactions_total, s._rejections_total = 0, 0
  s._action_ok_counts, s._action_reject_counts, s._phase_seconds = {}, {}, {Cachorro = 0}
  s.last_events, s.overlay_text, s.overlay_until = {}, nil, 0
  s.mood, s.mood_icon = "calm", ""
  s._hug_cd_until_ms, s._feed_cd_until_ms, s._play_cd_until_ms, s._bath_cd_until_ms = 0, 0, 0, 0
  s.growth_points, s.critical_seconds, s._critical_streak_sec, s._auto_vet_cd_sec = 0.0, 0, 0, 0
  s.vet_softlock_until_ts, s._frame_ms, s._last_tick_ts = 0, 0, s.clock:now()
  s.game_result, s.game_result_seq, s.new_sticker, s.new_sticker_seq = nil, 0, nil, 0
  s.litter, s.bath_choice = 0, 0
  s.care_minutes_total, s.life_deadline_day = 0, 40
  s.farewell_started, s.farewell_done, s.farewell_choice, s.farewell_memories = false, false, 0, false
  s.farewell_scheduled_day = 0
  s._dirty = true
  s.favorite_food, s.disliked_food, s.sick_type = "Latas", "Yogurt", nil
  s.seek_hint_until, s.legacy, s.stars = 0, {}, 0
end

local G = {}
for k, f in pairs(screens) do G[k] = f end
G.mark_dirty = function(s) s._dirty = true end
G._log_event = function(s, txt)
  local e = s.last_events
  e[#e + 1] = txt
  if #e > 10 then table.remove(e, 1) end
end
G._emit_sound = function(s, name) s.sound = name s.sound_seq = s.sound_seq + 1 end
G._init_fresh = function(s) fresh_fields(s) end
G.can_edit_name = function(s) return util.int(s.cycle) >= 2 end
G.set_name = function(s, nm)
  if not s:can_edit_name() then s.name = "Audrey" return false end
  s.name = nm
  s:mark_dirty()
  return true
end
G.cycle_name_preset = function(s)
  s.name_preset_idx = (s.name_preset_idx + 1) % #s.NAME_PRESETS
  s:set_name(s.NAME_PRESETS[s.name_preset_idx + 1])
  return s.name
end
G.indicators = function(s)
  return {H = util.int(s.hunger), F = util.int(s.affection), E = util.int(s.energy), S = util.int(s.health)}
end
G.current_label = function(s) return s.menu_items[s.selected_index + 1] end
G._evaluation_metrics_7d = function(s)
  return {avg_f_7d = 71.9, avg_s_7d = 0.0, critical_minutes_7d = 3.0, vet_visits_7d = 1.0, samples_min_7d = 10.0}
end
G._care_quality_01 = function(s) return 0.5 end
G._care_score_7d_01 = function(s) return 0.257 end
G._tail_pose = function(s) return "up" end
G.evolution_progress = function(s) return 0.333 end
G.is_night = function(s) return false end
G.farewell_step_name = function(s) return "sol" end
G.birth_step_name = function(s) return "negro" end
setmetatable(G, {__index = rules})

local function new_state()
  calls = {}
  local s = setmetatable({clock = Clock.new({2026, 10, 15}, T0), save_counter = 0, sound = nil, sound_seq = 0,
                          wifi_seq = 0}, {__index = G})
  fresh_fields(s)
  return s
end

local function near(a, b) return math.abs(a - b) < 1e-4 end

-- every state_screens function is a method taking the state first ---------------------------------------------
for name, f in pairs(screens) do assert(type(f) == "function", name) end

-- Estado: opens, focused on a stat or not ---------------------------------------------------------------------
do
  local s = new_state()
  s.overlay_text, s.overlay_until, s.status_page = "x", 5, 3
  s:enter_status_focus(0, "h")
  assert(s.mode == "status" and s.status_focus == "H" and s.status_page == 0 and s.overlay_text == nil)
  assert(s.last_events[#s.last_events] == "Abre estado (H)")
  s:enter_status_focus(0, "X") -- not a stat: plain Estado
  assert(s.mode == "status" and s.status_focus == nil and s.last_events[#s.last_events] == "Abre estado")
  s:enter_status_focus(0, nil)
  assert(s.status_focus == nil)
  s:exit_status(0)
  assert(s.mode == "main" and s.status_focus == nil and s.last_events[#s.last_events] == "Cierra estado")
end

-- Jugar's strip wraps, 0-based ---------------------------------------------------------------------------------
do
  local s = new_state()
  s.play_choice = 3
  s:enter_action_play(0)
  assert(s.mode == "action_play" and s.play_choice == 0)
  s:play_left()
  assert(s.play_choice == #s.PLAY_OPTIONS - 1)
  s:play_right()
  assert(s.play_choice == 0)
  s:exit_action_play(1000, "")    -- an empty message is no message
  assert(s.mode == "main" and s.overlay_text == nil and s.overlay_until == 0)
  s:exit_action_play(1000, "Bien")
  assert(s.overlay_text == "Bien" and s.overlay_until == 1900)
end

-- Comer opens on the first food she has (actions.first_open) --------------------------------------------------
do
  local s = new_state()
  s.feed_choice = 2
  s:enter_action_feed(1000)
  local c = called("first_open")
  assert(c and c[2] == s.FOOD_OPTIONS and c[3] == 2 and s.feed_choice == 4 and s.mode == "action_feed")
  s:exit_action_feed(2000, "Ñam")
  assert(s.mode == "main" and s.overlay_text == "Ñam" and s.overlay_until == 2900)
end

-- the meters: ten segments, Python's round (halves to even) ---------------------------------------------------
do
  local s = new_state()
  s.hunger, s.affection = 84.0, 85.0
  assert(s:_food_segments_10() == 8 and s:_happiness_hearts_10() == 8) -- round(8.5) == 8
  s.hunger, s.affection = 95.0, 150.0
  assert(s:_food_segments_10() == 10 and s:_happiness_hearts_10() == 10)
  s.hunger = -20.0
  assert(s:_food_segments_10() == 0)
  assert(math.type(s:_food_segments_10()) == "integer")
end

-- weight: her stage's ideal range, the balance, overweight ----------------------------------------------------
do
  local s = new_state()
  local r = s:_ideal_weight_range()
  assert(near(r[1], 2.2) and near(r[2], 4.0))
  s.phase = "Nadie"
  r = s:_ideal_weight_range()
  assert(r[1] == 4.5 and r[2] == 6.5)
  s.phase, s.weight_kg = "Cachorro", 3.1
  assert(near(s:_weight_balance(), 0.0))
  s.weight_kg = 4.0
  assert(near(s:_weight_balance(), 1.0)) -- half the range is 0.9
  assert(not s:_overweight())
  s.weight_kg = 4.01
  assert(s:_overweight())
  -- test_the_snapshot_says_when_she_is_overweight
  local lo, hi = 2.2, 4.0
  for _, case in ipairs({{lo - 0.5, false}, {(lo + hi) / 2, false}, {hi + 0.5, true}}) do
    s.weight_kg = case[1]
    assert(vm.build_ui(s).overweight == case[2])
  end
end

-- critical: any of the four at CRITICAL_MAX or under -----------------------------------------------------------
do
  local s = new_state()
  s.hunger, s.affection, s.energy, s.health = 11.0, 50.0, 50.0, 50.0
  assert(not s:critical_now())
  s.health = 10.0
  assert(s:critical_now())
end

-- the vet's soft-lock: Medicina waits, Veterinario never ------------------------------------------------------
do
  local s = new_state()
  assert(s:heal_can_choose(0) and s:heal_can_choose(1))
  s:_set_vet_softlock()
  assert(s.vet_softlock_until_ts == T0 + s.VET_SOFTLOCK_SEC and s:_vet_softlock_active())
  assert(s:_vet_softlock_left_sec() == 120)
  assert(not s:heal_can_choose(0) and not s:heal_can_choose(2) and s:heal_can_choose(1)) -- choice mod 2
  s.clock:advance(200)
  assert(not s:_vet_softlock_active() and s:_vet_softlock_left_sec() == 0 and s:heal_can_choose(0))
  s.in_critical = true
  assert(not s:heal_can_choose(0) and s:heal_can_choose(1))
end

-- Curar > Medicina blocked: it says why, and for how long ------------------------------------------------------
do
  local s = new_state()
  s:enter_action_heal(0)
  assert(s.mode == "action_heal" and s.heal_choice == 0)
  s:_set_vet_softlock()
  s:heal_confirm(1000)
  assert(s.mode == "action_heal" and s.overlay_text == "Solo veterinario (2m)" and s.overlay_until == 1900)
  assert(s.last_events[#s.last_events] == "Medicina bloqueada")
  s.vet_softlock_until_ts, s.in_critical = 0, true
  s:heal_confirm(1000)
  assert(s.overlay_text == "¡Llévame al veterinario!")
  s.vet_softlock_until_ts = s.clock:now() + 30 -- under a minute left: still "1m"
  s:heal_confirm(1000)
  assert(s.overlay_text == "Solo veterinario (1m)")
end

-- Curar > Medicina: well, nothing; sick, cured with a sound (test_medicine_that_works / cures_resfriado) --------
do
  local s = new_state()
  s.health = 95.0
  s:enter_action_heal(0)
  s:heal_confirm(1000)
  assert(s.overlay_text == "¡Estoy como una rosa!" and s.mode == "action_heal" and s.sound == nil)
  s.health = 60.0 -- not sick: the medicine does nothing, silently (test_medicine_that_does_nothing_is_silent)
  s:heal_confirm(1000)
  assert(s.sound == nil and s.mode == "main" and s.health == 68.0 and s.overlay_text == "¡Estoy como una rosa!")
  s.sick, s.health = true, 48.0
  s:enter_action_heal(2000)
  s:heal_confirm(3000)
  assert(s.sound == "curar" and s.sound_seq == 1 and not s.sick and s.health == 66.0)
  assert(s.mode == "main" and s.overlay_text == "¡Adiós, mocos!" and s.overlay_until == 3900)
  medicine = {applied = true, cured = false} -- a dose short: +8, the default message
  s.sick, s.health = true, 50.0
  s:enter_action_heal(4000)
  s:heal_confirm(5000)
  assert(s.health == 58.0 and s.overlay_text == "Medicina tomada" and s.sick)
end

-- Curar > Veterinario --------------------------------------------------------------------------------------------
do
  local s = new_state()
  s:enter_action_heal(0)
  s:heal_right() -- actions.heal_right is the module's
  assert(called("heal_right"))
  s.heal_choice = 1
  s:heal_confirm(1000)
  local c = called("vet")
  assert(c and c[2] == 1000 and c[3] == false)
  assert(s.mode == "main" and s.overlay_text == "¡Ya me curaron!" and s.overlay_until == 1900)
end

-- the bar minigame's score ---------------------------------------------------------------------------------------
do
  local s = new_state()
  s.minigame_cursor, s.minigame_target_center, s.minigame_target_half = 50.0, 50.0, 12.0
  assert(s:_minigame_score() == 1.0)
  s.minigame_cursor = 56.0
  assert(near(s:_minigame_score(), 0.5))
  s.minigame_cursor = 62.0
  assert(s:_minigame_score() == 0.0)
  s.minigame_cursor = 70.0
  assert(s:_minigame_score() == 0.0)
  s._frame_ms = 1234
  s:minigame_left()
  s:minigame_right()
  assert(called("minigame_left")[2] == 1234 and called("minigame_right")[2] == 1234)
end

-- Ajustes: the console's options, Nombre from cycle 2, Salir last (SettingsExitTest, RenameTest) -----------------
do
  local s = new_state()
  local opts = s:_settings_options()
  assert(table.concat(opts, ",") == "Sonido,Micro,Amigos,Idioma,Guía,Salir")
  for _, gone in ipairs({"Brillo", "Estilo", "Pantalla", "WiFi", "Nombre", "Reset suave"}) do
    assert(not util.contains(opts, gone), gone)
  end
  s.cycle = 2
  opts = s:_settings_options()
  assert(table.concat(opts, ",") == "Sonido,Micro,Amigos,Idioma,Nombre,Guía,Salir")
  s:enter_settings(0)
  assert(s.mode == "settings" and s.settings_index == 0)
  s:settings_left() -- one press from where it opens
  assert(opts[s.settings_index + 1] == "Salir")
  s:settings_right()
  assert(s.settings_index == 0)
  s.settings_index = util.index(opts, "Salir")
  s:settings_confirm(1000)
  assert(s.mode == "main" and s.last_events[#s.last_events] == "Cierra ajustes")
end

-- Ajustes > Sonido steps through medio, alto, bajo, noche, no (VolumeTest) ---------------------------------------
do
  local s = new_state()
  s:enter_settings(0)
  s.settings_index = util.index(s:_settings_options(), "Sonido")
  local seen = {}
  for t = 0, 5 do
    s:settings_confirm(1000 + t)
    seen[#seen + 1] = s.overlay_text
  end
  assert(table.concat(seen, ",") == "Sonido alto,Sonido bajo,Sonido noche,Sonido no,Sonido medio,Sonido alto")
  assert(s.overlay_until == 1905 and vm.build_ui(s).volume == 2)
  s.sound_mode, s.volume = 1, 0 -- not a step: from the first
  s:settings_confirm(2000)
  assert(s.sound_mode == 0 and s.volume == 2 and s.overlay_text == "Sonido alto")
  s.sound_mode, s.volume = 0, 7
  assert(settings.sound_name(s) == "alto")
  s.volume = -3
  assert(settings.sound_name(s) == "bajo")
end

-- Ajustes > Micro, Amigos, Idioma, Guía, Nombre --------------------------------------------------------------------
do
  local s = new_state()
  local opts = s:_settings_options()
  s.mode = "settings"
  s.settings_index = util.index(opts, "Micro")
  s:settings_confirm(1000)
  assert(s.mic_on == false and s.overlay_text == "Micro OFF" and vm.build_ui(s).mic_on == false)
  s:settings_confirm(1000)
  assert(s.mic_on == true and s.overlay_text == "Micro ON")
  s.settings_index = util.index(opts, "Amigos")
  s:settings_confirm(1000)
  assert(s.friends_on == false and s.overlay_text == "Amigos OFF" and vm.build_ui(s).friends_on == false)
  s.settings_index = util.index(opts, "Idioma")
  s:settings_confirm(1000)
  assert(s.language == "en" and s.overlay_text == "Idioma EN")
  s:settings_confirm(1000)
  assert(s.language == "es" and s.overlay_text == "Idioma ES")
  s.settings_index = util.index(opts, "Guía") + #opts -- the index wraps
  s:settings_confirm(1000)
  assert(s.mode == "guide")
  s.cycle = 2
  opts = s:_settings_options()
  s.settings_index = util.index(opts, "Nombre")
  s:settings_confirm(1000)
  assert(s.name == s.NAME_PRESETS[2] and s.last_events[#s.last_events] == "Renombra: " .. s.NAME_PRESETS[2])
  s:settings_confirm(2000)
  assert(s.name == s.NAME_PRESETS[3])
end

-- Diagnóstico's pages, QA ----------------------------------------------------------------------------------------
do
  local s = new_state()
  s:enter_tech_mode(0)
  assert(s.mode == "tech" and s.tech_page == 0)
  s:tech_page_left()
  assert(s.tech_page == #s.TECH_PAGES - 1)
  s:tech_page_right()
  assert(s.tech_page == 0)
  local ui = vm.build_ui(s)
  assert(ui.tech_diag.runtime.mode == "tech" and ui.tech_diag.vitals.hunger == 80 and ui.tech_diag.save.schema == 17)
  s:exit_tech_mode(0)
  assert(s.mode == "main" and next(vm.build_ui(s).tech_diag) == nil) -- empty outside Diagnóstico
  s:set_qa_mode(true, 1000)
  assert(s.qa_mode == true and s.overlay_text == "QA ON x8" and s.overlay_until == 1900)
  s:toggle_qa_mode(2000)
  assert(s.qa_mode == false and s.overlay_text == "QA OFF")
end

-- QA balance presets -----------------------------------------------------------------------------------------------
do
  local s = new_state()
  assert(s:apply_balance_preset("nada", 0) == false and s.qa_balance_preset == "equilibrada")
  assert(s:apply_balance_preset(nil, 0) == false)
  assert(s:apply_balance_preset("  Ligera ", 1000) == true)
  assert(s.qa_balance_preset == "ligera" and near(s.weight_kg, 3.1 - 0.45) and s.energy == 86.0 and s.stress == 20.0)
  assert(s.overlay_text == "Preset QA: ligera" and s.last_events[#s.last_events] == "Preset QA ligera")
  s:apply_balance_preset("robusta", 1000)
  assert(near(s.weight_kg, 3.1 + 0.55) and s.energy == 82.0 and s.stress == 23.0)
  s.energy = 120.0
  s:apply_balance_preset("equilibrada", 1000)
  assert(near(s.weight_kg, 3.1) and s.energy == 100.0)
end

-- Modo Sistema (SystemModeTest) --------------------------------------------------------------------------------------
local function open_system(option)
  local s = new_state()
  s.cycle, s.name, s.brightness_level, s.language, s.volume = 3, "Luna", 0, "en", 2
  s.birth_timestamp = T0 - 20 * 86400
  s:enter_system_mode(1000)
  if option then
    while s:system_options()[s.system_index + 1] ~= option do s:system_move(1) end
  end
  return s
end

do
  local s = open_system()
  assert(s.mode == "system" and s.system_index == 0)
  assert(table.concat(s:system_options(), ",") == "Diagnóstico,Nueva vida,Reset total,Salir")
  assert(s:system_options() ~= settings.SYSTEM_OPTIONS) -- a copy
  s:system_move(-1)
  assert(s.system_index == 3)
  for _, mode in ipairs({"farewell", "action_minigame", "birth"}) do
    local t = new_state()
    t.mode = mode
    t:enter_system_mode(1000)
    assert(t.mode == mode)
  end
  for _, flag in ipairs({"powered_off", "deep_sleep"}) do
    local t = new_state()
    t[flag] = true
    t:enter_system_mode(1000)
    assert(t.mode == "main")
  end
  for _, mode in ipairs({"status", "settings", "tech"}) do
    local t = new_state()
    t.mode = mode
    t:enter_system_mode(1000)
    assert(t.mode == "system")
  end
end

do -- Salir and Diagnóstico take a tap; the destructive ones ignore it
  local s = open_system("Salir")
  s:system_choose(2000, false)
  assert(s.mode == "main")
  s = open_system("Diagnóstico")
  s:system_choose(2000, false)
  assert(s.mode == "tech" and s.tech_page == 0)
  for _, option in ipairs({"Nueva vida", "Reset total"}) do
    s = open_system(option)
    s:system_choose(2000, false)
    assert(s.mode == "system" and s.cycle == 3 and s.name == "Luna")
    assert(s.overlay_text == "Mantén B 2 s para confirmar" and s.overlay_until == 3400)
  end
end

do -- Nueva vida: this cycle again from a kitten, the device's settings kept
  local s = open_system("Nueva vida")
  s.age_days, s.phase, s.name_preset_idx, s.sound_mode, s.ui_style = 20, "Adulto", 4, 2, 3
  s:system_choose(2000, true)
  assert(s.mode == "birth" and s.cycle == 3 and s.name == "Luna" and s.brightness_level == 0 and s.language == "en")
  assert(s.name_preset_idx == 4 and s.sound_mode == 2 and s.ui_style == 3 and s.volume == 2)
  assert(s.age_days == 0 and s.phase == "Cachorro" and s.birth_timestamp == T0)
  assert(s._frame_ms == 2000 and called("request_now")[2] == 2000)
  assert(s.last_events[#s.last_events] == "Nueva vida")
end

do -- ... never a way round a farewell already set
  local s = open_system("Nueva vida")
  s.farewell_scheduled_day = 40
  s:system_choose(2000, true)
  assert(s.cycle == 3 and s.birth_timestamp == T0 - 20 * 86400 and s.farewell_scheduled_day == 40)
  assert(s.overlay_text == "La despedida no se salta" and called("request_now") == nil)
  s = open_system("Nueva vida")
  s.farewell_started = true
  s:system_choose(2000, true)
  assert(s.cycle == 3 and s.mode == "system")
end

do -- Reset total: the first boot again
  local s = open_system("Reset total")
  s:system_choose(2000, true)
  assert(s.mode == "birth" and s.cycle == 1 and s.name == "Audrey" and s.brightness_level == 2 and s.language == "es")
  assert(s.last_events[#s.last_events] == "Reset total" and called("request_now"))
end

-- the snapshot: exactly the board's keys ----------------------------------------------------------------------------
local PY_KEYS = [[ui_contract_version mode indicators selected_index label menu_labels menu_icons overlay name cycle
scene background bird hidden hidden_here seek_warm scene_idx scenes seek_misses seek_searched seek_found
seek_first_try wants_play need game_result game_stars stickers new_sticker away sitter_no intro_step sitter_yes ask
ask_yes sitter_left_min sleeping deep_sleep powered_off power_state light_on day age_days phase quirks events mood
mood_icon tail_pose growth_points critical_sec critical_min evo_pct status_pages status_page status_focus tech_pages
tech_page qa_mode qa_tick_multiplier settings_index settings_options system_options system_index brightness_level
sound_mode volume ui_style mic_on seek_hint screen_off_sec language qa_balance_preset tech_diag personality
trust_bond stress confidence excitement stats weight_kg height_cm weight_ideal_low_kg weight_ideal_high_kg
weight_balance_pct overweight height_target_cm height_progress_pct heal_options heal_choice bath_options
bath_choice litter heal_blocked_medicine vet_softlock_sec_left in_critical sick sick_type selected_feed_type
feed_options feed_kinds play_options unlocks new_games play_choice food_options fiesta_item feed_choice
selected_food favorite_food disliked_food favorite_known fav_game fav_room fav_time food_segments food_segments_max
happiness_hearts happiness_hearts_max minigame_action minigame_label minigame_cursor minigame_target_center
minigame_target_half game life_deadline_day care_quality care_score_7d care_minutes avg_f_7d avg_s_7d
critical_minutes_7d vet_visits_7d can_edit_name night sound sound_seq farewell_started farewell_done farewell_step
farewell_t farewell_len farewell_choice farewell_memories birth_step grow_t grow_len grow_from grow_to grow_due
birth_t birth_len farewell_scheduled_day vet_softlock_until_ts critical_streak_min auto_vet_cd_min play_cd_sec_left
feed_cd_sec_left bath_cd_sec_left hug_cd_sec_left interactions_total rejections_total last_tick_age_sec qa_metrics
last_interaction_action last_interaction_ok about nickname anim_pace legacy heirloom stars weather dark dusk temp
season dream toy friend friends friends_on visitor visitor_gift animals gifts wifi_seq holiday]]
local expected = {}
local n_expected = 0
for k in PY_KEYS:gmatch("%S+") do expected[k] = true n_expected = n_expected + 1 end
assert(n_expected == 187)

do -- every value set (no Python None): every key there, none other
  local s = new_state()
  stub_returns = {fiesta_item = "Rosa", heirloom = "rueda", sitter_no = "today", need = "Feed", kind = "clear",
                  weather_now = {temp = 21}, season = "autumn", holiday = "diada", friend = "Luna",
                  visitor = "panda", visitor_gift = "flor", dream = "mimos", fav_game = "Simón", fav_room = 1,
                  fav_time = "morning", about = "activity_hi"}
  s.mode, s.ask, s.overlay_text, s.status_focus = "ask", "luz", "Hola", "H"
  s.game_result, s.game_result_seq, s.new_sticker, s.new_sticker_seq = {stars = 2}, 5, "s1", 7
  s.minigame_action, s.sound, s.sick_type, s.nickname = "Juego:Simon", "come", "resfriado", "Lulú"
  s.memory.first.favorite, s.memory.toy = 3, "pelota"
  local ui = vm.build_ui(s)
  local n = 0
  for k in pairs(ui) do
    assert(expected[k], "not a board key: " .. tostring(k))
    n = n + 1
  end
  for k in pairs(expected) do assert(ui[k] ~= nil, "missing: " .. k) end
  assert(n == 187)
  assert(ui.game_result.stars == 2 and ui.game_result.seq == 5 and s.game_result.seq == nil) -- a copy
  assert(ui.new_sticker.id == "s1" and ui.new_sticker.seq == 7)
  assert(ui.ask == "luz" and ui.temp == 21 and ui.weather == "clear" and ui.fav_room == "Cocina")
  assert(ui.favorite_known == "Latas" and ui.toy == "pelota" and ui.nickname == "Lulú" and ui.sick_type == "resfriado")
  stub_returns = {}
end

do -- a fresh game: Python's None keys absent, the rest as the board's
  local s = new_state()
  local ui = vm.build_ui(s)
  for _, k in ipairs({"overlay", "status_focus", "game_result", "new_sticker", "ask", "need", "sitter_no",
                      "sick_type", "nickname", "minigame_action", "sound", "fav_room", "favorite_known", "temp",
                      "toy", "fiesta_item", "heirloom", "about", "holiday"}) do
    assert(ui[k] == nil, k)
  end
  assert(ui.ui_contract_version == 2 and vm.UI_CONTRACT_VERSION == 2)
  assert(ui.mode == "main" and ui.label == "Feed" and ui.selected_index == 0 and #ui.menu_labels == #ui.menu_icons)
  assert(ui.indicators.H == 80 and ui.indicators.S == 90)
  assert(ui.scene == "Salón" and ui.scene_idx == 0 and ui.background == "bg_living.png")
  assert(ui.power_state == "on" and ui.away == false and ui.weather == "" and ui.seek_hint == -1)
  assert(ui.screen_off_sec == 360 and ui.brightness_level == 2 and ui.ui_style == 0 and ui.wifi_seq == 0)
  assert(table.concat(ui.settings_options, ",") == "Sonido,Micro,Amigos,Idioma,Guía,Salir")
  assert(ui.stats.Hambre == 80 and ui.stats["Energía"] == 80 and near(ui.stats.PesoKg, 3.0) and ui.stats.AlturaCm == 27.0)
  assert(near(ui.weight_ideal_low_kg, 2.2) and near(ui.weight_ideal_high_kg, 4.0))
  assert(ui.weight_balance_pct == 47) -- round(50 + 30 * (3.0 - 3.1) / 0.9)
  assert(ui.height_target_cm == 27.0 and ui.height_progress_pct == 100)
  assert(table.concat(ui.feed_kinds, ",") == "Comida,Comida,Snack,Comida,Snack,Snack")
  assert(ui.selected_food == "Leche" and ui.selected_feed_type == "Comida" and ui.bath_options[1] == "Bañarla")
  assert(ui.food_segments == 8 and ui.food_segments_max == 10 and ui.happiness_hearts == 7)
  assert(ui.heal_blocked_medicine == false and ui.vet_softlock_sec_left == 0)
  assert(ui.grow_t == 0 and ui.grow_len == 9000 and ui.birth_t == 300 and ui.birth_len == 3000)
  assert(ui.farewell_t == 10 and ui.farewell_len == 20 and ui.farewell_choice == "nueva_vida")
  assert(ui.anim_pace == 0.8 and ui.evo_pct == 33 and ui.care_quality == 50 and ui.care_score_7d == 25)
  assert(ui.avg_f_7d == 71 and ui.critical_minutes_7d == 3 and ui.vet_visits_7d == 1)
  assert(ui.can_edit_name == false and ui.night == false and ui.sound_seq == 0 and ui.minigame_label == "")
  assert(ui.favorite_food == "Latas" and ui.disliked_food == "Yogurt" and ui.last_interaction_action == "init")
  assert(ui.scenes ~= s.scenarios and #ui.scenes == 5) -- copies
  assert(ui.qa_metrics.phase_seconds ~= s._phase_seconds and ui.qa_metrics.phase_seconds.Cachorro == 0)
  assert(ui.personality ~= s.personality and ui.personality.activity == 0.5)
  assert(ui.quirks == s.quirks)
  assert(math.type(ui.critical_min) == "integer" and math.type(ui.trust_bond) == "integer")
end

do -- power_state, away, scene wrap, events: the last 3, or 10 in Estado
  local s = new_state()
  s.deep_sleep = true
  assert(vm.build_ui(s).power_state == "deep_sleep")
  s.powered_off = true
  assert(vm.build_ui(s).power_state == "off")
  s.sitter_until, s.current_scene = 1, 7
  local ui = vm.build_ui(s)
  assert(ui.away == true and ui.scene_idx == 2 and ui.scene == "Rascador" and ui.background == "bg_rasca.png")
  for i = 1, 12 do s:_log_event("e" .. i) end
  ui = vm.build_ui(s)
  assert(#ui.events == 3 and ui.events[1] == "e10" and ui.events[3] == "e12")
  s.mode = "status"
  ui = vm.build_ui(s)
  assert(#ui.events == 10 and ui.events[1] == "e3" and ui.events ~= s.last_events)
end

do -- hide and seek: warmer the nearer (SeekWarmthTest)
  local s = new_state()
  s.hidden, s.hidden_scene = true, 2
  local warm = {}
  for scene = 0, #s.scenarios - 1 do
    s.current_scene = scene
    warm[#warm + 1] = vm.build_ui(s).seek_warm
  end
  assert(table.concat(warm, ",") == "0,1,2,1,0")
  s.current_scene = 2
  assert(vm.build_ui(s).hidden_here == true)
  s.hidden = false
  assert(vm.build_ui(s).seek_warm == 0 and vm.build_ui(s).hidden_here == false)
  s.hidden, s.hidden_scene = true, -1
  assert(vm.build_ui(s).seek_warm == 0)
end

do -- hiding, she answered your voice: her room marked for SEEK_HINT_MS (test_hiding_she_answers_your_voice)
  local s = new_state()
  s.hidden, s.hidden_scene, s._frame_ms = true, 3, 2000
  s.seek_hint_until = 2000 + s.SEEK_HINT_MS
  assert(vm.build_ui(s).seek_hint == 3)
  s._frame_ms = 2000 + s.SEEK_HINT_MS + 100
  assert(vm.build_ui(s).seek_hint == -1)
  s._frame_ms, s.hidden = 2000, false
  assert(vm.build_ui(s).seek_hint == -1)
end

do -- cooldowns in whole seconds, never below 0
  local s = new_state()
  s._frame_ms = 10000
  s._play_cd_until_ms, s._feed_cd_until_ms, s._bath_cd_until_ms, s._hug_cd_until_ms = 12500, 9000, 10999, 11000
  local ui = vm.build_ui(s)
  assert(ui.play_cd_sec_left == 2 and ui.feed_cd_sec_left == 0 and ui.bath_cd_sec_left == 0)
  assert(ui.hug_cd_sec_left == 1)
  s._critical_streak_sec, s._auto_vet_cd_sec, s.critical_seconds = 179, 14400, 61
  ui = vm.build_ui(s)
  assert(ui.critical_streak_min == 2 and ui.auto_vet_cd_min == 240 and ui.critical_min == 1 and ui.critical_sec == 61)
  s.clock:advance(30)
  assert(vm.build_ui(s).last_tick_age_sec == 30)
end

do -- what past lives left: the last LEGACY_SHOWN
  local s = new_state()
  for i = 1, 8 do s.legacy[i] = {cycle = i, name = "A", item = "i" .. i} end
  local legacy = vm.build_ui(s).legacy
  assert(#legacy == 6 and legacy[1] == "i3" and legacy[6] == "i8")
end

do -- game_result {} and new_sticker "" are no result (Python's falsy)
  local s = new_state()
  s.game_result, s.new_sticker, s.nickname, s.sick_type = {}, "", "", ""
  local ui = vm.build_ui(s)
  assert(ui.game_result == nil and ui.new_sticker == nil and ui.nickname == nil and ui.sick_type == nil)
end

print("ok e")
