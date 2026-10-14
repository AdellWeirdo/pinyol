-- Tormenta: a vertical shoot-'em-up, the way the arcade's were (the monitor turned on its side): the game is drawn
-- on a 160x240 canvas standing up and shown turned a quarter round and twice as big (a low arcade resolution, and
-- a quarter of the pixels to clear and turn each frame), so the console is held on its side, its left
-- edge down. The arrows are read turned too. Bullets in hundreds: swarms, moved and drawn in C (docs/lua.md). No
-- pictures: ships drawn with polygons, the sky with rectangles and a swarm of streaks.
-- Holding the console on its side: the D-pad moves, A fires (held), B moves slowly for squeezing between bullets.
local VW, VH = 160, 240
local HIT = 2 -- half the ship's real size: only its heart is hit, as in those games

state, score, lives = "title", 0, 3 -- (global: tests/tormenta.script)
ship, foes, boss = {}, {}, nil
local t, flash = 0, 0
wave, shots, bullets, streaks = 0, nil, nil, nil -- (global too: the test)
local look = {angle = 90, scale = 2}

local function dpad() -- the arrows, read as they point with the console turned (its left edge down)
  return (btn("down") and 1 or 0) - (btn("up") and 1 or 0), (btn("left") and 1 or 0) - (btn("right") and 1 or 0)
end

function _init()
  show(0)
  canvas("V", VW, VH)
  canvas("ORB", 5, 5) target("ORB") circ(2, 2, 2, 0xFF4080) pset(2, 2, 0xFFF0F8) target()
  canvas("SHOT", 2, 6) target("SHOT") rect(0, 0, 2, 6, 0x80F0FF) rect(1, 0, 1, 6, 0xFFFFFF) target()
  canvas("STREAK", 1, 5) target("STREAK") rect(0, 0, 1, 5, 0x384878) target()
  local area = {-16, -16, VW + 16, VH + 16}
  shots, bullets, streaks = swarm(200, area), swarm(1500, area), swarm(120, area)
  sound("SFX_SHOT", {wave = "square", freq = 1800, slide = -3000, sustain = 0.01, decay = 0.03, volume = 0.12})
  sound("SFX_POP", {wave = "noise", freq = 700, slide = -800, sustain = 0.03, decay = 0.15, volume = 0.3})
  sound("SFX_BOOM", "explosion", 8)
  sound("SFX_HIT", {wave = "saw", freq = 600, slide = -900, sustain = 0.1, decay = 0.3, volume = 0.35})
end

local function start()
  state, score, lives, wave, foes, boss = "play", 0, 3, 0, {}, nil
  ship = {x = VW / 2, y = VH - 30, safe = 120}
  shots:clear() bullets:clear()
end

-- ------------------------------------------------------------------ bullets

local function fan(x, y, n, spread, speed) -- n bullets aimed at the ship, spread over that many radians
  local a = math.atan(ship.y - y, ship.x - x)
  for i = 1, n do
    local b = a + (i - (n + 1) / 2) * spread / math.max(1, n - 1)
    bullets:add(x, y, math.cos(b) * speed, math.sin(b) * speed)
  end
end

local function ring(x, y, n, speed, turn)
  for i = 0, n - 1 do
    local a = i / n * 2 * math.pi + (turn or 0)
    bullets:add(x, y, math.cos(a) * speed, math.sin(a) * speed)
  end
end

-- ------------------------------------------------------------------ playing

local function next_wave()
  wave = wave + 1
  if wave > 5 then boss = {x = VW / 2, y = -30, hp = 300, t = 0} return end
  for i = 1, 6 + wave do -- a line of small ships coming in on a curve, from one side or the other
    local left = (wave + i) % 2 == 0
    foes[#foes + 1] = {x = left and -10 - i * 15 or VW + 10 + i * 15, y = 30 + (i % 3) * 20, vx = left and 0.8 or -0.8,
                       hp = 3, t = -i * 6, fire = 50 + math.random(60)}
  end
end

local function update_ship()
  local dx, dy = dpad()
  local speed = btn("b") and 0.8 or 1.7
  ship.x = math.max(5, math.min(VW - 5, ship.x + dx * speed))
  ship.y = math.max(10, math.min(VH - 7, ship.y + dy * speed))
  if ship.safe > 0 then ship.safe = ship.safe - 1 end
  if btn("a") and t % 5 == 0 then
    shots:add(ship.x - 3, ship.y - 6, 0, -4.5) shots:add(ship.x + 3, ship.y - 6, 0, -4.5)
    sfx("SFX_SHOT")
  end
  if ship.safe == 0 and bullets:hit(ship.x - HIT, ship.y - HIT, HIT * 2, HIT * 2) > 0 then
    lives, ship.safe, flash = lives - 1, 150, 8
    bullets:clear()
    sfx("SFX_HIT")
    if lives <= 0 then state, t = "over", 0 end
  end
end

