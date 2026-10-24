-- boss: El Gran Gaviotrón, a clockwork seagull war-walker driven by a tiny seagull pilot, with the paellera on its back under an iron lid. Painted whole (sheet "boss", 384x320 a
-- frame, anchor between the feet); the places that matter are points of that frame (LOCAL below). It rains rockets from its wing gatlings, stomps (a shock wave runs along
-- the ground: jump it), charges its beak cannon, and then opens the pot: the saffron-rice core inside is the weak point, and only open.
local C = require("core.const")
local S = require("core.spr")
local Shots = require("core.shots")
local Fx = require("core.fx")
local Sound = require("core.sound")
local Music = require("core.music")
local Run = require("core.run")
local Hook = require("core.juice_hook")
local B = {}

B.active = false
B.hp, B.max_hp = 100, 100
B.done = false

local PLAN = {"rockets", "stomp", "beam", "pot"}

function B.reset() B.active, B.done, B.state = false, false, nil end

function B.enter(cam)
  B.active, B.done = true, false
  B.hp = B.max_hp
  B.x = cam + 300 + 260       -- steps in from the right
  B.target_x = cam + 300
  B.y = C.FLOOR + 8 -- the frame's anchor row is the soles (the arena's sand is a little deep)
  B.t, B.st, B.state, B.plan_i = 0, 0, "intro", 0
  B.pot_open, B.head_open = false, false
  B.hurt_t, B.flash = 0, 0
  B.wing, B.legs = "rest", "stand"
  B.charge = 0
  Music.play("jefe", 100)
  Hook.shake(4)
end

-- points of the boss frame (384 x 320, anchor 192,316 between the feet): where its head, its pot and its guns are
local AX, AY = 192, 316
local LOCAL = {head = {40, 35, 95, 85}, pot = {165, 28, 120, 88}, beak = {45, 92}, gun = {78, 182}}
local function world(px, py) return B.x + (px - AX), B.y + (py - AY) end

function B.boxes()
  local h, p = LOCAL.head, LOCAL.pot
  local hx, hy = world(h[1], h[2])
  local px, py = world(p[1], p[2])
  return {head = {hx, hy, h[3], h[4]}, pot = {px, py, p[3], p[4]}}
end

local function inside(b, x, y, r) return x + r > b[1] and x - r < b[1] + b[3] and y + r > b[2] and y - r < b[2] + b[4] end

function B.hit_at(x, y, r, dmg)
  if not B.active or B.state == "dying" or B.state == "intro" then return false end
  local bx = B.boxes()
  if inside(bx.pot, x, y, r) then
    if B.pot_open then B.damage(dmg) else Sound.play("clank", 0.5) Fx.add("hit", x, y) end
    return true
  end
  if inside(bx.head, x, y, r) then
    if B.head_open then B.damage(dmg * 0.5) else Sound.play("clank", 0.5) end
    Fx.add("hit", x, y)
    return true
  end
  -- the rest of the machine: a clank
  if x > B.x - 155 and x < B.x + 150 and y > C.FLOOR - 330 then Fx.add("hit", x, y) return true end
  return false
end

function B.touching(x, y, r)
  if not B.active or B.state == "dying" then return false end
  return x > B.x - 150 and x < B.x + 150 and y > C.FLOOR - 320
end

function B.blast(x, y, r, dmg)
  if B.hit_at(x, y - 60, r, dmg) then return end
end

function B.damage(d)
  if B.state == "dying" then return end
  B.hp = B.hp - d
  B.hurt_t = 6
  B.flash = 3
  Sound.play("hit", 0.35)
  if B.hp <= 0 then
    B.state, B.st = "dying", 0
    B.pot_open, B.head_open = false, false
    Music.stop(300)
    Hook.shake(8)
    Run.add(10000)
  end
end

local function next_plan()
  B.plan_i = B.plan_i % #PLAN + 1
  B.state, B.st = PLAN[B.plan_i], 0
end

