-- test_a: group A's modules (personality, mood, memory, care, needs, litter, stickers, power_state, hearing),
-- the rules the Python tests pin (test_personality_reject.py, test_rules_v11.py, test_core_flows.py,
-- test_v2_gameplay.py), on a hand-made state.

-- stubs first: the weather outside (fixed by the test) and the director's hour
local WEATHER = {kind = nil, sunny = false, cold = false, hot = false}
LOADED["core.weather"] = {
  HOLIDAYS = {"navidad", "halloween", "sant_jordi", "caga_tio", "nochevieja", "reyes", "carnaval", "pascua",
              "sant_joan", "diada"},
  kind = function(_s) return WEATHER.kind end,
  sunny = function(_s) return WEATHER.sunny end,
  cold = function(_s) return WEATHER.cold end,
  hot = function(_s) return WEATHER.hot end,
}
local HOUR = 12
LOADED["core.events"] = {hour = function(_s) return HOUR end}

local rules = require("core.rules")
local Clock = require("core.clock")
local util = require("core.util")
local personality = require("core.personality")
local mood = require("core.mood")
local memory = require("core.memory")
local care = require("core.care")
local needs = require("core.needs")
local litter = require("core.litter")
local stickers = require("core.stickers")
local power_state = require("core.power_state")
local hearing = require("core.hearing")

local function near(a, b, eps) return math.abs(a - b) <= (eps or 1e-4) end

-- random.random patched, as the Python tests do: a value, or a list of values in turn
local real_random = math.random
local function with_random(v, f)
  local seq = type(v) == "table" and v or nil
  local i = 0
  math.random = function(...)
    if select("#", ...) > 0 then return real_random(...) end
    if seq then i = i + 1 return seq[i] end
    return v
  end
  local ok, r = pcall(f)
  math.random = real_random
  assert(ok, r)
  return r
end

