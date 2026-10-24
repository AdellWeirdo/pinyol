-- foes: the automatons. Rodete (a tin-bucket thug) walks up and punches, Resorte (springs for legs) hops and pounces from the air, Caldero (a steam boiler) is slow, will not fall to a
-- single blow and slams the ground. They come in from the sides of the screen, never more than two attack at once, can be grabbed (all but Caldero), knocked down, thrown (a thrown one hurts
-- those it flies into) and burst into gears when they fall for good.
-- Every foe is a target of the hero's blows: x, y (depth), z (height), hw (half width), alive, and the methods hit, grabbed, thrown.
local C = require("core.const")
local U = require("core.util")
local S = require("core.spr")
local Run = require("core.run")
local Fx = require("core.fx")
local Sound = require("core.sound")
local Hook = require("core.juice_hook")
local F = {}

F.list = {}
F.on_die = nil   -- set by the play module: what a defeated foe leaves behind

local DEF = {
  rodete = {hp = 30, speed = 1.0, hw = 20, grab = true, reach = 48, dmg = 8, wind = 16, cool = 60, score = 300},
  resorte = {hp = 24, speed = 1.5, hw = 18, grab = true, reach = 40, dmg = 10, wind = 20, cool = 90, score = 400},
  caldero = {hp = 130, speed = 0.7, hw = 36, grab = false, reach = 86, dmg = 18, wind = 30, cool = 100, armor = true, score = 1500},
}
F.DEF = DEF

local E = {}
E.__index = E

function F.clear() for i = #F.list, 1, -1 do F.list[i] = nil end end

function F.count()
  local n = 0
  for _, f in ipairs(F.list) do if f.alive then n = n + 1 end end
  return n
end

-- how many are in the middle of an attack (two at a time at most)
local function attackers()
  local n = 0
  for _, f in ipairs(F.list) do if f.st == "atk" then n = n + 1 end end
  return n
end

