-- anim: which picture Audrey shows and what she plays once over it, from the sim's snapshot. A port of the board
-- game's platforms/esp32s3/animation.py (same tables, same rules); the sets are art.py's A_<SET> pictures.
local SETS = require("sets")
local M = {}

M.HOLIDAYS = {"navidad", "halloween", "sant_jordi", "caga_tio", "nochevieja", "reyes", "carnaval", "pascua",
              "sant_joan", "diada"}
local IS_HOLIDAY = {}
for _, h in ipairs(M.HOLIDAYS) do IS_HOLIDAY[h] = true end

-- a resting set's gestures: the one-offs, and the fewest and most animation ticks between two
local GESTURES = {
  idle = {{"ear_twitch", "tail_flick", "vuelta"}, 30, 75},
  idle_curious = {{"vuelta", "ear_twitch"}, 15, 40},
  idle_bored = {{"yawn", "tail_flick"}, 30, 75},
  idle_grumpy = {{"juzgando", "tail_flick"}, 23, 56},
  idle_sad = {{"cansada", "tail_flick"}, 38, 94},
  idle_lonely = {{"pedir", "ear_twitch"}, 23, 56},
  tired = {{"yawn", "cansada"}, 11, 30},
  happy = {{"happy_wiggle", "encontrada"}, 23, 56},
  happy_love = {{"mimos", "encontrada"}, 23, 56},
  happy_playful = {{"happy_wiggle", "tail_flick", "vuelta"}, 15, 40},
  happy_excited = {{"vuelta", "happy_wiggle"}, 11, 30},
  orgullosa = {{"presume"}, 23, 56},
  cojin = {{"cojin_espera"}, 23, 56},
  bola = {{"bola_oreja", "bola_cola", "bola_ojo"}, 11, 38},
  hidden = {{"esconde_orejas", "esconde_ojos", "esconde_cola", "esconde_pata"}, 11, 38},
}
for _, h in ipairs(M.HOLIDAYS) do -- in costume only its own gestures: a plain one would take it off
  local d = "disfraz_" .. h
  GESTURES[d] = {{d .. "_parpadea", d .. "_gesto", d .. "_fiesta"}, 23, 56}
end
local COSTUME_PARTY = {fiesta = true, gana = true, crece = true, amigo = true}

local PUPPY_ONCE = {
  ear_twitch = "cachorro_parpadea", tail_flick = "cachorro_cola", vuelta = "cachorro_pata",
  celebra = "cachorro_contenta", bola_entra = "cachorro_oye",
  yawn = "cachorro_yawn", cansada = "cachorro_cansada", pedir = "cachorro_pedir",
  mimos = "cachorro_mimos", enamorada = "cachorro_enamorada", rueda = "cachorro_enamorada",
  ablanda = "cachorro_enamorada", derretida = "cachorro_acompana",
  happy_wiggle = "cachorro_contenta", presume = "cachorro_contenta",
  encontrada = "cachorro_encontrada", juzgando = "cachorro_juzgando",
  negacion = "cachorro_negacion", molesta = "cachorro_molesta", furiosa = "cachorro_molesta",
  curada = "cachorro_curada",
}
local PUPPY_SOUND = {
  come = "cachorro_bebe", baila = "cachorro_baila", musica = "cachorro_baila", mira = "cachorro_observa",
  mira_lluvia = "cachorro_observa", escucha = "cachorro_oye", te_oye = "cachorro_oye",
  susto = {"cachorro_bola_entra", "cachorro_bola_sale"},
  bano = "cachorro_sacude", despierta = "cachorro_despierta", se_duerme_sola = "cachorro_se_duerme",
  acompana = "cachorro_acompana", saluda = "cachorro_saluda", aparece = "cachorro_aparece",
  tarda = "cachorro_tarda", pillada = "cachorro_pillada", investiga = "cachorro_investiga",
  juega_sola = "cachorro_juega", juguetea = "cachorro_juega", juega_juguete = "cachorro_juega",
}
local PUPPY_GESTURES = {
  cachorro_idle = {{"cachorro_parpadea", "cachorro_cola", "cachorro_mira", "cachorro_pata", "cachorro_amasa",
                    "cachorro_lava"}, 30, 75},
  cachorro_sleep = {{"cachorro_sueno"}, 30, 75},
  cachorro_sick_resfriado = {{"cachorro_estornuda"}, 20, 45},
  cachorro_bola = {{"cachorro_bola_oreja", "cachorro_bola_cola", "cachorro_bola_ojo"}, 11, 38},
  cachorro_cojin = {{"cachorro_cojin_espera"}, 23, 56},
}

