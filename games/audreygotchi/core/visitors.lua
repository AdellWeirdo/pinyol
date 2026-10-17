-- visitors: animal friends who drop by on their own (a port of audreygotchi/core/visitors.py).
-- (the owner, 2026-10-08): with one board there is no other Audreygotchi to meet (friends.py), so seven kawaii
-- animals come instead, now and then.
-- - about once every three days (GAP_MIN_SEC to GAP_MAX_SEC apart), the first a day or so in;
-- - by day (HOURS), while she is awake, well, at home and on the main screen, and while someone is there to see it
--   (a button in the last OWNER_NEAR_SEC); else the visit waits, it is never lost;
-- - the ones she has not met come first, in a random order; then any but the last one;
-- - each visit shows for SHOW_MS and makes her glad (JOY); each friend brings its own gift (GIFTS, the owner,
--   2026-10-08: seen handed over): a toy becomes hers if she has none, the rest more joy (GIFT_JOY); her memory
--   keeps who came and how often ("animals"), and her first friend is a first (the album's "amigo").
-- A new life starts with none met.
local util = require("core.util")
local memory = require("core.memory")
local asks = require("core.asks")
local events = require("core.events")
local M = {}

M.ANIMALS = {"conejita", "patito", "hamster", "zorrito", "panda", "iguana", "mapache"}
M.NAMES = {conejita = "Conejita", patito = "Patito", hamster = "Hámster", zorrito = "Zorrito",
           panda = "Panda", iguana = "Iguana", mapache = "Mapache"}
M.GIFTS = {conejita = "zanahoria", patito = "pluma", hamster = "pipa", zorrito = "uvas",
           panda = "bambu", iguana = "hibisco", mapache = "tapon"} -- each its own; the fox's, the fable's
M.GIFT_NAMES = {zanahoria = "una zanahoria", pluma = "una pluma", pipa = "una pipa",
                uvas = "uvas", bambu = "bambú", hibisco = "un hibisco", tapon = "un tapón brillante"}
M.GAP_MIN_SEC, M.GAP_MAX_SEC = 60 * 3600, 84 * 3600 -- two and a half to three and a half days
M.FIRST_MIN_SEC, M.FIRST_MAX_SEC = 20 * 3600, 36 * 3600
M.HOURS = {10, 20}
M.OWNER_NEAR_SEC = 120
M.SHOW_MS = 30000
M.JOY, M.GIFT_JOY = 8.0, 4.0

-- Saved visits, field by field (flash data): {animal = visits}, known animals only.
function M.restore(raw)
  if type(raw) ~= "table" then
    return {}
  end
  local out = {}
  for _, a in ipairs(M.ANIMALS) do
    if raw[a] ~= nil and memory.count(raw[a]) >= 1 then out[a] = memory.count(raw[a]) end
  end
  return out
end

local function _can_visit(s, now)
  if s.sleeping or s.deep_sleep or s.powered_off or s.hidden then
    return false
  end
  if util.int(s.sitter_until) ~= 0 or s.sick or s.in_critical or s.mode ~= "main" then
    return false
  end
  local fv = s.friend_visit
  if (fv ~= nil and fv ~= "") and util.int(s.friend_until) > util.int(s._frame_ms) then -- a board's friend is here
    return false
  end
  local h = events.hour(s)
  if not (M.HOURS[1] <= h and h < M.HOURS[2]) then
    return false
  end
  local d = now - util.int(s.last_input_ts)
  return 0 <= d and d <= M.OWNER_NEAR_SEC
end

local function _pick(s)
  local met = s.memory.animals
  local new = {}
  for _, a in ipairs(M.ANIMALS) do
    if met[a] == nil then new[#new + 1] = a end
  end
  if #new == 0 then
    for _, a in ipairs(M.ANIMALS) do
      if a ~= s.visitor then new[#new + 1] = a end
    end
  end
  return util.choice(new)
end

-- Each simulated minute: a friend comes when one is due and someone is there to see.
function M.minute(s)
  local now = asks.now(s)
  local due = util.int(s.visitor_next)
  if due == 0 or due - now > M.GAP_MAX_SEC then -- never set, or a clock that ran back
    local lo, hi = M.GAP_MIN_SEC, M.GAP_MAX_SEC
    if due == 0 then lo, hi = M.FIRST_MIN_SEC, M.FIRST_MAX_SEC end
    s.visitor_next = now + math.random(lo, hi)
    return
  end
  if now >= due and _can_visit(s, now) then
    M.visit(s, _pick(s), now)
  end
end

function M.visit(s, animal, now)
  local met = s.memory.animals
  met[animal] = util.get(met, animal, 0) + 1
  s.visitor, s.visitor_until = animal, util.int(s._frame_ms) + M.SHOW_MS
  s.visitor_next = now + math.random(M.GAP_MIN_SEC, M.GAP_MAX_SEC)
  memory.first(s, "friend")
  local gift, joy = M.GIFTS[animal], M.JOY
  local toy = s.memory.toy
  if util.contains(memory.TOYS, gift) and (toy == nil or toy == false or toy == "") then
    memory.keep_toy(s, gift) -- her first toy, a friend's gift
  else
    joy = joy + M.GIFT_JOY
  end
  s.affection = s:_clamp_stat(s.affection + joy)
  s:_emit_sound("amigo")
  s:_log_event(M.NAMES[animal] .. " le trae " .. M.GIFT_NAMES[gift])
  s:compute_mood()
  s:mark_dirty()
end

-- The animal on screen now, or nil.
function M.visiting(s)
  local left = util.int(s.visitor_until) - util.int(s._frame_ms)
  if (s.visitor ~= nil and s.visitor ~= "") and 0 < left and left <= M.SHOW_MS then
    return s.visitor
  end
  return nil
end

-- What the friend on screen brought her, or nil.
function M.gift(s)
  local animal = M.visiting(s)
  if animal then
    return M.GIFTS[animal]
  end
  return nil
end

-- The animals she has met, in ANIMALS' order.
function M.met(s)
  local out = {}
  for _, a in ipairs(M.ANIMALS) do
    if s.memory.animals[a] ~= nil then out[#out + 1] = a end
  end
  return out
end

-- The gifts she was brought, each with who brought it, in ANIMALS' order (her album's page of gifts, the owner
-- 2026-10-11): a friend always brings the same, so who came says what she has, those from before the page too.
function M.gifts(s)
  local out = {}
  for _, a in ipairs(M.met(s)) do out[#out + 1] = {M.GIFTS[a], a} end
  return out
end

return M
