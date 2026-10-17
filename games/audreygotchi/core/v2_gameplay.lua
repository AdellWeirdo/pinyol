-- v2_gameplay: her illnesses (types, triggers, symptoms, medicine) and her favourite and disliked food (a port of
-- audreygotchi/core/v2_gameplay.py).
local util = require("core.util")
local memory = require("core.memory")
local M = {}

-- --- V2 timings, in real time (they were QA-speed). Tune here while playing. ---
M.MINUTE_MS = 60000
M.HOUR_MS = 60 * M.MINUTE_MS
M.COLD_REST_MS = 2 * M.HOUR_MS                -- a cold clears after 2 h sick, once she sleeps
M.INDIGESTION_MS = 45 * M.MINUTE_MS           -- a tummy ache lasts 45 min
M.INDIGESTION_SNACK_MS = 20 * M.MINUTE_MS     -- a snack while it hurts adds 20 min
M.MEDICINE_INDIGESTION_CUT_MS = 15 * M.MINUTE_MS
M.MEDICINE_INDIGESTION_MIN_MS = 20 * M.MINUTE_MS
M.STRESS_ILLNESS_PER_H = 6.0                  -- stress the stress illness adds per hour

local ILLNESSES = {"resfriado", "indigestion", "estres", "agotamiento"}

local function strip(x) return (x:match("^%s*(.-)%s*$")) end

local function _ensure_fields(s)
  if s.favorite_food == nil then s.favorite_food = "" end
  if s.disliked_food == nil then s.disliked_food = "" end
  -- sick_type: Python sets None when missing, which in Lua is the field left out
  if s.sick_cause == nil then s.sick_cause = "" end
  if s.sick_since_ms == nil then s.sick_since_ms = 0 end
  if s.indigestion_until_ms == nil then s.indigestion_until_ms = 0 end
  if s._snack_streak == nil then s._snack_streak = 0 end
end

