-- lifecycle: her life's arc, the v11 evaluation, the farewell and the birth, growing up, her legacy and nickname
-- (a port of audreygotchi/core/lifecycle.py).
local util = require("core.util")
local memory = require("core.memory")
local personality = require("core.personality")
local scene_grow = require("core.scene_grow")
local scene_sancho = require("core.scene_sancho")
local M = {}

local function max_ms(script) -- max(ms for _n, ms, _s in script)
  local m = script[1][2]
  for _, st in ipairs(script) do m = math.max(m, st[2]) end
  return m
end

local function clamp_index(i, n) -- min(max(0, int(i)), n - 1): a 0-based step, kept in range
  return math.min(math.max(0, util.int(i)), n - 1)
end

function M.should_extend_life(s)
  local m = s:_evaluation_metrics_7d()
  if m.samples_min_7d <= 0 then
    return false
  end
  if m.avg_f_7d < s.EVAL_MIN_AVG_F then
    return false
  end
  if m.avg_s_7d < s.EVAL_MIN_AVG_S then
    return false
  end
  if m.critical_minutes_7d > s.EVAL_MAX_CRITICAL_MIN then
    return false
  end
  if m.vet_visits_7d > s.EVAL_MAX_VET_VISITS then
    return false
  end
  return true
end

function M.schedule_farewell_sunset(s, now_ms)
  if s.farewell_started then
    return
  end
  s.farewell_scheduled_day = util.int(s.day) -- not announced (Bible §29): a new star
  s.stars = util.int(s.stars) + 1
  s:_log_event("Despedida programada (sunset)")
  s:mark_dirty()
end

function M.try_start_scheduled_farewell(s, now_ms)
  if s.farewell_started or util.int(s.farewell_scheduled_day) <= 0 then
    return
  end

  if util.int(s.day) < util.int(s.farewell_scheduled_day) then
    return
  end
  if util.int(s.clock:local_hour()) < s.FAREWELL_SUNSET_HOUR then
    return
  end
  if tostring(s.mode):sub(1, 7) == "action_" then
    return
  end
  if s.mode ~= "main" then
    return
  end

  s:_start_farewell(now_ms)
end

-- Bible §32-§34: each life leaves one object that says who she was, by her strongest trait
M.LEGACY = {sociability = "foto", activity = "juguete", curiosity = "piedra",
            affection = "cojin", food = "cuenco", rhythm = "estrella"}
local LEGACY_AXES = {"sociability", "activity", "curiosity", "affection", "food", "rhythm"} -- the dict's order
M.LEGACY_FROM = 0.55 -- a trait at least this strong picks the object; else a star stays
M.LEGACY_SHOWN = 6   -- the room shows the last ones

-- Bible §37: the gesture a new puppy may inherit, very rarely, from the last one's object
M.HEIRLOOM = {juguete = "rueda", piedra = "vuelta", cojin = "mimos", foto = "happy_wiggle",
              cuenco = "encontrada", estrella = "presume"}