function F.spawn(kind, x, y)
  local d = DEF[kind]
  local f = setmetatable({kind = kind, d = d, x = x, y = y, z = 0, vx = 0, vz = 0, face = -1, hp = d.hp, max_hp = d.hp, st = "walk", t = math.random(0, 20), hw = d.hw,
                          alive = true, grabbable = d.grab, cool = 30 + math.random(0, 30), flash = 0, off = math.random(-30, 30), last_atk = 0, ent = true}, E)
  F.list[#F.list + 1] = f
  return f
end

-- from the side of the screen: side "l" or "r", at a depth of the street
function F.spawn_at(kind, side, cam, y)
  local x = side == "l" and cam - 40 or cam + C.W + 40
  return F.spawn(kind, x, y or math.random(C.Y_MIN, C.Y_MAX))
end

local function set(f, st) f.st, f.t = st, 0 end

function E:hit(dmg, dir, flags, atkid)
  if not self.alive then return false end
  if atkid > 0 and self.last_atk == atkid then return false end
  if self.st == "dying" then return false end
  self.last_atk = atkid
  self.hp = self.hp - dmg
  self.flash = 5
  Run.add(math.floor(dmg * 10))
  if self.held_by then self.held_by.held = nil self.held_by = nil end
  if self.hp <= 0 then
    self.alive = false
    self.vx, self.vz = dir * 3.5, 6
    set(self, "down")
    self.dying = true
    Run.kills = Run.kills + 1
    Run.add(self.d.score)
    Sound.play("die", 0.6)
    return true
  end
  if self.d.armor then
    if dmg >= 9 then set(self, "hurt") end
    self.face = -dir
    return true
  end
  self.face = -dir
  if flags and flags.down then
    self.vx, self.vz = dir * 3, 5.5
    set(self, "down")
    Sound.play("down", 0.6)
  else
    self.vx = dir * 1.5
    set(self, "hurt")
  end
  return true
end

function E:grabbed(hero)
  self.held_by = hero
  set(self, "held")
end

function E:thrown(face, dmg)
  self.held_by = nil
  self.face = -face
  self.vx, self.vz = face * 5, 5
  self.thrown_by = face
  self.hit_list = {}
  set(self, "down")
  self.hp = self.hp - dmg
  self.flash = 5
  Run.add(math.floor(dmg * 10))
  if self.hp <= 0 then
    self.alive = false
    self.dying = true
    Run.kills = Run.kills + 1
    Run.add(self.d.score)
  end
end

local function blow_on_hero(f, hero, reach, dmg, o)
  local dx = (hero.x - f.x) * f.face
  if o and o.round then dx = math.abs(hero.x - f.x) end
  if dx > -10 and dx < reach + hero.hw and math.abs(hero.y - f.y) < (o and o.depth or 18) and hero.z < 50 then
    return hero:hurt(dmg, hero.x >= f.x and 1 or -1, {down = o and o.down})
  end
end

-- the walk of every foe: towards a place near the hero, in depth first
local function approach(f, hero, reach)
  local dir = hero.x >= f.x and 1 or -1
  local goal = hero.x - dir * (reach - 10) + f.off * 0.3
  local dx = goal - f.x
  local sp = f.d.speed
  if math.abs(dx) > 4 then f.x = f.x + U.sign(dx) * sp end
  if math.abs(hero.y - f.y) > 4 then f.y = f.y + U.sign(hero.y - f.y) * sp * 0.6 end
  f.face = dir
  return math.abs(dx) <= 10 and math.abs(hero.y - f.y) <= 12
end

local function ai_rodete(f, hero)
  local d = f.d
  if f.st == "walk" then
    local near = approach(f, hero, d.reach)
    f.cool = f.cool - 1
    if near and f.cool <= 0 and attackers() < 2 and hero.st ~= "dead" then set(f, "atk") end
  elseif f.st == "atk" then
    if f.t == d.wind then
      if blow_on_hero(f, hero, d.reach, d.dmg) then Sound.play("punch") end
      f.x = f.x + f.face * 4
    end
    if f.t >= d.wind + 24 then f.cool = d.cool set(f, "walk") end
  end
end

local function ai_resorte(f, hero)
  local d = f.d
  if f.st == "walk" then
    local near = approach(f, hero, d.reach + 20)
    f.cool = f.cool - 1
    if (near or math.abs(hero.x - f.x) < 150) and f.cool <= 0 and attackers() < 2 and hero.st ~= "dead" then set(f, "atk") f.pounced = false end
  elseif f.st == "atk" then
    f.face = hero.x >= f.x and 1 or -1
    if f.t == d.wind then
      f.vz = 7.2
      f.z = 0.01
      f.vx = U.clamp((hero.x - f.x) / 28, -3.8, 3.8)
      f.vy = U.clamp((hero.y - f.y) / 28, -1.2, 1.2)
      Sound.play("jump", 0.6)
    elseif f.t > d.wind and f.z > 0 then
      f.vz = f.vz - C.GRAV
      f.z = f.z + f.vz
      f.x, f.y = f.x + f.vx, U.clamp(f.y + f.vy, C.Y_MIN, C.Y_MAX)
      if not f.pounced and math.abs(hero.x - f.x) < 34 and math.abs(hero.y - f.y) < 16 and hero.z < f.z + 40 then
        if hero:hurt(d.dmg, hero.x >= f.x and 1 or -1, {down = true}) then f.pounced = true Sound.play("clank") end
      end
      if f.z <= 0 then f.z, f.vz = 0, 0 f.land_t = f.t Sound.play("land", 0.6) Fx.add("dust", f.x, f.y, 10) end
    elseif f.land_t and f.t >= f.land_t + 16 then f.land_t, f.cool = nil, d.cool set(f, "walk") end
  end
end

local function ai_caldero(f, hero)
  local d = f.d
  if f.st == "walk" then
    local near = approach(f, hero, d.reach - 14)
    f.cool = f.cool - 1
    if near and f.cool <= 0 and attackers() < 2 and hero.st ~= "dead" then set(f, "atk") f.slammed = false end
  elseif f.st == "atk" then
    if f.t == d.wind and not f.slammed then
      f.slammed = true
      Sound.play("stomp", 0.9)
      Hook.shake(5)
      Fx.add("steam", f.x + f.face * 40, f.y, 40)
      Fx.add("dust", f.x + f.face * 50, f.y, 10)
      blow_on_hero(f, hero, d.reach, d.dmg, {round = true, depth = 30, down = true})
    end
    if f.t >= d.wind + 36 then f.cool = d.cool set(f, "walk") end
  end
end

local AI = {rodete = ai_rodete, resorte = ai_resorte, caldero = ai_caldero}

local function die_for_good(f)
  Sound.play("boom", 0.6)
  Fx.add("boom", f.x, f.y, 50)
  Fx.add("gears", f.x, f.y, 60)
  if F.on_die then F.on_die(f) end
end

function F.update(hero, cam)
  for i = #F.list, 1, -1 do
    local f = F.list[i]
    f.t = f.t + 1
    if f.flash > 0 then f.flash = f.flash - 1 end
    local st = f.st
    if st == "walk" or st == "atk" then
      if f.alive and hero.st ~= "win" then AI[f.kind](f, hero) end
      if st == "walk" and f.x < cam - 80 or f.x > cam + C.W + 80 then
        -- far outside the screen (a pushed one): walk back in
        f.x = U.clamp(f.x, cam - 60, cam + C.W + 60)
      end
    elseif st == "hurt" then
      f.x = f.x + f.vx
      f.vx = f.vx * 0.85
      if f.t >= 14 then set(f, "walk") end
    elseif st == "held" then
      -- the hero places it
    elseif st == "down" then
      if f.z > 0 or f.vz > 0 then
        f.vz = f.vz - C.GRAV
        f.z = f.z + f.vz
        f.x = f.x + f.vx
        if f.thrown_by then
          for _, o in ipairs(F.list) do
            if o ~= f and o.alive and not f.hit_list[o] and math.abs(o.x - f.x) < 30 and math.abs(o.y - f.y) < 18 and o.z < f.z + 50 then
              f.hit_list[o] = true
              o:hit(12, f.thrown_by, {down = true}, -1)
              Fx.add("hit", o.x, o.y, 50)
            end
          end
        end
        if f.z <= 0 then
          f.z, f.vz = 0, 0
          f.t = 0
          f.landed = true
          f.thrown_by = nil
          Sound.play("land", 0.7)
          Fx.add("dust", f.x, f.y, 10)
        end
      else
        f.vx = f.vx * 0.85
        f.x = f.x + f.vx
        f.landed = true
      end
      if f.landed and f.t > 30 then
        f.landed = false
        if f.dying then set(f, "dying") else set(f, "walk") f.cool = 40 f.hit_list = nil end
      end
    elseif st == "dying" then
      if f.t >= 24 then die_for_good(f) table.remove(F.list, i) end
    end
    f.y = U.clamp(f.y, C.Y_MIN - 10, C.Y_MAX + 6)
  end
end

local function frame_of(f)
  local st, t, k = f.st, f.t, f.kind
  if st == "walk" then
    if k == "resorte" then return "hop_" .. (t // 6) % 4 end
    if k == "caldero" then return "walk_" .. (t // 9) % 4 end
    return "walk_" .. (t // 7) % 4
  end
  if st == "atk" then
    if k == "caldero" then return "atk_" .. math.min(3, t // 12) end
    if k == "resorte" then return f.z > 0 and "atk_1" or (f.land_t and "atk_2" or "atk_0") end
    return "atk_" .. (t < f.d.wind and 0 or (t < f.d.wind + 8 and 1 or 2))
  end
  if st == "hurt" then return "hurt_" .. (t // 4) % 2 end
  if st == "held" then return (k == "caldero") and "hurt_1" or "hurt_1" end
  if st == "down" then
    if f.z > 0 then return f.vz > 0.5 and "fall_0" or "fall_1" end
    return "lie_0"
  end
  if st == "dying" then return "die_" .. math.min(2, t // 8) end
  return "idle_0"
end

function F.collect(out, cam)
  for _, f in ipairs(F.list) do
    out[#out + 1] = {y = f.y, foe = true, draw = function()
      local flicker = f.st == "dying" and (f.t // 3) % 2 == 0
      if f.st ~= "dying" then require("core.hero").shadow(f.x - cam, f.y, f.z) end
      if flicker then return end
      local o = {flip = f.face < 0}
      if f.flash > 0 then o.tint = 0xFFFFFF end
      S.draw(f.kind, frame_of(f), f.x - cam, f.y - f.z, o)
    end}
  end
end

return F
