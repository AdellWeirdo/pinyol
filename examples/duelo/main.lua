-- Duelo en el puerto: one against one, the way a Neo Geo fighting game looks. Everything is drawn at the screen's
-- full 480x320 from packed pictures (art.py): the sky and the city far behind, the crowd and the pier, two big
-- fighters of eleven frames each (0 still, 1-5 walking, 6-10 striking). The player picks a fighter; the console plays
-- the other. Best of three rounds of sixty seconds.
local juice = require("juice")
local particles = require("particles")

local STAGE_W, FLOOR = 572, 292      -- the stage's width (the near layer's), where the feet are
local NEAR_Y = 320 - 175
local REACH, CLOSEST = 132, 92       -- a strike lands within REACH of the body; bodies never closer than CLOSEST
local STRIKE = {6, 6, 7, 7, 7, 7, 8, 8, 8, 8, 8, 9, 9, 9, 9, 10, 10, 10, 10, 10} -- a strike, frame by frame (ticks)
local ACTIVE = 7                     -- the tick of the strike that can land (its first frame 8)
local FIGHTERS = {{id = "SPR_KAI", name = "KAI"}, {id = "SPR_RAN", name = "RAN"}}

local fx = particles.new()
state, round = "title", 1 -- read by tests/duelo.script
local timer, pick, clock, message = 0, 1, 0, nil
p = {} -- the two fighters
local cam = 0

local function fighter(who, x, dir, cpu)
  return {id = FIGHTERS[who].id, name = FIGHTERS[who].name, x = x, dir = dir, cpu = cpu, hp = 100, shown = 100,
          act = "idle", t = 0, frame = 0, flash = 0, wins = 0, guard = false, think = 0, plan = "near"}
end

local function new_round()
  p[1].x, p[1].dir, p[2].x, p[2].dir = 190, 1, 382, -1
  for _, f in ipairs(p) do f.hp, f.shown, f.act, f.t, f.flash, f.guard = 100, 100, "idle", 0, 0, false end
  state, timer, clock = "intro", 0, 60 * 60
  sfx("SND_ROUND")
end

local function start(who)
  p = {fighter(who, 190, 1, false), fighter(3 - who, 382, -1, true)}
  round = 1
  new_round()
end

function _init()
  show(0) -- no 240x160 world: every pixel at the screen's resolution
  sound("SND_HIT", "hit", 7)
  sound("SND_BLOCK", "blip", 3)
  sound("SND_SWING", {wave = "noise", freq = 900, slide = -4000, sustain = 0.03, decay = 0.08, volume = 0.25})
  sound("SND_KO", "explosion", 5)
  sound("SND_ROUND", "powerup", 2)
end

-- ------------------------------------------------------------------ fighting

local function other(f) return f == p[1] and p[2] or p[1] end

local function strike(f)
  if f.act == "idle" or f.act == "walk" then f.act, f.t = "strike", 0 sfx("SND_SWING", 0.6) end
end

local function land(a, b) -- a's strike reaches b
  local blocked = b.guard and b.act ~= "strike"
  local fist_x, fist_y = a.x + a.dir * 96 - cam, FLOOR - 120
  if blocked then
    b.hp = math.max(0, b.hp - 2)
    b.x = b.x + a.dir * 10
    sfx("SND_BLOCK")
    fx:burst(fist_x, fist_y, 8, {speed = 2.5, colours = {0x80C0FF, 0xFFFFFF}, life = 14, size = 2})
    juice.freeze(3)
  else
    b.hp = math.max(0, b.hp - 10)
    b.act, b.t, b.flash = "hurt", 0, 8
    sfx("SND_HIT")
    fx:burst(fist_x, fist_y, 18, {speed = 3.5, colours = {0xFFF080, 0xFF8030, 0xFFFFFF}, life = 18, size = 3})
    juice.shake(5)
    juice.freeze(6) -- a hit stops the picture a moment: it feels heavy
  end
end

