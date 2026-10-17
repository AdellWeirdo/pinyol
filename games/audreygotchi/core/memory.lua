-- memory: her memory and how she learns who she is, Character Bible §5, §8-§9, §48
-- (a port of audreygotchi/core/memory.py).
--
-- Kept small, all plain data for the save:
-- - day: today's tally of what you did together; at the game day's turn it becomes yesterday (recent memory,
--   §9.1) and teaches her temperament (§5), at most LEARN_MAX an axis a day.
-- - day_hours: when you were with her today; hours: the same, fading day by day (habits, §9.2). Index h + 1
--   holds hour h.
-- - first: the cycle's firsts, by game day (important memories, §9.3).
local util = require("core.util")
local HOLIDAYS = require("core.weather").HOLIDAYS
local M = {}

M.LEARN_MAX = 0.03 -- the owner's yes: an axis moves at most this much a day
M.LEARN_RATE = 0.12 -- each day an axis goes this share of the way to what the day says
M.HOURS_KEEP = 0.8 -- habit memory: yesterday's hours weigh this much in the next day's
M.HABIT_MIN = 5 -- her fading count at one hour for it to be a habit (about two days)
M.HABIT_SHARE = 0.3 -- and that hour holds at least this share of all her hours with you
M.RECALL_AFTER_DAYS = 7 -- a first comes back as a memory once it is this old
M.TOYS = {"pelota", "raton", "pluma", "tapon", "cinta"} -- what her first find may be: her toy
M.DREAMS = {"comida", "juego", "objeto", "nieve", "estrella", "juguete", "legado", "fiesta", "mimos"}
M.DREAM_SEC = 1800 -- asleep, the dream changes every half hour; one in three, none
M.FAV_GAME_MIN = 5 -- games started for a clear favourite (Bible §7)
M.FAV_ROOM_MIN = 600 -- awake minutes in a room for it to be hers, and a share of them:
M.FAV_ROOM_SHARE = 0.35
M.TALLY = {"cuddle", "play", "feed", "bath", "found", "friend", "refused", "refused_food", "refused_cuddle",
           "alone_min", "whim_yes", "whim_no"}
-- an interaction's name (its first word) to what she remembers of it
local KIND = {Mimos = "cuddle", Cuddle = "cuddle", Juego = "play", Alimentar = "feed", ["Baño"] = "bath"}
local REFUSED = {feed = "refused_food", cuddle = "refused_cuddle"}

local function tally()
  local d = {}
  for _, k in ipairs(M.TALLY) do d[k] = 0 end
  return d
end

local function zeros(n)
  local l = {}
  for i = 1, n do l[i] = 0 end
  return l
end

function M.fresh()
  return {day = tally(), yesterday = tally(),
          day_hours = zeros(24), hours = zeros(24), first = {}, at_day = 1,
          games = {}, rooms = {}, toy = nil, friends = {}, stars = {}, stickers = {},
          animals = {}}
end

-- max(0, int(v)), 0 for what int() cannot take
function M.count(v)
  if type(v) == "boolean" then return v and 1 or 0 end
  if type(v) == "string" then
    local digits = v:match("^%s*([+-]?%d+)%s*$") -- int("12"); int("1.5") and int("x") fail
    v = digits and tonumber(digits) or nil
  end
  if type(v) ~= "number" or v ~= v or v == math.huge or v == -math.huge then return 0 end
  return math.max(0, util.int(v))
end

local function first_n_keys(t, n) -- list(d.items())[:n]: Lua tables keep no order, so by sorted keys
  return util.slice(util.keys(t), 0, n)
end

