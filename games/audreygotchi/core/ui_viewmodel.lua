-- ui_viewmodel: the UI snapshot, everything the front end draws from (a port of audreygotchi/core/ui_viewmodel.py,
-- with the one name of ui_contract.py the core uses, UI_CONTRACT_VERSION). Same keys and values as the board's;
-- a Python None is nil here, so that key is simply absent from the table.
local util = require("core.util")
local bird = require("core.bird")
local scene_grow = require("core.scene_grow")
local scene_sancho = require("core.scene_sancho")
local actions = require("core.actions")
local litter = require("core.litter")
local needs = require("core.needs")
local events = require("core.events")
local weather = require("core.weather")
local lifecycle = require("core.lifecycle")
local friends = require("core.friends")
local visitors = require("core.visitors")
local memory = require("core.memory")
local personality = require("core.personality")
local M = {}

M.UI_CONTRACT_VERSION = 2 -- ui_contract.py

local function bool(v) -- Python's bool(): None, False, 0, "" and empty containers are false
  if v == nil or v == false or v == 0 or v == "" then return false end
  if type(v) == "table" then return next(v) ~= nil end
  return true
end

local function pair(a, b) -- a Python 2-tuple, returned as an array or as two values: both read the same
  if type(a) == "table" then return a[1], a[2] end
  return a, b
end

