-- Asalto al cañón: run and gun, the way a Neo Geo one looks. Every pixel at the screen's full 480x320, from packed
-- pictures (art.py): a canyon far behind (mirrored every other time, so it repeats with no seam), a ruined town street
-- in front, long, its pieces joined behind columns and palms; a heroine of eleven frames (0 still, 1-5 running, 6-10
-- firing), scrap robots that waddle and shoot, a walking tank at the end. A machine gun: hold A. Jump: B.
local juice = require("juice")
local particles = require("particles")

local FLOOR = 292                    -- where feet are
local CHUNK, CHUNKS = 645, 10        -- the street: pieces this wide (BG_NEAR), the level CHUNKS of them long
local LEVEL_W = CHUNK * CHUNKS
local FAR_W = 614
local HERO = {w = 128, h = 96, ax = 50, ay = 94}   -- the sheets' frame size and where the feet are (art/make_art.py)
local ROBOT = {ax = 52, ay = 78}
local WALKER = {ax = 150, ay = 158}
local BOOM = {ax = 72, ay = 72}
local WAVES = {                      -- when the camera reaches x: robots, from the right (or the left, negative)
  {300, 2}, {900, 3}, {1500, -2}, {1500, 2}, {2100, 4}, {2800, 3}, {3300, -3}, {3600, 4}, {4300, 5}, {4800, 3},
}

local fx = particles.new()
local shots, booms, wave = {}, {}, 1
hero, robots, foes, boss, cam = {}, {}, {}, nil, 0 -- (global: tests/asalto.script reads and moves them)
state, score = "title", 0
local timer = 0

local function reset()
  hero = {x = 120, y = FLOOR, vy = 0, dir = 1, frame = 0, t = 0, hp = 5, hurt = 0, cool = 0, ground = true}
  robots, shots, foes, booms, cam, wave, boss, score = {}, {}, {}, {}, 0, 1, nil, 0
  fx:clear()
  state, timer = "intro", 0
end

function _init()
  show(0) -- no 240x160 world: every pixel at the screen's resolution
  sound("SND_GUN", {wave = "noise", freq = 1200, slide = -3000, sustain = 0.01, decay = 0.05, volume = 0.18})
  sound("SND_ZAP", "laser", 4)
  sound("SND_BOOM", "explosion", 3)
  sound("SND_BIG", "explosion", 9)
  sound("SND_HIT", "hit", 2)
  sound("SND_OUCH", "hit", 11)
  sound("SND_GO", "powerup", 5)
end

-- ------------------------------------------------------------------ things that move

