-- tests/core/test_c.lua: group C (lifecycle, scene_grow, scene_sancho, scene_search, visitors), the rules that
-- matter, ported from the Python tests (test_rules_v11.py, test_core_flows.py). Run from the repo root:
-- LUA_ROOT=games/audreygotchi $LUA32 games/audreygotchi/tests/core/test_c.lua
local util = require("core.util")
local rules = require("core.rules")
local Clock = require("core.clock")

math.randomseed(1)

-- stubs of the modules other groups port: only what the Python exports, with its names
local AXES = {"sociability", "activity", "curiosity", "affection", "food", "rhythm", "pampered"}
LOADED["core.memory"] = {
  TOYS = {"pelota", "raton", "pluma", "tapon", "cinta"},
  count = function(v)
    if type(v) ~= "number" then return 0 end
    return math.max(0, util.int(v))
  end,
  remember = function(s, kind, n) s.memory.day[kind] = (s.memory.day[kind] or 0) + (n or 1) end,
  first = function(s, what) if s.memory.first[what] == nil then s.memory.first[what] = s.day end end,
  keep_toy = function(s, found)
    local t = s.memory.toy
    if t == nil or t == "" then s.memory.toy = found end
  end,
}
LOADED["core.personality"] = {
  about = function(s)
    local best, far = nil, 0.15
    for _, axis in ipairs(AXES) do
      local d = s:_pf(axis) - 0.5
      if math.abs(d) >= far then best, far = axis .. (d > 0 and "_hi" or "_lo"), math.abs(d) end
    end
    return best
  end,
}
LOADED["core.events"] = {
  LOW = {"grumpy", "sad", "sleepy", "nervous", "lonely"},
  hour = function(s)
    local ts = s._sim_ts
    if ts ~= nil and ts ~= 0 then return s.clock:localtime(ts).tm_hour end
    return s.clock:local_hour()
  end,
  later = function(s, at_ms, sound)
    if #s._later < 4 then
      local l = util.copy(s._later)
      l[#l + 1] = {at_ms, sound}
      s._later = l
    end
  end,
}
LOADED["core.asks"] = {
  now = function(s)
    local ts = s._sim_ts
    if ts == nil or ts == 0 then return s.clock:now() end
    return ts
  end,
}
LOADED["core.minigames"] = {
  record_result = function(s, game, stars, won)
    s.game_result = {game = game, stars = stars, won = won}
    s.game_result_seq = s.game_result_seq + 1
  end,
}

local lifecycle = require("core.lifecycle")
local scene_grow = require("core.scene_grow")
local scene_sancho = require("core.scene_sancho")
local scene_search = require("core.scene_search")
local visitors = require("core.visitors")

-- a fake GameState: the methods these modules call, then the rules
local G = setmetatable({}, {__index = rules})
function G:mark_dirty() self._dirty = true end
function G:_log_event(txt)
  local l = self.last_events
  l[#l + 1] = txt
  if #l > 10 then table.remove(l, 1) end
end
function G:_emit_sound(name) self.sound, self.sound_seq = name, self.sound_seq + 1 end
function G:_pf(key, default)
  local v = self.personality[key]
  if v == nil then return default or 0.5 end
  return v
end
function G:_clamp_stat(v, lo, hi) return math.max(lo or 0.0, math.min(hi or 100.0, v)) end
function G:compute_mood() self._moods = self._moods + 1 end
function G:_evaluation_metrics_7d() return self._metrics end
function G:_care_score_7d_01() return self._care end
function G:_should_extend_life() return lifecycle.should_extend_life(self) end
function G:_schedule_farewell_sunset(now_ms) lifecycle.schedule_farewell_sunset(self, now_ms) end
function G:_start_farewell(now_ms) lifecycle.start_farewell(self, now_ms) end
function G:_phase_transition_day(p) return lifecycle.phase_transition_day(self, p) end
function G:_phase_from_age_days(a) return lifecycle.phase_from_age_days(self, a) end
function G:try_evolve(now_ms) lifecycle.try_evolve(self, now_ms) end
function G:new_life() -- what lifecycle reads after GameState.new_life
  self.cycle = self.cycle + 1
  self.farewell_started, self.farewell_done, self.farewell_choice, self.farewell_memories = false, false, 0, false
  self.farewell_step, self.mode, self.nickname = 0, "main", ""
end
function G:active_menu_items() return self._menu end
function G:_record_minute_metrics(care) self._recorded[#self._recorded + 1] = care end
function G:_register_interaction(action, ok) self._interactions[#self._interactions + 1] = {action, ok} end
function G:exit_action_minigame(now_ms, msg) self.mode, self.overlay_text, self.overlay_until = "main", msg, now_ms + 900 end
function G:_minigame_apply(now_ms, action, score) self._applied = {action, score} end
function G:wake_by_button(now_ms, source) self._woken = source return true end
local META = {__index = G}

local DAY = 86400
local MENU = {"Feed", "Play", "Cuddle", "Bath", "Sleep", "Sitter", "Album", "Status", "Settings"}

local function new_state(hour, fields)
  local s = setmetatable({clock = Clock.start({2026, 10, 15}, 10 * DAY + (hour or 12) * 3600)}, META)
  -- the game_init fields these modules touch
  s.mode, s.phase, s.cycle, s.day, s.age_days, s.name = "main", "Adulto", 1, 11, 10, "Audrey"
  s.hunger, s.affection, s.energy, s.health, s.dirt, s.stress = 70.0, 50.0, 70.0, 90.0, 20.0, 20.0
  s.sick, s.in_critical, s.sleeping, s.deep_sleep, s.powered_off = false, false, false, false, false
  s.scenarios = {"Salón", "Cocina", "Rascador", "Estudio", "WC"}
  s.current_scene, s.hidden_scene, s.hidden = 0, -1, false
  s.seek_misses, s.seek_searched, s.seek_found, s.seek_first_try, s.seek_play = 0, 0, 0, 0, false
  s.sitter_until, s.sitter_day, s.sitter_yes, s.sancho_intro_at = 0, 0, false, 0
  s.nickname, s.intro_step, s.grow_from, s.grow_to = "", 0, "", ""
  s._grow_start_ms, s._grow_revealed, s._grow_calls, s._grow_call_ms = 0, false, 0, 0
  s._intro_next_ms, s._sim_ts, s.selected_index = 0, 0, 0
  s.quirks, s.personality, s.mood = {}, {}, "calm"
  s.memory = {day = {}, first = {}, animals = {}}
  s.last_events, s.overlay_text, s.overlay_until = {}, nil, 0
  s._hide_cd_until_ms = 0
  s.last_input_ts = s.clock:now()
  s._frame_ms, s._away, s._was_away, s._sim_second_accum = 0, false, false, 0
  s.life_deadline_day, s.farewell_started, s.farewell_step, s.farewell_next_ms = 40, false, 0, 0
  s.birth_step, s.birth_next_ms, s.farewell_done, s.farewell_choice = 0, 0, false, 0
  s.farewell_memories, s.farewell_scheduled_day, s.guide_seen = false, 0, false
  s._later = {}
  s.friend_visit, s.friend_until = nil, 0
  s.visitor, s.visitor_until, s.visitor_next = nil, 0, 0
  s.legacy, s.stars = {}, 0
  s.game_result, s.game_result_seq = nil, 0
  -- the fake's own
  s.sound, s.sound_seq, s._moods = nil, 0, 0
  s._metrics = {avg_f_7d = 0.0, avg_s_7d = 0.0, critical_minutes_7d = 0.0, vet_visits_7d = 0.0,
                samples_min_7d = 0.0}
  s._care = 0.5
  s._menu = MENU
  s._recorded, s._interactions = {}, {}
  for k, v in pairs(fields or {}) do s[k] = v end
  return s
end

local function same(a, b) -- deep equality
  if type(a) ~= "table" or type(b) ~= "table" then return a == b end
  for k, v in pairs(a) do if not same(v, b[k]) then return false end end
  for k in pairs(b) do if a[k] == nil then return false end end
  return true
end

local function names_of(script)
  local out = {}
  for i, st in ipairs(script) do out[i] = st[1] end
  return out
end

local function sum_ms(script, upto)
  local t = 0
  for i = 1, upto or #script do t = t + script[i][2] end
  return t
end

-- ============================================================== lifecycle: the v11 evaluation (Plan Maestro)

local function metrics(f, sv, crit, vet, m)
  return {avg_f_7d = f, avg_s_7d = sv, critical_minutes_7d = crit, vet_visits_7d = vet,
          samples_min_7d = m or 7 * 1440.0}
end

do -- test_day_40_extension_rule: an apt week, five more days and a star, never announced
  local s = new_state(12, {age_days = 40, day = 41})
  s._metrics = metrics(75.0, 65.0, 70.0, 0.0)
  lifecycle.life_cycle_check(s, 1000)
  assert(s.life_deadline_day == 45 and s.farewell_scheduled_day == 0, s.life_deadline_day)
  assert(s.stars == 1 and s.overlay_text == nil)
  assert(s.last_events[#s.last_events] == "Extiende vida a 45")
end

do -- test_day_40_non_apt_schedules_farewell: that evening, a star
  local s = new_state(12, {age_days = 40, day = 41})
  s._metrics = metrics(60.0, 55.0, 1260.0, 21.0)
  lifecycle.life_cycle_check(s, 1000)
  assert(s.life_deadline_day == 40 and s.farewell_scheduled_day == 41 and s.stars == 1)
  assert(s.last_events[#s.last_events] == "Despedida programada (sunset)" and s.overlay_text == nil)
end

do -- each threshold: averages at least the floor, critical minutes and vet visits at most the ceiling
  local s = new_state()
  s._metrics = metrics(70.0, 60.0, 120.0, 2.0) assert(lifecycle.should_extend_life(s) == true)
  s._metrics = metrics(69.5, 60.0, 120.0, 2.0) assert(lifecycle.should_extend_life(s) == false)
  s._metrics = metrics(70.0, 59.5, 120.0, 2.0) assert(lifecycle.should_extend_life(s) == false)
  s._metrics = metrics(70.0, 60.0, 121.0, 2.0) assert(lifecycle.should_extend_life(s) == false)
  s._metrics = metrics(70.0, 60.0, 120.0, 3.0) assert(lifecycle.should_extend_life(s) == false)
  s._metrics = metrics(90.0, 90.0, 0.0, 0.0, 0.0) assert(lifecycle.should_extend_life(s) == false) -- no data
end

do -- LifeEvaluationTest: evaluated only after LIFE_MIN_DAYS full days lived, not on screen day 40
  local called = false
  local s = new_state(12, {age_days = 39, day = 40})
  s._should_extend_life = function() called = true return false end
  lifecycle.life_cycle_check(s, 0)
  assert(not called and s.farewell_scheduled_day == 0)
  s.age_days = 40
  lifecycle.life_cycle_check(s, 0)
  assert(called and s.farewell_scheduled_day == 40)
  called = false
  lifecycle.life_cycle_check(s, 0) -- a farewell set: nothing more
  assert(not called and s.stars == 1)
end

do -- at LIFE_MAX_DAYS no evaluation: the farewell; the extension never goes past it; a farewell started waits
  local called = false
  local s = new_state(12, {age_days = 55, life_deadline_day = 55})
  s._should_extend_life = function() called = true return true end
  lifecycle.life_cycle_check(s, 0)
  assert(not called and s.farewell_scheduled_day == s.day)
  s = new_state(12, {age_days = 50, life_deadline_day = 50})
  s._should_extend_life = function() return true end
  lifecycle.life_cycle_check(s, 0)
  assert(s.life_deadline_day == 55 and s.stars == 1)
  s = new_state(12, {age_days = 50, life_deadline_day = 40, farewell_started = true})
  lifecycle.life_cycle_check(s, 0)
  assert(s.life_deadline_day == 40 and s.stars == 0)
end

do -- StarsTest: a new star before the farewell; none once it has started
  local s = new_state(21)
  lifecycle.schedule_farewell_sunset(s, 0)
  assert(s.stars == 1 and s.farewell_scheduled_day == 11 and s.overlay_text == nil)
  s.farewell_started = true
  lifecycle.schedule_farewell_sunset(s, 0)
  assert(s.stars == 1)
end

do -- the scheduled farewell starts on its day, from sunset, at home on the main screen
  local s = new_state(20, {farewell_scheduled_day = 11})
  lifecycle.try_start_scheduled_farewell(s, 0)
  assert(not s.farewell_started) -- 20:00, before sunset
  s.clock:advance(3600)
  s.mode = "action_feed"
  lifecycle.try_start_scheduled_farewell(s, 0)
  assert(not s.farewell_started)
  s.mode = "status"
  lifecycle.try_start_scheduled_farewell(s, 0)
  assert(not s.farewell_started)
  s.mode, s.day = "main", 10
  lifecycle.try_start_scheduled_farewell(s, 0)
  assert(not s.farewell_started)
  s.day = 11
  lifecycle.try_start_scheduled_farewell(s, 5000)
  assert(s.farewell_started and s.mode == "farewell" and s.farewell_scheduled_day == 0)
end

-- ============================================================== lifecycle: the farewell (the owner's script)

do -- FarewellTest: the script, its music, its length
  local names = names_of(lifecycle.FAREWELL_SCRIPT)
  assert(same(lifecycle.FAREWELL_STEPS, names) and names[1] == "habitacion" and #names == 29)
  assert(same(util.slice(names, -5), {"creditos", "gracias", "autores", "logo", "silencio"}))
  for _, shot in ipairs({"habitacion", "ventana", "estrella", "pulsa", "baja", "cerca", "revela", "llega",
                         "presenta", "entiende", "despide", "anda", "puerta", "sube", "ventanita", "prepara",
                         "despega", "aleja", "asciende", "destello", "su_estrella", "creditos", "gracias",
                         "autores", "logo", "silencio"}) do
    assert(util.contains(names, shot), shot)
  end
  for i = 1, #lifecycle.FAREWELL_SCRIPT - 1 do
    local st = lifecycle.FAREWELL_SCRIPT[i]
    assert(st[3] == "adios_" .. st[1], st[1])
  end
  assert(lifecycle.FAREWELL_SCRIPT[#lifecycle.FAREWELL_SCRIPT][3] == nil)
  assert(lifecycle.FAREWELL_SILENCE_MS == 10000 and lifecycle.FAREWELL_SCRIPT[#names][2] == 10000)
  local story = sum_ms(lifecycle.FAREWELL_SCRIPT, #names - 1)
  local birth = sum_ms(lifecycle.BIRTH_STEPS)
  assert(story == 107000 and story > 2 * birth and story <= 120000, story)
  assert(same(lifecycle.FAREWELL_CHOICES, {"nueva_vida", "recuerdos"}))
end

do -- test_the_owners_script_in_order: each step on its schedule, its sound once on entering it, no text
  local s = new_state(21)
  s:_start_farewell(0)
  assert(s.mode == "farewell" and s.sound == "adios_habitacion" and s.farewell_next_ms == 2500)
  assert(s.last_events[#s.last_events] == "Despedida")
  local seen, sounds, seq = {}, {}, s.sound_seq
  for ms = 0, 119900, 100 do
    s._frame_ms = ms
    lifecycle.update_farewell(s, ms)
    if s.sound_seq ~= seq then sounds[#sounds + 1], seq = s.sound, s.sound_seq end
    local step = lifecycle.farewell_step_name(s)
    if #seen == 0 or seen[#seen] ~= step then seen[#seen + 1] = step end
    assert(s.overlay_text == nil, ms)
  end
  assert(same(seen, names_of(lifecycle.FAREWELL_SCRIPT)))
  local want = {}
  for i = 2, #lifecycle.FAREWELL_SCRIPT do
    if lifecycle.FAREWELL_SCRIPT[i][3] then want[#want + 1] = lifecycle.FAREWELL_SCRIPT[i][3] end
  end
  assert(same(sounds, want) and #sounds == 27)
  assert(s.farewell_done)
end

do -- the quiet sky: B waits for it to end, then a new life and her birth
  local s = new_state(21)
  s:_start_farewell(0)
  local story = sum_ms(lifecycle.FAREWELL_SCRIPT, #lifecycle.FAREWELL_SCRIPT - 1)
  lifecycle.update_farewell(s, story + 100)
  assert(lifecycle.farewell_step_name(s) == "silencio" and not s.farewell_done)
  lifecycle.confirm_new_life_from_farewell(s, story + lifecycle.FAREWELL_SILENCE_MS - 1000)
  assert(s.cycle == 1 and s.mode == "farewell")
  lifecycle.update_farewell(s, story + lifecycle.FAREWELL_SILENCE_MS + 100)
  assert(s.farewell_done)
  lifecycle.confirm_new_life_from_farewell(s, story + lifecycle.FAREWELL_SILENCE_MS + 200)
  assert(s.cycle == 2 and s.mode == "birth" and s.birth_step == 0)
  assert(s.birth_next_ms == story + lifecycle.FAREWELL_SILENCE_MS + 200 + 300)
end

do -- test_the_snapshot_says_how_far_into_its_step
  local s = new_state(21)
  s:_start_farewell(0)
  s._frame_ms = 1000
  lifecycle.update_farewell(s, 1000)
  assert(same(lifecycle.farewell_timing(s), {1000, 2500}))
  s._frame_ms = 0
  assert(same(lifecycle.farewell_timing(s), {0, 2500}))
  s.farewell_step, s.farewell_done = #lifecycle.FAREWELL_SCRIPT - 1, true
  assert(same(lifecycle.farewell_timing(s), {10000, 10000}))
  s.farewell_step = 99
  assert(lifecycle.farewell_step_name(s) == "silencio")
  s.farewell_step = -3
  assert(lifecycle.farewell_step_name(s) == "habitacion")
end

do -- test_a_restart_mid_farewell_does_not_stall
  local s = new_state(21)
  s:_start_farewell(0)
  s.farewell_next_ms = (1 << 30) - 100 -- set on the last boot's tick base
  for ms = 0, 129750, 250 do lifecycle.update_farewell(s, ms) end
  assert(s.farewell_done)
end

do -- test_at_the_end_her_memories_are_a_second_choice / before the end the buttons pick nothing
  local s = new_state(21)
  s:_start_farewell(0)
  lifecycle.farewell_move(s)
  lifecycle.confirm_new_life_from_farewell(s, 1000)
  assert(s.farewell_choice == 0 and not s.farewell_memories and s.mode == "farewell")
  s.farewell_done = true
  lifecycle.farewell_move(s)
  assert(lifecycle.FAREWELL_CHOICES[s.farewell_choice + 1] == "recuerdos")
  lifecycle.confirm_new_life_from_farewell(s, 1000) -- B: her memories, not a new life
  assert(s.farewell_memories and s.mode == "farewell" and s.cycle == 1)
  lifecycle.farewell_move(s) -- reading them: nothing to pick
  assert(s.farewell_choice == 1)
  lifecycle.confirm_new_life_from_farewell(s, 2000) -- B: back to the choice
  assert(not s.farewell_memories)
  lifecycle.farewell_move(s)
  assert(s.farewell_choice == 0)
  lifecycle.confirm_new_life_from_farewell(s, 3000) -- B: a new life
  assert(s.mode == "birth" and s.cycle == 2)
end

-- ============================================================== lifecycle: legacy and heirloom (Bible §32-§37)

local function farewell_with(traits)
  local s = new_state(21)
  local p = {}
  for _, a in ipairs(AXES) do p[a] = 0.5 end
  for k, v in pairs(traits) do p[k] = v end
  s.personality = p
  s:_start_farewell(0)
  return s
end

do -- LegacyTest: she leaves what she was; a star if nothing stands out; the first strongest in the dict's order
  assert(farewell_with({activity = 0.9}).legacy[1].item == "juguete")
  assert(farewell_with({curiosity = 0.9}).legacy[1].item == "piedra")
  assert(farewell_with({affection = 0.9}).legacy[1].item == "cojin")
  assert(farewell_with({rhythm = 0.9}).legacy[1].item == "estrella")
  assert(farewell_with({sociability = 0.9}).legacy[1].item == "foto")
  assert(farewell_with({food = 0.9}).legacy[1].item == "cuenco")
  assert(farewell_with({}).legacy[1].item == "estrella")
  assert(farewell_with({pampered = 0.9}).legacy[1].item == "estrella") -- not one of LEGACY's
  assert(farewell_with({activity = 0.54}).legacy[1].item == "estrella") -- below LEGACY_FROM
  assert(farewell_with({food = 0.9, sociability = 0.9}).legacy[1].item == "foto")
  local s = farewell_with({activity = 0.9})
  assert(same(s.legacy, {{cycle = 1, name = "Audrey", item = "juguete"}}))
  s.farewell_started = false
  s:_start_farewell(0) -- one per life
  assert(#s.legacy == 1)
  assert(lifecycle.LEGACY_SHOWN == 6 and lifecycle.LEGACY_FROM == 0.55)
end

do -- InheritanceTest: the gesture of the last life before this one
  local s = new_state(12, {cycle = 2})
  s.legacy = {{cycle = 1, name = "Audrey", item = "cojin"}, {cycle = 1, name = "Audrey", item = "juguete"}}
  assert(lifecycle.heirloom(s) == "rueda")
  s.legacy = {}
  assert(lifecycle.heirloom(s) == nil)
  s.legacy = {{cycle = 1, item = "foto"}, {cycle = 2, item = "juguete"}} -- this life's does not count
  assert(lifecycle.heirloom(s) == "happy_wiggle")
  s.legacy = {{item = "piedra"}} -- no cycle: an earlier one
  assert(lifecycle.heirloom(s) == "vuelta")
  s.cycle = 1
  s.legacy = {{cycle = 1, item = "piedra"}}
  assert(lifecycle.heirloom(s) == nil)
end

-- ============================================================== lifecycle: the birth (the owner's intro)

do -- BirthAndGrowthTest: its steps in order, each sound once, no text, ~31 s, then home (or the guide)
  local steps = names_of(lifecycle.BIRTH_STEPS)
  assert(same(util.slice(steps, 1, 5), {"cielo", "estrella", "fugaz", "zoom"}))
  local sky = 0
  for _, st in ipairs(lifecycle.BIRTH_STEPS) do
    if st[1] == "cielo" or st[1] == "estrella" or st[1] == "fugaz" then sky = sky + st[2] end
  end
  assert(sky == 6000)
  local by = {}
  for _, st in ipairs(lifecycle.BIRTH_STEPS) do by[st[1]] = st[2] end
  assert(by.zoom >= 3000)
  for _, n in ipairs({"orejas", "cola", "reveal", "bostezo", "juzga", "saludo"}) do assert(by[n] // 5 >= 380, n) end
  assert(not util.contains(steps, "loaf") and same(util.slice(steps, -3), {"saludo", "idle", "logo"}))

  local s = new_state(21, {cycle = 2, guide_seen = true})
  lifecycle.start_birth(s, 40100)
  assert(s.mode == "birth" and s.birth_next_ms == 40400 and s.overlay_text == nil)
  local seen, sounds, seq, last = {}, {}, s.sound_seq, 0
  for ms = 40100, 89950, 50 do
    last = ms
    s._frame_ms = ms
    lifecycle.update_birth(s, ms)
    if s.sound_seq ~= seq then sounds[#sounds + 1], seq = s.sound, s.sound_seq end
    if s.mode ~= "birth" then break end
    local step = lifecycle.birth_step_name(s)
    if #seen == 0 or seen[#seen] ~= step then seen[#seen + 1] = step end
    assert(s.overlay_text == nil)
  end
  assert(same(seen, steps))
  local want = {}
  for _, st in ipairs(lifecycle.BIRTH_STEPS) do if st[3] then want[#want + 1] = st[3] end end
  assert(same(sounds, want))
  local total = sum_ms(lifecycle.BIRTH_STEPS)
  assert(total >= 27000 and total <= 31000 and total == 30900, total)
  assert(last >= 40100 + total and last <= 40100 + total + 100, last)
  assert(s.mode == "main")

  s = new_state(21)
  lifecycle.start_birth(s, 0)
  lifecycle.update_birth(s, total + 100)
  assert(s.mode == "guide") -- born: the buttons' guide the first time
end

do -- the snapshot says how far into its step; a restart mid-birth starts it again; B held skips it from life two
  local s = new_state(21, {cycle = 2})
  lifecycle.start_birth(s, 40100)
  s._frame_ms = 40200
  lifecycle.update_birth(s, 40200)
  assert(lifecycle.birth_step_name(s) == "negro" and same(lifecycle.birth_timing(s), {100, 300}))
  s.birth_next_ms = 1000000000 -- set on the last boot's ticks
  lifecycle.update_birth(s, 1000)
  assert(s.birth_next_ms == 1300 and s.birth_step == 0)
  lifecycle.skip_birth(s)
  assert(s.mode == "main")
  s = new_state(21, {cycle = 1})
  lifecycle.start_birth(s, 0)
  lifecycle.skip_birth(s) -- her first life: the buttons wait
  assert(s.mode == "birth")
  s.birth_step = 50
  assert(lifecycle.birth_step_name(s) == "logo")
end

do -- test_growing_up_is_shown_not_written
  local s = new_state(12)
  lifecycle.show_growth(s, "Cachorro", "Juvenil", 1000)
  assert(s.overlay_text == nil and s.grow_from == "Cachorro" and s.grow_to == "Juvenil")
end

-- ============================================================== lifecycle: stages, growing up, nickname

do -- phase windows move with the care of the last 7 closed days
  local s = new_state()
  s._care = 1.0
  assert(s:_phase_transition_day("Juvenil") == 2 and s:_phase_transition_day("Adulto") == 12)
  assert(s:_phase_transition_day("Senior") == 25)
  s._care = 0.3
  assert(s:_phase_transition_day("Juvenil") == 3 and s:_phase_transition_day("Adulto") == 18)
  assert(s:_phase_transition_day("Senior") == 32)
  s._care = 0.5 -- neutral: t = 0.8 of the way
  assert(s:_phase_transition_day("Juvenil") == 3 and s:_phase_transition_day("Adulto") == 17)
  assert(s:_phase_transition_day("Senior") == 31)
  s._care = 0.575
  assert(s:_phase_transition_day("Adulto") == 15)
  assert(s:_phase_transition_day("Cachorro") == 0 and s:_phase_transition_day(nil) == 0)
end

do -- PuppyTest: she grows up in two days with good care, three with bad
  local s = new_state()
  s._care = 1.0
  assert(s:_phase_from_age_days(1) == "Cachorro" and s:_phase_from_age_days(2) == "Juvenil")
  s._care = 0.3
  assert(s:_phase_from_age_days(2) == "Cachorro" and s:_phase_from_age_days(3) == "Juvenil")
end

do -- phase_from_age_days: Senior to day 39, Extra only with days earned, up to LIFE_MAX_DAYS
  local s = new_state()
  s._care = 1.0
  assert(s:_phase_from_age_days(-4) == "Cachorro")
  assert(s:_phase_from_age_days(11) == "Juvenil" and s:_phase_from_age_days(12) == "Adulto")
  assert(s:_phase_from_age_days(24) == "Adulto" and s:_phase_from_age_days(25) == "Senior")
  assert(s:_phase_from_age_days(39) == "Senior" and s:_phase_from_age_days(40) == "Senior")
  s.life_deadline_day = 45
  assert(s:_phase_from_age_days(40) == "Extra" and s:_phase_from_age_days(55) == "Extra")
  assert(s:_phase_from_age_days(56) == "Senior")
end

do -- next_phase and evolution_progress
  local s = new_state()
  s.phase = "Cachorro" assert(lifecycle.next_phase(s) == "Juvenil")
  s.phase = "Senior" assert(lifecycle.next_phase(s) == "Extra")
  s.phase = "Extra" assert(lifecycle.next_phase(s) == nil)
  s.phase = "???" assert(lifecycle.next_phase(s) == "Juvenil")
  s._care = 1.0
  s.phase, s.age_days = "Cachorro", 1 assert(lifecycle.evolution_progress(s) == 0.5)
  s.phase, s.age_days = "Cachorro", 0 assert(lifecycle.evolution_progress(s) == 0.0)
  s.phase, s.age_days = "Juvenil", 7 assert(lifecycle.evolution_progress(s) == 0.5)
  s.phase, s.age_days = "Adulto", 30 assert(lifecycle.evolution_progress(s) == 1.0)
  s.phase, s.age_days = "Senior", 32 assert(lifecycle.evolution_progress(s) == 0.5)
  s.phase, s.age_days = "Extra", 41 assert(lifecycle.evolution_progress(s) == 1.0)
end

local function grow(s, to)
  s._phase_from_age_days = function() return to end
  s:try_evolve(1000)
end

do -- NicknameTest: grown, her strongest trait, once; "neutral" when nothing stands out
  local s = new_state(12, {phase = "Juvenil", personality = {food = 0.8, activity = 0.6}})
  grow(s, "Juvenil")
  assert(s.nickname == "") -- not grown yet
  grow(s, "Adulto")
  assert(s.nickname == "food_hi" and s.phase == "Adulto")
  assert(s.grow_from == "Juvenil" and s.grow_to == "Adulto" and s.memory.first.phase_Adulto == 11)
  assert(s.affection == 52.0 and s.health == 92.0 and s.sancho_intro_at == 0)
  assert(s.last_events[#s.last_events] == "Evoluciona: Juvenil->Adulto")
  s = new_state(12, {phase = "Juvenil"})
  grow(s, "Adulto")
  assert(s.nickname == "neutral")
  s = new_state(12, {phase = "Juvenil", personality = {pampered = 0.2}})
  grow(s, "Adulto")
  s.personality = {activity = 0.95}
  grow(s, "Senior")
  assert(s.nickname == "pampered_lo" and s.phase == "Senior")
  s = new_state(12, {phase = "Adulto", personality = {curiosity = 0.9}})
  grow(s, "Adulto") -- an older save's grown cat gets hers too
  assert(s.nickname == "curiosity_hi" and #s.last_events == 0)
end

do -- growing out of puppyhood calls Sancho; never backwards; stages grown while nobody looked show as one
  local s = new_state(12, {phase = "Cachorro", affection = 99.0})
  grow(s, "Juvenil")
  assert(s.phase == "Juvenil" and s.sancho_intro_at == s.clock:now() + scene_sancho.INTRO_AFTER_SEC)
  assert(s.affection == 100.0 and s.nickname == "")
  grow(s, "Adulto")
  assert(s.grow_from == "Cachorro" and s.grow_to == "Adulto")
  s = new_state(12, {phase = "Senior"})
  grow(s, "Adulto")
  assert(s.phase == "Senior" and s.grow_to == "")
  s = new_state(12, {phase = "Cachorro", age_days = 3}) -- SanchoIntroTest, by her real age
  s:try_evolve(1000)
  assert(s.phase == "Juvenil" and s.sancho_intro_at > s.clock:now())
end

-- ============================================================== scene_grow (the owner, 2026-10-09/11)

do -- her silhouette flickers faster and faster to the flash
  local times = scene_grow.flicker_times()
  assert(times[1] == 1980 and times[2] == 2291 and times[3] == 2546)
  assert(scene_grow.GLOW_MS < times[1] and times[#times] < scene_grow.FLASH_MS)
  local prev, last = scene_grow.GLOW_MS, nil
  for _, t in ipairs(times) do
    local step = t - prev
    assert(last == nil or step <= last)
    prev, last = t, step
  end
  assert(#times > 15 and last == scene_grow.FLICKER_MIN_MS)
end

local function due_state(phase)
  local s = new_state(12, {phase = phase or "Cachorro"})
  grow(s, "Juvenil")
  return s
end

do -- it calls you and plays only on B: glow, reveal with its fanfare, home
  local s = due_state()
  scene_grow.update(s, 2000)
  assert(s.mode == "main" and s.sound == "crece_aviso" and scene_grow.can_show(s) == true)
  assert(same(scene_grow.timing(s), {0, scene_grow.GROW_MS}))
  scene_grow.start(s, 2200)
  assert(s.mode == "grow" and s.sound == "evoluciona" and s.overlay_text == nil and not s._grow_revealed)
  assert(scene_grow.can_show(s) == false)
  s._frame_ms = 2200
  scene_grow.update(s, 2200)
  assert(same(scene_grow.timing(s), {0, 8000}))
  scene_grow.update(s, 2200 + scene_grow.REVEAL_MS - 1)
  assert(s.sound == "evoluciona")
  scene_grow.update(s, 2200 + scene_grow.REVEAL_MS)
  assert(s.sound == "crece" and s._grow_revealed)
  local seq = s.sound_seq
  scene_grow.update(s, 2200 + scene_grow.REVEAL_MS + 100)
  assert(s.sound_seq == seq) -- its fanfare once
  scene_grow.update(s, 2200 + scene_grow.GROW_MS)
  assert(s.mode == "main" and s.grow_to == "" and s.grow_from == "" and scene_grow.can_show(s) == false)
end

do -- the chime comes again less often with time
  local s = due_state()
  local seq, calls = s.sound_seq, {}
  for t = 0, 40 * 60000 - 1000, 1000 do
    scene_grow.update(s, 2000 + t)
    if s.sound_seq ~= seq then
      seq = s.sound_seq
      if s.sound == "crece_aviso" then calls[#calls + 1] = t end
    end
  end
  local gaps = {}
  for i = 2, #calls do gaps[#gaps + 1] = calls[i] - calls[i - 1] end
  local first = scene_grow.CALL_FIRST_TIMES - 1
  for i = 1, first do assert(gaps[i] == scene_grow.CALL_FIRST_MS, i) end
  assert(#gaps > first)
  for i = first + 1, #gaps do assert(gaps[i] == scene_grow.CALL_LATER_MS, i) end
end

do -- asleep, away, unwell or elsewhere she does not call, and the call starts afresh after
  for _, k in ipairs({"sleeping", "deep_sleep", "powered_off", "hidden", "sick", "in_critical"}) do
    local s = due_state()
    s._grow_calls = 3
    s[k] = true
    scene_grow.update(s, 2000)
    assert(scene_grow.can_show(s) == false and s._grow_calls == 0 and s.sound ~= "crece_aviso", k)
  end
  local s = due_state()
  s.sitter_until = s.clock:now() + 100
  assert(scene_grow.can_show(s) == false)
  s.sitter_until, s.mode = 0, "status"
  assert(scene_grow.can_show(s) == false)
end

do -- a restart mid-scene (another tick base) plays it from its start
  local s = due_state()
  scene_grow.start(s, 1000000)
  scene_grow.update(s, 5000)
  assert(s._grow_start_ms == 5000 and s.mode == "grow")
  scene_grow.update(s, 5000 + 2 * scene_grow.GROW_MS + 1)
  assert(s._grow_start_ms == 5000 + 2 * scene_grow.GROW_MS + 1 and s.mode == "grow")
end

do -- Sancho comes after her scene, not before (scene_grow then scene_sancho.update_intro)
  local s = due_state()
  s.clock:advance(scene_sancho.INTRO_AFTER_SEC + 1) -- his time came while she waited
  s.last_input_ts = s.clock:now()
  scene_sancho.update_intro(s, 2000)
  assert(s.mode == "main") -- hers first
  scene_grow.start(s, 3000)
  scene_grow.update(s, 3000 + scene_grow.GROW_MS)
  assert(s.mode == "main" and s.sancho_intro_at == s.clock:now() + scene_sancho.INTRO_AFTER_SEC)
  scene_sancho.update_intro(s, 3100 + scene_grow.GROW_MS)
  assert(s.mode == "main") -- a moment to see her new self
  s.clock:advance(scene_sancho.INTRO_AFTER_SEC)
  s.last_input_ts = s.clock:now()
  scene_sancho.update_intro(s, 4000 + scene_grow.GROW_MS)
  assert(s.mode == "sancho_intro")
  s = new_state(12, {grow_to = "Adulto", sancho_intro_at = 0, mode = "grow"})
  scene_grow.update(s, scene_grow.GROW_MS) -- no introduction due: none set
  assert(s.mode == "main" and s.sancho_intro_at == 0)
end

-- ============================================================== scene_sancho (the owner's babysitter)

local function today(s)
  local lt = s.clock:localtime()
  return lt.tm_year * 1000 + lt.tm_yday
end

do -- why he cannot come, in this order
  local s = new_state()
  assert(scene_sancho.why_not(s) == nil)
  s.sleeping, s.hidden = true, true
  assert(scene_sancho.why_not(s) == "sleeping")
  s.sleeping = false
  assert(scene_sancho.why_not(s) == "hidden")
  s.hidden, s.in_critical = false, true
  assert(scene_sancho.why_not(s) == "critical")
  s.in_critical, s.sitter_day = false, today(s)
  assert(scene_sancho.why_not(s) == "today" and today(s) == 2026298)
  s.sitter_day = today(s) - 1
  assert(scene_sancho.why_not(s) == nil)
end

do -- calling him asks first, No picked; No keeps her home; when he cannot come, nothing to confirm
  local s = new_state()
  scene_sancho.ask(s, 1000)
  assert(s.mode == "sitter_confirm" and s.sitter_yes == false)
  scene_sancho.choose(s, true)
  assert(s.sitter_yes == true)
  scene_sancho.choose(s, false)
  scene_sancho.confirm(s, 1100)
  assert(s.mode == "main" and not scene_sancho.away(s))
  s.sleeping = true
  scene_sancho.ask(s, 1000)
  assert(s.mode == "main" and s.overlay_text == "Shhh... ¡que duerme!" and s.overlay_until == 1900)
end

do -- he takes her for eight hours, once a day; nothing changes while she is away; back, she missed you
  local s = new_state(12, {affection = 40.0})
  local t0 = s.clock:now()
  scene_sancho.ask(s, 1000)
  scene_sancho.choose(s, true)
  scene_sancho.confirm(s, 1000)
  assert(s.mode == "main" and scene_sancho.away(s) and s.sitter_until == t0 + 8 * 3600)
  assert(s.sitter_day == today(s) and s.sound == "sancho" and s.overlay_text == "¡Me voy con Sancho!")
  assert(scene_sancho.left_min(s) == 480 and s.last_events[#s.last_events] == "Se va con Sancho")
  assert(scene_sancho.why_not(s) == "today")
  local evolved = 0
  s.try_evolve = function() evolved = evolved + 1 end
  local away_secs = 0
  while true do
    s.clock:advance(1)
    if not scene_sancho.away_second(s, 5000) then break end
    away_secs = away_secs + 1
  end
  assert(away_secs == 8 * 3600 - 1 and s.clock:now() == t0 + 8 * 3600)
  assert(#s._recorded == (8 * 3600 - 1) // 60 and s._recorded[1] == 1.0 and evolved == #s._recorded)
  assert(not scene_sancho.away(s) and s.affection == 40.0 - s.SITTER_MISSED_F and s.sound == "vuelve")
  assert(s.overlay_text == "¡Sancho me trajo!" and s.last_input_ts == t0 and s._moods == 1) -- not by hand
  scene_sancho.call(s, 6000) -- not again today
  assert(not scene_sancho.away(s) and s.overlay_text == "Sancho ya vino hoy")
  s.clock:advance(DAY)
  scene_sancho.call(s, 7000)
  assert(scene_sancho.away(s))
end

do -- B picks her up early: you are here; the catch-up's second decides when she is back
  local s = new_state(12, {affection = 3.0, _was_away = true})
  scene_sancho.call(s, 1000)
  s.clock:advance(2 * 3600)
  scene_sancho.pick_up(s, 2000)
  assert(not scene_sancho.away(s) and s.affection == 0.0 and s.last_input_ts == s.clock:now())
  assert(s._was_away == false and s._away == false and s.overlay_until == 2900)
  s = new_state()
  scene_sancho.call(s, 1000)
  s._sim_ts = s.sitter_until
  assert(scene_sancho.away_second(s, 2000) == false and not scene_sancho.away(s))
end

do -- left_min rounds up and never goes below 0
  local s = new_state()
  assert(scene_sancho.left_min(s) == 0)
  s.sitter_until = s.clock:now() + 61 assert(scene_sancho.left_min(s) == 2)
  s.sitter_until = s.clock:now() + 60 assert(scene_sancho.left_min(s) == 1)
  s.sitter_until = s.clock:now() - 120 assert(scene_sancho.left_min(s) == 0)
end

local function intro_state()
  local s = new_state(12, {phase = "Juvenil"})
  s.sancho_intro_at = s.clock:now()
  return s
end

do -- SanchoIntroTest: it waits for you; not while she sleeps, hides or is unwell
  local s = intro_state()
  s.last_input_ts = s.clock:now() - 3600
  scene_sancho.update_intro(s, 1000)
  assert(s.mode == "main")
  s.last_input_ts = s.clock:now()
  s.sancho_intro_at = s.clock:now() + 1
  scene_sancho.update_intro(s, 1000)
  assert(s.mode == "main")
  s.sancho_intro_at = s.clock:now()
  scene_sancho.update_intro(s, 1000)
  assert(s.mode == "sancho_intro" and scene_sancho.intro_step_name(s) == "llega" and s._intro_next_ms == 4000)
  for _, k in ipairs({"sleeping", "deep_sleep", "powered_off", "hidden", "sick", "in_critical"}) do
    s = intro_state()
    s[k] = true
    scene_sancho.update_intro(s, 1000)
    assert(s.mode ~= "sancho_intro", k)
  end
  s = intro_state()
  s.sitter_until = s.clock:now() + 10
  scene_sancho.update_intro(s, 1000)
  assert(s.mode == "main")
  s = intro_state()
  s.sancho_intro_at = 0
  scene_sancho.update_intro(s, 1000)
  assert(s.mode == "main")
end

do -- four steps by their time, then home with his button picked
  local s = intro_state()
  scene_sancho.update_intro(s, 1000)
  local seen, t = {}, 1000
  while s.mode == "sancho_intro" and t < 60000 do
    local step = scene_sancho.intro_step_name(s)
    if #seen == 0 or seen[#seen] ~= step then seen[#seen + 1] = step end
    t = t + 500
    scene_sancho.update_intro(s, t)
  end
  assert(same(seen, {"llega", "saluda", "explica", "menu"}))
  assert(s.mode == "main" and s.sancho_intro_at == 0 and s.intro_step == 0)
  assert(s.selected_index == util.index(MENU, "Sitter") and s.selected_index == 5)
  assert(t == 1000 + 17000)
end

do -- B moves it on; a menu without his button leaves the cursor; a wrapped tick moves it on
  local s = intro_state()
  scene_sancho.update_intro(s, 1000)
  for _, step in ipairs({"saluda", "explica", "menu"}) do
    scene_sancho.intro_next(s, 1100)
    assert(scene_sancho.intro_step_name(s) == step)
  end
  scene_sancho.intro_next(s, 1200)
  assert(s.mode == "main")
  s = intro_state()
  s._menu, s.selected_index = {"Feed", "Play"}, 1
  scene_sancho.update_intro(s, 1000)
  for _ = 1, 3 do scene_sancho.intro_next(s, 1100) end
  assert(s.selected_index == 1)
  s = intro_state()
  scene_sancho.update_intro(s, 1000)
  s._intro_next_ms = 1000000
  scene_sancho.update_intro(s, 1000)
  assert(s.intro_step == 1)
  s.intro_step = 9 assert(scene_sancho.intro_step_name(s) == "menu")
  s.intro_step = -1 assert(scene_sancho.intro_step_name(s) == "llega")
  s = new_state()
  scene_sancho.intro_due(s)
  assert(s.sancho_intro_at == s.clock:now() + 8)
end

-- ============================================================== scene_search (hide and seek, A+C)

local real_choice = util.choice
local function hide_in(s, room, now_ms)
  util.choice = function() return room end
  scene_search.hide(s, now_ms or 0)
  util.choice = real_choice
end

do -- she hides in any room, a new round each time
  local s = new_state()
  for _ = 1, 30 do
    scene_search.hide(s, 0)
    assert(s.hidden and util.contains(s.HIDING_ROOMS, s.hidden_scene))
  end
  s.seek_misses, s.seek_searched, s.seek_play = 2, 5, true
  hide_in(s, 3)
  assert(s.hidden_scene == 3 and s.seek_misses == 0 and s.seek_searched == 0 and s.seek_play == false)
  assert(s.sound == "escondida")
end

do -- may_hide: never a puppy; not within HIDE_REST_MS of coming out; a far-ahead cooldown is a wrapped tick
  local s = new_state(12, {phase = "Cachorro"})
  assert(scene_search.may_hide(s, 10000) == false)
  s.phase = "Juvenil"
  assert(scene_search.may_hide(s, 10000) == true)
  scene_search.unhide(s, 2000)
  assert(scene_search.may_hide(s, 2000 + s.HIDE_REST_MS - 1) == false)
  assert(scene_search.may_hide(s, 2000 + s.HIDE_REST_MS) == true)
  s._hide_cd_until_ms = 5000 + s.HIDE_REST_MS + 1
  assert(scene_search.may_hide(s, 5000) == true)
  s._hide_cd_until_ms = 777
  hide_in(s, 1)
  scene_search.unhide(s) -- coming out on her own: no cooldown, no find
  assert(s._hide_cd_until_ms == 777 and not s.hidden and s.hidden_scene == -1 and s.seek_found == 0)
end

do -- while hidden, A and C walk the rooms without searching, round the house
  local s = new_state()
  hide_in(s, 3)
  scene_search.look(s, 1)
  assert(s.current_scene == 1 and s.seek_misses == 0)
  scene_search.look(s, -1)
  scene_search.look(s, -1)
  assert(s.current_scene == 4 and s.hidden)
end

do -- the wrong room: a miss, counted and marked; her room: found, more affection at the first try
  local s = new_state(12, {current_scene = 1})
  hide_in(s, 2)
  assert(scene_search.search_here(s, 1000) == false)
  assert(s.hidden and s.current_scene == 1 and s.seek_misses == 1 and s.seek_searched == 1 << 1)
  assert(s.sound == "buscar" and s.overlay_text == "¡Frío, frío!" and s.overlay_until == 1900)
  s.current_scene = 2
  assert(scene_search.search_here(s, 2000) == true)
  assert(not s.hidden and s.hidden_scene == -1 and s.overlay_text == "¡Aquí estoy!" and s.sound == "encontrada")
  assert(s.affection == 50.0 + s.SEEK_FOUND_F and s.seek_found == 1 and s.seek_first_try == 0)
  assert(s._hide_cd_until_ms == 2000 + s.HIDE_REST_MS and s.memory.day.found == 1 and s.memory.first.found == 11)
  assert(s._moods == 1 and s.last_events[#s.last_events] == "Encontrado")
  hide_in(s, 2)
  scene_search.search_here(s, 3000)
  assert(s.affection == 50.0 + s.SEEK_FOUND_F + s.SEEK_FIRST_TRY_F and s.seek_found == 2 and s.seek_first_try == 1)
end

do -- found from Play's Síguela: that game's reward and its stars, not hide and seek's affection
  local s = new_state(12, {current_scene = 2, affection = 50.0})
  hide_in(s, 2)
  s.seek_play, s.seek_misses = true, 1
  scene_search.search_here(s, 5000)
  assert(same(s._applied, {"Juego:SiguelaCasa", 1.0}) and s.affection == 50.0)
  assert(same(s.game_result, {game = "Siguela por la casa", stars = 2, won = true}) and s.seek_play == false)
  hide_in(s, 2)
  s.seek_play, s.seek_misses = true, 7
  scene_search.search_here(s, 6000)
  assert(s.game_result.stars == 1 and s.game_result_seq == 2)
end

do -- one lap of the rooms always finds her: one search per room
  for room = 0, 4 do
    for start = 0, 4 do
      local s = new_state(12, {current_scene = start})
      hide_in(s, room)
      local n
      for i = 0, #s.scenarios - 1 do
        n = i
        scene_search.search(s, 1000 * (i + 1))
        if not s.hidden then break end
      end
      assert(not s.hidden and s.current_scene == room and n == (room - start) % 5, room .. "," .. start)
    end
  end
  local s = new_state(12, {current_scene = 0})
  hide_in(s, 2)
  scene_search.search(s, 1000)
  assert(s.current_scene == 1 and s.seek_misses == 1 and s.seek_searched == 1)
  assert(s.last_events[#s.last_events] == "Busca en Cocina")
end

do -- A+C: switched off it wakes her; elsewhere nothing; asleep a hush; away nobody to look for
  local s = new_state(12, {powered_off = true})
  scene_search.search(s, 1000)
  assert(s._woken == "A+C" and s.sound == nil)
  s = new_state(12, {deep_sleep = true})
  scene_search.search(s, 1000)
  assert(s._woken == "A+C")
  s = new_state(12, {mode = "status"})
  scene_search.search(s, 1000)
  assert(s.sound == nil and #s.last_events == 0)
  s = new_state(12, {sleeping = true})
  scene_search.search(s, 1000)
  assert(s.overlay_text == "Shhh... ¡que duerme!" and s.last_events[1] == "Buscar: dormida" and s.sound == nil)
  s = new_state(12, {sitter_until = 5})
  scene_search.search(s, 1000)
  assert(s.sound == nil and #s.last_events == 0)
end

do -- SearchReplyTest: the sound at once, her answer a moment later; no text but the room she is in
  local real_reply = scene_search.reply
  local function search_with(answer, fields)
    local s = new_state(12, fields)
    local got_can_hide
    scene_search.reply = function(_, can_hide) got_can_hide = can_hide return answer end
    scene_search.search(s, 1000)
    scene_search.reply = real_reply
    return s, got_can_hide
  end
  local s, can_hide = search_with("investiga")
  assert(s.sound == "buscar" and same(s._later, {{1600, "investiga"}}) and can_hide == true)
  assert(s.last_events[#s.last_events] == "Buscar: investiga")
  s = search_with("tarda")
  assert(same(s._later, {{4000, "tarda"}}))
  s = search_with("trae_algo")
  assert(s.memory.day.found == 1)
  for _, answer in ipairs({"aparece", "juega_sola", "investiga", "trae_algo", "pillada", "tarda"}) do
    s = search_with(answer)
    assert(s.overlay_text == nil, answer)
  end
  s = search_with("otra_sala")
  assert(s.current_scene == 1 and s.overlay_text == "Cocina" and s.last_events[#s.last_events] == "Va a Cocina")
  s = search_with("se_esconde")
  assert(s.hidden and s._hide_cd_until_ms == 13000 and s.overlay_text == nil)
  assert(s.last_events[#s.last_events] == "Se esconde")
  s, can_hide = search_with("aparece", {phase = "Cachorro"})
  assert(can_hide == false)
end

do -- her answers by stage, temperament, energy (random weights, seeded)
  local function replies(fields, n, can_hide)
    math.randomseed(2)
    local out = {}
    for i = 1, n or 400 do out[i] = scene_search.reply(new_state(12, fields), can_hide) end
    return out
  end
  local function count(list, ...)
    local c = 0
    for _, x in ipairs(list) do
      for _, want in ipairs({...}) do if x == want then c = c + 1 end end
    end
    return c
  end
  local kinds = {}
  for _, r in ipairs(replies()) do kinds[r] = true end
  assert(util.len(kinds) >= 6)
  assert(count(replies({energy = 20.0}), "juega_sola") == 0) -- tired she does not play on her own
  assert(count(replies({personality = {curiosity = 0.9}}), "investiga", "trae_algo")
         > count(replies({personality = {curiosity = 0.1}}), "investiga", "trae_algo"))
  assert(count(replies({phase = "Juvenil"}), "pillada") > count(replies({phase = "Adulto"}), "pillada"))
  assert(count(replies({}, 400, false), "se_esconde") == 0)
  local real_random = math.random -- the first answer with weight, and the last
  math.random = function() return 0.0 end
  assert(scene_search.reply(new_state()) == "se_esconde" and scene_search.reply(new_state(), false) == "aparece")
  math.random = function() return 0.99999 end
  assert(scene_search.reply(new_state()) == "tarda")
  math.random = real_random
end

do -- Play > Síguela: too tired, a refused game; else she hides at once and it is a game
  local s = new_state(12, {mode = "action_play", energy = 10.0})
  scene_search.play_seek(s, 1000)
  assert(s.mode == "main" and not s.hidden and same(s._interactions, {{"Juego", false}}))
  assert(s.overlay_text == "Me quedé sin pilas")
  s = new_state(12, {mode = "action_play", energy = 80.0})
  util.choice = function() return 2 end
  scene_search.play_seek(s, 1000)
  util.choice = real_choice
  assert(s.mode == "main" and s.hidden and s.hidden_scene == 2 and s.seek_play == true)
  assert(s.overlay_text == "¡A que no me encuentras!" and s.sound == "escondida")
end

-- ============================================================== visitors (animal friends, the owner 2026-10-08)

local function visit_state(hour)
  local s = new_state(hour or 12, {age_days = 20, affection = 50.0})
  s.last_input_ts = s.clock:now()
  s._frame_ms = 5000
  return s
end

local function make_due(s) s.visitor_next = s.clock:now() - 1 end

do -- the first is set a day or so ahead; a due friend visits and the next is three days off
  local s = visit_state()
  visitors.minute(s)
  local ahead = s.visitor_next - s.clock:now()
  assert(ahead >= visitors.FIRST_MIN_SEC and ahead <= visitors.FIRST_MAX_SEC and visitors.visiting(s) == nil)
  make_due(s)
  visitors.minute(s)
  local v = visitors.visiting(s)
  assert(util.contains(visitors.ANIMALS, v) and s.sound == "amigo" and same(visitors.met(s), {v}))
  assert(visitors.gift(s) == visitors.GIFTS[v] and s.memory.first.friend == 11 and s.visitor_until == 35000)
  ahead = s.visitor_next - s.clock:now()
  assert(ahead >= visitors.GAP_MIN_SEC and ahead <= visitors.GAP_MAX_SEC)
  s.visitor_next = s.clock:now() + visitors.GAP_MAX_SEC + 1 -- a clock that ran back
  visitors.minute(s)
  ahead = s.visitor_next - s.clock:now()
  assert(ahead >= visitors.GAP_MIN_SEC and ahead <= visitors.GAP_MAX_SEC)
end

do -- each brings its gift: a toy hers if she has none, else more joy
  local s = visit_state()
  visitors.visit(s, "conejita", s.clock:now())
  assert(s.memory.toy == nil and s.affection == 50.0 + visitors.JOY + visitors.GIFT_JOY and s._moods == 1)
  assert(s.last_events[#s.last_events] == "Conejita le trae una zanahoria")
  visitors.visit(s, "patito", s.clock:now())
  assert(s.memory.toy == "pluma" and s.affection == 62.0 + visitors.JOY)
  visitors.visit(s, "mapache", s.clock:now()) -- a toy, but she has hers
  assert(s.memory.toy == "pluma" and s.affection == 70.0 + 12.0)
  assert(s.last_events[#s.last_events] == "Mapache le trae un tapón brillante")
  s.affection = 99.0
  visitors.visit(s, "panda", s.clock:now())
  assert(s.affection == 100.0)
end

do -- nobody there it waits for a button
  local s = visit_state()
  s.last_input_ts = s.last_input_ts - 600
  make_due(s)
  visitors.minute(s)
  assert(visitors.visiting(s) == nil)
  s.last_input_ts = s.clock:now() + 5 -- a press "in the future": nobody either
  visitors.minute(s)
  assert(visitors.visiting(s) == nil)
  s.last_input_ts = s.clock:now() - visitors.OWNER_NEAR_SEC
  visitors.minute(s)
  assert(visitors.visiting(s) ~= nil)
end

do -- not at night nor asleep nor unwell nor elsewhere nor with a board's friend here
  local cases = {{22, {}}, {9, {}}, {20, {}}, {12, {sleeping = true}}, {12, {deep_sleep = true}},
                 {12, {powered_off = true}}, {12, {hidden = true}}, {12, {sick = true}}, {12, {in_critical = true}},
                 {12, {mode = "status"}}, {12, {sitter_until = 99}}, {12, {friend_visit = "ab12", friend_until = 6000}}}
  for i, c in ipairs(cases) do
    local s = visit_state(c[1])
    for k, v in pairs(c[2]) do s[k] = v end
    make_due(s)
    visitors.minute(s)
    assert(visitors.visiting(s) == nil, i)
  end
  for _, h in ipairs({10, 19}) do
    local s = visit_state(h)
    s.friend_visit, s.friend_until = "ab12", 5000 -- that friend has gone
    make_due(s)
    visitors.minute(s)
    assert(visitors.visiting(s) ~= nil, h)
  end
  local s = visit_state(12)
  s._sim_ts = s.clock:now() + 10 * 3600 -- catch-up: the simulated second's hour (22:00)
  s.visitor_next = s._sim_ts - 1
  s.last_input_ts = s._sim_ts
  visitors.minute(s)
  assert(visitors.visiting(s) == nil)
end

do -- all seven come before any comes back, then not twice running
  local s = visit_state()
  local seen = {}
  for i = 1, 12 do
    make_due(s)
    visitors.minute(s)
    seen[i] = s.visitor
  end
  local first7 = util.slice(seen, 0, 7)
  table.sort(first7)
  local all = util.copy(visitors.ANIMALS)
  table.sort(all)
  assert(same(first7, all))
  for i = 2, #seen do assert(seen[i] ~= seen[i - 1]) end
end

do -- the visit lasts its time
  local s = visit_state()
  make_due(s)
  visitors.minute(s)
  s._frame_ms = s._frame_ms + visitors.SHOW_MS - 1
  assert(visitors.visiting(s) ~= nil)
  s._frame_ms = s._frame_ms + 1
  assert(visitors.visiting(s) == nil and visitors.gift(s) == nil)
end

do -- GiftAlbumTest: each friend's gift once, in ANIMALS' order; restore keeps known animals with a visit
  local s = visit_state()
  visitors.visit(s, "panda", 1000)
  visitors.visit(s, "conejita", 2000)
  assert(same(visitors.gifts(s), {{"zanahoria", "conejita"}, {"bambu", "panda"}}))
  visitors.visit(s, "panda", 3000)
  assert(#visitors.gifts(s) == 2 and s.memory.animals.panda == 2)
  assert(same(visitors.restore({panda = 2, conejita = 0, dragon = 3, patito = "x", iguana = 1.7}),
              {panda = 2, iguana = 1}))
  assert(same(visitors.restore("x"), {}) and same(visitors.restore(nil), {}))
end

print("ok c")