-- frames that are whole expressions hold this many animation ticks
M.HOLD = {hungry = 3, sick = 4, sick_resfriado = 4, sick_indigestion = 4, sick_estres = 4, critical = 4,
  mimos = 2, enamorada = 2, rueda = 2, derretida = 2, molesta = 2, furiosa = 2, negacion = 2, cansada = 3,
  bola_oreja = 4, bola_cola = 4, bola_ojo = 4, bola_entra = 2, bola_sale = 2,
  esconde_orejas = 2, esconde_cola = 2, esconde_pata = 2, esconde_ojos = 2, juzgando = 2, encontrada = 2,
  ablanda = 2, cojin_despierta = 2, presume = 2, vuelta = 2, cojin_entra = 2, cojin_espera = 3, pedir = 2,
  cachorro_mira = 2, cachorro_yawn = 2, cachorro_mimos = 2, cachorro_despierta = 2, cachorro_pata = 2,
  cachorro_oye = 2, cachorro_cola = 2, cachorro_sacude = 2, cachorro_encontrada = 2, cachorro_saluda = 2,
  cachorro_contenta = 2, cachorro_enamorada = 2, cachorro_negacion = 2, cachorro_juzgando = 2,
  cachorro_aparece = 2, cachorro_pedir = 2, cachorro_pillada = 2, cachorro_observa = 2, cachorro_investiga = 2,
  cachorro_amasa = 2, cachorro_lava = 2, cachorro_molesta = 2, cachorro_juega = 2,
  cachorro_cansada = 3, cachorro_bebe = 3, cachorro_sueno = 3, cachorro_tarda = 3, cachorro_se_duerme = 3,
  cachorro_acompana = 3, cachorro_sick = 4, cachorro_sick_resfriado = 4, cachorro_critical = 4,
  come = 3, se_duerme = 3, despierta = 2, saluda = 2, sacude = 2, cachorro_estornuda = 2, curada = 2,
  cachorro_curada = 2, cachorro_bola_oreja = 4, cachorro_bola_cola = 4, cachorro_bola_ojo = 4,
  cachorro_bola_entra = 2, cachorro_bola_sale = 2, cachorro_cojin_espera = 3, celebra = 3}
for _, h in ipairs(M.HOLIDAYS) do
  M.HOLD["disfraz_" .. h .. "_gesto"], M.HOLD["disfraz_" .. h .. "_parpadea"] = 3, 2
  M.HOLD["disfraz_" .. h .. "_fiesta"] = 3
end
-- one-offs that end on a pose she keeps this many ticks (~10 s), and short ones played twice
M.LINGER = {pedir = 38, cachorro_pedir = 38, cachorro_enamorada = 37, cachorro_acompana = 37, enamorada = 37,
            rueda = 37, derretida = 37, ablanda = 37, encontrada = 37, cansada = 37}
M.REPEAT = {ear_twitch = 2, tail_flick = 2, happy_wiggle = 2, cojin_espera = 2, cachorro_cojin_espera = 2,
            mimos = 2, sancho_mira = 2, sancho_lame = 2}
M.TURNS = {bola = {"bola_entra", "bola_sale"}, cojin = {"cojin_entra"},
           cachorro_bola = {"cachorro_bola_entra", "cachorro_bola_sale"}}

M.FOOD_SET = {Leche = "leche", Pienso = "pienso", Chuches = "chuches", Latas = "latas", Yogurt = "yogurt",
  Sandia = "sandia", Calabaza = "calabaza", Pavo = "pavo", ["Turrón"] = "turron", Gambas = "gambas",
  ["Roscón"] = "roscon", ["Butifarra d'ou"] = "butifarra", Mona = "mona", Coca = "coca",
  ["Pa amb tomàquet"] = "pa_amb_tomaquet"}
for _, f in pairs(M.FOOD_SET) do M.HOLD["come_" .. f] = 3 end

local EVENT_SETS = {
  mira = "vuelta", pajaro = "juzgando", escucha = "ear_twitch", cola = "tail_flick", bosteza = "yawn",
  encuentra_objeto = "presume", ensucia_habitacion = "juzgando", se_revuelca = "rueda",
  se_duerme_sola = "se_duerme", acompana = "derretida", baila = "baila", saluda = "saluda",
  aparece = "saluda", tarda = "happy_wiggle", juguetea = {"vuelta", "happy_wiggle"}, se_acerca = "enamorada",
  ronronea = "mimos", favorita = {"encontrada", "happy_wiggle"}, crece = {"celebra", "presume"},
  juega_sola = {"vuelta", "happy_wiggle"}, investiga = {"ear_twitch", "vuelta"}, trae_algo = "presume",
  pillada = "juzgando", te_mira = "encontrada", te_oye = "ear_twitch", mira_lluvia = {"vuelta", "ear_twitch"},
  juega_juguete = {"vuelta", "happy_wiggle"}, susto = {"bola_entra", "bola_sale"}, musica = "baila",
  ritual = {"happy_wiggle", "rueda", "enamorada"}, luna = {"ear_twitch", "presume"},
  mira_legado = {"ear_twitch", "presume"}, mira_estrella = {"ear_twitch", "presume"}, espera = "pedir",
  capricho = "pedir", llama = "pedir", fiesta = "celebra", gana = "celebra", pierde = "juzgando",
  regana = "juzgando", recuerdo = {"ear_twitch", "happy_wiggle", "cansada"},
}