-- A saved memory, field by field; anything missing or malformed (it is flash data) starts fresh. Without a
-- saved day (an older save) at_day is 0: the next update sets it, taking no day's turn.
function M.restore(raw)
  local mem = M.fresh()
  if type(raw) ~= "table" then
    mem["at_day"] = 0
    return mem
  end
  for _, key in ipairs({"day", "yesterday"}) do
    if type(raw[key]) == "table" then
      for k, v in pairs(raw[key]) do
        if util.contains(M.TALLY, k) then mem[key][k] = M.count(v) end
      end
    end
  end
  for _, key in ipairs({"day_hours", "hours"}) do
    if type(raw[key]) == "table" and #raw[key] == 24 then
      local l = {}
      for i = 1, 24 do l[i] = M.count(raw[key][i]) end
      mem[key] = l
    end
  end
  if type(raw["first"]) == "table" then
    for _, k in ipairs(first_n_keys(raw["first"], 64)) do
      local v = raw["first"][k]
      if M.count(v) >= 1 then
        mem["first"][tostring(k)] = M.count(v)
      end
    end
  end
  if type(raw["games"]) == "table" then
    local g = {}
    for _, k in ipairs(first_n_keys(raw["games"], 16)) do g[tostring(k)] = M.count(raw["games"][k]) end
    mem["games"] = g
  end
  if type(raw["stars"]) == "table" then -- each game's best, 0-3 stars
    local st = {}
    for _, k in ipairs(first_n_keys(raw["stars"], 16)) do st[tostring(k)] = math.min(3, M.count(raw["stars"][k])) end
    mem["stars"] = st
  end
  if type(raw["stickers"]) == "table" then -- her album, in the order earned
    local l = {}
    for _, v in ipairs(util.slice(raw["stickers"], 0, 32)) do
      if type(v) == "string" then l[#l + 1] = v end
    end
    mem["stickers"] = l
  end
  if type(raw["rooms"]) == "table" then
    local l = {}
    for _, v in ipairs(util.slice(raw["rooms"], 0, 16)) do l[#l + 1] = M.count(v) end
    mem["rooms"] = l
  end
  mem["at_day"] = M.count(util.get(raw, "at_day", 0))
  if util.contains(M.TOYS, raw["toy"]) then mem["toy"] = raw["toy"] else mem["toy"] = nil end
  return mem
end

function M.remember(s, kind, n)
  if n == nil then n = 1 end
  s.memory["day"][kind] = util.int(util.get(s.memory["day"], kind, 0)) + n
end

-- An important first of the cycle: kept with its day, never overwritten.
function M.first(s, what)
  if s.memory["first"][what] == nil then
    s.memory["first"][what] = util.int(s.day)
  end
end

local function strip(x) return (x:match("^%s*(.-)%s*$")) end

-- What she remembers of an interaction: its kind, refused or not, and its hour.
function M.interaction(s, action, ok)
  local events = require("core.events") -- here: events reads her memory
  local a = tostring(action)
  local colon = string.find(a, ":", 1, true)
  local word = strip(colon and a:sub(1, colon - 1) or a)
  local kind = KIND[word]
  if not ok then
    M.remember(s, util.get(REFUSED, kind, "refused"))
    return
  end
  local h = events.hour(s) + 1
  s.memory["day_hours"][h] = s.memory["day_hours"][h] + 1
  if kind then
    M.remember(s, kind)
    M.first(s, kind)
  end
end

-- The hour (0-23) you are usually with her (Bible §9.2), or nil while there is none.
function M.habit_hour(s)
  local hours = s.memory["hours"]
  local best = 0
  for h = 1, 23 do
    if hours[h + 1] > hours[best + 1] then best = h end -- the first of the highest, as max()
  end
  if hours[best + 1] >= M.HABIT_MIN and hours[best + 1] >= M.HABIT_SHARE * util.sum(hours) then
    return best
  end
  return nil
end

function M.game_started(s, game)
  local games = s.memory["games"]
  games[game] = util.int(util.get(games, game, 0)) + 1
end

-- Her favourite game (Bible §7): the one played most, once clearly so; else nil.
function M.fav_game(s)
  local games = s.memory["games"]
  if next(games) == nil then
    return nil
  end
  -- a tie at the top gives nil below, so which of the tied is `best` does not matter (Python: dict order)
  local names = util.keys(games)
  local best = names[1]
  for i = 2, #names do
    if games[names[i]] > games[best] then best = names[i] end
  end
  local ties = 0
  for _, g in ipairs(names) do
    if games[g] == games[best] then ties = ties + 1 end
  end
  if games[best] < M.FAV_GAME_MIN or ties > 1 then
    return nil
  end
  return best
end

function M.room_minute(s)
  local rooms = s.memory["rooms"]
  local i = util.int(s.current_scene)
  while #rooms <= i do
    rooms[#rooms + 1] = 0
  end
  local j = i >= 0 and i + 1 or #rooms + i + 1 -- rooms[i], Python's negative index included
  rooms[j] = rooms[j] + 1
end

-- The room she spends her awake time in, once clearly so; its 0-based index, else nil.
function M.fav_room(s)
  local rooms = util.slice(s.memory["rooms"], 0, #s.scenarios) -- saved data: only real rooms
  if #rooms == 0 then
    return nil
  end
  local best = 0
  for i = 1, #rooms - 1 do
    if rooms[i + 1] > rooms[best + 1] then best = i end
  end
  if rooms[best + 1] >= M.FAV_ROOM_MIN and rooms[best + 1] >= M.FAV_ROOM_SHARE * util.sum(rooms) then
    return best
  end
  return nil
end

-- Her favourite time of day, from your usual hour with her.
function M.fav_time(s)
  local h = M.habit_hour(s)
  if h == nil then
    return nil
  end
  if 7 <= h and h < 12 then return "morning" end
  if 12 <= h and h < 20 then return "afternoon" end
  return "evening"
end

local function has_toy(m)
  local toy = m["toy"]
  return toy ~= nil and toy ~= false and toy ~= ""
end

-- Her first find becomes her toy (Bible §24, §33); she keeps that one.
function M.keep_toy(s, found)
  if not has_toy(s.memory) then
    s.memory["toy"] = found
  end
end

-- Asleep: what she dreams of now, from her life, or nil (awake, or a dreamless while).
function M.dream(s)
  if not s.sleeping or s.deep_sleep then
    return nil
  end
  local m = s.memory
  local fiesta = false
  for _, h in ipairs(HOLIDAYS) do
    if m["first"][h] ~= nil then fiesta = true break end
  end
  local candidates = {
    {"comida", m["first"]["favorite"] ~= nil}, {"juego", M.fav_game(s) ~= nil},
    {"objeto", m["first"]["object"] ~= nil}, {"nieve", m["first"]["snow"] ~= nil},
    {"estrella", util.int(s.stars) > 0}, {"juguete", has_toy(m)},
    {"legado", #s.legacy > 0},
    {"fiesta", fiesta},
  }
  local have = {}
  for _, c in ipairs(candidates) do
    if c[2] then have[#have + 1] = c[1] end
  end
  if #have == 0 then have = {"mimos"} end
  local period = util.int(s._nap_sec) // M.DREAM_SEC + util.int(s.day)
  if period % 3 == 2 then -- one stretch in three is dreamless
    return nil
  end
  return have[(period - period // 3) % #have + 1] -- count dreamt stretches only: all come round
end

-- The firsts old enough to come back (Bible §10), by sorted name (Python: in the order they came).
function M.old_memories(s)
  local out = {}
  for _, k in ipairs(util.keys(s.memory["first"])) do
    if util.int(s.day) - util.int(s.memory["first"][k]) >= M.RECALL_AFTER_DAYS then out[#out + 1] = k end
  end
  return out
end

local function clamp(x, lo, hi)
  if x < lo then return lo end
  if x > hi then return hi end
  return x
end

-- Where each axis would settle if every day went like this one (Bible §5.1), between 0.1 and 0.9: no day
-- makes her an extreme. ponytail: feel weights, tune by watching weeks.
function M._targets(day, hours)
  local t = {
    sociability = 0.35 + 0.05 * math.min(day["cuddle"] + day["play"], 8)
                  - math.min(day["alone_min"] / 1200.0, 0.3), -- time alone: her own way
    activity = 0.25 + 0.06 * math.min(day["play"] + day["found"], 10), -- 3 a day: middling
    curiosity = 0.35 + 0.1 * math.min(day["found"], 5),
    affection = 0.35 + 0.08 * math.min(day["cuddle"], 5) - 0.04 * math.min(day["refused_cuddle"], 3),
    food = 0.4 + 0.04 * math.min(day["feed"], 5) - 0.12 * math.min(day["refused_food"], 3),
  }
  if day["whim_yes"] + day["whim_no"] ~= 0 then -- her whims: giving in spoils her, a No toughens her
    t["pampered"] = 0.5 + 0.15 * (math.min(day["whim_yes"], 2) - math.min(day["whim_no"], 2))
  end
  local you = util.sum(hours)
  if you ~= 0 then -- the mean hour you were with her: 08:00 an early bird, 22:00 a night owl
    local at = 0
    for i, n in ipairs(hours) do at = at + (i - 1) * n end
    t["rhythm"] = (at / you - 8.0) / 14.0
  end
  local out = {}
  for axis, v in pairs(t) do out[axis] = clamp(v, 0.1, 0.9) end
  return out
end

local WITH_YOU = {"cuddle", "play", "feed", "bath", "refused", "refused_food", "refused_cuddle"}

-- Each axis goes a little of the way towards where the day points, at most LEARN_MAX: the way you live
-- together settles her, and changes her again only slowly. A day without you (or days off) is not neglect
-- (Bible §43): it only says she was on her own, and curious if she found things.
local function learn(s, day, hours)
  local targets = M._targets(day, hours)
  local with_you = util.sum(hours)
  if with_you == 0 then
    for _, k in ipairs(WITH_YOU) do with_you = with_you + day[k] end
  end
  if with_you == 0 then
    local kept = {}
    for a, v in pairs(targets) do
      if a == "sociability" or a == "pampered" or (a == "curiosity" and day["found"] ~= 0) then kept[a] = v end
    end
    targets = kept
  end
  local p = util.copy(s.personality)
  for _, axis in ipairs(util.keys(targets)) do
    local target = targets[axis]
    local now = util.get(p, axis, 0.5) + 0.0
    p[axis] = clamp(now + clamp((target - now) * M.LEARN_RATE, -M.LEARN_MAX, M.LEARN_MAX), 0.0, 1.0)
  end
  s.personality = p
end

-- The game day turned (`days` of them, after days off): today's tally teaches her once and becomes
-- yesterday; after days off yesterday was a day alone, and her hours fade more.
function M.new_day(s, days)
  if days == nil then days = 1 end
  local mem = s.memory
  learn(s, mem["day"], mem["day_hours"])
  local fade = M.HOURS_KEEP ^ (days - 1)
  local hours = {}
  for i = 1, 24 do
    hours[i] = util.int(util.round((util.round(mem["hours"][i] * M.HOURS_KEEP) + mem["day_hours"][i]) * fade))
  end
  mem["hours"] = hours
  if days == 1 then mem["yesterday"] = mem["day"] else mem["yesterday"] = tally() end
  mem["day"] = tally()
  mem["day_hours"] = zeros(24)
  mem["at_day"] = util.int(s.day)
  s:mark_dirty()
end

return M
