-- mood: her mood, the Character Bible's 14 (§3), from her stats, temperament and context (§4)
-- (a port of audreygotchi/core/mood.py).
--
-- The owner's yes, 2026-10-05. The power states, sleep, illness and critical come first and are never held.
-- Awake, each Bible mood gets a score from a few plain terms; the best one wins, plus a small chance of the
-- day so two days in the same shape need not feel the same ("hoy está de mal humor"). An awake mood holds at
-- least MOOD_DWELL_SEC, unless another one beats it by MOOD_SWITCH_MARGIN: hunger or a fright should not wait
-- ten minutes.
--
-- The chance is derived from the game day, not drawn from `random`: the mood is recomputed after every action,
-- and must not shift the random sequence the rest of the game relies on.
local util = require("core.util")
local weather = require("core.weather")
local M = {}

M.MOOD_DWELL_SEC = 600
M.MOOD_SWITCH_MARGIN = 0.25
M.DAY_CHANCE = 0.15 -- the most the mood of the day can add to a score

-- the Python's icons are emoji: the console's text has none, so every icon is "" (as game_init's mood_icon)
M.ICONS = {
  off = "", deep_sleep = "", sick = "", critical = "",
  happy = "", calm = "", curious = "", playful = "", affectionate = "",
  bored = "", sleepy = "", grumpy = "", nervous = "", sad = "",
  proud = "", excited = "", lonely = "",
}
M.AWAKE = {"happy", "calm", "curious", "playful", "affectionate", "bored", "sleepy", "grumpy",
           "nervous", "sad", "proud", "excited", "lonely"}

local function pos(x)
  if x > 0 then return x end
  return 0.0
end

local function pick(cond, a, b) -- Python's `a if cond else b`
  if cond then return a end
  return b
end

local PHASE_CALM = {Senior = 0.05, Extra = 0.08} -- a senior is calmer, Extra more so (Bible §23, §26)

-- Each awake Bible mood's score, 0 and up, from 0-1 quantities.
function M.scores(s)
  local h, f, e, sv = s.hunger / 100.0, s.affection / 100.0, s.energy / 100.0, s.health / 100.0
  local t, d = s.stress / 100.0, s.dirt / 100.0
  local x, c, b = s.excitement / 100.0, s.confidence / 100.0, s.trust_bond / 100.0
  local curiosity, sociable, play = s:_pf("curiosity"), s:_pf("sociability"), s:_pf("activity")
  local night = s:is_night()
  local y = s.memory["yesterday"] -- recent memory (Bible §4): yesterday colours today
  local out = {
    grumpy = pos(0.35 - h) * 2.5 + pos(t - 0.55) * 1.5 + pick(d > 0.8, 0.2, 0.0),
    nervous = pos(t - 0.65) * 3.0,
    sad = pos(0.4 - f) * 1.8 + pos(0.6 - sv) * 1.2,
    lonely = pos(0.55 - f) * 1.4 * (0.5 + sociable) + math.min(y["alone_min"] / 600.0, 1.0) * 0.2,
    sleepy = pos(0.35 - e) * 2.4 + pick(night, 0.15, 0.0),
    -- nothing to do: little excitement, or a day before with no play and no cuddle
    bored = pos(e - 0.5) * (pos(0.5 - x) * 2.0
                            + pick(not (y["play"] ~= 0 or y["cuddle"] ~= 0), 0.15, 0.0)) * (0.5 + curiosity),
    playful = (pos(e - 0.6) * 0.6 + pos(x - 0.6) * 0.8 + pos(play - 0.5) * 0.8
               + math.min(y["play"], 4) * 0.02),
    curious = (pos(curiosity - 0.5) * 0.6 + pos(e - 0.5) * 0.3 + pick(night, 0.0, 0.1)
               + pick(s.phase == "Cachorro", 0.05, 0.0)), -- a puppy looks at all
    excited = pos(x - 0.7) * 2.6,
    -- how she shows love is her temperament's; loved, she need not show it all day
    affectionate = (pos(f - 0.8) * 1.5 * (0.5 + s:_pf("affection"))
                    + math.min(y["cuddle"], 4) * 0.02),
    happy = pos((h + f + e + sv) / 4.0 - 0.55) * 0.8 * (1.0 - t),
    proud = pos(c - 0.65) * 1.0 + pos(b - 0.8) * 0.8,
    calm = 0.2 + pos(0.4 - t) * 0.2 + util.get(PHASE_CALM, s.phase, 0.0),
  }
  local w = weather.kind(s) -- the weather outside (Bible §42)
  if w == "storm" then
    out["nervous"] = out["nervous"] + 0.2
  elseif w == "rain" or w == "snow" then
    out["calm"] = out["calm"] + 0.06
    out["sleepy"] = out["sleepy"] + 0.05
  end
  if weather.sunny(s) then
    out["happy"] = out["happy"] + 0.05
  end
  if weather.cold(s) then
    out["sleepy"] = out["sleepy"] + 0.08
    out["affectionate"] = out["affectionate"] + 0.04 -- she seeks the warmth of you
  elseif weather.hot(s) then
    out["sleepy"] = out["sleepy"] + 0.08
  end
  return out
end

-- 0-DAY_CHANCE, fixed for a mood on a game day: the mood of the day. Squared mod a prime, so each mood's share
-- moves on its own from day to day (small ints). `i` is the mood's 0-based place in AWAKE.
local function day_chance(day, i)
  local x = (util.int(day) * 1103 + i * 2003) % 997
  return ((x * x + 7 * i) % 997) / 996.0 * M.DAY_CHANCE
end
M._day_chance = day_chance

local function set(s, mood, now)
  if mood ~= s.mood then
    s._mood_since = now
  end
  s.mood = mood
  s.mood_icon = util.get(M.ICONS, mood, "")
end

function M.compute_mood(s)
  local hard = nil
  if s.powered_off then
    hard = "off"
  elseif s.deep_sleep then
    hard = "deep_sleep"
  elseif s.sleeping then
    hard = "sleepy"
  elseif s.sick then
    hard = "sick"
  elseif s.in_critical then
    hard = "critical"
  end
  local sim = util.get(s, "_sim_ts", 0) -- the simulated second in catch-up
  local now
  if sim ~= nil and sim ~= false and sim ~= 0 then
    now = util.int(sim)
  else
    now = util.int(s.clock:now())
  end
  if hard then
    set(s, hard, now)
    return
  end
  local sc = M.scores(s)
  for i, mood in ipairs(M.AWAKE) do
    sc[mood] = sc[mood] + day_chance(s.day, i - 1)
  end
  local best = M.AWAKE[1]
  for i = 2, #M.AWAKE do
    if sc[M.AWAKE[i]] > sc[best] then best = M.AWAKE[i] end -- the first of the highest, as max()
  end
  local cur = s.mood
  local since = now - util.int(util.get(s, "_mood_since", 0))
  local held = sc[cur] ~= nil and 0 <= since and since < M.MOOD_DWELL_SEC
  if held and sc[best] - sc[cur] < M.MOOD_SWITCH_MARGIN then
    return
  end
  set(s, best, now)
end

return M
