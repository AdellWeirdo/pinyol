-- Malabarista: a game the way a pocket LCD game looked (a Game & Watch): every figure is a fixed shape on the glass, either ON (dark) or OFF (a
-- faint ghost you can still see), over a picture printed in colour behind it; the world moves a step at a time with a beep, faster as the score
-- grows; the score in seven-segment digits; a clock when nobody plays. Everything is drawn with polygons: the glass, the printed picture and every
-- figure's ghost once (glass.lua, shown as a picture), and each frame only what is on.
--   The juggler throws balls from hand to hand; when one reaches a hand, press that hand's button (LEFT or RIGHT) in that step to catch it.
--   A: game A (the balls grow in number as you score)   B: game B (three balls and quicker)   START: the clock   three misses and it is over.
local lang = require("lang")
local S = require("shapes")
local GX, GY, GW, GH = S.GX, S.GY, S.GW, S.GH
local HL, HR, arc, drop_at = S.HL, S.HR, S.arc, S.drop_at
local ball, juggler, digits, colon = S.ball, S.juggler, S.digits, S.colon

local GHOST, ON = 0xB4BAA2, 0x1E2418
local PLATE_L = 0xF4D868

state, score, misses, balls_n, mode = "clock", 0, 0, 1, "A" -- (global: tests/malabar.script)
balls = {}
GAME = {catches = 0}
local t, step_t, step_ticks, caught, wait, drop = 0, 0, 22, {false, false}, 0, nil
local beat, bonus_t = 0, 0
local toast_text, toast_t = nil, 0

-- ------------------------------------------------------------------ playing

local function toast(s) toast_text, toast_t = s, 150 end
local function earn(id) if achieve(id) then toast(lang.tr("ach_" .. id)) sfx("SFX_BONUS") end end

function _init()
  show(0)
  lang.load()
  sound("SFX_STEP", {wave = "square", freq = 1760, sustain = 0.01, decay = 0.02, volume = 0.18})
  sound("SFX_CATCH", {wave = "square", freq = 2300, sustain = 0.03, decay = 0.05, volume = 0.25})
  sound("SFX_MISS", {wave = "square", freq = 330, sustain = 0.3, decay = 0.1, volume = 0.3, vibrato = 0.5, vibrato_speed = 12})
  sound("SFX_BONUS", {wave = "square", freq = 1500, arp = 1.5, arp_time = 0.06, sustain = 0.1, decay = 0.2, volume = 0.22})
  sound("SFX_SECOND", {wave = "square", freq = 2600, sustain = 0.005, decay = 0.01, volume = 0.08})
  GAME.best = stored("best", 0)
  menuitem(lang.tr("how"), function()
    if state == "clock" or state == "play" then GAME.back = state require("explain").enter() state = "explain" end
  end)
end

local function set_balls()
  balls = {}
  local n = balls_n
  if n == 1 then balls[1] = {k = 3, dir = 1}
  elseif n == 2 then balls[1] = {k = 3, dir = 1} balls[2] = {k = 0, dir = -1}
  else balls[1] = {k = 2, dir = 1} balls[2] = {k = 4, dir = -1} balls[3] = {k = 0, dir = -1} end
  caught = {false, false}
end

local function start(m)
  mode, state, score, misses, drop, wait = m, "play", 0, 0, nil, 30
  balls_n = m == "A" and 1 or 3
  if m == "B" then earn("juego_b") end
  step_ticks = m == "A" and 22 or 14
  set_balls()
  step_t = 0
  sfx("SFX_BONUS")
end

local function save_best()
  if score > GAME.best then GAME.best = score store("best", score) end
end

