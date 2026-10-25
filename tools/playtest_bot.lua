-- playtest_bot: the player that tools/playtest.py injects into a game (luafile, after PT_CFG and the game's adapter). It takes over btn/btnp, wraps _update, plays
-- one game as a perfect player, a human-like one (skill 0.1..0.9) or a monkey, and logs one "PT_RESULT ..." line. See docs/playtest.md.
--   PT_CFG   = {mode = "perfect" | "human" | "monkey", seed = n, skill = 0..1, cap = ticks}
--   PLAYTEST = the game's adapter (optional): progress(), done(), playing(), perfect(), probe(), deaths(), where(), stuck_ticks
local cfg = PT_CFG
local A = PLAYTEST or {}
math.randomseed(cfg.seed)
local rnd = math.random
local BUTTONS = {"left", "right", "up", "down", "a", "b", "c", "start"}
local DIRS = {"left", "right", "up", "down"}

PT = {t = 0, done = false, anomalies = {}, last_progress = nil, last_change = 0, deaths = 0}
local held, prev = {}, {}
local intents, ii = {}, 0 -- the perfect player's intent per tick, kept for the reaction delay
local pending = {} -- human: a press that waits (button -> tick it starts)
local release_until, extra, idle_until = {}, nil, 0
local explore = {until_t = 0, set = {}}

-- the console's menu items the game offers (its own "Cómo funciona"...): remember their callbacks so the monkeys can use them like a player opening the menu
local menu_cbs = {}
local real_menuitem = menuitem
if real_menuitem then
  menuitem = function(label, cb)
    if cb then menu_cbs[label] = cb else menu_cbs = {} end
    return real_menuitem(label, cb)
  end
  if _resume then pcall(_resume) end -- the game sets its items again, now through the wrapper
end

local function safe(f, ...)
  if not f then return nil end
  local ok, a = pcall(f, ...)
  if not ok then PT.anomalies["adapter_error"] = tostring(a):sub(1, 60) return nil end
  return a
end

btn = function(n) return held[n] or false end
btnp = function(n) return (held[n] and not prev[n]) or false end

local function set_of(list)
  local s = {}
  for _, b in ipairs(list or {}) do s[b] = true end
  return s
end

-- what a player who knew the game would hold now: the adapter's perfect(), else a random walk that changes every half second or so
local function perfect_intent()
  if A.perfect then
    local r = safe(A.perfect, PT)
    if r then return type(r) == "table" and (r[1] and set_of(r) or r) or {} end
  end
  if PT.t >= explore.until_t then
    explore.until_t = PT.t + 20 + rnd(40)
    explore.set = {}
    if rnd() < 0.8 then explore.set[DIRS[rnd(4)]] = true end
    if rnd() < 0.5 then explore.set.a = true end
    if rnd() < 0.3 then explore.set.b = true end
  end
  return explore.set
end

local function monkey_intent()
  if rnd() < 0.002 then -- open one of the game's menu items: an error in it is the game's, and ends the run as a crash
    local labels = {}
    for l in pairs(menu_cbs) do labels[#labels + 1] = l end
    table.sort(labels)
    if #labels > 0 then menu_cbs[labels[rnd(#labels)]]() end
  end
  if PT.t >= explore.until_t then
    explore.until_t = PT.t + 2 + rnd(10)
    explore.set = {}
    for _ = 1, rnd(3) do explore.set[BUTTONS[rnd(#BUTTONS)]] = true end
    if rnd() < 0.9 then explore.set.start = nil end -- START (the menu, the pause) only now and then
  end
  return explore.set
end

local function human_intent(skill)
  local want = perfect_intent()
  ii = ii + 1
  intents[ii] = want
  local delay = math.floor(30 - 25 * skill + 0.5)
  local seen = intents[ii - delay] or {}
  intents[ii - 130] = nil
  local out = {}
  local slip = 1 - skill
  if PT.t < idle_until then return out end
  if rnd() < slip * 0.002 then idle_until = PT.t + 30 + rnd(90) return out end -- a moment of looking elsewhere
  for _, b in ipairs(BUTTONS) do
    if seen[b] then
      if not prev[b] and not pending[b] and rnd() < slip * 0.35 then pending[b] = PT.t + 3 + rnd(15) end -- a late press
      if pending[b] and PT.t < pending[b] then
        -- not yet
      else
        pending[b] = nil
        if not (release_until[b] and PT.t < release_until[b]) then out[b] = true end
        if rnd() < slip * 0.02 then release_until[b] = PT.t + 2 + rnd(8) end -- let go too early
      end
    else
      pending[b] = nil
    end
  end
  if extra and PT.t < extra.t then out[extra.b] = true
  elseif rnd() < slip * 0.01 then extra = {b = BUTTONS[rnd(#BUTTONS - 1)], t = PT.t + 2 + rnd(5)} end -- a stray press
  return out
end

local function playing()
  if A.playing then return safe(A.playing) ~= false end
  return PT.t > 300
end

local function snapshot()
  local p = safe(A.progress)
  if p == nil then p = type(score) == "number" and score or 0 end
  local probe = safe(A.probe)
  local d = tostring(p)
  if type(probe) == "table" then
    local keys = {}
    for k in pairs(probe) do keys[#keys + 1] = k end
    table.sort(keys)
    for _, k in ipairs(keys) do
      local v = probe[k]
      if type(v) == "number" then
        if v ~= v or v == math.huge or v == -math.huge then PT.anomalies[k .. "_nan"] = PT.t
        elseif tostring(k):sub(1, 2) == "n_" and v < 0 then PT.anomalies[k .. "_negative"] = PT.t end
        d = d .. "|" .. string.format("%.1f", v)
      else d = d .. "|" .. tostring(v) end
    end
  end
  return p, d
end

local function finish(outcome)
  if PT.done then return end
  PT.done = true
  held = {}
  local p = snapshot()
  local an = {}
  for k, v in pairs(PT.anomalies) do an[#an + 1] = k .. "@" .. tostring(v):gsub("[%s=]", "_") end
  table.sort(an)
  local where = safe(A.where)
  local deaths = safe(A.deaths) or PT.deaths
  log(string.format("PT_RESULT outcome=%s ticks=%d progress=%s deaths=%s where=%s anomalies=%s", outcome, PT.t, tostring(p), tostring(deaths),
    tostring(where or "-"):gsub("[%s=]", "_"), #an > 0 and table.concat(an, ",") or "-"))
end

local game_update = _update
function _update(...)
  if PT.done then return end
  PT.t = PT.t + 1
  prev = held
  local intent
  if cfg.mode == "monkey" then intent = monkey_intent()
  elseif cfg.mode == "human" then intent = human_intent(cfg.skill or 0.5)
  else intent = perfect_intent() end
  if not playing() then -- a title, a menu, a game over: press the way on now and then
    intent = {}
    if PT.t % 40 < 6 then intent[PT.t % 80 < 40 and "a" or "start"] = true end
  end
  held = {}
  for k, v in pairs(intent) do held[k] = v end
  local r = game_update(...)
  if PT.t % 10 == 0 and A.invariants then -- a rule the game's own numbers must keep (a count that must match a list...): the first break is recorded
    local v = safe(A.invariants)
    if v then PT.anomalies["inv_" .. tostring(v):gsub("[^%w_]", "_")] = PT.anomalies["inv_" .. tostring(v):gsub("[^%w_]", "_")] or PT.t end
  end
  local d = safe(A.done)
  if d == "win" or d == "lose" then finish(d) return r end
  local p, dig = snapshot()
  if dig ~= PT.last_digest then PT.last_digest, PT.last_change = dig, PT.t end
  if p ~= PT.last_progress then PT.last_progress = p end
  if cfg.mode ~= "monkey" and PT.t - PT.last_change > (A.stuck_ticks or 3600) then finish("stuck") return r end
  if cfg.mode == "human" and (cfg.skill or 0.5) < 0.5 and PT.t - PT.last_change > 1800 then finish("giveup") return r end
  if PT.t >= cfg.cap then finish("timeout") end
  return r
end
