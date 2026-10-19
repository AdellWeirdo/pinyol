-- scene_sancho: Sancho, her flatmate, takes her for the day: the owner's babysitter, 2026-10-04 (a port of
-- audreygotchi/core/scene_sancho.py).
-- Called from the menu, once a local day, he takes her for SITTER_SEC; B picks her up before. While she is away
-- nothing about her changes (her stats stay as they were, no events, no illness), and for the v11 evaluation the
-- time counts as well cared. Back, she has missed you: SITTER_MISSED_F less affection.
-- `sitter_until` is a wall-clock timestamp (an integer), so the stay survives the board being off; catch-up brings
-- her back at the right simulated time.
local util = require("core.util")
local M = {}

function M.away(s)
  return util.int(s.sitter_until) > 0
end

local function _today(s)
  local lt = s.clock:localtime()
  return util.int(lt.tm_year) * 1000 + util.int(lt.tm_yday)
end

local _SAYS = {sleeping = "Shhh... ¡que duerme!", hidden = "Primero, encuéntrala",
               critical = "Te necesita a ti", today = "Sancho ya vino hoy"}

-- Why he cannot come now, as a key (the platform words it; _SAYS is B's answer), or nil.
function M.why_not(s)
  if s.sleeping then
    return "sleeping"
  end
  if s.hidden then
    return "hidden"
  end
  if s.in_critical then
    return "critical"
  end
  if util.int(s.sitter_day) ~= 0 and util.int(s.sitter_day) == _today(s) then -- 0: he never came
    return "today"
  end
  return nil
end

local function _refusal(s)
  local key = M.why_not(s)
  if key then
    return _SAYS[key]
  end
  return nil
end

-- The menu's Sancho: if he may come, ask first (No picked), the owner's wish.
function M.ask(s, now_ms)
  local refusal = _refusal(s)
  if refusal then
    s.overlay_text = refusal
    s.overlay_until = now_ms + 900
  else
    s.mode, s.sitter_yes = "sitter_confirm", false
  end
  s:mark_dirty()
end

-- A picks Sí, C picks No.
function M.choose(s, yes)
  s.sitter_yes = not not yes
  s:mark_dirty()
end

-- B on the question: Sí sends her off with him, No keeps her home.
function M.confirm(s, now_ms)
  s.mode = "main"
  if s.sitter_yes then
    M.call(s, now_ms)
  end
  s:mark_dirty()
end

-- He comes and takes her, if he may.
function M.call(s, now_ms)
  local refusal = _refusal(s)
  if refusal then
    s.overlay_text = refusal
    s.overlay_until = now_ms + 900
    s:mark_dirty()
    return
  end
  s.sitter_until = util.int(s.clock:now()) + util.int(s.SITTER_SEC)
  s.sitter_day = _today(s)
  s:_emit_sound("sancho")
  s.overlay_text = "¡Me voy con Sancho!"
  s.overlay_until = now_ms + 900
  s:_log_event("Se va con Sancho")
  s:mark_dirty()
end

-- Back home, early (B) or when the stay is over; she has missed you. by_hand defaults to true.
function M.pick_up(s, now_ms, by_hand)
  if by_hand == nil then by_hand = true end
  s.sitter_until = 0
  s._away = false -- not asleep on arrival, the absence rule waits a second
  if by_hand then -- you are here: picking her up ends any absence
    s.last_input_ts = util.int(s.clock:now())
    s._was_away = false
  end
  s.affection = math.max(0.0, s.affection - s.SITTER_MISSED_F)
  s:_emit_sound("vuelve")
  s.overlay_text = "¡Sancho me trajo!"
  s.overlay_until = now_ms + 900
  s:_log_event("Vuelve de casa de Sancho")
  s:compute_mood()
  s:mark_dirty()
end

-- One simulated second of her stay. True while she is still away (the rest of the simulation skips it), false once
-- she is back and the second goes on as usual.
function M.away_second(s, now_ms)
  local sim_ts = s._sim_ts -- getattr(state, "_sim_ts", 0) or now()
  if sim_ts == nil or sim_ts == 0 then sim_ts = s.clock:now() end
  if sim_ts >= util.int(s.sitter_until) then
    M.pick_up(s, now_ms, false)
    return false
  end
  s._sim_second_accum = s._sim_second_accum + 1
  if s._sim_second_accum >= 60 then
    s._sim_second_accum = 0
    s:_record_minute_metrics(1.0) -- well cared, the owner's call
    s:try_evolve(now_ms)          -- she keeps growing
  end
  return true
end

function M.left_min(s)
  if not M.away(s) then
    return 0
  end
  return math.max(0, (util.int(s.sitter_until) - util.int(s.clock:now()) + 59) // 60)
end

-- His introduction (the owner, 2026-10-06): every life, his button comes with Juvenil and he comes in to explain
-- himself: walks in, greets her, says what he does, points at his button. {step, how long it shows, ms}; B moves it on.
M.INTRO_STEPS = {{"llega", 3000}, {"saluda", 3000}, {"explica", 6000}, {"menu", 5000}}
M.INTRO_AFTER_SEC = 8 -- her growth's celebration plays first
M.INTRO_SEEN_SEC = 60 -- a button pressed this recently: you are there to see him

local function intro_max_ms() -- max(ms for _, ms in INTRO_STEPS)
  local m = M.INTRO_STEPS[1][2]
  for _, st in ipairs(M.INTRO_STEPS) do m = math.max(m, st[2]) end
  return m
end

-- She has grown out of puppyhood: he will come and meet her.
function M.intro_due(s)
  s.sancho_intro_at = util.int(s.clock:now()) + M.INTRO_AFTER_SEC
end

-- Each frame: start his introduction once it is due and you are there to see it, then move it on as each step's
-- time is up.
function M.update_intro(s, now_ms)
  if s.mode == "sancho_intro" then
    local left = util.int(s._intro_next_ms) - util.int(now_ms)
    if left <= 0 or left > 2 * intro_max_ms() then -- time's up, or the tick wrapped
      M.intro_next(s, now_ms)
    end
    return
  end
  local at, now = util.int(s.sancho_intro_at), s.clock:now()
  if at == 0 or now < at or now - s.last_input_ts > M.INTRO_SEEN_SEC then
    return
  end
  if s.grow_to ~= nil and s.grow_to ~= "" then -- her growing up shows first (scene_grow)
    return
  end
  if (s.mode ~= "main" or s.sleeping or s.deep_sleep or s.powered_off
      or s.hidden or s.sick or s.in_critical or M.away(s)) then
    return
  end
  s.mode, s.intro_step = "sancho_intro", 0
  s._intro_next_ms = util.int(now_ms) + M.INTRO_STEPS[1][2]
  s.overlay_text, s.overlay_until = nil, 0
  s:mark_dirty()
end

-- The next step (B, or its time is up); after the last, home with his button picked.
function M.intro_next(s, now_ms)
  s.intro_step = util.int(s.intro_step) + 1
  if s.intro_step >= #M.INTRO_STEPS then
    s.mode, s.sancho_intro_at, s.intro_step = "main", 0, 0
  else
    s._intro_next_ms = util.int(now_ms) + M.INTRO_STEPS[s.intro_step + 1][2]
    local items = s:active_menu_items()
    if M.INTRO_STEPS[s.intro_step + 1][1] == "menu" and util.contains(items, "Sitter") then
      s.selected_index = util.index(items, "Sitter") -- his button, ringed
    end
  end
  s:mark_dirty()
end

function M.intro_step_name(s)
  return M.INTRO_STEPS[math.min(math.max(0, util.int(s.intro_step)), #M.INTRO_STEPS - 1) + 1][1]
end

return M