-- The Python's own deterministic seed (no hash()): sum of (i + 1) * code point over "name|cycle|sorted quirks",
-- mod 0x7FFFFFFF. The string is walked by code points as Python does (UTF-8; bytes if it is not valid UTF-8, which
-- for Latin-1 text are the same numbers), and the sum is kept below 2^31 so it never wraps a 32-bit integer.
local function _stable_seed(s)
  local quirks = {}
  for _, x in ipairs(s.quirks) do quirks[#quirks + 1] = tostring(x) end
  table.sort(quirks)
  local cycle = math.tointeger(s.cycle) or s.cycle
  local raw = tostring(s.name) .. "|" .. tostring(cycle) .. "|" .. table.concat(quirks, ",")
  local MOD = 0x7FFFFFFF
  local acc, i = 0, 0
  local function add(code)
    local term = ((i + 1) * code) % MOD
    if term >= MOD - acc then acc = term - (MOD - acc) else acc = acc + term end
    i = i + 1
  end
  if utf8.len(raw) then
    for _, code in utf8.codes(raw) do add(code) end
  else
    for k = 1, #raw do add(raw:byte(k)) end
  end
  return acc
end
M._stable_seed = _stable_seed

local function _pick_unique(food_options, preferred_idx) -- 0-based indices, as the Python
  local n = math.max(1, #food_options)
  local idx = util.int(preferred_idx) % n
  if n == 1 then
    return idx
  end
  local out = (idx + 1) % n
  if out == idx then
    out = (out + 1) % n
  end
  return out
end

function M.init_v2_state(s)
  M.refresh_food_preferences(s)
end

function M.restore_v2_state_after_load(s)
  _ensure_fields(s)
  M.refresh_food_preferences(s)
  if s.sick then
    local st = s.sick_type
    if st == nil or st == false then st = "" end
    if strip(tostring(st)) == "" then
      s.sick_type = M.infer_illness_type(s)
    end
  else
    s.sick_type = nil
    s.sick_cause = ""
    s.sick_since_ms = 0
  end
end

function M.refresh_food_preferences(s)
  -- milk is a puppy's: never her favourite nor what she dislikes (the owner, 2026-10-06)
  local foods = {}
  for _, x in ipairs(util.get(s, "FOOD_OPTIONS", {})) do
    local name = tostring(x)
    if name ~= "" and name ~= "Leche" then foods[#foods + 1] = name end
  end
  if #foods < 2 then
    s.favorite_food = #foods > 0 and foods[1] or ""
    s.disliked_food = #foods > 0 and foods[1] or ""
    return
  end

  local seed = _stable_seed(s)
  local fav_idx = seed % #foods                -- 0-based

  local snacks = util.get(util.get(s, "FEED_TYPE_FOODS", {}), "Snack", {})
  if util.contains(util.get(s, "quirks", {}), "Glotona") and #snacks > 0 then
    local snack_idx = {}
    for i, x in ipairs(foods) do
      if util.contains(snacks, x) then snack_idx[#snack_idx + 1] = i - 1 end
    end
    if #snack_idx > 0 then
      fav_idx = snack_idx[seed % #snack_idx + 1]
    end
  end

  -- ported as is: _pick_unique only steps off the index it is given, so when (seed // n) % n == n - 1 the disliked
  -- food is her favourite too (e.g. "Audrey", cycle 1, Curiosa+Glotona+Huidiza: Chuches and Chuches)
  local disliked_idx = _pick_unique(foods, fav_idx + ((seed // math.max(1, #foods)) % #foods))
  s.favorite_food = tostring(foods[fav_idx + 1])
  s.disliked_food = tostring(foods[disliked_idx + 1])
end

function M.register_feed_outcome(s, now_ms, food_name, feed_type)
  local ftype = feed_type ~= nil and tostring(feed_type) or ""
  if ftype == "Snack" then
    s._snack_streak = math.min(6, util.int(s._snack_streak) + 1)
  else
    s._snack_streak = math.max(0, util.int(s._snack_streak) - 1)
  end

  if s.sick and s.sick_type == "indigestion" and ftype == "Snack" then
    s.indigestion_until_ms = math.max(util.int(s.indigestion_until_ms), util.int(now_ms) + M.INDIGESTION_SNACK_MS)
  end

  if not s.sick and ftype == "Snack" then
    local overfed = (util.int(s._snack_streak) >= 3) and (s.hunger > 68.0)
    if overfed and math.random() < 0.45 then
      M.start_illness(s, "indigestion", now_ms, "exceso_snacks")
    end
  end
end

function M.infer_illness_type(s)
  if s.energy < 10.0 then
    return "agotamiento"
  end
  if s.stress > 75.0 then
    return "estres"
  end
  if s.dirt > 65.0 and s.energy < 35.0 then
    return "resfriado"
  end
  return "indigestion"
end

local SICK_TEXT = {
  resfriado = "¡Achís! Me resfrié",
  indigestion = "Ay, mi barriguita",
  estres = "Estoy muy agobiada",
  agotamiento = "No puedo con mi alma",
}

function M.start_illness(s, illness, now_ms, cause)
  local ill = (illness == nil or illness == false) and "" or strip(tostring(illness)):lower()
  if not util.contains(ILLNESSES, ill) then
    return
  end
  s.sick = true
  s._med_doses = 0          -- a new illness counts its own doses
  memory.first(s, "sick")
  s:_emit_sound("enferma")
  s.sick_type = ill
  s.sick_cause = (cause == nil or cause == false) and "" or tostring(cause)
  s.sick_since_ms = util.int(now_ms)
  if ill == "indigestion" then
    s.indigestion_until_ms = math.max(util.int(s.indigestion_until_ms), util.int(now_ms) + M.INDIGESTION_MS)
  end
  if s.mode == "main" then
    s.overlay_text = util.get(SICK_TEXT, ill, "Me siento malita")
    s.overlay_until = util.int(now_ms) + 1200
  end
  s:_log_event("Enfermedad: " .. ill)
  s:mark_dirty()
end

local function current_illness(s) -- str(getattr(state, "sick_type", "") or infer_illness_type(state))
  local st = s.sick_type
  if st == nil or st == false or st == "" then st = M.infer_illness_type(s) end
  return tostring(st)
end

function M.cure_illness(s, now_ms, reason)
  reason = reason or "recuperacion"
  if not s.sick then
    return
  end
  local ill = current_illness(s)
  s.sick = false
  s.sick_type = nil
  s.sick_cause = ""
  s.sick_since_ms = 0
  s.indigestion_until_ms = 0
  s._med_doses = 0
  s:_log_event("Curada: " .. ill .. " (" .. tostring(reason) .. ")")
  s:mark_dirty()
end

function M.maybe_trigger_illness(s, now_ms, awake)
  if s.sick then
    return
  end

  local p_resfriado = 0.0
  if s.energy < 35.0 and s.dirt > 60.0 then
    p_resfriado = 0.003 + 0.003 * s:_pf("sensitivity")
  end

  local p_estres = 0.0
  if s.stress > 78.0 and s.affection < 40.0 then
    p_estres = 0.003 + 0.003 * s:_pf("sensitivity")
  end

  local p_agot = 0.0
  if awake and s.energy < 12.0 then
    p_agot = 0.004 + 0.003 * (1.0 - s:_pf("resilience"))
  end

  local roll = math.random()
  if p_agot > 0.0 and roll < p_agot then
    M.start_illness(s, "agotamiento", now_ms, "energia_baja_sostenida")
    return
  end
  if p_estres > 0.0 and roll < p_estres then
    M.start_illness(s, "estres", now_ms, "estres_alto")
    return
  end
  if p_resfriado > 0.0 and roll < p_resfriado then
    M.start_illness(s, "resfriado", now_ms, "suciedad_y_frio")
    return
  end
end

function M.apply_illness_symptoms(s, now_ms, awake, sleeping)
  if not s.sick then
    return
  end
  local ill = current_illness(s)
  s.sick_type = ill

  if ill == "resfriado" then
    s.energy = s.energy - 1.1 / 3600.0
    s.health = s.health - 1.0 / 3600.0
    if sleeping and (util.int(now_ms) - util.int(s.sick_since_ms)) > M.COLD_REST_MS then
      M.cure_illness(s, now_ms, "descanso")
      return
    end

  elseif ill == "indigestion" then
    s.hunger = s.hunger - 1.5 / 3600.0
    s.health = s.health - 0.8 / 3600.0
    if util.int(now_ms) >= util.int(s.indigestion_until_ms) and (sleeping or s.energy > 35.0) then
      M.cure_illness(s, now_ms, "tiempo")
      return
    end

  elseif ill == "estres" then
    s.stress = s:_clamp_stat(s.stress + M.STRESS_ILLNESS_PER_H / 3600.0)
    s.affection = s.affection - 1.0 / 3600.0
    s.health = s.health - 0.4 / 3600.0
    if s.stress < 45.0 and s.affection > 55.0 then
      M.cure_illness(s, now_ms, "calma")
      return
    end

  elseif ill == "agotamiento" then
    if awake then
      s.energy = s.energy - 1.7 / 3600.0
      s.health = s.health - 1.1 / 3600.0
    end
    if sleeping and s.energy > 52.0 then
      M.cure_illness(s, now_ms, "recupero_energia")
      return
    end
  end
end

M.DOSES = {resfriado = 1, indigestion = 2, estres = 2, agotamiento = 2}
-- a dose short of the cure says what else helps (the owner, 2026-10-09: no guessing)
M.NEXT_DOSE = {indigestion = "Mejor... otra dosis y nada de chuches",
               estres = "Más tranquila... otra dosis y mimos",
               agotamiento = "Otra dosis y a dormir"}
M.CURED = {resfriado = "¡Adiós, mocos!", indigestion = "¡Barriga como nueva!",
           estres = "Ya estoy tranquila", agotamiento = "¡Pilas cargadas!"}

-- Medicine cures every illness, the Tamagotchi way (the owner, 2026-10-09): a cold at the first dose, the rest at
-- the second (DOSES), sooner when she is already better; a dose short of it eases her and says what else helps.
-- Returns {applied = bool, cured = bool, message = string}.
function M.apply_medicine(s, now_ms)
  if not s.sick then
    return {applied = false, cured = false, message = "¡Estoy como una rosa!"}
  end
  local ill = current_illness(s)
  s.sick_type = ill
  s._med_doses = util.int(s._med_doses) + 1
  s.health = math.min(100.0, s.health + 6.0)
  if ill == "resfriado" then
    s.health = math.min(100.0, s.health + 10.0)
    s.energy = math.min(100.0, s.energy + 6.0)
  elseif ill == "indigestion" then
    s.indigestion_until_ms = math.max(util.int(now_ms) + M.MEDICINE_INDIGESTION_MIN_MS,
                                      util.int(s.indigestion_until_ms) - M.MEDICINE_INDIGESTION_CUT_MS)
  elseif ill == "estres" then
    s.stress = s:_clamp_stat(s.stress - 24.0)
  elseif ill == "agotamiento" then
    s.energy = math.min(100.0, s.energy + 18.0)
  end
  local better = (ill == "estres" and s.stress <= 45.0) or (ill == "agotamiento" and s.energy >= 45.0)
  if better or s._med_doses >= util.get(M.DOSES, ill, 1) then
    M.cure_illness(s, now_ms, "medicina")
    return {applied = true, cured = true, message = util.get(M.CURED, ill, "¡Curada!")}
  end
  return {applied = true, cured = false, message = util.get(M.NEXT_DOSE, ill, "Medicina tomada")}
end

return M