local function boom(x, y, big)
  booms[#booms + 1] = {x = x, y = y, t = 0, k = big and 1.6 or 1}
  fx:burst(x, y, big and 30 or 14, {speed = big and 5 or 3.5, gravity = 0.2, life = 40, size = 3, shape = "square",
                                     colours = {0xFFE080, 0xC07030, 0x504840}})
  sfx(big and "SND_BIG" or "SND_BOOM", big and 1 or 0.7)
  juice.shake(big and 8 or 3)
end

local function spawn(n)
  for i = 1, math.abs(n) do
    local left = n < 0
    robots[#robots + 1] = {x = left and cam - 30 - i * 60 or cam + 470 + i * 60, y = FLOOR, hp = 3, t = math.random(40),
                           flash = 0, cool = 60 + math.random(60), dir = left and 1 or -1, stop = 110 + math.random(140)}
  end
end

local function fire()
  local h = hero
  h.cool = 5
  local y = h.y - 52 + math.random(-2, 2)
  shots[#shots + 1] = {x = h.x + h.dir * 44, y = y, vx = h.dir * 10}
  sfx("SND_GUN", 0.5, {pitch = 0.9 + math.random() * 0.2})
end

local function hits(s, x0, y0, x1, y1) return s.x > x0 and s.x < x1 and s.y > y0 and s.y < y1 end

local function update_hero()
  local h = hero
  local dx = (btn("right") and 1 or 0) - (btn("left") and 1 or 0)
  if dx ~= 0 then h.dir = dx end
  h.x = math.max(cam + 30, math.min(LEVEL_W - 30, h.x + dx * 2.6))
  if h.ground and btnp("b") then h.vy, h.ground = -9.5, false end
  h.vy = h.vy + 0.5
  h.y = h.y + h.vy
  if h.y >= FLOOR then h.y, h.vy, h.ground = FLOOR, 0, true end
  h.cool = h.cool - 1
  local firing = btn("a")
  if firing and h.cool <= 0 then fire() end
  h.t = h.t + 1
  if not h.ground then h.frame = 3
  elseif dx ~= 0 then h.frame = 1 + (h.t // 5) % 5
  elseif firing then h.frame = 6 + (h.t // 3) % 5
  else h.frame = 0 end
  if h.hurt > 0 then h.hurt = h.hurt - 1 end
end

local function hurt_hero()
  if hero.hurt > 0 or state ~= "play" then return end
  hero.hp, hero.hurt = hero.hp - 1, 60
  sfx("SND_OUCH")
  juice.shake(6)
  if hero.hp <= 0 then state, timer = "over", 0 boom(hero.x, hero.y - 40, true) end
end

local function update_robots()
  for i = #robots, 1, -1 do
    local r = robots[i]
    r.t = r.t + 1
    if r.flash > 0 then r.flash = r.flash - 1 end
    r.dir = hero.x < r.x and -1 or 1
    local d = math.abs(hero.x - r.x)
    r.cool = r.cool - 1
    if r.cool <= 0 and d < 420 then -- a red shot
      r.cool, r.firing = 110 + math.random(60), 12
      foes[#foes + 1] = {x = r.x + r.dir * 44, y = r.y - 40, vx = r.dir * 3.2, vy = 0}
      sfx("SND_ZAP", 0.4)
    end
    if r.firing and r.firing > 0 then r.firing = r.firing - 1
    elseif d > r.stop then r.x = r.x + r.dir * 1.3 end
    if r.hp <= 0 then
      boom(r.x, r.y - 40)
      score = score + 100
      table.remove(robots, i)
    elseif r.x < cam - 300 or r.x > cam + 900 then table.remove(robots, i) end
  end
end

local function update_boss()
  local b = boss
  if not b then return end
  b.t = b.t + 1
  if b.flash > 0 then b.flash = b.flash - 1 end
  if b.dead then
    if b.t == 1 then -- the robots go with it
      for _, r in ipairs(robots) do boom(r.x, r.y - 40) end
      robots = {}
    end
    if b.t % 8 == 0 then boom(b.x + math.random(-90, 90), b.y - math.random(20, 140), b.t % 24 == 0) end
    if b.t > 150 then boss, state, timer = nil, "clear", 0 end
    return
  end
  local target = b.t % 600 < 300 and LEVEL_W - 130 or LEVEL_W - 300
  if math.abs(b.x - target) > 2 then b.x = b.x + (target > b.x and 0.7 or (b.x > LEVEL_W - 130 and -2 or -0.7)) end
  b.cool = b.cool - 1
  if b.cool <= 0 then -- two shells that fall where the heroine is going
    b.cool, b.firing = 100, 16
    for k = 0, 1 do
      foes[#foes + 1] = {x = b.x - 120, y = b.y - 106 + k * 18, vx = -3 - k * 1.5 + (hero.x - b.x) / 200, vy = -4, shell = true}
    end
    sfx("SND_BOOM", 0.6)
    juice.shake(2)
  end
  if b.firing > 0 then b.firing = b.firing - 1 end
  if b.t % 240 == 0 then spawn(2) end
  if b.hp <= 0 then b.dead, b.t = true, 0 score = score + 5000 end
end

local function update_shots()
  for i = #shots, 1, -1 do
    local s = shots[i]
    s.x = s.x + s.vx
    local gone = s.x < cam - 20 or s.x > cam + 500
    for _, r in ipairs(robots) do
      if not gone and hits(s, r.x - 30, r.y - 76, r.x + 30, r.y) then
        r.hp, r.flash, gone = r.hp - 1, 3, true
        sfx("SND_HIT", 0.3)
        fx:burst(s.x, s.y, 4, {speed = 2, life = 8, size = 1, colours = {0xFFFFFF, 0xFFD040}})
      end
    end
    if not gone and boss and not boss.dead and hits(s, boss.x - 110, boss.y - 150, boss.x + 110, boss.y - 20) then
      boss.hp, boss.flash, gone = boss.hp - 1, 3, true
      fx:burst(s.x, s.y, 4, {speed = 2, life = 8, size = 1, colours = {0xFFFFFF, 0xFFD040}})
    end
    if gone then table.remove(shots, i) end
  end
  for i = #foes, 1, -1 do
    local f = foes[i]
    f.x, f.y = f.x + f.vx, f.y + f.vy
    if f.shell then f.vy = f.vy + 0.18 end
    local gone = f.x < cam - 40 or f.x > cam + 520
    if hits(f, hero.x - 18, hero.y - 80, hero.x + 18, hero.y) then hurt_hero() gone = true end
    if f.shell and f.y >= FLOOR - 6 then boom(f.x, FLOOR - 30) gone = true
      if math.abs(f.x - hero.x) < 50 then hurt_hero() end
    end
    if gone then table.remove(foes, i) end
  end
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
    if btnp("a") or btnp("start") then reset() end
    return
  end
  if frozen then return end
  if state == "intro" and timer > 90 then state = "play" sfx("SND_GO") end
  if state == "play" or state == "intro" then update_hero() end
  update_robots()
  update_boss()
  update_shots()
  if state == "play" then
    while WAVES[wave] and cam >= WAVES[wave][1] do spawn(WAVES[wave][2]) wave = wave + 1 end
    if not boss and cam >= LEVEL_W - 480 then
      boss = {x = LEVEL_W + 160, y = FLOOR, hp = 120, t = 0, flash = 0, cool = 160, firing = 0}
    end
  end
  if state == "play" then cam = math.max(cam, math.min(LEVEL_W - 480, hero.x - 180)) end -- only forwards
  if (state == "over" or state == "clear") and timer > 120 and (btnp("a") or btnp("start")) then state = "title" end
end

-- ------------------------------------------------------------------ drawing

local MIRROR = {flip_x = true}

local function stage()
  local fx0 = -(cam * 0.3) % (2 * FAR_W) -- the far layer, mirrored every other time: no seam
  for k = -1, 1 do
    local x = cam + fx0 + k * 2 * FAR_W - 2 * FAR_W + 480
    if x + 2 * FAR_W > cam and x < cam + 480 then
      img("BG_FAR", x, 0)
      img("BG_FAR", x + FAR_W, 0, MIRROR)
    end
  end
  local first = cam // CHUNK
  for c = first, first + 1 do -- the street: its pieces, every other one mirrored
    if c < CHUNKS then
      if c % 2 == 1 then img("BG_NEAR", c * CHUNK, 0, MIRROR) else img("BG_NEAR", c * CHUNK, 0) end
    end
  end
end

local look = {} -- img's options, one table filled again for each call: no garbage for Lua to collect every frame

local function draw_robot(r)
  local o = look
  o.frame, o.flip_x, o.tint = r.firing and r.firing > 0 and 5 or 1 + (r.t // 7) % 4, r.dir > 0, r.flash > 0 and 0xFFFFFF or nil
  img("SPR_ROBOT", r.x - (r.dir > 0 and 96 - ROBOT.ax or ROBOT.ax), r.y - ROBOT.ay, o)
end

local function draw_hero()
  local h = hero
  if h.hurt > 0 and h.hurt % 6 < 3 then return end
  local flip = h.dir < 0
  look.frame, look.flip_x, look.tint = h.frame, flip, nil
  img("SPR_HERO", h.x - (flip and HERO.w - HERO.ax or HERO.ax), h.y - HERO.ay, look)
end

local function draw_boss()
  local b = boss
  if not b then return end
  local o = look
  o.frame, o.flip_x, o.tint = b.firing > 0 and 5 or 1 + (b.t // 10) % 4, false, b.flash > 0 and 0xFFFFFF or nil
  if b.dead and b.t % 4 < 2 then o.tint = 0x402018 end
  img("SPR_WALKER", b.x - WALKER.ax, b.y - WALKER.ay, o)
end

local function bullets()
  for _, s in ipairs(shots) do
    rect(s.x - 7, s.y - 2, 14, 4, 0xFFD040)
    rect(s.x - 3, s.y - 1, 8, 2, 0xFFFFE0)
  end
  for _, f in ipairs(foes) do
    if f.shell then circ(f.x, f.y, 6, 0x302820) circ(f.x - 2, f.y - 2, 2, 0x908070)
    else circ(f.x, f.y, 6, 0xFF3020) circ(f.x, f.y, 3, 0xFFC0A0) end
  end
  for _, b in ipairs(booms) do
    local k = b.k
    look.frame, look.flip_x, look.tint, look.scale = b.t // 4, false, nil, k
    img("SPR_BOOM", b.x - BOOM.ax * k, b.y - BOOM.ay * k, look)
    look.scale = nil
  end
end

local function hud()
  text(string.format("%07d", score), 16, 12, {font = "arcade", scale = 2, color = 0xFFE070, outline = 0x200010})
  for i = 1, 5 do rect(16 + (i - 1) * 18, 40, 14, 8, i <= hero.hp and 0xF04030 or 0x402020) end
  if boss and not boss.dead then
    rect(264, 14, 200, 12, 0x101018)
    rect(266, 16, math.floor(196 * boss.hp / 120), 8, 0xF0A020)
    text("TANQUE ARAÑA", 464, 32, {font = "arcade", align = "right", color = 0xFFFFFF, outline = 0x200010})
  end
end

local function title()
  img("BG_FAR", -100, 0)
  img("BG_NEAR", -100, 0)
  img("SPR_WALKER", 270, FLOOR - WALKER.ay, {frame = 0})
  img("SPR_HERO", 60, FLOOR - HERO.ay, {frame = 6 + (timer // 3) % 5})
  text("ASALTO", 240, 16, {font = "arcade", scale = 4, align = "center", color = 0xFFE070, gradient = 0xFF5020,
                           outline = 0x200010})
  text("AL CAÑON", 240, 82, {font = "arcade", scale = 2, align = "center", color = 0xFFFFFF, outline = 0x200010})
  if (timer // 30) % 2 == 0 then
    text("PULSA A", 240, 116, {font = "arcade", align = "center", color = 0xFFE070, outline = 0x200010})
  end
end

function _draw()
  if state == "title" then title() return end
  local ox, oy = juice.offset()
  camera(cam + ox, oy) -- from here, everything where it is in the level
  stage()
  for _, r in ipairs(robots) do draw_robot(r) end
  draw_boss()
  draw_hero()
  bullets()
  fx:draw()
  camera()
  hud()
  if state == "intro" then
    text("¡ADELANTE!", 240, 120, {font = "arcade", scale = 3, align = "center", color = 0xFFE070, gradient = 0xFF6020,
                                  outline = 0x200010})
  elseif state == "over" then
    text("FIN", 240, 120, {font = "arcade", scale = 4, align = "center", color = 0xFFFFFF, gradient = 0xFF4040,
                           outline = 0x200010})
  elseif state == "clear" then
    text("MISION", 240, 96, {font = "arcade", scale = 3, align = "center", color = 0xFFE070, gradient = 0xFF6020,
                             outline = 0x200010, wave = 2}) -- (the arcade font has no capital accents)
    text("CUMPLIDA", 240, 136, {font = "arcade", scale = 2, align = "center", color = 0xFFFFFF, outline = 0x200010})
    text(string.format("%07d", score), 240, 170, {font = "arcade", scale = 2, align = "center", color = 0xFFE070,
                                                  outline = 0x200010})
  end
  juice.draw()
end
