-- boss: El Gran Gólem de Oro. A torso, a head, two fists on arms made of turned sprites (the GBA's affine objects: one picture rotated by a matrix). It slams a fist
-- down where the hero stands (the fist stays down a moment and can be climbed), throws stone eggs (which hatch into bomb ducks if left), and opens its mouth after
-- that: a stone egg thrown into the open mouth, or a drop on its head, hurts it. Four hits.
local C = require("core.const")
local W = require("core.world")
local P = require("core.phys")
local S = require("core.spr")
local Fx = require("core.fx")
local Hero = require("core.hero")
local Foes = require("core.foes")
local Things = require("core.things")
local Sound = require("core.sound")
local Music = require("core.music")
local Run = require("core.run")
local B = {}

local FLOOR = 128
local TORSO = {x = 168, y = 64}
local HEAD = {x = 184, y = 34}
local EGG = {sheet = "BOSS32", prefix = "egg", n = 4, sw = 32, sh = 32, w = 12, h = 12}

B.active = false
B.hp = 4
B.done_t = nil

function B.reset() B.active, B.done_t, B.hp = false, nil, 4 B.ducks, B.shocks, B.fists = {}, {}, {} P.platforms = {} end

function B.enter(play)
  B.active, B.hp, B.done_t = true, 4, nil
  B.t = 0
  B.state, B.st = "intro", 0
  B.plan_i = 0
  B.ducks, B.shocks = {}, {}
  B.fists = {
    {x = 130, y = 72, hx = 130, hy = 72, state = "idle", st = 0},
    {x = 222, y = 72, hx = 222, hy = 72, state = "idle", st = 0},
  }
  B.cur = 1
  B.head_open = false
  B.hurt_t = 0
  B.shield = 2
  B.bits = {}
  Foes.thrown_hit = B.thrown_hit
  P.platforms = {}
  Music.play("jefe", 100)
end

local function plan()
  local base = {"slam", "slam", "egg", "open"}
  if B.hp <= 2 then base = {"slam", "slam", "slam", "egg", "open"} end
  B.plan_i = B.plan_i % #base + 1
  return base[B.plan_i]
end

function B.thrown_hit(e)
  if not B.active or B.state == "dead" or not e.egg then return false end
  if P.overlap(e.x, e.y, e.w, e.h, HEAD.x + 4, HEAD.y + 4, 24, 26) then
    if B.head_open then B.damage(1) else Sound.play("land") Fx.add("poof", e.x, e.y) end
    return true
  end
  return false
end

function B.damage(n)
  B.hp = B.hp - n
  B.hurt_t = 60
  B.head_open = false
  Sound.play("smash")
  W.shake(3, 24)
  Fx.add("explode", HEAD.x + 16, HEAD.y + 16)
  Fx.burst("debris", HEAD.x + 16, HEAD.y + 16, 6, 2)
  if B.shield > 0 then B.shield = B.shield - 1 end
  if B.hp <= 0 then
    B.state, B.st = "dead", 0
    Music.stop(200)
    Sound.play("boom")
  else
    B.state, B.st = "hurt", 0
  end
end

local function slam_target(f, x)
  f.state, f.st, f.tx = "track", 0, x
end

function B.update(play)
  local h = play.hero
  B.t = B.t + 1
  B.st = B.st + 1
  if B.hurt_t > 0 then B.hurt_t = B.hurt_t - 1 end
  P.platforms = {}
  for _, f in ipairs(B.fists) do
    f.st = f.st + 1
    if f.state == "track" then
      f.x = f.x + (math.max(120, math.min(Hero.cx(h) - 16, 206)) - f.x) * 0.1
      f.y = f.y + (28 - f.y) * 0.15
      if f.st > 46 then f.state, f.st, f.vy = "fall", 0, 0 end
    elseif f.state == "fall" then
      f.vy = f.vy + 0.8
      f.y = f.y + f.vy
      if f.y >= FLOOR - 32 then
        f.y, f.state, f.st = FLOOR - 32, "down", 0
        Sound.play("smash")
        W.shake(3, 16)
        Fx.add("smash", f.x + 16, FLOOR - 8)
        shock(f.x + 16 - W.cam_x, FLOOR - W.cam_y, 4, 12, 5)
        B.shocks[#B.shocks + 1] = {x = f.x + 8, y = FLOOR - 8, dir = -1, t = 0}
        B.shocks[#B.shocks + 1] = {x = f.x + 24, y = FLOOR - 8, dir = 1, t = 0}
      end
    elseif f.state == "down" then
      P.platforms[#P.platforms + 1] = {x = f.x + 2, y = f.y + 2, w = 28}
      if f.st > 70 then f.state, f.st = "rise", 0 end
    elseif f.state == "rise" then
      f.x = f.x + (f.hx - f.x) * 0.1
      f.y = f.y + (f.hy - f.y) * 0.1
      if f.st > 40 then f.state, f.st = "idle", 0 end
    else
      f.y = f.hy + math.sin((B.t + f.hx) / 25) * 3
    end
    -- a fist coming down hurts
    if f.state == "fall" and P.overlap(h.x, h.y, h.w, h.h, f.x + 2, f.y + 4, 28, 26) and h.state ~= "dead" then
      Hero.hurt(h, f.x + 16)
    end
  end
  for i = #B.shocks, 1, -1 do
    local s = B.shocks[i]
    s.t = s.t + 1
    s.x = s.x + s.dir * 1.8
    if s.t > 70 or s.x < 0 or s.x > 240 then table.remove(B.shocks, i)
    elseif h.ground and P.overlap(h.x, h.y + h.h - 8, h.w, 8, s.x - 6, FLOOR - 12, 12, 12) and h.state ~= "dead" then
      Hero.hurt(h, s.x)
    end
  end
  -- the ducks
  for i = #B.ducks, 1, -1 do
    local d = B.ducks[i]
    d.t = d.t + 1
    local dir = Hero.cx(h) > d.x and 1 or -1
    d.x = d.x + dir * 0.7
    d.dir = dir
    if d.t > 150 then
      Fx.add("explode", d.x, FLOOR - 10)
      Sound.play("boom", 0.6)
      W.shake(2, 10)
      if math.abs(Hero.cx(h) - d.x) < 26 and h.y + h.h > FLOOR - 28 and h.state ~= "dead" then Hero.hurt(h, d.x) end
      table.remove(B.ducks, i)
    elseif P.overlap(h.x, h.y, h.w, h.h, d.x - 8, FLOOR - 16, 16, 16) and Hero.attacking(h) then
      Fx.add("poof", d.x, FLOOR - 10)
      table.remove(B.ducks, i)
    end
  end
  -- eggs left alone hatch
  for _, e in ipairs(Foes.list) do
    if e.egg and e.state == "egg" and e.t > 260 then
      e.state, e.st = "dead", 99
      B.ducks[#B.ducks + 1] = {x = e.x + 6, t = 0, dir = 1}
      Sound.play("stun")
    end
  end
  -- the head and torso hurt by touch
  if B.state ~= "dead" and h.state ~= "dead" and h.state ~= "win" then
    if P.overlap(h.x, h.y, h.w, h.h, TORSO.x + 6, TORSO.y + 8, 52, 56) then Hero.hurt(h, TORSO.x + 32) end
    if P.overlap(h.x, h.y, h.w, h.h, HEAD.x + 4, HEAD.y + 4, 24, 26) then
      if B.head_open and (Hero.attacking(h) or h.vy > 0.5) and B.hurt_t == 0 then
        B.damage(1)
        h.vy, h.vx = -4, -1.5
      elseif not B.head_open then
        Hero.hurt(h, HEAD.x + 16)
      end
    end
  end
  -- the plan
  if B.state == "intro" then
    if B.st > 100 then B.state, B.st = plan(), 0 end
    if B.st == 30 then Sound.play("boom") W.shake(2, 40) end
  elseif B.state == "slam" then
    if B.st == 1 then
      slam_target(B.fists[B.cur], Hero.cx(h) - 16)
      B.cur = 3 - B.cur
    end
    if B.st > 170 then B.state, B.st = plan(), 0 end
  elseif B.state == "egg" then
    if B.st == 40 then
      local tx = Hero.cx(h) - 20
      Foes.egg(HEAD.x + 4, HEAD.y + 28, (tx - HEAD.x) / 52, -3.6, EGG)
      Sound.play("throw")
    end
    if B.st > 110 then B.state, B.st = plan(), 0 end
  elseif B.state == "open" then
    B.head_open = true
    if B.st > 230 then B.head_open = false B.state, B.st = plan(), 0 end
  elseif B.state == "hurt" then
    if B.st > 70 then B.state, B.st = plan(), 0 end
  elseif B.state == "dead" then
    if B.st % 12 == 0 then
      Fx.add("explode", TORSO.x + 8 + (B.st * 7) % 48, TORSO.y + 6 + (B.st * 5) % 44)
      Sound.play("boom", 0.4)
      W.shake(2, 6)
    end
    if B.st == 120 then
      for n = 1, 24 do Things.pop_coin(TORSO.x + 32, TORSO.y + 20, n % 4 == 0 and 3 or 2, (n - 12.5) * 0.25, -4 - (n % 5) * 0.5) end
      Sound.play("jewel")
    end
    if B.st > 130 then B.done_t = (B.done_t or 0) + 1 end
  end
end

local function angle(x0, y0, x1, y1) return math.deg(math.atan(y1 - y0, x1 - x0)) end

function B.draw(play)
  local t = B.t
  local hurt = B.hurt_t > 0 and (B.hurt_t // 3) % 2 == 0
  local dead = B.state == "dead"
  -- draw order: the first drawn is in front; fists, head, torso
  for i, f in ipairs(B.fists) do
    local sx, sy = f.x - W.cam_x, f.y - W.cam_y
    local frame = (f.state == "fall" and "fist_slam_0") or (f.state == "down" and "fist_slam_1") or (f.state == "track" and "fist_closed") or "fist_open"
    S.draw("BOSS32", frame, sx, sy, {prio = 1, flip = i == 2})
  end
  if not dead or B.st < 100 then
    local hf
    if dead then hf = "head_dead_" .. math.min(3, B.st // 25)
    elseif B.hurt_t > 0 then hf = "head_hurt_" .. math.min(2, (60 - B.hurt_t) // 20)
    elseif B.head_open then hf = "head_open_" .. ((t // 8) % 2)
    elseif B.state == "egg" or B.state == "intro" then hf = "head_laugh_" .. ((t // 6) % 2)
    else hf = "head_idle_" .. ((t // 10) % 4) end
    mat(1, math.sin(t / 30) * 3, 1)
    S.draw("BOSS32", hf, HEAD.x - W.cam_x, HEAD.y - W.cam_y + (B.state == "intro" and 0 or math.floor(math.sin(t / 20) * 1.5)), {prio = 1, mat = 1, double = false})
    if B.shield > 0 and not dead then S.draw("BOSS32", "shield_" .. (B.shield - 1), HEAD.x - W.cam_x, HEAD.y - W.cam_y - 2, {prio = 1}) end
  end
  local tf = dead and ("torso_crack_" .. math.min(2, B.st // 40)) or hurt and "torso_hurt" or (B.hp <= 3 and ("torso_crack_" .. (3 - B.hp - 1 < 0 and 0 or math.min(2, 3 - B.hp - 1))) or ("torso_" .. ((t // 24) % 3)))
  S.draw("BOSS64", tf, TORSO.x - W.cam_x + (B.state == "intro" and ((t % 4) - 2) or 0), TORSO.y - W.cam_y, {prio = 2})
  -- arms: two pieces between the shoulder and the fist, each turned toward it
  for i, f in ipairs(B.fists) do
    local shx, shy = TORSO.x + (i == 1 and 6 or 58), TORSO.y + 22
    local fx_, fy_ = f.x + 16, f.y + 16
    local a = angle(shx, shy, fx_, fy_)
    for k = 1, 2 do
      local m = 1 + i * 2 + k - 1
      local px = shx + (fx_ - shx) * (k / 3) - 16
      local py = shy + (fy_ - shy) * (k / 3) - 16
      mat(m, -a + (i == 2 and 180 or 0), 1)
      S.draw("BOSS32", k == 1 and "arm_a" or "arm_b", px - W.cam_x, py - W.cam_y, {prio = 2, mat = m, flip = false})
    end
  end
  for _, d in ipairs(B.ducks) do
    S.draw("BOSS32", "duck_" .. ((d.t // 6) % 4), d.x - 16 - W.cam_x, FLOOR - 32 - W.cam_y, {flip = (d.dir or 1) < 0})
  end
  for _, s in ipairs(B.shocks) do
    S.draw("FX16", "smash_" .. ((s.t // 4) % 4), s.x - 8 - W.cam_x, FLOOR - 16 - W.cam_y, {flip = s.dir < 0})
  end
end

return B
