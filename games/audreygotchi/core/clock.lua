-- clock: the game's own wall clock. pinyol has no clock that survives the console being off, so the player says
-- the date and the hour when a game starts (as Pokémon Gold did) and time goes on only while the game runs, faster
-- than real time (the front end calls advance). Seconds count from 30 days before that first midnight: the core
-- reads a time of 0 as "never" (the board's clock read the Unix epoch, so 0 was long ago), and 30 days keeps every
-- such rule right while the numbers stay small (exact in 32-bit floats for months of play). Same methods as the
-- board game's core/clock.py: now(), now_ms(), localtime(ts), local_hour().
local Clock = {}
Clock.__index = Clock

local CUM = {0, 31, 59, 90, 120, 151, 181, 212, 243, 273, 304, 334}

local function leap(y) return (y % 4 == 0 and y % 100 ~= 0) or y % 400 == 0 end

local function days_from_civil(y, m, d) -- days since 1970-01-01 (Howard Hinnant's)
  y = m <= 2 and y - 1 or y
  local era = (y >= 0 and y or y - 399) // 400
  local yoe = y - era * 400
  local doy = (153 * (m + (m > 2 and -3 or 9)) + 2) // 5 + d - 1
  local doe = yoe * 365 + yoe // 4 - yoe // 100 + doy
  return era * 146097 + doe - 719468
end

local function civil_from_days(z)
  z = z + 719468
  local era = (z >= 0 and z or z - 146096) // 146097
  local doe = z - era * 146097
  local yoe = (doe - doe // 1460 + doe // 36524 - doe // 146096) // 365
  local y = yoe + era * 400
  local doy = doe - (365 * yoe + yoe // 4 - yoe // 100)
  local mp = (5 * doy + 2) // 153
  local d = doy - (153 * mp + 2) // 5 + 1
  local m = mp + (mp < 10 and 3 or -9)
  return m <= 2 and y + 1 or y, m, d
end

Clock.EPOCH = 30 * 86400 -- the first midnight, in the clock's seconds

-- base: {year, month, day}, the first midnight; t: the clock's own seconds (as saved)
function Clock.new(base, t)
  return setmetatable({base = base or {2026, 10, 15}, t = t or Clock.EPOCH, ms = 0}, Clock)
end

function Clock.start(base, seconds_into_day) -- a new game's clock: that day, that hour
  return Clock.new(base, Clock.EPOCH + seconds_into_day)
end

function Clock:now() return self.t end
function Clock:now_ms() return self.ms end -- the front end's frame tick
function Clock:advance(sec) self.t = self.t + sec end

function Clock:localtime(ts)
  ts = (ts or self.t) - Clock.EPOCH
  local day = ts // 86400
  local sec = ts - day * 86400
  local z = days_from_civil(self.base[1], self.base[2], self.base[3]) + day
  local y, m, d = civil_from_days(z)
  local yday = CUM[m] + d + ((m > 2 and leap(y)) and 1 or 0)
  return {tm_year = y, tm_mon = m, tm_mday = d, tm_hour = sec // 3600, tm_min = (sec % 3600) // 60,
          tm_sec = sec % 60, tm_yday = yday, tm_wday = (z + 3) % 7} -- Monday 0, as Python's
end

function Clock:local_hour() return self:localtime().tm_hour end

-- self-check (tests/core): 2024-02-29 is a leap day, 1970-01-01 a Thursday
function Clock.self_check()
  local c = Clock.start({2024, 2, 28}, 86400 + 3600 * 5 + 61)
  local lt = c:localtime()
  assert(lt.tm_year == 2024 and lt.tm_mon == 2 and lt.tm_mday == 29 and lt.tm_hour == 5 and lt.tm_min == 1)
  assert(lt.tm_yday == 60, lt.tm_yday)
  assert(Clock.start({1970, 1, 1}, 0):localtime().tm_wday == 3)
  assert(Clock.start({2026, 12, 31}, 86400):localtime().tm_year == 2027)
  return true
end

return Clock
