-- boss: El Gran Gaviotrón, a giant mechanical seagull carrying an armoured paellera. It is made of parts (body, head, two wings, two legs, the pot) the game places on the body's
-- joints and animates separately. It rains sardine rockets from its wings, stomps (a shock wave runs along the ground: jump it), charges its beak cannon, and then opens the pot:
-- the saffron-rice core inside is the weak point, and only open.
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
  -- the body's anchor is where its joints are measured from; put it so the soles stand on the ground (a little below the floor line, the arena's sand is deep)
  local bsh, lsh = S.sheets.boss_body, S.sheets.boss_leg
  local lj = (bsh.joints and bsh.joints.leg_l) or {165, 296}
  B.y = (C.FLOOR + 8) - (lj[2] - bsh.ay) - ((lsh.ground_y or 183) - lsh.ay)
  B.t, B.st, B.state, B.plan_i = 0, 0, "intro", 0
  B.pot_open, B.head_open = false, false
  B.hurt_t, B.flash = 0, 0
  B.wing, B.legs = "rest", "stand"
  B.charge = 0
  Music.play("jefe", 100)
  Hook.shake(4)
end

local function joints()
  local sh = S.sheets.boss_body
  local j = sh.joints or {}
  local function w(name, dx, dy)
    local p = j[name] or {dx, dy}
    return B.x - sh.ax + p[1], B.y - sh.ay + p[2]
  end
  return w
end

function B.boxes()
  local w = joints()
  local hx, hy = w("head", 100, 248)
  local px, py = w("pot", 212, 238)
  return {head = {hx - 125, hy - 105, 150, 125}, pot = {px - 75, py - 150, 150, 150}}
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
  if x > B.x - 200 and x < B.x + 190 and y > C.FLOOR - 330 then Fx.add("hit", x, y) return true end
  return false
end

