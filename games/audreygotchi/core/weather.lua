-- weather: the world outside, the weather report, the season and the holidays from the date (a port of
-- audreygotchi/core/weather.py; Bible §36, §42; the owner's yes 2026-10-05).
--
-- The platform hands in a weather report now and then through GameState:set_weather(kind, temp_c, is_day, sun);
-- kind is one of KINDS, sun the day's sunrise and sunset as minutes of the local day (or nil). What it said counts
-- for WEATHER_STALE_SEC, then nothing does (no report, no weather: she is just at home); its sun times for
-- SUN_STALE_SEC. pinyol has no internet: the front end may feed it a generated report; without one s.weather is
-- nil and everything below behaves as the Python's with no report.
--
-- What it does to her lives where each effect belongs: the events she leans to (core/events.lua) and her mood
-- (core/mood.lua) read the helpers below.
local util = require("core.util")
local M = {}

M.KINDS = {"clear", "cloudy", "fog", "rain", "storm", "snow"}
M.WEATHER_STALE_SEC = 3 * 3600
M.COLD_BELOW, M.HOT_ABOVE, M.WARM_FROM = 8, 28, 15      -- degrees C
M.FIRSTS = {"snow", "storm"}                           -- weather she remembers seeing first
M.SUN_STALE_SEC = 3 * 24 * 3600 -- sunrise moves ~2 min a day: a report's sun holds for days
M.DUSK_MIN = 30                 -- the sky reddens this long before sunset (owner, 2026-10-09)

local function to_int(v) -- Python int() of a handed-in or saved value; nil where Python raises
  if type(v) == "string" then v = tonumber(v) end
  if type(v) ~= "number" or v ~= v or v == math.huge or v == -math.huge then return nil end
  return util.int(v)
end

-- {sunrise, sunset} in minutes of the local day, or nil if they make no sense
function M.sun_times(sun)
  if type(sun) ~= "table" then return nil end
  local rise, down = to_int(sun[1]), to_int(sun[2])
  if rise == nil or down == nil then return nil end
  if 0 <= rise and rise < down and down <= 1440 then return {rise, down} end
  return nil
end

function M.set_weather(s, kind, temp_c, is_day, sun)
  if not util.contains(M.KINDS, kind) then
    return
  end
  local day = not (is_day == nil or is_day == false or is_day == 0) -- bool(is_day)
  s.weather = {kind = kind, temp = util.int(util.round(temp_c + 0.0)), day = day, at = util.int(s.clock:now())}
  sun = M.sun_times(sun)
  if sun ~= nil then
    s.weather.sun = sun
  end
  if util.contains(M.FIRSTS, kind) then
    local first = s.memory.first
    if first[kind] == nil then first[kind] = util.int(s.day) end -- setdefault
  end
  s:mark_dirty()
end

-- the weather while it is fresh, else nil
function M.now(s)
  local w = s.weather
  if w == nil or next(w) == nil then return nil end
  local age = util.int(s.clock:now()) - util.int(util.get(w, "at", 0))
  if not (0 <= age and age <= M.WEATHER_STALE_SEC) then return nil end
  return w
end

-- {sunrise, sunset} from the last report while they hold, else nil
local function _sun(s)
  local w = s.weather
  if w == nil or next(w) == nil then return nil end
  local sun = w.sun
  if sun ~= nil and #sun > 0 then
    local age = util.int(s.clock:now()) - util.int(util.get(w, "at", 0))
    if 0 <= age and age <= M.SUN_STALE_SEC then return sun end
  end
  return nil
end

local function minute_of(s)
  local lt = s.clock:localtime()
  return util.int(lt.tm_hour) * 60 + util.int(util.get(lt, "tm_min", 0))
end

-- the minute of the local day, or nil with a clock that cannot say
local function _minute(s)
  local ok, m = pcall(minute_of, s)
  if ok then return m end
  return nil
end

-- Dark outside: by the clock against the last report's sunrise and sunset while they hold (owner, 2026-10-07:
-- a report from before sunrise kept the rooms at night past it), else the sun down by a fresh report, else the
-- night hours (D-14).
function M.dark(s)
  local sun, minute = _sun(s), _minute(s)
  if sun ~= nil and minute ~= nil then
    return not (sun[1] <= minute and minute < sun[2])
  end
  local w = M.now(s)
  if w ~= nil then return not w.day end
  return s:is_night()
end

-- the last DUSK_MIN minutes before sunset, by the last report's sun times while they hold
function M.dusk(s)
  local sun, minute = _sun(s), _minute(s)
  return sun ~= nil and minute ~= nil and sun[2] - M.DUSK_MIN <= minute and minute < sun[2]
