-- Torneo: one against one, the way a CPS2 fighting game looks (art.py): fighters in 15 colours and see-through, thirty
-- frames each and never zoomed; the camera only pans. The courtyard far behind moves at half the camera's speed, the
-- floor is drawn in bands of two rows, each moved by its own amount (nearer rows faster: the floor's perspective, as
-- that hardware did it with a scroll per line), and pillars in front move faster than everyone. Picking the same
-- fighter twice gives the second one other colours, borrowed from its _B picture (img's pal).
-- A: a slash. B: a kick. Up: a jump. Walking away from the other: guarding.
local juice = require("juice")
local particles = require("particles")

local STAGE_W, CAM_MID = 760, 140     -- the stage's width; the camera's x at its middle
local FLOOR = 300                     -- where the feet are
local FLOOR_TOP, FLOOR_H, FLOOR_W = 248, 72, 820
local K_TOP, K_BOTTOM = 0.62, 1.18    -- how fast the floor's farthest and nearest rows move with the camera
local W, BACK, FEET = 208, 76, 172    -- a frame's width, the body's centre and the feet in it
local CLOSEST, GRAVITY = 84, 0.45
MOVES = {                             -- (global: tests/torneo.script) frames tick by tick; the tick that lands; reach, damage, push
  slash = {frames = {10, 10, 11, 11, 12, 12, 12, 13, 13, 13, 14, 14, 14}, active = 5, reach = 118, damage = 8, push = 8},
  kick = {frames = {15, 15, 16, 16, 16, 17, 17, 17, 18, 18, 18, 18, 19, 19, 19, 19}, active = 6, reach = 138,
          damage = 12, push = 14},
}
local IDLE = {0, 1, 2, 3, 4, 3, 2, 1} -- breathing, a frame every 8 ticks
local FIGHTERS = {{id = "SPR_ALBA", name = "ALBA"}, {id = "SPR_GORM", name = "GORM"}}

local fx = particles.new()
state, round, pick, rival = "title", 1, 1, 2 -- read by tests/torneo.script
local timer, clock, message = 0, 0, nil
p = {} -- the two fighters
cam = CAM_MID

local function fighter(who, x, dir, cpu, pal)
  return {id = FIGHTERS[who].id, name = FIGHTERS[who].name, pal = pal, x = x, y = 0, vy = 0, vx = 0, dir = dir,
          cpu = cpu, hp = 100, shown = 100, act = "idle", t = 0, frame = 0, flash = 0, wins = 0, guard = false,
          think = 0, plan = "near"}
end

local function new_round()
  p[1].x, p[1].dir, p[2].x, p[2].dir = 300, 1, 460, -1
  for _, f in ipairs(p) do
    f.hp, f.shown, f.act, f.t, f.flash, f.guard, f.y, f.vy, f.vx = 100, 100, "idle", 0, 0, false, 0, 0, 0
  end
  state, timer, clock = "intro", 0, 60 * 60
  sfx("SND_ROUND")
end

local function start()
  local mirror = pick == rival -- the same fighter twice: the second in other colours
  p = {fighter(pick, 300, 1, false), fighter(rival, 460, -1, true, mirror and FIGHTERS[rival].id .. "_B" or nil)}
  round = 1
  new_round()
end

function _init()
  show(0) -- no 240x160 world: every pixel at the screen's resolution
  sound("SND_HIT", "hit", 7)
  sound("SND_HEAVY", "hit", 11)
  sound("SND_BLOCK", "blip", 3)
  sound("SND_SWING", {wave = "noise", freq = 900, slide = -4000, sustain = 0.03, decay = 0.08, volume = 0.25})
  sound("SND_JUMP", "jump", 2)
  sound("SND_KO", "explosion", 5)
  sound("SND_ROUND", "powerup", 2)
end

-- ------------------------------------------------------------------ fighting

local function other(f) return f == p[1] and p[2] or p[1] end
local function free(f) return f.act == "idle" or f.act == "walk" end

local function attack(f, move)
  if free(f) then f.act, f.move, f.t = "attack", MOVES[move], 0 sfx("SND_SWING", 0.6) end
end

local function jump(f, dx)
  if free(f) then f.act, f.t, f.vx = "jump", 0, dx * 2.6 sfx("SND_JUMP", 0.4) end
end

local function land(a, b) -- a's attack reaches b
  local m = a.move
  local hit_x, hit_y = a.x + a.dir * (m.reach - 30) - cam, FLOOR - 100
  if b.guard and free(b) then
    b.hp = math.max(0, b.hp - 2)
    b.act, b.t, b.x = "block", 0, b.x + a.dir * m.push
    sfx("SND_BLOCK")
    fx:burst(hit_x, hit_y, 8, {speed = 2.5, colours = {0x80C0FF, 0xFFFFFF}, life = 14, size = 2})
    juice.freeze(3)
  else
    b.hp = math.max(0, b.hp - m.damage)
    b.act, b.t, b.flash, b.vx, b.vy = "hurt", 0, 8, a.dir * m.push / 6, b.y < 0 and -3 or 0
    sfx(m == MOVES.kick and "SND_HEAVY" or "SND_HIT")
    fx:burst(hit_x, hit_y, 20, {speed = 3.5, colours = {0xFFF080, 0xFF8030, 0xFFFFFF}, life = 18, size = 3})
    juice.shake(m == MOVES.kick and 6 or 4)
    juice.freeze(m == MOVES.kick and 8 or 5)
  end
end

local function step(f)
  local o = other(f)
  if f.y == 0 and f.act ~= "ko" then f.dir = o.x > f.x and 1 or -1 end
  f.t = f.t + 1
  if f.flash > 0 then f.flash = f.flash - 1 end
  if f.act == "idle" then
    f.frame = IDLE[(f.t // 8) % #IDLE + 1]
  elseif f.act == "attack" then
    local fr = f.move.frames
    f.frame = fr[math.min(f.t, #fr)]
    if f.t == f.move.active and math.abs(o.x - f.x) <= f.move.reach and math.abs(o.y - f.y) < 60 then land(f, o) end
    if f.t >= #fr then f.act, f.t = "idle", 0 end
  elseif f.act == "jump" then
    if f.t == 4 then f.vy = -7.5 end -- a crouch first
    f.frame = f.t < 4 and 25 or (f.vy < -2 and 26 or (f.vy < 2 and 27 or 28))
  elseif f.act == "hurt" then
    f.frame = f.t < 8 and 20 or 21
    if f.t >= 16 and f.y == 0 then f.act, f.t = "idle", 0 end
  elseif f.act == "block" then
    f.frame = 22
    if f.t >= 12 then f.act, f.t = "idle", 0 end
  elseif f.act == "ko" then
    f.frame = f.t < 24 and 23 or 24
    f.vx = f.t < 24 and -f.dir * 2 or 0
  end
  f.x, f.y = f.x + f.vx, math.min(0, f.y + f.vy)
  if f.y < 0 or f.vy < 0 then f.vy = f.vy + GRAVITY end
  if f.y == 0 and f.vy > 0 then -- landed
    f.vy, f.vx = 0, 0
    if f.act == "jump" then f.act, f.t, f.frame = "land", 0, 29 end
  end
  if f.act == "land" then f.frame = 29 if f.t >= 6 then f.act, f.t = "idle", 0 end end
  if f.act == "hurt" or f.act == "block" then f.vx = f.vx * 0.8 end
  f.x = math.max(40, math.min(STAGE_W - 40, f.x))
  if f.y == 0 and o.y == 0 and math.abs(o.x - f.x) < CLOSEST then f.x = o.x - f.dir * CLOSEST end
  if f.shown > f.hp then f.shown = f.shown - 0.5 end -- the red part of the bar: what was just lost, going
end

local function walk(f, dx) -- dx: -1, 0 or 1; walking away from the other is guarding
  if not free(f) then return end
  f.guard = dx ~= 0 and dx ~= f.dir
  if dx == 0 then
    if f.act ~= "idle" then f.act, f.t = "idle", 0 end
    return
  end
  f.act = "walk"
  f.x = f.x + dx * (f.guard and 1.6 or 2.2)
  local k = (f.t // 6) % 5 -- frames 5-9, backwards when stepping back
  f.frame = 5 + (dx == f.dir and k or 4 - k)
end

local function player(f)
  local dx = (btn("right") and 1 or 0) - (btn("left") and 1 or 0)
  if btnp("up") then jump(f, dx) end
  walk(f, dx)
  if btnp("a") then attack(f, "slash") elseif btnp("b") then attack(f, "kick") end
end

local function cpu(f) -- keeps near, attacks when in reach, guards when the other winds up, jumps now and then
  local o = other(f)
  local d = math.abs(o.x - f.x)
  f.think = f.think - 1
  if f.think <= 0 then
    f.think = 20 + math.random(30)
    f.plan = math.random() < 0.25 and "back" or "near"
  end
  if o.act == "attack" and o.t < 4 and d < 150 and math.random() < 0.08 then f.plan, f.think = "guard", 24 end
  local dx = 0
  if f.plan == "guard" or f.plan == "back" then dx = -f.dir
  elseif d > 110 then dx = f.dir end
  if d > 200 and math.random() < 0.01 then jump(f, f.dir) end
  walk(f, dx)
  if f.plan == "near" and d <= 110 and math.random() < 0.04 then attack(f, math.random() < 0.6 and "slash" or "kick") end
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
    if btnp("up") or btnp("down") then rival = 3 - rival end
    if btnp("a") or btnp("start") then start() end
    return
  end
  if frozen then return end
  if state == "intro" then
    for _, f in ipairs(p) do step(f) end
    if timer > 90 then state, timer = "fight", 0 end
  elseif state == "fight" then
    for _, f in ipairs(p) do if f.cpu then cpu(f) else player(f) end end
    for _, f in ipairs(p) do step(f) end
    clock = clock - 1
    for i, f in ipairs(p) do
      if f.hp <= 0 then f.act, f.t = "ko", 0 round_over(p[3 - i], "K.O.") return end
    end
    if clock <= 0 then round_over(p[1].hp ~= p[2].hp and (p[1].hp > p[2].hp and p[1] or p[2]) or nil, "¡TIEMPO!") end
  elseif state == "ko" then
    for _, f in ipairs(p) do step(f) end
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

local function stage(c)
  local d = c - CAM_MID
  img("BG_FAR", -80 - d // 2, 0)
  for r = 0, FLOOR_H - 1, 2 do -- the floor: each band of two rows moved by its own amount
    clip(0, FLOOR_TOP + r, 480, 2)
    img("BG_FLOOR", math.floor(-(FLOOR_W - 480) / 2 - d * (K_TOP + (K_BOTTOM - K_TOP) * r / FLOOR_H)), FLOOR_TOP)
  end
  clip()
end

local function shadow(x, y) -- a dark oval under the feet
  shade(x - 38, y - 2, 76, 4)
  shade(x - 26, y - 4, 52, 8)
end

local look = {}
local function draw_fighter(f, x)
  local flip = f.dir < 0
  look.frame, look.flip_x, look.pal, look.tint = f.frame, flip, f.pal, nil
  if f.flash > 0 and f.flash % 4 < 2 then look.tint = 0xFFFFFF end -- struck: a white flash
  if f.dim then look.tint = 0x2A2030 end
  local shake = f.act == "hurt" and f.t < 8 and (f.t % 2 * 4 - 2) or 0
  shadow(x, FLOOR)
  img(f.id, x - (flip and W - 1 - BACK or BACK) + shake, FLOOR - FEET + math.floor(f.y), look)
end

local function front(c)
  img("BG_FRONT", math.floor(-(c - CAM_MID) * 1.35), 0)
end

local function bar(x, f, right)
  local w = 200
  rect(x - 2, 14, w + 4, 16, 0x101018)
  local lost, now = math.floor(w * f.shown / 100), math.floor(w * f.hp / 100)
  local left = right and x + w - now or x
  rect(right and x + w - lost or x, 16, lost, 12, 0xC01818)
  rect(left, 16, now, 12, 0x30C040)
  rect(left, 16, now, 3, 0xB0FFB0) -- a shine along the top
end

local function hud()
  bar(16, p[1], false)
  bar(264, p[2], true)
  text(p[1].name, 18, 34, {font = "arcade", color = 0xFFFFFF, outline = 0x101030})
  text(p[2].name, 462, 34, {font = "arcade", color = 0xFFFFFF, outline = 0x101030, align = "right"})
  for i = 1, p[1].wins do circ(104 + i * 14, 40, 5, 0xFFD030) end
  for i = 1, p[2].wins do circ(376 - i * 14, 40, 5, 0xFFD030) end
  text(string.format("%02d", math.max(0, clock // 60)), 240, 10, {font = "arcade", scale = 2, color = 0xFFF0B0,
                                                                   outline = 0x101030, align = "center"})
end

local function title()
  stage(CAM_MID)
  local same = pick == rival
  draw_fighter({dir = 1, frame = IDLE[(timer // 8) % #IDLE + 1], flash = 0, act = "idle", t = 0, y = 0,
                id = FIGHTERS[pick].id}, 150)
  draw_fighter({dir = -1, frame = IDLE[(timer // 8 + 3) % #IDLE + 1], flash = 0, act = "idle", t = 0, y = 0,
                id = FIGHTERS[rival].id, pal = same and FIGHTERS[rival].id .. "_B" or nil}, 330)
  front(CAM_MID)
  text("TORNEO", 240, 8, {font = "arcade", scale = 4, align = "center", color = 0xFFF0A0, gradient = 0xE04010,
                          outline = 0x101030, shadow = 0x000000})
  text("TU: " .. FIGHTERS[pick].name .. "   RIVAL: " .. FIGHTERS[rival].name, 240, 74,
       {font = "arcade", align = "center", color = 0xFFFFFF, outline = 0x101030})
  text("IZQ/DCHA: TU  ARRIBA: RIVAL", 240, 96, {font = "arcade", align = "center", color = 0xA0C0FF, outline = 0x101030})
  if (timer // 30) % 2 == 0 then
    text("PULSA A", 240, 124, {font = "arcade", align = "center", color = 0xFFE070, outline = 0x101030})
  end
end

function _draw()
  if state == "title" then title() fx:draw() return end
  local ox, oy = juice.offset()
  camera(ox, oy)
  stage(cam)
  local a, b = p[1], p[2] -- the one attacking in front
  if b.act == "attack" then a, b = b, a end
  draw_fighter(a, a.x - cam)
  draw_fighter(b, b.x - cam)
  front(cam)
  camera()
  fx:draw()
  hud()
  if state == "intro" then
    local t = timer < 50 and ("ROUND " .. round) or "¡LUCHA!"
    text(t, 240, 130, {font = "arcade", scale = 3, align = "center", color = 0xFFF0A0, gradient = 0xE04010,
                       outline = 0x101030})
  elseif state == "ko" then
    text(message, 240, 120, {font = "arcade", scale = 4, align = "center", color = 0xFFFFFF, gradient = 0xFF4040,
                             outline = 0x101030, shake = timer < 30 and 2 or 0})
  elseif state == "over" then
    local w = p[1].wins >= 2 and p[1] or p[2]
    text("GANA " .. w.name, 240, 120, {font = "arcade", scale = 3, align = "center", color = 0xFFF0A0,
                                        gradient = 0xE04010, outline = 0x101030})
    if timer > 60 then text("A: OTRA VEZ", 240, 180, {font = "arcade", align = "center", color = 0xFFFFFF, outline = 0x101030}) end
  end
  juice.draw()
end
