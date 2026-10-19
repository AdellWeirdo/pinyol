-- A whole life on the real core, minute by minute: a carer who feeds, bathes, cuddles, plays, heals and puts her to
-- bed, and now and then presses anything at all. Nothing may raise, and the life must end in its farewell between
-- day 40 and 55 with a new life after it.
--   LUA_ROOT=games/audreygotchi lua32 games/audreygotchi/tests/core/test_life.lua [days] [seed] [careless]
local Clock = require("core.clock")
local State = require("core.state")
local save = require("core.save")

local DAYS = tonumber(arg and arg[1]) or 60
math.randomseed(tonumber(arg and arg[2]) or 1)
local CARELESS = arg and arg[3] == "careless"

local s = State.new(Clock.start({2026, 10, 15}, 9 * 3600))
local now_ms = 0
local seen = {phases = {}, sick = 0, critical_min = 0, farewell_day = nil, new_life = false, modes = {},
              sounds = {}, games = 0, saves = 0}

local function step(ms) now_ms = now_ms + ms s:update(now_ms) end

local function choose(label) -- the menu's button with that label, pressed (true if it is there)
  for i, l in ipairs(s:active_menu_items()) do
    if l == label then
      s.selected_index = i - 1
      s:press_ok(now_ms)
      return true
    end
  end
  return false
end

local function play_game() -- through every screen, pressing until it is over
  for _ = 1, 400 do
    if s.mode ~= "action_minigame" then return end
    local r = math.random(3)
    if r == 1 then s:move_left() elseif r == 2 then s:move_right() else s:press_ok(now_ms) end
    step(300)
  end
  s:cancel_action(now_ms)
end

local function care_once()
  local m = s.mode
  if m == "ask" or m == "sitter_confirm" then s:press_ok(now_ms) return end
  if m == "guide" or m == "grow" or m == "sancho_intro" then s:press_ok(now_ms) return end
  if m ~= "main" then s:cancel_action(now_ms) return end
  if s.hidden then s:press_ok(now_ms) s:move_right() return end
  if s.grow_to ~= "" then s:press_ok(now_ms) return end
  if s.sitter_until ~= 0 then return end
  local night = s:is_night()
  if s.sleeping or s.deep_sleep then
    if s.hunger < 25 or s.dirt > 70 or s.affection < 25 or s.sick then s:press_ok(now_ms) end -- wake her
    return
  end
  -- the most urgent first: the lowest of what she needs; in the evening, ready for a long night (nothing wakes
  -- her at night, and she may sleep from the afternoon to the morning)
  local h = s.clock:local_hour()
  local evening = h >= 16 or night
  local wants = {
    {s.hunger, evening and 85 or 45, function() if choose("Feed") and s.mode == "action_feed" then s:press_ok(now_ms) end end},
    {s.affection, evening and 85 or 70, function() choose("Cuddle") end},
    {(s.sick or s.health < 50) and 0 or 100, 50, function()
      if choose("Heal") and s.mode == "action_heal" then s:move_right() s:press_ok(now_ms) end end},
    {100 - s.dirt, evening and 85 or 45, function()
      if choose("Bath") and s.mode == "action_bath" then if s.bath_choice ~= 0 then s:move_left() end s:press_ok(now_ms) end end},
    {(s.litter >= 2 or (evening and s.litter >= 1)) and 30 or 100, 50, function()
      if choose("Bath") and s.mode == "action_bath" then if s.bath_choice ~= 1 then s:move_right() end s:press_ok(now_ms) end end},
  }
  table.sort(wants, function(x, y) return x[1] - x[2] < y[1] - y[2] end)
  if wants[1][1] < wants[1][2] then wants[1][3]()
  elseif night then choose("Sleep")
  elseif s.energy > 40 and math.random() < 0.3 and choose("Play") then
    if s.mode == "action_play" then
      s:press_ok(now_ms)
      if s.mode == "action_minigame" then seen.games = seen.games + 1 play_game() end
    end
  elseif math.random() < 0.05 then -- now and then anything at all
    local r = math.random(5)
    if r == 1 then s:move_left() elseif r == 2 then s:move_right() elseif r == 3 then s:press_ok(now_ms)
    elseif r == 4 then s:cancel_action(now_ms) else s:search(now_ms) end
  end
end

local function care() -- a visit: up to four cares in a row, a few seconds apart (each reaction holds 2.5 s)
  for _ = 1, 4 do
    care_once()
    step(3000)
    if s.mode ~= "main" and s.mode ~= "ask" then s:cancel_action(now_ms) end
  end
end

local minutes = DAYS * 24 * 60
for minute = 1, minutes do
  s.clock:advance(60)
  step(1000)
  seen.sounds[s.sound or "-"] = true
  seen.modes[s.mode] = (seen.modes[s.mode] or 0) + 1
  seen.phases[s.phase] = seen.phases[s.phase] or s.day
  if s.sick then seen.sick = seen.sick + 1 end
  if s.in_critical then seen.critical_min = seen.critical_min + 1 end
  if s.mode == "birth" or s.mode == "farewell" then
    if s.mode == "farewell" and not seen.farewell_day then seen.farewell_day = s.day end
    s:press_ok(now_ms) -- the farewell ends on Nueva vida / Recuerdos: A picks the first
  elseif not CARELESS and minute % 20 == 0 then
    care()
  end
  if seen.farewell_day and s.cycle == 2 then seen.new_life = true break end
  if minute % (6 * 60) == 0 then -- a save and a load every six hours: the game goes on from the copy
    local copy = save.load(save.dump(s), now_ms)
    assert(copy, "a save that does not load")
    copy.clock:advance(0)
    s = copy
    seen.saves = seen.saves + 1
  end
end

local function keys(t) local out = {} for k, v in pairs(t) do out[#out + 1] = k .. "=" .. tostring(v) end table.sort(out) return table.concat(out, " ") end
print("day", s.day, "cycle", s.cycle, "phase", s.phase, "farewell on day", seen.farewell_day)
print("phases", keys(seen.phases))
print("sick minutes", seen.sick, "critical minutes", seen.critical_min, "games", seen.games, "saves", seen.saves)
print(string.format("H %.0f F %.0f E %.0f S %.0f D %.0f  weight %.2f", s.hunger, s.affection, s.energy, s.health,
                    s.dirt, s.weight_kg))
print("stickers", #s.memory.stickers, "legacy", #s.legacy, "stars", s.stars)
if not CARELESS and DAYS >= 56 then
  assert(seen.phases.Juvenil and seen.phases.Adulto and seen.phases.Senior, "she grows up")
  assert(seen.farewell_day and seen.farewell_day >= 40 and seen.farewell_day <= 56, "the farewell in its days")
  assert(seen.new_life and #s.legacy == 1, "a new life after it, keeping what she left")
end
print("ok life")
