-- boss: Péndulo, the grandfather-clock golem. It walks up to the hero and sweeps its arm, rings its bells (two shock rings roll along the floor: jump them), and leaps to slam the street
-- (the shock round it hurts anyone near the ground). A flurry of blows staggers it; below 40% it is enraged: it waits less. One whole-body painted sheet "pendulo".
local C = require("core.const")
local U = require("core.util")
local S = require("core.spr")
local Fx = require("core.fx")
local Sound = require("core.sound")
local Music = require("core.music")
local Run = require("core.run")
local Hook = require("core.juice_hook")
local B = {}

B.active, B.done = false, false
B.hp, B.max_hp = 360, 360
B.ent = nil
B.arena_min = nil
B.rings = {}
local E = {}
E.__index = E

function B.reset() B.active, B.done, B.ent, B.arena_min, B.rings = false, false, nil, nil, {} end

function B.enter(cam)
  B.active, B.done = true, false
  B.hp = B.max_hp
  B.arena_min = cam + 20
  B.rings = {}
  B.ent = setmetatable({x = cam + C.W + 160, y = 276, z = 0, vx = 0, vz = 0, hw = 56, alive = true, face = -1, st = "intro", t = 0, flash = 0, last_atk = 0, stagger = 0,
                        cool = 60, ent = true, hp = B.hp}, E)
  Music.play("jefe", 100)
  Hook.shake(4)
end

local function set(b, st) b.st, b.t = st, 0 end

function E:hit(dmg, dir, flags, atkid)
  if self.st == "dying" or self.st == "intro" or (atkid > 0 and self.last_atk == atkid) then return false end
  self.last_atk = atkid
  B.hp = B.hp - dmg
  self.hp = B.hp
  if U.blink(self) then self.flash = 4 end
  Run.add(math.floor(dmg * 8))
  self.stagger = self.stagger + dmg
  if B.hp <= 0 then
    set(self, "dying")
    self.alive = false
    Music.stop(300)
    Hook.shake(8)
    Run.add(10000)
    Sound.play("big")
    return true
  end
  if self.stagger >= 50 and (self.st == "walk" or self.st == "idle") then
    self.stagger = 0
    set(self, "hurt")
    Sound.play("clank")
  end
  return true
end

local function enraged() return B.hp < B.max_hp * 0.4 end

