-- test_b: group B (actions, action_runtime, interactions, navigation, asks, bird, save_policy), the asserts of
-- tests/test_rules_v11.py that touch them, on a hand-built state. Other groups' modules are stubbed.
local util = require("core.util")
local rules = require("core.rules")
local Clock = require("core.clock")
local E = Clock.EPOCH -- the clock's seconds at the base day's midnight

local function near(a, b) return math.abs(a - b) < 1e-3 end

-- ---------------------------------------------------------------- stubs (the Python names, minimal behaviour)
ROLL = 1.0          -- personality's random.random()
HOLIDAY = nil       -- weather.holiday()
REJECT_FN = nil     -- GameState.should_reject
CALLS = {}
local function call(name) CALLS[#CALLS + 1] = name end
local function called(name) return util.contains(CALLS, name) end

LOADED["core.weather"] = {PARENT = {caga_tio = "navidad", nochevieja = "navidad", reyes = "navidad"},
                          holiday = function(s, ts) return HOLIDAY end}
local memory = {}
function memory.first(s, what) if s.memory.first[what] == nil then s.memory.first[what] = s.day end end
function memory.remember(s, kind, n) s.memory.day[kind] = util.get(s.memory.day, kind, 0) + (n or 1) end
function memory.interaction(s, action, ok) end
function memory.game_started(s, game) s.memory.games[game] = util.get(s.memory.games, game, 0) + 1 end
function memory.fav_game(s)
  local best, n, ties = nil, -1, 0
  for _, g in ipairs(util.keys(s.memory.games)) do
    local c = s.memory.games[g]
    if c > n then best, n, ties = g, c, 1 elseif c == n then ties = ties + 1 end
  end
  if best == nil or n < 5 or ties > 1 then return nil end
  return best
end
LOADED["core.memory"] = memory
local events = {LOOK_MS = 6000}
function events.later(s, at_ms, sound)
  if #s._later < 4 then
    local l = util.copy(s._later)
    l[#l + 1] = {at_ms, sound}
    s._later = l
  end
end
function events.hour(s)
  local ts = util.get(s, "_sim_ts", 0)
  if ts ~= 0 then return s.clock:localtime(ts).tm_hour end
  return s.clock:local_hour()
end
function events.able(s)
  return s.mode == "main" and not (s.sleeping or s.deep_sleep or s.powered_off or s.hidden or s.sick or s.in_critical
    or s.sitter_until ~= 0 or s.wants_play or s._away)
end
function events.celebrate(s, day, now_ms)
  if day == nil or s.memory.first[day] ~= nil then return end
  memory.first(s, day)
  s.affection = math.min(100.0, s.affection + 10.0)
  s:_emit_sound("fiesta")
end
LOADED["core.events"] = events
local DIVA = {"Ahora no, que estoy divina", "Mmm... no me apetece", "Si me lo pides mejor..."}
LOADED["core.personality"] = {
  DIVA_LINES = DIVA,
  pick_rejection = function(c)
    if #c == 0 then return nil end
    local best = c[1]
    for _, x in ipairs(c) do if x[1] > best[1] then best = x end end
    if best[1] >= 1.0 or ROLL < best[1] then return best[2] end
    return nil
  end,
  sleep_refusal_want = function(s)
    if s.hunger < 50.0 then return "¡Primero la cena!", "Feed" end
    if s.affection < 50.0 then return "¡Antes, mimos!", "Cuddle" end
    return "¿Dormir? ¡A jugar!", "Play"
  end,
}
LOADED["core.v2_gameplay"] = {register_feed_outcome = function() call("feed_outcome") end,
                              cure_illness = function(s, now_ms, reason) s.sick = false call("cure:" .. reason) end}
LOADED["core.litter"] = {open_bath = function(s) s.mode = "action_bath" end, confirm = function() call("litter.confirm") end,
                         move = function(s, step) call("litter.move" .. step) end}
LOADED["core.lifecycle"] = {skip_birth = function(s) call("skip_birth") end, farewell_move = function() call("farewell_move") end}
LOADED["core.scene_grow"] = {can_show = function() return false end, start = function() call("grow") end}
LOADED["core.scene_sancho"] = {confirm = function() call("sancho.confirm") end, intro_next = function() call("intro_next") end,
                               choose = function(s, yes) s.sitter_yes = yes end}

local actions = require("core.actions")
local action_runtime = require("core.action_runtime")
local interactions = require("core.interactions")
local navigation = require("core.navigation")
local asks = require("core.asks")
local bird = require("core.bird")
local save_policy = require("core.save_policy")

-- ---------------------------------------------------------------- a hand-built GameState
local G = setmetatable({}, {__index = rules})
local META = {__index = G}
function G:mark_dirty() self._dirty = true end
function G:_emit_sound(name) self.sound, self.sound_seq = name, self.sound_seq + 1 end
function G:_log_event(txt) self.last_events[#self.last_events + 1] = txt end
function G:_register_interaction(action, ok) interactions.register_interaction(self, action, ok) end
function G:_clamp_stat(v) return util.clamp(v, 0.0, 100.0) end
function G:_pf(key) return util.get(self.personality, key, 0.5) end
function G:compute_mood() end
function G:maybe_purr() call("purr") end
function G:is_night() local h = self.clock:local_hour() return h >= self.NIGHT_HOURS[1] or h < self.NIGHT_HOURS[2] end
function G:active_menu_items() return navigation.active_menu_items(self) end
function G:current_label() return navigation.current_label(self) end
function G:status_page_left() navigation.status_page_left(self) end
function G:_selected_food_name() return actions.selected_food_name(self) end
function G:feed_left() actions.feed_left(self) end
function G:heal_right() actions.heal_right(self) end
function G:should_reject(now_ms, action) if REJECT_FN then return REJECT_FN(self, now_ms, action) end return nil end
function G:enter_action_feed()
  self.mode, self.feed_choice = "action_feed", actions.first_open(self, self.FOOD_OPTIONS, self.feed_choice)
end
function G:exit_action_feed(now_ms, msg) self.mode, self.overlay_text = "main", msg end
function G:enter_action_play()
  self.mode, self.play_choice = "action_play", actions.first_open(self, self.PLAY_OPTIONS, self.play_choice)
end
function G:enter_action_minigame(now_ms, key) self.mode, self.minigame_action = "action_minigame", key end
function G:minigame_confirm() call("minigame_confirm") end
function G:minigame_left() call("minigame_left") end
function G:enter_action_heal() self.mode = "action_heal" end
function G:exit_action_heal(now_ms, msg) self.mode, self.overlay_text = "main", msg end
function G:heal_confirm() call("heal_confirm") end
function G:enter_status() self.mode = "status" end
function G:exit_status() self.mode = "main" end
function G:enter_settings() self.mode = "settings" end
function G:system_choose(now_ms, held) call("system_choose:" .. tostring(held)) end
function G:_act_hug(now_ms) action_runtime.act_hug(self, now_ms) end
function G:_act_bath(now_ms) action_runtime.act_bath(self, now_ms) end
function G:enter_sleep(now_ms, reason) self.sleeping = true call("sleep:" .. reason) end
function G:wake_by_button() self.deep_sleep, self.powered_off = false, false call("wake") end
function G:critical_now() return math.min(self.hunger, self.affection, self.energy, self.health) <= self.CRITICAL_MAX end
function G:_record_vet_visit() call("vet_visit") end
function G:_set_vet_softlock() self.vet_softlock_until_ts = self.clock:now() + self.VET_SOFTLOCK_SEC end
function G:_vet_softlock_active() return self.clock:now() < self.vet_softlock_until_ts end
function G:_vet_softlock_left_sec() return math.max(0, util.int(self.vet_softlock_until_ts - self.clock:now())) end
function G:_call_sancho() self.mode = "sitter_confirm" end
function G:_pick_up() self.sitter_until = 0 self:_emit_sound("vuelve") end
function G:_play_seek() self.hidden = true end
function G:_look(step) call("look" .. step) end
function G:_search_here() call("search_here") end

local function pet(o)
  o = o or {}
  CALLS, ROLL, HOLIDAY, REJECT_FN = {}, 1.0, nil, nil
  local s = setmetatable({

    clock = Clock.start({2026, 10, 15}, (o.hour or 12) * 3600),
    menu_items = {"Feed", "Play", "Cuddle", "Bath", "Sleep", "Sitter", "Album", "Status", "Settings"},
    selected_index = 0, mode = "main", status_page = 0, heal_choice = 0, feed_choice = 0, play_choice = 0,
    guide_seen = false, day = 1, age_days = o.days or 20, phase = o.phase or "Adulto", cycle = 1,
    hunger = 50.0, affection = 50.0, energy = 80.0, health = 90.0, dirt = 60.0, weight_kg = 5.0, stress = 50.0,
    trust_bond = 52.0, excitement = 46.0, confidence = 50.0, personality = {},
    sick = false, in_critical = false, sleeping = false, deep_sleep = false, powered_off = false,
    current_scene = 0, hidden = false, sitter_until = 0, sancho_intro_at = 0, wants_play = false, _away = false,
    ask = nil, ask_yes = true, ask_until = 0, bed_at = 0, tucked_at = 0, bird_until = 0, bird_room = 0, _sim_ts = 0,
    memory = {first = {}, games = {}, animals = {}, day = {}},
    _last_interaction_action = "init", _last_interaction_ok = true, _interactions_total = 0, _rejections_total = 0,
    _action_ok_counts = {}, _action_reject_counts = {}, last_events = {}, overlay_until = 0,
    _reject_cd_until_ms = 0, _hug_cd_until_ms = 0, _feed_cd_until_ms = 0, _play_cd_until_ms = 0, _bath_cd_until_ms = 0,
    _hug_log = {}, favorite_food = "", disliked_food = "", _later = {}, _frame_ms = 0,
    farewell_started = false, farewell_scheduled_day = 0, vet_softlock_until_ts = 0, _critical_streak_sec = 0,
    _low_health_streak_sec = 0, _auto_vet_cd_sec = 0, sound_seq = 0,
  }, META)
  return s
end

local function index_of(s, label) return util.index(s:active_menu_items(), label) end
local function press(s, label, now_ms) s.mode, s.selected_index = "main", index_of(s, label) actions.press_ok(s, now_ms) end
local function feed(s, food, now_ms)
  s.mode, s.feed_choice = "action_feed", util.index(s.FOOD_OPTIONS, food)
  actions.press_ok(s, now_ms or 10000)
end

-- ---------------------------------------------------------------- feeding (ActionEffectsTest, RejectionTest)
for _, food in ipairs({"Pienso", "Latas"}) do -- a meal: H +25, D +5, F +2
  local s = pet() feed(s, food)
  assert(s.hunger == 75.0 and s.dirt == 65.0 and s.affection == 52.0, food)
  assert(s.mode == "main" and s.overlay_text == "¡Mmm, " .. food .. "!" and s.sound == "come")
end
for _, food in ipairs({"Chuches", "Yogurt", "Sandia"}) do -- a snack: H +12, D +2, F +6
  local s = pet() feed(s, food)
  assert(s.hunger == 62.0 and s.dirt == 62.0 and s.affection == 56.0, food)
end
do -- full: a meal is a no every time, a snack always goes down
  local s = pet() s.hunger = 90.0 ROLL = 0.999 feed(s, "Pienso", 1000)
  assert(s.hunger == 90.0 and s.sound == "rechazo" and s.overlay_text == "Paso, estoy llenita" and s.mode == "action_feed")
  assert(s._reject_cd_until_ms == 2200 and s._rejections_total == 1 and s._action_reject_counts["Alimentar"] == 1)
  s = pet() s.hunger = 89.9 ROLL = 0.0 feed(s, "Pienso", 1000) assert(s.hunger > 89.9)
  s = pet() s.hunger = 99.0 ROLL = 0.0 feed(s, "Chuches", 1000) assert(s.hunger == 100.0)
  for _, food in ipairs(rules.FOOD_OPTIONS) do -- hungry, she eats even the food she dislikes
    s = pet() s.hunger, s.disliked_food, ROLL = 30.0, food, 0.0 feed(s, food, 1000)
    assert(s.hunger > 30.0, food)
  end
end
do -- the food she dislikes, refused 30 % when H > 40; her favourite shows (FoodPreferenceTest)
  local function fp(food, hunger, roll)
    local s = pet() s.hunger, s.favorite_food, s.disliked_food = hunger or 50.0, "Latas", "Sandia"
    ROLL = roll or 0.99 feed(s, food, 1000) return s
  end
  assert(fp("Sandia", 50.0, 0.2).sound == "rechazo" and fp("Sandia", 50.0, 0.2).overlay_text == "¡Puaj! Eso no")
  assert(fp("Sandia", 50.0, 0.4).sound ~= "rechazo" and fp("Pienso", 50.0, 0.2).sound ~= "rechazo")
  assert(fp("Sandia", 30.0, 0.0).sound ~= "rechazo")
  local s = fp("Latas") assert(s.sound == "favorita" and s.memory.first.favorite == 1)
  assert(fp("Pienso").sound ~= "favorita" and fp("Pienso").memory.first.favorite == nil)
end
do -- still eating: the press is dropped
  local s = pet() feed(s, "Pienso", 10000) s.hunger = 30.0
  feed(s, "Pienso", 12499) assert(s.hunger == 30.0 and s.mode == "action_feed")
  feed(s, "Pienso", 12500) assert(s.hunger == 55.0)
  assert(s._action_ok_counts["Alimentar"] == 2 and s._interactions_total == 2)
end
do -- unlocks: a puppy only drinks milk, a meal (UnlocksTest)
  local s = pet({phase = "Cachorro", days = 0}) feed(s, "Leche") assert(s.hunger == 75.0 and s.sound == "come")
  s = pet({phase = "Cachorro", days = 0}) feed(s, "Pienso") assert(s.mode == "action_feed" and s.hunger == 50.0)
  s = pet({phase = "Juvenil", days = 0}) s.mode, s.play_choice = "action_play", util.index(rules.PLAY_OPTIONS, "Simón")
  actions.press_ok(s, 10000) assert(s.mode == "action_play")
end

-- ---------------------------------------------------------------- unlocks
do
  local FOODS = {Cachorro = {"Leche"}, Juvenil = {"Leche", "Pienso", "Chuches"}}
  for _, phase in ipairs(rules.PHASE_ORDER) do
    local u = actions.unlocks(pet({phase = phase, days = 30}))
    local open = {}
    for _, f in ipairs(rules.FOOD_OPTIONS) do if u[f] == nil then open[#open + 1] = f end end
    assert(table.concat(open, ",") == table.concat(FOODS[phase] or rules.FOOD_OPTIONS, ","), phase)
  end
  local GAMES = {{"Cachorro", 0, 1}, {"Cachorro", 1, 2}, {"Juvenil", 3, 3}, {"Juvenil", 6, 4}, {"Juvenil", 9, 5},
                 {"Adulto", 13, 6}, {"Adulto", 16, 7}, {"Senior", 26, 7}} -- the first n of PLAY_OPTIONS open
  for _, c in ipairs(GAMES) do
    local u = actions.unlocks(pet({phase = c[1], days = c[2]}))
    for i, g in ipairs(rules.PLAY_OPTIONS) do assert((u[g] == nil) == (i <= c[3]), c[1] .. c[2] .. g) end
  end
  local u = actions.unlocks(pet({phase = "Cachorro", days = 0}))
  assert(u["Pienso"] == "Juvenil" and u["Latas"] == "Adulto")
  assert(u["Quita nudos"] == "Juvenil" and u["Simón"] == "Adulto" and u["Cepillarla"] == "1")
  assert(actions.unlocks(pet({phase = "Juvenil", days = 3}))["Quita nudos"] == "6")
  local s = pet({phase = "Cachorro", days = 1})
  assert(table.concat(actions.new_games(s), ",") == "Palito con plumas,Cepillarla")
  s.memory.games["Palito con plumas"] = 1
  assert(table.concat(actions.new_games(s), ",") == "Cepillarla")
  s = pet({phase = "Cachorro", days = 0}) -- the submenus open on something she has
  assert(actions.first_open(s, rules.FOOD_OPTIONS, util.index(rules.FOOD_OPTIONS, "Latas")) == 0)
  assert(actions.first_open(pet(), rules.FOOD_OPTIONS, 7) == 1 and actions.first_open(pet(), {}, 3) == 0)
  assert(actions.food_kind(s, "Leche") == "Comida" and actions.food_kind(s, "Sandia") == "Snack")
  s.feed_choice = 7 assert(actions.selected_food_name(s) == "Pienso" and actions.selected_feed_type(s) == "Comida")
  s.feed_choice = 0 actions.feed_left(s) assert(s.feed_choice == 5) actions.feed_right(s) assert(s.feed_choice == 0)
  s.heal_choice = 1 actions.heal_right(s) assert(s.heal_choice == 0) actions.heal_left(s) assert(s.heal_choice == 1)
end

-- ---------------------------------------------------------------- cuddles and bath (ActionEffectsTest, SpamTest)
do
  local s = pet() action_runtime.act_hug(s, 10000)
  assert(s.affection == 60.0 and s.stress == 42.0 and s.hunger == 50.0 and s.energy == 80.0 and s.sound == "mimos")
  assert(s.overlay_text == "Prrrr..." and s._hug_cd_until_ms == 12500 and s._last_interaction_action == "Mimos")
  s = pet() s.affection = 86.0 action_runtime.act_hug(s, 10000) assert(s.affection == 88.0)
  s = pet() local health = s.health action_runtime.act_bath(s, 10000)
  assert(s.dirt == 20.0 and s.affection == 52.0 and s.energy == 80.0 and s.health == health and s.sound == "bano")
  assert(s.overlay_text == "¡Splash! Brrr..." and s._bath_cd_until_ms == 12500)
  s = pet() s.sleeping = true action_runtime.act_bath(s, 10000) assert(not s.sleeping)
  s = pet() s.in_critical = true action_runtime.act_bath(s, 10000)
  assert(s.dirt == 60.0 and s.overlay_text == "Baño no, estoy malita" and s._last_interaction_ok == false)
  s = pet() s.dirt = 10.0 action_runtime.act_bath(s, 10000)
  assert(s.dirt == 10.0 and s.overlay_text == "¡Pero si ya brillo!" and s._action_reject_counts["Baño"] == 1)
  -- a press while her reaction plays is dropped, quietly; right after it, it works
  for _, act in ipairs({action_runtime.act_hug, action_runtime.act_bath}) do
    s = pet() s.affection = 50.0
    act(s, 10000)
    local n, stress = s._interactions_total, s.stress
    act(s, 12499) assert(s._interactions_total == n and s.stress == stress)
    act(s, 12500) assert(s._interactions_total == n + 1 and s._last_interaction_ok == true)
  end
  s = pet() s.hunger = 30.0 -- cares one after another cost nothing
  action_runtime.act_bath(s, 10000) action_runtime.act_bath(s, 13000)
  action_runtime.act_hug(s, 16000) action_runtime.act_hug(s, 19000)
  assert(s.dirt == 0.0 and s.stress == 34.0)
  s = pet() -- a mashed cuddle annoys her: the fifth inside 20 s
  for _, t in ipairs({10000, 13000, 16000, 19000}) do action_runtime.act_hug(s, t) end
  local before = s.stress
  action_runtime.act_hug(s, 22000)
  assert(s.stress == before + 5.0 and s.sound == "enfado" and s.overlay_text == "¡Ya vale, humana!" and #s._hug_log == 0)
  action_runtime.act_hug(s, 40000) assert(s.sound == "mimos")
  s = pet() -- spaced cuddles never annoy
  for k = 0, 7 do action_runtime.act_hug(s, 10000 + k * 6000) assert(s.sound == "mimos") end
end

-- ---------------------------------------------------------------- what an interaction leaves (interactions)
do
  local s = pet()
  interactions.register_interaction(s, "Alimentar:Pienso", true)
  assert(s._action_ok_counts["Alimentar"] == 1 and s._last_interaction_action == "Alimentar:Pienso")
  assert(near(s.trust_bond, 52.85) and near(s.excitement, 47.9) and near(s.confidence, 50.6))
  interactions.register_interaction(s, "Play", false)
  assert(s._action_reject_counts["Play"] == 1 and s._rejections_total == 1 and s._last_interaction_ok == false)
  assert(near(s.trust_bond, 51.75) and near(s.excitement, 46.9) and near(s.confidence, 49.95))
  interactions.register_interaction(s, " Juego : x", true) assert(s._action_ok_counts["Juego"] == 1)
  interactions.register_interaction(s, "", true) assert(s._action_ok_counts["Unknown"] == 1)
  assert(s._interactions_total == 4)
end

-- ---------------------------------------------------------------- the vet (VetTest)
do
  local s = pet() s.energy, s.health, s.stress = 50.0, 30.0, 70.0
  interactions.apply_veterinary_care(s, 0, false)
  assert(s.health == 65.0 and s.stress == 40.0 and s.energy == 60.0 and s.affection == 45.0)
  assert(called("vet_visit") and called("cure:veterinario") and s.sound == "curar" and s.memory.first.vet == 1)
  assert(s.vet_softlock_until_ts == 0 and s.last_events[#s.last_events] == "Veterinario")
  s = pet() s.energy, s.health, s.hunger = 50.0, 30.0, 5.0 -- a visit from critical: 2 min of rest
  interactions.apply_veterinary_care(s, 0, false)
  assert(s.in_critical == true and s._critical_streak_sec == 0)
  s.dirt = 60.0
  for _, item in ipairs({"Feed", "Play", "Cuddle", "Bath", "Sleep"}) do
    local f, d = s.affection, s.dirt
    press(s, item, 5000)
    assert(s.mode == "main" and s.affection == f and s.dirt == d and not s.sleeping, item)
    assert(s.overlay_text == "Toca reposo (2m)", s.overlay_text)
  end
  press(s, "Status", 5000) assert(s.mode == "status")
  s.clock:advance(120) press(s, "Feed", 5000) assert(s.mode == "action_feed")
  s = pet() s.hunger, s._away = 5.0, true -- nobody saw it: no rest
  interactions.apply_veterinary_care(s, 0, true)
  s._away = false press(s, "Feed", 5000) assert(s.mode == "action_feed")
  assert(s._auto_vet_cd_sec == 14400 and s.overlay_text == "Fui sola al veterinario")
  assert(util.contains(s.last_events, "Veterinario automático"))
end

-- ---------------------------------------------------------------- refusals (RejectionTest, DivaTest, AutonomyTest)
do
  local s = pet() s.energy = 10.0 -- a refusal is not spam
  REJECT_FN = function() return "No ahora" end
  press(s, "Play", 10000)
  assert(s.stress == 50.0 and s.sound == "rechazo" and s.mode == "main" and s.overlay_text == "No ahora")
  for _, c in ipairs({{"hunger", 40.0, "Feed"}, {"affection", 40.0, "Cuddle"}, {"none", 0, "Play"}}) do
    s = pet() s.hunger, s.affection, s.energy = 70.0, 70.0, 95.0
    if c[1] ~= "none" then s[c[1]] = c[2] end
    REJECT_FN = function(st) return (LOADED["core.personality"].sleep_refusal_want(st)) end
    press(s, "Sleep", 1000)
    assert(not s.sleeping and s:current_label() == c[3], c[3])
  end
  s = pet() -- a refused cuddle: she comes back for it later, once
  REJECT_FN = function() return "No ahora" end
  press(s, "Cuddle", 1000) press(s, "Cuddle", 2000)
  assert(#s._later == 1 and s._later[1][1] == 31000 and s._later[1][2] == "se_acerca")
  REJECT_FN = nil
  press(s, "Cuddle", 11000) assert(#s._later == 0 and s.sound == "mimos")
  s = pet() s.stress = 10.0 -- the diva: scold her
  REJECT_FN = function() return DIVA[1] end
  press(s, "Cuddle", 1000)
  assert(s.overlay_text == DIVA[1] and s.mode == "ask" and s.ask == "diva" and s.ask_until == E + 12 * 3600 + 60)
  navigation.move_right(s) actions.press_ok(s, 2000)
  assert(s.mode == "main" and s.sound == "regana" and s.stress == 14.0 and s.memory.day.whim_no == 1)
  s = pet() REJECT_FN = function() return DIVA[2] end -- spoilt for it
  press(s, "Cuddle", 1000) actions.press_ok(s, 2000)
  assert(s.sound == "mimos" and s.affection == 53.0 and s.memory.day.whim_yes == 1 and s.ask == nil)
  s = pet() REJECT_FN = nil press(s, "Cuddle", 1000) assert(s.mode == "main" and s.sound == "mimos")
  s = pet() s._hug_cd_until_ms = 5000 REJECT_FN = function() call("rolled") return "x" end
  press(s, "Cuddle", 4999) assert(not called("rolled")) -- cooldowns come before the roll
  s._play_cd_until_ms = 5000 press(s, "Play", 4999) assert(not called("rolled") and s.mode == "main")
end

-- ---------------------------------------------------------------- the menu (HealMenuTest, MenuOrderTest...)
do
  local s = pet() s.health = 95.0
  assert(table.concat(s:active_menu_items(), ",") == "Feed,Play,Cuddle,Bath,Sleep,Sitter,Album,Status,Settings")
  s.sick = true local items = s:active_menu_items()
  assert(util.index(items, "Heal") - 1 == util.index(items, "Sleep"))
  s.sick, s.health = false, 40.0 assert(util.contains(s:active_menu_items(), "Heal"))
  s.health = 95.0 -- the cursor keeps its item when Curar comes or goes
  s.selected_index = index_of(s, "Settings") navigation.sync_menu_cursor(s)
  s.sick = true navigation.sync_menu_cursor(s) assert(s:current_label() == "Settings")
  s.sick = false navigation.sync_menu_cursor(s) assert(s:active_menu_items()[s.selected_index + 1] == "Settings")
  s.selected_index = 42 assert(s:current_label() == "Settings")
  s.sick = true press(s, "Heal", 1000) assert(s.mode == "action_heal")
  s = pet() s.sick = true s.memory.animals = {panda = 1} -- the whole menu, in order: the album waits
  assert(table.concat(s:active_menu_items(), ",") == "Feed,Play,Cuddle,Bath,Sleep,Heal,Sitter,Friends,Status,Settings")
  local real = actions.fiesta_item
  actions.fiesta_item = function() return "Pavo" end
  assert(#s:active_menu_items() == 10 and not util.contains(s:active_menu_items(), "Friends"))
  s.memory.animals = {} assert(#s:active_menu_items() == 10 and not util.contains(s:active_menu_items(), "Album"))
  s = pet({phase = "Cachorro"})
  assert(table.concat(util.slice(s:active_menu_items(), 5), ",") == "Fiesta,Album,Status,Settings")
  actions.fiesta_item = real
  s = pet() s.memory.animals = {panda = 1} -- her friends' button, then the album
  items = s:active_menu_items() assert(items[util.index(items, "Friends") + 2] == "Album")
  press(s, "Friends", 1000) assert(s.mode == "status" and rules.STATUS_PAGES[s.status_page + 1] == "Amigos")
  s = pet() press(s, "Album", 1000) assert(s.mode == "status" and rules.STATUS_PAGES[s.status_page + 1] == "Álbum")
  s = pet({phase = "Cachorro"}) assert(not util.contains(s:active_menu_items(), "Sitter"))
  s = pet() s.sancho_intro_at = 100 assert(not util.contains(s:active_menu_items(), "Sitter"))
  s.mode = "sancho_intro" assert(util.contains(s:active_menu_items(), "Sitter"))
  assert(#navigation.active_menu_icons(s) == 9 and navigation.needs_heal(s) == false)
  s.menu_items = {} assert(s:current_label() == "")
end

-- ---------------------------------------------------------------- holidays (HolidayTest)
do
  local s = pet() s.affection = 60.0 HOLIDAY = "halloween"
  assert(actions.fiesta_item(s) == "Calabaza")
  local items = s:active_menu_items() assert(items[util.index(items, "Sitter") + 2] == "Fiesta")
  press(s, "Fiesta", 2000)
  assert(s.hunger == 62.0 and s.affection == 76.0 and s.memory.first.halloween == 1 and s.overlay_text == "¡Mmm, Calabaza!")
  press(s, "Fiesta", 22000) assert(s.hunger == 74.0 and s.affection == 82.0)
  s = pet({phase = "Cachorro"}) HOLIDAY = "halloween" assert(actions.fiesta_item(s) == nil)
  assert(not util.contains(s:active_menu_items(), "Fiesta"))
  HOLIDAY = "sant_jordi" assert(util.contains(s:active_menu_items(), "Fiesta"))
  s = pet() s.affection = 60.0 HOLIDAY = "sant_jordi" press(s, "Fiesta", 2000)
  assert(s.hunger == 50.0 and s.affection == 70.0 and s.memory.first.sant_jordi == 1 and s.overlay_text == "¿Una rosa? ¡Para mí!")
  s = pet() HOLIDAY = "halloween" s._feed_cd_until_ms = 10000 press(s, "Fiesta", 2000) -- still eating: no moment
  assert(s.memory.first.halloween == nil)
  s = pet() HOLIDAY = "navidad" s.hunger = 95.0 press(s, "Fiesta", 2000) -- full, a meal refused: no moment
  assert(s.memory.first.navidad == nil and s.sound == "rechazo")
  s = pet() HOLIDAY = "reyes" assert(actions.fiesta_item(s) == "Roscón")
  HOLIDAY = nil assert(actions.fiesta_item(s) == nil)
end

-- ---------------------------------------------------------------- B and the screens
do
  local s = pet({hour = 23}) s.sleeping = true -- at night B does not wake her (NightRestTest)
  local seq = s.sound_seq
  press(s, "Feed", 1000) assert(s.sleeping and s.sound_seq == seq and string.find(s.overlay_text, "duerme", 1, true))
  s = pet({hour = 3}) s.sleeping, s.deep_sleep = true, true actions.press_ok(s, 1000)
  assert(s.deep_sleep and not called("wake"))
  s = pet({hour = 23}) s.sleeping = true press(s, "Status", 1000) assert(s.mode == "status" and s.sleeping)
  s = pet({hour = 10}) s.sleeping = true press(s, "Feed", 1000)
  assert(not s.sleeping and s.sound == "despierta" and s.overlay_text == "¿Mmm? ¿Ya es de día?" and s.mode == "main")
  s = pet({hour = 10}) s.deep_sleep = true actions.press_ok(s, 1000) assert(called("wake"))
  s = pet() s.mode = "guide" actions.press_ok(s, 1000) assert(s.mode == "main" and s.guide_seen)
  for _, m in ipairs({"birth", "grow"}) do s = pet() s.mode = m actions.press_ok(s, 1000) assert(s.mode == m) end
  s = pet() s.mode = "system" actions.press_ok(s, 1000) assert(called("system_choose:false"))
  s = pet() s.mode = "action_bath" actions.press_ok(s, 1000) assert(called("litter.confirm"))
  s = pet() s.mode = "status" actions.press_ok(s, 1000) assert(s.mode == "main")
  s = pet() s.mode = "sancho_intro" actions.press_ok(s, 1000) assert(called("intro_next"))
  s = pet() s.sitter_until = 5000 actions.press_ok(s, 1000) assert(s.sitter_until == 0 and s.sound == "vuelve")
  s = pet() s.hidden = true actions.press_ok(s, 1000) assert(called("search_here"))
  s = pet() press(s, "Sitter", 1000) assert(s.mode == "sitter_confirm") -- Sancho asks first (SanchoTest)
  navigation.move_left(s) assert(s.sitter_yes == true) navigation.move_right(s) assert(s.sitter_yes == false)
  interactions.cancel_action(s, 1100) assert(s.mode == "main")
  s = pet() s.sitter_until, s.selected_index = 5000, 2 -- away: A and C do nothing
  navigation.move_right(s) navigation.move_left(s) assert(s.selected_index == 2)
  s = pet() navigation.move_left(s) assert(s.selected_index == 0)
  for _ = 1, 12 do navigation.move_right(s) end assert(s.selected_index == 8)
  s = pet() s.mode = "status" navigation.move_left(s) assert(s.status_page == 5)
  s = pet() s.mode = "action_feed" navigation.move_left(s) assert(s.feed_choice == 5)
  s = pet() s.mode = "action_minigame" navigation.move_left(s) assert(called("minigame_left"))
  s = pet() s.mode = "farewell" navigation.move_right(s) assert(called("farewell_move"))
  s = pet() s.mode = "guide" navigation.move_right(s) assert(s.mode == "guide")
  s = pet() s.hidden = true navigation.move_left(s) assert(called("look-1"))
  s = pet() press(s, "Play", 1000) assert(s.mode == "action_play")
  s.play_choice = util.index(rules.PLAY_OPTIONS, "Quita nudos") s.memory.games["Quita nudos"] = 4
  actions.press_ok(s, 2000)
  assert(s.mode == "action_minigame" and s.minigame_action == "Juego:QuitaNudos" and s.sound == "favorita")
  s = pet() s.mode, s.play_choice = "action_play", util.index(rules.PLAY_OPTIONS, "Siguela por la casa")
  actions.press_ok(s, 1000) assert(s.hidden and s.memory.games["Siguela por la casa"] == 1)
  s = pet() s.overlay_text = "x" interactions.cancel_action(s, 1000) assert(s.overlay_text == nil and s.overlay_until == 0)
  s = pet() s.mode = "guide" interactions.cancel_action(s, 1000) assert(s.mode == "main" and s.guide_seen)
  s = pet() s.mode = "action_feed" interactions.cancel_action(s, 1000)
  assert(s.mode == "main" and s.overlay_text == "Vale, otro rato")
  s = pet() s.mode = "system" interactions.cancel_action(s, 1000) assert(called("system_choose:true"))
  s = pet() s.mode = "birth" interactions.cancel_action(s, 1000) assert(called("skip_birth"))
  s = pet() s.mode = "farewell" interactions.cancel_action(s, 1000) assert(s.mode == "farewell")
end

-- ---------------------------------------------------------------- what she asks (WhimTest, GoodnightTest)
do
  local function whim()
    local s = pet() asks.start(s, "whim", asks.WHIM_WAIT_SEC)
    assert(s.mode == "ask" and s.ask == "whim" and s.ask_yes == true and s.ask_until == E + 12 * 3600 + 900)
    return s
  end
  local s = whim() actions.press_ok(s, 2000) -- Mimos: F +3, it spoils her
  assert(s.mode == "main" and s.affection == 53.0 and s.memory.day.whim_yes == 1 and s.memory.day.whim_no == nil)
  for _, answer in ipairs({"no", "back", "timeout"}) do -- No, back or 15 min: it toughens her
    s = whim()
    if answer == "no" then navigation.move_right(s) actions.press_ok(s, 2000)
    elseif answer == "back" then interactions.cancel_action(s, 2000)
    else s.clock:advance(899) asks.minute(s, 2000) assert(s.mode == "ask") s.clock:advance(1) asks.minute(s, 2000) end
    assert(s.mode == "main" and s.affection == 50.0 and s.memory.day.whim_no == 1 and s.sound == "cola", answer)
  end
  s = pet({hour = 21}) s.dirt = 10.0 asks.minute(s, 1000) assert(s.mode == "main") -- bedtime: once a night
  s.clock:advance(3600) asks.minute(s, 1000)
  assert(s.mode == "ask" and s.ask == "bed" and s.ask_yes and s.sound == "bosteza" and s.bed_at == E + 22 * 3600)
  interactions.cancel_action(s, 1000) assert(s.mode == "main" and not s.sleeping and s.affection == 50.0)
  s.clock:advance(3600) asks.minute(s, 1000) assert(s.mode == "main")
  s = pet({hour = 22}) asks.minute(s, 1000) actions.press_ok(s, 1000) -- lights off: F +5, asleep till morning
  assert(s.mode == "main" and s.sleeping and s.affection == 55.0 and s.tucked_at == E + 22 * 3600 and called("sleep:buenas_noches"))
  assert(s.overlay_text == "Buenas noches" and asks.tucked_in(s))
  s.clock:advance(5 * 3600) assert(asks.tucked_in(s)) -- 03:00
  s.clock:advance(5 * 3600) assert(not asks.tucked_in(s)) -- 08:00
  s = pet({hour = 22}) asks.minute(s, 1000) s.clock:advance(30 * 60) asks.minute(s, 1000) -- timeout: nothing
  assert(s.mode == "main" and not s.sleeping and s.affection == 50.0)
  s = pet({hour = 22}) s.sleeping = true asks.minute(s, 1000) assert(s.mode == "main") -- not able: no question
  s = pet({hour = 23}) s._sim_ts = E + 21 * 3600 + 58 * 60 asks.minute(s, 1000) -- the simulated hour, not the wall's
  assert(s.mode == "main" and asks.now(s) == s._sim_ts)
  s._sim_ts = E + 22 * 3600 asks.minute(s, 1000) assert(s.mode == "ask" and s.bed_at == E + 22 * 3600)
  s = pet() s.ask = "diva" s.mode = "ask" asks.choose(s, false) assert(s.ask_yes == false)
end

-- ---------------------------------------------------------------- the sparrow (BirdTest)
do
  local s = pet({hour = 10}) s.stress = 40.0
  assert(bird.window_here(s)) s.current_scene = 1 assert(not bird.window_here(s)) s.current_scene = 0
  bird.land(s, 1000)
  assert(bird.here(s) and s.stress == 44.0 and s.bird_until == 26000 and s.bird_room == 0)
  local stress = s.stress
  press(s, "Feed", 2000) -- B shoos it and does nothing else
  assert(s.mode == "main" and not bird.here(s) and s.sound == "pajaro_vuela" and s.stress < stress)
  assert(s.affection > 50.0 and s.overlay_text == "¡Y no vuelvas!")
  s = pet() bird.land(s, 1000) bird.update(s, 1000 + bird.BIRD_MS - 1) assert(bird.here(s))
  bird.update(s, 1000 + bird.BIRD_MS) assert(not bird.here(s) and s.sound == "pajaro_vuela")
  s = pet() bird.land(s, 50000) s.current_scene = 3 assert(not bird.here(s))
  local seq = s.sound_seq bird.update(s, 50001) assert(s.bird_until == 0 and s.sound_seq == seq)
  s = pet() bird.land(s, 2 ^ 30 // 1) bird.update(s, 500) assert(s.bird_until == 0) -- a wrapped tick
  s = pet() s.bird_until = nil assert(not bird.here(s)) bird.update(s, 0)
end

-- ---------------------------------------------------------------- when to save (SavePolicyTest)
do
  local function saved_at(t) local s = pet() save_policy.save_due(s, t) save_policy.saved(s, t) return s end
  assert(save_policy.save_due(pet(), 5000) == false)
  local s = saved_at(1000) assert(not save_policy.save_due(s, 120999) and save_policy.save_due(s, 121000))
  s = saved_at(1000) s._frame_ms = 2000 save_policy.note_action(s)
  s._frame_ms = 10000 save_policy.note_action(s) -- joins the save already waiting
  assert(not save_policy.save_due(s, 16999) and save_policy.save_due(s, 17000))
  s = saved_at(1000) s.sleeping = true assert(save_policy.save_due(s, 2000))
  save_policy.saved(s, 2000) assert(not save_policy.save_due(s, 3000))
  s.sleeping = false assert(save_policy.save_due(s, 3000))
  s = saved_at(1000) s.farewell_scheduled_day = 40 assert(save_policy.save_due(s, 2000))
  s = saved_at(1000) s.cycle = s.cycle + 1 assert(save_policy.save_due(s, 2000))
  s = saved_at(1000000) assert(save_policy.save_due(s, 500))
  s = pet() s._frame_ms = 7000 save_policy.request_now(s)
  assert(s._save_group_ms == 7000 and s._save_last_ms == 7000 and save_policy.save_due(s, 7000))
  save_policy.saved(s, 8000) assert(s._save_group_ms == nil and s._save_marks[3] == 1)
end

print("ok b")