local function cd_sec_left(until_ms, frame_ms) -- a cooldown's whole seconds left, never below 0
  return math.max(0, util.int((util.int(until_ms) - util.int(frame_ms)) // 1000))
end

-- How warm the room on screen is in hide and seek (the owner, 2026-10-08: warmer the nearer, no words): 2 hers,
-- 1 a room away either side, 0 further; 0 when she is not hiding.
local function seek_warm(s)
  if not bool(s.hidden) or util.int(s.hidden_scene) < 0 then
    return 0
  end
  local n = math.max(1, #s.scenarios)
  local away = (util.int(s.current_scene) - util.int(s.hidden_scene)) % n
  return math.max(0, 2 - math.min(away, n - away))
end

local function seek_hint(s) -- hiding, she answered your voice: her room, for the seek bar to mark (else -1)
  local left = util.int(s.seek_hint_until) - util.int(s._frame_ms)
  if bool(s.hidden) and 0 < left and left <= s.SEEK_HINT_MS then
    return util.int(s.hidden_scene)
  end
  return -1
end

local function feed_kinds(s) -- Comida or Snack, food by food (FEED_TYPE_FOODS' keys in order: Comida, Snack)
  local out = {}
  for _, f in ipairs(s.FOOD_OPTIONS) do
    local kind = "Comida"
    for _, k in ipairs(util.keys(s.FEED_TYPE_FOODS)) do
      if util.contains(s.FEED_TYPE_FOODS[k], f) then
        kind = k
        break
      end
    end
    out[#out + 1] = kind
  end
  return out
end

local function legacy_items(s) -- what past lives left: the last LEGACY_SHOWN
  local out = {}
  for _, x in ipairs(util.slice(s.legacy, -lifecycle.LEGACY_SHOWN)) do out[#out + 1] = x.item end
  return out
end

-- the room, the menu, the screens
local function add_main(ui, s, scene_idx)
  local bg = nil
  if #s.BG_FILES > 0 then bg = s.BG_FILES[scene_idx % #s.BG_FILES + 1] end
  local game_result = nil
  if bool(s.game_result) then
    game_result = util.copy(s.game_result)
    game_result.seq = s.game_result_seq
  end
  local new_sticker = nil
  if bool(s.new_sticker) then new_sticker = {id = s.new_sticker, seq = s.new_sticker_seq} end

  ui.ui_contract_version = util.int(M.UI_CONTRACT_VERSION)
  ui.mode = s.mode
  ui.indicators = s:indicators()
  ui.selected_index = s.selected_index
  ui.label = s:current_label()
  ui.menu_labels = s:active_menu_items()
  ui.menu_icons = s:active_menu_icons()
  ui.overlay = s.overlay_text
  ui.name = s.name
  ui.cycle = s.cycle
  ui.scene = s.scenarios[scene_idx + 1]
  ui.background = bg
  ui.bird = bird.here(s) -- a sparrow at the window she glares at (core/bird.lua)
  ui.hidden = s.hidden
  ui.hidden_here = bool(bool(s.hidden) and util.int(s.current_scene) == util.int(s.hidden_scene))
  ui.seek_warm = seek_warm(s) -- hiding: 2 here, 1 a room away, 0 further
  ui.scene_idx = scene_idx
  ui.scenes = util.copy(s.scenarios)
  ui.seek_misses = util.int(s.seek_misses)
  ui.seek_searched = util.int(s.seek_searched)
  ui.seek_found = util.int(s.seek_found)
  ui.seek_first_try = util.int(s.seek_first_try)
  ui.wants_play = bool(s.wants_play)
  ui.need = needs.need(s) -- what she needs most: the menu item for it
  ui.game_result = game_result
  ui.game_stars = util.copy(s.memory.stars) -- each game's best
  ui.stickers = util.copy(s.memory.stickers) -- her album, in the order earned
  ui.new_sticker = new_sticker
  ui.away = util.int(s.sitter_until) > 0 -- with Sancho
  ui.sitter_no = scene_sancho.why_not(s) -- why Sancho cannot come now, or nil
  ui.intro_step = scene_sancho.intro_step_name(s) -- his introduction's step
  ui.sitter_yes = bool(s.sitter_yes) -- the answer picked, asking first
  ui.ask = (s.mode == "ask") and s.ask or nil -- what she asks (core/asks.lua)
  ui.ask_yes = bool(s.ask_yes)
  ui.sitter_left_min = scene_sancho.left_min(s)
  ui.sleeping = s.sleeping
  ui.deep_sleep = bool(s.deep_sleep)
  ui.powered_off = bool(s.powered_off)
  ui.power_state = bool(s.powered_off) and "off" or (bool(s.deep_sleep) and "deep_sleep" or "on")
  ui.light_on = s.light_on
  ui.day = s.day
  ui.age_days = util.int(s.age_days)
  ui.phase = s.phase
  ui.quirks = s.quirks
  ui.events = util.slice(s.last_events, s.mode == "status" and -10 or -3)
  ui.mood = s.mood
  ui.mood_icon = s.mood_icon
  ui.tail_pose = s:_tail_pose()
  ui.growth_points = util.int(s.growth_points)
  ui.critical_sec = util.int(s.critical_seconds)
  ui.critical_min = util.int(s.critical_seconds // 60)
  ui.evo_pct = util.int(s:evolution_progress() * 100)
  ui.status_pages = util.copy(s.STATUS_PAGES)
  ui.status_page = util.int(s.status_page)
  ui.status_focus = s.status_focus
  ui.tech_pages = util.copy(s.TECH_PAGES)
  ui.tech_page = util.int(s.tech_page)
  ui.qa_mode = bool(s.qa_mode)
  ui.qa_tick_multiplier = util.int(s.QA_TICK_MULTIPLIER)
  ui.settings_index = util.int(s.settings_index)
  ui.settings_options = s:_settings_options()
  ui.system_options = s:system_options()
  ui.system_index = util.int(s.system_index)
  ui.brightness_level = util.int(s.brightness_level)
  ui.sound_mode = util.int(s.sound_mode)
  ui.volume = util.int(s.volume) -- 0 bajo, 1 medio, 2 alto
  ui.ui_style = util.int(s.ui_style) -- Ajustes > Estilo on the board, an index into UI_STYLES
  ui.mic_on = bool(s.mic_on)
  ui.seek_hint = seek_hint(s)
  ui.screen_off_sec = util.int(s.SCREEN_OFF_SEC[util.int(s.screen_off_idx) % #s.SCREEN_OFF_SEC + 1])
  ui.language = tostring(s.language)
  ui.qa_balance_preset = tostring(s.qa_balance_preset)
  ui.tech_diag = (s.mode == "tech") and s:tech_diag_snapshot() or {} -- only shown there
end

-- her stats, weight and height
local function add_body(ui, s)
  local w = s:_ideal_weight_range()
  local w_lo, w_hi = w[1], w[2]
  local wb = s:_weight_balance()
  -- 50 ideal; <50 underweight; >50 overweight
  local w_balance_pct = util.int(math.max(0, math.min(100, util.round(50.0 + 30.0 * math.max(-1.5,
    math.min(1.5, wb))))))
  local h_target = util.get(s.PHASE_HEIGHT_CM, s.phase, 33.0) + 0.0
  local h_pct = util.int(math.max(0, math.min(100, util.round((s.height_cm / math.max(1.0, h_target)) * 100.0))))

  ui.personality = util.copy(s.personality)
  ui.trust_bond = util.int(s.trust_bond)
  ui.stress = util.int(s.stress)
  ui.confidence = util.int(s.confidence)
  ui.excitement = util.int(s.excitement)
  ui.stats = {
    Hambre = util.int(s.hunger),
    Afecto = util.int(s.affection),
    ["Energía"] = util.int(s.energy),
    Salud = util.int(s.health),
    Suciedad = util.int(s.dirt),
    PesoKg = util.round(s.weight_kg + 0.0, 2),
    AlturaCm = util.round(s.height_cm + 0.0, 1),
  }
  ui.weight_kg = util.round(s.weight_kg + 0.0, 2)
  ui.height_cm = util.round(s.height_cm + 0.0, 1)
  ui.weight_ideal_low_kg = util.round(w_lo + 0.0, 2)
  ui.weight_ideal_high_kg = util.round(w_hi + 0.0, 2)
  ui.weight_balance_pct = util.int(w_balance_pct)
  ui.overweight = s:_overweight()
  ui.height_target_cm = util.round(h_target + 0.0, 1)
  ui.height_progress_pct = util.int(h_pct)
end

-- action_heal, action_bath, action_feed, action_play, action_minigame
local function add_actions(ui, s)
  local sick_type = util.get(s, "sick_type", nil)
  if not bool(sick_type) then sick_type = nil end
  local fav_room_idx = memory.fav_room(s)
  local fav_room = nil
  if fav_room_idx ~= nil then fav_room = s.scenarios[fav_room_idx + 1] end
  local favorite_known = nil
  if s.memory.first.favorite ~= nil then favorite_known = s.favorite_food end

  ui.heal_options = util.copy(s.HEAL_OPTIONS)
  ui.heal_choice = util.int(s.heal_choice)
  ui.bath_options = util.copy(litter.BATH_OPTIONS) -- Baño: bathe her, or clean her box
  ui.bath_choice = util.int(s.bath_choice)
  ui.litter = util.int(s.litter) -- poops in her box, 0-3
  ui.heal_blocked_medicine = not s:heal_can_choose(0)
  ui.vet_softlock_sec_left = util.int(s:_vet_softlock_left_sec())
  ui.in_critical = bool(s.in_critical)
  ui.sick = bool(s.sick)
  ui.sick_type = sick_type
  ui.selected_feed_type = s:_selected_feed_type()
  ui.feed_options = util.copy(s.FOOD_OPTIONS)
  ui.feed_kinds = feed_kinds(s)
  ui.play_options = util.copy(s.PLAY_OPTIONS)
  ui.unlocks = actions.unlocks(s) -- locked options: the stage or day each opens at
  ui.new_games = actions.new_games(s) -- open and never played: marked new
  ui.play_choice = util.int(s.play_choice)
  ui.food_options = util.copy(s.FOOD_OPTIONS)
  ui.fiesta_item = actions.fiesta_item(s) -- what the holiday's button gives her, or nil
  ui.feed_choice = util.int(s.feed_choice)
  ui.selected_food = s:_selected_food_name()
  ui.favorite_food = tostring(util.get(s, "favorite_food", ""))
  ui.disliked_food = tostring(util.get(s, "disliked_food", ""))
  ui.favorite_known = favorite_known -- her favourite, once she has shown it (Bible §50); until then nobody knows
  ui.fav_game = memory.fav_game(s)
  ui.fav_room = fav_room
  ui.fav_time = memory.fav_time(s)
  ui.food_segments = util.int(s:_food_segments_10())
  ui.food_segments_max = 10
  ui.happiness_hearts = util.int(s:_happiness_hearts_10())
  ui.happiness_hearts_max = 10
  ui.minigame_action = s.minigame_action
  ui.minigame_label = s:_minigame_label(s.minigame_action)
  ui.minigame_cursor = s.minigame_cursor + 0.0
  ui.minigame_target_center = s.minigame_target_center + 0.0
  ui.minigame_target_half = s.minigame_target_half + 0.0
  ui.game = s:_game_view() -- a game with a board (Palito con plumas): its view
end

-- life cycle and farewell
local function add_life(ui, s)
  local ev7 = s:_evaluation_metrics_7d()
  local farewell_t, farewell_len = pair(lifecycle.farewell_timing(s))
  local grow_t, grow_len = pair(scene_grow.timing(s))
  local birth_t, birth_len = pair(lifecycle.birth_timing(s))

  ui.life_deadline_day = util.int(s.life_deadline_day)
  ui.care_quality = util.int(s:_care_quality_01() * 100)
  ui.care_score_7d = util.int(s:_care_score_7d_01() * 100)
  ui.care_minutes = util.int(s.care_minutes_total)
  ui.avg_f_7d = util.int(util.get(ev7, "avg_f_7d", 0.0))
  ui.avg_s_7d = util.int(util.get(ev7, "avg_s_7d", 0.0))
  ui.critical_minutes_7d = util.int(util.get(ev7, "critical_minutes_7d", 0.0))
  ui.vet_visits_7d = util.int(util.get(ev7, "vet_visits_7d", 0.0))
  ui.can_edit_name = bool(s:can_edit_name())
  ui.night = s:is_night()
  ui.sound = s.sound
  ui.sound_seq = util.int(s.sound_seq)

  ui.farewell_started = bool(s.farewell_started)
  ui.farewell_done = bool(s.farewell_done)
  ui.farewell_step = s:farewell_step_name()
  ui.farewell_t = farewell_t -- ms into the step, and its length: drawn by time, like the birth
  ui.farewell_len = farewell_len
  ui.farewell_choice = lifecycle.FAREWELL_CHOICES[s.farewell_choice + 1] -- under the logo, picked
  ui.farewell_memories = bool(s.farewell_memories) -- her memories on screen
  ui.birth_step = s:birth_step_name()
  ui.grow_t = grow_t -- her growing-up scene: ms into it, its length,
  ui.grow_len = grow_len -- the stage she leaves and the one she reaches
  ui.grow_from = s.grow_from
  ui.grow_to = s.grow_to
  ui.grow_due = scene_grow.can_show(s) -- it calls you: a chime, the LED, B to see it
  ui.birth_t = birth_t -- ms into the step, and its length: the intro is drawn by time
  ui.birth_len = birth_len
  ui.farewell_scheduled_day = util.int(s.farewell_scheduled_day)
end

-- vet soft-lock, cooldowns, QA, her world outside
local function add_world(ui, s)
  local nickname = s.nickname
  if not bool(nickname) then nickname = nil end
  local w_now = weather.now(s)
  local stage = events.stage(s)

  ui.vet_softlock_until_ts = util.int(s.vet_softlock_until_ts)
  ui.critical_streak_min = util.int(s._critical_streak_sec // 60)
  ui.auto_vet_cd_min = util.int(s._auto_vet_cd_sec // 60)
  ui.play_cd_sec_left = cd_sec_left(s._play_cd_until_ms, s._frame_ms)
  ui.feed_cd_sec_left = cd_sec_left(s._feed_cd_until_ms, s._frame_ms)
  ui.bath_cd_sec_left = cd_sec_left(s._bath_cd_until_ms, s._frame_ms)
  ui.hug_cd_sec_left = cd_sec_left(s._hug_cd_until_ms, s._frame_ms)
  ui.interactions_total = util.int(s._interactions_total)
  ui.rejections_total = util.int(s._rejections_total)
  ui.last_tick_age_sec = util.int(math.max(0, s.clock:now() - s._last_tick_ts))
  ui.qa_metrics = {
    actions_ok = util.copy(s._action_ok_counts),
    actions_reject = util.copy(s._action_reject_counts),
    phase_seconds = util.copy(s._phase_seconds),
  }
  ui.last_interaction_action = tostring(s._last_interaction_action)
  ui.last_interaction_ok = bool(s._last_interaction_ok)
  ui.about = personality.about(s) -- who she is, as a sentence key (Bible §50)
  ui.nickname = nickname -- what everyone calls her, grown
  ui.anim_pace = (type(stage) == "table") and stage[1] or stage -- a senior moves slower (Bible §23)
  ui.legacy = legacy_items(s)
  ui.heirloom = lifecycle.heirloom(s) -- the gesture she may inherit (Bible §37)
  ui.stars = util.int(s.stars) -- stars that stay in her window (Bible §27)
  ui.weather = weather.kind(s) or "" -- outside, while fresh (core/weather.lua)
  ui.dark = weather.dark(s) -- dark outside: the rooms at night
  ui.dusk = weather.dusk(s) -- the half hour before sunset: a warm sky
  ui.temp = (w_now ~= nil and w_now ~= false) and w_now.temp or nil
  ui.season = weather.season(s)
  ui.dream = memory.dream(s) -- asleep: what she dreams of (Bible §10)
  ui.toy = util.get(s.memory, "toy") -- her toy, her first find
  ui.friend = friends.visiting(s) -- a friend on screen now, by name
  ui.friends = friends.names(s)
  ui.friends_on = bool(s.friends_on)
  ui.visitor = visitors.visiting(s) -- an animal friend on screen now (visitors.lua)
  ui.visitor_gift = visitors.gift(s) -- ... and the gift it brought, handed over on screen
  ui.animals = visitors.met(s) -- the ones she has met: Estado > Amigos
  ui.gifts = visitors.gifts(s) -- what they brought her: Estado > Regalos
  ui.wifi_seq = util.int(s.wifi_seq) -- pinyol: no Ajustes > WiFi, so it never moves (kept for the contract)
  ui.holiday = weather.holiday(s)
end

function M.build_ui(s)
  local scene_idx = util.int(s.current_scene) % math.max(1, #s.scenarios)
  local ui = {}
  add_main(ui, s, scene_idx)
  add_body(ui, s)
  add_actions(ui, s)
  add_life(ui, s)
  add_world(ui, s)
  return ui
end

return M
