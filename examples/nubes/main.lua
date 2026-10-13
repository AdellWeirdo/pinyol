-- Sobre las nubes: a horizontal shoot-em-up, the way a Neo Geo one looks. Every pixel at the screen's full 480x320,
-- from packed pictures (art.py): a sunset sky that drifts slowly by, a band of clouds rushing past in front (mirrored
-- every other time, so it repeats with no seam), the ship, drones that spin in formation, and a battleship at the end
-- that fills the sky with orbs. A: fire (hold). B: a bomb, three of them, that clears the orbs.
local juice = require("juice")
local particles = require("particles")

local SKY_SLACK = 720 - 480          -- how far the sky can drift: it never needs to repeat
local CLOUD_W, CLOUD_Y = 960, 178
local SHIP = {w = 112, h = 40}
local DRONE = 48
local BOSS = {w = 432, h = 184}
local BOSS_AT = 60 * 45              -- the battleship comes after 45 seconds
local WAVES = {                      -- tick, kind, how many, at which height
  {120, "sine", 6, 90}, {360, "sine", 6, 230}, {600, "dive", 5, 0}, {840, "line", 7, 160}, {1080, "sine", 8, 120},
  {1320, "dive", 6, 0}, {1560, "line", 8, 80}, {1700, "line", 8, 240}, {1900, "sine", 10, 160}, {2200, "dive", 8, 0},
}

local fx = particles.new()
local booms, wave = {}, 1
local bolts = swarm(64) -- the ship's shots and the enemies' orbs: swarms, moved, tested and drawn in C
ship, drones, orbs, boss, t = {}, {}, swarm(1500), nil, 0 -- (global: tests/nubes.script reads and moves them)
state, score = "title", 0
local timer = 0
local look = {} -- img's options, filled again for each call: no garbage every frame

local function reset()
  ship = {x = 60, y = 150, lives = 3, bombs = 3, hurt = 0, cool = 0}
  drones, booms, boss, wave, t, score = {}, {}, nil, 1, 0, 0
  orbs:clear()
  bolts:clear()
  fx:clear()
  state, timer = "play", 0
end

function _init()
  show(0) -- no 240x160 world: every pixel at the screen's resolution
  sound("SND_BOLT", {wave = "square", freq = 900, slide = -2500, duty = 0.25, sustain = 0.02, decay = 0.05, volume = 0.15})
  sound("SND_ORB", "blip", 6)
  sound("SND_BOOM", "explosion", 3)
  sound("SND_BIG", "explosion", 9)
  sound("SND_BOMB", "explosion", 14)
  sound("SND_HIT", "hit", 2)
end

-- ------------------------------------------------------------------ things that move

