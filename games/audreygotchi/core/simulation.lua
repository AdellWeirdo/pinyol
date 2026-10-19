-- simulation: the clock's seconds become her life (a port of audreygotchi/core/simulation.py).
local asks = require("core.asks")
local litter = require("core.litter")
local needs = require("core.needs")
local stickers = require("core.stickers")
local visitors = require("core.visitors")
local events = require("core.events")
local memory = require("core.memory")
local scene_sancho = require("core.scene_sancho")
local bird = require("core.bird")
local scene_grow = require("core.scene_grow")
local v2_gameplay = require("core.v2_gameplay")
local M = {}

M.MAX_OVERLAY_MS = 10000 -- longest overlay is 2.5 s; anything further off is another time base
M.MAX_LATER_MS = 60000   -- longest "a moment later" is 30 s; further off, the tick has wrapped
M.GREET_LATER_MS = 20000 -- an independent hello: her own thing first, then a look
M.GREET_QUIET_MS = 5000  -- the hello plays out before any complaint
M.MORNING_SLEPT_SEC = 3 * 3600

local function greeting(s) -- Bible §44: how she says hello depends on who she is: delay in ms, what she does
  if s:_pf("sociability") < 0.4 then return M.GREET_LATER_MS, "mira" end
  if s:_pf("affection") < 0.4 then return 0, "escucha" end
  if s:_pf("activity") >= 0.6 then return 0, "juguetea" end
  return 0, "saluda"
end

local function morning_wake_due(s)
  local start, stop = s.MORNING_WAKE[1], s.MORNING_WAKE[2]
  local h = events.hour(s)
  return start <= h and h < stop
    and s._nap_sec >= M.MORNING_SLEPT_SEC
    and asks.now(s) - s.morning_wake_ts >= 12 * 3600
    and s.energy > s.AUTO_SLEEP_FORCE_ENERGY
end

local function greet_after_absence(s, now_ms)
  -- first button after an absence: she wakes up to say hello, the way she is; asleep at night she sleeps on
  s._was_away = false
  if (s.sleeping or s.deep_sleep) and s:is_night() then return end
  if s.sleeping then
    s.sleeping = false
    s.light_on = true
  end
  if s.hidden or s.sick or s.in_critical or s.sitter_until ~= 0 then
    s:_log_event("Vuelves tras una ausencia")
    s:compute_mood()
    s:mark_dirty()
    return
  end
  local delay, sound = greeting(s)
  s._complain_cd_until_ms = math.max(s._complain_cd_until_ms, now_ms + M.GREET_QUIET_MS)
  if delay ~= 0 then events.later(s, now_ms + delay, sound) else s:_emit_sound(sound) end
  s:_log_event("Vuelves tras una ausencia")
  s:compute_mood()
  s:mark_dirty()
end

