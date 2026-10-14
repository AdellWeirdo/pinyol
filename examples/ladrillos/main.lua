-- Ladrillos: a game the way a PICO-8 cartridge looks: a 128x128 screen in PICO-8's sixteen colours, cleared and drawn
-- again every frame with rect, circ, line and pset (on a canvas), shown twice as big in the middle of the console's
-- screen; text in a font four pixels wide; little square-wave blips. No pictures at all.
-- Arrows move the paddle; A serves the ball. Break every brick; three levels.
-- (fonts/p8.fnt is Press Start 2P at 8 pixels: tools/font2fnt.py pressstart2p, scale 1.)
local P8 = {[0] = 0x000000, 0x1D2B53, 0x7E2553, 0x008751, 0xAB5236, 0x5F574F, 0xC2C3C7, 0xFFF1E8, 0xFF004D, 0xFFA300,
            0xFFEC27, 0x00E436, 0x29ADFF, 0x83769C, 0xFF77A8, 0xFFCCAA}
local SX, SY = 112, 32            -- where the 128x128 screen sits, twice as big, on the console's 480x320
local COLS, ROWS, BW, BH = 10, 6, 11, 4
local LEVELS = {                  -- which bricks are there: a row of 10 per line, x a brick
  {"xxxxxxxxxx", "xxxxxxxxxx", "xxxxxxxxxx", "xxxxxxxxxx", "xxxxxxxxxx", "xxxxxxxxxx"},
  {"x.x.x.x.x.", ".x.x.x.x.x", "x.x.x.x.x.", ".x.x.x.x.x", "x.x.x.x.x.", ".x.x.x.x.x"},
  {"....xx....", "...xxxx...", "..xxxxxx..", ".xxxxxxxx.", "xxxxxxxxxx", "xxxx..xxxx"},
}
local ROW_COLOUR = {8, 9, 10, 11, 12, 14}

state, score, lives, level, bricks = "title", 0, 3, 1, {} -- (global: tests/ladrillos.script)
pad, ball = {}, {}
local t, shake, sparks = 0, 0, {}
local look = {scale = 2}

