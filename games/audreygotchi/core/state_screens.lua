-- state_screens: GameState's screens besides the room: Estado, the technical pages, Ajustes, Sistema, the action
-- menus (Curar, Comer, Jugar) and the minigames (a port of audreygotchi/core/state_screens.py). Thin wrappers over
-- the modules that hold the logic. Every function takes the state first; core/state.lua copies them into
-- GameState's methods, so the rest of the core calls them s:enter_status(now_ms).
local util = require("core.util")
local actions = require("core.actions")
local interactions = require("core.interactions")
local minigames = require("core.minigames")
local navigation = require("core.navigation")
local settings_system = require("core.settings_system")
local v2_gameplay = require("core.v2_gameplay")
-- pinyol: tech_diag.py is not ported; tech_diag_snapshot below builds a small table itself

local M = {}

local function truthy(v) -- Python's bool(): None, False, 0, "" and empty containers are false
  if v == nil or v == false or v == 0 or v == "" then return false end
  if type(v) == "table" then return next(v) ~= nil end
  return true
end

local function has_msg(msg) return msg ~= nil and msg ~= "" end -- Python's `if msg:`

-- -------------------------
-- STATUS SCREEN
-- -------------------------

function M.enter_status(s, now_ms)
  s.mode = "status"
  s.status_focus = nil
  s.overlay_text = nil
  s.overlay_until = 0
  s:_log_event("Abre estado")
  s:mark_dirty()
end

function M.enter_status_focus(s, now_ms, stat_key)
  local key = string.upper(tostring(stat_key or ""))
  if not util.contains({"H", "F", "E", "S"}, key) then
    s:enter_status(now_ms)
    return
  end
  s.mode = "status"
  s.status_page = 0
  s.status_focus = key
  s.overlay_text = nil
  s.overlay_until = 0
  s:_log_event("Abre estado (" .. key .. ")")
  s:mark_dirty()
end

function M.exit_status(s, now_ms)
  s.mode = "main"
  s.status_focus = nil
  s.overlay_text = nil
  s.overlay_until = 0
  s:_log_event("Cierra estado")
  s:mark_dirty()
end

function M.enter_tech_mode(s, now_ms) settings_system.enter_tech_mode(s, now_ms) end
function M.exit_tech_mode(s, now_ms) settings_system.exit_tech_mode(s, now_ms) end
function M.tech_page_left(s) settings_system.tech_page_left(s) end
function M.tech_page_right(s) settings_system.tech_page_right(s) end
function M.set_qa_mode(s, enabled, now_ms) settings_system.set_qa_mode(s, enabled, now_ms) end
function M.toggle_qa_mode(s, now_ms) settings_system.toggle_qa_mode(s, now_ms) end

function M.apply_balance_preset(s, preset, now_ms)
  return settings_system.apply_balance_preset(s, preset, now_ms)
end

function M.enter_system_mode(s, now_ms) settings_system.enter_system_mode(s, now_ms) end
function M.system_options(s) return util.copy(settings_system.SYSTEM_OPTIONS) end
function M.system_move(s, step) settings_system.system_move(s, step) end
function M.system_choose(s, now_ms, held) settings_system.system_choose(s, now_ms, held) end

function M.active_menu_items(s) return navigation.active_menu_items(s) end
function M._sync_menu_cursor(s) navigation.sync_menu_cursor(s) end
function M.active_menu_icons(s) return navigation.active_menu_icons(s) end

function M._settings_options(s) return settings_system.settings_options(s) end
function M.enter_settings(s, now_ms) settings_system.enter_settings(s, now_ms) end
function M.exit_settings(s, now_ms) settings_system.exit_settings(s, now_ms) end
function M.settings_left(s) settings_system.settings_left(s) end
function M.settings_right(s) settings_system.settings_right(s) end
function M.settings_confirm(s, now_ms) settings_system.settings_confirm(s, now_ms) end