local function boom(x, y, big)
  booms[#booms + 1] = {x = x, y = y, t = 0, k = big and 1.4 or 0.7}
  fx:burst(x, y, big and 24 or 10, {speed = big and 4 or 2.5, life = 30, size = 2, colours = {0xFFF0A0, 0xFF7040, 0x603050}})
  sfx(big and "SND_BIG" or "SND_BOOM", big and 1 or 0.6)
  if big then juice.shake(6) end
end

local function aim(x, y, speed, spread) -- an orb from (x, y) towards the ship, turned by spread radians
  local a = math.atan(ship.y - y, ship.x + 40 - x) + (spread or 0)
  orbs:add(x, y, math.cos(a) * speed, math.sin(a) * speed)
end

local function spawn(kind, n, y)
  for i = 1, n do
    local d = {kind = kind, x = 500 + i * 46, y = y, y0 = y, t = -i * 12, hp = 2, flash = 0, spin = i}
    if kind == "dive" then d.x, d.y = 500 + i * 60, i % 2 == 0 and -30 or 350 end
    drones[#drones + 1] = d
  end
end

local function update_ship()
  local s = ship
  local dx = (btn("right") and 1 or 0) - (btn("left") and 1 or 0)
  local dy = (btn("down") and 1 or 0) - (btn("up") and 1 or 0)
  s.x = math.max(0, math.min(480 - SHIP.w, s.x + dx * 3.2))
  s.y = math.max(20, math.min(300, s.y + dy * 3.2))
  s.cool = s.cool - 1
  if btn("a") and s.cool <= 0 then
    s.cool = 6
    bolts:add(s.x + 103, s.y - 5, 12, 0)
    bolts:add(s.x + 103, s.y + 9, 12, 0)
    sfx("SND_BOLT", 0.5)
  end
  if btnp("b") and s.bombs > 0 then -- a bomb: every orb gone, every drone hurt, the boss too
    s.bombs = s.bombs - 1
    for i = 1, math.min(#orbs, 60) do
      local x, y = orbs:get(i)
      fx:burst(x, y, 2, {speed = 1, life = 10, colours = {0xFFC0E0}})
    end
    orbs:clear()
    for _, d in ipairs(drones) do d.hp = d.hp - 5 end
    if boss then boss.hp = boss.hp - 30 end
    juice.flash(0xFFFFFF, 6)
    juice.shake(8)
    sfx("SND_BOMB")
  end
  if s.hurt > 0 then s.hurt = s.hurt - 1 end
end

local function hurt_ship()
  local s = ship
  if s.hurt > 0 or state ~= "play" then return end
  boom(s.x + 56, s.y, true)
  s.lives, s.hurt, s.x, s.y = s.lives - 1, 120, 40, 150
  if s.lives <= 0 then state, timer = "over", 0 end
end

local function update_drones()
  for i = #drones, 1, -1 do
    local d = drones[i]
    d.t = d.t + 1
    if d.t > 0 then
      if d.kind == "sine" then d.x, d.y = d.x - 2.4, d.y0 + math.sin(d.t / 18) * 50
      elseif d.kind == "line" then d.x = d.x - (d.t < 50 and 4 or 1.6)
      else -- dive: in from above or below, towards the ship's height, then away to the left
        d.x = d.x - 3
        d.y = d.y + (ship.y - d.y) * 0.03
      end
      if d.t % 90 == 45 and d.x < 470 and d.x > 120 then aim(d.x, d.y, 3) sfx("SND_ORB", 0.3) end
    end
    if d.flash > 0 then d.flash = d.flash - 1 end
    if d.hp <= 0 then boom(d.x, d.y) score = score + 150 table.remove(drones, i)
    elseif d.x < -60 then table.remove(drones, i) end
  end
end

local function update_boss()
  local b = boss
  if not b then return end
  b.t = b.t + 1
  if b.flash > 0 then b.flash = b.flash - 1 end
  if b.dead then
    if b.t % 6 == 0 then boom(b.x + math.random(0, BOSS.w), b.y + math.random(-70, 70), b.t % 18 == 0) end
    if b.t > 160 then boss, state, timer = nil, "clear", 0 score = score + 10000 end
    return
  end
  if b.x > 250 then b.x = b.x - 1.5 end
  b.y = 160 + math.sin(b.t / 90) * 50
  local core_x, core_y = b.x + 222, b.y + 2
  local phase = (b.t // 300) % 3
  if phase == 0 and b.t % 40 == 0 then -- rings from the core
    for k = 0, 23 do
      local a = k / 24 * 2 * math.pi + b.t / 50
      orbs:add(core_x, core_y, math.cos(a) * 2.2, math.sin(a) * 2.2)
    end
    sfx("SND_ORB", 0.6)
  elseif phase == 1 and b.t % 8 == 0 then -- the turrets: aimed, three at a time
    local tx = b.x + 60 + (b.t // 8 % 5) * 70
    for s = -1, 1 do aim(tx, b.y - 60, 3.5, s * 0.25) end
  elseif phase == 2 and b.t % 5 == 0 then -- a spiral
    local a = b.t / 9
    orbs:add(core_x, core_y, math.cos(a) * 2.8, math.sin(a) * 2.8)
    orbs:add(core_x, core_y, -math.cos(a) * 2.8, -math.sin(a) * 2.8)
  end
  if b.hp <= 0 then b.dead, b.t = true, 0 end
end

local function update_shots()
  bolts:step()
  for _, d in ipairs(drones) do -- a drone's box: how many bolts are in it (they go)
    if d.t > 0 then
      local n = bolts:hit(d.x - 26, d.y - 22, 52, 44)
      if n > 0 then d.hp, d.flash = d.hp - n, 3 end
    end
  end
  local b = boss
  if b and not b.dead then
    local n = bolts:hit(b.x + 60, b.y - 70, BOSS.w - 60, 140)
    if n > 0 then
      b.hp, b.flash = b.hp - n, 2
      if b.hp % 10 < n then sfx("SND_HIT", 0.4) end
    end
  end
  orbs:step()
  if orbs:hit(ship.x + 52, ship.y - 5, 12, 10) > 0 then hurt_ship() end -- the ship's heart: small, as in every such game
  for i = #booms, 1, -1 do
    booms[i].t = booms[i].t + 1
    if booms[i].t >= 20 then table.remove(booms, i) end
  end
end

-- ------------------------------------------------------------------ the loop

function _update()
  local frozen = juice.update()
  fx:update()
  timer = timer + 1
  if state == "title" then
    t = t + 1
    if btnp("a") or btnp("start") then reset() end
    return
  end
  if frozen then return end
  t = t + 1
  if state == "play" then update_ship() end
  while WAVES[wave] and t >= WAVES[wave][1] do spawn(WAVES[wave][2], WAVES[wave][3], WAVES[wave][4]) wave = wave + 1 end
  if state == "play" and not boss and t >= BOSS_AT then boss = {x = 500, y = 160, hp = 300, t = 0, flash = 0} end
  update_drones()
  update_boss()
  update_shots()
  if (state == "over" or state == "clear") and timer > 120 and (btnp("a") or btnp("start")) then state = "title" end
end

-- ------------------------------------------------------------------ drawing

local MIRROR = {flip_x = true}

local function sky()
  img("BG_SKY", -math.min(SKY_SLACK, t * 0.1) // 1, 0)
  local x = -(t * 2.2) % (2 * CLOUD_W) -- the clouds rush by, every other copy mirrored
  img("BG_CLOUDS", x - 2 * CLOUD_W, CLOUD_Y)
  img("BG_CLOUDS", x - CLOUD_W, CLOUD_Y, MIRROR)
  img("BG_CLOUDS", x, CLOUD_Y)
  if x + CLOUD_W < 480 then img("BG_CLOUDS", x + CLOUD_W, CLOUD_Y, MIRROR) end
end

local function draw_ship()
  local s = ship
  if state == "over" or (s.hurt > 0 and s.hurt % 8 < 4) then return end
  img("SPR_SHIP", s.x, s.y - SHIP.h // 2)
end

local function draw_drones()
  for _, d in ipairs(drones) do
    if d.t > 0 then
      look.frame, look.tint = (d.t // 4 + d.spin) % 5, d.flash > 0 and 0xFFFFFF or nil
      img("SPR_DRONE", d.x - DRONE // 2, d.y - DRONE // 2, look)
    end
  end
  look.tint = nil
end

local function draw_boss()
  local b = boss
  if not b then return end
  look.frame, look.tint = 0, b.flash > 0 and 0xFFFFFF or (b.dead and b.t % 4 < 2 and 0x401020) or nil
  img("SPR_BOSS", b.x, b.y - BOSS.h // 2, look)
  look.tint = nil
end

local function draw_shots()
  bolts:draw("SPR_BOLT")
  orbs:draw("SPR_ORB")
  for _, b in ipairs(booms) do
    look.frame, look.scale = b.t // 4, b.k
    img("SPR_BOOM", b.x - 72 * b.k, b.y - 72 * b.k, look)
  end
  look.scale = nil
end

local function hud()
  text(string.format("%07d", score), 16, 10, {font = "arcade", scale = 2, color = 0xFFE070, outline = 0x200010})
  for i = 1, ship.lives or 0 do
    look.scale = 0.3
    img("SPR_SHIP", 16 + (i - 1) * 40, 40, look)
  end
  look.scale = nil
  for i = 1, ship.bombs or 0 do circ(470 - (i - 1) * 18, 20, 6, 0xFF60A0) circ(470 - (i - 1) * 18, 20, 3, 0xFFFFFF) end
  if boss and not boss.dead then
    rect(140, 300, 200, 10, 0x200818)
    rect(141, 301, math.max(0, math.floor(198 * boss.hp / 300)), 8, 0xFF4080)
  end
end

local function title()
  sky()
  img("SPR_BOSS", 230, 6)
  img("SPR_SHIP", 60 + math.sin(timer / 30) * 10, 120)
  text("SOBRE LAS", 240, 172, {font = "arcade", scale = 2, align = "center", color = 0xFFFFFF, outline = 0x200010})
  text("NUBES", 240, 212, {font = "arcade", scale = 4, align = "center", color = 0xFFE070, gradient = 0xFF4080,
                           outline = 0x200010})
  if (timer // 30) % 2 == 0 then
    text("PULSA A", 240, 296, {font = "arcade", align = "center", color = 0xFFFFFF, outline = 0x200010})
  end
end

function _draw()
  if state == "title" then title() return end
  camera(juice.offset())
  sky()
  draw_drones()
  draw_boss()
  draw_ship()
  draw_shots()
  fx:draw()
  camera()
  hud()
  if state == "over" then
    text("FIN", 240, 130, {font = "arcade", scale = 4, align = "center", color = 0xFFFFFF, gradient = 0xFF4080,
                           outline = 0x200010})
  elseif state == "clear" then
    text("FASE", 240, 110, {font = "arcade", scale = 3, align = "center", color = 0xFFE070, gradient = 0xFF6020,
                            outline = 0x200010, wave = 2})
    text("SUPERADA", 240, 150, {font = "arcade", scale = 2, align = "center", color = 0xFFFFFF, outline = 0x200010})
  end
  juice.draw()
end