local function load_level(n)
  bricks = {}
  for r = 1, ROWS do
    for c = 1, COLS do
      if LEVELS[n][r]:sub(c, c) == "x" then
        bricks[#bricks + 1] = {x = 4 + (c - 1) * (BW + 1), y = 16 + (r - 1) * (BH + 1), colour = ROW_COLOUR[r], row = r}
      end
    end
  end
  pad = {x = 52, w = 24}
  ball = {x = 64, y = 116, vx = 0, vy = 0, served = false}
end

function _init()
  show(0) -- no 240x160 world: the canvas is the screen
  canvas("P8", 128, 128)
  sound("SFX_PAD", {wave = "square", freq = 330, sustain = 0.02, decay = 0.05, volume = 0.25})
  sound("SFX_WALL", {wave = "square", freq = 220, sustain = 0.02, decay = 0.04, volume = 0.2})
  sound("SFX_LOSE", {wave = "square", freq = 440, slide = -600, sustain = 0.15, decay = 0.2, volume = 0.3})
  for r = 1, ROWS do sound("SFX_BRICK" .. r, {wave = "square", freq = 523 * 2 ^ ((r - 1) / 6), arp = 2, arp_time = 0.03,
                                              sustain = 0.02, decay = 0.08, volume = 0.25}) end
end

-- ------------------------------------------------------------------ playing

local function sparkle(b)
  for _ = 1, 10 do
    sparks[#sparks + 1] = {x = b.x + math.random(BW), y = b.y + math.random(BH), vx = (math.random() - 0.5) * 2,
                           vy = -math.random() * 1.5, life = 15 + math.random(15), colour = b.colour}
  end
end

local function update_ball()
  local b = ball
  if not b.served then
    b.x, b.y = pad.x + pad.w / 2, 116
    if btnp("a") then b.vx, b.vy, b.served = 0.9, -1.6, true end
    return
  end
  b.x, b.y = b.x + b.vx, b.y + b.vy
  if b.x < 2 or b.x > 125 then b.vx, b.x = -b.vx, math.max(2, math.min(125, b.x)) sfx("SFX_WALL") end
  if b.y < 2 then b.vy, b.y = -b.vy, 2 sfx("SFX_WALL") end
  if b.vy > 0 and b.y >= 118 and b.y <= 122 and b.x >= pad.x - 2 and b.x <= pad.x + pad.w + 2 then
    local k = (b.x - pad.x) / pad.w - 0.5 -- where on the paddle: the edges send it sideways
    local speed = math.min(3, math.sqrt(b.vx ^ 2 + b.vy ^ 2) * 1.02)
    b.vx, b.vy = speed * k * 1.6, -math.sqrt(math.max(0.5, speed ^ 2 - (speed * k * 1.6) ^ 2))
    sfx("SFX_PAD")
  end
  for i = #bricks, 1, -1 do
    local k = bricks[i]
    if b.x + 2 > k.x and b.x - 2 < k.x + BW and b.y + 2 > k.y and b.y - 2 < k.y + BH then
      local ox = math.min(b.x + 2 - k.x, k.x + BW - (b.x - 2)) -- the side it came through: the smaller overlap
      local oy = math.min(b.y + 2 - k.y, k.y + BH - (b.y - 2))
      if ox < oy then b.vx = -b.vx else b.vy = -b.vy end
      table.remove(bricks, i)
      score = score + 10 * (7 - k.row)
      sparkle(k)
      shake = 4
      sfx("SFX_BRICK" .. k.row)
      break
    end
  end
  if b.y > 132 then
    lives = lives - 1
    sfx("SFX_LOSE")
    shake = 8
    if lives <= 0 then state, t = "over", 0 else b.served = false end
  end
end

function _update()
  t = t + 1
  if shake > 0 then shake = shake - 1 end
  for i = #sparks, 1, -1 do
    local s = sparks[i]
    s.x, s.y, s.vy, s.life = s.x + s.vx, s.y + s.vy, s.vy + 0.08, s.life - 1
    if s.life <= 0 then table.remove(sparks, i) end
  end
  if state == "title" then
    if btnp("a") or btnp("start") then score, lives, level, state = 0, 3, 1, "play" load_level(1) end
  elseif state == "play" then
    local dx = (btn("right") and 1 or 0) - (btn("left") and 1 or 0)
    pad.x = math.max(0, math.min(128 - pad.w, pad.x + dx * 2.5))
    update_ball()
    if #bricks == 0 then
      if level == #LEVELS then state, t = "won", 0 else level = level + 1 load_level(level) end
    end
  elseif (state == "over" or state == "won") and t > 60 and btnp("a") then
    state = "title"
  end
end

-- ------------------------------------------------------------------ drawing: on the 128x128 canvas, as PICO-8 does

local function say(s, x, y, colour) -- PICO-8's letters are four of its pixels wide: eight of the console's
  text(s, SX + x * 2, SY + y * 2, {font = "p8", color = P8[colour]})
end

function _draw()
  cls(P8[0])
  target("P8")
  cls(P8[1])
  if state == "title" then
    for i = 0, 15 do circ(64 + math.cos(t / 30 + i / 2.5) * 40, 70 + math.sin(t / 22 + i / 2.5) * 20, 3, P8[i]) end
  else
    for _, k in ipairs(bricks) do
      rect(k.x, k.y, BW, BH, P8[k.colour])
      rect(k.x, k.y + BH - 1, BW, 1, P8[k.colour == 10 and 9 or 5]) -- a shadow under each brick
    end
    rect(pad.x, 120, pad.w, 3, P8[7])
    rect(pad.x + 1, 121, pad.w - 2, 1, P8[6])
    circ(ball.x, ball.y, 2, P8[7])
    for _, s in ipairs(sparks) do pset(s.x, s.y, P8[s.life > 8 and s.colour or 5]) end
    for i = 1, lives do -- a heart for each life, pixel by pixel
      local x = 128 - i * 8
      rect(x, 3, 2, 1, P8[8]) rect(x + 3, 3, 2, 1, P8[8]) rect(x - 1, 4, 7, 2, P8[8])
      rect(x, 6, 5, 1, P8[8]) rect(x + 1, 7, 3, 1, P8[8]) pset(x + 2, 8, P8[8])
    end
  end
  target()
  local ox, oy = shake > 0 and math.random(-2, 2) or 0, shake > 0 and math.random(-2, 2) or 0
  img("P8", SX + ox, SY + oy, look)
  if state == "title" then
    say("LADRILLOS", 46, 30, 7 + (t // 8) % 9)
    if (t // 20) % 2 == 0 then say("PULSA A", 50, 100, 6) end
  else
    say(string.format("%05d", score), 2, 2, 7)
    say("NIVEL " .. level, 50, 2, 6)
    if state == "over" then say("FIN", 58, 70, 8) elseif state == "won" then say("¡GANASTE!", 46, 70, 11) end
    if state == "play" and not ball.served then say("A: SACAR", 48, 100, 6) end
  end
end