-- pinyol: the board's tech_diag.build_snapshot is not ported; Diagnóstico gets a small table, one entry per
-- TECH_PAGES page (Runtime, Vitals, Save)
function M.tech_diag_snapshot(s)
  return {
    runtime = {
      mode = tostring(s.mode),
      qa_mode = truthy(s.qa_mode),
      qa_preset = tostring(s.qa_balance_preset),
      tick_sec = util.int(s.TICK_INTERVAL_SEC),
      dirty = truthy(s._dirty),
      last_tick_age_sec = util.int(math.max(0, s.clock:now() - s._last_tick_ts)),
      interactions = util.int(s._interactions_total),
      rejections = util.int(s._rejections_total),
    },
    vitals = {
      hunger = util.int(s.hunger),
      affection = util.int(s.affection),
      energy = util.int(s.energy),
      health = util.int(s.health),
      dirt = util.int(s.dirt),
      weight_kg = util.round(s.weight_kg + 0.0, 2),
      critical_min = util.int(s.critical_seconds // 60),
      power = truthy(s.powered_off) and "off" or (truthy(s.deep_sleep) and "deep_sleep" or "on"),
    },
    save = {
      schema = util.int(s.SAVE_SCHEMA_VERSION),
      save_counter = util.int(s.save_counter),
      care_minutes = util.int(s.care_minutes_total),
      life_deadline_day = util.int(s.life_deadline_day),
      vet_softlock_s = util.int(s:_vet_softlock_left_sec()),
    },
  }
end

function M.status_page_left(s) navigation.status_page_left(s) end
function M.status_page_right(s) navigation.status_page_right(s) end

-- -------------------------
-- ACTION MENUS
-- -------------------------

function M.enter_action_heal(s, now_ms)
  s.mode = "action_heal"
  s.overlay_text = nil
  s.overlay_until = 0
  s.heal_choice = 0
  s:_log_event("Abre curar")
  s:mark_dirty()
end

function M.exit_action_heal(s, now_ms, msg)
  s.mode = "main"
  if has_msg(msg) then
    s.overlay_text = msg
    s.overlay_until = now_ms + 900
  else
    s.overlay_text = nil
    s.overlay_until = 0
  end
  s:_log_event("Cierra curar")
  s:mark_dirty()
end

function M.heal_left(s) actions.heal_left(s) end
function M.heal_right(s) actions.heal_right(s) end
function M.feed_left(s) actions.feed_left(s) end
function M.feed_right(s) actions.feed_right(s) end
function M._selected_food_name(s) return actions.selected_food_name(s) end
function M._selected_feed_type(s) return actions.selected_feed_type(s) end

function M.enter_action_feed(s, now_ms)
  s.mode = "action_feed"
  s.overlay_text = nil
  s.overlay_until = 0
  s.feed_choice = actions.first_open(s, s.FOOD_OPTIONS, s.feed_choice)
  s:_log_event("Abre alimentar")
  s:mark_dirty()
end

function M.exit_action_feed(s, now_ms, msg)
  s.mode = "main"
  if has_msg(msg) then
    s.overlay_text = msg
    s.overlay_until = now_ms + 900
  else
    s.overlay_text = nil
    s.overlay_until = 0
  end
  s:_log_event("Cierra alimentar")
  s:mark_dirty()
end

function M.enter_action_play(s, now_ms)
  s.mode = "action_play"
  s.play_choice = 0 -- the first game opens at birth (UNLOCK_PHASE)
  s.overlay_text = nil
  s.overlay_until = 0
  s:_log_event("Abre juego")
  s:mark_dirty()
end

function M.exit_action_play(s, now_ms, msg)
  s.mode = "main"
  if has_msg(msg) then
    s.overlay_text = msg
    s.overlay_until = now_ms + 900
  else
    s.overlay_text = nil
    s.overlay_until = 0
  end
  s:_log_event("Cierra juego")
  s:mark_dirty()
end

function M.play_left(s)
  local n = #s.PLAY_OPTIONS
  s.play_choice = (util.int(s.play_choice) - 1) % math.max(1, n)
  s:mark_dirty()
end

function M.play_right(s)
  local n = #s.PLAY_OPTIONS
  s.play_choice = (util.int(s.play_choice) + 1) % math.max(1, n)
  s:mark_dirty()
end

function M._food_segments_10(s)
  return util.int(math.max(0, math.min(10, util.round(s.hunger / 10.0))))
end

function M._happiness_hearts_10(s)
  return util.int(math.max(0, math.min(10, util.round(s.affection / 10.0))))
end

-- her stage's ideal weight, {lo, hi} (a Python tuple: an array)
function M._ideal_weight_range(s)
  local r = util.get(s.IDEAL_WEIGHT_RANGES, s.phase, {4.5, 6.5})
  return {r[1] + 0.0, r[2] + 0.0}
end

-- 0 = ideal. Negative = underweight. Positive = overweight. Roughly [-1.5..1.5]
function M._weight_balance(s)
  local r = s:_ideal_weight_range()
  local lo, hi = r[1], r[2]
  local mid = (lo + hi) * 0.5
  local half = math.max(0.25, (hi - lo) * 0.5)
  return (s.weight_kg + 0.0 - mid) / half
end

-- above her stage's ideal range: she dozes sooner and games tire her more
function M._overweight(s)
  return s.weight_kg + 0.0 > s:_ideal_weight_range()[2]
end

function M.critical_now(s)
  return math.min(s.hunger, s.affection, s.energy, s.health) <= s.CRITICAL_MAX
end

-- soft-lock: in critical, no Medicina
function M.heal_can_choose(s, choice_idx)
  choice_idx = util.int(choice_idx) % 2
  if choice_idx == 0 and (truthy(s.in_critical) or s:_vet_softlock_active()) then
    return false
  end
  return true
end

function M._vet_softlock_active(s)
  return s.clock:now() < s.vet_softlock_until_ts
end

function M._vet_softlock_left_sec(s)
  local left = util.int(s.vet_softlock_until_ts - s.clock:now())
  return math.max(0, left)
end

function M._set_vet_softlock(s)
  s.vet_softlock_until_ts = s.clock:now() + s.VET_SOFTLOCK_SEC
end

function M.heal_confirm(s, now_ms)
  local idx = util.int(s.heal_choice) % 2
  local opt = s.HEAL_OPTIONS[idx + 1]

  if not s:heal_can_choose(idx) then
    local left = s:_vet_softlock_left_sec()
    if left > 0 then
      local mm = math.max(1, left // 60)
      s.overlay_text = string.format("Solo veterinario (%dm)", mm)
    else
      s.overlay_text = "¡Llévame al veterinario!"
    end
    s.overlay_until = now_ms + 900
    s:_log_event("Medicina bloqueada")
    s:mark_dirty()
    return
  end

  if opt == "Medicina" then
    if (not truthy(s.sick)) and (not truthy(s.in_critical)) and s.health >= 90 then
      s.overlay_text = "¡Estoy como una rosa!"
      s.overlay_until = now_ms + 900
      s:_log_event("No necesita medicina")
      s:mark_dirty()
      return
    end

    local outcome = v2_gameplay.apply_medicine(s, now_ms)
    if truthy(outcome.applied) then
      s:_emit_sound("curar")
    end
    s.health = math.min(100.0, s.health + (truthy(util.get(outcome, "cured", false)) and 18.0 or 8.0))
    s:_log_event("Medicina")
    s:exit_action_heal(now_ms, tostring(util.get(outcome, "message", "Medicina tomada")))
  else
    s:_apply_veterinary_care(now_ms, false)
    s:exit_action_heal(now_ms, "¡Ya me curaron!")
  end
end

-- -------------------------
-- MINIGAMES
-- -------------------------

function M._minigame_profile(s, action) return minigames.minigame_profile(s, action) end
function M._minigame_label(s, action) return minigames.minigame_label(s, action) end
function M.enter_action_minigame(s, now_ms, action) minigames.enter_action_minigame(s, now_ms, action) end
function M.exit_action_minigame(s, now_ms, msg) minigames.exit_action_minigame(s, now_ms, msg) end
function M._update_minigame(s, now_ms) minigames.update_minigame(s, now_ms) end

function M._minigame_score(s)
  local dist = math.abs(s.minigame_cursor + 0.0 - s.minigame_target_center)
  if dist <= s.minigame_target_half + 0.0 then
    return math.max(0.0, 1.0 - (dist / math.max(0.01, s.minigame_target_half + 0.0)))
  end
  return 0.0
end

function M._game_view(s) return minigames.game_view(s) end
function M._minigame_apply(s, now_ms, action, score) minigames.minigame_apply(s, now_ms, action, score) end
function M.minigame_confirm(s, now_ms) minigames.minigame_confirm(s, now_ms) end

-- A and C carry no time: they use the frame tick of the last update(), never the wall clock
function M.minigame_left(s) minigames.minigame_left(s, util.int(s._frame_ms)) end
function M.minigame_right(s) minigames.minigame_right(s, util.int(s._frame_ms)) end

function M._apply_veterinary_care(s, now_ms, automatic)
  interactions.apply_veterinary_care(s, now_ms, automatic)
end

return M