-- a GameState with only what group A touches; its methods as state.py's
local G = {}
function G:_pf(key, default) return personality.pf(self, key, default or 0.5) end
function G:_clamp_stat(v, lo, hi) return personality.clamp_stat(self, v, lo or 0.0, hi or 100.0) end
function G:_emit_sound(name) self.sound = name self.sound_seq = self.sound_seq + 1 end
function G:_log_event(txt) self.last_events[#self.last_events + 1] = txt end
function G:mark_dirty() self._dirty = true end
function G:is_night() return self.night end
function G:compute_mood() mood.compute_mood(self) end
function G:active_menu_items() return self.menu end
function G:_act_bath(now_ms) self.bathed_at = now_ms self.dirt = self.dirt - 20.0 end
function G:_register_interaction(action, ok)
  self.interactions[#self.interactions + 1] = {action, ok}
  memory.interaction(self, action, ok)
end
function G:_may_hide(_now_ms) return self.may_hide end
function G:_hide(_now_ms) self.hidden, self.hidden_scene = true, 3 end
function G:_can_wake_now() return power_state.can_wake_now(self) end
function G:enter_sleep(now_ms, reason, show_overlay)
  if show_overlay == nil then show_overlay = true end
  return power_state.enter_sleep(self, now_ms, reason or "manual", show_overlay)
end
function G:wake_by_button(now_ms, source) return power_state.wake_by_button(self, now_ms, source or "botón") end
function G:should_reject(now_ms, action) return personality.should_reject(self, now_ms, action) end
setmetatable(G, {__index = rules})

local function pet(over)
  local s = {
    clock = Clock.new({2026, 6, 15}, 12 * 3600),
    mode = "main", overlay_text = nil, overlay_until = 0, _dirty = false,
    hunger = 80.0, affection = 70.0, energy = 80.0, health = 90.0, dirt = 10.0,
    stress = 24.0, excitement = 46.0, confidence = 50.0, trust_bond = 52.0,
    phase = "Cachorro", sick = false, in_critical = false, sleeping = false, deep_sleep = false,
    powered_off = false, hidden = false, hidden_scene = -1, light_on = true,
    quirks = {}, personality = {}, memory = memory.fresh(),
    day = 1, age_days = 0, mood = "calm", mood_icon = "", _mood_since = -1000000000, _sim_ts = 0,
    _complain_cd_until_ms = 0, _purr_cd_until_ms = 0, _reject_cd_until_ms = 0, _interactions_total = 0,
    sitter_until = 0, wants_play = false, litter = 0, _litter_sec = 0, bath_choice = 0,
    new_sticker = nil, new_sticker_seq = 0, scenarios = {"Salón", "Cocina", "Rascador", "Estudio", "WC"},
    current_scene = 0, stars = 0, legacy = {}, _nap_sec = 0, _awake_sec = 1800, _last_wake_ts = 0.0,
    mic_on = true, _frame_ms = 0, _heard_until = {}, _was_away = false, _input_pending_ts = 0.0,
    seek_hint_until = 0, _hide_cd_until_ms = 0,
    -- the test's own: what was heard, logged, registered; the hour; the menu; scene_search's answer
    sound = nil, sound_seq = 0, last_events = {}, interactions = {}, night = false, may_hide = true,
    menu = {"Feed", "Play", "Cuddle", "Bath", "Sleep", "Sitter", "Album", "Status", "Settings"},
  }
  for k, v in pairs(over or {}) do s[k] = v end
  return setmetatable(s, {__index = G})
end

local function logged(s, txt) return util.contains(s.last_events, txt) end

-- ================================================================== personality: refusals (D-16, v8.1 §5.4)
do
  -- test_personality_reject.py
  local s = pet({energy = 10.0, stress = 10.0})
  assert(with_random(0.0, function() return s:should_reject(1000, "Juego") end) == "Estoy sin pilas")
  assert(s._reject_cd_until_ms >= 1000 + 1200)
  s = pet({affection = 95.0, stress = 10.0})
  assert(with_random(0.0, function() return s:should_reject(3000, "Mimos") end) == "Voy servida de mimos")
  assert(s._reject_cd_until_ms >= 3000 + 1200)
  -- several conditions: one roll against the highest (rolling each in turn, 0.99 then 0.0, would refuse)
  s = pet({energy = 15.0, stress = 95.0})
  assert(with_random({0.99, 0.0}, function() return s:should_reject(5000, "Play") end) == nil)
  s = pet({energy = 15.0, stress = 95.0})
  assert(with_random(0.0, function() return s:should_reject(6000, "Play") end) == "Estoy sin pilas") -- 50 % beats 40 %
  -- the cooldown suppresses a recheck
  s = pet({energy = 5.0, _reject_cd_until_ms = 4500})
  assert(with_random(0.0, function() return s:should_reject(4000, "Juego") end) == nil)
  -- the Play label, spent
  s = pet({energy = 8.0})
  local msg = with_random(0.0, function() return s:should_reject(1000, "Play") end)
  assert(type(msg) == "string" and #msg > 0)
  -- spaces and case
  s = pet({energy = 5.0})
  assert(with_random(0.99, function() return s:should_reject(1000, "  PLAY ") end) == "Estoy sin pilas")
  s = pet({energy = 5.0})
  assert(with_random(0.0, function() return s:should_reject(1000, nil) end) == nil)
end

do
  -- RejectionTest: the fixed odds (refused just under p, not at p)
  local function refuses(action, roll, stats)
    local s = pet({phase = "Adulto", age_days = 20, hunger = 50.0, affection = 50.0, energy = 80.0, stress = 20.0})
    for k, v in pairs(stats or {}) do s[k] = v end
    return with_random(roll, function() return s:should_reject(1000, action) end) ~= nil
  end
  local function odds(action, p, stats)
    assert(refuses(action, p - 0.001, stats), action)
    assert(not refuses(action, p, stats), action)
  end
  odds("Play", 0.50, {energy = 19.0})
  odds("Play", 0.40, {stress = 71.0})
  odds("Cuddle", 0.50, {affection = 91.0})
  odds("Cuddle", 0.30, {stress = 81.0})
  odds("Sleep", 0.50, {energy = 81.0})
  odds("dormir", 0.50, {energy = 81.0})
  assert(not refuses("Sleep", 0.0, {energy = 80.0}))
  assert(refuses("Play", 0.999, {energy = 11.9})) -- below GAME_MIN_ENERGY: a no, every time
  for _, action in ipairs({"Play", "Cuddle"}) do assert(not refuses(action, 0.0)) end
  for _, action in ipairs({"Feed", "Bath"}) do assert(not refuses(action, 0.0, {stress = 100.0})) end
  assert(not refuses("Play", 0.0, {weight_kg = 9.5}))
end

do
  -- sent to bed with energy to spare: she says what she wants
  local s = pet({hunger = 40.0, affection = 70.0, energy = 95.0})
  local w = personality.sleep_refusal_want(s)
  assert(w[1] == "¡Primero la cena!" and w[2] == "Feed")
  assert(string.find(with_random(0.0, function() return s:should_reject(1000, "Sleep") end):lower(), "cena", 1, true))
  s = pet({hunger = 70.0, affection = 40.0, energy = 95.0})
  w = personality.sleep_refusal_want(s)
  assert(w[1] == "¡Antes, mimos!" and w[2] == "Cuddle")
  s = pet({hunger = 70.0, affection = 70.0, energy = 95.0})
  w = personality.sleep_refusal_want(s)
  assert(w[1] == "¿Dormir? ¡A jugar!" and w[2] == "Play")
  assert(string.find(w[1]:lower(), "jugar", 1, true))
end

do
  -- pick_rejection: none, a sure no, the first of the highest
  assert(personality.pick_rejection({}) == nil)
  assert(with_random(0.999, function() return personality.pick_rejection({{0.3, "a"}, {1.0, "b"}}) end) == "b")
  assert(with_random(0.0, function() return personality.pick_rejection({{0.5, "a"}, {0.5, "b"}, {0.2, "c"}}) end)
         == "a")
  assert(with_random(0.6, function() return personality.pick_rejection({{0.5, "a"}}) end) == nil)
end

do
  -- DivaTest: a spoilt cat plays the diva; an independent one never
  local function diva(pampered, roll, total)
    local s = pet({phase = "Adulto", energy = 80.0, stress = 10.0, affection = 50.0,
                   personality = {pampered = pampered}, _interactions_total = total or 0})
    return with_random(roll, function() return s:should_reject(1000, "Cuddle") end)
  end
  assert(util.contains(personality.DIVA_LINES, diva(1.0, 0.0)))
  assert(diva(1.0, 0.0, 4) == personality.DIVA_LINES[2]) -- int(_interactions_total) % 3
  assert(diva(1.0, 0.19) ~= nil and diva(1.0, 0.21) == nil) -- 0.4 * (1.0 - 0.5)
  assert(diva(0.8, 0.119) ~= nil and diva(0.8, 0.121) == nil) -- at its most spoilt (0.8), 12 %
  assert(diva(0.3, 0.0) == nil)
  assert(diva(0.5, 0.0) == nil) -- born neutral: never
  local s = pet({personality = {pampered = 1.0}})
  assert(with_random(0.0, function() return s:should_reject(1000, "Feed") end) == nil) -- only play and cuddles
end

-- ================================================================== personality: complaints, purrs, the tail
do
  -- RejectionSoundTest.test_complaints: each complaint's sound
  for _, case in ipairs({{{sick = true}, "enferma", "Miau... estoy malita"},
                         {{in_critical = true, hunger = 5.0}, "alerta", "¡MIAU! ¡Ayúdame!"},
                         {{hunger = 12.0}, "hambre", "¡Miaaau! ¡Hambre!"}}) do
    local s = pet(case[1])
    with_random(0.0, function() personality.maybe_complain(s, 10000) end)
    assert(s.sound == case[2], case[2])
    assert(s.overlay_text == case[3] and s.overlay_until == 10900 and s._complain_cd_until_ms == 22000)
    assert(logged(s, case[3]) and s._dirty)
  end
  -- tired: written, not heard
  local s = pet({energy = 12.0})
  with_random(0.0, function() personality.maybe_complain(s, 10000) end)
  assert(s.sound == nil and s.overlay_text == "Zzz... qué sueño")
  -- the odds: sick, p = 0.10 + 0.04 * sensitivity
  s = pet({sick = true, personality = {sensitivity = 0.5}})
  with_random(0.121, function() personality.maybe_complain(s, 10000) end)
  assert(s.sound == nil)
  with_random(0.119, function() personality.maybe_complain(s, 10000) end)
  assert(s.sound == "enferma")
  -- never over what is on screen, nor in a menu, nor in her cooldown; nothing to say, nothing said
  s = pet({sick = true, overlay_text = "hola", overlay_until = 20000})
  with_random(0.0, function() personality.maybe_complain(s, 10000) end)
  assert(s.sound == nil)
  s = pet({sick = true, overlay_text = "", overlay_until = 20000}) -- "" is nothing on screen
  with_random(0.0, function() personality.maybe_complain(s, 10000) end)
  assert(s.sound == "enferma")
  s = pet({sick = true, mode = "status"})
  with_random(0.0, function() personality.maybe_complain(s, 10000) end)
  assert(s.sound == nil)
  s = pet({sick = true, _complain_cd_until_ms = 10001})
  with_random(0.0, function() personality.maybe_complain(s, 10000) end)
  assert(s.sound == nil)
  s = pet()
  with_random(0.0, function() personality.maybe_complain(s, 10000) end)
  assert(s.sound == nil and s.overlay_text == nil)
end

do
  -- test_purring_is_shown_not_written
  local s = pet({mood = "affectionate"})
  with_random(0.0, function() personality.maybe_purr(s, 1000) end)
  assert(s.overlay_text == nil and s.sound == "ronronea" and #s.last_events == 0)
  assert(s._purr_cd_until_ms == 1000 + personality.PURR_CD_MS and personality.PURR_CD_MS == 180000)
  local seq = s.sound_seq
  with_random(0.0, function() personality.maybe_purr(s, 2000) end) -- in her cooldown
  assert(s.sound_seq == seq)
  -- purr_p = 0.02 + 0.08 * trust/100 + 0.04 * sociability = 0.0816 here
  s = pet({mood = "affectionate"})
  with_random(0.082, function() personality.maybe_purr(s, 1000) end)
  assert(s.sound == nil)
  s = pet({mood = "calm"})
  with_random(0.0, function() personality.maybe_purr(s, 1000) end)
  assert(s.sound == nil)
end

do
  -- test_tail_pose_rules
  local s = pet({affection = 80.0, energy = 70.0, hunger = 70.0, health = 80.0})
  assert(personality.tail_pose(s) == "up")
  s.energy = 10.0
  assert(personality.tail_pose(s) == "down")
  s.energy, s.hunger, s.health, s.affection = 60.0, 60.0, 60.0, 50.0
  assert(personality.tail_pose(s) == "neutral")
  s.energy, s.affection, s.powered_off = 10.0, 80.0, true
  assert(personality.tail_pose(s) == "neutral")
  assert(personality.tail_pose(pet({sick = true, affection = 90.0})) == "down")
end

-- ================================================================== personality: who she is
do
  -- test_born_neutral_but_for_her_quirks
  math.randomseed(1)
  for _ = 1, 20 do
    local quirks = util.sample(rules.QUIRKS, util.choice({2, 3}))
    local p = personality.generate_personality(pet({quirks = quirks}))
    for _, axis in ipairs(personality.AXES) do
      assert(0.4 - 1e-6 <= p[axis] and p[axis] <= 0.6 + 1e-6, axis)
    end
    assert(p.resilience ~= nil and p.sensitivity ~= nil)
    assert(p.resilience >= 0.0 and p.resilience <= 1.0)
  end
  local p = personality.generate_personality(pet({quirks = {"Glotona", "Huidiza"}}))
  assert(near(p.food, 0.6) and near(p.sociability, 0.4) and near(p.affection, 0.45))
  assert(p.resilience >= 0.34 - 1e-6 and p.resilience <= 0.5 + 1e-6)
  assert(p.sensitivity >= 0.56 - 1e-6 and p.sensitivity <= 0.72 + 1e-6)
  p = personality.generate_personality(pet({quirks = {"Dormilona"}}))
  assert(near(p.activity, 0.4) and near(p.rhythm, 0.45) and near(p.curiosity, 0.5))
end

do
  -- test_status_says_a_sentence: the axis furthest out, never a number
  local s = pet({personality = {curiosity = 0.85}})
  assert(personality.about(s) == "curiosity_hi")
  s.personality = {sociability = 0.2, curiosity = 0.7}
  assert(personality.about(s) == "sociability_lo")
  s.personality = {}
  assert(personality.about(s) == nil) -- nothing stands out yet
  -- pf: the default, a saved string, junk
  assert(personality.pf(pet({personality = {food = "0.7"}}), "food") == 0.7)
  assert(personality.pf(pet({personality = {food = "x"}}), "food", 0.3) == 0.3)
  assert(personality.pf(pet({personality = 5}), "food") == 0.5)
  assert(personality.clamp_stat(nil, 120) == 100.0 and personality.clamp_stat(nil, -3) == 0.0)
  assert(personality.clamp_stat(nil, 5, 10.0, 20.0) == 10.0)
end

do
  -- personality_drift_minute: stress by the hour, the bond, the baselines
  local s = pet()
  personality.personality_drift_minute(s)
  assert(near(s.stress, 24.0 - 2.0 / 60.0))
  local care_proxy = (70.0 * 0.35 + 90.0 * 0.35 + 80.0 * 0.30) / 100.0
  assert(near(s.trust_bond, 52.0 + (care_proxy - 0.55) * 1.1 - ((s.stress - 50.0) / 100.0) * 0.8))
  assert(near(s.excitement, 46.0 + 0.015 * 4.0) and near(s.confidence, 50.0))
  s = pet({sleeping = true})
  personality.personality_drift_minute(s)
  assert(near(s.stress, 24.0 - 0.1))
  s = pet({in_critical = true})
  personality.personality_drift_minute(s)
  assert(near(s.stress, 24.0 + 4.0 / 60.0))
  s = pet({stress = 0.0})
  personality.personality_drift_minute(s)
  assert(s.stress == 0.0)
end

-- ================================================================== mood (Bible §3-§4)
local BIBLE = {"happy", "calm", "curious", "playful", "affectionate", "bored", "sleepy", "grumpy",
               "nervous", "sad", "sick", "proud", "excited", "lonely"}

local function moody(kw)
  local s = pet({hunger = 70.0, affection = 60.0, energy = 70.0, health = 90.0, stress = 20.0, dirt = 20.0,
                 excitement = 50.0, confidence = 50.0, trust_bond = 52.0, mood = "calm", _mood_since = -1000000000})
  for k, v in pairs(kw or {}) do s[k] = v end
  s:compute_mood()
  return s
end

do
  WEATHER.kind, WEATHER.sunny, WEATHER.cold, WEATHER.hot = nil, false, false, false
  assert(moody({hunger = 10.0}).mood == "grumpy")
  assert(moody({stress = 85.0}).mood == "nervous")
  assert(moody({affection = 100.0, personality = {affection = 0.9}}).mood == "affectionate")
  assert(moody({energy = 12.0}).mood == "sleepy")
  assert(moody({affection = 20.0, health = 40.0}).mood == "sad")
  assert(moody({trust_bond = 90.0, confidence = 90.0}).mood == "proud")
  assert(moody({excitement = 95.0}).mood == "excited")
  -- the hard states come first
  for _, case in ipairs({{"powered_off", "off"}, {"deep_sleep", "deep_sleep"}, {"sleeping", "sleepy"},
                         {"sick", "sick"}, {"in_critical", "critical"}}) do
    assert(moody({[case[1]] = true}).mood == case[2], case[1])
  end
  assert(moody({sick = true}).mood_icon == "") -- the console's text has no emoji
  -- every awake mood is a Bible mood, and many come
  local seen, n = {}, 0
  for _, h in ipairs({10, 60, 95}) do for _, f in ipairs({15, 60, 95}) do for _, e in ipairs({10, 60, 95}) do
    for _, t in ipairs({20, 85}) do for _, x in ipairs({30, 95}) do for _, b in ipairs({52, 95}) do
      local m = moody({hunger = h + 0.0, affection = f + 0.0, energy = e + 0.0, stress = t + 0.0,
                       excitement = x + 0.0, trust_bond = b + 0.0, confidence = b + 0.0}).mood
      assert(util.contains(BIBLE, m), m)
      if not seen[m] then seen[m] = true n = n + 1 end
    end end end
  end end end
  assert(n >= 8, n)
end

do
  -- an awake mood holds a while, unless another beats it clearly
  local s = moody({affection = 100.0, personality = {affection = 0.9}})
  assert(s.mood == "affectionate" and s._mood_since == s.clock:now())
  s.affection = 85.0 -- a little less loved: still affectionate for now
  s:compute_mood()
  assert(s.mood == "affectionate")
  s.clock:advance(mood.MOOD_DWELL_SEC + 1)
  s:compute_mood()
  assert(s.mood ~= "affectionate")
  s = moody({affection = 88.0})
  s.hunger = 5.0 -- starving: grumpy at once
  s:compute_mood()
  assert(s.mood == "grumpy")
  -- a clock set back does not freeze her mood
  s = moody({affection = 88.0})
  s._mood_since = s.clock:now() + 3600
  s.affection = 78.0
  s:compute_mood()
  assert(s.mood ~= "affectionate")
  -- the mood of the day is steady, and is the day's
  assert(moody().mood == moody().mood)
  assert(near(mood._day_chance(1, 0), 0.040512048, 1e-6))
  assert(near(mood._day_chance(1, 5), 0.135843373, 1e-6))
  assert(near(mood._day_chance(7, 12), 0.113855421, 1e-6))
  -- in catch-up, the simulated second is her clock
  s = moody({_sim_ts = 5000, hunger = 5.0})
  assert(s.mood == "grumpy" and s._mood_since == 5000)
end

do
  -- yesterday colours her mood; a senior is calmer; the weather outside
  local s = pet({phase = "Adulto", hunger = 70.0, affection = 60.0, energy = 70.0, health = 90.0, stress = 20.0,
                 dirt = 20.0})
  local calm = mood.scores(s)
  s.memory["yesterday"]["play"] = 4
  assert(mood.scores(s)["playful"] > calm["playful"])
  s.memory["yesterday"]["alone_min"] = 600
  assert(mood.scores(s)["lonely"] > calm["lonely"])
  assert(mood.scores(pet({phase = "Senior"}))["calm"] > mood.scores(pet({phase = "Adulto"}))["calm"])
  assert(mood.scores(pet({phase = "Cachorro"}))["curious"] > mood.scores(pet({phase = "Adulto"}))["curious"])
  local before = mood.scores(s)
  WEATHER.kind = "storm"
  assert(near(mood.scores(s)["nervous"], before["nervous"] + 0.2))
  WEATHER.kind = "rain"
  assert(near(mood.scores(s)["calm"], before["calm"] + 0.06) and near(mood.scores(s)["sleepy"], before["sleepy"] + 0.05))
  WEATHER.kind, WEATHER.cold = "cloudy", true
  assert(mood.scores(s)["sleepy"] > before["sleepy"])
  assert(near(mood.scores(s)["affectionate"], before["affectionate"] + 0.04))
  WEATHER.cold, WEATHER.hot = false, true
  assert(near(mood.scores(s)["sleepy"], before["sleepy"] + 0.08))
  WEATHER.hot, WEATHER.sunny = false, true
  assert(near(mood.scores(s)["happy"], before["happy"] + 0.05))
  WEATHER.kind, WEATHER.sunny = nil, false
  s.night = true
  assert(near(mood.scores(s)["sleepy"], before["sleepy"] + 0.15))
end

-- ================================================================== memory (Bible §5, §8-§9)
local AXES = personality.AXES

local function neutral()
  local p = {}
  for _, a in ipairs(AXES) do p[a] = 0.5 end
  p.resilience, p.sensitivity = 0.5, 0.5
  return p
end

local function a_day(s, tally)
  for k, v in pairs(tally or {}) do s.memory["day"][k] = v end
  local before = util.copy(s.personality)
  memory.new_day(s)
  local d = {}
  for _, k in ipairs(AXES) do d[k] = s.personality[k] - before[k] end
  return d
end

do
  local m = memory.fresh()
  assert(m.at_day == 1 and #m.hours == 24 and #m.day_hours == 24 and m.toy == nil and m.day.whim_no == 0)
  assert(util.len(m.day) == #memory.TALLY)

  local d = a_day(pet({personality = neutral()}), {cuddle = 4, play = 1})
  assert(d.sociability > 0 and d.affection > 0)
  local s = pet({personality = neutral()})
  s.personality.activity = 0.4
  assert(a_day(s, {play = 4}).activity > 0)
  assert(a_day(pet({personality = neutral()}), {alone_min = 600}).sociability < 0)
  assert(a_day(pet({personality = neutral()}), {found = 3}).curiosity > 0)
  assert(a_day(pet({personality = neutral()}), {feed = 1, refused_food = 3}).food < 0)
  -- her rhythm follows your hours
  s = pet({personality = neutral()})
  s.memory["day_hours"][22 + 1] = 5
  assert(a_day(s).rhythm > 0)
  s = pet({personality = neutral()})
  s.memory["day_hours"][7 + 1] = 5
  assert(a_day(s).rhythm < 0)
  -- a day without you is not neglect: only more her own cat
  d = a_day(pet({personality = neutral()}), {alone_min = 300})
  assert(d.sociability < 0)
  for _, k in ipairs({"activity", "curiosity", "affection", "food", "rhythm", "pampered"}) do assert(d[k] == 0, k) end
  assert(a_day(pet({personality = neutral()}), {found = 3}).curiosity > 0)
  -- whims: giving in spoils her, a No toughens her, no whims no lesson
  assert(a_day(pet({personality = neutral()}), {whim_yes = 2}).pampered > 0)
  assert(a_day(pet({personality = neutral()}), {whim_no = 2}).pampered < 0)
  assert(a_day(pet({personality = neutral()}), {cuddle = 4, play = 2}).pampered == 0)
  -- never more than 0.03 a day
  d = a_day(pet({personality = neutral()}), {cuddle = 50, play = 50, found = 50, feed = 50})
  for k, v in pairs(d) do assert(math.abs(v) <= 0.03 + 1e-6, k) end
  assert(near(d.activity, 0.03))
  -- a missing axis starts at the middle
  s = pet({personality = {}})
  memory.new_day(s)
  assert(s.personality.sociability ~= nil and s.personality.activity == nil)
end

do
  -- the day becomes yesterday; days off teach once and leave yesterday empty
  local s = pet({personality = neutral(), day = 4})
  s.memory["day"]["play"] = 3
  memory.new_day(s)
  assert(s.memory["yesterday"]["play"] == 3 and s.memory["day"]["play"] == 0 and s.memory.at_day == 4)
  assert(s._dirty)
  s = pet({personality = neutral(), day = 12})
  s.memory["day"]["play"] = 4
  local a = s.personality.activity
  memory.new_day(s, 5)
  local tally = {}
  for _, k in ipairs(memory.TALLY) do tally[k] = 0 end
  tally.play = 4
  local target = memory._targets(tally, {0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0})
  local once = math.min((target.activity - a) * memory.LEARN_RATE, memory.LEARN_MAX)
  assert(near(s.personality.activity - a, once))
  assert(util.sum({s.memory.yesterday.play, s.memory.yesterday.cuddle, s.memory.yesterday.alone_min}) == 0)
  -- the hours fade: round(h * 0.8) + today, then 0.8 a day off
  s = pet({personality = neutral()})
  s.memory.hours[10] = 10
  s.memory.day_hours[10] = 2
  memory.new_day(s)
  assert(s.memory.hours[10] == 10 and math.type(s.memory.hours[10]) == "integer")
  memory.new_day(s, 3)
  assert(s.memory.hours[10] == 5) -- round(round(8) * 0.64) = round(5.12)
end

do
  -- test_a_broken_memory_starts_fresh
  local mem = memory.restore({day = {play = "x"}, hours = {}, first = {bath = 3, play = "n"}, at_day = "z",
                              yesterday = 5})
  assert(mem.day.play == 0 and mem.hours[24] == 0 and #mem.hours == 24)
  assert(mem.first.bath == 3 and mem.first.play == nil and util.len(mem.first) == 1)
  assert(mem.at_day >= 0)
  assert(memory.restore(nil).at_day == 0 and memory.restore("junk").at_day == 0)
  mem = memory.restore({day = {play = 2, nope = 9}, stars = {["Simón"] = 7, ["Quita nudos"] = 2},
                        stickers = {"comida", 5, "mimos"}, rooms = {1, -4, "3"}, toy = "pluma", at_day = 6,
                        games = {Juego = 2.9}})
  assert(mem.day.play == 2 and mem.day.nope == nil)
  assert(mem.stars["Simón"] == 3 and mem.stars["Quita nudos"] == 2)
  assert(#mem.stickers == 2 and mem.stickers[2] == "mimos")
  assert(mem.rooms[1] == 1 and mem.rooms[2] == 0 and mem.rooms[3] == 3)
  assert(mem.toy == "pluma" and mem.at_day == 6 and mem.games.Juego == 2)
  assert(memory.restore({toy = "hueso"}).toy == nil)
  assert(memory.count("12") == 12 and memory.count("1.5") == 0 and memory.count(-3) == 0)
  assert(memory.count(2.7) == 2 and memory.count(true) == 1 and memory.count({}) == 0 and memory.count(nil) == 0)
end

do
  -- test_what_you_do_is_tallied, test_firsts_are_kept
  HOUR = 12
  local s = pet({day = 3})
  memory.interaction(s, "Mimos", true)
  memory.interaction(s, "Juego", true)
  memory.interaction(s, "Alimentar:Pienso", false)
  memory.interaction(s, "Mimos", false)
  memory.interaction(s, "Luz", false)
  memory.interaction(s, "Luz", true)
  memory.interaction(s, "Baño:Jabón", true)
  local day = s.memory["day"]
  assert(day.cuddle == 1 and day.play == 1 and day.refused_food == 1 and day.refused_cuddle == 1)
  assert(day.refused == 1 and day.bath == 1)
  assert(util.sum(s.memory["day_hours"]) == 4 and s.memory["day_hours"][12 + 1] == 4) -- the ones she took
  s.day = 9
  memory.interaction(s, "Juego", true)
  assert(s.memory["first"]["play"] == 3 and s.memory["first"]["bath"] == 3)
  assert(s.memory["first"]["feed"] == nil) -- refused is no first
  memory.remember(s, "alone_min")
  memory.remember(s, "alone_min", 5)
  assert(s.memory.day.alone_min == 6)
end

do
  -- habits: your usual hour becomes hers; scattered hours are no habit; her favourite time
  local s = pet({personality = neutral()})
  assert(memory.habit_hour(s) == nil and memory.fav_time(s) == nil)
  for _ = 1, 3 do
    s.memory["day_hours"][21 + 1] = s.memory["day_hours"][21 + 1] + 3
    memory.new_day(s)
  end
  assert(memory.habit_hour(s) == 21 and memory.fav_time(s) == "evening")
  s = pet({personality = neutral()})
  for h = 8, 21 do s.memory["day_hours"][h + 1] = s.memory["day_hours"][h + 1] + 1 end
  memory.new_day(s)
  assert(memory.habit_hour(s) == nil)
  for _, case in ipairs({{17, "afternoon"}, {9, "morning"}, {0, "evening"}}) do
    s = pet({personality = neutral()})
    for _ = 1, 3 do
      s.memory["day_hours"][case[1] + 1] = s.memory["day_hours"][case[1] + 1] + 3
      memory.new_day(s)
    end
    assert(memory.habit_hour(s) == case[1] and memory.fav_time(s) == case[2], case[2])
  end
end

do
  -- her favourite game and room
  local s = pet()
  assert(memory.fav_game(s) == nil)
  for _ = 1, 5 do memory.game_started(s, "Quita nudos") end
  assert(s.memory["games"]["Quita nudos"] == 5 and memory.fav_game(s) == "Quita nudos")
  s.memory["games"] = {["Quita nudos"] = 6, ["Simón"] = 6}
  assert(memory.fav_game(s) == nil) -- not clearly
  s.memory["games"] = {["Quita nudos"] = 4}
  assert(memory.fav_game(s) == nil)
  s = pet({current_scene = 3})
  memory.room_minute(s)
  assert(#s.memory["rooms"] == 4 and s.memory["rooms"][3 + 1] == 1)
  assert(memory.fav_room(s) == nil)
  for _ = 1, memory.FAV_ROOM_MIN do memory.room_minute(s) end
  assert(memory.fav_room(s) == 3)
  s.memory["rooms"] = {0, 0, 0, 0, 0, 0, 900} -- a room that does not exist
  assert(memory.fav_room(s) == nil)
  s.memory["rooms"] = {}
  assert(memory.fav_room(s) == nil)
end

do
  -- the first find is her toy; she keeps it
  local s = pet()
  memory.keep_toy(s, "pluma")
  memory.keep_toy(s, "raton")
  assert(s.memory.toy == "pluma")
  s.memory.toy = ""
  memory.keep_toy(s, "raton")
  assert(s.memory.toy == "raton")
end

do
  -- dreams: awake none; asleep, of her life, one stretch in three none, all come round
  local s = pet()
  assert(memory.dream(s) == nil)
  s.sleeping = true
  s.memory["first"]["favorite"] = 1
  s.memory["games"] = {["Quita nudos"] = 6}
  local function dreams()
    local seen, none = {}, false
    for half_hour = 0, 11 do
      s._nap_sec = half_hour * 1800
      local d = memory.dream(s)
      if d == nil then none = true else seen[d] = true end
    end
    return seen, none
  end
  local seen, none = dreams()
  assert(none)
  for d in pairs(seen) do assert(util.contains(memory.DREAMS, d), d) end
  s.memory["toy"] = "pluma" -- three things: all come round
  seen = dreams()
  assert(util.len(seen) == 3 and seen.comida and seen.juego and seen.juguete)
  -- with nothing yet she dreams of cuddles
  s = pet({sleeping = true, _nap_sec = 0})
  local d = memory.dream(s)
  assert(d == "mimos" or d == nil)
  s.day = 0 -- period 0
  assert(memory.dream(s) == "mimos")
  s.deep_sleep = true
  assert(memory.dream(s) == nil)
  -- the stars, a legacy, a holiday, her firsts of the weather
  s = pet({sleeping = true, day = 0, stars = 2, legacy = {{cycle = 1}}})
  s.memory.first.halloween, s.memory.first.object, s.memory.first.snow = 1, 1, 1
  seen = dreams()
  for _, k in ipairs({"objeto", "nieve", "estrella", "legado", "fiesta"}) do assert(seen[k], k) end
end

do
  -- old memories come back once a week old
  local s = pet({day = 20})
  s.memory["first"] = {play = 18}
  assert(#memory.old_memories(s) == 0)
  s.memory["first"] = {play = 3, bath = 13, feed = 14}
  local old = memory.old_memories(s)
  assert(#old == 2 and old[1] == "bath" and old[2] == "play")
end

-- ================================================================== care
do
  local s = pet()
  assert(near(care.care_score_minute(s), 1.0 + 4 * 1.2 + 0.02 + 26.0 / 120.0))
  s.sick = true
  assert(near(care.care_score_minute(s), 1.0 + 4 * 1.2 - 2.8 + 0.02 + 26.0 / 120.0))
  s = pet({hunger = 54.0, energy = 54.0, health = 69.0, affection = 59.0, stress = 50.0, trust_bond = 50.0})
  assert(near(care.care_score_minute(s), 1.0))
  s.in_critical, s.dirt = true, 76.0
  assert(near(care.care_score_minute(s), 1.0 - 4.2 - 1.5))
  s = pet({stress = 50.0, trust_bond = 50.0, quirks = {"Dormilona", "Glotona", "Huidiza"}, sleeping = true,
           hunger = 30.0, hidden = true})
  assert(near(care.care_score_minute(s), 1.0 + 3 * 1.2 + 0.4 - 0.6 - 0.3))
  assert(care.care_score_minute(pet({trust_bond = 400.0})) == 8.0)
  assert(care.care_score_minute(pet({sick = true, in_critical = true, dirt = 90.0, hunger = 0.0, energy = 0.0,
                                     health = 0.0, affection = 0.0, trust_bond = 0.0, stress = 300.0})) == -6.0)
end

-- ================================================================== needs
local function needy(kw)
  local s = pet({phase = "Adulto", age_days = 20, hunger = 80.0, affection = 80.0, energy = 80.0, health = 90.0,
                 dirt = 10.0})
  for k, v in pairs(kw or {}) do s[k] = v end
  return s
end

do
  assert(needs.need(needy()) == nil)
  assert(needs.need(needy({hunger = 10.0})) == "Feed")
  assert(needs.need(needy({dirt = 90.0})) == "Bath")
  assert(needs.need(needy({affection = 10.0})) == "Cuddle")
  assert(needs.need(needy({hunger = 10.0, dirt = 90.0, affection = 10.0})) == "Feed")
  assert(needs.need(needy({energy = 10.0})) == "Sleep")
  assert(needs.need(needy({wants_play = true})) == "Play")
  assert(needs.need(needy({litter = 2})) == "Bath") -- the box smells
  assert(needs.need(needy({litter = 1})) == nil)
  -- asleep she needs nothing unless unwell
  assert(needs.need(needy({hunger = 10.0, sleeping = true})) == nil)
  assert(needs.need(needy({sick = true, sleeping = true, menu = {"Heal", "Feed"}})) == "Heal")
  assert(needs.need(needy({in_critical = true})) == nil) -- Heal not in this menu
  for _, kw in ipairs({{powered_off = true}, {sitter_until = 5}, {hidden = true}, {mode = "farewell"}}) do
    kw.hunger = 10.0
    assert(needs.need(needy(kw)) == nil)
  end
  -- she calls once when a need comes
  local s = needy()
  needs.call_minute(s)
  local seq = s.sound_seq
  s.hunger = 10.0
  needs.call_minute(s)
  assert(s.sound == "llama" and s.sound_seq == seq + 1 and logged(s, "Te llama") and s._need_called == "Feed")
  needs.call_minute(s)
  assert(s.sound_seq == seq + 1) -- once, not every minute
  s.hunger = 80.0
  needs.call_minute(s)
  assert(s._need_called == nil)
end

-- ================================================================== litter
do
  local s = pet()
  for _ = 1, litter.LITTER_EVERY_SEC * 5 do litter.second(s) end
  assert(s.litter == 3 and s._litter_sec == 0)
  s = pet()
  for _ = 1, litter.LITTER_EVERY_SEC - 1 do litter.second(s) end
  assert(s.litter == 0)
  litter.second(s)
  assert(s.litter == 1 and s._dirty)
  assert(not litter.smells(s) and litter.dirt_rate(s) == 1.0)
  s.litter = 2
  assert(litter.smells(s) and litter.dirt_rate(s) == 1.5)
  -- Baño opens the choice, the box first when dirty; B cleans it
  s = pet({litter = 1, affection = 50.0, stress = 20.0, overlay_text = "x", overlay_until = 99})
  litter.open_bath(s, 1000)
  assert(s.mode == "action_bath" and s.bath_choice == 1 and s.overlay_text == nil and s.overlay_until == 0)
  litter.confirm(s, 1100)
  assert(s.mode == "main" and s.litter == 0 and s.sound == "limpia" and s.affection == 52.0 and s.stress == 15.0)
  assert(s.overlay_text == "¡Arenero limpito!" and s.overlay_until == 2000 and logged(s, "Limpias el arenero"))
  assert(s.interactions[1][1] == "Arenero" and s.interactions[1][2] == true)
  -- or she is bathed
  s = pet({dirt = 80.0})
  litter.open_bath(s, 1000)
  assert(s.bath_choice == 0)
  litter.confirm(s, 1100)
  assert(s.bathed_at == 1100 and s.dirt < 80.0 and s.mode == "main")
  -- a clean box: nothing to do
  s = pet()
  litter.clean(s, 500)
  assert(s.overlay_text == "¡Si ya está limpio!" and s.overlay_until == 1400 and s.sound == nil)
  -- the cursor wraps
  s = pet({bath_choice = 1})
  litter.move(s, 1)
  assert(s.bath_choice == 0)
  litter.move(s, -1)
  assert(s.bath_choice == 1)
  assert(litter.BATH_OPTIONS[1] == "Bañarla" and litter.BATH_OPTIONS[2] == "Arenero")
end

-- ================================================================== stickers
do
  local s = pet()
  stickers.check(s)
  assert(#s.memory["stickers"] == 0 and s.sound == nil)
  s.memory["first"]["feed"] = 1
  local seq = s.sound_seq
  stickers.check(s)
  assert(#s.memory["stickers"] == 1 and s.memory["stickers"][1] == "comida")
  assert(s.sound == "pegatina" and s.new_sticker == "comida" and s.new_sticker_seq == 1 and logged(s, "Nueva pegatina"))
  stickers.check(s)
  assert(#s.memory["stickers"] == 1 and s.sound_seq == seq + 1)
  -- games and time earn theirs, in the album's order
  s = pet({age_days = 7})
  for _, g in ipairs(rules.PLAY_OPTIONS) do s.memory["stars"][g] = 1 end
  s.memory["stars"]["Simón"] = 3
  stickers.check(s)
  local got = s.memory["stickers"]
  assert(#got == 3 and got[1] == "tres_estrellas" and got[2] == "todos_los_juegos" and got[3] == "semana")
  assert(s.new_sticker == "semana")
  s.memory["stars"]["Simón"] = nil
  s.age_days = 30
  stickers.check(s)
  assert(#got == 4 and got[4] == "mes")
  assert(#stickers.IDS == 16 and stickers.IDS[1] == "comida" and stickers.IDS[16] == "mes")
end

-- ================================================================== power_state
do
  -- test_wake_sleep_transitions_consistent
  local s = pet()
  assert(power_state.enter_sleep(s, 1000, "manual", true))
  assert(s.sleeping and not s.deep_sleep and s.overlay_text == "A soñar con atún" and s.overlay_until == 1900)
  assert(s.mood == "sleepy" and logged(s, "Sleep manual") and s._nap_sec == 0 and s._awake_sec == 0)
  assert(power_state.request_deep_sleep(s, 2000, "test"))
  assert(s.deep_sleep and not s.sleeping and not s.light_on and s.overlay_text == "Sueño profundo...")
  assert(logged(s, "Entra sleep profundo (test)") and s.mood == "deep_sleep")
  assert(not power_state.request_deep_sleep(s, 2500, "test")) -- already
  assert(power_state.wake_by_button(s, 5000, "test"))
  assert(not s.deep_sleep and not s.sleeping and s.light_on and s.mode == "main")
  assert(s.overlay_text == "Bostezo y voy..." and logged(s, "Wake (test)") and s._last_wake_ts == s.clock:now())
  -- not twice within WAKE_MIN_INTERVAL_SEC
  s.deep_sleep = true
  assert(not power_state.wake_by_button(s, 5100, "test"))
  s.clock:advance(rules.WAKE_MIN_INTERVAL_SEC)
  assert(power_state.wake_by_button(s, 5200))
  assert(logged(s, "Wake (botón)"))
  -- awake and on: nothing to wake
  assert(not power_state.wake_by_button(s, 9000))
  -- switched off: on again, a little energy
  s = pet({powered_off = true, energy = 1.0, mode = "status"})
  assert(not power_state.enter_sleep(s, 1000))
  assert(not power_state.request_deep_sleep(s, 1000))
  assert(power_state.wake_by_button(s, 1000, "test"))
  assert(not s.powered_off and s.light_on and s.mode == "main" and s.energy == 4.0)
  assert(s.overlay_text == "Arrancando motores...")
  -- no overlay when asked; her farewell keeps its screen
  s = pet({mode = "farewell", overlay_text = nil})
  assert(power_state.enter_sleep(s, 1000, "auto", false))
  assert(s.mode == "farewell" and s.overlay_text == nil and logged(s, "Sleep auto"))
  s = pet({mode = "status"})
  power_state.enter_sleep(s, 1000)
  assert(s.mode == "main" and s.overlay_text == "A soñar con atún" and logged(s, "Sleep manual"))
end

do
  -- the light: off puts her to bed, on wakes her
  local s = pet()
  power_state.act_light(s, 1000)
  assert(not s.light_on and s.sleeping and s.overlay_text == "¡A oscuras!" and s.overlay_until == 1900)
  assert(logged(s, "Apaga luz") and logged(s, "Sleep light_off"))
  assert(s.interactions[1][1] == "Luz" and s.interactions[1][2] == true)
  s.deep_sleep = true
  power_state.act_light(s, 2000)
  assert(s.light_on and not s.sleeping and not s.deep_sleep and s.overlay_text == "¡Hágase la luz!")
  assert(logged(s, "Enciende luz") and #s.interactions == 2)
  -- switched off, the light button wakes her
  s = pet({powered_off = true, light_on = false})
  power_state.act_light(s, 1000)
  assert(not s.powered_off and s.light_on and logged(s, "Wake (Luz)") and #s.interactions == 0)
  assert(power_state.can_wake_now(pet({_last_wake_ts = 12 * 3600 - 2})))
  assert(not power_state.can_wake_now(pet({_last_wake_ts = 12 * 3600 - 1})))
end

-- ================================================================== hearing (D-31)
local function listener(kw)
  local s = pet({quirks = {"Curiosa", "Glotona"}, hunger = 70.0, affection = 60.0, energy = 70.0, health = 90.0,
                 stress = 20.0})
  for k, v in pairs(kw or {}) do s[k] = v end
  return s
end

do
  -- a voice turns her ears and keeps her company, not every word
  local s = listener()
  hearing.hear(s, "voz", 1000)
  assert(s.sound == "te_oye" and s._input_pending_ts > 0 and s._frame_ms == 1000)
  local seq = s.sound_seq
  hearing.hear(s, "voz", 5000)
  assert(s.sound_seq == seq)
  hearing.hear(s, "voz", 1000 + rules.HEAR_COOLDOWN_MS["voz"] + 1)
  assert(s.sound_seq == seq + 1)
  -- a loud noise frightens her
  s = listener()
  hearing.hear(s, "ruido", 1000)
  assert(s.sound == "susto" and s.stress > 20.0 and not s.hidden)
  -- a skittish one hides from it
  s = listener({quirks = {"Huidiza", "Curiosa"}})
  hearing.hear(s, "ruido", 1000)
  assert(s.hidden and s._hide_cd_until_ms == 13000)
  -- ...as does a stressed one, unless she may not hide now
  s = listener({stress = 66.0})
  hearing.hear(s, "ruido", 1000)
  assert(s.hidden)
  s = listener({quirks = {"Huidiza"}, may_hide = false})
  hearing.hear(s, "ruido", 1000)
  assert(not s.hidden and s.sound == "susto")
  -- a loud noise counts once in twenty minutes
  s = listener()
  hearing.hear(s, "ruido", 1000)
  local stress = s.stress
  hearing.hear(s, "ruido", 61000)
  assert(s.stress == stress)
  hearing.hear(s, "ruido", 1000 + 20 * 60000)
  assert(near(s.stress, stress + rules.FRIGHT_STRESS))
  -- a voice after an absence is no hello
  s = listener({_was_away = true})
  hearing.hear(s, "voz", 1000)
  assert(s._input_pending_ts == 0.0 and s.sound == "te_oye")
  -- unwell she does not run and hide
  s = listener({quirks = {"Huidiza", "Curiosa"}, sick = true})
  hearing.hear(s, "ruido", 1000)
  assert(not s.hidden and s.sound == "susto")
  -- music: she sways
  s = listener()
  hearing.hear(s, "musica", 1000)
  assert(s.sound == "musica" and near(s.excitement, 49.0))
  -- hiding, she answers your voice from her room
  s = listener({hidden = true, hidden_scene = 3})
  hearing.hear(s, "voz", 2000)
  assert(s.sound == "responde" and s.seek_hint_until == 2000 + rules.SEEK_HINT_MS)
  s = listener({hidden = true})
  hearing.hear(s, "ruido", 2000)
  assert(s.sound == nil and s.stress == 20.0)
  -- asleep at night nothing wakes her; by day a noise does, a voice not
  s = listener({sleeping = true, night = true})
  hearing.hear(s, "ruido", 1000)
  assert(s.sleeping and s.sound == nil)
  s = listener({sleeping = true})
  hearing.hear(s, "ruido", 1000)
  assert(not s.sleeping and s.sound == "despierta" and logged(s, "La despertó un ruido"))
  s = listener({sleeping = true})
  hearing.hear(s, "voz", 1000)
  assert(s.sleeping and s.sound == nil and s._input_pending_ts == 0.0)
  -- the micro off, and the times nobody hears
  for _, kw in ipairs({{mic_on = false}, {powered_off = true}, {deep_sleep = true}, {mode = "farewell"},
                       {mode = "birth"}, {mode = "sancho_intro"}, {mode = "grow"}, {sitter_until = 7}}) do
    s = listener(kw)
    hearing.hear(s, "ruido", 2000)
    assert(s.sound_seq == 0 and s._heard_until["ruido"] == nil and s._frame_ms == 0)
  end
  s = listener()
  hearing.hear(s, "silbido", 2000)
  assert(s.sound_seq == 0 and s._frame_ms == 0)
  -- in a menu: heard, not shown
  s = listener({mode = "status"})
  hearing.hear(s, "voz", 2000)
  assert(s.sound == nil and s._heard_until["voz"] == 2000 + rules.HEAR_COOLDOWN_MS["voz"] and s._input_pending_ts > 0)
  -- a cooldown set on another tick base is forgotten
  s = listener()
  s._heard_until["voz"] = 2000 + rules.HEAR_COOLDOWN_MS["voz"] + 1
  hearing.hear(s, "voz", 2000)
  assert(s.sound == "te_oye")
end

print("ok a")