function B.touching(x, y, r)
  if not B.active or B.state == "dying" then return false end
  return x > B.x - 190 and x < B.x + 170 and y > C.FLOOR - 320
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
  local w = joints()
  if B.state == "intro" then
    B.x = B.x + (B.target_x - B.x) * 0.03
    B.legs = (B.st // 6) % 2 == 0 and "step" or "stand"
    if B.st == 40 or B.st == 90 then Sound.play("stomp", 0.8) Hook.shake(4) end
    if B.st > 150 then B.legs = "stand" next_plan() end
  elseif B.state == "rockets" then
    B.wing = B.st < 30 and "open" or (B.st < 110 and "fire" or "rest")
    if B.st >= 40 and B.st < 110 and (B.st - 40) % (fast and 12 or 18) == 0 then
      local wx, wy = w("wing", 228, 222)
      local tx = chef.x + (math.random() - 0.5) * 220
      local T = 56
      Shots.hostile("rocket", wx - 60, wy - 40, (tx - (wx - 60)) / T, -5, {grav = true})
      Sound.play("rocket", 0.5)
    end
    if B.st > 130 then B.wing = "rest" next_plan() end
  elseif B.state == "stomp" then
    B.legs = B.st < 40 and "step" or (B.st < 80 and "stomp" or "stand")
    if B.st == 62 then
      Sound.play("stomp", 0.9)
      Hook.shake(7)
      Fx.add("boom_l", B.x - 120, C.FLOOR - 20)
      Shots.hostile("shock", B.x - 120, C.FLOOR - 12, -4.2, 0)
      if fast then Shots.hostile("shock", B.x - 120, C.FLOOR - 12, -3.0, 0) end
    end
    if B.st > 110 then B.legs = "stand" next_plan() end
  elseif B.state == "beam" then
    B.head_open = B.st > 20 and B.st < 150
    B.charge = B.st
    if B.st == 90 or (fast and B.st == 110) then
      local hx, hy = w("head", 100, 248)
      local mx, my = hx - 128, hy - 9      -- the beak's muzzle (boss_head.json: [22, 111] in a frame anchored at [150, 120])
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
      Fx.add(B.st % 24 == 0 and "boom_l" or "boom_m", B.x - 170 + math.random(340), C.FLOOR - 40 - math.random(260))
      Sound.play("boom", 0.45)
      Hook.shake(3)
    end
    if B.st > 260 then B.done = true end
  end
  if B.state ~= "dying" and chef.state == "play" then
    -- the legs hurt a chef who stands under them
    if math.abs(chef.x - (B.x - 100)) < 70 and B.state == "stomp" and B.st >= 55 and B.st < 66 and chef.y > C.FLOOR - 20 then Hook.shake(2) chef.hurt() end
    if chef.x > B.x - 70 and chef.vehicle == nil then chef.hurt() end
  end
end

local function frame(prefix, n, t, every) return prefix .. "_" .. ((t // every) % n) end

function B.draw(cam)
  if not B.active then return end
  local t = B.t
  local sx = B.x - cam
  local dead = B.state == "dying"
  local w = joints()
  local function at(name, dx, dy)
    local x, y = w(name, dx, dy)
    return x - cam, y
  end
  local flash = B.flash > 0 and 0xFFFFFF or nil
  local lx, ly = at("leg_l", 165, 296)
  local rx, ry = at("leg_r", 228, 292)
  local lf
  if B.legs == "stomp" then lf = "stomp_" .. math.min(3, (B.st - 40) // 10)
  elseif B.legs == "step" then lf = "step_" .. (t // 5) % 8
  else lf = "stand" end
  if dead then lf = "broken_" .. (t // 12) % 2 end
  -- painted far to near: the far leg, the body, the near leg, the pot, the wing, the head
  S.draw("boss_leg", B.legs == "step" and ("step_" .. ((t // 5 + 4) % 8)) or lf, rx, ry, {})
  local bf
  if dead then bf = "dead_" .. math.min(3, B.st // 50)
  elseif B.hurt_t > 0 then bf = "hurt_" .. (B.hurt_t // 3) % 2
  elseif B.hp < 33 then bf = "damaged_2" elseif B.hp < 66 then bf = "damaged_1" else bf = frame("idle", 6, t, 8) end
  S.draw("boss_body", bf, sx, B.y, {tint = flash})
  S.draw("boss_leg", lf, lx, ly, {})
  local px, py = at("pot", 212, 238)
  local pf
  if dead then pf = "destroyed_" .. math.min(3, B.st // 30)
  elseif B.pot_open then pf = B.st < 36 and ("opening_" .. math.min(5, (B.st - 30) // 3 + 0)) or ("open_" .. (t // 6) % 4)
  elseif B.hp < 33 then pf = "cracked_2" elseif B.hp < 66 then pf = "cracked_1" else pf = "closed" end
  if B.hurt_t > 0 and B.pot_open then pf = "hit_" .. (t // 3) % 3 end
  S.draw("boss_pot", pf, px, py, {tint = B.pot_open and flash or nil})
  local wx, wy = at("wing", 228, 222)
  local wf = B.wing == "open" and ("open_" .. math.min(3, B.st // 8)) or (B.wing == "fire" and ("fire_" .. (t // 4) % 4) or ("rest_" .. (t // 10) % 4))
  if dead then wf = "broken_" .. (t // 14) % 2 end
  S.draw("boss_wing", wf, wx, wy, {})
  local hx, hy = at("head", 100, 248)
  local hf
  if dead then hf = "dead_" .. math.min(3, B.st // 40)
  elseif B.hurt_t > 0 then hf = "hurt_" .. (B.hurt_t // 2) % 3
  elseif B.head_open then hf = B.st < 90 and ("open_" .. (t // 6) % 4) or ("fire_" .. (t // 4) % 3)
  elseif B.state == "intro" or B.state == "pot" then hf = "laugh_" .. (t // 8) % 4
  else hf = "idle_" .. (t // 10) % 4 end
  S.draw("boss_head", hf, hx, hy, {tint = flash})
  if B.state == "beam" and B.head_open and B.st < 90 then S.draw("boss_fx", "charge_" .. (t // 4) % 6, hx - 128, hy - 9, {}) end
end

return B
