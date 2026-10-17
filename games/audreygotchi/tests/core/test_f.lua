-- test_f: group F, core/events.lua, core/weather.lua, core/v2_gameplay.lua (ports of the Python tests in
-- test_rules_v11.py, test_v2_gameplay.py and test_bible_64.py that touch them).
local util = require("core.util")
local rules = require("core.rules")

-- the modules other groups port: small faithful copies of the Python functions these modules call
local HABIT_MIN, HABIT_SHARE, RECALL_AFTER_DAYS = 5, 0.3, 7
local FAV_GAME_MIN, FAV_ROOM_MIN, FAV_ROOM_SHARE = 5, 600, 0.35
local function argmax(list) -- first index (0-based) of the largest value
  local best = 0
  for i = 1, #list - 1 do if list[i + 1] > list[best + 1] then best = i end end
  return best
end
LOADED["core.memory"] = {
  TOYS = {"pelota", "raton", "pluma", "tapon", "cinta"},
  first = function(s, what) if s.memory.first[what] == nil then s.memory.first[what] = util.int(s.day) end end,
  habit_hour = function(s)
    local hours = s.memory.hours
    local best = argmax(hours)
    if hours[best + 1] >= HABIT_MIN and hours[best + 1] >= HABIT_SHARE * util.sum(hours) then return best end
    return nil
  end,
  old_memories = function(s)
    local out = {}
    for _, k in ipairs(util.keys(s.memory.first)) do
      if util.int(s.day) - s.memory.first[k] >= RECALL_AFTER_DAYS then out[#out + 1] = k end
    end
    return out
  end,
  fav_game = function(s)
    local games = s.memory.games
    if next(games) == nil then return nil end
    local best
    for _, g in ipairs(util.keys(games)) do if best == nil or games[g] > games[best] then best = g end end
    local ties = 0
    for _, n in pairs(games) do if n == games[best] then ties = ties + 1 end end
    if games[best] < FAV_GAME_MIN or ties > 1 then return nil end
    return best
  end,
  fav_room = function(s)
    local rooms = util.slice(s.memory.rooms, 0, #s.scenarios)
    if #rooms == 0 then return nil end
    local best = argmax(rooms)
    if rooms[best + 1] >= FAV_ROOM_MIN and rooms[best + 1] >= FAV_ROOM_SHARE * util.sum(rooms) then return best end
    return nil
  end,
  keep_toy = function(s, found) if s.memory.toy == nil then s.memory.toy = found end end,
}
local WINDOW_ROOMS = {"bg_living.png", "bg_studio.png"}
LOADED["core.bird"] = {
  BIRD_MS = 25000,
  window_here = function(s) return util.contains(WINDOW_ROOMS, s.BG_FILES[s.current_scene % #s.BG_FILES + 1]) end,
  land = function(s, now_ms)
    s.bird_until, s.bird_room = now_ms + 25000, s.current_scene
    s.stress = s:_clamp_stat(s.stress + 4.0)
    s:mark_dirty()
  end,
}
LOADED["core.hearing"] = {
  fright = function(s, now_ms)
    s.stress = s:_clamp_stat(s.stress + s.FRIGHT_STRESS)
    local skittish = util.contains(s.quirks, "Huidiza") or s.stress >= 70.0
    if skittish and not (s.sick or s.in_critical) and s:_may_hide(now_ms) then
      s:_hide(now_ms)
      s._hide_cd_until_ms = now_ms + 12000
    else
      s:_emit_sound("susto")
    end
    s:mark_dirty()
  end,
}
local HEIRLOOM = {juguete = "rueda", piedra = "vuelta", cojin = "mimos", foto = "happy_wiggle",
                  cuenco = "encontrada", estrella = "presume"}
LOADED["core.lifecycle"] = {
  heirloom = function(s)
    local earlier = {}
    for _, x in ipairs(s.legacy) do if util.get(x, "cycle", 0) < s.cycle then earlier[#earlier + 1] = x end end
    if #earlier == 0 then return nil end
    return HEIRLOOM[earlier[#earlier].item]
  end,
}
LOADED["core.asks"] = {
  WHIM_WAIT_SEC = 15 * 60,
  start = function(s, kind, wait_sec)
    s.mode, s.ask, s.ask_yes = "ask", kind, true
    s.ask_until = (s._sim_ts ~= 0 and s._sim_ts or s.clock:now()) + wait_sec
    s:mark_dirty()
  end,
}

local events = require("core.events")
local weather = require("core.weather")
local v2 = require("core.v2_gameplay")
local Clock = require("core.clock")

-- a clock on a given local date and hour (the Python tests' _DateClock / _HourClock)
local FakeClock = {}
FakeClock.__index = FakeClock
function FakeClock.new(t, month, day, hour)
  return setmetatable({t = t, year = 2026, month = month, day = day, hour = hour, minute = 0}, FakeClock)
end
function FakeClock:now() return self.t end
function FakeClock:now_ms() return 0 end
function FakeClock:local_hour() return self.hour end
function FakeClock:localtime(ts)
  return {tm_year = self.year, tm_mon = self.month, tm_mday = self.day, tm_hour = self.hour, tm_min = self.minute,
          tm_sec = 0, tm_yday = 1, tm_wday = 0}
end

-- GameState's methods these modules call, as the Python's
local methods = setmetatable({}, {__index = rules})
function methods:_pf(key, default)
  local v = self.personality[key]
  if v == nil then return default or 0.5 end
  return v + 0.0
end
function methods:_clamp_stat(v, lo, hi) return math.max(lo or 0.0, math.min(hi or 100.0, v + 0.0)) end
function methods:_emit_sound(name) self.sound, self.sound_seq = name, self.sound_seq + 1 end
function methods:_log_event(txt)
  local l = self.last_events
  l[#l + 1] = txt
  if #l > 10 then table.remove(l, 1) end
end
function methods:mark_dirty() self._dirty = true end
function methods:is_night() local h = self.clock:local_hour() return h >= 22 or h < 8 end
function methods:_may_hide(now_ms)
  if self.phase == "Cachorro" then return false end
  local until_ms = self._hide_cd_until_ms
  return now_ms >= until_ms or until_ms - now_ms > self.HIDE_REST_MS
end
function methods:_hide(now_ms)
  self.hidden, self.hidden_scene = true, util.choice(self.HIDING_ROOMS)
  self.seek_misses, self.seek_searched, self.seek_play = 0, 0, false
  self:_emit_sound("escondida")
  self:mark_dirty()
end
function methods:enter_sleep(now_ms, reason, show_overlay)
  self.sleeping, self.light_on, self.sleep_reason = true, false, reason
  return true
end
function methods:set_weather(kind, temp_c, is_day, sun) weather.set_weather(self, kind, temp_c, is_day, sun) end
local META = {__index = methods}

local TALLY = {"cuddle", "play", "feed", "bath", "found", "friend", "refused", "refused_food", "refused_cuddle",
               "alone_min", "whim_yes", "whim_no"}
local function zeros(n) local t = {} for i = 1, n do t[i] = 0 end return t end

local function pet(o)
  o = o or {}
  local day = {}
  for _, k in ipairs(TALLY) do day[k] = 0 end
  local s = {
    clock = o.clock or FakeClock.new(100000, o.month or 10, o.mday or 5, o.hour or 12),
    mode = "main", sleeping = false, deep_sleep = false, powered_off = false, hidden = false, hidden_scene = -1,
    sick = false, in_critical = false, sitter_until = 0, wants_play = false, _away = false,
    phase = "Adulto", personality = {}, mood = "calm", quirks = {"Curiosa"}, name = "Audrey", cycle = 1, day = 1,
    hunger = 70.0, affection = 60.0, energy = 70.0, health = 90.0, stress = 20.0, dirt = 20.0, excitement = 46.0,
    memory = {day = day, first = {}, hours = zeros(24), day_hours = zeros(24), rooms = {}, games = {}},
    scenarios = {"Salón", "Cocina", "Rascador", "Estudio", "WC"}, current_scene = 0, legacy = {}, stars = 0,
    farewell_scheduled_day = 0, last_input_ts = 0, _frame_ms = 0, _hide_cd_until_ms = 0, _sim_ts = 0,
    _ev_min = 0, _ev_ring = {}, _ev_last_big = -1000000, _ev_ready = {}, events_once = {}, _later = {},
    _looking_until = 0, light_on = true, play_choice = 0, sound_seq = 0, last_events = {}, overlay_until = 0,
    bird_until = 0, bird_room = 0, favorite_food = "", disliked_food = "", sick_cause = "", sick_since_ms = 0,
    indigestion_until_ms = 0, _med_doses = 0, _snack_streak = 0,
  }
  for k, v in pairs(o) do
    if k ~= "clock" and k ~= "month" and k ~= "mday" and k ~= "hour" then s[k] = v end
  end
  return setmetatable(s, META)
end

local function with_random(value, fn) -- patch random.random for the length of fn
  local real = math.random
  math.random = function(a, b) if a == nil then return value end return real(a, b) end
  local ok, err = pcall(fn)
  math.random = real
  assert(ok, err)
end

local function close(a, b, eps) return math.abs(a - b) <= (eps or 1e-4) end

-- ===================================================================================== weather

do -- Easter moves every year (Meeus/Jones/Butcher)
  local want = {[2024] = {3, 31}, [2025] = {4, 20}, [2026] = {4, 5}, [2027] = {3, 28}, [2038] = {4, 25},
                [2000] = {4, 23}, [2100] = {3, 28}, [2019] = {4, 21}}
  for y, md in pairs(want) do
    local e = weather.easter(y)
    assert(e[1] == md[1] and e[2] == md[2], "easter " .. y .. ": " .. e[1] .. "/" .. e[2])
  end
end

do -- the holidays of Spain and Catalonia, 2026 (Easter 5 April: Carnaval 12-17 Feb)
  local cases = {
    {12, 20, "navidad"}, {12, 24, "caga_tio"}, {12, 25, "caga_tio"}, {12, 31, "nochevieja"}, {1, 5, "reyes"},
    {1, 6, "reyes"}, {2, 11, nil}, {2, 12, "carnaval"}, {2, 17, "carnaval"}, {2, 18, nil}, {4, 5, "pascua"},
    {4, 6, "pascua"}, {4, 7, nil}, {6, 22, nil}, {6, 23, "sant_joan"}, {6, 24, "sant_joan"}, {9, 11, "diada"},
    {9, 12, nil}, {4, 23, "sant_jordi"}, {4, 22, nil}, {4, 24, nil}, {10, 29, "halloween"}, {10, 25, "halloween"},
    {10, 24, nil}, {10, 5, nil}, {1, 4, "navidad"}, {1, 7, nil}, {12, 14, nil}, {12, 15, "navidad"},
  }
  for _, c in ipairs(cases) do
    local got = weather._holiday({2026, c[1], c[2]})
    assert(got == c[3], string.format("%d/%d: %s", c[1], c[2], tostring(got)))
    local s = pet({clock = FakeClock.new(100000, c[1], c[2], 12)})          -- through holiday(s)
    assert(weather.holiday(s) == c[3])
  end
  assert(weather._holiday((nil)) == nil and weather._holiday({}) == nil)
  -- Sant Jordi keeps its rose on Easter Monday (2038)
  assert(weather._holiday({2038, 4, 23}) == "sant_jordi")
  assert(weather._holiday({2038, 4, 26}) == "pascua")
  -- a leap year's Carnaval (2024: Easter 31 March, Dijous Gras 8 Feb, Tuesday 13 Feb)
  assert(weather._holiday({2024, 2, 8}) == "carnaval" and weather._holiday({2024, 2, 13}) == "carnaval")
  assert(weather._holiday({2024, 2, 7}) == nil and weather._holiday({2024, 2, 14}) == nil)
  assert(weather.PARENT.caga_tio == "navidad" and weather.PARENT.reyes == "navidad" and #weather.HOLIDAYS == 10)
  -- with the real clock: a game started on 23 April 2026
  local s = pet({clock = Clock.start({2026, 4, 23}, 3600)})
  assert(weather.holiday(s) == "sant_jordi")
  assert(weather.holiday(s, Clock.EPOCH + 86400 + 60) == nil)       -- the 24th, asked at its own ts
end

do -- the holiday is kept for its minute, then read again (the window ends with its date)
  local s = pet({clock = FakeClock.new(100000, 10, 31, 12)})
  assert(weather.holiday(s) == "halloween")
  s.clock.month, s.clock.day = 11, 1
  assert(weather.holiday(s) == "halloween")                         -- same minute: the memo
  s.clock.t = s.clock.t + 60
  assert(weather.holiday(s) == nil)
  assert(s._holiday_memo[1] == (100000 + 60) // 60 and s._holiday_memo[2] == nil)
end

do -- seasons
  local function season(m) return weather.season(pet({clock = FakeClock.new(100000, m, 1, 12)})) end
  assert(season(1) == "winter" and season(7) == "summer" and season(3) == "spring" and season(9) == "autumn")
  assert(season(12) == "winter" and season(2) == "winter" and season(6) == "summer" and season(11) == "autumn")
end

do -- dark outside by the sun, else by the night hours
  local s = pet({clock = FakeClock.new(100000, 10, 5, 20)})
  assert(s.weather == nil and weather.dark(s) == false)           -- no report: the night hours, 22-08
  s:set_weather("clear", 15.0, false)                               -- the sun is down
  assert(weather.dark(s) == true)
  s:set_weather("clear", 15.0, true)
  assert(weather.dark(s) == false)
  s.clock.t = s.clock.t + 4 * 3600                                  -- a stale report counts for nothing
  s.clock.hour = 23
  assert(weather.dark(s) == true)
end

do -- dark by the sun times, so an old report does not keep the night
  local rise, sunset = 7 * 60 + 54, 19 * 60 + 18
  local s = pet({clock = FakeClock.new(100000, 10, 5, 7)})
  s.clock.minute = 41
  s:set_weather("fog", 18.0, false, {rise, sunset})
  assert(weather.dark(s) == true)
  s.clock.t = s.clock.t + 46 * 60
  s.clock.hour, s.clock.minute = 8, 27
  assert(weather.dark(s) == false)
  s.clock.t = s.clock.t + 11 * 3600                                 -- the report is stale; its sun is not
  s.clock.hour, s.clock.minute = 19, 30
  assert(weather.now(s) == nil and weather.dark(s) == true)
  s.clock.t = s.clock.t + weather.SUN_STALE_SEC                     -- days without a report: the night hours
  s.clock.hour = 20
  assert(weather.dark(s) == false)
end

do -- the half hour before sunset reddens, and she looks out
  local s = pet({clock = FakeClock.new(100000, 10, 5, 18)})
  s.clock.minute = 48
  assert(weather.dusk(s) == false)                                  -- no sun times: no dusk
  s:set_weather("clear", 18.0, true, {474, 1158})                   -- sunset 19:18
  assert(weather.dusk(s) == true)
  assert(events._weight(s, "mira_lluvia", 18) > 0)
  s.clock.minute = 47
  assert(weather.dusk(s) == false)
  assert(events._weight(s, "mira_lluvia", 18) == 0)
  s.clock.hour, s.clock.minute = 19, 18                             -- the sun down: night, not dusk
  assert(weather.dusk(s) == false and weather.dark(s) == true)
end

do -- sun times that make no sense are left out
  local s = pet({clock = FakeClock.new(100000, 10, 5, 20)})
  s:set_weather("clear", 15.0, true, {1200, 300})                   -- sunset before sunrise: ignored
  assert(s.weather.sun == nil and weather.dark(s) == false)         -- the report's own word stands
  s:set_weather("clear", 15.0, true, {474, 1158})
  assert(s.weather.sun[1] == 474 and s.weather.sun[2] == 1158 and weather.dark(s) == true)
  assert(weather.sun_times({0, 1440})[2] == 1440 and weather.sun_times({-1, 30}) == nil)
  assert(weather.sun_times(nil) == nil and weather.sun_times({5}) == nil and weather.sun_times({"x", 9}) == nil)
  assert(weather.sun_times({"60", 120.7})[1] == 60 and weather.sun_times({"60", 120.7})[2] == 120)
end

do -- the report itself: an unknown kind is ignored, the temperature rounded as Python's round()
  local s = pet()
  s:set_weather("hail", 10, true)
  assert(s.weather == nil)
  s:set_weather("cloudy", 15.5, 1)
  assert(s.weather.temp == 16 and s.weather.day == true and s.weather.at == 100000 and s._dirty)
  s:set_weather("cloudy", 14.5, 0)
  assert(s.weather.temp == 14 and s.weather.day == false)
  s:set_weather("cloudy", -0.6, true)
  assert(s.weather.temp == -1 and math.type(s.weather.temp) == "integer")
end

do -- rain she watches from the window; old weather counts for nothing
  local s = pet()
  assert(events._weight(s, "mira_lluvia", 12) == 0)
  s:set_weather("rain", 12, true)
  assert(events._weight(s, "mira_lluvia", 12) > 0 and weather.kind(s) == "rain")
  s:set_weather("storm", 14, true)
  s.clock.t = s.clock.t + 3 * 3600
  assert(weather.kind(s) == "storm")                                -- 3 h still counts
  s.clock.t = s.clock.t + 1
  assert(weather.kind(s) == nil and weather.now(s) == nil)
  s.weather = {}                                                     -- an empty one: none
  assert(weather.now(s) == nil and weather.dusk(s) == false)
end

do -- a storm makes her readier to hide, keeps her in; warm sun she lies in; cold and heat, naps
  local s = pet()
  local calm_hide, calm_walk = events._weight(s, "se_esconde", 12), events._weight(s, "pasea", 12)
  s:set_weather("storm", 14, true)
  assert(close(events._weight(s, "se_esconde", 12), calm_hide * 2.0))
  assert(close(events._weight(s, "pasea", 12), calm_walk * 0.6))
  s = pet({affection = 80.0})
  local before = events._weight(s, "se_revuelca", 12)
  s:set_weather("clear", 22, true)
  assert(weather.sunny(s) and close(events._weight(s, "se_revuelca", 12), before * 3.0))
  s:set_weather("clear", 14, true)                                  -- not warm
  assert(not weather.sunny(s))
  s:set_weather("clear", 22, false)                                 -- not by day
  assert(not weather.sunny(s))
  s = pet({energy = 20.0})
  local nap = events._weight(s, "se_duerme_sola", 12)
  s:set_weather("cloudy", 3, true)
  assert(weather.cold(s) and not weather.hot(s) and close(events._weight(s, "se_duerme_sola", 12), nap * 1.5))
  s:set_weather("clear", 29, true)
  assert(weather.hot(s) and not weather.cold(s))
  s:set_weather("clear", 8, true)
  assert(not weather.cold(s))                                       -- 8 is not below 8
  s:set_weather("clear", 28, true)
  assert(not weather.hot(s))
end

do -- her first snow and her first storm are memories, kept with their day
  local s = pet({clock = FakeClock.new(100000, 1, 20, 12), day = 4})
  s:set_weather("snow", -1, true)
  assert(s.memory.first.snow == 4)
  s.day = 9
  s:set_weather("snow", -2, true)
  assert(s.memory.first.snow == 4)                                  -- setdefault
  s:set_weather("rain", 5, true)
  assert(s.memory.first.rain == nil)
end

-- ===================================================================================== events

do -- the table of events
  local n = 0
  for ev, spec in pairs(events.EVENTS) do
    n = n + 1
    assert(util.contains(events.EVENT_IDS, ev), ev)
    assert(util.contains({"common", "uncommon", "rare", "very_rare"}, spec[1]), ev)
  end
  assert(n == #events.EVENT_IDS and n == 24)
  assert(events.EVENTS.capricho[3][1][1] == 9 and events.EVENTS.capricho[3][1][2] == 21 and #events.EVENTS.capricho[3] == 1)
  assert(events.EVENTS.mira_estrella[1] == "rare" and events.EVENTS.mira_estrella[3][1][1] == 19)
  assert(events.EVENTS.mira_legado[1] == "rare" and events.EVENTS.herencia[1] == "very_rare")
  assert(events.EVENTS.ritual[1] == "very_rare" and events.EVENTS.luna[1] == "very_rare")
  assert(events.EVENTS.pasea[2] == 30 and events.EVENTS.pajaro[2] == 120 and events.EVENTS.mira[3] == nil)
  local big = 0
  for _, t in ipairs(events.TIERS) do if t[1] ~= "common" then big = big + t[2] end end
  assert(big <= 0.04)                                               -- events that change something are rare
  assert(rules.HIDE_REST_MS == events.GAP_MIN * 60000 and rules.HEAR_COOLDOWN_MS.ruido == events.GAP_MIN * 60000)
  assert(events.RING == 8 and events.LOOK_MS == 6000 and events.LATER_MAX == 4)
end

do -- the stages: pace, share, leanings
  assert(events.stage(pet({phase = "Senior"}))[1] == 0.85 and events.stage(pet({phase = "Nope"}))[1] == 1.0)
  assert(events.stage(pet({phase = "Cachorro"}))[2] < events.stage(pet({phase = "Juvenil"}))[2])
  assert(events.stage(pet({phase = "Cachorro"}))[3].se_duerme_sola > util.get(events.stage(pet({phase = "Juvenil"}))[3], "se_duerme_sola", 1.0))
  local function grown(phase)
    local s = pet({phase = phase, affection = 80.0, day = 30})
    s.memory.first = {play = 3}
    return s
  end
  local function w(phase, ev) return events._weight(grown(phase), ev) end
  assert(w("Cachorro", "mira") > w("Adulto", "mira"))
  assert(w("Juvenil", "ensucia_habitacion") > w("Adulto", "ensucia_habitacion"))
  assert(w("Senior", "recuerdo") > w("Adulto", "recuerdo"))
  assert(w("Extra", "acompana") > w("Adulto", "acompana"))
  assert(w("Extra", "pide_jugar") < w("Adulto", "pide_jugar"))
  -- a puppy: no past to recall yet, never hides on her own
  local puppy = grown("Cachorro")
  puppy.stars, puppy.cycle, puppy.legacy, puppy.mood = 1, 2, {{cycle = 1, item = "juguete"}}, "happy"
  for _, ev in ipairs({"se_esconde", "recuerdo", "mira_legado", "mira_estrella", "ritual", "herencia", "baila"}) do
    assert(events._weight(puppy, ev, 12) == 0, ev)
  end
end

do -- the hour leans, never rules: curious mornings, quiet evenings, play in the afternoon
  local s = pet()
  assert(close(events._lean(s, "mira", 8), 1.5) and close(events._lean(s, "mira", 21), 0.7))
  assert(close(events._lean(s, "mira", 13), 1.0) and close(events._lean(s, "escucha", 3), 1.05))
  assert(close(events._lean(s, "pide_jugar", 16), 1.5) and close(events._lean(s, "pide_jugar", 12), 1.0))
  assert(close(events._lean(s, "cola", 12), 0.7) and close(events._lean(s, "bosteza", 12), 1.0))
  s.energy = 39.0
  assert(close(events._lean(s, "bosteza", 12), 2.0) and events._lean(s, "pide_jugar", 16) == 0)
  s.energy = 29.0
  assert(events._lean(s, "pasea", 16) == 0 and close(events._lean(s, "se_duerme_sola", 12), 2.0))
  s.energy, s.stress = 70.0, 71.0
  assert(close(events._lean(s, "pasea", 16), (0.5 + 0.5 + 0.25 + 0.5) * 1.5))
  s.scenarios = {"Salón"}
  assert(events._lean(s, "pasea", 16) == 0)
  s = pet({dirt = 81.0})
  assert(events._lean(s, "ensucia_habitacion", 12) == 0)
  s.dirt = 80.0
  assert(close(events._lean(s, "ensucia_habitacion", 12), 0.75))
  s = pet({affection = 69.0})
  assert(events._lean(s, "acompana", 12) == 0)
  s.affection, s.mood = 85.0, "lonely"
  assert(events._lean(s, "acompana", 12) == 0 and events._lean(s, "se_revuelca", 12) == 0)
  s.mood = "playful"
  assert(close(events._lean(s, "acompana", 12), 1.0) and events._lean(s, "baila", 12) == 1.0)
  s.energy = 59.0
  assert(events._lean(s, "baila", 12) == 0)
  assert(events._lean(s, "nada", 12) == 0)
end

do -- a whim only when she needs nothing, two a day at most (WhimTest)
  local function whim_pet() return pet({hunger = 70.0, affection = 70.0, energy = 70.0, health = 90.0}) end
  assert(events._lean(whim_pet(), "capricho", 12) > 0)
  for _, fv in ipairs({{"hunger", 59.0}, {"affection", 59.0}, {"energy", 59.0}, {"health", 79.0},
                       {"dirt", 41.0}, {"mood", "sad"}}) do
    local s = whim_pet()
    s[fv[1]] = fv[2]
    assert(events._lean(s, "capricho", 12) == 0, fv[1])
  end
  for _, c in ipairs({{0, 1, true}, {1, 1, false}, {0, 2, false}, {2, 0, false}}) do
    local s = whim_pet()
    s.memory.day.whim_yes, s.memory.day.whim_no = c[1], c[2]
    assert((events._lean(s, "capricho", 12) > 0) == c[3])
  end
  local s = whim_pet()
  s.personality = {pampered = 0.9}
  assert(close(events._lean(s, "capricho", 12), 1.4))               -- a spoilt cat asks more
  events.happen(s, "capricho", 1000)
  assert(s.mode == "ask" and s.ask == "whim" and s.ask_until == 100000 + 900 and s.sound == "capricho")
end

do -- an old memory comes back, more near the end
  local s = pet({day = 20})
  s.memory.first = {play = 18}
  assert(events._weight(s, "recuerdo") == 0)                        -- too recent to recall
  s.memory.first = {play = 3}
  local before = events._weight(s, "recuerdo")
  assert(before > 0)
  s.farewell_scheduled_day = 21
  assert(events._weight(s, "recuerdo") > before)
end

do -- secrets: a special answer to your routine, a night owl at the moon
  local s = pet({hour = 21})
  s.memory.hours[22] = 9                                            -- her usual hour: 21
  s.last_input_ts = s.clock.t - 60
  assert(events._weight(s, "ritual", 21) > 0)
  assert(events._weight(s, "ritual", 15) == 0)                      -- not her hour
  s.last_input_ts = s.clock.t - 3600
  assert(events._weight(s, "ritual", 21) == 0)
  s = pet({hour = 21, personality = {rhythm = 0.8}})
  assert(events._weight(s, "luna", 21) > 0 and events._weight(s, "luna", 12) == 0)
  s.personality = {rhythm = 0.3}
  assert(events._weight(s, "luna", 21) == 0)
end

do -- she waits for you at your usual hour, and the hour before
  local s = pet()
  s.memory.hours[22] = 9
  assert(events._lean(s, "espera", 21) == 1.0 and events._lean(s, "espera", 20) == 1.0)
  assert(events._lean(s, "espera", 12) == 0)
  s.memory.hours = zeros(24)
  s.memory.hours[1] = 9                                             -- at midnight: 23 too
  assert(events._lean(s, "espera", 23) == 1.0 and events._lean(s, "espera", 0) == 1.0)
  for hour, expect in pairs({[20] = true, [21] = true, [12] = false}) do
    local p = pet({hour = hour})
    p.memory.hours[22] = 9
    math.randomseed(1)
    local seen = false
    for _ = 1, 400 do if events.direct(p, 1000) == "espera" then seen = true end end
    assert(seen == expect, hour)
  end
end

do -- what earlier lives left, and the last one's gesture
  local function inherit(legacy, scene)
    local s = pet({cycle = 2, current_scene = scene or 0})
    for _, it in ipairs(legacy or {}) do s.legacy[#s.legacy + 1] = {cycle = 1, name = "Audrey", item = it} end
    return s
  end
  assert(events._weight(inherit({"juguete"}), "mira_legado") > 0)
  assert(events._weight(inherit(), "mira_legado") == 0)                       -- nothing left
  assert(events._weight(inherit({"juguete"}, 1), "mira_legado") == 0)         -- not here
  assert(events._weight(inherit({"juguete"}, 5), "mira_legado") > 0)          -- 5 % 5: the living room
  assert(events._weight(inherit({"estrella"}), "mira_legado") > events._weight(inherit({"juguete"}), "mira_legado"))
  assert(events._weight(inherit({"juguete"}), "herencia") > 0 and events._weight(inherit(), "herencia") == 0)
  local same = pet({cycle = 1, legacy = {{cycle = 1, item = "juguete"}}})     -- this life's own: not earlier
  assert(events._weight(same, "mira_legado") == 0 and events._weight(same, "herencia") == 0)
end

do -- her stars, of an evening
  local s = pet({hour = 21})
  assert(events._weight(s, "mira_estrella", 21) == 0)                         -- no star yet
  s.stars = 1
  local before = events._weight(s, "mira_estrella", 21)
  assert(before > 0)
  s.farewell_scheduled_day = 41
  assert(events._weight(s, "mira_estrella", 21) > before)                     -- more, near the end
  events.happen(s, "mira_estrella", 1000)
  assert(s.memory.first.stars == 1 and s._ev_last_big == s._ev_min and #s._ev_ring == 1)
end

do -- the sparrow: only by day, in a room with a window, and dry
  local s = pet({month = 10, mday = 10, hour = 10, stress = 40.0})
  assert(events._weight(s, "pajaro", 10) > 0)
  assert(close(events._lean(s, "pajaro", 10), 1.5) and close(events._lean(s, "pajaro", 13), 1.0))
  assert(events._weight(pet({current_scene = 1}), "pajaro", 10) == 0)          -- the kitchen
  assert(events._weight(pet({current_scene = 3}), "pajaro", 10) > 0)           -- the studio
  assert(events._weight(pet({hour = 23}), "pajaro", 23) == 0)                  -- dark outside
  s:set_weather("rain", 12.0, true)
  assert(events._weight(s, "pajaro", 10) == 0)
  s = pet({stress = 40.0})
  events.happen(s, "pajaro", 1000)
  assert(s.bird_until == 26000 and s.sound == "pajaro" and s.stress > 40.0)
  assert(s._ev_ready.pajaro == s._ev_min + 120)                              -- its cooldown
end

do -- her toy: the first find
  local s = pet()
  assert(events._weight(s, "juega_juguete") == 0)
  events.happen(s, "encuentra_objeto", 1000)
  assert(util.contains(LOADED["core.memory"].TOYS, s.memory.toy) and s.memory.first.object == 1)
  assert(s.memory.day.found == 1 and s.affection == 60.0 and s.sound == "encuentra_objeto")   -- it gives nothing
  assert(events._weight(s, "juega_juguete") > 0)
  local toy = s.memory.toy
  events.happen(s, "encuentra_objeto", 2000)
  assert(s.memory.toy == toy and s.memory.day.found == 2)            -- she keeps the first
  s.energy = 29.0
  assert(events._weight(s, "juega_juguete") == 0)
end

do -- asking to play and hiding come through it
  local s = pet()
  events.happen(s, "pide_jugar", 1000)
  assert(s.wants_play == true and s.sound == "pide_jugar" and s.excitement == 49.0 and s._dirty)
  s = pet()
  s.memory.games = {["Quita nudos"] = 6}
  events.happen(s, "pide_jugar", 1000)                               -- asking, she asks for her favourite
  assert(s.PLAY_OPTIONS[s.play_choice + 1] == "Quita nudos" and s.play_choice == 3)
  s = pet()
  math.randomseed(2)
  events.happen(s, "se_esconde", 1000)
  assert(s.hidden == true and s.hidden_scene >= 0 and s.hidden_scene <= 4)
  assert(s.sound == "escondida" and s.last_events[#s.last_events] == "Se esconde")   -- its own sound
  assert(s._ev_prev == "se_esconde" and s._ev_ring[1] == "se_esconde")
  s = pet({hour = 15, energy = 25.0})
  events.happen(s, "se_duerme_sola", 1000)
  assert(s.sleeping == true and s.light_on == true and s.sleep_reason == "siesta" and s.overlay_text == nil)
  s = pet({dirt = 96.0})
  events.happen(s, "ensucia_habitacion", 1000)
  assert(s.dirt == 100.0)
  s = pet()
  s._frame_ms = 1000
  events.happen(s, "mira", 1000)                                     -- she looks at something
  assert(s._looking_until == 7000 and #s._ev_ring == 0 and s._ev_last_big == -1000000)
end

do -- she does not narrate herself
  for _, ev in ipairs(events.EVENT_IDS) do
    local s = pet()
    events.happen(s, ev, 1000)
    assert(s.overlay_text == nil, ev)
  end
end

do -- walking about, she moves to another room, or to hers
  local s = pet()
  events.happen(s, "pasea", 1000)
  assert(s.current_scene ~= 0 and s._ev_ready.pasea == 30)
  math.randomseed(4)
  local landed, wrapped = 0, 0
  for _ = 1, 200 do
    s = pet()
    s.memory.rooms = {0, 0, 0, 900, 0}
    events.happen(s, "pasea", 1000)
    if s.current_scene == 3 then landed = landed + 1 end
    if s.current_scene == 4 then wrapped = wrapped + 1 end
    assert(s.current_scene >= 0 and s.current_scene <= 4)
  end
  assert(landed > 80 and wrapped > 0)                                -- 0 - 1 is the last room
end

do -- a very rare event, once a life
  local once = {}
  for _, ev in ipairs(events.EVENT_IDS) do if events.EVENTS[ev][1] == "very_rare" then once[#once + 1] = ev end end
  assert(#once == 4 and once[1] == "baila")
  local s = pet()
  local before = s.events_once
  events.happen(s, once[1], 1000)
  assert(s.events_once[1] == once[1] and #before == 0)               -- a new list, as the Python's
  s._ev_min, s._ev_last_big, s.mood = 1000000, 0, "happy"
  with_random(0.0, function()
    for _ = 1, 10 do assert(events.pick(s) ~= once[1]) end
  end)
  -- stronger than the Python's (r = 0 is always the common tier): the very rare tier, nothing else in the way
  local fresh = pet({mood = "happy"})
  fresh._ev_min, fresh._ev_last_big = 1000000, 0
  with_random(0.5056, function() assert(events.pick(fresh) == "baila") end)
  events.happen(fresh, "baila", 1000)
  fresh._ev_prev, fresh._ev_ring = nil, {}
  with_random(0.5056, function() assert(events.pick(fresh) == nil) end)
end

do -- later: at most LATER_MAX waiting, each a new list
  local s = pet()
  for i = 1, 6 do events.later(s, 1000 * i + 0.7, "se_acerca") end
  assert(#s._later == 4 and s._later[1][1] == 1000 and s._later[4][2] == "se_acerca")
  local l = s._later
  s._later = {}
  events.later(s, 5, "x")
  assert(#l == 4 and #s._later == 1)
end

do -- the hour comes from the simulated second during a catch-up
  local s = pet({clock = Clock.start({2026, 10, 15}, 12 * 3600)})
  assert(events.hour(s) == 12)
  s._sim_ts = Clock.EPOCH + 3 * 3600 + 59
  assert(events.hour(s) == 3)
  s._sim_ts = 0
  assert(events.hour(s) == 12)
end

do -- able: awake on the main screen, home, not waiting on her cushion
  assert(events.able(pet()) == true)
  for _, kv in ipairs({{"sleeping", true}, {"mode", "status"}, {"hidden", true}, {"sitter_until", 1},
                       {"wants_play", true}, {"deep_sleep", true}, {"powered_off", true}, {"sick", true},
                       {"in_critical", true}, {"_away", true}}) do
    local s = pet()
    s[kv[1]] = kv[2]
    assert(events.able(s) == false, kv[1])
    s._ev_min = 0
    for _ = 1, 300 do assert(events.direct(s, 1000) == nil) end
    assert(s._ev_min == 0)
  end
end

do -- a holiday's moment, once a life: F +10, a first, a sound
  local s = pet({affection = 95.0, day = 3})
  events.celebrate(s, "halloween", 1000)
  assert(s.affection == 100.0 and s.memory.first.halloween == 3 and s.sound == "fiesta")
  assert(s.last_events[#s.last_events] == "Fiesta: halloween")
  s.affection = 50.0
  events.celebrate(s, "halloween", 2000)
  events.celebrate(s, nil, 2000)
  events.celebrate(s, "", 2000)
  assert(s.affection == 50.0 and s.sound_seq == 1)
end

do -- petards scare her on Sant Joan's eve, from 21:00
  for _, c in ipairs({{6, 23, 22, false, true}, {6, 23, 20, false, false}, {6, 24, 22, false, false},
                      {6, 23, 22, true, false}, {6, 23, 21, false, true}}) do
    local s = pet({month = c[1], mday = c[2], hour = c[3], sleeping = c[4], quirks = {"Curiosa"}})
    with_random(0.0, function() events.revetlla(s, 1000) end)
    assert(s.stress == 20.0 + (c[5] and rules.FRIGHT_STRESS or 0.0), c[2] .. " " .. c[3])
    if c[5] then assert(s.sound == "susto" and s.last_events[#s.last_events] == "Un petardo") end
  end
  local s = pet({month = 6, mday = 23, hour = 22})
  with_random(1 / 30, function() events.revetlla(s, 1000) end)        -- not below PETARD_P: none
  assert(s.stress == 20.0)
end

-- the director, minute by minute (EventDirectorTest)
local function run(s, minutes, seed)
  math.randomseed(seed or 7)
  local seen = {}
  for i = 1, minutes do
    local ev = events.direct(s, 1000)
    seen[i] = ev or false
    if ev == "se_esconde" then s.hidden, s.hidden_scene = false, -1 end
    if ev == "pide_jugar" or ev == "ensucia_habitacion" then s.wants_play, s.dirt = false, 20.0 end
    if ev == "se_duerme_sola" then s.sleeping = false end
    if ev == "capricho" then s.mode = "main" end
  end
  return seen
end
local function count_of(seen, v) local n = 0 for _, e in ipairs(seen) do if e == v then n = n + 1 end end return n end
local function tier_of(e) return e and events.EVENTS[e][1] end

do -- nothing is the most frequent, but something small does happen
  local seen = run(pet(), 6000)
  local nothing = count_of(seen, false) / #seen
  assert(nothing > 0.45 and nothing < 0.7, nothing)
end

do -- the budget by rarity
  local minutes = 50000
  local seen = run(pet(), minutes)
  local n = {}
  for _, e in ipairs(seen) do if e then n[tier_of(e)] = (n[tier_of(e)] or 0) + 1 end end
  assert(minutes / 65 < n.uncommon and n.uncommon < minutes / 40, n.uncommon)
  assert(minutes / 700 <= (n.rare or 0) and (n.rare or 0) <= minutes / 300, n.rare)
  for _, ev in ipairs(events.EVENT_IDS) do
    if events.EVENTS[ev][1] == "very_rare" then assert(count_of(seen, ev) <= 1, ev) end
  end
end

do -- never the same twice running; distinctive ones 20 minutes apart
  local seen = run(pet(), 20000)
  local happened, big, at = {}, {}, {}
  for i, e in ipairs(seen) do
    if e then
      happened[#happened + 1] = e
      if tier_of(e) ~= "common" then big[#big + 1] = e; at[#at + 1] = i end
    end
  end
  for i = 2, #happened do assert(happened[i] ~= happened[i - 1]) end
  for i = 2, #big do assert(big[i] ~= big[i - 1]) end              -- not even with a small one in between
  for i = 1, #big - events.RING do
    local window = util.slice(big, i - 1, i - 1 + events.RING)
    for _, e in ipairs(window) do assert(count_of(window, e) <= 4) end
  end
  for i = 2, #at do assert(at[i] - at[i - 1] >= 20) end
end

do -- hours come from the clock: no asking to play at 23:00, yawns in the morning
  local night = run(pet({hour = 23}), 5000)
  assert(count_of(night, "pide_jugar") == 0 and count_of(night, "pasea") == 0)
  local morning = run(pet({hour = 8}), 5000)
  assert(count_of(morning, "bosteza") > 0)
end

do -- tired in the afternoon she naps on her own; she keeps you company when she loves you
  assert(count_of(run(pet({hour = 15, energy = 25.0}), 3000), "se_duerme_sola") > 0)
  assert(count_of(run(pet({hour = 15}), 3000), "se_duerme_sola") == 0)
  assert(count_of(run(pet({affection = 85.0}), 3000), "acompana") > 0)
  assert(count_of(run(pet({affection = 40.0}), 3000), "acompana") == 0)
end

do -- she hides on her own now and then (not a puppy)
  math.randomseed(3)
  local s, hid = pet(), false
  for _ = 1, 3000 do
    if events.direct(s, 1000) == "se_esconde" then hid = true break end
  end
  assert(hid and s.hidden)
  local puppy = run(pet({phase = "Cachorro"}), 5000)
  assert(count_of(puppy, "se_esconde") == 0)
end

do -- Extra breathes: fewer events than a grown cat
  local function nothing(phase)
    local s = pet({phase = phase, affection = 80.0, day = 30})
    s.memory.first = {play = 3}
    return count_of(run(s, 3000, 5), false)
  end
  assert(nothing("Extra") > nothing("Adulto"))
end

-- ===================================================================================== v2_gameplay

do -- her favourite and disliked food: the Python's own numbers (a deterministic seed, no hash())
  local want = { -- name, quirks, seed, favourite, disliked (from the Python, 2026-10-15)
    {"Audrey", {"Curiosa", "Dormilona"}, 35563, "Yogurt", "Chuches"},
    {"Audrey", {"Curiosa", "Glotona"}, 30217, "Yogurt", "Latas"},
    {"Audrey", {"Curiosa", "Huidiza"}, 30094, "Sandia", "Yogurt"},
    {"Audrey", {"Dormilona", "Glotona"}, 35400, "Chuches", "Latas"},
    {"Audrey", {"Dormilona", "Huidiza"}, 35265, "Pienso", "Sandia"},
    {"Audrey", {"Glotona", "Huidiza"}, 30067, "Yogurt", "Latas"},
    {"Audrey", {"Curiosa", "Dormilona", "Glotona"}, 59277, "Chuches", "Latas"},
    {"Audrey", {"Curiosa", "Glotona", "Huidiza"}, 52224, "Chuches", "Chuches"},   -- the Python bug, kept
    {"Luna", {"Curiosa", "Dormilona"}, 30305, "Pienso", "Latas"},
    {"Luna", {"Dormilona", "Glotona"}, 30146, "Sandia", "Sandia"},
    {"Luna", {"Curiosa", "Dormilona", "Huidiza"}, 52312, "Latas", "Pienso"},
    {"Ñoña", {"Curiosa", "Dormilona"}, 30819, "Sandia", "Yogurt"},
    {"Ñoña", {"Dormilona", "Huidiza"}, 30537, "Latas", "Pienso"},
    {"Ñoña", {"Dormilona", "Glotona", "Huidiza"}, 52667, "Sandia", "Yogurt"},
  }
  for _, c in ipairs(want) do
    local s = pet({name = c[1], quirks = util.shuffle(util.copy(c[2]))})   -- sorted: the order does not matter
    assert(v2._stable_seed(s) == c[3], c[1] .. " " .. v2._stable_seed(s))
    v2.init_v2_state(s)
    assert(s.favorite_food == c[4] and s.disliked_food == c[5], c[1] .. ": " .. s.favorite_food .. "/" .. s.disliked_food)
    assert(s.favorite_food ~= "Leche" and util.contains(s.FOOD_OPTIONS, s.favorite_food))
  end
  local s = pet({name = "Audrey", quirks = {"Curiosa", "Dormilona"}, cycle = 2})
  v2.refresh_food_preferences(s)
  assert(v2._stable_seed(s) ~= 35563)                                -- a new life, maybe new tastes
  -- seasonal food keeps her favourite: the date plays no part
  s = pet({month = 10, mday = 5})
  v2.refresh_food_preferences(s)
  local fav, dis = s.favorite_food, s.disliked_food
  s.clock.month, s.clock.day = 10, 29
  v2.refresh_food_preferences(s)
  assert(s.favorite_food == fav and s.disliked_food == dis)
end

do -- indigestion from too many snacks (hunger above 68, three in a row, a 0.45 chance)
  local s = pet({hunger = 85.0})
  with_random(0.0, function()
    v2.register_feed_outcome(s, 1000, "Chuches", "Snack")
    v2.register_feed_outcome(s, 2000, "Yogurt", "Snack")
    assert(not s.sick)
    v2.register_feed_outcome(s, 3000, "Sandia", "Snack")
  end)
  assert(s.sick == true and s.sick_type == "indigestion" and s.sick_cause == "exceso_snacks")
  assert(s.indigestion_until_ms == 3000 + v2.INDIGESTION_MS and s.overlay_text == "Ay, mi barriguita")
  v2.register_feed_outcome(s, 3000, "Chuches", "Snack")              -- a snack while it hurts: +20 min
  assert(s.indigestion_until_ms == 3000 + v2.INDIGESTION_MS)         -- the later of the two
  v2.register_feed_outcome(s, 3000 + 40 * 60000, "Chuches", "Snack")
  assert(s.indigestion_until_ms == 3000 + 40 * 60000 + v2.INDIGESTION_SNACK_MS)
  s = pet({hunger = 68.0})
  with_random(0.0, function() for t = 1, 5 do v2.register_feed_outcome(s, t, "Chuches", "Snack") end end)
  assert(not s.sick and s._snack_streak == 5)
  with_random(0.0, function() for t = 1, 5 do v2.register_feed_outcome(s, t, "Chuches", "Snack") end end)
  assert(s._snack_streak == 6)                                       -- capped
  v2.register_feed_outcome(s, 1, "Latas", "Comida")
  v2.register_feed_outcome(s, 1, "Latas", nil)
  assert(s._snack_streak == 4)
  s = pet({hunger = 85.0, _snack_streak = 2})
  with_random(0.45, function() v2.register_feed_outcome(s, 1, "Chuches", "Snack") end)
  assert(not s.sick)                                                 -- not below 0.45
end

do -- falling ill
  local s = pet()
  v2.start_illness(s, "  Resfriado ", 500, nil)
  assert(s.sick and s.sick_type == "resfriado" and s.sick_cause == "" and s.sick_since_ms == 500)
  assert(s.sound == "enferma" and s.memory.first.sick == 1 and s._med_doses == 0)
  assert(s.overlay_text == "¡Achís! Me resfrié" and s.overlay_until == 1700)
  assert(s.last_events[#s.last_events] == "Enfermedad: resfriado" and s.indigestion_until_ms == 0)
  s = pet({mode = "status"})
  v2.start_illness(s, "estres", 0, "test")
  assert(s.sick and s.overlay_text == nil)                           -- not on the main screen: no text
  s = pet()
  v2.start_illness(s, "gripe", 0, "test")
  v2.start_illness(s, nil, 0, "test")
  assert(not s.sick and s.sound == nil)
end

do -- the illness she has, when the save lost it
  assert(v2.infer_illness_type(pet({energy = 9.0, stress = 90.0})) == "agotamiento")
  assert(v2.infer_illness_type(pet({stress = 76.0})) == "estres")
  assert(v2.infer_illness_type(pet({dirt = 66.0, energy = 34.0})) == "resfriado")
  assert(v2.infer_illness_type(pet()) == "indigestion")
  local s = pet({sick = true})
  v2.restore_v2_state_after_load(s)
  assert(util.contains({"resfriado", "indigestion", "estres", "agotamiento"}, s.sick_type))
  s = pet({sick = true, sick_type = "  "})
  v2.restore_v2_state_after_load(s)
  assert(s.sick_type == "indigestion")
  s = pet({sick = false, sick_type = "estres", sick_cause = "x", sick_since_ms = 9})
  s.favorite_food, s.sick_cause, s._snack_streak = nil, nil, nil
  v2.restore_v2_state_after_load(s)
  assert(s.sick_type == nil and s.sick_cause == "" and s.sick_since_ms == 0 and s._snack_streak == 0)
  assert(s.favorite_food ~= nil and s.favorite_food ~= "")
end

do -- V2 timers run on real time: a cold needs hours of sleep, not seconds
  local now = 1000000
  local s = pet()
  v2.start_illness(s, "resfriado", now, "test")
  v2.apply_illness_symptoms(s, now + 41000, false, true)
  assert(s.sick)
  v2.apply_illness_symptoms(s, now + 2 * v2.HOUR_MS + 1000, false, true)
  assert(not s.sick and s.sick_type == nil and s.last_events[#s.last_events] == "Curada: resfriado (descanso)")
  s = pet()                                                          -- awake, it does not clear
  v2.start_illness(s, "resfriado", now, "test")
  v2.apply_illness_symptoms(s, now + 3 * v2.HOUR_MS, true, false)
  assert(s.sick and s.energy < 70.0 and s.health < 90.0)
end

do -- indigestion lasts about 45 minutes
  local now = 1000000
  local s = pet()
  v2.start_illness(s, "indigestion", now, "test")
  s.energy = 80.0
  v2.apply_illness_symptoms(s, now + 30 * v2.MINUTE_MS, true, false)
  assert(s.sick)
  v2.apply_illness_symptoms(s, now + 46 * v2.MINUTE_MS, true, false)
  assert(not s.sick and s.indigestion_until_ms == 0)
  s = pet({energy = 30.0})                                           -- tired and awake: it waits
  v2.start_illness(s, "indigestion", now, "test")
  v2.apply_illness_symptoms(s, now + 46 * v2.MINUTE_MS, true, false)
  assert(s.sick)
  v2.apply_illness_symptoms(s, now + 47 * v2.MINUTE_MS, false, true)  -- asleep: gone
  assert(not s.sick)
end

do -- the stress illness counts per hour
  local s = pet()
  v2.start_illness(s, "estres", 1000000, "test")
  s.stress, s.affection = 60.0, 20.0                                 -- keeps it from curing itself
  for second = 0, 3599 do v2.apply_illness_symptoms(s, 1000000 + second * 1000, true, false) end
  assert(math.abs(s.stress - 66.0) <= 0.5, s.stress)
  s.stress, s.affection = 44.0, 56.0
  v2.apply_illness_symptoms(s, 9000000, true, false)
  assert(not s.sick)                                                 -- calm and loved: cured
end

do -- exhaustion: awake it wears her, asleep above 52 it clears
  local s = pet()
  v2.start_illness(s, "agotamiento", 0, "test")
  v2.apply_illness_symptoms(s, 1000, false, false)
  assert(s.energy == 70.0 and s.health == 90.0)
  v2.apply_illness_symptoms(s, 1000, true, false)
  assert(s.energy < 70.0 and s.sick)
  v2.apply_illness_symptoms(s, 2000, false, true)
  assert(not s.sick)
  s = pet({sick = true, sick_type = nil, energy = 5.0})              -- no type: inferred and kept
  v2.apply_illness_symptoms(s, 1000, true, false)
  assert(s.sick_type == "agotamiento")
end

do -- what may make her ill, each minute (random patched to 0)
  local cases = {
    {{energy = 5.0}, true, "agotamiento", "energia_baja_sostenida"},
    {{energy = 5.0}, false, nil},                                    -- asleep: not exhaustion
    {{stress = 80.0, affection = 30.0}, true, "estres", "estres_alto"},
    {{energy = 30.0, dirt = 70.0}, true, "resfriado", "suciedad_y_frio"},
    {{energy = 5.0, dirt = 70.0, stress = 80.0, affection = 30.0}, true, "agotamiento"},   -- first
    {{}, true, nil},
  }
  for _, c in ipairs(cases) do
    local s = pet(c[1])
    with_random(0.0, function() v2.maybe_trigger_illness(s, 1000, c[2]) end)
    assert(s.sick_type == c[3], tostring(c[3]))
    if c[4] then assert(s.sick_cause == c[4]) end
  end
  local s = pet({energy = 5.0})
  with_random(0.0071, function() v2.maybe_trigger_illness(s, 1000, true) end)   -- p = 0.004 + 0.003 * 0.5
  assert(not s.sick)
  s = pet({sick = true, sick_type = "estres", energy = 5.0})
  with_random(0.0, function() v2.maybe_trigger_illness(s, 1000, true) end)
  assert(s.sick_type == "estres")                                    -- already ill: nothing new
end

do -- medicine cures every illness in two doses at most; a cold in one
  local s = pet({sick = true, sick_type = "resfriado", health = 48.0})
  local r = v2.apply_medicine(s, 1)
  assert(r.applied and r.cured and r.message == "¡Adiós, mocos!")
  assert(not s.sick and s.sick_type == nil and s.health >= 56.0 and s._med_doses == 0)
  for _, ill in ipairs({"indigestion", "estres", "agotamiento"}) do
    s = pet({stress = 95.0, energy = 5.0})                           -- not better on its own after one dose
    v2.start_illness(s, ill, 0, "test")
    r = v2.apply_medicine(s, 1000)
    assert(s.sick and r.applied and not r.cured and r.message == v2.NEXT_DOSE[ill], ill)
    r = v2.apply_medicine(s, 3000)
    assert(not s.sick and r.cured and r.message == v2.CURED[ill], ill)
  end
  s = pet({stress = 60.0})                                            -- better at once: one dose
  v2.start_illness(s, "estres", 0, "test")
  assert(v2.apply_medicine(s, 1000).cured and s.stress == 36.0)
  s = pet({energy = 30.0})
  v2.start_illness(s, "agotamiento", 0, "test")
  assert(v2.apply_medicine(s, 1000).cured)
  s = pet()
  v2.start_illness(s, "indigestion", 0, "test")
  v2.apply_medicine(s, 1000)
  assert(s.indigestion_until_ms == math.max(1000 + 20 * 60000, 45 * 60000 - 15 * 60000))
  r = v2.apply_medicine(pet({health = 60.0}), 1000)
  assert(not r.applied and not r.cured and r.message == "¡Estoy como una rosa!")
  v2.cure_illness(s, 1)                                               -- not sick: nothing
  assert(not s.sick)
  s = pet({sick = true, sick_type = "estres"})
  v2.cure_illness(s, 1)
  assert(s.last_events[#s.last_events] == "Curada: estres (recuperacion)")
end

print("ok f")