local function step(f)
  local o = other(f)
  f.dir = o.x > f.x and 1 or -1
  f.t = f.t + 1
  if f.flash > 0 then f.flash = f.flash - 1 end
  if f.act == "strike" then
    f.frame = STRIKE[math.min(f.t, #STRIKE)]
    if f.t == ACTIVE and math.abs(o.x - f.x) <= REACH then land(f, o) end
    if f.t >= #STRIKE then f.act, f.t = "idle", 0 end
  elseif f.act == "hurt" then
    f.frame, f.x = 0, f.x - f.dir * (f.t < 8 and 2 or 0) -- pushed back, then steady
    if f.t >= 16 then f.act, f.t = "idle", 0 end
  elseif f.act == "ko" then
    f.frame = 0
  end
  f.x = math.max(40, math.min(STAGE_W - 40, f.x))
  if math.abs(o.x - f.x) < CLOSEST then f.x = o.x - f.dir * CLOSEST end
  if f.shown > f.hp then f.shown = f.shown - 0.5 end -- the red part of the bar: what was just lost, going
end

local function walk(f, dx) -- dx: -1, 0 or 1; walking away from the other is guarding
  if f.act ~= "idle" and f.act ~= "walk" then return end
  f.guard = dx ~= 0 and dx ~= f.dir
  if dx == 0 then f.act, f.frame = "idle", 0 return end
  f.act = "walk"
  f.x = f.x + dx * (f.guard and 1.6 or 2.2)
  local k = (f.t // 6) % 5 -- frames 1-5, backwards when stepping back
  f.frame = 1 + (dx == f.dir and k or 4 - k)
end

local function player(f)
  walk(f, (btn("right") and 1 or 0) - (btn("left") and 1 or 0))
  if btnp("a") or btnp("b") then strike(f) end
end

local function cpu(f) -- keeps near, strikes when in reach, steps back to guard when the other winds up
  local o = other(f)
  local d = math.abs(o.x - f.x)
  f.think = f.think - 1
  if f.think <= 0 then
    f.think = 20 + math.random(30)
    f.plan = math.random() < 0.25 and "back" or "near"
  end
  if o.act == "strike" and o.t < 4 and d < REACH + 20 and math.random() < 0.08 then f.plan, f.think = "guard", 24 end
  local dx = 0
  if f.plan == "guard" or f.plan == "back" then dx = -f.dir
  elseif d > REACH - 10 then dx = f.dir end
  walk(f, dx)
  if d <= REACH - 8 and f.plan == "near" and math.random() < 0.05 then strike(f) end
end

local function round_over(winner, why)
  state, timer, message = "ko", 0, why
  if winner then winner.wins = winner.wins + 1 end
  sfx("SND_KO")
  juice.freeze(20)
end

-- ------------------------------------------------------------------ the loop

function _update()
  local frozen = juice.update()
  fx:update()
  timer = timer + 1
  if state == "title" then
    if btnp("left") then pick = 1 end
    if btnp("right") then pick = 2 end
    if btnp("a") or btnp("start") then start(pick) end
    return
  end
  if frozen then return end
  if state == "intro" then
    if timer > 90 then state, timer = "fight", 0 end
  elseif state == "fight" then
    for _, f in ipairs(p) do if f.cpu then cpu(f) else player(f) end end
    for _, f in ipairs(p) do step(f) end
    clock = clock - 1
    for i, f in ipairs(p) do
      if f.hp <= 0 then f.act = "ko" round_over(p[3 - i], "K.O.") return end
    end
    if clock <= 0 then round_over(p[1].hp ~= p[2].hp and (p[1].hp > p[2].hp and p[1] or p[2]) or nil, "¡TIEMPO!") end
  elseif state == "ko" then
    for _, f in ipairs(p) do if f.shown > f.hp then f.shown = f.shown - 0.5 end end
    if timer > 150 then
      if p[1].wins >= 2 or p[2].wins >= 2 then state, timer = "over", 0
      else round = round + 1 new_round() end
    end
  elseif state == "over" then
    if timer > 60 and (btnp("a") or btnp("start")) then state, timer = "title", 0 end
  end
  local mid = (p[1].x + p[2].x) / 2
  cam = math.floor(math.max(0, math.min(STAGE_W - 480, mid - 240)))
end

-- ------------------------------------------------------------------ drawing

local function stage()
  img("BG_FAR", -57 - cam // 2, 0)
  img("BG_NEAR", -cam, NEAR_Y)
end

local function shadow(x, y) -- a soft dark oval under the feet
  shade(x - 42, y - 2, 84, 4)
  shade(x - 30, y - 4, 60, 8)
end

local function draw_fighter(f, x)
  local flip = f.dir < 0
  local o = {frame = f.frame, flip_x = flip}
  if f.flash > 0 and f.flash % 4 < 2 then o.tint = 0xFFFFFF end -- struck: a white flash
  if f.act == "ko" or f.dim then o.tint = 0x3A2030 end -- beaten, or not picked
  local shake = f.act == "hurt" and f.t < 8 and (f.t % 2 * 4 - 2) or 0
  shadow(x, FLOOR)
  img(f.id, x - (flip and 121 or 70) + shake, FLOOR - 181, o)
end

local function bar(x, f, right)
  local w = 200
  rect(x - 2, 14, w + 4, 18, 0x101018)
  local lost, now = math.floor(w * f.shown / 100), math.floor(w * f.hp / 100)
  if right then
    rect(x + w - lost, 16, lost, 14, 0xD02020)
    rect(x + w - now, 16, now, 14, 0xF0C020)
  else
    rect(x, 16, lost, 14, 0xD02020)
    rect(x, 16, now, 14, 0xF0C020)
  end
  rect(right and x + w - now or x, 16, now, 3, 0xFFF0B0) -- a shine along the top
end

local function hud()
  bar(16, p[1], false)
  bar(264, p[2], true)
  text(p[1].name, 18, 36, {font = "arcade", color = 0xFFFFFF, outline = 0x200010})
  text(p[2].name, 462, 36, {font = "arcade", color = 0xFFFFFF, outline = 0x200010, align = "right"})
  for i = 1, p[1].wins do circ(110 + i * 14, 42, 5, 0xF0C020) end
  for i = 1, p[2].wins do circ(370 - i * 14, 42, 5, 0xF0C020) end
  text(tostring(math.max(0, clock // 60)), 240, 12, {font = "arcade", scale = 2, color = 0xFFF0B0, outline = 0x200010,
                                                    align = "center"})
end

local function title()
  img("BG_FAR", -80, 0)
  img("BG_NEAR", -46, NEAR_Y)
  draw_fighter({dir = 1, frame = 0, flash = 0, act = "idle", t = 0, id = "SPR_KAI", dim = pick ~= 1}, 130)
  draw_fighter({dir = -1, frame = 0, flash = 0, act = "idle", t = 0, id = "SPR_RAN", dim = pick ~= 2}, 350)
  text("DUELO", 240, 6, {font = "arcade", scale = 4, align = "center", color = 0xFFE070, gradient = 0xFF6020,
                          outline = 0x200010})
  text("EN EL PUERTO", 240, 76, {font = "arcade", scale = 2, align = "center", color = 0xFFFFFF, outline = 0x200010})
  local names = pick == 1 and "> KAI <    RAN  " or "  KAI    > RAN <"
  text(names, 240, 110, {font = "arcade", align = "center", color = 0xFFFFFF, outline = 0x200010})
  if (timer // 30) % 2 == 0 then
    text("PULSA A", 240, 300, {font = "arcade", align = "center", color = 0xFFE070, outline = 0x200010})
  end
end

function _draw()
  if state == "title" then title() fx:draw() return end
  camera(juice.offset())
  stage()
  local a, b = p[1], p[2] -- the one striking in front
  if b.act == "strike" then a, b = b, a end
  draw_fighter(a, a.x - cam)
  draw_fighter(b, b.x - cam)
  camera()
  fx:draw()
  hud()
  if state == "intro" then
    local t = timer < 50 and ("ROUND " .. round) or "¡PELEA!"
    text(t, 240, 130, {font = "arcade", scale = 3, align = "center", color = 0xFFE070, gradient = 0xFF6020,
                       outline = 0x200010})
  elseif state == "ko" then
    text(message, 240, 120, {font = "arcade", scale = 4, align = "center", color = 0xFFFFFF, gradient = 0xFF4040,
                             outline = 0x200010, shake = timer < 30 and 2 or 0})
  elseif state == "over" then
    local w = p[1].wins >= 2 and p[1] or p[2]
    text("GANA " .. w.name, 240, 120, {font = "arcade", scale = 3, align = "center", color = 0xFFE070,
                                        gradient = 0xFF6020, outline = 0x200010})
    if timer > 60 then text("A: OTRA VEZ", 240, 180, {font = "arcade", align = "center", color = 0xFFFFFF, outline = 0x200010}) end
  end
  juice.draw()
end