local function update_foes()
  for i = #foes, 1, -1 do
    local f = foes[i]
    f.t = f.t + 1
    if f.t > 0 then
      f.x, f.y = f.x + f.vx, f.y + 0.2 + math.sin(f.t / 30) * 0.4
      f.fire = f.fire - 1
      if f.fire <= 0 and f.y > 0 and f.y < VH * 0.6 then fan(f.x, f.y, 3, 0.5, 1.1) f.fire = 90 + math.random(60) end
      f.hp = f.hp - shots:hit(f.x - 6, f.y - 5, 12, 10)
    end
    if f.hp <= 0 then
      table.remove(foes, i)
      score = score + 100
      sfx("SFX_POP")
    elseif f.t > 0 and (f.x < -40 or f.x > VW + 40 or f.y > VH + 15) then
      table.remove(foes, i)
    end
  end
  if #foes == 0 and not boss then next_wave() end
end

local function update_boss()
  local b = boss
  b.t = b.t + 1
  if b.y < 45 then b.y = b.y + 0.5 return end
  b.x = VW / 2 + math.sin(b.t / 90) * 45
  if b.t % 6 == 0 then -- two arms of a spiral, and a ring now and then
    local a = b.t / 25
    bullets:add(b.x, b.y + 10, math.cos(a) * 1.1, math.sin(a) * 1.1)
    bullets:add(b.x, b.y + 10, math.cos(a + math.pi) * 1.1, math.sin(a + math.pi) * 1.1)
  end
  if b.t % 120 == 0 then ring(b.x, b.y + 10, 24, 0.9, b.t / 60) end
  if b.t % 90 == 45 then fan(b.x, b.y + 15, 5, 0.6, 1.5) end
  b.hp = b.hp - shots:hit(b.x - 25, b.y - 15, 50, 30)
  if b.hp <= 0 then
    score, boss, state, t = score + 5000, nil, "won", 0
    bullets:clear()
    sfx("SFX_BOOM")
  end
end

function _update()
  t = t + 1
  if flash > 0 then flash = flash - 1 end
  if t % 3 == 0 then streaks:add(math.random(VW), -5, 0, 3 + math.random() * 2) end -- the sky rushing past
  streaks:step()
  if state == "title" or state == "over" or state == "won" then
    if (btnp("a") or btnp("start")) and (state == "title" or t > 60) then start() end
    return
  end
  update_ship()
  update_foes()
  if boss then update_boss() end
  shots:step()
  bullets:step()
end

-- ------------------------------------------------------------------ drawing: on the standing canvas, then turned

local function ship_shape(x, y, c)
  poly({x, y - 7, x + 6, y + 5, x, y + 3, x - 6, y + 5}, c)
  pset(x, y, 0xFFFFFF) -- its heart: what bullets hit
end

local function foe_shape(f)
  poly({f.x - 6, f.y - 4, f.x + 6, f.y - 4, f.x, f.y + 5}, 0xF06030)
  circ(math.floor(f.x), math.floor(f.y - 2), 2, 0xFFD060)
end

local function boss_shape(b)
  poly({b.x - 30, b.y - 10, b.x + 30, b.y - 10, b.x + 20, b.y + 10, b.x - 20, b.y + 10}, 0x5040A0)
  poly({b.x - 15, b.y + 10, b.x + 15, b.y + 10, b.x, b.y + 20}, 0x8070E0)
  circ(math.floor(b.x), math.floor(b.y), 5, b.t % 20 < 10 and 0xFF4080 or 0xFFF0F8)
end

local function say(s, y, c, k) text(s, VW // 2, y, {font = "p8", align = "center", color = c, scale = k or 1}) end

function _draw()
  target("V")
  cls(flash > 0 and 0x402030 or 0x0A1028)
  streaks:draw("STREAK")
  if state ~= "title" then
    for _, f in ipairs(foes) do foe_shape(f) end
    if boss then boss_shape(boss) end
    shots:draw("SHOT")
    if state == "play" and (ship.safe == 0 or t % 8 < 5) then ship_shape(ship.x, ship.y, 0x60D0FF) end
    bullets:draw("ORB")
    text(tostring(score), 4, 4, {font = "p8", color = 0xFFFFFF})
    for i = 1, lives do ship_shape(VW - i * 10, 10, 0x60D0FF) end
    if boss then rect(20, 20, math.floor(120 * boss.hp / 300), 2, 0xFF4080) end
  end
  if state == "title" then
    say("TORMENTA", 80, 0xFFF070, 2)
    say("GIRA LA CONSOLA", 115, 0xA0C0FF)
    if (t // 30) % 2 == 0 then say("PULSA A", 150, 0xFFFFFF) end
  elseif state == "over" then say("FIN", 110, 0xFF6060, 2)
  elseif state == "won" then say("¡VICTORIA!", 110, 0xFFF070) end
  target()
  img("V", 240 - VW, 160 - VH, look) -- turned a quarter round, twice as big: its top on the console's right edge
end