end

function M.kind(s)
  local w = M.now(s)
  if w ~= nil then return w.kind end
  return nil
end

function M.cold(s)
  local w = M.now(s)
  return w ~= nil and w.temp < M.COLD_BELOW
end

function M.hot(s)
  local w = M.now(s)
  return w ~= nil and w.temp > M.HOT_ABOVE
end

function M.sunny(s)
  local w = M.now(s)
  return w ~= nil and w.kind == "clear" and w.day == true and w.temp >= M.WARM_FROM
end

local function date_of(s, ts)
  local lt
  if ts ~= nil and ts ~= 0 then lt = s.clock:localtime(ts) else lt = s.clock:localtime() end
  return {util.int(lt.tm_year), util.int(lt.tm_mon), util.int(lt.tm_mday)}
end

-- {year, month, day} by the local clock (at `ts`, else now), or nil with a clock that cannot say
function M._date(s, ts)
  local ok, d = pcall(date_of, s, ts)
  if ok then return d end
  return nil
end

local SEASONS = {"winter", "winter", "spring", "spring", "spring", "summer", "summer", "summer",
                 "autumn", "autumn", "autumn", "winter"}

function M.season(s)
  local d = M._date(s)
  if d == nil then
    return nil
  end
  return SEASONS[d[2]]
end

M.HOLIDAYS = {"navidad", "halloween", "sant_jordi", "caga_tio", "nochevieja", "reyes", "carnaval", "pascua",
              "sant_joan", "diada"}
-- the days with a holiday of their own (owner, 2026-10-06 and 2026-10-07), keyed month * 100 + day (Python's
-- (month, day)); the Christmas ones fall inside Christmas's window, which keeps its tree and its food (PARENT)
local _DAYS = {[423] = "sant_jordi", [623] = "sant_joan", [624] = "sant_joan", [911] = "diada",
               [1224] = "caga_tio", [1225] = "caga_tio", [1231] = "nochevieja", [105] = "reyes", [106] = "reyes"}
M.PARENT = {caga_tio = "navidad", nochevieja = "navidad", reyes = "navidad"}
local _CUM = {0, 31, 59, 90, 120, 151, 181, 212, 243, 273, 304, 334}

-- Easter Sunday's {month, day}, Gregorian (the anonymous algorithm, Meeus/Jones/Butcher)
function M.easter(year)
  local a, b, c = year % 19, year // 100, year % 100
  local h = (19 * a + b - b // 4 - (b - (b + 8) // 25 + 1) // 3 + 15) % 30
  local l = (32 + 2 * (b % 4) + 2 * (c // 4) - h - c % 4) % 7
  local m = (a + 11 * h + 22 * l) // 451
  local n = h + l - 7 * m + 114
  return {n // 31, n % 31 + 1}
end

local function _yday(year, month, day)
  local leap = year % 4 == 0 and (year % 100 ~= 0 or year % 400 == 0)
  return _CUM[month] + day + ((leap and month > 2) and 1 or 0)
end

-- The most particular holiday of a date: a day of its own, then a moveable one, then a window. A day first keeps
-- Sant Jordi's rose when Easter Monday falls on 23 April.
function M._holiday(d)
  if d == nil or #d == 0 then
    return nil
  end
  local year, month, day = d[1], d[2], d[3]
  local own = _DAYS[month * 100 + day]
  if own ~= nil then
    return own
  end
  local e_md = M.easter(year)
  local t, e = _yday(year, month, day), _yday(year, e_md[1], e_md[2])
  if e - 52 <= t and t <= e - 47 then -- Carnaval: Dijous Gras to its Tuesday
    return "carnaval"
  end
  if e <= t and t <= e + 1 then       -- Pascua: Sunday and Monday, the Mona's day
    return "pascua"
  end
  if (month == 12 and day >= 15) or (month == 1 and day <= 6) then
    return "navidad"
  end
  if month == 10 and day >= 25 then
    return "halloween"
  end
  return nil
end

-- The holiday at `ts` (else now), or nil; kept for its minute, since a snapshot asks several times and a board's
-- localtime costs ~0.6 ms.
function M.holiday(s, ts)
  local at = ts
  if at == nil or at == 0 then at = s.clock:now() end
  local minute = util.int(at) // 60
  local memo = s._holiday_memo
  if memo ~= nil and memo[1] == minute then
    return memo[2]
  end
  s._holiday_memo = {minute, M._holiday(M._date(s, ts))} -- transient: {minute, holiday or nil}
  return s._holiday_memo[2]
end

return M
