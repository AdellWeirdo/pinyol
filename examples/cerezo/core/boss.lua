-- boss: Topo Rey, the giant mole that gnaws the cherry tree's roots. He lives under the floor of the last room and
-- comes up at one of three mounds. Each time he surfaces he does one thing (rocks, an eruption under the hero, falling
-- stalactites in the second half) and is left dazed, which is when the pala hurts him. Twelve hits.
local C = require("core.const")
local U = require("core.util")
local W = require("core.world")
local S = require("core.spr")
local E = require("core.ents")
local Game = require("core.game")
local FX = require("core.fx")
local Sound = require("core.sound")
local Pick = require("core.pickups")
local Proj = require("core.proj")
local Hero = require("core.hero")
local Things = require("core.things")
local B = {}

local MAXHP = 12

-- the mounds he comes up at, in cells of the room (the room is the area's screen the thing is in)
local function mounds(def)
  local sx, sy = math.floor(def.cx / C.SW), math.floor(def.cy / C.SH)
  local ox, oy = sx * C.SW, sy * C.SH
  return {{ox + 3, oy + 3}, {ox + 7, oy + 2}, {ox + 11, oy + 3}}
end

function B.spawn(def)
  if Game.flags.topo_dead then return nil end
  local m = mounds(def)
  local b = {kind = "boss", team = "enemy", id = "topo_rey", hp = MAXHP, mode = "wait", t = 0, mound = 2, mounds = m, def = def,
             x = m[2][1] * C.T - 8, y = m[2][2] * C.T - 16, hurt_t = 0, flash = 0, sort = 18, hidden = true,
             bx = 6, by = 6, bw = 20, bh = 22, no_damage = true, shots = {}, hits_taken = 0}
  Game.boss_hit = false
  function b.update(self) B.update(self) end
  function b.draw(self) B.draw(self) end
  function b.hit(self, dmg, dir) return B.hit(self, dmg, dir) end
  return E.add(b)
end

local function phase2(b) return b.hp <= MAXHP // 2 end

local function go(b, mode) b.mode, b.t = mode, 0 end

local function pick_mound(b)
  local choices = {}
  for i = 1, 3 do if i ~= b.mound then choices[#choices + 1] = i end end
  b.mound = choices[math.random(#choices)]
  local m = b.mounds[b.mound]
  b.x, b.y = m[1] * C.T - 8, m[2] * C.T - 16
end

local function fire_rocks(b)
  local h = E.hero
  for i = -1, 1 do
    local dx, dy = h.x - (b.x + 8), h.y - (b.y + 12)
    local ang = math.atan(dy, dx) + i * 0.32
    Proj.new({x = b.x + 12, y = b.y + 14, vx = math.cos(ang) * 1.5, vy = math.sin(ang) * 1.5, frames = {"topo_throw"}, size = 8,
              gravity = 0.12, vz = 2.2, z = 10, life = 90, dmg = 1})
  end
  Sound.play("hit")
end

function B.update(b)
  b.t = b.t + 1
  if b.flash > 0 then b.flash = b.flash - 1 end
  local h = E.hero
  local speed = phase2(b) and 0.75 or 1
  if b.mode == "wait" then
    -- the fight begins when the hero is in the room
    if h and W.sx == math.floor(b.def.cx / C.SW) and W.sy == math.floor(b.def.cy / C.SH) and b.t > 60 then
      require("core.music").play("boss")
      go(b, "emerge")
    end
  elseif b.mode == "emerge" then
    b.hidden = false
    if b.t == 1 then Sound.play("dig") FX.shake(2, 14) FX.dust(b.x + 16, b.y + 30) end
    if b.t > math.floor(26 * speed) then
      local roll = math.random(phase2(b) and 3 or 2)
      go(b, roll == 1 and "roar" or (roll == 2 and "erupt_wind" or "stalac"))
    end
  elseif b.mode == "roar" then
    if b.t == math.floor(20 * speed) then fire_rocks(b) end
    if b.t > math.floor(46 * speed) then go(b, "dizzy") end
  elseif b.mode == "erupt_wind" then -- he goes under; a crack runs to where the hero stood, and he comes up there
    b.hidden = true
    if b.t == 1 then b.tx, b.ty = h.x - 8, h.y - 14 end
    local k = math.min(1, b.t / (50 * speed))
    local sx, sy = b.mounds[b.mound][1] * C.T - 8, b.mounds[b.mound][2] * C.T - 16
    b.cx, b.cy = sx + (b.tx - sx) * k, sy + (b.ty - sy) * k
    if b.t % 5 == 0 then FX.dust(b.cx + 16, b.cy + 28) end
    if b.t > math.floor(60 * speed) then
      b.x, b.y = U.clamp(b.tx, 24, W.area.gw * C.T - 56), U.clamp(b.ty, 24, W.area.gh * C.T - 56)
      b.hidden = false
      Sound.play("dig") FX.shake(3, 12)
      if h and U.overlap(h.x + 2, h.y + 4, 12, 11, b.x - 4, b.y + 4, 40, 30) then Hero.hurt(h, 2, b.x + 16, b.y + 16) end
      go(b, "dizzy")
    end
  elseif b.mode == "stalac" then -- shadows on the floor, then rocks fall on them
    if b.t == 1 then
      b.drops = {}
      for i = 1, 5 do
        b.drops[i] = {x = h.x + math.random(-48, 48), y = h.y + math.random(-24, 24), t = i * 8}
      end
      Sound.play("hit")
    end
    for _, d in ipairs(b.drops) do
      d.t = d.t + 1
      if d.t == 50 then
        FX.shake(1, 6) Sound.play("kill") FX.dust(d.x, d.y)
        if h and U.overlap(h.x + 4, h.y + 6, 8, 9, d.x - 8, d.y - 8, 16, 16) then Hero.hurt(h, 1, d.x, d.y) end
      end
    end
    if b.t > 80 then b.drops = nil go(b, "dizzy") end
  elseif b.mode == "dizzy" then -- dazed: this is when he can be hit
    if b.t > math.floor(110 / speed) then go(b, "burrow") end
  elseif b.mode == "hurt" then
    if b.t > 18 then go(b, b.hp > 0 and "dizzy" or "dead") b.t = 40 end
  elseif b.mode == "burrow" then
    if b.t == 1 then Sound.play("dig") end
    if b.t > 24 then
      b.hidden = true
      pick_mound(b)
      go(b, "gone")
    end
  elseif b.mode == "gone" then
    if b.t > math.floor(50 * speed) then go(b, "emerge") end
  elseif b.mode == "dead" then
    B.dying(b)
  end
end

-- a hit: only while he is dazed
function B.hit(b, dmg, dir)
  if b.mode ~= "dizzy" and b.mode ~= "hurt" then
    Sound.play("deny")
    FX.spark(b.x + 16, b.y + 16)
    return false
  end
  if b.mode == "hurt" then return false end
  b.hp = b.hp - dmg
  b.flash = 16
  FX.freeze(5) FX.shake(2, 8) Sound.play("hit") FX.spark(b.x + 16, b.y + 16)
  if b.hp <= 0 then
    go(b, "dead")
    b.t = 0
  else
    go(b, "hurt")
  end
  return true
end

function B.dying(b)
  if b.t == 1 then
    b.hidden = false
    require("core.music").stop()
    FX.freeze(10)
    Game.flags.topo_dead = true
    achieve("rey_destronado")
    if not Game.boss_hit then achieve("sin_rasgunos") end
  end
  if b.t % 5 == 0 and b.t < 90 then
    FX.poof(b.x + math.random(4, 28), b.y + math.random(4, 28))
    Sound.play("kill")
    FX.shake(2, 4)
  end
  if b.t == 100 then
    b.dead = true
    Pick.drop("heart", b.x + 16, b.y + 20, true)
    -- the heart container and the golden cherry
    Sound.play("secret")
    local cx, cy = b.mounds[2][1], b.mounds[2][2] + 1
    Things.spawn({kind = "chest_item", cx = cx, cy = cy, item = "contenedor_corazon", flag = "boss_heart"})
    require("core.music").jingle("jingle_win", 8)
    require("core.music").play("raiz")
    Game.cereza_pending = true
  end
end

function B.draw(b)
  local frame = "rey_idle"
  local m = b.mode
  if m == "wait" or b.hidden then
    -- the mounds show where he may come up
    for i, mm in ipairs(b.mounds) do
      local sx, sy = W.to_screen(mm[1] * C.T, mm[2] * C.T)
      S.draw("MON", "topo_mound", sx, sy)
    end
    if m == "erupt_wind" then
      local sx, sy = W.to_screen(b.cx + 8, b.cy + 14)
      S.draw("MON", "topo_mound", sx, sy)
    end
    if b.drops then
      for _, d in ipairs(b.drops) do
        local sx, sy = W.to_screen(d.x - 8, d.y - 8)
        if d.t < 50 then S.draw("UI8", "spark_0", sx + 4, sy + 4) end
      end
    end
    return
  end
  if m == "emerge" then frame = "rey_up_" .. math.min(2, b.t // 9)
  elseif m == "roar" then frame = (b.t // 8) % 2 == 0 and "rey_roar_0" or "rey_roar_1"
  elseif m == "dizzy" then frame = (b.t // 12) % 2 == 0 and "rey_dizzy_0" or "rey_dizzy_1"
  elseif m == "hurt" then frame = "rey_hurt"
  elseif m == "burrow" then frame = "rey_down_" .. math.min(2, b.t // 8)
  elseif m == "dead" then frame = "rey_dead_" .. math.min(3, b.t // 24)
  elseif m == "stalac" then frame = "rey_roar_0" end
  if b.flash > 0 and (b.flash // 2) % 2 == 0 then return end
  local sx, sy = W.to_screen(b.x, b.y)
  S.draw("BOSS", frame, sx, sy)
  if b.drops then
    for _, d in ipairs(b.drops) do
      local dx, dy = W.to_screen(d.x - 8, d.y - 8)
      if d.t < 50 then S.draw("UI8", "spark_0", dx + 4, dy + 4) end
    end
  end
end

Things.kinds.boss = B.spawn

-- the chest the boss leaves, already open to the hero: touching it gives the item
Things.kinds.chest_item = function(def)
  if def.flag and Game.flags[def.flag] then return nil end
  local e = {kind = "pedestal", x = def.cx * C.T, y = def.cy * C.T, t = 0, hw = 16, hh = 16, hx = 0, hy = 0, sort = 8}
  function e.update(self)
    self.t = self.t + 1
    local h = E.hero
    if U.overlap(self.x + 2, self.y + 2, 12, 12, h.x + 4, h.y + 6, 8, 8) then
      if def.flag then Game.flags[def.flag] = true end
      self.dead = true
      require("core.rewards").get(def.item, def.after)
    end
  end
  function e.draw(self)
    local sx, sy = W.to_screen(self.x, self.y + math.floor(math.sin(self.t / 9) * 2))
    S.draw("ITEMS16", def.item, sx, sy)
  end
  return E.add(e)
end

return B
