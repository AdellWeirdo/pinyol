-- state: GameState, a port of audreygotchi/core/state.py. A game is a plain table of fields (saved as it is) whose
-- metatable holds the rules (core/rules.lua), these methods and the screens' (core/state_screens.lua). Modules get
-- the state as `s` and call its methods with a colon: s:_emit_sound("come").
local util = require("core.util")
local rules = require("core.rules")
local action_runtime = require("core.action_runtime")
local actions = require("core.actions")
local care = require("core.care")
local game_init = require("core.game_init")
local interactions = require("core.interactions")
local save_policy = require("core.save_policy")
local lifecycle = require("core.lifecycle")
local navigation = require("core.navigation")
local events = require("core.events")
local friends = require("core.friends")
local hearing = require("core.hearing")
local weather = require("core.weather")
local mood = require("core.mood")
local personality = require("core.personality")
local power_state = require("core.power_state")
local scene_sancho = require("core.scene_sancho")
local scene_search = require("core.scene_search")
local simulation = require("core.simulation")
local ui_viewmodel = require("core.ui_viewmodel")
local state_screens = require("core.state_screens")

local G = setmetatable({}, {__index = rules}) -- GameState's methods, then the rules
local META = {__index = G}
local M = {G = G}

for name, fn in pairs(state_screens) do
  if type(fn) == "function" then G[name] = fn end
end

function M.new(clock) -- a fresh game on that clock
  local s = setmetatable({clock = clock}, META)
  s:_init_fresh()
  s.save_counter = 0
  s.sound = nil      -- the newest sound event and its sequence number: the front end plays it when sound_seq moves
  s.sound_seq = 0
  s.wifi_seq = 0
  s._save_last_ms = nil
  s._save_group_ms = nil
  s._save_marks = nil
  return s
end

function M.attach(s, clock) -- a loaded table becomes a game again
  s.clock = clock
  return setmetatable(s, META)
end

-- ------------------------------------------------------------------ init / reset

function G:_init_fresh() game_init.init_fresh(self) end
function G:_generate_personality() return personality.generate_personality(self) end

function G:new_life()
  local next_cycle = self.cycle + 1
  local name_keep, legacy_keep, style_keep = self.name, util.deepcopy(self.legacy), self.ui_style
  local volume_keep, guide_keep = self.volume, self.guide_seen
  self:_init_fresh()
  self.ui_style = style_keep
  self.volume, self.guide_seen = volume_keep, guide_keep
  self.cycle = math.max(1, next_cycle)
  self.legacy = legacy_keep -- what each Audrey left stays (Bible §32)
  self.name = self.cycle <= 1 and "Audrey" or tostring(name_keep or "Audrey")
  local idx = util.index(self.NAME_PRESETS, self.name)
  if idx then self.name_preset_idx = idx end
  self:_log_event("Nueva vida")
  self:mark_dirty()
end

function G:reset_total()
  self:_init_fresh()
  self:_log_event("Reset total")
  self:mark_dirty()
end

function G:mark_dirty() self._dirty = true end

function G:consume_dirty()
  if self._dirty then self._dirty = false return true end
  return false
end

-- ------------------------------------------------------------------ clock / rhythm

function G:rhythm()
  local hour = self.clock:local_hour()
  if hour >= 7 and hour < 13 then return "mañana" end
  if hour >= 13 and hour < 20 then return "tarde" end
  return "noche"
end

function G:cancel_action(now_ms)
  self:_note_input()
  interactions.cancel_action(self, now_ms)
end

function G:set_weather(kind, temp_c, is_day, sun) weather.set_weather(self, kind, temp_c, is_day, sun) end
function G:hear(kind, now_ms) hearing.hear(self, kind, now_ms) end
function G:meet(friend_id, name, now_ms) friends.meet(self, friend_id, name, now_ms) end

function G:_note_input()
  -- committed by update() once the simulation reaches the present
  self._input_pending_ts = self.clock:now()
  self.wants_play = false -- any button attends to her
  -- Bible §41: she was looking at something, you pressed: she looks at you, nothing more
  local left = self._looking_until - self._frame_ms
  if left > 0 and left <= events.LOOK_MS and self.mode == "main" then self:_emit_sound("te_mira") end
  self._looking_until = 0
  save_policy.note_action(self)
end

function G:save_due(now_ms) return save_policy.save_due(self, now_ms) end
function G:saved(now_ms) save_policy.saved(self, now_ms) end

-- ------------------------------------------------------------------ life cycle and farewell

function G:_care_quality_01()
  if self.care_minutes_total <= 0 then return 0.0 end
  local avg = self.care_points_total / self.care_minutes_total
  return util.clamp((avg + 6.0) / 14.0, 0.0, 1.0)
