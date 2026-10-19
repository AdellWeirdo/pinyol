-- world: what the board learnt from outside, made here. The weather came from the internet; here a report is made
-- from the date (a Mediterranean year: Barcelona's sun and rain), the same for the same day and hour. Other
-- Audreygotchis came over Bluetooth; here over pinyol's link, consoles running this game nearby. Her ears were the
-- board's microphone; here pinyol's mic(): a voice, a bang, music.
local M = {}

-- by month: sunrise and sunset (minutes of the local day), mean temperature, and the chances of rain, storm,
-- snow and fog (the rest: a quarter cloudy, else clear)
local CLIMATE = {
  {495, 1065, 10, .12, .02, .05, .05}, {475, 1100, 11, .12, .02, .04, .05}, {435, 1130, 13, .14, .02, 0, .02},
  {445, 1225, 15, .18, .02, 0, .02}, {410, 1255, 18, .16, .03, 0, .02}, {395, 1285, 22, .10, .04, 0, .02},
  {410, 1280, 25, .05, .04, 0, .02}, {435, 1250, 26, .08, .08, 0, .02}, {460, 1200, 23, .14, .10, 0, .02},
  {485, 1150, 19, .18, .06, 0, .02}, {460, 1050, 14, .16, .02, 0, .05}, {490, 1045, 11, .14, .02, .03, .05},
}

local function chance(key, salt) -- the same number in 0..1 for the same key: an LCG step over it
  local x = (key * 1103515 + salt * 12345) % 2147483
  x = (x * 16807) % 2147483
  return x / 2147483
end

local last_hour = nil

function M.weather(s)
  local lt = s.clock:localtime()
  local hour_key = ((lt.tm_year % 100) * 400 + lt.tm_yday) * 24 + lt.tm_hour
  if hour_key == last_hour then return end
  last_hour = hour_key
  local c = CLIMATE[lt.tm_mon]
  local block = ((lt.tm_year % 100) * 400 + lt.tm_yday) * 4 + lt.tm_hour // 6 -- one sky every six hours
  local r = chance(block, 7)
  local kind = "clear"
  if r < c[4] then kind = "rain"
  elseif r < c[4] + c[5] then kind = "storm"
  elseif r < c[4] + c[5] + c[6] then kind = "snow"
  elseif r < c[4] + c[5] + c[6] + c[7] then kind = "fog"
  elseif r < c[4] + c[5] + c[6] + c[7] + 0.25 then kind = "cloudy" end
  local minute = lt.tm_hour * 60 + lt.tm_min
  local swing = math.cos((lt.tm_hour - 15) / 24 * 2 * math.pi) * 4 -- coolest at dawn, warmest at three
  local temp = c[3] + swing + (chance(block, 3) - 0.5) * 6 - (kind == "snow" and 10 or 0)
  s:set_weather(kind, temp, minute >= c[1] and minute < c[2], {c[1], c[2]})
end

-- ------------------------------------------------------------------ friends, over the link

local FRIEND_EVERY = 120 -- ticks: say hello every two seconds while friends are on

function M.friends(s, now_ms, t)
  if not s.friends_on or not link then return end
  if t % FRIEND_EVERY == 0 then link.send({n = s.name}) end
  for from, msg in link.recv do
    if type(msg) == "table" and type(msg.n) == "string" and type(from) == "number" then
      s:meet(string.format("%x", math.abs(from)), msg.n, now_ms)
    end
  end
end

-- ------------------------------------------------------------------ her ears

local E = {voiced = 0, heard_voice = false}
local VOICE_TICKS, MUSIC_TICKS = 18, 240 -- a voice: a pitch held a third of a second; music: four seconds

function M.ears(s, now_ms, speaking)
  if not s.mic_on or not mic then return end
  local level, pitch, hit = mic()
  if not level or speaking then E.voiced = 0 return end -- no microphone, or our own speaker playing
  if hit and level > 0.5 then s:hear("ruido", now_ms) end
  if pitch > 0 and level > 0.12 then
    E.voiced = E.voiced + 1
    if E.voiced == VOICE_TICKS then s:hear("voz", now_ms) end
    if E.voiced == MUSIC_TICKS then s:hear("musica", now_ms) end
  elseif level < 0.05 then
    E.voiced = 0
  end
end

return M
