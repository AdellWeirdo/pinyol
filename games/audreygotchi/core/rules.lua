-- rules: the game's numbers, a port of audreygotchi/core/rules.py (v11 values unless a comment says otherwise).
-- GameState reads them through its metatable: s.TICK_INTERVAL_SEC.
local R = {}

R.HEAR_COOLDOWN_MS = {voz = 15000, ruido = 20 * 60000, musica = 60000}
R.FRIGHT_STRESS = 5.0
R.HIDE_REST_MS = 20 * 60000
R.SEEK_HINT_MS = 4000
R.SAVE_SCHEMA_VERSION = 17
R.TICK_INTERVAL_SEC = 1
R.QA_TICK_MULTIPLIER = 8

R.PHASE_ORDER = {"Cachorro", "Juvenil", "Adulto", "Senior", "Extra"}
R.PHASE_WINDOWS = {Juvenil = {2, 3}, Adulto = {12, 18}, Senior = {25, 32}}
R.CARE_SHIFT_GOOD = 0.70
R.CARE_SHIFT_BAD = 0.45
R.NAME_PRESETS = {"Audrey", "Luna", "Nala", "Mia", "Kira", "Noa", "Olive", "Moka"}

R.STATUS_PAGES = {"Stats", "Eventos", "Cómo es", "Álbum", "Regalos", "Amigos"}
R.QUIRKS = {"Curiosa", "Dormilona", "Glotona", "Huidiza"}
R.TECH_PAGES = {"Runtime", "Vitals", "Save"}

R.HEAL_OPTIONS = {"Medicina", "Veterinario"}
R.FOOD_OPTIONS = {"Leche", "Pienso", "Chuches", "Latas", "Yogurt", "Sandia"}
R.FEED_EFFECTS = {
  Comida = {H = 25.0, D = 5.0, F = 2.0},
  Snack = {H = 12.0, D = 2.0, F = 6.0},
}
R.FEED_TYPE_OPTIONS = {"Comida", "Snack"}
R.FEED_TYPE_FOODS = {
  Comida = {"Leche", "Pienso", "Latas", "Pavo", "Butifarra d'ou", "Pa amb tomàquet"},
  Snack = {"Chuches", "Yogurt", "Sandia", "Calabaza", "Turrón", "Gambas", "Roscón", "Mona", "Coca"},
}
R.SEASON_FOODS = {halloween = "Calabaza", navidad = "Pavo", caga_tio = "Turrón", nochevieja = "Gambas",
                  reyes = "Roscón", carnaval = "Butifarra d'ou", pascua = "Mona", sant_joan = "Coca",
                  diada = "Pa amb tomàquet"}
R.PLAY_OPTIONS = {"Palito con plumas", "Cepillarla", "Siguela por la casa", "Quita nudos", "Puntero láser",
                  "Trile de cajas", "Simón"}
R.UNLOCK_PHASE = {
  Pienso = "Juvenil", Chuches = "Juvenil", Latas = "Adulto", Yogurt = "Adulto", Sandia = "Adulto",
  ["Siguela por la casa"] = "Juvenil", ["Quita nudos"] = "Juvenil", ["Puntero láser"] = "Juvenil",
  ["Trile de cajas"] = "Adulto", ["Simón"] = "Adulto", Calabaza = "Juvenil", Pavo = "Juvenil",
  ["Turrón"] = "Juvenil", Gambas = "Juvenil", ["Roscón"] = "Juvenil", ["Butifarra d'ou"] = "Juvenil",
  Mona = "Juvenil", Coca = "Juvenil", ["Pa amb tomàquet"] = "Juvenil",
}
R.UNLOCK_DAY = {Cepillarla = 1, ["Quita nudos"] = 6, ["Puntero láser"] = 9, ["Simón"] = 16}
R.AUTO_VET_TRIGGER_SECONDS = 120
R.AUTO_VET_COOLDOWN_SEC = 4 * 3600
R.VET_SOFTLOCK_SEC = 120
R.REACT_SEC = 2.5
R.PET_COOLDOWN_SEC = R.REACT_SEC
R.FEED_COOLDOWN_SEC = R.REACT_SEC
R.PLAY_COOLDOWN_SEC = R.REACT_SEC
R.MEAL_FULL_AT = 90.0
R.GAME_MIN_ENERGY = 12.0
R.HUG_MASH = {4, 20000}
R.GAME_ENERGY = 10.0
R.GAME_ENERGY_HEAVY = 15.0
R.BATH_COOLDOWN_SEC = R.REACT_SEC
R.CRITICAL_MAX = 10.0
R.IDEAL_WEIGHT_RANGES = {
  Cachorro = {2.2, 4.0}, Juvenil = {3.8, 5.8}, Adulto = {4.6, 6.6}, Senior = {4.2, 6.4}, Extra = {4.0, 6.2},
}
R.PHASE_HEIGHT_CM = {Cachorro = 27.0, Juvenil = 30.0, Adulto = 33.0, Senior = 33.0, Extra = 33.0}

R.LIFE_MIN_DAYS = 40
R.LIFE_MAX_DAYS = 55
R.LIFE_EXT_BLOCK = 5
R.EVAL_WINDOW_DAYS = 7
R.EVAL_MIN_AVG_F = 70.0
R.EVAL_MIN_AVG_S = 60.0
R.EVAL_MAX_CRITICAL_MIN = 120
R.EVAL_MAX_VET_VISITS = 2
R.FAREWELL_SUNSET_HOUR = 21
R.NIGHT_HOURS = {22, 8}
R.SCREEN_OFF_SEC = {360, 900, 0}
R.UI_STYLES = {"Galleta", "Malvavisco", "Burbuja", "Clásica"}
R.HIDING_ROOMS = {0, 1, 2, 3, 4}
R.SITTER_SEC = 8 * 3600
R.SITTER_MISSED_F = 5.0
R.SEEK_FOUND_F = 5.0
R.SEEK_FIRST_TRY_F = 8.0
R.MOOD_DWELL_SEC = 600
R.DEEP_SLEEP_MIN_ENERGY = 22.0
R.AUTO_DEEP_SLEEP_LIGHT_OFF_MIN = 4
R.POWER_OFF_MIN_ENERGY = 0.5
R.WAKE_MIN_INTERVAL_SEC = 2
R.AUTO_SLEEP_GRACE_SEC = 30 * 60
R.AUTO_SLEEP_FORCE_ENERGY = 15.0
R.DOZE_ENERGY = 60.0
R.DOZE_ENERGY_HEAVY = 70.0
R.AUTO_WAKE_ENERGY = 95.0
R.MIN_NAP_SEC = 20 * 60
R.MORNING_WAKE = {8, 12}
R.ABSENCE_SEC = 4 * 3600
R.ABSENCE_HUNGER_FLOOR = 10.0
R.ABSENCE_HEALTH_FLOOR = 20.0
R.PERSONALITY_DECAY_PER_MIN = 0.015
R.MINIGAME_SPEED_MIN = 48.0
R.MINIGAME_SPEED_MAX = 88.0

R.CARE_QUALITY_MIN = 0.62
R.CRITICAL_SECONDS_MAX = 12 * 60 * 60
R.MIN_CARE_MINUTES_FOR_JUDGE = 24 * 60

R.BG_FILES = {"bg_living.png", "bg_kitchen.png", "bg_rasca.png", "bg_studio.png", "bg_wc.png"}

return R