end

function G:_score_to_quality_01(score) return util.clamp((score + 6.0) / 14.0, 0.0, 1.0) end

function G:_closed_days_7d() -- buckets of the last 7 closed days (D-15): today is still open
  local current = math.max(1, self.day)
  local out = {}
  for d = math.max(1, current - self.EVAL_WINDOW_DAYS), current - 1 do
    local b = self.daily_metrics[tostring(d)]
    if type(b) == "table" then out[#out + 1] = b end
  end
  return out
end

function G:_care_score_7d_01()
  local minutes, c = 0.0, 0.0
  for _, b in ipairs(self:_closed_days_7d()) do
    minutes = minutes + util.get(b, "c_m", 0.0)
    c = c + util.get(b, "c_sum", 0.0)
  end
  if minutes <= 0.0 then return 0.5 end -- D-15: no closed day yet, neutral
  return util.clamp(c / minutes, 0.0, 1.0)
end

function G:_current_day_key() return math.max(1, (self.clock:now() - self.birth_timestamp) // 86400 + 1) end

function G:_day_bucket(day_key)
  local k = tostring(day_key)
  local b = self.daily_metrics[k]
  if type(b) ~= "table" then
    b = {m = 0.0, f_sum = 0.0, s_sum = 0.0, critical_m = 0.0, vet_v = 0.0, c_sum = 0.0, c_m = 0.0}
    self.daily_metrics[k] = b
  end
  return b
end

function G:_record_minute_metrics(care_01)
  local day_key = self:_current_day_key()
  local b = self:_day_bucket(day_key)
  b.m = util.get(b, "m", 0.0) + 1.0
  b.c_sum = util.get(b, "c_sum", 0.0) + care_01
  b.c_m = util.get(b, "c_m", 0.0) + 1.0
  local away = self.sitter_until > 0 -- with Sancho: counted as well cared (owner)
  local f = away and math.max(self.affection, self.EVAL_MIN_AVG_F) or self.affection
  local sv = away and math.max(self.health, self.EVAL_MIN_AVG_S) or self.health
  b.f_sum = util.get(b, "f_sum", 0.0) + f
  b.s_sum = util.get(b, "s_sum", 0.0) + sv
  if self.in_critical then b.critical_m = util.get(b, "critical_m", 0.0) + 1.0 end
  self:_prune_daily_metrics(day_key)
end

function G:_record_vet_visit()
  local b = self:_day_bucket(self:_current_day_key())
  b.vet_v = util.get(b, "vet_v", 0.0) + 1.0
end

function G:_prune_daily_metrics(current_day)
  local keep_from = current_day - math.max(14, self.EVAL_WINDOW_DAYS + 2)
  for _, k in ipairs(util.keys(self.daily_metrics)) do
    local d = tonumber(k)
    if d == nil or d < keep_from then self.daily_metrics[k] = nil end
  end
end

function G:_evaluation_metrics_7d()
  local minutes, f_sum, s_sum, critical_m, vet_v = 0.0, 0.0, 0.0, 0.0, 0.0
  for _, b in ipairs(self:_closed_days_7d()) do
    minutes = minutes + util.get(b, "m", 0.0)
    f_sum = f_sum + util.get(b, "f_sum", 0.0)
    s_sum = s_sum + util.get(b, "s_sum", 0.0)
    critical_m = critical_m + util.get(b, "critical_m", 0.0)
    vet_v = vet_v + util.get(b, "vet_v", 0.0)
  end
  return {
    avg_f_7d = minutes > 0 and f_sum / minutes or 0.0,
    avg_s_7d = minutes > 0 and s_sum / minutes or 0.0,
    critical_minutes_7d = critical_m,
    vet_visits_7d = vet_v,
    samples_min_7d = minutes,
  }
end

function G:can_edit_name() return self.cycle >= 2 end

function G:set_name(new_name)
  if not self:can_edit_name() then self.name = "Audrey" return false end
  local nm = tostring(new_name or ""):match("^%s*(.-)%s*$")
  if nm == "" then return false end
  self.name = nm:sub(1, 16)
  self:mark_dirty()
  return true
end

function G:cycle_name_preset()
  local n = math.max(1, #self.NAME_PRESETS)
  self.name_preset_idx = (self.name_preset_idx + 1) % n
  self:set_name(self.NAME_PRESETS[self.name_preset_idx + 1])
  return self.name
end

function G:_should_extend_life() return lifecycle.should_extend_life(self) end
function G:_schedule_farewell_sunset(now_ms) lifecycle.schedule_farewell_sunset(self, now_ms) end
function G:_try_start_scheduled_farewell(now_ms) lifecycle.try_start_scheduled_farewell(self, now_ms) end
function G:_update_birth(now_ms) lifecycle.update_birth(self, now_ms) end
function G:birth_step_name() return lifecycle.birth_step_name(self) end
function G:_start_farewell(now_ms) lifecycle.start_farewell(self, now_ms) end
function G:farewell_step_name() return lifecycle.farewell_step_name(self) end
function G:_update_farewell(now_ms) lifecycle.update_farewell(self, now_ms) end
function G:confirm_new_life_from_farewell(now_ms) lifecycle.confirm_new_life_from_farewell(self, now_ms) end

-- ------------------------------------------------------------------ personality, mood

function G:_pf(key, default) return personality.pf(self, key, default or 0.5) end
function G:_clamp_stat(v, lo, hi) return personality.clamp_stat(self, v, lo or 0.0, hi or 100.0) end
function G:_register_interaction(action, ok) interactions.register_interaction(self, action, ok) end

function G:_emit_sound(name)
  self.sound = name
  self.sound_seq = self.sound_seq + 1
end

function G:_personality_drift_minute() personality.personality_drift_minute(self) end
function G:compute_mood() mood.compute_mood(self) end
function G:maybe_complain(now_ms) personality.maybe_complain(self, now_ms) end
function G:maybe_purr(now_ms) personality.maybe_purr(self, now_ms) end
function G:should_reject(now_ms, action) return personality.should_reject(self, now_ms, action) end

-- ------------------------------------------------------------------ navigation and actions

function G:move_left() self:_note_input() navigation.move_left(self) end
function G:move_right() self:_note_input() navigation.move_right(self) end
function G:current_label() return navigation.current_label(self) end
function G:press_ok(now_ms) self:_note_input() actions.press_ok(self, now_ms) end
function G:search(now_ms) self:_note_input() scene_search.search(self, now_ms) end
function G:_call_sancho(now_ms) scene_sancho.ask(self, now_ms) end
function G:_pick_up(now_ms) scene_sancho.pick_up(self, now_ms) end
function G:_play_seek(now_ms) scene_search.play_seek(self, now_ms) end
function G:_look(step) scene_search.look(self, step) end
function G:_search_here(now_ms) return scene_search.search_here(self, now_ms) end
function G:_hide(now_ms) scene_search.hide(self, now_ms) end
function G:_unhide(now_ms) scene_search.unhide(self, now_ms) end
function G:_may_hide(now_ms) return scene_search.may_hide(self, now_ms) end

function G:_act_light(now_ms) power_state.act_light(self, now_ms) end
function G:_can_wake_now() return power_state.can_wake_now(self) end
function G:enter_sleep(now_ms, reason, show_overlay)
  if show_overlay == nil then show_overlay = true end
  return power_state.enter_sleep(self, now_ms, reason or "manual", show_overlay)
end
function G:request_deep_sleep(now_ms, source) return power_state.request_deep_sleep(self, now_ms, source or "auto") end
function G:wake_by_button(now_ms, source) return power_state.wake_by_button(self, now_ms, source or "botón") end
function G:_act_bath(now_ms) action_runtime.act_bath(self, now_ms) end
function G:_act_hug(now_ms) action_runtime.act_hug(self, now_ms) end

-- ------------------------------------------------------------------ evolution

function G:_phase_transition_day(phase_name) return lifecycle.phase_transition_day(self, phase_name) end
function G:_phase_from_age_days(age_days) return lifecycle.phase_from_age_days(self, age_days) end
function G:next_phase() return lifecycle.next_phase(self) end
function G:evolution_progress() return lifecycle.evolution_progress(self) end
function G:try_evolve(now_ms) lifecycle.try_evolve(self, now_ms) end
function G:care_score_minute() return care.care_score_minute(self) end

-- ------------------------------------------------------------------ simulation

function G:update(now_ms) simulation.update(self, now_ms) end
function G:_life_cycle_check(now_ms) lifecycle.life_cycle_check(self, now_ms) end
function G:_simulate_second(now_ms) simulation.simulate_second(self, now_ms) end

function G:_log_event(txt)
  local l = self.last_events
  l[#l + 1] = txt
  if #l > 10 then table.remove(l, 1) end
end

function G:_tail_pose() return personality.tail_pose(self) end

function G:is_night() -- D-14: [22:00, 08:00), local time
  local start, stop = self.NIGHT_HOURS[1], self.NIGHT_HOURS[2]
  local hour = self.clock:local_hour()
  return hour >= start or hour < stop
end

function G:indicators()
  return {H = util.int(self.hunger), F = util.int(self.affection), E = util.int(self.energy),
          S = util.int(self.health)}
end

function G:ui() return ui_viewmodel.build_ui(self) end

return M