function B.update(hero, cam)
  local b = B.ent
  if not b then return end
  b.t = b.t + 1
  if b.flash > 0 then b.flash = b.flash - 1 end
  local fast = enraged() and 1.5 or 1
  local st = b.st
  b.face = hero.x >= b.x and 1 or -1
  if st == "intro" then
    b.x = b.x + (cam + C.W - 150 - b.x) * 0.03
    if b.t == 40 or b.t == 90 then Sound.play("stomp", 0.8) Hook.shake(4) end
    if b.t > 130 then set(b, "walk") end
  elseif st == "walk" or st == "idle" then
    local dx = hero.x - b.x
    b.cool = b.cool - fast
    if math.abs(dx) > 100 then b.x = b.x + U.sign(dx) * 0.8 * fast end
    if math.abs(hero.y - b.y) > 4 then b.y = b.y + U.sign(hero.y - b.y) * 0.5 end
    b.st = math.abs(dx) > 100 and "walk" or "idle"
    if b.cool <= 0 and hero.st ~= "dead" then
      local r = math.random()
      if math.abs(dx) < 130 and r < 0.5 then set(b, "swing")
      elseif r < 0.75 then set(b, "chime")
      else set(b, "slam") end
    end
  elseif st == "swing" then
    if b.t == 26 then
      Sound.play("whoosh")
      local dx = (hero.x - b.x) * b.face
      if dx > -20 and dx < 130 and math.abs(hero.y - b.y) < 30 and hero.z < 60 then hero:hurt(18, b.face, {down = true}) Sound.play("heavy") end
    end
    if b.t > 56 then b.cool = 70 set(b, "walk") end
  elseif st == "chime" then
    if b.t == 26 then
      Sound.play("bell")
      Hook.shake(3)
      for _, d in ipairs({-1, 1}) do B.rings[#B.rings + 1] = {x = b.x + d * 40, y = b.y, vx = d * 3.2, t = 0, hit = false} end
    end
    if b.t > 60 then b.cool = 80 set(b, "walk") end
  elseif st == "slam" then
    if b.t == 24 then b.vz, b.z = 11, 0.01 b.vx = U.clamp((hero.x - b.x) / 40, -4, 4) Sound.play("jump") end
    if b.t > 24 and b.z > 0 then
      b.vz = b.vz - C.GRAV
      b.z = b.z + b.vz
      b.x = b.x + b.vx
      b.y = U.clamp(b.y + U.sign(hero.y - b.y) * 0.5, C.Y_MIN, C.Y_MAX)
      if b.z <= 0 then
        b.z, b.vz = 0, 0
        b.land = b.t
        Sound.play("stomp", 1)
        Hook.shake(8)
        Fx.add("boom", b.x, b.y, 30)
        Fx.add("dust", b.x - 50, b.y, 20)
        Fx.add("dust", b.x + 50, b.y, 20)
        if math.abs(hero.x - b.x) < 130 and math.abs(hero.y - b.y) < 36 and hero.z < 30 then hero:hurt(22, hero.x >= b.x and 1 or -1, {down = true}) end
      end
    end
    if b.land and b.t > b.land + 30 then b.land = nil b.cool = 90 set(b, "walk") end
  elseif st == "hurt" then
    if b.t > 14 then set(b, "walk") end
  elseif st == "dying" then
    if b.t % 9 == 0 then
      Fx.add("boom", b.x - 60 + math.random(120), b.y, 20 + math.random(110))
      Sound.play("boom", 0.5)
      Hook.shake(3)
    end
    if b.t > 190 then B.done = true end
  end
  b.x = U.clamp(b.x, B.arena_min + 60, cam + C.W + 200)
  b.y = U.clamp(b.y, C.Y_MIN, C.Y_MAX)
  -- the shock rings along the floor
  for i = #B.rings, 1, -1 do
    local r = B.rings[i]
    r.t, r.x = r.t + 1, r.x + r.vx
    if not r.hit and math.abs(hero.x - r.x) < 20 and math.abs(hero.y - r.y) < 24 and hero.z < 26 then
      r.hit = hero:hurt(14, U.sign(r.vx), {down = true})
    end
    if r.t > 200 or r.x < cam - 60 or r.x > cam + C.W + 60 then table.remove(B.rings, i) end
  end
end

local function frame_of(b)
  local st, t = b.st, b.t
  if st == "walk" then return "walk_" .. (t // 8) % 3 end
  if st == "idle" or st == "intro" then
    if enraged() and st ~= "intro" then return "rage_" .. (t // 6) % 2 end
    return "idle_" .. (t // 12) % 3
  end
  if st == "swing" then return "swing_" .. (t < 24 and 0 or (t < 40 and 1 or 2)) end
  if st == "chime" then return "chime_" .. math.min(2, t // 20) end
  if st == "slam" then return b.land and "slam_2" or (b.z > 0 and "slam_1" or (b.t < 24 and "slam_0" or "slam_3")) end
  if st == "hurt" then return "hurt_" .. (t // 6) % 2 end
  if st == "dying" then return t < 30 and "fall_0" or (t < 70 and "fall_1" or "die_" .. math.min(3, (t - 70) // 25)) end
  return "idle_0"
end

function B.collect(out, cam)
  local b = B.ent
  if not b then return end
  out[#out + 1] = {y = b.y, foe = true, draw = function()
    require("core.hero").shadow(b.x - cam, b.y, b.z * 0.5)
    S.draw("pendulo", frame_of(b), b.x - cam, b.y - b.z, {flip = b.face < 0, tint = b.flash > 0 and 0xFFFFFF or nil})
  end}
  for _, r in ipairs(B.rings) do
    out[#out + 1] = {y = r.y + 1, draw = function()
      local k = 10 + (r.t // 3) % 3 * 3
      circ(r.x - cam, r.y - 12, k + 4, 0x402000, false)
      circ(r.x - cam, r.y - 12, k, 0xFFE060, false)
      circ(r.x - cam, r.y - 12, k - 3, 0xFFFFFF, false)
    end}
  end
end

return B
