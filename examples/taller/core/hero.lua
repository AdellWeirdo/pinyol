-- hero: the player. A clockmaker in a clockwork exo-frame walks the street floor in two directions (along it and in depth), strikes a three-hit combo, jumps, kicks in the air,
-- grabs and throws, and unleashes a special when the steam gauge is full. Parts torn from broken automatons change how it fights for a while (Armored Warriors' idea).
-- States: idle walk atk jump jatk special grab hold throw hurt down dead win. Frames come from the sheet named like the hero (gen/gpt_jobs.py HERO_SHEETS).
local C = require("core.const")
local U = require("core.util")
local S = require("core.spr")
local Run = require("core.run")
local Foes = require("core.foes")
local Props = require("core.props")
local Boss = require("core.boss")
local Fx = require("core.fx")
local Sound = require("core.sound")
local Hook = require("core.juice_hook")
local In = require("core.input")
local H = {}
H.__index = H

H.DEFS = {
  vera = {hp = 100, speed = 2.0, jump = 9.0, dmg = 1.0, reach = 46},
  tomas = {hp = 130, speed = 1.6, jump = 8.4, dmg = 1.35, reach = 56},
  mina = {hp = 80, speed = 2.6, jump = 10.2, dmg = 0.85, reach = 46},
}
-- the parts: what they change, and the colour of the ring round the hero while worn
H.PARTS = {
  hammer = {color = 0xFF9020, dmg = 1.6, reach = 10, down = true},
  springs = {color = 0x40E060, jump = 1.3, speed = 1.15, air = 1.5},
  wrench = {color = 0x40D0FF, rate = 0.65, dmg = 1.2},
  boiler = {color = 0xFF4030, armor = 0.6, burst = true},
}

local WINDUP, ACTIVE, RECOVER = 4, 4, 6
local STEP_DMG = {6, 6, 10}

function H.new(id, x, y)
  local d = H.DEFS[id]
  local h = setmetatable({id = id, d = d, x = x, y = y, z = 0, vx = 0, vy = 0, vz = 0, face = 1, st = "idle", t = 0, hp = d.hp, max_hp = d.hp, lives = C.LIVES,
                          inv = C.INVULN, meter = 0, step = 0, atkid = 0, flash = 0, part = nil, part_t = 0, hw = 18, ent = true, win_t = 0}, H)
  return h
end

local function pr(h) return h.part and H.PARTS[h.part] or {} end

function H:take_part(kind)
  self.part, self.part_t = kind, C.PART_TICKS
  Run.parts = Run.parts + 1
  Run.parts_kinds[kind] = true
  Sound.play("part")
  Fx.add("gears", self.x, self.y, self.z + 60)
end

-- every thing a blow can land on: the automatons, the props, the boss
local function targets()
  local out = {}
  for _, f in ipairs(Foes.list) do out[#out + 1] = f end
  for _, p in ipairs(Props.list) do out[#out + 1] = p end
  if Boss.ent then out[#out + 1] = Boss.ent end
  return out
end

-- a blow on what is in front (or all round with `round`): reach in pixels, damage, flags {down, kind}
local function strike(h, reach, dmg, o)
  o = o or {}
  h.atkid = h.atkid + 1
  local n = 0
  local p = pr(h)
  dmg = dmg * h.d.dmg * (p.dmg or 1)
  reach = reach + (p.reach or 0)
  for _, t in ipairs(targets()) do
    local dx = (t.x - h.x) * h.face
    local near = o.round and math.abs(t.x - h.x) < reach + t.hw or (dx > -12 and dx < reach + t.hw)
    if near and math.abs(t.y - h.y) < (o.depth or 18) and math.abs(t.z - h.z) < 56 and t.alive ~= false then
      if t:hit(dmg, t.x >= h.x and 1 or -1, {down = o.down or p.down, kind = o.kind}, h.atkid) then
        n = n + 1
        h.meter = math.min(C.METER, h.meter + 6)
        Fx.add("hit", t.x - (t.x - h.x) * 0.3, t.y, math.max(t.z + 54, 40))
      end
    end
  end
  if n > 0 then
    Sound.play(o.down and "heavy" or "punch")
    Hook.shake(o.down and 3 or 1)
    if o.down then Hook.freeze(3) end
  else
    Sound.play("whoosh", 0.7)
  end
  return n
end

local function set(h, st) h.st, h.t = st, 0 end

local function start_atk(h, step)
  set(h, "atk")
  h.step, h.buf = step, false
  h.swung = false
end

-- is there an automaton to grab right in front?
local function grab_target(h)
  for _, f in ipairs(Foes.list) do
    local dx = (f.x - h.x) * h.face
    if f.grabbable and f.alive and f.st ~= "held" and dx > 0 and dx < 50 and math.abs(f.y - h.y) < 14 and f.z < 8 then return f end
  end
end

function H:hurt(dmg, dir, flags)
  if self.inv > 0 or self.st == "special" or self.st == "dead" or self.st == "down" or self.god then return false end
  local p = pr(self)
  dmg = math.floor(dmg * (p.armor or 1) + 0.5)
  self.hp = self.hp - dmg
  self.meter = math.min(C.METER, self.meter + 10)
  if U.blink(self) then self.flash = 4 end
  Sound.play("hit")
  Hook.shake(2)
  if self.held then self.held.st, self.held.t, self.held = "walk", 0, nil end
  if p.burst then
    Fx.add("steam", self.x, self.y, 50)
    Sound.play("steam", 0.6)
    for _, f in ipairs(Foes.list) do
      if math.abs(f.x - self.x) < 80 and math.abs(f.y - self.y) < 30 and f.alive then f:hit(8, f.x >= self.x and 1 or -1, {down = true}, -1) end
    end
  end
  if self.hp <= 0 then
    self.hp = 0
    self.face = dir and -dir or self.face
    self.vx, self.vz = (dir or 0) * 3, 5
    set(self, "dead")
    self.lives = self.lives - 1
    Run.deaths = Run.deaths + 1
    Sound.play("die")
    return true
  end
  if (flags and flags.down) or self.z > 0 then
    self.vx, self.vz = (dir or 0) * 2.8, 5
    set(self, "down")
    Sound.play("down")
  else
    set(self, "hurt")
    self.vx = (dir or 0) * 1.2
  end
  self.inv = 30
  return true
end

local function land(h)
  h.z, h.vz = 0, 0
  Sound.play("land", 0.6)
  Fx.add("dust", h.x, h.y, 10)
end

-- the buttons: In.btn(name); a bot may hold them (core/input.lua)
function H:update(cam)
  local d, p = self.d, pr(self)
  self.t = self.t + 1
  if self.inv > 0 then self.inv = self.inv - 1 end
  if self.flash > 0 then self.flash = self.flash - 1 end
  if self.part then
    self.part_t = self.part_t - 1
    if self.part_t <= 0 then self.part = nil end
  end
  local st = self.st
  local left, right, up, down = In.btn("left"), In.btn("right"), In.btn("up"), In.btn("down")
  local speed = d.speed * (p.speed or 1)
  local minx, maxx = cam + 22, cam + C.W - 22
  if st == "idle" or st == "walk" then
    local dx = (right and 1 or 0) - (left and 1 or 0)
    local dy = (down and 1 or 0) - (up and 1 or 0)
    self.x = self.x + dx * speed
    self.y = self.y + dy * speed * 0.7
    if dx ~= 0 then self.face = dx end
    self.st = (dx ~= 0 or dy ~= 0) and "walk" or "idle"
    if In.btnp("a") then
      local f = grab_target(self)
      if f and (dx == self.face) then
        set(self, "grab")
        self.held = f
        f:grabbed(self)
      else
        start_atk(self, 1)
      end
    elseif In.btnp("b") then
      self.vz = d.jump * (p.jump or 1)
      self.z = 0.01
      set(self, "jump")
      Sound.play("jump")
    elseif In.btnp("c") and self.meter >= C.METER then
      self.meter = 0
      Run.specials = Run.specials + 1
      self.inv = 70
      set(self, "special")
      Sound.play("special")
    end
  elseif st == "atk" then
    local rate = p.rate or 1
    local w, a, r = WINDUP * rate, ACTIVE * rate, RECOVER * rate
    if In.btnp("a") then self.buf = true end
    if not self.swung and self.t >= w then
      self.swung = true
      local last = self.step == 3
      strike(self, d.reach, STEP_DMG[self.step], {down = last, kind = "punch"})
      self.x = self.x + self.face * 2
    end
    if self.t >= w + a and self.buf and self.step < 3 then start_atk(self, self.step + 1)
    elseif self.t >= w + a + r then set(self, "idle") end
  elseif st == "jump" or st == "jatk" then
    local dx = (right and 1 or 0) - (left and 1 or 0)
    local dy = (down and 1 or 0) - (up and 1 or 0)
    self.x = self.x + dx * speed * 0.9
    self.y = self.y + dy * speed * 0.5
    if dx ~= 0 and st == "jump" then self.face = dx end
    self.vz = self.vz - C.GRAV
    self.z = self.z + self.vz
    if st == "jump" and In.btnp("a") then
      set(self, "jatk")
      local air = p.air or 1
      strike(self, d.reach - 6, 9 * air, {down = true, kind = "kick"})
    end
    if self.z <= 0 then land(self) set(self, "idle") end
  elseif st == "special" then
    local k = self.t
    if k == 12 or k == 18 or k == 24 then strike(self, 80, 8, {round = true, depth = 40, kind = "special"}) Fx.add("gears", self.x, self.y, 70)
    elseif k == 30 then strike(self, 90, 12, {round = true, depth = 40, down = true, kind = "special"}) Hook.shake(5) end
    if self.id == "mina" and k > 8 and k < 30 then self.x = self.x + self.face * 2.6 end
    if k >= 36 then set(self, "idle") end
  elseif st == "grab" then
    if self.t >= 8 then set(self, "hold") end
  elseif st == "hold" then
    if self.held then self.held.x, self.held.y = self.x + self.face * 30, self.y end
    if In.btnp("a") or self.t > 50 then set(self, "throw") end
  elseif st == "throw" then
    if self.t == 6 and self.held then
      local f = self.held
      self.held = nil
      Run.throws = Run.throws + 1
      f:thrown(self.face, 14 * d.dmg)
      self.meter = math.min(C.METER, self.meter + 10)
      Sound.play("heavy")
      Hook.shake(3)
    end
    if self.t >= 15 then set(self, "idle") end
  elseif st == "hurt" then
    self.x = self.x + self.vx
    self.vx = self.vx * 0.9
    if self.t >= 14 then set(self, "idle") end
  elseif st == "down" or st == "dead" then
    if self.z > 0 or self.vz > 0 then
      self.vz = self.vz - C.GRAV
      self.z = self.z + self.vz
      self.x = self.x + self.vx
      if self.z <= 0 then land(self) self.t = 0 self.fell = true end
    else
      self.vx = self.vx * 0.85
      self.x = self.x + self.vx
      self.fell = true
    end
    if st == "down" and self.fell and self.t > 38 then self.fell = false set(self, "getup") self.inv = 70 end
  elseif st == "getup" then
    if self.t >= 22 then set(self, "idle") end
  elseif st == "win" then
    self.win_t = self.win_t + 1
  end
  self.x = U.clamp(self.x, minx, maxx)
  if Boss.arena_min and self.x < Boss.arena_min then self.x = Boss.arena_min end
  self.y = U.clamp(self.y, C.Y_MIN, C.Y_MAX)
end

function H:frame()
  local st, t = self.st, self.t
  if st == "idle" then return "idle_" .. (t // 9) % 4 end
  if st == "walk" then return "walk_" .. (t // 5) % 6 end
  if st == "atk" then
    local rate = pr(self).rate or 1
    return "atk_" .. ((self.step - 1) * 2 + (t < WINDUP * rate and 0 or 1))
  end
  if st == "jump" then return self.vz > 2.5 and "jump_0" or (self.vz > -2.5 and "jump_1" or "jump_2") end
  if st == "jatk" then return "jumpatk_" .. (t < 6 and 0 or 1) end
  if st == "special" then return "special_" .. math.min(5, t // 6) end
  if st == "grab" then return "grab_0" end
  if st == "hold" then return "grab_1" end
  if st == "throw" then return "throw_" .. math.min(2, t // 5) end
  if st == "hurt" then return "hurt_0" end
  if st == "down" or st == "dead" then
    if self.z > 0 then return self.vz > 1 and "fall_0" or "fall_1" end
    return "lie_0"
  end
  if st == "getup" then return "getup_" .. math.min(2, t // 8) end
  if st == "win" then return "win_" .. (self.win_t // 10) % 3 end
  return "idle_0"
end

-- a shadow made of three darkened strips
local function shadow(x, y, z)
  local k = math.max(0.5, 1 - z / 140)
  local w = math.floor(30 * k)
  shade(x - w // 2, y - 3, w, 2)
  shade(x - math.floor(w * 0.7), y - 1, math.floor(w * 1.4), 2)
  shade(x - w // 2, y + 1, w, 2)
end
H.shadow = shadow

function H:collect(out, cam)
  out[#out + 1] = {y = self.y, draw = function()
    if self.st == "dead" and self.t > 95 and (self.t // 4) % 2 == 0 then return end
    shadow(self.x - cam, self.y, self.z)
    if self.inv > 0 and self.st ~= "special" and (self.t // 3) % 2 == 0 and self.st ~= "down" and self.st ~= "getup" then return end
    local p = pr(self)
    local o = {flip = self.face < 0, alt = Run.alt}
    if self.flash > 0 then o.tint = 0xFFFFFF end
    if self.part and (self.part_t > 180 or (self.part_t // 5) % 2 == 0) then o.outline = p.color end
    if self.st == "special" then o.outline = 0xFFFFA0 end
    S.draw(self.id, self:frame(), self.x - cam, self.y - self.z, o)
  end}
end

return H