local function level()
  if mode == "A" then
    local n = score < 10 and 1 or score < 30 and 2 or 3
    if n > balls_n then
      balls_n = n
      set_balls() -- the new ball is on the board, not only counted
      wait = 30
      if n == 3 then earn("tres_bolas") end
    end
  end
  step_ticks = math.max(8, (mode == "A" and 22 or 14) - score // 8)
end

local function step() -- one step of the world: every ball goes on; one that reached a hand is caught or falls
  sfx("SFX_STEP")
  local missed = false
  local arrives = {false, false} -- which hands a ball reaches this step
  for _, b in ipairs(balls) do
    if b.k == 6 then arrives[b.dir == 1 and 2 or 1] = true end
  end
  for _, b in ipairs(balls) do
    if b.k == 6 then -- it arrived at the hand of side `arrive` last step: caught if that button was pressed since
      local side = b.dir == 1 and 2 or 1
      -- the other hand pressed as well, with no ball for it, is a clumsy grab: holding both buttons catches nothing
      if caught[side] and (arrives[3 - side] or not caught[3 - side]) then
        score = score + 1
        GAME.catches = GAME.catches + 1
        sfx("SFX_CATCH")
        b.k, b.dir = 1, -b.dir
        if score == 10 then earn("diez") end
        if score == 100 then earn("cien") end
        if score == 100 or score == 200 then misses, bonus_t = 0, 90 sfx("SFX_BONUS") end
      else
        missed = side
      end
    else
      b.k = b.k + 1
    end
  end
  caught = {false, false}
  level()
  if missed then
    misses = misses + 1
    drop = {side = missed, k = 1}
    sfx("SFX_MISS")
    balls = {}
    wait = 90
    if misses >= 3 then state = "over" save_best() end
  end
end

local function sample_clock(c) return c and string.format("%02d%02d", c.hour, c.min) or "----" end

function _update()
  t = t + 1
  if toast_t > 0 then toast_t = toast_t - 1 end
  if bonus_t > 0 then bonus_t = bonus_t - 1 end
  if state == "explain" then
    if require("explain").update() then state = GAME.back or "clock" end
    return
  end
  if state == "clock" then
    if btnp("a") then start("A") elseif btnp("b") then start("B") end
    local c = clock()
    if c and c.sec ~= GAME.sec then GAME.sec = c.sec sfx("SFX_SECOND") beat = beat + 1 end
    return
  end
  if btnp("start") and (state == "over" or state == "play") then save_best() state = "clock" return end
  if state == "over" then
    if btnp("a") then start("A") elseif btnp("b") then start("B") end
    if drop and t % 10 == 0 and drop.k < 3 then drop.k = drop.k + 1 end
    return
  end
  -- playing
  if btnp("left") or btn("left") then caught[1] = true end
  if btnp("right") or btn("right") then caught[2] = true end
  if drop then
    if t % 14 == 0 then drop.k = drop.k + 1 if drop.k > 3 then drop = nil end end
  end
  if wait > 0 then
    wait = wait - 1
    if wait == 0 and #balls == 0 then set_balls() end
    return
  end
  step_t = step_t + 1
  if step_t >= step_ticks then step_t = 0 step() end
end

-- ------------------------------------------------------------------ drawing: only what is on

local function glass_text(s, x, y) text(s, x, y, {font = "pocket_lcd_title", align = "center", color = ON}) end

function _draw()
  img("LCD", 0, 0)
  if state == "explain" then require("explain").draw(juggler, ball, digits, colon, arc, HL, HR, ON, GHOST) return end
  local lh = btn("left")
  local rh = btn("right")
  if state == "clock" then
    -- the clock: the hour and the minutes; the colon blinks each second; the juggler throws one ball slowly
    digits(sample_clock(clock()), ON)
    if beat % 2 == 0 then colon(ON) end
    juggler(ON, beat % 4 == 1, beat % 4 == 3)
    local k = beat % 12
    if k >= 1 and k <= 5 then local x, y = arc(k, 1) ball(x, y, ON) elseif k >= 7 and k <= 11 then local x, y = arc(k - 6, -1) ball(x, y, ON) end
    if k == 0 or k == 6 then ball((k == 0 and HL or HR)[1] + (k == 0 and -10 or 10), HL[2] - 4, ON) end
    if (t // 40) % 2 == 0 then glass_text(lang.tr("press"), 240, GY + GH - 22) end
    return
  end
  juggler(ON, lh, rh)
  digits(string.format("%04d", score % 10000), ON)
  for _, b in ipairs(balls) do
    if b.k == 0 then ball((b.dir == 1 and HL or HR)[1] + (b.dir == 1 and -10 or 10), HL[2] - 4, ON)
    elseif b.k == 6 then ball((b.dir == 1 and HR or HL)[1] + (b.dir == 1 and 10 or -10), HL[2] - 4, ON)
    else local x, y = arc(b.k, b.dir) ball(x, y, ON) end
  end
  if drop then local x, y = drop_at(drop.side, math.min(3, drop.k)) ball(x, y, ON) end
  for i = 1, misses do circ(GX + GW - 84 + i * 22, GY + 22, 7, ON) end
  if state == "over" and (t // 30) % 2 == 0 then glass_text(lang.tr("over"), 240, GY + GH - 22) end
  if bonus_t > 0 and (bonus_t // 8) % 2 == 0 then glass_text("BONUS", 240, GY + GH - 22) end
  if toast_t > 0 then
    rect(80, 8, 320, 20, 0x3A3226)
    text(toast_text, 240, 10, {font = "pocket_lcd_small", align = "center", color = PLATE_L})
  end
end
