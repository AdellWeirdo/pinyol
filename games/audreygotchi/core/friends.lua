-- friends: other Audreygotchis nearby are friends (a port of audreygotchi/core/friends.py). On the board they came
-- over Bluetooth; here over pinyol's link (consoles running this game near each other): the front end hands each
-- one it hears to s:meet(id, name, now_ms). Both come from the air, so both are cleaned here.
local memory = require("core.memory")
local util = require("core.util")
local M = {}

M.FRIENDS_MAX = 8
M.NAME_MAX, M.ID_MAX = 12, 12
M.VISIT_COOLDOWN_SEC = 3600
M.VISIT_GAP_SEC = 600
M.VISITS_PER_DAY = 4
M.CONFIRM_SEC, M.CONFIRM_WITHIN_SEC = 30, 600
M.CANDIDATES_MAX = 16
M.VISIT_SHOW_MS = 20000
M.VISIT_JOY, M.GIFT_JOY = 8.0, 6.0

function M.clean_id(friend_id)
  local fid = tostring(friend_id):lower():sub(1, M.ID_MAX)
  if fid ~= "" and fid:match("^[0-9a-f]+$") then return fid end
  return nil
end

function M.clean_name(name) -- printable (no control characters), at most NAME_MAX letters, or ""
  local out = {}
  for _, c in utf8.codes(tostring(name):sub(1, M.NAME_MAX * 4)) do
    if c >= 32 and not (c >= 0x7F and c <= 0x9F) and not (c >= 0x2000 and c <= 0x206F) and c ~= 0xFEFF then
      out[#out + 1] = utf8.char(c)
    end
  end
  local s = table.concat(out):match("^%s*(.-)%s*$")
  local n = 0
  local cut = s
  for p in utf8.codes(s) do
    n = n + 1
    if n > M.NAME_MAX then cut = s:sub(1, p - 1) break end
  end
  return cut:match("^%s*(.-)%s*$")
end

local function can_meet(s)
  if not s.friends_on or s.sleeping or s.deep_sleep or s.powered_off then return false end
  if s.sitter_until ~= 0 or s.hidden then return false end -- at Sancho's, or hiding: nobody to see
  return s.mode == "main" and not (s.sick or s.in_critical)
end

local function confirmed(s, fid, now) -- a new console counts once heard again, CONFIRM_SEC to CONFIRM_WITHIN_SEC later
  local cand = s._friend_candidates
  local first = cand[fid]
  if first == nil or not (now - first >= 0 and now - first <= M.CONFIRM_WITHIN_SEC) then
    if cand[fid] == nil and util.len(cand) >= M.CANDIDATES_MAX then
      local oldest
      for _, k in ipairs(util.keys(cand)) do if oldest == nil or cand[k] < cand[oldest] then oldest = k end end
      cand[oldest] = nil
    end
    cand[fid] = now
    return false
  end
  if now - first < M.CONFIRM_SEC then return false end -- the same scan
  cand[fid] = nil
  return true
end

local function befriend(s, fid, day)
  local friends = s.memory.friends
  if util.len(friends) >= M.FRIENDS_MAX then
    local once
    for _, k in ipairs(util.keys(friends)) do
      if friends[k].visits <= 1 and (once == nil or friends[k].seen < friends[once].seen) then once = k end
    end
    if once == nil then return nil end -- all came back: a ninth waits for a free place
    friends[once] = nil
  end
  friends[fid] = {name = "?", met = day, seen = 0, gift = 0, visits = 0}
  memory.first(s, "friend")
  return friends[fid]
end

local function hex_mod(fid, n) -- int(fid, 16) % n without a 48-bit number
  local acc = 0
  for i = 1, #fid do acc = (acc * 16 + tonumber(fid:sub(i, i), 16)) % n end
  return acc
end

function M.meet(s, friend_id, name, now_ms)
  local fid = M.clean_id(friend_id)
  if not fid or not can_meet(s) then return end
  local friends, now, day = s.memory.friends, s.clock:now(), s.day
  local f = friends[fid]
  if f == nil and not confirmed(s, fid, now) then return end
  if f and f.seen > now then f.seen = now return end -- a clock that ran back: the hour starts now
  if f and now - f.seen < M.VISIT_COOLDOWN_SEC then return end -- still beside her
  local last = s._friend_visit_ts
  if (last ~= nil and now - last >= 0 and now - last < M.VISIT_GAP_SEC) or s.memory.day.friend >= M.VISITS_PER_DAY then
    return
  end
  f = f or befriend(s, fid, day)
  if f == nil then return end
  local nm = M.clean_name(name)
  if nm ~= "" then f.name = nm end
  f.seen, f.visits = now, f.visits + 1
  s._friend_visit_ts = now
  s.memory.day.friend = s.memory.day.friend + 1
  s._frame_ms = now_ms
  s.friend_visit, s.friend_until = fid, now_ms + M.VISIT_SHOW_MS
  local joy = M.VISIT_JOY
  if f.gift ~= day then -- the first visit today brings something
    f.gift = day
    if s.memory.toy ~= nil and s.memory.toy ~= "" then joy = joy + M.GIFT_JOY
    else memory.keep_toy(s, memory.TOYS[hex_mod(fid, #memory.TOYS) + 1]) end
  end
  s.affection = s:_clamp_stat(s.affection + joy)
  s:_emit_sound("amigo")
  s:_log_event("Visita de " .. f.name)
  s:compute_mood()
  s:mark_dirty()
end

function M.visiting(s) -- the friend on screen now, by name, or nil
  local fid = s.friend_visit
  local left = s.friend_until - s._frame_ms
  if fid == nil or not (left > 0 and left <= M.VISIT_SHOW_MS) or s.memory.friends[fid] == nil then return nil end
  return s.memory.friends[fid].name
end

function M.names(s) -- her friends, the most recently seen first
  local fr = s.memory.friends
  local ks = util.keys(fr)
  table.sort(ks, function(a, b) return fr[a].seen > fr[b].seen end)
  local out = {}
  for _, k in ipairs(ks) do out[#out + 1] = fr[k].name end
  return out
end

return M