function M.update(s, now_ms)
  local now = s.clock:now()
  s._frame_ms = now_ms
  if s.overlay_text ~= nil and s.overlay_until - now_ms > M.MAX_OVERLAY_MS then s.overlay_until = now_ms + 900 end

  if s.mode == "birth" then s:_update_birth(now_ms) return end
  if s.mode == "farewell" then
    s:_update_farewell(now_ms)
    if s.overlay_text ~= nil and now_ms >= s.overlay_until then s.overlay_text = nil end
    return
  end

  scene_grow.update(s, now_ms)
  bird.update(s, now_ms)
  scene_sancho.update_intro(s, now_ms)

  -- a tick a second, catching up
  if now - s._last_tick_ts >= s.TICK_INTERVAL_SEC then
    local ticks = (now - s._last_tick_ts) // s.TICK_INTERVAL_SEC
    ticks = math.max(1, math.min(ticks, 7200))
    local sim_ticks = ticks
    if s.qa_mode then sim_ticks = sim_ticks * s.QA_TICK_MULTIPLIER end
    sim_ticks = math.max(1, math.min(sim_ticks, 7200))
    local step = ticks * s.TICK_INTERVAL_SEC / sim_ticks
    for i = 0, sim_ticks - 1 do
      s._sim_ts = s._last_tick_ts + math.floor((i + 1) * step)
      local away_from = math.max(s.last_input_ts, s.morning_wake_ts) + s.ABSENCE_SEC
      s._away = s._last_tick_ts + i * step >= away_from
      s._was_away = s._was_away or s._away
      s:_simulate_second(now_ms)
    end
    s._away = false
    s._last_tick_ts = s._last_tick_ts + ticks * s.TICK_INTERVAL_SEC
    s:mark_dirty()
  end

  if s._input_pending_ts ~= 0 and now - s._last_tick_ts < s.TICK_INTERVAL_SEC then
    s.last_input_ts = s._input_pending_ts
    s._input_pending_ts = 0
  end
  local awake_able = not (s.powered_off or s.deep_sleep)
  if s._was_away and awake_able and now - s.last_input_ts < s.ABSENCE_SEC then greet_after_absence(s, now_ms) end
  s:_sync_menu_cursor()

  if s.mode == "action_minigame" then s:_update_minigame(now_ms) end

  if s.overlay_text ~= nil and now_ms >= s.overlay_until then s.overlay_text = nil end
  -- a moment later: only if she is there to be seen
  if #s._later > 0 then
    local waiting, due = {}, {}
    for _, x in ipairs(s._later) do
      if x[1] - now_ms <= M.MAX_LATER_MS then
        waiting[#waiting + 1] = x
        if now_ms >= x[1] then due[#due + 1] = x end
      end
    end
    if #due > 0 then
      local first = due[1]
      for _, x in ipairs(due) do if x[1] < first[1] then first = x end end
      for i, x in ipairs(waiting) do if x == first then table.remove(waiting, i) break end end
      if events.able(s) then s:_emit_sound(first[2]) end
    end
    s._later = waiting
  end

  s.age_days = math.max(0, (now - s.birth_timestamp) // 86400)
  s.day = s.age_days + 1
  local at = s.memory.at_day
  if at <= 0 then
    s.memory.at_day = s.day
  elseif s.day > at then
    memory.new_day(s, s.day - at) -- the day she lived teaches her (Bible §5)
  end

  if s.cycle <= 1 and s.name ~= "Audrey" then s.name = "Audrey" end

  s:compute_mood()
  if not s.powered_off and not s.deep_sleep and s.sitter_until == 0 then
    s:maybe_complain(now_ms)
    s:maybe_purr(now_ms)
  end
  s:try_evolve(now_ms)
  s:_life_cycle_check(now_ms)
  s:_try_start_scheduled_farewell(now_ms)
end

function M.simulate_second(s, now_ms)
  if s.sitter_until ~= 0 and scene_sancho.away_second(s, now_ms) then return end -- with Sancho: nothing changes
  local awake = (not s.sleeping) and (not s.deep_sleep) and (not s.powered_off)
  local sleeping = s.sleeping or s.deep_sleep
  if s._away and awake then
    s:enter_sleep(now_ms, "ausencia", false)
    awake, sleeping = false, true
  end
  litter.second(s)
  local ph = s.phase
  s._phase_seconds[ph] = (s._phase_seconds[ph] or 0) + 1

  if s.powered_off then
    s.hunger = s.hunger - (2.0 / 3600.0) * 0.3
    s.dirt = s.dirt + (2.0 / 3600.0) * 0.3
  elseif sleeping then
    -- asleep, per hour (v11): E +10, H -2, F -1, D +2
    s.energy = s.energy + 10.0 / 3600.0
    s.hunger = s.hunger - 2.0 / 3600.0
    s.affection = s.affection - 1.0 / 3600.0
    s.dirt = s.dirt + 2.0 / 3600.0 * litter.dirt_rate(s)
    s._nap_sec = s._nap_sec + 1
    s._awake_sec = 0
    -- she wakes on her own once rested (never cutting a nap just begun)
    if s.sleeping and not s.deep_sleep and not s._away and s.energy >= s.AUTO_WAKE_ENERGY
        and s._nap_sec >= s.MIN_NAP_SEC and not asks.tucked_in(s) then
      s.sleeping = false
      s.light_on = true
      s:_emit_sound("bosteza")
      s:_log_event("Se despierta sola")
      s:compute_mood()
      s:mark_dirty()
    elseif morning_wake_due(s) then
      s.sleeping, s.deep_sleep = false, false
      s.light_on = true
      s.morning_wake_ts = asks.now(s)
      s:_emit_sound("bosteza")
      s:_log_event("Se despierta por la mañana")
      s:compute_mood()
      s:mark_dirty()
    end
  elseif awake then
    -- awake, per hour (v11): H -6, F -3, E -4, D +5
    s.hunger = s.hunger - 6.0 / 3600.0
    s.affection = s.affection - 3.0 / 3600.0
    s.energy = s.energy - 4.0 / 3600.0
    s.dirt = s.dirt + 5.0 / 3600.0 * litter.dirt_rate(s)
    s._awake_sec = s._awake_sec + 1
    s._nap_sec = 0
    -- she dozes off when low: not just after waking nor in an action screen, unless exhausted (v11 phase 2)
    local exhausted = s.energy < s.AUTO_SLEEP_FORCE_ENERGY
    local may_doze = s.mode:sub(1, 7) ~= "action_" and s._awake_sec >= s.AUTO_SLEEP_GRACE_SEC
    local doze = s:_overweight() and s.DOZE_ENERGY_HEAVY or s.DOZE_ENERGY
    if s.energy < doze and (exhausted or may_doze) then s:enter_sleep(now_ms, "energia_baja", false) end
  end

  -- into deep sleep
  if not s.powered_off and not s.deep_sleep and s.sleeping and not s.light_on
      and s.energy <= s.DEEP_SLEEP_MIN_ENERGY and s._light_off_minutes >= s.AUTO_DEEP_SLEEP_LIGHT_OFF_MIN then
    s:request_deep_sleep(now_ms, "auto")
  end

  -- critical (D-03)
  s.in_critical = s:critical_now()
  if s.in_critical then
    s.critical_seconds = s.critical_seconds + 1
    s._critical_streak_sec = s._critical_streak_sec + 1
    s._sec_non_critical = 0
  else
    s._critical_streak_sec = 0
    s._sec_non_critical = s._sec_non_critical + 1
  end
  if s.health < 20.0 then s._low_health_streak_sec = s._low_health_streak_sec + 1
  else s._low_health_streak_sec = 0 end

  -- illness v2: types, causes, symptoms, cures
  v2_gameplay.maybe_trigger_illness(s, now_ms, awake)
  v2_gameplay.apply_illness_symptoms(s, now_ms, awake, sleeping)

  -- health by conditions, judged once a minute
  if s.hunger < 15.0 then s._sec_health_h = s._sec_health_h + 1 end
  if s.energy < 10.0 then s._sec_health_e = s._sec_health_e + 1 end
  if s.dirt > 80.0 then s._sec_health_d = s._sec_health_d + 1 end
  if s.affection < 15.0 then s._sec_health_f = s._sec_health_f + 1 end

  s._sim_second_accum = s._sim_second_accum + 1
  if s._sim_second_accum >= 60 then
    s._sim_second_accum = 0
    if not s.light_on and (s.sleeping or s.deep_sleep) then s._light_off_minutes = s._light_off_minutes + 1
    else s._light_off_minutes = 0 end

    local health_drop = 0
    if s._sec_health_h >= 1 then health_drop = health_drop + 1 end
    if s._sec_health_e >= 1 then health_drop = health_drop + 1 end
    if s._sec_health_d >= 1 then health_drop = health_drop + 1 end
    if s._sec_health_f >= 1 then health_drop = health_drop + 1 end
    health_drop = math.min(3, health_drop)
    if health_drop > 0 then s.health = s.health - health_drop end
    s._sec_health_h, s._sec_health_e, s._sec_health_d, s._sec_health_f = 0, 0, 0, 0

    s:_personality_drift_minute()
    needs.call_minute(s)
    stickers.check(s)
    visitors.minute(s)
    local alone = asks.now(s) >= s.last_input_ts + s.ABSENCE_SEC
    local h = events.hour(s)
    if alone and h >= 8 and h < 22 then
      memory.remember(s, "alone_min")
    elseif awake and s.mode == "main" and not s.hidden then
      memory.room_minute(s)
    end

    -- hidden, she comes out on her own once calm
    if s.hidden then
      local calm = s.stress < 45.0 or s.trust_bond > 70.0
      if calm and math.random() < 0.20 then
        s:_unhide(now_ms)
        s:_log_event("Sale de su escondite")
      end
    end

    asks.minute(s, now_ms)
    events.revetlla(s, now_ms)
    events.direct(s, now_ms)

    -- weight drifts with her metabolism: 0.0018 kg/h awake, half asleep (per minute)
    if awake then s.weight_kg = math.max(1.8, s.weight_kg - 0.0018 / 60.0)
    elseif sleeping then s.weight_kg = math.max(1.8, s.weight_kg - 0.0009 / 60.0) end

    local cs = s:care_score_minute()
    if s.phase ~= "Senior" and s.phase ~= "Extra" then s.growth_points = math.max(0.0, s.growth_points + cs) end
    s.care_points_total = s.care_points_total + cs
    s.care_minutes_total = s.care_minutes_total + 1
    s:_record_minute_metrics(s:_score_to_quality_01(cs))
    s:try_evolve(now_ms)
  end

  -- she recovers: +1 every 10 non-critical minutes in a row
  if s._sec_non_critical > 0 and s._sec_non_critical % 600 == 0 then s.health = math.min(100.0, s.health + 1.0) end

  -- the vet on her own when health stays very low
  if s._auto_vet_cd_sec > 0 then s._auto_vet_cd_sec = s._auto_vet_cd_sec - 1 end
  if s.health < 20.0 and s._low_health_streak_sec >= s.AUTO_VET_TRIGGER_SECONDS and s._auto_vet_cd_sec <= 0 then
    s:_apply_veterinary_care(now_ms, true)
  end

  -- off, out of energy
  if not s.powered_off and s.energy <= s.POWER_OFF_MIN_ENERGY then
    s.powered_off = true
    s.deep_sleep = false
    s.sleeping = false
    s.mode = "main"
    s.overlay_text = "Me apago... sin pilas"
    s.overlay_until = now_ms + 1400
    s:_log_event("Apagado")
  end

  -- away: hunger and health have floors (the critical time is already counted)
  if s._away then
    s.hunger = math.max(s.hunger, s.ABSENCE_HUNGER_FLOOR)
    s.health = math.max(s.health, s.ABSENCE_HEALTH_FLOOR)
  end

  s.hunger = math.max(0.0, math.min(100.0, s.hunger))
  s.energy = math.max(0.0, math.min(100.0, s.energy))
  s.affection = math.max(0.0, math.min(100.0, s.affection))
  s.health = math.max(0.0, math.min(100.0, s.health))
  s.dirt = math.max(0.0, math.min(100.0, s.dirt))
end

return M