-- The tiny gesture of the last Audrey before this one, or nil in a first life.
function M.heirloom(s)
  local earlier = {}
  for _, x in ipairs(s.legacy) do
    if util.int(util.get(x, "cycle", 0)) < util.int(s.cycle) then earlier[#earlier + 1] = x end
  end
  if #earlier == 0 then
    return nil
  end
  return M.HEIRLOOM[earlier[#earlier].item]
end

function M.leave_legacy(s)
  for _, x in ipairs(s.legacy) do
    if util.int(util.get(x, "cycle", 0)) == util.int(s.cycle) then
      return -- one per life
    end
  end
  local axis, best = nil, nil -- max(LEGACY, key=_pf): the first strongest, in the dict's order
  for _, a in ipairs(LEGACY_AXES) do
    local v = s:_pf(a)
    if best == nil or v > best then axis, best = a, v end
  end
  local item = "estrella"
  if s:_pf(axis) >= M.LEGACY_FROM then item = M.LEGACY[axis] end
  local legacy = util.copy(s.legacy)
  legacy[#legacy + 1] = {cycle = util.int(s.cycle), name = tostring(s.name), item = item}
  s.legacy = legacy
end

-- The owner's farewell script (2026-10-07, Guion completo de la despedida; after Bible §30):
-- night at home, she notices a star, it comes down and turns out to be a pet-taxi rocket, she
-- says goodbye to her home, boards from the balcony, it takes off and leaves her star in the
-- sky; the credits, and a quiet sky with her star before B starts a new life. No core text.
-- {step, how long in ms, its sound on entering it}
M.FAREWELL_SILENCE_MS = 10000 -- the quiet sky before B starts a new life
local function farewell_script(steps)
  local out = {}
  for _, st in ipairs(steps) do
    local name, ms = st[1], st[2]
    local sound = nil
    if name ~= "silencio" then sound = "adios_" .. name end
    out[#out + 1] = {name, ms, sound}
  end
  return out
end
M.FAREWELL_SCRIPT = farewell_script({
  -- 1, calm at home: the room, her, she notices something
  {"habitacion", 2500}, {"calma", 4000}, {"nota", 3000},
  -- 2, the sky: the camera to the window and up, a star unlike the others, back to her
  {"ventana", 3500}, {"estrella", 3000}, {"mira", 2500},
  -- 3, the star comes down: it pulses, falls, nears the house
  {"pulsa", 2000}, {"baja", 3000}, {"cerca", 3000},
  -- 4, it is a rocket: the reveal, at the balcony, its "pip pip"
  {"revela", 3000}, {"llega", 3000}, {"presenta", 2500},
  -- 5, goodbye home: she understands, looks round, walks off, the door, up the ramp, at its window
  {"entiende", 2500}, {"despide", 3500}, {"anda", 3500}, {"puerta", 3000}, {"sube", 4000},
  {"ventanita", 3000},
  -- 6, take-off: ready, up, the house from outside as it rises
  {"prepara", 2500}, {"despega", 3000}, {"aleja", 3500},
  -- 7, her star: smaller and smaller, the flash, the new star, the sky holds
  {"asciende", 3000}, {"destello", 2500}, {"su_estrella", 4000},
  -- 8, the credits, her last words, the game's credits and who it is a gift for, the game's
  -- logo, the quiet before a new life
  {"creditos", 10000}, {"gracias", 3500}, {"autores", 14500}, {"logo", 6000},
  {"silencio", M.FAREWELL_SILENCE_MS},
}) -- each step's music on entering it (adios_<step>, the platform's): the owner, 2026-10-07
M.FAREWELL_STEPS = {}
for i, st in ipairs(M.FAREWELL_SCRIPT) do M.FAREWELL_STEPS[i] = st[1] end
-- what B can choose under the logo once the quiet sky is over: the owner, 2026-10-07
M.FAREWELL_CHOICES = {"nueva_vida", "recuerdos"}

function M.start_farewell(s, now_ms)
  if s.farewell_started then
    return
  end
  s.farewell_started = true
  s.farewell_scheduled_day = 0
  s.farewell_done = false
  s.farewell_choice, s.farewell_memories = 0, false
  s.farewell_step = 0
  s.farewell_next_ms = now_ms + M.FAREWELL_SCRIPT[1][2]
  s.mode = "farewell"
  M.leave_legacy(s)
  s:_emit_sound(M.FAREWELL_SCRIPT[1][3]) -- its first step's music, as each step's on entering it
  s.overlay_text = nil
  s.overlay_until = 0
  s:_log_event("Despedida")
  s:mark_dirty()
end

-- The script's steps on their schedule, each step's sound once on entering it; only once the quiet sky has held
-- FAREWELL_SILENCE_MS does B start a new life.
function M.update_farewell(s, now_ms)
  if not s.farewell_started or s.farewell_done then
    return
  end
  local i = clamp_index(s.farewell_step, #M.FAREWELL_SCRIPT)
  if util.int(s.farewell_next_ms) - util.int(now_ms) > 2 * max_ms(M.FAREWELL_SCRIPT) then
    s.farewell_next_ms = now_ms + M.FAREWELL_SCRIPT[i + 1][2] -- set on the last boot's ticks
  end
  local last = #M.FAREWELL_SCRIPT - 1
  while not s.farewell_done and now_ms >= s.farewell_next_ms do
    if s.farewell_step < last then
      s.farewell_step = s.farewell_step + 1
      local step = M.FAREWELL_SCRIPT[s.farewell_step + 1]
      local ms, sound = step[2], step[3]
      s.farewell_next_ms = s.farewell_next_ms + ms
      if sound then
        s:_emit_sound(sound) -- once, on entering the step
      end
    else
      s.farewell_done = true
    end
    s:mark_dirty()
  end
end

function M.farewell_step_name(s)
  return M.FAREWELL_STEPS[clamp_index(s.farewell_step, #M.FAREWELL_STEPS) + 1]
end

-- {ms into the step, its length}: the platform draws the farewell by time, like the birth.
function M.farewell_timing(s)
  local length = M.FAREWELL_SCRIPT[clamp_index(s.farewell_step, #M.FAREWELL_SCRIPT) + 1][2]
  if s.farewell_done then
    return {length, length}
  end
  local left = util.int(s.farewell_next_ms) - util.int(s._frame_ms)
  return {math.max(0, math.min(length, length - left)), length}
end

-- The owner's intro (2026-10-06, Guion definitivo de la intro de nacimiento; Bible §28): no
-- text, ~31 s, the buttons waiting for her. {step, how long in ms, its sound on entering it}
M.BIRTH_STEPS = {
  {"negro", 300, nil}, {"cielo", 3000, nil}, {"estrella", 1600, "nace_estrella"},
  {"fugaz", 1400, "nace_fugaz"},       -- the owner: the sky held ~6 s, her star born, falling
  {"zoom", 3300, "nace_zoom"}, {"espera", 600, nil}, -- one calm camera move (owner, 2026-10-07)
  -- her moments: each frame ~0.4 s, so she is seen (the owner, 2026-10-07: too fast before)
  {"cae", 1200, "nace_cae"}, {"rebota", 1500, "nace_rebota"}, {"silencio", 800, nil},
  {"orejas", 2000, "nace_orejas"}, {"cola", 2000, "nace_cola"}, {"reveal", 2000, nil},
  {"bostezo", 2000, "nace_bostezo"}, {"mira", 2400, nil}, {"juzga", 2000, nil},
  {"saludo", 2000, "nace_saludo"}, {"idle", 1200, nil}, -- then as the game begins (owner)
  {"logo", 1600, "nace_logo"},
}

function M.start_birth(s, now_ms)
  s.mode = "birth"
  s.birth_step = 0
  s.birth_next_ms = util.int(now_ms) + M.BIRTH_STEPS[1][2]
  s.overlay_text = nil
  s.overlay_until = 0
  s:mark_dirty()
end

function M.update_birth(s, now_ms)
  if util.int(s.birth_next_ms) - util.int(now_ms) > 2 * max_ms(M.BIRTH_STEPS) then
    s.birth_next_ms = util.int(now_ms) + M.BIRTH_STEPS[1][2] -- set on the last boot's ticks
  end
  while s.mode == "birth" and now_ms >= s.birth_next_ms do
    if s.birth_step < #M.BIRTH_STEPS - 1 then
      s.birth_step = s.birth_step + 1
      local step = M.BIRTH_STEPS[s.birth_step + 1]
      local ms, sound = step[2], step[3]
      s.birth_next_ms = s.birth_next_ms + ms
      if sound then
        s:_emit_sound(sound) -- once, on entering the step
      end
    else -- born: the buttons' guide the first time (2026-10-09)
      if s.guide_seen then s.mode = "main" else s.mode = "guide" end
    end
    s:mark_dirty()
  end
end

-- B held: from her second life on, the intro gives way (the owner's script).
function M.skip_birth(s)
  if s.mode == "birth" and util.int(s.cycle) > 1 then
    s.mode = "main"
    s:mark_dirty()
  end
end

function M.birth_step_name(s)
  return M.BIRTH_STEPS[clamp_index(s.birth_step, #M.BIRTH_STEPS) + 1][1]
end

-- {ms into the step, its length}: the platform draws each step by time, not by frame.
function M.birth_timing(s)
  local length = M.BIRTH_STEPS[clamp_index(s.birth_step, #M.BIRTH_STEPS) + 1][2]
  local left = util.int(s.birth_next_ms) - util.int(s._frame_ms)
  return {math.max(0, math.min(length, length - left)), length}
end

-- A new stage, shown on glass, not written: its scene waits for you (scene_grow).
function M.show_growth(s, old, new, now_ms)
  scene_grow.due(s, old, new)
end

-- A or C at the farewell's end: the other choice; nothing to pick while her memories show.
function M.farewell_move(s)
  if s.farewell_done and not s.farewell_memories then
    s.farewell_choice = 1 - s.farewell_choice
  end
end

-- B at the farewell's end: the choice picked, a new life or her memories; from her memories, back to the choice.
function M.confirm_new_life_from_farewell(s, now_ms)
  if not (s.mode == "farewell" and s.farewell_started and s.farewell_done) then
    return
  end
  if s.farewell_memories then
    s.farewell_memories = false
  elseif M.FAREWELL_CHOICES[s.farewell_choice + 1] == "recuerdos" then
    s.farewell_memories = true
  else
    s:new_life()
    M.start_birth(s, now_ms)
  end
end

function M.phase_transition_day(s, phase_name)
  local wnd = s.PHASE_WINDOWS[tostring(phase_name)]
  if wnd == nil or #wnd == 0 then
    return 0
  end
  local start, stop = util.int(wnd[1]), util.int(wnd[2])
  local q = s:_care_score_7d_01()
  if q >= s.CARE_SHIFT_GOOD then
    return start
  end
  if q <= s.CARE_SHIFT_BAD then
    return stop
  end
  local t = (s.CARE_SHIFT_GOOD - q) / math.max(0.001, (s.CARE_SHIFT_GOOD - s.CARE_SHIFT_BAD))
  return util.int(util.round(start + t * (stop - start)))
end

function M.phase_from_age_days(s, age_days)
  local age = math.max(0, util.int(age_days))
  local d_juv = s:_phase_transition_day("Juvenil")
  local d_adult = s:_phase_transition_day("Adulto")
  local d_senior = s:_phase_transition_day("Senior")

  if age < d_juv then
    return "Cachorro"
  end
  if age < d_adult then
    return "Juvenil"
  end
  if age < d_senior then
    return "Adulto"
  end
  if age <= 39 then
    return "Senior"
  end
  if util.int(s.life_deadline_day) > s.LIFE_MIN_DAYS and age <= s.LIFE_MAX_DAYS then
    return "Extra"
  end
  return "Senior"
end

function M.next_phase(s)
  local i = util.index(s.PHASE_ORDER, s.phase) or 0
  if i >= #s.PHASE_ORDER - 1 then
    return nil
  end
  return s.PHASE_ORDER[i + 2] -- PHASE_ORDER[i + 1], 0-based
end

function M.evolution_progress(s)
  local age = math.max(0, util.int(s.age_days))
  if s.phase == "Cachorro" then
    local tgt = s:_phase_transition_day("Juvenil")
    return math.max(0.0, math.min(1.0, age / math.max(1, tgt)))
  end
  if s.phase == "Juvenil" then
    local start = s:_phase_transition_day("Juvenil")
    local stop = s:_phase_transition_day("Adulto")
    return math.max(0.0, math.min(1.0, (age - start) / math.max(1, stop - start)))
  end
  if s.phase == "Adulto" then
    local start = s:_phase_transition_day("Adulto")
    local stop = s:_phase_transition_day("Senior")
    return math.max(0.0, math.min(1.0, (age - start) / math.max(1, stop - start)))
  end
  if s.phase == "Senior" then
    return math.max(0.0, math.min(1.0, (age - 25) / math.max(1, 39 - 25)))
  end
  return 1.0
end

-- Grown, she gets her nickname once (owner, 2026-10-06): her most marked trait, as Status words it (about()), or
-- "neutral" when nothing stands out; it never changes after.
function M.give_nickname(s)
  if (s.nickname == nil or s.nickname == "") and util.contains({"Adulto", "Senior", "Extra"}, s.phase) then
    s.nickname = personality.about(s) or "neutral"
    s:mark_dirty()
  end
end

function M.try_evolve(s, now_ms)
  local old = tostring(s.phase)
  local calc = s:_phase_from_age_days(s.age_days)

  local old_i = util.index(s.PHASE_ORDER, old) or 0
  local new_i = util.index(s.PHASE_ORDER, calc)
  if new_i == nil then new_i = old_i end
  if new_i < old_i then
    calc = old
  end

  if calc == old then
    M.give_nickname(s) -- an older save's grown cat gets hers too
    return
  end

  s.phase = calc
  memory.first(s, "phase_" .. tostring(calc))
  s.affection = math.min(100.0, s.affection + 2.0)
  s.health = math.min(100.0, s.health + 2.0)

  M.show_growth(s, old, calc, now_ms)
  if old == "Cachorro" then
    scene_sancho.intro_due(s) -- his button comes now: he will come and meet her
  end
  M.give_nickname(s)

  s:_log_event("Evoluciona: " .. old .. "->" .. tostring(calc))
  s:mark_dirty()
end

function M.life_cycle_check(s, now_ms)
  if s.farewell_started then
    return
  end
  if util.int(s.farewell_scheduled_day) > 0 then
    return
  end

  -- checkpoints count full days lived (v9 §3.1); s.day is the 1-based day on screen
  if util.int(s.age_days) < util.int(s.life_deadline_day) then
    return
  end

  if util.int(s.life_deadline_day) >= s.LIFE_MAX_DAYS then
    s:_schedule_farewell_sunset(now_ms)
    return
  end

  if s:_should_extend_life() then
    -- she simply goes on living: never told she earned days, a star stays (Bible §27)
    s.stars = util.int(s.stars) + 1
    s.life_deadline_day = math.min(s.LIFE_MAX_DAYS, util.int(s.life_deadline_day) + s.LIFE_EXT_BLOCK)
    s:_log_event("Extiende vida a " .. tostring(s.life_deadline_day))
    s:mark_dirty()
  else
    s:_schedule_farewell_sunset(now_ms)
  end
end

return M