function B.update(chef, cam)
  if not B.active then return end
  B.t, B.st = B.t + 1, B.st + 1
  if B.hurt_t > 0 then B.hurt_t = B.hurt_t - 1 end
  if B.flash > 0 then B.flash = B.flash - 1 end
  local fast = B.hp < 55
  if B.state == "intro" then
    B.x = B.x + (B.target_x - B.x) * 0.03
    B.legs = (B.st // 6) % 2 == 0 and "step" or "stand"
    if B.st == 40 or B.st == 90 then Sound.play("stomp", 0.8) Hook.shake(4) end
    if B.st > 150 then B.legs = "stand" next_plan() end
  elseif B.state == "rockets" then
    B.wing = B.st < 30 and "open" or (B.st < 110 and "fire" or "rest")
    if B.st >= 40 and B.st < 110 and (B.st - 40) % (fast and 12 or 18) == 0 then
      local gx, gy = world(LOCAL.gun[1], LOCAL.gun[2])
      local tx = chef.x + (math.random() - 0.5) * 220
      local T = 56
      Shots.hostile("rocket", gx, gy, (tx - gx) / T, -5, {grav = true})
      Sound.play("rocket", 0.5)
    end
    if B.st > 130 then B.wing = "rest" next_plan() end
  elseif B.state == "stomp" then
    B.legs = B.st < 40 and "step" or (B.st < 80 and "stomp" or "stand")
    if B.st == 62 then
      Sound.play("stomp", 0.9)
      Hook.shake(7)
      Fx.add("boom_l", B.x - 130, C.FLOOR - 20)
      Shots.hostile("shock", B.x - 130, C.FLOOR - 12, -4.2, 0)
      if fast then Shots.hostile("shock", B.x - 130, C.FLOOR - 12, -3.0, 0) end
    end
    if B.st > 110 then B.legs = "stand" next_plan() end
  elseif B.state == "beam" then
    B.head_open = B.st > 20 and B.st < 150
    B.charge = B.st
    if B.st == 90 or (fast and B.st == 110) then
      local mx, my = world(LOCAL.beak[1], LOCAL.beak[2]) -- the beak's muzzle
      for k = -1, 1 do
        local tx = chef.x + k * 90
        local dx, dy = tx - mx, C.FLOOR - my
        local l = math.sqrt(dx * dx + dy * dy)
        Shots.hostile("beam", mx, my, dx / l * 6.5, dy / l * 6.5)
      end
      Sound.play("beam", 0.7)
    end
    if B.st > 160 then B.head_open = false next_plan() end
  elseif B.state == "pot" then
    B.pot_open = B.st > 30 and B.st < 330
    if B.st == 30 then Sound.play("stomp", 0.5) end
    if B.st > 350 then B.pot_open = false next_plan() end
  elseif B.state == "dying" then
    if B.st % 8 == 0 then
      Fx.add(B.st % 24 == 0 and "boom_l" or "boom_m", B.x - 150 + math.random(300), C.FLOOR - 40 - math.random(260))
      Sound.play("boom", 0.45)
      Hook.shake(3)
    end
    if B.st > 260 then B.done = true end
  end
  if B.state ~= "dying" and chef.state == "play" then
    -- the legs hurt a chef who stands under them
    if math.abs(chef.x - (B.x - 110)) < 70 and B.state == "stomp" and B.st >= 55 and B.st < 66 and chef.y > C.FLOOR - 20 then Hook.shake(2) chef.hurt() end
    if chef.x > B.x - 60 and chef.vehicle == nil then chef.hurt() end
  end
end

-- the frame to draw: the state of the fight decides, in this order
local function pick()
  local t, st = B.t, B.st
  if B.state == "dying" then return "dead_" .. math.min(5, st // 43) end
  local hit = B.hurt_t > 0
  if B.pot_open then
    if hit then return "open_" .. (t // 3) % 4 end
    if st < 52 then return "opening_" .. math.min(3, (st - 30) // 5) end
    return "open_" .. (t // 6) % 4
  end
  if hit then return "hurt_" .. (B.hurt_t // 3) % 2 end
  if B.state == "beam" and B.head_open then
    if st < 90 then return "charge_" .. math.min(3, (st - 20) // 18) end
    return "fire_" .. (t // 4) % 2
  end
  if B.state == "rockets" and st >= 40 and st < 110 then return "gat_" .. (t // 3) % 4 end
  if B.state == "stomp" and st >= 40 and st < 80 then return "stomp_" .. math.min(3, (st - 40) // 10) end
  if (B.state == "intro" and B.legs == "step") or (B.state == "stomp" and st < 40) then return "walk_" .. (t // 5) % 6 end
  if B.hp < 66 then return "dmg_" .. (t // 12) % 2 end
  return "idle_" .. (t // 8) % 4
end

function B.draw(cam)
  if not B.active then return end
  S.draw("boss", pick(), B.x - cam, B.y, {tint = B.flash > 0 and 0xFFFFFF or nil})
  if B.state == "beam" and B.head_open and B.st < 90 then
    local mx, my = world(LOCAL.beak[1], LOCAL.beak[2])
    S.draw("boss_fx", "charge_" .. (B.t // 4) % 6, mx - cam, my, {})
  end
end

return B