M.EVENT_SET_NAMES = EVENT_SETS

local MOOD_SET = {calm = "idle", curious = "idle_curious", bored = "idle_bored", grumpy = "idle_grumpy",
  sad = "idle_sad", lonely = "idle_lonely", sleepy = "tired", happy = "happy", affectionate = "happy_love",
  playful = "happy_playful", excited = "happy_excited", proud = "orgullosa", nervous = "bola"}
M.HUNGRY_BELOW = 30
M.ANIM_MS = {idle = 270, jugar = 145, comer = 190, enferma = 190, dormir = 370}

function M.has(set) return SETS[set] == true end

function M.pick(set) -- the nearest drawn prefix (cachorro_happy_love -> cachorro_happy -> cachorro), then idle
  local s = set
  while s do
    if SETS[s] then return s end
    s = s:match("^(.*)_[^_]+$")
  end
  return set:sub(1, 9) == "cachorro_" and "cachorro" or "idle"
end

function M.puppy(ui) return ui.phase == "Cachorro" end

local function puppy_once(name)
  if type(name) == "table" then
    local out = {}
    for _, s in ipairs(name) do
      local n = PUPPY_ONCE[s]
      if n and out[#out] ~= n then out[#out + 1] = n end
    end
    return #out > 0 and out or nil
  end
  return PUPPY_ONCE[name]
end

M.puppy_once = puppy_once

function M.gestures(wanted) -- {one-offs}, min, max, or nil
  if wanted:sub(1, 9) ~= "cachorro_" then return GESTURES[wanted] end
  if PUPPY_GESTURES[wanted] then return PUPPY_GESTURES[wanted] end
  local rule = GESTURES[wanted:sub(10)]
  local names = rule and puppy_once(rule[1])
  return names and {names, rule[2], rule[3]} or nil
end

function M.gesture_ok(name, ui) -- the extra gestures only when her stats call for them
  local ind = ui.indicators or {}
  if name == "vuelta" then return (ind.E or 0) >= 60 end
  if name == "encontrada" then return (ind.F or 0) >= 90 end
  if name == "presume" then return (ind.S or 0) >= 60 end
  return true
end

local function reaction(sound, ui)
  if COSTUME_PARTY[sound] and IS_HOLIDAY[ui.holiday or ""] and not M.puppy(ui) then
    return "disfraz_" .. ui.holiday .. "_fiesta"
  end
  local ind = ui.indicators or {}
  local f, e, t = ind.F or 0, ind.E or 100, ui.stress or 0
  if sound == "mimos" then
    if t > 50 then return "ablanda" end
    if f > 85 then return "rueda" end
    if f > 50 then return e < 40 and "derretida" or "enamorada" end
    return "mimos"
  end
  if sound == "bano" then return {"sacude", "juzgando"} end
  if sound == "despierta" then return {"despierta", "juzgando"} end
  if sound == "vuelve" then return "juzgando" end
  if sound == "come" then
    local verb, food = tostring(ui.last_interaction_action or ""):match("^([^:]+):(.+)$")
    if verb == "Alimentar" and M.FOOD_SET[food] then return "come_" .. M.FOOD_SET[food] end
    return "come"
  end
  if sound == "encontrada" then return "encontrada" end
  if sound == "curar" then return "curada" end
  if sound == "hambre" then return "pedir" end
  if sound == "enfado" then return t > 60 and "furiosa" or "molesta" end
  if sound == "rechazo" then
    local what = tostring(ui.last_interaction_action or "")
    if what:sub(1, 9) == "Alimentar" or what == "Sleep" or (what == "Cuddle" and f > 90) then return "negacion" end
    if what == "Play" and e < 20 then return "cansada" end
    return "molesta"
  end
  if sound == "mira" and e < 60 then return "ear_twitch" end
  if sound == "herencia" then return ui.heirloom end
  return EVENT_SETS[sound]
end

function M.reaction_set(sound, ui) -- a set or {sets} she plays once over any state, or nil
  if M.puppy(ui) then return PUPPY_SOUND[sound] or puppy_once(reaction(sound, ui)) end
  return reaction(sound, ui)
end

local function sprite_set(ui)
  if ui.sleeping or ui.deep_sleep then return "sleep" end
  if ui.hidden then return "hidden" end
  if ui.in_critical then return "critical" end
  if ui.sick then return ui.sick_type and ("sick_" .. ui.sick_type) or "sick" end
  if ui.bird then return "juzgando" end
  if ((ui.indicators or {}).H or 100) < M.HUNGRY_BELOW then return "hungry" end
  if ui.wants_play then return "cojin" end
  if IS_HOLIDAY[ui.holiday or ""] and not M.puppy(ui) then return "disfraz_" .. ui.holiday end
  return MOOD_SET[ui.mood] or "idle"
end

function M.sprite_set(ui) -- the resting set to show
  local name = sprite_set(ui)
  return M.puppy(ui) and ("cachorro_" .. name) or name
end

return M
