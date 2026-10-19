-- personality: her temperament, her complaints, purrs and refusals (a port of audreygotchi/core/personality.py).
local util = require("core.util")
local M = {}

-- The Character Bible's six axes (§5.1), each 0 at one end and 1 at the other: independent-social,
-- calm-playful, cautious-curious, reserved-affectionate, picky-foodie, early-night owl; and a
-- seventh from her whims, independent-pampered (owner, 2026-10-06). She is born neutral but for
-- her quirks and learns the rest living with you (core/memory.lua).
M.AXES = {"sociability", "activity", "curiosity", "affection", "food", "rhythm", "pampered"}
M.QUIRK_BIAS = {Curiosa = {curiosity = 0.1}, Dormilona = {activity = -0.1, rhythm = -0.05},
                Glotona = {food = 0.1}, Huidiza = {sociability = -0.1, affection = -0.05}}
M.ABOUT_FROM = 0.15 -- an axis this far from the middle is worth a sentence in Status
-- a spoilt cat plays the diva (the owner, 2026-10-09, Tamagotchi's discipline): no reason, a no;
-- its odds grow with the pampered axis past DIVA_FROM, and you may spoil her or scold her for it
M.DIVA_P, M.DIVA_FROM = 0.4, 0.5 -- born neutral (0.5), never; at its most spoilt (0.8), 12 %
M.DIVA_LINES = {"Ahora no, que estoy divina", "Mmm... no me apetece", "Si me lo pides mejor..."}

local function has_text(v) -- Python's truthiness of an Optional[str]
  return v ~= nil and v ~= false and v ~= ""
end

function M.generate_personality(s)
  local p = {}
  for _, axis in ipairs(M.AXES) do p[axis] = 0.5 end
  for _, quirk in ipairs(s.quirks) do
    local bias = util.get(M.QUIRK_BIAS, quirk, {})
    for _, axis in ipairs(util.keys(bias)) do p[axis] = p[axis] + bias[axis] end
  end
  -- innate, for illness: they do not learn
  p.resilience = 0.5 - (util.contains(s.quirks, "Glotona") and 0.08 or 0.0) + util.uniform(-0.08, 0.08)
  p.sensitivity = 0.5 + (util.contains(s.quirks, "Huidiza") and 0.14 or 0.0) + util.uniform(-0.08, 0.08)
  for _, k in ipairs(util.keys(p)) do
    p[k] = math.max(0.0, math.min(1.0, p[k]))
  end
  return p
end

-- Status's sentence about who she is (Bible §6, §50): the axis furthest from the middle, if any is far
-- enough, as "<axis>_hi" or "<axis>_lo"; never a number.
function M.about(s)
  local best, far = nil, M.ABOUT_FROM
  for _, axis in ipairs(M.AXES) do
    local d = M.pf(s, axis) - 0.5
    if math.abs(d) >= far then
      best, far = axis .. (d > 0 and "_hi" or "_lo"), math.abs(d)
    end
  end
  return best
end

function M.pf(s, key, default)
  if default == nil then default = 0.5 end
  local p = s.personality
  local v = default
  if type(p) == "table" then v = util.get(p, key, default) end
  if type(v) == "number" then return v + 0.0 end
  local n = type(v) == "string" and tonumber(v) or nil -- float("0.7"); anything else: the default
  if n then return n + 0.0 end
  return default + 0.0
end

function M.clamp_stat(_s, v, lo, hi)
  if lo == nil then lo = 0.0 end
  if hi == nil then hi = 100.0 end
  return math.max(lo, math.min(hi, v + 0.0))
end

function M.personality_drift_minute(s)
  -- Stress T (D-12), per hour and applied each minute: asleep -6, critical +4, awake and calm -2.
  -- A decimal accumulator; the UI shows the integer.
  local stress_per_h
  if s.sleeping or s.deep_sleep then
    stress_per_h = -6.0
  elseif s.in_critical then
    stress_per_h = 4.0
  else
    stress_per_h = -2.0
  end
  s.stress = s:_clamp_stat(s.stress + stress_per_h / 60.0)

  -- the bond moves slowly: up with steady care, down with accumulated stress
  local care_proxy = (s.affection * 0.35 + s.health * 0.35 + s.energy * 0.30) / 100.0
  local trust_delta = (care_proxy - 0.55) * 1.1 - ((s.stress - 50.0) / 100.0) * 0.8
  s.trust_bond = s:_clamp_stat(s.trust_bond + trust_delta)

  -- excitement and confidence tend to their baseline, with inertia
  s.excitement = s:_clamp_stat(s.excitement - s.PERSONALITY_DECAY_PER_MIN * (s.excitement - 50.0))
  s.confidence = s:_clamp_stat(s.confidence - s.PERSONALITY_DECAY_PER_MIN * (s.confidence - 50.0))
end

function M.maybe_complain(s, now_ms)
  if s.mode ~= "main" then return end
  if has_text(s.overlay_text) and now_ms < s.overlay_until then
    return -- never talk over what is on screen
  end
  if now_ms < s._complain_cd_until_ms then return end

  local p = 0.0
  local msg = nil
  local sound = nil -- v9 §16.1

  if s.sick then
    p = 0.10 + (0.04 * s:_pf("sensitivity"))
    msg, sound = "Miau... estoy malita", "enferma"
  elseif s.in_critical then
    p = 0.12 + (0.05 * s:_pf("sensitivity"))
    msg, sound = "¡MIAU! ¡Ayúdame!", "alerta"
  elseif s.hunger <= 12 then
    p = 0.08 + (0.04 * s:_pf("sensitivity"))
    msg, sound = "¡Miaaau! ¡Hambre!", "hambre"
  elseif s.energy <= 12 then
    p = 0.06 + (0.02 * (1.0 - s:_pf("sociability")))
    msg = "Zzz... qué sueño"
  end

  if msg and math.random() < p then
    if sound then s:_emit_sound(sound) end
    s.overlay_text = msg
    s.overlay_until = now_ms + 900
    s:_log_event((msg:gsub("%(", ""):gsub("%)", "")))
    s._complain_cd_until_ms = now_ms + 12000
    s:mark_dirty()
  end
end

M.PURR_CD_MS = 180000 -- a purr at most every 3 min: each one now plays on glass

function M.maybe_purr(s, now_ms)
  if s.mode ~= "main" then return end
  if has_text(s.overlay_text) and now_ms < s.overlay_until then
    return -- never talk over what is on screen
  end
  if now_ms < s._purr_cd_until_ms then return end
  local purr_p = 0.02 + 0.08 * (s.trust_bond / 100.0) + 0.04 * s:_pf("sociability")
  if s.mood == "affectionate" and math.random() < purr_p then
    s:_emit_sound("ronronea") -- shown, not written, and not logged: it filled the log
    s._purr_cd_until_ms = now_ms + M.PURR_CD_MS
    s:mark_dirty()
  end
end

-- The tail: "up" happy / playful; "down" tired, hungry or unwell; "neutral" the rest.
function M.tail_pose(s)
  if s.powered_off or s.deep_sleep or s.hidden then
    return "neutral"
  end
  if s.sick or s.in_critical or s.health < 45.0 or s.energy < 25.0 or s.hunger < 25.0 then
    return "down"
  end
  if s.affection >= 70.0 and s.energy >= 35.0 and s.hunger >= 35.0 and s.health >= 55.0 then
    return "up"
  end
  return "neutral"
end

-- D-16: when several rejection conditions hold, ONE roll against the highest probability -- never one roll
-- per condition, never a sum. `candidates` is an array of {probability, message} for the conditions that
-- hold; returns the message or nil.
function M.pick_rejection(candidates)
  if #candidates == 0 then return nil end
  local best = candidates[1]
  for i = 2, #candidates do
    if candidates[i][1] > best[1] then best = candidates[i] end -- the first of the highest, as max()
  end
  local p, msg = best[1], best[2]
  if p >= 1.0 or math.random() < p then return msg end -- 1.0: a no, every time
  return nil
end

-- Why she will not go to bed: she wants something. Her most pressing want, as {the words she says, the menu
-- item that answers it}.
function M.sleep_refusal_want(s)
  if s.hunger < 50.0 then
    return {"¡Primero la cena!", "Feed"}
  end
  if s.affection < 50.0 then
    return {"¡Antes, mimos!", "Cuddle"}
  end
  return {"¿Dormir? ¡A jugar!", "Play"}
end

local PLAY_ACTIONS = {juego = true, play = true}
local CUDDLE_ACTIONS = {mimos = true, cuddle = true}
local SLEEP_ACTIONS = {sleep = true, dormir = true}

function M.should_reject(s, now_ms, action)
  if now_ms < s._reject_cd_until_ms then return nil end

  local act = tostring(action or ""):match("^%s*(.-)%s*$"):lower()

  -- v8.1 §5.4, fixed odds; D-16: several conditions combine by the highest. Food's full-belly refusal is
  -- judged on the feed screen, where meal and snack differ.
  local candidates = {}
  if PLAY_ACTIONS[act] then
    if s.energy < s.GAME_MIN_ENERGY then -- spent: a no, every time (2026-10-09)
      candidates[#candidates + 1] = {1.0, "Estoy sin pilas"}
    elseif s.energy < 20.0 then
      candidates[#candidates + 1] = {0.50, "Estoy sin pilas"}
    end
    if s.stress > 70.0 then
      candidates[#candidates + 1] = {0.40, "Hoy no estoy para juegos"}
    end
  end

  if CUDDLE_ACTIONS[act] then
    if s.affection > 90.0 then
      candidates[#candidates + 1] = {0.50, "Voy servida de mimos"}
    end
    if s.stress > 80.0 then
      candidates[#candidates + 1] = {0.30, "Necesito mi espacio"}
    end
  end

  -- the owner's rule (2026-10-04), beyond v11: sent to bed with energy to spare, she refuses, and says what
  -- she wants instead (see sleep_refusal_want)
  if SLEEP_ACTIONS[act] and s.energy > 80.0 then
    candidates[#candidates + 1] = {0.50, M.sleep_refusal_want(s)[1]}
  end

  local diva = M.DIVA_P * math.max(0.0, M.pf(s, "pampered") - M.DIVA_FROM)
  if diva ~= 0 and (PLAY_ACTIONS[act] or CUDDLE_ACTIONS[act]) then
    candidates[#candidates + 1] = {diva, M.DIVA_LINES[util.int(s._interactions_total) % #M.DIVA_LINES + 1]}
  end
  local msg = M.pick_rejection(candidates)
  if msg ~= nil then
    s._reject_cd_until_ms = now_ms + 1200
  end
  return msg
end

return M
